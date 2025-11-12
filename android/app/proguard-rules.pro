# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Audio service rules
-keep class com.ryanheise.audioservice.** { *; }

# Keep audio session
-keep class com.ryanheise.audio_session.** { *; }

# Just audio rules
-keep class com.ryanheise.just_audio.** { *; }

# Mongo dart rules
-keep class com.mongodb.** { *; }
-keepclassmembers class com.mongodb.** { *; }