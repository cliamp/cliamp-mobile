package stream.cliamp.mobile.data

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * A song picked out of the device library. The [station] form is what the rest
 * of the app plays: a local file is just a Station whose `url` is a content
 * URI, so the whole playback pipeline behaves exactly as it does for a stream.
 */
data class LocalSong(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val albumId: Long,
    /** duration in milliseconds. */
    val durationMs: Long,
    val sizeBytes: Long,
    val uri: Uri,
) {
    val station: Station
        get() = Station(
            id = "local:$id",
            name = title,
            url = uri.toString(),
            source = StationSource.Local,
            cover = albumArtUri(albumId).toString(),
            artist = artist,
            album = album,
            durationMs = durationMs,
        )

    /** Longest sort field is the safe proxy for "starts with title". */
    val sortKey: String get() = title.lowercase()
}

private fun albumArtUri(albumId: Long): Uri =
    ContentUris.withAppendedId(Uri.parse("content://media/external/audio/albumart"), albumId)

/** "4:32" style duration for local-song rows and headers. */
fun durationLabel(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val m = total / 60
    val s = total % 60
    return "%d:%02d".format(m, s)
}

/**
 * Reads the phone's audio library from MediaStore, like Samsung Music and the
 * rest do. Nothing here is cached to disk — the OS owns that store, so we just
 * query it fresh on demand and keep a plain StateFlow for the UI to observe.
 */
class LocalLibrary(private val context: Context) {

    private val _songs = MutableStateFlow<List<Station>>(emptyList())
    val songs: StateFlow<List<Station>> = _songs.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun refresh() {
        _loading.value = true
        Thread {
            val found = runCatching { querySongs() }.getOrElse { e ->
                _error.value = e.message ?: "could not read the library"
                emptyList()
            }
            _songs.value = found
            _loading.value = false
        }.start()
    }

    private fun querySongs(): List<Station> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
        )
        val sort = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        val list = mutableListOf<Station>()
        val cursor = context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            sort,
        ) ?: return list
        cursor.use { c ->
            val id = c.getColumnIndex(MediaStore.Audio.Media._ID)
            val t = c.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val a = c.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val al = c.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val alId = c.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
            val d = c.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val s = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
            while (c.moveToNext()) {
                list += LocalSong(
                    id = c.getLong(id),
                    title = c.getString(t) ?: "unknown",
                    artist = c.getString(a) ?: "unknown artist",
                    album = c.getString(al) ?: "",
                    albumId = c.getLong(alId),
                    durationMs = c.getLong(d),
                    sizeBytes = c.getLong(s),
                    uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, c.getLong(id)),
                ).station
            }
        }
        return list
    }
}