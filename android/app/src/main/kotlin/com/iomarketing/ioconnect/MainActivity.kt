package com.iomarketing.ioconnect

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.iomarketing.whatsapp"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.iomarketing.whatsapp").setMethodCallHandler { call, result ->
            if (call.method == "openWhatsApp") {
                val phoneNumber = call.argument<String>("phone")
                if (phoneNumber != null) {
                    openWhatsApp(phoneNumber)
                    result.success(null)
                } else {
                    result.error("UNAVAILABLE", "Número de telefone não disponível", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openWhatsApp(phoneNumber: String) {
        try {
            val uri = Uri.parse("https://wa.me/$phoneNumber")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.setPackage("com.whatsapp")
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
            } else {
                // Caso o WhatsApp não esteja instalado, abre no navegador
                val browserIntent = Intent(Intent.ACTION_VIEW, uri)
                startActivity(browserIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
