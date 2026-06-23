import SwiftUI
import MarkdownUI
import AppKit

struct PreviewContentView: View {
    @ObservedObject var viewModel: PreviewViewModel
    let settings: SettingsModel

    var body: some View {
        Group {
            if settings.quickNoteMode {
                quickNoteView
            } else {
                // If a valid file is set
                if let url = viewModel.fileURL,
                   FileManager.default.fileExists(atPath: url.path) {

                    // Show Markdown
                    ScrollView(.vertical) {
                        Markdown(viewModel.text)
                            .markdownTheme(.gitHub)
                            .padding(Constants.textPadding)
                    }

                } else {
                    // Placeholder when no file is selected
                    Text(LocalizedStringKey("placeholder.pleaseSelectFile"))
                        .foregroundColor(.gray)
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: Constants.cornerRadius,
                                style: .continuous
                            )
                        )
                }
            }
        }
        .padding(Constants.scrollPadding)
        .frame(
            minWidth: CGFloat(settings.previewWidth),
            maxWidth: CGFloat(settings.previewWidth),
            alignment: .leading
        )
        .background(Color(red: 24.0/255.0, green: 25.0/255.0, blue: 29.0/255.0, opacity: 1.0))
        .clipShape(
            RoundedRectangle(
                cornerRadius: Constants.cornerRadius,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !settings.quickNoteMode else { return }
            guard settings.openOnClick,
                  let fileURL = viewModel.fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  let obsidianURL = fileURL.obsidianOpenURL else {
                return
            }
            NSWorkspace.shared.open(obsidianURL)
        }
    }

    @ViewBuilder
    private var quickNoteView: some View {
        if let folderURL = settings.quickNoteFolderURL {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.blue)
                    Text(LocalizedStringKey("quicknote.title"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }

                ZStack(alignment: .topLeading) {
                    if #available(macOS 13.0, *) {
                        TextEditor(text: $viewModel.quickNoteText)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .background(Color(white: 0.15))
                            .cornerRadius(4)
                    } else {
                        TextEditor(text: $viewModel.quickNoteText)
                            .font(.system(size: 13))
                            .cornerRadius(4)
                    }

                    if viewModel.quickNoteText.isEmpty {
                        Text(LocalizedStringKey("quicknote.placeholder"))
                            .foregroundColor(.gray)
                            .font(.system(size: 13))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let error = viewModel.quickNoteError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }

                HStack {
                    Button(action: {
                        viewModel.quickNoteText = ""
                        viewModel.quickNoteError = nil
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.hidePreviewWindow()
                        }
                    }) {
                        Text(LocalizedStringKey("quicknote.cancel"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Button(action: {
                        saveQuickNote()
                    }) {
                        Text(LocalizedStringKey("quicknote.save"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(6)
                    }
                    .disabled(viewModel.quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(Constants.textPadding)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(.yellow)
                Text(LocalizedStringKey("quicknote.noFolderConfigure"))
                    .foregroundColor(.gray)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                Button(action: {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showSettings()
                    }
                }) {
                    Text(LocalizedStringKey("quicknote.configureNow"))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func saveQuickNote() {
        guard let folderURL = settings.quickNoteFolderURL else { return }
        let text = viewModel.quickNoteText

        do {
            let savedFileURL = try FileHelper.saveQuickNote(text: text, folderURL: folderURL)
            viewModel.quickNoteText = ""
            viewModel.quickNoteError = nil

            // Hide the preview window
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.hidePreviewWindow()
            }

            // Optionally open in Obsidian if openOnClick is enabled
            if settings.openOnClick, let obsidianURL = savedFileURL.obsidianOpenURL {
                NSWorkspace.shared.open(obsidianURL)
            }
        } catch {
            viewModel.quickNoteError = String(
                format: NSLocalizedString("quicknote.saveFailed", comment: ""),
                error.localizedDescription
            )
        }
    }
}
