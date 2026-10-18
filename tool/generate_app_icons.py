"""Derive Android launcher assets from the approved rounded white ribbon.

The PNG is rendered from assets/branding/ribbon-outline.svg. Keep the vector
and PNG together when revising the design. Desktop assets are unchanged.
Requires Pillow; no image-generation API or credentials.
"""
from pathlib import Path
import math
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
master = Image.open(ROOT / 'assets/branding/ribbon-outline.png').convert('RGBA')
box = master.getchannel('A').point(lambda value: 255 if value > 128 else 0).getbbox()
assert box, 'Master must contain a visible symbol'
symbol = master.crop(box)


def foreground(size, adaptive=False):
    if adaptive:
        points = [(x, y) for y in range(symbol.height) for x in range(symbol.width)
                  if symbol.getpixel((x, y))[3] > 16]
        radius = max(math.hypot(x - symbol.width / 2, y - symbol.height / 2)
                     for x, y in points)
        scale = size * 30 / 108 / radius
    else:
        scale = size * .76 / max(symbol.size)
    resized = symbol.resize((round(symbol.width * scale), round(symbol.height * scale)),
                            Image.Resampling.LANCZOS)
    # White RGB everywhere; only alpha defines the unfilled rounded outline.
    white = Image.new('RGBA', resized.size, (255, 255, 255, 0))
    white.putalpha(resized.getchannel('A'))
    resized = white
    canvas = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    canvas.alpha_composite(resized, ((size - resized.width) // 2,
                                    (size - resized.height) // 2))
    return canvas


res = ROOT / 'android/app/src/main/res'
for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2),
                       ('xxhdpi', 3), ('xxxhdpi', 4)]:
    folder = res / f'mipmap-{density}'
    foreground(round(48 * scale)).save(folder / 'ic_launcher.png')
    fg = foreground(round(108 * scale), adaptive=True)
    fg.save(folder / 'ic_launcher_foreground.png')
    fg.save(folder / 'ic_launcher_monochrome.png')

for qualifier, monochrome in [('v26', False), ('v33', True)]:
    folder = res / f'mipmap-anydpi-{qualifier}'
    extra = '\n    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />' if monochrome else ''
    (folder / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/launcher_background" />\n'
        f'    <foreground android:drawable="@mipmap/ic_launcher_foreground" />{extra}\n'
        '</adaptive-icon>\n')
(res / 'values/launcher_colors.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="launcher_background">#00000000</color>\n</resources>\n')
foreground(1024).save(ROOT / 'assets/branding/app-icon.png')
print('Generated Android transparent legacy/adaptive/monochrome icons; desktop untouched.')
