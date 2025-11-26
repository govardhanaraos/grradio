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

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Mediation adapters
-keep class com.google.ads.mediation.** { *; }
-keep class * implements com.google.ads.mediation.MediationAdapter { *; }
-keep class * implements com.google.ads.mediation.MediationBannerAdapter { *; }
-keep class * implements com.google.ads.mediation.MediationInterstitialAdapter { *; }
-keep class * implements com.google.ads.mediation.MediationNativeAdapter { *; }

# For AppLovin mediation (if used)
-keep class com.applovin.** { *; }

# For Facebook mediation (if used)
-keep class com.facebook.ads.** { *; }

# Keep relevant data for analytics
-keep class * extends java.util.ListResourceBundle {
    protected Object[][] getContents();
}

-keep public class com.google.android.gms.common.internal.safeparcel.SafeParcelable {
    public static final *** NULL;
}

-keepnames @com.google.android.gms.common.annotation.KeepName class *
-keepclassmembernames class * {
    @com.google.android.gms.common.annotation.KeepName *;
}

-keepnames class * implements android.os.Parcelable {
    public static final ** CREATOR;
}