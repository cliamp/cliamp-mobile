package stream.cliamp.mobile.data

import kotlinx.serialization.Serializable

/** Where a station came from. Drives both grouping and the accent it gets. */
enum class StationSource { Cliamp, Directory, Custom, Local }

@Serializable
data class Station(
    val id: String,
    val name: String,
    val url: String,
    val source: StationSource,
    val slug: String = "",
    val tags: String = "",
    val country: String = "",
    val countryCode: String = "",
    val codec: String = "",
    val bitrate: Int = 0,
    val votes: Int = 0,
    val homepage: String = "",
    val favicon: String = "",
    val uuid: String = "",
    /** Artwork URI for local songs and playlists (a content:// or file:// string). */
    val cover: String = "",
    /** Local-file metadata, empty for streams. */
    val artist: String = "",
    val album: String = "",
    val durationMs: Long = 0L,
) {
    /** `mp3 · 128k · Germany`, skipping whatever the directory did not know. */
    val meta: String
        get() = buildList {
            if (codec.isNotBlank()) add(codec.lowercase())
            if (bitrate > 0) add("${bitrate}k")
            if (country.isNotBlank()) add(country.lowercase())
        }.joinToString(" · ")

    val tagList: List<String>
        get() = tags.split(',', ' ')
            .map { it.trim().lowercase() }
            .filter { it.length > 1 }
            .distinct()
}

/** What the player is currently doing, projected out of Media3. */
data class NowPlaying(
    val station: Station? = null,
    val streamTitle: String = "",
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val error: String? = null,
    val elapsedMs: Long = 0L,
    val bufferedMs: Long = 0L,
    val bitrateKbps: Int = 0,
    val sampleRateHz: Int = 0,
)
