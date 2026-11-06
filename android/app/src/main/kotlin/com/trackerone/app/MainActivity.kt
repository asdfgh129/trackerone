package com.trackerone.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // 极光厂商通道点击会触发 Flutter 自动深链，在 3.29+ 上表现为白屏。
    // 深链由 app_links 统一处理，这里关闭引擎的自动接管。
    override fun shouldHandleDeeplinking(): Boolean = false
}
