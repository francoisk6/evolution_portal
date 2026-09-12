import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties from android/key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.evolution_portal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.evolution_portal"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One flavor per distributable app. "main" is the existing multi-workspace
    // build and MUST keep applicationId com.evolution_portal - that id is fixed
    // for the life of the Play listing. Standalone tenants get their own id and
    // install alongside it.
    //
    // Note: once flavors exist, a bare `flutter build apk` fails. Every build
    // needs --flavor, and the workspace lock is passed via --dart-define:
    //
    //   flutter build apk --flavor portal
    //   flutter build apk --flavor dmp \
    //     --dart-define=WORKSPACE_SLUG=dmp \
    //     --dart-define=WORKSPACE_NAME=DMP \
    //     --dart-define=API_BASE_URL=https://dmpapi.evolution-portal.com
    flavorDimensions += "workspace"

    productFlavors {
        // Not named "main": that collides with Gradle's built-in `main`
        // source set and fails configuration.
        create("portal") {
            dimension = "workspace"
            // No suffix: this is the published app.
            resValue("string", "app_name", "Evolution Portal")
        }
        create("dmp") {
            dimension = "workspace"
            applicationIdSuffix = ".dmp"
            resValue("string", "app_name", "DMP")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // Use your release keystore (NOT debug)
            signingConfig = signingConfigs.getByName("release")

            // R8 on: Play flags DEX optimization below threshold when this is
            // off. Only the Android/Kotlin side is affected - Dart code is
            // AOT-compiled and untouched - so the blast radius is plugin glue
            // reached by reflection. Plugins ship their own consumer rules;
            // app-specific keeps go in proguard-rules.pro.
            //
            // Keep build/app/outputs/mapping/<flavor>Release/mapping.txt for
            // each release or crash reports come back unreadable.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

android.applicationVariants.all {
    outputs.all {
        val appName = "evolution"
        val vName = versionName
        val vCode = versionCode
        @Suppress("UnstableApiUsage")
        (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl).outputFileName =
            "${appName}-${name}-v${vName}+${vCode}.apk"
    }
}
