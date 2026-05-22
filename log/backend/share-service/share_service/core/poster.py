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

import math
from pathlib import Path
from typing import Optional, Tuple

import qrcode
from PIL import Image, ImageDraw, ImageFilter, ImageFont


# Canvas — 750×1334 (mobile portrait standard)
# 之前 COVER_H 设到 750 让封面是正方形，但加上标题/元数据/QR 就溢出底部了。
# 600 给封面够大（4:3），剩余 734 px 容纳文字 + 320 QR + 标签 + footer 还有余。
W, H = 750, 1334
S = 3  # 抗锯齿倍率：先 3 倍绘制，再缩回 750x1334

MAIN_CARD = (29, 36, 693, 1264)
COVER_BOX = (38, 43, 674, 492)
INFO_PANEL = (39, 544, 672, 754)

TITLE_POS = (78, 581)
TITLE_MAX_W = 300
TITLE_STAR = (343, 592)
TITLE_DOTS = (369, 598, 506)
MAP_ICON_BOX = (556, 594, 120, 90)

META_CHIP = (75, 668, 265, 45)
ROUTE_BAR = (60, 732, 630, 62)

QR_CARD = (216, 815, 318, 318)
QR_IMG = (234, 833, 282, 282)
CAPTION_Y = 1144
FOOTER_Y = 1224

BG_TOP = "#FCF4EC"
BG_BOTTOM = "#F7E9DA"
CARD = "#FFFFFF"
PANEL = "#FBF1E6"
PANEL_2 = "#F8EBDD"
BROWN = "#482C11"
TEXT_BROWN = "#60401F"
TEXT_ROUTE = "#6A4A2E"
TEXT_GREY = "#67615C"
FOOTER_GREY = "#7B7774"
GOLD = "#DDB582"
GOLD_DARK = "#D5A467"
GOLD_LIGHT = "#E8C996"
MAP_LIGHT = "#F1D9B8"
ROUTE_BG = "#F8EEE1"
ROUTE_BORDER = "#EEDDC6"
WAVE = "#F7E8D8"

# Font discovery — try common CJK fonts in order. Server has Noto Sans CJK SC.
# _FONT_CANDIDATES = [
#     "/data2/cse12310817/.fonts/NotoSansCJKsc-VF.ttf",
#     "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
#     "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
#     "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
# ]

_TITLE_FONT_CANDIDATES = [
    "/data2/cse12310817/.fonts/NotoSerifCJKsc-Regular.otf",
    "/data2/cse12310817/.fonts/NotoSansCJKsc-VF.ttf",
    "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSerifCJK-Regular.ttc",
    "/usr/share/fonts/truetype/arphic/ukai.ttc",
    "C:/Windows/Fonts/STXINGKA.TTF",
    "C:/Windows/Fonts/STKAITI.TTF",
    "C:/Windows/Fonts/simkai.ttf",
    "C:/Windows/Fonts/simsun.ttc",
]

_BODY_FONT_CANDIDATES = [
    "/data2/cse12310817/.fonts/NotoSansCJKsc-VF.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/msyhbd.ttc",
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/simsun.ttc",
]


def _font(size: int, kind: str = "body") -> ImageFont.ImageFont:
    candidates = _TITLE_FONT_CANDIDATES if kind == "title" else _BODY_FONT_CANDIDATES
    for p in candidates:
        if Path(p).is_file():
            try:
                return ImageFont.truetype(p, size=size * S)
            except Exception:
                pass
    # 兜底：默认字体（不支持中文，但避免 500）
    return ImageFont.load_default()

# def _font(size: int) -> ImageFont.ImageFont:
#     for p in _FONT_CANDIDATES:
#         if Path(p).is_file():
#             try:
#                 return ImageFont.truetype(p, size=size)
#             except Exception:
#                 pass
#     # 兜底：默认字体（不支持中文，但避免 500）
#     return ImageFont.load_default()


def _xy(v: float) -> int:
    return int(round(v * S))


def _box(box: Tuple[int, int, int, int]) -> Tuple[int, int, int, int]:
    x, y, w, h = box
    return _xy(x), _xy(y), _xy(x + w), _xy(y + h)


def _rgba(hex_color: str, alpha: int = 255) -> Tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def _linear_gradient(size: Tuple[int, int], top: str, bottom: str) -> Image.Image:
    w, h = size
    t = tuple(int(top.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    b = tuple(int(bottom.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        r = y / max(1, h - 1)
        col = tuple(int(t[i] * (1 - r) + b[i] * r) for i in range(3))
        draw.line((0, y, w, y), fill=col)
    return img.convert("RGBA")


def _add_shadow(base: Image.Image, box: Tuple[int, int, int, int], radius: int,
                blur: int = 18, offset: Tuple[int, int] = (0, 8),
                color: Tuple[int, int, int, int] = (110, 78, 45, 46)) -> None:
    x, y, w, h = box
    mask = Image.new("L", base.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(
        [_xy(x + offset[0]), _xy(y + offset[1]),
         _xy(x + offset[0] + w), _xy(y + offset[1] + h)],
        radius=_xy(radius),
        fill=255,
    )
    mask = mask.filter(ImageFilter.GaussianBlur(_xy(blur)))
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(Image.new("RGBA", base.size, color), (0, 0), mask)
    base.alpha_composite(layer)


def _rounded_rect(draw: ImageDraw.ImageDraw, box: Tuple[int, int, int, int], radius: int,
                  fill: Tuple[int, int, int, int],
                  outline: Optional[Tuple[int, int, int, int]] = None,
                  width: int = 1) -> None:
    draw.rounded_rectangle(
        _box(box),
        radius=_xy(radius),
        fill=fill,
        outline=outline,
        width=_xy(width) if outline else 1,
    )


def _draw_dotted_line(draw: ImageDraw.ImageDraw, x1: int, y: int, x2: int,
                      color: str = GOLD_LIGHT, alpha: int = 150,
                      dash: int = 3, gap: int = 6, width: int = 1) -> None:
    cur = x1
    while cur < x2:
        draw.line(
            (_xy(cur), _xy(y), _xy(min(cur + dash, x2)), _xy(y)),
            fill=_rgba(color, alpha),
            width=max(1, _xy(width)),
        )
        cur += dash + gap


def _draw_star(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int,
               color: str = GOLD, alpha: int = 240) -> None:
    pts = []
    for i in range(8):
        ang = -math.pi / 2 + i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.34
        pts.append((_xy(cx + math.cos(ang) * rr), _xy(cy + math.sin(ang) * rr)))
    draw.polygon(pts, fill=_rgba(color, alpha))


def _draw_pin(draw: ImageDraw.ImageDraw, cx: int, cy: int, size: int,
              fill: str = GOLD_DARK, alpha: int = 255) -> None:
    r = size * 0.38
    top = cy - size * 0.42
    draw.ellipse((_xy(cx - r), _xy(top), _xy(cx + r), _xy(top + 2 * r)), fill=_rgba(fill, alpha))
    draw.polygon([
        (_xy(cx - r * 0.65), _xy(top + r * 1.28)),
        (_xy(cx + r * 0.65), _xy(top + r * 1.28)),
        (_xy(cx), _xy(cy + size * 0.46)),
    ], fill=_rgba(fill, alpha))
    ir = size * 0.13
    draw.ellipse(
        (_xy(cx - ir), _xy(top + r - ir), _xy(cx + ir), _xy(top + r + ir)),
        fill=(255, 255, 255, 230),
    )


def _draw_route_dot(draw: ImageDraw.ImageDraw, x: int, y: int) -> None:
    draw.ellipse((_xy(x - 6), _xy(y - 6), _xy(x + 6), _xy(y + 6)), fill=_rgba(GOLD_DARK, 210))
    draw.rounded_rectangle(
        (_xy(x - 1), _xy(y + 5), _xy(x + 1), _xy(y + 18)),
        radius=_xy(1),
        fill=_rgba(GOLD_DARK, 180),
    )


def _draw_map_icon(draw: ImageDraw.ImageDraw) -> None:
    x, y, w, h = MAP_ICON_BOX
    c = _rgba(MAP_LIGHT, 115)
    lw = _xy(4)

    pts1 = [(x + 3, y + 68), (x + 35, y + 38), (x + 62, y + 52),
            (x + 91, y + 27), (x + 116, y + 56)]
    pts2 = [(x + 3, y + 68), (x + 47, y + 76), (x + 75, y + 62), (x + 116, y + 76)]
    pts3 = [(x + 35, y + 38), (x + 47, y + 76)]
    pts4 = [(x + 62, y + 52), (x + 75, y + 62)]

    for pts in (pts1, pts2, pts3, pts4):
        draw.line([(_xy(px), _xy(py)) for px, py in pts], fill=c, width=lw, joint="curve")

    pcx, pcy = x + 92, y + 18
    rr = 17
    draw.ellipse((_xy(pcx - rr), _xy(pcy - rr), _xy(pcx + rr), _xy(pcy + rr)), outline=c, width=lw)
    draw.line(
        (_xy(pcx - 12), _xy(pcy + 10), _xy(pcx), _xy(pcy + 36), _xy(pcx + 13), _xy(pcy + 10)),
        fill=c,
        width=lw,
    )
    draw.ellipse((_xy(pcx - 5), _xy(pcy - 5), _xy(pcx + 5), _xy(pcy + 5)), outline=c, width=_xy(3))


def _draw_background_decor(base: Image.Image) -> None:
    leaf = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(leaf)
    d.ellipse((_xy(-40), _xy(-20), _xy(125), _xy(58)), fill=(86, 124, 47, 95))
    d.ellipse((_xy(25), _xy(-18), _xy(195), _xy(47)), fill=(126, 150, 81, 75))
    d.ellipse((_xy(-10), _xy(40), _xy(98), _xy(110)), fill=(97, 135, 53, 60))
    leaf = leaf.filter(ImageFilter.GaussianBlur(_xy(13)))
    base.alpha_composite(leaf)


def _draw_bottom_waves(base: Image.Image) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    fill1 = _rgba(WAVE, 130)
    fill2 = _rgba("#FAEFE3", 160)

    d.polygon([
        (_xy(29), _xy(1256)), (_xy(29), _xy(1205)), (_xy(90), _xy(1194)),
        (_xy(150), _xy(1214)), (_xy(214), _xy(1208)), (_xy(290), _xy(1230)),
        (_xy(290), _xy(1298)), (_xy(29), _xy(1298)),
    ], fill=fill1)
    d.polygon([
        (_xy(29), _xy(1278)), (_xy(29), _xy(1234)), (_xy(88), _xy(1220)),
        (_xy(170), _xy(1248)), (_xy(250), _xy(1240)), (_xy(318), _xy(1265)),
        (_xy(318), _xy(1298)), (_xy(29), _xy(1298)),
    ], fill=fill2)

    d.polygon([
        (_xy(510), _xy(1298)), (_xy(510), _xy(1248)), (_xy(575), _xy(1220)),
        (_xy(640), _xy(1218)), (_xy(705), _xy(1196)), (_xy(722), _xy(1196)),
        (_xy(722), _xy(1298)),
    ], fill=fill1)
    d.polygon([
        (_xy(560), _xy(1298)), (_xy(560), _xy(1265)), (_xy(615), _xy(1244)),
        (_xy(682), _xy(1236)), (_xy(722), _xy(1220)), (_xy(722), _xy(1298)),
    ], fill=fill2)

    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(_box(MAIN_CARD), radius=_xy(30), fill=255)
    clipped = Image.new("RGBA", base.size, (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), mask)
    base.alpha_composite(clipped)

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


# def _ellipsize(draw: ImageDraw.ImageDraw, text: str,
#                font: ImageFont.ImageFont, max_w: int) -> str:
#     """Cut `text` and append '…' so it fits in `max_w` px when drawn."""
#     if not text:
#         return ""
#     if draw.textlength(text, font=font) <= max_w:
#         return text
#     out = text
#     while out and draw.textlength(out + "…", font=font) > max_w:
#         out = out[:-1]
#     return (out + "…") if out else "…"

def _ellipsize(draw: ImageDraw.ImageDraw, text: str,
               font: ImageFont.ImageFont, max_w: int) -> str:
    if not text:
        return ""
    max_w_s = _xy(max_w)
    if draw.textlength(text, font=font) <= max_w_s:
        return text
    out = text
    while out and draw.textlength(out + "…", font=font) > max_w_s:
        out = out[:-1]
    return out + "…" if out else "…"

def _draw_text_vcenter(draw: ImageDraw.ImageDraw, x: int, box_y: int, box_h: int,
                       text: str, font: ImageFont.ImageFont,
                       fill: Tuple[int, int, int, int]) -> None:
    """Draw text vertically centered inside a fixed-height box."""
    bbox = draw.textbbox((0, 0), text, font=font)
    text_h = bbox[3] - bbox[1]
    y = _xy(box_y) + (_xy(box_h) - text_h) / 2 - bbox[1]
    draw.text((_xy(x), int(round(y))), text, font=font, fill=fill)

# def _draw_cover(canvas: Image.Image, cover_path: Optional[Path]) -> None:
#     """Cover photo top section. Crop-to-fill so it always looks tight."""
#     if cover_path and cover_path.is_file():
#         try:
#             with Image.open(cover_path) as src:
#                 src = src.convert("RGB")
#                 # crop-to-fill into (W × COVER_H)
#                 src_ratio = src.width / src.height
#                 target_ratio = W / COVER_H
#                 if src_ratio > target_ratio:
#                     # source is wider: crop horizontally
#                     new_w = int(src.height * target_ratio)
#                     left = (src.width - new_w) // 2
#                     src = src.crop((left, 0, left + new_w, src.height))
#                 else:
#                     # source is taller: crop vertically
#                     new_h = int(src.width / target_ratio)
#                     top = (src.height - new_h) // 2
#                     src = src.crop((0, top, src.width, top + new_h))
#                 src = src.resize((W, COVER_H), resample=Image.LANCZOS)
#                 canvas.paste(src, (0, 0))
#                 return
#         except Exception:
#             pass
#     # fallback: gradient block when no cover
#     draw = ImageDraw.Draw(canvas)
#     for y in range(COVER_H):
#         # vertical gradient from accent blue to lighter blue
#         t = y / COVER_H
#         r = int(24 + (200 - 24) * t)
#         g = int(144 + (220 - 144) * t)
#         b = int(255 + (240 - 255) * t)
#         draw.line([(0, y), (W, y)], fill=(r, g, b))

def _paste_cover(base: Image.Image, cover_path: Optional[Path]) -> None:
    x, y, w, h = COVER_BOX

    if cover_path and cover_path.is_file():
        try:
            with Image.open(cover_path) as src:
                src = src.convert("RGB")
                src_ratio = src.width / src.height
                target_ratio = w / h

                if src_ratio > target_ratio:
                    new_w = int(src.height * target_ratio)
                    left = (src.width - new_w) // 2
                    src = src.crop((left, 0, left + new_w, src.height))
                else:
                    new_h = int(src.width / target_ratio)
                    top = (src.height - new_h) // 2
                    src = src.crop((0, top, src.width, top + new_h))

                src = src.resize((_xy(w), _xy(h)), Image.Resampling.LANCZOS).convert("RGBA")
        except Exception:
            src = _linear_gradient((_xy(w), _xy(h)), "#F4D7B6", "#B88755")
    else:
        src = _linear_gradient((_xy(w), _xy(h)), "#F4D7B6", "#B88755")

    mask = Image.new("L", (_xy(w), _xy(h)), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, _xy(w), _xy(h)],
        radius=_xy(25),
        fill=255,
    )
    base.paste(src, (_xy(x), _xy(y)), mask)
    
    
# def compose_poster(
#     share_url: str,
#     trip_name: str,
#     node_count: int,
#     total_distance: float,
#     route_preview: str,
#     cover_path: Optional[Path],
# ) -> bytes:
#     """Render the poster to a JPG byte stream.

#     `route_preview` already formatted by caller (e.g. "红树林 → 深圳湾 → 科技园").
#     Empty string if no preview to show.
#     """
#     canvas = Image.new("RGB", (W, H), (255, 255, 255))
#     _draw_cover(canvas, cover_path)

#     draw = ImageDraw.Draw(canvas)

#     # ---- text section ----
#     f_title = _font(48)
#     f_meta = _font(28)
#     f_preview = _font(26)
#     f_caption = _font(24)
#     f_footer = _font(22)

#     text_x = PADDING
#     text_max_w = W - 2 * PADDING

#     # Title (1 line, ellipsize)
#     title = _ellipsize(draw, trip_name or "ItsMapPin 分享",
#                        f_title, text_max_w)
#     title_y = COVER_H + 32
#     draw.text((text_x, title_y), title, font=f_title, fill=(26, 26, 26))

#     # Meta chip: "N 节点 · X.Xkm"
#     chip_parts: list[str] = []
#     if node_count:
#         chip_parts.append(f"{node_count} 节点")
#     if total_distance and total_distance > 0:
#         chip_parts.append(f"{total_distance:.1f}km")
#     chip = " · ".join(chip_parts) if chip_parts else ""
#     meta_y = title_y + 64
#     if chip:
#         draw.text((text_x, meta_y), chip, font=f_meta, fill=(107, 114, 128))

#     # Route preview (1 line, ellipsize)
#     preview_y = meta_y + 42
#     if route_preview:
#         preview = _ellipsize(draw, route_preview, f_preview, text_max_w)
#         draw.text((text_x, preview_y), preview,
#                   font=f_preview, fill=(107, 114, 128))

#     # ---- QR section ----
#     qr_size = 320
#     qr_y = preview_y + 60
#     qr_x = (W - qr_size) // 2

#     qr_img = _make_qr(share_url, qr_size)
#     canvas.paste(qr_img, (qr_x, qr_y))

#     # subtle border around QR
#     draw.rectangle(
#         [qr_x - 2, qr_y - 2, qr_x + qr_size + 2, qr_y + qr_size + 2],
#         outline=(229, 231, 235), width=2,
#     )

#     # caption below QR
#     cap_y = qr_y + qr_size + 28
#     cap = "扫码查看完整路线"
#     cap_w = draw.textlength(cap, font=f_caption)
#     draw.text(((W - cap_w) / 2, cap_y), cap,
#               font=f_caption, fill=(75, 85, 99))

#     # footer pinned to bottom
#     foot_y = H - 44
#     footer = "ItsMapPin · 旅行回放"
#     foot_w = draw.textlength(footer, font=f_footer)
#     draw.text(((W - foot_w) / 2, foot_y), footer,
#               font=f_footer, fill=(156, 163, 175))

#     # ---- output ----
#     buf = io.BytesIO()
#     canvas.save(buf, format="JPEG", quality=88, optimize=True)
#     return buf.getvalue()

def compose_poster(
    share_url: str,
    trip_name: str,
    node_count: int,
    total_distance: float,
    route_preview: str,
    cover_path: Optional[Path],
) -> bytes:
    """Render the poster to a JPG byte stream.

    保持函数签名不变，避免影响 FastAPI 路由调用。
    """
    canvas = _linear_gradient((W * S, H * S), BG_TOP, BG_BOTTOM)
    _draw_background_decor(canvas)
    draw = ImageDraw.Draw(canvas)

    # 主白色卡片 + 顶部封面图
    _add_shadow(canvas, MAIN_CARD, radius=34, blur=18, offset=(0, 8), color=(106, 75, 42, 48))
    _rounded_rect(
        draw,
        MAIN_CARD,
        radius=32,
        fill=_rgba(CARD, 250),
        outline=(255, 255, 255, 210),
        width=2,
    )
    _paste_cover(canvas, cover_path)

    # 下方信息面板
    _add_shadow(canvas, INFO_PANEL, radius=30, blur=12, offset=(0, -2), color=(160, 120, 70, 20))
    _rounded_rect(
        draw,
        INFO_PANEL,
        radius=31,
        fill=_rgba(PANEL, 248),
        outline=_rgba("#F0DCC6", 230),
        width=1,
    )

    panel_grad = _linear_gradient((_xy(INFO_PANEL[2]), _xy(INFO_PANEL[3])), PANEL, PANEL_2)
    panel_mask = Image.new("L", (_xy(INFO_PANEL[2]), _xy(INFO_PANEL[3])), 0)
    ImageDraw.Draw(panel_mask).rounded_rectangle(
        [0, 0, _xy(INFO_PANEL[2]), _xy(INFO_PANEL[3])],
        radius=_xy(31),
        fill=245,
    )
    canvas.paste(panel_grad, (_xy(INFO_PANEL[0]), _xy(INFO_PANEL[1])), panel_mask)
    draw = ImageDraw.Draw(canvas)

    # 字体
    f_title = _font(65, "title")
    f_meta = _font(24, "body")
    f_route = _font(22, "body")
    f_caption = _font(23, "body")
    f_footer = _font(22, "body")

    # 标题区
    title = _ellipsize(draw, trip_name or "ItsMapPin 分享", f_title, TITLE_MAX_W)
    draw.text((_xy(TITLE_POS[0]), _xy(TITLE_POS[1])), title, font=f_title, fill=_rgba(BROWN, 255))
    _draw_star(draw, TITLE_STAR[0], TITLE_STAR[1], 12, GOLD, 245)
    _draw_dotted_line(
        draw,
        TITLE_DOTS[0],
        TITLE_DOTS[1],
        TITLE_DOTS[2],
        GOLD_LIGHT,
        135,
        dash=3,
        gap=7,
        width=1,
    )
    _draw_map_icon(draw)

    # 元信息胶囊
    _rounded_rect(
        draw,
        META_CHIP,
        radius=23,
        fill=_rgba("#FFFDF8", 210),
        outline=_rgba(GOLD_DARK, 210),
        width=1,
    )
    _draw_pin(draw, 106, 690, 27, GOLD_DARK, 245)

    chip_parts: list[str] = []
    if node_count:
        chip_parts.append(f"{node_count} 节点")
    if total_distance and total_distance > 0:
        chip_parts.append(f"{total_distance:.1f}km")

    chip_text = " · ".join(chip_parts) if chip_parts else "路线回放"
    _draw_text_vcenter(draw, 131, META_CHIP[1], META_CHIP[3], chip_text, f_meta, _rgba(TEXT_BROWN, 255))

    # 路线预览条
    _rounded_rect(
        draw,
        ROUTE_BAR,
        radius=28,
        fill=_rgba(ROUTE_BG, 225),
        outline=_rgba(ROUTE_BORDER, 210),
        width=1,
    )
    _draw_route_dot(draw, 85, 761)
    route_text = _ellipsize(draw, route_preview or "暂无路线预览", f_route, 535)
    _draw_text_vcenter(draw, 114, ROUTE_BAR[1], ROUTE_BAR[3], route_text, f_route, _rgba(TEXT_ROUTE, 245))

    # QR 白色卡片
    _add_shadow(canvas, QR_CARD, radius=16, blur=14, offset=(0, 4), color=(86, 68, 45, 32))
    _rounded_rect(
        draw,
        QR_CARD,
        radius=17,
        fill=(255, 255, 255, 252),
        outline=(255, 255, 255, 235),
        width=1,
    )

    # 扫码说明
    _draw_dotted_line(draw, 94, CAPTION_Y + 15, 204, GOLD_LIGHT, 150, dash=3, gap=6, width=1)
    _draw_star(draw, 225, CAPTION_Y + 15, 11, GOLD, 240)

    caption = "扫码查看完整路线"
    cap_w = draw.textlength(caption, font=f_caption)
    draw.text(
        (_xy((W - cap_w / S) / 2), _xy(CAPTION_Y)),
        caption,
        font=f_caption,
        fill=_rgba(TEXT_GREY, 255),
    )

    _draw_star(draw, 517, CAPTION_Y + 15, 11, GOLD, 240)
    _draw_dotted_line(draw, 545, CAPTION_Y + 15, 654, GOLD_LIGHT, 150, dash=3, gap=6, width=1)

    # 底部波浪 + 品牌文字
    _draw_bottom_waves(canvas)
    draw = ImageDraw.Draw(canvas)

    _draw_dotted_line(draw, 132, FOOTER_Y + 13, 205, GOLD_LIGHT, 95, dash=3, gap=6, width=1)
    _draw_dotted_line(draw, 544, FOOTER_Y + 13, 617, GOLD_LIGHT, 95, dash=3, gap=6, width=1)

    footer = "ItsMapPin · 旅行回放"
    foot_w = draw.textlength(footer, font=f_footer)
    draw.text(
        (_xy((W - foot_w / S) / 2), _xy(FOOTER_Y)),
        footer,
        font=f_footer,
        fill=_rgba(FOOTER_GREY, 255),
    )

    # 先缩图，再贴二维码，避免二维码被抗锯齿模糊
    final_img = canvas.resize((W, H), Image.Resampling.LANCZOS).convert("RGB")
    qr = _make_qr(share_url, QR_IMG[2])
    final_img.paste(qr, (QR_IMG[0], QR_IMG[1]))

    buf = io.BytesIO()
    final_img.save(buf, format="JPEG", quality=92, optimize=True)
    return buf.getvalue()