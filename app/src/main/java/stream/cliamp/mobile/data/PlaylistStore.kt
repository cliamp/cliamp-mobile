package stream.cliamp.mobile.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import stream.cliamp.mobile.net.Http

private val Context.playlistDataStore by preferencesDataStore("playlists")

/**
 * Persists user playlists. A playlist is a small [Station] (source Local): its
 * `slug` is the stable id, `name` the title, `cover` an artwork URI, and `meta`
 * a human "N songs" line. Members are remembered as `local:<id>` strings so
 * they survive a MediaStore re-scan (URIs can move). The ordered song list for
 * a playlist is resolved against the live library when you open it.
 */
class PlaylistStore(private val context: Context) {

    data class Playlist(
        val station: Station,
        /** Ordered member ids (`local:<id>`), matching [LocalLibrary] ids. */
        val songIds: List<String>,
    )

    private val KMembers = stringPreferencesKey("members")
    private val KPlaylists = stringPreferencesKey("playlists")

    val playlists: Flow<List<Playlist>> = context.playlistDataStore.data.map { p ->
        val stations = p[KPlaylists]?.let {
            runCatching { Http.json.decodeFromString<List<Station>>(it) }.getOrNull()
        } ?: emptyList()
        val members = decodeMembers(p[KMembers])
        stations.map { s -> Playlist(s, members[s.slug].orEmpty()) }
    }

    suspend fun create(name: String, cover: String = "") {
        val slug = "pl:${System.nanoTime()}"
        val station = Station(
            id = slug,
            name = name.trim().ifBlank { "new playlist" },
            url = "cliamp-playlist://$slug",
            source = StationSource.Local,
            slug = slug,
            cover = cover,
        )
        editStations { it + station }
    }

    suspend fun rename(slug: String, name: String) {
        val clean = name.trim()
        if (clean.isBlank()) return
        editStations { list -> list.map { if (it.slug == slug) it.copy(name = clean) else it } }
    }

    suspend fun delete(slug: String) {
        editStations { list -> list.filterNot { it.slug == slug } }
        context.playlistDataStore.edit { p ->
            val members = decodeMembers(p[KMembers]).toMutableMap()
            members.remove(slug)
            p[KMembers] = Http.json.encodeToString(members)
        }
    }

    suspend fun setCover(slug: String, cover: String) {
        editStations { list -> list.map { if (it.slug == slug) it.copy(cover = cover) else it } }
    }

    /** Adds a song; returns false if it was already present. */
    suspend fun addSong(slug: String, songId: String): Boolean {
        var added = false
        context.playlistDataStore.edit { p ->
            val members = decodeMembers(p[KMembers]).toMutableMap()
            val cur = members[slug].orEmpty()
            if (songId !in cur) { members[slug] = cur + songId; added = true }
            p[KMembers] = Http.json.encodeToString(members)
        }
        return added
    }

    suspend fun removeSong(slug: String, songId: String) {
        context.playlistDataStore.edit { p ->
            val members = decodeMembers(p[KMembers]).toMutableMap()
            members[slug] = members[slug].orEmpty().filterNot { it == songId }
            p[KMembers] = Http.json.encodeToString(members)
        }
    }

    /** Reorder in one shot; pass the full wanted order. */
    suspend fun setOrder(slug: String, songIds: List<String>) {
        context.playlistDataStore.edit { p ->
            val members = decodeMembers(p[KMembers]).toMutableMap()
            members[slug] = songIds
            p[KMembers] = Http.json.encodeToString(members)
        }
    }

    /** Resolved, playable songs for a playlist against the current library. */
    fun songsOf(playlist: Playlist, library: List<Station>): List<Station> {
        val byId = library.associateBy { it.id }
        return playlist.songIds.mapNotNull(byId::get)
    }

    private fun decodeMembers(raw: String?): Map<String, List<String>> =
        raw?.let { runCatching { Http.json.decodeFromString<Map<String, List<String>>>(it) }.getOrNull() }
            ?: emptyMap()

    private suspend fun editStations(update: (List<Station>) -> List<Station>) {
        context.playlistDataStore.edit { p ->
            val cur = p[KPlaylists]?.let {
                runCatching { Http.json.decodeFromString<List<Station>>(it) }.getOrNull()
            } ?: emptyList()
            p[KPlaylists] = Http.json.encodeToString(update(cur))
        }
    }
}