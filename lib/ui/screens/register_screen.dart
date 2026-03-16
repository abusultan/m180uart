import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_service.dart';
import '../../core/app_strings.dart';
import '../../data/models/representative_model.dart';
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _locationController = TextEditingController();
  final _machineSerialController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  static const List<String> _machineTypes = [
    'sunshine',
    'crust',
    'rockspace',
    'mechanic',
    'atb',
  ];
  bool _isLoading = false;
  String? _error;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  String _machineOwnership = 'owner';
  bool _loadingReps = false;
  List<Representative> _representatives = [];
  int? _selectedRepresentativeId;
  String? _selectedMachineType;

  @override
  void initState() {
    super.initState();
    _loadRepresentatives();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _locationController.dispose();
    _machineSerialController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadRepresentatives() async {
    setState(() => _loadingReps = true);
    try {
      final reps = await ApiService().getRepresentatives();
      if (!mounted) return;
      setState(() {
        _representatives = reps;
        _loadingReps = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReps = false);
    }
  }

  Widget _buildRepresentativeDropdown() {
    final list = _representatives;

    return DropdownButtonFormField<int>(
      value: _selectedRepresentativeId,
      hint: Text(
        AppStrings.of(context, 'select_representative'),
        style: const TextStyle(color: Colors.grey),
      ),
      items: list
          .map(
            (rep) => DropdownMenuItem(
              value: rep.id,
              child: Text(rep.displayName),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() => _selectedRepresentativeId = value);
      },
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: InputDecoration(
        labelText: AppStrings.of(context, 'select_representative'),
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(
          Icons.badge,
          color: Color(0xFF00FF88),
        ),
      ),
      style: const TextStyle(color: Colors.white),
      validator: (value) {
        if (value == null) {
          return AppStrings.of(context, 'error_representative_required');
        }
        return null;
      },
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final address = _addressController.text.trim();
      final machineType = _selectedMachineType?.trim() ?? '';
      final machineSerial = _machineSerialController.text.trim();
      final pass = _passwordController.text.trim();
      final confirmPass = _confirmPasswordController.text.trim();
      final registrationLocation = _locationController.text.trim().isEmpty
          ? address
          : _locationController.text.trim();

      final response = await ApiService().register(
        name,
        email,
        phone,
        address,
        pass,
        confirmPass,
        machineType: machineType,
        machineSerial: machineSerial,
        machineOwnership: _machineOwnership,
        distributorId: _selectedRepresentativeId,
        location: registrationLocation,
      );

      if (response.success) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (Route<dynamic> route) => false,
        );
      } else {
        setState(() => _error = response.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00FF88)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.of(context, 'create_account'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),

                // Name
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'name'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.person,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 3) {
                      return AppStrings.of(context, 'error_name_length');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'email'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.email,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.of(context, 'error_email_empty');
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return AppStrings.of(context, 'error_email_invalid');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'phone'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.phone,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.of(context, 'error_phone_empty');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Address
                TextFormField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'address'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.location_on,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.of(context, 'error_address_empty');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _locationController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'location'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.my_location,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Machine Type
                DropdownButtonFormField<String>(
                  initialValue: _selectedMachineType,
                  items: _machineTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedMachineType = value);
                  },
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'machine_type'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.precision_manufacturing,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.of(context, 'error_generic');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Representative
                if (_loadingReps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppStrings.of(context, 'loading_representatives'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else
                  _buildRepresentativeDropdown(),
                if (!_loadingReps && _representatives.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      AppStrings.of(context, 'no_representatives'),
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                const SizedBox(height: 16),

                // Machine Serial
                TextFormField(
                  controller: _machineSerialController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'machine_serial'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.confirmation_number,
                      color: Color(0xFF00FF88),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.grey,
                      ),
                      onPressed: () async {
                        final String? scanned = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const _SerialScanScreen(),
                          ),
                        );
                        if (scanned != null && scanned.isNotEmpty) {
                          _machineSerialController.text = scanned;
                        }
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.of(context, 'error_generic');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Machine Ownership
                DropdownButtonFormField<String>(
                  value: _machineOwnership,
                  items: [
                    DropdownMenuItem(
                      value: 'owner',
                      child: Text(AppStrings.of(context, 'ownership_owner')),
                    ),
                    DropdownMenuItem(
                      value: 'rent',
                      child: Text(AppStrings.of(context, 'ownership_rent')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _machineOwnership = value);
                  },
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'machine_ownership'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.home_work,
                      color: Color(0xFF00FF88),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'password'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock,
                      color: Color(0xFF00FF88),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _passwordVisible = !_passwordVisible;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return AppStrings.of(context, 'error_password_length');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_confirmPasswordVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'confirm_password'),
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF00FF88),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _confirmPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _confirmPasswordVisible = !_confirmPasswordVisible;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return AppStrings.of(context, 'error_password_match');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),

                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF88),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : Text(
                            AppStrings.of(context, 'register_button'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SerialScanScreen extends StatefulWidget {
  const _SerialScanScreen();

  @override
  State<_SerialScanScreen> createState() => _SerialScanScreenState();
}

class _SerialScanScreenState extends State<_SerialScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _found = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Serial'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_found) return;
              final barcode =
                  capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
              final raw = barcode?.rawValue?.trim();
              if (raw != null && raw.isNotEmpty) {
                _found = true;
                Navigator.of(context).pop(raw);
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                'وجّه الكاميرا على QR أو Barcode',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
