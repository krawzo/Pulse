"""Resize the existing Pulse artwork for Android's legacy launcher densities."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "windows/runner/resources/pulse_icon_source.png"
RES = ROOT / "android/app/src/main/res"
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def main() -> None:
    image = Image.open(SOURCE).convert("RGB")
    # The supplied image has generous black padding. This fixed square crop
    # keeps the entire mark while using more of each launcher icon's area.
    cropped = image.crop((150, 150, 1130, 1130))
    for density, size in DENSITIES.items():
        target = RES / f"mipmap-{density}/ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        cropped.resize((size, size), Image.Resampling.LANCZOS).save(target)


if __name__ == "__main__":
    main()
