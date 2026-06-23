import SwiftUI
import MarkdownUI
import AppKit

struct PreviewContentView: View {
    @ObservedObject var viewModel: PreviewViewModel
    let settings: SettingsModel

    private var contentWidth: CGFloat {
        settings.quickNoteMode ? max(CGFloat(settings.previewWidth), 760) : CGFloat(settings.previewWidth)
    }

    var body: some View {
        Group {
            if settings.quickNoteMode {
                quickNoteView
            } else if let url = viewModel.fileURL,
                      FileManager.default.fileExists(atPath: url.path) {
                ScrollView(.vertical) {
                    Markdown(viewModel.text)
                        .markdownTheme(.gitHub)
                        .padding(Constants.textPadding)
                }
            } else {
                Text(LocalizedStringKey("placeholder.pleaseSelectFile"))
                    .foregroundColor(.gray)
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(settings.quickNoteMode ? 0 : Constants.scrollPadding)
        .frame(minWidth: contentWidth, maxWidth: contentWidth, alignment: .leading)
        .background(Color(red: 24.0/255.0, green: 25.0/255.0, blue: 29.0/255.0, opacity: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius, style: .continuous))
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
            VStack(alignment: .leading, spacing: 12) {
                quickNoteHeader(folderURL: folderURL)

                ZStack(alignment: .topLeading) {
                    MarkdownEditingTextView(
                        text: $viewModel.quickNoteText,
                        onPasteImage: { image in
                            pasteImage(image, folderURL: folderURL)
                        }
                    )

                    if viewModel.quickNoteText.isEmpty {
                        Text(LocalizedStringKey("quicknote.placeholder"))
                            .foregroundColor(.white.opacity(0.34))
                            .font(.system(size: 16, design: .monospaced))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
                .background(Color(red: 31.0/255.0, green: 33.0/255.0, blue: 38.0/255.0))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                if let error = viewModel.quickNoteError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }

                quickNoteFooter
            }
            .padding(16)
        } else {
            missingFolderView
        }
    }

    private func quickNoteHeader(folderURL: URL) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(LocalizedStringKey("quicknote.title"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LocalizedStringKey("quicknote.destination"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                Text(folderURL.pathRelativeToHome)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 310, alignment: .trailing)
            }
        }
    }

    private var quickNoteFooter: some View {
        HStack {
            Text(String(format: NSLocalizedString("quicknote.wordCount", comment: ""), wordCount))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))

            Text(LocalizedStringKey("quicknote.pasteHint"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.35))

            Spacer()

            Button(action: cancelQuickNote) {
                Text(LocalizedStringKey("quicknote.cancel"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button(action: saveQuickNote) {
                Text(LocalizedStringKey("quicknote.save"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(7)
            }
            .disabled(viewModel.quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(viewModel.quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var missingFolderView: some View {
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
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var wordCount: Int {
        viewModel.quickNoteText
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private func pasteImage(_ image: NSImage, folderURL: URL) -> String? {
        do {
            let relativePath = try FileHelper.savePastedImage(image, in: folderURL)
            viewModel.quickNoteError = nil
            return "\n![](\(relativePath))\n"
        } catch {
            viewModel.quickNoteError = String(
                format: NSLocalizedString("quicknote.imagePasteFailed", comment: ""),
                error.localizedDescription
            )
            return nil
        }
    }

    private func cancelQuickNote() {
        viewModel.quickNoteError = nil
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hidePreviewWindow()
        }
    }

    private func saveQuickNote() {
        guard let folderURL = settings.quickNoteFolderURL else { return }
        let text = viewModel.quickNoteText

        do {
            let savedFileURL = try FileHelper.saveQuickNote(text: text, folderURL: folderURL)
            viewModel.quickNoteText = ""
            viewModel.quickNoteError = nil

            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.hidePreviewWindow()
            }

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

struct MarkdownEditingTextView: NSViewRepresentable {
    @Binding var text: String
    var onPasteImage: (NSImage) -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownNSTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.insertionPointColor = .white
        textView.string = text
        context.coordinator.applyMarkdownStyle(to: textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        textView.onPasteImage = onPasteImage

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        context.coordinator.applyMarkdownStyle(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        private var isStyling = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            applyMarkdownStyle(to: textView)
        }

        func applyMarkdownStyle(to textView: NSTextView) {
            guard !isStyling, let textStorage = textView.textStorage else { return }
            isStyling = true

            let selectedRanges = textView.selectedRanges
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            let baseColor = NSColor.white.withAlphaComponent(0.92)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 3
            paragraphStyle.paragraphSpacing = 5

            textStorage.beginEditing()
            if fullRange.length > 0 {
                textStorage.setAttributes([
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: paragraphStyle
                ], range: fullRange)
            }

            let nsText = textView.string as NSString
            nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
                guard lineRange.location < textStorage.length else { return }
                let line = nsText.substring(with: lineRange)
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("# ") {
                    textStorage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                        .foregroundColor: NSColor.white
                    ], range: lineRange)
                } else if trimmed.hasPrefix("## ") {
                    textStorage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                        .foregroundColor: NSColor.white
                    ], range: lineRange)
                } else if trimmed.hasPrefix("### ") {
                    textStorage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                        .foregroundColor: NSColor.white
                    ], range: lineRange)
                } else if trimmed.hasPrefix(">") {
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.85)
                    ], range: lineRange)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("- [") {
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.white.withAlphaComponent(0.86)
                    ], range: lineRange)
                }
            }

            highlightInline(pattern: "`[^`]+`", in: textStorage, text: textView.string, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.systemGreen.withAlphaComponent(0.95)
            ])

            highlightInline(pattern: "\\*\\*([^*]+)\\*\\*", in: textStorage, text: textView.string, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
            ])

            highlightInline(pattern: "_([^_]+)_", in: textStorage, text: textView.string, attributes: [
                .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            ])

            textStorage.endEditing()
            textView.selectedRanges = selectedRanges
            isStyling = false
        }

        private func highlightInline(pattern: String, in textStorage: NSTextStorage, text: String, attributes: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: (text as NSString).length)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                textStorage.addAttributes(attributes, range: match.range)
            }
        }
    }
}

final class MarkdownNSTextView: NSTextView {
    var onPasteImage: ((NSImage) -> String?)?

    override func cancelOperation(_ sender: Any?) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hidePreviewWindow()
        } else {
            super.cancelOperation(sender)
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard let listPrefix = continuedListPrefix() else {
            super.insertNewline(sender)
            return
        }

        if listPrefix.shouldExitList {
            let range = listPrefix.currentMarkerRange
            if shouldChangeText(in: range, replacementString: "") {
                textStorage?.replaceCharacters(in: range, with: "")
                didChangeText()
            }
            return
        }

        insertText("\n\(listPrefix.nextMarker)", replacementRange: selectedRange())
    }

    override func paste(_ sender: Any?) {
        if let image = pasteboardImage(),
           let markdown = onPasteImage?(image) {
            insertText(markdown, replacementRange: selectedRange())
            return
        }

        super.paste(sender)
    }

    private func pasteboardImage() -> NSImage? {
        let pasteboard = NSPasteboard.general

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
            for url in urls where url.isFileURL {
                if let image = NSImage(contentsOf: url as URL) {
                    return image
                }
            }
        }

        return nil
    }

    private struct ListContinuation {
        let nextMarker: String
        let currentMarkerRange: NSRange
        let shouldExitList: Bool
    }

    private func continuedListPrefix() -> ListContinuation? {
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }

        let nsText = string as NSString
        guard nsText.length > 0 else { return nil }

        let cursor = min(selection.location, nsText.length)
        let lineLookupLocation = max(0, min(cursor, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: lineLookupLocation, length: 0))
        let lineText = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

        guard let marker = listMarker(in: lineText) else { return nil }

        let markerLocation = lineRange.location + marker.leadingWhitespaceCount
        let markerRange = NSRange(location: markerLocation, length: marker.markerLength)
        let shouldExitList = lineText.dropFirst(marker.leadingWhitespaceCount + marker.markerLength)
            .trimmingCharacters(in: .whitespaces)
            .isEmpty

        return ListContinuation(
            nextMarker: marker.nextMarker,
            currentMarkerRange: markerRange,
            shouldExitList: shouldExitList
        )
    }

    private struct ListMarker {
        let leadingWhitespaceCount: Int
        let markerLength: Int
        let nextMarker: String
    }

    private func listMarker(in lineText: String) -> ListMarker? {
        if let marker = regexListMarker(
            in: lineText,
            pattern: #"^(\s*)(-\s+\[[ xX]\]\s+)"#,
            nextMarker: { "\($0[1])- [ ] " }
        ) {
            return marker
        }

        if let marker = regexListMarker(
            in: lineText,
            pattern: #"^(\s*)([-*]\s+)"#,
            nextMarker: { "\($0[1])\($0[2])" }
        ) {
            return marker
        }

        return regexListMarker(
            in: lineText,
            pattern: #"^(\s*)(\d+)([.)]\s+)"#,
            nextMarker: { groups in
                let nextNumber = (Int(groups[2]) ?? 0) + 1
                return "\(groups[1])\(nextNumber)\(groups[3])"
            }
        )
    }

    private func regexListMarker(
        in lineText: String,
        pattern: String,
        nextMarker: ([String]) -> String
    ) -> ListMarker? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = lineText as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: lineText, range: range) else { return nil }

        let groups = (0..<match.numberOfRanges).map { index -> String in
            let groupRange = match.range(at: index)
            guard groupRange.location != NSNotFound else { return "" }
            return nsLine.substring(with: groupRange)
        }

        return ListMarker(
            leadingWhitespaceCount: (groups[safe: 1] ?? "").count,
            markerLength: match.range(at: 0).length - (groups[safe: 1] ?? "").count,
            nextMarker: nextMarker(groups)
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
