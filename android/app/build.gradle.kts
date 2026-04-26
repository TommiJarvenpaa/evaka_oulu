plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun gitVersionCode(): Int {
    return Runtime.getRuntime().exec(arrayOf("git", "rev-list", "HEAD", "--count"))
        .inputStream.bufferedReader().readText().trim().toIntOrNull() ?: 1
}

fun gitVersionName(): String {
    val tag = Runtime.getRuntime().exec(arrayOf("git", "describe", "--tags", "--abbrev=0"))
        .inputStream.bufferedReader().readText().trim()
    if (tag.isEmpty()) return "0.1.${gitVersionCode()}"
    val commitsSinceTag = Runtime.getRuntime().exec(arrayOf("git", "rev-list", "$tag..HEAD", "--count"))
        .inputStream.bufferedReader().readText().trim().toIntOrNull() ?: 0
    return "$tag.$commitsSinceTag"
}

android {
    namespace = "fi.tommijarvenpaa.evaka_oulu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "fi.tommijarvenpaa.evaka_oulu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = gitVersionCode()
        versionName = gitVersionName()
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    applicationVariants.all {
        outputs.all {
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl).outputFileName =
                "eVaka-Oulu-${versionName}.apk"
        }
    }
}

flutter {
    source = "../.."
}
