import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_strings.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../providers/language_provider.dart';
import 'login_screen.dart';
import 'cut_settings_screen.dart';
import 'cart_screen.dart';
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
    final bool isSelected =
        provider.locale?.languageCode == code ||
        (provider.locale == null &&
            Localizations.localeOf(context).languageCode == code);

    return ElevatedButton(
      onPressed: () {
        provider.setLocale(Locale(code));
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? const Color(0xFF00FF88)
            : const Color(0xFF1E1E1E),
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
