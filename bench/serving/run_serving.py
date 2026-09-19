#!/usr/bin/env python3
"""run_serving.py — web-serving benchmark harness for ooke (story 134.6, baseline half).

Method is deliberately a mirror of toke's `bench/patterns/run_patterns.py` (131.5):

  * every measured binary is **pinned** — copied to a private temp dir and
    sha256'd — before the first measurement, so a concurrent `make` in
    toke/, toke-ooke/ or toke-website/ cannot swap the binary mid-run
    (the same failure 131.39 fixed for tkc; two other agents are on
    toke-ooke's build path while this runs);
  * central tendency is the **median**, never the mean, with a percentile
    **bootstrap 95 % CI** (1000 resamples, fixed seed) so two numbers can be
    compared rather than merely printed;
  * resident memory comes from the same kernel counters run_patterns uses:
    `os.wait4` rusage (ru_maxrss) for the process we spawn, plus `ps` RSS
    sampling of the whole process group, because the toke HTTP server forks
    worker processes whose rusage is reported to *their* parent, not to us;
  * `hw.model`, cpu count, OS, thermal state and 1-minute load average are
    stamped into every results file, and `--max-load` / `--allow-load` work
    exactly as in run_patterns: the run refuses to start above the load
    ceiling unless `--allow-load` is given, in which case every result
    carries `load_warning: true`.

WHAT IS MEASURED
  cold start   process launch -> first byte of the first served response
  ttfb         time to first byte, fresh connection and reused connection,
               for a static page, a templated page and an API route
  throughput   requests/second over a concurrency sweep, with the knee
  memory       RSS at idle and under sustained load
  size/build   binary size on disk, clean build wall time

SERVERS
  website   ~/tk/toke-website `website` binary — the real site, toke's std.http
  ooke      ~/tk/toke-ooke `ooke-toke serve` on ooke's own testproj scaffold
  caddy     caddy file-server over the same build/ directory — the reference

Results: bench/serving/results/<YYYY-MM-DD>.json.  macOS only.  Stdlib only.
"""
from __future__ import annotations

import argparse
import atexit
import datetime as dt
import errno
import hashlib
import json
import os
import platform
import random
import re
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent                 # bench/serving
OOKE_ROOT = HERE.parents[1]                            # toke-ooke
RESULTS = HERE / "results"
TOKE_ROOT = Path(os.environ.get("TOKE_ROOT", Path.home() / "tk" / "toke"))
WEBSITE_ROOT = Path(os.environ.get("WEBSITE_ROOT", Path.home() / "tk" / "toke-website"))

sys.path.insert(0, str(TOKE_ROOT / "scripts" / "patterns"))
try:
    import tkc_pin  # noqa: E402  (131.39) — only for the compiler stamp
except Exception:                                      # pragma: no cover
    tkc_pin = None

BOOTSTRAP = 1000
DEFAULT_MAX_LOAD = 2.0
HOST = "127.0.0.1"


# ─────────────────────────── helpers ────────────────────────────────────────
def die(msg, code=2):
    print(f"run_serving: {msg}", file=sys.stderr)
    sys.exit(code)


def sh(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kw).stdout.strip()
    except Exception:
        return ""


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def bootstrap_ci(samples, resamples=BOOTSTRAP, seed=1346):
    """Percentile bootstrap 95 % CI of the median (same routine as run_patterns)."""
    if not samples:
        return [None, None]
    if len(samples) < 2:
        return [round(samples[0], 4), round(samples[0], 4)]
    rng = random.Random(seed)
    n = len(samples)
    meds = sorted(statistics.median(rng.choices(samples, k=n)) for _ in range(resamples))
    return [round(meds[int(0.025 * resamples)], 4),
            round(meds[min(resamples - 1, int(0.975 * resamples))], 4)]


def pct(samples, q):
    if not samples:
        return None
    s = sorted(samples)
    k = min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))
    return s[k]


def summarise(samples, unit="ms"):
    if not samples:
        return {"n": 0}
    return {
        "n": len(samples),
        "unit": unit,
        "min": round(min(samples), 4),
        "median": round(statistics.median(samples), 4),
        "ci95_median": bootstrap_ci(samples),
        "p95": round(pct(samples, 0.95), 4),
        "p99": round(pct(samples, 0.99), 4),
        "max": round(max(samples), 4),
        "mean": round(statistics.fmean(samples), 4),
        "stdev": round(statistics.stdev(samples), 4) if len(samples) > 1 else 0.0,
    }


def load_now():
    """1-min load average, stamped on every phase: this machine is shared with other
    agents and with a security scanner that storms, so a number measured at load 80 is
    not the same measurement as one taken at load 5."""
    return round(os.getloadavg()[0], 2)


def free_port():
    s = socket.socket()
    s.bind((HOST, 0))
    p = s.getsockname()[1]
    s.close()
    return p


# ─────────────────────────── binary pinning (131.39 discipline) ─────────────
class Pin:
    """A private copy of a binary, so a concurrent rebuild cannot change it mid-run."""

    def __init__(self, src: Path, pin_dir: Path, name=None):
        self.source = str(src)
        self.name = name or src.name
        self.path = str(pin_dir / self.name)
        shutil.copy2(src, self.path)
        os.chmod(self.path, 0o755)
        self.size = os.path.getsize(self.path)
        self.sha256 = sha256_file(self.path)
        self.src_sha256 = sha256_file(src)
        self.src_mtime = dt.datetime.fromtimestamp(os.path.getmtime(src),
                                                   dt.timezone.utc).isoformat(timespec="seconds")

    def stamp(self):
        return {"pinned_copy": self.path, "source": self.source, "sha256": self.sha256,
                "source_sha256_at_pin": self.src_sha256, "source_mtime_utc": self.src_mtime,
                "size_bytes": self.size}


# ─────────────────────────── HTTP client ────────────────────────────────────
class HttpError(Exception):
    pass


def _dechunk(raw):
    """Strip HTTP/1.1 chunked framing so body sizes are comparable across servers."""
    out, i = bytearray(), 0
    while i < len(raw):
        j = raw.find(b"\r\n", i)
        if j < 0:
            break
        try:
            n = int(raw[i:j].split(b";")[0], 16)
        except ValueError:
            return bytes(raw)
        if n == 0:
            break
        out += raw[j + 2:j + 2 + n]
        i = j + 2 + n + 2
    return bytes(out)


def _read_response(s, buf=b"", dechunk=True):
    """Read one complete HTTP/1.1 response. Returns (status, headers, body, t_first_byte)."""
    t_first = None
    while b"\r\n\r\n" not in buf:
        d = s.recv(65536)
        if not d:
            raise HttpError("connection closed in headers")
        if t_first is None:
            t_first = time.perf_counter()
        buf += d
    if t_first is None:
        t_first = time.perf_counter()
    head, body = buf.split(b"\r\n\r\n", 1)
    lines = head.decode("latin1").split("\r\n")
    try:
        status = int(lines[0].split()[1])
    except (IndexError, ValueError):
        raise HttpError(f"bad status line {lines[0]!r}")
    hdrs = {}
    for ln in lines[1:]:
        if ":" in ln:
            k, v = ln.split(":", 1)
            hdrs[k.lower().strip()] = v.strip()
    if "content-length" in hdrs:
        n = int(hdrs["content-length"])
        while len(body) < n:
            d = s.recv(65536)
            if not d:
                raise HttpError("short body")
            body += d
        rest, body = body[n:], body[:n]
    elif hdrs.get("transfer-encoding", "").lower() == "chunked":
        while not body.endswith(b"0\r\n\r\n"):
            d = s.recv(65536)
            if not d:
                raise HttpError("short chunked body")
            body += d
        rest = b""
        if dechunk:   # so byte counts compare with Content-Length servers
            body = _dechunk(body)
    else:
        rest = b""
    return status, hdrs, body, t_first, rest


def request(port, path, sock=None, timeout=10.0, dechunk=True):
    """One GET. Returns (status, nbytes, ttfb_ms, total_ms, sock_or_None).

    `sock=None` opens a fresh connection and the connect time is *included* in
    ttfb — that is what a browser's first paint sees. Pass a live socket to
    measure the reused-connection case instead."""
    fresh = sock is None
    t0 = time.perf_counter()
    if fresh:
        sock = socket.create_connection((HOST, port), timeout=timeout)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(timeout)
    req = (f"GET {path} HTTP/1.1\r\nHost: {HOST}:{port}\r\n"
           f"User-Agent: toke-bench/134.6\r\nAccept: */*\r\n\r\n").encode()
    if not fresh:
        t0 = time.perf_counter()
    sock.sendall(req)
    status, hdrs, body, t_first, _ = _read_response(sock, dechunk=dechunk)
    t_end = time.perf_counter()
    keep = hdrs.get("connection", "").lower() != "close"
    return status, len(body), (t_first - t0) * 1000.0, (t_end - t0) * 1000.0, (sock if keep else None)


def wait_until_serving(port, path, deadline_s, proc=None, t_start=None):
    """Busy-poll until the first byte of a real response arrives.

    Returns seconds measured from `t_start` (default: entry to this function) to
    that first byte, or None if the deadline passed or the process died. Pass the
    instant captured just before fork/exec to get a true cold-start number."""
    t_enter = time.perf_counter()
    t0 = t_enter if t_start is None else t_start
    while time.perf_counter() - t_enter < deadline_s:
        if proc is not None and proc.poll() is not None:
            return None
        try:
            s = socket.create_connection((HOST, port), timeout=1.0)
        except OSError as e:
            if e.errno in (errno.ECONNREFUSED, errno.ECONNRESET, errno.EADDRNOTAVAIL, errno.ETIMEDOUT):
                time.sleep(0.0002)
                continue
            raise
        try:
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            s.settimeout(2.0)
            s.sendall((f"GET {path} HTTP/1.1\r\nHost: {HOST}:{port}\r\n"
                       f"User-Agent: toke-bench/134.6\r\n\r\n").encode())
            status, _, _, t_first, _ = _read_response(s)
            if status == 200:
                return t_first - t0
        except (OSError, HttpError):
            time.sleep(0.0002)
            continue
        finally:
            try:
                s.close()
            except OSError:
                pass
    return None


# ─────────────────────────── server control ─────────────────────────────────
class Server:
    """A server under test: how to launch it, where, and on what routes."""

    def __init__(self, key, label, argv_fn, cwd, ready_path, routes, port_mode,
                 stack, load_routes=(), prepare=None):
        self.key, self.label = key, label
        self.argv_fn, self.cwd = argv_fn, Path(cwd)
        self.ready_path, self.routes = ready_path, routes
        self.load_routes = list(load_routes) or list(routes)[:1]
        self.port_mode = port_mode              # "argv" | "config"
        self.stack = stack
        self.prepare = prepare                  # fn(port) -> None, for config-port servers
        self.proc = None
        self.port = None
        self.log = None

    def start(self, port, logdir):
        if self.prepare:
            self.prepare(port)
        self.port = port
        self.log = open(Path(logdir) / f"{self.key}-{port}.log", "wb")
        t0 = time.perf_counter()
        self.proc = subprocess.Popen(self.argv_fn(port), cwd=str(self.cwd),
                                     stdout=self.log, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
        return t0

    def pids(self):
        """The server's whole process group (it forks workers)."""
        if not self.proc:
            return []
        out = sh(["ps", "-o", "pid=", "-g", str(self.proc.pid)])
        pids = [int(x) for x in out.split()] if out else []
        return pids or [self.proc.pid]

    def rss_detail(self):
        """[(pid, rss_kb)] for the whole process group. RSS sums over forked
        workers double-count copy-on-write pages, so the per-pid breakdown is
        kept alongside the sum."""
        pids = self.pids()
        if not pids:
            return []
        out = sh(["ps", "-o", "pid=,rss=", "-p", ",".join(str(p) for p in pids)])
        rows = []
        for ln in out.splitlines():
            parts = ln.split()
            if len(parts) == 2:
                rows.append((int(parts[0]), int(parts[1])))
        return rows

    def rss_kb(self):
        rows = self.rss_detail()
        return sum(v for _, v in rows) if rows else None

    def stop(self):
        """SIGTERM the group, SIGKILL what survives, reap with wait4 for rusage."""
        if not self.proc:
            return {}
        rus = {}
        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
        except OSError:
            pass
        killed = False
        for _ in range(30):
            if self.proc.poll() is not None:
                break
            time.sleep(0.1)
        else:
            killed = True
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except OSError:
                pass
        try:
            pid, status, ru = os.wait4(self.proc.pid, 0)
            rus = {"ru_maxrss_kb": round(ru.ru_maxrss / 1024.0),   # macOS reports bytes
                   "ru_utime_s": round(ru.ru_utime, 3),
                   "ru_stime_s": round(ru.ru_stime, 3),
                   "exit_status": status}
        except (ChildProcessError, OSError):
            rus = {}
        rus["needed_sigkill"] = killed
        # sweep any orphaned workers
        for p in self.pids():
            try:
                os.kill(p, signal.SIGKILL)
            except OSError:
                pass
        if self.log:
            self.log.close()
        self.proc = None
        return rus


# ─────────────────────────── phases ─────────────────────────────────────────
def precheck_routes(server, logdir, deadline_s, log):
    """Serve every route once and record status, size and body sha256 BEFORE measuring.

    This exists because a concurrent agent rebuilt `toke-website/build/` mid-run and
    `/index.html` disappeared: 150 TTFB samples were quietly collected against 404s.
    The body sha256 recorded here pins the exact content every later number was
    measured over."""
    port = free_port()
    server.start(port, logdir)
    if wait_until_serving(port, server.ready_path, deadline_s, server.proc) is None:
        server.stop()
        return {"status": "server_would_not_start"}
    routes, bad = {}, []
    for name, path in server.routes.items():
        try:
            st, nb, ttfb, tot, sk = request(port, path)
            if sk:
                sk.close()
        except (OSError, HttpError) as e:
            routes[name] = {"path": path, "error": repr(e)}
            bad.append(name)
            continue
        # re-fetch to hash the body
        try:
            sock = socket.create_connection((HOST, port), timeout=10)
            sock.sendall((f"GET {path} HTTP/1.1\r\nHost: {HOST}:{port}\r\n\r\n").encode())
            st2, hdrs, body, _, _ = _read_response(sock)
            sock.close()
            digest = hashlib.sha256(body).hexdigest()
        except (OSError, HttpError):
            digest = None
        routes[name] = {"path": path, "status": st, "bytes": nb, "body_sha256": digest}
        if st != 200 or nb == 0:
            bad.append(name)
    server.stop()
    out = {"status": "ok" if not bad else "failed", "routes": routes, "bad": bad,
           "loadavg_1min": load_now()}
    for n, r in routes.items():
        log(f"    {n:<16} {r.get('status')} {r.get('bytes')} B  "
            f"{(r.get('body_sha256') or '')[:12]}")
    return out


def measure_cold_start(server, trials, logdir, deadline_s, log):
    """Process launch -> first byte of the first served response, `trials` times."""
    samples, fails = [], 0
    for i in range(trials):
        port = free_port()
        t0 = server.start(port, logdir)
        dt_s = wait_until_serving(port, server.ready_path, deadline_s, server.proc, t_start=t0)
        if dt_s is None:
            fails += 1
        else:
            samples.append(dt_s * 1000.0)
        server.stop()
        log(f"    cold[{i + 1}/{trials}] {'fail' if dt_s is None else f'{dt_s * 1000:.1f} ms'}")
    out = summarise(samples)
    out["trials"] = trials
    out["failures"] = fails
    out["loadavg_1min"] = load_now()
    out["definition"] = ("wall from just before fork/exec to the first byte of the first "
                         "HTTP 200 on " + server.ready_path + "; the client busy-polls "
                         "connect() so poll granularity is ~0.2 ms, not a fixed sleep")
    return out


def measure_ttfb(server, n_fresh, n_reused, warmup, logdir, deadline_s, log):
    """Median/p95 TTFB per route, fresh connection and reused connection.

    The server is RESTARTED before every route. toke's std.http carries a
    hard-coded per-source-IP limiter (`RATE_LIMIT_MAX 200` connections per
    `RATE_LIMIT_WINDOW 60` s, http.c:664-701) applied in `handle_connection`,
    i.e. per TCP connection, not per request, and each forked worker keeps its
    own table. A fresh-connection batch therefore burns one rate-limit slot per
    sample: n_fresh is kept under 200 and the counter is reset by the restart.
    Any 429 that still appears is recorded rather than dropped."""
    out = {}
    for name, path in server.routes.items():
        entry = {"path": path}
        port = free_port()
        server.start(port, logdir)
        if wait_until_serving(port, server.ready_path, deadline_s, server.proc) is None:
            entry["status"] = "server_would_not_start"
            server.stop()
            out[name] = entry
            continue

        # warm up on ONE reused connection so warm-up costs no rate-limit slots
        sock = None
        for _ in range(warmup):
            try:
                st, nb, ttfb, tot, sock = request(port, path, sock=sock)
            except (OSError, HttpError):
                sock = None
        if sock:
            sock.close()

        fresh, total, sizes, statuses, errs = [], [], set(), {}, []
        for _ in range(n_fresh):
            try:
                st, nb, ttfb, tot, sk = request(port, path)
                if sk:
                    sk.close()
            except (OSError, HttpError) as e:
                errs.append(repr(e))
                continue
            statuses[st] = statuses.get(st, 0) + 1
            if st != 200:
                continue
            sizes.add(nb)
            fresh.append(ttfb)
            total.append(tot)

        ka, ka_err, ka_status = [], 0, {}
        sock = None
        for _ in range(n_reused):
            try:
                st, nb, ttfb, tot, sock = request(port, path, sock=sock)
                ka_status[st] = ka_status.get(st, 0) + 1
                if st == 200:
                    ka.append(ttfb)
                else:
                    ka_err += 1
            except (OSError, HttpError):
                ka_err += 1
                sock = None
        if sock:
            sock.close()
        entry["fresh_status_counts"] = {str(k): v for k, v in statuses.items()}
        entry["reused_status_counts"] = {str(k): v for k, v in ka_status.items()}
        entry["body_bytes"] = sorted(sizes)
        entry["ttfb_fresh_conn_ms"] = summarise(fresh)
        entry["total_fresh_conn_ms"] = summarise(total)
        entry["ttfb_reused_conn_ms"] = summarise(ka)
        entry["fresh_conn_errors"] = len(errs)
        entry["fresh_conn_error_sample"] = errs[:3]
        entry["reused_conn_errors"] = ka_err
        entry["loadavg_1min"] = load_now()
        entry["definition"] = ("fresh: connect() through to the first byte of the response, "
                               "one new TCP connection per sample, connection setup INCLUDED "
                               "— what a browser sees on a cold link. reused: send through "
                               "first byte on an already-open keep-alive connection — the "
                               "server's own service time.")
        server.stop()
        out[name] = entry
        m = entry["ttfb_fresh_conn_ms"]
        log(f"    ttfb {name:<16} fresh median {m.get('median')} ms  p95 {m.get('p95')} ms  "
            f"reused median {entry['ttfb_reused_conn_ms'].get('median')} ms  "
            f"({entry['body_bytes']} B, n={m.get('n')}, statuses {entry['fresh_status_counts']})")
    return out


def probe_rate_limit(server, logdir, deadline_s, log, cap=600, recovery=True):
    """Open fresh connections until the server stops answering 200, then (optionally)
    wait out the window and check recovery. Records a product characteristic, not
    just a measurement nuisance."""
    port = free_port()
    server.start(port, logdir)
    if wait_until_serving(port, server.ready_path, deadline_s, server.proc) is None:
        server.stop()
        return {"status": "server_would_not_start"}
    path = server.routes.get("api") or server.ready_path
    first_bad, bad_status, n_ok = None, None, 0
    t0 = time.perf_counter()
    for i in range(cap):
        try:
            st, nb, ttfb, tot, sk = request(port, path)
            if sk:
                sk.close()
        except (OSError, HttpError) as e:
            first_bad, bad_status = i, repr(e)
            break
        if st == 200:
            n_ok += 1
        else:
            first_bad, bad_status = i, st
            break
    elapsed = time.perf_counter() - t0
    out = {"loadavg_1min": load_now(),
           "fresh_connections_before_first_non_200": first_bad,
           "first_non_200": bad_status,
           "ok_before": n_ok,
           "elapsed_s": round(elapsed, 3),
           "cap": cap,
           "path": path,
           "method": "sequential fresh TCP connections, one request each, closed by the client"}
    if first_bad is not None and recovery:
        time.sleep(62)
        try:
            st, nb, ttfb, tot, sk = request(port, path)
            if sk:
                sk.close()
            out["recovered_after_62s"] = (st == 200)
            out["recovery_status"] = st
        except (OSError, HttpError) as e:
            out["recovered_after_62s"] = False
            out["recovery_status"] = repr(e)
    server.stop()
    log(f"    rate limit: {first_bad} fresh connections in {out['elapsed_s']} s before "
        f"{bad_status}; recovered after 62 s: {out.get('recovered_after_62s')}")
    return out


def _load_worker(port, path, concurrency, duration, results, lock, stop_evt):
    lat, ok, err, statuses, conns = [], 0, 0, {}, 0
    sock = None
    deadline = time.perf_counter() + duration
    while time.perf_counter() < deadline and not stop_evt.is_set():
        try:
            if sock is None:
                conns += 1
            st, nb, ttfb, tot, sock = request(port, path, sock=sock, timeout=10.0,
                                              dechunk=False)
            statuses[st] = statuses.get(st, 0) + 1
            if st == 200:
                ok += 1
                lat.append(tot)
            else:
                err += 1
        except (OSError, HttpError) as e:
            err += 1
            statuses[repr(e)[:40]] = statuses.get(repr(e)[:40], 0) + 1
            sock = None
    if sock:
        try:
            sock.close()
        except OSError:
            pass
    with lock:
        results["ok"] += ok
        results["err"] += err
        results["conns"] += conns
        results["lat"].extend(lat)
        for k, v in statuses.items():
            results["statuses"][k] = results["statuses"].get(k, 0) + v


def probe_memory_growth(server, logdir, deadline_s, log, routes=None, total=20000,
                        marks=(2000, 5000, 10000, 20000)):
    """Sustained single-connection load, sampling process-group RSS at fixed request
    counts. Separates 'memory grows with how many requests have been served' (a leak)
    from 'memory is an allocation high-water mark that rises and falls' (churn) —
    the concurrency sweep cannot tell those apart because it varies two things at once."""
    out = {}
    for name in (routes or list(server.routes)):
        path = server.routes[name]
        port = free_port()
        server.start(port, logdir)
        if wait_until_serving(port, server.ready_path, deadline_s, server.proc) is None:
            out[name] = {"status": "server_would_not_start"}
            server.stop()
            continue
        series = [{"requests": 0, "rss_kb": server.rss_kb(), "procs": len(server.pids())}]
        sock, done, t0 = None, 0, time.perf_counter()
        for i in range(1, total + 1):
            try:
                st, nb, ttfb, tot, sock = request(port, path, sock=sock, dechunk=False)
                done += 1
            except (OSError, HttpError):
                sock = None
            if i in marks:
                series.append({"requests": i, "rss_kb": server.rss_kb(),
                               "procs": len(server.pids()),
                               "elapsed_s": round(time.perf_counter() - t0, 2)})
        if sock:
            sock.close()
        rsss = [p["rss_kb"] for p in series[1:] if p["rss_kb"]]
        out[name] = {"path": path, "completed": done, "series": series,
                     "monotonic": all(b >= a for a, b in zip(rsss, rsss[1:])) if rsss else None,
                     "loadavg_1min": load_now(),
                     "method": "one keep-alive connection, RSS = sum over the process group",
                     "reading": "monotonic true would indicate a leak; false means the figure "
                                "is an allocation high-water mark that rises and falls"}
        server.stop()
        log(f"    mem {name:<18} " + "  ".join(
            f"{p['requests']}:{p['rss_kb']}KB" for p in series))
    return out


def measure_throughput(server, path, levels, duration, logdir, deadline_s, log,
                       sample_rss=True):
    """Concurrency sweep with keep-alive. Reports rps, latency and RSS under load.

    The server is RESTARTED for every concurrency level: each level then starts
    from a cold process with an empty rate-limit table and no carried-over state,
    and one bad level cannot poison the next. `conns` counts how many TCP
    connections the level opened (client threads plus reconnects forced by
    KEEPALIVE_MAX_REQUESTS=1000), because that number is what the per-IP limiter
    counts — a level whose `statuses` contains 429 is rate-limited, not saturated."""
    rows = []
    for c in levels:
        port = free_port()
        server.start(port, logdir)
        if wait_until_serving(port, server.ready_path, deadline_s, server.proc) is None:
            rows.append({"concurrency": c, "status": "server_would_not_start"})
            server.stop()
            continue
        results = {"ok": 0, "err": 0, "lat": [], "conns": 0, "statuses": {}}
        lock = threading.Lock()
        stop_evt = threading.Event()
        rss_samples = []

        def sampler():
            while not stop_evt.is_set():
                v = server.rss_kb()
                if v:
                    rss_samples.append(v)
                time.sleep(0.1)

        th = [threading.Thread(target=_load_worker,
                               args=(port, path, c, duration, results, lock, stop_evt))
              for _ in range(c)]
        smp = threading.Thread(target=sampler) if sample_rss else None
        t0 = time.perf_counter()
        if smp:
            smp.start()
        for t in th:
            t.start()
        for t in th:
            t.join(duration + 30)
        stop_evt.set()
        if smp:
            smp.join(5)
        el = time.perf_counter() - t0
        lat = results["lat"]
        row = {
            "concurrency": c,
            "duration_s": round(el, 3),
            "completed": results["ok"],
            "errors": results["err"],
            "connections_opened": results["conns"],
            "statuses": results["statuses"],
            "rate_limited": bool(results["statuses"].get(429)),
            "rps": round(results["ok"] / el, 1) if el else None,
            "latency_ms": summarise(lat),
            "rss_kb_under_load": {"n": len(rss_samples),
                                  "median": statistics.median(rss_samples) if rss_samples else None,
                                  "max": max(rss_samples) if rss_samples else None},
            "loadavg_1min": load_now(),
        }
        rows.append(row)
        server.stop()
        log(f"    c={c:<4} {str(row['rps']):>9} rps  p50 {row['latency_ms'].get('median')} ms  "
            f"p95 {row['latency_ms'].get('p95')} ms  conns {row['connections_opened']}  "
            f"errors {row['errors']}{'  RATE-LIMITED' if row['rate_limited'] else ''}")
    return rows


def knee(rows):
    """Peak rps in the sweep, and the first concurrency ABOVE the peak at which
    throughput falls more than 5 % below it. Rate-limited and failed levels are
    excluded. `degrades_at: null` means throughput never fell that far inside the
    sweep, not that it is unbounded."""
    rows = [r for r in rows if r.get("rps") and not r.get("rate_limited")]
    if not rows:
        return {"peak_rps": None, "peak_concurrency": None, "degrades_at": None}
    peak = max(rows, key=lambda r: r["rps"])
    after = [r for r in rows if r["concurrency"] > peak["concurrency"]
             and r["rps"] < peak["rps"] * 0.95]
    return {"peak_rps": peak["rps"], "peak_concurrency": peak["concurrency"],
            "degrades_at": after[0]["concurrency"] if after else None,
            "rps_at_c1": next((r["rps"] for r in rows if r["concurrency"] == 1), None),
            "rps_at_max_c": rows[-1]["rps"],
            "rule": "peak = highest rps in the sweep; degrades_at = lowest concurrency "
                    "above the peak whose rps is more than 5 % below it; null = no such "
                    "level inside the sweep"}


def measure_build(name, repo, pinned_tkc, log, target_rel):
    """Clean build wall time, in a throwaway copy so no agent's tree is touched."""
    tmp = Path(tempfile.mkdtemp(prefix=f"bench-build-{name}-"))
    dest = tmp / repo.name
    log(f"    copying {repo} -> {dest}")
    r = subprocess.run(["rsync", "-a", "--exclude", ".git", "--exclude", "test-results",
                        f"{repo}/", f"{dest}/"], capture_output=True, text=True)
    if r.returncode != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        return {"status": "copy_failed", "stderr": r.stderr[-2000:]}
    env = dict(os.environ)
    make = ["make"]
    if pinned_tkc:
        make.append(f"TKC={pinned_tkc}")
        make.append(f"TOKE={pinned_tkc}")
    subprocess.run(["make", "clean"], cwd=str(dest), capture_output=True, text=True, timeout=300)
    t0 = time.perf_counter()
    b = subprocess.run(make, cwd=str(dest), capture_output=True, text=True, env=env, timeout=3600)
    el = time.perf_counter() - t0
    target = dest / target_rel
    out = {"status": "ok" if b.returncode == 0 and target.exists() else "failed",
           "returncode": b.returncode,
           "wall_s": round(el, 2),
           "n": 1,
           "target": target_rel,
           "target_bytes": target.stat().st_size if target.exists() else None,
           "make_args": make,
           "loadavg_1min": load_now(),
           "note": "single clean build (`make clean && make`) in a throwaway rsync copy of the "
                   "repo, so no agent's working tree is touched; n=1, and the machine was "
                   "loaded — treat as an order of magnitude, not a gate"}
    if out["status"] != "ok":
        out["stderr_tail"] = b.stderr[-3000:]
    shutil.rmtree(tmp, ignore_errors=True)
    log(f"    build {name}: {out['status']} in {out['wall_s']} s")
    return out


# ─────────────────────────── meta ───────────────────────────────────────────
def collect_meta(args, pins, load, site_dir, site_manifest=None):
    therm = sh(["pmset", "-g", "therm"])
    meta = {
        "date": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "story": "134.6 (baseline half — measures the build as it stands, before the uplift)",
        "harness": "toke-ooke/bench/serving/run_serving.py",
        "hw_model": sh(["sysctl", "-n", "hw.model"]),
        "hw_ncpu": os.cpu_count(),
        "hw_memsize_bytes": int(sh(["sysctl", "-n", "hw.memsize"]) or 0),
        "os": f"{platform.system()} {platform.release()} ({platform.mac_ver()[0]})",
        "python": platform.python_version(),
        "loadavg_1_5_15": [round(x, 2) for x in os.getloadavg()],
        "max_load": args.max_load,
        "load_warning": load > args.max_load,
        "load_caveat": ("a background process permanently pins a core on this machine, so a "
                        "1-min load average below 2 is unreachable; --allow-load was used and "
                        "every number here is therefore measured on a loaded machine. Medians "
                        "and p95s are inflated relative to an idle box; treat them as an upper "
                        "bound on latency and a lower bound on throughput."),
        "thermal": [ln.strip() for ln in therm.splitlines() if ln.strip()],
        "site_dir": str(site_dir),
        "site_content_pin": site_manifest or {},
        "runs": {"cold_trials": args.cold_trials, "ttfb_fresh_n": args.ttfb_fresh_n,
                 "ttfb_reused_n": args.ttfb_reused_n,
                 "warmup": args.warmup, "load_duration_s": args.duration,
                 "concurrency_levels": args.levels},
        "stats": {"central": "median", "ci": "percentile bootstrap, 1000 resamples, seed 1346",
                  "p95": "nearest-rank on the sorted sample"},
        "pins": {k: v.stamp() for k, v in pins.items()},
    }
    if tkc_pin is not None:
        try:
            p = tkc_pin.pin(toke_repo=TOKE_ROOT)
            meta["tkc"] = p.stamp()
            meta["tkc_pinned_path"] = p.path
            atexit.register(p.close)
        except Exception as e:                          # pragma: no cover
            meta["tkc"] = {"error": repr(e)}
    return meta


# ─────────────────────────── main ───────────────────────────────────────────
def build_servers(args, pins, site_dir, ooke_site):
    servers = {}

    if "website" in pins:
        servers["website"] = Server(
            key="website",
            label="toke-website `website` binary (toke std.http, --http, 2 workers)",
            argv_fn=lambda p: [pins["website"].path, "--http", "--port", str(p)],
            cwd=site_dir,
            ready_path="/api/health",
            routes={"static": "/index.html", "templated": "/", "api": "/api/health",
                    "templated_small": "/ooke", "static_small": "/robots.txt"},
            load_routes=("static", "templated", "api", "static_small"),
            port_mode="argv",
            stack="toke 2.8.0 stdlib std.http (tk_web_glue.c servepages/servedir/getstaticmime)",
        )

    if "ooke" in pins and ooke_site:
        def prep(port, d=ooke_site):
            toml = d / "ooke.toml"
            txt = toml.read_text()
            txt = re.sub(r"(?m)^port\s*=\s*\d+", f"port = {port}", txt)
            toml.write_text(txt)

        servers["ooke"] = Server(
            key="ooke",
            label="ooke-toke `serve` on ooke's own testproj scaffold",
            argv_fn=lambda p: [pins["ooke"].path, "serve"],
            cwd=ooke_site,
            ready_path="/api/health",
            routes={"page_prerendered": "/", "api": "/api/health"},
            load_routes=("page_prerendered", "api"),
            port_mode="config",
            stack="ooke src/serve.tk -> toke std.http. NOTE: ooke renders every page "
                  "ONCE at startup (serveregisterstatic -> http.getstatic) and serves the "
                  "rendered HTML from memory, so its page route is an in-memory static "
                  "response, NOT a per-request render. The website binary's "
                  "http.servepages re-reads and re-renders the .tkt from disk on every "
                  "request. The two 'page' numbers are therefore different workloads and "
                  "must not be compared head to head.",
            prepare=prep,
        )

    if "caddy" in pins:
        servers["caddy"] = Server(
            key="caddy",
            label="caddy file-server (Go, production static file server) — REFERENCE",
            argv_fn=lambda p: [pins["caddy"].path, "file-server", "--root",
                               str(site_dir / "build"), "--listen", f"{HOST}:{p}",
                               "--no-compress"],
            cwd=site_dir,
            ready_path="/index.html",
            routes={"static": "/index.html", "static_small": "/robots.txt"},
            load_routes=("static", "static_small"),
            port_mode="argv",
            stack="caddy v2 file-server over the same build/ tree and the same bytes",
        )
    return servers


def main():
    ap = argparse.ArgumentParser(description="ooke web-serving benchmark (134.6 baseline)")
    ap.add_argument("--server", action="append", choices=["website", "ooke", "caddy"],
                    help="server to measure (repeatable; default all available)")
    ap.add_argument("--cold-trials", type=int, default=20)
    ap.add_argument("--ttfb-fresh-n", type=int, default=150,
                    help="fresh-connection TTFB samples per route (kept under the "
                         "hard-coded 200-connections-per-60s per-IP limiter in http.c)")
    ap.add_argument("--ttfb-reused-n", type=int, default=1000,
                    help="reused-connection TTFB samples per route")
    ap.add_argument("--warmup", type=int, default=30)
    ap.add_argument("--duration", type=float, default=4.0, help="seconds per concurrency level")
    ap.add_argument("--levels", type=int, nargs="+", default=[1, 2, 4, 8, 16, 32, 64, 128])
    ap.add_argument("--startup-deadline", type=float, default=60.0)
    ap.add_argument("--skip-build", action="store_true", help="skip the clean-build timing")
    ap.add_argument("--skip-recovery", action="store_true",
                    help="skip the 62 s rate-limit recovery wait")
    ap.add_argument("--max-load", type=float, default=DEFAULT_MAX_LOAD)
    ap.add_argument("--allow-load", action="store_true",
                    help="run even above --max-load; results carry load_warning: true")
    ap.add_argument("--site-snapshot",
                    help="directory to stage the site from instead of WEBSITE_ROOT. Use this "
                         "whenever another agent may be rebuilding toke-website: the content "
                         "must be pinned exactly like the binaries are, or a route can vanish "
                         "mid-run (it did — see README §8)")
    ap.add_argument("--out", help="results path (default results/<date>.json)")
    args = ap.parse_args()

    if sys.platform != "darwin":
        die("macOS only (ru_maxrss units, sysctl hw.model, ps -g)")
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)

    load = os.getloadavg()[0]
    if load > args.max_load and not args.allow_load:
        die(f"1-min loadavg {load:.2f} > {args.max_load} — machine busy; retry later, "
            f"raise --max-load, or pass --allow-load (results flagged load_warning)")
    if load > args.max_load:
        print(f"run_serving: WARNING loadavg {load:.2f} > {args.max_load}; "
              f"results will carry load_warning: true", file=sys.stderr)

    log = lambda *a: print(*a, flush=True)  # noqa: E731

    scratch = Path(tempfile.mkdtemp(prefix="run-serving-"))
    atexit.register(lambda: shutil.rmtree(scratch, ignore_errors=True))
    pin_dir = scratch / "pinned"
    pin_dir.mkdir()
    logdir = scratch / "logs"
    logdir.mkdir()

    # Working copies: never measure inside a tree another agent may be editing.
    site_dir = scratch / "site"
    site_src = Path(args.site_snapshot).resolve() if args.site_snapshot else WEBSITE_ROOT
    log(f"run_serving: staging {site_src} -> {site_dir}")
    subprocess.run(["rsync", "-a", "--exclude", ".git", "--exclude", "test-results",
                    "--exclude", "logs", f"{site_src}/", f"{site_dir}/"], check=True)
    (site_dir / "logs").mkdir(exist_ok=True)
    site_files = [f for f in site_dir.rglob("*") if f.is_file()]
    site_manifest = {"source": str(site_src),
                     "pinned_snapshot": bool(args.site_snapshot),
                     "files": len(site_files),
                     "bytes": sum(f.stat().st_size for f in site_files)}

    ooke_site = scratch / "ookesite"
    if (OOKE_ROOT / "testproj").is_dir():
        subprocess.run(["rsync", "-a", f"{OOKE_ROOT / 'testproj'}/", f"{ooke_site}/"], check=True)
    else:
        ooke_site = None

    want = set(args.server) if args.server else {"website", "ooke", "caddy"}
    pins = {}
    # with a pinned snapshot, pin the binary from the snapshot too, so binary and
    # content are the same instant of the tree
    website_bin = (site_src / "website") if (site_src / "website").exists() \
        else (WEBSITE_ROOT / "website")
    if "website" in want and website_bin.exists():
        pins["website"] = Pin(website_bin, pin_dir, "website")
    if "ooke" in want and (OOKE_ROOT / "ooke-toke").exists():
        pins["ooke"] = Pin(OOKE_ROOT / "ooke-toke", pin_dir, "ooke-toke")
    if "caddy" in want and shutil.which("caddy"):
        pins["caddy"] = Pin(Path(shutil.which("caddy")), pin_dir, "caddy")
    if not pins:
        die("no binaries to measure")

    meta = collect_meta(args, pins, load, site_dir, site_manifest)
    results = {"meta": meta, "servers": {}, "build": {}}
    log(f"run_serving: {meta['hw_model']} ncpu={meta['hw_ncpu']} load={load:.2f} "
        f"pins={list(pins)}")

    servers = build_servers(args, pins, site_dir, ooke_site)
    for key in ("website", "ooke", "caddy"):
        srv = servers.get(key)
        if srv is None:
            continue
        log(f"\n[{key}] {srv.label}")
        entry = {"label": srv.label, "stack": srv.stack, "cwd": str(srv.cwd),
                 "binary": pins[key].stamp(), "routes": srv.routes,
                 "port_mode": srv.port_mode}

        log("  precondition: every route serves 200")
        pre = precheck_routes(srv, logdir, args.startup_deadline, log)
        entry["precondition"] = pre
        if pre["status"] != "ok":
            entry["status"] = "precondition_failed"
            log(f"  !! precondition failed: {pre}")
            results["servers"][key] = entry
            continue

        log("  cold start")
        entry["cold_start_ms"] = measure_cold_start(srv, args.cold_trials, logdir,
                                                    args.startup_deadline, log)
        if entry["cold_start_ms"].get("n", 0) == 0:
            entry["status"] = "would_not_serve"
            entry["evidence_log"] = sorted(str(p) for p in logdir.glob(f"{key}-*.log"))[-1:]
            log("  !! server never served a 200 — skipping the rest for this server")
            results["servers"][key] = entry
            continue

        port = free_port()
        srv.start(port, logdir)
        up = wait_until_serving(port, srv.ready_path, args.startup_deadline, srv.proc)
        if up is None:
            entry["status"] = "would_not_serve_on_second_launch"
            srv.stop()
            results["servers"][key] = entry
            continue

        time.sleep(1.0)
        idle = [srv.rss_kb() for _ in range(10)]
        idle = [v for v in idle if v]
        entry["rss_kb_idle"] = {"n": len(idle),
                                "median": statistics.median(idle) if idle else None,
                                "per_pid": srv.rss_detail(),
                                "note": "sum of RSS over the server's whole process group "
                                        "(`ps -o rss= -g <pgid>`), sampled 1 s after the first "
                                        "200 and before any load; includes forked workers, so "
                                        "copy-on-write pages are counted once per worker — the "
                                        "per-pid breakdown is given so the sum can be discounted"}
        entry["worker_processes"] = len(srv.pids())
        entry["rusage_idle"] = srv.stop()

        log("  rate-limit probe")
        entry["rate_limit"] = probe_rate_limit(srv, logdir, args.startup_deadline, log,
                                               recovery=not args.skip_recovery)

        log("  ttfb (server restarted per route)")
        entry["ttfb"] = measure_ttfb(srv, args.ttfb_fresh_n, args.ttfb_reused_n,
                                     args.warmup, logdir, args.startup_deadline, log)

        log("  memory growth probe (single connection, sustained)")
        entry["memory_growth"] = probe_memory_growth(srv, logdir, args.startup_deadline, log)

        entry["throughput"] = {}
        under = []
        for rname in srv.load_routes:
            lp = srv.routes[rname]
            log(f"  throughput on {rname} ({lp}) — server restarted per level")
            lv = measure_throughput(srv, lp, args.levels, args.duration, logdir,
                                    args.startup_deadline, log)
            entry["throughput"][rname] = {
                "path": lp,
                "mode": "keep-alive, one connection per client thread, reconnect on close, "
                        "server restarted before each concurrency level",
                "client": "python3 threads, blocking sockets. Control: at c=1 the measured "
                          "requests/second equals 1/mean-latency to three digits, so the "
                          "client adds no measurable per-request overhead at that level. "
                          "Above ~8 threads the GIL is a plausible ceiling; the caddy rows "
                          "are the control — where caddy goes higher on the same route, the "
                          "client was not the limit.",
                "levels": lv,
                "knee": knee(lv),
            }
            under += [r["rss_kb_under_load"]["max"] for r in lv
                      if r.get("rss_kb_under_load", {}).get("max")]
        entry["rss_kb_under_load_max"] = max(under) if under else None
        entry["status"] = "ok"
        results["servers"][key] = entry

    if not args.skip_build:
        log("\n[build] clean build timings (throwaway copies)")
        tkc = meta.get("tkc_pinned_path")
        if "website" in pins:
            results["build"]["website"] = measure_build("website", site_src, tkc, log, "website")
        if "ooke" in pins:
            results["build"]["ooke"] = measure_build("ooke", OOKE_ROOT, tkc, log, "ooke-toke")

    results["meta"]["loadavg_1min_at_end"] = load_now()
    results["binary_sizes"] = {k: {"path": v.source, "bytes": v.size, "sha256": v.sha256}
                               for k, v in pins.items()}

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = Path(args.out) if args.out else RESULTS / f"{dt.date.today().isoformat()}.json"
    out.write_text(json.dumps(results, indent=1) + "\n")
    log(f"\nresults: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
