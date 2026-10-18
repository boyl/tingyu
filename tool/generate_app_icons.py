"""Package the approved sound-island master into native launcher resources.

Requires Pillow. No image-generation API or credentials are needed to rerun.
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = '#FBF8F3'
master = Image.open(ROOT / 'assets/branding/sound-island.png').convert('RGBA')
alpha = master.getchannel('A')
box = alpha.point(lambda value: 255 if value > 128 else 0).getbbox()
assert box, 'Master must contain a visible symbol'
symbol = master.crop(box)


def foreground(size, adaptive=False):
    if adaptive:
        # All visible pixels fit inside Android's central 66dp safe circle.
        points = [(x, y) for y in range(symbol.height) for x in range(symbol.width)
                  if symbol.getpixel((x, y))[3] > 16]
        radius = max(math.hypot(x - symbol.width / 2, y - symbol.height / 2)
                     for x, y in points)
        scale = size * 30 / 108 / radius
    else:
        scale = size * .76 / max(symbol.size)
    resized = symbol.resize((round(symbol.width * scale), round(symbol.height * scale)),
                            Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (size, size))
    canvas.alpha_composite(resized, ((size - resized.width) // 2,
                                    (size - resized.height) // 2))
    return canvas


def tile(size, desktop=False):
    canvas = Image.new('RGBA', (size, size))
    if desktop:
        inset = round(size * .07)
        ImageDraw.Draw(canvas).rounded_rectangle(
            (inset, inset, size - inset - 1, size - inset - 1),
            radius=round(size * .19), fill=BACKGROUND)
        logo = foreground(round(size * .86))
        canvas.alpha_composite(logo, ((size - logo.width) // 2, (size - logo.height) // 2))
    else:
        canvas.paste(BACKGROUND, (0, 0, size, size))
        canvas.alpha_composite(foreground(size))
    return canvas


res = ROOT / 'android/app/src/main/res'
for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2),
                       ('xxhdpi', 3), ('xxxhdpi', 4)]:
    folder = res / f'mipmap-{density}'
    folder.mkdir(parents=True, exist_ok=True)
    tile(round(48 * scale)).save(folder / 'ic_launcher.png')
    fg = foreground(round(108 * scale), adaptive=True)
    fg.save(folder / 'ic_launcher_foreground.png')
    mono = Image.new('RGBA', fg.size, 'white')
    mono.putalpha(fg.getchannel('A'))
    mono.save(folder / 'ic_launcher_monochrome.png')

for qualifier, monochrome in [('v26', False), ('v33', True)]:
    folder = res / f'mipmap-anydpi-{qualifier}'
    folder.mkdir(parents=True, exist_ok=True)
    extra = '\n    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />' if monochrome else ''
    (folder / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        f'    <background android:drawable="@color/launcher_background" />\n'
        f'    <foreground android:drawable="@mipmap/ic_launcher_foreground" />{extra}\n'
        '</adaptive-icon>\n')
(res / 'values/launcher_colors.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    f'    <color name="launcher_background">{BACKGROUND}</color>\n</resources>\n')

for size in [16, 32, 64, 128, 256, 512, 1024]:
    tile(size, desktop=True).save(
        ROOT / f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png')
tile(256, desktop=True).save(ROOT / 'windows/runner/resources/app_icon.ico',
                           sizes=[(s, s) for s in [16, 24, 32, 48, 64, 128, 256]])
tile(1024).save(ROOT / 'assets/branding/app-icon.png')
print('Generated Android legacy/adaptive/monochrome, macOS and Windows icons.')
