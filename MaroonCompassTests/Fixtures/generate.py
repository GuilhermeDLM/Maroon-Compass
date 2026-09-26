"""Generate entirely synthetic schedule screenshots for local Vision evaluation.

Requires Pillow. No screenshot, account data, or university portal content is used.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


OUT = Path(__file__).parent


def font(size: int, bold: bool = False):
    candidates = [
        Path("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf"),
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default(size=size)


def card(name: str, lines: list[str], *, width: int, dark: bool = False,
         low_resolution: bool = False, crop_right: int = 0):
    background = "#17191F" if dark else "#F7F7F4"
    foreground = "#F7F7F4" if dark else "#1A1B20"
    muted = "#BABBC4" if dark else "#50545F"
    accent = "#D79AAB" if dark else "#6A3047"
    scale = width / 1200
    margin = int(66 * scale)
    line_height = int(82 * scale)
    height = int((260 + 82 * len(lines)) * scale)
    canvas = Image.new("RGB", (width, height), background)
    draw = ImageDraw.Draw(canvas)
    title_font = font(max(19, int(47 * scale)), bold=True)
    body_font = font(max(14, int(36 * scale)))
    draw.text((margin, margin), "Sample student schedule", font=title_font, fill=accent)
    draw.text((margin, margin + int(65 * scale)), "SYNTHETIC · FOR QA ONLY", font=font(max(12, int(25 * scale))), fill=muted)
    top = margin + int(150 * scale)
    for index, line in enumerate(lines):
        draw.text((margin, top + index * line_height), line, font=body_font, fill=foreground)
    if crop_right:
        canvas = canvas.crop((0, 0, width - crop_right, height))
    if low_resolution:
        canvas = canvas.resize((max(1, canvas.width // 2), max(1, canvas.height // 2)), Image.Resampling.BILINEAR)
        canvas = canvas.filter(ImageFilter.GaussianBlur(radius=1.3))
    canvas.save(OUT / name, optimize=True)


card("clean-light.png", [
    "MATH 251-502 Calculus 3",
    "Tue Thu 5:30 PM - 6:45 PM BLOC 1O9",
    "Wed RECITATION 09:10 - 10:00 BLOC 169",
    "CHEM 117-541 General Chemistry Laboratory",
    "Tue LAB 11:10 AM - 2:00 PM HELD 302",
], width=1200)

card("dark-compact.png", [
    "POLS 207-502 State and Local Government",
    "Mon Wed Fri 09:10 - 10:00 HECC 100",
    "ENGR 102-505 Engineering Lab I",
    "Mon LAB 17:10 - 18:00 ZACH 353",
    "Mon LAB 18:01 - 19:00 ZACH 353",
], width=900, dark=True)

card("cropped-missing-column.png", [
    "POLS 207-502 State and Local Government",
    "09:10 - 10:00",
    "MATH 251-502 Calculus 3",
    "Tue Thu 5:30 PM - 6:45 PM BLOC 1O9",
], width=900, crop_right=130)

card("blurry-low-resolution.png", [
    "CHEM 117-541 General Chemistry Laboratory",
    "Tue LAB 11:10 AM - 2:00 PM HELD 302",
    "MATH 251-502 Calculus 3",
    "Wed RECITATION 09:10 - 10:00 BLOC 169",
], width=900, low_resolution=True)

card("unrelated-text.png", [
    "MATH 251-502 Calculus 3",
    "Tue Thu 5:30 PM - 6:45 PM BLOC 1O9",
    "Dining hours 9:00 AM - 5:00 PM",
    "Campus news and account settings",
], width=1200)
