import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AttachmentsScreen extends StatelessWidget {
  const AttachmentsScreen({super.key});

  static const List<_SupportItem> _items = [
    _SupportItem(
      title: 'تطبيق الدعم الفني',
      type: 'تطبيق',
      description: 'تحميل تطبيق الدعم لحل المشاكل.',
      url: 'https://example.com/support-app',
      icon: Icons.apps,
    ),
    _SupportItem(
      title: 'شرح الاتصال بالماكينة',
      type: 'فيديو',
      description: 'فيديو يشرح طريقة الربط.',
      url: 'https://example.com/how-to-connect',
      icon: Icons.play_circle_fill,
    ),
    _SupportItem(
      title: 'حل مشكلة القص',
      type: 'فيديو',
      description: 'فيديو لحل مشكلة التقطيع.',
      url: 'https://example.com/cut-fix',
      icon: Icons.play_circle_fill,
    ),
    _SupportItem(
      title: 'صورة توضيحية للإعدادات',
      type: 'صورة',
      description: 'صورة توضيحية للخطوات.',
      url: 'https://example.com/settings-image',
      icon: Icons.image,
    ),
  ];

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError(context, 'الرابط غير صحيح.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _showError(context, 'تعذّر فتح الرابط.');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('ملحقات'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF00FF88),
                child: Icon(item.icon, color: Colors.black),
              ),
              title: Text(
                item.title,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                '${item.type} • ${item.description}',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: const Icon(Icons.open_in_new, color: Colors.grey),
              onTap: () => _openLink(context, item.url),
            ),
          );
        },
      ),
    );
  }
}

class _SupportItem {
  final String title;
  final String type;
  final String description;
  final String url;
  final IconData icon;

  const _SupportItem({
    required this.title,
    required this.type,
    required this.description,
    required this.url,
    required this.icon,
  });
}
