import SwiftUI
import Foundation
import KeyboardShortcuts
import AppKit

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var updateManager: UpdateManager
    @State private var showingImporter = false

    private func screenWidth() -> Double {
        Double(NSScreen.main?.visibleFrame.width ?? 800)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label(LocalizedStringKey("settings.markdownFile"), systemImage: "doc.text")) {
                HStack {
                    Text(model.fileURL?.pathRelativeToHome ?? NSLocalizedString("settings.none", comment: ""))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(LocalizedStringKey("settings.choose")) {
                        showingImporter = true
                    }
                    .fileImporter(isPresented: $showingImporter,
                                  allowedContentTypes: [.plainText],
                                  allowsMultipleSelection: false) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            model.fileURL = url
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            GroupBox(label: Label(LocalizedStringKey("settings.quickNoteMode"), systemImage: "note.text.badge.plus")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(LocalizedStringKey("settings.enableQuickNote"), isOn: $model.quickNoteMode)

                    if model.quickNoteMode {
                        HStack {
                            Text(model.quickNoteFolderURL?.pathRelativeToHome ?? NSLocalizedString("settings.none", comment: ""))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(LocalizedStringKey("settings.chooseFolder")) {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.begin { response in
                                    if response == .OK, let url = panel.url {
                                        model.quickNoteFolderURL = url
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            GroupBox(label: Label(LocalizedStringKey("settings.previewLines"), systemImage: "text.alignleft")) {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(model.previewLines) },
                            set: { model.previewLines = Int($0) }
                        ),
                        in: 5...100,
                        step: 5
                    )
                    Text("\(model.previewLines)")
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            GroupBox(label: Label(LocalizedStringKey("settings.previewWidth"), systemImage: "arrow.left.and.right")) {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(model.previewWidth) },
                            set: { model.previewWidth = Int($0) }
                        ),
                        in: 200...screenWidth(),
                        step: 50
                    )
                    Text("\(model.previewWidth)")
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            GroupBox(label: Label(LocalizedStringKey("settings.hotCorners"), systemImage: "rectangle.portrait.inset.filled")) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Toggle(LocalizedStringKey("settings.topLeft"), isOn: $model.topLeft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(LocalizedStringKey("settings.topRight"), isOn: $model.topRight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Toggle(LocalizedStringKey("settings.bottomLeft"), isOn: $model.bottomLeft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(LocalizedStringKey("settings.bottomRight"), isOn: $model.bottomRight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            GroupBox(label: Label(LocalizedStringKey("settings.behavior"), systemImage: "gearshape")) {
                VStack(alignment: .leading) {
                    Toggle(LocalizedStringKey("settings.openInObsidian"), isOn: $model.openOnClick)
                    Toggle(LocalizedStringKey("settings.openAtLogin"), isOn: $model.launchAtLogin)
                    Toggle(LocalizedStringKey("settings.enableShortcut"), isOn: $model.shortcutEnabled)

                    if model.shortcutEnabled {
                        HStack {
                            Text(LocalizedStringKey("settings.shortcut"))
                            KeyboardShortcuts.Recorder(for: .togglePreview)
                            Spacer()
                        }
                        .padding(.vertical, 5)

                        Picker("", selection: $model.shortcutCorner) {
                            ForEach(Corner.allCases, id: \.rawValue) { corner in
                                Text(corner.rawValue.capitalized).tag(corner)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                        .padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            SoftwareUpdateSection(updateManager: updateManager)

            Button {
                if let url = URL(string: "https://github.com/nbox/ObsidianHotCornerMD") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text(LocalizedStringKey("settings.viewOnGitHub"))
                    Spacer()
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            GroupBox {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Label(LocalizedStringKey("settings.quit"), systemImage: "power")
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(minWidth: 350)
    }
}

struct SoftwareUpdateSection: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        GroupBox(label: Label(LocalizedStringKey("settings.softwareUpdate"), systemImage: "arrow.clockwise.circle")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(LocalizedStringKey("update.currentVersion"))
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                        .foregroundColor(.secondary)
                }

                if let lastCheck = updateManager.lastCheckDate {
                    HStack {
                        Text(LocalizedStringKey("update.lastChecked"))
                        Spacer()
                        Text(formatDate(lastCheck))
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }

                Divider()

                switch updateManager.state {
                case .idle, .upToDate, .error:
                    VStack(alignment: .leading, spacing: 6) {
                        Button(LocalizedStringKey("update.checkForUpdates")) {
                            updateManager.checkForUpdates()
                        }
                        .disabled(updateManager.isCheckingForUpdates)

                        if case .error(let message) = updateManager.state {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.red)
                        } else if case .upToDate = updateManager.state {
                            Text(LocalizedStringKey("update.upToDate"))
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    }

                case .checking:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 18, height: 18)
                        Text(LocalizedStringKey("update.checking"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                case .available(let info):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: NSLocalizedString("update.newAvailable", comment: ""), info.version))
                            .font(.system(size: 13, weight: .semibold))

                        if !info.releaseNotes.isEmpty {
                            ScrollView {
                                Text(info.releaseNotes)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(maxHeight: 90)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }

                        HStack {
                            Button(LocalizedStringKey("update.downloadAndInstall")) {
                                updateManager.downloadUpdate(info)
                            }
                            Spacer()
                            Button(LocalizedStringKey("update.skip")) {
                                updateManager.skipVersion(info.version)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        HStack {
                            Text(String(format: NSLocalizedString("update.downloading", comment: ""), Int(progress * 100)))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(LocalizedStringKey("update.cancel")) {
                                updateManager.cancelDownload()
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                case .installing:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 18, height: 18)
                        Text(LocalizedStringKey("update.installing"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
