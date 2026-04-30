"""
Fix _load_pod_timing in analysis.ipynb so that concurrency_level is
read from metadata.json instead of joined from dagster_runs.
This resolves KeyError: 'mean_overhead_s' when pod_timing and
dagster_runs were collected in different experiment passes.
"""
import json
from pathlib import Path

NB = Path(__file__).parent.parent / 'notebooks' / 'analysis.ipynb'
nb = json.loads(NB.read_text(encoding='utf-8'))

OLD_FUNC = (
    "def _load_pod_timing(runs_df: pd.DataFrame) -> pd.DataFrame:\n"
    "    frames = []\n"
    "    base = DATA_RAW / 'exp2-kubernetes-isolation' / 'part-a'\n"
    "    for p in sorted(base.glob('*/run*/pod_timing.csv')):\n"
    "        frames.append(pd.read_csv(p))\n"
    "    if not frames:\n"
    "        return pd.DataFrame()\n"
    "    df = pd.concat(frames, ignore_index=True).drop_duplicates('run_id')\n"
    "    for col in ['submitted_ts', 'scheduled_ts', 'running_ts', 'job_start_ts']:\n"
    "        if col in df.columns:\n"
    "            df[col] = pd.to_datetime(df[col], utc=True, errors='coerce')\n"
    "    df['sched_latency_s']  = (df['scheduled_ts'] - df['submitted_ts']).dt.total_seconds().clip(lower=0)\n"
    "    df['startup_s']        = (df['job_start_ts']  - df['running_ts'] ).dt.total_seconds().clip(lower=0)\n"
    "    df['total_overhead_s'] = (df['job_start_ts']  - df['submitted_ts']).dt.total_seconds().clip(lower=0)\n"
    "    if not runs_df.empty:\n"
    "        meta = runs_df[['run_id', 'concurrency_level', 'status']].drop_duplicates('run_id')\n"
    "        df   = df.merge(meta, on='run_id', how='left')\n"
    "    return df[df['status'] == 'SUCCESS'].copy() if 'status' in df.columns else df"
)

NEW_FUNC = (
    "def _load_pod_timing(runs_df: pd.DataFrame) -> pd.DataFrame:\n"
    "    # concurrency_level is read from metadata.json because pod_timing and\n"
    "    # dagster_runs may come from different collection passes (zero run_id overlap).\n"
    "    import json as _json\n"
    "    frames = []\n"
    "    base = DATA_RAW / 'exp2-kubernetes-isolation' / 'part-a'\n"
    "    for p in sorted(base.glob('*/run*/pod_timing.csv')):\n"
    "        df_p = pd.read_csv(p)\n"
    "        meta_path = p.parent / 'metadata.json'\n"
    "        if meta_path.exists():\n"
    "            meta = _json.loads(meta_path.read_text())\n"
    "            df_p['concurrency_level'] = meta.get('concurrent_jobs')\n"
    "        frames.append(df_p)\n"
    "    if not frames:\n"
    "        return pd.DataFrame()\n"
    "    df = pd.concat(frames, ignore_index=True).drop_duplicates('run_id')\n"
    "    for col in ['submitted_ts', 'scheduled_ts', 'running_ts', 'job_start_ts']:\n"
    "        if col in df.columns:\n"
    "            df[col] = pd.to_datetime(df[col], utc=True, errors='coerce')\n"
    "    df['sched_latency_s']  = (df['scheduled_ts'] - df['submitted_ts']).dt.total_seconds().clip(lower=0)\n"
    "    df['startup_s']        = (df['job_start_ts']  - df['running_ts'] ).dt.total_seconds().clip(lower=0)\n"
    "    df['total_overhead_s'] = (df['job_start_ts']  - df['submitted_ts']).dt.total_seconds().clip(lower=0)\n"
    "    if 'concurrency_level' in df.columns:\n"
    "        df['concurrency_level'] = pd.to_numeric(df['concurrency_level'], errors='coerce')\n"
    "    else:\n"
    "        df['concurrency_level'] = np.nan\n"
    "    # Best-effort status join; rows without a match are treated as SUCCESS\n"
    "    if not runs_df.empty and 'run_id' in runs_df.columns:\n"
    "        status_map = runs_df[['run_id', 'status']].drop_duplicates('run_id')\n"
    "        df = df.merge(status_map, on='run_id', how='left')\n"
    "    if 'status' not in df.columns or df['status'].isna().all():\n"
    "        df['status'] = 'SUCCESS'\n"
    "    return df[df['status'] == 'SUCCESS'].copy()"
)

# Also fix k8s_dashboard cell: guard panel 3/4 against empty pod_sum
OLD_DASH_P3 = (
    "# -- Panel 3: Actual startup overhead by level --------------------------------\n"
    "ax = axes[1, 0]\n"
    "# Use startup_oh_s computed in SQ3 cell (pod_lifetime - exec_time)\n"
    "if 'startup_oh_s' in pod_sum.columns:\n"
    "    _oh = pod_sum['startup_oh_s'].reindex(LEVELS).fillna(0).values\n"
    "    _oh_std = pod_sum['std_overhead_s'].reindex(LEVELS).fillna(0).values\n"
    "else:\n"
    "    _pod_lt = pod_sum['mean_overhead_s'].reindex(LEVELS).fillna(0).values\n"
    "    _exec_a = k8s_df['mean_s'].reindex(LEVELS).fillna(0).values\n"
    "    _oh = _pod_lt - _exec_a\n"
    "    _oh_std = pod_sum['std_overhead_s'].reindex(LEVELS).fillna(0).values if not pod_sum.empty else np.zeros(len(LEVELS))\n"
)

NEW_DASH_P3 = (
    "# -- Panel 3: Actual startup overhead by level --------------------------------\n"
    "ax = axes[1, 0]\n"
    "_has_overhead = not pod_sum.empty and 'mean_overhead_s' in pod_sum.columns\n"
    "if _has_overhead:\n"
    "    if 'startup_oh_s' in pod_sum.columns:\n"
    "        _oh = pod_sum['startup_oh_s'].reindex(LEVELS).fillna(0).values\n"
    "        _oh_std = pod_sum['std_overhead_s'].reindex(LEVELS).fillna(0).values\n"
    "    else:\n"
    "        _pod_lt = pod_sum['mean_overhead_s'].reindex(LEVELS).fillna(0).values\n"
    "        _exec_a = k8s_df['mean_s'].reindex(LEVELS).fillna(0).values if not k8s_df.empty else np.zeros(len(LEVELS))\n"
    "        _oh = _pod_lt - _exec_a\n"
    "        _oh_std = pod_sum['std_overhead_s'].reindex(LEVELS).fillna(0).values\n"
    "else:\n"
    "    _oh = _oh_std = np.zeros(len(LEVELS))\n"
)

OLD_DASH_P4 = (
    "# -- Panel 4: K8s total pod time vs VM exec time -----------------------------\n"
    "ax = axes[1, 1]\n"
    "_vm_exec = vm_df['mean_s'].reindex(LEVELS).values\n"
    "_k8s_tot = pod_sum['mean_overhead_s'].reindex(LEVELS).values  # total pod lifetime\n"
    "ax.plot(_x, _vm_exec, 'o-', color=VM_C, linewidth=2, markersize=7, label='VM exec time (survivors)')\n"
    "ax.plot(_x, _k8s_tot, 's-', color=K8S_C, linewidth=2, markersize=7, label='K8s total pod time (startup+exec)')\n"
    "ax.fill_between(_x, _vm_exec, _k8s_tot, where=(_k8s_tot < _vm_exec), alpha=0.15, color=GREEN, label='K8s faster')\n"
    "ax.fill_between(_x, _vm_exec, _k8s_tot, where=(_k8s_tot >= _vm_exec), alpha=0.10, color=VM_C)\n"
)

NEW_DASH_P4 = (
    "# -- Panel 4: K8s total pod time vs VM exec time -----------------------------\n"
    "ax = axes[1, 1]\n"
    "_vm_exec = vm_df['mean_s'].reindex(LEVELS).values if not vm_df.empty else np.full(len(LEVELS), np.nan)\n"
    "_k8s_tot = pod_sum['mean_overhead_s'].reindex(LEVELS).values if _has_overhead else np.full(len(LEVELS), np.nan)\n"
    "ax.plot(_x, _vm_exec, 'o-', color=VM_C, linewidth=2, markersize=7, label='VM exec time (survivors)')\n"
    "ax.plot(_x, _k8s_tot, 's-', color=K8S_C, linewidth=2, markersize=7, label='K8s total pod time (startup+exec)')\n"
    "_valid = ~np.isnan(_vm_exec) & ~np.isnan(_k8s_tot)\n"
    "if _valid.any():\n"
    "    ax.fill_between(_x, _vm_exec, _k8s_tot, where=_valid & (_k8s_tot < _vm_exec), alpha=0.15, color=GREEN, label='K8s faster')\n"
    "    ax.fill_between(_x, _vm_exec, _k8s_tot, where=_valid & (_k8s_tot >= _vm_exec), alpha=0.10, color=VM_C)\n"
)

patched = 0
for cell in nb['cells']:
    if cell['cell_type'] != 'code':
        continue
    src = ''.join(cell['source'])
    new_src = src
    if OLD_FUNC in new_src:
        new_src = new_src.replace(OLD_FUNC, NEW_FUNC)
        patched += 1
    if OLD_DASH_P3 in new_src:
        new_src = new_src.replace(OLD_DASH_P3, NEW_DASH_P3)
        patched += 1
    if OLD_DASH_P4 in new_src:
        new_src = new_src.replace(OLD_DASH_P4, NEW_DASH_P4)
        patched += 1
    if new_src != src:
        cell['source'] = [new_src]

NB.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding='utf-8')
print(f"Patched {patched} location(s). Saved to {NB}")
