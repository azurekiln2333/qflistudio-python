package com.azurekiln.qfli.pyflow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pythonChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pythonChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qfli_py/native")
            .also { channel ->
                channel.setMethodCallHandler(QfliPyNative::handleMethodCall)
            }
        QfliPySelfCheck.start(applicationContext)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pythonChannel?.setMethodCallHandler(null)
        pythonChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
