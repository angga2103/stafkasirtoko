package com.kasirtoko.app.stafkasirtoko

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class MainActivity : FlutterActivity() {
    companion object {
        private const val SECURITY_CHANNEL = "com.kasirtoko.app.stafkasirtoko/security"
        private const val HARDWARE_CHANNEL = "com.kasirtoko.app.stafkasirtoko/hardware"
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val KEK_ALIAS = "stafkasirtoko_vault_kek_v1"
        private const val PREFS_NAME = "stafkasirtoko_secure_prefs"
        private const val KEY_LEGACY_AES = "legacy_api21_aes_b64"
    }

    private val cryptoExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "putSecure" -> {
                    val key = call.argument<String>("key") ?: ""
                    val value = call.argument<String>("value") ?: ""
                    if (key.isBlank()) {
                        result.error("INVALID_KEY", "Secure key empty", null)
                        return@setMethodCallHandler
                    }
                    cryptoExecutor.execute {
                        try {
                            val wrapped = encryptValue(value)
                            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                                .edit()
                                .putString("sec_$key", wrapped)
                                .apply()
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("KEYSTORE_PUT_ERROR", e.message, null) }
                        }
                    }
                }

                "getSecure" -> {
                    val key = call.argument<String>("key") ?: ""
                    if (key.isBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    cryptoExecutor.execute {
                        try {
                            val wrapped = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                                .getString("sec_$key", null)
                            val plain = if (!wrapped.isNullOrEmpty()) decryptValue(wrapped) else null
                            mainHandler.post { result.success(plain) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("KEYSTORE_GET_ERROR", e.message, null) }
                        }
                    }
                }

                "deleteSecure" -> {
                    val key = call.argument<String>("key") ?: ""
                    if (key.isNotBlank()) {
                        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            .edit()
                            .remove("sec_$key")
                            .apply()
                    }
                    result.success(true)
                }

                "clearAllSecure" -> {
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .clear()
                        .apply()
                    result.success(true)
                }

                "getDeviceModel" -> {
                    val model = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
                    result.success(model)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playBeep" -> {
                    val durationMs = call.argument<Int>("durationMs") ?: 120
                    try {
                        if (toneGenerator == null) {
                            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 95)
                        }
                        toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, durationMs)
                    } catch (_: Exception) {}
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        toneGenerator?.release()
        toneGenerator = null
        cryptoExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun getOrCreateKey(): SecretKey {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            val existing = ks.getKey(KEK_ALIAS, null) as? SecretKey
            if (existing != null) return existing

            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
            val spec = KeyGenParameterSpec.Builder(
                KEK_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
            gen.init(spec)
            return gen.generateKey()
        }
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_LEGACY_AES, null)
        val raw = if (!existing.isNullOrEmpty()) {
            Base64.decode(existing, Base64.NO_WRAP)
        } else {
            ByteArray(32).also {
                SecureRandom().nextBytes(it)
                prefs.edit().putString(KEY_LEGACY_AES, Base64.encodeToString(it, Base64.NO_WRAP)).apply()
            }
        }
        return SecretKeySpec(raw, "AES")
    }

    private fun encryptValue(plaintext: String): String {
        val key = getOrCreateKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val iv = cipher.iv
        val ct = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return "v1:${Base64.encodeToString(iv, Base64.NO_WRAP)}:${Base64.encodeToString(ct, Base64.NO_WRAP)}"
    }

    private fun decryptValue(envelope: String): String {
        if (!envelope.startsWith("v1:")) {
            throw IllegalArgumentException("Malformed secure credential envelope")
        }
        val parts = envelope.split(":", limit = 3)
        if (parts.size != 3) throw IllegalArgumentException("Malformed secure credential envelope")
        val iv = Base64.decode(parts[1], Base64.NO_WRAP)
        val ct = Base64.decode(parts[2], Base64.NO_WRAP)
        val key = getOrCreateKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        return String(cipher.doFinal(ct), Charsets.UTF_8)
    }
}
