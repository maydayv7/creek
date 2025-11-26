package com.example.adobe

import android.content.Context
import android.util.Log 
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
    fun analyzeColorStyle(imagePath: String): Map<String, Any>? {
        Log.d("LinkChecker", "1. analyzeColorStyle called in Kotlin")
        return try {
            val py = Python.getInstance()
            Log.d("LinkChecker", "2. Python Instance obtained")

            // CHECK 1: Loading the module
            // This MUST match your python filename "color_style_infer.py"
            val module = py.getModule("color_style_infer") 
            Log.d("LinkChecker", "3. Module 'color_style_infer' found!")

            // CHECK 2: Calling the function
            Log.d("LinkChecker", "4. Calling python function 'analyze_color_style'...")
            val resultObj = module.callAttr("analyze_color_style", imagePath)
            
            val jsonResult = resultObj.toString()
            Log.d("LinkChecker", "5. Success! Python returned: $jsonResult")
            
            mapOf("raw_json" to jsonResult, "success" to true)
        } catch (e: com.chaquo.python.PyException) {
            // Python crashed (Import error, Syntax error, etc.)
            Log.e("LinkChecker", "PYTHON CRASH: ${e.message}")
            e.printStackTrace()
            mapOf("success" to false, "error" to "Python Crash: ${e.message}")
        } catch (e: Exception) {
            // Kotlin/Java crashed (Module not found, etc.)
            Log.e("LinkChecker", "JAVA CRASH: ${e.message}")
            e.printStackTrace()
            mapOf("success" to false, "error" to "Java Crash: ${e.message}")
        }
    }
    fun analyzeImage(imagePath: String): String? {
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
