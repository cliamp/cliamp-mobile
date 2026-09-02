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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import stream.cliamp.mobile.data.Station
import stream.cliamp.mobile.playback.PlayerConnection
import stream.cliamp.mobile.ui.components.CliampIcons
import stream.cliamp.mobile.ui.components.Gutter
import stream.cliamp.mobile.ui.components.ListRow
import stream.cliamp.mobile.ui.components.ScreenHeader
import stream.cliamp.mobile.ui.components.SectionLabel
import stream.cliamp.mobile.ui.theme.CliampType
import stream.cliamp.mobile.ui.theme.LocalPalette
import stream.cliamp.mobile.ui.theme.Mono

/** The always-available queue panel: just up-next, with reorder / remove. */
@UnstableApi
@Composable
fun QueueScreen(
    player: PlayerConnection,
    current: Station?,
    playing: Boolean,
    onPlay: (Station, List<Station>) -> Unit,
    onOpenPlayer: () -> Unit,
    onBack: () -> Unit,
) {
    val p = LocalPalette.current
    val queue by player.queue.collectAsState(initial = emptyList())

    Column(Modifier.fillMaxSize().background(p.ground)) {
        ScreenHeader {
            Row(
                Modifier.fillMaxWidth().padding(start = Gutter, end = Gutter, top = 8.dp, bottom = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Mono("‹ queue", CliampType.screenTitle, p.ink, Modifier.clickable { onBack() })
            }
        }

        LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
            if (queue.isEmpty()) {
                item {
                    Box(Modifier.fillMaxWidth().padding(horizontal = Gutter, vertical = 28.dp)) {
                        Mono(
                            "nothing queued — play a station and its list follows it here",
                            CliampType.rowSecondary, p.inkFaint,
                        )
                    }
                }
            }

            item {
                if (queue.isNotEmpty()) {
                    SectionLabel("in the list — ${queue.size}")
                }
            }

            itemsIndexed(queue, key = { _, s -> s.url }) { idx, s ->
                val active = current?.url == s.url
                ListRow(
                    onClick = { onPlay(s, queue); onOpenPlayer() },
                    verticalPadding = 11.dp,
                    leading = {
                        Box(
                            Modifier.size(28.dp).clip(RoundedCornerShape(4.dp))
                                .then(
                                    if (active) Modifier.background(p.accent)
                                    else Modifier.border(1.dp, p.chipBorder, RoundedCornerShape(4.dp))
                                ),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (active && playing) {
                                Icon(CliampIcons.Pause, null, Modifier.size(9.dp), tint = p.onAccent)
                            } else {
                                Mono(
                                    "%02d".format((idx + 1).coerceAtMost(99)),
                                    CliampType.meta,
                                    if (active) p.onAccent else p.inkFaint,
                                )
                            }
                        }
                    },
                    trailing = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            SquareGlyph("^") {
                                if (idx > 0) player.reorderQueue(from = idx, to = idx - 1)
                            }
                            SquareGlyph("v") {
                                if (idx < queue.lastIndex) player.reorderQueue(from = idx, to = idx + 1)
                            }
                            SquareGlyph("×") {
                                player.removeFromQueue(idx)
                            }
                        }
                    },
                ) {
                    Mono(
                        s.name,
                        if (active) CliampType.rowPrimaryMedium else CliampType.rowPrimary,
                        if (active) p.accent else p.ink,
                        maxLines = 1,
                    )
                    Mono(
                        if (active && playing) "playing" else s.meta.ifBlank { "live stream" },
                        CliampType.rowSecondary,
                        if (active && playing) p.accent else p.inkTertiary,
                        maxLines = 1,
                    )
                }
            }
            item { Spacer(Modifier.height(20.dp)) }
        }
    }
}

@Composable
private fun SquareGlyph(
    label: String,
    onClick: () -> Unit,
) {
    val p = LocalPalette.current
    Box(
        Modifier
            .size(28.dp)
            .clip(RoundedCornerShape(4.dp))
            .border(1.dp, p.keyBorder, RoundedCornerShape(4.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Mono(label, CliampType.tabLabel, p.ink)
    }
}