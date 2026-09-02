package stream.cliamp.mobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.launch
import stream.cliamp.mobile.data.Prefs
import stream.cliamp.mobile.data.Repository
import stream.cliamp.mobile.data.Station
import stream.cliamp.mobile.data.StationArtSource
import stream.cliamp.mobile.data.StationSource
import stream.cliamp.mobile.playback.PlaybackBus
import stream.cliamp.mobile.playback.PlayerConnection
import stream.cliamp.mobile.ui.components.BrickMeter
import stream.cliamp.mobile.ui.components.CliampIcons
import stream.cliamp.mobile.ui.components.Gutter
import stream.cliamp.mobile.ui.components.MechKey
import stream.cliamp.mobile.ui.components.MeterSize
import stream.cliamp.mobile.ui.components.StreamingRule
import stream.cliamp.mobile.ui.components.StripedArt
import stream.cliamp.mobile.ui.components.ToggleKey
import stream.cliamp.mobile.ui.components.rememberMeter
import stream.cliamp.mobile.ui.theme.CliampType
import stream.cliamp.mobile.ui.theme.LocalPalette
import stream.cliamp.mobile.ui.theme.Mono

@UnstableApi
@Composable
fun NowPlayingScreen(
    repository: Repository,
    prefs: Prefs,
    player: PlayerConnection,
    onOpenScope: () -> Unit,
) {
    val p = LocalPalette.current
    val scope = rememberCoroutineScope()

    val state by player.state.collectAsState()
    val station by PlaybackBus.station.collectAsState()
    val streamTitle by PlaybackBus.streamTitle.collectAsState()
    val format by PlaybackBus.format.collectAsState()
    val error by PlaybackBus.error.collectAsState()
    val reconnect by PlaybackBus.reconnectAttempt.collectAsState()
    val stats by repository.stats.collectAsState()
    val favorites by prefs.favorites.collectAsState(initial = emptyList())
    val visualizer by prefs.visualizer.collectAsState(initial = "spectrum")

    val spectrumSource = PlaybackBus.spectrum.collectAsState()
    val isFav = station != null && favorites.any { it.url == station!!.url }
    val listeners = station?.let { s ->
        if (s.source == StationSource.Cliamp) stats?.stations?.get(s.slug)?.activeListeners else null
    }

    Column(Modifier.fillMaxSize().background(p.ground).statusBarsPadding()) {
        // The concept's art plate is `flex: 0 1 auto; max-height: 284px`, i.e.
        // it is the first thing to give way. Compose has no shrink factor, so
        // we measure the column and hand the plate whatever is left over -
        // otherwise the FAV row silently walks off the bottom of the frame.
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val reserved = 356.dp
            val artSide = minOf(maxWidth - Gutter * 2, (maxHeight - reserved)).coerceIn(96.dp, 284.dp)

        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = Gutter),
            verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
        ) {
            StationArt(
                station = station,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .size(artSide),
            )

            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(CliampIcons.PlayTiny, null, Modifier.size(width = 9.dp, height = 10.dp), tint = p.accent)
                    Mono(
                        when {
                            reconnect > 0 -> "RECONNECTING · $reconnect"
                            error != null -> "STREAM ERROR"
                            state.buffering -> "BUFFERING"
                            state.playing -> "ON AIR"
                            station != null -> "PAUSED"
                            else -> "NOTHING TUNED"
                        },
                        CliampType.nowPlayingLabel,
                        when {
                            reconnect > 0 -> p.amber
                            error != null -> p.destructiveInk
                            else -> p.accent
                        },
                    )
                }
                Mono(
                    station?.name ?: "pick a station",
                    CliampType.trackTitle,
                    p.ink,
                    maxLines = 2,
                )
                Mono(
                    streamTitle.ifBlank { error ?: station?.tagList?.take(3)?.joinToString(" · ").orEmpty() },
                    CliampType.rowPrimary,
                    if (error != null && streamTitle.isBlank()) p.destructiveInk else p.inkSecondary,
                    maxLines = 2,
                )
                Mono(
                    buildList {
                        station?.let { s ->
                            add(if (s.source == StationSource.Cliamp) "cliamp radio" else "directory")
                            if (s.country.isNotBlank() && s.source != StationSource.Cliamp) add(s.country.lowercase())
                            format.summary(s.meta).takeIf { it.isNotBlank() }?.let(::add)
                            if (s.votes > 0) add("${compact(s.votes)} votes")
                        }
                        listeners?.let { add("$it listening") }
                    }.joinToString(" · ").ifBlank { "12 cliamp channels · 50k+ directory" },
                    CliampType.body,
                    p.inkTertiary,
                    maxLines = 1,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
                val frame = rememberMeter(
                    columns = MeterSize.NowPlaying.columns,
                    live = state.playing,
                    spectrum = if (visualizer != "off") spectrumSource else null,
                )
                BrickMeter(
                    frame = frame,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(MeterSize.NowPlaying.height)
                        .clickable(onClick = onOpenScope),
                    brick = MeterSize.NowPlaying.brick,
                    gap = MeterSize.NowPlaying.gap,
                )

                StreamingRule(
                    label = when {
                        reconnect > 0 -> "reconnecting"
                        error != null -> "no signal"
                        state.buffering -> "buffering"
                        state.playing -> "streaming"
                        station != null -> "paused"
                        else -> "stopped"
                    },
                    color = when {
                        reconnect > 0 -> p.amber
                        error != null -> p.destructiveInk
                        else -> p.accent
                    },
                    dim = !state.playing && reconnect == 0,
                )
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Bottom,
                ) {
                    Mono(clock(state.positionMs), CliampType.rowSecondary, p.inkSecondary)
                    Mono(
                        if (state.playing) "${state.bufferedMs / 1000}s buffered"
                        else "tap the meter for scope · eq",
                        CliampType.meta,
                        p.inkFaint,
                        maxLines = 1,
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    MechKey(
                        onClick = { player.prev() },
                        modifier = Modifier.weight(1f),
                        enabled = state.hasPrev,
                    ) { Icon(CliampIcons.Prev, "previous station", Modifier.size(width = 21.dp, height = 17.dp)) }

                    MechKey(
                        onClick = { player.toggle() },
                        modifier = Modifier.weight(1.7f),
                        filled = true,
                    ) {
                        if (state.playing) {
                            Icon(CliampIcons.Pause, "pause", Modifier.size(width = 20.dp, height = 22.dp))
                        } else {
                            Icon(CliampIcons.PlayTab, "play", Modifier.size(22.dp))
                        }
                    }

                    MechKey(
                        onClick = { player.next() },
                        modifier = Modifier.weight(1f),
                        enabled = state.hasNext,
                    ) { Icon(CliampIcons.Next, "next station", Modifier.size(width = 21.dp, height = 17.dp)) }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    ToggleKey(
                        icon = CliampIcons.Shuffle,
                        label = "SHUF",
                        on = false,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            val pool = repository.directory.value.stations.ifEmpty { repository.cliamp.value }
                            pool.randomOrNull()?.let { s ->
                                player.play(s, pool)
                                repository.reportPlay(s)
                            }
                        },
                    )
                    ToggleKey(
                        icon = CliampIcons.MeterSmall,
                        label = "SCOPE",
                        on = false,
                        modifier = Modifier.weight(1f),
                        onClick = onOpenScope,
                    )
                    ToggleKey(
                        icon = if (isFav) CliampIcons.StarFilled else CliampIcons.Star,
                        label = "FAV",
                        on = isFav,
                        modifier = Modifier.weight(1f),
                        onClick = { station?.let { s -> scope.launch { prefs.toggleFavorite(s) } } },
                    )
                }
            }
        }
        }
        Spacer(Modifier.height(10.dp))
    }
}

/**
 * Art is never invented, but it is not always absent either. Directory stations
 * usually publish an og:image on their homepage, and that is the station's own
 * branding rather than something we made up, so it is shown when it exists and
 * the striped plate stands in when it does not.
 *
 * The logo is contained, not cropped: most og:images are 1200x630 wordmarks and
 * a square centre crop cuts them in half.
 */
@Composable
private fun StationArt(station: Station?, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    val context = LocalContext.current
    var art by remember(station?.id) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(station?.id) {
        art = null
        val s = station ?: return@LaunchedEffect
        art = if (s.source == StationSource.Local) {
            stream.cliamp.mobile.data.LocalArt.bitmapFor(s.cover, context.contentResolver)?.asImageBitmap()
        } else {
            StationArtSource.bitmapFor(s)?.asImageBitmap()
        }
    }
    val caption = when {
        station == null -> "[ no station tuned ]"
        station.source == StationSource.Local ->
            if (station.album.isNotBlank()) "[ ${station.album.lowercase()} · ${station.artist.lowercase()} ]"
            else "[ local file ]"
        station.source == StationSource.Cliamp -> "[ ${station.slug} · cliamp radio ]"
        station.countryCode.isNotBlank() -> "[ ${station.countryCode.lowercase()} · live stream ]"
        else -> "[ live stream ]"
    }
    val badge = station?.codec?.uppercase()?.takeIf { it.isNotBlank() }
        ?: station?.let { if (it.bitrate > 0) "${it.bitrate}K" else null }

    StripedArt(
        modifier = modifier,
        caption = if (art == null) caption else null,
        badge = badge,
    ) {
        art?.let { bmp ->
            Image(
                bitmap = bmp,
                contentDescription = station?.name,
                modifier = Modifier.fillMaxSize().padding(14.dp),
                contentScale = ContentScale.Fit,
            )
        }
        if (art == null && station?.source == StationSource.Cliamp) {
            Icon(
                CliampIcons.Mark,
                null,
                Modifier
                    .align(Alignment.Center)
                    .size(width = 132.dp, height = 110.dp),
                tint = p.accent.copy(alpha = 0.16f),
            )
        }
    }
}

private fun compact(n: Int): String = when {
    n >= 1_000_000 -> "%.1fm".format(n / 1_000_000f)
    n >= 1_000 -> "%.1fk".format(n / 1_000f)
    else -> n.toString()
}

private fun clock(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
