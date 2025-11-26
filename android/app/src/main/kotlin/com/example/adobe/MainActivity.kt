package com.example.adobe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.adobe/methods"
    private val scope = CoroutineScope(Dispatchers.Default)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Python immediately in the background
        scope.launch(Dispatchers.IO) {
            ImageAnalyzer.initializePython(context)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            // Launch a new coroutine for every method call on the IO dispatcher for parallel execution
            scope.launch(Dispatchers.IO) {
                try {
                    val response: Any? = when (call.method) {
                        "analyzeLayout" -> {
                            val path = call.argument<String>("imagePath")!!
                            ImageAnalyzer.analyzeLayout(path)
                        }
                        "analyzeColorStyle" -> {
                            val path = call.argument<String>("imagePath")!!
                            ImageAnalyzer.analyzeColorStyle(path)
                        }
                        "downloadInstagramImage" -> {
                            val url = call.argument<String>("url")!!
                            val outputDir = call.argument<String>("outputDir")!!
                            ImageAnalyzer.downloadInstagramImage(url, outputDir)
                        }
                        else -> null
                    }

                    // Switch back to the Main Thread to send the result to Flutter
                    withContext(Dispatchers.Main) {
                        if (response != null) {
                            result.success(response)
                        } else {
                            if (call.method == "downloadInstagramImage") {
                                // Specific error handling for downloader if needed
                                result.error("ERROR", "Download returned null", null)
                            } else if (response == null && (call.method == "analyzeLayout" || call.method == "analyzeColorStyle")) {
                                // Python returned null (error inside script)
                                result.error("ANALYSIS_ERROR", "Python returned null", null)
                            } else {
                                result.notImplemented()
                            }
                        }
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("EXCEPTION", e.message, e.stackTraceToString())
                    }
                }
            }
        }
    }
}
