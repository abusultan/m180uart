import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_strings.dart';
import 'package:flutter_project/core/serial/machine_handshake.dart';
import 'package:flutter_project/core/serial/mietubl_protocol.dart';
import 'package:flutter_project/core/serial/mietubl_cut_sender.dart';
import '../../services/api_service.dart';
import 'package:flutter_project/core/serial/serial_service.dart';
import '../../providers/language_provider.dart';
import 'login_screen.dart';
import 'cut_settings_screen.dart';
import 'attachments_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
              CutterSerialService().disconnect();
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
    final cutter = CutterSerialService();
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
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => false,
      );
    } finally {
      handshake.dispose();
    }
  }

  Future<void> _sendTestFile(BuildContext context) async {
    final cutter = CutterSerialService();
    if (!cutter.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الماكينة غير متصلة - اذهب لشاشة الاتصال أولاً'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        content: const Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('جاري إرسال القصة التجريبية...', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );

    try {
      // Run handshake first
      final ok = await _performHandshakeSync();
      if (!ok) throw Exception('فشل الهاند شيك');

      // Real PLT cut file (Samsung 2017 半包前膜) embedded directly
      const String testPlt = 'IN;PA;PU1405,339;PD1412,336;PD1426,352;PD1428,348;PD1448,352;PD1511,351;PD1534,343;PD1552,326;PD1562,304;PD1563,280;PD1554,257;PD1538,239;PD1516,229;PD1491,228;PD601,228;PD578,237;PD561,253;PD550,275;PD550,300;PD558,323;PD575,340;PD597,351;PD621,351;PD1448,351;PD1508,351;PU1778,249;PD1775,243;PD1769,240;PD1762,241;PD1752,223;PD1748,227;PD1730,216;PD1729,223;PD1705,230;PD1686,248;PD1675,271;PD1674,296;PD1683,320;PD1700,339;PD1723,350;PD1749,351;PD1773,342;PD1792,325;PD1803,302;PD1804,276;PD1795,252;PD1778,233;PD1755,222;PD1729,222;PD1705,230;PD1685,247;PD1681,255;PU74,89;PD81,91;PD81,291;PD81,4620;PD88,4618;PD91,4610;PD2327,4610;PD2324,4602;PD2317,4599;PD2317,271;PD2312,238;PD2301,208;PD2284,181;PD2261,156;PD2234,136;PD2205,123;PD2174,116;PD2140,115;PD237,115;PD204,120;PD174,131;PD147,148;PD123,170;PD103,197;PD89,226;PD82,258;PD81,291;PD81,411;PU2316,0;!PG;';

      // Convert PLT text to bytes (each character → its byte value)
      final pltBytes = testPlt.codeUnits;

      // Convert to hex string (same as Arrays.byteArrayToHexStr in Java)
      final hexData = pltBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

      // Use MietublCutSender to send with proper protocol framing
      final sender = MietublCutSender(
        cutter,
        onProgress: (p) => debugPrint('TestCut progress: $p%'),
        onStatus: (s) => debugPrint('TestCut: $s'),
      );

      final success = await sender.sendCutFromBltFile(hexData, fileName: 'test.plt');

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'تم إرسال القصة ✅ - الماكينة تقص الآن' : 'فشل الإرسال'),
            backgroundColor: success ? const Color(0xFF00FF88) : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.redAccent),
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
