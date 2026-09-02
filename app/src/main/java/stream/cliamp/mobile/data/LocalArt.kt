package stream.cliamp.mobile.data

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Artwork for local songs. Unlike radio streams, local files have real covers
 * in the MediaStore (usually the embedded album art rounded up into
 * `content://media/external/audio/albumart`), so we read that directly instead
 * of scraping a homepage.
 *
 * [Station.cover] holds the URI to draw from; for a local song it is the album
 * art, for a playlist it is the cover the user chose (itself likely an album
 * art URI or a picked content URI). Bandwidth is not a concern here, so no
 * network path is involved at all.
 */
object LocalArt {

    private const val TARGET = 512
    private val bitmaps = LruCache<String, Bitmap>(16)
    private val misses = LruCache<String, Boolean>(64)

    suspend fun bitmapFor(cover: String?, resolver: ContentResolver): Bitmap? {
        if (cover.isNullOrBlank()) return null
        bitmaps.get(cover)?.let { return it }
        if (misses.get(cover) == true) return null
        val bmp = decode(cover, resolver)
        if (bmp == null) misses.put(cover, true) else bitmaps.put(cover, bmp)
        return bmp
    }

    private suspend fun decode(cover: String, resolver: ContentResolver): Bitmap? =
        withContext(Dispatchers.IO) {
            runCatching {
                val uri = Uri.parse(cover)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@withContext null
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= TARGET && bounds.outHeight / (sample * 2) >= TARGET) {
                    sample *= 2
                }
                val opts = BitmapFactory.Options().apply { inSampleSize = sample }
                resolver.openInputStream(uri)?.use {
                    BitmapFactory.decodeStream(it, null, opts)
                }
            }.getOrNull()
        }
}