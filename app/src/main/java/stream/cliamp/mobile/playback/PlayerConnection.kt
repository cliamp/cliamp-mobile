package stream.cliamp.mobile.playback

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import stream.cliamp.mobile.data.Station
import stream.cliamp.mobile.data.StationSource

/**
 * The UI's handle on playback. Transport goes through a MediaController rather
 * than straight to the ExoPlayer, so the app, the notification and any
 * Bluetooth remote all drive the same state machine.
 */
@UnstableApi
class PlayerConnection(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    private var controller: MediaController? = null

    private val _state = MutableStateFlow(PlayerState())
    val state: StateFlow<PlayerState> = _state.asStateFlow()

    private val _queue = MutableStateFlow<List<Station>>(emptyList())
    private val _queueIndex = MutableStateFlow(-1)

    /** The list prev/next walks. Set whenever the user plays from a list. */
    val queue: StateFlow<List<Station>> = _queue.asStateFlow()

    /** Index of the currently-playing station in [queue], or -1. */
    val queueIndex: StateFlow<Int> = _queueIndex.asStateFlow()

    val currentQueue: List<Station> get() = _queue.value

    /** Called once the controller is live, if the user asked for auto-resume. */
    var onReady: (() -> Unit)? = null

    fun connect() {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            val c = runCatching { future.get() }.getOrNull() ?: return@addListener
            controller = c
            c.addListener(object : Player.Listener {
                override fun onEvents(player: Player, events: Player.Events) = sync()
            })
            sync()
            onReady?.invoke()
        }, MoreExecutors.directExecutor())

        scope.launch {
            while (true) {
                delay(500)
                sync()
            }
        }
    }

    private fun sync() {
        val c = controller ?: return
        val qi = _queueIndex.value
        _state.value = PlayerState(
            playing = c.isPlaying,
            buffering = c.playbackState == Player.STATE_BUFFERING,
            idle = c.playbackState == Player.STATE_IDLE && c.mediaItemCount == 0,
            positionMs = c.currentPosition.coerceAtLeast(0),
            bufferedMs = (c.bufferedPosition - c.currentPosition).coerceAtLeast(0),
            volume = c.volume,
            hasPrev = qi > 0,
            hasNext = qi >= 0 && qi < _queue.value.lastIndex,
        )
    }

    fun play(station: Station, from: List<Station> = emptyList()) {
        var q = _queue.value
        if (from.isNotEmpty()) {
            _queue.value = from
            q = from
            _queueIndex.value = from.indexOfFirst { it.url == station.url }
        } else if (q.none { it.url == station.url }) {
            _queue.value = listOf(station)
            q = listOf(station)
            _queueIndex.value = 0
        } else {
            _queueIndex.value = q.indexOfFirst { it.url == station.url }
        }
        val queue = q

        PlaybackBus.publishStation(station)
        PlaybackBus.publishError(null)
        PlaybackBus.publishFormat(StreamFormat())

        scope.launch {
            val c = controller ?: return@launch
            // A list of local files is a real playlist: Media3 should play one
            // after another. Radio lists are only for prev/next stepping, so we
            // never auto-advance a mixed/stream source.
            val playlist = queue.takeIf { it.all { s -> s.source == StationSource.Local } && it.size > 1 }
            if (playlist != null) {
                val items = playlist.map { s ->
                    PlaybackService.mediaItem(context, s, StreamResolver.resolve(s.url))
                }
                c.setMediaItems(items, _queueIndex.value.coerceIn(0, items.lastIndex), 0L)
            } else {
                c.setMediaItem(PlaybackService.mediaItem(context, station, StreamResolver.resolve(station.url)))
            }
            c.prepare()
            c.play()
            sync()
        }
    }

    fun toggle() {
        val c = controller ?: return
        if (c.isPlaying) c.pause()
        else {
            if (c.mediaItemCount == 0) {
                PlaybackBus.station.value?.let { play(it) }
            } else {
                // a stalled live stream has to be re-primed, not resumed
                c.prepare()
                c.play()
            }
        }
        sync()
    }

    fun stop() {
        controller?.stop()
        controller?.clearMediaItems()
        PlaybackBus.publishStreamTitle("")
        sync()
    }

    fun next() = step(+1)
    fun prev() = step(-1)

    private fun step(delta: Int) {
        val q = _queue.value
        if (q.isEmpty()) return
        val i = (_queueIndex.value + delta).coerceIn(0, q.lastIndex)
        if (i == _queueIndex.value) return
        play(q[i], q)
    }

    /** Insert [station] into the queue without replacing it. */
    fun addToQueue(station: Station, at: Int = Int.MAX_VALUE) {
        val q = _queue.value.toMutableList()
        val qi = _queueIndex.value
        val pos = if (at == Int.MAX_VALUE) q.size else at.coerceIn(0, q.size)
        val insertBefore = pos <= qi
        q.add(pos, station)
        _queue.value = q
        if (insertBefore) _queueIndex.value = qi + 1
        sync()
    }

    /** Drop the station at [index], keeping the playing item stable. */
    fun removeFromQueue(index: Int) {
        val q = _queue.value
        if (index !in q.indices) return
        val qi = _queueIndex.value
        val newQ = q.filterIndexed { i, _ -> i != index }
        _queue.value = newQ
        _queueIndex.value = when {
            index < qi -> (qi - 1).coerceAtLeast(-1)
            index == qi && newQ.isEmpty() -> -1
            index == qi -> qi
            else -> qi
        }
        sync()
    }

    /** Move the station at [from] to [to], keeping the playing item stable. */
    fun reorderQueue(from: Int, to: Int) {
        val q = _queue.value
        if (from !in q.indices || to !in q.indices || from == to) return
        val qi = _queueIndex.value
        val item = q[from]
        val moved = q.toMutableList().apply {
            removeAt(from)
            add(to, item)
        }
        _queue.value = moved
        // the playing station follows its item through the move
        _queueIndex.value = moved.indexOfFirst { it.url == item.url }.let { if (qi == from) it else qi }
        sync()
    }

    fun clearQueue() {
        if (_queue.value.isEmpty()) return
        _queue.value = emptyList()
        _queueIndex.value = -1
        sync()
    }

    fun setVolume(v: Float) {
        controller?.volume = v.coerceIn(0f, 1f)
        sync()
    }

    fun release() {
        controller?.release()
        controller = null
    }

    @Suppress("unused")
    private fun currentItem(): MediaItem? = controller?.currentMediaItem
}

data class PlayerState(
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val idle: Boolean = true,
    val positionMs: Long = 0,
    val bufferedMs: Long = 0,
    val volume: Float = 1f,
    val hasPrev: Boolean = false,
    val hasNext: Boolean = false,
)
