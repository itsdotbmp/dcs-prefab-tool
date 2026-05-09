"""Look at how 'Trees' is referenced in Syria.tile."""
from pathlib import Path

TILE = Path(r"D:\Program Files\Eagle Dynamics\DCS World\Mods\terrains\Syria\surface\Syria.tile")

with TILE.open('rb') as f:
    data = f.read()

# Find every position of literal 'Trees' followed by a length-prefix string pattern,
# and dump 256 bytes of context around each
needle = b'Trees'
pos = 0
n_found = 0
while True:
    p = data.find(needle, pos)
    if p == -1:
        break
    n_found += 1
    start = max(0, p - 64)
    end = min(len(data), p + 192)
    print(f'\n--- offset {p:#x} (match {n_found}) ---')
    chunk = data[start:end]
    # Hex+ASCII dump
    for i in range(0, len(chunk), 16):
        line = chunk[i:i+16]
        hexpart = ' '.join(f'{b:02x}' for b in line)
        asciipart = ''.join(chr(b) if 32 <= b < 127 else '.' for b in line)
        marker = '<<' if start + i <= p < start + i + 16 else '  '
        print(f'  {start+i:08x} {marker} {hexpart:<48} {asciipart}')
    pos = p + 1

print(f'\nTotal "Trees" occurrences: {n_found}')

# Also pull all printable runs of >=12 chars
import re
runs = re.findall(rb'[\x20-\x7e]{12,}', data)
seen = set()
print(f'\n=== All printable strings >=12 chars in Syria.tile ===')
for r in runs:
    s = r.decode('latin-1')
    if s not in seen:
        seen.add(s)
        print(f'  {s!r}')
