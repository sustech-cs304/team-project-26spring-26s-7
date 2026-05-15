"""Share-poster composition (v1.1).

Builds a 750x1334 portrait JPG combining:
  * cover photo (top half)
  * trip title + meta chips + route preview
  * QR code linking to the share URL

Used by `GET /share/{shortcode}/poster.jpg` to serve a single-image
"share to anyone" artifact. The QR encodes the full signed share URL,
so scanning takes the recipient straight to /s/{code}?t=&s=.

Fonts: Noto Sans CJK SC is required on the server (server has it under
/data2/cse12310817/.fonts/). If missing → falls back to PIL default.
"""
from __future__ import annotations

import io
from pathlib import Path
from typing import Optional

import qrcode
from PIL import Image, ImageDraw, ImageFont


# Canvas — 750×1334 (mobile portrait standard)
# 之前 COVER_H 设到 750 让封面是正方形，但加上标题/元数据/QR 就溢出底部了。
# 600 给封面够大（4:3），剩余 734 px 容纳文字 + 320 QR + 标签 + footer 还有余。
W, H = 750, 1334
COVER_H = 600
PADDING = 56

# Font discovery — try common CJK fonts in order. Server has Noto Sans CJK SC.
_FONT_CANDIDATES = [
    "/data2/cse12310817/.fonts/NotoSansCJKsc-VF.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
]


def _font(size: int) -> ImageFont.ImageFont:
    for p in _FONT_CANDIDATES:
        if Path(p).is_file():
            try:
                return ImageFont.truetype(p, size=size)
            except Exception:
                pass
    # 兜底：默认字体（不支持中文，但避免 500）
    return ImageFont.load_default()


def _make_qr(url: str, size_px: int) -> Image.Image:
    """Build a black/white QR PNG sized to fit `size_px` square."""
    qr = qrcode.QRCode(
        version=None,                       # auto-size based on URL length
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=2,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#111111", back_color="#FFFFFF").convert("RGB")
    if img.size[0] != size_px:
        img = img.resize((size_px, size_px), resample=Image.NEAREST)
    return img


def _ellipsize(draw: ImageDraw.ImageDraw, text: str,
               font: ImageFont.ImageFont, max_w: int) -> str:
    """Cut `text` and append '…' so it fits in `max_w` px when drawn."""
    if not text:
        return ""
    if draw.textlength(text, font=font) <= max_w:
        return text
    out = text
    while out and draw.textlength(out + "…", font=font) > max_w:
        out = out[:-1]
    return (out + "…") if out else "…"


def _draw_cover(canvas: Image.Image, cover_path: Optional[Path]) -> None:
    """Cover photo top section. Crop-to-fill so it always looks tight."""
    if cover_path and cover_path.is_file():
        try:
            with Image.open(cover_path) as src:
                src = src.convert("RGB")
                # crop-to-fill into (W × COVER_H)
                src_ratio = src.width / src.height
                target_ratio = W / COVER_H
                if src_ratio > target_ratio:
                    # source is wider: crop horizontally
                    new_w = int(src.height * target_ratio)
                    left = (src.width - new_w) // 2
                    src = src.crop((left, 0, left + new_w, src.height))
                else:
                    # source is taller: crop vertically
                    new_h = int(src.width / target_ratio)
                    top = (src.height - new_h) // 2
                    src = src.crop((0, top, src.width, top + new_h))
                src = src.resize((W, COVER_H), resample=Image.LANCZOS)
                canvas.paste(src, (0, 0))
                return
        except Exception:
            pass
    # fallback: gradient block when no cover
    draw = ImageDraw.Draw(canvas)
    for y in range(COVER_H):
        # vertical gradient from accent blue to lighter blue
        t = y / COVER_H
        r = int(24 + (200 - 24) * t)
        g = int(144 + (220 - 144) * t)
        b = int(255 + (240 - 255) * t)
        draw.line([(0, y), (W, y)], fill=(r, g, b))


def compose_poster(
    share_url: str,
    trip_name: str,
    node_count: int,
    total_distance: float,
    route_preview: str,
    cover_path: Optional[Path],
) -> bytes:
    """Render the poster to a JPG byte stream.

    `route_preview` already formatted by caller (e.g. "红树林 → 深圳湾 → 科技园").
    Empty string if no preview to show.
    """
    canvas = Image.new("RGB", (W, H), (255, 255, 255))
    _draw_cover(canvas, cover_path)

    draw = ImageDraw.Draw(canvas)

    # ---- text section ----
    f_title = _font(48)
    f_meta = _font(28)
    f_preview = _font(26)
    f_caption = _font(24)
    f_footer = _font(22)

    text_x = PADDING
    text_max_w = W - 2 * PADDING

    # Title (1 line, ellipsize)
    title = _ellipsize(draw, trip_name or "ItsMapPin 分享",
                       f_title, text_max_w)
    title_y = COVER_H + 32
    draw.text((text_x, title_y), title, font=f_title, fill=(26, 26, 26))

    # Meta chip: "N 节点 · X.Xkm"
    chip_parts: list[str] = []
    if node_count:
        chip_parts.append(f"{node_count} 节点")
    if total_distance and total_distance > 0:
        chip_parts.append(f"{total_distance:.1f}km")
    chip = " · ".join(chip_parts) if chip_parts else ""
    meta_y = title_y + 64
    if chip:
        draw.text((text_x, meta_y), chip, font=f_meta, fill=(107, 114, 128))

    # Route preview (1 line, ellipsize)
    preview_y = meta_y + 42
    if route_preview:
        preview = _ellipsize(draw, route_preview, f_preview, text_max_w)
        draw.text((text_x, preview_y), preview,
                  font=f_preview, fill=(107, 114, 128))

    # ---- QR section ----
    qr_size = 320
    qr_y = preview_y + 60
    qr_x = (W - qr_size) // 2

    qr_img = _make_qr(share_url, qr_size)
    canvas.paste(qr_img, (qr_x, qr_y))

    # subtle border around QR
    draw.rectangle(
        [qr_x - 2, qr_y - 2, qr_x + qr_size + 2, qr_y + qr_size + 2],
        outline=(229, 231, 235), width=2,
    )

    # caption below QR
    cap_y = qr_y + qr_size + 28
    cap = "扫码查看完整路线"
    cap_w = draw.textlength(cap, font=f_caption)
    draw.text(((W - cap_w) / 2, cap_y), cap,
              font=f_caption, fill=(75, 85, 99))

    # footer pinned to bottom
    foot_y = H - 44
    footer = "ItsMapPin · 旅行回放"
    foot_w = draw.textlength(footer, font=f_footer)
    draw.text(((W - foot_w) / 2, foot_y), footer,
              font=f_footer, fill=(156, 163, 175))

    # ---- output ----
    buf = io.BytesIO()
    canvas.save(buf, format="JPEG", quality=88, optimize=True)
    return buf.getvalue()
