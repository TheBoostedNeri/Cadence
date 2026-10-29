package com.nerijus.cadence.network

import com.nerijus.cadence.config.HttpStatus
import com.nerijus.cadence.config.NetworkPolicy
import com.nerijus.cadence.model.AppError
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class HttpResponse(val statusCode: Int, val body: String) {
    val isSuccess: Boolean get() = statusCode in HttpStatus.success
}

/** One request off the main thread. Network failures become `AppError`s; HTTP errors come back
 *  as responses for the caller to read. */
suspend fun httpRequest(
    url: String,
    method: String = "GET",
    headers: Map<String, String> = emptyMap(),
    body: String? = null,
    contentType: String? = null,
    useCache: Boolean = false,
): HttpResponse = withContext(Dispatchers.IO) {
    val connection = URL(url).openConnection() as HttpURLConnection
    try {
        connection.connectTimeout = NetworkPolicy.CONNECT_TIMEOUT_MILLIS
        connection.readTimeout = NetworkPolicy.READ_TIMEOUT_MILLIS
        connection.requestMethod = method
        connection.useCaches = useCache
        headers.forEach(connection::setRequestProperty)
        if (body != null) {
            val bytes = body.toByteArray()
            connection.doOutput = true
            contentType?.let { connection.setRequestProperty("Content-Type", it) }
            connection.setFixedLengthStreamingMode(bytes.size)
            connection.outputStream.use { it.write(bytes) }
        } else if (method == "POST") {
            // Google rejects a POST that doesn't state a length, even an empty one.
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(0)
            connection.outputStream.close()
        }
        val statusCode = connection.responseCode
        val stream = if (statusCode in HttpStatus.success) connection.inputStream else connection.errorStream
        HttpResponse(statusCode, stream?.bufferedReader()?.use { it.readText() }.orEmpty())
    } catch (error: Throwable) {
        throw AppError.from(error)
    } finally {
        connection.disconnect()
    }
}

/** `a=1&b=2`, sorted and percent-encoded. */
fun formEncode(parameters: Map<String, String>): String = parameters.entries
    .sortedBy { it.key }
    .joinToString("&") { (name, value) -> "${encode(name)}=${encode(value)}" }

private fun encode(text: String): String = URLEncoder.encode(text, Charsets.UTF_8.name())

const val FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"
const val JSON_CONTENT_TYPE = "application/json"
