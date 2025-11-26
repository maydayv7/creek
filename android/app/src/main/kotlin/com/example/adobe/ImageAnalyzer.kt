package com.example.adobe

import android.content.Context
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import java.util.concurrent.CountDownLatch

object ImageAnalyzer {
    private val initLatch = CountDownLatch(1)
    private var isInitializing = false

    fun initializePython(context: Context) {
        if (!isInitializing) {
            isInitializing = true
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(context))
            }
            initLatch.countDown()
        }
    }

    private fun waitForPython() {
        try {
            initLatch.await()
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
    }

    fun analyzeColorStyle(imagePath: String): String? {
        waitForPython()
        return try {
            val py = Python.getInstance()
            val module = py.getModule("color_style_infer")
            val resultObj = module.callAttr("analyze_color_style", imagePath)
            resultObj.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun analyzeLayout(imagePath: String): String? {
        waitForPython()
        return try {
            val py = Python.getInstance()
            val module = py.getModule("analyze_layout")
            val result = module.callAttr("analyze_single_image", imagePath)
            result.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun downloadInstagramImage(url: String, outputDir: String): String? {
        waitForPython()
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
