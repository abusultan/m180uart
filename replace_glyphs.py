import re

with open('lib/core/font_glyphs_data.dart', 'r') as f:
    content = f.read()

def replace_map(content, var_name, dart_file):
    with open(dart_file, 'r') as f:
        new_map = f.read()
        
    pattern = r'(static const Map<String, List<List<Offset>>> ' + var_name + r' = \{).*?(^\};\n)'
    # Use re.DOTALL and re.MULTILINE to match across multiple lines
    content = re.sub(pattern, r'\1\n' + new_map + r'\2', content, flags=re.DOTALL | re.MULTILINE)
    return content

content = replace_map(content, 'oswaldGlyphs', 'oswald.dart')
content = replace_map(content, 'cinzelGlyphs', 'cinzel.dart')
content = replace_map(content, 'righteousGlyphs', 'righteous.dart')
content = replace_map(content, 'stencilRegular', 'stencil.dart')

with open('lib/core/font_glyphs_data.dart', 'w') as f:
    f.write(content)
