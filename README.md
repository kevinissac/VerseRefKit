# VerseRefKit

## What is this package?

A multi-language Bible reference parser for Android (Kotlin/JVM) and iOS (Swift). It
converts between USFM (`GEN.1.2`, `1CO.3.4`) and readable references, and finds
references inside free text, in whichever supported language the text is written. Both
platforms read the same book data and pass the same test cases, so they behave identically.

## Installation

### Android (Kotlin/JVM) — via [JitPack](https://jitpack.io)

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        maven("https://jitpack.io")
    }
}

// build.gradle.kts
dependencies {
    implementation("com.github.kevinissac:VerseRefKit:v0.1.0")
}
```

### iOS / macOS (Swift Package Manager)

In Xcode choose **File → Add Package Dependencies…** and enter
`https://github.com/kevinissac/VerseRefKit`, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kevinissac/VerseRefKit", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "VerseRefKit", package: "VerseRefKit")]),
]
```

## Languages supported

- [x] English
- [x] Malayalam
- [ ] Tamil (soon)
- [ ] Hindi (soon)

## Docs

### Usage

The main entry point is `VerseRef` on both platforms (Swift module: `VerseRefKit`).

Kotlin:

```kotlin
import com.kevinissac.verserefkit.VerseRef

VerseRef.usfm("1 Cor 3:4")          // "1CO.3.4"
VerseRef.usfm("റോമർ 8:28")          // "ROM.8.28"
VerseRef.humanReadable("ROM.8.28")  // "Romans 8:28"
VerseRef.findReferenceSpans("see Rom 8:28-30")  // [(range, "Rom 8:28-30")]
```

Swift:

```swift
import VerseRefKit

VerseRef.usfm(from: "1 Cor 3:4")            // "1CO.3.4"
VerseRef.usfm(from: "റോമർ 8:28")            // "ROM.8.28"
VerseRef.humanReadable(from: "ROM.8.28")    // "Romans 8:28"
VerseRef.findReferenceSpans(in: "see Rom 8:28-30")  // [ReferenceSpan(range:, text: "Rom 8:28-30")]
```

Full names and common abbreviations are recognised, case-insensitively and with flexible
whitespace. Numbered books start with a digit (`"1 Cor"`).

### Adding a language

1. Add `data/languages/<code>.json` (see `ml.json`): a map of USFM book code to names and
   abbreviations.
2. Run `python3 tools/generate.py` to regenerate the Kotlin and Swift tables.
3. Add cases for the new language to `data/tests/*.tsv`, then run both test suites.

### Development

```
python3 tools/generate.py        # after editing anything in data/
./gradlew :verserefkit-android:test # Kotlin
swift test                       # Swift
```

## Layout

```
data/            book names, verse counts and shared test cases
tools/           generate.py — builds the Kotlin and Swift tables from data/
android/         Kotlin library (verserefkit-android)
Sources/VerseRefKit  Swift library
```

## License

MIT — see [LICENSE](LICENSE).
