import Foundation

/// Where a station came from. Drives both grouping and the accent it gets.
public enum StationSource: String, Sendable, CaseIterable {
    case cliamp = "Cliamp"
    case directory = "Directory"
    case custom = "Custom"
    case local = "Local"
    case provider = "Provider"
    case podcast = "Podcast"
}

public struct Station: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var url: String
    public var source: StationSource
    public var slug: String
    public var tags: String
    public var country: String
    public var countryCode: String
    public var codec: String
    public var bitrate: Int
    public var votes: Int
    public var homepage: String
    public var favicon: String
    public var uuid: String
    /// Artwork URI for local songs and playlists (a file or asset URL).
    public var cover: String
    /// Local-file metadata, empty for streams.
    public var artist: String
    public var album: String
    public var durationMs: Int64
    /// When the file first entered the local library, seconds since epoch.
    public var dateAdded: Int64

    public init(
        id: String,
        name: String,
        url: String,
        source: StationSource,
        slug: String = "",
        tags: String = "",
        country: String = "",
        countryCode: String = "",
        codec: String = "",
        bitrate: Int = 0,
        votes: Int = 0,
        homepage: String = "",
        favicon: String = "",
        uuid: String = "",
        cover: String = "",
        artist: String = "",
        album: String = "",
        durationMs: Int64 = 0,
        dateAdded: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.source = source
        self.slug = slug
        self.tags = tags
        self.country = country
        self.countryCode = countryCode
        self.codec = codec
        self.bitrate = bitrate
        self.votes = votes
        self.homepage = homepage
        self.favicon = favicon
        self.uuid = uuid
        self.cover = cover
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.dateAdded = dateAdded
    }

    /// `mp3 · 128k · Germany`, skipping whatever the directory did not know.
    public var meta: String {
        var parts: [String] = []
        if !codec.isEmpty { parts.append(codec.lowercased()) }
        if bitrate > 0 { parts.append("\(bitrate)k") }
        if !country.isEmpty { parts.append(country.lowercased()) }
        return parts.joined(separator: " · ")
    }

    /// `artist · album` for local files, blank if neither is known.
    public var artistAlbum: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A finite thing with an end, as opposed to a live stream.
    public var isTrack: Bool {
        source == .local || source == .provider || source == .podcast
    }

    public var tagList: [String] {
        tags.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count > 1 }
            .uniqued()
    }

    /// The one-line fallback under a station's name, per source.
    public var sourceLine: String {
        switch source {
        case .cliamp: "cliamp radio"
        case .local: artistAlbum.isEmpty ? "local audio" : artistAlbum
        case .podcast: artist.isEmpty ? "podcast" : artist
        default: meta.isEmpty ? "live stream" : meta
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
