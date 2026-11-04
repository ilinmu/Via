# Keep JNI entry points and the policy bridge.
-keep class io.github.ilinmu.via.policy.PolicyEngine { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Tink (pulled in by androidx.security:security-crypto) annotates its classes
# with error-prone and JSR-305 annotations that only exist at compile time.
# R8 full mode treats the missing classes as errors, so ignore them.
-dontwarn com.google.errorprone.annotations.**
-dontwarn com.google.j2objc.annotations.**
-dontwarn javax.annotation.**
