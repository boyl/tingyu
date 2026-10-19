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
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportSource: File? = null
    private var spectrum: SpectrumCapture? = null
    private val exportRequest = 7018
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        spectrum?.release()
        spectrum = SpectrumCapture(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.tingyu/storage").setMethodCallHandler { call, result ->
            if (call.method != "installedBytes") { result.notImplemented(); return@setMethodCallHandler }
            Thread {
                try {
                    val bytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val manager = getSystemService(android.app.usage.StorageStatsManager::class.java)
                        manager.queryStatsForUid(android.os.storage.StorageManager.UUID_DEFAULT, applicationInfo.uid).appBytes
                    } else {
                        // Older platforms expose installed APK/split/native files, not compiled ART sizes.
                        val apk = listOfNotNull(applicationInfo.sourceDir) + (applicationInfo.splitSourceDirs?.toList() ?: emptyList())
                        apk.distinct().sumOf { File(it).length() } + File(applicationInfo.nativeLibraryDir).walkTopDown().filter { it.isFile }.sumOf { it.length() }
                    }
                    runOnUiThread { result.success(bytes) }
                } catch (_: Exception) { runOnUiThread { result.error("STORAGE", "无法获取应用安装大小", null) } }
            }.start()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.tingyu/external").setMethodCallHandler { call, result ->
            if (call.method !in listOf("openBilibiliApp", "openBilibiliVideo", "openBilibiliLogin")) { result.notImplemented(); return@setMethodCallHandler }
            val login = call.method == "openBilibiliLogin"
            val loginUrl = call.argument<String>("url")
            if (login && (loginUrl == null || android.net.Uri.parse(loginUrl).let { it.scheme != "https" || it.host != "passport.bilibili.com" || !it.path.orEmpty().contains("login") })) {
                result.error("INVALID_LOGIN", "登录地址无效", null); return@setMethodCallHandler
            }
            val bvid = call.argument<String>("bvid")
            val page = (call.argument<Int>("page") ?: 1).coerceAtLeast(1)
            val video = call.method == "openBilibiliVideo"
            if (video && (bvid == null || !Regex("^BV[0-9A-Za-z]{10}$").matches(bvid))) {
                result.error("INVALID_VIDEO", "视频编号无效", null)
                return@setMethodCallHandler
            }
            var opened = false
            for (packageName in listOf("tv.danmaku.bili", "com.bilibili.app.in")) {
                val intent = if (login) {
                    // Official QR URL carries this session; the official client decides whether to confirm it.
                    Intent(Intent.ACTION_VIEW, android.net.Uri.parse("bilibili://browser/?url=" + android.net.Uri.encode(loginUrl))).setPackage(packageName)
                } else if (video) {
                    android.content.Intent(android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse("https://www.bilibili.com/video/$bvid?p=$page")).setPackage(packageName)
                } else packageManager.getLaunchIntentForPackage(packageName) ?: continue
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
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "tingyu音频.m4a")
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

    override fun onDestroy() {
        spectrum?.release()
        spectrum = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureDisplayEdges()
        window.decorView.post { showSystemBars() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) window.decorView.post { showSystemBars() }
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
    private fun showSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                show(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
    }
}
