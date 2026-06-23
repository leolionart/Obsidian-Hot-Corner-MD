import Foundation

extension URL {
    private static let invalidObsidianPathCharacters =
        CharacterSet.controlCharacters.union(.newlines)

    /// obsidian://open?path=… URL
    var obsidianOpenURL: URL? {
        let rawPath = path
        guard !rawPath.isEmpty else {
            return nil
        }
        if rawPath.rangeOfCharacter(from: Self.invalidObsidianPathCharacters) != nil {
            return nil
        }
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: rawPath)]
        return components.url
    }

    /// Convert "/Users/<name>/…/Projects/Vault/file.md" to "Projects/Vault/file.md"
    var pathRelativeToHome: String {
        let homePrefix = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        if path.hasPrefix(homePrefix) {
            return String(path.dropFirst(homePrefix.count))
        } else {
            return path
        }
    }
}

struct FileHelper {
    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    static func saveQuickNote(text rawText: String, folderURL: URL, date: Date = Date()) throws -> URL {
        let body = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        let fileURL = uniqueFileURL(in: folderURL, baseName: fileDateFormatter.string(from: date))
        let markdown = normalizedMarkdown(from: body)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func uniqueFileURL(in folderURL: URL, baseName: String) -> URL {
        let manager = FileManager.default
        var candidate = folderURL.appendingPathComponent("\(baseName).md")
        var index = 2

        while manager.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(baseName)-\(index).md")
            index += 1
        }

        return candidate
    }

    private static func normalizedMarkdown(from body: String) -> String {
        guard let firstLine = body
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else {
            return body + "\n"
        }

        if firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return body + "\n"
        }

        let title = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)

        return "# \(title)\n\n\(body)\n"
    }
}
