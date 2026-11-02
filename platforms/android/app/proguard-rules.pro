# Keep JNI entry points and the policy bridge.
-keep class com.autowifi.policy.PolicyEngine { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
