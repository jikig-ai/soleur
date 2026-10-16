#!/usr/bin/env python3
"""ci-pr-affected-replay.py: escape-rate replay and go/no-go arithmetic for S4 PR C (#9729, ADR-276).

READ-ONLY. It never writes to the repository, never sets a variable and never dispatches a workflow.
It answers one question for activation prerequisite 2: if the PROPOSED per-suite rule had been
applied to the last N first-parent commits of main (and to every queue ejection in the same window),
how many times would a pull_request run have skipped a suite that the full battery then failed?

THE PROPOSED RULE (stored literally in every receipt, with its sha256, so PR D's selector can be
pinned to it): a suite is skipped iff its AFFECTED_SELECTED row is 0, the row is not always_on, the
AFFECTED_SUMMARY line says `fallback=none`, and the diff is evaluable (a changed path with a comma, a
non-printable byte or a list over 100000 bytes is NOT evaluable and skips nothing). Today's rule skips
nothing, so replaying it would be vacuous (CTO R2).

TWO POPULATIONS (a recorded limit, read it before trusting a rate):
  commits    the last N first-parent commits of main. Every one of them landed, so a commit that
             broke a skippable suite was already refused by the queue's full battery and is NOT here:
             this population is near-vacuous for escapes BY CONSTRUCTION (survivorship). It is the
             reading CTO ruling R2 names, so it is computed and reported.
  ejections  every failed merge_group run of ci.yml since the oldest commit's date. These are the
             candidates the full battery refused: the population that can actually hold an escape.
Both run against TODAY's index and selector (the replay of an older diff uses the current edges).

CLASSES (per unit; a unit is a commit or an ejected queue run):
  clean              a full-battery run on the identical tree concluded success
  rule-irrelevant    the failing jobs or suites are ones the rule would have run anyway
  flake-cleared      a would-skip suite failed but the identical tree went green (same-SHA success, or
                     a later queue run of the same PR with the identical changed-file set), or the
                     suite failed in >= 3 units with >= 2 distinct changed-file sets (multi-unit flake)
  escape             a would-skip suite failed on >= 2 attempts of the identical tree (deterministic)
  unverified         a would-skip suite failed and nothing proves it a flake or deterministic
  not-evaluable      an API read failed or was truncated, no run exists, a failed shard has no [FAIL]
                     line, or the diff could not be listed. A failed READ is never "no failure".

Every remote read goes through `gh api` (a PATH seam for tests); the selector is PR_AFFECTED_REPLAY_TEST_ALL
(default scripts/test-all.sh); durations come from scripts/suite-durations{,-heavy}.tsv.

SUBCOMMANDS
  collect      --out DIR [--commits N] [--chunk I/K] [--repo R] [--base REF]
  ejections    --out DIR [--since ISO] [--commits N] [--repo R] [--base REF]
  aggregate    DIR [--baseline-min M] [--selector-min S] [--out FILE]
  verdict      --a S --b S --c S --d S
  cp-upper     K N [CONF]
  audit        [--root DIR] [--list FILE]
The receipt paths are arguments; no repository path literal lives in this file.
"""
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time

RULE_TEXT = (
    "skip a suite iff AFFECTED_SELECTED sel=0 and reason is not always_on and "
    "AFFECTED_SUMMARY fallback=none and the diff is evaluable "
    "(no comma or non-printable path byte, list at most 100000 bytes)"
)
RULE_SHA256 = hashlib.sha256(RULE_TEXT.encode()).hexdigest()
LIST_LIMIT = 100000
SUITE_JOB = re.compile(r"^test-(scripts|webplat|bun)( \(|$)|^test-scripts-heavy( \(|$)")
FAIL_LINE = re.compile(r"^\[FAIL\] (\S+) \((\d+)ms\) log=")
FULL_EVENTS = ("merge_group", "push")
ANSI = re.compile(r"\x1b\[[0-9;]*[mGKHF]")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ")


class ReadError(Exception):
    """A remote or local read failed. Callers class the unit not-evaluable; it is never 'nothing found'."""


def run(cmd, cwd=None, env=None, check=True):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
    if check and p.returncode != 0:
        raise ReadError("%s rc=%d %s" % (cmd[0], p.returncode, p.stderr.strip()[:160]))
    return p


def gh_text(path, escapes=False):
    cmd = ["gh", "api"] + (["--allow-escape-sequences"] if escapes else []) + [path]
    last = None
    for attempt in range(3):
        p = run(cmd, check=False)
        if p.returncode == 0:
            return p.stdout
        last = p.stderr.strip()[:160]
        time.sleep(1 + attempt)
    raise ReadError("gh api %s failed: %s" % (path.split("?")[0], last))


def gh_pages(path):
    """--paginate output is a run of JSON documents, not one array; decode them in turn."""
    cmd = ["gh", "api", "--paginate", path]
    last = None
    for attempt in range(3):
        p = run(cmd, check=False)
        if p.returncode == 0:
            docs, pos, s = [], 0, p.stdout
            dec = json.JSONDecoder()
            try:
                while pos < len(s):
                    while pos < len(s) and s[pos].isspace():
                        pos += 1
                    if pos >= len(s):
                        break
                    d, pos = dec.raw_decode(s, pos)
                    docs.append(d)
            except ValueError as e:
                raise ReadError("unparseable page for %s: %s" % (path.split("?")[0], e))
            return docs
        last = p.stderr.strip()[:160]
        time.sleep(1 + attempt)
    raise ReadError("gh api --paginate %s failed: %s" % (path.split("?")[0], last))


def repo_root():
    return run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()


def durations(root):
    d = {}
    for name in ("suite-durations.tsv", "suite-durations-heavy.tsv"):
        p = os.path.join(root, "scripts", name)
        if not os.path.exists(p):
            continue
        for line in open(p):
            if line.startswith("#") or not line.strip():
                continue
            f = line.rstrip("\n").split("\t")
            if len(f) >= 2 and f[1].isdigit():
                d[f[0]] = int(f[1])
    return d


def evaluable(files):
    if not files:
        return False, "empty-diff"
    for f in files:
        if "," in f:
            return False, "comma-in-path"
        if any(ord(c) < 0x20 or ord(c) > 0x7e for c in f):
            return False, "non-printable-path"
    if len(",".join(files).encode()) > LIST_LIMIT:
        return False, "list-over-limit"
    return True, ""


def select(root, files):
    """-> (fallback, skipped_suites, selected_n, total_n). Raises ReadError on a selector failure."""
    test_all = os.environ.get("PR_AFFECTED_REPLAY_TEST_ALL") or os.path.join(root, "scripts", "test-all.sh")
    env = {k: v for k, v in os.environ.items() if k not in ("CI", "SOLEUR_TEST_FORCE_ALL", "GITHUB_OUTPUT")}
    p = run(["bash", test_all, "--print-selection", "--paths=" + ",".join(files)], cwd=root, env=env, check=False)
    if p.returncode != 0:
        raise ReadError("selector rc=%d" % p.returncode)
    skipped, fb, sel, tot = [], None, 0, 0
    for line in p.stdout.splitlines():
        f = line.split("\t")
        if f[0] == "AFFECTED_SELECTED" and len(f) >= 4:
            tot += 1
            if f[2] == "1":
                sel += 1
            elif f[2] == "0" and f[3] != "always_on":
                skipped.append(f[1])
        elif line.startswith("AFFECTED_SUMMARY"):
            m = re.search(r"fallback=(\S+)", line)
            fb = m.group(1) if m else None
    if fb is None or tot == 0:
        raise ReadError("selector printed no summary or no rows")
    return fb, sorted(skipped), sel, tot


def commit_files(root, sha):
    p = run(["git", "diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", sha], cwd=root)
    return sorted(set(x for x in p.stdout.splitlines() if x))


def api_commit_files(repo, sha):
    docs = gh_pages("repos/%s/commits/%s?per_page=100" % (repo, sha))
    files = []
    for d in docs:
        files += [x["filename"] for x in d.get("files", [])]
    return sorted(set(files))


def ci_runs(repo, sha):
    d = json.loads(gh_text("repos/%s/actions/workflows/ci.yml/runs?head_sha=%s&per_page=100" % (repo, sha)))
    runs = d.get("workflow_runs", [])
    if d.get("total_count") != len(runs):
        raise ReadError("truncated run list for %s" % sha[:10])
    return [r for r in runs if r.get("event") in FULL_EVENTS]


def failing_jobs(repo, run_id):
    docs = gh_pages("repos/%s/actions/runs/%s/jobs?per_page=100&filter=latest" % (repo, run_id))
    jobs = []
    for d in docs:
        jobs += d.get("jobs", [])
    if not jobs:
        raise ReadError("empty jobs list for run %s" % run_id)
    return [(j["id"], j["name"]) for j in jobs if j.get("conclusion") == "failure" and j["name"] != "test"]


def fail_suites(repo, job_id, cache_dir):
    path = os.path.join(cache_dir, "job-%s.log" % job_id)
    if os.path.exists(path):
        text = open(path, errors="replace").read()
    else:
        text = gh_text("repos/%s/actions/jobs/%s/logs" % (repo, job_id), escapes=True)
        os.makedirs(cache_dir, exist_ok=True)
        open(path, "w").write(text)
    suites = []
    for line in ANSI.sub("", text).splitlines():
        m = FAIL_LINE.match(STAMP.sub("", line))
        if m:
            suites.append(m.group(1))
    return sorted(set(suites))


def classify(unit, repo, cache_dir, same_tree_green):
    """Fill unit['cls'] and unit['reason'] from the unit's run record and its would-skip set."""
    r = unit.get("run")
    if r is None:
        unit["cls"], unit["reason"] = "not-evaluable", unit.get("reason") or "no-run"
        return
    if r["conclusion"] == "success":
        unit["cls"], unit["reason"] = "clean", ""
        return
    skipped = set(unit.get("skipped_suites") or [])
    try:
        fj = failing_jobs(repo, r["id"])
    except ReadError as e:
        unit["cls"], unit["reason"] = "not-evaluable", "jobs-read: %s" % e
        return
    unit["failing"] = []
    would_skip_hit, ne = [], False
    for jid, name in fj:
        if SUITE_JOB.match(name):
            try:
                suites = fail_suites(repo, jid, cache_dir)
            except ReadError as e:
                unit["failing"].append({"job": name, "suites": [], "note": "log-read"})
                ne = True
                continue
            if not suites:
                unit["failing"].append({"job": name, "suites": [], "note": "no-fail-line"})
                ne = True
                continue
            unit["failing"].append({"job": name, "suites": suites})
            would_skip_hit += [s for s in suites if s in skipped]
        else:
            unit["failing"].append({"job": name, "suites": [], "note": "always-run-job"})
    if would_skip_hit:
        unit["would_skip_failures"] = sorted(set(would_skip_hit))
        if same_tree_green(unit):
            unit["cls"], unit["reason"] = "flake-cleared", "identical-tree-green"
        elif unit.get("attempts_failed", 1) >= 2:
            unit["cls"], unit["reason"] = "escape", "deterministic"
        else:
            unit["cls"], unit["reason"] = "unverified", "would-skip-suite-failed"
    elif ne:
        unit["cls"], unit["reason"] = "not-evaluable", "failed-job-without-fail-line"
    elif not unit["failing"]:
        unit["cls"], unit["reason"] = "not-evaluable", "failure-without-failed-job"
    else:
        unit["cls"], unit["reason"] = "rule-irrelevant", ""


def base_unit(kind, idx, sha):
    return {"kind": kind, "idx": idx, "sha": sha, "files_n": 0, "files_hash": "", "fallback": "", "skipped_suites": [],
            "skipped_min": 0.0, "run": None, "cls": "not-evaluable", "reason": "", "failing": []}


def fill_selection(u, root, files, dur):
    ok, why = evaluable(files)
    u["files_n"] = len(files)
    u["files_hash"] = hashlib.sha256("\n".join(files).encode()).hexdigest()[:16]
    if not ok:
        u["reason"] = why
        u["fallback"] = "not-evaluable"
        return False
    fb, skipped, sel, tot = select(root, files)
    u["fallback"] = fb
    if fb == "none":
        u["skipped_suites"] = skipped
        u["skipped_min"] = round(sum(dur.get(s, 1180) for s in skipped) / 60000.0, 3)
    return True


def read_done(path):
    done = {}
    if os.path.exists(path):
        for line in open(path):
            try:
                u = json.loads(line)
                done[(u["kind"], u["sha"])] = u
            except ValueError:
                pass
    return done


def cmd_collect(a):
    root, dur = repo_root(), durations(repo_root())
    shas = run(["git", "rev-list", "--first-parent", "-n", str(a.commits), a.base], cwd=root).stdout.split()
    if len(shas) < a.commits:
        print("replay: only %d first-parent commits reachable from %s" % (len(shas), a.base), file=sys.stderr)
    i_, k_ = (int(x) for x in a.chunk.split("/"))
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "units-commits-%d-of-%d.jsonl" % (i_, k_))
    done = read_done(path)
    cache = os.path.join(a.out, "joblogs")
    out = open(path, "a")
    n = 0
    for idx, sha in enumerate(shas):
        if idx % k_ != i_ - 1 or ("commit", sha) in done:
            continue
        u = base_unit("commit", idx, sha)
        try:
            fill_selection(u, root, commit_files(root, sha), dur)
        except ReadError as e:
            u["reason"] = "selection: %s" % e
        try:
            runs = ci_runs(a.repo, sha)
        except ReadError as e:
            runs, u["reason"] = None, "runs-read: %s" % e
        if runs is not None:
            if runs:
                ok = [r for r in runs if r["conclusion"] == "success"]
                pick = ok[0] if ok else sorted(runs, key=lambda r: r["created_at"])[-1]
                u["run"] = {"id": pick["id"], "event": pick["event"], "conclusion": pick["conclusion"],
                            "attempt": pick["run_attempt"]}
                u["runs_n"] = len(runs)
                u["attempts_failed"] = pick["run_attempt"] if pick["conclusion"] != "success" else 0
            classify(u, a.repo, cache, lambda x, rs=runs: any(r["conclusion"] == "success" for r in rs))
        if u["cls"] == "not-evaluable" and not u["reason"]:
            u["reason"] = "no-run"
        out.write(json.dumps(u, sort_keys=True) + "\n")
        out.flush()
        n += 1
    print("replay collect: chunk %s wrote %d units to %s" % (a.chunk, n, path))
    return 0


def pr_of(branch):
    m = re.search(r"/pr-(\d+)-", branch or "")
    return m.group(1) if m else ""


def cmd_ejections(a):
    root, dur = repo_root(), durations(repo_root())
    since = a.since
    if not since:
        sha = run(["git", "rev-list", "--first-parent", "-n", str(a.commits), a.base], cwd=root).stdout.split()[-1]
        since = run(["git", "log", "-1", "--format=%cI", sha], cwd=root).stdout.strip()
    docs = gh_pages("repos/%s/actions/workflows/ci.yml/runs?event=merge_group&created=%s..%s&per_page=100"
                    % (a.repo, since, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())))
    runs = [r for d in docs for r in d.get("workflow_runs", [])]
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "units-ejections.jsonl")
    done = read_done(path)
    cache = os.path.join(a.out, "joblogs")
    by_pr = {}
    for r in runs:
        by_pr.setdefault(pr_of(r.get("head_branch")), []).append(r)
    files_of = {}

    def files_for(r):
        if r["head_sha"] not in files_of:
            files_of[r["head_sha"]] = api_commit_files(a.repo, r["head_sha"])
        return files_of[r["head_sha"]]

    out = open(path, "a")
    n = 0
    fail_runs = sorted([r for r in runs if r["conclusion"] == "failure"], key=lambda r: r["created_at"])
    for idx, r in enumerate(fail_runs):
        if ("ejection", r["head_sha"]) in done:
            continue
        u = base_unit("ejection", idx, r["head_sha"])
        u["run"] = {"id": r["id"], "event": "merge_group", "conclusion": "failure", "attempt": r["run_attempt"]}
        u["attempts_failed"] = r["run_attempt"]
        u["pr"] = pr_of(r.get("head_branch"))
        try:
            files = files_for(r)
            fill_selection(u, root, files, dur)
        except ReadError as e:
            u["reason"] = "files: %s" % e
            u["cls"] = "not-evaluable"
            out.write(json.dumps(u, sort_keys=True) + "\n")
            continue

        def cleared(unit, r=r):
            # a LATER queue run of the same PR with the identical changed-file set that succeeded
            for o in by_pr.get(pr_of(r.get("head_branch")), []):
                if o["created_at"] > r["created_at"] and o["conclusion"] == "success":
                    try:
                        if hashlib.sha256("\n".join(files_for(o)).encode()).hexdigest()[:16] == unit["files_hash"]:
                            return True
                    except ReadError:
                        return False
            return False
        classify(u, a.repo, cache, cleared)
        out.write(json.dumps(u, sort_keys=True) + "\n")
        out.flush()
        n += 1
    print("replay ejections: wrote %d units to %s (window since %s, %d merge_group runs, %d failed)"
          % (n, path, since, len(runs), len(fail_runs)))
    return 0


def cp_upper(k, n, conf=0.95):
    """One-sided Clopper-Pearson upper bound: the p with P(X <= k | n, p) = 1 - conf (bisection, stdlib)."""
    if n <= 0:
        return 1.0
    if k >= n:
        return 1.0
    target = 1.0 - conf
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2
        cdf = sum(math.comb(n, i) * mid ** i * (1 - mid) ** (n - i) for i in range(k + 1))
        if cdf > target:
            lo = mid
        else:
            hi = mid
    return hi


def load_units(d):
    units = []
    for name in sorted(os.listdir(d)):
        if name.startswith("units-") and name.endswith(".jsonl"):
            for line in open(os.path.join(d, name)):
                if line.strip():
                    units.append(json.loads(line))
    return units


def mark_multi_unit_flakes(units):
    """A would-skip suite that failed in >= 3 units with >= 2 distinct changed-file sets is a flake class."""
    seen = {}
    for u in units:
        for s in u.get("would_skip_failures", []):
            seen.setdefault(s, []).append(u)
    flaky = {s for s, us in seen.items() if len(us) >= 3 and len({x["files_hash"] for x in us}) >= 2}
    for u in units:
        if u["cls"] == "unverified" and set(u.get("would_skip_failures", [])) <= flaky:
            u["cls"], u["reason"] = "flake-cleared", "multi-unit-flake"
    return sorted(flaky)


def summarize(units):
    c = {}
    for u in units:
        c[u["cls"]] = c.get(u["cls"], 0) + 1
    n = len(units)
    attributable = c.get("escape", 0)
    unverified = c.get("unverified", 0)
    ne = c.get("not-evaluable", 0)
    return {"n": n, "classes": c, "attributable": attributable, "unverified_as_escape": attributable + unverified,
            "worst_case": attributable + unverified + ne,
            "point": (attributable + unverified) / n if n else 0.0,
            "bound_worst_case": cp_upper(attributable + unverified + ne, n) if n else 1.0}


def cmd_aggregate(a):
    units = load_units(a.dir)
    if not units:
        print("replay aggregate: no units under %s" % a.dir, file=sys.stderr)
        return 2
    flaky = mark_multi_unit_flakes(units)
    commits = [u for u in units if u["kind"] == "commit"]
    ejects = [u for u in units if u["kind"] == "ejection"]
    lines = ["SOLEUR_PR_AFFECTED_REPLAY rule_sha256=%s" % RULE_SHA256, "rule=%s" % RULE_TEXT]
    results = {}
    for label, pop in (("commits", commits), ("commits+ejections", commits + ejects)):
        s = summarize(pop)
        results[label] = s
        lines.append("population=%s n=%d classes=%s" % (label, s["n"], json.dumps(s["classes"], sort_keys=True)))
        lines.append("  attributable=%d/%d unverified_as_escape=%d/%d (point %.2f%%) worst_case=%d/%d "
                     "cp95_upper_on_worst_case=%.2f%%" % (s["attributable"], s["n"], s["unverified_as_escape"], s["n"],
                                                         100 * s["point"], s["worst_case"], s["n"], 100 * s["bound_worst_case"]))
    lines.append("multi_unit_flake_suites=%s" % (",".join(flaky) or "none"))
    ev = [u for u in commits if u["fallback"] not in ("not-evaluable", "")]
    if commits:
        vals = [u["skipped_min"] if u["fallback"] == "none" else 0.0 for u in commits]
        mean = sum(vals) / len(vals)
        sd = (sum((v - mean) ** 2 for v in vals) / (len(vals) - 1)) ** 0.5 if len(vals) > 1 else 0.0
        se = sd / math.sqrt(len(vals))
        net = mean - a.selector_min
        lines.append("saving commits=%d evaluable=%d mean_skipped_suite_min=%.2f se=%.2f selector_min=%.2f net_mean=%.2f "
                     "net_mean_plus_2se=%.2f baseline_min=%.2f bar_min=%.2f"
                     % (len(commits), len(ev), mean, se, a.selector_min, net, net + 2 * se, a.baseline_min, 0.2 * a.baseline_min))
        lines.append("fallbacks=%s" % json.dumps({k: sum(1 for u in commits if u["fallback"] == k)
                                                  for k in sorted({u["fallback"] for u in commits})}))
    text = "\n".join(lines) + "\n"
    sys.stdout.write(text)
    if a.out:
        open(a.out, "w").write(text)
        with open(a.out + ".tsv", "w") as t:
            t.write("kind\tidx\tsha\tfiles_n\tfallback\tskipped_min\tcls\treason\trun\n")
            for u in units:
                t.write("\t".join(str(x) for x in (u["kind"], u["idx"], u["sha"], u["files_n"], u["fallback"], u["skipped_min"],
                                                   u["cls"], u["reason"], (u.get("run") or {}).get("id", ""))) + "\n")
    return 0


def band(value, threshold, higher_is_better):
    lo, hi = threshold * 0.9, threshold * 1.1
    if higher_is_better:
        return "pass" if value >= hi else ("fail" if value < lo else "within-10%")
    return "pass" if value <= lo else ("fail" if value > hi else "within-10%")


STATUSES = ("pass", "fail", "within-10%", "unmeasured")


def verdict(a_, b_, c_, d_):
    """GO iff every criterion passes; NO-GO iff any fails; otherwise UNDECIDED (reason says why)."""
    s = [a_, b_, c_, d_]
    for x in s:
        if x not in STATUSES:
            raise ValueError("unknown criterion status %r" % x)
    if "fail" in s:
        return "NO-GO", "criterion-failed"
    if "unmeasured" in s:
        return "UNDECIDED", "incomplete"
    if "within-10%" in s:
        return "UNDECIDED", "within-10%"
    return "GO", "all-pass"


def cmd_verdict(a):
    v, why = verdict(a.a, a.b, a.c, a.d)
    print("computed=%s reason=%s" % (v, why))
    return 0


def cmd_cp(a):
    print("%.6f" % cp_upper(a.k, a.n, a.conf))
    return 0


def tracked_files(root):
    return set(run(["git", "ls-files"], cwd=root).stdout.splitlines())


def suite_refs(root, suite, tracked):
    """Tracked repo paths this suite file (and the libs it sources, one level) names literally."""
    texts = []
    cand = []
    for guess in (suite, suite + ".test.sh", suite + ".sh", suite + ".test.ts", suite + ".test.py"):
        gp = os.path.join(root, guess)
        if os.path.isfile(gp):
            cand.append(gp)
            break
    for p in cand:
        t = open(p, errors="replace").read()
        texts.append(t)
        for m in re.finditer(r"""(?:source|\.)\s+["']?(?:\$\{?[A-Za-z_]+\}?/)?([A-Za-z0-9_./-]+\.sh)""", t):
            q = os.path.join(root, m.group(1))
            if os.path.isfile(q):
                texts.append(open(q, errors="replace").read())
    blob = "\n".join(texts)
    return sorted(f for f in tracked if f not in (suite,) and len(f) > 6 and f in blob)


def cmd_audit(a):
    """Index-completeness audit over the selector's own rows: every tracked path a registered suite names
    must match one of that suite's declared/derived patterns. Prints one `gap` line per suite with gaps."""
    root = a.root or repo_root()
    test_all = os.environ.get("PR_AFFECTED_REPLAY_TEST_ALL") or os.path.join(root, "scripts", "test-all.sh")
    env = {k: v for k, v in os.environ.items() if k not in ("CI", "SOLEUR_TEST_FORCE_ALL", "GITHUB_OUTPUT")}
    if a.list:
        rows = open(a.list).read().splitlines()
    else:
        p = run(["bash", test_all, "--print-selection", "--paths=README.md"], cwd=root, env=env)
        rows = p.stdout.splitlines()
    tracked = tracked_files(root)
    suites = 0
    gaps = []
    for line in rows:
        f = line.split("\t")
        if f[0] != "AFFECTED_SELECTED" or len(f) < 5:
            continue
        suites += 1
        suite, pats = f[1], f[4].split("|")
        regs = []
        for pt in pats:
            try:
                regs.append(re.compile(pt))
            except re.error:
                pass
        refs = suite_refs(root, suite, tracked)
        miss = [r for r in refs if not any(rg.search(r) for rg in regs)]
        if miss:
            gaps.append((suite, miss))
    if suites == 0:
        print("replay audit: the selector printed no AFFECTED_SELECTED rows", file=sys.stderr)
        return 2
    for suite, miss in gaps:
        print("gap\t%s\t%d\t%s" % (suite, len(miss), ",".join(miss[:6])))
    print("SOLEUR_PR_AFFECTED_AUDIT suites=%d gap_suites=%d gap_refs=%d" % (suites, len(gaps), sum(len(m) for _, m in gaps)))
    return 0 if not gaps else 1


def main(argv):
    ap = argparse.ArgumentParser(prog="ci-pr-affected-replay")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("collect")
    c.add_argument("--out", required=True)
    c.add_argument("--commits", type=int, default=300)
    c.add_argument("--chunk", default="1/1")
    c.add_argument("--repo", default="jikig-ai/soleur")
    c.add_argument("--base", default="origin/main")
    e = sub.add_parser("ejections")
    e.add_argument("--out", required=True)
    e.add_argument("--since", default="")
    e.add_argument("--commits", type=int, default=300)
    e.add_argument("--repo", default="jikig-ai/soleur")
    e.add_argument("--base", default="origin/main")
    g = sub.add_parser("aggregate")
    g.add_argument("dir")
    g.add_argument("--baseline-min", type=float, default=99.8, dest="baseline_min")
    g.add_argument("--selector-min", type=float, default=1.29, dest="selector_min")
    g.add_argument("--out", default="")
    v = sub.add_parser("verdict")
    for k in "abcd":
        v.add_argument("--" + k, required=True)
    p = sub.add_parser("cp-upper")
    p.add_argument("k", type=int)
    p.add_argument("n", type=int)
    p.add_argument("conf", type=float, nargs="?", default=0.95)
    u = sub.add_parser("audit")
    u.add_argument("--root", default="")
    u.add_argument("--list", default="")
    a = ap.parse_args(argv)
    if a.cmd == "collect" and not re.match(r"^[1-9][0-9]*/[1-9][0-9]*$", a.chunk):
        print("replay: --chunk must be I/K with I,K >= 1", file=sys.stderr)
        return 2
    try:
        return {"collect": cmd_collect, "ejections": cmd_ejections, "aggregate": cmd_aggregate, "verdict": cmd_verdict,
                "cp-upper": cmd_cp, "audit": cmd_audit}[a.cmd](a)
    except ReadError as e:
        print("replay: %s" % e, file=sys.stderr)
        return 3
    except ValueError as e:
        print("replay: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
