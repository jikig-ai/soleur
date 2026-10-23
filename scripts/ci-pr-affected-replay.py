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
  ratchet      [--root DIR] [--list FILE] [--baseline FILE] [--accept FILE] [--base REF] [--print-baseline] [--report FILE]
The receipt paths are arguments; no repository path literal lives in this file.

AUDIT OUTPUT. `gap<TAB>suite<TAB>N<TAB>paths` (the first six, all with --all-refs, which also prints under it one
`ref<TAB>suite<TAB>path<TAB>file:line<TAB>anchor/ordinal<TAB>text` line per boundary line naming each path: the data an accept row
is written from); `unaudited<TAB>suite<TAB>why` (why: short-row, the first pattern when the suite has no readable input, or
`unreadable:<relpath>[,<relpath>]` when a tracked test file of a directory suite cannot be read; its readable files are still
scanned); `stale<TAB>suite<TAB>path<TAB>anchor/ordinal<TAB>why`; then one SOLEUR_PR_AFFECTED_AUDIT summary line:
`suites= always_on= audited= unaudited= gap_suites= gap_refs= accepted= stale= refs= files_read=`. UNITS: `suites` counts selector ROWS.
Per suite LABEL (rows that share a label are one suite: always_on if any of its rows is, its gaps and accept rows merged, each gap
attributed to the rows whose text names it): `always_on`, `audited` (labels that are none of always_on, unaudited or accepted
unread: never negative), `unaudited` and `gap_suites`. Per (label, path) PAIR: `gap_refs` (after the exemptions), `refs` (before any
exemption) and `accepted` (pairs exempted, plus one per suite accepted whole by a `*` row). Per accept-row entry: `stale`. Distinct
real files read: `files_read`. A change of the audit's REACH shows in `refs` and `files_read` even when the gaps do not move. The SET
of gaps does not depend on the order of the selector rows; the printed ORDER of the gap paths (and so which six `gap` shows) follows it.
Every path printed has a backslash, a control character and, inside a comma-joined list, the comma written as
\\xHH, and a C1 control, soft hyphen, zero-width or joiner character, U+2028/2029 or bidi control (the classes are listed on quote_field)
written as \\uXXXX, so a tracked name cannot add a line or a column or reorder the text. A suite or library is read only when it is a regular file of at most
8 MiB inside the tree (a symlink is followed only to a regular file inside the tree); anything else is `unreadable:`, including a
`source`d tracked file that is a dangling symlink, a directory or deleted from the work tree. While a suite has an unreadable member
its accept rows are not judged by their text (only `*` rows and untracked paths are stale).

DECLARED LIMITS. The walk costs the text length times the longest tracked component name when both are adversarial: a tracked 255-character
name such as 'a-a-...' against a suite that repeats it took 2.7 s at 100 KB and 11.5 s at 400 KB (about 230 s per view at the 8 MiB read cap);
real names and real suites are far below this, and it needs a hostile tracked name plus a hostile suite on the pinned tree. A tracked path
that contains a newline is found by the scan (it is reported as a gap) but lines are split on newline, so it has no `ref` line and no accept
row can exempt it: fail-closed, and no such name is tracked. A path glued to the tail of an ANSI colour code is display text and is not a
read. The reach and its limits are in the next section.

REACH (S4 index completion PR1b, #10448; frozen here: the ADR-276 amendment points at it, it does not quote it). `gap_suites=0` means LITERAL-NAME COMPLETENESS OVER
WHAT THIS AUDIT READS (the suite file, its source closure and the naming walk below, an approximation of the selector closure from inside):
necessary, not sufficient. What the audit reads for one selector row, in this order:
  1. the suite's own file (a directory suite: its bun-discoverable test files);
  2. the SOURCE CLOSURE of each of them: `source X` / `. X` lines, to depth 8 (the selector expands the files at distance 0 to 7; its 8th pass
     names the distance-8 files as edges without expanding them, so the audit reads one level further: it over-reports, the safe direction), breadth first, each
     real file once, a cycle ending at the visited file. Operands: `$(dirname "$0")/`, `$(dirname "${BASH_SOURCE[0]}")/`, `$SCRIPT_DIR/`,
     `${SCRIPT_DIR}/`, `$HERE/`, `${HERE}/`, `$DIR/` and `${DIR}/` resolve against the directory of the INCLUDING file (`..` normalised);
     `$REPO_ROOT/`, `${REPO_ROOT}/`, `$ROOT_DIR/`, any other `$X/` prefix and a bare path resolve against the repo root. Only a tracked .sh or
     .bash target is read, never a runner trigger;
  3. the NAMING WALK: a CODE file (.sh .bash .py .ts .tsx .jsx .js .mjs .cjs .mts .cts .rb) that the row lists in `pats` as an exact `^file`
     entry and that an already-read text names literally, to depth 8 (sorted within a level), per row. After each level is read, the source
     closure of its files is read too (a fresh 8-level closure per walk file, or the depth left for a file already read as a closure member) and both feed the next level's naming. The two
     runner triggers are never nodes; a `glob:` or `dir/` entry never is.
Every file is read at most once per run and the read order is canonical (per row: each input followed by its closure; then, level by level,
the walk files of the level by sorted path followed by their closures; the rows of a label ordered by their whole pattern list), so an
accept row's ordinal never depends on the order the selector printed the rows. An edge is credited exactly when the selector would select
the suite for a diff naming the path (edge_hit mirrors `_diff_touches`).
DRAIN-REVEAL: reach is frozen as a definition but its result moves through declared edges and through the text of files it reads: declaring
a code file as an edge makes the audit read that file, which can reveal more pairs. Accept an anchor-keyed row when the suite does not read or
execute the file, declare an edge only when it does, and re-run the audit to a fixpoint.
DECLARED LIMITS (what no run of this audit proves):
  - literal names only: no computed path, glob expansion or variable-indirect operand;
  - hops are `source` / `.` lines to .sh or .bash targets. The selector also mints edges from `bash|sh|python3|node|bun|exec` invocations of a
    path, from `VAR=path; source "$VAR"` assignments, `source --`, other extensions, dotted python imports (`import pkg.mod`), the stem fan of a
    stem suite and prefixes assigned from `$(cd ... && pwd)` (80 tracked lines use `. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/x.sh"`
    and are not followed; about 90 tracked lines use a `source` or `.` of a `$(cd ...)` prefix). Measured when this was reviewed: 295 of 536
    audited labels list in `pats` a code file (CODE_EXT, exact `^file`) that the audit never reads (1,166 label-path pairs; command: code_pats_of(pats)
    minus the files reach_texts() returns, over `test-all.sh --print-selection --paths=README.md`);
  - `$(dirname "$0")` inside a sourced file resolves against that file, as the selector's own convention does (bash resolves $0 to the entry script);
  - the first pattern of a row is taken to be the suite's own file (true by the selector's construction); a runner trigger as first pattern is unaudited;
  - data inputs in `pats` (manifests, workflows, SKILL.md files, baselines, tsv tables, docs) are checked as declared edges but their contents
    are never scanned, and code reached only through them is not read; code files that a `dir/` or `glob:` entry covers are read by nothing
    (making them nodes would add 621 pairs and 10 gap suites on the pinned tree);
  - suites the runner declines under `--pr-gated` (ADR-262), directory and glob reads, bun helper files and the bunfig preload are not modelled;
  - the comment table strips only a whole-line comment of the file's own language: a line inside a docstring or heredoc body that begins with the
    comment marker is blanked (under-read), other block-comment and heredoc lines stay an over-report;
  - a tracked name holding a TAB or a double quote is framed differently in the selector's diff blob (no such name is tracked);
  - a runner trigger is covered by the trigger list (a diff touching one runs the full battery), not by its own edges; the registration-only and
    staged-diff premise of the runner classifier is unchanged.

ACCEPT FILE (--accept FILE; tab-separated, `#` lines and blank lines skipped; a missing file exempts nothing and says so on stderr):
  suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>     one row per source line that names the path
  suite<TAB>*<TAB>-<TAB>-<TAB>false-positive: <reason>                   a whole suite that has NO inputs at all (never one with any)
  anchor    the first 12 hex of sha256 over `" ".join(line.split())`, where `line` is the comment-stripped source line AS WRITTEN
            (whitespace collapsed; Unicode whitespace too, as str.split() does; a comment line is blanked, never removed)
  ordinal   1, 2, ...: the Nth line with that anchor, counted over the files in the canonical read order (see REACH): the suite file, its
            source closure, then the naming-walk files
A gap is accepted only when every boundary line that names it has a row. The 3-column form `suite<TAB>path<TAB>reason` was retired.
STALE rows (exit 1, reason printed): not-a-gap (the pair is not a gap before the exemptions: an edge declares it, or no line names
it), anchor-not-live, path-untracked, suite-unaudited, suite-unregistered, suite-always-on, star-row-readable-suite,
star-row-unreadable-members, star-row-tracked-suite (git tracks the suite's input, so it is not a suite with no inputs even if the
file is missing, dangling or a directory link). Delete the row.

RATCHET (S4 index completion PR3a, #10448; the amendment of ADR-276). `ratchet` is the audit as a CI check that is green on a tree whose audit exits 1: the live gap
set (after the --accept exemptions) must EQUAL a committed, shrink-only baseline (scripts/ci-pr-affected-audit.baseline.tsv, repo-relative, one
`suite<TAB>path` line per pair, each field written by quote_field, sorted and unique in the C locale, with a final newline). What it proves is the
literal-name completeness over what the audit reads (REACH above): necessary but not sufficient, and never "index complete". It is advisory until a later PR
makes its CI context required. The live set and the baseline are read from the checkout; the base (HEAD^1, or --base REF) is read for the baseline-state table
(adoption, deletion), the growth rule, the cause text of a new pair, the oracle notice and the merge-base copy of the lint-ratchet.py helper (on a developer
checkout HEAD^1 is just the previous local commit, so those are not meaningful there; read the CI result or pass --base).
  EXIT CODES  0 clean; 1 drift (a verdict about the tree); 2 infrastructure (the check could not be trusted). A usage error is argparse's rc 2 and prints no marker.
  ORDER  every exit-2 condition comes before every exit-1 verdict, so infrastructure is never a verdict: the selector (rc, hang), then the FLOORS on what it
         printed (exactly one AFFECTED_SUMMARY naming fallback= and of=; fallback=none; no other non-blank line; no short row; every row within the selector's
         grammar: five columns, a selected flag of 0 or 1 and a reason that is one of the non-empty `_AC_CLASS="..."` literals of the tracked scripts/test-all.sh,
         read at run time; the AFFECTED_SELECTED row count equals its of=; no tracked input unreadable for a reason other than absence (EACCES, EIO: floor-unreadable);
         at least one suite and one file read), then the base (resolved with git, its lint-ratchet.py loaded from the BASE commit, not the PR tree: a PR cannot weaken
         the helper and the baseline together; a base without the file, or one that does not compile, is internal). Then the verdicts, each class printed and the first one named in the marker: unaudited suite; a `*`
         accept row for a readable suite; a stale or invalid accept row; a new pair (or baseline-deleted); a stale baseline line; a duplicate baseline
         line; a baseline not in C-locale order or without its final newline; a baseline line the base does not have (grown).
  BASELINE STATE  base absent / HEAD present: adoption, passes when live equals the baseline. Base present / HEAD absent: passes only when nothing is live
         (the strict-zero end state), else baseline-deleted. Absent at both: strict zero (a live pair is a new pair). Present at both: equality, plus the
         growth rule as a GLOBAL pair-set check (`head lines - base lines` must be empty, so a swap, a new suite and a count that did not move are all refused).
  The baseline is compared as OPAQUE rendered lines (there is no baseline parser); the failure text names the suite, the path and the referencing file:line, gives the two
  remedies (declare an edge only when the suite really reads the file; add an anchor-keyed accept row when it merely names it) and never offers a way to add a pair.
  --print-baseline writes ONLY the baseline bytes to stdout (the marker and diagnostics go to stderr, nothing is written to disk): with no baseline file it prints every
  live pair; once one exists it prints only the baseline lines that are still live (prune-only), so a regeneration can shrink the file and never grow it. It refuses
  (exit 2, census-degraded) when the census is degraded (an unaudited suite, a stale or malformed accept row): a file printed from it would lose live pairs.
  --report FILE also writes the full, uncapped failure text (stdout prints the first 25 entries of each class and a count): on a verdict, on an exit-2 stop (the reason line and
  the marker) and under --print-baseline (the notice and the marker); a path that cannot be written is one stderr line, never the verdict. The last stdout line is
  `SOLEUR_PR_AFFECTED_RATCHET exit=<0|1|2> reason=<token> live=<n> baseline=<n>`; `oracle-inputs-changed: <files>` is printed, non-blocking, when the diff to the base
  touches the check's own oracle: .github/workflows/ci.yml, this script, plugins/soleur/scripts/lint-ratchet.py, the accept file, scripts/lib/test-affected-paths.sh,
  scripts/test-all.sh or the baseline. A new accept row is therefore announced, and is the drain tool, not a verdict.
  EXIT-2 REASONS  selector-failed, selector-timeout, floor-summary, floor-fallback, floor-extra, floor-short-row, floor-bad-row, floor-rows-vs-of, floor-unreadable,
  floor-no-suites, base-unresolved, baseline-unreadable, accept-unreadable, census-degraded (--print-baseline only), internal.

EXIT CODES (collect, ejections, aggregate, audit): 0 done and clean; 1 audit found gaps, unaudited suites or stale accept rows; 2 usage or
a value error (a malformed --since, an unknown status, an incomplete aggregate directory); 3 a remote or local READ
failed (git, the selector, a file the audit must read, the --accept or --list file); 4 an internal error. `verdict` and `cp-upper` exit 0 whatever they print: read `computed=GO|NO-GO|UNDECIDED`
on stdout, the exit code carries no verdict. An uncaught Python error is rc 4, never rc 1.
"""
import argparse
import errno
import hashlib
import json
import math
import os
import re
import stat
import subprocess
import sys
import time
import types
from bisect import bisect_left
from collections import Counter

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
    "critical-css-gate", "affected-index-ratchet",
))
FAIL_LINE = re.compile(r"^\[(?:FAIL|KILLED)\] ([A-Za-z0-9._/+-]+) \((?:\d+ms|exit=)")
FULL_EVENTS = ("merge_group", "push")
COMMIT_FILES_CAP = 3000
ANSI = re.compile(r"\x1b\[[0-9;]*[mGKHF]")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ")


class ReadError(Exception):
    """A remote or local read failed. Callers class the unit not-evaluable; it is never 'nothing found'."""


class ReadTimeout(ReadError):
    """A subprocess outlived its timeout (the ratchet maps one on the selector to selector-timeout)."""


try:
    GH_TIMEOUT = float(os.environ.get("PR_AFFECTED_REPLAY_GH_TIMEOUT", "180"))
    SELECT_TIMEOUT = float(os.environ.get("PR_AFFECTED_REPLAY_SELECT_TIMEOUT", "900"))
    GIT_TIMEOUT = float(os.environ.get("PR_AFFECTED_REPLAY_GIT_TIMEOUT", "120"))
except ValueError as _e:  # import time is before main()'s handlers: a bad seam value is a usage error (rc 2), never rc 1
    print("replay: PR_AFFECTED_REPLAY_GH_TIMEOUT / _SELECT_TIMEOUT / _GIT_TIMEOUT must be numbers: %s" % _e, file=sys.stderr)
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
        raise ReadTimeout("%s timed out after %ss" % (cmd[0], timeout))
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
        with open(p) as fh:
            for line in fh:
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
    with open(path, "a") as out:
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

    with open(path, "a") as out:
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


# The whole-line comment marker of a file's OWN language, by extension of its real path. A line that is a comment in a different
# language is not blanked (`// docs/a.md` in a .sh is a command word and a path), and an extension that is not listed strips
# nothing: over-reporting is the audit's safe direction. Block comments, docstrings and heredoc bodies are a declared over-report.
COMMENT_PREFIX = {
    ".sh": "#", ".bash": "#", ".py": "#", ".rb": "#", ".yml": "#", ".yaml": "#",
    ".ts": "//", ".tsx": "//", ".js": "//", ".jsx": "//", ".mjs": "//", ".cjs": "//", ".mts": "//", ".cts": "//",
}


def comment_prefix(path):
    return COMMENT_PREFIX.get(os.path.splitext(path)[1], "")


def strip_comments(text, prefix):
    """Blank whole-line comments of the file's own language (`prefix`, from comment_prefix; empty strips nothing; only space and tab may
    precede the marker, as in bash): a path named only in a comment is a mention, not a read. Lines are split on "\\n" only (bash does not split on a vertical tab, a form feed, a lone
    carriage return or U+2028); a carriage return is removed only when it directly precedes the line feed (CRLF), a lone one is an
    ordinary character. A stripped line becomes an empty line, so every line keeps its number."""
    lines = text.replace("\r\n", "\n").split("\n")
    if not prefix:
        return "\n".join(lines)
    return "\n".join("" if line.lstrip(" \t").startswith(prefix) else line for line in lines)


def tracked_files(root):
    """Every tracked path, read with -z as BYTES: without -z git prints a name holding a non-ASCII byte as a quoted ASCII string, which
    no read can ever match, and text mode would turn a carriage return in a name into a line feed. Decoded like the files are
    (UTF-8, undecodable bytes replaced), so a name and a mention of it agree."""
    return {f.decode("utf-8", errors="replace") for f in run(["git", "ls-files", "-z"], cwd=root, binary=True).stdout.split(b"\0") if f}


GLOB_CHARSET = re.compile(r"[^A-Za-z0-9_./*-]")


def edge_hit(pt, path):
    """True exactly when the selector would select the suite for a diff whose only name is `path`: `_diff_touches` with the single
    entry `pt`, over `_diff_edge_hit` (one function, one call site; a bash-versus-python differential in the suite pins it to the
    real functions). An entry WITHOUT a `^` is a plain substring of the path (a non-caret `glob:` entry is therefore dead, and the
    empty entry matches everything). A `^` entry is `glob:<head>/<tail>` (a bash `[[ == ]]` glob over the whole path, `*` crosses
    `/`), `dir/` (a prefix) or a file (exact equality). Nothing is a regex: a path holding ( ) [ ] + $ matches itself, and `^a.sh`
    does not match `a.sh.bak`. EVERY malformed glob shape matches (a glob edge can only widen a selection): a byte outside
    [A-Za-z0-9_./*-], a head that is absolute, begins with `./` or `../`, or holds `//`, `/./` or `/../`, a head not ending in `/`, a tail
    ending in `/`, a tail without `*`. A tracked name holding a TAB or a double quote is framed differently in the selector's diff blob and
    is not modelled (no such name is tracked)."""
    if not pt.startswith("^"):
        return pt in path
    e = pt[1:]
    if e.startswith("glob:"):
        g = e[len("glob:"):]
        if GLOB_CHARSET.search(g):
            return True
        head = g.split("*", 1)[0]
        if head.startswith("/"):        # the head is not repo-relative: six shapes, one line each
            return True
        if head.startswith("./"):
            return True
        if head.startswith("../"):
            return True
        if "//" in head:
            return True
        if "/./" in head:
            return True
        if "/../" in head:
            return True
        if not head.endswith("/"):      # head not /-terminated
            return True
        tail = g[len(head):]
        if tail.endswith("/"):          # unmatchable tail
            return True
        if "*" not in tail:             # a tail without a wildcard
            return True
        # `*` matches any run of characters, `/` included, and a run of stars is one star: split on `*`, anchor the first and the last
        # segment and find the middle ones in order. Linear in the path, where the equivalent regex is polynomial in the number of stars.
        segs = g.split("*")
        first, last = segs[0], segs[-1]
        if len(path) < len(first) + len(last) or not path.startswith(first) or not path.endswith(last):
            return False
        pos, stop = len(first), len(path) - len(last)
        for seg in segs[1:-1]:
            k = path.find(seg, pos, stop)
            if k < 0:
                return False
            pos = k + len(seg)
        return True
    if e.endswith("/"):
        return path.startswith(e)
    return path == e


def suite_file(root, pattern):
    """The suite's own file is the FIRST pattern of its selector row (`^path`, dots literal). None when that is not a
    readable file (a directory suite, a runner trigger, or a pattern the selector derived differently): the caller counts it unaudited."""
    path = pattern[1:] if pattern.startswith("^") else pattern
    full = os.path.join(root, path)
    return full if path and path not in RUNNER_TRIGGERS and not path.endswith("/") and os.path.isfile(full) else None


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
# A `source X` / `. X` line. group 1 is the operand prefix (`$(dirname "$0")`, `$(dirname "${BASH_SOURCE[0]}")` or `$VAR` / `${VAR}`), group 2 the
# rest of the path (it starts with `/` after a prefix). The keyword must not be glued to a word or to a dot (`resource x.sh` and a prose
# `see. lib/x.sh` are not hops), and the blank after it is a space or tab (never a newline). Only .sh and .bash targets are followed. A prefix
# is recognised only when a `/` follows it (the lookahead), which also keeps one long `source $<identifier>` token linear instead of quadratic.
SOURCE_HOP = re.compile(
    r"""(?<![\w.])(?:source|\.)[ \t]+["']?"""
    r"""(\$\(dirname[ \t]+"?(?:\$0|\$\{BASH_SOURCE\[0\]\})"?\)(?=/)|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(?=/))?"""
    r"""([A-Za-z0-9_./-]+\.(?:sh|bash))""")
# The operand prefixes that stand for the INCLUDING file's directory (the selector's `_affected_edge_token` resolves `$HERE`, `$SCRIPT_DIR`
# and both `$(dirname ...)` spellings that way; `$DIR` is added). Every other prefix (`$REPO_ROOT`, `$ROOT_DIR`, an unknown `$X`, no prefix)
# is tried at the repo root; only a TRACKED target is ever read, so a wrong guess costs nothing.
HOP_DIR_VARS = frozenset(("SCRIPT_DIR", "HERE", "DIR"))
HOP_DEPTH = 8    # source-hop levels followed from a suite input (the selector reads distance 0 to 7: the audit reads one level further, the safe direction)
WALK_DEPTH = 8   # naming-walk levels followed over code files the selector row lists
# The files the naming walk may read: code, by extension. A data file in `pats` is a declared input the audit checks but never scans.
CODE_EXT = frozenset((".sh", ".bash", ".py", ".ts", ".tsx", ".jsx", ".js", ".mjs", ".cjs", ".mts", ".cts", ".rb"))
# bun's test discovery: *.test.* *_test.* *.spec.* *_spec.* over js, jsx, ts, tsx and the module-flavoured mjs, cjs, mts, cts. A
# SUPERSET on purpose: bunfig `pathIgnorePatterns` are not applied (over-scanning is the safe direction).
BUN_TEST = re.compile(r"[._](?:test|spec)\.(?:js|jsx|ts|tsx|mjs|cjs|mts|cts)$")
MAX_READ = 8 * 1024 * 1024   # a suite or library larger than this is not read (unreadable:), whatever it is


def views(text):
    """-> (full, light), equal length: `full` is `text` with every printf escape and attached short option replaced by spaces;
    `light` is `text` as written (see the boundary note above). Both are the same object when there is nothing to blank."""
    full = SHORT_OPTION.sub(lambda m: " " * len(m.group(0)), ESCAPE.sub(lambda m: " " * len(m.group(0)), text))
    return (text, text) if full == text else (full, text)


def boundary(text, i):
    """True when a match at offset i of ONE view of the text starts a path component (see WORD_CHARS)."""
    return i == 0 or WORD.match(text[i - 1]) is None


QUOTE_U = re.compile("[\u0080-\u009f\u00ad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u2064\u2066-\u2069\ufeff]")   # C1, soft hyphen, Arabic letter mark, Mongolian vowel separator, zero-width/word joiners, separators, bidi controls


def quote_field(s, comma=False):
    """`s` for a line of audit output. A backslash, a C0 control, DEL and, in a comma-joined list, the comma become \\xHH. These become \\uXXXX: a C1 control (U+0080-009F), U+00AD, U+061C, U+180E, the zero-width and joiner characters (U+200B-200F, U+2060-2064, U+FEFF), U+2028/2029 and the bidi controls (U+202A-202E, U+2066-2069). No tracked name can add a line, a column or a list member to the output or reorder it, and the escape is injective (the backslash itself is escaped). Other invisible or look-alike Unicode is printed as is."""
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
    written (`raws`), its two views (`views`), the RAW `source` operands it holds (`hops`: (prefix, rest) pairs, resolved per call against
    the including file's logical path) and the tracked paths it names (`refs`), keyed on the FULL path (two libraries named helper.sh in
    different directories are two entries). `ops` counts every start candidate and every trie step, so a test can
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
        self.faults = set()   # real paths whose read failed with an OSError other than ENOENT (EACCES, EIO ...): the census is incomplete, not "unaudited"
        self.raws = {}
        self.views = {}
        self.refs = {}
        self.hops = {}

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
        raw = strip_comments(read_bytes(path, base).decode("utf-8", errors="replace"), comment_prefix(path))
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
    except ReadError as e:
        if isinstance(e.__context__, OSError) and e.__context__.errno not in (None, errno.ENOENT):
            index.faults.add(real)
        if bad is None:
            raise
        if path not in bad:
            bad.append(path)
        return None
    return real, full, light, index.raws[real]


def hop_targets(rel, raws, tracked):
    """The tracked, repo-relative targets of the `source` operands `raws` of the file whose LOGICAL repo-relative path is `rel`, in text
    order. A prefix that stands for the including file's directory resolves against it, every other prefix and a bare path against the
    repo root; a target that is not tracked, is a runner trigger or leaves the tree is dropped."""
    out = []
    for pre, rest in raws:
        if pre:
            if not rest.startswith("/"):
                continue
            home = os.path.dirname(rel) if pre.startswith("$(dirname") or pre.strip("${}") in HOP_DIR_VARS else ""
            q = os.path.normpath(os.path.join(home, rest.lstrip("/")))
        elif rest.startswith("/"):
            continue
        else:
            q = os.path.normpath(rest)
        if q in tracked and q not in RUNNER_TRIGGERS and q not in out:
            out.append(q)
    return out


def hops_of(index, real, rel):
    """The tracked files the file at `real` (logical path `rel`) sources. The raw matches are memoised per real path, unexcluded;
    the resolution is per call, because it depends on the logical path the file was reached by."""
    raws = index.hops.get(real)
    if raws is None:
        raws = index.hops[real] = [(m.group(1) or "", m.group(2)) for m in SOURCE_HOP.finditer(index.raws[real])]
    return hop_targets(rel, raws, index.tracked)


def source_closure(root, got, rel, index, bad):
    """-> [try_read() tuple]: `got` (reached as the repo-relative path `rel`), then the files it sources, then theirs, breadth first, in
    discovery order, to HOP_DEPTH levels. A visited set keyed on the real path ends a cycle. A tracked target that cannot be read is
    listed in `bad` (the suite is then unaudited, never clean)."""
    out, visited, level = [got], {got[0]}, [(got, rel)]
    for _ in range(HOP_DEPTH):
        nxt = []
        for g, r in level:
            for q in hops_of(index, g[0], r):
                path = os.path.normpath(os.path.join(root, q))
                real = os.path.realpath(path)
                if real in visited:
                    continue
                visited.add(real)
                h = try_read(index, path, bad, root)
                if h is not None:
                    out.append(h)
                    nxt.append((h, q))
        level = nxt
        if not level:
            break
    return out


def suite_texts(root, inputs, index, bad=None):
    """-> [(real path, full view, light view, text as written)]: the suite's own files, each followed by the libraries it sources (the
    `source` closure to HOP_DEPTH levels, breadth first, discovery order), each real file once. A file that cannot be read is skipped
    and listed in `bad` (ReadError when `bad` is None). A sourced path counts only when it is a TRACKED path (so the count does not
    depend on untracked files in the work tree); one that is not a readable regular file inside the tree (a dangling symlink, a
    directory, a file deleted from the work tree) is an unreadable file; a sourced name that is not tracked is not read. This is the
    closure only: the naming walk over the selector row's code files is reach_texts()."""
    out, seen = [], set()
    for p in inputs:
        path = os.path.normpath(p)
        got = try_read(index, path, bad, root)
        if got is None:
            continue
        for g in source_closure(root, got, os.path.relpath(path, root), index, bad):
            if g[0] not in seen:
                seen.add(g[0])
                out.append(g)
    return out


def code_pats_of(pats, index):
    """The tracked code files a selector row lists as exact `^file` entries, in order, once each: the nodes of the naming walk. A
    `glob:` or `dir/` entry, a non-caret entry, a data file and a runner trigger are never a node."""
    out, seen = [], set()
    for pt in pats:
        e = pt[1:]
        if (pt.startswith("^") and e and not e.startswith("glob:") and not e.endswith("/") and e not in RUNNER_TRIGGERS
                and os.path.splitext(e)[1] in CODE_EXT and e in index.tracked and e not in seen):
            seen.add(e)
            out.append(e)
    return out


def reach_texts(root, inputs, pats, index, bad):
    """suite_texts() plus the naming walk: from the files read so far, every code file the selector row lists in `pats` (code_pats_of)
    that one of them names literally is read, level by level to WALK_DEPTH (sorted within a level); after each level the source closure
    of its files is read too, and both feed the next level's naming (the selector expands every file's edges, so a library a walk file
    sources can name the next code pat). All state is row-local (`seen` is per call; PathIndex only memoises contents), so a verdict
    never depends on the order of the rows."""
    out = suite_texts(root, inputs, index, bad)
    code = set(code_pats_of(pats, index))
    if not code:
        return out
    seen, frontier = {t[0] for t in out}, list(out)
    for _ in range(WALK_DEPTH):
        named = set()
        for g in frontier:
            named |= refs_of(index, g) & code
        level = []
        for q in sorted(named):
            path = os.path.join(root, q)
            if os.path.realpath(path) in seen:
                continue
            got = try_read(index, path, bad, root)
            if got is not None and got[0] not in seen:
                seen.add(got[0])
                out.append(got)
                level.append((got, q))
        frontier = [got for got, _ in level]
        for got, q in level:
            for g in source_closure(root, got, q, index, bad)[1:]:
                if g[0] not in seen:
                    seen.add(g[0])
                    out.append(g)
                    frontier.append(g)
        if not frontier:
            break
    return out


def refs_of(index, got):
    """The tracked paths one file (a try_read() tuple) names, memoised on the real path and UNEXCLUDED: the suite's own path is
    dropped by the caller, per call, because the same library is read for other suites that do name it. The ONE scan site of the
    audit: suite_refs() and the naming walk both read through it."""
    r = index.refs.get(got[0])
    if r is None:
        r = index.refs[got[0]] = scan_views(index, got[1], got[2])
    return r


def suite_refs(root, suite, inputs, index, texts=None, bad=None):
    """Tracked repo paths that the texts of this suite name literally. `texts` is reach_texts() (the suite's files, the libraries they
    source and the code files its selector row lists and the texts name); without it only the suite_texts() closure is read, which is
    what the memoisation fixtures want. The per-file result is memoised UNEXCLUDED: the suite's own path is dropped here, per call,
    because the same library is read for other suites that do name it."""
    named = set()
    for got in (texts if texts is not None else suite_texts(root, inputs, index, bad)):
        named |= refs_of(index, got)
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
    1, 2, ... over the files in the canonical read order (the suite file, its source closure, then the naming-walk files; see REACH), so two
    identical reading lines are two rows.
    `lineno` counts physical lines (a comment line is blanked, never removed)."""
    count, out = {}, []
    for q, no, written in boundary_lines(texts, path):
        text = " ".join(written.split())
        a = hashlib.sha256(text.encode()).hexdigest()[:12]
        count[a] = count.get(a, 0) + 1
        out.append((a, count[a], q, no, text))
    return out


def load_accept(path, base=None):
    """Exemptions: see the ACCEPT FILE section of --help. A missing file is no exemptions (one stderr line says so); a file that
    cannot be read is a ReadError (rc 3); a malformed row is a ValueError (rc 2) that names the failing column. With `base` (the ratchet's default
    accept file inside the checkout) the file is read through read_bytes: a symlink that leaves `base`, a device or an oversized file is refused.
    -> {suite: {path: [(anchor, ordinal, reason)]}}"""
    acc = {}
    if not os.path.exists(path):
        print("replay: --accept %s does not exist: no exemptions" % path, file=sys.stderr)
        return acc
    try:
        if base is None:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        else:
            text = read_bytes(path, base).decode("utf-8")
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
      pair_texts  {label: {path: reach_texts() of the rows that left the path undeclared}} for the gaps (ref_lines)
      unaudited   [(label, why, quoted)] unique; `quoted` says `why` was already passed through quote_field
      stale       [(label, path, anchor/ordinal, why)], sorted and unique
      extra       the selector lines that are not AFFECTED_SELECTED rows (AFFECTED_SUMMARY, AFFECTED_FALLBACK)
      registered  {label: reason} (`always_on` when any row of the label is)
      labels      every label seen   refs  distinct (label, path) pairs found before any exemption   files_read  distinct real files read"""

    def __init__(self, root, index):
        self.root, self.index = root, index
        self.suites = self.accepted = self.refs = 0
        self.gaps, self.miss, self.registered, self.pair_texts = {}, {}, {}, {}
        self.labels, self.short_rows, self.always_on_labels, self.accepted_unread_labels = set(), set(), set(), set()
        self.unaudited, self.stale, self.extra = [], [], []
        self.grammar = []   # (selected flag, reason, column count) of every row with at least five columns, for the ratchet's row-grammar floor

    @property
    def gap_refs(self):
        return sum(len(v) for v in self.gaps.values())

    @property
    def files_read(self):
        return len(self.index.raws)

    @property
    def always_on(self):
        return len(self.always_on_labels)

    @property
    def unaudited_labels(self):
        return len({u[0] for u in self.unaudited})

    @property
    def audited(self):
        """Labels that are none of always_on, unaudited or accepted-without-reading: a set difference, so a label in two states (a short
        row beside an always_on row) is subtracted once and the count cannot go negative."""
        return len(self.labels - self.always_on_labels - {u[0] for u in self.unaudited} - self.accepted_unread_labels)

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
    """The accept rows of one readable suite against its live gaps -> (stale, accepted, kept). `texts_of[path]` is the reach_texts()
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
    label once, so the SET of results does not depend on row order (the printed order of paths does): a label is always_on if any of its rows is; a path is a gap of the label when
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
        c.grammar.append((f[2], f[3], len(f)))
        g = groups.setdefault(label, {"always_on": False, "reason": f[3], "rows": []})
        if f[3] == "always_on":
            g["always_on"] = True
        g["reason"] = f[3]
        g["rows"].append(f[4].split("|"))
    for label, g in groups.items():
        g["rows"].sort()   # ordinals must not depend on the order the selector printed a label's rows: the whole pattern list is the key
        c.registered[label] = "always_on" if g["always_on"] else g["reason"]
        if g["always_on"]:
            c.always_on_labels.add(label)
            continue
        rules = accept.get(label, {})
        bad, dead, ok, found = [], [], [], set()
        for pats in g["rows"]:
            inputs = suite_inputs(root, pats[0], index)
            if inputs is None:
                dead.append(pats[0])
                continue
            texts = reach_texts(root, inputs, pats, index, bad)
            refs = suite_refs(root, label, inputs, index, texts)
            found.update(refs)
            ok.append((texts, [r for r in refs if not any(edge_hit(pt, r) for pt in pats)]))
        c.refs += len(found)
        if not ok:   # no row has an input to read
            tracked_suite = any(has_tracked_input(index, d) for d in dead)
            if "*" in rules and not tracked_suite:
                c.accepted += 1
                c.accepted_unread_labels.add(label)
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


# ---- ratchet (S4 index completion PR3a): the audit as a check that is green on a tree the audit fails -----------------------------------------------
RATCHET_BASELINE = "scripts/ci-pr-affected-audit.baseline.tsv"
RATCHET_ACCEPT = "scripts/ci-pr-affected-audit.accept.tsv"
RATCHET_LINT = "plugins/soleur/scripts/lint-ratchet.py"
RATCHET_TEST_ALL = "scripts/test-all.sh"
RATCHET_PATHS_LIB = "scripts/lib/test-affected-paths.sh"
RATCHET_MARKER = "SOLEUR_PR_AFFECTED_RATCHET"
RATCHET_CAP = 25
# The files whose change in a diff makes the check's OWN oracle part of that diff (a non-blocking notice, never a verdict): the workflow, this script, the
# helper (its merge-base copy decides the base text, but the PR-tree copy is what a later run trusts), the accept file (a new row exempts a new pair), the path
# library and the runner (they decide what the selector prints, so what is "live") and the baseline.
RATCHET_ORACLE = (".github/workflows/ci.yml", "scripts/ci-pr-affected-replay.py", RATCHET_LINT, RATCHET_ACCEPT, RATCHET_PATHS_LIB, RATCHET_TEST_ALL, RATCHET_BASELINE)
STAR_WHYS = ("star-row-readable-suite", "star-row-unreadable-members", "star-row-tracked-suite")
RATCHET_REMEDY_NEW = (
    "remedy: declare the path in AFFECTED_<LABEL>_PATHS in scripts/lib/test-affected-paths.sh only when the suite really reads or executes the file "
    "(that is what the selector must know); editing that file runs the full battery once",
    "remedy: or add an anchor-keyed accept row to " + RATCHET_ACCEPT + " only when the suite merely names the file (a message, a fixture it writes "
    "into a scratch tree, a negative-test string); the reason names the line kind",
    "remedy: accept row shape: suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason> (anchor and ordinal are on the ref line above)",
    "remedy: an accept row on a file the suite really reads is a false negative once the lever flips; no automated control checks that the suite does not "
    "read this file, this check does not verify it, and a CODEOWNERS entry routes the review but no required review exists in this repository's ruleset",
    "remedy: a baseline row cannot be added",
)
QUOTE_CTL = re.compile("[\x00-\x08\x0a-\x1f\x7f]")
AC_CLASS = re.compile(r'(?<![A-Za-z0-9_])_AC_CLASS="([^"]+)"')


class RatchetInfra(Exception):
    """Infrastructure, not a verdict: the ratchet exits 2 with `reason`, a fixed token that never carries a path, a ref or a SHA."""

    def __init__(self, reason, message):
        super().__init__(message)
        self.reason = reason


def no_suites(c):
    """True, after one stderr line, when the selector printed no AFFECTED_SELECTED row: a census over nothing proves nothing (audit shares this)."""
    if c.suites == 0:
        print("replay audit: the selector printed no AFFECTED_SELECTED rows", file=sys.stderr)
        return True
    return False


def ratchet_reasons(root, tracked=None):
    """The reasons the selector assigns a row: every non-empty `_AC_CLASS="<literal>"` assignment on a non-comment line of the tracked scripts/test-all.sh,
    read at run time through the audit's confined reader (never listed here). An unreadable or untracked file, or a set that lacks `always_on`, is exit 2."""
    if tracked is not None and RATCHET_TEST_ALL not in tracked:
        raise RatchetInfra("internal", "cannot derive the selector's row grammar: %s is not tracked" % RATCHET_TEST_ALL)
    try:
        text = read_bytes(os.path.join(root, RATCHET_TEST_ALL), root).decode("utf-8", errors="replace")
    except ReadError as e:
        raise RatchetInfra("internal", "cannot derive the selector's row grammar from %s: %s" % (RATCHET_TEST_ALL, quote_field(str(e))))
    found = set()
    for line in text.split("\n"):
        if not line.lstrip().startswith("#"):
            found.update(AC_CLASS.findall(line))
    if "always_on" not in found:
        raise RatchetInfra("internal", "cannot derive the selector's row grammar: %s names no _AC_CLASS=\"always_on\" literal" % RATCHET_TEST_ALL)
    return found


def ratchet_floors(c):
    """Every input the ratchet cannot trust is exit 2, never a verdict. `c.extra` is a CLOSED set: after the AFFECTED_SELECTED rows the real selector
    prints exactly one AFFECTED_SUMMARY on stdout in this mode (a measurement, plan Phase 0), so any other non-blank line (AFFECTED_FALLBACK,
    AFFECTED_UNRESOLVED, AFFECTED_RUNNER_IN_SCOPE, AFFECTED_DIVERGENT, an unknown prefix, a stray line, a space-prefixed row) is a hazard. A row is held to the
    selector's grammar (five columns, a selected flag of 0 or 1, a reason the selector assigns: ratchet_reasons)."""
    summaries = [x for x in c.extra if x.startswith("AFFECTED_SUMMARY ")]
    if len(summaries) != 1:
        raise RatchetInfra("floor-summary", "want exactly one AFFECTED_SUMMARY line, the selector printed %d" % len(summaries))
    fb = re.search(r"\bfallback=(\S+)", summaries[0])
    if fb is None:
        raise RatchetInfra("floor-summary", "the AFFECTED_SUMMARY line names no fallback=")
    if fb.group(1) != "none":
        raise RatchetInfra("floor-fallback", "the selector fell back (fallback=%s) and printed no per-suite decision" % quote_field(fb.group(1)))
    others = [x for x in c.extra if not x.startswith("AFFECTED_SUMMARY ")]
    if others:
        raise RatchetInfra("floor-extra", "%d unexpected selector line(s), the first starts %s" % (len(others), quote_field(others[0][:24])))
    if c.short_rows:
        raise RatchetInfra("floor-short-row", "%d AFFECTED_SELECTED row(s) too short to name their edges" % len(c.short_rows))
    reasons = ratchet_reasons(c.root, c.index.tracked)
    bad = [g for g in c.grammar if g[0] not in ("0", "1") or g[1] not in reasons or g[2] != 5]
    if bad:
        raise RatchetInfra("floor-bad-row", "%d AFFECTED_SELECTED row(s) fail the selector grammar (five columns, selected 0 or 1, a reason the selector assigns)" % len(bad))
    of = re.search(r"\bof=(\d+)\b", summaries[0])
    if of is None:
        raise RatchetInfra("floor-summary", "the AFFECTED_SUMMARY line names no of=<n>")
    if c.suites != int(of.group(1)):
        raise RatchetInfra("floor-rows-vs-of", "the selector printed %d AFFECTED_SELECTED row(s) but its summary says of=%s" % (c.suites, of.group(1)))
    if c.index.faults:
        raise RatchetInfra("floor-unreadable", "%d tracked input(s) could not be read (a permission or I/O error, not a missing file): the census is incomplete" % len(c.index.faults))
    if not c.suites:
        raise RatchetInfra("floor-no-suites", "a census over zero suites proves nothing")
    if c.files_read == 0:
        raise RatchetInfra("floor-no-suites", "a census that read zero files proves nothing")


def ratchet_load(root, sha, env):
    """The helpers of plugins/soleur/scripts/lint-ratchet.py AS THE MERGE BASE HAS THEM (`git show <sha>:path`, compiled into a module that has no file and
    no .pyc; ADR-290 does the same), never the PR tree's copy: one PR could otherwise weaken the helper and the baseline together. A base without the file, or
    one that does not compile, is exit 2 internal."""
    hint = "a PR that moves that helper must land the move first"
    p = run(["git", "show", "%s:%s" % (sha, RATCHET_LINT)], cwd=root, env=env, check=False, timeout=GIT_TIMEOUT, binary=True)
    if p.returncode != 0:
        raise RatchetInfra("internal", "the merge base has no %s: %s" % (RATCHET_LINT, hint))
    mod = types.ModuleType("lint_ratchet")
    mod.__file__ = os.path.join(root, RATCHET_LINT)
    try:
        exec(compile(p.stdout, "<merge-base>/" + RATCHET_LINT, "exec", dont_inherit=True), mod.__dict__)
    except Exception as e:
        raise RatchetInfra("internal", "the merge-base copy of %s does not load (%s): %s" % (RATCHET_LINT, type(e).__name__, hint))
    for name in ("baseline_at", "InfraError"):
        if getattr(mod, name, None) is None:
            raise RatchetInfra("internal", "%s has no %s at the merge base: %s" % (RATCHET_LINT, name, hint))
    return mod


def ratchet_base(root, ref, rel):
    """-> (sha, the baseline text at the base or None when the base has no such file). An unresolvable base is exit 2, never an adoption."""
    env = dict(os.environ)
    for k in GIT_LOCATION_VARS:
        env.pop(k, None)   # the helpers' git calls ignore any inherited git location, like run() does
    if ref.startswith("-"):
        raise RatchetInfra("base-unresolved", "--base %s looks like an option, not a ref" % quote_field(ref))
    p = run(["git", "rev-parse", "--verify", "--end-of-options", ref + "^{commit}"], cwd=root, env=env, check=False, timeout=GIT_TIMEOUT)
    sha = p.stdout.strip() if p.returncode == 0 else ""
    if not sha:
        raise RatchetInfra("base-unresolved", "%s does not resolve to a commit (a root commit or a shallow clone): fetch more history, fetch-depth: 2 is the minimum" % quote_field(ref))
    mod = ratchet_load(root, sha, env)
    try:
        return sha, mod.baseline_at(root, sha, rel, env)
    except mod.InfraError as e:
        raise RatchetInfra("base-unresolved", "%s" % quote_field(str(e)))


def ratchet_changed(root, sha):
    """-> (added, touched): the paths the committed diff from the base to HEAD adds, and all it names."""
    raw = run(["git", "diff", "--name-status", "-z", "--no-renames", sha, "HEAD", "--"], cwd=root, binary=True, timeout=GIT_TIMEOUT).stdout
    toks = [t.decode("utf-8", errors="replace") for t in raw.split(b"\0") if t]
    added, touched = set(), set()
    for status, path in zip(toks[0::2], toks[1::2]):
        touched.add(path)
        if status == "A":
            added.add(path)
    return added, touched


def ratchet_oracle(touched, rel):
    """The files whose change makes this check's own oracle part of the diff (a non-blocking notice, never a verdict); --baseline may name another file."""
    return [p for p in dict.fromkeys(RATCHET_ORACLE + (rel,)) if p in touched]


def ratchet_read(root, rel):
    """The baseline text of the checkout, or None when the file is absent. Read through the audit's confined reader: a symlink that leaves the tree, a
    device or an oversized file is a ReadError (exit 2), never printed."""
    try:
        return read_bytes(os.path.join(root, rel), root).decode("utf-8", errors="replace")
    except ReadError as e:
        if isinstance(e.__context__, FileNotFoundError):
            return None
        raise


def baseline_split(text):
    """-> (lines, final_newline) of a baseline text: the lines are opaque."""
    if text is None:
        return [], True
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines, text == "" or text.endswith("\n")


def shown(line):
    """A baseline line for the failure text: as written, unless it holds a control character (other than the TAB column separator) or a character quote_field escapes."""
    return quote_field(line) if QUOTE_CTL.search(line) or QUOTE_U.search(line) else line


def ratchet_new_entry(c, pair, added, touched):
    """The failure text of one new pair: suite, path, referencing file:line, then the cause (precedence: the change added the file; else it edited the file
    that names it; else neither), then the line(s) an accept row is keyed on."""
    s, p = pair
    refs = c.ref_lines(s, p)
    q = quote_field
    entry = ["new-pair\t%s\t%s\t%s" % (q(s), q(p), "%s:%d" % (q(refs[0][2]), refs[0][3]) if refs else "-")]
    edited = [r[2] for r in refs if r[2] in touched]
    if p in added:
        cause = "your change added file %s, which suite %s names" % (q(p), q(s))
    elif edited:
        cause = "your change edited %s, which suite %s reads and which names %s" % (q(edited[0]), q(s), q(p))
    else:
        cause = ("your change touched neither %s nor %s (main is already red for this pair, or a covering edge was removed): rebase, then declare the "
                 "edge or add an accept row" % (q(refs[0][2]) if refs else "the suite", q(p)))
    entry.append("  cause: " + cause)
    for anchor, ordinal, rel, no, text in refs[:3]:
        entry.append("  ref\t%s:%d\t%s/%d\t%s" % (q(rel), no, anchor, ordinal, q(text)))
    return entry


def ratchet_marker(code, reason, st):
    return "%s exit=%d reason=%s live=%d baseline=%d" % (RATCHET_MARKER, code, reason, st["live"], st["baseline"])


def ratchet_report(a, lines):
    """--report FILE: written on every exit path that reaches it (a verdict, an exit-2 stop, --print-baseline). A path that cannot be written costs one stderr
    line and never the verdict."""
    if not a.report:
        return
    try:
        with open(a.report, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    except OSError as e:
        print("replay: ratchet: cannot write --report %s: %s" % (quote_field(a.report), e.strerror or e), file=sys.stderr)


def ratchet_infra(a, st, reason, message):
    """Exit 2: one stderr line naming the reason, then the marker (stderr in --print-baseline mode, where stdout is only the baseline)."""
    line, marker = "replay: ratchet: %s: %s" % (reason, message), ratchet_marker(2, reason, st)
    print(line, file=sys.stderr)
    print(marker, file=sys.stderr if a.print_baseline else sys.stdout)
    ratchet_report(a, [line, marker])
    return 2


def cmd_ratchet(a):
    """See RATCHET in --help. The four arms below are distinct on purpose and every one maps to exit 2 (never 3 or 4): a failure of the check is not a verdict."""
    st = {"stage": "root", "live": 0, "baseline": 0}
    try:
        return ratchet_run(a, st)
    except RatchetInfra as e:
        return ratchet_infra(a, st, e.reason, str(e))
    except ReadError as e:
        reason = {"rows": "selector-failed", "accept": "accept-unreadable", "baseline": "baseline-unreadable"}.get(st["stage"], "internal")
        if isinstance(e, ReadTimeout) and st["stage"] == "rows":
            reason = "selector-timeout"
        return ratchet_infra(a, st, reason, quote_field(str(e)))
    except OSError as e:
        return ratchet_infra(a, st, "floor-unreadable", quote_field("%s: %s" % (type(e).__name__, e)))
    except Exception as e:
        print("replay: internal error: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return ratchet_infra(a, st, "internal", "an unexpected error stopped the check")


def ratchet_run(a, st):
    root = a.root or repo_root()
    rel = a.baseline or RATCHET_BASELINE
    st["stage"] = "accept"
    accept, accept_err = {}, None
    default_accept = os.path.join(root, RATCHET_ACCEPT)
    apath = a.accept or (default_accept if os.path.lexists(default_accept) else "")
    if apath:
        try:
            accept = load_accept(apath, None if a.accept else root)
        except ValueError as e:
            accept_err = str(e)
    st["stage"] = "rows"
    rows = load_rows(a.list, root)
    st["stage"] = "census"
    c = audit_census(root, rows, accept)
    ratchet_floors(c)
    pairs = {"%s\t%s" % (quote_field(s), quote_field(p)): (s, p) for s, ps in c.gaps.items() for p in ps}
    live = sorted(pairs)
    st["live"] = len(live)
    st["stage"] = "baseline"
    head_text = ratchet_read(root, rel)
    head_lines, final_nl = baseline_split(head_text)
    st["baseline"] = len(head_lines)
    st["stage"] = "base"
    if a.print_baseline:
        if c.unaudited or c.stale or accept_err:
            raise RatchetInfra("census-degraded", "an unaudited suite or a stale or malformed accept row makes the live set incomplete: a baseline printed from it would lose live pairs; fix the census first")
        keep = live if head_text is None else sorted(set(head_lines) & set(live))
        try:
            sha = ratchet_base(root, a.base or "HEAD^1", rel)[0]
            touched = ratchet_changed(root, sha)[1]
            oracle = ratchet_oracle(touched, rel)
        except (RatchetInfra, ReadError):
            oracle = []   # a developer checkout without a base still prints its baseline
        notice = ["oracle-inputs-changed: " + " ".join(oracle)] if oracle else []
        for line in notice:
            print(line, file=sys.stderr)
        sys.stdout.write("".join(line + "\n" for line in keep))
        marker = ratchet_marker(0, "pass", st)
        print(marker, file=sys.stderr)
        ratchet_report(a, notice + [marker])
        return 0
    sha, base_text = ratchet_base(root, a.base or "HEAD^1", rel)
    added, touched = ratchet_changed(root, sha)
    oracle = ratchet_oracle(touched, rel)
    live_set, head_set = set(live), set(head_lines)
    uniq = list(dict.fromkeys(head_lines))
    base_set = set(baseline_split(base_text)[0])
    q = quote_field
    findings = []   # (reason, [entry, ...], remedy lines); an entry is a list of output lines
    if c.unaudited:
        findings.append(("unaudited", [["unaudited\t%s\t%s" % (q(s), why if quoted else q(why))] for s, why, quoted in c.unaudited],
                         ["remedy: the audit could not read the suite above in full: make its inputs readable or correct its selector row"]))
    stars = [x for x in c.stale if x[3] in STAR_WHYS]
    if stars:
        findings.append(("star-row", [["star-row\t%s\t%s\t%s\t%s" % (q(s), q(p), key, why)] for s, p, key, why in stars],
                         ["remedy: delete the accept row: a suite with any tracked input cannot be accepted whole"]))
    stales = [["stale-accept\t%s\t%s\t%s\t%s" % (q(s), q(p), key, why)] for s, p, key, why in c.stale if why not in STAR_WHYS]
    if accept_err:
        stales.append(["stale-accept\t-\t-\t-\t%s" % q(accept_err)])
    if stales:
        findings.append(("stale-accept", stales, ["remedy: delete the accept row: the tree no longer backs it, or it is malformed"]))
    new = [line for line in live if line not in head_set]
    if new and head_text is None and base_text is not None:
        findings.append(("baseline-deleted", [["baseline-deleted\t%s\t%d pair(s) are still live" % (q(rel), len(new))]],
                         ["remedy: restore it from main: git checkout origin/main -- %s" % rel]))
    elif new:
        findings.append(("new-pair", [ratchet_new_entry(c, pairs[line], added, touched) for line in new], list(RATCHET_REMEDY_NEW)))
    gone = [line for line in uniq if line not in live_set]
    if gone:
        findings.append(("stale-line", [["stale-line\t%s\t%s" % (q(rel), shown(line))] for line in gone], []))
    seen = Counter(head_lines)
    dups = [line for line in uniq if seen[line] > 1]
    if dups:
        findings.append(("baseline-dup", [["baseline-dup\t%s\t%s" % (q(rel), shown(line))] for line in dups], []))
    if uniq != sorted(uniq) or not final_nl:
        findings.append(("baseline-order", [["baseline-order\t%s\tnot in C-locale sorted order with a final newline" % q(rel)]], []))
    if base_text is not None and head_text is not None:
        grown = [line for line in uniq if line not in base_set]
        if grown:
            findings.append(("grown", [["grown\t%s\t%s" % (q(rel), shown(line))] for line in grown], []))
    out, rep = [], []
    for reason, entries, remedy in findings:
        for entry in entries:
            rep.extend(entry)
        for entry in entries[:RATCHET_CAP]:
            out.extend(entry)
        if len(entries) > RATCHET_CAP:
            out.append("more\t%s\t%d" % (reason, len(entries) - RATCHET_CAP))
        out.extend(remedy)
        rep.extend(remedy)
    names = {f[0] for f in findings}
    if names & {"stale-line", "baseline-dup", "baseline-order", "grown"}:
        tail = []
        if "stale-line" in names:
            tail.append("remedy: confirm the pair is really gone on a clean checkout; if the selector output was partial or this run exited 2, do not prune: rerun")
        tail.append("remedy: delete the offending line(s) above from %s; if the file is in conflict, restore main's copy with git checkout origin/main -- %s, then run: "
                    "python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > %s.new && mv %s.new %s" % (rel, rel, rel, rel, rel))
        out.extend(tail)
        rep.extend(tail)
    if oracle:
        out.append("oracle-inputs-changed: " + " ".join(oracle))
        rep.append(out[-1])
    code = 1 if findings else 0
    out.append(ratchet_marker(code, findings[0][0] if findings else "pass", st))
    ratchet_report(a, rep + [out[-1]])
    sys.stdout.write("\n".join(out) + "\n")
    return code


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
    if no_suites(c):
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
                  "anchor = first 12 hex of sha256(\" \".join(line.split())) of the comment-stripped line; ordinal = the Nth identical line (suite file, its source closure, then the naming-walk files); "
                  "a missing file exempts nothing; the full format and the stale reasons are in the ACCEPT FILE section of the top-level --help)")
    u.add_argument("--all-refs", action="store_true", dest="all_refs", help="print every undeclared path, not the first six, and a ref line (file:line, anchor/ordinal, text) per boundary line")
    r = sub.add_parser("ratchet", help="the audit as a check that is green on a tree the audit fails: live gap pairs must equal the committed shrink-only baseline")
    r.add_argument("--root", default="", help="the tree to check (default: the current checkout)")
    r.add_argument("--list", default="", help="read the selector output from FILE instead of running the selector")
    r.add_argument("--baseline", default="", help="repo-relative baseline path (default scripts/ci-pr-affected-audit.baseline.tsv)")
    r.add_argument("--accept", default="", help="the accept TSV (default scripts/ci-pr-affected-audit.accept.tsv when it exists)")
    r.add_argument("--base", default="", help="the ref the growth rule, the baseline-state table, the cause text and the helper copy come from (default HEAD^1; meaningful in CI, where HEAD is a merge commit)")
    r.add_argument("--print-baseline", action="store_true", dest="print_baseline", help="print the baseline to stdout (every live pair when no baseline exists, else the baseline lines still live) and write nothing; refuses (exit 2) on a degraded census")
    r.add_argument("--report", default="", help="also write the full, uncapped failure text to FILE (on a verdict, on an exit-2 stop and under --print-baseline; an unwritable path costs one stderr line)")
    a = ap.parse_args(argv)
    if a.cmd == "collect" and not re.match(r"^[1-9][0-9]*/[1-9][0-9]*$", a.chunk):
        print("replay: --chunk must be I/K with I,K >= 1", file=sys.stderr)
        return 2
    try:
        return {"collect": cmd_collect, "ejections": cmd_ejections, "aggregate": cmd_aggregate, "verdict": cmd_verdict,
                "cp-upper": cmd_cp, "audit": cmd_audit, "ratchet": cmd_ratchet}[a.cmd](a)
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
