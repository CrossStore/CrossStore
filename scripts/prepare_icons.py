#!/usr/bin/env python3
"""Preprocess package-owned color masters into e-ink assets.

Algorithm ported from CrossMux scripts/prepare_app_icons.py (MIT).
Requires Pillow; does not generate new illustrations or modify masters.
"""
from pathlib import Path
import argparse
import json
import math
from PIL import Image, ImageFilter

def fitted_master(path: Path, size: int) -> Image.Image:
    """Fit alpha bounds once at final size; all outputs share identical geometry."""
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    # Ignore stray nearly transparent generator pixels when measuring bounds.
    bounds = alpha.point(lambda value: 255 if value >= 16 else 0).getbbox()
    if bounds is None:
        raise ValueError(f"Empty image: {path}")
    image = image.crop(bounds)
    extent = max(1, round(size * 0.875))
    image.thumbnail((extent, extent), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (size, size))
    result.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    return result


def gray_source(color: Image.Image) -> Image.Image:
    """White matte, perceptual sRGB luma, modest contrast; never quantize early."""
    matte = Image.new("RGBA", color.size, "white")
    matte.alpha_composite(color)
    rgb = matte.convert("RGB")
    # Integer Rec.709 luma approximation in display-referred sRGB. This is a
    # perceptual asset mapping, not a claim about measured panel reflectance.
    channels = rgb.tobytes()
    values = [(54 * r + 183 * g + 19 * b + 128) // 256
              for r, g, b in zip(channels[0::3], channels[1::3], channels[2::3])]
    gray = Image.new("L", color.size)
    gray.putdata(values)
    # Expand the dark ink and cream ends without per-icon histogram stretching.
    gray = gray.point(lambda v: max(0, min(255, round((v - 10) * 255 / 235))))
    return gray.filter(ImageFilter.UnsharpMask(radius=0.55, percent=80, threshold=4))


def quantize(gray: Image.Image, levels: int, dither: bool) -> Image.Image:
    """Fixed palette; restrained serpentine Floyd-Steinberg inside midtones."""
    width, height = gray.size
    step = 255 / (levels - 1)
    source = list(gray.tobytes())
    if levels == 2 and not dither:
        # Small outlines average with white during downsampling. Preserve their
        # coverage optically instead of imposing the large-icon midpoint.
        threshold = 166 if width <= 48 else 146
        result = Image.new("P", gray.size)
        result.putdata([0 if value < threshold else 1 for value in source])
        result.putpalette([0, 0, 0, 255, 255, 255] + [255] * 762)
        return result
    indices = [0] * len(source)
    current = [0.0] * (width + 2)
    following = [0.0] * (width + 2)
    for y in range(height):
        direction = -1 if dither and y % 2 else 1
        columns = range(width) if direction == 1 else range(width - 1, -1, -1)
        for x in columns:
            original = source[y * width + x]
            # Keep light paper, dark outlines and already representable tones
            # clean. Only diffuse midtones; high-frequency spots on cream pages
            # obscure small icon semantics more than the extra tone helps.
            nearest = min(levels - 1, int(original / step + 0.5))
            locked = dither and (original <= 28 or original >= 220 or abs(original - nearest * step) <= 7)
            if locked:
                indices[y * width + x] = 0 if original <= 28 else levels - 1 if original >= 220 else nearest
                continue
            value = max(0.0, min(255.0, original + current[x + 1]))
            index = min(levels - 1, max(0, int(value / step + 0.5)))
            indices[y * width + x] = index
            if dither:
                error = (value - index * step) * 0.9
                current[x + 1 + direction] += error * 7 / 16
                following[x + 1 - direction] += error * 3 / 16
                following[x + 1] += error * 5 / 16
                following[x + 1 + direction] += error / 16
        current, following = following, [0.0] * (width + 2)
    result = Image.new("P", gray.size)
    result.putdata(indices)
    palette = []
    for i in range(256):
        value = round(min(i, levels - 1) * step)
        palette.extend((value, value, value))
    result.putpalette(palette)
    return result


def pack_pixels(image: Image.Image, bits: int) -> bytes:
    """Top-down rows, left-to-right MSB first, 0=black, max=white."""
    width, height = image.size
    stride = (width * bits + 7) // 8
    data = bytearray([255] * (stride * height))
    mask = (1 << bits) - 1
    for y in range(height):
        for x in range(width):
            bit = x * bits
            offset = y * stride + bit // 8
            shift = 8 - bits - bit % 8
            data[offset] = (data[offset] & ~(mask << shift)) | (image.getpixel((x, y)) << shift)
    return bytes(data)


def unpack_pixels(data: bytes, width: int, height: int, bits: int) -> list[int]:
    stride = (width * bits + 7) // 8
    mask = (1 << bits) - 1
    return [(data[y * stride + x * bits // 8] >> (8 - bits - x * bits % 8)) & mask
            for y in range(height) for x in range(width)]


def build(folder):
    master = folder / "icons/master.png"
    if not master.is_file(): raise ValueError(f"missing master: {master}")
    for size in (32,48,64,96,128):
        color=fitted_master(master,size)
        dest=folder/"icons/color"/str(size);dest.mkdir(parents=True,exist_ok=True)
        color.save(dest/"icon.png",optimize=True)
        gray=gray_source(color)
        for levels in (2,4,16):
            bits=int(math.log2(levels))
            for mode in (["plain","dither"] if levels<=4 and size>=64 else ["plain"]):
                converted=quantize(gray,levels,mode=="dither")
                directory=folder/"icons"/f"g{levels}"/str(size)/mode
                directory.mkdir(parents=True,exist_ok=True)
                converted.save(directory/"icon.png",bits=bits,optimize=True)
                data=pack_pixels(converted,bits)
                assert unpack_pixels(data,size,size,bits)==list(converted.tobytes())
                if (size==32 and mode=="plain") or (size==64 and levels<=4 and mode=="dither") or (size==96 and levels==16):
                    assets=folder/"assets";assets.mkdir(exist_ok=True)
                    (assets/f"icon-g{levels}-{size}.bin").write_bytes(data)
    path=folder/"manifest.json";manifest=json.loads(path.read_text())
    manifest['assets']=sorted(set(manifest.get('assets',[])) | {str(p.relative_to(folder)) for p in (folder/'assets').glob('icon-*.bin')})
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f"{folder.name}: color + 2/4/16 shades; packed round trips passed")

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages',nargs='+',type=Path)
    for folder in parser.parse_args().packages: build(folder)
