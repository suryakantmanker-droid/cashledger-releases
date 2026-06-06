"""
Premium Fintech App Icon Generator — Expense Tracker Pro
Produces 4 variations × 3 backgrounds = 12 PNGs at 1024×1024.
"""

from PIL import Image, ImageDraw, ImageFilter
import math, os

SIZE   = 1024
S      = SIZE
HALF   = S // 2
RADIUS = int(S * 0.225)   # icon corner radius

OUT = os.path.join(os.path.dirname(__file__), "assets", "images", "icons")
os.makedirs(OUT, exist_ok=True)

# ── Palette ──────────────────────────────────────────────────────────────────
NAVY1   = (4,   7,  24)          # deepest background
NAVY2   = (11,  18,  55)
NAVY3   = (22,  38, 100)
INDIGO  = (99, 102, 241)
PURPLE  = (124,  58, 237)
GREEN   = (52,  211, 153)        # emerald-400
GREENB  = (74,  222, 128)        # green-400
CYAN    = (34,  211, 238)        # cyan-400
CYANL   = (103, 232, 249)        # cyan-300
WHITE   = (255, 255, 255)
SILVER  = (190, 210, 245)
GOLD    = (251, 191,  36)
L1      = (220, 232, 255)        # light bg top
L2      = (248, 251, 255)        # light bg bottom


# ── Helpers ──────────────────────────────────────────────────────────────────

def new_rgba():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def vert_grad(c1, c2, alpha=255):
    img = new_rgba()
    d   = ImageDraw.Draw(img)
    for y in range(S):
        t   = y / (S - 1)
        col = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (alpha,)
        d.line([(0, y), (S, y)], fill=col)
    return img


def round_mask(radius=RADIUS):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S-1, S-1], radius=radius, fill=255)
    return m


def apply_round(img, radius=RADIUS):
    out = img.copy().convert("RGBA")
    mask = round_mask(radius)
    r, g, b, a = out.split()
    from PIL import ImageChops
    out.putalpha(ImageChops.multiply(a, mask))
    return out


def bg_dark():   return vert_grad(NAVY1, NAVY3)
def bg_light():  return vert_grad(L1, L2)
def bg_trans():  return new_rgba()


def add_layer(base, layer):
    return Image.alpha_composite(base, layer)


def glow_blob(cx, cy, r, color, peak=70):
    """Soft radial glow blob."""
    layer = new_rgba()
    d     = ImageDraw.Draw(layer)
    for i in range(r, 0, -4):
        t = i / r
        a = int(peak * 4 * t * (1 - t))          # parabola peaking at 0.5
        d.ellipse([cx-i, cy-i, cx+i, cy+i], fill=(*color, a))
    return layer


def glow_line(pts, color, lw=6, gr=14, ga=80):
    """Line with soft outer glow."""
    layer = new_rgba()
    d     = ImageDraw.Draw(layer)
    for i in range(gr, 0, -1):
        t = 1 - i / gr
        d.line(pts, fill=(*color, int(ga * t * t)), width=lw + i * 2)
    d.line(pts, fill=(*color, 255), width=lw)
    return layer


def peak_dot(cx, cy, outer_col, inner_col=WHITE, r=13):
    """Glowing endpoint dot."""
    layer = new_rgba()
    d     = ImageDraw.Draw(layer)
    # halo
    for i in range(r*3, r, -1):
        t = 1 - (i - r) / (r*2)
        d.ellipse([cx-i, cy-i, cx+i, cy+i], fill=(*outer_col, int(40*t)))
    # ring
    d.ellipse([cx-r-3, cy-r-3, cx+r+3, cy+r+3], fill=(*NAVY2, 255))
    d.ellipse([cx-r,   cy-r,   cx+r,   cy+r],   fill=(*outer_col, 255))
    d.ellipse([cx-r//2, cy-r//2, cx+r//2, cy+r//2], fill=(*inner_col, 255))
    return layer


def soft_shadow(x0, y0, x1, y1, cr, dy=18, strength=110):
    """Drop shadow for a rounded rect."""
    layer = new_rgba()
    d     = ImageDraw.Draw(layer)
    for i in range(30, 0, -1):
        a = int(strength * (i/30) ** 2)
        d.rounded_rectangle([x0-i, y0+dy-i, x1+i, y1+dy+i],
                             radius=cr+i, fill=(0, 0, 20, a))
    return layer.filter(ImageFilter.GaussianBlur(18))


def gradient_strip(x0, y0, x1, y1, c1, c2, card_cr, strip_h):
    """Horizontal gradient strip clipped to rounded-rect top."""
    layer = new_rgba()
    d     = ImageDraw.Draw(layer)
    for i in range(strip_h):
        t   = i / max(strip_h - 1, 1)
        col = tuple(int(c1[j] + (c2[j]-c1[j])*t) for j in range(3)) + (255,)
        d.line([(x0, y0+i), (x1, y0+i)], fill=col)
    # clip to rounded-rect top half only
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=card_cr, fill=255)
    ImageDraw.Draw(mask).rectangle([x0, y0+strip_h, x1, y1], fill=0)
    layer.putalpha(mask)
    return layer


# ── Variation 1 : Wallet Card + Rising Graph ──────────────────────────────────
def v1(bg_type="dark"):
    img = {"dark": bg_dark, "light": bg_light, "trans": bg_trans}[bg_type]()

    if bg_type == "dark":
        img = add_layer(img, glow_blob(HALF, HALF, int(S*.44), INDIGO, 55))

    # card geometry
    cw, ch = int(S*.65), int(S*.46)
    cr      = int(ch * .13)
    x0      = HALF - cw // 2
    y0      = HALF - ch // 2 + int(S*.01)

    # shadow
    img = add_layer(img, soft_shadow(x0, y0, x0+cw, y0+ch, cr, dy=20, strength=90))

    # card body
    body = new_rgba()
    bc   = (22, 32, 82, 238) if bg_type != "light" else (245, 248, 255, 238)
    ImageDraw.Draw(body).rounded_rectangle([x0, y0, x0+cw, y0+ch], radius=cr, fill=bc)
    img  = add_layer(img, body)

    # gradient header strip
    sh = int(ch * .33)
    c1_s = (67, 56, 202) if bg_type != "light" else INDIGO
    img  = add_layer(img, gradient_strip(x0, y0, x0+cw, y0+ch, c1_s, CYAN, cr, sh))

    draw = ImageDraw.Draw(img)

    # EMV chip
    cpx, cpy = x0 + int(cw*.09), y0 + int(ch*.08)
    cpw, cph  = int(cw*.17), int(ch*.15)
    draw.rounded_rectangle([cpx, cpy, cpx+cpw, cpy+cph],
                            radius=int(cph*.28), fill=(*GOLD, 255))
    for k in range(3):
        ly = cpy + int(cph*.20) + k * int(cph*.27)
        draw.rectangle([cpx+4, ly, cpx+cpw-4, ly+max(2,int(cph*.12))],
                       fill=(*NAVY2, 160))

    # NFC dots (right side of stripe)
    for k, r in enumerate([18, 13, 8]):
        ax = x0 + cw - int(cw*.08) - k*22
        ay = y0 + sh // 2
        draw.ellipse([ax-r, ay-r, ax+r, ay+r], fill=(*WHITE, 185 - k*50))

    # chart area
    px0, px1 = x0 + int(cw*.07), x0 + cw - int(cw*.07)
    py0, py1 = y0 + sh + int(ch*.10), y0 + ch - int(ch*.09)
    pw, ph    = px1-px0, py1-py0

    raw = [(0,.82),(0.14,.67),(0.27,.72),(0.41,.46),
           (0.55,.49),(0.67,.27),(0.79,.17),(0.90,.09),(1.0,.02)]
    pts = [(int(px0+x*pw), int(py0+y*ph)) for x, y in raw]

    # area-fill under line
    poly = pts + [(px1, py1), (px0, py1)]
    fill_l = new_rgba()
    fm     = Image.new("L", (S, S), 0)
    ImageDraw.Draw(fm).polygon(poly, fill=255)
    fd = ImageDraw.Draw(fill_l)
    for row in range(ph):
        t = row / ph
        fd.line([(px0, py0+row),(px1, py0+row)], fill=(*GREEN, int(28*(1-t))))
    fill_l.putalpha(fm)
    img = add_layer(img, fill_l)

    img = add_layer(img, glow_line(pts, GREEN, lw=6, gr=14, ga=85))
    img = add_layer(img, peak_dot(*pts[-1], GREEN, r=12))

    # subtle horizontal grid lines
    draw = ImageDraw.Draw(img)
    for k in range(1, 3):
        gy = py0 + int(ph * k / 3)
        draw.line([(px0, gy),(px1, gy)], fill=(*SILVER, 20), width=1)

    return apply_round(img)


# ── Variation 2 : Rupee Symbol + Bar Analytics ──────────────────────────────
def v2(bg_type="dark"):
    img = {"dark": bg_dark, "light": bg_light, "trans": bg_trans}[bg_type]()

    if bg_type == "dark":
        img = add_layer(img, glow_blob(HALF, int(S*.48), int(S*.46), (16,185,129), 50))

    # 3 ascending bars (behind the ₹)
    bar_count   = 4
    bar_gap     = int(S * .045)
    bar_w       = int(S * .085)
    total_bar_w = bar_count * bar_w + (bar_count-1) * bar_gap
    bar_x_start = HALF - total_bar_w // 2 + int(S*.01)
    bar_base    = int(S * .72)
    bar_heights = [int(S*.22), int(S*.33), int(S*.44), int(S*.55)]
    bar_cr      = int(bar_w * .28)
    bar_colors  = [
        (*GREEN, 60),
        (*GREEN, 90),
        (*CYAN, 110),
        (*CYAN, 140),
    ]

    bar_layer = new_rgba()
    bd        = ImageDraw.Draw(bar_layer)
    for k in range(bar_count):
        bx   = bar_x_start + k * (bar_w + bar_gap)
        bh   = bar_heights[k]
        by   = bar_base - bh
        col  = bar_colors[k]
        bd.rounded_rectangle([bx, by, bx+bar_w, bar_base],
                             radius=bar_cr, fill=col)

    # top caps glow
    for k in range(bar_count):
        bx  = bar_x_start + k*(bar_w+bar_gap)
        bh  = bar_heights[k]
        by  = bar_base - bh
        cx  = bx + bar_w//2
        cap = new_rgba()
        ImageDraw.Draw(cap).ellipse([cx-bar_w//2, by-4, cx+bar_w//2, by+bar_w//2],
                                    fill=(*CYAN, 80))
        bar_layer = add_layer(bar_layer, cap)

    img = add_layer(img, bar_layer)

    # ₹ symbol drawn with bold rectangles + line
    draw    = ImageDraw.Draw(img)
    sym_col = WHITE if bg_type != "light" else NAVY2
    sx      = HALF - int(S*.12)
    sy      = int(S*.26)
    sw      = int(S*.24)           # symbol width
    sh      = int(S*.46)           # symbol height
    lw      = int(S*.045)          # line thickness

    # Vertical stem
    draw.rectangle([sx, sy, sx+lw, sy+sh], fill=(*sym_col, 255))
    # Top horizontal bar
    draw.rounded_rectangle([sx, sy, sx+sw, sy+lw],
                            radius=lw//2, fill=(*sym_col, 255))
    # Middle horizontal bar
    mid_y = sy + int(sh * .32)
    draw.rounded_rectangle([sx, mid_y, sx+int(sw*.82), mid_y+lw],
                            radius=lw//2, fill=(*sym_col, 255))
    # Diagonal slash (bottom right)
    slash_pts = [
        sx + lw,         mid_y + lw + int(lw*.5),
        sx + sw + lw//2, sy + sh,
        sx + sw - lw//4, sy + sh,
        sx,              mid_y + lw + int(lw*.5),
    ]
    slash_layer = new_rgba()
    sd          = ImageDraw.Draw(slash_layer)
    sd.polygon(slash_pts, fill=(*sym_col, 255))
    img = add_layer(img, slash_layer)

    # Accent dot on top-right of ₹
    draw = ImageDraw.Draw(img)
    dot_col = CYAN if bg_type != "light" else INDIGO
    draw.ellipse([sx+sw-lw//2, sy-lw//2,
                  sx+sw+lw,    sy+lw],  fill=(*dot_col, 255))

    # Small upward arrow (top right of icon)
    arrow_col = GREEN
    acx = int(S * .76)
    acy = int(S * .26)
    ar  = int(S * .065)
    agl = new_rgba()
    ImageDraw.Draw(agl).ellipse([acx-ar-8, acy-ar-8, acx+ar+8, acy+ar+8],
                                fill=(*GREEN, 20))
    ImageDraw.Draw(agl).ellipse([acx-ar, acy-ar, acx+ar, acy+ar],
                                fill=(*GREEN, 255))
    aw = int(ar * .42)
    al = int(ar * .52)
    ImageDraw.Draw(agl).polygon([
        (acx,    acy - al),
        (acx-aw, acy + al//2),
        (acx+aw, acy + al//2),
    ], fill=(*WHITE, 255))
    img = add_layer(img, agl)

    return apply_round(img)


# ── Variation 3 : Abstract Finance Circle + Arrow ────────────────────────────
def v3(bg_type="dark"):
    img = {"dark": bg_dark, "light": bg_light, "trans": bg_trans}[bg_type]()

    if bg_type == "dark":
        img = add_layer(img, glow_blob(HALF, HALF, int(S*.46), PURPLE, 50))
        img = add_layer(img, glow_blob(int(S*.6), int(S*.4), int(S*.3), CYAN, 30))

    # Outer ring (donut) with gradient
    ring_r      = int(S * .355)
    ring_thick  = int(S * .065)
    GAP_DEG     = 55                    # gap at top of ring (degrees each side)
    ring_layer  = new_rgba()
    rd          = ImageDraw.Draw(ring_layer)

    # Draw ring as arc segments with colour sweep
    seg_count = 300
    start_deg = -90 + GAP_DEG
    end_deg   = 270 - GAP_DEG
    span      = end_deg - start_deg

    for k in range(seg_count):
        t     = k / seg_count
        angle = start_deg + t * span
        # colour sweep: GREEN → CYAN → GREEN
        t2 = abs(t - 0.5) * 2          # 0 at edges → 1 at midpoint
        col = tuple(int(CYAN[i] + (GREEN[i]-CYAN[i]) * t2) for i in range(3))
        a_rad = math.radians(angle)
        x1 = HALF + (ring_r - ring_thick//2) * math.cos(a_rad)
        y1 = HALF + (ring_r - ring_thick//2) * math.sin(a_rad)
        x2 = HALF + (ring_r + ring_thick//2) * math.cos(a_rad)
        y2 = HALF + (ring_r + ring_thick//2) * math.sin(a_rad)
        rd.line([(x1,y1),(x2,y2)], fill=(*col, 255), width=max(4, int(S*.008)))

    img = add_layer(img, ring_layer)

    # Ring glow (blur a thicker version)
    ring_glow = new_rgba()
    rgd       = ImageDraw.Draw(ring_glow)
    for k in range(seg_count):
        t     = k / seg_count
        angle = start_deg + t * span
        col   = GREEN
        a_rad = math.radians(angle)
        x1 = HALF + (ring_r-ring_thick) * math.cos(a_rad)
        y1 = HALF + (ring_r-ring_thick) * math.sin(a_rad)
        x2 = HALF + (ring_r+ring_thick) * math.cos(a_rad)
        y2 = HALF + (ring_r+ring_thick) * math.sin(a_rad)
        rgd.line([(x1,y1),(x2,y2)], fill=(*col, 30), width=int(S*.03))
    ring_glow = ring_glow.filter(ImageFilter.GaussianBlur(14))
    img       = add_layer(img, ring_glow)

    # End-cap glow dots on ring
    for angle_deg in [start_deg, end_deg]:
        a_rad = math.radians(angle_deg)
        ex    = HALF + ring_r * math.cos(a_rad)
        ey    = HALF + ring_r * math.sin(a_rad)
        img   = add_layer(img, glow_blob(int(ex), int(ey), int(S*.06), CYAN, 120))
        draw  = ImageDraw.Draw(img)
        dr    = int(S*.025)
        draw.ellipse([ex-dr, ey-dr, ex+dr, ey+dr], fill=(*CYANL, 255))

    # Bold upward arrow inside circle
    draw      = ImageDraw.Draw(img)
    arrow_col = WHITE if bg_type != "light" else NAVY2
    aw        = int(S * .095)         # arrow half-width
    ah        = int(S * .28)          # arrow height
    ax        = HALF
    ay_top    = HALF - int(S * .15)
    ay_bot    = HALF + int(S * .13)
    stem_w    = int(aw * .60)

    # Arrow head (triangle)
    arrow_layer = new_rgba()
    ad          = ImageDraw.Draw(arrow_layer)
    ad.polygon([
        (ax,       ay_top),
        (ax - aw,  ay_top + aw),
        (ax + aw,  ay_top + aw),
    ], fill=(*arrow_col, 255))

    # Arrow stem
    ad.rectangle([ax - stem_w//2, ay_top + aw - 4,
                  ax + stem_w//2, ay_bot],
                 fill=(*arrow_col, 255))

    # Small green dot on stem (percentage indicator)
    dot_y = ay_top + aw + int((ay_bot - ay_top - aw) * .55)
    dot_r = int(stem_w * .75)
    ad.ellipse([ax-dot_r, dot_y-dot_r, ax+dot_r, dot_y+dot_r],
               fill=(*NAVY2, 255))
    ad.ellipse([ax-dot_r+4, dot_y-dot_r+4, ax+dot_r-4, dot_y+dot_r-4],
               fill=(*CYAN, 255))

    img = add_layer(img, arrow_layer)

    # Small "%" text replaced by two small circles (minimalist)
    draw = ImageDraw.Draw(img)
    for dx, dy in [(-int(S*.085), int(S*.19)), (int(S*.085), int(S*.19))]:
        cr2 = int(S*.018)
        draw.ellipse([HALF+dx-cr2, HALF+dy-cr2, HALF+dx+cr2, HALF+dy+cr2],
                     fill=(*CYAN, 180))

    return apply_round(img)


# ── Variation 4 : Ultra Minimal Sparkline ────────────────────────────────────
def v4(bg_type="dark"):
    img = {"dark": bg_dark, "light": bg_light, "trans": bg_trans}[bg_type]()

    if bg_type == "dark":
        # Very subtle, deep glow
        img = add_layer(img, glow_blob(HALF, int(S*.52), int(S*.50), INDIGO, 35))

    # Single bold sparkline — S-curve rising left to right
    pad  = int(S * .18)
    lx0  = pad
    lx1  = S - pad
    ly0  = int(S * .33)
    ly1  = int(S * .70)
    lw   = lx1 - lx0
    lh   = ly1 - ly0

    # Smooth cubic-like curve via many small segments
    def cubic(t, p0, p1, p2, p3):
        u = 1-t
        return (u**3*p0 + 3*u**2*t*p1 + 3*u*t**2*p2 + t**3*p3)

    # Control points for a pleasant S-curve
    n_seg  = 200
    ctrl_x = [lx0, lx0+lw*.25, lx0+lw*.65, lx1]
    ctrl_y = [ly1, ly1-lh*.05, ly0+lh*.08, ly0]

    pts = []
    for k in range(n_seg+1):
        t  = k / n_seg
        px = cubic(t, *ctrl_x)
        py = cubic(t, *ctrl_y)
        pts.append((px, py))

    line_col = GREENB if bg_type != "light" else (16, 120, 80)

    # Area fill under curve
    fill_poly = pts + [(lx1, ly1+20), (lx0, ly1+20)]
    fill_l    = new_rgba()
    fm        = Image.new("L", (S, S), 0)
    ImageDraw.Draw(fm).polygon(fill_poly, fill=255)
    fd        = ImageDraw.Draw(fill_l)
    for row in range(lh + 30):
        t = row / (lh + 30)
        fd.line([(lx0, int(ly0)+row), (lx1, int(ly0)+row)],
                fill=(*line_col, int(22*(1-t))))
    fill_l.putalpha(fm)
    img = add_layer(img, fill_l)

    # Glow line (thick glow + crisp line)
    gl = new_rgba()
    gd = ImageDraw.Draw(gl)
    # outer glow
    for i in range(22, 0, -1):
        t = 1 - i/22
        gd.line(pts, fill=(*line_col, int(55*t*t)), width=8+i*2)
    # crisp line
    gd.line(pts, fill=(*line_col, 255), width=8)
    img = add_layer(img, gl)

    # Peak dot (top-right end)
    peak = pts[-1]
    img  = add_layer(img, glow_blob(int(peak[0]), int(peak[1]), int(S*.1), GREEN, 90))
    dr   = ImageDraw.Draw(img)
    dr.ellipse([peak[0]-20, peak[1]-20, peak[0]+20, peak[1]+20],
               fill=(*NAVY2, 255))
    dr.ellipse([peak[0]-14, peak[1]-14, peak[0]+14, peak[1]+14],
               fill=(*GREENB, 255))
    dr.ellipse([peak[0]-7,  peak[1]-7,  peak[0]+7,  peak[1]+7],
               fill=(*WHITE, 255))

    # Valley dot (start)
    start = pts[0]
    dr.ellipse([start[0]-10, start[1]-10, start[0]+10, start[1]+10],
               fill=(*line_col, 160))

    # Three tiny horizontal accent lines (bottom left — minimalist detail)
    if bg_type == "dark":
        accent_col = (*SILVER, 30)
    elif bg_type == "light":
        accent_col = (*NAVY3, 25)
    else:
        accent_col = (*WHITE, 25)
    for k in range(3):
        lly = int(S*.80) + k * int(S*.03)
        llw = int(S*.10) - k * int(S*.025)
        dr.rounded_rectangle([pad, lly, pad+llw, lly+int(S*.012)],
                              radius=int(S*.006), fill=accent_col)

    return apply_round(img)


# ── Render all variations ─────────────────────────────────────────────────────
print("Generating premium icons...")

variants = [
    ("v1_wallet_graph",      v1),
    ("v2_rupee_analytics",   v2),
    ("v3_abstract_circle",   v3),
    ("v4_ultra_minimal",     v4),
]
backgrounds = ["dark", "light", "trans"]

for name, fn in variants:
    for bg in backgrounds:
        icon = fn(bg)
        path = os.path.join(OUT, f"{name}_{bg}.png")
        icon.save(path, "PNG")
        print(f"  OK  {name}_{bg}.png")

# Also save V4 dark as the primary app_icon (best for dark launcher bg)
best = v4("dark")
primary = os.path.join(os.path.dirname(__file__), "assets", "images", "app_icon.png")
best.save(primary, "PNG")

# Transparent foreground from V4 for adaptive icon
fg_layer = v4("trans")
fg_path  = os.path.join(os.path.dirname(__file__), "assets", "images", "app_icon_foreground.png")
fg_layer.save(fg_path, "PNG")

print(f"\nOK Primary icon -> assets/images/app_icon.png")
print(f"OK Foreground   -> assets/images/app_icon_foreground.png")
print(f"OK All icons    -> assets/images/icons/")
print("\nNow run:  dart run flutter_launcher_icons")
