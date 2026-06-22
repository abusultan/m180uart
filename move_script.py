import os
import re

package_name = "flutter_project"

moves = {
    'lib/core/sunshine_text_overlay.dart': 'lib/features/sunshine/services/sunshine_text_overlay.dart',
    'lib/ui/screens/cut_text_overlay_sheet.dart': 'lib/features/sunshine/screens/sunshine_text_overlay_screen.dart',
    'lib/core/dq_cut_service.dart': 'lib/features/dq/services/dq_cut_service.dart',
    'lib/core/dq_custom_cut.dart': 'lib/features/dq/services/dq_custom_cut.dart',
    'lib/core/dq_sjm_text_overlay.dart': 'lib/features/dq/services/dq_sjm_text_overlay.dart',
    'lib/ui/screens/dq_text_on_cut_screen.dart': 'lib/features/dq/screens/dq_text_on_cut_screen.dart',
    'lib/ui/screens/dq_custom_cut_screen.dart': 'lib/features/dq/screens/dq_custom_cut_screen.dart',
    'lib/ui/screens/dashboard_screen.dart': 'lib/features/dashboard/screens/dashboard_screen.dart',
    'lib/services/serial_service.dart': 'lib/core/serial/serial_service.dart',
    'lib/core/machine_protocol.dart': 'lib/core/serial/machine_protocol.dart',
    'lib/core/machine_handshake.dart': 'lib/core/serial/machine_handshake.dart',
}

# Ensure destination directories exist
for dest in moves.values():
    os.makedirs(os.path.dirname(dest), exist_ok=True)

# 1. Rename files
for src, dest in moves.items():
    if os.path.exists(src):
        os.rename(src, dest)
        print(f"Moved {src} to {dest}")

# Mapping of old filename (basename) to new package import path
# We'll use this to replace relative imports.
file_mapping = {}
for src, dest in moves.items():
    old_filename = os.path.basename(src)
    # The new package import path
    # e.g. lib/features/sunshine/services/sunshine_text_overlay.dart -> package:flutter_project/features/sunshine/services/sunshine_text_overlay.dart
    new_import_path = f"package:{package_name}/" + dest[4:] # strip "lib/"
    file_mapping[old_filename] = new_import_path

def update_imports():
    dart_files = []
    for root, dirs, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart'):
                dart_files.append(os.path.join(root, file))
    
    # Regex to find imports: import '...filename.dart';
    for file_path in dart_files:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        modified = False
        
        for old_filename, new_import in file_mapping.items():
            # match: import '../some/path/filename.dart';
            # or import 'filename.dart';
            # Replace with: import 'package:flutter_project/...';
            pattern = r"import\s+['\"](?:(?!\package:)[^'\"]*/)*" + re.escape(old_filename) + r"['\"];"
            replacement = f"import '{new_import}';"
            
            new_content = re.sub(pattern, replacement, content)
            if new_content != content:
                content = new_content
                modified = True
                
        # Also, rename CutTextOverlaySheet to SunshineTextOverlayScreen in the content
        if 'CutTextOverlaySheet' in content:
            content = content.replace('CutTextOverlaySheet', 'SunshineTextOverlayScreen')
            modified = True
        
        if modified:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)

update_imports()
print("Move and import update complete.")
