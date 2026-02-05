package com.example.flutter_project

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import com.caverock.androidsvg.SVG
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.ByteArrayInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "svg_renderer"

    private fun decodeSvg(bytes: ByteArray): String {
        if (bytes.size >= 2) {
            val b0 = bytes[0]
            val b1 = bytes[1]
            if (b0 == 0xFF.toByte() && b1 == 0xFE.toByte()) {
                return sanitizeSvg(String(bytes, Charsets.UTF_16LE))
            }
            if (b0 == 0xFE.toByte() && b1 == 0xFF.toByte()) {
                return sanitizeSvg(String(bytes, Charsets.UTF_16BE))
            }
        }
        val headLen = if (bytes.size > 200) 200 else bytes.size
        val head = String(bytes, 0, headLen, Charsets.ISO_8859_1)
        return if (head.contains("encoding=\"UTF-16\"") || head.contains("encoding='UTF-16'")) {
            sanitizeSvg(String(bytes, Charsets.UTF_16LE))
        } else {
            sanitizeSvg(String(bytes, Charsets.UTF_8))
        }
    }

    private fun sanitizeSvg(input: String): String {
        var text = input
        text = text.replace(Regex("<\\?xml[^>]*\\?>"), "")
        text = text.replace(Regex("<!DOCTYPE[^>]*>"), "")
        text = text.replace(Regex("<metadata[^>]*>.*?</metadata>", RegexOption.DOT_MATCHES_ALL), "")
        return text
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderSvg" -> {
                        try {
                            val svgText = call.argument<String>("svg") ?: ""
                            val width = call.argument<Int>("width") ?: 0
                            val height = call.argument<Int>("height") ?: 0
                            if (svgText.isEmpty() || width <= 0 || height <= 0) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val svg = SVG.getFromString(svgText)
                            svg.documentWidth = width.toFloat()
                            svg.documentHeight = height.toFloat()
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                            svg.renderToCanvas(canvas)
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            result.success(stream.toByteArray())
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    "renderSvgBytes" -> {
                        try {
                            val bytes = call.argument<ByteArray>("bytes")
                            val width = call.argument<Int>("width") ?: 0
                            val height = call.argument<Int>("height") ?: 0
                            if (bytes == null || bytes.isEmpty() || width <= 0 || height <= 0) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val decoded = decodeSvg(bytes)
                            val svg = SVG.getFromString(decoded)
                            svg.documentWidth = width.toFloat()
                            svg.documentHeight = height.toFloat()
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                            svg.renderToCanvas(canvas)
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            result.success(stream.toByteArray())
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
