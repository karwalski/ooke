#!/usr/bin/env python3
"""run_build.py — story 134.4. Macro runtime measurement of ooke using the
Epic 131.5 method, by importing run_patterns.py itself: same run_once
(perf_counter wall around spawn->exit, ru_maxrss from os.wait4), same
bootstrap_ci (1000 resamples, seed 131), same 2 warm-ups + N timed runs,
same DEFAULT_MAX_LOAD=2.0 guard, same liballoccount.dylib alloc pass.
"""
import argparse, hashlib, json, os, platform, shutil, statistics, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, os.path.expanduser("~/tk/toke/bench/patterns"))
sys.path.insert(0, os.path.expanduser("~/tk/toke/scripts/patterns"))
import run_patterns as rp

ROOT = Path("/private/tmp/s134_4")
DYLIB = Path(os.path.expanduser("~/tk/toke/bench/patterns/liballoccount.dylib"))

def tree_sha(d):
    h = hashlib.sha256()
    for p in sorted(Path(d).rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(d)).encode()); h.update(p.read_bytes())
    return h.hexdigest()

def run_cmd(argv, cwd, timeout_s, extra_env=None, want_stderr=False):
    """run_patterns.run_once, but for an arbitrary argv/cwd."""
    env = dict(os.environ)
    if extra_env: env.update(extra_env)
    res = rp.RunResult()
    import select, signal
    stderr_target = subprocess.PIPE if want_stderr else subprocess.DEVNULL
    t0 = time.perf_counter()
    p = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE, stderr=stderr_target, cwd=str(cwd))
    fds = {p.stdout.fileno(): []}
    if want_stderr: fds[p.stderr.fileno()] = []
    deadline = t0 + timeout_s; open_fds = set(fds)
    while open_fds:
        rem = deadline - time.perf_counter()
        if rem <= 0:
            try: os.kill(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            res.timed_out = True; break
        ready, _, _ = select.select(list(open_fds), [], [], rem)
        for fd in ready:
            data = os.read(fd, 65536)
            if data: fds[fd].append(data)
            else: open_fds.discard(fd)
    _, status, ru = os.wait4(p.pid, 0)
    res.wall_ms = (time.perf_counter() - t0) * 1000.0
    res.rss_kb = ru.ru_maxrss // 1024
    res.status = os.waitstatus_to_exitcode(status) if not res.timed_out else -9
    res.stdout = b"".join(fds[p.stdout.fileno()])
    if want_stderr: res.stderr = b"".join(fds[p.stderr.fileno()])
    for f in (p.stdout, p.stderr):
        if f: f.close()
    return res

def measure(name, binary, fixture, argv_tail, runs, warmups, outdir_rel, timeout_s=120.0):
    wk = ROOT / f"wk-{name}"
    walls, rsses = [], []
    out_sha = None
    for i in range(warmups + runs):
        if wk.exists(): shutil.rmtree(wk)
        shutil.copytree(fixture, wk, symlinks=False)
        r = run_cmd([str(binary)] + argv_tail, wk, timeout_s)
        if r.status != 0 or r.timed_out:
            return {"error": f"exit={r.status} timed_out={r.timed_out}", "stdout": r.stdout[-400:].decode('utf8','replace')}
        if i >= warmups:
            walls.append(r.wall_ms); rsses.append(r.rss_kb)
            s = tree_sha(wk / outdir_rel)
            if out_sha is None: out_sha = s
            elif out_sha != s: return {"error": "output_nondeterministic"}
    # allocations: one extra run under the counter
    if wk.exists(): shutil.rmtree(wk)
    shutil.copytree(fixture, wk, symlinks=False)
    ar = run_cmd([str(binary)] + argv_tail, wk, timeout_s,
                 extra_env={"DYLD_INSERT_LIBRARIES": str(DYLIB)}, want_stderr=True)
    allocs = rp.parse_alloc(ar.stderr) if not ar.timed_out else None
    if wk.exists(): shutil.rmtree(wk)
    return {
        "runs": runs, "warmups": warmups,
        "wall_ms_median": round(statistics.median(walls), 3),
        "wall_ci95": rp.bootstrap_ci(walls),
        "wall_min": round(min(walls), 3), "wall_max": round(max(walls), 3),
        "wall_samples": [round(w, 3) for w in walls],
        "rss_kb_median": int(statistics.median(rsses)),
        "rss_kb_min": min(rsses), "rss_kb_max": max(rsses),
        "allocs": allocs, "output_sha256": out_sha,
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=15)
    ap.add_argument("--warmups", type=int, default=2)
    ap.add_argument("--max-load", type=float, default=rp.DEFAULT_MAX_LOAD)
    ap.add_argument("--allow-load", action="store_true")
    ap.add_argument("--fixture", default=str(ROOT / "fixture-site"))
    ap.add_argument("--outdir", default="build-docs")
    ap.add_argument("--variants", default="before,after")
    ap.add_argument("--tag", default="run")
    a = ap.parse_args()
    load = os.getloadavg()[0]
    if load > a.max_load and not a.allow_load:
        print(f"run_ooke: 1-min loadavg {load:.2f} > {a.max_load} — machine busy; retry later", file=sys.stderr)
        sys.exit(2)
    rec = {"tag": a.tag, "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
           "machine": {"model": rp.sh(["sysctl","-n","hw.model"]), "cpus": os.cpu_count(),
                       "mem_bytes": int(rp.sh(["sysctl","-n","hw.memsize"]) or 0),
                       "os": platform.platform(), "python": platform.python_version()},
           "loadavg_1min_start": round(load, 2), "max_load": a.max_load,
           "load_warning": load > a.max_load,
           "tkc": {"path": "/private/tmp/s134_4/toke-clean/toke",
                   "sha256": hashlib.sha256(open("/private/tmp/s134_4/toke-clean/toke","rb").read()).hexdigest()},
           "fixture": a.fixture, "fixture_sha256": tree_sha(a.fixture),
           "variants": {}}
    for v in a.variants.split(","):
        binary = ROOT / f"ooke-{v}" / "ooke-toke"
        print(f"  {v}: {binary}", file=sys.stderr)
        rec["variants"][v] = {
            "binary": str(binary),
            "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "binary_bytes": binary.stat().st_size,
            **measure(v, binary, a.fixture, ["build", "."], a.runs, a.warmups, a.outdir),
        }
        print(f"    wall {rec['variants'][v].get('wall_ms_median')} ms  rss {rec['variants'][v].get('rss_kb_median')} kB", file=sys.stderr)
    rec["loadavg_1min_end"] = round(os.getloadavg()[0], 2)
    rec["load_warning"] = rec["load_warning"] or rec["loadavg_1min_end"] > a.max_load
    out = ROOT / f"results-{a.tag}.json"
    out.write_text(json.dumps(rec, indent=1))
    print(json.dumps({k: rec[k] for k in ("tag","loadavg_1min_start","loadavg_1min_end","load_warning")}, indent=1))
    print(f"-> {out}")

if __name__ == "__main__":
    main()
