package app.tingyu.tingyu

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sqrt

class SpectrumCapture(messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var visualizer: Visualizer? = null
    private var sink: EventChannel.EventSink? = null
    private var generation = 0

    init {
        EventChannel(messenger, "app.tingyu/spectrum/events").setStreamHandler(this)
        MethodChannel(messenger, "app.tingyu/spectrum").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    if (sessionId == null || sessionId <= 0) {
                        result.success(false)
                    } else {
                        result.success(start(sessionId))
                    }
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stop()
    }

    fun release() = stop()

    private fun start(sessionId: Int): Boolean {
        stop()
        val generation = ++this.generation
        return try {
            val capture = Visualizer(sessionId)
            capture.captureSize = Visualizer.getCaptureSizeRange()[1]
            capture.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int,
                    ) {}

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int,
                    ) {
                        if (fft == null || generation != this@SpectrumCapture.generation) return
                        val levels = bands(fft, samplingRate)
                        main.post {
                            if (generation == this@SpectrumCapture.generation) sink?.success(levels)
                        }
                    }
                },
                Visualizer.getMaxCaptureRate(),
                false,
                true,
            )
            capture.enabled = true
            visualizer = capture
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun stop() {
        generation++
        visualizer?.let { capture ->
            try {
                capture.enabled = false
            } catch (_: RuntimeException) {}
            try {
                capture.release()
            } catch (_: RuntimeException) {}
        }
        visualizer = null
    }
}

private const val bandCount = 32

private fun bands(fft: ByteArray, samplingRateMilli: Int): ArrayList<Double> {
    val levels = ArrayList<Double>(bandCount)
    val sampleRate = samplingRateMilli / 1000.0
    if (fft.size < 4 || sampleRate <= 0.0) {
        repeat(bandCount) { levels.add(0.0) }
        return levels
    }
    val bins = fft.size / 2
    val maxHz = min(16000.0, sampleRate / 2.0)
    val minHz = 40.0
    if (maxHz <= minHz) {
        repeat(bandCount) { levels.add(0.0) }
        return levels
    }
    val logMin = ln(minHz)
    val logMax = ln(maxHz)
    val edges = DoubleArray(bandCount + 1) { index ->
        exp(logMin + (logMax - logMin) * index / bandCount)
    }
    for (band in 0 until bandCount) {
        var peak = 0.0
        var bin = 1
        while (bin < bins - 1) {
            val hz = bin * sampleRate / fft.size
            if (hz >= edges[band] && hz < edges[band + 1]) {
                val magnitude = hypot(fft[2 * bin].toDouble(), fft[2 * bin + 1].toDouble())
                if (magnitude > peak) peak = magnitude
            }
            bin++
        }
        levels.add(sqrt(peak / 72.0).coerceIn(0.0, 1.0))
    }
    return levels
}
