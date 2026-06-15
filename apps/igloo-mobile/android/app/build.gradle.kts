plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.frostr.igloo"
    compileSdk = 35
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.frostr.igloo"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
            )
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources.excludes.addAll(
            listOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES"),
        )
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
        // Unit tests covering PollStatusParse helpers (the time-stamp null
        // handling for the Android save→dashboard path).
        getByName("test") {
            java.srcDirs("src/test/java")
        }
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            isIncludeAndroidResources = false
        }
    }
}

tasks.register("ensureUniffiGenerated") {
    doLast {
        val out = file("src/main/java/com/frostr/igloo/rust/igloo_mobile_core.kt")
        if (!out.exists()) {
            throw GradleException("Missing UniFFI Kotlin bindings. Run `rmp bindings kotlin` first.")
        }
    }
}

tasks.named("preBuild") {
    dependsOn("ensureUniffiGenerated")
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.3")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-text")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")

    debugImplementation("androidx.compose.ui:ui-tooling")

    // Secure storage (Keychain/Keystore-backed EncryptedSharedPreferences)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // UniFFI JNA
    implementation("net.java.dev.jna:jna:5.14.0@aar")

    // QR rendering for Distribute step (mobile-create-keyset-flow,
    // VAL-CREATE-015). zxing-core is the lightweight Kotlin-friendly target.
    implementation("com.google.zxing:core:3.5.3")

    // Local unit tests exercising PollStatusParse (the JSON null timestamp
    // helper used by AppManager.pollSignerStatus on the Android
    // save→dashboard path; mobile-android-onboard-save-poll-timer-fix).
    // `org.json` is supplied by the Android SDK at runtime, but the local
    // JVM test classpath needs a host-side implementation so the next worker
    // can run `:app:testDebugUnitTest` without booting an emulator.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}
