plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "io.github.ilinmu.via"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.ilinmu.via"
        minSdk = 29
        targetSdk = 35
        // CI passes -PbuildNumber=<run number> so the APK version matches the
        // release tag (v1.0.<run>); local builds fall back to 1.
        val buildNumber = (project.findProperty("buildNumber") as String?)?.toIntOrNull() ?: 1
        versionCode = buildNumber
        versionName = "1.0.$buildNumber"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    signingConfigs {
        create("release") {
            // CI publishes unsigned test APKs unless a keystore is configured.
            // Set these in the local environment or CI secrets; never commit
            // signing material.
            val store = System.getenv("VIA_RELEASE_KEYSTORE")
            if (!store.isNullOrBlank()) {
                storeFile = file(store)
                storePassword = System.getenv("VIA_RELEASE_STORE_PASSWORD")
                keyAlias = System.getenv("VIA_RELEASE_KEY_ALIAS")
                keyPassword = System.getenv("VIA_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Release artifacts are R8-shrunk: without it the unused Material
            // icons alone add tens of megabytes.
            isMinifyEnabled = true
            isShrinkResources = true
            // Without a configured keystore, Gradle leaves the APK unsigned
            // rather than publishing a package signed with the shared debug key.
            if (!System.getenv("VIA_RELEASE_KEYSTORE").isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
