package com.creek.ui

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.creek.ui/methods"
    private val scope = CoroutineScope(Dispatchers.Default)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // This updates the activity's intent to the new one
    }

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
                        "generateStylesheet" -> {
                            val jsonList = call.argument<List<String>>("jsonList")!!
                            ImageAnalyzer.generateStylesheet(jsonList)
                        }
                        "generateMagicPrompt" -> {
                            val stylesheetJson = call.argument<String>("stylesheetJson") ?: "{}"
                            val caption = call.argument<String>("caption") ?: ""
                            val userPrompt = call.argument<String>("userPrompt") ?: ""
                            ImageAnalyzer.generateMagicPrompt(stylesheetJson, caption, userPrompt)
                        }
                        "getShareSource" -> {
                            val componentName = intent.component?.className
                            when {
                                componentName?.contains("ShareToFiles") == true -> "files"
                                componentName?.contains("ShareToMoodboards") == true -> "moodboards"
                                else -> "moodboards"
                            }
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
                            } else if (response == null) {
                                // Python returned null (error inside script)
                                result.error("PYTHON_ERROR", "Python returned null for ${call.method}", null)
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
