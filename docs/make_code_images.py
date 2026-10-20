"""
Render key R snippets as editor-style PNGs for the assessment documents.
    uv run --with pygments --with pillow python docs/make_code_images.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from pygments import highlight
from pygments.formatters import ImageFormatter
from pygments.lexers import SLexer

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "code_images"
OUT.mkdir(exist_ok=True)

# (output name, source file, first line, last line)
SNIPPETS = [
    ("01_pipeline", "run_all.R", 8, 25),
    ("02_imd_rule", "R/02_build_features.R", 61, 81),
    ("03_wilson_kappa", "R/00_setup.R", 145, 158),
    ("04_gev_mle", "R/00_setup.R", 192, 216),
    ("05_markov", "R/08_markov_spells.R", 31, 37),
    ("06_ml_features", "R/10_ml_models.R", 25, 39),
    ("07_ml_models", "R/10_ml_models.R", 62, 85),
    ("08_shiny", "app/app.R", 65, 73),
]

BG = (40, 44, 52)
BAR = (33, 37, 43)
FONT = "DejaVu Sans Mono"

for name, src, a, b in SNIPPETS:
    lines = (ROOT / src).read_text().splitlines()[a - 1:b]
    code = "\n".join(lines)
    png = highlight(code, SLexer(), ImageFormatter(
        style="one-dark", font_name=FONT, font_size=22, line_numbers=True,
        line_number_start=a, line_number_chars=3, line_number_pad=14,
        line_number_bg=BG, line_number_fg=(99, 109, 131),
        line_number_separator=False, image_pad=28, line_pad=6))
    tmp = OUT / f"{name}_raw.png"
    tmp.write_bytes(png)
    body = Image.open(tmp).convert("RGB")
    tmp.unlink()

    # editor window: title bar with traffic lights and the file name
    bar_h = 54
    win = Image.new("RGB", (max(body.width, 900), body.height + bar_h), BG)
    win.paste(body, (0, bar_h))
    d = ImageDraw.Draw(win)
    d.rectangle([0, 0, win.width, bar_h], fill=BAR)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([24 + i * 30, 19, 40 + i * 30, 35], fill=c)
    font = ImageFont.truetype("DejaVuSans.ttf", 19)
    d.text((win.width / 2, bar_h / 2), f"{src}  ·  lines {a}–{b}", fill=(171, 178, 191),
           font=font, anchor="mm")

    # rounded corners on a white page background
    mask = Image.new("L", win.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *win.size], radius=18, fill=255)
    page = Image.new("RGB", win.size, (255, 255, 255))
    page.paste(win, (0, 0), mask)
    page.save(OUT / f"{name}.png", optimize=True)
    print("wrote", (OUT / f"{name}.png").relative_to(ROOT), page.size)
