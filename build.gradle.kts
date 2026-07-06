// Świadomie użyto sprawdzonych, stabilnych wersji (AGP 8.6 / Kotlin 2.0), a nie najnowszych
// (AGP jest już w linii 9.x z nowym modelem "built-in Kotlin" — zbyt świeże, by pisać to na ślepo
// bez możliwości kompilacji testowej). Android Studio przy pierwszym otwarciu może zaproponować
// automatyczny upgrade Gradle/AGP — można to bezpiecznie zaakceptować.
plugins {
    id("com.android.application") version "8.6.0" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
}
