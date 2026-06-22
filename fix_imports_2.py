import os
import re

package_name = "flutter_project"

def update_imports():
    dart_files = []
    for root, dirs, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart'):
                dart_files.append(os.path.join(root, file))
    
    for file_path in dart_files:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        modified = False
        
        # In dart files, we want to replace import '../../xxx' with package import.
        # But this can be tricky because we need to know the depth.
        # Actually, let's just replace the specific imports that failed.
        
        # For dq_text_on_cut_screen.dart:
        if 'dq_text_on_cut_screen.dart' in file_path:
            content = content.replace("import '../../core/app_strings.dart';", "import 'package:flutter_project/core/localization/app_strings.dart';")
            content = content.replace("import '../../core/sjm_cipher.dart';", "import 'package:flutter_project/core/sjm_cipher.dart';")
            content = content.replace("import '../../core/cut_file_transformer.dart';", "import 'package:flutter_project/core/cut_file_transformer.dart';")
            content = content.replace("import '../../core/font_path_service.dart';", "import 'package:flutter_project/core/font_path_service.dart';")
            content = content.replace("import '../../core/text_overlay_fonts.dart';", "import 'package:flutter_project/core/text_overlay_fonts.dart';")
            modified = True
            
        # For sunshine_text_overlay.dart:
        if 'sunshine_text_overlay.dart' in file_path:
            content = content.replace("import '../cut_file_transformer.dart';", "import 'package:flutter_project/core/cut_file_transformer.dart';")
            content = content.replace("import '../font_path_service.dart';", "import 'package:flutter_project/core/font_path_service.dart';")
            content = content.replace("import '../text_overlay_fonts.dart';", "import 'package:flutter_project/core/text_overlay_fonts.dart';")
            content = content.replace("import 'package:flutter_project/features/sunshine/services/sunshine_text_overlay_screen.dart';", "import 'package:flutter_project/features/sunshine/screens/sunshine_text_overlay_screen.dart';")
            # Wait, CutPathData and CutTextOverlaySpec are missing. Let's find them. They were probably in sunshine_text_overlay.dart itself!
            # Let me check if CutPathData is imported.
            modified = True
            
        if modified:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)

update_imports()
print("Fixed relative imports.")
