import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Podpis APK.
// 1) Jeżeli istnieje android/key.properties (NIE commitowany) albo zmienne
//    środowiskowe CZYTAMSAM_KEYSTORE / CZYTAMSAM_KEYSTORE_PASSWORD /
//    CZYTAMSAM_KEY_ALIAS / CZYTAMSAM_KEY_PASSWORD (np. z GitHub Secrets),
//    używany jest PRYWATNY klucz wydania.
// 2) W przeciwnym razie używany jest JAWNY, PUBLICZNY klucz testowy
//    android/keystore/czytamsam-public-test.jks. Jest stały (aktualizacje
//    kolejnych wersji testowych zachowują dane), ale NIE jest tajny.
//    Patrz README_PL.md, rozdział „Podpis i aktualizacje”.
// ---------------------------------------------------------------------------
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(propKey: String, envKey: String): String? =
    keyProps.getProperty(propKey) ?: System.getenv(envKey)?.takeIf { it.isNotBlank() }

val privateStore = signingValue("storeFile", "CZYTAMSAM_KEYSTORE")
val usePrivateKey = privateStore != null && file(privateStore).exists()

android {
    namespace = "pl.czytamsam.czytam_sam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // STAŁY identyfikator aplikacji – nie zmieniać (zmiana = inna aplikacja,
        // utrata możliwości aktualizacji z zachowaniem danych).
        applicationId = "pl.czytamsam.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("publicTest") {
            storeFile = file("../keystore/czytamsam-public-test.jks")
            storePassword = "czytamsam-test"
            keyAlias = "czytamsam-test"
            keyPassword = "czytamsam-test"
        }
        if (usePrivateKey) {
            create("privateRelease") {
                storeFile = file(privateStore!!)
                storePassword = signingValue("storePassword", "CZYTAMSAM_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "CZYTAMSAM_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "CZYTAMSAM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("publicTest")
        }
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (usePrivateKey) {
                signingConfigs.getByName("privateRelease")
            } else {
                signingConfigs.getByName("publicTest")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Lokalne rozpoznawanie mowy (Apache-2.0). Model językowy NIE jest
    // dołączany – opiekun importuje go z pliku (patrz README_PL.md).
    implementation("com.alphacephei:vosk-android:0.3.75@aar") // @aar: bez zależności przechodnich (JNA w wersji aar poniżej)
    implementation("net.java.dev.jna:jna:5.18.1@aar")
}

flutter {
    source = "../.."
}
