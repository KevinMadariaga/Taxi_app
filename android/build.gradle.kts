import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")

    // Set Java 17 via the Android extension so plugins that explicitly override
    // sourceCompatibility (e.g. flutter_image_compress_common with VERSION_11) can still do so.
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    // Only set Kotlin jvmTarget when the plugin has not explicitly configured one.
    // This overrides KGP 2.x's JDK-inferred default (JDK 21 → jvmTarget 21) for plugins
    // that leave jvmTarget unset, without overriding plugins like flutter_image_compress_common
    // whose explicit kotlinOptions { jvmTarget = '11' } translates to an explicit set().
    tasks.withType<KotlinCompile>().configureEach {
        if (!compilerOptions.jvmTarget.isPresent) {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
