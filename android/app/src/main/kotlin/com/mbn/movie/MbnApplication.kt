package com.mbn.movie

import android.app.Application
import android.content.Context
import android.os.Build
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/** Initializes trust even for background downloads started without an Activity. */
class MbnApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT < 31) CompatibilityTrust.install(this)
    }
}

private object CompatibilityTrust {
    fun install(context: Context) {
        val factory = CertificateFactory.getInstance("X.509")
        val roots = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
        for (name in listOf("isrg-root-x1.pem", "isrg-root-x2.pem")) {
            val certificate = context.assets.open("flutter_assets/assets/certificates/$name")
                .use { factory.generateCertificate(it) }
            roots.setCertificateEntry(name, certificate)
        }
        fun manager(store: KeyStore?): X509TrustManager =
            TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                .apply { init(store) }.trustManagers.filterIsInstance<X509TrustManager>().first()
        val system = manager(null)
        val additional = manager(roots)
        val combined = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
                system.checkClientTrusted(chain, authType)
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                try {
                    system.checkServerTrusted(chain, authType)
                } catch (error: CertificateException) {
                    additional.checkServerTrusted(chain, authType)
                }
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> =
                system.acceptedIssuers + additional.acceptedIssuers
        }
        val tls = SSLContext.getInstance("TLS")
        tls.init(null, arrayOf(combined), SecureRandom())
        HttpsURLConnection.setDefaultSSLSocketFactory(tls.socketFactory)
        // Android's default hostname verifier remains active.
    }
}
