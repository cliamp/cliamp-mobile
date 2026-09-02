package stream.cliamp.mobile.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.launch
import stream.cliamp.mobile.data.Prefs
import stream.cliamp.mobile.data.LocalLibrary
import stream.cliamp.mobile.data.PlaylistStore
import stream.cliamp.mobile.data.Repository
import stream.cliamp.mobile.data.Station
import stream.cliamp.mobile.playback.PlaybackBus
import stream.cliamp.mobile.playback.PlayerConnection
import stream.cliamp.mobile.ui.components.CliampTabBar
import stream.cliamp.mobile.ui.components.Tab
import stream.cliamp.mobile.ui.screens.CommandScreen
import stream.cliamp.mobile.ui.screens.LocalScreen
import stream.cliamp.mobile.ui.screens.MiniPlayer
import stream.cliamp.mobile.ui.screens.NowPlayingScreen
import stream.cliamp.mobile.ui.screens.QueueScreen
import stream.cliamp.mobile.ui.screens.ScopeScreen
import stream.cliamp.mobile.ui.screens.SettingsScreen
import stream.cliamp.mobile.ui.screens.StationsScreen
import stream.cliamp.mobile.ui.screens.StatsScreen
import stream.cliamp.mobile.ui.theme.LocalPalette

/** Screens that stack on top of a tab rather than replacing it. */
private sealed interface Overlay {
    data object None : Overlay
    data object Scope : Overlay
    data object Stats : Overlay
    data object Settings : Overlay
}

/** Which half of the LIB tab is showing: the radio browse or the local library. */
private enum class LibPane(val label: String) { Radio("radio"), Local("local") }

@UnstableApi
@Composable
fun CliampRoot(
    repository: Repository,
    prefs: Prefs,
    player: PlayerConnection,
    localLibrary: LocalLibrary,
    playlists: PlaylistStore,
    dark: Boolean,
) {
    val p = LocalPalette.current
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(Tab.Lib) }
    var overlay by remember { mutableStateOf<Overlay>(Overlay.None) }
    var libPane by remember { mutableStateOf(LibPane.Local) }

    val playerState by player.state.collectAsState()
    val station by PlaybackBus.station.collectAsState()
    val streamTitle by PlaybackBus.streamTitle.collectAsState()
    val favorites by prefs.favorites.collectAsState(initial = emptyList())
    val reconnect by PlaybackBus.reconnectAttempt.collectAsState()

    val onPlay: (Station, List<Station>) -> Unit = { s, from ->
        player.play(s, from)
        repository.reportPlay(s)
    }

    BackHandler(enabled = overlay != Overlay.None || tab != Tab.Lib) {
        when {
            overlay != Overlay.None -> overlay = Overlay.None
            else -> tab = Tab.Lib
        }
    }

    Column(Modifier.fillMaxSize().background(p.ground)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (overlay) {
                Overlay.Scope -> ScopeScreen(
                    prefs = prefs,
                    station = station,
                    streamTitle = streamTitle,
                    playing = playerState.playing,
                    onBack = { overlay = Overlay.None },
                )
                Overlay.Stats -> StatsScreen(
                    repository = repository,
                    prefs = prefs,
                    onBack = { overlay = Overlay.None },
                    onPlay = { s -> onPlay(s, repository.cliamp.value) },
                )
                Overlay.Settings -> SettingsScreen(
                    prefs = prefs,
                    repository = repository,
                    onBack = { overlay = Overlay.None },
                )
                Overlay.None -> when (tab) {
                    Tab.Play -> NowPlayingScreen(
                        repository = repository,
                        prefs = prefs,
                        player = player,
                        onOpenScope = { overlay = Overlay.Scope },
                    )
                    Tab.Lib -> when (libPane) {
                        LibPane.Radio -> StationsScreen(
                            repository = repository,
                            prefs = prefs,
                            current = station,
                            playing = playerState.playing,
                            favorites = favorites,
                            onPlay = onPlay,
                            onToggleFavorite = { s -> scope.launch { prefs.toggleFavorite(s) } },
                            onOpenStats = { overlay = Overlay.Stats },
                            onOpenSettings = { overlay = Overlay.Settings },
                            onOpenPlayer = { tab = Tab.Play },
                            onSwitchPane = { libPane = LibPane.Local },
                        )
                        LibPane.Local -> LocalScreen(
                            localLibrary = localLibrary,
                            playlists = playlists,
                            current = station,
                            playing = playerState.playing,
                            favorites = favorites,
                            onPlay = onPlay,
                            onToggleFavorite = { s -> scope.launch { prefs.toggleFavorite(s) } },
                            onOpenPlayer = { tab = Tab.Play },
                            switchPane = { libPane = LibPane.Radio },
                        )
                    }
                    Tab.Queue -> QueueScreen(
                        prefs = prefs,
                        player = player,
                        current = station,
                        playing = playerState.playing,
                        onPlay = onPlay,
                        onOpenPlayer = { tab = Tab.Play },
                    )
                    Tab.Cmd -> CommandScreen(
                        repository = repository,
                        prefs = prefs,
                        onPlay = onPlay,
                        onOpenScope = { overlay = Overlay.Scope },
                        onOpenStats = { overlay = Overlay.Stats },
                        onOpenSettings = { overlay = Overlay.Settings },
                        onOpenPlayer = { tab = Tab.Play },
                    )
                }
            }
        }

        AnimatedVisibility(
            visible = overlay == Overlay.None && tab != Tab.Play && station != null,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            MiniPlayer(
                station = station,
                streamTitle = streamTitle,
                playing = playerState.playing,
                buffering = playerState.buffering,
                reconnecting = reconnect,
                onToggle = { player.toggle() },
                onOpen = { tab = Tab.Play },
            )
        }

        if (overlay == Overlay.None) {
            CliampTabBar(current = tab, onSelect = { tab = it })
        }
    }
}
