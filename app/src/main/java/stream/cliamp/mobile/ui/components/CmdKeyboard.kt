package stream.cliamp.mobile.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import stream.cliamp.mobile.ui.theme.CliampType
import stream.cliamp.mobile.ui.theme.LocalHapticsEnabled
import stream.cliamp.mobile.ui.theme.LocalPalette
import stream.cliamp.mobile.ui.theme.Mono

/** Which layout the shared keyboard uses. */
enum class CmdKeyboardMode {
    /** Plain text entry: letters + shift + backspace + space + enter. */
    Text,

    /** The command console: adds `:cmd`, `-` and a filled `RUN ⏎`. */
    Cmd,
}

/** The three letter rows shared by both keyboard modes. */
private val rows = listOf(
    "qwertyuiop".toList(),
    "asdfghjkl".toList(),
    "zxcvbnm".toList(),
)

/** The number row at the top of the keyboard. */
private val numberRow = "1234567890".toList()

/**
 * The custom CMD-style keyboard, always shown inline. Renders a number row,
 * the letter rows plus a shift/backspace row and a bottom row whose keys
 * depend on [mode]. Drives the caller through plain string callbacks.
 */
@Composable
fun CmdKeyboard(
    shift: Boolean,
    onKey: (String) -> Unit,
    onShift: () -> Unit,
    onBackspace: () -> Unit,
    onReturn: () -> Unit,
    onColon: (() -> Unit)? = null,
    mode: CmdKeyboardMode = CmdKeyboardMode.Cmd,
    modifier: Modifier = Modifier,
) {
    val p = LocalPalette.current
    Column(
        modifier
            .fillMaxWidth()
            .background(if (p.dark) p.panel else p.panel)
            .padding(horizontal = 6.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            numberRow.forEach { c ->
                Cap(c.toString(), Modifier.weight(1f), onClick = { onKey(c.toString()) })
            }
        }
        rows.forEachIndexed { i, row ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                if (i == 2) {
                    Cap("⇧", Modifier.weight(1.4f), active = shift, onClick = onShift)
                }
                row.forEach { c ->
                    Cap(
                        if (shift) c.uppercase() else c.toString(),
                        Modifier.weight(1f),
                        onClick = { onKey(c.toString()) },
                    )
                }
                if (i == 2) {
                    Cap("⌫", Modifier.weight(1.4f), onClick = onBackspace)
                }
            }
        }
        when (mode) {
            CmdKeyboardMode.Text -> Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Cap("space", Modifier.weight(3f), onClick = { onKey(" ") })
                Cap("⏎", Modifier.weight(2f), filled = true, onClick = onReturn)
            }

            CmdKeyboardMode.Cmd -> Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                if (onColon != null) Cap(":cmd", Modifier.weight(1.6f), onClick = onColon)
                Cap("space", Modifier.weight(3f), onClick = { onKey(" ") })
                Cap("-", Modifier.weight(1f), onClick = { onKey("-") })
                Cap("RUN ⏎", Modifier.weight(2f), filled = true, onClick = onReturn)
            }
        }
        Spacer(Modifier.height(6.dp))
    }
}

@Composable
private fun Cap(
    label: String,
    modifier: Modifier = Modifier,
    filled: Boolean = false,
    active: Boolean = false,
    onClick: () -> Unit,
) {
    val p = LocalPalette.current
    val hf = LocalHapticFeedback.current
    val hapticsEnabled = LocalHapticsEnabled.current
    val face = when {
        filled && p.dark -> p.accent
        filled -> p.ink
        active -> p.accentWash
        p.dark -> p.keyFace
        else -> p.ground
    }
    val fg = when {
        filled && p.dark -> p.onAccent
        filled -> p.ground
        active -> p.accent
        else -> p.ink
    }
    Box(
        modifier
            .height(42.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(face)
            .then(if (!filled) Modifier.border(1.dp, p.keyBorder, RoundedCornerShape(6.dp)) else Modifier)
            .clickable {
                if (hapticsEnabled) hf.performHapticFeedback(HapticFeedbackType.VirtualKey)
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Mono(label, CliampType.keyCap, fg, maxLines = 1)
    }
}

/** The animated accent block used as a text cursor, same as the CMD bar. */
@Composable
fun CmdCursor() {
    val p = LocalPalette.current
    val t = rememberInfiniteTransition(label = "cmdCursor")
    val a by t.animateFloat(
        initialValue = 1f, targetValue = 0f,
        animationSpec = infiniteRepeatable(tween(560), RepeatMode.Reverse),
        label = "cmdCursorAlpha",
    )
    Box(
        Modifier
            .padding(start = 2.dp)
            .size(width = 10.dp, height = 18.dp)
            .alpha(if (a > 0.5f) 1f else 0f)
            .background(p.accent)
    )
}