package com.seagate.curator.stxphotos.android.accountmanager

import android.accounts.Account as AndroidAccount
import android.accounts.AccountManager
import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.lang.Exception

class AccountManagerApiImpl(private val context: Context) : AccountManagerApi {

    companion object {
        private const val TAG = "AccountManagerApiImpl"
        private const val APP_ACCOUNT_TYPE = "com.seagate.curator"
        const val KEY_OC_ACCOUNT_VERSION = "oc_account_version";
        const val KEY_OC_BASE_URL = "oc_base_url";
        const val KEY_OC_DISPLAY_NAME = "oc_display_name";
        const val KEY_OC_EMAIL = "oc_email";
        const val KEY_OC_ID = "oc_id";
        const val KEY_IS_KITEWORKS_SERVER = "is_kiteworks_server";
        const val KEY_RA_ACCESS_TOKEN = "ra_access_token";
        const val KEY_RA_REFRESH_TOKEN = "ra_refresh_token";
        const val KEY_RA_FAVORITE_DEVICE_CERT_COMMON_NAME = "ra_favorite_device_cert_common_name";
    }

    private val accountManager: AccountManager by lazy {
        AccountManager.get(context)
    }

    private val coroutineScope = CoroutineScope(Dispatchers.IO)

    override fun addAccount(account: Account, password: String, callback: (Result<Account>) -> Unit) {
        coroutineScope.launch {
            try {
                val androidAccount = AndroidAccount(account.name, account.type)
                val success = accountManager.addAccountExplicitly(androidAccount, password, null)

                callback(Result.success(account))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getAccounts(callback: (Result<List<Account>>) -> Unit) {
        coroutineScope.launch {
            try {
                // Only expose this app's accounts to the Dart side to avoid
                // accidentally operating on Google/Samsung/other provider accounts,
                // which can trigger SecurityException on newer Android versions.
                val androidAccounts = accountManager.getAccountsByType(APP_ACCOUNT_TYPE)
                val accounts = androidAccounts.map { androidAccount ->
                    Account(
                        name = androidAccount.name,
                        type = androidAccount.type
                    )
                }

                callback(Result.success(accounts))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun removeAccount(account: Account, callback: (Result<Boolean>) -> Unit) {
        coroutineScope.launch {
            try {
                val androidAccount = AndroidAccount(account.name, account.type)
                val future = accountManager.removeAccount(androidAccount, null, null, null)
                val bundleResult = future.result

                val success = bundleResult.getBoolean(
                    AccountManager.KEY_BOOLEAN_RESULT,
                    false
                )

                callback(Result.success(success))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun hasAccount(accountName: String, accountType: String, callback: (Result<Boolean>) -> Unit) {
        coroutineScope.launch {
            try {
                val accounts = accountManager.getAccountsByType(accountType)
                val exists = accounts.any { it.name == accountName }

                callback(Result.success(exists))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun setUserData(account: Account, userData: Map<String, String?>, callback: (Result<Boolean>) -> Unit) {
        coroutineScope.launch {
            try {
                if (!accountExists(account)) {
                    callback(Result.failure(
                        IllegalArgumentException("Account does not exist: ${account.name}")
                    ))
                    return@launch
                }

                val androidAccount = AndroidAccount(account.name, account.type)
                userData.entries.forEach {
                  (key, value) ->
                    if (value != null) {
                        accountManager.setUserData(androidAccount, key, value)
                    }
                }

                callback(Result.success(true))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getUserData(account: Account, keys: List<String>, callback: (Result<Map<String, String?>>) -> Unit) {
        coroutineScope.launch {
            try {
                if (!accountExists(account)) {
                    callback(Result.failure(
                        IllegalArgumentException("Account does not exist: ${account.name}")
                    ))
                    return@launch
                }

                val androidAccount = AndroidAccount(account.name, account.type)
                val userDataMap = keys.associateWith { key ->
                  accountManager.getUserData(androidAccount, key)
                }


              callback(Result.success(userDataMap))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getPassword(account: Account, callback: (Result<String?>) -> Unit) {
        coroutineScope.launch {
            try {
                if (!accountExists(account)) {
                    callback(Result.failure(
                        IllegalArgumentException("Account does not exist: ${account.name}")
                    ))
                    return@launch
                }

                val androidAccount = AndroidAccount(account.name, account.type)
                val password = accountManager.getPassword(androidAccount)

                callback(Result.success(password))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun setPassword(account: Account, password: String?, callback: (Result<Boolean>) -> Unit) {
        coroutineScope.launch {
            try {
                if (!accountExists(account)) {
                    callback(Result.failure(
                        IllegalArgumentException("Account does not exist: ${account.name}")
                    ))
                    return@launch
                }

                val androidAccount = AndroidAccount(account.name, account.type)
                accountManager.setPassword(androidAccount, password)

                callback(Result.success(true))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun removeUserData(account: Account, keys: List<String>, callback: (Result<Boolean>) -> Unit) {
        coroutineScope.launch {
            try {
                if (!accountExists(account)) {
                    callback(Result.failure(
                        IllegalArgumentException("Account does not exist: ${account.name}")
                    ))
                    return@launch
                }

                val androidAccount = AndroidAccount(account.name, account.type)

                keys.forEach { key ->
                  accountManager.setUserData(androidAccount, key, null)
                }

                callback(Result.success(true))
            } catch (e: SecurityException) {
                callback(Result.failure(e))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    private fun accountExists(account: Account): Boolean {
        return try {
            val accounts = accountManager.getAccountsByType(account.type)
            accounts.any { it.name == account.name }
        } catch (_: Exception) {
            false
        }
    }
}
