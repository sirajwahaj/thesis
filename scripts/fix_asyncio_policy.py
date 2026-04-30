"""Add asyncio WindowsSelectorEventLoopPolicy to notebook setup cell."""
import json
from pathlib import Path

NB = Path(__file__).parent.parent / 'notebooks' / 'analysis.ipynb'
nb = json.loads(NB.read_text(encoding='utf-8'))

OLD = 'import os, warnings\nfrom pathlib import Path'
NEW = (
    'import asyncio, os, sys, warnings\n'
    'from pathlib import Path\n'
    '\n'
    '# Suppress ZMQ ProactorEventLoop warning on Windows\n'
    'if sys.platform == "win32":\n'
    '    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())'
)

patched = 0
for cell in nb['cells']:
    if cell['cell_type'] != 'code':
        continue
    src = ''.join(cell['source'])
    if OLD in src and 'asyncio' not in src:
        cell['source'] = [src.replace(OLD, NEW, 1)]
        patched += 1

NB.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding='utf-8')
print(f'Patched {patched} cell(s)')
