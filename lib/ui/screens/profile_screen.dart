import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_strings.dart';
import '../../core/machine_handshake.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../providers/language_provider.dart';
import 'login_screen.dart';
import 'cut_settings_screen.dart';
import 'cart_screen.dart';
import 'attachments_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const String _testFileUrl =
      'http://www.cutabc.cn:8091/Userfile/Attach/25032415-1430.plt';

  void _requestRepresentative(BuildContext context) {
    final user = ApiService().currentUser;
    final repName = user?.representativeName ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          AppStrings.of(context, 'request_rep'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          repName.isEmpty
              ? AppStrings.of(context, 'no_rep_found')
              : '${AppStrings.of(context, 'rep_notification_msg')}$repName',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.of(context, 'cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          if (repName.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppStrings.of(context, 'notification_sent')),
                    backgroundColor: const Color(0xFF00FF88),
                  ),
                );
              },
              child: Text(
                AppStrings.of(context, 'send'),
                style: const TextStyle(color: Color(0xFF00FF88)),
              ),
            ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          AppStrings.of(context, 'logout_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          AppStrings.of(context, 'logout_confirm'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.of(context, 'cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              CutterBluetoothService().disconnect();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) => false,
              );
            },
            child: Text(
              AppStrings.of(context, 'logout'),
              style: const TextStyle(
                color: Color(0xFF00FF88),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _performHandshakeSync() async {
    final cutter = CutterBluetoothService();
    final serial = (cutter.serialNumber ?? '').trim();

    String? preferred = MachineHandshake.normalizeAlgorithm(
      cutter.successfulHandshakeType,
    );
    if ((preferred == null || preferred.isEmpty) && serial.isNotEmpty) {
      preferred = MachineHandshake.normalizeAlgorithm(
        await cutter.getCachedHandshake(serial),
      );
    }

    final completer = Completer<bool>();
    final handshake = MachineHandshake(
      cutter,
      preferredAlgorithm: preferred,
      handshakeMode: 'sync',
      persistOnSuccess: true,
      onStatusUpdate: (_) {},
      onHandshakeComplete: (success) {
        if (!completer.isCompleted) completer.complete(success);
      },
    );
    handshake.startHandshake();
    try {
      final timeoutSeconds =
          preferred == MachineHandshake.algoRockspace ? 25 : 20;
      return await completer.future.timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () => false,
      );
    } finally {
      handshake.dispose();
    }
  }

  Future<void> _sendTestFile(BuildContext context) async {
    final cutter = CutterBluetoothService();
    if (!cutter.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('السيريال غير متصل'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    // Always run handshake before sending to ensure the session is authenticated.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'جاري تحميل الملف وإرساله...',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final serial = cutter.serialNumber?.toUpperCase() ?? '';
      final isPlt = serial.startsWith("DQ") ||
          serial.startsWith("DX") ||
          serial.startsWith("LH");
      final ok = await _performHandshakeSync();
      if (!ok) {
        throw Exception('فشل الهاند شيك');
      }

      final isPhonefilmMode = cutter.lastHandshakeMode == 'phonefilm';

      final file = await ApiService().downloadFile(_testFileUrl);
      if (file == null) {
        throw Exception('فشل تنزيل الملف');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('ملف فارغ');
      }

      if (isPlt) {
        await cutter.writeBytes(
          bytes,
          chunkSize: bytes.length,
          packetDelayMs: 0,
        );
      } else {
        final blockSize = 2048;
        final delayMs = isPhonefilmMode ? 400 : 2;
        int offset = 0;
        while (offset < bytes.length) {
          int end = offset + blockSize;
          if (end > bytes.length) end = bytes.length;
          final chunk = bytes.sublist(offset, end);
          await cutter.writeBytes(
            chunk,
            chunkSize: chunk.length,
            packetDelayMs: 0,
          );
          if (delayMs > 0) {
            await Future.delayed(Duration(milliseconds: delayMs));
          }
          offset = end;
        }
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال الملف بنجاح'),
            backgroundColor: Color(0xFF00FF88),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الإرسال: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'profile')),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFF1E1E1E),
              child: Icon(Icons.person, size: 60, color: Color(0xFF00FF88)),
            ),
            const SizedBox(height: 24),
            Text(
              user?.name ?? AppStrings.of(context, 'guest'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              user?.email ?? "",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            _buildInfoTile(
              Icons.phone,
              AppStrings.of(context, 'phone'),
              user?.phone ?? "N/A",
            ),
            _buildInfoTile(
              Icons.location_on,
              AppStrings.of(context, 'address'),
              user?.address ?? "N/A",
            ),
            _buildInfoTile(
              Icons.confirmation_number,
              AppStrings.of(context, 'remaining_pieces'),
              user?.remainingPieces.toString() ?? "0",
            ),
            const SizedBox(height: 16),
            ListTile(
              tileColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(
                Icons.shopping_cart,
                color: Color(0xFF00FF88),
              ),
              title: Text(
                AppStrings.of(context, 'product_cart'),
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CartScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              tileColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(
                Icons.notifications_active,
                color: Color(0xFF00FF88),
              ),
              title: Text(
                AppStrings.of(context, 'request_rep'),
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _requestRepresentative(context),
            ),
            const SizedBox(height: 16),
            ListTile(
              tileColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.link, color: Color(0xFF00FF88)),
              title: Text(
                AppStrings.of(context, 'attachments'),
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AttachmentsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              tileColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.send, color: Color(0xFF00FF88)),
              title: const Text(
                'إرسال ملف تجريبي للماكينة',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'يرسل الملف مباشرة عبر السيريال',
                style: TextStyle(color: Colors.grey),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _sendTestFile(context),
            ),
            const SizedBox(height: 16),
            ListTile(
              tileColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.tune, color: Color(0xFF00FF88)),
              title: Text(
                AppStrings.of(context, 'cut_settings'),
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CutSettingsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // Language Selection
            Text(
              AppStrings.of(context, 'language'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLanguageButton(
                  context,
                  languageProvider,
                  'English',
                  'en',
                ),
                const SizedBox(width: 16),
                _buildLanguageButton(
                  context,
                  languageProvider,
                  'العربية',
                  'ar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageButton(
    BuildContext context,
    LanguageProvider provider,
    String label,
    String code,
  ) {
    final bool isSelected = provider.locale?.languageCode == code ||
        (provider.locale == null &&
            Localizations.localeOf(context).languageCode == code);

    return ElevatedButton(
      onPressed: () {
        provider.setLocale(Locale(code));
      },
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isSelected ? const Color(0xFF00FF88) : const Color(0xFF1E1E1E),
        foregroundColor: isSelected ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(label),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00FF88)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
