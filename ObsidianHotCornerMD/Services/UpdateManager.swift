import Foundation
import AppKit
import Combine

// MARK: - Update State
enum UpdateState {
    case idle
    case checking
    case available(UpdateInfo)
    case upToDate
    case downloading(progress: Double)
    case installing
    case error(String)

    var description: String {
        switch self {
        case .idle: return NSLocalizedString("update.state.idle", comment: "Idle")
        case .checking: return NSLocalizedString("update.state.checking", comment: "Checking for updates...")
        case .available(let info): return String(format: NSLocalizedString("update.state.available", comment: "Update available: %@"), info.version)
        case .upToDate: return NSLocalizedString("update.state.upToDate", comment: "App is up to date")
        case .downloading(let progress): return String(format: NSLocalizedString("update.state.downloading", comment: "Downloading: %d%%"), Int(progress * 100))
        case .installing: return NSLocalizedString("update.state.installing", comment: "Installing...")
        case .error(let msg): return String(format: NSLocalizedString("update.state.error", comment: "Error: %@"), msg)
        }
    }
}

// MARK: - Update Manager
class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published var state: UpdateState = .idle
    @Published var lastCheckDate: Date?

    @Published var canCheckForUpdates = true
    @Published var isCheckingForUpdates = false

    private var downloadTask: URLSessionDownloadTask?
    private var downloadingVersion: String?
    private var downloadingIsDMG: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private let autoCheckInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private let autoCheckKey = "lastUpdateCheckDate"
    private let skipVersionKey = "skipUpdateVersion"

    override init() {
        super.init()
        lastCheckDate = UserDefaults.standard.object(forKey: autoCheckKey) as? Date

        $state
            .map { state in
                if case .checking = state { return true }
                if case .downloading = state { return true }
                if case .installing = state { return true }
                return false
            }
            .assign(to: \.isCheckingForUpdates, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func checkForUpdates() {
        checkForUpdates(silent: false)
    }

    func checkForUpdatesSilently() {
        guard let lastCheck = lastCheckDate,
              Date().timeIntervalSince(lastCheck) >= autoCheckInterval else {
            if lastCheckDate == nil {
                checkForUpdates(silent: true)
            }
            return
        }
        checkForUpdates(silent: true)
    }

    func downloadUpdate(_ info: UpdateInfo) {
        state = .downloading(progress: 0)
        downloadingVersion = info.version
        downloadingIsDMG = info.isDMG

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: info.downloadURL)
        downloadTask?.resume()
    }

    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: skipVersionKey)
        state = .idle
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    // MARK: - Private Methods

    private func checkForUpdates(silent: Bool) {
        if !silent { state = .checking }

        UpdateChecker.shared.checkForUpdates { [weak self] result in
            guard let self = self else { return }

            self.lastCheckDate = Date()
            UserDefaults.standard.set(self.lastCheckDate, forKey: self.autoCheckKey)

            switch result {
            case .available(let info):
                let skipped = UserDefaults.standard.string(forKey: self.skipVersionKey)
                if silent && skipped == info.version {
                    self.state = .idle
                    return
                }
                self.state = .available(info)

            case .upToDate:
                self.state = .upToDate
                if silent {
                    self.state = .idle
                } else {
                     DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                         self.state = .idle
                     }
                }

            case .error(let message):
                self.state = .error(message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - Install

    private func install(zipPath: URL) {
        state = .installing

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.prepareInstall(zipPath: zipPath)

            DispatchQueue.main.async {
                switch result {
                case .success(let tempApp):
                    self.relaunchWithNewApp(tempApp: tempApp)
                case .failure(let error):
                    self.state = .error(error)
                }
            }
        }
    }

    private func installFromDMG(dmgPath: URL) {
        state = .installing

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.prepareDMGInstall(dmgPath: dmgPath)

            DispatchQueue.main.async {
                switch result {
                case .success(let tempApp):
                    self.relaunchWithNewApp(tempApp: tempApp)
                case .failure(let error):
                    self.state = .error(error)
                }
            }
        }
    }

    private enum InstallResult {
        case success(tempApp: String)
        case failure(error: String)
    }

    private func prepareInstall(zipPath: URL) -> InstallResult {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("ObsidianHotCornerMDUpdate")

        // Clean up previous temp dir
        try? fileManager.removeItem(at: tempDir)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Unzip
        let unzipOutput = shell("unzip -o '\(zipPath.path)' -d '\(tempDir.path)'")
        guard unzipOutput.ok else {
            return .failure(error: NSLocalizedString("error.unzipFailed", comment: "Failed to unzip update file."))
        }

        // Find .app bundle
        var appBundlePath: String?
        if let contents = try? fileManager.contentsOfDirectory(atPath: tempDir.path) {
            for item in contents {
                if item.hasSuffix(".app") {
                    appBundlePath = tempDir.appendingPathComponent(item).path
                    break
                }
            }
        }

        guard let sourceApp = appBundlePath else {
            return .failure(error: NSLocalizedString("error.noAppInZip", comment: "No app bundle found in update."))
        }

        return .success(tempApp: sourceApp)
    }

    private func prepareDMGInstall(dmgPath: URL) -> InstallResult {
        let fileManager = FileManager.default
        let mountPoint = fileManager.temporaryDirectory
            .appendingPathComponent("ObsidianHotCornerMDMount-\(UUID().uuidString)", isDirectory: true)

        // Step 1: Strip quarantine from DMG
        _ = shell("xattr -cr \(shellQuote(dmgPath.path))")

        do {
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        } catch {
            return .failure(error: error.localizedDescription)
        }

        // Step 2: Mount DMG at a unique path so existing mounted DMGs cannot be mistaken for the update.
        let attachOutput = shell(
            "hdiutil attach -nobrowse -noverify -mountpoint \(shellQuote(mountPoint.path)) \(shellQuote(dmgPath.path))"
        )
        guard attachOutput.ok else {
            try? fileManager.removeItem(at: mountPoint)
            return .failure(error: String(format: NSLocalizedString("error.mountDMG", comment: "Failed to mount DMG file. Output: %@"), attachOutput.output))
        }

        // Step 3: Parse device from output. The mount point is the unique path we provided.
        var devicePath: String?
        let lines = attachOutput.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            let fields = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if let first = fields.first, first.hasPrefix("/dev/") {
                if devicePath == nil || line.contains(mountPoint.path) {
                    devicePath = fields[0]
                }
            }
        }

        guard let device = devicePath else {
            _ = shell("hdiutil detach \(shellQuote(mountPoint.path)) -force 2>/dev/null || true")
            try? fileManager.removeItem(at: mountPoint)
            return .failure(error: String(format: NSLocalizedString("error.parseMount", comment: "Could not parse mount point. Output: %@"), attachOutput.output))
        }

        // Step 4: Find app bundle in mounted volume
        var appInDMG: String?
        if let contents = try? fileManager.contentsOfDirectory(atPath: mountPoint.path) {
            for item in contents {
                if item.hasSuffix(".app") {
                    appInDMG = mountPoint.appendingPathComponent(item).path
                    break
                }
            }
        }

        guard let sourceApp = appInDMG else {
            _ = shell("hdiutil detach \(shellQuote(device)) -force")
            try? fileManager.removeItem(at: mountPoint)
            return .failure(error: NSLocalizedString("error.noAppInDMG", comment: "No app bundle found in DMG."))
        }

        // Step 5: Copy to temp location
        let tempApp = fileManager.temporaryDirectory
            .appendingPathComponent("ObsidianHotCornerMD-new-\(UUID().uuidString).app")
            .path
        _ = shell("rm -rf \(shellQuote(tempApp))")
        let copyOutput = shell("cp -R \(shellQuote(sourceApp)) \(shellQuote(tempApp))")
        guard copyOutput.ok else {
            _ = shell("hdiutil detach \(shellQuote(device)) -force")
            try? fileManager.removeItem(at: mountPoint)
            return .failure(error: NSLocalizedString("error.copyAppFailed", comment: "Failed to copy app from DMG."))
        }

        // Step 6: Strip quarantine from copied app
        _ = shell("xattr -cr \(shellQuote(tempApp))")
        _ = shell("xattr -d com.apple.quarantine \(shellQuote(tempApp)) 2>/dev/null || true")

        // Step 7: Unmount DMG
        let detachOutput = shell("hdiutil detach \(shellQuote(device)) -force")
        if !detachOutput.ok {
            print("Warning: Failed to detach DMG device \(device): \(detachOutput.output)")
        }
        try? fileManager.removeItem(at: mountPoint)

        return .success(tempApp: tempApp)
    }

    private func relaunchWithNewApp(tempApp: String) {
        let bundlePath = Bundle.main.bundlePath

        // Set flag to reopen settings after update
        UserDefaults.standard.set(true, forKey: "obsidianhotcornermd.reopenSettings")
        UserDefaults.standard.synchronize()

        // Improved relaunch script with longer wait and explicit process termination
        let quotedBundlePath = shellQuote(bundlePath)
        let quotedTempApp = shellQuote(tempApp)

        let script = """
        # Wait for app to terminate gracefully (poll up to 10 seconds)
        for i in {1..20}; do
            if ! pgrep -x "ObsidianHotCornerMD" > /dev/null 2>&1; then
                echo "App terminated gracefully after $(($i * 500))ms"
                break
            fi
            sleep 0.5
        done

        # If still running, force kill
        if pgrep -x "ObsidianHotCornerMD" > /dev/null 2>&1; then
            echo "App still running after 10s, force killing..."
            pkill -9 -x "ObsidianHotCornerMD"
            sleep 1
        fi

        # Replace old app with new
        rm -rf \(quotedBundlePath)
        mv \(quotedTempApp) \(quotedBundlePath)

        # Final quarantine strip
        xattr -cr \(quotedBundlePath)

        # Launch new version
        open \(quotedBundlePath)
        """

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        try? task.run()

        NSApp.terminate(nil)
    }

    @discardableResult
    private func shell(_ command: String) -> (output: String, ok: Bool) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus == 0)
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - URLSession Download Delegate

extension UpdateManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let version = downloadingVersion ?? "latest"
        let fileExtension = downloadingIsDMG ? "dmg" : "zip"
        let filePath = tempDir.appendingPathComponent("ObsidianHotCornerMD-\(version).\(fileExtension)")

        do {
            if FileManager.default.fileExists(atPath: filePath.path) {
                try FileManager.default.removeItem(at: filePath)
            }
            try FileManager.default.copyItem(at: location, to: filePath)

            if downloadingIsDMG {
                installFromDMG(dmgPath: filePath)
            } else {
                install(zipPath: filePath)
            }
        } catch {
            state = .error(String(format: NSLocalizedString("error.saveUpdate", comment: "Failed to save update file: %@"), error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.state = .downloading(progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        DispatchQueue.main.async {
            if (error as NSError).code == NSURLErrorCancelled {
                self.state = .idle
            } else {
                self.state = .error(String(format: NSLocalizedString("error.downloadFailed", comment: "Download failed: %@"), error.localizedDescription))
            }
        }
    }
}
