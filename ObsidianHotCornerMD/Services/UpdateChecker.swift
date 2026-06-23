import Foundation

// MARK: - Update Info
struct UpdateInfo {
    let version: String
    let downloadURL: URL
    let releaseNotes: String
    let publishedAt: Date?
    let isDMG: Bool
}

// MARK: - Update Check Result
enum UpdateCheckResult {
    case available(UpdateInfo)
    case upToDate
    case error(String)
}

// MARK: - Update Checker
class UpdateChecker {
    static let shared = UpdateChecker()

    // Configurable repository (defaults to leolionart/Obsidian-Hot-Corner-MD)
    var repository: String = "leolionart/Obsidian-Hot-Corner-MD"

    var allowPrereleases: Bool = {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let hasPrereleaseSuffix = currentVersion.contains("-") ||
                                  currentVersion.lowercased().contains("beta") ||
                                  currentVersion.lowercased().contains("alpha") ||
                                  currentVersion.lowercased().contains("rc")
        return UserDefaults.standard.bool(forKey: "allowPrereleases") || hasPrereleaseSuffix
    }()

    private var githubAPIURL: String {
        return "https://api.github.com/repos/\(repository)/releases"
    }

    private init() {}

    /// Check for updates asynchronously
    func checkForUpdates(completion: @escaping (UpdateCheckResult) -> Void) {
        guard let url = URL(string: githubAPIURL) else {
            completion(.error("Invalid API URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15 // 15 seconds timeout

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.error(String(format: NSLocalizedString("error.network", comment: "Network error: %@"), error.localizedDescription)))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.error(NSLocalizedString("error.invalidResponse", comment: "Invalid response")))
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    completion(.error(String(format: NSLocalizedString("error.server", comment: "Server error: %d"), httpResponse.statusCode)))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.error(NSLocalizedString("error.noData", comment: "No data received")))
                }
                return
            }

            self?.parseResponse(data: data, completion: completion)
        }

        task.resume()
    }

    private func parseResponse(data: Data, completion: @escaping (UpdateCheckResult) -> Void) {
        do {
            // Parse as array of releases
            guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { completion(.error(NSLocalizedString("error.invalidJSON", comment: "Invalid JSON format"))) }
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            // Find the highest version release (not draft/prerelease unless allowed)
            var bestRelease: [String: Any]?
            var bestVersion = ""

            for release in releases {
                guard let tagName = release["tag_name"] as? String,
                      release["draft"] as? Bool != true else { continue }

                let isPrerelease = release["prerelease"] as? Bool == true
                if isPrerelease && !allowPrereleases {
                    continue
                }

                let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                // Compare with current best
                if bestVersion.isEmpty {
                    bestVersion = version
                    bestRelease = release
                } else {
                    if compareVersions(version, bestVersion) == .orderedDescending {
                        bestVersion = version
                        bestRelease = release
                    }
                }
            }

            guard let release = bestRelease, !bestVersion.isEmpty else {
                DispatchQueue.main.async { completion(.upToDate) }
                return
            }

            // Check if update available (bestVersion > currentVersion)
            if compareVersions(bestVersion, currentVersion) != .orderedDescending {
                DispatchQueue.main.async { completion(.upToDate) }
                return
            }

            // Find DMG/ZIP download URL (prefer DMG)
            var downloadURL: URL?
            var isDMG = false
            if let assets = release["assets"] as? [[String: Any]] {
                // First pass: look for DMG
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.lowercased().hasSuffix(".dmg"),
                       let urlString = asset["browser_download_url"] as? String,
                       let url = URL(string: urlString) {
                        downloadURL = url
                        isDMG = true
                        break
                    }
                }

                // Second pass: fallback to ZIP if no DMG found
                if downloadURL == nil {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.lowercased().hasSuffix(".zip"),
                           let urlString = asset["browser_download_url"] as? String,
                           let url = URL(string: urlString) {
                            downloadURL = url
                            isDMG = false
                            break
                        }
                    }
                }
            }

            guard let finalDownloadURL = downloadURL else {
                DispatchQueue.main.async { completion(.error(NSLocalizedString("error.noDownloadFile", comment: "No download file found in release"))) }
                return
            }

            // Parse metadata
            let releaseNotes = release["body"] as? String ?? ""
            var publishedAt: Date?
            if let publishedString = release["published_at"] as? String {
                let formatter = ISO8601DateFormatter()
                publishedAt = formatter.date(from: publishedString)
            }

            let updateInfo = UpdateInfo(
                version: bestVersion,
                downloadURL: finalDownloadURL,
                releaseNotes: releaseNotes,
                publishedAt: publishedAt,
                isDMG: isDMG
            )

            DispatchQueue.main.async { completion(.available(updateInfo)) }

        } catch {
            DispatchQueue.main.async {
                completion(.error(String(format: NSLocalizedString("error.jsonParse", comment: "JSON parse error: %@"), error.localizedDescription)))
            }
        }
    }

    /// Compare two version strings
    /// Returns: .orderedAscending if v1 < v2, .orderedSame if equal, .orderedDescending if v1 > v2
    func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let components1 = v1.components(separatedBy: "-")
        let components2 = v2.components(separatedBy: "-")

        let base1 = components1[0]
        let base2 = components2[0]

        let baseResult = base1.compare(base2, options: .numeric)
        if baseResult != .orderedSame {
            return baseResult
        }

        // If base versions are the same, let's look at the prerelease part.
        // A version without a prerelease part is greater than one with a prerelease part.
        if components1.count == 1 && components2.count > 1 {
            return .orderedDescending
        }
        if components1.count > 1 && components2.count == 1 {
            return .orderedAscending
        }
        if components1.count == 1 && components2.count == 1 {
            return .orderedSame
        }

        // Both have prerelease components, compare them numerically.
        return components1[1].compare(components2[1], options: .numeric)
    }
}
