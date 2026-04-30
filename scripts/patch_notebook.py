"""Patch analysis.ipynb: fix hardcoded macOS path and load real VM CSV data."""
import json
from pathlib import Path

REPO = Path(__file__).parent.parent
NB   = REPO / 'notebooks' / 'analysis.ipynb'

nb = json.loads(NB.read_text(encoding='utf-8'))

SETUP_ID   = 'a5bcd704'
DATALOAD_ID = 'f6b9a3eb'

SETUP_SRC = """\
import os, warnings
from pathlib import Path

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.ticker as mticker
from scipy import stats

warnings.filterwarnings('ignore')

# \u2500\u2500 Absolute paths \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
# nbconvert sets CWD to the notebook's directory; go up one level to repo root
_nb_dir   = Path(os.getcwd())
REPO_ROOT = (_nb_dir / '..').resolve() if (_nb_dir / '..' / 'data').exists() else _nb_dir.resolve()
if not (REPO_ROOT / 'data').exists():
    # Absolute fallback for this machine
    REPO_ROOT = Path(r'C:\\Users\\Wahaj\\Desktop\\thesis')

DATA_RAW    = REPO_ROOT / 'data' / 'raw'
DATA_PROC   = REPO_ROOT / 'data' / 'processed'
RESULTS_DIR = REPO_ROOT / 'results'
DATA_PROC.mkdir(parents=True, exist_ok=True)
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

# \u2500\u2500 Plot style \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
try:
    plt.style.use('seaborn-v0_8-whitegrid')
except OSError:
    plt.style.use('seaborn-whitegrid')

plt.rcParams.update({
    'figure.dpi'        : 150,
    'savefig.dpi'       : 150,
    'font.family'       : 'DejaVu Sans',
    'font.size'         : 11,
    'axes.titlesize'    : 13,
    'axes.titleweight'  : 'bold',
    'axes.titlepad'     : 12,
    'axes.labelsize'    : 11,
    'axes.labelpad'     : 6,
    'xtick.labelsize'   : 10,
    'ytick.labelsize'   : 10,
    'legend.fontsize'   : 10,
    'legend.framealpha' : 0.92,
    'legend.edgecolor'  : '#cccccc',
    'axes.spines.top'   : False,
    'axes.spines.right' : False,
    'grid.alpha'        : 0.35,
    'figure.facecolor'  : 'white',
    'axes.facecolor'    : '#FAFAFA',
})

# \u2500\u2500 Colour palette \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
VM_C    = '#C0392B'   # deep red    \u2014 VM / DockerRunLauncher
K8S_C   = '#2980B9'  # steel blue  \u2014 Kubernetes / K8sRunLauncher
AMBER   = '#D68910'  # amber       \u2014 crossover / warning
GREEN   = '#1E8449'  # dark green  \u2014 success zone
GRAY    = '#626567'  # slate gray  \u2014 neutral lines

# \u2500\u2500 Experiment constants \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
LEVELS       = [1, 2, 3, 5, 7, 10]
LEVEL_LABELS = ['L1\\n(1 job)', 'L2\\n(2 jobs)', 'L3\\n(3 jobs)',
                'L4\\n(5 jobs)', 'L5\\n(7 jobs)', 'L6\\n(10 jobs)']
LEVEL_MAP    = {1: 'L1', 2: 'L2', 3: 'L3', 5: 'L4', 7: 'L5', 10: 'L6'}
REPS         = 3

print(f'Repo  : {REPO_ROOT}')
print(f'Raw   : {DATA_RAW}')
print(f'Output: {RESULTS_DIR}')
print('Setup complete.')
"""

DATALOAD_SRC = """\
# \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
# VM Real Data  (Experiment 1 \u2014 DockerRunLauncher on single VM)
# Source: data/raw/exp1-vm-degradation/  (real experimental CSVs)
# \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
def _load_vm_runs() -> pd.DataFrame:
    frames = []
    base = DATA_RAW / 'exp1-vm-degradation'
    for p in sorted(base.glob('*/run*/dagster_runs.csv')):
        frames.append(pd.read_csv(p))
    if not frames:
        print('WARNING: No VM CSV files found under', base)
        return pd.DataFrame()
    df = pd.concat(frames, ignore_index=True).drop_duplicates('run_id')
    df['start_time'] = pd.to_datetime(df['start_time'], utc=True, errors='coerce')
    df['end_time']   = pd.to_datetime(df['end_time'],   utc=True, errors='coerce')
    df['duration_s'] = (df['end_time'] - df['start_time']).dt.total_seconds()
    df['concurrency_level'] = pd.to_numeric(df['concurrency_level'], errors='coerce')
    return df

vm_all = _load_vm_runs()
vm_ok  = vm_all[vm_all['status'] == 'SUCCESS'].copy() if not vm_all.empty else pd.DataFrame()

if not vm_all.empty:
    _grp = vm_all.groupby('concurrency_level')
    vm_df = pd.DataFrame({
        'total':   _grp['run_id'].count(),
        'success': _grp['status'].apply(lambda x: (x == 'SUCCESS').sum()),
        'mean_s':  vm_ok.groupby('concurrency_level')['duration_s'].mean().round(2),
        'std_s':   vm_ok.groupby('concurrency_level')['duration_s'].std().round(2),
    }).reindex(LEVELS)
    vm_df['failure']      = (vm_df['total'] - vm_df['success']).fillna(0).astype(int)
    vm_df['success_rate'] = (vm_df['success'] / vm_df['total'] * 100).round(1)
    vm_df.index           = vm_df.index.astype(int)
    vm_df.index.name      = 'level'
else:
    vm_df = pd.DataFrame()

# \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
# K8s Real Data  (Experiment 2A \u2014 K8sRunLauncher on Kind single-node cluster)
# Source: data/raw/exp2-kubernetes-isolation/part-a/
# \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
def _load_k8s_runs() -> pd.DataFrame:
    frames = []
    base = DATA_RAW / 'exp2-kubernetes-isolation' / 'part-a'
    for p in sorted(base.glob('*/run*/dagster_runs.csv')):
        frames.append(pd.read_csv(p))
    if not frames:
        print('WARNING: No K8s CSV files found under', base)
        return pd.DataFrame()
    df = pd.concat(frames, ignore_index=True).drop_duplicates('run_id')
    df['start_time'] = pd.to_datetime(df['start_time'], utc=True, errors='coerce')
    df['end_time']   = pd.to_datetime(df['end_time'],   utc=True, errors='coerce')
    df['duration_s'] = (df['end_time'] - df['start_time']).dt.total_seconds()
    df['concurrency_level'] = pd.to_numeric(df['concurrency_level'], errors='coerce')
    return df


def _load_pod_timing(runs_df: pd.DataFrame) -> pd.DataFrame:
    frames = []
    base = DATA_RAW / 'exp2-kubernetes-isolation' / 'part-a'
    for p in sorted(base.glob('*/run*/pod_timing.csv')):
        frames.append(pd.read_csv(p))
    if not frames:
        return pd.DataFrame()
    df = pd.concat(frames, ignore_index=True).drop_duplicates('run_id')
    for col in ['submitted_ts', 'scheduled_ts', 'running_ts', 'job_start_ts']:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], utc=True, errors='coerce')
    df['sched_latency_s']  = (df['scheduled_ts'] - df['submitted_ts']).dt.total_seconds().clip(lower=0)
    df['startup_s']        = (df['job_start_ts']  - df['running_ts'] ).dt.total_seconds().clip(lower=0)
    df['total_overhead_s'] = (df['job_start_ts']  - df['submitted_ts']).dt.total_seconds().clip(lower=0)
    if not runs_df.empty:
        meta = runs_df[['run_id', 'concurrency_level', 'status']].drop_duplicates('run_id')
        df   = df.merge(meta, on='run_id', how='left')
    return df[df['status'] == 'SUCCESS'].copy() if 'status' in df.columns else df


k8s_all  = _load_k8s_runs()
pod_data = _load_pod_timing(k8s_all)
k8s_ok   = k8s_all[k8s_all['status'] == 'SUCCESS'].copy() if not k8s_all.empty else pd.DataFrame()

if not k8s_ok.empty:
    k8s_df = (
        k8s_ok.groupby('concurrency_level')
        .agg(n_runs=('run_id', 'count'),
             mean_s=('duration_s', 'mean'),
             std_s =('duration_s', 'std'),
             min_s =('duration_s', 'min'),
             max_s =('duration_s', 'max'))
        .reindex(LEVELS).round(2)
    )
    k8s_df.index = k8s_df.index.astype(int)
    k8s_df.index.name = 'level'
    k8s_df['success_rate'] = 100.0
else:
    k8s_df = pd.DataFrame()

if not pod_data.empty:
    pod_sum = (
        pod_data.groupby('concurrency_level')
        .agg(n_pods          =('run_id',         'count'),
             mean_sched_s    =('sched_latency_s', 'mean'),
             mean_startup_s  =('startup_s',       'mean'),
             std_startup_s   =('startup_s',       'std'),
             mean_overhead_s =('total_overhead_s','mean'),
             std_overhead_s  =('total_overhead_s','std'))
        .reindex(LEVELS).round(2)
    )
    pod_sum.index = pod_sum.index.astype(int)
    pod_sum.index.name = 'level'
else:
    pod_sum = pd.DataFrame()

# \u2500\u2500 Print summary \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
print('\u2500\u2500\u2500 VM Dagster runs (deduplicated) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500')
print(f'  Total unique run_ids: {len(vm_all):,}')
if not vm_all.empty:
    for s, n in vm_all['status'].value_counts().items():
        print(f'  {s:<14} {n:>4}')
print()
print('\u2500\u2500\u2500 K8s Dagster runs (deduplicated) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500')
print(f'  Total unique run_ids: {len(k8s_all):,}')
if not k8s_all.empty:
    for s, n in k8s_all['status'].value_counts().items():
        tag = '  \u2190 used' if s == 'SUCCESS' else '  \u2190 excluded'
        print(f'  {s:<14} {n:>4}{tag}')
print(f'  Pod timing rows: {len(pod_data):,}')
print()
if not vm_df.empty:
    print('\u2500\u2500\u2500 VM per-level summary \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500')
    print(vm_df[['total', 'success', 'failure', 'success_rate', 'mean_s', 'std_s']].to_string())
print('\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500')
"""

patched = 0
for cell in nb['cells']:
    if cell.get('cell_type') != 'code':
        continue
    cid = cell.get('id', '')
    if cid == SETUP_ID:
        cell['source'] = SETUP_SRC
        cell['outputs'] = []
        cell['execution_count'] = None
        patched += 1
        print(f'Patched setup cell {cid}')
    elif cid == DATALOAD_ID:
        cell['source'] = DATALOAD_SRC
        cell['outputs'] = []
        cell['execution_count'] = None
        patched += 1
        print(f'Patched data-loading cell {cid}')

# Remove any extra cells appended by edit_notebook_file (they have #VSC- style IDs)
before = len(nb['cells'])
nb['cells'] = [c for c in nb['cells'] if not str(c.get('id', '')).startswith('VSC-')]
after = len(nb['cells'])
if before != after:
    print(f'Removed {before - after} stale #VSC- cells')

NB.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding='utf-8')
print(f'Saved. Patched {patched}/2 target cells.')
