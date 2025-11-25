package com.example.adobe

import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

object ImageAnalyzer {
    private var pythonInitialized = false

    fun initializePython(context: android.content.Context) {
        if (!pythonInitialized) {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(context))
            }
            pythonInitialized = true
        }
    }

    fun analyzeImage(imagePath: String): String? {
        return try {
            val py = Python.getInstance()
            val module = py.getModule("analyzer")
            val result = module.callAttr("analyze_single_image", imagePath)
            result.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun downloadInstagramImage(url: String, outputDir: String): String? {
        return try {
            val py = Python.getInstance()
            val module = py.getModule("instagram_downloader")
            val result = module.callAttr("download_instagram_image", url, outputDir)
            result.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}


