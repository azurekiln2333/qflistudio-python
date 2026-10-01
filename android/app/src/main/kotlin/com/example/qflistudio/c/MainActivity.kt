package com.azurekiln.qfli.pyflow

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private var pythonChannel: MethodChannel? = null
    private var platformChannel: MethodChannel? = null
    private var startupOverlay: FrameLayout? = null
    private var startupProgressBar: ProgressBar? = null
    private var startupProgress = 0.0
    private var flutterUiDisplayed = false
    private var startupFrameCommitted = false
    private var startupFrameCommitCallback: Runnable? = null
    private var systemSplashRemoval: (() -> Unit)? = null

    // Surface mode gates the whole Android view tree before Flutter's first frame.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashView ->
                systemSplashRemoval = { splashView.remove() }
                releaseSystemSplashIfReady()
            }
        }
        super.onCreate(savedInstanceState)
        if (!flutterUiDisplayed) showStartupOverlay()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pythonChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qfli_py/native")
            .also { channel ->
                channel.setMethodCallHandler(QfliPyNative::handleMethodCall)
            }
        platformChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qflistudio/platform")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method != "startupProgress") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    val progress = ((call.arguments as? Map<*, *>)?.get("progress") as? Number)?.toDouble()
                    if (progress == null || !progress.isFinite()) {
                        result.error("INVALID_PROGRESS", "Progress must be a finite number", null)
                        return@setMethodCallHandler
                    }
                    startupProgress = progress.coerceIn(0.0, 1.0)
                    startupProgressBar?.setProgress((startupProgress * 1000).roundToInt(), true)
                    result.success(null)
                }
            }
        QfliPySelfCheck.start(applicationContext)
    }

    private fun showStartupOverlay() {
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(getColor(R.color.startup_background))
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        val icon = ImageView(this).apply {
            setImageResource(R.drawable.startup_icon)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        overlay.addView(icon, FrameLayout.LayoutParams(dp(96), dp(96), Gravity.CENTER))

        val progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = false
            max = 1000
            progressDrawable = getDrawable(R.drawable.startup_progress)
            progress = (startupProgress * max).roundToInt()
        }
        val progressLayout = FrameLayout.LayoutParams(0, dp(4), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
            .apply { bottomMargin = dp(48) }
        overlay.addView(progressBar, progressLayout)
        overlay.addOnLayoutChangeListener { _, left, _, right, _, _, _, _, _ ->
            val width = minOf(dp(420), (right - left - dp(64)).coerceAtLeast(0))
            if (progressLayout.width != width) {
                progressLayout.width = width
                progressBar.layoutParams = progressLayout
            }
        }
        startupOverlay = overlay
        startupProgressBar = progressBar
        addContentView(overlay, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Keep the system splash until the native overlay has a submitted frame.
            val callback = Runnable {
                startupFrameCommitCallback = null
                if (startupOverlay !== overlay) return@Runnable
                startupFrameCommitted = true
                releaseSystemSplashIfReady()
            }
            startupFrameCommitCallback = callback
            overlay.viewTreeObserver.registerFrameCommitCallback(callback)
        }
    }

    private fun releaseSystemSplashIfReady() {
        if (!startupFrameCommitted && !flutterUiDisplayed) return
        val remove = systemSplashRemoval ?: return
        systemSplashRemoval = null
        remove()
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterUiDisplayed = true
        releaseSystemSplashIfReady()
        startupOverlay?.animate()?.alpha(0f)?.setDuration(200)?.withEndAction {
            removeStartupOverlay()
        }?.start()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        startupOverlay?.setBackgroundColor(getColor(R.color.startup_background))
        startupProgressBar?.apply {
            progressDrawable = getDrawable(R.drawable.startup_progress)
            progress = (startupProgress * max).roundToInt()
        }
    }

    private fun removeStartupOverlay() {
        val overlay = startupOverlay ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            startupFrameCommitCallback?.let { callback ->
                overlay.viewTreeObserver.takeIf { it.isAlive }?.unregisterFrameCommitCallback(callback)
            }
            startupFrameCommitCallback = null
        }
        startupOverlay = null
        startupProgressBar = null
        overlay.animate().cancel()
        (overlay.parent as? ViewGroup)?.removeView(overlay)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pythonChannel?.setMethodCallHandler(null)
        pythonChannel = null
        platformChannel?.setMethodCallHandler(null)
        platformChannel = null
        removeStartupOverlay()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.clearOnExitAnimationListener()
            systemSplashRemoval?.invoke()
            systemSplashRemoval = null
        }
        removeStartupOverlay()
        super.onDestroy()
    }
}
