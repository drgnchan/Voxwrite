# Flutter plugins are registered by generated code. Preserve runtime metadata
# used by platform channels and JSON/network implementations.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-dontwarn org.conscrypt.**
