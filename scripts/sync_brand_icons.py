"""Derive every platform's brand artwork from the two approved rounded icons.

The originals remain unchanged. UIKit launcher assets are deliberately opaque:
iOS applies its own home-screen mask. In-app, desktop and Android artwork keeps
the transparent exterior corners of the approved PNGs.
"""
from __future__ import annotations

import argparse
import base64
from io import BytesIO
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'Resources/Icons'
try:
    from PIL import Image
except ImportError:
    # Build dependencies stay outside application packages and the global Python.
    sys.path.insert(0, str(ROOT / '.build-deps/icon-rendering'))
    try:
        from PIL import Image
    except ImportError as error:
        raise RuntimeError('Install the icon build dependency: python -m pip install --target .build-deps/icon-rendering Pillow') from error


def png(image: Image.Image) -> bytes:
    stream = BytesIO()
    image.save(stream, format='PNG')
    return stream.getvalue()


def outputs() -> dict[Path, bytes]:
    result = {}
    for dark, source in ((False, 'AsterHandIconLightRounded1024.png'),
                         (True, 'AsterHandIconDarkRounded1024.png')):
        with Image.open(ICONS / source) as opened:
            icon = opened.convert('RGBA')
        if icon.size != (1024, 1024) or icon.getpixel((0, 0))[3] != 0:
            raise ValueError('Expected approved 1024px icon with transparent corners: ' + source)
        if icon.getpixel((100, 512))[3] != 255:
            raise ValueError('Brand tile must remain opaque: ' + source)
        full = png(icon)
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
               'viewBox="0 0 1024 1024"><image width="1024" height="1024" '
               'xlink:href="data:image/png;base64,' + base64.b64encode(full).decode('ascii') + '"/></svg>\n').encode('utf-8')
        result[ROOT / 'Resources' / ('AgentGoIconDark.svg' if dark else 'AgentGoIcon.svg')] = svg
        if not dark:
            result[ROOT / 'desktop/public/agentgo.svg'] = svg
        result[ICONS / ('AgentGoIconDark1024.png' if dark else 'AgentGoIcon1024.png')] = full
        for suffix, size in (('', 64), ('@2x', 128), ('@3x', 192)):
            result[ICONS / ('AsterHandBrand' + ('Dark' if dark else '') + suffix + '.png')] = png(
                icon.resize((size, size), Image.Resampling.LANCZOS))
        launcher = Image.new('RGB', icon.size, '#121212' if dark else '#ffffff')
        launcher.paste(icon, mask=icon.getchannel('A'))
        for base, sizes in ((60, (2, 3)), (40, (2, 3)), (29, (2, 3)), (20, (2, 3))):
            for scale in sizes:
                result[ICONS / ('AppIcon' + ('Dark' if dark else '') + f'{base}x{base}@{scale}x.png')] = png(
                    launcher.resize((base * scale, base * scale), Image.Resampling.LANCZOS))
        for directory in ('desktop/public', 'desktop/linux/public'):
            result[ROOT / directory / ('icon-dark.png' if dark else 'icon-light.png')] = full
        if not dark:
            result[ROOT / 'desktop/linux/public/icon.png'] = full
        result[ROOT / 'android/app/src/main/assets/ui' / ('icon-dark.png' if dark else 'icon.png')] = full
        result[ROOT / 'android/app/src/main/res' / ('drawable-night' if dark else 'drawable') / 'asterhand_icon.png'] = full
    return result


def sync(check=False):
    changed = []
    for path, content in outputs().items():
        if not path.parent.exists():continue
        if not path.exists() or path.read_bytes() != content:
            changed.append(str(path.relative_to(ROOT)))
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
    if check and changed:
        raise ValueError('Brand icons out of sync: ' + ', '.join(changed))
    return changed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    changed = sync(args.check)
    print('AsterHand brand icons: ' + ('in sync' if args.check else f'{len(changed)} files updated'))
