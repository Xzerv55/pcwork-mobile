allprojects {
    repositories {
        google()
        // Keep Kotlin artifacts on the Maven Central mirror instead of GitHub redirects.
        maven {
            url = uri("https://maven-central.storage-download.googleapis.com/maven2/")
            content {
                includeGroupByRegex("org\\.jetbrains\\.kotlin(\\..*)?")
            }
        }
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)
subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects { project.evaluationDependsOn(":app") }

tasks.register<Delete>("clean") { delete(rootProject.layout.buildDirectory) }
