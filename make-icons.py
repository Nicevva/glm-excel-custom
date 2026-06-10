# -*- coding: utf-8 -*-
# Build AI-in-Excel-branded add-in icons from the company wordmark.
#   - square ribbon/app icons: icon-16/32/64/80.png (wordmark fit-by-width, centered, transparent)
#   - wide header logo:        header-logo.png      (trimmed wordmark, transparent)
import io, os
from PIL import Image, ImageChops

SRC = r"YOUR_LOGO_PATH.jpg"        # square ribbon/app icons
HEADER_SRC = r"YOUR_HEADER_LOGO_PATH.jpeg"  # compact header logo
OUT = "public/assets"

if not os.path.exists(SRC) or not os.path.exists(HEADER_SRC):
    print("SKIP make-icons: source images not found (placeholder icons already in place).")
    print("  Set SRC and HEADER_SRC at the top of this file to your own logo images.")
    import sys; sys.exit(0)


def to_transparent(path, lo=215, hi=248):
    """Trim white margin and turn the white background transparent,
    keeping the teal letters solid. Returns an RGBA image."""
    im = Image.open(path).convert("RGB")
    bg = Image.new("RGB", im.size, (255, 255, 255))
    box = ImageChops.difference(im, bg).convert("L").point(lambda x: 255 if x > 18 else 0).getbbox()
    if box:
        im = im.crop(box)
    lut = [255 if i <= lo else (0 if i >= hi else int(255 * (hi - i) / (hi - lo))) for i in range(256)]
    rgba = im.convert("RGBA")
    rgba.putalpha(im.convert("L").point(lut))
    return rgba


# --- header logo: from the compact source -----------------------------------
hdr = to_transparent(HEADER_SRC)
h = 64
w = max(1, round(hdr.width * h / hdr.height))
hdr.resize((w, h), Image.LANCZOS).save(f"{OUT}/header-logo.png")
print("header-logo.png:", (w, h), "from", HEADER_SRC)

im = Image.open(SRC).convert("RGB")

# --- trim the white margin around the wordmark --------------------------------
bg = Image.new("RGB", im.size, (255, 255, 255))
diff = ImageChops.difference(im, bg).convert("L").point(lambda x: 255 if x > 18 else 0)
box = diff.getbbox()
if box:
    im = im.crop(box)
print("trimmed size:", im.size)

# --- white -> transparent, keep the teal letters solid -----------------------
# luminance ramp: <=215 fully opaque, 215..248 fades out, >=248 transparent
gray = im.convert("L")
lo, hi = 215, 248
lut = [255 if i <= lo else (0 if i >= hi else int(255 * (hi - i) / (hi - lo))) for i in range(256)]
alpha = gray.point(lut)
logo = im.convert("RGBA")
logo.putalpha(alpha)

# --- square icons: fit wordmark by width, center vertically, transparent ------
def square(size, pad_ratio=0.12):
    pad = round(size * pad_ratio)
    avail = size - 2 * pad
    scale = min(avail / logo.width, avail / logo.height)
    nw, nh = max(1, round(logo.width * scale)), max(1, round(logo.height * scale))
    mark = logo.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(mark, ((size - nw) // 2, (size - nh) // 2), mark)
    return canvas

for s in (16, 32, 64, 80):
    square(s).save(f"{OUT}/icon-{s}.png")
    print(f"icon-{s}.png written")

# --- multi-size .ico for the Windows shortcut --------------------------------
import os as _os
_os.makedirs("installer", exist_ok=True)
square(256).save("installer/app.ico",
                 sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("installer/app.ico written")

print("DONE")
