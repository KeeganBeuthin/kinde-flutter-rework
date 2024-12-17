package com.example.kindeflutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Bundle
import android.util.Log
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationService

class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    private lateinit var authService: AuthorizationService
    private val CHANNEL = "com.example.kindeflutter/auth"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "handleAuthResponse" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        authService = AuthorizationService(this)
        handleIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        authService.dispose()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        Log.d(TAG, "\n=== MainActivity Intent Lifecycle ===")
        Log.d(TAG, "Thread ID: ${Thread.currentThread().id}")
        Log.d(TAG, "Activity Instance: ${this.hashCode()}")
        
        val data = intent.data
        if (data != null) {
            Log.d(TAG, "\n=== Intent Data Detail ===")
            Log.d(TAG, "Full URI: ${data.toString()}")
            Log.d(TAG, "Intent Delivery Time: ${System.currentTimeMillis()}")
            Log.d(TAG, "Intent Flags Detail:")
            Log.d(TAG, "- Raw flags: ${intent.flags}")
            Log.d(TAG, "- Is new task: ${(intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK) != 0}")
            Log.d(TAG, "- Is single top: ${(intent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP) != 0}")
        }
    }
}