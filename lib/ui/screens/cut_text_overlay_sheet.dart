import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/cut_text_overlay_service.dart';
import '../../core/text_overlay_fonts.dart';

class CutTextOverlaySheetResult {
  const CutTextOverlaySheetResult({this.spec, this.cleared = false});

  final CutTextOverlaySpec? spec;
  final bool cleared;
}

Future<CutTextOverlaySheetResult?> showCutTextOverlaySheet(
  BuildContext context, {
  CutTextOverlaySpec? initialSpec,
}) {
  return showModalBottomSheet<CutTextOverlaySheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B1B1B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _CutTextOverlaySheet(initialSpec: initialSpec),
  );
}

class _CutTextOverlaySheet extends StatefulWidget {
  const _CutTextOverlaySheet({this.initialSpec});

  final CutTextOverlaySpec? initialSpec;

  @override
  State<_CutTextOverlaySheet> createState() => _CutTextOverlaySheetState();
}

class _CutTextOverlaySheetState extends State<_CutTextOverlaySheet> {
  late final TextEditingController _controller;
  late bool _flipHorizontally;
  late String _fontFamily;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSpec?.text ?? '');
    _flipHorizontally = widget.initialSpec?.flipHorizontally ?? false;
    _fontFamily = widget.initialSpec?.fontFamily ?? 'AdobeGothic';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = TextOverlayFonts.normalizeText(
      _controller.text,
      fontFamily: _fontFamily,
    );
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'text_overlay_error_empty')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      CutTextOverlaySheetResult(
        spec: CutTextOverlaySpec(
          text: normalized,
          dx: widget.initialSpec?.dx ?? 0,
          dy: widget.initialSpec?.dy ?? 0,
          scale: widget.initialSpec?.scale ?? 15.0,
          rotation: widget.initialSpec?.rotation ?? 0.0,
          flipHorizontally: _flipHorizontally,
          fontFamily: _fontFamily,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    String displayFontFamily = _fontFamily;
    if (displayFontFamily == 'AlibabaBlack') {
      displayFontFamily = 'AlibabaPuHuiTi';
    }

    return Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppStrings.of(context, 'text_overlay_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(context, 'text_overlay_subtitle'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                    color: Colors.white, fontFamily: displayFontFamily),
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'text_overlay_field'),
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: AppStrings.of(context, 'text_overlay_hint'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF00FF88)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _LabeledDropdown<String>(
                label: AppStrings.of(context, 'text_overlay_font'),
                value: _fontFamily,
                items: [
                  DropdownMenuItem(
                    value: 'AdobeGothic',
                    child: Text('Adobe Gothic',
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'AdobeGothic')),
                  ),
                  DropdownMenuItem(
                    value: 'AlibabaBlack',
                    child: Text('Alibaba Black',
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'AlibabaPuHuiTi')),
                  ),
                  DropdownMenuItem(
                    value: 'Stencil',
                    child: Text('Stencil',
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'Stencil')),
                  ),
                  DropdownMenuItem(
                    value: 'Oswald',
                    child: Text('Oswald',
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'Oswald')),
                  ),
                  DropdownMenuItem(
                    value: 'Righteous',
                    child: Text('Righteous',
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'Righteous')),
                  ),
                  DropdownMenuItem(
                    value: 'Cinzel',
                    child: Text('Cinzel',
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'Cinzel')),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _fontFamily = value);
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _flipHorizontally,
                activeColor: const Color(0xFF00FF88),
                title: Text(
                  AppStrings.of(context, 'text_overlay_flip'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  AppStrings.of(context, 'text_overlay_drag_hint'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                onChanged: (value) {
                  setState(() => _flipHorizontally = value);
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  if (widget.initialSpec != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pop(const CutTextOverlaySheetResult(cleared: true));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child:
                            Text(AppStrings.of(context, 'text_overlay_remove')),
                      ),
                    ),
                  if (widget.initialSpec != null) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(AppStrings.of(context, 'text_overlay_apply')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ));
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: const Color(0xFF252525),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF00FF88)),
            ),
          ),
          iconEnabledColor: Colors.white70,
        ),
      ],
    );
  }
}
