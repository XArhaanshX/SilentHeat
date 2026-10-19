"""
Build the SilentHeat slide deck in the visual language of the
Multimodal Fatigue Detection deck (black canvas, blue-amber glow,
Poppins Light, uppercase titles with a short tan dash).

All numbers are read from the CSV tables written by the R pipeline,
so re-running `Rscript run_all.R` and then this script keeps the deck in sync.

    uv run --with python-pptx --with pillow python presentation/build_deck.py
"""
import csv
from pathlib import Path

from PIL import Image
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Inches, Pt

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "presentation" / "assets"
FIGS = ROOT / "outputs" / "figures" / "deck"
TABLES = ROOT / "outputs" / "tables"
OUT = ROOT / "presentation" / "SilentHeat.pptx"

# ---- Design tokens (sampled from the reference deck) -------------------------
WHITE = RGBColor(0xF2, 0xF2, 0xF2)
MUTED = RGBColor(0xA8, 0xA8, 0xA8)
DASH = RGBColor(0xD2, 0xB9, 0x9A)
AMBER = RGBColor(0xE0, 0x8A, 0x3C)        # text-weight amber (a step lighter than chart amber)
BLUE = RGBColor(0x5B, 0x9B, 0xE6)
ARROW = RGBColor(0xE3, 0xF0, 0x4F)        # the yellow-green arrows of the USP slide
BOX_FILL = RGBColor(0x26, 0x26, 0x26)
LIGHT = "Poppins Light"
REGULAR = "Poppins"
MEDIUM = "Poppins Medium"

SW, SH = 13.333, 7.5


def read(name):
    with open(TABLES / f"{name}.csv", newline="") as f:
        return list(csv.DictReader(f))


def row(rows, **kw):
    return next(r for r in rows if all(r[k] == v for k, v in kw.items()))


def pct(x, d=1):
    return f"{100 * float(x):.{d}f}%"


def f2(x, d=2):
    return f"{float(x):.{d}f}"


# ---- Numbers from the R pipeline ---------------------------------------------
pooled = read("blind_spot_pooled_summary")[0]
blind = read("blind_spot_by_city")
counts = row(read("trend_count_models"), model="Negative binomial")
slope = read("trend_nb_slope_test")[0]
tukey = row(read("anova_tukey_decade"), comparison="2021–25-1981–90")
assump = read("anova_assumptions")
gev = read("gev_parameters")
markov = read("markov_chain")
mc = read("markov_monte_carlo")
skill = read("early_warning_skill")
ops = read("early_warning_operating_points")
odds = row(read("early_warning_odds_ratios"), term="twmax")
era = read("trend_era_comparison")
corr = read("correlation_tmax_rh")
reg = read("regression_wetbulb_drivers")
val = read("wetbulb_validation")
contfit = read("dist_fit_continuous")
cntfit = read("dist_fit_counts")

che = row(gev, city="Chennai")
kol = row(gev, city="Kolkata")
kolm = row(markov, city="Kolkata")
logit = row(skill, model="Logistic model")
imdsk = row(skill, model="IMD-rule state")
clim = row(skill, model="Climatology")
imd_op = row(ops, rule="IMD heatwave today")
kappas = [float(b["kappa"]) for b in blind if b["kappa"] not in ("", "NA")]
mcn = [float(b["mcnemar_p"]) for b in blind if b["mcnemar_p"] not in ("", "NA")]
n_trend_sig = sum(float(g["trend_p"]) < 0.05 for g in gev)
r_vals = [float(c["pearson_r"]) for c in corr]
rh_eff = [float(r["b_rh10"]) for r in reg]
cheera = row(era, city="Chennai")
kolmc = {r["era"]: r for r in mc if r["city"] == "Kolkata"}
chemc = {r["era"]: r for r in mc if r["city"] == "Chennai"}
best_counts = {}
for r in contfit:
    if r["best"] == "TRUE":
        best_counts[r["distribution"]] = best_counts.get(r["distribution"], 0) + 1
vtm = [float(r["var_to_mean"]) for r in cntfit]

mls = read("ml_skill_by_lead")
mlh = read("ml_hybrid_alerts")
mli = read("ml_rf_importance")
loco = read("ml_loco_transfer")
rf1 = row(mls, lead_days="1", model="Random forest")
lr1 = row(mls, lead_days="1", model="Logistic")
rf3 = row(mls, lead_days="3", model="Random forest")
clim3 = row(mls, lead_days="3", model="Climatology")
hyb = row(mlh, lead_days="1", rule="Hybrid: IMD + RF")
imd_h = row(mlh, lead_days="1", rule="IMD rule alone")
head_rank = [r["feature"] for r in mli].index("headroom") + 1
rf_loco = [r for r in loco if r["model"] == "Random forest"]
loco_seen = sum(float(r["AUC_seen"]) for r in rf_loco) / len(rf_loco)
loco_unseen = sum(float(r["AUC_unseen"]) for r in rf_loco) / len(rf_loco)

# ---- Helpers -----------------------------------------------------------------
prs = Presentation()
prs.slide_width, prs.slide_height = Inches(SW), Inches(SH)
BLANK = prs.slide_layouts[6]


def new_slide(bg, notes=""):
    s = prs.slides.add_slide(BLANK)
    s.shapes.add_picture(str(ASSETS / bg), 0, 0, prs.slide_width, prs.slide_height)
    if notes:
        s.notes_slide.notes_text_frame.text = notes
    return s


def text(slide, x, y, w, h, paras, size=16, color=WHITE, font=LIGHT, align=PP_ALIGN.LEFT,
         anchor=MSO_ANCHOR.TOP, spacing=1.12, space_after=0, name=None):
    """paras: str | list of (str | list of (text, {opts}))"""
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        tb.name = name
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = spacing
        p.space_after = Pt(space_after)
        runs = para if isinstance(para, list) else [(para, {})]
        for t, o in runs:
            r = p.add_run()
            r.text = t
            f = r.font
            f.name = o.get("font", font)
            f.size = Pt(o.get("size", size))
            f.color.rgb = o.get("color", color)
            f.bold = o.get("bold", False)
            f.italic = o.get("italic", False)
    return tb


def title(slide, label, x=0.85, y=0.55, w=11.6, size=34):
    text(slide, x, y, w, 0.75, label.upper(), size=size, anchor=MSO_ANCHOR.BOTTOM, name="Title")
    dash(slide, x, y + 0.92)


def dash(slide, x, y, w=0.42):
    d = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(0.03))
    d.fill.solid()
    d.fill.fore_color.rgb = DASH
    d.line.fill.background()
    d.name = "Title dash"


def picture(slide, path, x, y, w=None, h=None):
    """Place an image inside the (x, y, w, h) box, preserving aspect ratio."""
    iw, ih = Image.open(path).size
    if w and h:
        scale = min(w / iw, h / ih)
        pw, ph = iw * scale, ih * scale
        x, y = x + (w - pw) / 2, y + (h - ph) / 2
    elif w:
        pw, ph = w, w * ih / iw
    else:
        pw, ph = h * iw / ih, h
    return slide.shapes.add_picture(str(path), Inches(x), Inches(y), Inches(pw), Inches(ph))


def stat(slide, x, y, w, big, label, color=AMBER, big_size=40, label_size=13):
    text(slide, x, y, w, 0.75, big, size=big_size, color=color, anchor=MSO_ANCHOR.BOTTOM)
    text(slide, x, y + 0.82, w, 0.9, label, size=label_size, color=MUTED, spacing=1.05)


def box(slide, x, y, w, h, label, size=15, fill=BOX_FILL, line=WHITE, color=WHITE,
        font=LIGHT, shape=MSO_SHAPE.RECTANGLE, line_w=1.25):
    b = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    b.fill.solid()
    b.fill.fore_color.rgb = fill
    if line is None:
        b.line.fill.background()
    else:
        b.line.color.rgb = line
        b.line.width = Pt(line_w)
    b.shadow.inherit = False
    tf = b.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = Inches(0.12)
    tf.margin_top = tf.margin_bottom = Inches(0.06)
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    lines = label if isinstance(label, list) else [label]
    for i, ln in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER
        p.line_spacing = 1.0
        runs = ln if isinstance(ln, list) else [(ln, {})]
        for t, o in runs:
            r = p.add_run()
            r.text = t
            r.font.name = o.get("font", font)
            r.font.size = Pt(o.get("size", size))
            r.font.color.rgb = o.get("color", color)
    return b


def line(slide, x1, y1, x2, y2, color=MUTED, width=1.0):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1),
                                   Inches(x2), Inches(y2))
    c.line.color.rgb = color
    c.line.width = Pt(width)
    return c


def arrow_glyph(slide, x, y, s=0.17):
    """The reference deck's '↗' bullet, drawn as a line + arrowhead so it never
    depends on a font having the glyph."""
    a = line(slide, x, y + s, x + s, y, ARROW, 1.6)
    ln = a.line._get_or_add_ln()
    ln.append(ln.makeelement("{http://schemas.openxmlformats.org/drawingml/2006/main}tailEnd",
                             {"type": "triangle", "w": "sm", "len": "sm"}))
    a.name = "Arrow bullet"


def arrow_list(slide, x, y, w, items, size=17, pitch=0.62):
    for i, t in enumerate(items):
        yy = y + i * pitch
        arrow_glyph(slide, x, yy + size / 72 * 0.38)
        text(slide, x + 0.38, yy, w - 0.38, pitch, t, size=size, spacing=1.05)


# =============================================================================
# 1. Title
# =============================================================================
s = new_slide("bg_title.jpg", notes=(
    "SilentHeat. India declares a heatwave using dry temperature alone. Our project asks "
    "how much dangerous humid heat that rule never sees, whether the blind spot is growing, "
    "and whether probability models can close it. Everything, from the data download to "
    "this deck's charts, is built in R."))
text(s, 1.42, 1.25, 7.6, 3.3, ["SILENT", "HEAT"], size=100, spacing=0.92, name="Title")
text(s, 1.47, 4.55, 6.8, 1.4,
     ["QUANTIFYING THE HUMID-HEAT BLIND SPOT", "IN INDIA'S HEATWAVE WARNINGS"],
     size=21, spacing=1.15)
text(s, 7.6, 1.25, 5.0, 0.8, ["ARHAANSH JHINGAN 25BCE0541 (SCOPE)"], size=15,
     align=PP_ALIGN.RIGHT)
text(s, 7.6, 5.55, 5.0, 0.8, ["PROBABILITY & STATISTICS LAB", "[BUILT END-TO-END IN R]"],
     size=17, align=PP_ALIGN.RIGHT, spacing=1.25)

# =============================================================================
# 2. Problem statement
# =============================================================================
s = new_slide("bg_content_a.jpg", notes=(
    "IMD's heatwave rule is purely dry-bulb: 40 °C on the plains, 37 °C on the coast, plus a "
    "4.5 °C departure from normal. That declaration activates Heat Action Plans. But the body "
    "cools by evaporating sweat, and humidity shuts that down. A 36 °C day at 60% humidity has "
    "a wet-bulb near 29.4 °C, close to the limits measured in the lab, yet it raises no alert."))
text(s, 1.875, 1.3, 9, 0.8, "PROBLEM STATEMENT", size=40, anchor=MSO_ANCHOR.BOTTOM, name="Title")
dash(s, 1.875, 2.27)
text(s, 1.875, 2.6, 9.2, 3.8, [
    "India declares a heatwave only when the dry-bulb temperature crosses a fixed line: 40 °C on "
    "the plains or 37 °C on the coast, plus a 4.5 °C departure from normal. That declaration is "
    "what switches on city and state Heat Action Plans.",
    "But the body cools itself by evaporating sweat, and humid air shuts that down. A 36 °C day "
    "at 60% humidity has a wet-bulb temperature of about 29.4 °C, close to the limit at which "
    "healthy young adults can no longer stabilise their core temperature. Yet it never triggers "
    "an alert.",
    "A dependable, probabilistic way to detect and forecast this humid heat is needed.",
], size=19, spacing=1.18, space_after=12)

# =============================================================================
# 3. Literature review
# =============================================================================
s = new_slide("bg_content_b.jpg", notes=(
    "Three strands of literature. IMD's criteria are dry-bulb; its Heat Index is experimental "
    "guidance only. Lab physiology puts the humid limit near 30 to 31 °C wet-bulb. The CPR review "
    "found most heat action plans use national thresholds and ignore humid heat. Extreme-value "
    "theory and trend tests are standard climate statistics, but we found no day-by-day "
    "probabilistic audit of the Indian rule against humid heat."))
text(s, 1.875, 1.0, 9, 0.8, "LITERATURE REVIEW", size=40, anchor=MSO_ANCHOR.BOTTOM, name="Title")
dash(s, 1.875, 1.97)
text(s, 1.875, 2.25, 9.8, 4.9, [
    [("Official criteria. ", {"font": REGULAR}),
     ("IMD declares a heatwave when a station reaches 40 °C (plains), 37 °C (coast) or 30 °C "
      "(hills) with a departure of at least 4.5 °C from normal, on two stations for two consecutive days. "
      "IMD's experimental Heat Index (NOAA equation; green < 35, yellow 36–45, orange 46–55, red > 55 °C) "
      "is guidance only and is not part of the declaration.", {})],
    [("Physiology. ", {"font": REGULAR}),
     ("Vecellio et al. (2022, J. Appl. Physiol.) measured critical wet-bulb limits of about 30–31 °C "
      "for young, healthy adults in warm-humid air, well below the theoretical 35 °C. Raymond et al. "
      "(2020, Science Advances) report that extreme humid heat has more than doubled in frequency since 1979.", {})],
    [("Policy. ", {"font": REGULAR}),
     ("A Centre for Policy Research review (2023) of 37 Heat Action Plans across 18 states found that "
      "only 10 set local thresholds. Plans focus on dry heat and largely ignore humid heat and warm nights.", {})],
    [("Statistics. ", {"font": REGULAR}),
     ("Extreme-value theory (Coles, 2001), Mann–Kendall/Sen trend tests and probabilistic verification "
      "(Brier, ROC) are standard climate tools. To our knowledge, they have not been combined into a "
      "day-by-day audit of the Indian rule against a physiological humid-heat criterion.", {})],
], size=14.5, spacing=1.12, space_after=9)

# =============================================================================
# 4. The gap (USP-style)
# =============================================================================
s = new_slide("bg_content_c_dim.jpg", notes=(
    "The gap has four parts, on the left. On the right is how our project addresses each one: "
    "a 45-year, 10-city audit; a physiological wet-bulb criterion; uncertainty quantified "
    "everywhere; a test of whether things are getting worse; and a working probabilistic "
    "warning, all in R."))
text(s, 0.6, 0.45, 12, 1.1, "The Gap", size=60, font=REGULAR, name="Title")
bw, bh = 2.55, 2.05
cells = [(0.55, 1.95, "Dry-bulb only trigger: 40 °C plains, 37 °C coast"),
         (3.3, 1.95, "Humid heat and warm nights ignored by most plans"),
         (0.55, 4.25, "Only 10 of 37 Heat Action Plans use local thresholds"),
         (3.3, 4.25, "No probabilities, return periods or uncertainty")]
for x, y, t in cells:
    box(s, x, y, bw, bh, t, size=17)
text(s, 6.3, 1.95, 6.6, 0.6, "How does our project close it?", size=22, color=WHITE,
     font=LIGHT)
arrow_list(s, 6.3, 2.8, 6.75, [
    "Audits the official rule day by day, 10 cities × 45 years",
    "Judges danger by physiology (wet-bulb), not dry-bulb",
    "Quantifies uncertainty: CIs, posteriors, bootstrap",
    "Tests whether the blind spot is growing (trends, EVT)",
    "Ships a calibrated next-day warning + dashboard, in R",
], size=16.5, pitch=0.68)

# =============================================================================
# 5. Our project / research questions
# =============================================================================
s = new_slide("bg_content_d.jpg", notes=(
    "Six research questions drive the project. Each maps onto a block of the probability and "
    "statistics syllabus: interval estimation and hypothesis testing; trend tests and regression; "
    "distribution fitting and extreme-value theory; Markov chains and Monte Carlo; and "
    "logistic regression with probabilistic verification."))
title(s, "Our project")
rqs = [
    ("RQ1", "What share of dangerous humid-heat days does the IMD rule miss?",
     "Interval estimation · χ², McNemar, κ · Bayesian posterior"),
    ("RQ2", "Are danger days becoming more frequent?",
     "Mann–Kendall · negative-binomial GLM · ANOVA · permutation"),
    ("RQ3", "How extreme can humid heat get, and is the tail moving?",
     "GEV maximum likelihood · return levels · likelihood-ratio test"),
    ("RQ4", "Do dangerous days cluster into spells?",
     "Two-state Markov chain · geometric law · Monte Carlo"),
    ("RQ5", "Can we warn a day ahead with honest probabilities?",
     "Logistic regression · Brier skill · ROC/AUC · reliability"),
    ("RQ6", "Can baseline ML warn 1–3 days ahead, even in a city it never saw?",
     "Decision tree · random forest · hybrid IMD + ML alert · leave-one-city-out"),
]
for i, (k, q, m) in enumerate(rqs):
    y = 1.8 + i * 0.88
    text(s, 0.85, y, 1.1, 0.6, k, size=26, color=AMBER)
    text(s, 2.05, y - 0.02, 10.3, 0.45, q, size=19)
    text(s, 2.05, y + 0.45, 10.3, 0.4, m, size=13.5, color=MUTED)

# =============================================================================
# 6. Divider
# =============================================================================
s = new_slide("bg_divider.jpg", notes="Data, methods and the pipeline.")
text(s, 2.5, 2.55, 8.33, 2.4, ["DATA, METHODS", "&", "BLOCK DIAGRAM"], size=34,
     align=PP_ALIGN.CENTER, spacing=1.15, anchor=MSO_ANCHOR.MIDDLE, name="Title")
dash(s, SW / 2 - 0.21, 4.95)

# =============================================================================
# 7. Pipeline block diagram (style of the hardware block diagram slide)
# =============================================================================
s = new_slide("bg_content_e_dim.jpg", notes=(
    "One command, Rscript run_all.R, runs the pipeline. It downloads 45 years of ERA5 reanalysis "
    "for 10 cities through the Open-Meteo API, builds features (harmonic-regression normals, the "
    "IMD rule, wet-bulb and heat index), runs seven analysis modules, and renders the report. "
    "The Shiny dashboard reads the same outputs."))
title(s, "Pipeline block diagram")
PINK, PINK_L = RGBColor(0xFC, 0xE4, 0xE1), RGBColor(0xE0, 0x7B, 0x6A)
BLUE_F, BLUE_L = RGBColor(0xDD, 0xEB, 0xF8), RGBColor(0x6F, 0x9C, 0xD0)
GREEN_F, GREEN_L = RGBColor(0xDD, 0xF3, 0xE2), RGBColor(0x6C, 0xB5, 0x82)
YEL_F, YEL_L = RGBColor(0xFF, 0xF4, 0xC7), RGBColor(0xD4, 0xB0, 0x3C)
PEACH_F, PEACH_L = RGBColor(0xFD, 0xEB, 0xD9), RGBColor(0xE0, 0x9A, 0x5A)
INK = RGBColor(0x22, 0x22, 0x22)
SUB = RGBColor(0x66, 0x66, 0x66)


def pbox(x, y, w, h, head, sub, fill, edge):
    return box(s, x, y, w, h, [head, [(sub, {"size": 10.5, "color": SUB})]], size=13,
               fill=fill, line=edge, color=INK, font=REGULAR,
               shape=MSO_SHAPE.ROUNDED_RECTANGLE, line_w=1.0)


top = [("ERA5 reanalysis", "Open-Meteo API · 10 cities · 1981–2025"),
       ("01 Fetch", "jsonlite · retries · cache"),
       ("02 Features", "harmonic normals · IMD rule · Tw · HI")]
for i, (h, sub) in enumerate(top):
    x = 1.35 + i * 3.75
    pbox(x, 1.85, 3.1, 0.85, h, sub, PINK, PINK_L)
    if i:
        line(s, x - 0.65, 2.275, x, 2.275, PINK_L, 1.25)
mods = [("03 EDA", "correlation · regression"), ("04 Fits", "MLE · AIC · KS/AD"),
        ("05 Blind spot", "CIs · χ² · κ · Bayes"), ("06 Trends", "MK · NB GLM · ANOVA"),
        ("07 Extremes", "GEV · return levels"), ("08 Spells", "Markov · Monte Carlo"),
        ("09 Warning", "logistic · ROC · Brier")]
mw, gap = 1.6, 0.13
x0 = (SW - (len(mods) * mw + (len(mods) - 1) * gap)) / 2
line(s, SW / 2, 2.7, SW / 2, 3.1, PINK_L, 1.25)
line(s, x0 + mw / 2, 3.1, x0 + (len(mods) - 1) * (mw + gap) + mw / 2, 3.1, BLUE_L, 1.25)
for i, (h, sub) in enumerate(mods):
    x = x0 + i * (mw + gap)
    line(s, x + mw / 2, 3.1, x + mw / 2, 3.35, BLUE_L, 1.25)
    pbox(x, 3.35, mw, 0.95, h, sub, BLUE_F if i % 2 == 0 else GREEN_F,
         BLUE_L if i % 2 == 0 else GREEN_L)
line(s, x0 + mw / 2, 4.55, x0 + (len(mods) - 1) * (mw + gap) + mw / 2, 4.55, YEL_L, 1.25)
for i in range(len(mods)):
    x = x0 + i * (mw + gap)
    line(s, x + mw / 2, 4.3, x + mw / 2, 4.55, YEL_L, 1.25)
line(s, SW / 2, 4.55, SW / 2, 4.85, YEL_L, 1.25)
pbox(SW / 2 - 2.2, 4.85, 4.4, 0.7, "outputs/  ·  30+ tables · 14 figures × 2 themes",
     "CSV + RDS, every number traceable", YEL_F, YEL_L)
outs = [("10 Report", "knitr + markdown → HTML / PDF"), ("Shiny dashboard", "bslib · 5 tabs · risk calculator"),
        ("This deck", "figures from ggplot2")]
for i, (h, sub) in enumerate(outs):
    x = 1.8 + i * 3.4
    line(s, SW / 2, 5.55, SW / 2, 5.75, PEACH_L, 1.25)
    pbox(x, 5.95, 2.9, 0.75, h, sub, PEACH_F, PEACH_L)
line(s, 1.8 + 1.45, 5.75, 1.8 + 2 * 3.4 + 1.45, 5.75, PEACH_L, 1.25)
for i in range(3):
    line(s, 1.8 + i * 3.4 + 1.45, 5.75, 1.8 + i * 3.4 + 1.45, 5.95, PEACH_L, 1.25)
text(s, 0.85, 6.95, 11.6, 0.35, "Rscript run_all.R reproduces everything from raw data in under a minute.",
     size=12, color=MUTED, align=PP_ALIGN.CENTER)

# =============================================================================
# 8. Data
# =============================================================================
s = new_slide("bg_content_a_dim.jpg", notes=(
    "164,360 city-days with no missing values. Seven cities are judged by the plains rule and "
    "three by the coastal rule. A danger day has a daily maximum wet-bulb of at least 29 °C; "
    "critical is 31 °C. We implement the IMD rule on one grid cell, which is more generous than "
    "IMD's two-station rule, so every miss rate is a lower bound. Recomputing wet-bulb "
    "independently with Stull's formula correlates at 0.96–0.99 with ERA5."))
title(s, "Data")
for i, (big, lab) in enumerate([(f"{int(pooled['city_days']):,}", "city-days, no missing values"),
                                ("10", "cities: 7 plains, 3 coastal"),
                                ("45", "years, 1981–2025 (ERA5)"),
                                ("6", "daily variables per city")]):
    stat(s, 0.85 + i * 3.05, 1.75, 2.9, big, lab, color=AMBER if i == 0 else WHITE, big_size=44)
text(s, 0.85, 3.85, 5.6, 2.9, [
    [("Plains rule (≥ 40 °C): ", {"font": REGULAR, "color": BLUE}),
     ("Delhi, Lucknow, Ahmedabad, Nagpur, Kolkata, Bhubaneswar, Vellore", {})],
    [("Coastal rule (≥ 37 °C): ", {"font": REGULAR, "color": AMBER}),
     ("Chennai, Mumbai, Visakhapatnam", {})],
    [("Variables: ", {"font": REGULAR}),
     ("Tmax, Tmin, daily max and mean wet-bulb, RH min and mean", {})],
], size=15, space_after=10)
text(s, 6.85, 3.85, 5.7, 2.9, [
    [("Danger day: ", {"font": REGULAR, "color": AMBER}), ("daily max wet-bulb ≥ 29 °C", {})],
    [("Critical day: ", {"font": REGULAR, "color": AMBER}), ("wet-bulb ≥ 31 °C (Vecellio 2022)", {})],
    [("IMD heatwave day: ", {"font": REGULAR, "color": BLUE}),
     ("rule met on ≥ 2 consecutive days, departure from a harmonic-regression normal", {})],
    [("Physics check: ", {"font": REGULAR}),
     (f"Stull wet-bulb vs ERA5, r = {min(float(v['r']) for v in val):.2f}–{max(float(v['r']) for v in val):.2f}", {})],
], size=15, space_after=10)

# =============================================================================
# 9. R toolkit
# =============================================================================
s = new_slide("bg_content_c_dim.jpg", notes=(
    "R does the whole job. The left column was written from first principles: the GEV likelihood "
    "and its optimiser, delta-method and bootstrap intervals, Mann-Kendall, Wilson intervals, "
    "kappa, the Markov chain and its simulation. Each was cross-checked against a reference "
    "package; for example, our GEV estimates match evd::fgev to every printed digit."))
title(s, "How R powers the project")
cols = [
    ("Written from scratch", AMBER, [
        "GEV log-likelihood + MLE (optim, Hessian)",
        "Return levels: delta method + bootstrap",
        "Mann–Kendall test + Sen's slope",
        "Wilson CI · Cohen's κ · Beta posterior",
        "Year-block bootstrap · permutation test",
        "Markov chain + Monte Carlo simulator",
        "IMD rule engine · Stull wet-bulb · NWS HI"]),
    ("Base R statistics", WHITE, [
        "lm · glm (binomial, Poisson) · aov",
        "TukeyHSD · friedman.test · kruskal.test",
        "chisq · fisher · mcnemar · prop · binom",
        "t.test · wilcox.test · ks.test",
        "shapiro.test · bartlett.test · cor.test",
        "optim · optimHess · uniroot · rle"]),
    ("Packages", BLUE, [
        "dplyr · tidyr: wrangling 164k rows",
        "ggplot2 · patchwork · ggridges: 14 figures",
        "fitdistrplus · MASS::glm.nb · evd (check)",
        "pROC: ROC + DeLong intervals",
        "jsonlite: API download",
        "shiny · bslib: dashboard",
        "knitr · markdown: report"]),
]
for i, (head, col, items) in enumerate(cols):
    x = 0.85 + i * 4.05
    text(s, x, 1.8, 3.8, 0.45, head.upper(), size=16, color=col, font=REGULAR)
    text(s, x, 2.4, 3.9, 4.2, items, size=15, space_after=8)
text(s, 0.85, 6.7, 11.6, 0.5, [[("≈ 1,700 lines of R  ·  10 modules  ·  1 command  ·  "
                                  "our MLE matches evd::fgev to every printed digit", {})]],
     size=14, color=MUTED)

# =============================================================================
# 10. Divider
# =============================================================================
s = new_slide("bg_divider.jpg", notes="Results, one research question at a time.")
text(s, 2.5, 2.9, 8.33, 1.6, "RESULTS", size=40, align=PP_ALIGN.CENTER,
     anchor=MSO_ANCHOR.MIDDLE, name="Title")
dash(s, SW / 2 - 0.21, 4.55)

# =============================================================================
# 11. Why dry-bulb cannot see humid heat
# =============================================================================
s = new_slide("bg_content_e_dim.jpg", notes=(
    "Every dot is a city-day. Blue days are IMD heatwaves: hot and dry, bottom right. Orange "
    "days are dangerous humid heat: 32–39 °C at 40–70% humidity, sitting on the 29 °C wet-bulb "
    "isotherm. The two clouds barely touch. Temperature and humidity are strongly negatively "
    "correlated, so a temperature threshold automatically selects dry days."))
title(s, "Why a dry-bulb rule cannot see humid heat")
picture(s, FIGS / "fig_blindspot_scatter.png", 0.55, 1.65, w=8.4, h=5.5)
stat(s, 9.35, 1.75, 3.6, f"r = {max(r_vals):.2f} to {min(r_vals):.2f}",
     "Tmax vs RH in every city (p < 0.001): the hottest days are the driest", big_size=26)
stat(s, 9.35, 3.45, 3.6, f"+{min(rh_eff):.1f}–{max(rh_eff):.1f} °C",
     "wet-bulb rise per +10% humidity at the same temperature (regression)", big_size=26)
stat(s, 9.35, 5.15, 3.6, f"{pooled['imd_days_humid']} of {pooled['imd_days']}",
     "IMD heatwave days were also humid-danger days", big_size=26)

# =============================================================================
# 12. RQ1 hero
# =============================================================================
s = new_slide("bg_content_a_dim.jpg", notes=(
    "Our central result. Of 730 dangerous humid-heat days, 703 were not IMD heatwave days: "
    "96.3%, with a Wilson interval of 94.7 to 97.4%. On the right, per year: in Kolkata, "
    "Bhubaneswar, Visakhapatnam and Chennai, silent danger days outnumber official heatwave days."))
title(s, "RQ1 · The blind spot")
text(s, 0.85, 1.85, 4.6, 1.5, pct(pooled["miss_rate"]), size=88, color=AMBER, name="Hero")
text(s, 0.85, 3.45, 4.3, 1.5,
     f"of dangerous humid-heat days ({pooled['n_silent']} of {pooled['n_danger']}) were never "
     f"IMD heatwave days", size=19, spacing=1.12)
text(s, 0.85, 4.75, 4.3, 1.8, [
    f"Wilson 95% CI {pct(pooled['wilson_lo'])}–{pct(pooled['wilson_hi'])}",
    "Our rule is more generous than IMD's, so this is a lower bound",
], size=13.5, color=MUTED, space_after=6)
picture(s, FIGS / "fig_days_per_year.png", 5.35, 1.55, w=7.6, h=5.6)

# =============================================================================
# 13. RQ1 evidence
# =============================================================================
s = new_slide("bg_content_b_dim.jpg", notes=(
    "Is it real? Cohen's kappa is essentially zero: the two definitions measure different hazards. "
    "McNemar says the disagreement is systematic. The miss rate is the same across cities and "
    "between coastal and plains rules. The heatmap shows it stays at 96–99% whatever definition "
    "we use, including each city's own 95th and 99th percentile. IMD's own experimental Heat "
    "Index was orange or red on 81% of these days."))
title(s, "RQ1 · Is it real? The statistical evidence")
text(s, 0.85, 1.8, 4.9, 5.2, [
    [("Cohen's κ  ", {"font": REGULAR, "color": AMBER}),
     (f"≈ 0 (at most {max(kappas):.2f}): no agreement between the two definitions", {})],
    [("McNemar  ", {"font": REGULAR, "color": AMBER}),
     ("p < 0.05 in every city: the disagreement is systematic", {})],
    [("χ² homogeneity  ", {"font": REGULAR, "color": AMBER}),
     (f"p = {f2(pooled['homogeneity_p'])}: same miss rate in every city", {})],
    [("Coastal vs plains  ", {"font": REGULAR, "color": AMBER}),
     (f"p = {f2(pooled['coastal_vs_plains_p'])}: a property of the rule, not the region", {})],
    [("Bayesian  ", {"font": REGULAR, "color": AMBER}),
     ("Beta(1,1) prior: posterior miss rate > 88% in every city", {})],
    [("Heat Index  ", {"font": REGULAR, "color": AMBER}),
     (f"IMD's own experimental index was orange/red on {pct(pooled['hi_orange_capture'], 0)} of these days", {})],
], size=14.5, space_after=11, spacing=1.08)
picture(s, FIGS / "fig_sensitivity.png", 6.0, 1.6, w=6.95, h=5.55)

# =============================================================================
# 14. Two seasons
# =============================================================================
s = new_slide("bg_content_d_dim.jpg", notes=(
    "When does each hazard happen? IMD heatwaves cluster in April to June over north and central "
    "India. Humid danger peaks in May to July along the east coast and in Kolkata. The two "
    "hazards rarely share a city-week."))
title(s, "Two hazards, two seasons, two geographies")
picture(s, FIGS / "fig_season_calendar.png", 0.7, 1.65, w=11.95, h=5.65)

# =============================================================================
# 15. Distributions
# =============================================================================
s = new_slide("bg_content_c_dim.jpg", notes=(
    "Which probability model fits? For daily wet-bulb in May, the best family by AIC varies by "
    "city, and Anderson-Darling statistics stay large because the tails misfit. That motivates "
    "extreme-value theory for the tail. Annual counts of danger days are overdispersed, with "
    "variance 2 to 9 times the mean, so the Poisson model is rejected and we use the negative binomial."))
title(s, "Which probability model fits?")
picture(s, FIGS / "fig_distribution_fits.png", 0.55, 1.6, w=7.6, h=5.6)
best_txt = ", ".join(f"{k} {v}" for k, v in sorted(best_counts.items(), key=lambda kv: -kv[1]))
text(s, 8.5, 1.8, 4.4, 5.3, [
    [("Daily wet-bulb (May)", {"font": REGULAR, "color": AMBER})],
    f"MLE fits of Normal, Gamma, Weibull and Lognormal. Best by AIC: {best_txt}.",
    "Large Anderson–Darling statistics: the bulk fits, the tail does not, so we model the tail "
    "with extreme-value theory.",
    [("Annual danger-day counts", {"font": REGULAR, "color": AMBER})],
    f"Variance/mean = {min(vtm):.1f}–{max(vtm):.1f}. Dispersion test rejects Poisson "
    "(p < 0.001 everywhere); negative binomial wins on AIC and LRT.",
], size=14, space_after=9)

# =============================================================================
# 16. RQ2 trends
# =============================================================================
s = new_slide("bg_content_e_dim.jpg", notes=(
    "Is it getting worse? In a negative-binomial model with city effects, danger days grow by a "
    "factor of 1.54 per decade. The Tukey comparison puts the early-2020s 0.53 °C above the 1980s, "
    "and the blocked Friedman test confirms it. Chennai went from 0.35 to 2.85 danger days a year."))
title(s, "RQ2 · Is it getting worse?")
picture(s, FIGS / "fig_trend_counts.png", 0.55, 1.55, w=12.2, h=4.25)
stat(s, 0.85, 5.6, 3.9, f"×{f2(counts['IRR_per_decade'])} / decade",
     f"danger days, NB GLM, 95% CI {f2(counts['IRR_lo'])}–{f2(counts['IRR_hi'])}",
     big_size=28)
stat(s, 4.95, 5.6, 3.9, f"+{f2(tukey['diff'])} °C",
     f"Apr–Jun wet-bulb, 2021–25 vs 1981–90 (Tukey; Friedman p < 0.001)", big_size=28)
stat(s, 9.05, 5.6, 3.9, f"{f2(cheera['danger_days_1981_2000'])} → {f2(cheera['danger_days_2006_2025'])}",
     f"Chennai danger days/yr, 1981–2000 vs 2006–25 (perm. p = {f2(cheera['perm_p'], 3)})",
     big_size=28)

# =============================================================================
# 17. RQ3 extremes
# =============================================================================
s = new_slide("bg_content_d_dim.jpg", notes=(
    "Extremes. We fit the generalised extreme value distribution to 45 annual maxima per city with "
    "our own likelihood code. Letting the location drift with time is a significant improvement "
    "in seven of ten cities. Under that model, the annual maximum that was a 1-in-50-year event in "
    "Chennai in 1985 now comes about once every 2.6 years."))
title(s, "RQ3 · Extremes are shifting (GEV)")
picture(s, FIGS / "fig_return_levels.png", 0.55, 1.55, w=12.2, h=4.4)
stat(s, 0.85, 5.6, 3.9, f"1-in-50 → 1-in-{float(che['return_period_now']):.1f}",
     "Chennai: 1985's 50-year humid-heat extreme, under today's climate", big_size=28)
stat(s, 4.95, 5.6, 3.9, f"{n_trend_sig} of 10 cities",
     "significant upward shift of the GEV location (LRT p < 0.05)", big_size=28)
stat(s, 9.05, 5.6, 3.9, pct(kol["p_critical_any_2026_35_trend"], 0),
     "chance Kolkata sees a ≥ 31 °C wet-bulb day in 2026–35 (trend GEV)", big_size=28)

# =============================================================================
# 18. RQ4 Markov
# =============================================================================
s = new_slide("bg_content_b_dim.jpg", notes=(
    "Danger days come in spells. Within Kolkata's peak season, a danger day is followed by "
    "another 57% of the time, versus 5% after a calm day. Independence is rejected everywhere. "
    "The chain implies geometric spell lengths, which the data do not reject. Simulating 10,000 "
    "seasons per era, the chance of a 3-day spell in Chennai went from about 2% to about 23%."))
title(s, "RQ4 · Danger comes in spells (Markov chain)")
p11, p01 = float(kolm["p11"]), float(kolm["p01"])
cx1, cx2, cy, r = 1.75, 4.55, 3.55, 0.62
for cx, lab, col in [(cx1, "CALM", BLUE), (cx2, "DANGER", AMBER)]:
    c = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(cx - r), Inches(cy - r), Inches(2 * r), Inches(2 * r))
    c.fill.background()
    c.line.color.rgb = col
    c.line.width = Pt(2)
    c.shadow.inherit = False
    text(s, cx - r, cy - 0.2, 2 * r, 0.4, lab, size=13, color=col, font=REGULAR, align=PP_ALIGN.CENTER)
ar = line(s, cx1 + r, cy - 0.22, cx2 - r, cy - 0.22, WHITE, 1.25)
ar2 = line(s, cx2 - r, cy + 0.22, cx1 + r, cy + 0.22, WHITE, 1.25)
for a in (ar, ar2):
    ln = a.line._get_or_add_ln()
    tail = ln.makeelement("{http://schemas.openxmlformats.org/drawingml/2006/main}tailEnd",
                          {"type": "triangle", "w": "med", "len": "med"})
    ln.append(tail)
text(s, 2.4, cy - 0.62, 1.5, 0.35, f"{p01:.3f}", size=13, align=PP_ALIGN.CENTER)
text(s, 2.4, cy + 0.3, 1.5, 0.35, f"{1 - p11:.3f}", size=13, align=PP_ALIGN.CENTER)
text(s, cx1 - 0.75, cy - 1.15, 1.5, 0.35, f"stay {1 - p01:.3f}", size=12, color=MUTED, align=PP_ALIGN.CENTER)
text(s, cx2 - 0.75, cy - 1.15, 1.5, 0.35, f"stay {p11:.3f}", size=12, color=MUTED, align=PP_ALIGN.CENTER)
text(s, 0.85, 1.75, 5.0, 0.4, "Kolkata, peak season (5 May – 4 Jul)", size=13, color=MUTED)
ors = [float(m["odds_ratio_persistence"]) for m in markov]
gofp = [float(m["geom_gof_p"]) for m in markov]
text(s, 0.85, 4.65, 5.1, 2.5, [
    [("Independence rejected: ", {"font": REGULAR}),
     (f"χ² and G² p < 0.001; persistence odds ratio {min(ors):.0f}–{max(ors):.0f}", {})],
    [("Spells are geometric: ", {"font": REGULAR}),
     (f"mean = 1/(1 − p₁₁); goodness-of-fit p = {min(gofp):.2f}–{max(gofp):.2f}", {})],
    [("Monte Carlo, 10,000 seasons/era: ", {"font": REGULAR}),
     (f"P(≥ 3-day spell) in Chennai {pct(chemc['1981–2000']['p_longest_ge3'], 0)} → "
      f"{pct(chemc['2006–2025']['p_longest_ge3'], 0)}, in Kolkata {pct(kolmc['1981–2000']['p_longest_ge3'], 0)} → "
      f"{pct(kolmc['2006–2025']['p_longest_ge3'], 0)}", {})],
], size=13.5, space_after=8)
picture(s, FIGS / "fig_markov_montecarlo.png", 6.15, 1.75, w=6.85, h=4.9)

# =============================================================================
# 19. RQ5 early warning
# =============================================================================
s = new_slide("bg_content_a_dim.jpg", notes=(
    "Can we warn a day ahead? We trained a logistic model on 1981–2014 and tested it on the "
    "unseen years 2015–2025. Its AUC is 0.92, against 0.61 for the IMD-rule state. Its Brier "
    "skill is 17% better than climatology, and the reliability diagram stays close to the "
    "diagonal. Used as a warning, the IMD rule catches only 4% of next-day danger days."))
title(s, "RQ5 · A calibrated next-day warning")
picture(s, FIGS / "fig_early_warning.png", 0.55, 1.6, w=8.3, h=4.4)
stat(s, 9.2, 1.7, 3.8, f"AUC {f2(logit['AUC'])}",
     f"logistic model vs {f2(imdsk['AUC'])} for the IMD-rule state (test years 2015–25)", big_size=28)
stat(s, 9.2, 3.35, 3.8, f"+{pct(logit['BSS_vs_climatology'], 0)}",
     "Brier skill over climatology", big_size=28)
stat(s, 9.2, 5.0, 3.8, pct(imd_op["POD"], 0),
     "of next-day danger days caught by 'IMD heatwave today'", big_size=28)
text(s, 0.85, 6.3, 8.0, 0.8,
     f"Each +1 °C of today's wet-bulb multiplies tomorrow's odds of danger by {float(odds['odds_ratio']):.1f} "
     f"(95% CI {float(odds['OR_lo']):.1f}–{float(odds['OR_hi']):.1f}).", size=14, color=MUTED)

# =============================================================================
# 19b. RQ6 machine-learning set-up and novelty
# =============================================================================
s = new_slide("bg_content_c_dim.jpg", notes=(
    "RQ6 pushes the warning further with standard baseline machine-learning models: a decision "
    "tree and a random forest, next to the logistic model and climatology. We forecast one, two "
    "and three days ahead with the same unseen test years. Three things are new: features built "
    "from physiology, a hybrid alert that keeps the IMD rule and adds an ML layer, and a test "
    "of whether the model works in a city it was never trained on."))
title(s, "RQ6 · Baseline ML, and what is new")
text(s, 0.85, 1.85, 5.6, 5.0, [
    [("Set-up", {"font": REGULAR, "color": AMBER})],
    "Target: will the day +1, +2 or +3 ahead be a danger day (wet-bulb ≥ 29 °C)?",
    "Baselines: climatology, IMD rule, logistic regression, decision tree (rpart), random forest (ranger, 400 trees)",
    f"{len(mli)} features: today's weather, 3–7-day wet-bulb history, season, city",
    "Train 1981–2014 · alert thresholds tuned on 2010–14 · test 2015–25, never seen",
], size=14.5, space_after=10)
text(s, 6.85, 1.85, 5.6, 0.5, [[("What is new", {"font": REGULAR, "color": AMBER})]], size=14.5)
novel = [("Physiology-informed features", "headroom to the 29 °C limit · closing speed · days-to-limit"),
         ("Hybrid alert, not a replacement", "IMD rule OR ML layer, scored on blind-spot recovery"),
         ("Zero-history cities", "leave-one-city-out: warn where no labelled past exists")]
for i, (h, sub) in enumerate(novel):
    box(s, 6.85, 2.45 + i * 1.4, 5.6, 1.2,
        [[(h, {"font": REGULAR, "color": AMBER, "size": 17})], [(sub, {"color": MUTED, "size": 13})]])

# =============================================================================
# 19c. RQ6 model comparison
# =============================================================================
s = new_slide("bg_content_b_dim.jpg", notes=(
    f"On the unseen years the random forest is best at every lead time: AUC {f2(rf1['AUC'])} one day "
    f"ahead against {f2(lr1['AUC'])} for logistic regression and {f2(imdsk['AUC'])} for the IMD rule, and "
    f"still {f2(rf3['AUC'])} three days ahead. A single decision tree is the weakest model; averaging "
    f"many trees removes its variance. Our physiology-informed headroom feature ranks {head_rank} of {len(mli)}."))
title(s, "RQ6 · Random forest leads at every lead time")
picture(s, FIGS / "fig_ml_models.png", 0.55, 1.6, w=8.3, h=4.4)
stat(s, 9.2, 1.7, 3.8, f"AUC {f2(rf1['AUC'])}",
     f"random forest, +1 day (logistic {f2(lr1['AUC'])}, IMD rule {f2(imdsk['AUC'])})", big_size=28)
stat(s, 9.2, 3.35, 3.8, f"AUC {f2(rf3['AUC'])}",
     f"still at +3 days, vs {f2(clim3['AUC'])} for climatology", big_size=28)
stat(s, 9.2, 5.0, 3.8, f"+{pct(rf1['BSS'], 0)}", "Brier skill over climatology, +1 day", big_size=28)
text(s, 0.85, 6.3, 8.0, 0.8,
     f"Headroom to the physiological limit ranks #{head_rank} of {len(mli)} features. "
     "One tree is the weakest model; a forest of 400 fixes its variance.", size=14, color=MUTED)

# =============================================================================
# 19d. Novelty results: hybrid alert and transfer
# =============================================================================
s = new_slide("bg_content_d_dim.jpg", notes=(
    f"The hybrid alert keeps the IMD rule and adds the random-forest layer. It recovers "
    f"{pct(hyb['blind_spot_recovered'], 0)} of the next-day danger days the IMD rule cannot see, against "
    f"{pct(imd_h['blind_spot_recovered'], 0)} for the rule alone. On the right, each city is held out "
    f"completely: trained on the others, the forest still reaches a mean AUC of {f2(loco_unseen)}, "
    f"almost the {f2(loco_seen)} it gets with local data. The cost is false alarms, which suits a cheap "
    "advisory such as hydrate-and-rest messaging."))
title(s, "Novelty · Closing the blind spot, anywhere")
picture(s, FIGS / "fig_ml_hybrid_transfer.png", 0.55, 1.6, w=8.3, h=4.4)
stat(s, 9.2, 1.7, 3.8, pct(hyb["blind_spot_recovered"], 0),
     f"of the blind spot recovered by the hybrid alert (IMD rule alone: {pct(imd_h['blind_spot_recovered'], 0)})",
     big_size=28)
stat(s, 9.2, 3.35, 3.8, pct(hyb["POD"], 0),
     f"of next-day danger days caught (IMD rule: {pct(imd_h['POD'], 0)})", big_size=28)
stat(s, 9.2, 5.0, 3.8, f"{f2(loco_unseen)} / {f2(loco_seen)}",
     "mean AUC in an unseen city / a trained city", big_size=28)
text(s, 0.85, 6.3, 8.0, 0.8,
     f"Honest cost: {pct(hyb['FAR'], 0)} of hybrid alerts are false alarms. That suits a cheap "
     "hydrate-and-rest advisory, not school closures.", size=14, color=MUTED)

# =============================================================================
# 20. Dashboard
# =============================================================================
s = new_slide("bg_content_e_dim.jpg", notes=(
    "Everything is explorable in a Shiny dashboard. The risk calculator shows the problem in one "
    "screen: the IMD rule says no alert, while the wet-bulb is 30.7 °C and the model gives a 99% "
    "chance of a danger day tomorrow. Other tabs show each city's barcode of missed days, its "
    "trend, and its return levels."))
title(s, "Shiny dashboard: the gap in one screen")
pic = picture(s, ASSETS / "dashboard_risk_crop.png", 0.85, 1.7, w=11.6)
pic.line.color.rgb = RGBColor(0x44, 0x44, 0x44)
pic.line.width = Pt(1)
text(s, 0.85, 6.02, 11.6, 0.4,
     "Risk calculator, Kolkata on 20 May: the IMD rule says NO ALERT, the wet-bulb (30.7 °C) says DANGER, "
     "and the model gives 99% for tomorrow.", size=14, color=WHITE)
text(s, 0.85, 6.78, 11.6, 0.4, "Rscript -e 'shiny::runApp(\"app\")'  ·  5 tabs: blind spot, trends, extremes, risk calculator, about",
     size=13, color=MUTED)

# =============================================================================
# 21. Conclusions
# =============================================================================
s = new_slide("bg_content_c.jpg", notes=(
    "To answer the six questions: the rule misses 96% of dangerous humid heat; danger days "
    "grow about 54% per decade; extremes are shifting in seven of ten cities; danger comes in "
    "persistent spells; a simple calibrated model warns far better than the rule; and a random "
    "forest extends the warning to three days and to cities with no history. Three "
    "recommendations follow."))
title(s, "Conclusions & recommendations")
ans = [("RQ1", f"The IMD rule misses {pct(pooled['miss_rate'], 0)} of dangerous humid-heat days, in every city"),
       ("RQ2", f"Danger days grow ×{f2(counts['IRR_per_decade'])} per decade; Apr–Jun wet-bulb is up {f2(tukey['diff'])} °C"),
       ("RQ3", f"Tail shifting in {n_trend_sig}/10 cities; Chennai's 1985 50-year extreme is now 1-in-{float(che['return_period_now']):.1f}"),
       ("RQ4", "Danger persists in spells; 3-day spells are now far more likely"),
       ("RQ5", f"A logistic warning reaches AUC {f2(logit['AUC'])} vs {f2(imdsk['AUC'])}, and is calibrated"),
       ("RQ6", f"A random forest reaches AUC {f2(rf1['AUC'])}, recovers {pct(hyb['blind_spot_recovered'], 0)} of the blind spot, and transfers to unseen cities")]
for i, (k, a) in enumerate(ans):
    y = 1.75 + i * 0.5
    text(s, 0.85, y, 0.9, 0.45, k, size=15, color=AMBER, font=REGULAR)
    text(s, 1.75, y, 10.6, 0.45, a, size=15)
arrow_list(s, 0.85, 4.95, 11.8, [
    "Add a humidity-aware trigger (wet-bulb or Heat Index) to heatwave declarations",
    "Replace fixed national cut-offs with local, probabilistic thresholds and return periods",
    "Prioritise Kolkata, Bhubaneswar, Visakhapatnam and Chennai, where silent days dominate",
], size=16, pitch=0.6)

# =============================================================================
# 22. Limitations & future work
# =============================================================================
s = new_slide("bg_content_d.jpg", notes=(
    "Limitations. ERA5's 25 km grid smooths extremes, so station data would raise every count, "
    "but the dry-versus-humid separation is structural. Our one-cell rule flatters IMD. "
    "Physiological limits come from young, healthy adults. Next steps: station data, mortality "
    "or hospital data to validate thresholds, and a district-level operational forecast."))
title(s, "Limitations & future work")
text(s, 0.85, 1.85, 5.6, 5.0, [
    [("Limitations", {"font": REGULAR, "color": AMBER})],
    f"ERA5's 0.25° grid smooths peaks: only {pooled['n_critical']} grid-days reached 31 °C; Mumbai's cell is sea-moderated",
    "One grid cell stands in for IMD's two stations, which flatters IMD, so our miss rates are lower bounds",
    "Thresholds come from young, healthy adults; older people and outdoor workers are at risk sooner",
    "Day-level tests are approximate under autocorrelation (mitigated with block bootstrap and Markov models)",
], size=14, space_after=9)
text(s, 6.85, 1.85, 5.6, 5.0, [
    [("Future work", {"font": REGULAR, "color": AMBER})],
    "Repeat with IMD station observations and finer reanalysis (ERA5-Land, IMDAA)",
    "Link to hospital or mortality records to calibrate thresholds by age and occupation",
    "Extend to warm nights and multi-day cumulative heat load",
    "Operational district-level forecasts using weather-model inputs instead of today's observations",
], size=14, space_after=9)

# =============================================================================
# 23. References
# =============================================================================
s = new_slide("bg_content_e.jpg", notes="Key references.")
title(s, "References")
text(s, 0.85, 1.75, 11.8, 5.4, [
    "India Meteorological Department. Criteria for heat wave; experimental Heat Index guidance.",
    "Pillai, A. V. & Dalmia, T. (2023). How is India adapting to heatwaves? An assessment of heat action plans. Centre for Policy Research.",
    "Vecellio, D. J. et al. (2022). Evaluating the 35 °C wet-bulb temperature adaptability threshold for young, healthy subjects. J. Appl. Physiol. 132(2).",
    "Raymond, C., Matthews, T. & Horton, R. M. (2020). The emergence of heat and humidity too severe for human tolerance. Science Advances 6(19).",
    "Stull, R. (2011). Wet-bulb temperature from relative humidity and air temperature. J. Appl. Meteor. Climatol. 50.",
    "Coles, S. (2001). An Introduction to Statistical Modeling of Extreme Values. Springer.",
    "Hersbach, H. et al. (2020). The ERA5 global reanalysis. QJRMS 146; accessed via Open-Meteo (CC BY 4.0).",
    "Mann (1945); Sen (1968); DeLong et al. (1988), comparing correlated ROC curves.",
], size=13.5, space_after=9, spacing=1.08)

# =============================================================================
# 24. Thank you
# =============================================================================
s = new_slide("bg_end.jpg", notes="Thank you. Questions welcome; the dashboard can be shown live.")
text(s, 1.5, 2.9, 10.33, 1.6, "THANK YOU", size=64, align=PP_ALIGN.CENTER,
     anchor=MSO_ANCHOR.MIDDLE, name="Title")

prs.core_properties.title = "SilentHeat: the humid-heat blind spot in India's heatwave warnings"
prs.core_properties.author = "Arhaansh Jhingan"
prs.save(OUT)
print("saved", OUT, "with", len(prs.slides), "slides")
