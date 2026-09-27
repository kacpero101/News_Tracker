#!/usr/bin/env python3
"""Generates the News Tracker app icon (1024x1024 PNG, no alpha channel).

Usage: python3 Tools/generate_app_icon.py  (requires Pillow: pip install pillow)
Writes NewsTrackerApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

SCALE = 2           # draw at 2048 px, then downsample for smooth edges
SIZE = 1024 * SCALE

NAVY = (11, 47, 107)
TEAL = (26, 167, 161)
WHITE = (255, 255, 255)
LINE_GREY = (199, 210, 228)
ORANGE = (255, 138, 0)

OUTPUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "NewsTrackerApp", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png",
)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background():
    """Diagonal navy → teal gradient with a soft highlight in the top-left corner."""
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * (SIZE - 1))
            pixels[x, y] = lerp(NAVY, TEAL, t)
    glow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(glow).ellipse((-SIZE * 0.3, -SIZE * 0.35, SIZE * 0.7, SIZE * 0.55), fill=34)
    glow = glow.filter(ImageFilter.GaussianBlur(SIZE * 0.12))
    return Image.composite(Image.new("RGB", (SIZE, SIZE), WHITE), image, glow)


def s(value):
    """Design units (1024 grid) → pixels."""
    return round(value * SCALE)


def draw_icon():
    image = background()

    # Card with a soft drop shadow.
    card = (s(212), s(162), s(812), s(862))
    shadow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (card[0], card[1] + s(22), card[2], card[3] + s(22)), radius=s(56), fill=110
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(24)))
    image = Image.composite(Image.new("RGB", (SIZE, SIZE), (5, 20, 45)), image, shadow)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(card, radius=s(56), fill=WHITE)

    # Headline bar and text lines.
    left, right = s(272), s(752)
    draw.rounded_rectangle((left, s(226), right, s(286)), radius=s(30), fill=NAVY)
    for top, width in ((326, 480), (376, 480), (426, 320)):
        draw.rounded_rectangle((left, s(top), left + s(width), s(top + 28)), radius=s(14), fill=LINE_GREY)

    # Rising price chart with a filled area and an arrow head.
    chart = [(282, 782), (402, 682), (488, 730), (608, 598), (718, 502)]
    points = [(s(x), s(y)) for x, y in chart]
    baseline = s(806)
    area = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(area).polygon(points + [(points[-1][0], baseline), (points[0][0], baseline)], fill=70)
    image = Image.composite(Image.new("RGB", (SIZE, SIZE), ORANGE), image, area)
    draw = ImageDraw.Draw(image)
    width = s(34)
    draw.line(points[:-1] + [points[-1]], fill=ORANGE, width=width, joint="curve")
    for x, y in points[:1]:
        draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=ORANGE)

    # Arrow head along the last segment.
    (x1, y1), (x2, y2) = points[-2], points[-1]
    angle = math.atan2(y2 - y1, x2 - x1)
    length, spread = s(92), math.radians(32)
    tip = (x2 + math.cos(angle) * s(24), y2 + math.sin(angle) * s(24))
    head = [
        tip,
        (tip[0] - length * math.cos(angle - spread), tip[1] - length * math.sin(angle - spread)),
        (tip[0] - length * math.cos(angle + spread), tip[1] - length * math.sin(angle + spread)),
    ]
    draw.polygon(head, fill=ORANGE)

    return image.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    icon = draw_icon()
    icon.save(OUTPUT, "PNG")
    print("Saved", os.path.normpath(OUTPUT), icon.size, icon.mode)
