package stream.cliamp.mobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.media3.common.util.UnstableApi
import kotlin.math.roundToInt
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

/** The always-available queue panel: just up-next, with drag-to-reorder / remove. */
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
    val listState = rememberLazyListState()

    // Drag-reorder state: url of the item being dragged, its accumulated pixel
    // offset and the row height used as the threshold for sliding across items.
    var draggingUrl by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableStateOf(0f) }
    var rowHeight by remember { mutableIntStateOf(1) }

    fun liveIndex(url: String): Int = queue.indexOfFirst { it.url == url }

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

        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = listState) {
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
                    SectionLabel("in the list — ${queue.size} — hold a row & drag to reorder")
                }
            }

            itemsIndexed(queue, key = { _, s -> s.url }) { idx, s ->
                val active = current?.url == s.url
                val isDragging = draggingUrl == s.url

                ListRow(
                    modifier = Modifier
                        .zIndex(if (isDragging) 1f else 0f)
                        .graphicsLayer {
                            if (isDragging) {
                                scaleX = 1.02f
                                scaleY = 1.02f
                                shadowElevation = 8.dp.toPx()
                            }
                        }
                        .offset { IntOffset(0, if (isDragging) dragOffset.roundToInt() else 0) }
                        .pointerInput(s.url) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    draggingUrl = s.url
                                    rowHeight = size.height
                                    dragOffset = 0f
                                },
                                onDrag = { change, dragAmount ->
                                    change.consume()
                                    dragOffset += dragAmount.y
                                    val crossed = (dragOffset / rowHeight).toInt()
                                    if (crossed != 0) {
                                        dragOffset -= crossed * rowHeight
                                        val from = liveIndex(s.url)
                                        val to = (from + crossed).coerceIn(0, queue.lastIndex)
                                        if (to != from) player.reorderQueue(from = from, to = to)
                                    }
                                },
                                onDragEnd = { draggingUrl = null; dragOffset = 0f },
                                onDragCancel = { draggingUrl = null; dragOffset = 0f },
                            )
                        },
                    onClick = { if (!isDragging) { onPlay(s, queue); onOpenPlayer() } },
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
                        SquareGlyph("×") {
                            if (!isDragging) player.removeFromQueue(idx)
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