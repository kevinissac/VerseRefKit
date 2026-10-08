pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

rootProject.name = "VerseRefKit"

include(":verserefkit-android")
project(":verserefkit-android").projectDir = file("android")
