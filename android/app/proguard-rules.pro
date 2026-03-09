# Keep JNI-bound serial classes and members stable.
-keep class android.serialport.** { *; }
-keepclasseswithmembers class android.serialport.SerialPort {
    native <methods>;
}
-keepclassmembers class android.serialport.SerialPort {
    java.io.FileDescriptor mFd;
    java.io.FileInputStream mFileInputStream;
    java.io.FileOutputStream mFileOutputStream;
}
