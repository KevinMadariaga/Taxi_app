import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { stream ->
        keystoreProperties.load(stream)
    }
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        localProperties.load(stream)
    }
}

fun resolveStoreFile(path: String?): java.io.File? {
    if (path.isNullOrBlank()) return null
    val candidate = file(path)
    if (candidate.isAbsolute) return candidate

    val fromRoot = rootProject.file(path)
    return if (fromRoot.exists()) fromRoot else candidate
}

val releaseStoreFile = resolveStoreFile(keystoreProperties.getProperty("storeFile"))

val mapsApiKey = sequenceOf(
    project.findProperty("MAPS_API_KEY") as String?,
    localProperties.getProperty("MAPS_API_KEY"),
    System.getenv("MAPS_API_KEY")
).firstOrNull { !it.isNullOrBlank() } ?: ""

val isReleaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

fun hasReleaseSigningConfig(): Boolean {
    return releaseStoreFile?.exists() == true &&
        listOf("storePassword", "keyAlias", "keyPassword")
            .all { !keystoreProperties.getProperty(it).isNullOrBlank() }
}

if (isReleaseBuildRequested && !hasReleaseSigningConfig()) {
    throw GradleException(
        "Release signing is not configured. Create android/key.properties based on android/key.properties.example and provide a valid keystore."
    )
}

if (isReleaseBuildRequested && mapsApiKey.isBlank()) {
    throw GradleException(
        "MAPS_API_KEY is missing for release build. Define it in local.properties, gradle.properties, or as environment variable MAPS_API_KEY."
    )
}

android {
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
    }
    namespace = "com.taxiya.taxiapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Enable core library desugaring for libraries that require Java language
        // features on older Android runtimes (required by some plugins).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.taxiya.taxiapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigningConfig()) {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (hasReleaseSigningConfig()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required for core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("org.apache.httpcomponents:httpclient:4.5.13")
    // WorkManager: encola la cancelación server-side de la solicitud desde
    // MainActivity.onTaskRemoved. Persiste el job en su propia base de datos,
    // así que sobrevive a que Android mate el proceso justo después.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
