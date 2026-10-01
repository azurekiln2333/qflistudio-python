package com.azurekiln.qfli.pyflow

import android.os.Handler
import android.os.Looper
import androidx.annotation.Keep
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

@Keep
class QfliPyNativeResult(
    val exitCode: Int,
    outputBytes: ByteArray,
    errorBytes: ByteArray?,
    val truncated: Boolean,
) {
    val output = String(outputBytes, Charsets.UTF_8)
    val error = errorBytes?.let { String(it, Charsets.UTF_8) }

    fun toChannelResult(): Map<String, Any?> = mapOf(
        "exitCode" to exitCode,
        "output" to output,
        "error" to error,
        "truncated" to truncated,
    )
}

@Keep
object QfliPyNative {
    private val loadError = try {
        System.loadLibrary("qfli_py")
        null
    } catch (error: UnsatisfiedLinkError) {
        error.message ?: "Unable to load native Python runtime"
    }

    internal val executor = Executors.newSingleThreadExecutor { task ->
        Thread(null, task, "QfliPy", 1024L * 1024L)
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private data class RunSession(val token: Long, var submitted: Boolean = false)
    private val sessions = mutableMapOf<String, RunSession>()
    private var nextRunId = 0L

    private external fun nativeVersion(): ByteArray
    private external fun nativeCreateCancel(): Long
    private external fun nativeCancel(token: Long)
    private external fun nativeFreeCancel(token: Long)
    private external fun nativeRun(
        source: ByteArray,
        stdin: ByteArray,
        heapKb: Int,
        projectPath: ByteArray,
        entryFile: ByteArray,
        compileOnly: Boolean,
        token: Long,
        artifactOutput: ByteArray,
        bytecodeFile: ByteArray,
    ): QfliPyNativeResult

    internal fun prepareRun(): String = synchronized(sessions) {
        check(loadError == null) { loadError ?: "Native Python runtime unavailable" }
        val id = (++nextRunId).toString()
        sessions[id] = RunSession(nativeCreateCancel())
        id
    }

    internal fun cancelRun(id: String): Boolean = synchronized(sessions) {
        val session = sessions[id] ?: return@synchronized false
        nativeCancel(session.token)
        true
    }

    private fun releaseRun(id: String) = synchronized(sessions) {
        sessions.remove(id)?.let { nativeFreeCancel(it.token) }
    }

    fun availability(): Map<String, Any?> = if (loadError == null) {
        mapOf(
            "available" to true,
            "version" to String(nativeVersion(), Charsets.UTF_8),
            "detail" to "MicroPython native runtime",
            "runControl" to true,
            "bytecode" to true,
        )
    } else {
        mapOf("available" to false, "version" to "", "detail" to loadError)
    }

    internal fun run(
        source: String,
        stdin: String = "",
        heapKb: Int = 8192,
        projectPath: String = "",
        entryFile: String = "",
        compileOnly: Boolean = false,
        runId: String? = null,
        artifactOutput: String = "",
        bytecodeFile: String = "",
    ): QfliPyNativeResult {
        check(loadError == null) { loadError ?: "Native Python runtime unavailable" }
        val token = if (runId == null) 0L else synchronized(sessions) {
            val session = checkNotNull(sessions[runId]) { "Unknown Python run" }
            check(!session.submitted) { "Python run already submitted" }
            session.submitted = true
            session.token
        }
        try {
            return nativeRun(
            source.toByteArray(Charsets.UTF_8),
            stdin.toByteArray(Charsets.UTF_8),
            heapKb,
            projectPath.toByteArray(Charsets.UTF_8),
            entryFile.toByteArray(Charsets.UTF_8),
            compileOnly,
            token,
            artifactOutput.toByteArray(Charsets.UTF_8),
            bytecodeFile.toByteArray(Charsets.UTF_8),
        )
        } finally {
            if (runId != null) releaseRun(runId)
        }
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> result.success(availability())
            "prepareRun" -> {
                try {
                    result.success(prepareRun())
                } catch (error: Exception) {
                    result.error("QFLI_PY_NATIVE_ERROR", error.message, null)
                }
            }
            "cancel" -> result.success(call.argument<String>("runId")?.let { cancelRun(it) } ?: false)
            "run", "checkSyntax", "compile" -> {
                val source = call.argument<String>("source")
                if (source == null) {
                    result.error("QFLI_PY_BAD_ARGUMENT", "Missing Python source", null)
                    return
                }
                if (loadError != null) {
                    result.error("QFLI_PY_MODULE_MISSING", loadError, null)
                    return
                }
                val stdin = call.argument<String>("stdin") ?: ""
                val heapKb = call.argument<Number>("heapKb")?.toInt() ?: 8192
                val projectPath = call.argument<String>("projectPath") ?: ""
                val entryFile = call.argument<String>("entryFile") ?: ""
                val compileOnly = call.method != "run"
                val runId = call.argument<String>("runId")
                val artifactOutput = call.argument<String>("artifactOutput") ?: ""
                val bytecodeFile = call.argument<String>("bytecodeFile") ?: ""
                executor.execute {
                    try {
                        val outcome = run(source, stdin, heapKb, projectPath, entryFile,
                            compileOnly, runId, artifactOutput, bytecodeFile)
                        mainHandler.post { result.success(outcome.toChannelResult()) }
                    } catch (error: Exception) {
                        mainHandler.post {
                            result.error("QFLI_PY_NATIVE_ERROR", error.message, null)
                        }
                    } catch (error: LinkageError) {
                        mainHandler.post {
                            result.error("QFLI_PY_MODULE_MISSING", error.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
