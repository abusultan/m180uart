String sanitizeSvg(String svg) {
  String result = svg;
  result = result.replaceAll(RegExp(r'<\?xml[^>]*\?>'), '');
  result = result.replaceAll(RegExp(r'<!DOCTYPE[^>]*>'), '');
  result = result.replaceAll(
    RegExp(r'<metadata[^>]*>.*?</metadata>', dotAll: true),
    '',
  );
  return result;
}

String toOutlineSvg(String svg) {
  String result = sanitizeSvg(svg);
  const overrideStyle =
      '<style>*{fill:none !important;stroke:black !important;stroke-width:3.5 !important;stroke-opacity:1 !important;}</style>';
  if (result.contains('</style>')) {
    result = result.replaceFirst('</style>', '</style>$overrideStyle');
  } else {
    result = result.replaceFirstMapped(
      RegExp(r'<svg\b[^>]*>'),
      (match) => '${match.group(0)}$overrideStyle',
    );
  }
  result = result.replaceAll(RegExp(r'fill="[^"]*"'), 'fill="none"');
  result = result.replaceAll(RegExp(r"fill='[^']*'"), 'fill="none"');
  result = result.replaceAll(RegExp(r'fill:[^;\"]*;?'), 'fill:none;');
  result = result.replaceAll(RegExp(r'fill-opacity="[^"]*"'), 'fill-opacity="1"');
  result = result.replaceAll(RegExp(r"fill-opacity='[^']*'"), 'fill-opacity="1"');
  result = result.replaceAll(RegExp(r'fill-opacity:[^;\"]*;?'), 'fill-opacity:1;');
  result = result.replaceAll(
    RegExp(r'fill:#?[0-9a-fA-F]{3,8}'),
    'fill:none',
  );
  result = result.replaceAll(
    RegExp(r'fill\s*=\s*[^\s>]+'),
    'fill="none"',
  );
  result = result.replaceAll(RegExp(r'stroke="[^"]*"'), 'stroke="black"');
  result = result.replaceAll(RegExp(r"stroke='[^']*'"), 'stroke="black"');
  result = result.replaceAll(RegExp(r'stroke:[^;\"]*;?'), 'stroke:black;');
  result = result.replaceAll(
    RegExp(r'stroke-opacity="[^"]*"'),
    'stroke-opacity="1"',
  );
  result = result.replaceAll(
    RegExp(r"stroke-opacity='[^']*'"),
    'stroke-opacity="1"',
  );
  result = result.replaceAll(
    RegExp(r'stroke-opacity:[^;\"]*;?'),
    'stroke-opacity:1;',
  );
  result = result.replaceAll(RegExp(r'opacity="[^"]*"'), 'opacity="1"');
  result = result.replaceAll(RegExp(r"opacity='[^']*'"), 'opacity="1"');
  result = result.replaceAll(RegExp(r'opacity:[^;\"]*;?'), 'opacity:1;');
  result = result.replaceAll(RegExp(r'display="none"'), 'display="block"');
  result = result.replaceAll(RegExp(r"display='none'"), 'display="block"');
  result = result.replaceAll(RegExp(r'display:none;?'), 'display:block;');
  result = result.replaceAll(
    RegExp(r'visibility="hidden"'),
    'visibility="visible"',
  );
  result = result.replaceAll(
    RegExp(r"visibility='hidden'"),
    'visibility="visible"',
  );
  result = result.replaceAll(
    RegExp(r'visibility:hidden;?'),
    'visibility:visible;',
  );
  result = result.replaceAll(
    RegExp(r'stroke\s*=\s*[^\s>]+'),
    'stroke="black"',
  );
  result = result.replaceAll(
    RegExp(r'stroke-width="[^"]*"'),
    'stroke-width="3.5"',
  );
  result = result.replaceAll(
    RegExp(r"stroke-width='[^']*'"),
    'stroke-width="3.5"',
  );
  result = result.replaceAll(
    RegExp(r'stroke-width:[^;\"]*;?'),
    'stroke-width:3.5;',
  );
  result = result.replaceAll(
    RegExp(r'stroke-width\s*=\s*[^\s>]+'),
    'stroke-width="3.5"',
  );
  result = result.replaceAllMapped(
    RegExp(r'style="([^"]*)"'),
    (m) {
      final s = m.group(1) ?? '';
      final cleaned = s
          .replaceAll(RegExp(r'fill\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'stroke\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'stroke-width\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'fill-opacity\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'stroke-opacity\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'opacity\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'display\s*:[^;]+;?'), '')
          .replaceAll(RegExp(r'visibility\s*:[^;]+;?'), '');
      return 'style="$cleaned"';
    },
  );
  result = result.replaceAllMapped(
    RegExp(r'<svg\b[^>]*>'),
    (m) {
      final tag = m.group(0) ?? '';
      final noFill = tag.replaceAll(
        RegExp(r'fill\s*=\s*[^\s>]+'),
        'fill="none"',
      );
      final withStroke = noFill.replaceAll(
        RegExp(r'stroke\s*=\s*[^\s>]+'),
        'stroke="black"',
      );
      return withStroke.replaceAll(
        RegExp(r'stroke-width\s*=\s*[^\s>]+'),
        'stroke-width="3.5"',
      );
    },
  );
  result = result.replaceAll(
    RegExp(r'<path\b'),
    '<path stroke="black" stroke-width="3.5" fill="none"',
  );
  result = result.replaceAll(
    RegExp(r'<rect\b'),
    '<rect stroke="black" stroke-width="3.5" fill="none"',
  );
  result = result.replaceAll(
    RegExp(r'<circle\b'),
    '<circle stroke="black" stroke-width="3.5" fill="none"',
  );
  result = result.replaceAll(
    RegExp(r'<polygon\b'),
    '<polygon stroke="black" stroke-width="3.5" fill="none"',
  );
  result = result.replaceAll(
    RegExp(r'<polyline\b'),
    '<polyline stroke="black" stroke-width="3.5" fill="none"',
  );
  return result;
}
