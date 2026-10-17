package app.tingyu.tingyu

import android.graphics.Color
import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import android.view.WindowManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportSource: File? = null
    private val exportRequest = 7018
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.tingyu/external").setMethodCallHandler { call, result ->
            if (call.method != "openBilibiliApp") { result.notImplemented(); return@setMethodCallHandler }
            var opened = false
            for (packageName in listOf("tv.danmaku.bili", "com.bilibili.app.in")) {
                val intent = packageManager.getLaunchIntentForPackage(packageName) ?: continue
                try {
                    startActivity(intent)
                    opened = true
                    break
                } catch (_: android.content.ActivityNotFoundException) {
                    // Try another official client, then let Dart open the browser.
                } catch (_: SecurityException) {
                    // A disabled/restricted client is not a successful handoff.
                }
            }
            result.success(opened)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.tingyu/export").setMethodCallHandler { call, result ->
            if (call.method != "saveM4a") { result.notImplemented(); return@setMethodCallHandler }
            if (exportResult != null) { result.error("BUSY", "已有导出任务", null); return@setMethodCallHandler }
            val source = File(call.argument<String>("path") ?: "").canonicalFile
            if (!source.isFile || !source.path.startsWith(filesDir.canonicalPath + File.separator) || !source.name.endsWith(".m4a")) {
                result.error("SOURCE", "导出源文件无效", null); return@setMethodCallHandler
            }
            exportResult = result
            exportSource = source
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/mp4"
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "听屿音频.m4a")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI,
                        DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:Download"))
                }
            }
            try { startActivityForResult(intent, exportRequest) }
            catch (e: Exception) { exportResult = null; exportSource = null; result.error("PICKER", "无法打开保存位置", null) }
        }
    }

    @Deprecated("Platform document picker result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequest) return
        val result = exportResult ?: return
        val source = exportSource
        exportResult = null
        exportSource = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || source == null) { result.success(null); return }
        Thread {
            try {
                val sourceDigest = MessageDigest.getInstance("SHA-256")
                var sourceBytes = 0L
                contentResolver.openOutputStream(uri, "wt").use { output ->
                    requireNotNull(output)
                    source.inputStream().use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            sourceDigest.update(buffer, 0, count)
                            sourceBytes += count
                        }
                    }
                }
                val digest = MessageDigest.getInstance("SHA-256")
                var bytes = 0L
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input)
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                        bytes += count
                    }
                }
                val writtenDigest = digest.digest()
                require(sourceBytes == bytes && sourceDigest.digest().contentEquals(writtenDigest))
                val sha = writtenDigest.joinToString("") { "%02x".format(it) }
                runOnUiThread { result.success(mapOf("uri" to uri.toString(), "bytes" to bytes, "sha256" to sha)) }
            } catch (e: Exception) {
                try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { }
                runOnUiThread { result.error("WRITE", "无法保存音频，请检查空间与目标位置", null) }
            }
        }.start()
    }

    private var keyboardWasVisible = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureDisplayEdges()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.setOnApplyWindowInsetsListener { _, insets ->
                val keyboardVisible = insets.isVisible(WindowInsets.Type.ime())
                if (keyboardWasVisible && !keyboardVisible) {
                    window.decorView.postDelayed({ hideSystemBars() }, 300)
                }
                keyboardWasVisible = keyboardVisible
                insets
            }
        }
        window.decorView.post { hideSystemBars() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) window.decorView.post { hideSystemBars() }
    }

    // Extend the background into camera cutouts; Flutter SafeArea protects controls.
    // Explicit policy is required on Android 9-14, including vendor Android builds.
    @Suppress("DEPRECATION")
    private fun configureDisplayEdges() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                } else {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    @Suppress("DEPRECATION")
    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }
}
