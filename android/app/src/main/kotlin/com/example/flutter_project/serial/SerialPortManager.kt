package com.example.flutter_project.serial

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.serialport.SerialPort
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.plugin.common.EventChannel

class SerialPortManager {
    private var serialPort: SerialPort? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private var readThread: Thread? = null
    private val running = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    @Synchronized
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    @Synchronized
    fun isOpen(): Boolean = serialPort != null && running.get()

    @Synchronized
    fun open(path: String?, baud: Int): Boolean {
        val portPath = if (path.isNullOrBlank()) defaultPortPath() else path
        close()
        serialPort = SerialPort(File(portPath), baud, 0)
        input = serialPort!!.inputStream
        output = serialPort!!.outputStream
        startReadLoop()
        return true
    }

    @Synchronized
    fun write(bytes: ByteArray) {
        output?.write(bytes)
        output?.flush()
    }

    @Synchronized
    fun close() {
        running.set(false)
        readThread?.interrupt()
        readThread = null
        try {
            input?.close()
        } catch (_: Exception) {
        }
        try {
            output?.close()
        } catch (_: Exception) {
        }
        try {
            serialPort?.close()
        } catch (_: Exception) {
        }
        input = null
        output = null
        serialPort = null
    }

    private fun startReadLoop() {
        running.set(true)
        readThread = Thread {
            val buffer = ByteArray(1024)
            while (running.get() && input != null) {
                try {
                    val len = input!!.read(buffer)
                    if (len > 0) {
                        val data = String(buffer, 0, len, Charsets.ISO_8859_1)
                        mainHandler.post {
                            eventSink?.success(data)
                        }
                    }
                } catch (_: Exception) {
                    // Stop on read errors
                    running.set(false)
                }
            }
        }
        readThread?.start()
    }

    private fun defaultPortPath(): String {
        val model = getProp("ro.product.model") ?: ""
        val release = Build.VERSION.RELEASE
        return if (((model == "upus" || model == "D26S") && release == "9") ||
            (model == "custom_cutting" && release == "12")
        ) {
            "/dev/ttyS0"
        } else {
            "/dev/ttyS1"
        }
    }

    private fun getProp(key: String): String? {
        return try {
            val cls = Class.forName("android.os.SystemProperties")
            cls.getDeclaredMethod("get", String::class.java).invoke(cls, key) as String
        } catch (_: Exception) {
            null
        }
    }
}
