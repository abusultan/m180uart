import sys
import json
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from fontTools.pens.transformPen import TransformPen

class PolylinePen(BasePen):
    def __init__(self, glyphSet, scale_x, scale_y, flip_y=False):
        super().__init__(glyphSet)
        self.scale_x = scale_x
        self.scale_y = scale_y
        self.flip_y = flip_y
        self.polylines = []
        self.current_polyline = []
        self.current_pt = None
        self.glyfTable = glyphSet

    def _moveTo(self, pt):
        if self.current_polyline:
            self.polylines.append(self.current_polyline)
        self.current_polyline = [self._transform(pt)]
        self.current_pt = pt

    def _lineTo(self, pt):
        self.current_polyline.append(self._transform(pt))
        self.current_pt = pt

    def _curveToOne(self, pt1, pt2, pt3):
        pts = self._flatten_cubic(self.current_pt, pt1, pt2, pt3, 10)
        self.current_polyline.extend([self._transform(p) for p in pts[1:]])
        self.current_pt = pt3

    def _qCurveToOne(self, pt1, pt2):
        pts = self._flatten_quadratic(self.current_pt, pt1, pt2, 10)
        self.current_polyline.extend([self._transform(p) for p in pts[1:]])
        self.current_pt = pt2

    def addComponent(self, glyphName, transformation, **kwargs):
        try:
            glyph = self.glyphSet[glyphName]
        except KeyError:
            return
        tPen = TransformPen(self, transformation)
        glyph.draw(tPen, self.glyfTable)

    def _closePath(self):
        if self.current_polyline:
            if self.current_polyline[0] != self.current_polyline[-1]:
                self.current_polyline.append(self.current_polyline[0])
            self.polylines.append(self.current_polyline)
        self.current_polyline = []
        self.current_pt = None

    def _endPath(self):
        if self.current_polyline:
            self.polylines.append(self.current_polyline)
        self.current_polyline = []
        self.current_pt = None

    def _transform(self, pt):
        y = pt[1] * self.scale_y
        if self.flip_y:
            y = 1.6 - y
        return (pt[0] * self.scale_x, y)
        
    def _flatten_cubic(self, p0, p1, p2, p3, steps):
        pts = []
        for i in range(steps + 1):
            t = i / steps
            x = (1-t)**3 * p0[0] + 3*(1-t)**2 * t * p1[0] + 3*(1-t) * t**2 * p2[0] + t**3 * p3[0]
            y = (1-t)**3 * p0[1] + 3*(1-t)**2 * t * p1[1] + 3*(1-t) * t**2 * p2[1] + t**3 * p3[1]
            pts.append((x, y))
        return pts

    def _flatten_quadratic(self, p0, p1, p2, steps):
        pts = []
        for i in range(steps + 1):
            t = i / steps
            x = (1-t)**2 * p0[0] + 2*(1-t)*t * p1[0] + t**2 * p2[0]
            y = (1-t)**2 * p0[1] + 2*(1-t)*t * p1[1] + t**2 * p2[1]
            pts.append((x, y))
        return pts

def extract(font_path, flip_y=False):
    font = TTFont(font_path)
    cmap = font.getBestCmap()
    glyf = font['glyf']
    head = font['head']
    
    units = head.unitsPerEm
    scale_x = 1.0 / units
    scale_y = 1.6 / units
    
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:',./<>?"
    
    output = {}
    
    for char in chars:
        code = ord(char)
        if code not in cmap:
            continue
        glyph_name = cmap[code]
        if glyph_name not in glyf.glyphs:
            continue
            
        glyph = glyf[glyph_name]
        
        pen = PolylinePen(glyf, scale_x, scale_y, flip_y)
        glyph.draw(pen, glyf)
        
        if pen.polylines:
            output[char] = []
            for pl in pen.polylines:
                formatted_pl = [(round(p[0], 2), round(p[1], 2)) for p in pl]
                output[char].append(formatted_pl)
                
    return output

if __name__ == "__main__":
    font_path = sys.argv[1]
    flip_y = len(sys.argv) > 2 and sys.argv[2] == 'flip'
    res = extract(font_path, flip_y)
    
    out_dart = ""
    for char, polylines in res.items():
        if char == "'":
            c = r"\'"
        elif char == "\\":
            c = r"\\"
        else:
            c = char
        out_dart += f"  '{c}': [\n"
        for pl in polylines:
            out_dart += "    [" + ", ".join([f"Offset({p[0]:.2f}, {p[1]:.2f})" for p in pl]) + "],\n"
        out_dart += "  ],\n"
        
    print(out_dart)
