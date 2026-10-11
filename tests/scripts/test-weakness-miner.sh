#!/usr/bin/env bash
# Tests for scripts/weakness-miner.sh (#6037) — read-only weakness-miner.
# Isolated temp roots so the real learnings corpus / digest are never touched.
# NOTE: no `set -e` — this is an accumulate-then-exit gate; a nonzero probe
# inside a command substitution must not abort before _report prints.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ONE owning root for every fixture below, removed by ONE EXIT trap installed BEFORE anything is
# sourced (ADR-129: a sourced helper may compose with a prior trap; a later trap replaces it).
# Each fixture was a bare `mktemp -d` with no cleanup: a direct run left five `tmp.*` dirs behind
# (#9117). A fixture dir is `$WM_ROOT/<name>.XXXXXX`, so a replaced trap still leaves one entry, not five.
WM_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/weakness-miner-test.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
# Canonical assert_fixture_dir -- byte-identical copy (fixture-scan.py requires it); do not reword.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
_wm_cleanup() { assert_fixture_dir "$WM_ROOT"; rm -rf "$WM_ROOT"; }
trap _wm_cleanup EXIT

# The shell fixture chokepoint (#7849), replacing the nine-variable `unset GIT_…` that stood
# here. That scrub was a hand-copied transcription of one list; this file sources the list
# itself, so the two cannot drift. Every git call below is a bare `( cd "$root" && git … )`
# with no -C and no explicit env, so an inherited GIT_DIR from a hook would send these fixture
# commits into the developer's real repository -- the #7833 defect. The scrub SILENTLY removed
# such an inheritance; sourcing here ABORTS on it, naming this file, so the broken entry point
# gets fixed instead of papered over. Every fixture root below then calls `git_fixture_env` --
# including the three that create no repo, because the scrub it replaces was suite-wide and a
# per-fixture replacement that skipped them would cover strictly less.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

SCRIPT="$REPO_ROOT/scripts/weakness-miner.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

# Write a learning file with a given tags array. $1=path $2=comma-sep tags
_learning() {
  local path="$1" tags="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
date: 2026-07-05
category: workflow-patterns
tags: [${tags}]
---
# Learning: fixture
## Session Errors
none.
EOF
}

# ---------------------------------------------------------------------------
# Test 1 — clustering: a tag-pair in >=3 files ranks; a pair in 2 files does not.
# Uses SOLEUR_WM_FILES to feed an explicit file list (bypasses git selection).
# ---------------------------------------------------------------------------
t_clustering() {
  local root; root=$(mktemp -d "$WM_ROOT/fixture.XXXXXX")
  git_fixture_env "$root" || {
    echo "FATAL: test-weakness-miner: git_fixture_env refused the clustering fixture $root" >&2
    exit 1
  }
  # 3 files share (ci, drift-guard); only 2 share (supabase, rls)
  _learning "$root/a.md" "ci, drift-guard, bash"
  _learning "$root/b.md" "ci, drift-guard, terraform"
  _learning "$root/c.md" "ci, drift-guard, vitest"
  _learning "$root/d.md" "supabase, rls, migration"
  _learning "$root/e.md" "supabase, rls, storage"
  local digest="$root/digest.md"
  SOLEUR_WM_FILES="$(printf '%s\n' "$root/a.md" "$root/b.md" "$root/c.md" "$root/d.md" "$root/e.md")" \
    SOLEUR_WM_DIGEST_PATH="$digest" SOLEUR_WM_MIN_MEMBERS=3 \
    bash "$SCRIPT" >/dev/null 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then _report "clustering: script runs" FAIL "(exit $rc)"; return; fi
  _report "clustering: script runs" ok
  if grep -qiE 'drift-guard.*—.*3 learnings|3 learnings' "$digest" && grep -qi 'drift-guard' "$digest"; then
    _report "clustering: >=3 pair (ci+drift-guard) ranked" ok
  else
    _report "clustering: >=3 pair (ci+drift-guard) ranked" FAIL "(digest: $(tr '\n' '|' <"$digest"))"
  fi
  # the 2-member (supabase+rls) pair must NOT be a ranked cluster heading
  if grep -qE '^###.*supabase.*rls|^###.*rls.*supabase' "$digest"; then
    _report "clustering: 2-member pair suppressed" FAIL "(supabase+rls should not rank)"
  else
    _report "clustering: 2-member pair suppressed" ok
  fi
}

# ---------------------------------------------------------------------------
# Test 2 — git first-appearance window: only in-window learnings are selected.
# Real temp git repo; controlled commit dates; NO SOLEUR_WM_FILES so the script
# uses --diff-filter=A first-appearance selection. SOLEUR_WM_SINCE pins cutoff.
# ---------------------------------------------------------------------------
t_git_window() {
  local root; root=$(mktemp -d "$WM_ROOT/fixture.XXXXXX")
  git_fixture_env "$root" || {
    echo "FATAL: test-weakness-miner: git_fixture_env refused the git-window fixture $root" >&2
    exit 1
  }
  ( cd "$root" && git init -q -b main && git config user.email t@t && git config user.name t )
  local ld="$root/knowledge-base/project/learnings"
  # OLD file first-appears 2026-01-01 (out of window)
  _learning "$ld/old.md" "oldtag-x, oldtag-y, oldtag-z"
  ( cd "$root" && git add -A && GIT_AUTHOR_DATE="2026-01-01T00:00:00" GIT_COMMITTER_DATE="2026-01-01T00:00:00" git commit -q -m old )
  # NEW files first-appear 2026-07-05 (in window); 3 share (win-a, win-b)
  _learning "$ld/n1.md" "win-a, win-b, x1"
  _learning "$ld/n2.md" "win-a, win-b, x2"
  _learning "$ld/n3.md" "win-a, win-b, x3"
  ( cd "$root" && git add -A && GIT_AUTHOR_DATE="2026-07-05T00:00:00" GIT_COMMITTER_DATE="2026-07-05T00:00:00" git commit -q -m new )
  local digest="$root/digest.md"
  ( cd "$root" && SOLEUR_WM_LEARNINGS_DIR="knowledge-base/project/learnings" \
      SOLEUR_WM_DIGEST_PATH="digest.md" SOLEUR_WM_SINCE="2026-06-28" SOLEUR_WM_MIN_MEMBERS=3 \
      bash "$SCRIPT" >/dev/null 2>&1 )
  if grep -qi 'win-a' "$digest" && ! grep -qi 'oldtag' "$digest"; then
    _report "git-window: in-window selected, out-of-window excluded" ok
  else
    _report "git-window: in-window selected, out-of-window excluded" FAIL "(digest: $(tr '\n' '|' <"$digest" 2>/dev/null))"
  fi
}

# ---------------------------------------------------------------------------
# Test 3 — zero-mutation: after a run in a git repo, ONLY the digest path is
# modified (AC4a). The digest is the single write sink.
# ---------------------------------------------------------------------------
t_zero_mutation() {
  local root; root=$(mktemp -d "$WM_ROOT/fixture.XXXXXX")
  git_fixture_env "$root" || {
    echo "FATAL: test-weakness-miner: git_fixture_env refused the zero-mutation fixture $root" >&2
    exit 1
  }
  ( cd "$root" && git init -q -b main && git config user.email t@t && git config user.name t )
  local ld="$root/knowledge-base/project/learnings"
  _learning "$ld/z1.md" "za, zb, z1"
  _learning "$ld/z2.md" "za, zb, z2"
  _learning "$ld/z3.md" "za, zb, z3"
  ( cd "$root" && git add -A && GIT_AUTHOR_DATE="2026-07-05T00:00:00" GIT_COMMITTER_DATE="2026-07-05T00:00:00" git commit -q -m seed )
  ( cd "$root" && SOLEUR_WM_LEARNINGS_DIR="knowledge-base/project/learnings" \
      SOLEUR_WM_DIGEST_PATH="knowledge-base/project/weakness-digest.md" \
      SOLEUR_WM_SINCE="2026-06-28" SOLEUR_WM_MIN_MEMBERS=3 bash "$SCRIPT" >/dev/null 2>&1 )
  local dirty; dirty="$(cd "$root" && git status --porcelain | awk '{print $2}' | sort -u)"
  if [[ "$dirty" == "knowledge-base/project/weakness-digest.md" ]]; then
    _report "zero-mutation: only digest path modified" ok
  else
    _report "zero-mutation: only digest path modified" FAIL "(dirty: ${dirty//$'\n'/,})"
  fi
}

# ---------------------------------------------------------------------------
# Test 4 — no-cluster case: fewer than MIN_MEMBERS sharing a pair → benign note.
# ---------------------------------------------------------------------------
t_no_cluster() {
  local root; root=$(mktemp -d "$WM_ROOT/fixture.XXXXXX")
  git_fixture_env "$root" || {
    echo "FATAL: test-weakness-miner: git_fixture_env refused the no-cluster fixture $root" >&2
    exit 1
  }
  _learning "$root/a.md" "solo-a, solo-b"
  _learning "$root/b.md" "solo-c, solo-d"
  local digest="$root/digest.md"
  SOLEUR_WM_FILES="$(printf '%s\n' "$root/a.md" "$root/b.md")" \
    SOLEUR_WM_DIGEST_PATH="$digest" SOLEUR_WM_MIN_MEMBERS=3 \
    bash "$SCRIPT" >/dev/null 2>&1
  if grep -qiE 'no recurring pattern' "$digest"; then
    _report "no-cluster: benign note rendered" ok
  else
    _report "no-cluster: benign note rendered" FAIL "(digest: $(tr '\n' '|' <"$digest" 2>/dev/null))"
  fi
}

# ---------------------------------------------------------------------------
# Test 5 — workflow mutation boundary (AC4b): the bot-PR `add-paths` is exactly
# the single digest path and never widens.
# ---------------------------------------------------------------------------
t_workflow_addpaths() {
  local wf="$REPO_ROOT/.github/workflows/weakness-miner.yml"
  if [[ ! -f "$wf" ]]; then _report "workflow: exists" FAIL "(missing $wf)"; return; fi
  local ap; ap="$(awk '/add-paths:/{gsub(/^[[:space:]]*add-paths:[[:space:]]*/,"");print;exit}' "$wf")"
  if [[ "$ap" == "knowledge-base/project/weakness-digest.md" ]]; then
    _report "workflow: add-paths is single digest path (AC4b)" ok
  else
    _report "workflow: add-paths is single digest path (AC4b)" FAIL "(got: '$ap')"
  fi
}

# ---------------------------------------------------------------------------
# Test 6 — member-set dedup: 3 files sharing 3 tags {p,q,r} must produce ONE
# cluster heading (labelled p + q + r), NOT the 3 K-choose-2 pair headings.
# ---------------------------------------------------------------------------
t_dedup() {
  local root; root=$(mktemp -d "$WM_ROOT/fixture.XXXXXX")
  git_fixture_env "$root" || {
    echo "FATAL: test-weakness-miner: git_fixture_env refused the dedup fixture $root" >&2
    exit 1
  }
  _learning "$root/a.md" "pp, qq, rr"
  _learning "$root/b.md" "pp, qq, rr"
  _learning "$root/c.md" "pp, qq, rr"
  local digest="$root/digest.md"
  SOLEUR_WM_FILES="$(printf '%s\n' "$root/a.md" "$root/b.md" "$root/c.md")" \
    SOLEUR_WM_DIGEST_PATH="$digest" SOLEUR_WM_MIN_MEMBERS=3 \
    bash "$SCRIPT" >/dev/null 2>&1
  local headings; headings="$(grep -c '^### ' "$digest" 2>/dev/null)"
  if [[ "$headings" == "1" ]] && grep -qE '^### pp \+ qq \+ rr — 3 learnings' "$digest"; then
    _report "dedup: 3 files sharing 3 tags → one merged cluster heading" ok
  else
    _report "dedup: 3 files sharing 3 tags → one merged cluster heading" FAIL "(headings=$headings; digest: $(tr '\n' '|' <"$digest"))"
  fi
}

# ---------------------------------------------------------------------------
# Test 7 — bot-PR author identity (#9454 item 4, ADR-285). Every caller of the
# bot-PR composite must author, push and arm its PR as the soleur-infra App
# (minted in the caller's own job, in a job that runs no content-producing
# step), keeping the workflow token only for the synthetic check-runs; and the
# composite must fail closed for any gh call that is not one of its two helpers.
# A PR authored and armed as the workflow token had its runs held and its queue
# entry received no merge_group runs (PR 10013, 2026-10-11).
#
# Static: no network, no git. The population is DERIVED (every workflow step
# that uses the composite, floor of one), never listed. The guard program and
# the mutation program are written to $WM_ROOT once and run by python3; each
# mutation row is applied to COPIES of the real files and must turn the guard RED.
# ---------------------------------------------------------------------------
WM_GUARD_PY="$WM_ROOT/guard.py"
WM_MUTATE_PY="$WM_ROOT/mutate.py"
assert_fixture_dir "$WM_ROOT"
cat > "$WM_GUARD_PY" <<'PYGUARD'
#!/usr/bin/env python3
"""Static guard: every caller of the bot-PR composite authors, pushes and arms its PR as the
soleur-infra App (#9454 item 4 / ADR-285). Prints one `VIOLATION <id>: <message>` line per
finding and a final `CALLERS <n>` line. Always exits 0: the caller counts violations."""
import copy
import json
import os
import re
import sys

import yaml

WF_DIR = os.environ["WM_GUARD_WORKFLOWS"]
COMPOSITE = os.environ["WM_GUARD_COMPOSITE"]
CALLED = "./.github/actions/bot-pr-with-synthetic-checks"
MINT = "./.github/actions/mint-infra-app-token"
ALLOWED_USES = ("actions/checkout@", "actions/download-artifact@", "DopplerHQ/cli-action@", MINT, CALLED)

violations = []


def v(rid, msg):
    violations.append("VIOLATION %s: %s" % (rid, msg))


def squash(s):
    return re.sub(r"\s+", "", str(s))


def needs_closure(jobs, job):
    seen, stack = [], list((job.get("needs") if isinstance(job.get("needs"), list) else [job.get("needs")]) if job.get("needs") else [])
    while stack:
        n = stack.pop()
        if n in seen or n not in jobs:
            continue
        seen.append(n)
        nn = jobs[n].get("needs")
        stack.extend(nn if isinstance(nn, list) else ([nn] if nn else []))
    return seen


def check_caller(fname, doc, jname, jobs, job, steps, idx, st):
    tag = "%s::%s" % (fname, jname)
    w = st.get("with") or {}
    prt = str(w.get("pr-token", "")).strip()
    m = re.fullmatch(r"\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\.token\s*\}\}", prt)
    if not m:
        v("G1", "%s: pr-token must be the output of a mint step in this job (got %r)" % (tag, prt))
    else:
        mi = [i for i, s in enumerate(steps) if s.get("id") == m.group(1)]
        if not mi or mi[0] >= idx:
            v("G2", "%s: the step %r that produces pr-token must exist and run BEFORE the composite" % (tag, m.group(1)))
        else:
            ms = steps[mi[0]]
            mw = ms.get("with") or {}
            if str(ms.get("uses", "")).strip() != MINT:
                v("G3", "%s: pr-token must come from %s" % (tag, MINT))
            try:
                perms = json.loads(str(mw.get("permissions", "null")))
            except ValueError:
                perms = None
            if perms != {"contents": "write", "pull_requests": "write"}:
                v("G4", "%s: mint permissions must be exactly contents:write + pull_requests:write" % tag)
            if str(mw.get("repositories", "")).strip() != "soleur":
                v("G5", "%s: mint repositories must be exactly soleur" % tag)
            if squash(mw.get("doppler-token", "")) != "${{secrets.DOPPLER_TOKEN_INFRA_APP}}":
                v("G6", "%s: mint must read the narrow DOPPLER_TOKEN_INFRA_APP secret" % tag)
            if "doppler-project" in mw:
                v("G7", "%s: mint must not name doppler-project (narrow default only)" % tag)
    if squash(w.get("gh-token", "")) != "${{github.token}}":
        v("G8", "%s: gh-token must stay the workflow token (the ruleset matches check-runs from integration 15368)" % tag)
    if job.get("environment") != "infra-privileged":
        v("G9", "%s: the credential job must declare environment: infra-privileged (a scalar)" % tag)
    if "github.ref == 'refs/heads/main'" not in str(job.get("if", "")):
        v("G10", "%s: the credential job must be gated on github.ref == 'refs/heads/main'" % tag)
    for s in steps:
        if "run" in s:
            v("G11", "%s: the credential job must run no inline script (step %r); content-producing steps belong in a job with no credential" % (tag, s.get("name", s.get("id", "?"))))
        u = str(s.get("uses", ""))
        if u and not any(u.startswith(a) for a in ALLOWED_USES):
            v("G11", "%s: the credential job may only use checkout, download-artifact, the Doppler CLI, the mint and the composite (got %s)" % (tag, u))
    cos = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
    if not cos or any(str((s.get("with") or {}).get("persist-credentials")).lower() != "false" for s in cos):
        v("G12", "%s: every checkout in the credential job needs persist-credentials: false" % tag)
    chain = needs_closure(jobs, job)
    if not chain:
        v("G13", "%s: the credential job must depend on a separate content-producing job" % tag)
    for n in chain:
        nj = jobs[n]
        if nj.get("environment") is not None or "secrets." in json.dumps(nj):
            v("G13", "%s: job %s feeds the credential job and must hold no environment or secret reference" % (tag, n))
    perm = job.get("permissions", doc.get("permissions"))
    if perm != {"contents": "read", "checks": "write"}:
        v("G14", "%s: workflow-token permissions must be exactly contents:read + checks:write (got %r)" % (tag, perm))


callers = 0
for fname in sorted(os.listdir(WF_DIR)):
    if not fname.endswith((".yml", ".yaml")):
        continue
    doc = yaml.safe_load(open(os.path.join(WF_DIR, fname)))
    jobs = (doc or {}).get("jobs") or {}
    for jname, job in jobs.items():
        steps = job.get("steps") or []
        for idx, st in enumerate(steps):
            if str(st.get("uses", "")).strip() == CALLED:
                callers += 1
                check_caller(fname, doc, jname, jobs, job, steps, idx, st)
if callers == 0:
    v("FLOOR", "zero callers of the composite were evaluated; a walk that finds none must fail, never pass")


def blank_quotes(line):
    out, q, esc = [], None, False
    for ch in line:
        if q:
            if esc:
                esc = False
                out.append(" ")
            elif ch == "\\" and q == '"':
                esc = True
                out.append(" ")
            elif ch == q:
                q = None
                out.append(ch)
            else:
                out.append(" ")
        else:
            if ch in "\"'":
                q = ch
            out.append(ch)
    return "".join(out)


CMD_POS = r"(?:^|[;&|(!]|\bthen\b|\bdo\b|\belse\b|\$\()\s*"

cdoc = yaml.safe_load(open(COMPOSITE))
if "pr-token" not in (cdoc.get("inputs") or {}):
    v("C1", "the composite must declare the pr-token input")
step = next((s for s in cdoc["runs"]["steps"] if "pr create" in str(s.get("run", ""))), None)
if step is None:
    v("C2", "the composite's PR-opening step was not found")
else:
    env = step.get("env") or {}
    if "GH_TOKEN" in env:
        v("C3", "the step must not carry a step-level GH_TOKEN (a bare gh call would author as that token)")
    if squash(env.get("PR_TOKEN", "")) != "${{inputs.pr-token}}" or squash(env.get("GATE_TOKEN", "")) != "${{inputs.gh-token}}":
        v("C4", "the step env must carry exactly PR_TOKEN from inputs.pr-token and GATE_TOKEN from inputs.gh-token")
    lines = [l for l in str(step["run"]).splitlines() if l.strip() and not l.strip().startswith("#")]
    text = "\n".join(lines)
    stmts = [l.strip() for l in lines]
    if len(stmts) < 2 or not stmts[0].startswith("set ") or not stmts[1].startswith('case "$-" in'):
        v("C5", "the first statements must be set and then the xtrace refusal (case \"$-\" in)")
    nochange = text.find("No changes to commit")
    for label, pat in (
        ("an _bearer_ok check of PR_TOKEN", r'_bearer_ok\s+"\$\{?PR_TOKEN'),
        ("the PR_TOKEN == GATE_TOKEN refusal", r'\[\[\s*"\$PR_TOKEN"\s*==\s*"\$GATE_TOKEN"\s*\]\]'),
    ):
        mm = re.search(pat, text)
        if not mm or (nochange >= 0 and mm.start() > nochange):
            v("C6", "%s must exist before the no-change exit" % label)
    first_ref = text.find("GITHUB_REF")
    if first_ref < 0 or (nochange >= 0 and first_ref > nochange):
        v("C6", "a GITHUB_REF main refusal must exist before the no-change exit")
    um = re.search(r"^\s*unset\s+PR_TOKEN\s+GATE_TOKEN\s+GH_TOKEN\s*$", text, re.M)
    dl = text.find("curl -sSLo")
    if not um or (dl >= 0 and um.start() > dl):
        v("C7", "unset PR_TOKEN GATE_TOKEN GH_TOKEN must run before any download or repo script")
    body = text
    for helper, var in (("gh_app", "_pr"), ("gh_gate", "_gate")):
        hm = re.search(r'^\s*%s\(\)\s*\{\s*GH_TOKEN="\$%s"\s+gh\s+"\$@";\s*\}\s*$' % (helper, var), body, re.M)
        if not hm:
            v("C8", "the %s helper must be defined as GH_TOKEN=\"$%s\" gh \"$@\"" % (helper, var))
        else:
            body = body.replace(hm.group(0), "")
    for n, l in enumerate(body.splitlines()):
        if re.search(CMD_POS + r"gh\s", blank_quotes(l)):
            v("C9", "a bare gh call (no gh_app or gh_gate helper): %s" % l.strip())
    for verb in ("create", "edit", "merge"):
        if not re.search(r"\bgh_app\s+pr\s+%s\b" % verb, body):
            v("C10", "gh pr %s must go through gh_app" % verb)
    if re.search(r"\bgh_gate\s+pr\b", body):
        v("C10", "a PR write goes through gh_gate (the workflow token)")
    if re.search(r"\bgh_app\s+api\b", body):
        v("C11", "the check-runs POST goes through gh_app (a different integration id fails the ruleset match)")
    if not re.search(r'\bgh_gate\s+api\s+"repos/\$\{REPO\}/check-runs"', body):
        v("C11", "the check-runs POST must go through gh_gate")
    if not re.search(r"\bgit_remote\s+push\b", body):
        v("C12", "git push must go through git_remote (the App token as a per-command extra header)")
    if re.search(CMD_POS + r"git\s+push\b", blank_quotes(body), re.M):
        v("C12", "a bare git push uses the checkout credential, not the App token")
    gm = re.search(r"^\s*git_remote\(\)\s*\{.*?^\s*\}", body, re.M | re.S)
    if not gm or not all(t in gm.group(0) for t in ("GIT_CONFIG_COUNT=1", "GIT_CONFIG_KEY_0=http.https://github.com/.extraheader", 'GIT_CONFIG_VALUE_0="$_hdr"')):
        v("C12", "git_remote must pass the header through GIT_CONFIG_COUNT/KEY_0/VALUE_0 in the per-command environment")
    if not re.search(r"base64 -w ?0|tr -d '\\n'", body):
        v("C13", "the header must be built newline-free (base64 -w0 or tr -d)")
    joined = re.sub(r"\\\n\s*", " ", body)
    ts = re.search(r"^\s*unset\s+(GIT_TRACE[^\n]*)$", joined, re.M)
    need = {"GIT_TRACE", "GIT_TRACE_CURL", "GIT_TRACE_REDACT", "GIT_CURL_VERBOSE", "GIT_HTTP_TRACE_AUTH_HEADER"}
    if not ts or not need <= set(re.split(r"[\s\\]+", ts.group(1))):
        v("C14", "the git trace variables must be unset before the push (%s)" % ", ".join(sorted(need)))

print("\n".join(violations))
print("CALLERS %d" % callers)
PYGUARD
assert_fixture_dir "$WM_ROOT"
cat > "$WM_MUTATE_PY" <<'PYMUTATE'
#!/usr/bin/env python3
"""Apply ONE named mutation to copies of the real workflow and composite.
usage: mutate.py <row> <real-workflow> <real-composite> <outdir>
Writes <outdir>/wf/weakness-miner.yml and <outdir>/composite.yml. Exits 3 when the mutation did
not change the bytes it targets (a mutation that does not land reports the baseline, which reads
as a pass)."""
import copy
import os
import sys

import yaml

row, wf_path, comp_path, out = sys.argv[1:5]
wf = open(wf_path).read()
comp = open(comp_path).read()
doc = None


def sub(text, old, new):
    if text.count(old) < 1:
        sys.exit("MUTATION-ANCHOR-MISSING: %r" % old)
    return text.replace(old, new, 1)


def struct(fn):
    d = yaml.safe_load(wf)
    fn(d)
    return yaml.safe_dump(d, sort_keys=False)


PRT = "pr-token: ${{ steps.app.outputs.token }}"
if row == "1-pr-token-is-workflow-token":
    wf = sub(wf, PRT, "pr-token: ${{ github.token }}")
elif row == "1b-pr-token-secrets-spelling":
    wf = sub(wf, PRT, "pr-token: ${{ secrets.GITHUB_TOKEN }}")
elif row == "2-pr-token-deleted":
    wf = sub(wf, "          " + PRT + "\n", "")
elif row == "3-mint-after-composite":
    def f(d):
        st = d["jobs"]["open-pr"]["steps"]
        i = [k for k, s in enumerate(st) if s.get("id") == "app"][0]
        j = [k for k, s in enumerate(st) if str(s.get("uses", "")).endswith("bot-pr-with-synthetic-checks")][0]
        st[i], st[j] = st[j], st[i]
    wf = struct(f)
elif row == "4-environment-removed":
    wf = sub(wf, "    environment: infra-privileged\n", "")
elif row == "5-third-caller-bad":
    def f(d):
        jobs = d["jobs"]
        jobs["open-pr-2"] = copy.deepcopy(jobs["open-pr"])
        bad = copy.deepcopy(jobs["open-pr"])
        for s in bad["steps"]:
            if str(s.get("uses", "")).endswith("bot-pr-with-synthetic-checks"):
                s["with"]["pr-token"] = "${{ github.token }}"
        jobs["open-pr-3"] = bad
    wf = struct(f)
elif row == "7-bare-gh":
    comp = sub(comp, '          gh_app pr merge "$BRANCH" --squash --auto\n', '          gh_app pr merge "$BRANCH" --squash --auto\n          gh pr view "$BRANCH"\n')
elif row == "8a-merge-through-gate":
    comp = sub(comp, "gh_app pr merge", "gh_gate pr merge")
elif row == "8b-create-through-gate":
    comp = sub(comp, "gh_app pr create", "gh_gate pr create")
elif row == "8c-edit-through-gate":
    comp = sub(comp, "gh_app pr edit", "gh_gate pr edit")
elif row == "9-push-without-app-header":
    comp = sub(comp, "git_remote push -u origin", "git push -u origin")
elif row == "10-check-runs-through-app":
    comp = sub(comp, 'gh_gate api "repos/', 'gh_app api "repos/')
elif row == "11a-equality-refusal-deleted":
    comp = sub(comp, '[[ "$PR_TOKEN" == "$GATE_TOKEN" ]]', "false")
elif row == "11b-unset-deleted":
    comp = sub(comp, "        unset PR_TOKEN GATE_TOKEN GH_TOKEN\n", "        :\n")
elif row == "11c-step-level-gh-token":
    comp = sub(comp, "        PR_TOKEN: ${{ inputs.pr-token }}\n", "        GH_TOKEN: ${{ inputs.gh-token }}\n        PR_TOKEN: ${{ inputs.pr-token }}\n")
elif row == "11d-pr-token-shape-check-dropped":
    comp = sub(comp, "_bearer_ok \"${PR_TOKEN:-}\"; then", "_bearer_ok \"${GATE_TOKEN:-}\"; then")
elif row == "12a-miner-in-credential-job":
    def f(d):
        d["jobs"]["open-pr"]["steps"].insert(0, {"name": "Run weakness-miner", "run": "bash scripts/weakness-miner.sh"})
    wf = struct(f)
elif row == "12b-environment-on-mine":
    wf = sub(wf, "  mine:\n    runs-on: ubuntu-latest\n", "  mine:\n    environment: infra-privileged\n    runs-on: ubuntu-latest\n")
elif row == "12c-secret-in-mine":
    wf = sub(wf, "        run: bash scripts/weakness-miner.sh\n", "        run: bash scripts/weakness-miner.sh\n        env:\n          LEAK: ${{ secrets.RESEND_API_KEY }}\n")
elif row == "13-persist-credentials-dropped":
    wf = sub(wf, "          ref: main\n          persist-credentials: false   # the push header is the only credential on the wire\n", "          ref: main\n")
elif row == "14-extra-write-permission":
    wf = sub(wf, "      checks: write    # the synthetic check-runs, posted under the workflow token\n", "      checks: write    # the synthetic check-runs, posted under the workflow token\n      pull-requests: write\n")
else:
    sys.exit("unknown row %r" % row)

os.makedirs(os.path.join(out, "wf"), exist_ok=True)
open(os.path.join(out, "wf", "weakness-miner.yml"), "w").write(wf)
open(os.path.join(out, "composite.yml"), "w").write(comp)
PYMUTATE

_wm_guard() { # $1 = workflows dir, $2 = composite path; prints the guard's lines
  WM_GUARD_WORKFLOWS="$1" WM_GUARD_COMPOSITE="$2" python3 -I "$WM_GUARD_PY" 2>&1
}
_wm_count() { # $1 = guard output; prints the number of VIOLATION lines
  printf '%s\n' "$1" | awk '/^VIOLATION /{n++} END{print n+0}'
}

GUARD_CASES=0
GUARD_EXPECTED_CASES=25

t_workflow_pr_identity() {
  local real_wf="$REPO_ROOT/.github/workflows/weakness-miner.yml"
  local real_comp="$REPO_ROOT/.github/actions/bot-pr-with-synthetic-checks/action.yml"
  local root; root=$(mktemp -d "$WM_ROOT/guard.XXXXXX")
  assert_fixture_dir "$root"
  git_fixture_env "$root" || {
    echo "FATAL: test-weakness-miner: git_fixture_env refused the identity-guard fixture $root" >&2
    exit 1
  }
  local f
  for f in "$real_wf" "$real_comp"; do
    [[ -f "$f" ]] || { _report "identity guard: input exists" FAIL "(missing $f)"; return; }
  done

  # H1 — the guard's own positive control, BEFORE any verdict: a known-bad caller must come
  # back RED, or the walk is blind and every green below would be meaningless.
  mkdir -p "$root/h1"
  cat > "$root/h1/bad.yml" <<'YML'
name: known-bad
on: workflow_dispatch
permissions:
  contents: read
jobs:
  go:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/bot-pr-with-synthetic-checks
        with:
          pr-token: ${{ github.token }}
          gh-token: ${{ github.token }}
YML
  local out n
  out=$(_wm_guard "$root/h1" "$real_comp")
  n=$(_wm_count "$out")
  if (( n == 0 )); then
    printf 'FATAL: the identity guard reported a known-bad caller GREEN; its walk is blind. Output: %s\n' "$out" >&2
    exit 2
  fi
  GUARD_CASES=$((GUARD_CASES + 1))
  _report "identity guard H1: known-bad caller is RED ($n violations)" ok

  # H2 — a must-PASS input that differs from the canonical in permitted ways (other file and job
  # names, mint step id appmint, unrelated steps between mint and composite, no inner spaces in
  # the expression): a guard that rejects everything fails here.
  mkdir -p "$root/h2"
  cat > "$root/h2/other-bot.yml" <<'YML'
name: other-bot
on: workflow_dispatch
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
      - run: echo producing
  publish:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    environment: infra-privileged
    runs-on: ubuntu-latest
    permissions:
      contents: read
      checks: write
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          persist-credentials: false
      - uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c
      - id: appmint
        uses: ./.github/actions/mint-infra-app-token
        with:
          doppler-token: ${{secrets.DOPPLER_TOKEN_INFRA_APP}}
          installation-id: "166065653"
          permissions: '{"pull_requests":"write","contents":"write"}'
          repositories: soleur
      - uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093
      - uses: ./.github/actions/bot-pr-with-synthetic-checks
        with:
          gh-token: ${{github.token}}
          pr-token: ${{steps.appmint.outputs.token}}
YML
  out=$(_wm_guard "$root/h2" "$real_comp")
  n=$(_wm_count "$out")
  GUARD_CASES=$((GUARD_CASES + 1))
  if (( n == 0 )) && [[ "$out" == *"CALLERS 1"* ]]; then
    _report "identity guard H2: compliant non-canonical caller is GREEN" ok
  else
    _report "identity guard H2: compliant non-canonical caller is GREEN" FAIL "(got: $(printf '%s' "$out" | tr '\n' '|'))"
  fi

  # The real tree.
  out=$(_wm_guard "$REPO_ROOT/.github/workflows" "$real_comp")
  n=$(_wm_count "$out")
  GUARD_CASES=$((GUARD_CASES + 1))
  if (( n == 0 )) && [[ "$out" =~ CALLERS\ ([0-9]+) ]] && (( BASH_REMATCH[1] >= 1 )); then
    _report "identity guard: the real tree is GREEN (${BASH_REMATCH[1]} caller(s) evaluated)" ok
  else
    _report "identity guard: the real tree is GREEN" FAIL "(got: $(printf '%s' "$out" | tr '\n' '|'))"
  fi

  # Row 6 — the floor: a workflows directory with zero callers must FAIL, never pass.
  mkdir -p "$root/r6"
  printf 'name: empty\non: workflow_dispatch\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$root/r6/none.yml"
  out=$(_wm_guard "$root/r6" "$real_comp")
  GUARD_CASES=$((GUARD_CASES + 1))
  if [[ "$out" == *"VIOLATION FLOOR"* ]]; then
    _report "identity guard row 6: zero callers is RED (floor)" ok
  else
    _report "identity guard row 6: zero callers is RED (floor)" FAIL "(got: $(printf '%s' "$out" | tr '\n' '|'))"
  fi

  # Rows 1-5 and 7-14: each mutation is applied to COPIES of the real files and must (a) land,
  # (b) turn the guard RED with the named violation id.
  local row want mdir
  while IFS='|' read -r row want; do
    [[ -z "$row" ]] && continue
    mdir="$root/m.$row"
    assert_fixture_dir "$mdir"
    GUARD_CASES=$((GUARD_CASES + 1))
    if ! python3 -I "$WM_MUTATE_PY" "$row" "$real_wf" "$real_comp" "$mdir" >"$root/mutate.out" 2>&1; then
      _report "identity guard $row: mutation lands" FAIL "($(tr '\n' ' ' < "$root/mutate.out"))"
      continue
    fi
    if cmp -s "$mdir/wf/weakness-miner.yml" "$real_wf" && cmp -s "$mdir/composite.yml" "$real_comp"; then
      _report "identity guard $row: mutation lands" FAIL "(the mutated copies are byte-identical to the real files)"
      continue
    fi
    out=$(_wm_guard "$mdir/wf" "$mdir/composite.yml")
    if [[ "$out" == *"VIOLATION"*"$want"* ]]; then
      _report "identity guard $row: RED on $want" ok
    else
      _report "identity guard $row: RED on $want" FAIL "(got: $(printf '%s' "$out" | tr '\n' '|'))"
    fi
  done <<'ROWS'
1-pr-token-is-workflow-token|G1
1b-pr-token-secrets-spelling|G1
2-pr-token-deleted|G1
3-mint-after-composite|G2
4-environment-removed|G9
5-third-caller-bad|open-pr-3
7-bare-gh|C9
8a-merge-through-gate|C10
8b-create-through-gate|C10
8c-edit-through-gate|C10
9-push-without-app-header|C12
10-check-runs-through-app|C11
11a-equality-refusal-deleted|C6
11b-unset-deleted|C7
11c-step-level-gh-token|C3
11d-pr-token-shape-check-dropped|C6
12a-miner-in-credential-job|G11
12b-environment-on-mine|G13
12c-secret-in-mine|G13
13-persist-credentials-dropped|G12
14-extra-write-permission|G14
ROWS
}

t_clustering
t_git_window
t_zero_mutation
t_no_cluster
t_workflow_addpaths
t_dedup
t_workflow_pr_identity

echo "----"
echo "weakness-miner: $pass passed, $fail failed"
# Anti-vacuity floor for the identity guard: the case count must match what was written, so a
# deleted row or a loop that ran zero times cannot report green. Printed with printf and exit,
# never through _report, which is the helper this floor backstops.
if (( GUARD_CASES != GUARD_EXPECTED_CASES )); then
  printf 'FAIL: identity guard ran %s cases, expected %s\n' "$GUARD_CASES" "$GUARD_EXPECTED_CASES" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
