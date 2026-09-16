import CliampCore
import Foundation
import os

/// Follows a `.m3u`/`.pls` link one hop to a playable URL, the way Android's
/// `StreamResolver` does at play time. HLS and everything else pass straight
/// through; a failed fetch falls back to the original URL rather than
/// refusing to play, and the bound keeps a mislabelled endpoint from
/// streaming megabytes into memory.
enum StreamResolver {
    private static let log = Logger(subsystem: "stream.cliamp.mobile", category: "resolver")
    private static let maxBody = 512 * 1024

    static func resolve(_ urlString: String) async -> String {
        let kind = PlaylistKind(url: urlString)
        guard kind == .m3u || kind == .pls, let url = URL(string: urlString) else {
            return urlString
        }
        guard let body = await fetchText(url) else { return urlString }
        let first = kind == .m3u
            ? PlaylistText.firstURL(inM3U: body)
            : PlaylistText.firstURL(inPLS: body)
        guard let first else { return urlString }
        log.info("resolved \(urlString, privacy: .public) -> \(first, privacy: .public)")
        return first
    }

    private static func fetchText(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= maxBody
        else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
