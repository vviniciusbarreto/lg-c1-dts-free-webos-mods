#!/usr/bin/env python3
"""Builds dts_icon.png (144x144, white on transparent, letters cut out) from an official DTS logo SVG
that YOU supply. No brand artwork is shipped in this repository.

  pip install cairosvg pillow
  python3 tools/make_dts_icon.py path/to/dts_logo.svg dts_icon.png

The SVG is expected to be the classic "dts" box: a black rectangle with the white letters "dts".
The result is the box in white with the letters transparent, like the LG badge icons.
"""
import io, sys
import cairosvg
from PIL import Image, ImageOps

src, out = sys.argv[1], sys.argv[2]
png = cairosvg.svg2png(url=src, output_width=2000, background_color="white")
lum = Image.open(io.BytesIO(png)).convert("L")
alpha = ImageOps.invert(lum)                       # black -> opaque, white -> transparent
alpha = alpha.crop(alpha.point(lambda v: 255 if v > 10 else 0).getbbox())
N = 144
s = min(N / alpha.width, N / alpha.height)
w, h = round(alpha.width * s), round(alpha.height * s)
alpha = alpha.resize((w, h), Image.LANCZOS)
white = Image.new("RGBA", (w, h), (255, 255, 255, 255)); white.putalpha(alpha)
icon = Image.new("RGBA", (N, N), (255, 255, 255, 0)); icon.alpha_composite(white, ((N - w) // 2, (N - h) // 2))
icon.save(out)
print("wrote", out, w, "x", h)
