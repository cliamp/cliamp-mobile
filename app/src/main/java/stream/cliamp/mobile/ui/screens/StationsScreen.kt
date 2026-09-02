package stream.cliamp.mobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import stream.cliamp.mobile.data.DirectoryQuery
import stream.cliamp.mobile.data.Prefs
import stream.cliamp.mobile.data.Repository
import stream.cliamp.mobile.data.Station
import stream.cliamp.mobile.data.StationSource
import stream.cliamp.mobile.ui.components.Chip
import stream.cliamp.mobile.ui.components.CliampIcons
import stream.cliamp.mobile.ui.components.Gutter
import stream.cliamp.mobile.ui.components.HairlineDivider
import stream.cliamp.mobile.ui.components.ListRow
import stream.cliamp.mobile.ui.components.ScreenHeader
import stream.cliamp.mobile.ui.components.SectionLabel
import stream.cliamp.mobile.ui.theme.CliampType
import stream.cliamp.mobile.ui.theme.LocalPalette
import stream.cliamp.mobile.ui.theme.Mono

private enum class Source(val label: String) {
    All("all"), Cliamp("cliamp"), Directory("directory"), Favs("favs")
}

@Composable
fun StationsScreen(
    repository: Repository,
    prefs: Prefs,
    current: Station?,
    playing: Boolean,
    favorites: List<Station>,
    onPlay: (Station, List<Station>) -> Unit,
    onToggleFavorite: (Station) -> Unit,
    onOpenStats: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenPlayer: () -> Unit,
) {
    val p = LocalPalette.current
    var source by remember { mutableStateOf(Source.All) }

    // The LIB tab's favourites row shows radio stations only — local songs
    // live in their own smart playlists on the PLAYLISTS tab.
    val radioFavorites = favorites.filterNot { it.source == StationSource.Local }

    val cliamp by repository.cliamp.collectAsState()
    val stats by repository.stats.collectAsState()
    val directory by repository.directory.collectAsState()
    val dirStats by repository.directoryStats.collectAsState()
    val tags by repository.tags.collectAsState()

    val listState = rememberLazyListState()
    val nearEnd by remember {
        derivedStateOf {
            val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            last >= listState.layoutInfo.totalItemsCount - 8
        }
    }
    LaunchedEffect(nearEnd, directory.stations.size) {
        if (nearEnd && source != Source.Cliamp && source != Source.Favs) repository.nextPage()
    }

    Column(Modifier.fillMaxSize().background(p.ground)) {
        ScreenHeader {
            Row(
                Modifier.fillMaxWidth().padding(start = Gutter, end = Gutter, top = 8.dp, bottom = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Mono("Stations", CliampType.screenTitle, p.ink)
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        CliampIcons.MeterSmall, "cliamp radio stats",
                        Modifier.size(16.dp).clickable(onClick = onOpenStats),
                        tint = p.amber,
                    )
                    Icon(
                        CliampIcons.ListShort, "settings",
                        Modifier.size(16.dp).clickable(onClick = onOpenSettings),
                        tint = p.inkSecondary,
                    )
                }
            }
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                    .padding(start = Gutter, end = Gutter, top = 6.dp, bottom = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                Source.entries.forEach { s ->
                    Chip(s.label, source == s, onClick = { source = s })
                }
                Spacer(Modifier.width(4.dp))
                Chip(
                    "trending",
                    directory.query == DirectoryQuery.Trending,
                    onClick = { repository.loadDirectory(DirectoryQuery.Trending, reset = true) },
                )
                Chip(
                    "top voted",
                    directory.query == DirectoryQuery.TopVoted,
                    onClick = { repository.loadDirectory(DirectoryQuery.TopVoted, reset = true) },
                )
            }
        }

        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState) {

            if (source == Source.Favs || source == Source.All) {
                if (radioFavorites.isNotEmpty()) {
                    item {
                        SectionLabel("favourites — ${radioFavorites.size}")
                    }
                    items(radioFavorites, key = { "fav:${it.url}" }) { s ->
                        StationRow(
                            station = s,
                            listeners = repository.listeners(s),
                            active = current?.url == s.url,
                            playing = playing && current?.url == s.url,
                            favorite = true,
                            onPlay = { onPlay(s, radioFavorites); onOpenPlayer() },
                            onToggleFavorite = { onToggleFavorite(s) },
                        )
                    }
                } else if (source == Source.Favs) {
                    item { EmptyNote("no favourites yet — star a station from any list") }
                }
            }

            if (source == Source.All || source == Source.Cliamp) {
                item {
                    SectionLabel("cliamp radio — ${cliamp.size}") {
                        Mono(
                            stats?.let { "${it.activeListeners} listening" } ?: "…",
                            CliampType.meta,
                            p.amber,
                        )
                    }
                }
                items(cliamp, key = { "cl:${it.url}" }) { s ->
                    StationRow(
                        station = s,
                        listeners = repository.listeners(s),
                        active = current?.url == s.url,
                        playing = playing && current?.url == s.url,
                        favorite = favorites.any { it.url == s.url },
                        onPlay = { onPlay(s, cliamp); onOpenPlayer() },
                        onToggleFavorite = { onToggleFavorite(s) },
                    )
                }
            }

            if (source == Source.All || source == Source.Directory) {
                item {
                    SectionLabel(
                        "directory — " + (dirStats?.playable?.let { "%,d".format(it) } ?: "loading")
                    ) {
                        Mono(directory.query.label, CliampType.meta, p.inkTertiary)
                    }
                }
                if (tags.isNotEmpty()) {
                    item {
                        Row(
                            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                                .padding(horizontal = Gutter, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(7.dp),
                        ) {
                            tags.take(24).forEach { t ->
                                val q = directory.query
                                Chip(
                                    t.name,
                                    selected = q is DirectoryQuery.Tag && q.tag == t.name,
                                    onClick = { repository.loadDirectory(DirectoryQuery.Tag(t.name), reset = true) },
                                )
                            }
                        }
                    }
                    item { Spacer(Modifier.height(6.dp)) }
                }
                items(directory.stations, key = { "dir:${it.url}" }) { s ->
                    StationRow(
                        station = s,
                        listeners = null,
                        active = current?.url == s.url,
                        playing = playing && current?.url == s.url,
                        favorite = favorites.any { it.url == s.url },
                        onPlay = { onPlay(s, directory.stations); onOpenPlayer() },
                        onToggleFavorite = { onToggleFavorite(s) },
                    )
                }
                item {
                    when {
                        directory.error != null -> EmptyNote("directory: ${directory.error}")
                        directory.loading -> EmptyNote("loading more…")
                        directory.exhausted -> EmptyNote("end of ${directory.query.label}")
                        else -> Spacer(Modifier.height(8.dp))
                    }
                }
            }

            item { Spacer(Modifier.height(20.dp)) }
        }
    }
}

@Composable
private fun StationRow(
    station: Station,
    listeners: Int?,
    active: Boolean,
    playing: Boolean,
    favorite: Boolean,
    onPlay: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    val p = LocalPalette.current
    ListRow(
        onClick = onPlay,
        verticalPadding = 11.dp,
        leading = {
            Box(
                Modifier
                    .size(28.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .then(
                        if (active) Modifier.background(p.accent)
                        else Modifier.border(1.dp, p.chipBorder, RoundedCornerShape(4.dp))
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (playing) CliampIcons.Pause else CliampIcons.PlayRow,
                    null,
                    Modifier.size(if (playing) 9.dp else 11.dp),
                    tint = if (active) p.onAccent else p.inkTertiary,
                )
            }
        },
        trailing = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (listeners != null) {
                    Mono("$listeners", CliampType.rowSecondary, if (listeners > 0) p.amber else p.inkFaint)
                } else if (station.votes > 0) {
                    Mono(compact(station.votes), CliampType.meta, p.inkFaint)
                }
                Icon(
                    if (favorite) CliampIcons.StarFilled else CliampIcons.Star,
                    "favourite",
                    Modifier.size(15.dp).clickable(onClick = onToggleFavorite),
                    tint = if (favorite) p.accent else p.inkFaint,
                )
            }
        },
    ) {
        Mono(
            station.name,
            if (active) CliampType.rowPrimaryMedium else CliampType.rowPrimary,
            if (active) p.accent else p.ink,
            maxLines = 1,
        )
        Mono(
            buildList {
                if (station.source == StationSource.Cliamp) add("cliamp radio")
                station.meta.takeIf { it.isNotBlank() }?.let { add(it) }
                station.tagList.take(2).forEach { add(it) }
            }.joinToString(" · "),
            CliampType.rowSecondary,
            p.inkTertiary,
            maxLines = 1,
        )
    }
}

@Composable
private fun EmptyNote(text: String) {
    val p = LocalPalette.current
    Column {
        Box(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 18.dp)) {
            Mono(text, CliampType.rowSecondary, p.inkFaint)
        }
        HairlineDivider()
    }
}

private fun compact(n: Int): String = when {
    n >= 1_000_000 -> "%.1fm".format(n / 1_000_000f)
    n >= 1_000 -> "%.1fk".format(n / 1_000f)
    else -> n.toString()
}
