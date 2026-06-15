package com.frostr.igloo

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * Render a black-on-white QR code bitmap via the zxing-core public Writer API
 * (stable since 3.5.x). Lives in its own file so the Compose layer doesn't
 * need to know about zxing directly.
 *
 * Returns null when payload is empty or the encoder rejects the input.
 */
fun qrBitmap(payload: String, sizePx: Int = 600): Bitmap? {
    if (payload.isBlank()) return null
    return try {
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 1,
            EncodeHintType.CHARACTER_SET to "UTF-8"
        )
        val writer = QRCodeWriter()
        val matrix = writer.encode(payload, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
        val width = matrix.width
        val height = matrix.height
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val color = if (matrix.get(x, y)) Color.BLACK else Color.WHITE
                bitmap.setPixel(x, y, color)
            }
        }
        bitmap
    } catch (_: Throwable) {
        null
    }
}
