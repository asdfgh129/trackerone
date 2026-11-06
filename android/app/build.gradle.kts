import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：复制 android/key.properties.example 为 android/key.properties。
// 文件不存在时回退到 debug 签名，保证 `flutter run` 与 CI 自检可用。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseSigning = keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("storeFile").orEmpty().isNotEmpty()

android {
    namespace = "com.trackerone.app"
    // traccar_client_sdk 要求 compileSdk >= 37。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 使用 java.time，需要脱糖。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.trackerone.app"
        // traccar_client_sdk 要求 API 24+；目标 API 36。
        minSdk = 24
        targetSdk = 36

        // 极光推送占位配置：未配置时 PUSH_PROVIDER=none，不影响启动。
        // 正式构建请通过 -Pjpush.appKey=... 或 local.properties 注入。
        manifestPlaceholders["JPUSH_PKGNAME"] = applicationId!!
        manifestPlaceholders["JPUSH_APPKEY"] =
            (project.findProperty("jpush.appKey") as String?) ?: ""
        manifestPlaceholders["JPUSH_CHANNEL"] =
            (project.findProperty("jpush.channel") as String?) ?: "developer-default"
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 正式包必须使用 key.properties 中的上传密钥。
            // 缺失时由下面的 beforeVariants 直接失败，禁止回退 debug 签名。
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// 防止误把 debug 签名包当成 release 包发布。
androidComponents {
    beforeVariants(selector().withBuildType("release")) {
        check(hasReleaseSigning) {
            "缺少 android/key.properties 或 storeFile。拒绝构建 release 包；" +
                "请先按 docs/15 生成 upload-keystore.jks 并填写 key.properties。"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
