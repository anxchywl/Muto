#!/usr/bin/env bash
# fails when line coverage of hand-written code falls below the floor
#
# generated localizations are excluded: they are produced from the arb files
# and testing them would measure the generator, not this project
set -euo pipefail

REPORT="${1:?usage: coverage_floor.sh <lcov.info> <floor-percent>}"
FLOOR="${2:?usage: coverage_floor.sh <lcov.info> <floor-percent>}"

python3 - "$REPORT" "$FLOOR" <<'PY'
import sys

report, floor = sys.argv[1], float(sys.argv[2])
excluded = ('/l10n/generated/',)

found = hit = 0
for block in open(report).read().split('end_of_record'):
    source = lines_found = lines_hit = None
    for line in block.splitlines():
        if line.startswith('SF:'):
            source = line[3:]
        elif line.startswith('LF:'):
            lines_found = int(line[3:])
        elif line.startswith('LH:'):
            lines_hit = int(line[3:])
    if not source or lines_found is None:
        continue
    if any(fragment in source for fragment in excluded):
        continue
    found += lines_found
    hit += lines_hit

if found == 0:
    print('no coverage data')
    sys.exit(1)

pct = 100 * hit / found
print(f'line coverage {pct:.1f}% ({hit}/{found}), floor {floor:.0f}%')
sys.exit(0 if pct >= floor else 1)
PY
