#!/usr/bin/env python3
"""ci-pr-affected-replay.py: escape-rate replay and go/no-go arithmetic for S4 PR C (#9729, ADR-276).

READ-ONLY. It never writes to a tracked file, never sets a variable and never dispatches a workflow. It writes only
under --out, and the selector it runs keeps its own gitignored derive cache under the checkout it reads.
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
  ejections  every merge_group run of ci.yml between the oldest and the newest commit's date (the same window) that is not a
             success: failure, timed_out, startup_failure, an unfinished run and cancelled (a cancelled shard fails the aggregate). These are the
             candidates the full battery refused: the population that can actually hold an escape.
Both run against TODAY's index and selector (the replay of an older diff uses the current edges).

CLASSES (per unit; a unit is a commit or an ejected queue run):
  clean              a full-battery run on the identical tree concluded success
  rule-irrelevant    the failing jobs or suites are ones the rule would have run anyway
  flake-cleared      a would-skip suite failed but the identical tree went green (same-SHA success, or a later
                     queue run of the same PR whose changed files are the identical (name, blob sha) set), or the
                     suite failed in >= 3 units from >= 3 distinct PRs with >= 2 distinct changed-file sets
                     (multi-unit flake; only an `unverified` unit is ever flipped, never an `escape`)
  escape             a would-skip suite failed on >= 2 attempts of the identical tree: attempt 1's jobs and logs are
                     READ and must name the same suite (run_attempt alone is a counter, not evidence)
  unverified         a would-skip suite failed and nothing proves it a flake or deterministic
  not-evaluable      an API read failed, timed out or was truncated, no run exists, a failed shard has no [FAIL] or
                     [KILLED] line, a job is cancelled/timed out/unfinished with no would-skip hit, or the diff
                     could not be listed. A failed READ is never "no failure".

Every remote read goes through `gh api` (a PATH seam for tests); the selector is PR_AFFECTED_REPLAY_TEST_ALL
(default scripts/test-all.sh); durations come from scripts/suite-durations{,-heavy}.tsv.

SUBCOMMANDS
  collect      --out DIR [--commits N] [--chunk I/K] [--repo R] [--base REF] [--redo-unevaluable] [--reclassify]
  ejections    --out DIR [--since YYYY-MM-DDTHH:MM:SSZ] [--until YYYY-MM-DDTHH:MM:SSZ] [--commits N] [--repo R] [--base REF] [--redo-unevaluable] [--reclassify]
  aggregate    DIR [--baseline-min M] [--selector-min S] [--out FILE] [--expect-commits N] [--commits-only]
  verdict      --a S --b S --c S --d S     (status: pass | fail | within-10% | unmeasured; a and c only for within-10%)
  cp-upper     K N [CONF]                  (a FRACTION, not a percent: 0.009936 is 0.99%)
  audit        [--root DIR] [--list FILE] [--accept FILE] [--all-refs]
The receipt paths are arguments; no repository path literal lives in this file.

AUDIT OUTPUT. `gap<TAB>suite<TAB>N<TAB>paths` (the first six, all with --all-refs, which also prints under it one
`ref<TAB>suite<TAB>path<TAB>file:line<TAB>anchor/ordinal<TAB>text` line per boundary line naming each path: the data an accept row
is written from); `unaudited<TAB>suite<TAB>why` (why: short-row, the first pattern when the suite has no readable input, or
`unreadable:<relpath>[,<relpath>]` when a tracked test file of a directory suite cannot be read; its readable files are still
scanned); `stale<TAB>suite<TAB>path<TAB>anchor/ordinal<TAB>why`; then one SOLEUR_PR_AFFECTED_AUDIT summary line:
`suites= always_on= audited= unaudited= gap_suites= gap_refs= accepted= stale= refs= files_read=`. UNITS: `suites` counts selector ROWS;
every other count is per suite LABEL (rows that share a label are one suite: always_on if any of its rows is, its gaps and accept rows
merged, each gap attributed to the rows whose text names it); `refs` counts distinct (label, path) PAIRS the audited suites name before
any exemption, and `files_read` the distinct real files read, so a change of the audit's REACH shows in these two numbers even when
the gaps do not move. Every path printed has a backslash, a control character and, inside a comma-joined list, the comma written as
\\xHH, and a C1 control, zero-width character, U+2028/2029 or bidi control written as \\uXXXX, so a tracked name cannot add a line or a
column or reorder the text. A suite or library is read only when it is a regular file of at most
8 MiB inside the tree (a symlink is followed only to a regular file inside the tree); anything else is `unreadable:`, including a
`source`d tracked file that is a dangling symlink, a directory or deleted from the work tree. While a suite has an unreadable member
its accept rows are not judged by their text (only `*` rows and untracked paths are stale).

ACCEPT FILE (--accept FILE; tab-separated, `#` lines and blank lines skipped; a missing file exempts nothing and says so on stderr):
  suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>     one row per source line that names the path
  suite<TAB>*<TAB>-<TAB>-<TAB>false-positive: <reason>                   a whole suite that has NO inputs at all (never one with any)
  anchor    the first 12 hex of sha256 over `" ".join(line.split())`, where `line` is the comment-stripped source line AS WRITTEN
            (whitespace collapsed; Unicode whitespace too, as str.split() does; a comment line is blanked, never removed)
  ordinal   1, 2, ...: the Nth line with that anchor, counted over the suite file and then the libraries it sources, in hop order
A gap is accepted only when every boundary line that names it has a row. The 3-column form `suite<TAB>path<TAB>reason` was retired.
STALE rows (exit 1, reason printed): not-a-gap (the pair is not a gap before the exemptions: an edge declares it, or no line names
it), anchor-not-live, path-untracked, suite-unaudited, suite-unregistered, suite-always-on, star-row-readable-suite,
star-row-unreadable-members, star-row-tracked-suite (git tracks the suite's input, so it is not a suite with no inputs even if the
file is missing, dangling or a directory link). Delete the row.

EXIT CODES (collect, ejections, aggregate, audit): 0 done and clean; 1 audit found gaps, unaudited suites or stale accept rows; 2 usage or
a value error (a malformed --since, an unknown status, an incomplete aggregate directory); 3 a remote or local READ
failed (git, the selector, a file the audit must read, the --accept or --list file); 4 an internal error. `verdict` and `cp-upper` exit 0 whatever they print: read `computed=GO|NO-GO|UNDECIDED`
on stdout, the exit code carries no verdict. An uncaught Python error is rc 4, never rc 1.
"""
import argparse
import hashlib
import json
import math
import os
import re
import stat
import subprocess
import sys
import time
from bisect import bisect_left

RULE_TEXT = (
    "skip a suite iff AFFECTED_SELECTED sel=0 and reason is not always_on and "
    "AFFECTED_SUMMARY fallback=none and the diff is evaluable "
    "(no comma or non-printable path byte, list at most 100000 bytes)"
)
RULE_SHA256 = hashlib.sha256(RULE_TEXT.encode()).hexdigest()
LIST_LIMIT = 100000
SUITE_JOB = re.compile(r"^test-(scripts|webplat|bun)( \(|$)|^test-scripts-heavy( \(|$)")
# Every other ci.yml job, which the rule never skips. An allowlist: a failing job whose name is in neither set is a job
# this tool has not classified, so the unit is not-evaluable rather than reassuring (a parity test pins this set to ci.yml).
ALWAYS_RUN_JOBS = frozenset((
    "detect-changes", "push-dedupe", "draft-light", "pr-selection", "credential-path-guard", "lint-bot-statuses",
    "encryption-posture", "marketplace-manifest-guard", "service-role-allowlist-gate", "tc-document-sha-guard",
    "adr-ordinals", "rule-body-lint", "lockfile-sync", "sandbox-canary-capture-gate", "plugin-root-propagation-gate",
    "lint-webplat", "web-platform-build", "shard-totality-mutations", "grok-fidelity", "harness-discovery", "test", "e2e",
    "critical-css-gate",
))
FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\] ([A-Za-z0-9._/+-]+) \((?:\d+ms|exit=)")
FULL_EVENTS = ("merge_group", "push")
COMMIT_FILES_CAP = 3000
ANSI = re.compile(r"\x1b\[[0-9;]*[mGKHF]")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ")


class ReadError(Exception):
    """A remote or local read failed. Callers class the unit not-evaluable; it is never 'nothing found'."""


try:
    GH_TIMEOUT = float(os.environ.get("PR_AFFECTED_REPLAY_GH_TIMEOUT", "180"))
    SELECT_TIMEOUT = float(os.environ.get("PR_AFFECTED_REPLAY_SELECT_TIMEOUT", "900"))
except ValueError as _e:  # import time is before main()'s handlers: a bad seam value is a usage error (rc 2), never rc 1
    print("replay: PR_AFFECTED_REPLAY_GH_TIMEOUT / _SELECT_TIMEOUT must be numbers: %s" % _e, file=sys.stderr)
    sys.exit(2)
# The same nine names as GIT_LOCATION_VARS in plugins/soleur/test/lib/git-fixture-env.sh and the gate's git_ro (a parity row pins all three).
GIT_LOCATION_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                     "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_TEMPLATE_DIR", "GIT_EXEC_PATH")
# The selector reads the repository and prints rows; it needs no credential. An allowlist, not a denylist: a new
# secret-bearing variable (GH_TOKEN, a cloud key) must not reach a script that is itself part of the tree under test.
SELECT_ENV_KEEP = ("PATH", "LANG", "TMPDIR", "TZ", "USER", "SHELL")


def run(cmd, cwd=None, env=None, check=True, timeout=None, binary=False):
    if env is None and cmd and cmd[0] == "git":
        env = {k: v for k, v in os.environ.items() if k not in GIT_LOCATION_VARS}
    try:
        if binary:
            p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
        else:
            p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ReadError("%s timed out after %ss" % (cmd[0], timeout))
    if check and p.returncode != 0:
        raise ReadError("%s rc=%d %s" % (cmd[0], p.returncode, (p.stderr.decode("utf-8", "replace") if binary else p.stderr).strip()[:160]))
    return p


def retry_sleep(attempt, factor=1):
    time.sleep(float(os.environ.get("PR_AFFECTED_REPLAY_RETRY_SLEEP", "1")) * (1 + attempt) * factor)


def rate_limited(stderr):
    m = re.search(r"HTTP (\d{3})", stderr or "")
    return bool(m and m.group(1) == "403" and "rate limit" in (stderr or "").lower())


def transient(stderr):
    """A 4xx other than 429 will answer the same way every time: do not spend three sleeps on it. GitHub answers a
    primary rate limit with 403, which is the one 4xx that does clear."""
    m = re.search(r"HTTP (\d{3})", stderr or "")
    if rate_limited(stderr):
        return True
    return not (m and m.group(1).startswith("4") and m.group(1) != "429")


def gh_text(path, escapes=False):
    cmd = ["gh", "api"] + (["--allow-escape-sequences"] if escapes else []) + [path]
    last = None
    for attempt in range(3):
        p = run(cmd, check=False, timeout=GH_TIMEOUT)
        if p.returncode == 0:
            return p.stdout
        last = p.stderr.strip()[:160]
        if not transient(p.stderr):
            break
        retry_sleep(attempt, 10 if rate_limited(p.stderr) else 1)   # a rate limit clears in tens of seconds at best
    raise ReadError("gh api %s failed: %s" % (path.split("?")[0], last))


def gh_pages(path):
    """--paginate output is a run of JSON documents, not one array; decode them in turn."""
    cmd = ["gh", "api", "--paginate", path]
    last = None
    for attempt in range(3):
        p = run(cmd, check=False, timeout=GH_TIMEOUT)
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
        if not transient(p.stderr):
            break
        retry_sleep(attempt, 10 if rate_limited(p.stderr) else 1)
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


def select_env(home):
    """The allowlisted environment, with HOME pointed at an empty scratch directory: ~/.config/gh holds the credential
    the allowlist exists to keep away from the selector."""
    env = {k: v for k, v in os.environ.items() if k in SELECT_ENV_KEEP or k.startswith("PR_AFFECTED_REPLAY_")
           or k.startswith("LC_")}
    env["HOME"] = home
    return env


def run_selector(root, args):
    import shutil
    import tempfile
    test_all = os.environ.get("PR_AFFECTED_REPLAY_TEST_ALL") or os.path.join(root, "scripts", "test-all.sh")
    home = tempfile.mkdtemp(prefix="replay-home.")
    try:
        return run(["bash", test_all, "--print-selection"] + args, cwd=root, env=select_env(home), check=False,
                   timeout=SELECT_TIMEOUT)
    finally:
        shutil.rmtree(home, ignore_errors=True)


def select(root, files):
    """-> (fallback, skipped_suites, selected_n, total_n). Raises ReadError on a selector failure."""
    p = run_selector(root, ["--paths=" + ",".join(files)])
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
    if fb is None:
        raise ReadError("selector printed no AFFECTED_SUMMARY line")
    if fb != "none":
        # a fallback (runner-changed, undecidable diff) runs the FULL battery and prints no per-suite rows: nothing is skipped
        return fb, [], 0, 0
    if tot == 0:
        raise ReadError("selector reported fallback=none but printed no AFFECTED_SELECTED rows")
    return fb, sorted(skipped), sel, tot


def commit_files(root, sha):
    # -z: without it git quotes a non-ASCII path ("\\303\\251"), which is printable ASCII and would look evaluable
    p = run(["git", "diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", "-z", sha], cwd=root)
    return sorted(set(x for x in p.stdout.split("\0") if x))


def api_commit_files(repo, sha):
    """-> sorted [(filename, blob sha)]. The blob sha is what makes "the identical tree" a content claim: a name
    set alone is equal for a one-line fix and for the commit it fixes."""
    docs = gh_pages("repos/%s/commits/%s?per_page=100" % (repo, sha))
    files = []
    for d in docs:
        for x in d.get("files", []):
            if not x.get("sha"):
                # a name-only comparison is exactly the claim the blob exists to prevent
                raise ReadError("commit %s lists %s without a blob sha" % (sha[:10], x.get("filename")))
            files.append((x["filename"], x["sha"]))
    if len(files) >= COMMIT_FILES_CAP:
        # the commits API stops listing at 3000 files without saying so: a list at the cap is a truncated list
        raise ReadError("commit %s lists %d files, the API's cap: the list may be truncated" % (sha[:10], len(files)))
    return sorted(set(files))


def content_key(pairs):
    return hashlib.sha256("\n".join("%s %s" % (n, b) for n, b in pairs).encode()).hexdigest()[:16]


def ci_runs(repo, sha):
    try:
        d = json.loads(gh_text("repos/%s/actions/workflows/ci.yml/runs?head_sha=%s&per_page=100" % (repo, sha)))
    except ValueError as e:
        raise ReadError("unparseable run list for %s: %s" % (sha[:10], e))
    runs = d.get("workflow_runs", [])
    if d.get("total_count") != len(runs):
        raise ReadError("truncated run list for %s" % sha[:10])
    return [r for r in runs if r.get("event") in FULL_EVENTS]


SETTLED = ("success", "failure", "skipped", "neutral")


def failing_jobs(repo, run_id, attempt=None):
    """-> (failing [(id, name)], unsettled [name]). A job that is cancelled, timed out or has no conclusion has not
    said whether a would-skip suite failed in it, so the caller cannot class the run on the failures it did read."""
    path = ("repos/%s/actions/runs/%s/attempts/%s/jobs?per_page=100" % (repo, run_id, attempt) if attempt
            else "repos/%s/actions/runs/%s/jobs?per_page=100&filter=latest" % (repo, run_id))
    docs = gh_pages(path)
    jobs = []
    for d in docs:
        jobs += d.get("jobs", [])
    if not jobs:
        raise ReadError("empty jobs list for run %s" % run_id)
    if docs and docs[0].get("total_count") is not None and docs[0]["total_count"] != len(jobs):
        raise ReadError("truncated jobs list for run %s (%s of %s)" % (run_id, len(jobs), docs[0]["total_count"]))
    return ([(j["id"], j["name"]) for j in jobs if j.get("conclusion") == "failure" and j["name"] != "test"],
            [j["name"] for j in jobs if j.get("conclusion") not in SETTLED and j["name"] != "test"])


def fail_suites(repo, job_id, cache_dir):
    path = os.path.join(cache_dir, "job-%d.log" % int(job_id))
    if os.path.exists(path):
        with open(path, errors="replace") as fh:
            text = fh.read()
    else:
        text = gh_text("repos/%s/actions/jobs/%s/logs" % (repo, job_id), escapes=True)
        os.makedirs(cache_dir, exist_ok=True)
        part = "%s.part.%d" % (path, os.getpid())
        with open(part, "w") as fh:
            fh.write(text)
        os.replace(part, path)
    suites = []
    for line in ANSI.sub("", text).splitlines():
        m = FAIL_LINE.match(STAMP.sub("", line))
        if m:
            suites.append(m.group(1))
    return sorted(set(suites))


def suites_failed_in(repo, fj, cache_dir):
    """-> (suites, failing rows, unread) over the failing jobs of one attempt. A suite-shard job whose log cannot be read
    or names no [FAIL]/[KILLED] line, and a failing job in neither the suite-shard family nor ALWAYS_RUN_JOBS, set
    `unread`: they are notes, never an empty answer."""
    suites, failing, ne = set(), [], False
    for jid, name in fj:
        if not SUITE_JOB.match(name):
            if name.split(" (")[0] in ALWAYS_RUN_JOBS:
                failing.append({"job": name, "suites": [], "note": "always-run-job"})
            else:
                failing.append({"job": name, "suites": [], "note": "unclassified-job"})
                ne = True
            continue
        try:
            got = fail_suites(repo, jid, cache_dir)
        except ReadError:
            failing.append({"job": name, "suites": [], "note": "log-read"})
            ne = True
            continue
        if not got:
            failing.append({"job": name, "suites": [], "note": "no-fail-line"})
            ne = True
            continue
        failing.append({"job": name, "suites": got})
        suites |= set(got)
    return suites, failing, ne


def escape_confirmed(unit, repo, cache_dir, hit):
    """Deterministic = the SAME would-skip suite failed in attempt 1 as well. run_attempt alone is a counter, not
    evidence about which suite failed in the earlier attempt, so attempt 1's jobs and logs are read."""
    try:
        fj1, _ = failing_jobs(repo, unit["run"]["id"], attempt=1)
        s1, _, _ = suites_failed_in(repo, fj1, cache_dir)
    except ReadError:
        return False
    return bool(s1 & set(hit))


def classify(unit, repo, cache_dir, same_tree_green):
    """Fill unit['cls'] and unit['reason'] from the unit's run record and its would-skip set."""
    r = unit.get("run")
    if r is None:
        unit["cls"], unit["reason"] = "not-evaluable", unit.get("reason") or "no-run"
        return
    if r["conclusion"] == "success":
        unit["cls"], unit["reason"] = "clean", ""
        return
    if unit.get("sel_error"):
        unit["cls"], unit["reason"] = "not-evaluable", "selection: %s" % unit["sel_error"]
        return
    if unit.get("fallback") == "not-evaluable" and unit.get("reason") == "empty-diff":
        # an empty changed-file list for a failed run is a failed or partial diff read, not a diff the rule skips nothing for
        unit["cls"], unit["reason"] = "not-evaluable", "empty-diff"
        return
    skipped = set(unit.get("skipped_suites") or [])
    try:
        fj, unsettled = failing_jobs(repo, r["id"])
    except ReadError as e:
        unit["cls"], unit["reason"] = "not-evaluable", "jobs-read: %s" % e
        return
    names, unit["failing"], ne = suites_failed_in(repo, fj, cache_dir)
    would_skip_hit = sorted(s for s in names if s in skipped)
    if would_skip_hit:
        unit["would_skip_failures"] = would_skip_hit
        if same_tree_green(unit):
            unit["cls"], unit["reason"] = "flake-cleared", "identical-tree-green"
        elif unit.get("attempts_failed", 1) >= 2 and escape_confirmed(unit, repo, cache_dir, would_skip_hit):
            unit["cls"], unit["reason"] = "escape", "deterministic"
        else:
            unit["cls"], unit["reason"] = "unverified", "would-skip-suite-failed"
    elif ne:
        odd = [f["job"] for f in unit["failing"] if f.get("note") == "unclassified-job"]
        unit["cls"], unit["reason"] = "not-evaluable", ("unclassified-job: %s" % ",".join(odd)[:120] if odd
                                                       else "failed-job-without-fail-line")
    elif unsettled:
        unit["cls"], unit["reason"] = "not-evaluable", "unsettled-jobs: %s" % ",".join(sorted(unsettled))[:120]
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
    fb, skipped, _sel, _tot = select(root, files)
    u["fallback"] = fb
    if fb == "none":
        u["skipped_suites"] = skipped
        u["skipped_min"] = round(sum(dur.get(s, 1180) for s in skipped) / 60000.0, 3)
    return True


def read_done(path, redo=False, reclassify=False):
    """Units already collected. A line that does not parse (a write cut off by a kill) is dropped and the file is
    rewritten without it. With redo, not-evaluable rows and rows with no recorded selection are dropped so they are
    collected again (a transient API failure must not be frozen as an answer); with reclassify every non-clean row is
    (the classifier changed: clean rows rest only on the run's own conclusion and stay)."""
    done, keep, dirty = {}, [], False
    if os.path.exists(path):
        with open(path) as fh:
            lines = fh.readlines()
        for line in lines:
            try:
                u = json.loads(line)
            except ValueError:
                dirty = True
                continue
            if (redo and (u.get("cls") == "not-evaluable" or not u.get("fallback"))) or (reclassify and u.get("cls") != "clean"):
                dirty = True
                continue
            done[(u["kind"], u["sha"])] = u
            keep.append(line if line.endswith("\n") else line + "\n")
        if dirty:
            with open(path, "w") as fh:
                fh.write("".join(keep))
    return done


def cmd_collect(a):
    root, dur = repo_root(), durations(repo_root())
    shas = run(["git", "rev-list", "--first-parent", "-n", str(a.commits), a.base], cwd=root).stdout.split()
    if len(shas) < a.commits:
        print("replay: only %d first-parent commits reachable from %s" % (len(shas), a.base), file=sys.stderr)
    i_, k_ = (int(x) for x in a.chunk.split("/"))
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "units-commits-%d-of-%d.jsonl" % (i_, k_))
    done = read_done(path, a.redo_unevaluable, a.reclassify)
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
            u["sel_error"] = str(e)
            u["fallback"] = "selection-error"
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
            # a success run is picked first and classes `clean`, so a failed commit unit never has a same-sha success to clear it
            classify(u, a.repo, cache, lambda unit: False)
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


ISO_UTC = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
SEARCH_CAP = 1000


def cmd_ejections(a):
    root, dur = repo_root(), durations(repo_root())
    since, until = a.since, a.until
    for flag, val in (("--since", since), ("--until", until)):
        if val and not ISO_UTC.match(val):
            # GitHub's created= filter silently matches nothing for an offset such as +02:00
            raise ValueError("%s must be UTC, YYYY-MM-DDTHH:MM:SSZ" % flag)
    if not since or not until:
        # the window is the commit window: oldest and newest committer time of the last N first-parent commits of --base
        shas = run(["git", "rev-list", "--first-parent", "-n", str(a.commits), a.base], cwd=root).stdout.split()
        if not shas:
            raise ReadError("no first-parent commits reachable from %s" % a.base)
        iso = lambda sha: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(run(["git", "log", "-1", "--format=%ct", sha], cwd=root).stdout.strip())))
        since = since or iso(shas[-1])
        until = until or iso(shas[0])
    docs = gh_pages("repos/%s/actions/workflows/ci.yml/runs?event=merge_group&created=%s..%s&per_page=100"
                    % (a.repo, since, until))
    runs = [r for d in docs for r in d.get("workflow_runs", [])]
    total = docs[0].get("total_count") if docs else None
    if not runs:
        raise ReadError("no merge_group runs in %s..%s: an empty window is a failed read, not a clean one" % (since, until))
    if total is None or total != len(runs) or total >= SEARCH_CAP:
        raise ReadError("merge_group run list is truncated or uncounted (total_count=%s, read %d, cap %d): narrow --since"
                        % (total, len(runs), SEARCH_CAP))
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "units-ejections.jsonl")
    done = read_done(path, a.redo_unevaluable, a.reclassify)
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
    # Every conclusion except `success` is a queue run the full battery REFUSED or could not finish (`failure`, `timed_out`,
    # `startup_failure`, an unfinished run, and `cancelled`: a cancelled shard fails the aggregate `test`, so the run is
    # classed from its jobs, where an unsettled shard makes it not-evaluable). None is dropped. The conclusion histogram
    # below names the whole population.
    fail_runs = sorted([r for r in runs if r["conclusion"] != "success"], key=lambda r: r["created_at"])
    hist = {}
    for r in runs:
        k = r["conclusion"] or "in-progress"
        hist[k] = hist.get(k, 0) + 1
    for idx, r in enumerate(fail_runs):
        if ("ejection", r["head_sha"]) in done:
            continue
        u = base_unit("ejection", idx, r["head_sha"])
        u["run"] = {"id": r["id"], "event": "merge_group", "conclusion": r["conclusion"] or "in-progress",
                    "attempt": r["run_attempt"]}
        u["attempts_failed"] = r["run_attempt"]
        u["pr"] = pr_of(r.get("head_branch"))
        try:
            pairs = files_for(r)
            u["content_key"] = content_key(pairs)
            fill_selection(u, root, [x[0] for x in pairs], dur)
        except ReadError as e:
            u["sel_error"] = str(e)
            u["fallback"] = "selection-error"
            u["reason"] = "files: %s" % e
            if "selector" not in str(e):
                u["cls"] = "not-evaluable"
                out.write(json.dumps(u, sort_keys=True) + "\n")
                out.flush()
                n += 1
                continue

        def cleared(unit, r=r):
            # a LATER queue run of the SAME PR whose changed files are the identical (name, blob) set and succeeded.
            # A run whose branch names no PR cannot be tied to one, so nothing clears it.
            pr = pr_of(r.get("head_branch"))
            if not pr or not unit.get("content_key"):
                return False
            for o in by_pr.get(pr, []):
                if o["created_at"] > r["created_at"] and o["conclusion"] == "success":
                    try:
                        if content_key(files_for(o)) == unit["content_key"]:
                            return True
                    except ReadError:
                        return False
            return False
        classify(u, a.repo, cache, cleared)
        out.write(json.dumps(u, sort_keys=True) + "\n")
        out.flush()
        n += 1
    with open(os.path.join(a.out, "ejections-window.json"), "w") as fh:
        json.dump({"since": since, "until": until, "runs": len(runs), "refused": len(fail_runs), "conclusions": hist}, fh, sort_keys=True)
    print("replay ejections: wrote %d units to %s (window %s..%s, %d merge_group runs, %d failed)"
          % (n, path, since, until, len(runs), len(fail_runs)))
    print("replay ejections: conclusions %s" % json.dumps(hist, sort_keys=True))
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
        cdf = sum(math.exp(math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1)
                           + i * math.log(mid) + (n - i) * math.log1p(-mid)) for i in range(k + 1))
        if cdf > target:
            lo = mid
        else:
            hi = mid
    return hi


def load_units(d):
    """Every unit under d. Raises ValueError on a duplicate (kind, sha) (two chunk layouts in one directory would count a
    unit twice and tighten the bound) and on a torn line."""
    units, seen = [], set()
    for name in sorted(os.listdir(d)):
        if name.startswith("units-") and name.endswith(".jsonl"):
            with open(os.path.join(d, name)) as fh:
                for line in fh:
                    if not line.strip():
                        continue
                    u = json.loads(line)
                    key = (u["kind"], u["sha"])
                    if key in seen:
                        raise ValueError("duplicate unit %s %s (in %s): two chunk layouts in one directory?" % (key[0], key[1][:10], name))
                    seen.add(key)
                    units.append(u)
    return units


def check_complete(units, expect_commits, commits_only, d):
    """A population that is missing a chunk, or has no ejections file, reads exactly like a complete clean one."""
    commits = [u for u in units if u["kind"] == "commit"]
    idxs = sorted(u["idx"] for u in commits)
    if commits and idxs != list(range(len(idxs))):
        raise ValueError("commit units are not contiguous 0..%d (a chunk is missing or a layout was mixed)" % (len(idxs) - 1))
    if expect_commits is not None and len(commits) != expect_commits:
        raise ValueError("expected %d commit units, found %d" % (expect_commits, len(commits)))
    if not commits_only and not os.path.exists(os.path.join(d, "units-ejections.jsonl")):
        raise ValueError("no units-ejections.jsonl under %s: the commits population is near-vacuous by construction "
                         "(pass --commits-only to say that is intended)" % d)
    if not commits_only:
        meta_path = os.path.join(d, "ejections-window.json")
        if not os.path.exists(meta_path):
            raise ValueError("no ejections-window.json under %s: re-run `ejections` so the population is checked against the "
                             "number of refused runs the window held" % d)
        with open(meta_path) as fh:
            meta = json.load(fh)
        have = len([u for u in units if u["kind"] == "ejection"])
        if have != meta["refused"]:
            raise ValueError("%d ejection units, but the window held %d refused runs: the population is short or stale" % (have, meta["refused"]))


def mark_multi_unit_flakes(units):
    """A would-skip suite that failed in >= 3 units from >= 3 distinct PRs (a commit counts as its own) with >= 2 distinct
    changed-file sets is a flake class. Only `unverified` units are flipped: an `escape` is never cleared by a count."""
    seen = {}
    for u in units:
        for s in u.get("would_skip_failures", []):
            seen.setdefault(s, []).append(u)
    flaky = {s for s, us in seen.items() if len(us) >= 3 and len({x["files_hash"] for x in us}) >= 2
             and len({x.get("pr") or x["sha"] for x in us}) >= 3}
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
    check_complete(units, a.expect_commits, a.commits_only, a.dir)
    flaky = mark_multi_unit_flakes(units)
    commits = [u for u in units if u["kind"] == "commit"]
    ejects = [u for u in units if u["kind"] == "ejection"]
    lines = ["SOLEUR_PR_AFFECTED_REPLAY rule_sha256=%s" % RULE_SHA256, "rule=%s" % RULE_TEXT,
             "ejection_units=%d commit_units=%d" % (len(ejects), len(commits))]
    mp = os.path.join(a.dir, "ejections-window.json")
    if os.path.exists(mp) and not a.commits_only:
        with open(mp) as fh:
            m = json.load(fh)
        lines.append("ejection_window=%s..%s runs=%d refused=%d conclusions=%s"
                     % (m["since"], m["until"], m["runs"], m["refused"], json.dumps(m["conclusions"], sort_keys=True)))
    results = {}
    for label, pop in (("commits", commits), ("commits+ejections", commits + ejects)):
        s = summarize(pop)
        results[label] = s
        lines.append("population=%s n=%d classes=%s" % (label, s["n"], json.dumps(s["classes"], sort_keys=True)))
        routes = {}
        for u in pop:
            k = "%s:%s" % (u["cls"], u["reason"] or "-")
            routes[k] = routes.get(k, 0) + 1
        lines.append("  routes=%s" % json.dumps(routes, sort_keys=True))
        lines.append("  attributable=%d/%d unverified_as_escape=%d/%d (point %.2f%%) worst_case=%d/%d "
                     "cp95_upper_on_worst_case=%.2f%%" % (s["attributable"], s["n"], s["unverified_as_escape"], s["n"],
                                                         100 * s["point"], s["worst_case"], s["n"], 100 * s["bound_worst_case"]))
    lines.append("attributable means: a would-skip suite failed on >= 2 attempts of the identical tree and attempt 1 failed "
                 "the same suite (deterministic, uncleared). Everything else a would-skip suite did is unverified or cleared above.")
    lines.append("multi_unit_flake_suites=%s" % (",".join(flaky) or "none"))
    # evaluable = the selector ran on a readable diff and applied the rule (fallback=none); a full-battery fallback
    # (runner-changed, undecidable diff) skips nothing and is counted under fallbacks=, not here
    ev = [u for u in commits if u["fallback"] == "none"]
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
        with open(a.out, "w") as fh:
            fh.write(text)
        with open(a.out + ".tsv", "w") as t:
            t.write("kind\tidx\tsha\tfiles_n\tfallback\tskipped_min\tcls\treason\trun\n")
            for u in units:
                t.write("\t".join(str(x) for x in (u["kind"], u["idx"], u["sha"], u["files_n"], u["fallback"], u["skipped_min"],
                                                   u["cls"], re.sub(r"[\t\r\n]", " ", u["reason"]), (u.get("run") or {}).get("id", ""))) + "\n")
    return 0


STATUSES = ("pass", "fail", "within-10%", "unmeasured")


def verdict(a_, b_, c_, d_):
    """GO iff every criterion passes; NO-GO iff any fails; otherwise UNDECIDED (reason says why)."""
    s = [a_, b_, c_, d_]
    for x in s:
        if x not in STATUSES:
            raise ValueError("unknown criterion status %r" % x)
    for name, x in (("b", b_), ("d", d_)):
        if x == "within-10%":
            raise ValueError("criterion %s is a yes/no census and has no 10%% band" % name)
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


# A diff that touches either path degrades --affected to the full battery (runner-changed), so a suite that names
# them is covered by the trigger list and not by its own declared inputs.
RUNNER_TRIGGERS = ("scripts/test-all.sh", "scripts/lib/test-affected-paths.sh")


def strip_comments(text):
    """Blank whole-line comments: a path named only in a comment is a mention, not a read. Lines are split on "\\n" only (bash does
    not split on a vertical tab, a form feed, a lone carriage return or U+2028); a carriage return is removed only when it directly
    precedes the line feed (CRLF), a lone one is an ordinary character. A stripped line becomes an empty line, so every line keeps
    its number."""
    keep = []
    for line in text.replace("\r\n", "\n").split("\n"):
        t = line.lstrip()
        keep.append("" if t.startswith("#") or t.startswith("//") else line)
    return "\n".join(keep)


def tracked_files(root):
    """Every tracked path, read with -z as BYTES: without -z git prints a name holding a non-ASCII byte as a quoted ASCII string, which
    no read can ever match, and text mode would turn a carriage return in a name into a line feed. Decoded like the files are
    (UTF-8, undecodable bytes replaced), so a name and a mention of it agree."""
    return {f.decode("utf-8", errors="replace") for f in run(["git", "ls-files", "-z"], cwd=root, binary=True).stdout.split(b"\0") if f}


def edge_hit(pt, path):
    """The selector's own edge grammar (`_diff_edge_hit` in the runner), applied to one path: `^glob:<head>/<tail>` is a
    bash `[[ == ]]` glob (`*` crosses `/`); `^dir/` is a prefix; `^file` is exact equality. Nothing is a regex: a path
    holding ( ) [ ] + $ matches itself, and `^a.sh` does not match `a.sh.bak`."""
    e = pt[1:] if pt.startswith("^") else pt
    if e.startswith("glob:"):
        g = e[len("glob:"):]
        return re.match("^" + "".join(".*" if c == "*" else "." if c == "?" else re.escape(c) for c in g) + "$", path) is not None
    if e.endswith("/"):
        return path.startswith(e)
    return path == e


def suite_file(root, pattern):
    """The suite's own file is the FIRST pattern of its selector row (`^path`, dots literal). None when that is not a
    readable file (a directory suite, or a pattern the selector derived differently): the caller counts it unaudited."""
    path = pattern[1:] if pattern.startswith("^") else pattern
    full = os.path.join(root, path)
    return full if path and not path.endswith("/") and os.path.isfile(full) else None


# ONE BOUNDARY DEFINITION. A match starts where the character before it is not a word character [A-Za-z0-9_] (or at the start of
# the text): after `/`, a quote, a tab, `=`, `$(`, `-` inside a word and so on a path starts a new component. Two spellings in the
# SOURCE text stand for a character that is not a word character at run time: a printf/echo escape (`A\tdocs/x`: a letter in the
# source, a tab in the running program) and an attached short option (`-Iplugins/x`: the option letter is not part of the path; a
# `-` counts as an option only after whitespace, a quote or the start of the text, so `${V:-docs/x.md}` and `a-docs/x.md` keep their
# path). views() returns TWO views of equal length (offsets and line numbers do not move), and a path is named when EITHER view names
# it: the FULL view blanks the whole escape or option with spaces (`\x09docs/x`, `-Iplugins/x`), the LIGHT view is the text as written,
# for the case where the escape or option letter is the head of the path (`\tests/x`, `\bin/x`, `-docs/x`: the backslash and the dash
# are not word characters, so they already end the previous component; blanking only the introducer would change nothing). Over-keeping
# is the audit's safe direction. A mention that starts inside a word (`xlib/mid.txt` for the
# tracked `lib/mid.txt`) is a different name, not a read, and so is a path glued to the tail of a colour code (`\033[0m<path>`: the
# leftover m is a word character in BOTH views; DECLARED DROP, display text). The right edge is deliberately open: `a.sh` is still
# named by `a.sh.bak`. The start regex of PathIndex and boundary() derive from WORD_CHARS.
WORD_CHARS = "A-Za-z0-9_"
WORD = re.compile("[%s]" % WORD_CHARS)
ESCAPE = re.compile(r"\\(?:[abefnrtv]|0[0-7]{0,3}|x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{4})")
SHORT_OPTION = re.compile(r"""(?<![^\s"'])-[A-Za-z](?=\S)""")
SOURCE_HOP = re.compile(r"""(?:source|\.)\s+["']?(?:\$\{?[A-Za-z_]+\}?/)?([A-Za-z0-9_./-]+\.sh)""")
# bun's test discovery: *.test.* *_test.* *.spec.* *_spec.* over js, jsx, ts, tsx and the module-flavoured mjs, cjs, mts, cts. A
# SUPERSET on purpose: bunfig `pathIgnorePatterns` are not applied (over-scanning is the safe direction).
BUN_TEST = re.compile(r"[._](?:test|spec)\.(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$")
MAX_READ = 8 * 1024 * 1024   # a suite or library larger than this is not read (unreadable:), whatever it is


def views(text):
    """-> (full, light), equal length: `full` is `text` with every printf escape and attached short option replaced by spaces;
    `light` is `text` as written (see the boundary note above). Both are the same object when there is nothing to blank."""
    full = SHORT_OPTION.sub(lambda m: " " * len(m.group(0)), ESCAPE.sub(lambda m: " " * len(m.group(0)), text))
    return (text, text) if full == text else (full, text)


def normalise(text):
    """The full view of `text` (see views)."""
    return views(text)[0]


def boundary(text, i):
    """True when a match at offset i of ONE view of the text starts a path component (see WORD_CHARS)."""
    return i == 0 or WORD.match(text[i - 1]) is None


QUOTE_U = re.compile("[\u0080-\u009f\u200b-\u200f\u2028-\u202e\u2066-\u2069\ufeff]")   # C1, zero-width, line/paragraph separators, bidi controls


def quote_field(s, comma=False):
    """`s` for a line of audit output: a backslash, a C0 control, DEL and, in a comma-joined list, the comma become \\xHH; a C1 control,
    a zero-width character, U+2028/2029 and a bidi control become \\uXXXX. No tracked name can add a line, a column or a list member to
    the output, hide text from a reader or reorder it, and the escape is injective (the backslash itself is escaped)."""
    return "".join("\\x%02x" % ord(c) if ord(c) < 0x20 or c == "\x7f" or c == "\\" or (comma and c == ",")
                   else "\\u%04x" % ord(c) if QUOTE_U.match(c) else c for c in s)


def name_regex(names):
    """A regex (no group around it) that matches the start of any of `names`, built from a PREFIX TRIE of the names: the work at a
    position is bounded by the alphabet, not by the number of names. Characters are escaped. A name that is a prefix of another
    ends the descent (the shorter name already starts a match)."""
    trie = {}
    for n in names:
        node = trie
        for ch in n:
            node = node.setdefault(ch, {})
        node[""] = True

    def emit(node):
        if "" in node:
            return ""
        alts = [re.escape(ch) + emit(node[ch]) for ch in sorted(node)]
        return alts[0] if len(alts) == 1 else "(?:%s)" % "|".join(alts)
    return emit(trie)


def trie_leaf(trie, name):
    """The dict of the character trie `trie` at the end of `name`, created on the way (the leaf value lives under the key "")."""
    for ch in name:
        trie = trie.setdefault(ch, {})
    return trie


class PathNode:
    """One directory of the tracked tree: character tries of its file names (`ftrie`, leaf = the tracked path) and of its
    sub-directory names (`dtrie`, leaf = the sub-directory's PathNode), so a walk costs the characters it matches and not the
    number of names or of distinct name lengths."""
    __slots__ = ("dtrie", "ftrie")

    def __init__(self):
        self.dtrie, self.ftrie = {}, {}


class PathIndex:
    """The tracked paths as a component trie, plus what one audit run memoises across suites: each file's comment-stripped text as
    written (`raws`), its two views (`views`) and the tracked paths it names (`refs`), keyed on the FULL path (two libraries named
    helper.sh in different directories are two entries). `ops` counts every start candidate and every trie step, so a test can
    bound the work by an operation count instead of a clock."""

    def __init__(self, tracked):
        self.tracked = set(tracked)
        self.paths = sorted(self.tracked)
        self.root = PathNode()
        for p in self.paths:
            comps = p.split("/")
            node = self.root
            for c in comps[:-1]:
                leaf = trie_leaf(node.dtrie, c)
                if "" not in leaf:
                    leaf[""] = PathNode()
                node = leaf[""]
            trie_leaf(node.ftrie, comps[-1])[""] = p
        names = {p.split("/")[0] for p in self.paths}
        self.start = re.compile(r"(?<![%s])(?=%s)" % (WORD_CHARS, name_regex(names))) if names else None
        self.ops = 0
        self.raws = {}
        self.views = {}
        self.refs = {}

    def under(self, prefix):
        """The tracked paths that start with `prefix`, in order."""
        i = bisect_left(self.paths, prefix)
        out = []
        while i < len(self.paths) and self.paths[i].startswith(prefix):
            out.append(self.paths[i])
            i += 1
        return out


def walk_text(index, text):
    """Every tracked path that ONE view of a text names starting at a component boundary. A candidate start is a boundary where
    some top-level name begins; from there the match is extended component by component through the character tries of the tracked
    tree and stops at the first component that is not tracked, so the work follows the text and not the number of tracked paths,
    names or name lengths."""
    out = set()
    if index.start is None:
        return out
    for m in index.start.finditer(text):
        index.ops += 1
        cur, node = m.start(), index.root
        while node is not None:
            t, i = node.ftrie, cur       # every file name that starts here (a name that is a prefix of another is named by both)
            while True:
                leaf = t.get("")
                if leaf is not None:
                    out.add(leaf)
                ch = text[i:i + 1]
                t = t.get(ch) if ch else None
                if t is None:
                    break
                i += 1
                index.ops += 1
            t, i, nxt = node.dtrie, cur, None   # the sub-directory whose name is followed by a slash
            while True:
                ch = text[i:i + 1]
                if not ch:
                    break
                if ch == "/":
                    nxt = t.get("")
                    break
                t = t.get(ch)
                if t is None:
                    break
                i += 1
                index.ops += 1
            node, cur = nxt, i + 1
    return out


def scan_views(index, full, light):
    """The union of the tracked paths the full and the light view name (one walk when they are the same text)."""
    out = walk_text(index, full)
    if light is not full:
        out |= walk_text(index, light)
    return out


def scan_text(index, text):
    """Every tracked path that `text` (as written, comments already stripped) names at a component boundary in either view."""
    return scan_views(index, *views(text))


def read_bytes(path, base):
    """The bytes of a regular file of at most MAX_READ bytes, or ReadError. A symlink is followed only when it resolves to a path
    inside `base` (the tree under audit); the file is opened non-blocking and without following a link, and must be a regular file,
    so a device, a FIFO, a directory or a link to a file outside the tree is refused rather than read."""
    real = os.path.realpath(path)
    if base is not None:
        top = os.path.realpath(base)
        if real != top and not real.startswith(top.rstrip(os.sep) + os.sep):
            raise ReadError("cannot read %s: it resolves outside %s" % (path, base))
    try:
        fd = os.open(real, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
    except OSError as e:
        raise ReadError("cannot read %s: %s" % (path, e.strerror or e))
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ReadError("cannot read %s: not a regular file" % path)
        chunks, size = [], 0
        while True:
            b = os.read(fd, 1 << 20)
            if not b:
                return b"".join(chunks)
            chunks.append(b)
            size += len(b)
            if size > MAX_READ:
                raise ReadError("cannot read %s: larger than %d bytes" % (path, MAX_READ))
    except OSError as e:
        raise ReadError("cannot read %s: %s" % (path, e.strerror or e))
    finally:
        os.close(fd)


def read_text(index, path, base=None):
    """The comment-stripped text of one file as written (`index.raws[path]`) and its two views, read once per run; returns the
    views. ReadError when the file is not a readable regular file (see read_bytes)."""
    v = index.views.get(path)
    if v is None:
        raw = strip_comments(read_bytes(path, base).decode("utf-8", errors="replace"))
        index.raws[path] = raw
        v = index.views[path] = views(raw)
    return v


def suite_inputs(root, pattern, index):
    """The files a suite's reads are taken from: its own file, or for a directory suite (the first pattern is a `dir/`
    prefix) the tracked bun-discoverable test files under it. None when there is neither, and the caller counts it unaudited."""
    path = suite_file(root, pattern)
    if path is not None:
        return [path]
    d = pattern[1:] if pattern.startswith("^") else pattern
    if not d.endswith("/") or d.startswith("glob:") or not os.path.isdir(os.path.join(root, d)):
        return None
    files = [os.path.join(root, f) for f in index.under(d) if BUN_TEST.search(f)]
    return files or None


def try_read(index, path, bad, base=None):
    """-> (real path, full, light, as written), or None with `path` appended to `bad`; with bad=None an unreadable file raises
    ReadError. EVERY 'can this file be read' question goes through here. Everything read is keyed on the REAL path, so two names for
    one file (a symlink, a symlinked directory) are one read, one memo entry and one set of ordinals."""
    real = os.path.realpath(path)
    try:
        full, light = read_text(index, real, base)
    except ReadError:
        if bad is None:
            raise
        if path not in bad:
            bad.append(path)
        return None
    return real, full, light, index.raws[real]


def suite_texts(root, inputs, index, bad=None):
    """-> [(real path, full view, light view, text as written)]: the suite's own files, then the libraries they source (one hop, in
    hop order), each real file once. A file that cannot be read is skipped and listed in `bad` (ReadError when `bad` is None). A
    sourced path counts only when it is a TRACKED path (so the count does not depend on untracked files in the work tree); one that
    is not a readable regular file inside the tree (a dangling symlink, a directory, a file deleted from the work tree) is an
    unreadable file; a sourced name that is not tracked is not read."""
    out, seen = [], set()
    for p in inputs:
        got = try_read(index, os.path.normpath(p), bad, root)
        if got is None:
            continue
        chain = [got]
        for m in SOURCE_HOP.finditer(got[3]):
            q = os.path.normpath(os.path.join(root, m.group(1)))
            if os.path.relpath(q, root) in index.tracked:
                g = try_read(index, q, bad, root)
                if g is not None:
                    chain.append(g)
        for g in chain:
            if g[0] not in seen:
                seen.add(g[0])
                out.append(g)
    return out


def suite_refs(root, suite, inputs, index, texts=None, bad=None):
    """Tracked repo paths this suite (its file, or a directory suite's test files) and the libs it sources, one level, names
    literally. The per-file result is memoised UNEXCLUDED: the suite's own path is dropped here, per call, because the same
    library is read for other suites that do name it. `texts` is suite_texts() when the caller already has it."""
    named = set()
    for q, full, light, _ in (texts if texts is not None else suite_texts(root, inputs, index, bad)):
        r = index.refs.get(q)
        if r is None:
            r = index.refs[q] = scan_views(index, full, light)
        named |= r
    top = os.path.realpath(root)
    own = {os.path.relpath(p, root) for p in inputs} | {os.path.relpath(os.path.realpath(p), top) for p in inputs}
    return sorted(f for f in named if f != suite and f not in own and f not in RUNNER_TRIGGERS)


def boundary_lines(texts, path):
    """-> [(file, lineno, line as written)] for every line of the suite's texts in which either view holds a boundary match of
    `path`, in order. A file that does not contain the path at all is skipped before it is split."""
    out = []
    for q, full, light, written in texts:
        if path not in full and path not in light:
            continue
        wl, fl = written.split("\n"), full.split("\n")
        ll = fl if light is full else light.split("\n")
        for no, (a, b) in enumerate(zip(fl, ll), 1):
            for line in ((a,) if a is b or a == b else (a, b)):
                i = line.find(path)
                while i >= 0 and not boundary(line, i):
                    i = line.find(path, i + 1)
                if i >= 0:
                    out.append((q, no, wl[no - 1]))
                    break
    return out


def pair_anchors(texts, path):
    """-> [(anchor, ordinal, file, lineno, text)] for every line of the suite's texts that holds a boundary match of `path` in
    either view, in order. The anchor and `text` are the line AS WRITTEN with its whitespace collapsed (" ".join(line.split()), so
    re-indenting or CRLF do not move it), and the anchor is the first 12 hex of its sha256. The ordinal numbers identical anchors
    1, 2, ... over the suite file and then its sourced libraries in hop order, so two identical reading lines are two rows.
    `lineno` counts physical lines (a comment line is blanked, never removed)."""
    count, out = {}, []
    for q, no, written in boundary_lines(texts, path):
        text = " ".join(written.split())
        a = hashlib.sha256(text.encode()).hexdigest()[:12]
        count[a] = count.get(a, 0) + 1
        out.append((a, count[a], q, no, text))
    return out


def load_accept(path):
    """Exemptions: see the ACCEPT FILE section of --help. A missing file is no exemptions (one stderr line says so); a file that
    cannot be read is a ReadError (rc 3); a malformed row is a ValueError (rc 2) that names the failing column.
    -> {suite: {path: [(anchor, ordinal, reason)]}}"""
    acc = {}
    if not os.path.exists(path):
        print("replay: --accept %s does not exist: no exemptions" % path, file=sys.stderr)
        return acc
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as e:
        raise ReadError("cannot read the accept file %s: %s" % (path, e.strerror or e))
    seen = set()
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        where = "%s:%d" % (path, n)
        if len(f) != 5:
            raise ValueError("%s: %d column(s), want 5: suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>; the 3-column "
                             "form `suite<TAB>path<TAB>reason` was retired (see --help, ACCEPT FILE)" % (where, len(f)))
        if not f[0]:
            raise ValueError("%s: col 1 (suite) is empty" % where)
        if not f[1]:
            raise ValueError("%s: col 2 (path) is empty" % where)
        if f[1] == "*":
            if f[2:4] != ["-", "-"]:
                raise ValueError("%s: col 3 and col 4 of a `*` row must both be `-`: suite<TAB>*<TAB>-<TAB>-<TAB>false-positive: <reason>" % where)
        else:
            if not re.match(r"^[0-9a-f]{12}$", f[2]):
                raise ValueError("%s: col 3 (anchor) must be 12 lowercase hex characters (the first 12 of the sha256, see --help)" % where)
            if not re.match(r"^[1-9][0-9]*$", f[3]):
                raise ValueError("%s: col 4 (ordinal) must be 1, 2, ... (the Nth identical line)" % where)
        if not re.match(r"^false-positive: \S", f[4]):
            raise ValueError("%s: col 5 (reason) must be `false-positive: ` followed by a reason" % where)
        if tuple(f[:4]) in seen:
            raise ValueError("%s: duplicate accept row" % where)
        seen.add(tuple(f[:4]))
        acc.setdefault(f[0], {}).setdefault(f[1], []).append((f[2], int(f[3]) if f[3] != "-" else 0, f[4]))
    return acc


class Census:
    """What one audit run found; cmd_audit only formats it, and a later ratchet reads it instead of parsing stdout. The unit is the
    suite LABEL: selector rows that share a label are one suite (texts, gaps, accept rows and the always_on decision are merged),
    except `suites`, which counts selector rows.
      gaps        {label: [paths still undeclared after the exemptions]}, in row order
      miss        {label: [paths undeclared BEFORE the exemptions]}
      pair_texts  {label: {path: suite_texts() of the rows that left the path undeclared}} for the gaps (ref_lines)
      unaudited   [(label, why, quoted)] unique; `quoted` says `why` was already passed through quote_field
      stale       [(label, path, anchor/ordinal, why)], sorted and unique
      extra       the selector lines that are not AFFECTED_SELECTED rows (AFFECTED_SUMMARY, AFFECTED_FALLBACK)
      registered  {label: reason} (`always_on` when any row of the label is)
      labels      every label seen   refs  distinct (label, path) pairs found before any exemption   files_read  distinct real files read"""

    def __init__(self, root, index):
        self.root, self.index = root, index
        self.suites = self.always_on = self.accepted = self.accepted_unread = self.refs = 0
        self.gaps, self.miss, self.registered, self.pair_texts = {}, {}, {}, {}
        self.labels, self.short_rows = set(), set()
        self.unaudited, self.stale, self.extra = [], [], []

    @property
    def gap_refs(self):
        return sum(len(v) for v in self.gaps.values())

    @property
    def files_read(self):
        return len(self.index.raws)

    @property
    def unaudited_labels(self):
        return len({u[0] for u in self.unaudited})

    @property
    def audited(self):
        return len(self.labels) - self.always_on - self.unaudited_labels - self.accepted_unread

    def add_unaudited(self, label, why, quoted=False):
        if (label, why, quoted) not in self.unaudited:
            self.unaudited.append((label, why, quoted))

    def ref_lines(self, label, path):
        """The boundary lines of `label` that name `path`: [(anchor, ordinal, file, lineno, text)], file relative to the root."""
        top = os.path.realpath(self.root)
        return [(a, o, os.path.relpath(q, top), no, t) for a, o, q, no, t in pair_anchors(self.pair_texts[label][path], path)]


def stale_entries(suite, path, entries, why):
    return [(suite, path, "-/-" if e[0] == "-" else "%s/%d" % (e[0], e[1]), why) for e in entries]


def judge_rules(suite, rules, miss, texts_of, tracked, star_why, partial=False):
    """The accept rows of one readable suite against its live gaps -> (stale, accepted, kept). `texts_of[path]` is the suite_texts()
    of the rows that left `path` undeclared. A row is stale when it is a `*` row (a suite with any input is not accepted whole),
    names an untracked path, names a pair that is not a gap before the exemptions (an edge now declares it, or no line names it any
    more), or an (anchor, ordinal) that no live boundary line carries. A gap is accepted only when EVERY boundary line of the pair has
    a row; the rest are kept. With `partial` (some member of the suite could not be read, so the text is incomplete) nothing is
    judged by its text: only `*` rows and untracked paths are stale and nothing is accepted, so no row that is correct for the whole
    text is reported as one to delete."""
    stale, anchors, miss_set = [], {}, set(miss)
    for path, entries in rules.items():
        if path == "*":
            stale += stale_entries(suite, path, entries, star_why)
        elif path not in tracked:
            stale += stale_entries(suite, path, entries, "path-untracked")
        elif partial:
            continue
        elif path not in miss_set:
            stale += stale_entries(suite, path, entries, "not-a-gap")
        else:
            anchors[path] = pair_anchors(texts_of.get(path, []), path)
            live = {(a[0], a[1]) for a in anchors[path]}
            stale += stale_entries(suite, path, [e for e in entries if (e[0], e[1]) not in live], "anchor-not-live")
    accepted, kept = 0, []
    for path in miss:
        want = {(e[0], e[1]) for e in rules.get(path, [])}
        lines = anchors.get(path, [])
        if lines and all((a[0], a[1]) in want for a in lines):
            accepted += 1
        else:
            kept.append(path)
    return stale, accepted, kept


def merge_unique(into, items):
    seen = set(into)
    into.extend(i for i in items if i not in seen and not seen.add(i))


def has_tracked_input(index, pattern):
    """True when git tracks the suite's input(s) for the first selector pattern: the file itself, or a bun-discoverable test file
    under a directory pattern (whatever the work tree holds)."""
    path = pattern[1:] if pattern.startswith("^") else pattern
    if path.startswith("glob:"):
        return False
    if path.endswith("/"):
        return any(BUN_TEST.search(f) for f in index.under(path))
    return path in index.tracked


def audit_census(root, rows, accept):
    """Index-completeness census over the selector's own rows (`rows`: every line the selector printed): the tracked paths each
    registered suite names that none of its declared/derived edges cover. One pass groups the rows by label; the second judges each
    label once, so nothing depends on row order: a label is always_on if any of its rows is; a path is a gap of the label when
    some row's text names it and that row's edges do not cover it, and its anchors come from the texts of those rows only."""
    index = PathIndex(tracked_files(root))
    c = Census(root, index)
    groups = {}
    for line in rows:
        f = line.split("\t")
        if f[0] != "AFFECTED_SELECTED":
            if line.strip():
                c.extra.append(line)
            continue
        c.suites += 1
        label = f[1] if len(f) > 1 else "?"
        c.labels.add(label)
        if len(f) < 5:
            c.add_unaudited(label, "short-row")
            c.short_rows.add(label)
            continue
        g = groups.setdefault(label, {"always_on": False, "reason": f[3], "rows": []})
        if f[3] == "always_on":
            g["always_on"] = True
        g["reason"] = f[3]
        g["rows"].append(f[4].split("|"))
    for label, g in groups.items():
        c.registered[label] = "always_on" if g["always_on"] else g["reason"]
        if g["always_on"]:
            c.always_on += 1
            continue
        rules = accept.get(label, {})
        bad, dead, ok, found = [], [], [], set()
        for pats in g["rows"]:
            inputs = suite_inputs(root, pats[0], index)
            if inputs is None:
                dead.append(pats[0])
                continue
            texts = suite_texts(root, inputs, index, bad)
            refs = suite_refs(root, label, inputs, index, texts)
            found.update(refs)
            ok.append((texts, [r for r in refs if not any(edge_hit(pt, r) for pt in pats)]))
        c.refs += len(found)
        if not ok:   # no row has an input to read
            tracked_suite = any(has_tracked_input(index, d) for d in dead)
            if "*" in rules and not tracked_suite:
                c.accepted += 1
                c.accepted_unread += 1
            else:
                for d in dead:
                    c.add_unaudited(label, d)
            if "*" in rules and tracked_suite:
                c.stale += stale_entries(label, "*", rules["*"], "star-row-tracked-suite")
            for path, entries in rules.items():
                if path != "*":
                    c.stale += stale_entries(label, path, entries, "suite-unaudited")
            continue
        for d in dead:   # a sibling row of the label with nothing to read
            c.add_unaudited(label, d)
        if bad:
            c.add_unaudited(label, "unreadable:" + ",".join(sorted(quote_field(os.path.relpath(b, root), True) for b in bad)), True)
        miss, texts_of = [], {}
        for texts, m in ok:
            for path in m:
                if path not in texts_of:
                    miss.append(path)
                    texts_of[path] = []
                have = {t[0] for t in texts_of[path]}
                texts_of[path].extend(t for t in texts if t[0] not in have)
        c.miss[label] = miss
        if rules:
            stale, accepted, kept = judge_rules(label, rules, miss, texts_of, index.tracked,
                                                "star-row-unreadable-members" if bad else "star-row-readable-suite", partial=bool(bad))
            c.stale += stale
            c.accepted += accepted
        else:
            kept = miss
        if kept:
            c.gaps[label] = kept
            c.pair_texts[label] = {x: texts_of[x] for x in kept}
    for suite, rules in accept.items():
        if suite in c.short_rows and suite not in c.registered:
            why = "suite-unaudited"
        elif suite not in c.registered:
            why = "suite-unregistered"
        elif c.registered[suite] == "always_on":
            why = "suite-always-on"
        else:
            continue
        for path, entries in rules.items():
            c.stale += stale_entries(suite, path, entries, why)
    c.stale = sorted(set(c.stale))
    return c


def load_rows(list_path, root):
    """Every line the selector printed (or the file `list_path` holds), AFFECTED_SUMMARY and AFFECTED_FALLBACK included; a trailing
    carriage return is dropped from each, so the last edge of a CRLF file still hits."""
    if list_path:
        try:
            with open(list_path, encoding="utf-8", errors="replace", newline="") as fh:
                return [line.rstrip("\r") for line in fh.read().split("\n")]
        except OSError as e:
            raise ReadError("cannot read the rows file %s: %s" % (list_path, e.strerror or e))
    sp = run_selector(root, ["--paths=README.md"])
    if sp.returncode != 0:
        raise ReadError("selector rc=%d: rows printed before a failure are not an audit" % sp.returncode)
    return sp.stdout.split("\n")


def cmd_audit(a):
    """Index-completeness audit over the selector's own rows: every tracked path a registered suite names
    must be hit by one of that suite's declared/derived edges. Prints one `gap` line per suite with gaps (the first six
    paths, or all with --all-refs, which also prints one `ref` line per boundary line), one `unaudited` line per suite whose
    inputs could not be read in full and one `stale` line per accept row the tree no longer backs (see audit_census). Exit 0 only
    when no gap, no unaudited suite and no stale row remain after the --accept exemptions: a suite the audit never read is not a
    suite with no gaps. always_on suites run on every diff, so their index is moot. A row too short to name its edges is
    unaudited. A directory suite is read through its bun test files; one it cannot read in full is `unreadable:<relpath>`.
    Every path in the output goes through quote_field."""
    root = a.root or repo_root()
    accept = load_accept(a.accept) if a.accept else {}
    c = audit_census(root, load_rows(a.list, root), accept)
    if c.suites == 0:
        print("replay audit: the selector printed no AFFECTED_SELECTED rows", file=sys.stderr)
        return 2
    for suite, found in c.gaps.items():
        print("gap\t%s\t%d\t%s" % (quote_field(suite), len(found), ",".join(quote_field(p, True) for p in (found if a.all_refs else found[:6]))))
        if a.all_refs:
            for path in found:
                for anchor, ordinal, rel, no, text in c.ref_lines(suite, path):
                    print("ref\t%s\t%s\t%s:%d\t%s/%d\t%s" % (quote_field(suite), quote_field(path), quote_field(rel), no, anchor, ordinal, quote_field(text)))
    for suite, why, quoted in c.unaudited:
        print("unaudited\t%s\t%s" % (quote_field(suite), why if quoted else quote_field(why)))
    for suite, p, key, why in c.stale:
        print("stale\t%s\t%s\t%s\t%s" % (quote_field(suite), quote_field(p), key, why))
    print("SOLEUR_PR_AFFECTED_AUDIT suites=%d always_on=%d audited=%d unaudited=%d gap_suites=%d gap_refs=%d accepted=%d stale=%d refs=%d files_read=%d"
          % (c.suites, c.always_on, c.audited, c.unaudited_labels, len(c.gaps), c.gap_refs, c.accepted, len(c.stale), c.refs, c.files_read))
    return 0 if not c.gaps and not c.unaudited and not c.stale else 1


def main(argv):
    ap = argparse.ArgumentParser(prog="ci-pr-affected-replay", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("collect", help="classify the last N first-parent commits of main")
    c.add_argument("--out", required=True, help="directory the units-*.jsonl and joblogs/ are written under")
    c.add_argument("--commits", type=int, default=300, help="how many first-parent commits of --base (default 300)")
    c.add_argument("--chunk", default="1/1", help="I/K: collect every K-th commit starting at I (default 1/1)")
    c.add_argument("--repo", default="jikig-ai/soleur", help="OWNER/REPO the run records are read from")
    c.add_argument("--base", default="origin/main", help="ref whose first-parent history is replayed")
    c.add_argument("--redo-unevaluable", action="store_true", dest="redo_unevaluable",
                   help="drop every not-evaluable unit and collect it again")
    c.add_argument("--reclassify", action="store_true", help="drop every non-clean unit and collect it again")
    e = sub.add_parser("ejections", help="classify every failed merge_group run since the window start (--since is UTC)")
    e.add_argument("--out", required=True, help="the same directory collect wrote to")
    e.add_argument("--since", default="", help="window start, UTC; default: committer time of the oldest of the last N commits")
    e.add_argument("--until", default="", help="window end, UTC; default: committer time of the newest of them")
    e.add_argument("--commits", type=int, default=300, help="size of the commit window the default --since/--until come from")
    e.add_argument("--repo", default="jikig-ai/soleur", help="OWNER/REPO the merge_group runs are read from")
    e.add_argument("--base", default="origin/main", help="ref whose first-parent history defines the window")
    e.add_argument("--redo-unevaluable", action="store_true", dest="redo_unevaluable",
                   help="drop every not-evaluable unit and collect it again")
    e.add_argument("--reclassify", action="store_true", help="drop every non-clean unit and collect it again")
    g = sub.add_parser("aggregate", help="summarise a collected directory; prints the receipt text")
    g.add_argument("dir", help="the directory collect and ejections wrote to")
    g.add_argument("--baseline-min", type=float, default=99.8, dest="baseline_min",
                   help="billed job-minutes per PR run the 20%% bar is taken of (default 99.8)")
    g.add_argument("--selector-min", type=float, default=1.29, dest="selector_min", help="billed selector minutes per run (default 1.29)")
    g.add_argument("--out", default="", help="also write the receipt text here, and a per-unit TSV beside it")
    g.add_argument("--expect-commits", type=int, default=None, dest="expect_commits",
                   help="refuse (rc 2) unless exactly N commit units are present")
    g.add_argument("--commits-only", action="store_true", dest="commits_only",
                   help="allow a directory with no units-ejections.jsonl (the near-vacuous population only)")
    v = sub.add_parser("verdict", help="GO/NO-GO arithmetic over four criterion statuses (pass|fail|within-10%%|unmeasured)")
    for k, what in (("a", "escape gate"), ("b", "index completeness"), ("c", "net saving"), ("d", "documentation census")):
        v.add_argument("--" + k, required=True, help="criterion %s (%s): pass | fail | within-10%%%% | unmeasured" % (k, what))
    p = sub.add_parser("cp-upper", help="one-sided Clopper-Pearson upper bound for K events in N")
    p.add_argument("k", type=int, help="events observed")
    p.add_argument("n", type=int, help="units observed")
    p.add_argument("conf", type=float, nargs="?", default=0.95, help="one-sided confidence (default 0.95); prints a fraction")
    u = sub.add_parser("audit", help="index-completeness audit; run it on a pinned origin/main tree")
    u.add_argument("--root", default="", help="the tree to audit (default: the current checkout; use a pinned detached one)")
    u.add_argument("--list", default="", help="read AFFECTED_SELECTED rows from FILE instead of running the selector")
    u.add_argument("--accept", default="", help="TSV of exemptions: suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>, or suite<TAB>*<TAB>-<TAB>-<TAB>false-positive: <reason> for a suite with no inputs; "
                  "anchor = first 12 hex of sha256(\" \".join(line.split())) of the comment-stripped line; ordinal = the Nth identical line (suite file, then sourced libraries in hop order); "
                  "a missing file exempts nothing (see the ACCEPT FILE section above)")
    u.add_argument("--all-refs", action="store_true", dest="all_refs", help="print every undeclared path, not the first six, and a ref line (file:line, anchor/ordinal, text) per boundary line")
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
    except Exception as e:  # an internal error must not exit 1, which is the audit's "gaps found"
        print("replay: internal error: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
