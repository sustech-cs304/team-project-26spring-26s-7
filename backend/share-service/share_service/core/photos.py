"""Photo processing for /api/v1/share/publish (P08 API 规范 §8.1 step 5–6).

Pipeline:
  raw bytes → Image.open() (Pillow auto-detects JPEG/PNG/HEIF/WebP)
            → strip EXIF (rotation honoured, then EXIF dropped)
            → re-encode as WebP at two widths: 375 and 750
            → write to cache/{shortCode}/{flatIdx}_{width}w.webp

Naming uses `flatIdx` (the multipart `photo_N` index) rather than
nodeOrder / photoIdx so the filename is guaranteed unique even when a
client sends duplicate nodeOrders. The mapping flatIdx → (nodeOrder,
photoIdx) lives in `share_publish.photo_index_json` and the per-share
manifest.json on disk.

EXIF clean rationale (规范 §8.1 step 5): even though the spec assumes the
client did EXIF strip on-device (alignment doc §2.2), the server must still
do a "保底" (defensive) cleanup so a misbehaving client cannot leak GPS or
device info to the public viewer.

WebP rationale: smaller payload (~30% of JPEG at same perceptual quality),
universal browser support since 2020, and the spec calls for it explicitly.
"""
from __future__ import annotations

import io
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageOps

# Spec §4.1: client and server agree on these two widths. 375w = 1x at
# typical phone width, 750w = 2x for high-DPR displays. The H5 viewer
# decides which to load via srcset.
WIDTHS: tuple[int, ...] = (375, 750)
WEBP_QUALITY = 78  # tuned for visible quality vs payload — adjust if needed.


@dataclass(frozen=True)
class ProcessedPhoto:
    """One source photo, transcoded into N width variants on disk."""
    flat_idx: int
    relative_paths: dict[int, str]  # width -> "{flatIdx}_{w}w.webp"


def process_one(
    raw: bytes,
    out_dir: Path,
    flat_idx: int,
) -> ProcessedPhoto:
    """Decode `raw`, strip EXIF, write WebP variants under `out_dir`.

    `out_dir` is the per-shortcode directory; the caller has already
    ensured it exists. `flat_idx` is the multipart photo_N index — used
    as the filename prefix because it's guaranteed unique within a
    publish even if nodeOrder / photoIdx have duplicates.
    """
    with Image.open(io.BytesIO(raw)) as img:
        # ImageOps.exif_transpose applies the EXIF orientation tag and
        # then drops it — exactly the "honour rotation, strip metadata"
        # behaviour we want. Without this step a portrait phone photo
        # would render sideways in the H5 viewer.
        img = ImageOps.exif_transpose(img)

        # Drop alpha for JPEG-origin photos to keep WebP small. PNG/HEIF
        # with real transparency keeps RGBA.
        if img.mode == "RGBA" and _looks_opaque(img):
            img = img.convert("RGB")
        elif img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGB")

        src_w, src_h = img.size
        relative_paths: dict[int, str] = {}
        for target_w in WIDTHS:
            if src_w <= target_w:
                # Don't upscale: write the original size at this width slot.
                resized = img.copy()
            else:
                target_h = round(src_h * target_w / src_w)
                resized = img.resize(
                    (target_w, target_h), resample=Image.LANCZOS
                )
            filename = f"{flat_idx}_{target_w}w.webp"
            out_path = out_dir / filename
            resized.save(
                out_path,
                format="WEBP",
                quality=WEBP_QUALITY,
                method=6,   # slowest/best encoder pass
                exif=b"",   # belt-and-braces: no EXIF in output
            )
            relative_paths[target_w] = filename

    return ProcessedPhoto(
        flat_idx=flat_idx,
        relative_paths=relative_paths,
    )


def _looks_opaque(img: Image.Image) -> bool:
    """Cheap heuristic: if alpha channel min == 255, treat as opaque."""
    if img.mode != "RGBA":
        return True
    alpha = img.getchannel("A")
    return alpha.getextrema()[0] == 255


def assign_photos_to_nodes(
    photos: Iterable[bytes],
    photo_counts: list[int],
) -> list[list[bytes]]:
    """Partition the flat photo list across nodes by photoCount.

    Spec §4.3: photos are assigned in nodeOrder, sliced by each node's
    photoCount. Caller has already validated `sum(photo_counts) == len(photos)`.
    """
    photos_list = list(photos)
    out: list[list[bytes]] = []
    cursor = 0
    for n in photo_counts:
        out.append(photos_list[cursor : cursor + n])
        cursor += n
    return out
