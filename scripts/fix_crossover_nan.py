"""
Fix SQ4 crossover cell: guard int() conversion against NaN when
no crossover threshold is reached in the collected data.
"""
import json
from pathlib import Path

NB = Path(__file__).parent.parent / 'notebooks' / 'analysis.ipynb'
nb = json.loads(NB.read_text(encoding='utf-8'))

OLD = (
    "rel_label  = LEVEL_MAP.get(int(reliability_co), f'L?({reliability_co})')\n"
    "perf_label = LEVEL_MAP.get(int(performance_co), f'L?({performance_co})')\n"
    "net_label  = LEVEL_MAP.get(int(net_co),         f'L?({net_co})')"
)

NEW = (
    "def _co_label(val):\n"
    "    if pd.isna(val):\n"
    "        return 'none (not reached in dataset)'\n"
    "    return LEVEL_MAP.get(int(val), f'L?({val})')\n"
    "\n"
    "rel_label  = _co_label(reliability_co)\n"
    "perf_label = _co_label(performance_co)\n"
    "net_label  = _co_label(net_co)"
)

patched = 0
for cell in nb['cells']:
    if cell['cell_type'] != 'code':
        continue
    src = ''.join(cell['source'])
    if OLD in src:
        cell['source'] = [src.replace(OLD, NEW)]
        patched += 1

NB.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding='utf-8')
print(f"Patched {patched} location(s). Saved.")
