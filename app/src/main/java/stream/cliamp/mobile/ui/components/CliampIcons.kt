package stream.cliamp.mobile.ui.components

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * Hand-drawn geometry only: rectangles, triangles, straight paths. No rounded
 * caps, no gradients, no emoji. Every path below is copied out of the concept
 * SVGs so the shapes stay identical; colour comes from the Icon tint.
 */
private fun solid(w: Float, h: Float, vararg d: String): ImageVector =
    ImageVector.Builder(
        defaultWidth = w.dp, defaultHeight = h.dp,
        viewportWidth = w, viewportHeight = h,
    ).apply {
        d.forEach { addPath(addPathNodes(it), fill = SolidColor(Color.White)) }
    }.build()

private fun stroked(w: Float, h: Float, sw: Float, vararg d: String): ImageVector =
    ImageVector.Builder(
        defaultWidth = w.dp, defaultHeight = h.dp,
        viewportWidth = w, viewportHeight = h,
    ).apply {
        d.forEach {
            addPath(
                addPathNodes(it),
                stroke = SolidColor(Color.White),
                strokeLineWidth = sw,
                strokeLineCap = StrokeCap.Butt,
                strokeLineJoin = StrokeJoin.Miter,
            )
        }
    }.build()

private fun rect(x: Float, y: Float, w: Float, h: Float) = "M$x ${y}h${w}v${h}h${-w}z"

private fun rrect(x: Float, y: Float, w: Float, h: Float, r: Float): String = buildString {
    append("M${x + r} ${y}")
    append("h${w - 2 * r}a$r $r 0 0 1 $r ${r}")
    append("v${h - 2 * r}a$r $r 0 0 1 ${-r} ${r}")
    append("h${-(w - 2 * r)}a$r $r 0 0 1 ${-r} ${-r}")
    append("v${-(h - 2 * r)}a$r $r 0 0 1 $r ${-r}z")
}

private fun circle(cx: Float, cy: Float, r: Float): String =
    "M${cx - r} $cy" +
        "a$r $r 0 1 1 ${2 * r} 0" +
        "a$r $r 0 1 1 ${-2 * r} 0z"

object CliampIcons {

    /**
     * The cliamp mark: the eight-bar spectrum from Cliamp.svg. Tinted with the
     * accent in app chrome; [CliampLogoColours] keeps the brand colours for the
     * launcher icon and the about row, where the palette rules do not apply.
     */
    val Mark = solid(
        378.88f, 317.44f,
        "M0.0,122.88h20.48v71.68h-20.48z",
        "M51.2,71.68h20.48v174.08h-20.48z",
        "M102.4,20.48h20.48v276.48h-20.48z",
        "M153.6,92.16h20.48v133.12h-20.48z",
        "M204.8,0.0h20.48v317.44h-20.48z",
        "M256.0,81.92h20.48v153.6h-20.48z",
        "M307.2,40.96h20.48v235.52h-20.48z",
        "M358.4,112.64h20.48v92.16h-20.48z",
    )

    /** Full-colour brand mark, same geometry, used sparingly. */
    val MarkColour: ImageVector = ImageVector.Builder(
        defaultWidth = 378.88f.dp, defaultHeight = 317.44f.dp,
        viewportWidth = 378.88f, viewportHeight = 317.44f,
    ).apply {
        listOf(
            Color(0xFF00FF41) to "M0.0,122.88h20.48v71.68h-20.48z",
            Color(0xFFFFE000) to "M51.2,71.68h20.48v174.08h-20.48z",
            Color(0xFFFF9500) to "M102.4,20.48h20.48v276.48h-20.48z",
            Color(0xFF00FF41) to "M153.6,92.16h20.48v133.12h-20.48z",
            Color(0xFFFF3B1F) to "M204.8,0.0h20.48v317.44h-20.48z",
            Color(0xFF00FF41) to "M256.0,81.92h20.48v153.6h-20.48z",
            Color(0xFFFF9500) to "M307.2,40.96h20.48v235.52h-20.48z",
            Color(0xFF00FF41) to "M358.4,112.64h20.48v92.16h-20.48z",
        ).forEach { (c, d) -> addPath(addPathNodes(d), fill = SolidColor(c)) }
    }.build()

    val PlayTiny = solid(9f, 10f, "M0 0l9 5-9 5z")
    val PlayRow = solid(14f, 14f, "M1 1l12 6-12 6z")
    val PlayTab = solid(18f, 18f, "M2 1l14 8-14 8z")
    val PlayWide = solid(12f, 13f, "M0 0l12 6.5L0 13z")

    val Prev = solid(22f, 18f, "M12 9L22 1v16z", "M2 9L12 1v16z", rect(0f, 1f, 2.4f, 16f))
    val Next = solid(22f, 18f, "M10 9L0 17V1z", "M20 9L10 17V1z", rect(19.6f, 1f, 2.4f, 16f))
    val Pause = solid(20f, 22f, rrect(1f, 0f, 6.5f, 22f, 1f), rrect(12.5f, 0f, 6.5f, 22f, 1f))
    val Stop = solid(20f, 20f, rect(1f, 1f, 18f, 18f))

    val Shuffle = stroked(18f, 14f, 1.8f, "M1 3h4l8 8h4", "M1 11h4l8-8h4")
    val Repeat = stroked(18f, 14f, 1.8f, "M2 5V3h14v8H4", "M6 8l-3 3 3 3")
    val Star = stroked(16f, 16f, 1.8f, "M8 1.5l1.9 4.2 4.6.5-3.4 3.1.9 4.5L8 11.6 4 13.8l.9-4.5L1.5 6.2l4.6-.5z")
    val StarFilled = solid(16f, 16f, "M8 1.5l1.9 4.2 4.6.5-3.4 3.1.9 4.5L8 11.6 4 13.8l.9-4.5L1.5 6.2l4.6-.5z")

    val LibTab = stroked(18f, 18f, 1.7f, rect(1f, 1f, 5f, 16f), rect(8f, 1f, 5f, 16f), "M15 2l2 15")
    /**
     * A vinyl disc: outer groove ring, a sliver of the label, and the centre
     * hole. Reads as "music library" at tab size and stays distinct from the
     * queue's line-list and LIB's book-stack.
     */
    val PlaylistsTab = ImageVector.Builder(
        defaultWidth = 18.dp, defaultHeight = 18.dp, viewportWidth = 18f, viewportHeight = 18f,
    ).apply {
        val groove = addPathNodes("M9 2a7 7 0 1 1 -0.001 0")
        addPath(groove, stroke = SolidColor(Color.White), strokeLineWidth = 1.6f)
        // label ring inside the grooves
        addPath(addPathNodes("M9 5a4 4 0 1 1 -0.001 0"), fill = SolidColor(Color.White))
        // centre hole
        val hole = addPathNodes("M9 7.2a1.8 1.8 0 1 1 -0.001 0")
        addPath(hole, fill = SolidColor(Color.White))
        addPath(hole, stroke = SolidColor(Color(0xFF000000)), strokeLineWidth = 1f)
    }.build()
    val QueueTabLines = stroked(18f, 18f, 1.7f, "M1 4h16M1 9h11M1 14h11")
    val QueueTabArrow = solid(18f, 18f, "M15 11l3 2-3 2z")
    val CmdTab = stroked(18f, 18f, 1.7f, rrect(0.9f, 1.9f, 16.2f, 14.2f, 2f), "M4.5 7l2.2 2.2L4.5 11.4M8.6 11.8h5")
    val CmdSmall = stroked(18f, 18f, 1.7f, rrect(0.9f, 1.9f, 16.2f, 14.2f, 2f), "M4.5 7l2.2 2.2L4.5 11.4")

    val Search = stroked(16f, 16f, 1.8f, "M6.6 1.5a5.1 5.1 0 100 10.2 5.1 5.1 0 100-10.2z", "M10.4 10.4L15 15")
    val Plus = solid(14f, 14f, rect(6f, 0f, 2f, 14f), rect(0f, 6f, 14f, 2f))
    val Minus = solid(12f, 12f, rect(0f, 5f, 12f, 2f))
    val Check = stroked(13f, 13f, 2.2f, "M1.5 7l3.2 3.2L11.5 3")
    val Xmark = stroked(12f, 12f, 1.8f, "M2 2l8 8M10 2l-8 8")
    val CaretDown = solid(10f, 10f, "M0 2h10L5 8z")
    val CaretRight = solid(10f, 10f, "M2 0v10l6-5z")
    val Download = stroked(16f, 16f, 1.6f, "M8 1v9", "M4.5 6.5L8 10l3.5-3.5", "M1.5 13.5h13")
    /** Vertical ellipsis: row overflow menu. */
    val More = solid(16f, 16f, circle(8f, 3f, 2.2f), circle(8f, 8f, 2.2f), circle(8f, 13f, 2.2f))
    val Lines = solid(16f, 14f, rect(0f, 0f, 16f, 2f), rect(0f, 6f, 16f, 2f), rect(0f, 12f, 16f, 2f))
    val ListShort = stroked(16f, 16f, 1.7f, "M1 3h14M1 8h9M1 13h9")
    val MeterSmall = solid(
        14f, 14f,
        rect(0f, 9f, 2.4f, 5f), rect(3.9f, 5f, 2.4f, 9f),
        rect(7.8f, 1f, 2.4f, 13f), rect(11.6f, 6f, 2.4f, 8f),
    )
    val Speaker = stroked(20f, 20f, 1.7f, "M2 7l5-4v14l-5-4z", "M11 6.5a4 4 0 010 7")
    val SpeakerSolid = solid(20f, 20f, "M2 7l5-4v14l-5-4z")
    val Clock = stroked(20f, 20f, 1.7f, "M10 1.8a8.2 8.2 0 100 16.4 8.2 8.2 0 100-16.4z", "M10 5.5v5l3.5 2")
    val Globe = stroked(20f, 20f, 1.6f, "M10 1.8a8.2 8.2 0 100 16.4 8.2 8.2 0 100-16.4z", "M1.8 10h16.4", "M10 1.8c4 4.4 4 11.9 0 16.4c-4-4.5-4-12 0-16.4z")

    val SignalBars = solid(
        17f, 12f,
        rect(0f, 8f, 3f, 4f), rect(4.6f, 5.5f, 3f, 6.5f),
        rect(9.2f, 3f, 3f, 9f), rect(13.8f, 0f, 3f, 12f),
    )
    val Battery = ImageVector.Builder(
        defaultWidth = 24.dp, defaultHeight = 12.dp, viewportWidth = 24f, viewportHeight = 12f,
    ).apply {
        addPath(
            addPathNodes(rrect(0.5f, 0.5f, 20f, 11f, 3f)),
            stroke = SolidColor(Color.White), strokeLineWidth = 1f,
        )
        addPath(addPathNodes(rrect(2.5f, 2.5f, 15f, 7f, 1.5f)), fill = SolidColor(Color.White))
        addPath(addPathNodes(rrect(22f, 4f, 2f, 4f, 1f)), fill = SolidColor(Color.White))
    }.build()
}
