package com.mbn.movie

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Bundle

class AuthBridgeProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        val ctx = context ?: return null
        val prefs = ctx.getSharedPreferences("mbn_auth_bridge", Context.MODE_PRIVATE)
        if (method == "getAuthToken") {
            val token = prefs.getString("token", null)
            val email = prefs.getString("email", null)
            if (!token.isNullOrEmpty()) {
                return Bundle().apply {
                    putString("token", token)
                    putString("email", email ?: "")
                }
            }
        }
        return null
    }

    override fun query(uri: Uri, p: Array<out String>?, s: String?, sa: Array<out String>?, o: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
