#!/usr/bin/env python3
"""Item F mutation battery (plan Phase 4): one mutant at a time, graded by a named substring.

Data-driven: the rows live in mutation-rows.json (data, not swept), so this script holds no reader shape as text. Each row edits the guard
(and sometimes another file, or adds one) inside a SCRATCH sandbox allocated by scripts/soleur-sandbox.sh, runs the guard there under
`ulimit -v 6000000`, and grades:

  RED          the guard exited 1 or 3 AND printed every expected substring (the row's named case, check or message)
  WRONG-REASON the guard went red but not for the named reason (re-aim the row; never counted)
  SURVIVED     the guard exited 0
  INSTRUMENT   exit 126/127/134/137/139 or a timeout (the run did not measure anything)
  NO-LAND      the mutation did not change the file (a mutation that does not land reports the baseline)

The unmutated control must exit 0 first, in each mode. Mode `fast` truncates the guard before the producer-side block and appends a small
verdict tail (the rows whose checks sit before that block); mode `full` runs the whole guard. Mutants edit only new guard code and fixtures,
never a trap or a signal helper.

usage: mutation-battery.py [--rows FILE] [--only ID[,ID...]] [--out FILE]

The repository is found with `git rev-parse --show-toplevel` from this file's directory, so the battery runs from the spec directory and from its archived
location alike. The environment is pinned to a UTF-8 locale: the non-UTF-8 fixture only differs from a plain line there (GNU grep calls such a line binary
only in a UTF-8 locale).
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=HERE, text=True).strip()
GUARD_REL = ".claude/hooks/grep-q-pipe-guard.test.sh"
CUT_MARK = "# THE PRODUCER SIDE (S7b, #9217 Arm P; widened by S7c)."
TAIL = (
    "if (( ${#sweep_probe_fail[@]} == 0 )); then echo \"PASS: grep-q-sweep-probe-pass (truncated)\"; "
    "else FAIL=1; echo \"FAIL: the derived sweep's own probe is broken (truncated run):\"; "
    "printf '  %s\\n' \"${sweep_probe_fail[@]}\"; exit 1; fi\nexit \"$FAIL\"\n"
)
INSTRUMENT_RC = {126, 127, 134, 137, 139, 124}


def clean_env():
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["GIT_AUTHOR_NAME"] = env["GIT_COMMITTER_NAME"] = "battery"
    env["GIT_AUTHOR_EMAIL"] = env["GIT_COMMITTER_EMAIL"] = "battery@example.invalid"
    env["LC_ALL"] = "C.UTF-8"
    return env


def inside(sbx, rel):
    """The sandbox path for a row's relative path; refuses anything that resolves outside the sandbox."""
    fp = os.path.realpath(os.path.join(sbx, rel))
    if fp != os.path.realpath(sbx) and not fp.startswith(os.path.realpath(sbx) + os.sep):
        raise SystemExit("row path escapes the sandbox: %r" % rel)
    return fp


def run(cmd, cwd=None, timeout=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env or clean_env(), capture_output=True, text=True, timeout=timeout)


def truncate(text):
    i = text.index(CUT_MARK)
    j = text.rfind("\n# ---", 0, i)
    return text[: j + 1] + TAIL


def apply_edits(text, edits):
    for e in edits:
        n = e.get("count", 1)
        if text.count(e["old"]) != n:
            raise SystemExit("row edit anchor count %d (want %d): %r" % (text.count(e["old"]), n, e["old"][:80]))
        text = text.replace(e["old"], e["new"])
    return text


def run_guard(sbx, text, mode, timeout=420):
    path = os.path.join(sbx, GUARD_REL)
    body = truncate(text) if mode == "fast" else text
    with open(path, "w") as fh:
        fh.write(body)
    t0 = time.time()
    try:
        p = run(["bash", "-c", "ulimit -v 6000000; exec bash %s" % GUARD_REL], cwd=sbx, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t0
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT", time.time() - t0


def restore(sbx, pristine):
    with open(os.path.join(sbx, GUARD_REL), "w") as fh:
        fh.write(pristine)
    run(["git", "checkout", "-q", "--", "."], cwd=sbx)
    run(["git", "clean", "-fdq"], cwd=sbx)
    st = run(["git", "status", "--porcelain"], cwd=sbx).stdout.strip()
    if st:
        raise SystemExit("sandbox not clean after restore: %s" % st[:200])


def main():
    args = sys.argv[1:]
    rows_file = os.path.join(HERE, "mutation-rows.json")
    only = None
    out_path = os.path.join(HERE, "battery-results.txt")
    while args:
        a = args.pop(0)
        if a == "--rows":
            rows_file = args.pop(0)
        elif a == "--only":
            only = set(args.pop(0).split(","))
        elif a == "--out":
            out_path = args.pop(0)
    with open(rows_file) as fh:
        rows = json.load(fh)
    if only:
        rows = [r for r in rows if r["id"] in only]

    new = run(["bash", "scripts/soleur-sandbox.sh", "new", "itemf-battery"], cwd=REPO)
    lines = new.stdout.strip().splitlines()
    sbx = lines[-1] if lines else ""
    if not sbx or not os.path.isdir(sbx):
        raise SystemExit("sandbox allocation failed: %s" % (new.stdout + new.stderr)[:300])
    results = []
    try:
        for step in (["git", "init", "-q"], ["git", "add", "-A"], ["git", "commit", "-q", "-m", "sandbox"]):
            c = run(step, cwd=sbx)
            if c.returncode != 0:
                raise SystemExit("sandbox step %s failed: %s" % (" ".join(step), c.stderr[:300]))
        with open(os.path.join(REPO, GUARD_REL)) as fh:
            pristine = fh.read()
        with open(os.path.join(sbx, GUARD_REL)) as fh:
            if fh.read() != pristine:
                raise SystemExit("the sandbox guard differs from the working tree guard")

        for mode in ("fast", "full"):
            if mode == "full" and not any(r.get("mode") == "full" for r in rows):
                continue
            rc, out, dt = run_guard(sbx, pristine, mode)
            line = "CONTROL %-4s rc=%s %.0fs" % (mode, rc, dt)
            print(line, flush=True)
            results.append(line)
            if rc != 0:
                print(out[-1500:])
                raise SystemExit("the unmutated control is not green in %s mode; every row would be void" % mode)
            restore(sbx, pristine)

        for r in rows:
            mode = r.get("mode", "fast")
            text = apply_edits(pristine, r.get("edits", []))
            changed = text != pristine
            for fe in r.get("file_edits", []):
                fp = inside(sbx, fe["file"])
                with open(fp) as fh:
                    old = fh.read()
                if fe.get("append") is not None:
                    new_body = old + fe["append"]
                else:
                    if old.count(fe["old"]) != fe.get("count", 1):
                        raise SystemExit("file edit anchor count for %s in %s" % (r["id"], fe["file"]))
                    new_body = old.replace(fe["old"], fe["new"])
                changed = changed or (new_body != old)
                with open(fp, "w") as fh:
                    fh.write(new_body)
            for ad in r.get("add_files", []):
                fp = inside(sbx, ad["path"])
                os.makedirs(os.path.dirname(fp), exist_ok=True)
                with open(fp, "w") as fh:
                    fh.write(ad["text"])
                changed = True
            if not changed:
                verdict = "NO-LAND"
                rc, out, dt = -1, "", 0.0
            else:
                rc, out, dt = run_guard(sbx, text, mode)
                want = r.get("expect", [])
                rcs = r.get("rc", [1, 3])
                if rc in INSTRUMENT_RC:
                    verdict = "INSTRUMENT"
                elif rc == 0:
                    verdict = "SURVIVED"
                elif rc in rcs and all(w in out for w in want):
                    verdict = "RED"
                else:
                    verdict = "WRONG-REASON"
            line = "%-14s %-12s %-5s rc=%-3s %4.0fs  %s" % (r["id"], verdict, mode, rc, dt, r.get("desc", ""))
            print(line, flush=True)
            if verdict not in ("RED",):
                missing = [w for w in r.get("expect", []) if w not in out]
                print("    missing: %r  tail: %s" % (missing, out[-400:].replace("\n", " | ")), flush=True)
            results.append(line)
            restore(sbx, pristine)
    finally:
        run(["bash", "scripts/soleur-sandbox.sh", "rm", sbx], cwd=REPO)
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "w") as fh:
            fh.write("\n".join(results) + "\n")
    reds = sum(1 for x in results if " RED " in x)
    print("RED %d of %d rows (results: %s)" % (reds, len(rows), out_path))


if __name__ == "__main__":
    main()
