"""Generate CivLink icon: civilization hexagon + LAN network nodes.
Original artwork, no official Civilization VI assets. Navy + gold palette.
Renders at 512px with supersampling, then emits a multi-size ICO.
"""
import math
from PIL import Image, ImageDraw

S = 512
CENTER = S / 2
NAVY = (30, 58, 95, 255)        # #1E3A5F
NAVY_DK = (19, 39, 66, 255)     # #132742
GOLD = (240, 183, 71, 255)      # #F0B747
GOLD_LT = (255, 214, 128, 255)  # #FFD680
WHITE = (244, 248, 252, 255)
NODE = (37, 99, 235, 255)       # #2563EB accent-blue node

def hexpts(cx, cy, r, rot=-math.pi / 2):
    return [(cx + r * math.cos(rot + i * math.pi / 3),
             cy + r * math.sin(rot + i * math.pi / 3)) for i in range(6)]

def render():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Rounded navy tile background
    pad = 22
    d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=96, fill=NAVY,
                        outline=NAVY_DK, width=8)

    # Subtle inner hexagon "civilization tile" (dark, slightly smaller)
    inner = hexpts(CENTER, CENTER + 6, 178)
    d.polygon(inner, fill=NAVY_DK)

    # Gold hexagon outline (the Civ-style tile edge)
    outer = hexpts(CENTER, CENTER, 186)
    d.line(outer + [outer[0]], fill=GOLD, width=20, joint="curve")

    # Network edges: from center to each vertex plus a ring, forming a LAN mesh
    v = hexpts(CENTER, CENTER, 120)
    for p in v:
        d.line([(CENTER, CENTER), p], fill=GOLD_LT, width=10)
    d.line(v + [v[0]], fill=GOLD_LT, width=10, joint="curve")

    # Nodes: blue circles with white core at each vertex, gold node at center
    node_r = 26
    for (x, y) in v:
        d.ellipse([x - node_r, y - node_r, x + node_r, y + node_r], fill=NODE,
                  outline=WHITE, width=6)
        d.ellipse([x - 8, y - 8, x + 8, y + 8], fill=WHITE)
    cr = 34
    d.ellipse([CENTER - cr, CENTER - cr, CENTER + cr, CENTER + cr], fill=GOLD,
              outline=WHITE, width=7)
    d.ellipse([CENTER - 12, CENTER - 12, CENTER + 12, CENTER + 12], fill=NAVY_DK)
    return img

def main():
    big = render()
    sizes = [256, 128, 64, 48, 32, 16]
    frames = []
    for s in sizes:
        frames.append(big.resize((s, s), Image.LANCZOS))
    out = r"C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink\gui-tauri\src-tauri\icons\icon.ico"
    frames[0].save(out, format="ICO", sizes=[(s, s) for s in sizes])
    # Also a PNG preview for the user
    big.resize((256, 256), Image.LANCZOS).save(
        r"C:\Users\dd\Desktop\injciv6-v0.3.3\icon-new-preview.png")
    print("wrote", out)

if __name__ == "__main__":
    main()
