package com.kinde.kinde_flutter_sdk

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.content.Intent
import android.net.Uri
import android.util.Log

/** KindeFlutterSdkPlugin */
class KindeFlutterSdkPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, 
    PluginRegistry.NewIntentListener, PluginRegistry.ActivityResultListener {

  private enum class AuthState {
      NONE,
      PKCE_PENDING,
      NORMAL_PENDING
  }

  private lateinit var channel : MethodChannel
  private var activityBinding: ActivityPluginBinding? = null
  private val TAG = "KindeFlutterSDK"
  private var pendingOperation: Result? = null
  private var currentNonce: String? = null
  private var currentState: String? = null
  private var authState = AuthState.NONE
  private val RC_AUTH = 65031
  private var methodCallCount = 0
  private var lastMethodCallTime: Long = 0

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "\n=== Plugin Attachment to Engine ===")
    Log.d(TAG, "Time: ${System.currentTimeMillis()}")
    Log.d(TAG, "Thread ID: ${Thread.currentThread().id}")
    Log.d(TAG, "Instance Hash: ${this.hashCode()}")
    
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "kinde_flutter_sdk")
    channel.setMethodCallHandler(this)
    Log.d(TAG, "Method Channel Handler Set")
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    methodCallCount++
    lastMethodCallTime = System.currentTimeMillis()
    
    Log.d(TAG, "\n=== Method Call #$methodCallCount ===")
    Log.d(TAG, "Time: $lastMethodCallTime")
    Log.d(TAG, "Thread ID: ${Thread.currentThread().id}")
    Log.d(TAG, "Method: ${call.method}")
    Log.d(TAG, "Instance Hash: ${this.hashCode()}")
    
    synchronized(this) {
        when (call.method) {
            "authorize" -> {
                // Normal auth flow
                authState = AuthState.NORMAL_PENDING
                currentNonce = call.argument<String>("nonce")
                currentState = call.argument<String>("state")
                
                if (pendingOperation != null) {
                    pendingOperation?.error("cancelled", 
                        "Operation cancelled due to new request", null)
                }
                pendingOperation = result
                Log.d(TAG, "Started Normal Auth - State: $currentState")
            }
            "authorizeAndExchangeCode" -> {
                // PKCE flow
                authState = AuthState.PKCE_PENDING
                currentNonce = call.argument<String>("nonce")
                currentState = call.argument<String>("state")
                
                if (pendingOperation != null) {
                    pendingOperation?.error("cancelled", 
                        "Operation cancelled due to new request", null)
                }
                pendingOperation = result
                Log.d(TAG, "Started PKCE Auth - State: $currentState")
            }
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            else -> {
                result.notImplemented()
            }
        }
    }
  }

  override fun onNewIntent(intent: Intent): Boolean {
    Log.d(TAG, "\n=== Intent Processing Detail ===")
    Log.d(TAG, "Time: ${System.currentTimeMillis()}")
    Log.d(TAG, "Auth State: $authState")
    Log.d(TAG, "Current State: $currentState")
    
    val data = intent.data
    if (data != null) {
        synchronized(this) {
            try {
                val state = data.getQueryParameter("state")
                val code = data.getQueryParameter("code")
                
                when (authState) {
                    AuthState.PKCE_PENDING -> {
                        if (state != currentState) {
                            // Instead of failing, transition to normal flow
                            Log.d(TAG, "PKCE state mismatch, transitioning to normal flow")
                            authState = AuthState.NORMAL_PENDING
                            pendingOperation?.success(mapOf(
                                "type" to "authorization",
                                "code" to code,
                                "state" to state,
                                "nonce" to currentNonce,
                                "shouldRetry" to true
                            ))
                        } else {
                            handleSuccessfulAuth(intent)
                        }
                    }
                    AuthState.NORMAL_PENDING -> {
                        if (state != currentState) {
                            Log.e(TAG, "Normal flow state mismatch")
                            pendingOperation?.error("state_mismatch", 
                                "Authorization state mismatch", null)
                        } else {
                            handleSuccessfulAuth(intent)
                        }
                    }
                    AuthState.NONE -> {
                        Log.e(TAG, "No pending authentication")
                        pendingOperation?.error("invalid_state", 
                            "No pending authentication", null)
                    }
                }
                return true
            } catch (e: Exception) {
                Log.e(TAG, "Error processing intent: ${e.message}")
                pendingOperation?.error("processing_error", e.message, null)
            }
        }
    }
    return false
  }

  private fun handleSuccessfulAuth(data: Intent) {
    val uri = data.data
    if (uri != null) {
        pendingOperation?.success(mapOf(
            "type" to "authorization",
            "code" to uri.getQueryParameter("code"),
            "state" to uri.getQueryParameter("state"),
            "nonce" to currentNonce
        ))
        
        // Reset state
        authState = AuthState.NONE
        currentState = null
        currentNonce = null
        pendingOperation = null
        Log.d(TAG, "Auth completed successfully, state reset")
    } else {
        pendingOperation?.error("invalid_data", "No URI data in Intent", null)
    }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    Log.d(TAG, "\n=== Activity Result ===")
    Log.d(TAG, "Request Code: $requestCode")
    Log.d(TAG, "Result Code: $resultCode")
    Log.d(TAG, "Auth State: $authState")
    
    if (requestCode == RC_AUTH && pendingOperation != null) {
        if (resultCode == -1) { // RESULT_OK
            return true // Let onNewIntent handle the success case
        } else {
            synchronized(this) {
                pendingOperation?.error("cancelled", 
                    "User cancelled the authorization", null)
                resetState()
            }
            return true
        }
    }
    return false
  }

  private fun resetState() {
    authState = AuthState.NONE
    currentState = null
    currentNonce = null
    pendingOperation = null
    Log.d(TAG, "State reset completed")
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
    binding.addActivityResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding?.removeActivityResultListener(this)
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
    binding.addActivityResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding?.removeActivityResultListener(this)
    activityBinding = null
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}