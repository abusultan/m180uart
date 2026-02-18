package android.serialport;

import android.util.Log;
import java.io.File;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class SerialPort {
    private static final String TAG = "SerialPort";
    private static final String[] SU_CANDIDATES = new String[] {"/system/bin/su", "/system/xbin/su", "/su/bin/su"};
    private static String sSuPath = "/system/bin/su";
    private FileDescriptor mFd;
    private FileInputStream mFileInputStream;
    private FileOutputStream mFileOutputStream;

    private static native FileDescriptor open(String path, int baudrate, int flags);

    public native void close();

    public static void setSuPath(String path) {
        if (path != null) {
            sSuPath = path;
        }
    }

    private static String resolveSuPath() {
        File preferred = new File(sSuPath);
        if (preferred.exists() && preferred.canExecute()) {
            return preferred.getAbsolutePath();
        }

        for (String candidate : SU_CANDIDATES) {
            File f = new File(candidate);
            if (f.exists() && f.canExecute()) {
                return candidate;
            }
        }
        return null;
    }

    public SerialPort(File device, int baudrate, int flags) throws SecurityException, IOException {
        if (!device.canRead() || !device.canWrite()) {
            final String suPath = resolveSuPath();
            if (suPath != null) {
                try {
                    Process su = Runtime.getRuntime().exec(suPath);
                    su.getOutputStream().write(("chmod 666 " + device.getAbsolutePath() + "\nexit\n").getBytes());
                    su.waitFor();
                } catch (Exception e) {
                    Log.w(TAG, "chmod via su failed for " + device.getAbsolutePath() + ": " + e.getMessage());
                }
            } else {
                Log.w(TAG, "su not found; trying direct open for " + device.getAbsolutePath());
            }
        }
        FileDescriptor fd = open(device.getAbsolutePath(), baudrate, flags);
        this.mFd = fd;
        if (fd != null) {
            this.mFileInputStream = new FileInputStream(this.mFd);
            this.mFileOutputStream = new FileOutputStream(this.mFd);
            return;
        }
        Log.e(TAG, "native open returns null");
        throw new IOException();
    }

    public SerialPort(String path, int baudrate, int flags) throws SecurityException, IOException {
        this(new File(path), baudrate, flags);
    }

    public SerialPort(File device, int baudrate) throws SecurityException, IOException {
        this(device, baudrate, 0);
    }

    public SerialPort(String path, int baudrate) throws SecurityException, IOException {
        this(new File(path), baudrate, 0);
    }

    public InputStream getInputStream() {
        return this.mFileInputStream;
    }

    public OutputStream getOutputStream() {
        return this.mFileOutputStream;
    }

    static {
        System.loadLibrary("serial_port");
    }
}
