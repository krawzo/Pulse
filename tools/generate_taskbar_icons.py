"""Regenerate the monochrome Windows taskbar thumbnail icons (requires Pillow)."""

from pathlib import Path

from PIL import Image, ImageDraw


TARGET = Path(__file__).resolve().parents[1] / "windows" / "runner" / "resources"
WHITE = (255, 255, 255, 255)


def make_icon(name: str) -> None:
    image = Image.new("RGBA", (128, 128))
    draw = ImageDraw.Draw(image)
    if name in ("play", "next", "previous"):
        if name == "play":
            draw.polygon([(44, 27), (44, 101), (99, 64)], fill=WHITE)
        elif name == "next":
            draw.polygon([(24, 30), (24, 98), (83, 64)], fill=WHITE)
            draw.rounded_rectangle((88, 27, 101, 101), radius=3, fill=WHITE)
        else:
            draw.rounded_rectangle((27, 27, 40, 101), radius=3, fill=WHITE)
            draw.polygon([(45, 64), (104, 30), (104, 98)], fill=WHITE)
    elif name == "pause":
        draw.rounded_rectangle((35, 27, 52, 101), radius=4, fill=WHITE)
        draw.rounded_rectangle((76, 27, 93, 101), radius=4, fill=WHITE)
    else:
        points = [(64, 105), (25, 70), (20, 59), (20, 47), (27, 35),
                  (38, 29), (50, 31), (64, 43), (78, 31), (90, 29),
                  (101, 35), (108, 47), (108, 59), (103, 70)]
        draw.line(points + [points[0]], fill=WHITE, width=10, joint="curve")
        if name == "favorite_on":
            draw.polygon(points, fill=WHITE)
    image.save(TARGET / f"taskbar_{name}.ico", format="ICO",
               sizes=[(16, 16), (24, 24), (32, 32), (48, 48)])


for icon in ("favorite", "favorite_on", "previous", "play", "pause", "next"):
    make_icon(icon)
