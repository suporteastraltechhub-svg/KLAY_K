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
    try {
        afterEvaluate {
            if (project.plugins.hasPlugin("com.android.library") || project.plugins.hasPlugin("com.android.application")) {
                try {
                    val androidExt = project.extensions.getByName("android")
                    androidExt.javaClass.getMethod("setNdkVersion", String::class.java)
                        .invoke(androidExt, "29.0.14206865")
                } catch (_: Exception) {
                }
            }
        }
    } catch (_: Exception) {
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
