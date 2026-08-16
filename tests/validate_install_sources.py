#!/usr/bin/env python3
"""
RabbitHole install-source validator.

Verifies that every tool declared in:
  - roles/*/plugin.yaml   (v2.0.0 framework, authoritative)
  - rabbithole.sh         (legacy installer, role install_* functions)
has a VALID and REACHABLE install source, so that when the real installer
runs the tool WILL be downloaded.

It does NOT download any tool binary:
  - git sources  -> `git ls-remote` (lists refs only, no clone)
  - pypi/cargo  -> tiny JSON API GET (no package download)
  - http/wget   -> `curl -I/-L -o /dev/null` (headers only, no body)
  - native      -> structural check (distro package, no network)
  - custom      -> extracts embedded URLs and checks them

Exit code 0 = all reachable, non-zero = at least one source unreachable.
"""

import os
import re
import sys
import json
import subprocess
import concurrent.futures

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROLES_DIR = os.path.join(ROOT, "roles")
LEGACY = os.path.join(ROOT, "rabbithole.sh")

# ---------------------------------------------------------------------------
# Low level check primitives (no downloads)
# ---------------------------------------------------------------------------

def _run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def curl_status(url, timeout=25):
    # Range 0-0 => fetch only 1 byte (no tool binary is actually downloaded),
    # follow redirects, report the final HTTP status code.
    code, out, err = _run(
        ["curl", "-s", "-r", "0-0", "-L", "-o", os.devnull, "-w", "%{http_code}",
         "-H", "User-Agent: RabbitHole-Validator/1.0",
         "--max-time", str(timeout), url]
    )
    if code != 0:
        return None, f"curl exit {code}: {err.strip()[:120]}"
    out = out.strip()
    return (int(out) if out.isdigit() else None), ("" if out.isdigit() else out[:120])


def git_ls(url, timeout=30):
    code, _, err = _run(["git", "ls-remote", "--quiet", "--heads", url], timeout)
    if code == 0:
        return True, ""
    code2, _, _ = _run(["git", "ls-remote", "--quiet", "--tags", url], timeout)
    if code2 == 0:
        return True, ""
    return False, (err.strip()[:120] or f"exit {code}")


def go_repo(path):
    m = re.search(r"(github\.com/[^/\s]+/[^/\s@]+)", path)
    return ("https://" + m.group(1)) if m else None


def check_git(url):
    ok, detail = git_ls(url)
    if ok:
        return True, "git ls-remote OK"
    st, d = curl_status(url)
    if st and st < 400:
        return True, f"http {st} (git ls-remote failed: {detail})"
    return False, f"git ls-remote failed ({detail}); http={st}"


def check_pypi(pkg):
    from urllib.parse import quote
    st, d = curl_status(f"https://pypi.org/pypi/{quote(pkg)}/json")
    if st and 200 <= st < 400:
        return True, f"pypi {st}"
    return False, f"pypi http {st}"


def check_cargo(crate):
    from urllib.parse import quote
    st, d = curl_status(f"https://crates.io/api/v1/crates/{quote(crate)}")
    if st and 200 <= st < 400:
        return True, f"crates.io {st}"
    return False, f"crates.io http {st}"


def check_http(url):
    st, d = curl_status(url)
    if st and 200 <= st < 400:
        return True, f"http {st}"
    return False, f"http {st} {d}"


# ---------------------------------------------------------------------------
# Source collection
# ---------------------------------------------------------------------------

records = []  # {role, method, name, source}


def add(role, method, name, source):
    records.append({"role": role, "method": method, "name": name, "source": source})


def parse_role_yaml(path):
    dirname = os.path.basename(os.path.dirname(path))
    # read the human role name first
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^name:\s*"(.*)"', line.strip())
            if m:
                _ROLE_NAMES[dirname] = m.group(1)
                break
    role = _ROLE_NAMES.get(dirname, "?")
    method = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            m = re.match(r"^([a-z_]+):\s*$", s)
            if m:
                method = m.group(1)
                continue
            m2 = re.match(r'^-\s+"(.*)"\s*$', s)
            if m2 and method:
                item = m2.group(1)
                parts = item.split(None, 1)
                name = parts[0]
                rest = parts[1] if len(parts) > 1 else ""
                if method == "native":
                    add(role, "native", name, item)
                elif method in ("go", "pipx", "git", "cargo", "wget"):
                    add(role, method, name, rest.strip())
                elif method == "custom":
                    add(role, "custom", name, item)


_ROLE_NAMES = {}


def _role_name_from_file(path):
    return _ROLE_NAMES.get(os.path.basename(os.path.dirname(path)), "?")


LEGACY_ROLE_MAP = {
    "install_osint": "OSINT Analyst",
    "install_bugbounty": "Bug Bounty Hunter",
    "install_pentester": "Pentester",
    "install_redteam": "Red Team Operator",
    "install_blueteam": "Blue Team / SOC Analyst",
    "install_dfir": "DFIR Analyst",
    "install_threatintel": "Threat Intelligence Analyst",
}


def parse_legacy(path):
    with open(path, encoding="utf-8") as f:
        content = f.read()
    fn_re = re.compile(r"function\s+(install_\w+)\s*\(\s*\)\s*\{(.*?)\n\}", re.DOTALL)
    for fname, body in fn_re.findall(content):
        role = LEGACY_ROLE_MAP.get(fname)
        if not role:
            continue
        for m in re.finditer(r'install_go\s+"([^"]+)"\s+"([^"]+)"', body):
            add(role, "go", m.group(1), m.group(2))
        for m in re.finditer(r'install_pipx\s+"([^"]+)"\s+"([^"]+)"', body):
            add(role, "pipx", m.group(1), m.group(2))
        for m in re.finditer(r'install_git\s+"([^"]+)"\s+"([^"]+)"(?:\s+"([^"]*)")?', body):
            add(role, "git", m.group(1), m.group(2))
        for m in re.finditer(r'install_native\s+"([^"]+)"\s+"([^"]+)"\s+"([^"]+)"\s+"([^"]+)"', body):
            add(role, "native", m.group(1), f"{m.group(2)}/{m.group(3)}/{m.group(4)}")
        for m in re.finditer(r'install_cargo\s+"([^"]+)"\s+"([^"]*)"', body):
            add(role, "cargo", m.group(1), m.group(2))
        for m in re.finditer(r'install_wget\s+"([^"]+)"\s+"([^"]+)"', body):
            add(role, "wget", m.group(1), m.group(2))
        # inline wget/curl binary downloads (capture URLs from each command line)
        for line in body.splitlines():
            if "wget" in line or "curl" in line:
                for um in re.finditer(r"https?://\S+", line):
                    url = um.group(0).rstrip('"\'\\')
                    name = url.rsplit("/", 1)[-1].split("?")[0] or "download"
                    if name:
                        add(role, "wget", name, url)


# ---------------------------------------------------------------------------
# Map a record to the concrete checks it needs
# ---------------------------------------------------------------------------

def compute_tests(rec):
    method, src = rec["method"], rec["source"]
    if method == "native":
        return [("structural", rec["source"])]
    if method == "go":
        repo = go_repo(src)
        if repo:
            return [("git", repo)]
        return [("http", "https://" + src.split()[0])]
    if method == "git":
        url = src.split()[0] if src.split() else src
        if url.startswith("http"):
            return [("git", url)]
        return [("http", src)]
    if method == "pipx":
        if src.startswith("git+"):
            return [("git", src[4:])]
        return [("pypi", src)]
    if method == "cargo" or (method == "cargo"):
        if "http" in src or "--git" in src:
            m = re.search(r"https?://\S+", src)
            if m:
                return [("git", m.group(0))]
            return [("http", src)]
        crate = src.split()[0] if src.split() else src
        return [("cargo", crate)]
    if method in ("wget", "http"):
        return [("http", src)]
    if method == "custom":
        urls = re.findall(r"https?://\S+", src)
        if urls:
            return [("http", u.rstrip('"\'')) for u in urls]
        return [("manual", src)]
    return [("manual", src)]


def run_test(kind, target):
    if kind == "git":
        return check_git(target)
    if kind == "pypi":
        return check_pypi(target)
    if kind == "cargo":
        return check_cargo(target)
    if kind == "http":
        return check_http(target)
    if kind == "structural":
        return True, "structural (distro-dependent)"
    if kind == "manual":
        return True, "manual review"
    return False, "unknown kind"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not os.path.isdir(ROLES_DIR):
        print("ERROR: roles/ directory not found; run from repo root context", file=sys.stderr)
    for fn in sorted(os.listdir(ROLES_DIR)):
        y = os.path.join(ROLES_DIR, fn, "plugin.yaml")
        if os.path.isfile(y):
            parse_role_yaml(y)
    if os.path.isfile(LEGACY):
        parse_legacy(LEGACY)

    # dedupe records (yaml + legacy often declare the same tool)
    _seen = set()
    _deduped = []
    for rec in records:
        key = (rec["role"], rec["method"], rec["name"], rec["source"])
        if key in _seen:
            continue
        _seen.add(key)
        _deduped.append(rec)
    records[:] = _deduped

    # dedupe identical (method,source) to avoid redundant network calls
    seen = set()
    tasks = []  # (dedup_key, kind, target, rec_ref)
    for rec in records:
        for kind, target in compute_tests(rec):
            key = (kind, target)
            if key in seen:
                continue
            seen.add(key)
            tasks.append((kind, target))

    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
        fut_map = {ex.submit(run_test, k, t): (k, t) for k, t in tasks}
        for fut in concurrent.futures.as_completed(fut_map):
            k, t = fut_map[fut]
            try:
                ok, detail = fut.result()
            except Exception as e:  # noqa
                ok, detail = False, str(e)
            results[(k, t)] = (ok, detail)

    # Evaluate each record
    passed = failed = info = 0
    failed_rows = []
    method_counts = {}
    for rec in records:
        tests = compute_tests(rec)
        rec_ok = True
        rec_details = []
        for kind, target in tests:
            ok, detail = results.get((kind, target), (False, "no result"))
            rec_details.append(f"{kind}:{detail}")
            if kind in ("structural", "manual"):
                info += 0  # counted separately below
            if kind not in ("structural", "manual") and not ok:
                rec_ok = False
        method_counts[rec["method"]] = method_counts.get(rec["method"], 0) + 1
        if rec_ok:
            if all(k in ("structural", "manual") for k, _ in tests):
                info += 1
            else:
                passed += 1
        else:
            failed += 1
            failed_rows.append((rec["role"], rec["method"], rec["name"], rec["source"], "; ".join(rec_details)))

    # Report
    print("=" * 78)
    print("RabbitHole install-source validation")
    print("=" * 78)
    print(f"Total tool entries parsed : {len(records)}")
    print(f"Network-checked (pass)   : {passed}")
    print(f"Structural/manual (info) : {info}")
    print(f"FAILED (unreachable)     : {failed}")
    print("-" * 78)
    print("Methods covered:")
    for m, c in sorted(method_counts.items()):
        print(f"  {m:10s}: {c}")
    print("-" * 78)

    if failed_rows:
        print("FAILURES:")
        for role, method, name, src, det in failed_rows:
            print(f"  [{role}] {name} ({method}) src={src}")
            print(f"      -> {det}")
        print("-" * 78)

    # JSON report
    report = {
        "total": len(records),
        "passed": passed,
        "info": info,
        "failed": failed,
        "method_counts": method_counts,
        "failures": [
            {"role": r, "method": m, "name": n, "source": s, "detail": d}
            for r, m, n, s, d in failed_rows
        ],
    }
    out_path = os.path.join(ROOT, "tests", "validation_report.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"JSON report written to {out_path}")

    print("=" * 78)
    if failed:
        print("RESULT: FAIL - some tool sources are unreachable / invalid.")
        sys.exit(1)
    else:
        print("RESULT: PASS - all checked tool sources are reachable.")


if __name__ == "__main__":
    main()
