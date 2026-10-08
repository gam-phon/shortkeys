import AppKit
import CryptoKit
import Observation
import Security

/// Checks GitHub for a newer release and installs it.
///
/// An update is installed only if its SHA-256 checksum matches the release's
/// SHA256SUMS.txt *and* it's signed by the same certificate as the running app.
/// The app is then replaced in place, so the login item and the Accessibility
/// permission (which belongs to the signing certificate) carry over.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()
    nonisolated static let repository = "gam-phon/shortkeys"

    struct Release: Sendable, Equatable {
        let version: String
        let pageURL: URL
        let zipURL: URL
        let checksumsURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var lastChecked: Date?
    /// Set on the first launch after an update: the version it updated from.
    private(set) var updatedFrom: String?

    /// Snapshot test only: shows the "updated from" note without a real update.
    func simulateUpdate(from version: String) {
        updatedFrom = version
    }

    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?
    @ObservationIgnored private var waitingForIdle = false

    /// How long the Mac must be untouched before an automatic update restarts Shortkeys.
    /// (`SHORTKEYS_IDLE_BEFORE_INSTALL` overrides it for tests.)
    nonisolated static var idleBeforeInstall: TimeInterval {
        ProcessInfo.processInfo.environment["SHORTKEYS_IDLE_BEFORE_INSTALL"].flatMap(TimeInterval.init) ?? 5 * 60
    }

    static var checksAutomatically: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.checkForUpdates) as? Bool ?? true
    }

    static var installsAutomatically: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.installUpdatesAutomatically) as? Bool ?? true
    }

    // MARK: - Automatic updates

    /// Called at launch: notes a just-finished update, checks now, and lets the
    /// system run a check about once a day (scheduled by macOS, not a timer).
    func start() {
        let defaults = UserDefaults.standard
        if let last = defaults.string(forKey: SettingsKey.lastRunVersion), last != currentVersion {
            updatedFrom = last
        }
        defaults.set(currentVersion, forKey: SettingsKey.lastRunVersion)

        let scheduler = NSBackgroundActivityScheduler(identifier: "com.yaser.shortkeys.update-check")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await Updater.shared.automaticCheck(atLaunch: false)
                completion(.finished)
            }
        }
        self.scheduler = scheduler

        Task { await automaticCheck(atLaunch: true) }
    }

    /// Checks (if enabled) and installs a found update (if enabled): right away
    /// at launch, otherwise once the Mac has been idle for a while.
    func automaticCheck(atLaunch: Bool) async {
        guard Self.checksAutomatically else { return }
        await check()
        guard Self.installsAutomatically, let release = availableRelease, Self.canReplaceWithoutPassword else { return }
        if atLaunch {
            await install(release)
        } else {
            await installWhenIdle(release)
        }
    }

    /// Waits until nobody has used the keyboard or mouse for `idleBeforeInstall`,
    /// so the restart never interrupts a hotkey. Only runs while an update waits.
    private func installWhenIdle(_ release: Release) async {
        guard !waitingForIdle else { return }
        waitingForIdle = true
        defer { waitingForIdle = false }
        while Self.idleSeconds < Self.idleBeforeInstall {
            try? await Task.sleep(for: .seconds(60))
            guard Self.installsAutomatically, availableRelease == release else { return }
        }
        await install(release)
    }

    /// Seconds since the last keyboard or mouse input.
    nonisolated static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// An automatic update never asks for a password: a copy installed as root
    /// (by an older .pkg) is updated only when the user clicks Update.
    static var canReplaceWithoutPassword: Bool {
        let path = plainPath(Bundle.main.bundleURL)
        let owner = try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountID] as? NSNumber
        return owner?.uint32Value == getuid()
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var availableRelease: Release? {
        if case .available(let release) = state { release } else { nil }
    }

    var isBusy: Bool {
        [.checking, .downloading, .installing].contains(state)
    }

    // MARK: - Checking

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await Self.fetchLatestRelease()
            lastChecked = .now
            state = Self.isVersion(release.version, newerThan: currentVersion) ? .available(release) : .upToDate
        } catch {
            state = .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }

    /// Checks unless that happened recently (used at launch and when Settings opens).
    func checkIfDue() async {
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < 60 * 60 { return }
        await check()
    }

    @concurrent
    nonisolated static func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // CI runners share IP addresses and hit GitHub's anonymous rate limit;
        // they provide a token. Normal installs don't need one.
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("GitHub didn't return the latest release.")
        }

        struct GitHubRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard
            let zip = release.assets.first(where: { $0.name == "Shortkeys-\(version).zip" }),
            let checksums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" })
        else {
            throw UpdateError("The latest release has no app download.")
        }
        return Release(
            version: version,
            pageURL: release.html_url,
            zipURL: zip.browser_download_url,
            checksumsURL: checksums.browser_download_url
        )
    }

    /// Compares dotted versions numerically: 1.10.0 is newer than 1.9.2.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Installing

    func install(_ release: Release) async {
        guard !isBusy else { return }
        state = .downloading
        do {
            let newApp = try await Self.downloadAndVerify(release)
            state = .installing
            try Self.replaceRunningApp(with: newApp)
            NSApp.terminate(nil) // the helper waits for this, then swaps the app and reopens it
        } catch {
            state = .failed("Couldn't update: \(error.localizedDescription)")
        }
    }

    /// Downloads the release, checks its checksum and signature, and returns the unpacked app.
    @concurrent
    nonisolated static func downloadAndVerify(_ release: Release) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShortkeysUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let (downloaded, _) = try await URLSession.shared.download(from: release.zipURL)
        let zip = folder.appending(path: release.zipURL.lastPathComponent)
        try FileManager.default.moveItem(at: downloaded, to: zip)

        // Checksum: SHA256SUMS.txt lines look like "<hex>  Shortkeys-1.2.0.zip".
        let (checksumData, _) = try await URLSession.shared.data(from: release.checksumsURL)
        let expected = String(decoding: checksumData, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasSuffix(" \(zip.lastPathComponent)") }?
            .split(separator: " ").first.map(String.init)
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard let expected, expected == actual else {
            throw UpdateError("The download is damaged (its checksum doesn't match).")
        }

        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path(percentEncoded: false), folder.path(percentEncoded: false)]
        try unzip.run()
        unzip.waitUntilExit()
        let app = folder.appending(path: "Shortkeys.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path(percentEncoded: false)) else {
            throw UpdateError("The download couldn't be unpacked.")
        }

        try verifySignature(of: app)
        return app
    }

    /// The new app must be signed by the same certificate as this one.
    nonisolated static func verifySignature(of app: URL) throws {
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw UpdateError("The download isn't a valid app.")
        }
        guard let requirement = updateRequirement() else {
            throw UpdateError("Couldn't read this app's signature.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else {
            throw UpdateError("The download isn't signed by the Shortkeys developer.")
        }
    }

    /// The running app's designated requirement ("this bundle ID, signed by this
    /// certificate"). An ad-hoc build's requirement pins its exact binary, which
    /// no update can match; then only the bundle ID is required (the checksum
    /// still has to match).
    nonisolated static func updateRequirement() -> SecRequirement? {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard
            SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
            SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
            SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
            SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text
        else { return nil }

        guard (text as String).contains("cdhash") else { return requirement }
        var identifierOnly: SecRequirement?
        let bundleID = Bundle.main.bundleIdentifier ?? "com.yaser.shortkeys"
        SecRequirementCreateWithString("identifier \"\(bundleID)\"" as CFString, [], &identifierOnly)
        return identifierOnly
    }

    /// Starts a helper that waits for Shortkeys to quit, swaps in the new app and
    /// reopens it. The old app is only removed once the new one is in place; if
    /// the swap fails, the old app is put back. Either way Shortkeys reopens.
    static func replaceRunningApp(with newApp: URL) throws {
        let target = plainPath(Bundle.main.bundleURL)
        let parent = (target as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            throw UpdateError("Shortkeys can't write to \(parent). Install the update from the release page instead.")
        }
        // Installed by an older .pkg as root: take ownership once (password prompt),
        // so the app can be replaced now and in future updates.
        let owner = try? FileManager.default.attributesOfItem(atPath: target)[.ownerAccountID] as? NSNumber
        if owner?.uint32Value != getuid() {
            let user = NSUserName()
            guard AdminPrompt.run(
                "chown -R \(AdminPrompt.quoted(user)):staff \(AdminPrompt.quoted(target))",
                reason: "Shortkeys needs your password once to install updates."
            ) else {
                throw UpdateError("The update was cancelled.")
            }
        }
        // The previous version goes to the Trash (as "Shortkeys <version>.app"),
        // so an update can be undone by putting it back.
        let script = """
            pid="$1"; target="${2%/}"; new="${3%/}"; trashed="$4"
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            if /usr/bin/ditto "$new" "$target.updating"; then
                if mv "$target" "$target.old"; then
                    if mv "$target.updating" "$target"; then
                        mkdir -p "$(dirname "$trashed")"
                        mv "$target.old" "$trashed" || rm -rf "$target.old"
                    else
                        mv "$target.old" "$target"
                    fi
                fi
                rm -rf "$target.updating"
            fi
            /usr/bin/open "$target"
            rm -rf "$(dirname "$new")"
            """
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")
        let trashed = URL.homeDirectory.appending(path: ".Trash/Shortkeys \(Updater.shared.currentVersion) (\(stamp)).app")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            "-c", script, "shortkeys-update",
            String(ProcessInfo.processInfo.processIdentifier),
            target,
            plainPath(newApp),
            plainPath(trashed),
        ]
        try helper.run()
    }

    /// A file URL's path without a trailing slash. A bundle URL is a directory
    /// URL ("…/Shortkeys.app/"); with the slash, "$target.updating" would point
    /// inside the app, and replacing it would delete the update too.
    nonisolated static func plainPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
