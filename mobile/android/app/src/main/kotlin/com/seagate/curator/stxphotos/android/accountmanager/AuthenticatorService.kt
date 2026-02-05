package com.seagate.curator.stxphotos.android.accountmanager

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

class AuthenticatorService : Service() {
    
    companion object {
        const val TAG = "AuthenticatorService"
    }
    
    private lateinit var authenticator: Authenticator
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AuthenticatorService created")
        authenticator = Authenticator(this)
    }
    
    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "AuthenticatorService bound")
        return authenticator.iBinder
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "AuthenticatorService destroyed")
    }
}