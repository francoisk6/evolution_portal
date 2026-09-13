# App-specific R8 / ProGuard rules.
#
# Most of what matters is supplied automatically:
#   - Flutter engine rules come from the Flutter Gradle plugin
#   - Plugins ship consumer rules in their own AARs
# Dart code is AOT-compiled and never passes through R8, so only Android/Kotlin
# glue is at risk here - typically anything reached purely by reflection.

# Entry point named in AndroidManifest.
-keep class com.evolution_portal.** { *; }

# Flutter embedding: belt and braces. Deferred components and the split-install
# shim are referenced reflectively and warn if absent.
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.android.play.core.**

# Keep annotations and signatures so reflection and generics still resolve.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Readable crash reports: keep line numbers, hide the original file name.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
