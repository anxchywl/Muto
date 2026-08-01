#!/usr/bin/env bash
# regenerates the abstract placeholder images used by the sample listings
#
# these are flat generated shapes, never photographs, so the repository never
# carries a real item, a real place, or a real person
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="muto_feature/assets/sample/images"
mkdir -p "$OUT"

python3 - "$OUT" <<'PY'
import struct
import sys
import zlib

out = sys.argv[1]

WIDTH, HEIGHT = 600, 450

# muted tones drawn from the app_ui palette so placeholders sit inside the
# product's own colour language rather than shouting for attention
TONES = [
    ((0xEE, 0xE5, 0xFF), (0xC9, 0xB6, 0xF2)),
    ((0xEA, 0xEA, 0xFF), (0xB8, 0xBE, 0xEE)),
    ((0xD4, 0xF7, 0xE5), (0xA6, 0xDC, 0xC2)),
    ((0xFF, 0xF3, 0xE0), (0xEF, 0xD2, 0xA8)),
    ((0xD4, 0xE5, 0xFF), (0xA8, 0xC2, 0xEF)),
    ((0xF3, 0xE5, 0xF5), (0xD3, 0xB6, 0xDA)),
    ((0xE3, 0xE5, 0xE5), (0xC2, 0xC6, 0xC6)),
    ((0xF2, 0xF2, 0xFF), (0xC6, 0xC6, 0xEA)),
]


def chunk(tag, data):
    body = tag + data
    return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))


def write_png(path, base, accent):
    rows = bytearray()
    for y in range(HEIGHT):
        rows.append(0)  # no per-scanline filter
        for x in range(WIDTH):
            # a single soft diagonal band, nothing representational
            band = ((x + y) // 60) % 2
            r, g, b = accent if band else base
            rows += bytes((r, g, b))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(rows), 9))
    png += chunk(b'IEND', b'')

    with open(path, 'wb') as handle:
        handle.write(png)


for index, (base, accent) in enumerate(TONES, start=1):
    target = f'{out}/sample-{index:02d}.png'
    write_png(target, base, accent)
    print(f'wrote {target}')
PY
