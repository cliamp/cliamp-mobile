package stream.cliamp.mobile.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import kotlinx.coroutines.launch
import stream.cliamp.mobile.data.LocalArt
import stream.cliamp.mobile.data.LocalLibrary
import stream.cliamp.mobile.data.PlaylistStore
import stream.cliamp.mobile.data.Station
import stream.cliamp.mobile.data.durationLabel
import stream.cliamp.mobile.ui.components.Chip
import stream.cliamp.mobile.ui.components.CliampIcons
import stream.cliamp.mobile.ui.components.Gutter
import stream.cliamp.mobile.ui.components.HairlineDivider
import stream.cliamp.mobile.ui.components.IconLabelButton
import stream.cliamp.mobile.ui.components.ListRow
import stream.cliamp.mobile.ui.components.ScreenHeader
import stream.cliamp.mobile.ui.components.SectionLabel
import stream.cliamp.mobile.ui.components.StripedArt
import stream.cliamp.mobile.ui.theme.CliampType
import stream.cliamp.mobile.ui.theme.LocalPalette
import stream.cliamp.mobile.ui.theme.Mono

private enum class LocalPane(val label: String) {
    Songs("all local songs"), Playlists("playlists")
}

/**
 * The LIB tab's local half. Reads the phone's audio library via [LocalLibrary]
 * and lets the user play any song (through the normal Station pipeline, so
 * queue/prev/next/artwork all just work) and build playlists with covers.
 */
@Composable
fun LocalScreen(
    localLibrary: LocalLibrary,
    playlists: PlaylistStore,
    current: Station?,
    playing: Boolean,
    favorites: List<Station>,
    onPlay: (Station, List<Station>) -> Unit,
    onToggleFavorite: (Station) -> Unit,
    onOpenPlayer: () -> Unit,
) {
    val p = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var pane by remember { mutableStateOf(LocalPane.Songs) }
    var query by remember { mutableStateOf("") }
    var openSlug by remember { mutableStateOf<String?>(null) }
    var creatingName by remember { mutableStateOf(false) }
    var renamingSlug by remember { mutableStateOf<String?>(null) }

    val songs by localLibrary.songs.collectAsState()
    val loading by localLibrary.loading.collectAsState()
    val libError by localLibrary.error.collectAsState()
    val allPlaylists by playlists.playlists.collectAsState(initial = emptyList())

    val audioPerm = if (Build.VERSION.SDK_INT >= 33)
        Manifest.permission.READ_MEDIA_AUDIO
    else Manifest.permission.READ_EXTERNAL_STORAGE
    var haveAudio by remember { mutableStateOf(checkAudio(context, audioPerm)) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { ok -> haveAudio = ok; if (ok) localLibrary.refresh() }

    val coverLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        openSlug?.let { slug ->
            val cover = uri?.toString().orEmpty()
            if (cover.isNotBlank()) scope.launch { playlists.setCover(slug, cover) }
        }
    }

    LaunchedEffect(haveAudio) {
        if (haveAudio) localLibrary.refresh()
    }

    val filtered = filterSongs(songs, query)
    val showing = allPlaylists.firstOrNull { it.station.slug == openSlug }
    val playAndOpen: (Station, List<Station>) -> Unit = { s, list -> onPlay(s, list); onOpenPlayer() }

    val canGoBack = showing != null || pane == LocalPane.Playlists
    BackHandler(enabled = canGoBack) {
        when {
            showing != null -> openSlug = null
            else -> pane = LocalPane.Songs
        }
    }

    Column(Modifier.fillMaxSize().background(p.ground)) {
        ScreenHeader {
            Row(
                Modifier.fillMaxWidth().padding(start = Gutter, end = Gutter, top = 8.dp, bottom = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Mono(if (showing != null) showing.station.name else "library", CliampType.screenTitle, p.ink, maxLines = 1)
            }
            if (showing != null) {
                // playlist detail sub-header
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(start = Gutter, end = Gutter, top = 8.dp, bottom = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    Chip("‹ back", selected = false, onClick = { openSlug = null })
                    Chip("add songs", selected = false, onClick = { pane = LocalPane.Songs })
                    Chip("set cover", selected = false, onClick = { coverLauncher.launch("image/*") })
                }
            } else {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(start = Gutter, end = Gutter, top = 8.dp, bottom = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    LocalPane.entries.forEach { e -> Chip(e.label, pane == e, onClick = { pane = e }) }
                }
            }
            Row(
                Modifier.fillMaxWidth().padding(start = Gutter, end = Gutter, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Mono("▸ ", CliampType.chip, p.inkTertiary)
                Mono(
                    if (query.isBlank()) "search songs, artists, albums" else query,
                    CliampType.rowPrimary,
                    if (query.isBlank()) p.inkFaint else p.ink,
                    maxLines = 1,
                )
            }
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                !haveAudio -> PermissionPrompt(onGrant = { permissionLauncher.launch(audioPerm) })
                loading && songs.isEmpty() -> CenterNote("reading the library…", p.inkFaint)
                libError != null && songs.isEmpty() -> CenterNote(libError!!, p.destructiveInk)
                showing != null -> PlaylistDetailShown(
                    playlist = showing,
                    songIds = showing.songIds,
                    songs = songs,
                    allSongs = filtered,
                    current = current,
                    playing = playing,
                    onPlay = playAndOpen,
                    onRemove = { id -> scope.launch { playlists.removeSong(showing.station.slug, id) } },
                    onAdd = { id -> scope.launch { playlists.addSong(showing.station.slug, id) } },
                    adding = pane == LocalPane.Songs,
                    doneAdding = { pane = LocalPane.Playlists },
                )
                pane == LocalPane.Songs -> SongList(
                    songs = filtered,
                    favorites = favorites,
                    current = current,
                    playing = playing,
                    onPlay = playAndOpen,
                    onToggleFavorite = onToggleFavorite,
                )
                pane == LocalPane.Playlists -> PlaylistList(
                    playlists = allPlaylists,
                    songs = songs,
                    creating = creatingName,
                    renamingSlug = renamingSlug,
                    onCreate = { name -> scope.launch { playlists.create(name) }; creatingName = false },
                    onBeginCreate = { creatingName = true },
                    onCancel = { creatingName = false; renamingSlug = null },
                    onRename = { slug, name ->
                        scope.launch { playlists.rename(slug, name) }
                        renamingSlug = null
                    },
                    onBeginRename = { renamingSlug = it },
                    onDelete = { slug ->
                        scope.launch { playlists.delete(slug) }
                        if (renamingSlug == slug) renamingSlug = null
                        if (openSlug == slug) openSlug = null
                    },
                    onAddSongs = { slug -> openSlug = slug; pane = LocalPane.Songs },
                    onOpen = { openSlug = it.station.slug },
                )
            }
        }
    }
}

private fun checkAudio(context: android.content.Context, perm: String): Boolean =
    context.checkSelfPermission(perm) == android.content.pm.PackageManager.PERMISSION_GRANTED

private fun filterSongs(songs: List<Station>, q: String): List<Station> {
    val needle = q.trim().lowercase()
    if (needle.isEmpty()) return songs
    return songs.filter { s ->
        s.name.lowercase().contains(needle) ||
            s.artist.lowercase().contains(needle) ||
            s.album.lowercase().contains(needle)
    }
}

@Composable
private fun CenterNote(text: String, color: androidx.compose.ui.graphics.Color) {
    val p = LocalPalette.current
    Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
        Mono(text, CliampType.rowSecondary, color)
    }
}

@Composable
private fun PermissionPrompt(onGrant: () -> Unit) {
    val p = LocalPalette.current
    Column(Modifier.fillMaxWidth().padding(Gutter)) {
        Spacer(Modifier.height(12.dp))
        Mono("this app needs to read your audio files to show them here.", CliampType.rowPrimary, p.ink)
        Spacer(Modifier.height(4.dp))
        Mono("nothing leaves the phone. no import, no upload, no sync.", CliampType.rowSecondary, p.inkTertiary)
        Spacer(Modifier.height(14.dp))
        IconLabelButton(CliampIcons.PlayRow, "grant access", onClick = onGrant)
        Spacer(Modifier.height(12.dp))
        HairlineDivider()
    }
}

@Composable
private fun SongList(
    songs: List<Station>,
    favorites: List<Station>,
    current: Station?,
    playing: Boolean,
    onPlay: (Station, List<Station>) -> Unit,
    onToggleFavorite: (Station) -> Unit,
) {
    val p = LocalPalette.current
    if (songs.isEmpty()) {
        CenterNote("no songs — tune the radio or drop files on the phone", p.inkFaint)
        return
    }
    LazyColumn(Modifier.fillMaxSize()) {
        item { SectionLabel("all music — ${songs.size}") }
        items(songs, key = { it.id }) { s ->
            SongRow(
                station = s,
                active = current?.url == s.url,
                playing = playing && current?.url == s.url,
                favorite = favorites.any { it.url == s.url },
                onPlay = { onPlay(s, songs) },
                onToggleFavorite = { onToggleFavorite(s) },
            )
        }
        item { Spacer(Modifier.height(20.dp)) }
    }
}

@Composable
private fun SongRow(
    station: Station,
    active: Boolean,
    playing: Boolean,
    favorite: Boolean,
    onPlay: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    val p = LocalPalette.current
    val context = LocalContext.current
    var art by remember(station.id) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(station.id, station.cover) {
        art = LocalArt.bitmapFor(station.cover, context.contentResolver)?.asImageBitmap()
    }
    ListRow(
        onClick = onPlay,
        verticalPadding = 9.dp,
        leading = {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(40.dp).clip(RoundedCornerShape(4.dp))
                        .then(if (art == null) Modifier.border(1.dp, p.chipBorder, RoundedCornerShape(4.dp)) else Modifier),
                    contentAlignment = Alignment.Center,
                ) {
                    if (art != null) {
                        Image(art!!, station.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    } else {
                        Box(Modifier.fillMaxSize().background(p.panel), contentAlignment = Alignment.Center) {
                            Icon(if (playing && active) CliampIcons.Pause else CliampIcons.PlayRow, null,
                                Modifier.size(12.dp), tint = p.inkTertiary)
                        }
                    }
                }
            }
        },
        trailing = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Mono(durationLabel(station.durationMs), CliampType.meta, p.inkFaint)
                Icon(
                    if (favorite) CliampIcons.StarFilled else CliampIcons.Star,
                    "favourite",
                    Modifier.size(15.dp).clickable(onClick = onToggleFavorite),
                    tint = if (favorite) p.accent else p.inkFaint,
                )
            }
        },
    ) {
        Mono(station.name, if (active) CliampType.rowPrimaryMedium else CliampType.rowPrimary,
            if (active) p.accent else p.ink, maxLines = 1)
        Mono(
            buildList {
                if (station.artist.isNotBlank()) add(station.artist)
                if (station.album.isNotBlank()) add(station.album)
            }.joinToString(" · ").ifBlank { durationLabel(station.durationMs) },
            CliampType.rowSecondary, p.inkTertiary, maxLines = 1,
        )
    }
}

@Composable
private fun PlaylistList(
    playlists: List<PlaylistStore.Playlist>,
    songs: List<Station>,
    creating: Boolean,
    renamingSlug: String?,
    onCreate: (String) -> Unit,
    onBeginCreate: () -> Unit,
    onCancel: () -> Unit,
    onRename: (String, String) -> Unit,
    onBeginRename: (String) -> Unit,
    onDelete: (String) -> Unit,
    onAddSongs: (String) -> Unit,
    onOpen: (PlaylistStore.Playlist) -> Unit,
) {
    val p = LocalPalette.current
    val context = LocalContext.current
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
            if (playlists.isEmpty() && !creating) {
                item {
                    CenterNote("no playlists yet — make one and add your songs", p.inkFaint)
                }
            } else if (playlists.isNotEmpty()) {
                item { SectionLabel("playlists — ${playlists.size}") }
            }
            if (creating) {
                item {
                    InlineNameField(
                        initial = "",
                        placeholder = "name this playlist",
                        onDone = onCreate,
                        onCancel = onCancel,
                    )
                }
            }
            items(playlists, key = { it.station.slug }) { pl ->
                if (pl.station.slug == renamingSlug) {
                    InlineNameField(
                        initial = pl.station.name,
                        placeholder = "rename playlist",
                        onDone = { onRename(pl.station.slug, it) },
                        onCancel = onCancel,
                    )
                } else {
                    PlaylistRow(
                        pl = pl,
                        songs = songs,
                        onOpen = onOpen,
                        onEdit = { onBeginRename(pl.station.slug) },
                        onDelete = { onDelete(pl.station.slug) },
                        onAddSongs = { onAddSongs(pl.station.slug) },
                        context = context,
                    )
                }
            }
            item { Spacer(Modifier.height(20.dp)) }
            item {
                if (!creating) {
                    NewPlaylistCard(onClick = onBeginCreate)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun PlaylistRow(
    pl: PlaylistStore.Playlist,
    songs: List<Station>,
    onOpen: (PlaylistStore.Playlist) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onAddSongs: () -> Unit,
    context: android.content.Context,
) {
    val p = LocalPalette.current
    val cover = pl.station.cover
    var art by remember(pl.station.slug) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(pl.station.slug, cover) {
        art = LocalArt.bitmapFor(cover, context.contentResolver)?.asImageBitmap()
    }
    ListRow(
        onClick = { onOpen(pl) },
        verticalPadding = 9.dp,
        leading = {
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(5.dp))
                    .then(if (art == null) Modifier.border(1.dp, p.chipBorder, RoundedCornerShape(5.dp)) else Modifier),
            ) {
                if (art != null) {
                    Image(art!!, pl.station.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                } else {
                    StripedArt(modifier = Modifier.fillMaxSize(), radius = 5.dp, caption = null)
                }
            }
        },
        trailing = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Mono("${pl.songIds.size} songs", CliampType.meta, p.inkFaint)
                PlaylistMenu(onAddSongs = onAddSongs, onEdit = onEdit, onDelete = onDelete)
                Icon(CliampIcons.CaretRight, "open", Modifier.size(11.dp), tint = p.inkTertiary)
            }
        },
    ) {
        Mono(pl.station.name, CliampType.rowPrimaryMedium, p.ink, maxLines = 1)
        Mono(
            pl.songIds.joinToString(" · ") { titleOf(it, songs) }.ifBlank { "empty playlist" },
            CliampType.rowSecondary, p.inkTertiary, maxLines = 1,
        )
    }
}

/** The ⋮ overflow menu on a playlist row: edit the name, or remove the playlist. */
@Composable
private fun PlaylistMenu(onAddSongs: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    val p = LocalPalette.current
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.size(36.dp).clip(RoundedCornerShape(5.dp)).clickable { open = true },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                CliampIcons.More, "menu",
                Modifier.size(17.dp),
                tint = p.inkTertiary,
            )
        }
        if (open) {
            Popup(
                onDismissRequest = { open = false },
                alignment = Alignment.TopEnd,
                offset = IntOffset(0, 8),
            ) {
                Column(
                    Modifier.width(170.dp).clip(RoundedCornerShape(6.dp))
                        .background(p.ground).border(1.dp, p.hairlineRegion, RoundedCornerShape(6.dp)),
                ) {
                    MenuItem("add songs", p.ink, onAddSongs) { open = false }
                    HairlineDivider(region = true)
                    MenuItem("edit name", p.ink, onEdit) { open = false }
                    HairlineDivider(region = true)
                    MenuItem("remove playlist", p.destructiveInk, onDelete) { open = false }
                }
            }
        }
    }
}

@Composable
private fun MenuItem(label: String, color: androidx.compose.ui.graphics.Color, action: () -> Unit, close: () -> Unit) {
    val p = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().clickable {
            close()
            action()
        }.padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Mono(label, CliampType.chip, color)
    }
}

/** A monospace, palette-styled input for naming playlists. */
@Composable
private fun InlineNameField(
    initial: String,
    placeholder: String,
    onDone: (String) -> Unit,
    onCancel: () -> Unit,
) {
    val p = LocalPalette.current
    var text by remember { mutableStateOf(initial) }
    val focusRequester = remember { FocusRequester() }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { focusRequester.requestFocus() }
    Row(
        Modifier.fillMaxWidth().padding(Gutter)
            .clip(RoundedCornerShape(6.dp)).border(1.dp, p.chipBorder, RoundedCornerShape(6.dp))
            .background(p.panel).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        BasicTextField(
            value = text,
            onValueChange = { text = it.take(48) },
            modifier = Modifier.weight(1f).focusRequester(focusRequester),
            textStyle = CliampType.rowPrimary.copy(color = p.ink),
            cursorBrush = SolidColor(p.accent),
            singleLine = true,
            decorationBox = { inner ->
                Box {
                    if (text.isEmpty()) Mono(placeholder, CliampType.rowPrimary, p.inkFaint)
                    inner()
                }
            },
        )
        Mono("SAVE", CliampType.tabLabel, p.accent,
            Modifier.clip(RoundedCornerShape(4.dp)).background(p.accent.copy(alpha = 0.14f))
                .clickable { onDone(text) }.padding(horizontal = 9.dp, vertical = 7.dp))
        Mono("CANCEL", CliampType.tabLabel, p.inkTertiary,
            Modifier.clip(RoundedCornerShape(4.dp)).border(1.dp, p.chipBorder, RoundedCornerShape(4.dp))
                .clickable(onClick = onCancel).padding(horizontal = 9.dp, vertical = 7.dp))
    }
}

@Composable
private fun NewPlaylistCard(onClick: () -> Unit) {
    val p = LocalPalette.current
    Box(
        Modifier.fillMaxWidth().padding(Gutter).clip(RoundedCornerShape(8.dp)).background(p.panel)
            .border(1.dp, p.hairlineRegion, RoundedCornerShape(8.dp)).clickable(onClick = onClick)
            .padding(15.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(CliampIcons.Plus, "new playlist", Modifier.size(14.dp), tint = p.accent)
            Mono("new playlist", CliampType.chip, p.accent)
        }
    }
}

private fun titleOf(id: String, songs: List<Station>): String =
    songs.firstOrNull { it.id == id }?.name ?: ""

@Composable
private fun PlaylistDetailShown(
    playlist: PlaylistStore.Playlist,
    songIds: List<String>,
    songs: List<Station>,
    allSongs: List<Station>,
    current: Station?,
    playing: Boolean,
    onPlay: (Station, List<Station>) -> Unit,
    onRemove: (String) -> Unit,
    onAdd: (String) -> Unit,
    adding: Boolean,
    doneAdding: () -> Unit,
) {
    val p = LocalPalette.current
    val members = playlist.songIds.mapNotNull { id -> songs.firstOrNull { it.id == id } }

    if (adding && allSongs.isNotEmpty()) {
        // add mode: show all songs with a check affordance
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 6.dp)) {
                    Mono(playlist.station.name, CliampType.chip, p.accent)
                    Spacer(Modifier.width(8.dp))
                    Mono("· tap to add", CliampType.meta, p.inkTertiary)
                }
            }
            items(allSongs, key = { it.id }) { s ->
                val inPl = s.id in songIds
                ListRow(
                    onClick = { if (inPl) onRemove(s.id) else onAdd(s.id) },
                    verticalPadding = 9.dp,
                    leading = {
                        Box(
                            Modifier.size(28.dp).clip(RoundedCornerShape(4.dp))
                                .then(if (inPl) Modifier.background(p.accent)
                                      else Modifier.border(1.dp, p.chipBorder, RoundedCornerShape(4.dp))),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (inPl) Icon(CliampIcons.Check, null, Modifier.size(11.dp), tint = p.onAccent)
                        }
                    },
                    trailing = { Icon(CliampIcons.Minus, "remove", Modifier.size(13.dp), if (inPl) p.accent else p.inkFaint) },
                ) {
                    Mono(s.name, CliampType.rowPrimary, p.ink, maxLines = 1)
                    Mono(if (s.artist.isNotBlank()) s.artist else s.meta, CliampType.rowSecondary, p.inkTertiary, maxLines = 1)
                }
            }
            item {
                Row(Modifier.fillMaxWidth().padding(Gutter).horizontalScroll(rememberScrollState())) {
                    Chip("done", selected = false, onClick = doneAdding)
                }
            }
            item { Spacer(Modifier.height(16.dp)) }
        }
        return
    }

    LazyColumn(Modifier.fillMaxSize()) {
        if (members.isEmpty()) {
            item {
                Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                    Mono("empty — tap add songs", CliampType.rowSecondary, p.inkFaint)
                }
            }
        } else {
            item { SectionLabel("songs — ${members.size}") }
            items(members, key = { it.id }) { s ->
                ListRow(
                    onClick = { onPlay(s, members) },
                    verticalPadding = 9.dp,
                    leading = {
                        Box(
                            Modifier.size(28.dp).clip(RoundedCornerShape(4.dp))
                                .then(if (current?.url == s.url) Modifier.background(p.accent)
                                      else Modifier.border(1.dp, p.chipBorder, RoundedCornerShape(4.dp))),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                if (current?.url == s.url && playing) CliampIcons.Pause else CliampIcons.PlayRow,
                                null,
                                Modifier.size(if (current?.url == s.url && playing) 9.dp else 11.dp),
                                tint = if (current?.url == s.url) p.onAccent else p.inkTertiary,
                            )
                        }
                    },
                    trailing = {
                        Mono("DROP", CliampType.tabLabel, p.destructiveInk,
                            Modifier.clip(RoundedCornerShape(4.dp)).clickable { onRemove(s.id) }
                                .padding(horizontal = 8.dp, vertical = 6.dp))
                    },
                ) {
                    Mono(s.name, CliampType.rowPrimary, if (current?.url == s.url) p.accent else p.ink, maxLines = 1)
                    Mono(
                        buildList {
                            if (s.artist.isNotBlank()) add(s.artist)
                            if (s.album.isNotBlank()) add(s.album)
                        }.joinToString(" · ").ifBlank { durationLabel(s.durationMs) },
                        CliampType.rowSecondary, p.inkTertiary, maxLines = 1,
                    )
                }
            }
        }
        item { Spacer(Modifier.height(20.dp)) }
    }
}