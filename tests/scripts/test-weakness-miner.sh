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
# that resolves to the composite, in any spelling, floor of one, cross-checked
# against a raw count of `uses:` lines naming it), never listed. The guard
# program and the mutation program are written to $WM_ROOT once and run by
# python3; each mutation row is applied to COPIES of the real files and must
# turn the guard RED on its named violation id.
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
import posixpath
import re
import sys

import yaml

WF_DIR = os.environ["WM_GUARD_WORKFLOWS"]
COMPOSITE = os.environ["WM_GUARD_COMPOSITE"]
CANON_SH = os.environ.get("WM_GUARD_CANON", "")
ACT_DIR = os.environ.get("WM_GUARD_ACTIONS") or os.path.join(WF_DIR, "..", "actions")
CALLED_REL = ".github/actions/bot-pr-with-synthetic-checks"
MINT_REL = ".github/actions/mint-infra-app-token"
REMOTE_PREFIX = "jikig-ai/soleur/"
ALLOWED_REMOTE = ("actions/checkout", "actions/download-artifact", "DopplerHQ/cli-action")
INSTALLATION_ID = "166065653"

violations = []


def v(rid, msg):
    violations.append("VIOLATION %s: %s" % (rid, msg))


def squash(s):
    return re.sub(r"\s+", "", str(s))


def resolve(uses):
    """Repo-relative action path a `uses` string names (local, ..-spelled or self-remote), else None."""
    u = str(uses or "").strip()
    if u.startswith("./"):
        return posixpath.normpath(u[2:])
    if u.startswith(REMOTE_PREFIX):
        return posixpath.normpath(u[len(REMOTE_PREFIX):].split("@", 1)[0])
    return None


def needs_closure(jobs, job):
    def as_list(n):
        return n if isinstance(n, list) else ([n] if n else [])

    seen, stack = [], as_list(job.get("needs"))
    while stack:
        n = stack.pop()
        if n in seen or n not in jobs:
            continue
        seen.append(n)
        stack.extend(as_list(jobs[n].get("needs")))
    return seen


def check_caller(fname, doc, jname, jobs, job, steps, idx, st):
    tag = "%s::%s" % (fname, jname)
    raw_uses = str(st.get("uses", "")).strip()
    if raw_uses != "./" + CALLED_REL:
        v("G0", "%s: the composite must be called by its canonical local spelling ./%s (got %r)" % (tag, CALLED_REL, raw_uses))
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
            if resolve(ms.get("uses")) != MINT_REL or str(ms.get("uses", "")).strip() != "./" + MINT_REL:
                v("G3", "%s: pr-token must come from ./%s" % (tag, MINT_REL))
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
            if str(mw.get("installation-id", "")).strip().strip("\"'") != INSTALLATION_ID:
                v("G18", "%s: mint installation-id must be %s" % (tag, INSTALLATION_ID))
            if "if" in ms or "continue-on-error" in ms:
                v("G19", "%s: the mint step must carry no `if` and no continue-on-error" % tag)
    if squash(w.get("gh-token", "")) != "${{github.token}}":
        v("G8", "%s: gh-token must stay the workflow token (the ruleset matches check-runs from integration 15368)" % tag)
    if "continue-on-error" in st:
        v("G19", "%s: the composite step must carry no continue-on-error" % tag)
    if job.get("environment") != "infra-privileged":
        v("G9", "%s: the credential job must declare environment: infra-privileged (a scalar)" % tag)
    if re.sub(r"^\$\{\{|\}\}$", "", squash(job.get("if", ""))) != "github.ref=='refs/heads/main'":
        v("G10", "%s: the credential job must be gated on exactly github.ref == 'refs/heads/main'" % tag)
    if job.get("env") or doc.get("env") or any(s.get("env") for s in steps):
        v("G15", "%s: the credential job (and the workflow) must set no env: at job, workflow or step level" % tag)
    for s in steps:
        if "run" in s:
            v("G11", "%s: the credential job must run no inline script (step %r); content-producing steps belong in a job with no credential" % (tag, s.get("name", s.get("id", "?"))))
        u = str(s.get("uses", "")).strip()
        if not u:
            continue
        rel = resolve(u)
        if rel is not None:
            if rel not in (MINT_REL, CALLED_REL):
                v("G11", "%s: the credential job may only use checkout, download-artifact, the Doppler CLI, the mint and the composite (got %s)" % (tag, u))
        elif u.split("@", 1)[0] not in ALLOWED_REMOTE:
            v("G11", "%s: the credential job may only use checkout, download-artifact, the Doppler CLI, the mint and the composite (got %s)" % (tag, u))
    cos = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
    if not cos or any(str((s.get("with") or {}).get("persist-credentials")).lower() != "false" for s in cos):
        v("G12", "%s: every checkout in the credential job needs persist-credentials: false" % tag)
    for s in cos:
        cw = s.get("with") or {}
        if str(cw.get("ref", "")) != "main" or not set(cw) <= {"ref", "persist-credentials", "fetch-depth", "fetch-tags"}:
            v("G17", "%s: a credential-job checkout must pin ref: main and set only ref/persist-credentials/fetch-depth/fetch-tags" % tag)
    for s in steps:
        if str(s.get("uses", "")).startswith("actions/download-artifact@"):
            dw = s.get("with") or {}
            dp = str(dw.get("path", ""))
            if (not set(dw) <= {"name", "path"} or "name" not in dw or not dp.startswith("knowledge-base/")
                    or ".." in dp.split("/") or dp.startswith("/")):
                v("G17", "%s: the artifact download must set only name and a path under knowledge-base/ (got %r)" % (tag, dict(dw)))
    if set(job) - {"needs", "if", "environment", "runs-on", "timeout-minutes", "permissions", "steps"} or job.get("runs-on") != "ubuntu-latest":
        v("G20", "%s: the credential job may set only needs/if/environment/runs-on/timeout-minutes/permissions/steps and must run on ubuntu-latest (no container, defaults, strategy, services, env)" % tag)
    for s in steps:
        u = str(s.get("uses", "")).strip()
        if u and resolve(u) is None and not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}", u):
            v("G20", "%s: every third-party action in the credential job must be pinned to a 40-hex commit SHA (got %s)" % (tag, u))
    if (set(w) - {"add-paths", "branch-prefix", "commit-message", "pr-title-prefix", "pr-body", "change-summary", "pr-token", "gh-token"}
            or str(w.get("skip-auto-merge", "false")).lower() != "false"):
        v("G20", "%s: the composite step may pass only its content inputs and pr-token/gh-token, and must not skip auto-merge" % tag)
    chain = needs_closure(jobs, job)
    if not chain:
        v("G13", "%s: the credential job must depend on a separate content-producing job" % tag)
    for n in chain:
        nj = jobs[n]
        dump = json.dumps(nj)
        eff = nj.get("permissions", doc.get("permissions"))
        if (nj.get("environment") is not None or re.search(r"\bsecrets\b", dump)
                or "write" in json.dumps(eff)):
            v("G13", "%s: job %s feeds the credential job and must hold no environment, secret reference or write permission" % (tag, n))
    perm = job.get("permissions", doc.get("permissions"))
    if perm != {"contents": "read", "checks": "write"}:
        v("G14", "%s: workflow-token permissions must be exactly contents:read + checks:write (got %r)" % (tag, perm))


callers = 0
raw_mentions = 0
for fname in sorted(os.listdir(WF_DIR)):
    if not fname.endswith((".yml", ".yaml")):
        continue
    text = open(os.path.join(WF_DIR, fname)).read()
    if "bot-pr-with-synthetic-checks" not in text:
        continue
    raw_mentions += len(re.findall(r"^\s*-?\s*uses:\s*\S*bot-pr-with-synthetic-checks", text, re.M))
    doc = yaml.safe_load(text)
    jobs = (doc or {}).get("jobs") or {}
    for jname, job in jobs.items():
        steps = job.get("steps") or []
        for idx, st in enumerate(steps):
            if resolve(st.get("uses")) == CALLED_REL:
                callers += 1
                check_caller(fname, doc, jname, jobs, job, steps, idx, st)
if callers == 0:
    v("FLOOR", "zero callers of the composite were evaluated; a walk that finds none must fail, never pass")
if callers != raw_mentions:
    v("POP", "%d caller(s) evaluated but %d `uses:` line(s) name the composite; a spelling the walk cannot resolve is an unevaluated caller" % (callers, raw_mentions))
if os.path.isdir(ACT_DIR):
    for d in sorted(os.listdir(ACT_DIR)):
        ay = os.path.join(ACT_DIR, d, "action.yml")
        if d != posixpath.basename(CALLED_REL) and os.path.isfile(ay) and re.search(
                r"^\s*-?\s*uses:\s*\S*bot-pr-with-synthetic-checks", open(ay).read(), re.M):
            v("WRAP", "composite action %s wraps the bot-PR composite; the guard evaluates workflow callers only" % d)


def blank_quotes(line):
    out, q, esc = [], None, False
    for ch in line:
        if q:
            if esc:
                esc = False
                out.append("x")
            elif ch == "\\" and q == '"':
                esc = True
                out.append("x")
            elif ch == q:
                q = None
                out.append(ch)
            else:
                out.append("x")
        else:
            if ch in "\"'":
                q = ch
            out.append(ch)
    return "".join(out)


def code_of(line):
    return re.sub(r"(^|\s)#.*$", r"\1", blank_quotes(line))


PRE = (r"(?:^|[;&|(!{`)]|\$\(|\b(?:then|do|else|if|while|until|command|exec|env|xargs|time|nohup|sudo|timeout\s+\S+)\b)\s*"
       r"(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?")

cdoc = yaml.safe_load(open(COMPOSITE))
if "pr-token" not in (cdoc.get("inputs") or {}):
    v("C1", "the composite must declare the pr-token input")
csteps = (cdoc.get("runs") or {}).get("steps") or []
if not csteps:
    v("C2", "the composite's PR-opening step was not found")
else:
    if len(csteps) != 1 or "uses" in csteps[0] or csteps[0].get("shell") != "bash" or set(csteps[0]) - {"name", "shell", "env", "run"}:
        v("C2", "the composite must be exactly one inline `shell: bash` run step with only name/shell/env/run keys: a second step, a `uses:`, another shell or an `if`/working-directory is outside the analysed body")
    step = csteps[0]
    env = step.get("env") or {}
    if "GH_TOKEN" in env:
        v("C3", "the step must not carry a step-level GH_TOKEN (a bare gh call would author as that token)")
    if squash(env.get("PR_TOKEN", "")) != "${{inputs.pr-token}}" or squash(env.get("GATE_TOKEN", "")) != "${{inputs.gh-token}}":
        v("C4", "the step env must carry exactly PR_TOKEN from inputs.pr-token and GATE_TOKEN from inputs.gh-token")
    lines = [l for l in str(step.get("run", "")).splitlines() if l.strip() and not l.strip().startswith("#")]
    text = "\n".join(lines)
    nocomment = "\n".join(re.sub(r"(^|\s)#.*$", r"\1", l) for l in lines)
    stmts = [l.strip() for l in lines]
    if len(stmts) < 2 or not stmts[0].startswith("set ") or not stmts[1].startswith('case "$-" in'):
        v("C5", "the first statements must be set and then the xtrace refusal (case \"$-\" in)")
    nochange = text.find("No changes to commit")

    def refusal_blocks(pat):
        return list(re.finditer(pat + r"\s*then(.*?)\n\s*fi\b", text, re.S))

    for label, pat in (
        ("an _bearer_ok refusal of PR_TOKEN", r'if ! _bearer_ok "\$\{PR_TOKEN:-\}";'),
        ("an _bearer_ok refusal of GATE_TOKEN", r'if ! _bearer_ok "\$\{GATE_TOKEN:-\}";'),
        ("the PR_TOKEN == GATE_TOKEN refusal", r'if \[\[ "\$PR_TOKEN" == "\$GATE_TOKEN" \]\];'),
        ("the off-main refusal", r'if \[ "\$\{GITHUB_REF:-\}" != "refs/heads/main" \];'),
    ):
        blocks = refusal_blocks(pat)
        if not blocks:
            v("C6", "%s must exist" % label)
            continue
        if nochange >= 0 and blocks[0].start() > nochange:
            v("C6", "%s must come before the no-change exit" % label)
        for b in blocks:
            body_lines = [l.strip() for l in b.group(1).splitlines() if l.strip()]
            if (len(body_lines) != 2 or not (body_lines[0].startswith('echo "::error::') and body_lines[0].endswith('"'))
                    or not re.fullmatch(r"exit [1-9][0-9]*", body_lines[1])):
                v("C6", "%s must have exactly one echo of an ::error:: line then a bare exit N" % label)
    if not re.search(
            r'case "\$-" in\s*\n\s*\*x\*\)\s*\n\s*if \[ -n "\$\{PR_TOKEN:\+x\}\$\{GATE_TOKEN:\+x\}" \]; then\s*\n'
            r'\s*echo "::error::[^\n]*"\s*\n\s*exit 78\s*\n\s*fi\s*\n\s*;;\s*\n\s*esac', text):
        v("C5", "the xtrace refusal must be exactly: case on $-, *x*) with a live PR_TOKEN or GATE_TOKEN, one echo, exit 78")
    pm = re.search(r'^\s*_pr="\$PR_TOKEN"\s*$', nocomment, re.M)
    gm = re.search(r'^\s*_gate="\$GATE_TOKEN"\s*$', nocomment, re.M)
    if not pm or not gm:
        v("C18", '_pr must be assigned from "$PR_TOKEN" and _gate from "$GATE_TOKEN" (a swap authors as the workflow token)')
    if not re.search(r'^\s*_hdr="Authorization: basic \$\(printf \'%s\' "x-access-token:\$\{_pr\}" \| base64 -w0\)"\s*$', nocomment, re.M):
        v("C18", "the push header must be exactly _hdr=\"Authorization: basic $(printf '%s' \"x-access-token:${_pr}\" | base64 -w0)\" and never built from _gate")
    for label, pat in (("_pr", r"^\s*_pr="), ("_gate", r"^\s*_gate="), ("_hdr", r"^\s*_hdr="), ("_bearer_ok", r"^\s*_bearer_ok\(\)"),
                       ("gh_app", r"^\s*gh_app\(\)"), ("gh_gate", r"^\s*gh_gate\(\)"), ("git_remote", r"^\s*git_remote\(\)")):
        if len(re.findall(pat, nocomment, re.M)) != 1:
            v("C20", "%s must be defined or assigned exactly once (a later one wins at runtime)" % label)
    allowed_lines = {
        "_pr": (r'^\s*_pr="\$PR_TOKEN"\s*$', r'^\s*gh_app\(\)', r'^\s*_hdr=', r'^\s*unset _hdr _pr _gate\s*$'),
        "_gate": (r'^\s*_gate="\$GATE_TOKEN"\s*$', r'^\s*gh_gate\(\)', r'^\s*unset _hdr _pr _gate\s*$'),
        "PR_TOKEN": (r'if \[ -n "\$\{PR_TOKEN:\+x\}', r'if ! _bearer_ok "\$\{PR_TOKEN:-\}"', r'if \[\[ "\$PR_TOKEN" == "\$GATE_TOKEN" \]\]',
                     r'^\s*_pr="\$PR_TOKEN"\s*$', r'^\s*unset PR_TOKEN GATE_TOKEN GH_TOKEN\s*$'),
        "GATE_TOKEN": (r'if \[ -n "\$\{PR_TOKEN:\+x\}', r'if ! _bearer_ok "\$\{GATE_TOKEN:-\}"', r'if \[\[ "\$PR_TOKEN" == "\$GATE_TOKEN" \]\]',
                       r'^\s*_gate="\$GATE_TOKEN"\s*$', r'^\s*unset PR_TOKEN GATE_TOKEN GH_TOKEN\s*$'),
    }
    for var, pats in allowed_lines.items():
        for l in nocomment.splitlines():
            if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(var), l) and not any(re.search(pt, l) for pt in pats):
                v("C20", "%s may appear only where it is assigned, refused, scoped into its helper or unset: %s" % (var, l.strip()))
    um = re.search(r"^\s*unset\s+PR_TOKEN\s+GATE_TOKEN\s+GH_TOKEN\s*$", text, re.M)
    dl = text.find("curl -sSLo")
    if not um or (dl >= 0 and um.start() > dl) or (pm and um.start() < pm.start()) or (gm and um.start() < gm.start()):
        v("C7", "_pr and _gate must be assigned, then PR_TOKEN GATE_TOKEN GH_TOKEN unset, before any download or repo script")
    body = text
    for helper, var in (("gh_app", "_pr"), ("gh_gate", "_gate")):
        hdef = re.search(r'^\s*%s\(\)\s*\{\s*GH_TOKEN="\$%s"\s+gh\s+"\$@";\s*\}\s*$' % (helper, var), body, re.M)
        if not hdef:
            v("C8", "the %s helper must be defined as GH_TOKEN=\"$%s\" gh \"$@\"" % (helper, var))
        else:
            body = body.replace(hdef.group(0), "")
    codelines = [code_of(l) for l in body.splitlines()]
    codebody = "\n".join(codelines)
    for l in codelines:
        if re.search(PRE + r"gh\s", l):
            v("C9", "a bare gh call (no gh_app or gh_gate helper): %s" % l.strip())
    for l in codelines:
        if re.search(r"\b(eval|xargs|trap|source)\b|\b(ba)?sh\s+-c\b|set\s+\+e|python3\s+-c", l):
            v("C16", "eval, xargs, trap, source, sh -c, set +e and python -c hide commands from the guard: %s" % l.strip())
    for l in body.splitlines():
        if re.search(PRE + r"(curl|wget)\b", code_of(l)) and "gitleaks" not in l:
            v("C16", "a curl or wget other than the gitleaks download could author a PR through another client: %s" % l.strip())
    for verb in ("create", "edit", "merge"):
        if not re.search(PRE + r"gh_app\s+pr\s+%s\b" % verb, codebody, re.M):
            v("C10", "gh pr %s must go through gh_app, at command position" % verb)
    for mm in re.finditer(r"\bgh_app\s+(\S+\s+\S+)", body):
        if mm.group(1) not in ("pr create", "pr edit", "pr merge"):
            v("C10", "gh_app may only run pr create, pr edit and pr merge (got %s)" % mm.group(1))
    for mm in re.finditer(r"\bgh_gate\s+(\S+)\s+(\S+)", body):
        if (mm.group(1), mm.group(2)) != ("api", '"repos/${REPO}/check-runs"'):
            v("C11", "gh_gate may only POST repos/${REPO}/check-runs (got %s %s)" % (mm.group(1), mm.group(2)))
    if not re.search(PRE + r'gh_gate\s+api\s+"repos/\$\{REPO\}/check-runs"', body, re.M):
        v("C11", "the check-runs POST must go through gh_gate, at command position")
    if not re.search(PRE + r"git_remote\s+push\b", codebody, re.M):
        v("C12", "git push must go through git_remote (the App token as a per-command extra header), at command position")
    for l in codelines:
        if re.search(PRE + r"git\s+(?:-[A-Za-z]\s+\S+\s+|--\S+\s+)*push\b", l):
            v("C12", "a bare git push uses the checkout credential, not the App token: %s" % l.strip())
    if not re.search(r'^\s*git_remote\(\) \{\s*\n\s*GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http\.https://github\.com/\.extraheader \\\n'
                     r'\s*GIT_CONFIG_VALUE_0="\$_hdr" git "\$@"\s*\n\s*\}\s*$', nocomment, re.M):
        v("C12", "git_remote must be exactly the per-command GIT_CONFIG_COUNT/KEY_0/VALUE_0 header wrapper around git")
    for mm in re.finditer(r"\bgit_remote\s+([a-z-]+)", body):
        if mm.group(1) not in ("push", "ls-remote"):
            v("C12", "git_remote may only run push and ls-remote (got %s)" % mm.group(1))
    hline = re.search(r"^\s*_hdr=.*$", nocomment, re.M)
    if not hline or "base64 -w0" not in hline.group(0):
        v("C13", "the header must be built newline-free with base64 -w0")
    joined = re.sub(r"\\\n\s*", " ", body)
    ts = re.search(r"^\s*unset\s+(GIT_TRACE[^\n]*)$", joined, re.M)
    need = {"GIT_TRACE", "GIT_TRACE_CURL", "GIT_TRACE_REDACT", "GIT_CURL_VERBOSE", "GIT_HTTP_TRACE_AUTH_HEADER"}
    first_git = joined.find("git_remote()")
    if not ts or not need <= set(re.split(r"[\s\\]+", ts.group(1))) or (first_git >= 0 and ts.start() > first_git):
        v("C14", "the git trace variables must be unset before git_remote is defined (%s)" % ", ".join(sorted(need)))
    for fm in re.finditer(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", nocomment, re.M):
        if fm.group(1) not in ("_bearer_ok", "gh_app", "gh_gate", "git_remote"):
            v("C17", "an unrecognised shell function %s() can wrap gh or git outside the helpers" % fm.group(1))
    bot_name = bot_email = ""
    if CANON_SH and os.path.isfile(CANON_SH):
        ctext = open(CANON_SH).read()
        bn = re.search(r"^BOT_NAME='([^']+)'", ctext, re.M)
        be = re.search(r"^BOT_EMAIL='([^']+)'", ctext, re.M)
        bot_name, bot_email = (bn.group(1) if bn else ""), (be.group(1) if be else "")
    un = re.findall(r'^\s*git config user\.name "([^"]+)"\s*$', nocomment, re.M)
    ue = re.findall(r'^\s*git config user\.email "([^"]+)"\s*$', nocomment, re.M)
    if not bot_name or un != [bot_name] or ue != [bot_email]:
        v("C19", "the commit identity must be exactly the pin-bump script's BOT_NAME/BOT_EMAIL (the PR author, pusher and committer are one App identity)")
    canon = ""
    if CANON_SH and os.path.isfile(CANON_SH):
        cm = re.search(r"^_bearer_ok\(\).*$", open(CANON_SH).read(), re.M)
        canon = cm.group(0).strip() if cm else ""
    bm = re.search(r"^\s*(_bearer_ok\(\).*)$", body, re.M)
    if not canon or not bm or bm.group(1).strip() != canon:
        v("C15", "the composite's _bearer_ok must be byte-identical to the canonical copy in bump-inngest-bootstrap-pin.sh")

print("\n".join(violations))
print("CALLERS %d" % callers)
PYGUARD
assert_fixture_dir "$WM_ROOT"
cat > "$WM_MUTATE_PY" <<'PYMUTATE'
#!/usr/bin/env python3
"""Apply ONE named mutation to copies of the real workflow and composite.
usage: mutate.py <row> <real-workflow> <real-composite> <outdir>
Writes <outdir>/wf/weakness-miner.yml and <outdir>/composite.yml. Exits non-zero when the
mutation anchor is missing (a mutation that does not land reports the baseline, which reads as
a pass)."""
import copy
import os
import sys

import yaml

row, wf_path, comp_path, out = sys.argv[1:5]
wf = open(wf_path).read()
comp = open(comp_path).read()


def sub(text, old, new):
    if text.count(old) < 1:
        sys.exit("MUTATION-ANCHOR-MISSING: %r" % old)
    return text.replace(old, new, 1)


def struct(fn):
    d = yaml.safe_load(wf)
    fn(d)
    return yaml.safe_dump(d, sort_keys=False)


def second_caller(uses, pr_token):
    def f(d):
        jobs = d["jobs"]
        j = copy.deepcopy(jobs["open-pr"])
        for s in j["steps"]:
            if "bot-pr-with-synthetic-checks" in str(s.get("uses", "")):
                s["uses"] = uses
                s["with"]["pr-token"] = pr_token
        jobs["open-pr-2"] = j
    return f


PRT = "pr-token: ${{ steps.app.outputs.token }}"
APPLY = {}


def row_fn(name):
    def deco(fn):
        APPLY[name] = fn
        return fn
    return deco


@row_fn("1-pr-token-is-workflow-token")
def _():
    global wf
    wf = sub(wf, PRT, "pr-token: ${{ github.token }}")


@row_fn("1b-pr-token-secrets-spelling")
def _():
    global wf
    wf = sub(wf, PRT, "pr-token: ${{ secrets.GITHUB_TOKEN }}")


@row_fn("2-pr-token-deleted")
def _():
    global wf
    wf = sub(wf, "          " + PRT + "\n", "")


@row_fn("3-mint-after-composite")
def _():
    global wf

    def f(d):
        st = d["jobs"]["open-pr"]["steps"]
        i = [k for k, s in enumerate(st) if s.get("id") == "app"][0]
        j = [k for k, s in enumerate(st) if str(s.get("uses", "")).endswith("bot-pr-with-synthetic-checks")][0]
        st[i], st[j] = st[j], st[i]
    wf = struct(f)


@row_fn("4-environment-removed")
def _():
    global wf
    wf = sub(wf, "    environment: infra-privileged\n", "")


@row_fn("5-third-caller-bad")
def _():
    global wf

    def f(d):
        jobs = d["jobs"]
        jobs["open-pr-2"] = copy.deepcopy(jobs["open-pr"])
        bad = copy.deepcopy(jobs["open-pr"])
        for s in bad["steps"]:
            if str(s.get("uses", "")).endswith("bot-pr-with-synthetic-checks"):
                s["with"]["pr-token"] = "${{ github.token }}"
        jobs["open-pr-3"] = bad
    wf = struct(f)


@row_fn("7-bare-gh")
def _():
    global comp
    comp = sub(comp, '          gh_app pr merge "$BRANCH" --squash --auto\n', '          gh_app pr merge "$BRANCH" --squash --auto\n          gh pr view "$BRANCH"\n')


@row_fn("8a-merge-through-gate")
def _():
    global comp
    comp = sub(comp, "gh_app pr merge", "gh_gate pr merge")


@row_fn("8b-create-through-gate")
def _():
    global comp
    comp = sub(comp, "gh_app pr create", "gh_gate pr create")


@row_fn("8c-edit-through-gate")
def _():
    global comp
    comp = sub(comp, "gh_app pr edit", "gh_gate pr edit")


@row_fn("9-push-without-app-header")
def _():
    global comp
    comp = sub(comp, "git_remote push -u origin", "git push -u origin")


@row_fn("10-check-runs-through-app")
def _():
    global comp
    comp = sub(comp, 'gh_gate api "repos/', 'gh_app api "repos/')


@row_fn("11a-equality-refusal-deleted")
def _():
    global comp
    comp = sub(comp, '[[ "$PR_TOKEN" == "$GATE_TOKEN" ]]', "false")


@row_fn("11b-unset-deleted")
def _():
    global comp
    comp = sub(comp, "        unset PR_TOKEN GATE_TOKEN GH_TOKEN\n", "        :\n")


@row_fn("11c-step-level-gh-token")
def _():
    global comp
    comp = sub(comp, "        PR_TOKEN: ${{ inputs.pr-token }}\n", "        GH_TOKEN: ${{ inputs.gh-token }}\n        PR_TOKEN: ${{ inputs.pr-token }}\n")


@row_fn("11d-pr-token-shape-check-dropped")
def _():
    global comp
    comp = sub(comp, '_bearer_ok "${PR_TOKEN:-}"; then', '_bearer_ok "${GATE_TOKEN:-}"; then')


@row_fn("12a-miner-in-credential-job")
def _():
    global wf

    def f(d):
        d["jobs"]["open-pr"]["steps"].insert(0, {"name": "Run weakness-miner", "run": "bash scripts/weakness-miner.sh"})
    wf = struct(f)


@row_fn("12b-environment-on-mine")
def _():
    global wf
    wf = sub(wf, "  mine:\n    runs-on: ubuntu-latest\n", "  mine:\n    environment: infra-privileged\n    runs-on: ubuntu-latest\n")


@row_fn("12c-secret-in-mine")
def _():
    global wf
    wf = sub(wf, "        run: bash scripts/weakness-miner.sh\n", "        run: bash scripts/weakness-miner.sh\n        env:\n          LEAK: ${{ secrets.RESEND_API_KEY }}\n")


@row_fn("13-persist-credentials-dropped")
def _():
    global wf
    wf = sub(wf, "          ref: main\n          persist-credentials: false   # the push header is the only credential on the wire\n", "          ref: main\n")


@row_fn("14-extra-write-permission")
def _():
    global wf
    wf = sub(wf, "      checks: write    # the synthetic check-runs, posted under the workflow token\n", "      checks: write    # the synthetic check-runs, posted under the workflow token\n      pull-requests: write\n")


# --- rows added after review: bindings, population, unrowed checks -----------------------
@row_fn("15-pr-assign-swapped")
def _():
    global comp
    comp = sub(comp, '        _pr="$PR_TOKEN"\n', '        _pr="$GATE_TOKEN"\n')


@row_fn("16-gate-assign-swapped")
def _():
    global comp
    comp = sub(comp, '        _gate="$GATE_TOKEN"\n', '        _gate="$PR_TOKEN"\n')


@row_fn("17-header-from-gate-token")
def _():
    global comp
    comp = sub(comp, "x-access-token:${_pr}", "x-access-token:${_gate}")


@row_fn("18-equality-refusal-inert")
def _():
    global comp
    i = comp.index('if [[ "$PR_TOKEN" == "$GATE_TOKEN" ]]; then')
    j = comp.index("exit 1", i)
    comp = comp[:j] + ":" + comp[j + len("exit 1"):]


@row_fn("19-bearer-body-weakened")
def _():
    global comp
    i = comp.index("_bearer_ok() {")
    j = comp.index("return 1", i)
    comp = comp[:j] + "return 0" + comp[j + len("return 1"):]


@row_fn("20-second-composite-step")
def _():
    global comp
    comp = comp.rstrip("\n") + "\n    - name: Extra\n      shell: bash\n      env:\n        GH_TOKEN: ${{ inputs.gh-token }}\n      run: gh pr merge --admin\n"


@row_fn("21-bare-gh-env-prefixed")
def _():
    global comp
    comp = sub(comp, '          gh_app pr merge "$BRANCH" --squash --auto\n', '          gh_app pr merge "$BRANCH" --squash --auto\n          GH_TOKEN="$_gate" gh pr ready "$BRANCH"\n')


@row_fn("22-third-helper")
def _():
    global comp
    comp = sub(comp, '        gh_gate() { GH_TOKEN="$_gate" gh "$@"; }\n', '        gh_gate() { GH_TOKEN="$_gate" gh "$@"; }\n        gh_wf() { GH_TOKEN="$_gate" gh "$@"; }\n')


@row_fn("23-gate-token-writes-a-pr-endpoint")
def _():
    global comp
    comp = sub(comp, '        if [[ "$SKIP_AUTO_MERGE" != "true" ]]; then\n', '        gh_gate api "repos/${REPO}/pulls" -f x=y\n        if [[ "$SKIP_AUTO_MERGE" != "true" ]]; then\n')


@row_fn("24-merge-neutered-by-echo")
def _():
    global comp
    comp = sub(comp, '          gh_app pr merge "$BRANCH" --squash --auto\n', '          echo gh_app pr merge "$BRANCH" --squash --auto\n')


@row_fn("25-trace-unset-after-push")
def _():
    global comp
    block = ("        unset GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP \\\n"
             "          GIT_TRACE_CURL GIT_TRACE_CURL_NO_DATA GIT_TRACE_REDACT GIT_TRACE2 \\\n"
             "          GIT_TRACE2_PERF GIT_TRACE2_EVENT GIT_CURL_VERBOSE GIT_HTTP_TRACE_AUTH_HEADER\n")
    comp = sub(comp, block, "")
    comp = sub(comp, '        git_remote push -u origin "$BRANCH"\n', '        git_remote push -u origin "$BRANCH"\n' + block)


@row_fn("26-caller-trailing-slash")
def _():
    global wf
    wf = struct(second_caller("./.github/actions/bot-pr-with-synthetic-checks/", "${{ github.token }}"))


@row_fn("27-caller-remote-spelling")
def _():
    global wf
    wf = struct(second_caller("jikig-ai/soleur/.github/actions/bot-pr-with-synthetic-checks@main", "${{ github.token }}"))


@row_fn("28-if-or-always")
def _():
    global wf
    wf = sub(wf, "    if: github.ref == 'refs/heads/main'\n", "    if: github.ref == 'refs/heads/main' || always()\n")


@row_fn("29-secret-bracket-in-mine")
def _():
    global wf
    wf = sub(wf, "        run: bash scripts/weakness-miner.sh\n", "        run: bash scripts/weakness-miner.sh\n        env:\n          LEAK: ${{ secrets['RESEND_API_KEY'] }}\n")


@row_fn("30-mint-sibling-prefix-action")
def _():
    global wf

    def f(d):
        d["jobs"]["open-pr"]["steps"].insert(2, {"uses": "./.github/actions/mint-infra-app-token-x"})
    wf = struct(f)


@row_fn("31-installation-id-changed")
def _():
    global wf
    wf = sub(wf, 'installation-id: "166065653"', 'installation-id: "1"')


@row_fn("32-job-env-bash-env")
def _():
    global wf
    wf = sub(wf, "    environment: infra-privileged\n", "    environment: infra-privileged\n    env:\n      BASH_ENV: /x\n")


@row_fn("33-download-path-widened")
def _():
    global wf
    wf = sub(wf, "          path: knowledge-base/project\n", "          path: .\n")


@row_fn("34-checkout-ref-dropped")
def _():
    global wf
    wf = sub(wf, "          ref: main\n", "")


@row_fn("35-mine-write-permission")
def _():
    global wf
    wf = sub(wf, "  mine:\n    runs-on: ubuntu-latest\n", "  mine:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: write\n")


@row_fn("36-mint-continue-on-error")
def _():
    global wf
    wf = sub(wf, "        id: app\n", "        id: app\n        continue-on-error: true\n")


@row_fn("37-mint-uses-other-action")
def _():
    global wf
    wf = sub(wf, "        uses: ./.github/actions/mint-infra-app-token\n", "        uses: ./.github/actions/notify-ops-email\n")


@row_fn("38-mint-permissions-widened")
def _():
    global wf
    wf = sub(wf, """permissions: '{"contents":"write","pull_requests":"write"}'""", """permissions: '{"contents":"write","pull_requests":"write","administration":"write"}'""")


@row_fn("39-mint-repositories-widened")
def _():
    global wf
    wf = sub(wf, "          repositories: soleur\n", "          repositories: soleur,other\n")


@row_fn("40-mint-broad-doppler-token")
def _():
    global wf
    wf = sub(wf, "doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}", "doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}")


@row_fn("41-mint-names-a-doppler-project")
def _():
    global wf
    wf = sub(wf, "          repositories: soleur\n", "          repositories: soleur\n          doppler-project: soleur-infra-privileged\n")


@row_fn("42-gh-token-is-the-app-token")
def _():
    global wf
    wf = sub(wf, "gh-token: ${{ github.token }}", "gh-token: ${{ steps.app.outputs.token }}")


@row_fn("43-composite-input-renamed")
def _():
    global comp
    comp = sub(comp, "  pr-token:\n", "  pr-tokenx:\n")


@row_fn("44-composite-pr-token-env-from-gate")
def _():
    global comp
    comp = sub(comp, "        PR_TOKEN: ${{ inputs.pr-token }}\n", "        PR_TOKEN: ${{ inputs.gh-token }}\n")


@row_fn("45-statement-before-xtrace-refusal")
def _():
    global comp
    comp = sub(comp, '        case "$-" in\n', '        echo hi\n        case "$-" in\n')


@row_fn("46-gh-app-helper-uses-gate-token")
def _():
    global comp
    comp = sub(comp, 'gh_app() { GH_TOKEN="$_pr" gh "$@"; }', 'gh_app() { GH_TOKEN="$_gate" gh "$@"; }')


@row_fn("47-header-built-with-newlines")
def _():
    global comp
    comp = sub(comp, "base64 -w0", "base64")


@row_fn("48-eval-hides-a-command")
def _():
    global comp
    comp = sub(comp, '          gh_app pr merge "$BRANCH" --squash --auto\n', '          gh_app pr merge "$BRANCH" --squash --auto\n          eval "true"\n')



# --- rows added after the fix round -------------------------------------------------------
GATE_DEF = '        gh_gate() { GH_TOKEN="$_gate" gh "$@"; }\n'


@row_fn("49-commit-identity-reverted")
def _():
    global comp
    comp = sub(comp, 'git config user.name "soleur-infra[bot]"', 'git config user.name "github-actions[bot]"')


@row_fn("50-second-pr-assignment")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        _pr="$_gate"\n')


@row_fn("51-refusal-exit-via-or")
def _():
    global comp
    i = comp.index('if [[ "$PR_TOKEN" == "$GATE_TOKEN" ]]; then')
    j = comp.index("exit 1", i)
    comp = comp[:j] + "true || exit 1" + comp[j + len("exit 1"):]


@row_fn("52-header-from-gate-with-pr-in-a-comment")
def _():
    global comp
    comp = sub(comp, """"x-access-token:${_pr}" | base64 -w0)\"""", """"x-access-token:${_gate}" | base64 -w0)" # x-access-token:${_pr}""")


@row_fn("53-bare-gh-in-a-case-arm")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        case x in x) gh pr view 1 ;; esac\n')


@row_fn("54-bare-gh-absolute-path")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        /usr/bin/gh pr ready "$BRANCH"\n')


@row_fn("55-curl-with-the-gate-token")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        curl -H "Authorization: Bearer ${_gate}" https://api.github.com/repos/${REPO}/pulls\n')


@row_fn("56-remote-action-not-allowlisted")
def _():
    global wf

    def f(d):
        d["jobs"]["open-pr"]["steps"].insert(2, {"uses": "evil/action@v1"})
    wf = struct(f)


@row_fn("57-needs-removed")
def _():
    global wf
    wf = sub(wf, "    needs: mine\n", "")


@row_fn("58-gh-app-closes-a-pr")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        gh_app pr close "$BRANCH"\n')


@row_fn("59-xtrace-refusal-without-exit")
def _():
    global comp
    comp = sub(comp, "exit 78", ":")


@row_fn("60-bearer-ok-redefined")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        _bearer_ok() { return 0; }\n')


@row_fn("61-gh-app-redefined")
def _():
    global comp
    comp = sub(comp, GATE_DEF, GATE_DEF + '        gh_app() { GH_TOKEN="$_gate" "$(command -v gh)" "$@"; }\n')


@row_fn("62-composite-shell-bash-x")
def _():
    global comp
    comp = sub(comp, "      shell: bash\n", "      shell: bash -x {0}\n")


@row_fn("63-credential-job-self-hosted")
def _():
    global wf
    wf = sub(wf, "    environment: infra-privileged\n    runs-on: ubuntu-latest\n", "    environment: infra-privileged\n    runs-on: self-hosted\n")


@row_fn("64-skip-auto-merge-true")
def _():
    global wf
    wf = sub(wf, "          " + PRT + "\n", "          " + PRT + "\n          skip-auto-merge: 'true'\n")


@row_fn("65-action-ref-is-a-branch")
def _():
    global wf
    wf = sub(wf, "DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4", "DopplerHQ/cli-action@main")

if row not in APPLY:
    sys.exit("unknown row %r" % row)
APPLY[row]()
os.makedirs(os.path.join(out, "wf"), exist_ok=True)
open(os.path.join(out, "wf", "weakness-miner.yml"), "w").write(wf)
open(os.path.join(out, "composite.yml"), "w").write(comp)
PYMUTATE

_wm_guard() { # $1 = workflows dir, $2 = composite path; prints the guard's lines
  WM_GUARD_WORKFLOWS="$1" WM_GUARD_COMPOSITE="$2" \
    WM_GUARD_CANON="$REPO_ROOT/.github/scripts/bump-inngest-bootstrap-pin.sh" \
    python3 -I "$WM_GUARD_PY" 2>&1
}
_wm_count() { # $1 = guard output; prints the number of VIOLATION lines
  printf '%s\n' "$1" | awk '/^VIOLATION /{n++} END{print n+0}'
}

GUARD_CASES=0
GUARD_RAN_ROWS=""
# The row names, listed a SECOND time and independently of the ROWS table below, so a deleted or
# duplicated row changes the set and the floor at the bottom of the file refuses to report green.
GUARD_EXPECTED_ROWS="1-pr-token-is-workflow-token 1b-pr-token-secrets-spelling 2-pr-token-deleted 3-mint-after-composite 4-environment-removed 5-third-caller-bad 7-bare-gh 8a-merge-through-gate 8b-create-through-gate 8c-edit-through-gate 9-push-without-app-header 10-check-runs-through-app 11a-equality-refusal-deleted 11b-unset-deleted 11c-step-level-gh-token 11d-pr-token-shape-check-dropped 12a-miner-in-credential-job 12b-environment-on-mine 12c-secret-in-mine 13-persist-credentials-dropped 14-extra-write-permission 15-pr-assign-swapped 16-gate-assign-swapped 17-header-from-gate-token 18-equality-refusal-inert 19-bearer-body-weakened 20-second-composite-step 21-bare-gh-env-prefixed 22-third-helper 23-gate-token-writes-a-pr-endpoint 24-merge-neutered-by-echo 25-trace-unset-after-push 26-caller-trailing-slash 27-caller-remote-spelling 28-if-or-always 29-secret-bracket-in-mine 30-mint-sibling-prefix-action 31-installation-id-changed 32-job-env-bash-env 33-download-path-widened 34-checkout-ref-dropped 35-mine-write-permission 36-mint-continue-on-error 37-mint-uses-other-action 38-mint-permissions-widened 39-mint-repositories-widened 40-mint-broad-doppler-token 41-mint-names-a-doppler-project 42-gh-token-is-the-app-token 43-composite-input-renamed 44-composite-pr-token-env-from-gate 45-statement-before-xtrace-refusal 46-gh-app-helper-uses-gate-token 47-header-built-with-newlines 48-eval-hides-a-command 49-commit-identity-reverted 50-second-pr-assignment 51-refusal-exit-via-or 52-header-from-gate-with-pr-in-a-comment 53-bare-gh-in-a-case-arm 54-bare-gh-absolute-path 55-curl-with-the-gate-token 56-remote-action-not-allowlisted 57-needs-removed 58-gh-app-closes-a-pr 59-xtrace-refusal-without-exit 60-bearer-ok-redefined 61-gh-app-redefined 62-composite-shell-bash-x 63-credential-job-self-hosted 64-skip-auto-merge-true 65-action-ref-is-a-branch"
GUARD_EXPECTED_CASES=76

t_workflow_pr_identity() {
  local real_wf="$REPO_ROOT/.github/workflows/weakness-miner.yml"
  local real_comp="$REPO_ROOT/.github/actions/bot-pr-with-synthetic-checks/action.yml"
  python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: test-weakness-miner: python3 PyYAML is required by the identity guard" >&2; exit 2; }
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
  # back RED on a named rule with the walk having found it, or the walk is blind and every
  # green below would be meaningless.
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
  if (( n == 0 )) || [[ "$out" != *"CALLERS 1"* || "$out" != *"VIOLATION G1:"* ]]; then
    printf 'FATAL: the identity guard did not flag a known-bad caller on G1 (CALLERS 1); its walk is blind. Output: %s\n' "$out" >&2
    exit 2
  fi
  GUARD_CASES=$((GUARD_CASES + 1))
  _report "identity guard H1: known-bad caller is RED on G1 ($n violations)" ok

  # H2 — a must-PASS input that differs from the canonical in permitted ways (other file and job
  # names, mint step id appmint, unrelated steps between mint and composite, no inner spaces in
  # the expression, a different mint key order): a guard that rejects everything fails here.
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
          ref: main
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
        with:
          name: digest
          path: knowledge-base/project
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

  # The mutation rows: each is applied to COPIES of the real files and must (a) land,
  # (b) turn the guard RED with the named violation id (a rule id such as C18 must appear as
  # `VIOLATION C18:`, never as a prefix of C180 or inside message text; a non-id token is a
  # message substring).
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
    local hit=0
    if [[ "$want" =~ ^[A-Z]+[0-9]*$ ]]; then
      [[ "$out" == *"VIOLATION $want:"* ]] && hit=1
    else
      [[ "$out" == *"VIOLATION"*"$want"* ]] && hit=1
    fi
    if (( hit )); then
      _report "identity guard $row: RED on $want" ok
      GUARD_RAN_ROWS+="$row "
    else
      _report "identity guard $row: RED on $want" FAIL "(got: $(printf '%s' "$out" | tr '\n' '|'))"
    fi
  done <<'ROWS'
1-pr-token-is-workflow-token|G1
1b-pr-token-secrets-spelling|G1
2-pr-token-deleted|G1
3-mint-after-composite|G2
4-environment-removed|G9
5-third-caller-bad|G1
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
15-pr-assign-swapped|C18
16-gate-assign-swapped|C18
17-header-from-gate-token|C18
18-equality-refusal-inert|C6
19-bearer-body-weakened|C15
20-second-composite-step|C2
21-bare-gh-env-prefixed|C9
22-third-helper|C17
23-gate-token-writes-a-pr-endpoint|C11
24-merge-neutered-by-echo|C10
25-trace-unset-after-push|C14
26-caller-trailing-slash|G0
27-caller-remote-spelling|G0
28-if-or-always|G10
29-secret-bracket-in-mine|G13
30-mint-sibling-prefix-action|G11
31-installation-id-changed|G18
32-job-env-bash-env|G15
33-download-path-widened|G17
34-checkout-ref-dropped|G17
35-mine-write-permission|G13
36-mint-continue-on-error|G19
37-mint-uses-other-action|G3
38-mint-permissions-widened|G4
39-mint-repositories-widened|G5
40-mint-broad-doppler-token|G6
41-mint-names-a-doppler-project|G7
42-gh-token-is-the-app-token|G8
43-composite-input-renamed|C1
44-composite-pr-token-env-from-gate|C4
45-statement-before-xtrace-refusal|C5
46-gh-app-helper-uses-gate-token|C8
47-header-built-with-newlines|C13
48-eval-hides-a-command|C16
49-commit-identity-reverted|C19
50-second-pr-assignment|C20
51-refusal-exit-via-or|C6
52-header-from-gate-with-pr-in-a-comment|C18
53-bare-gh-in-a-case-arm|C9
54-bare-gh-absolute-path|C9
55-curl-with-the-gate-token|C16
56-remote-action-not-allowlisted|G11
57-needs-removed|G13
58-gh-app-closes-a-pr|C10
59-xtrace-refusal-without-exit|C5
60-bearer-ok-redefined|C20
61-gh-app-redefined|C20
62-composite-shell-bash-x|C2
63-credential-job-self-hosted|G20
64-skip-auto-merge-true|G20
65-action-ref-is-a-branch|G20
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
# Anti-vacuity floor for the identity guard: the case count AND the set of rows that went RED on
# their named id must match what was written, so a deleted, duplicated or neutered row cannot
# report green. Printed with printf and exit, never through _report, which is the helper this
# floor backstops.
if (( GUARD_CASES != GUARD_EXPECTED_CASES )); then
  printf 'FAIL: identity guard ran %s cases, expected %s\n' "$GUARD_CASES" "$GUARD_EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$(printf '%s\n' $GUARD_RAN_ROWS | sort)" != "$(printf '%s\n' $GUARD_EXPECTED_ROWS | sort)" ]]; then
  printf 'FAIL: identity guard rows that went RED on their id differ from the expected set\n' >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
