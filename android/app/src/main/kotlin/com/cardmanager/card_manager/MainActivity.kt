package com.cardmanager.card_manager

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cardmanager.card_manager/ocr"
    private val REQUEST_CODE_OCR = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startOcrScan") {
                pendingResult = result
                val intent = Intent(this, ScanActivity::class.java)
                startActivityForResult(intent, REQUEST_CODE_OCR)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_OCR) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val jsonResult = data.getStringExtra("ocr_result")
                pendingResult?.success(jsonResult)
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }
}
