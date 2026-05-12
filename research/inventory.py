"""Inventory Syria terrain mod files by extension and size."""
from pathlib import Path
from collections import defaultdict

ROOT = Path(r"D:\Program Files\Eagle Dynamics\DCS World\Mods\terrains\Syria")

by_ext: dict[str, list[Path]] = defaultdict(list)
total_by_ext: dict[str, int] = defaultdict(int)

for p in ROOT.rglob('*'):
    if p.is_file():
        ext = p.suffix.lower()
        by_ext[ext].append(p)
        total_by_ext[ext] += p.stat().st_size

print(f'{"Ext":12} {"Count":>6}  {"Total bytes":>16}')
print('-' * 42)
for ext in sorted(total_by_ext, key=lambda e: -total_by_ext[e]):
    print(f'{ext:12} {len(by_ext[ext]):>6}  {total_by_ext[ext]:>16,}')

print()
print('Notable single files (any ext that has only 1 file):')
for ext in sorted(by_ext):
    if len(by_ext[ext]) == 1:
        p = by_ext[ext][0]
        rel = p.relative_to(ROOT)
        print(f'  {p.stat().st_size:>14,}  {rel}')
