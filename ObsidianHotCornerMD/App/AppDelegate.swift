import Cocoa
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePreview = KeyboardShortcuts.Name("togglePreview")
}

class AppDelegate: NSObject, NSApplicationDelegate, HotCornerDelegate {
    var statusItem: NSStatusItem!



    var popover: NSPopover!
    let settings = SettingsModel()
    let monitor = HotCornerMonitor()
    let updateManager = UpdateManager()

    private var previewWindow: PreviewWindow!
    private var hideTimer: Timer?
    private var keyMonitor: Any?
    private var suppressQuickNoteUntilCornerExit = false
    private var suppressQuickNoteUntil = Date.distantPast
    // Cache file contents to avoid re-reading during animations
    private var cachedText: String = ""
    private var cachedURL: URL?
    private var cachedMTime: Date?

    private func loadContent() -> String {
        guard let url = settings.fileURL else {
            cachedURL = nil
            cachedMTime = nil
            cachedText = ""
            return ""
        }
        // If the URL changed, drop the cache
        if cachedURL != url {
            cachedMTime = nil
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let mtime = attrs[.modificationDate] as? Date
            if cachedURL == url, let cachedMTime, let mtime, cachedMTime == mtime {
                return cachedText
            }
            // Read the file
            let text = try String(contentsOf: url, encoding: .utf8)
            cachedURL = url
            cachedMTime = mtime
            cachedText = text
            return text
        } catch {
            // On error keep cached text if available; otherwise show an error string
            return cachedText.isEmpty ? NSLocalizedString("error.badFile", comment: "") : cachedText
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        previewWindow = PreviewWindow(settings: settings)
        // Hide Dock icon but allow window interaction
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Settings")
            btn.action = #selector(toggleSettings(_:))
            btn.target = self
        }


        // Settings popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SettingsView(model: settings, updateManager: updateManager))

        // Start mouse movement monitor
        monitor.delegate = self
        monitor.start()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.settings.quickNoteMode,
               self.previewWindow.isVisible,
               event.keyCode == 53 {
                self.dismissQuickNoteWindow()
                return nil
            }
            return event
        }

        // Trigger update check silently on launch
        updateManager.checkForUpdatesSilently()

        // Reopen settings popover if relaunching from update install
        if UserDefaults.standard.bool(forKey: "obsidianhotcornermd.reopenSettings") {
            UserDefaults.standard.removeObject(forKey: "obsidianhotcornermd.reopenSettings")
            UserDefaults.standard.synchronize()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showSettings()
            }
        }


        KeyboardShortcuts.onKeyUp(for: .togglePreview) { [weak self] in
            guard let self = self, self.settings.shortcutEnabled else { return }
            let corner = self.settings.shortcutCorner
            if self.previewWindow.isVisible {
                self.previewWindow.hide()
            } else {
                if self.settings.quickNoteMode {
                    if !self.previewWindow.isVisible {
                        self.previewWindow.resetQuickNoteText()
                    }
                    self.previewWindow.show(
                        for: corner,
                        content: "",
                        maxLines: self.settings.previewLines,
                        fileURL: nil
                    )
                } else if self.settings.fileURL != nil {
                    let content = self.loadContent()
                    self.previewWindow.show(
                        for: corner,
                        content: content,
                        maxLines: self.settings.previewLines,
                        fileURL: self.settings.fileURL
                    )
                }
            }
        }
    }

    @objc func toggleSettings(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showSettings()
        }
    }

    func hidePreviewWindow() {
        dismissQuickNoteWindow()
    }

    func dismissQuickNoteWindow() {
        if settings.quickNoteMode {
            suppressQuickNoteUntilCornerExit = true
            suppressQuickNoteUntil = Date().addingTimeInterval(2.0)
            hideTimer?.invalidate()
            hideTimer = nil
        }
        previewWindow.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fadeDuration + 0.05) { [weak self] in
            self?.previewWindow.hideImmediately()
        }
    }

    func showSettings() {
        previewWindow.hide()
        guard let btn = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Size popover to fit content with a sensible minimum width
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            let fit = view.fittingSize
            let minWidth: CGFloat = 350
            popover.contentSize = NSSize(width: max(minWidth, fit.width), height: fit.height)
        }
    }


    // Handle mouse movement: show/hide the preview
    func mouseMoved(to corner: Corner?) {
        let loc = NSEvent.mouseLocation
        // Ignore if the pointer is over the preview window
        if previewWindow.frame.contains(loc) && !settings.quickNoteMode {
            return
        }
        // Update only when the corner changes


        let s = settings
        let active = (corner == .topLeft && s.topLeft)
        || (corner == .topRight && s.topRight)
        || (corner == .bottomLeft && s.bottomLeft)
        || (corner == .bottomRight && s.bottomRight)

        if !active {
            suppressQuickNoteUntilCornerExit = false
        }

        if active, let corner = corner {
            // Entered a corner — cancel hide timer
            hideTimer?.invalidate()
            hideTimer = nil

            if s.quickNoteMode && (suppressQuickNoteUntilCornerExit || Date() < suppressQuickNoteUntil) {
                return
            }

            if s.quickNoteMode {
                if !previewWindow.isVisible {
                    previewWindow.resetQuickNoteText()
                }
                previewWindow.show(
                    for: corner,
                    content: "",
                    maxLines: s.previewLines,
                    fileURL: nil
                )
            } else {
                // Show or reposition the preview window
                previewWindow.show(
                    for: corner,
                    content: loadContent(),
                    maxLines: s.previewLines,
                    fileURL: s.fileURL
                )
            }
        } else {
            // On exit — start a one‑shot hide timer
            if !s.quickNoteMode {
                hideTimer?.invalidate()
                hideTimer = Timer.scheduledTimer(withTimeInterval: Constants.hideDelay, repeats: false) { [weak self] _ in
                    self?.previewWindow.hide()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        monitor.stop()
        settings.saveSettings()
    }
}
