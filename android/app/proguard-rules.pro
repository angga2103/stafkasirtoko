# R8 optimization & ML Kit barcode scanning keep rules for KasirToko Staff
-keep class com.google.mlkit.** { *; }
-keepclassmembers class * { @com.google.mlkit.** <methods>; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn java.lang.invoke.**
-dontwarn com.google.errorprone.annotations.**
