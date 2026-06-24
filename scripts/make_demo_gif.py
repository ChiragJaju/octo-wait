#!/usr/bin/env python3
"""
Generates an illustrative demo GIF for octo-wait (no real screen capture).
It mocks the player window and animates the core loop:
  idle/paused  ->  prompt submitted (plays)  ->  AI stops (pause + remember spot)
  ->  next prompt (RESUMES from the remembered timestamp).

Output: assets/demo.gif
"""
import math, os
from PIL import Image, ImageDraw, ImageFont

W, H = 760, 480
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "demo.gif")

# palette (matches player.html)
BG      = (11, 16, 32)
BAR     = (17, 24, 51)
BORDER  = (29, 39, 72)
TEXT    = (230, 236, 255)
MUTED   = (159, 176, 216)
GREEN   = (56, 211, 159)
AMBER   = (240, 166, 74)
RED     = (255, 70, 70)
OCEAN1  = (16, 52, 96)
OCEAN2  = (8, 28, 60)
OCTO    = (90, 150, 240)
OCTO_D  = (60, 110, 200)

F  = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FM = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
def font(path, sz): return ImageFont.truetype(path, sz)
f_status = font(FB, 20); f_small = font(F, 15); f_pill = font(FB, 13)
f_time = font(FM, 15); f_term = font(FM, 15); f_cap = font(FB, 17)

def rr(d, box, r, **kw): d.rounded_rectangle(box, radius=r, **kw)

def mmss(s):
    s = int(s); return f"{s//60}:{s%60:02d}"

def octopus(d, cx, cy, bob, wig):
    """A cute (generic) blue octopus — a nod to Oswald, not a copy."""
    cy += int(3*math.sin(bob))
    # tentacles
    for k in range(6):
        ang = math.pi*(0.15 + 0.7*k/5)
        bx = cx - 46 + k*18
        for j in range(5):
            t = j/4.0
            x = bx + 10*math.sin(wig + k + t*3)
            y = cy + 30 + t*42
            rad = 8 - 5*t
            d.ellipse([x-rad, y-rad, x+rad, y+rad], fill=OCTO_D)
    # head
    d.ellipse([cx-52, cy-58, cx+52, cy+40], fill=OCTO)
    # eyes
    for ex in (-20, 20):
        d.ellipse([cx+ex-15, cy-30, cx+ex+15, cy], fill=(255,255,255))
        d.ellipse([cx+ex-6, cy-22, cx+ex+6, cy-10], fill=(20,28,50))
    # smile
    d.arc([cx-22, cy-8, cx+22, cy+22], start=10, end=170, fill=(20,28,50), width=4)

def frame(state):
    img = Image.new("RGB", (W, H), (6, 9, 20))
    d = ImageDraw.Draw(img)
    # window
    rr(d, [16, 16, W-16, H-16], 18, fill=BG, outline=BORDER, width=2)
    # ---- top bar ----
    rr(d, [16, 16, W-16, 70], 18, fill=BAR)
    d.rectangle([16, 50, W-16, 70], fill=BAR)
    playing = state["playing"]
    dot = GREEN if playing else AMBER
    # pulsing dot when playing
    pr = 8 + (2*abs(math.sin(state["i"]*0.5)) if playing else 0)
    d.ellipse([40-pr, 43-pr, 40+pr, 43+pr], fill=dot)
    d.text((58, 33), state["status"], font=f_status, fill=TEXT)
    # episode title (right)
    ep = "Oswald — “Catrina’s Cake”"
    tw = d.textlength(ep, font=f_small)
    d.text((W-40-tw-92, 36), ep, font=f_small, fill=MUTED)
    # pill
    rr(d, [W-40-84, 31, W-40, 55], 12, outline=BORDER, width=2)
    d.text((W-40-72, 35), "octo-wait", font=f_pill, fill=MUTED)

    # ---- video area ----
    vx0, vy0, vx1, vy1 = 36, 86, W-36, 360
    for yy in range(vy0, vy1):
        t = (yy-vy0)/(vy1-vy0)
        c = tuple(int(OCEAN1[k]+(OCEAN2[k]-OCEAN1[k])*t) for k in range(3))
        d.line([vx0, yy, vx1, yy], fill=c)
    # bubbles
    for bx,by,br in [(120,300,5),(160,250,3),(620,310,6),(560,260,4),(300,330,3)]:
        oy = (state["i"]*4) % 60
        d.ellipse([bx-br, by-oy-br, bx+br, by-oy+br], outline=(120,160,210), width=2)
    octopus(d, W//2, 232, state["i"]*0.6, state["i"]*0.8)

    # center play/pause glyph (semi-transparent)
    gl = Image.new("RGBA", (W, H), (0,0,0,0)); gd = ImageDraw.Draw(gl)
    cx, cy = W//2, 232
    if playing:
        gd.polygon([(cx-16,cy-22),(cx-16,cy+22),(cx+22,cy)], fill=(255,255,255,70))
    else:
        gd.rectangle([cx-20,cy-22,cx-6,cy+22], fill=(255,255,255,120))
        gd.rectangle([cx+6,cy-22,cx+20,cy+22], fill=(255,255,255,120))
    img.paste(Image.alpha_composite(img.convert("RGBA"), gl).convert("RGB"))
    d = ImageDraw.Draw(img)

    # progress bar
    dur = 690.0
    cur = state["time"]
    px0, px1, py = vx0+14, vx1-14, vy1-22
    d.rounded_rectangle([px0, py, px1, py+6], 3, fill=(255,255,255,60), outline=None)
    d.rounded_rectangle([px0, py, px0+(px1-px0)*(cur/dur), py+6], 3, fill=RED)
    knob = px0+(px1-px0)*(cur/dur)
    d.ellipse([knob-7, py-4, knob+7, py+10], fill=RED)
    d.text((px0, py-26), mmss(cur), font=f_time, fill=(255,255,255))
    rdur = mmss(dur); d.text((px1-d.textlength(rdur, font=f_time), py-26), rdur, font=f_time, fill=MUTED)

    # caption under video (key messaging)
    if state.get("cap"):
        capcol = state.get("capcol", GREEN)
        cw = d.textlength(state["cap"], font=f_cap)
        d.text(((W-cw)//2, 372), state["cap"], font=f_cap, fill=capcol)

    # ---- terminal strip ----
    rr(d, [36, 404, W-36, H-26], 10, fill=(9, 13, 26), outline=BORDER, width=2)
    y = 414
    for line, col in state["term"]:
        d.text((52, y), line, font=f_term, fill=col); y += 22
    return img

# ---------- timeline ----------
frames, durations = [], []
clock = {"t": 42.0, "i": 0}
def add(n, playing, status, term, cap=None, capcol=GREEN, adv=2.0, ms=90):
    for _ in range(n):
        if playing: clock["t"] += adv
        frames.append(frame({"playing":playing,"status":status,"time":clock["t"],
                              "term":term,"cap":cap,"capcol":capcol,"i":clock["i"]}))
        durations.append(ms); clock["i"] += 1

idle = [("❯ ", MUTED), ("✓ done — your turn", (120,200,150))]
work1 = [("❯ refactor the auth module", TEXT), ("● Claude is working…", GREEN)]
stop  = [("❯ refactor the auth module", MUTED), ("✓ done — your turn", (120,200,150))]
work2 = [("❯ now add tests for it", TEXT), ("● Claude is working…", GREEN)]

# A) idle / paused
add(6, False, "Idle — paused", idle, cap="waiting for a prompt", capcol=AMBER, ms=110)
# B) prompt submitted -> plays
add(14, True,  "AI is working — playing", work1, cap="prompt sent → Oswald plays", ms=85)
remembered = clock["t"]
# C) AI stops -> pause, freeze the timestamp
add(8, False, "Idle — paused", stop, cap=f"AI stopped → paused at {mmss(remembered)}", capcol=AMBER, ms=130)
# D) next prompt -> RESUMES from the remembered spot
add(16, True,  "AI is working — playing", work2,
    cap=f"next prompt → resumes from {mmss(remembered)} ▶", ms=85)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
frames[0].save(OUT, save_all=True, append_images=frames[1:], duration=durations,
               loop=0, optimize=True, disposal=2)
print("wrote", os.path.abspath(OUT), "frames:", len(frames),
      "size:", round(os.path.getsize(OUT)/1024,1), "KB")
PY = None
