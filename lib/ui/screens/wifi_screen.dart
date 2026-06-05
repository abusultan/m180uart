import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  static const _channel = MethodChannel('wifi_manager');

  List<Map<String, dynamic>> _networks = [];
  Map<String, dynamic>? _currentWifi;
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingSsid;

  @override
  void initState() {
    super.initState();
    _loadCurrentWifi();
    _scan();
  }

  Future<void> _loadCurrentWifi() async {
    try {
      final result = await _channel.invokeMethod('getCurrentWifi');
      if (mounted) {
        setState(() {
          _currentWifi = Map<String, dynamic>.from(result as Map);
        });
      }
    } catch (_) {}
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final result = await _channel.invokeMethod('scanWifi');
      if (mounted) {
        final list = (result as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() => _networks = list);
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('Failed to scan WiFi networks', isError: true);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
      await _loadCurrentWifi();
    }
  }

  Future<void> _connect(String ssid, String password) async {
    setState(() {
      _connecting = true;
      _connectingSsid = ssid;
    });
    try {
      final success = await _channel.invokeMethod('connectWifi', {
        'ssid': ssid,
        'password': password,
      });
      if (mounted) {
        if (success == true) {
          _showSnackBar('Connected to $ssid');
        } else {
          _showSnackBar('Failed to connect to $ssid', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Connection error: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connectingSsid = null;
        });
      }
      await _loadCurrentWifi();
      await _scan();
    }
  }

  Future<void> _disconnect() async {
    try {
      await _channel.invokeMethod('disconnectWifi');
      if (mounted) _showSnackBar('Disconnected');
    } catch (_) {
      if (mounted) _showSnackBar('Failed to disconnect', isError: true);
    }
    await _loadCurrentWifi();
    await _scan();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF00FF88),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPasswordDialog(String ssid) {
    final controller = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                ssid,
                style: const TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white54,
                        ),
                        onPressed: () {
                          setDialogState(() => obscure = !obscure);
                        },
                      ),
                    ),
                    onSubmitted: (_) {
                      Navigator.pop(ctx);
                      _connect(ssid, controller.text);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _connect(ssid, controller.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF88),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onNetworkTap(Map<String, dynamic> network) {
    final ssid = network['ssid'] as String;
    final security = network['security'] as String;
    final isConnected = network['isConnected'] as bool? ?? false;

    if (isConnected) return;

    if (security == 'OPEN') {
      _connect(ssid, '');
    } else {
      _showPasswordDialog(ssid);
    }
  }

  IconData _signalIcon(int level) {
    if (level >= -50) return Icons.wifi;
    if (level >= -70) return Icons.wifi_2_bar;
    return Icons.wifi_1_bar;
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _currentWifi?['isConnected'] == true;
    final connectedSsid = _currentWifi?['ssid'] ?? '';
    final connectedIp = _currentWifi?['ip'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('WiFi'),
        backgroundColor: Colors.transparent,
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00FF88),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _scan,
            ),
        ],
      ),
      body: Column(
        children: [
          // Current connection card
          if (isConnected)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2E1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00FF88).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi, color: Color(0xFF00FF88), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connectedSsid,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Connected • $connectedIp',
                          style: const TextStyle(
                            color: Color(0xFF00FF88),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _disconnect,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                    ),
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),

          // Connecting overlay
          if (_connecting)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Connecting to $_connectingSsid...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // Available networks header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Text(
                  'Available Networks',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_networks.length} found',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),

          // Networks list
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF00FF88),
              backgroundColor: const Color(0xFF1E1E1E),
              onRefresh: _scan,
              child: _networks.isEmpty && !_scanning
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text(
                            'No networks found.\nPull down to scan.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _networks.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final network = _networks[index];
                        return _buildNetworkTile(network);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkTile(Map<String, dynamic> network) {
    final ssid = network['ssid'] as String;
    final level = network['level'] as int? ?? -100;
    final security = network['security'] as String? ?? 'OPEN';
    final isConnected = network['isConnected'] as bool? ?? false;
    final isCurrentlyConnecting = _connecting && _connectingSsid == ssid;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFF1A2E1A)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        onTap: isCurrentlyConnecting || _connecting
            ? null
            : () => _onNetworkTap(network),
        leading: Icon(
          _signalIcon(level),
          color: isConnected ? const Color(0xFF00FF88) : Colors.white54,
          size: 22,
        ),
        title: Text(
          ssid,
          style: TextStyle(
            color: isConnected ? const Color(0xFF00FF88) : Colors.white,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: isConnected
            ? const Text(
                'Connected',
                style: TextStyle(color: Color(0xFF00FF88), fontSize: 11),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (security != 'OPEN')
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.lock, size: 14, color: Colors.white38),
              ),
            if (isCurrentlyConnecting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00FF88),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
