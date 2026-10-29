package com.nerijus.cadence.images

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.http.HttpResponseCache
import android.util.LruCache
import com.nerijus.cadence.config.HttpStatus
import com.nerijus.cadence.config.NetworkCache
import com.nerijus.cadence.config.NetworkPolicy
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Downloads and decodes artwork. Decoded images stay in memory; downloads go through the system's
 * HTTP cache on disk, like the iPhone app's shared URLCache, so covers survive relaunches.
 */
class ImageLoader(context: Context) {
    private val memory = object : LruCache<String, Bitmap>(NetworkCache.MEMORY_CAPACITY) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val downloads = Dispatchers.IO.limitedParallelism(NetworkCache.PARALLEL_DOWNLOADS)

    init {
        // Also caches API responses, as far as their headers allow.
        if (HttpResponseCache.getInstalled() == null) {
            HttpResponseCache.install(File(context.cacheDir, NetworkCache.DIRECTORY), NetworkCache.DISK_CAPACITY)
        }
    }

    /** The image already in memory, so a screen can show it without a loading frame. */
    fun cached(url: String, sizePx: Int): Bitmap? = memory.get(key(url, sizePx))

    /** The image at `url`, decoded at no more than about twice `sizePx` across, or null if it
     *  can't be loaded. */
    suspend fun load(url: String, sizePx: Int): Bitmap? {
        val key = key(url, sizePx)
        memory.get(key)?.let { return it }
        val bitmap = withContext(downloads) {
            runCatching { decode(download(url), sizePx) }.getOrNull()
        } ?: return null
        memory.put(key, bitmap)
        return bitmap
    }

    private fun download(url: String): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = NetworkPolicy.CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = NetworkPolicy.READ_TIMEOUT_MILLIS
            connection.useCaches = true
            check(connection.responseCode in HttpStatus.success)
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    private fun decode(bytes: ByteArray, sizePx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        // Halve until the shorter side is no more than twice what's shown; artwork is cropped to it.
        var sampleSize = 1
        while (minOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= sizePx * 2) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    private fun key(url: String, sizePx: Int) = "$sizePx@$url"
}
