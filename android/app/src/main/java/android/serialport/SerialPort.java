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

    public SerialPort(File device, int baudrate, int flags) throws SecurityException, IOException {
        if (!device.canRead() || !device.canWrite()) {
            try {
                Process su = Runtime.getRuntime().exec(sSuPath);
                su.getOutputStream().write(("chmod 666 " + device.getAbsolutePath() + "\nexit\n").getBytes());
                if (su.waitFor() != 0 || !device.canRead() || !device.canWrite()) {
                    throw new SecurityException();
                }
            } catch (Exception e) {
                e.printStackTrace();
                throw new SecurityException();
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
