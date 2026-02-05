package com.seagate.curator.stxphotos.android.accountmanager

import android.accounts.AbstractAccountAuthenticator
import android.accounts.Account
import android.accounts.AccountAuthenticatorResponse
import android.accounts.AccountManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

class Authenticator(private val context: Context) : AbstractAccountAuthenticator(context) {

    companion object {
        const val ACCOUNT_AUTH_TOKEN_TYPE = "full_access"
        const val TAG = "Authenticator"
    }

    override fun addAccount(
        response: AccountAuthenticatorResponse,
        accountType: String,
        authTokenType: String?,
        requiredFeatures: Array<String>?,
        options: Bundle?
    ): Bundle {
        Log.d(TAG, "addAccount called for type: $accountType")
        val result = Bundle()
        return result
    }

    override fun getAuthToken(
        response: AccountAuthenticatorResponse,
        account: Account,
        authTokenType: String,
        options: Bundle?
    ): Bundle {
        Log.d(TAG, "getAuthToken for account: ${account.name}, type: $authTokenType")

        val result = Bundle()
        return result
    }

    override fun confirmCredentials(
        response: AccountAuthenticatorResponse,
        account: Account,
        options: Bundle?
    ): Bundle? {
        Log.d(TAG, "confirmCredentials for account: ${account.name}")
        return null
    }

    override fun editProperties(
        response: AccountAuthenticatorResponse,
        accountType: String
    ): Bundle? {
        Log.d(TAG, "editProperties for account type: $accountType")
        return null
    }

    override fun updateCredentials(
        response: AccountAuthenticatorResponse,
        account: Account,
        authTokenType: String?,
        options: Bundle?
    ): Bundle? {
        Log.d(TAG, "updateCredentials for account: ${account.name}")
        return null
    }

    override fun getAuthTokenLabel(authTokenType: String): String {
        return when (authTokenType) {
            ACCOUNT_AUTH_TOKEN_TYPE -> "Curator Access"
            else -> "Unknown token type"
        }
    }

    override fun hasFeatures(
        response: AccountAuthenticatorResponse,
        account: Account,
        features: Array<String>
    ): Bundle {
        Log.d(TAG, "hasFeatures for account: ${account.name}, features: ${features.joinToString()}")

        val result = Bundle()
        result.putBoolean(AccountManager.KEY_BOOLEAN_RESULT, false)
        return result
    }
}
