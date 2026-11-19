plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.favlib.favorites2"
    compileSdk = 37   // flutter_local_notifications و androidx.core 1.19 تتطلبان 37 (لا يغيّر الأجهزة المدعومة)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true   // مطلوب لـ flutter_local_notifications
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.favlib.favorites2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // توقيع ثابت كي تُثبَّت التحديثات فوق النسخة السابقة. المفتاح خارج git:
    // محليًا signing/release.keystore + signing/keystore.pass، وفي CI متغيرات البيئة KEYSTORE_FILE / KEYSTORE_PASS (أسرار GitHub).
    val ksFile = System.getenv("KEYSTORE_FILE")?.let { file(it) } ?: rootProject.file("../signing/release.keystore")
    val ksPass = System.getenv("KEYSTORE_PASS") ?: rootProject.file("../signing/keystore.pass").takeIf { it.exists() }?.readText()?.trim()
    signingConfigs {
        create("release") {
            if (ksFile.exists() && ksPass != null) {
                storeFile = ksFile; storePassword = ksPass; keyAlias = "favorites2"; keyPassword = ksPass
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (ksFile.exists() && ksPass != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}
