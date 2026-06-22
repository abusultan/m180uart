import re

with open('lib/core/font_glyphs_data.dart', 'r') as f:
    content = f.read()

# Replace '$': [ with '\$': [
content = content.replace("'$':", r"'\$':")

with open('lib/core/font_glyphs_data.dart', 'w') as f:
    f.write(content)
