package com.example.adobe

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.adobe/image_analyzer"
    private val INSTAGRAM_CHANNEL = "com.example.adobe/instagram_downloader"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Python
        ImageAnalyzer.initializePython(this)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "analyzeImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath != null) {
                        try {
                            val analysisResult = ImageAnalyzer.analyzeImage(imagePath)
                            if (analysisResult != null) {
                                result.success(analysisResult)
                            } else {
                                result.error("ANALYSIS_ERROR", "Failed to analyze image", null)
                            }
                        } catch (e: Exception) {
                            result.error("ANALYSIS_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Image path is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTAGRAM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadInstagramImage" -> {
                    val url = call.argument<String>("url")
                    val outputDir = call.argument<String>("outputDir")
                    if (url != null && outputDir != null) {
                        try {
                            val downloadResult = ImageAnalyzer.downloadInstagramImage(url, outputDir)
                            if (downloadResult != null) {
                                result.success(downloadResult)
                            } else {
                                result.error("DOWNLOAD_ERROR", "Failed to download Instagram image", null)
                            }
                        } catch (e: Exception) {
                            result.error("DOWNLOAD_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "URL or output directory is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
