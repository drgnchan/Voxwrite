#!/usr/bin/env python3
"""Generate the original VoxWrite launcher icon for all desktop/mobile targets."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def gradient_layer() -> Image.Image:
    start = (145, 134, 232)
    middle = (102, 91, 181)
    end = (61, 52, 126)
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = max(0.0, min(1.0, (x * 0.42 + y * 0.78) / (SIZE * 1.20)))
            if t < 0.52:
                color = mix(start, middle, t / 0.52)
            else:
                color = mix(middle, end, (t - 0.52) / 0.48)
            pixels[x, y] = (*color, 255)
    return image


def render_icon(*, circular: bool = False) -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    box = (82, 72, 942, 932)

    shadow_mask = Image.new("L", (SIZE, SIZE), 0)
    shadow_draw = ImageDraw.Draw(shadow_mask)
    if circular:
        shadow_draw.ellipse((86, 84, 938, 936), fill=150)
    else:
        shadow_draw.rounded_rectangle((86, 84, 938, 936), radius=222, fill=150)
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(34))
    shadow = Image.new("RGBA", (SIZE, SIZE), (22, 18, 53, 0))
    shadow.putalpha(shadow_mask)
    canvas.alpha_composite(shadow)

    mask = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    if circular:
        mask_draw.ellipse(box, fill=255)
    else:
        mask_draw.rounded_rectangle(box, radius=220, fill=255)

    surface = gradient_layer()

    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((-180, -220, 700, 660), fill=(255, 255, 255, 30))
    glow_draw.ellipse((570, 610, 1110, 1130), fill=(29, 20, 75, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(34))
    surface.alpha_composite(glow)
    surface.putalpha(mask)
    canvas.alpha_composite(surface)

    wave_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    wave_shadow_draw = ImageDraw.Draw(wave_shadow)
    centers = [290, 364, 438, 512, 586, 660, 734]
    heights = [154, 258, 378, 500, 378, 258, 154]
    width = 48
    for center_x, height in zip(centers, heights):
        top = 504 - height // 2 + 18
        bottom = 504 + height // 2 + 18
        wave_shadow_draw.rounded_rectangle(
            (center_x - width // 2, top, center_x + width // 2, bottom),
            radius=width // 2,
            fill=(25, 17, 67, 90),
        )
    wave_shadow = wave_shadow.filter(ImageFilter.GaussianBlur(16))
    wave_shadow.putalpha(Image.composite(wave_shadow.getchannel("A"), Image.new("L", (SIZE, SIZE)), mask))
    canvas.alpha_composite(wave_shadow)

    wave = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    wave_draw = ImageDraw.Draw(wave)
    for center_x, height in zip(centers, heights):
        top = 504 - height // 2
        bottom = 504 + height // 2
        wave_draw.rounded_rectangle(
            (center_x - width // 2, top, center_x + width // 2, bottom),
            radius=width // 2,
            fill=(255, 255, 255, 250),
        )
    wave.putalpha(Image.composite(wave.getchannel("A"), Image.new("L", (SIZE, SIZE)), mask))
    canvas.alpha_composite(wave)
    return canvas


def save_resized(image: Image.Image, path: Path, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)


def main():
    icon = render_icon()
    round_icon = render_icon(circular=True)

    branding = ROOT / "artifacts" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    icon.save(branding / "voxwrite-icon-1024.png")
    round_icon.save(branding / "voxwrite-icon-round-1024.png")

    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, size in android_sizes.items():
        save_resized(icon, android_res / folder / "ic_launcher.png", size)
        save_resized(round_icon, android_res / folder / "ic_launcher_round.png", size)

    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    mac_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in mac_sizes:
        save_resized(icon, mac_dir / f"app_icon_{size}.png", size)

    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    ico_frames = [icon.resize((size, size), Image.Resampling.LANCZOS) for size in ico_sizes]
    ico_path = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    ico_frames[-1].save(ico_path, format="ICO", sizes=[(s, s) for s in ico_sizes])

    preview = Image.new("RGBA", (1500, 620), (241, 240, 246, 255))
    draw = ImageDraw.Draw(preview)
    draw.rounded_rectangle((70, 70, 550, 550), radius=54, fill=(255, 255, 255))
    draw.rounded_rectangle((570, 70, 1050, 550), radius=54, fill=(28, 27, 35))
    draw.rounded_rectangle((1070, 70, 1430, 550), radius=54, fill=(255, 255, 255))
    preview.alpha_composite(icon.resize((360, 360), Image.Resampling.LANCZOS), (130, 130))
    preview.alpha_composite(icon.resize((360, 360), Image.Resampling.LANCZOS), (630, 130))
    preview.alpha_composite(round_icon.resize((260, 260), Image.Resampling.LANCZOS), (1120, 180))
    preview.convert("RGB").save(branding / "voxwrite-icon-preview.png")


if __name__ == "__main__":
    main()
