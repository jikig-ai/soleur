#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015,SC2034,SC1091  # `A && B || C` is the row idiom; the row table is a QUOTED heredoc of shell text and the python oracle is single-quoted on purpose; a few globals are read by sourced-in-place helpers
# Guard 1 of the W2 plan (knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md):
# the destructive-command PreToolUse hook (plugins/soleur/hooks/destructive-command-guard.sh, ADR-274).
#
# PROPERTY. A Bash tool call whose command, after lexing and wrapper unwrapping, runs a command in the
# D1 set receives `ask` or `deny`, never an implicit allow, in every spelling bash reads as that command
# (within the D2 scope); a command in the same family outside D1 receives no decision; an envelope the
# hook cannot read receives `ask`; the kill switch (SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1) and nothing else
# turns the guard off; a missing `jq` or `perl` degrades to a raw scan, never to an implicit allow.
#
# ASSEMBLY. Three code paths run from envelope to decision, and each has its own rows: the lexer path
# (the chokepoint), the zero-spawn prefilter skip (which may only skip what the lexer path would also
# allow: every boundary character has a row), and the degraded raw-scan path (jq or perl missing). Plus
# the registration (hooks.json), the output shape (envelope, escape hatch, issues URL) and the kill switch.
#
# THE ORACLE (Phase 1.2). The expected decision of an EXECUTED row is never what the hook printed. The
# row's command is run for real by `bash -c` against a PATH that holds RECORDING STUBS ONLY (every stub
# appends its argv and cwd to a file and exits 0), with a temp HOME and a temp working tree; the shell
# supplies lexing, quoting, tilde and variable expansion, globbing, `cd`, wrappers and nesting. A small
# rule table written in python (an independent second implementation of D1, sharing no code with the hook)
# turns the recorded argv into none|ask|deny. Because the oracle's HOME is empty, a glob such as `~/*`
# stays literal in the recorded argv and is read as "the contents of home", which is how the hook reads it.
#   * The oracle can never run a destructive command: a canary ABORTS the suite before any row unless
#     `rm`, `terraform` and `git` resolve inside the stub directory; every executed row is linted for a
#     PATH reset, `command -p`, `exec`, and any absolute binary path in command position; the temp
#     tree and HOME are re-checked after every row.
#   * Only rows whose command words are bare names execute (kind X, Xh, C, D). A row with an absolute
#     binary path, a glob that would expand against the REAL root, a NUL byte, garbage stdin, a
#     non-string command, or a policy ask the shell cannot reproduce (an unresolvable `cd`) carries a
#     LITERAL expected value (kind L) and is never executed.
#   * Every executed row also carries the author's INTENT; the suite requires oracle == intent before it
#     judges the hook, so a bug in the rule table cannot silently move an expectation (a disagreement is
#     reported as a harness defect, not as a hook failure).
#   * kind D rows are dead code a static hook cannot see (`false && terraform destroy`): their expected
#     value is a literal ask or deny AND they are executed once to prove the label honest (the stub must
#     NOT fire), so they are excluded from the executed-stub-fired comparison without being unchecked.
#   Stated honestly: the rule table is a second implementation by the same author; the mutation suite and
#   the in-suite harness rows below are what check it.
#
# THE ROW TABLE is a QUOTED heredoc, one row per line: `kind @@ label @@ want @@ cwd @@ command`. The
# command is the rest of the line, raw (no shell expansion, so quotes, `$`, backticks and backslashes
# are exactly what the agent would send). `@NL@` and `@TAB@` stand for a newline and a tab, `@TREE@`
# `@SUB@` `@HOME@` `@HOMEPARENT@` `@ROOT@` `@LINK@` `@R1@`..`@R5@` for fixture paths, and a `-` cwd is
# the working tree.
#
# HARNESS ROWS (Guard 1): (a) delete one expected-ask row from a COPY of this suite -> the floor fails
# (run below in a count-only mode so it costs milliseconds; the control copy must NOT trip it);
# (b) make the `terraform` stub record nothing -> the oracle expectation for `terraform destroy` turns
# from ask to none and the same comparison the rows use reddens against a hook that answers ask;
# (c) the must-PASS list and the ordinary-command corpus (kind C) drive inputs that are not the canonical
# destructive spelling, and the ask rate on that corpus is printed and must be 0.
# (a2) a reduced run prints a REDUCED RUN banner first and a NOT THE FULL GATE line before its summary; (lint) the lint
# that keeps the oracle from executing a destructive command is fed every unsafe spelling it must refuse (two spaces or a tab in
# `command -p`, `then exec`, an absolute redirect, a cd to an absolute path) and the look-alikes it must accept, a suite COPY
# carrying an unsafe row must stop with exit 2, and a COPY whose oracle deletes the canary must stop with exit 2.
#
# DOCUMENTED RESIDUALS the rows deliberately do not depend on: an identical `bash -c`/`eval` string is
# lexed once, so no must-ASK row relies on a second inner occurrence under a different `cd`; a raw-scan
# miss with jq missing is an allow (stated in the hook header and ADR-274).
#
# Anti-vacuity: `CHECKED` moves at the call site (never in pass/fail), pass + fail must equal it, an
# instrument self-test drives both helpers, and the row floor is a literal directly above its `if`,
# reported by a direct printf + exit 1 and never through the helpers it backstops.
#
# Run: bash plugins/soleur/test/destructive-command-guard-hook.test.sh
# Time: 35 s on a quiet machine, ~110 s under load (every executed row spawns the hook, a shell and the oracle). The 60 s budget
#      in the mutation suite's header is the quiet figure.
# A run that is narrowed or redirected by a seam below says so on its FIRST line ([REDUCED RUN: ...], [COUNT-ONLY RUN: ...],
# [REDIRECTED RUN: ...]) and again before its summary ([NOT THE FULL GATE: ...]); the exit status is unchanged.
# Env: GUARD_HOOK (default: the real hook; point at a throwaway stub to prove the rows are not vacuous),
#      GUARD_REPO_ROOT (the tree the hook, lexer, hooks.json and test lib are read from; the mutation suite
#      points it at a mutated COPY) and GUARD_FAST_COUNT (used only by the in-suite meta copy),
#      DCG_ROWS (reduced mode, used only by destructive-command-guard-mutation.test.sh: an ERE matched
#      against each row LABEL; rows that do not match are not run and not counted, the unlabelled static,
#      registration and harness checks always run, and the MIN_CASES floor (see its definition) is replaced by the floor of the
#      selected rows, so a reduced run proves the selected rows and nothing else).
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C
set -uo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SUITE_DIR/../../.." && pwd)"
SEAM_ROOT="${GUARD_REPO_ROOT:-}"; SEAM_HOOK="${GUARD_HOOK:-}"
REPO_ROOT="${GUARD_REPO_ROOT:-$DEFAULT_ROOT}"
GUARD_HOOK="${GUARD_HOOK:-$REPO_ROOT/plugins/soleur/hooks/destructive-command-guard.sh}"
HOOKS_JSON="$REPO_ROOT/plugins/soleur/hooks/hooks.json"
LEXER="$REPO_ROOT/plugins/soleur/hooks/lib/shell-argv.pl"
SELF="$SUITE_DIR/$(basename "${BASH_SOURCE[0]}")"
FAST="${GUARD_FAST_COUNT:-}"
ROWSEL="${DCG_ROWS:-}"
# The plugin README sentences the doc rows below require, each at the START of a line inside the `## Destructive-Command Guard`
# section (HTML comments and fenced code stripped first), exactly once. They live HERE and nowhere else in the suite: rewriting
# a sentence in the README is a one-edit change to the matching variable. The kill-switch sentence is the same kind of anchor.
README_SENT_NONCOVERAGE='The guard does not cover a plain `terraform apply`, secret writes, SQL, non-Bash tools, `terragrunt` or `pulumi` destroy, or indirect command forms (scripts or heredocs fed to a shell, wrappers it does not unwrap, obfuscated command names), and is not a substitute for scoped credentials.'
README_SENT_HOSTED="Not active in Soleur-hosted sessions: hosted Bash runs in the sandbox under the workspace's approval mode, and in the default autonomous mode (after the owner's one-time acknowledgement) commands outside a short blocklist run without a prompt; this guard does not add one."
README_SENT_KILL='`SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` turns it off.'
# Loud first line for any run that is not the full gate. NOTFULL is repeated before the summary.
NOTFULL=""
if [[ -n "$ROWSEL" ]]; then
  printf '[REDUCED RUN: DCG_ROWS=%s — not the full gate]\n' "$ROWSEL"; NOTFULL="${NOTFULL:+$NOTFULL; }DCG_ROWS=$ROWSEL selects a subset of the rows"
fi
if [[ -n "$FAST" ]]; then
  printf '[COUNT-ONLY RUN: GUARD_FAST_COUNT is set, no hook is executed — not the full gate]\n'; NOTFULL="${NOTFULL:+$NOTFULL; }GUARD_FAST_COUNT skips every execution"
fi
if [[ -n "$SEAM_ROOT" && "$SEAM_ROOT" != "$DEFAULT_ROOT" ]]; then
  printf '[REDIRECTED RUN: GUARD_REPO_ROOT=%s — the live tree is not what is judged]\n' "$SEAM_ROOT"; NOTFULL="${NOTFULL:+$NOTFULL; }GUARD_REPO_ROOT points at another tree"
fi
if [[ -n "$SEAM_HOOK" ]]; then
  printf '[REDIRECTED RUN: GUARD_HOOK=%s — the live hook is not what is judged]\n' "$SEAM_HOOK"; NOTFULL="${NOTFULL:+$NOTFULL; }GUARD_HOOK points at another hook"
fi
# want_row <label>: always true unless DCG_ROWS (reduced mode) is set; then the label must match it.
want_row_quiet() { [[ -z "$ROWSEL" ]] || [[ "$1" =~ $ROWSEL ]]; }
SELECTED=0
want_row() { # the counter moves here, at the call site, for every row that will run
  if [[ -z "$ROWSEL" ]] || [[ "$1" =~ $ROWSEL ]]; then SELECTED=$((SELECTED + 1)); return 0; fi
  return 1
}

PASS_COUNT=0
FAIL_COUNT=0
CHECKED=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }
# A verdict at the call site: the counter moves HERE, independent of pass()/fail().
chk() { # chk <label> <ok|anything else> [detail]
  CHECKED=$((CHECKED + 1))
  if [[ "$2" == ok ]]; then pass "$1"; else fail "$1${3:+ -- $3}"; fi
}

# Instrument self-test: both helpers must record before any row runs.
_iv_p="$PASS_COUNT"; _iv_f="$FAIL_COUNT"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$PASS_COUNT" -ne $((_iv_p + 1)) || "$FAIL_COUNT" -ne $((_iv_f + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
PASS_COUNT=0; FAIL_COUNT=0

harness_die() { printf 'HARNESS: %s\n' "$1" >&2; exit 2; }

JQ_BIN="$(command -v jq)" || harness_die "jq is required"
PERL_BIN="$(command -v perl)" || harness_die "perl is required"
PY_BIN="$(command -v python3)" || harness_die "python3 is required"
REAL_GIT="$(command -v git)" || harness_die "git is required"
TIMEOUT_BIN="$(command -v timeout)" || harness_die "timeout is required"
[[ -n "${BASH:-}" && -x "$BASH" ]] || harness_die "cannot resolve the running bash"

# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
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

WORK="$(mktemp -d "$TMPDIR/dcg-hook.XXXXXXXX")" || harness_die "mktemp failed"
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"
assert_fixture_dir "$WORK"
cd "$WORK" || harness_die "cannot enter the scratch root"

# --- the fixture world: HOME, a working tree and the ancestors between them -------------------------
ROOT="$WORK/root"
HOMEPARENT="$ROOT/h"
HOME_W="$HOMEPARENT/home"
HOME_LINK="$ROOT/homelink"
TREE="$ROOT/t/tree"
mkdir -p "$HOME_W" "$TREE/sub" "$TREE/build" "$TREE/node_modules" "$WORK/stub" "$WORK/rec" "$WORK/repos" "$WORK/decoy" "$WORK/meta" \
  || harness_die "mkdir failed"
ln -s "$HOME_W" "$HOME_LINK" && ln -s "$HOME_W" "$TREE/link" || harness_die "symlink failed"
: > "$TREE/.canary"
R1="$WORK/repos/r1"; R2="$WORK/repos/r2"; R3="$WORK/repos/r3"; R4="$WORK/repos/r4"; R5="$WORK/repos/r5"
STUB="$WORK/stub"
CUR_HOME="$HOME_W"

# Every fixture git call strips inherited GIT_* variables BY PREFIX (a lefthook-exported GIT_DIR must not
# redirect it onto the caller's repository). GIT_UNSET (`env -u` over every exported GIT_* name) is also
# handed to the hook runs below; the in-process scrub makes the shared fixture-env tripwire (sourced next)
# pass instead of aborting a hook-driven run.
GIT_UNSET=()
while IFS= read -r _v; do [[ -n "$_v" ]] && GIT_UNSET+=(-u "$_v"); done < <(compgen -e | grep '^GIT_' || true)
for ((_i = 1; _i < ${#GIT_UNSET[@]}; _i += 2)); do unset "${GIT_UNSET[$_i]}"; done
# shellcheck source=plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
mkrepo() { # mkrepo <dir> <current-branch> <origin-head-branch|-> <upstream-head-branch|->
  local d="$1" cur="$2" oh="$3" uh="$4"
  assert_fixture_dir "$d"
  mkdir -p "$d" || return 1
  (
    git_fixture_env "$d" || exit 1
    git -c core.hooksPath=/dev/null init -q -b "$cur" "$d" >/dev/null 2>&1 || exit 1
    git -C "$d" -c core.hooksPath=/dev/null commit -q --allow-empty -m init >/dev/null 2>&1 || exit 1
    git -C "$d" remote add origin /nonexistent/origin.git || exit 1
    git -C "$d" update-ref refs/remotes/origin/trunk HEAD || exit 1
    if [[ "$oh" != - ]]; then git -C "$d" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$oh" || exit 1; fi
    if [[ "$uh" != - ]]; then
      git -C "$d" remote add upstream /nonexistent/upstream.git || exit 1
      git -C "$d" update-ref refs/remotes/upstream/dev2 HEAD || exit 1
      git -C "$d" symbolic-ref refs/remotes/upstream/HEAD "refs/remotes/upstream/$uh" || exit 1
    fi
  ) </dev/null
}

# --- the recording stubs -----------------------------------------------------------------------------
# Every stub records `argc NUL cwd NUL name NUL arg NUL ...` (one file per invocation: a pipeline runs its
# members concurrently) and exits 0. They call no external program.
STUB_NAMES="rm terraform tofu terragrunt pulumi git sudo doas env timeout nice nohup doppler aws-vault op xargs ls cat grep find docker npm wc tee sort head tail sed awk curl jq tar python3 diff mkdir cp mv date make node touch sleep chmod kubectl psql"
if [[ -z "$FAST" ]]; then
  assert_fixture_dir "$STUB"
  cat > "$STUB/rm" <<'STUBEOF'
#!/bin/sh
[ -n "$STUB_REC" ] || exit 0
{ printf "%s\0" "$#" "$PWD" "${0##*/}"; for a in "$@"; do printf "%s\0" "$a"; done; } >> "$STUB_REC/$STUB_SERIAL.$$"
exit 0
STUBEOF
  chmod +x "$STUB/rm"
  for _n in $STUB_NAMES; do [[ "$_n" == rm ]] || cp "$STUB/rm" "$STUB/$_n"; done
  # The shells are links to the real bash: a `bash -c` row needs a bash on the stub PATH, and with a
  # stub-only PATH it can only ever run stubs.
  for _n in bash sh dash zsh ksh; do ln -s "$BASH" "$STUB/$_n"; done
  # CANARY: abort the whole suite unless the destructive names resolve INSIDE the stub directory.
  for _n in rm terraform git; do
    _res="$(env -i "PATH=$STUB" "$BASH" -c "command -v $_n" 2>/dev/null)"
    [[ "$_res" == "$STUB/$_n" ]] || harness_die "CANARY: '$_n' resolves to '${_res:-nothing}', not into the stub dir; refusing to run any row"
  done
  # A broken-stub dir for harness row (b): identical, except the terraform stub records nothing.
  STUB_BROKEN="$WORK/stub-broken"; mkdir -p "$STUB_BROKEN"
  assert_fixture_dir "$STUB_BROKEN"
  for _n in $STUB_NAMES; do ln -s "$STUB/$_n" "$STUB_BROKEN/$_n"; done
  rm -f "$STUB_BROKEN/terraform"; printf '#!/bin/sh\nexit 0\n' > "$STUB_BROKEN/terraform"; chmod +x "$STUB_BROKEN/terraform"
  for _n in bash sh dash zsh ksh; do ln -s "$BASH" "$STUB_BROKEN/$_n"; done
  # The fixture repositories for the default-branch rows.
  mkrepo "$R1" feature trunk dev2 || harness_die "fixture repo r1"
  mkrepo "$R2" trunk trunk - || harness_die "fixture repo r2"
  mkrepo "$R3" main trunk - || harness_die "fixture repo r3"
  mkrepo "$R4" trunk - - || harness_die "fixture repo r4"
  mkrepo "$R5" master - - || harness_die "fixture repo r5"
else
  STUB_BROKEN="$WORK/stub-broken"
fi

# A jq shim that fails ONLY on `-nc` (the hook's output builder) and hands every other call to the real jq: the hook can read its
# envelope but cannot build its decision output (the fixed fallback).
if [[ -z "$FAST" ]]; then
  assert_fixture_dir "$WORK/shim-jqnc"
  mkdir -p "$WORK/shim-jqnc" || harness_die "shim mkdir"
  printf '#!/bin/sh\ncase "$1" in -nc) exit 3 ;; esac\nexec "%s" "$@"\n' "$JQ_BIN" > "$WORK/shim-jqnc/jq"; chmod +x "$WORK/shim-jqnc/jq"
fi
# A jq shim that errors on every regex function (a jq built without Oniguruma) and hands everything else to the real jq.
if [[ -z "$FAST" ]]; then
  assert_fixture_dir "$WORK/shim-jqre"
  mkdir -p "$WORK/shim-jqre" || harness_die "shim mkdir"
  printf '#!/bin/sh\nfor a in "$@"; do\n  case "$a" in *gsub*|*sub\(*|*test\(*|*match\(*|*capture\(*|*scan\(*|*splits\(*|*ascii_downcase*) echo "jq: error: regex support is not built in" >&2; exit 5 ;; esac\ndone\nexec "%s" "$@"\n' "$JQ_BIN" > "$WORK/shim-jqre/jq"; chmod +x "$WORK/shim-jqre/jq"
fi
# A symlink farm of every /usr/bin and /bin utility except the removed ones: the jq-less and perl-less PATHs.
farm_make() { # farm_make <name> <removed...>  -> $WORK/farm-<name>
  local d="$WORK/farm-$1" r t; shift
  assert_fixture_dir "$d"
  mkdir -p "$d" || harness_die "farm mkdir"
  ln -sf /usr/bin/* "$d"/ 2>/dev/null
  if [[ -d /bin && ! -L /bin ]]; then ln -sf /bin/* "$d"/ 2>/dev/null; fi
  for t in jq perl git; do [[ -e "$d/$t" ]] || ln -sf "$(command -v "$t")" "$d/$t"; done
  for r in "$@"; do rm -f "$d/$r"; done
}
if [[ -z "$FAST" ]]; then
  farm_make nojq jq
  farm_make noperl perl
  farm_make notr tr
  farm_make none jq perl
  # a perl that exists but dies without printing anything
  farm_make badperl perl
  assert_fixture_dir "$WORK"
  printf '#!/bin/sh\nexit 255\n' > "$WORK/farm-badperl/perl"; chmod +x "$WORK/farm-badperl/perl"
fi

# --- the python rule table (D1, independent of the hook) ---------------------------------------------
assert_fixture_dir "$WORK"
cat > "$WORK/oracle.py" <<'PYEOF'
import os, sys

mode = sys.argv[1]

if mode == "lex":
    data = sys.stdin.buffer.read().split(b"\0")
    if data and data[-1] == b"":
        data.pop()
    i = 0
    while i < len(data):
        f = data[i]
        if f == b"C":
            ctx = data[i + 1].decode()
            n = int(data[i + 2])
            words = [data[i + 4 + 2 * k].decode("utf-8", "replace") for k in range(n)]
            print("%s|%s" % (ctx, " ".join(words)))
            i += 3 + 2 * n
        elif f == b"OK":
            print("OK")
            i += 1
        elif f == b"E":
            print("E:%s" % data[i + 1].decode())
            i += 2
        else:
            print("??")
            i += 1
    sys.exit(0)

HOME = os.environ["ORACLE_HOME"]
GIT = os.environ["ORACLE_GIT"]
RANK = {"none": 0, "ask": 1, "deny": 2}
GITENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
GITENV.update({"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"})


def worst(a, b):
    return a if RANK[a] >= RANK[b] else b


def read_records(path):
    recs = []
    for name in sorted(os.listdir(path)):
        if not name.startswith(os.environ["ORACLE_SERIAL"] + "."):
            continue
        parts = open(os.path.join(path, name), "rb").read().split(b"\0")
        if parts and parts[-1] == b"":
            parts.pop()
        i = 0
        while i < len(parts):
            argc = int(parts[i])
            cwd = parts[i + 1].decode("utf-8", "surrogateescape")
            argv = [p.decode("utf-8", "surrogateescape") for p in parts[i + 2:i + 3 + argc]]
            recs.append((cwd, argv))
            i += 3 + argc
    return recs


def collapse(p):
    return "/" + p.lstrip("/") if p.startswith("/") else p


def anc_or_eq(a, b):
    a = a.rstrip("/") or "/"
    b = b.rstrip("/") or "/"
    return a == "/" or b == a or b.startswith(a + "/")


def resolve_target(t, cwd):
    """The path rm would operate on: a trailing slash or a glob suffix follows a symlink, a bare name does not."""
    if t == "":
        return None, False
    follow = glob = False
    d = t
    if t == "*":
        d, follow, glob = ".", True, True
    elif t.endswith("/*"):
        d, follow, glob = (t[:-2] or "/"), True, True
    elif t.endswith("/"):
        follow = True
        if t.rstrip("/").split("/")[-1] == ".":
            return None, False  # './' and 'x/./' end in '.': rm refuses it
    absd = d if d.startswith("/") else cwd + "/" + d
    if follow:
        return collapse(os.path.realpath(absd)), glob
    stripped = absd.rstrip("/")
    head, tail = os.path.split(stripped)
    if tail == ".":
        return None, False  # rm refuses '.'
    if tail == "..":
        return collapse(os.path.realpath(absd)), False
    return collapse(os.path.join(os.path.realpath(head or "/"), tail)), False


def rm_decision(args, cwd):
    recursive, targets, end = False, [], False
    for a in args:
        if end:
            targets.append(a)
        elif a == "--":
            end = True
        elif a.startswith("--"):
            if a == "--recursive":
                recursive = True
        elif a.startswith("-") and len(a) > 1:
            if "r" in a[1:] or "R" in a[1:]:
                recursive = True
        else:
            targets.append(a)
    if not recursive:
        return "none"
    hl = os.path.normpath(HOME)
    hp = os.path.realpath(HOME)
    cwdp = os.path.realpath(cwd)
    out = "none"
    for t in targets:
        p, glob = resolve_target(t, cwdp)
        if p is None:
            continue
        if anc_or_eq(p, hl) or anc_or_eq(p, hp):
            out = worst(out, "deny")
        elif anc_or_eq(p, cwdp) and not glob:
            out = worst(out, "ask")  # the contents of the cwd (./*) are routine; the cwd itself is not
    return out


def tf_decision(args):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 1
    if i >= len(args):
        return "none"
    sub, rest = args[i], args[i + 1:]
    if sub == "destroy":
        return "ask"
    if sub == "apply" and any(a in ("-destroy", "--destroy", "-destroy=true", "--destroy=true") for a in rest):
        return "ask"
    return "none"


def git_out(repo, *a):
    import subprocess
    try:
        r = subprocess.run([GIT, "-C", repo] + list(a), capture_output=True, text=True, env=GITENV, stdin=subprocess.DEVNULL, timeout=20)
    except Exception:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def git_decision(args, cwd):
    repo, i = cwd, 0
    while i < len(args):
        a = args[i]
        if a == "-C":
            repo = os.path.join(repo, args[i + 1]) if i + 1 < len(args) else repo
            i += 2
        elif a == "-c":
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            break
    if i >= len(args) or args[i] != "push":
        return "none"
    force = delete = allf = mirror = repo_opt = False
    pos, end, j = [], False, i + 1
    while j < len(args):
        a = args[j]
        if end:
            pos.append(a)
        elif a == "--":
            end = True
        elif a.startswith("--"):
            name = a.split("=", 1)[0]
            if name in ("--force", "--force-with-lease", "--force-if-includes"):
                force = True
            elif name == "--delete":
                delete = True
            elif name == "--all":
                allf = True
            elif name == "--mirror":
                mirror = True
            elif name == "--repo":
                repo_opt = True
                if "=" not in a:
                    j += 1
            elif name in ("--push-option", "--receive-pack", "--exec"):
                if "=" not in a:
                    j += 1
        elif a.startswith("-") and len(a) > 1:
            for k in range(1, len(a)):
                c = a[k]
                if c == "f":
                    force = True
                elif c == "d":
                    delete = True
                elif c == "o":
                    if k == len(a) - 1:
                        j += 1
                    break
        else:
            pos.append(a)
        j += 1
    remote = None if repo_opt else (pos[0] if pos else None)
    refspecs = pos if repo_opt else pos[1:]
    named = remote or "origin"
    defaults = {"main", "master"}
    head = git_out(repo, "symbolic-ref", "--short", "refs/remotes/%s/HEAD" % named)
    if head:
        defaults.add(head[len(named) + 1:] if head.startswith(named + "/") else head)
    cur = git_out(repo, "symbolic-ref", "--short", "HEAD")
    if (allf or mirror) and force:
        return "ask"
    dests = []
    for r in refspecs:
        f = False
        if r.startswith("+"):
            f, r = True, r[1:]
        dele = False
        if ":" in r:
            src, dst = r.split(":", 1)
            if dst.startswith("+"):
                f, dst = True, dst[1:]
            dele = src == ""
        else:
            dst = cur if r == "HEAD" else r
        if dst and dst.startswith("refs/heads/"):
            dst = dst[len("refs/heads/"):]
        dests.append((dst, f, dele or delete))
    if not refspecs and not allf and not mirror and cur:
        dests.append((cur, False, False))
    for dst, f, dele in dests:
        if dst in defaults and (force or f or dele):
            return "ask"
    return "none"


def is_assign(a):
    name = a.split("=", 1)[0]
    return "=" in a and name != "" and not name[0].isdigit() and name.replace("_", "a").isalnum()


def unwrap(name, args):
    i, n = 0, len(args)
    if name == "sudo":
        vals = {"-u", "-g", "-h", "-p", "-C", "-r", "-t", "-T", "-U", "-D", "-R", "--user", "--group", "--host", "--prompt", "--chdir", "--chroot", "--role", "--type"}
        while i < n and args[i].startswith("-") and args[i] != "-":
            a = args[i]
            i += 1
            if a == "--":
                break
            if a in vals:
                i += 1
        while i < n and is_assign(args[i]):
            i += 1
    elif name == "doas":
        while i < n and args[i].startswith("-") and args[i] != "-":
            a = args[i]
            i += 1
            if a == "--":
                break
            if a in ("-u", "-C"):
                i += 1
    elif name == "env":
        while i < n:
            a = args[i]
            if a == "--":
                i += 1
                break
            if a in ("-u", "--unset", "-C", "--chdir"):
                i += 2
            elif a.startswith("-") and a != "-":
                i += 1
            elif is_assign(a):
                i += 1
            else:
                break
    elif name == "timeout":
        while i < n and args[i].startswith("-"):
            a = args[i]
            i += 1
            if a in ("-s", "-k", "--signal", "--kill-after"):
                i += 1
        i += 1
    elif name == "nice":
        while i < n and args[i].startswith("-"):
            a = args[i]
            i += 1
            if a in ("-n", "--adjustment"):
                i += 1
    return args[i:]


def decide(argv, cwd, depth=0):
    if not argv or depth > 8:
        return "none"
    name, args = os.path.basename(argv[0]), argv[1:]
    d = "none"
    if name == "rm":
        d = rm_decision(args, cwd)
    elif name in ("terraform", "tofu"):
        d = tf_decision(args)
    elif name == "git":
        d = git_decision(args, cwd)
    elif name in ("sudo", "doas", "env", "timeout", "nice", "nohup"):
        d = decide(unwrap(name, args), cwd, depth + 1)
    for idx, a in enumerate(args):
        if a == "--":
            d = worst(d, decide(args[idx + 1:], cwd, depth + 1))
    return d


recs = read_records(sys.argv[2])
best = "none"
for cwd, argv in recs:
    best = worst(best, decide(argv, cwd))
print("%s %d" % (best, len(recs)))
PYEOF

# --- helpers: placeholders, the oracle, the hook driver ---------------------------------------------
subst() {
  local s="$1"
  s="${s//@HOMEPARENT@/$HOMEPARENT}"; s="${s//@HOMEPHYS@/$HOME_W}"; s="${s//@HOME@/$CUR_HOME}"
  s="${s//@ROOT@/$ROOT}"; s="${s//@SUB@/$TREE/sub}"; s="${s//@TREE@/$TREE}"; s="${s//@LINK@/$TREE/link}"
  s="${s//@R1@/$R1}"; s="${s//@R2@/$R2}"; s="${s//@R3@/$R3}"; s="${s//@R4@/$R4}"; s="${s//@R5@/$R5}"
  s="${s//@NL@/$'\n'}"; s="${s//@TAB@/$'\t'}"
  SUBST_OUT="$s"
}

# The oracle may only execute a row whose command words are bare names. The lint is applied to the RAW row template (placeholders such
# as @TREE@ are not paths yet), so any literal `/` in command position, in a redirect target or after a cd is a real filesystem path.
LEAD_RE='(^|[;&|(`{!]|\$\(|(^|[[:space:]])(then|do|else|elif|if|while|until|time))[[:space:]]*'
EXEC_LINT_RE="${LEAD_RE}/"
EXEC_LINT_EXEC_RE="${LEAD_RE}exec([[:space:]]|\$)"
EXEC_LINT_CMDP_RE='(^|[^[:alnum:]_-])command[[:space:]]+-[a-zA-Z]*p'
EXEC_LINT_CD_RE="${LEAD_RE}(builtin[[:space:]]+)?(cd|pushd)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+/"
EXEC_LINT_REDIR_RE='>[|>]?[[:space:]]*(/[^[:space:];&|)<>]*)'
safe_to_execute() { # <raw command template>
  local rest="$1" tgt
  case "$1" in
    *PATH=*|*"command -p"*|*"/bin/"*|*"/sbin/"*|*"/usr/"*|*"hash "*|*"enable "*|*"builtin "*) return 1 ;;
  esac
  [[ "$1" =~ $EXEC_LINT_RE ]] && return 1
  [[ "$1" =~ $EXEC_LINT_EXEC_RE ]] && return 1
  [[ "$1" =~ $EXEC_LINT_CMDP_RE ]] && return 1
  [[ "$1" =~ $EXEC_LINT_CD_RE ]] && return 1
  # a redirect to an absolute path writes outside the fixture world, except /dev/null
  while [[ "$rest" =~ $EXEC_LINT_REDIR_RE ]]; do
    tgt="${BASH_REMATCH[1]}"
    [[ "$tgt" == /dev/null ]] || return 1
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  return 0
}

ORC=none; ORC_N=0; ORACLE_SERIAL=0
oracle_derive() { # <cmd> <cwd> <home> [stub-dir]  -> ORC (none|ask|deny), ORC_N (recorded invocations)
  local cmd="$1" cwd="$2" home="$3" stub="${4:-$STUB}" recf="$WORK/rec" out
  ORC=none; ORC_N=0
  [[ -n "$FAST" ]] && return 0
  ORACLE_SERIAL=$((ORACLE_SERIAL + 1))
  ( cd "$cwd" && "$TIMEOUT_BIN" 20 env -i "PATH=$stub" "HOME=$home" "STUB_REC=$recf" "STUB_SERIAL=$ORACLE_SERIAL" LC_ALL=C TERM=dumb \
      "$BASH" -c "$cmd"$'\nwait' ) </dev/null >/dev/null 2>&1
  # The oracle must never have touched the world it ran in.
  [[ -e "$TREE/.canary" && -d "$HOME_W" && -d "$TREE/sub" && -d /usr/bin ]] || harness_die "the oracle disturbed its fixture world while running: ${cmd:0:80}"
  out="$(env "ORACLE_HOME=$home" "ORACLE_GIT=$REAL_GIT" "ORACLE_SERIAL=$ORACLE_SERIAL" "$PY_BIN" -I -S "$WORK/oracle.py" rules "$recf" </dev/null 2>/dev/null)" || out=""
  case "$out" in
    none\ *|ask\ *|deny\ *) ORC="${out%% *}"; ORC_N="${out##* }" ;;
    *) ORC="oracle-error" ;;
  esac
}

HOOK_OUT=""; HOOK_ERR=""; HOOK_RC=0
ERRF="$WORK/hook.err"
INF="$WORK/hook.in"
# hook_run <stdin-text> [ENV=VAL ...]: the hook runs with the real PATH unless PATH= is passed.
hook_run() {
  local in="$1"; shift
  HOOK_OUT=""; HOOK_ERR=""; HOOK_RC=0
  [[ -n "$FAST" ]] && return 0
  assert_fixture_dir "$INF"
  printf '%s' "$in" > "$INF"
  HOOK_OUT="$("$TIMEOUT_BIN" 30 env ${GIT_UNSET[@]+"${GIT_UNSET[@]}"} -u SOLEUR_DISABLE_DESTRUCTIVE_GUARD -u CLAUDE_PROJECT_DIR \
    "HOME=$CUR_HOME" "$@" "$BASH" "$GUARD_HOOK" <"$INF" 2>"$ERRF")"; HOOK_RC=$?
  HOOK_ERR="$(cat "$ERRF" 2>/dev/null)"
}
mkjson() { # <command> <cwd>; the command goes in through a file, not an argument (one argument is capped at 128 KB)
  "$JQ_BIN" -nc --rawfile c <(printf '%s' "$1") --arg cwd "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$cwd,session_id:"s-1"}'
}
GOT=""
classify() {
  GOT=""
  if [[ "$HOOK_RC" -ne 0 ]]; then GOT="error(rc=$HOOK_RC)"; return 0; fi
  if [[ -z "$HOOK_OUT" ]]; then GOT=none; return 0; fi
  local d
  d="$(printf '%s' "$HOOK_OUT" | "$JQ_BIN" -r 'select(type=="object" and (.hookSpecificOutput|type)=="object" and .hookSpecificOutput.hookEventName=="PreToolUse") | .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" || d=""
  case "$d" in ask|deny) GOT="$d" ;; *) GOT="malformed" ;; esac
}
# The ONE comparison every row uses (harness row (b) drives it directly).
verdict_of() { [[ "$1" == "$2" ]] && printf 'ok' || printf 'bad'; }

ROWS_EXEC=0; ROWS_LIT=0; ROWS_DEAD=0; CORPUS_N=0; CORPUS_ASK=0; CORPUS_ERR=0
# run_row <kind> <label> <want> <cwd-template> <command-template>
run_row() {
  local kind="$1" label="$2" want="$3" cwdt="$4" cmdt="$5" cmd cwd
  want_row "$label" || return 0
  [[ "$cwdt" == - ]] && cwdt='@TREE@'
  CUR_HOME="$HOME_W"; [[ "$kind" == Xh ]] && CUR_HOME="$HOME_LINK"
  subst "$cmdt"; cmd="$SUBST_OUT"; subst "$cwdt"; cwd="$SUBST_OUT"
  case "$kind" in
    X|Xh|C|D)
      safe_to_execute "$cmdt" || harness_die "row '$label' is not safe to execute under the oracle (absolute path, PATH reset, exec): make it a literal row"
      ROWS_EXEC=$((ROWS_EXEC + 1))
      oracle_derive "$cmd" "$cwd" "$CUR_HOME"
      ;;
    L) ROWS_LIT=$((ROWS_LIT + 1)) ;;
    *) harness_die "unknown row kind '$kind' ($label)" ;;
  esac
  hook_run "$(mkjson "$cmd" "$cwd")"
  classify
  if [[ "$kind" == C ]]; then
    CORPUS_N=$((CORPUS_N + 1))
    case "$GOT" in ask|deny) CORPUS_ASK=$((CORPUS_ASK + 1)) ;; error*|malformed) CORPUS_ERR=$((CORPUS_ERR + 1)) ;; esac
  fi
  case "$kind" in
    X|Xh|C)
      if [[ "$ORC" != "$want" ]]; then
        chk "$label" bad "HARNESS DEFECT: oracle=$ORC but the author's intent=$want (the hook was not judged)"
      else
        chk "$label" "$(verdict_of "$ORC" "$GOT")" "want=$ORC got=$GOT"
      fi ;;
    D)
      ROWS_DEAD=$((ROWS_DEAD + 1))
      if [[ "$ORC" != none ]]; then
        chk "$label" bad "HARNESS DEFECT: labelled dead code but the stub fired (oracle=$ORC); make it an X row"
      else
        chk "$label" "$(verdict_of "$want" "$GOT")" "want=$want got=$GOT (dead code: the stub did not fire)"
      fi ;;
    L) chk "$label" "$(verdict_of "$want" "$GOT")" "want=$want got=$GOT" ;;
  esac
  CUR_HOME="$HOME_W"
}
# run_table <fd>: read rows `kind @@ label @@ want @@ cwd @@ command` from the given descriptor.
run_table() {
  local line kind label want cwd cmd rest
  while IFS= read -r -u "$1" line; do
    [[ -z "$line" || "$line" == '#'* ]] && continue
    kind="${line%% @@ *}"; rest="${line#* @@ }"
    label="${rest%% @@ *}"; rest="${rest#* @@ }"
    want="${rest%% @@ *}"; rest="${rest#* @@ }"
    cwd="${rest%% @@ *}"; cmd="${rest#* @@ }"
    run_row "$kind" "$label" "$want" "$cwd" "$cmd"
  done
}
# env_row <label> <want> <stdin-text> [ENV=VAL ...]: a literal row with its own stdin and environment.
env_row() {
  local label="$1" want="$2" in="$3"; shift 3
  want_row "$label" || return 0
  ROWS_LIT=$((ROWS_LIT + 1))
  hook_run "$in" "$@"
  classify
  chk "$label" "$(verdict_of "$want" "$GOT")" "want=$want got=$GOT"
}
# jqchk <label> <jq filter> [jq args]: assert on the LAST hook output.
jqchk() {
  local label="$1" filter="$2"; shift 2
  want_row "$label" || return 0
  if [[ -n "$FAST" ]]; then chk "$label" bad "fast"; return 0; fi
  if printf '%s' "$HOOK_OUT" | "$JQ_BIN" -e "$@" "$filter" >/dev/null 2>&1; then chk "$label" ok; else chk "$label" bad "output: ${HOOK_OUT:0:240}"; fi
}
# reason_has <label> <literal substring>: assert the last hook output's reason holds the substring (and says so on failure).
reason_has() {
  jqchk "$1" '.hookSpecificOutput.permissionDecisionReason | contains($s)' --arg s "$2"
}

# The ask reasons open with a sentence for the person reading the prompt; the agent's instructions follow under their own label.
ASK_LEAD='The guard paused this command and is asking you. It has not run yet and runs only if you approve.'
ASK_LEAD_RX='The guard paused this command and is asking you\. It has not run yet and runs only if you approve\. '
# bound_row <label> <want> <cwd-template> <command> [reason ERE] [ENV=VAL ...]: a literal row that ALSO asserts the answer arrived in
# under 5 s. The hook's own deadline is 6 s of the harness's 10 s timeout. Times are whole-second deltas of `date +%s`,
# so a delta below 5 proves the real elapsed time was below 5 s. Contention caveat: a machine under heavy load can make
# a correct hook read as slow here; that is the signal the row exists to give, not a flake to widen away.
bound_row() {
  local label="$1" want="$2" cwdt="$3" cmd="$4" rx="${5:-}" t0 t1 el ok=ok why=""
  want_row "$label" || return 0
  ROWS_LIT=$((ROWS_LIT + 1))
  subst "$cwdt"
  t0="$(date +%s)"
  hook_run "$(mkjson "$cmd" "$SUBST_OUT")" "${@:6}"
  t1="$(date +%s)"; el=$((t1 - t0))
  classify
  [[ "$GOT" == "$want" ]] || { ok=bad; why="want=$want got=$GOT"; }
  if [[ -z "$FAST" && "$el" -ge 5 ]]; then ok=bad; why="$why elapsed=${el}s (limit 5 s)"; fi
  if [[ -n "$rx" ]] && ! printf '%s' "$HOOK_OUT" | "$JQ_BIN" -e --arg rx "$rx" '.hookSpecificOutput.permissionDecisionReason | test($rx)' >/dev/null 2>&1; then
    ok=bad; why="$why reason does not match /$rx/: ${HOOK_OUT:0:160}"
  fi
  chk "$label" "$ok" "$why"
}
# rep <text> <count>: the text repeated count times, in REP_OUT.
rep() { local _s="" _i; for ((_i = 0; _i < $2; _i++)); do _s+="$1"; done; REP_OUT="$_s"; }
# mk_hook_tree <name> -> HT_HOOK: a private copy of the hook directory (hook + lib), so a row can swap the lexer for a
# stub or change one constant of the hook without touching the live tree. Skipped in the count-only meta copy.
mk_hook_tree() {
  local src d; src="$(dirname "$GUARD_HOOK")"; d="$WORK/trees/$1"
  HT_HOOK="$d/destructive-command-guard.sh"
  [[ -n "$FAST" ]] && return 0
  assert_fixture_dir "$d"
  mkdir -p "$d/lib" || harness_die "mk_hook_tree mkdir"
  cp "$GUARD_HOOK" "$d/destructive-command-guard.sh" && cp "$src"/lib/shell-argv.pl "$d/lib/shell-argv.pl" || harness_die "mk_hook_tree cp"
  cp "$src"/lib/hook-tool-kind.sh "$d/lib/" 2>/dev/null || true
  chmod +x "$HT_HOOK"
}
# tree_row <label> <want> <hook path> <stdin text> [ENV=VAL ...]: env_row against a hook other than the live one.
tree_row() {
  local label="$1" want="$2" hk="$3" in="$4" saved="$GUARD_HOOK"; shift 4
  GUARD_HOOK="$hk"
  env_row "$label" "$want" "$in" "$@"
  GUARD_HOOK="$saved"
}

# Instrument self-test, part 2: the helpers that OWN the verdict (verdict_of, chk, jqchk and env_row's comparison) are driven with a
# known-good and a known-bad input each, before any row. Reported by printf + exit 1, never through the helpers it backstops. A
# helper that always reads "ok" would otherwise turn every row green: nothing else in the suite drives them with a bad input.
_st_fatal() { printf '[FATAL] instrument self-test: %s\n' "$1" >&2; exit 1; }
_st_p="$PASS_COUNT"; _st_f="$FAIL_COUNT"; _st_c="$CHECKED"; _st_rowsel="$ROWSEL"; _st_out="$HOOK_OUT"
ROWSEL=""   # the probes below must run whatever DCG_ROWS selects
[[ "$(verdict_of a a)" == ok && "$(verdict_of a b)" == bad && "$(verdict_of '' x)" == bad && "$(verdict_of ask none)" == bad ]] \
  || _st_fatal "verdict_of does not tell an equal pair from an unequal one"
# chk: ok records a pass and only a pass, anything else records a fail and only a fail, and CHECKED moves for each
{ chk "self-test: chk ok" ok; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 1)) && "$FAIL_COUNT" -eq "$_st_f" && "$CHECKED" -eq $((_st_c + 1)) ]] || _st_fatal "chk did not record a pass for ok"
{ chk "self-test: chk bad" bad; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 1)) && "$FAIL_COUNT" -eq $((_st_f + 1)) && "$CHECKED" -eq $((_st_c + 2)) ]] || _st_fatal "chk did not record a fail for bad"
{ chk "self-test: chk other" "okay"; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 1)) && "$FAIL_COUNT" -eq $((_st_f + 2)) && "$CHECKED" -eq $((_st_c + 3)) ]] || _st_fatal "chk did not record a fail for a value that is not exactly ok"
# jqchk: asserts on HOOK_OUT; a true filter passes, a false and a null filter fail, extra jq args reach the filter
# (the count-only meta copy has FAST set, where jqchk records a fixed bad: nothing to probe there)
if [[ -z "$FAST" ]]; then
HOOK_OUT='{"a":1,"b":"x"}'
_st_p="$PASS_COUNT"; _st_f="$FAIL_COUNT"
{ jqchk "self-test: jqchk true" '.a == 1'; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 1)) && "$FAIL_COUNT" -eq "$_st_f" ]] || _st_fatal "jqchk failed a filter that is true of the output"
{ jqchk "self-test: jqchk false" '.a == 2'; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 1)) && "$FAIL_COUNT" -eq $((_st_f + 1)) ]] || _st_fatal "jqchk passed a filter that is false of the output"
{ jqchk "self-test: jqchk null" '.zz'; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 1)) && "$FAIL_COUNT" -eq $((_st_f + 2)) ]] || _st_fatal "jqchk passed a filter that is null on the output"
{ jqchk "self-test: jqchk arg" '.b == $v' --arg v x; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 2)) && "$FAIL_COUNT" -eq $((_st_f + 2)) ]] || _st_fatal "jqchk did not hand its --arg to the filter"
HOOK_OUT=""
{ jqchk "self-test: jqchk empty output" '.a == 1'; } >/dev/null 2>&1
[[ "$PASS_COUNT" -eq $((_st_p + 2)) && "$FAIL_COUNT" -eq $((_st_f + 3)) ]] || _st_fatal "jqchk passed on an empty output"
fi
# env_row (and hook_run, classify): one stub hook that asks and one that stays silent, each against a wanted ask and a wanted none
if [[ -z "$FAST" ]]; then
  assert_fixture_dir "$WORK"
  mkdir -p "$WORK/selftest" || harness_die "selftest mkdir"
  cat > "$WORK/selftest/ask.sh" <<'ASKEOF'
#!/bin/sh
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"r"}}'
ASKEOF
  printf '#!/bin/sh\nexit 0\n' > "$WORK/selftest/silent.sh"
  _st_saved="$GUARD_HOOK"
  _st_run() { # <stub> <want> <expect: ok|bad>
    local p0="$PASS_COUNT" f0="$FAIL_COUNT"
    GUARD_HOOK="$WORK/selftest/$1"; { env_row "self-test: env_row" "$2" '{}'; } >/dev/null 2>&1; GUARD_HOOK="$_st_saved"
    if [[ "$3" == ok ]]; then [[ "$PASS_COUNT" -eq $((p0 + 1)) && "$FAIL_COUNT" -eq "$f0" ]]; else [[ "$PASS_COUNT" -eq "$p0" && "$FAIL_COUNT" -eq $((f0 + 1)) ]]; fi
  }
  _st_run ask.sh ask ok || _st_fatal "env_row did not pass a stub hook that asks when an ask was wanted"
  _st_run silent.sh none ok || _st_fatal "env_row did not pass a stub hook that is silent when none was wanted"
  _st_run ask.sh none bad || _st_fatal "env_row passed a stub hook that asks when none was wanted"
  _st_run silent.sh ask bad || _st_fatal "env_row passed a stub hook that is silent when an ask was wanted"
fi
ROWSEL="$_st_rowsel"; HOOK_OUT="$_st_out"; GOT=""
PASS_COUNT=0; FAIL_COUNT=0; CHECKED=0; ROWS_LIT=0; SELECTED=0

# =====================================================================================================
echo "== static: the hook file, its header and its portability =="
if [[ -f "$GUARD_HOOK" && -x "$GUARD_HOOK" ]]; then _x=ok; else _x=bad; fi
chk "the hook exists and is executable ($GUARD_HOOK)" "$_x"
if [[ -f "$GUARD_HOOK" && "$(head -n 1 "$GUARD_HOOK")" == '#!/usr/bin/env bash' ]]; then _x=ok; else _x=bad; fi
chk "the hook starts with the bash shebang" "$_x"
if [[ -f "$GUARD_HOOK" ]] && "$BASH" -n "$GUARD_HOOK" 2>/dev/null; then _x=ok; else _x=bad; fi
chk "the hook parses (bash -n)" "$_x"
# The bash-4 / GNU-only token list. `;&` counts only as a case terminator (not when a `|` follows it, as in the IFS string `$';&|\n'`).
BASH4_RE='(declare -A|declare -n|local -n|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}|\[\[ -v |;;&|;&([^|]|$)|\|&|printf( -v +[A-Za-z_]+)? +[^ ]*%q|sort -z|xargs -r|find [^|;]*-printf|grep -P|sed +-[a-zA-Z]*r|readlink -f|realpath|sed -i|date -d|stat -c)'
_b4=1; [[ -f "$GUARD_HOOK" ]] && _b4="$(grep -cE -- "$BASH4_RE" "$GUARD_HOOK")"
if [[ "$_b4" == 0 ]]; then _x=ok; else _x=bad; fi
chk "the hook uses no bash-4 feature and no GNU-only flag (count is 0)" "$_x" "hits: $_b4"
# the pattern itself can fail: every known-bad spelling is a hit and the known-good look-alikes are not
_b4_miss=""
for _s in 'x=${v,,}' 'x=${v^^}' 'x=${v,}' 'declare -n r=x' 'local -n r=x' '[[ -v X ]]' 'case x in a) ls ;;& b) ;; esac' 'case x in a) ls ;& b) ;; esac' 'a |& b' 'printf %q x' 'printf -v o %q x' 'readarray -t a' 'mapfile a' 'declare -A m' 'sort -z' 'xargs -r ls' 'find src -printf x' 'grep -P x' 'sed -r s/a/b/' 'sed -nr s/a/b/' 'readlink -f x' 'realpath x'; do
  printf '%s\n' "$_s" | grep -qE -- "$BASH4_RE" || _b4_miss+=" [$_s]"
done
for _s in "IFS=\$';&|\\n'" 'sed -E s/a/b/' 'x=${v:-,,}' 'printf %s x' 'find src -name x' 'grep -E x' 'sort -u'; do
  if printf '%s\n' "$_s" | grep -qE -- "$BASH4_RE"; then _b4_miss+=" false-hit[$_s]"; fi
done
if [[ -z "$_b4_miss" ]]; then _x=ok; else _x=bad; fi
chk "the bash-4 token pattern flags every known-bad spelling and none of the look-alikes" "$_x" "wrong:$_b4_miss"
if [[ -f "$LEXER" && -r "$LEXER" ]]; then _x=ok; else _x=bad; fi
chk "the vendored lexer is present" "$_x"
_hdr=""; [[ -f "$GUARD_HOOK" ]] && _hdr="$(head -n 200 "$GUARD_HOOK")"
if grep -qF 'SOLEUR_DISABLE_DESTRUCTIVE_GUARD' <<<"$_hdr" && grep -qi 'restart' <<<"$_hdr"; then _x=ok; else _x=bad; fi
chk "the header documents the kill switch and that it needs a session restart" "$_x"
if grep -qi 'settings' <<<"$_hdr" && grep -Eqi 'env (block|setting)|`env`|"env"' <<<"$_hdr"; then _x=ok; else _x=bad; fi
chk "the header documents that a settings-level env block can set the kill switch (Guard 1 row 20)" "$_x"
if grep -qF 'updatedInput' <<<"$_hdr"; then _x=ok; else _x=bad; fi
chk "the header states the guard judges the original command, not another hook's updatedInput" "$_x"
if grep -qi 'terraform apply' <<<"$_hdr" && grep -Eqi 'not (a substitute|cover)|does not cover|not decided' <<<"$_hdr"; then _x=ok; else _x=bad; fi
chk "the header carries the non-coverage statement (a plain terraform apply is not covered)" "$_x"
# the header's "User-facing statement" is the README's pinned sentence (README_SENT_NONCOVERAGE), word for word: comment markers
# and line breaks of the header are removed first, so a re-wrapped header still passes and a reworded one does not
_hdr_flat="$(printf '%s\n' "$_hdr" | sed -E 's/^# ?//' | tr '\n' ' ' | tr -s ' ')"
if [[ "$_hdr_flat" == *"User-facing statement: $README_SENT_NONCOVERAGE"* ]]; then _x=ok; else _x=bad; fi
chk "the header's User-facing statement is the README's non-coverage sentence, word for word" "$_x"

# Every rule id the hook can emit is listed in the hooks roster (.claude/hooks/README.md), in backticks, on the hook's own row.
# The ids are DERIVED from the hook source (a `note <rank> <id>` call or the id that opens an `emit` reason), never hand-copied;
# the floor keeps an empty derivation (a changed emit shape) from reading as "all listed".
HOOKS_README="$REPO_ROOT/.claude/hooks/README.md"
_RID_LABEL="README roster: every rule id the hook can emit is listed on its row (derived from the hook source)"
if want_row "$_RID_LABEL"; then
  _rids="$( { grep -oE 'note [12] [a-z]+(-[a-z0-9]+)*' "$GUARD_HOOK" | awk '{print $3}'
              grep -oE 'emit(_fixed)? (ask|deny|"\$1") "[a-z]+(-[a-z0-9]+)*:' "$GUARD_HOOK" | sed -E 's/^.*"//; s/:$//'
            } | sort -u )"
  _rrow="$(grep -F '| `destructive-command-guard.sh`' "$HOOKS_README" 2>/dev/null)"
  _rmiss=""; _rn=0
  for _r in $_rids; do _rn=$((_rn + 1)); grep -qF -- "\`$_r\`" <<<"$_rrow" || _rmiss+=" $_r"; done
  if [[ "$_rn" -ge 13 && -n "$_rrow" && -z "$_rmiss" ]]; then _x=ok; else _x=bad; fi
  chk "$_RID_LABEL" "$_x" "derived ids=$_rn (floor 13), row found=$([[ -n "$_rrow" ]] && echo yes || echo no), missing:${_rmiss:- none}"
fi

echo "== registration (Guard 1, M7) =="
_reg() { "$JQ_BIN" -e --arg h destructive-command-guard.sh "$@" "$HOOKS_JSON" >/dev/null 2>&1 && printf ok || printf bad; }
chk "hooks.json carries a PreToolUse entry that runs the hook" "$(_reg '[.hooks.PreToolUse[] | select(.hooks | map(.command) | any(contains($h)))] | length == 1')"
chk "that entry's matcher matches Bash" "$(_reg '[.hooks.PreToolUse[] | select(.hooks | map(.command) | any(contains($h))) | select(.matcher as $m | "Bash" | test($m))] | length == 1')"
chk "that entry's matcher does not match Edit or exec (D9: ^Bash$ only)" "$(_reg '([.hooks.PreToolUse[] | select(.hooks | map(.command) | any(contains($h)))] | length == 1) and ([.hooks.PreToolUse[] | select(.hooks | map(.command) | any(contains($h))) | select(.matcher as $m | ("Edit" | test($m)) or ("exec" | test($m)))] | length == 0)')"
chk "the hook entry carries an explicit numeric timeout" "$(_reg '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains($h)) | .timeout | select(type == "number" and . > 0)] | length == 1')"
chk "the hook is registered after the snapshot guard" "$(_reg '[.hooks.PreToolUse | to_entries[] | select(.value.hooks | map(.command) | any(contains($h))) | .key][0] > ([.hooks.PreToolUse | to_entries[] | select(.value.hooks | map(.command) | any(contains("browser-snapshot-credential-guard.sh"))) | .key][0])')"
chk "the hook's registered command is the shell-quoted form (bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/destructive-command-guard.sh\"), as the plugin's session-start hooks are" "$(_reg --arg c 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/destructive-command-guard.sh"' '[.hooks.PreToolUse[].hooks[] | select(.command | contains($h)) | .command] == [$c]')"
# The registered command string, run the way the harness runs it (a shell, CLAUDE_PLUGIN_ROOT in the environment), with a plugin root
# whose path holds a space: an unquoted ${CLAUDE_PLUGIN_ROOT} splits there, exits 127 and the call runs with no decision.
if [[ -z "$FAST" ]]; then
  SPROOT="$WORK/sp ace"; assert_fixture_dir "$SPROOT"
  _hksrc="$(dirname "$GUARD_HOOK")"; assert_fixture_dir "$_hksrc"
  mkdir -p "$SPROOT/hooks" && cp -R "$_hksrc/." "$SPROOT/hooks/" || harness_die "cannot copy the hooks to a path with a space"
  _regcmd="$("$JQ_BIN" -r --arg h destructive-command-guard.sh '[.hooks.PreToolUse[].hooks[] | select(.command | contains($h)) | .command][0] // ""' "$HOOKS_JSON")"
else _regcmd=x; fi
if want_row "registration: the registered command runs the hook when the plugin root contains a space"; then
  if [[ -n "$FAST" ]]; then GOT=ask; else
    assert_fixture_dir "$INF"
    printf '%s' "$(mkjson 'terraform destroy' "$TREE")" > "$INF"
    HOOK_OUT="$(env ${GIT_UNSET[@]+"${GIT_UNSET[@]}"} -u SOLEUR_DISABLE_DESTRUCTIVE_GUARD -u CLAUDE_PROJECT_DIR "HOME=$CUR_HOME" "CLAUDE_PLUGIN_ROOT=$SPROOT" "$TIMEOUT_BIN" 30 sh -c "$_regcmd" <"$INF" 2>"$ERRF")"; HOOK_RC=$?
    classify
  fi
  chk "registration: the registered command runs the hook when the plugin root contains a space" "$(verdict_of ask "$GOT")" "want=ask got=$GOT command: ${_regcmd:0:120}"
fi

echo "== the plugin README states the scope and the hosted gap (CPO round 1, C1/C2) =="
# Read from the real tree (REPO_ROOT), and skipped in reduced mode: the mutation suite's copy holds no README.
# Exact-sentence anchors with an exact count of 1; never a negated grep.
PLUGIN_README="$REPO_ROOT/plugins/soleur/README.md"
# readme_section: the `## Destructive-Command Guard` section of the plugin README with HTML comments (single and multi-line) and
# fenced code removed, so neither can hold a sentence the rows then count.
readme_section() {
  [[ -f "$PLUGIN_README" ]] || return 0
  "$PERL_BIN" -0777 -ne 'my $t = $_; $t =~ s/<!--.*?-->//gs; my ($o, $in, $fence) = ("", 0, 0);
    for my $l (split /\n/, $t) {
      if ($l =~ /^\s*(?:```|~~~)/) { $fence = !$fence; next }
      next if $fence;
      if ($l =~ /^## /) { $in = ($l eq "## Destructive-Command Guard") ? 1 : 0; next }
      $o .= "$l\n" if $in;
    }
    print $o;' "$PLUGIN_README"
}
# _readme_count <sentence>: the number of section lines that START with the sentence (a negating prefix or a mid-line mention does not count).
_readme_count() { readme_section | S="$1" awk 'index($0, ENVIRON["S"]) == 1 { c++ } END { print c + 0 }'; }
_readme_row() { # <label> <literal sentence>
  want_row "$1" || return 0
  local n sec
  n="$(_readme_count "$2")"; sec="$(readme_section | grep -c . || true)"
  if [[ "$n" == 1 && "$sec" -ge 5 ]]; then _x=ok; else _x=bad; fi
  chk "$1" "$_x" "expected exactly one line STARTING with the sentence in the '## Destructive-Command Guard' section of $PLUGIN_README (found $n; section has $sec non-blank lines)"
}
_readme_row "README: the non-coverage sentence appears exactly once" "$README_SENT_NONCOVERAGE"
_readme_row "README: the hosted-gap line appears exactly once" "$README_SENT_HOSTED"
_readme_row "README: the kill switch is documented exactly once as an assignment" "$README_SENT_KILL"

echo "== the lexer contract the hook relies on (records, once each) =="
lex_dump() { printf '%s' "$1" | "$PERL_BIN" "$LEXER" 2>/dev/null | "$PY_BIN" -I -S "$WORK/oracle.py" lex 2>/dev/null; }
_cases_lex() {
  local cmd="$1" want="$2" label="$3" got
  got="$(lex_dump "$cmd")"
  chk "lexer: $label" "$(verdict_of "$want" "$got")" "got=$(printf '%s' "$got" | tr '\n' '~')"
}
_cases_lex 'ls' $'top|ls\nOK' "a known command yields at least one record (M3)"
_cases_lex 'echo $(terraform plan; true)' $'subst|terraform plan\nsubst|true\ntop|echo $(terraform plan; true)\nOK' "a substitution lexed twice yields each command exactly once"
_cases_lex 'terraform plan 2>&1 | tee log' $'top|terraform plan\ntop|tee log\nOK' "a redirect is not a separator (two commands, not four)"
_cases_lex 'ls #x; terraform destroy' $'top|ls\nOK' "a comment hides what follows it"
_cases_lex 'echo a#b; terraform destroy' $'top|echo a#b\ntop|terraform destroy\nOK' "a mid-word hash is not a comment"
_HD='<<'  # kept out of any literal heredoc-looking text so the vacuity-floor gate's heredoc scanner is not fooled
_cases_lex "cat ${_HD}EOF"$'\nterraform destroy\nEOF\nrm -rf x' $'top|cat\ntop|rm -rf x\nOK' "a quoted-text heredoc body is data, the command after it is a command"
_cases_lex "echo 'unbalanced" 'E:exit2' "an unbalanced quote is a parse failure, not zero records"
_cases_lex '((ls); (terraform destroy))' $'top|ls\ntop|terraform destroy\nOK' "a double paren re-read as two subshells keeps each command exactly once"

# =====================================================================================================
echo "== the grammar fixture and the must-PASS rows (oracle-derived) =="
run_table 3 3<<'ROWS'
# ---- rm: deny (D1) ---------------------------------------------------------------------------------
X @@ rm -rf ~ @@ deny @@ - @@ rm -rf ~
X @@ rm -fr ~ @@ deny @@ - @@ rm -fr ~
X @@ rm -r -f ~ @@ deny @@ - @@ rm -r -f ~
X @@ rm --recursive --force ~ @@ deny @@ - @@ rm --recursive --force ~
X @@ rm -Rf $HOME @@ deny @@ - @@ rm -Rf $HOME
X @@ rm -rf -- ~ @@ deny @@ - @@ rm -rf -- ~
X @@ backslash-escaped rm @@ deny @@ - @@ \rm -rf ~
X @@ quoted command word @@ deny @@ - @@ "rm" -rf ~
X @@ rm -r ~ (no -f) @@ deny @@ - @@ rm -r ~
X @@ rm ~ -rf (flags after the target) @@ deny @@ - @@ rm ~ -rf
X @@ rm -rf ~/ @@ deny @@ - @@ rm -rf ~/
X @@ rm -rf $HOME/ @@ deny @@ - @@ rm -rf $HOME/
X @@ rm -rf ${HOME} @@ deny @@ - @@ rm -rf ${HOME}
X @@ rm -rf "$HOME" (quoted $HOME is home) @@ deny @@ - @@ rm -rf "$HOME"
X @@ rm -rf "${HOME}/" @@ deny @@ - @@ rm -rf "${HOME}/"
X @@ rm -rf / @@ deny @@ - @@ rm -rf /
X @@ rm -rf // @@ deny @@ - @@ rm -rf //
X @@ rm -rf /../.. @@ deny @@ - @@ rm -rf /../..
X @@ rm -rf ~/* (contents of home) @@ deny @@ - @@ rm -rf ~/*
X @@ rm -rf $HOME/* @@ deny @@ - @@ rm -rf $HOME/*
X @@ rm -rf the parent of home (an ancestor) @@ deny @@ - @@ rm -rf @HOMEPARENT@
X @@ rm -rf the root of the fixture (an ancestor) @@ deny @@ - @@ rm -rf @ROOT@
X @@ rm -rf ancestor/* @@ deny @@ - @@ rm -rf @HOMEPARENT@/*
X @@ rm -rf home/.. @@ deny @@ - @@ rm -rf @HOME@/..
X @@ rm -rf home/../home @@ deny @@ - @@ rm -rf @HOME@/../home
X @@ relative path resolving to home @@ deny @@ - @@ cd @TREE@ && rm -rf ../../h/home
X @@ relative path resolving to an ancestor of home @@ deny @@ - @@ cd @TREE@ && rm -rf ../../h
X @@ symlink to home with a trailing slash follows it @@ deny @@ - @@ rm -rf @LINK@/
X @@ symlink to home with a glob suffix follows it @@ deny @@ - @@ rm -rf @LINK@/*
X @@ cd ~ && rm -rf ./* @@ deny @@ - @@ cd ~ && rm -rf ./*
X @@ cd ~ && rm -rf * @@ deny @@ - @@ cd ~ && rm -rf *
X @@ cd ~; rm -rf ./* (a semicolon list) @@ deny @@ - @@ cd ~; rm -rf ./*
X @@ pushd ~ && rm -rf * @@ deny @@ - @@ pushd ~ && rm -rf *
X @@ cd $HOME && rm -rf ./* @@ deny @@ - @@ cd $HOME && rm -rf ./*
X @@ rm -rf ./* with home as the working directory @@ deny @@ @HOME@ @@ rm -rf ./*
X @@ rm -rf * with home as the working directory @@ deny @@ @HOME@ @@ rm -rf *
X @@ rm -rf .. with home as the working directory @@ deny @@ @HOME@ @@ rm -rf ..
Xh @@ symlinked HOME: rm -rf ~ @@ deny @@ - @@ rm -rf ~
Xh @@ symlinked HOME: rm -rf ~/ @@ deny @@ - @@ rm -rf ~/
Xh @@ symlinked HOME: rm -rf $HOME @@ deny @@ - @@ rm -rf $HOME
Xh @@ symlinked HOME: the physical path of home @@ deny @@ - @@ rm -rf @HOMEPHYS@
Xh @@ symlinked HOME: cd ~ && rm -rf ./* @@ deny @@ - @@ cd ~ && rm -rf ./*
# ---- rm: ask (the working directory or an ancestor) ------------------------------------------------
X @@ rm -rf .. from a subdirectory @@ ask @@ @SUB@ @@ rm -rf ..
X @@ rm -rf ../.. from a subdirectory @@ ask @@ @SUB@ @@ rm -rf ../..
X @@ rm -rf the absolute path above the cwd @@ ask @@ @SUB@ @@ rm -rf @TREE@
X @@ rm -rf an absolute ancestor of the cwd @@ ask @@ @SUB@ @@ rm -rf @ROOT@/t
X @@ rm -rf the cwd by absolute path @@ ask @@ @SUB@ @@ rm -rf @SUB@
X @@ rm -rf with one target that is the cwd among others @@ ask @@ - @@ rm -rf ./build ../tree
X @@ rm -rf ../../.. from a subdirectory reaches an ancestor of home @@ deny @@ @SUB@ @@ rm -rf ../../..
# ---- rm: no decision --------------------------------------------------------------------------------
X @@ rm -rf node_modules @@ none @@ - @@ rm -rf node_modules
X @@ rm -rf ./build @@ none @@ - @@ rm -rf ./build
X @@ rm -rf an absolute child of the cwd @@ none @@ - @@ rm -rf @TREE@/build
X @@ rm -rf build node_modules (two targets) @@ none @@ - @@ rm -rf build node_modules
X @@ rm -rf sub/../build @@ none @@ - @@ rm -rf sub/../build
X @@ rm -rf . (rm refuses it) @@ none @@ @SUB@ @@ rm -rf .
X @@ rm -rf ./ (rm refuses it) @@ none @@ @SUB@ @@ rm -rf ./
X @@ rm -rf ../build sibling @@ none @@ @SUB@ @@ rm -rf ../build
X @@ rm -rf ./* in a directory that is not home @@ none @@ - @@ cd @TREE@ && rm -rf ./*
X @@ rm -rf ./* in an empty subdirectory @@ none @@ - @@ cd @SUB@ && rm -rf ./*
X @@ rm ~ (no recursive flag) @@ none @@ - @@ rm ~
X @@ rm -- -rf ~ (after -- nothing is an option: -rf is a file name) @@ none @@ - @@ rm -- -rf ~
X @@ rm -f ~/x.txt @@ none @@ - @@ rm -f ~/x.txt
X @@ rm -rf ~/projects @@ none @@ - @@ rm -rf ~/projects
X @@ rm -rf ~/.cache/foo @@ none @@ - @@ rm -rf ~/.cache/foo
X @@ rm -rf a nonexistent target under home @@ none @@ - @@ rm -rf ~/definitely-not-here/x
X @@ rm -rf '~' (a quoted tilde is a directory named ~) @@ none @@ - @@ rm -rf '~'
X @@ rm -rf "~" @@ none @@ - @@ rm -rf "~"
X @@ rm -rf '$HOME' (single-quoted, not expanded) @@ none @@ - @@ rm -rf '$HOME'
X @@ rm -rf link (a bare symlink is only unlinked) @@ none @@ - @@ rm -rf link
X @@ rm -rf an unresolvable $VAR target @@ none @@ - @@ rm -rf $TARGET_DIR
X @@ rm -rf "$VAR" (empty) @@ none @@ - @@ rm -rf "$TARGET_DIR"
X @@ rm -rf $VAR/build @@ none @@ - @@ rm -rf $TARGET_DIR/build
# ---- rm: wrappers, nesting, lists -------------------------------------------------------------------
X @@ terraform plan; rm -rf ~ @@ deny @@ - @@ terraform plan; rm -rf ~
X @@ ls && rm -rf ~ @@ deny @@ - @@ ls && rm -rf ~
X @@ a pipe member @@ deny @@ - @@ echo a | rm -rf ~
X @@ sudo -u x rm -rf ~ @@ deny @@ - @@ sudo -u x rm -rf ~
X @@ sudo -n rm -rf ~ @@ deny @@ - @@ sudo -n rm -rf ~
X @@ env -i rm -rf ~ @@ deny @@ - @@ env -i rm -rf ~
X @@ timeout 5 rm -rf ~ @@ deny @@ - @@ timeout 5 rm -rf ~
X @@ nice -n 5 rm -rf ~ @@ deny @@ - @@ nice -n 5 rm -rf ~
X @@ nohup rm -rf ~ & @@ deny @@ - @@ nohup rm -rf ~ &
X @@ command rm -rf ~ @@ deny @@ - @@ command rm -rf ~
X @@ time rm -rf ~ @@ deny @@ - @@ time rm -rf ~
X @@ an assignment prefix @@ deny @@ - @@ FOO=1 BAR=2 rm -rf ~
X @@ bash -c 'rm -rf ~' @@ deny @@ - @@ bash -c 'rm -rf ~'
X @@ sh -c "rm -rf $HOME" @@ deny @@ - @@ sh -c "rm -rf $HOME"
L @@ bash -lc 'rm -rf ~' (a flag cluster, literal: a login shell may reset PATH) @@ deny @@ - @@ bash -lc 'rm -rf ~'
X @@ nested bash -c @@ deny @@ - @@ bash -c 'bash -c "rm -rf ~"'
X @@ eval "rm -rf ~" @@ deny @@ - @@ eval "rm -rf ~"
X @@ eval of eval @@ deny @@ - @@ eval "eval 'rm -rf ~'"
X @@ a command substitution @@ deny @@ - @@ echo $(rm -rf ~)
X @@ a backtick substitution @@ deny @@ - @@ echo `rm -rf ~`
X @@ a subshell @@ deny @@ - @@ (rm -rf ~)
X @@ a brace group @@ deny @@ - @@ { rm -rf ~; }
X @@ an if body @@ deny @@ - @@ if true; then rm -rf ~; fi
X @@ a newline list @@ deny @@ - @@ ls@NL@rm -rf ~
X @@ a continuation line @@ deny @@ - @@ rm -rf \@NL@  ~
X @@ doppler run -- rm -rf ~ @@ deny @@ - @@ doppler run -- rm -rf ~
# ---- terraform / tofu (ask) --------------------------------------------------------------------------
X @@ terraform destroy @@ ask @@ - @@ terraform destroy
X @@ tofu destroy @@ ask @@ - @@ tofu destroy
X @@ terraform apply -destroy @@ ask @@ - @@ terraform apply -destroy
X @@ tofu apply -destroy -auto-approve @@ ask @@ - @@ tofu apply -destroy -auto-approve
X @@ terraform apply -auto-approve -destroy @@ ask @@ - @@ terraform apply -auto-approve -destroy
X @@ terraform -chdir=infra destroy @@ ask @@ - @@ terraform -chdir=infra destroy
X @@ terraform -chdir=infra apply -destroy @@ ask @@ - @@ terraform -chdir=infra apply -destroy
X @@ terraform destroy -target=x -auto-approve @@ ask @@ - @@ terraform destroy -target=aws_instance.x -auto-approve
X @@ ls && terraform destroy @@ ask @@ - @@ ls && terraform destroy
X @@ terraform plan; terraform destroy @@ ask @@ - @@ terraform plan; terraform destroy
X @@ background terraform destroy @@ ask @@ - @@ terraform destroy &
X @@ a pipe member terraform destroy @@ ask @@ - @@ echo y | terraform destroy
X @@ an assignment prefix @@ ask @@ - @@ TF_VAR_x=1 terraform destroy
X @@ sudo -u x terraform destroy @@ ask @@ - @@ sudo -u x terraform destroy
X @@ sudo -E terraform destroy @@ ask @@ - @@ sudo -E terraform destroy
X @@ doas -u x terraform destroy @@ ask @@ - @@ doas -u x terraform destroy
X @@ env -i terraform destroy @@ ask @@ - @@ env -i terraform destroy
X @@ env FOO=1 terraform destroy @@ ask @@ - @@ env FOO=1 terraform destroy
X @@ env -u X terraform destroy @@ ask @@ - @@ env -u X terraform destroy
X @@ timeout 5 terraform destroy @@ ask @@ - @@ timeout 5 terraform destroy
X @@ timeout -s KILL 5 terraform destroy @@ ask @@ - @@ timeout -s KILL 5 terraform destroy
X @@ nice -n 5 terraform destroy @@ ask @@ - @@ nice -n 5 terraform destroy
X @@ nohup terraform destroy @@ ask @@ - @@ nohup terraform destroy
X @@ command terraform destroy @@ ask @@ - @@ command terraform destroy
X @@ time terraform destroy @@ ask @@ - @@ time terraform destroy
X @@ sudo env timeout 5 nice -n 5 terraform destroy @@ ask @@ - @@ sudo env timeout 5 nice -n 5 terraform destroy
X @@ doppler run -- terraform destroy @@ ask @@ - @@ doppler run -- terraform destroy
X @@ doppler run with options @@ ask @@ - @@ doppler run --project p --config c -- terraform destroy
X @@ aws-vault exec p -- terraform destroy @@ ask @@ - @@ aws-vault exec p -- terraform destroy
X @@ op run -- terraform destroy @@ ask @@ - @@ op run -- terraform destroy
X @@ bash -c 'terraform destroy' @@ ask @@ - @@ bash -c 'terraform destroy'
L @@ bash -lc 'terraform destroy' (literal: a login shell may reset PATH) @@ ask @@ - @@ bash -lc 'terraform destroy'
X @@ sh -c "terraform destroy" @@ ask @@ - @@ sh -c "terraform destroy"
X @@ zsh -c 'terraform destroy' @@ ask @@ - @@ zsh -c 'terraform destroy'
X @@ dash -c 'terraform destroy' @@ ask @@ - @@ dash -c 'terraform destroy'
X @@ ksh -c 'terraform destroy' @@ ask @@ - @@ ksh -c 'terraform destroy'
X @@ eval "terraform destroy" @@ ask @@ - @@ eval "terraform destroy"
X @@ a command substitution @@ ask @@ - @@ echo "$(terraform destroy)"
X @@ a substitution whose group continues @@ ask @@ - @@ echo $(terraform destroy; true)
X @@ a backtick substitution @@ ask @@ - @@ echo `terraform destroy`
X @@ a process substitution @@ ask @@ - @@ diff <(terraform destroy) x
X @@ a subshell @@ ask @@ - @@ (terraform destroy)
X @@ a brace group @@ ask @@ - @@ { terraform destroy; }
X @@ a for body @@ ask @@ - @@ for i in 1; do terraform destroy; done
X @@ a case body @@ ask @@ - @@ case x in x) terraform destroy;; esac
X @@ a double paren re-read as two subshells @@ ask @@ - @@ ((ls); (terraform destroy))
X @@ an arithmetic expansion before it @@ ask @@ - @@ echo $((1+2)); terraform destroy
X @@ a newline list @@ ask @@ - @@ ls@NL@terraform destroy
X @@ a mid-word hash is not a comment @@ ask @@ - @@ echo a#b; terraform destroy
X @@ a quoted hash is not a comment @@ ask @@ - @@ echo "# comment"; terraform destroy
X @@ a heredoc, then a real command after the terminator @@ ask @@ - @@ cat <<EOF@NL@terraform destroy@NL@EOF@NL@terraform destroy
X @@ an unquoted heredoc body substitutes @@ ask @@ - @@ cat <<EOF@NL@$(terraform destroy)@NL@EOF
X @@ a command substitution inside ${...} that runs @@ ask @@ - @@ echo ${UNSET_V:-$(terraform destroy)}
X @@ $'..' decoded in the subcommand word @@ ask @@ - @@ terraform $'destroy'
X @@ $'..' decoded in the command word @@ ask @@ - @@ $'terraform' destroy
X @@ redirect and list: ls &> out; terraform destroy @@ ask @@ - @@ ls &> @TREE@/out.log; terraform destroy
X @@ pipe-and: terraform destroy |& tee log @@ ask @@ - @@ terraform destroy |& tee @TREE@/out.log
X @@ clobber redirect then destroy @@ ask @@ - @@ echo x >| @TREE@/out.log; terraform destroy
X @@ more than 32 simple commands, destroy last (no record cap) @@ ask @@ - @@ echo 1; echo 2; echo 3; echo 4; echo 5; echo 6; echo 7; echo 8; echo 9; echo 10; echo 11; echo 12; echo 13; echo 14; echo 15; echo 16; echo 17; echo 18; echo 19; echo 20; echo 21; echo 22; echo 23; echo 24; echo 25; echo 26; echo 27; echo 28; echo 29; echo 30; echo 31; echo 32; echo 33; echo 34; echo 35; echo 36; echo 37; echo 38; echo 39; echo 40; terraform destroy
# ---- terraform / tofu: no decision -------------------------------------------------------------------
X @@ terraform plan @@ none @@ - @@ terraform plan
X @@ terraform plan -destroy @@ none @@ - @@ terraform plan -destroy
X @@ tofu plan -destroy @@ none @@ - @@ tofu plan -destroy
X @@ a plain terraform apply (D2, not decided) @@ none @@ - @@ terraform apply
X @@ terraform apply tfplan (D2, not decided) @@ none @@ - @@ terraform apply tfplan
X @@ terraform apply -auto-approve (D2, not decided) @@ none @@ - @@ terraform apply -auto-approve
X @@ terraform init -upgrade @@ none @@ - @@ terraform init -upgrade
X @@ terraform workspace select destroy (not the subcommand) @@ none @@ - @@ terraform workspace select destroy
X @@ terraform state list @@ none @@ - @@ terraform state list
X @@ command -v rm @@ none @@ - @@ command -v rm
X @@ command -v terraform @@ none @@ - @@ command -v terraform
X @@ command -v rm -rf ~ (a look-up only: rm never runs) @@ none @@ - @@ command -v rm -rf ~
X @@ doppler run -- terraform plan @@ none @@ - @@ doppler run -- terraform plan
X @@ doppler run -- ls @@ none @@ - @@ doppler run -- ls
X @@ xargs is not unwrapped (D1/D2 stated non-coverage) @@ none @@ - @@ echo ~ | xargs rm -rf
# ---- quoted text and heredocs: no decision -----------------------------------------------------------
X @@ echo "terraform destroy" @@ none @@ - @@ echo "terraform destroy"
X @@ echo 'rm -rf ~' @@ none @@ - @@ echo 'rm -rf ~'
X @@ echo terraform destroy (an argument, not a command) @@ none @@ - @@ echo terraform destroy
X @@ git commit -m "rm -rf /" @@ none @@ - @@ git commit -m "rm -rf /"
X @@ git commit -m 'terraform destroy' @@ none @@ - @@ git commit -m 'terraform destroy'
X @@ grep destroy -r . (recursive, flag after the pattern) @@ none @@ - @@ grep destroy -r .
X @@ a heredoc body containing terraform destroy @@ none @@ - @@ cat <<EOF@NL@terraform destroy@NL@EOF
X @@ a heredoc body containing rm -rf ~ @@ none @@ - @@ cat <<EOF@NL@rm -rf ~@NL@EOF
X @@ a quoted heredoc body with a substitution is data @@ none @@ - @@ cat <<'EOF'@NL@$(terraform destroy)@NL@EOF
X @@ a here-string @@ none @@ - @@ cat <<< "terraform destroy"
X @@ a heredoc with a dash and tabs @@ none @@ - @@ cat <<-EOF@NL@@TAB@terraform destroy@NL@@TAB@EOF
X @@ ls #x; terraform destroy (a comment) @@ none @@ - @@ ls #x; terraform destroy
X @@ echo $(terraform plan; true) @@ none @@ - @@ echo $(terraform plan; true)
X @@ terraform plan 2>&1 | tee log @@ none @@ - @@ terraform plan 2>&1 | tee @TREE@/out.log
X @@ terraform plan |& tee log @@ none @@ - @@ terraform plan |& tee @TREE@/out.log
X @@ a clobber redirect @@ none @@ - @@ echo x >| @TREE@/out.log
X @@ a double paren with a comment-free body @@ none @@ - @@ ((ls); (ls))
X @@ more than 32 simple commands, all benign (no record cap) @@ none @@ - @@ echo 1; echo 2; echo 3; echo 4; echo 5; echo 6; echo 7; echo 8; echo 9; echo 10; echo 11; echo 12; echo 13; echo 14; echo 15; echo 16; echo 17; echo 18; echo 19; echo 20; echo 21; echo 22; echo 23; echo 24; echo 25; echo 26; echo 27; echo 28; echo 29; echo 30; echo 31; echo 32; echo 33; echo 34; echo 35; echo 36; echo 37; echo 38; echo 39; echo 40
X @@ more than 32 simple commands, all benign, quoted so they reach the lexer (no record cap) @@ none @@ - @@ echo "1"; echo "2"; echo "3"; echo "4"; echo "5"; echo "6"; echo "7"; echo "8"; echo "9"; echo "10"; echo "11"; echo "12"; echo "13"; echo "14"; echo "15"; echo "16"; echo "17"; echo "18"; echo "19"; echo "20"; echo "21"; echo "22"; echo "23"; echo "24"; echo "25"; echo "26"; echo "27"; echo "28"; echo "29"; echo "30"; echo "31"; echo "32"; echo "33"; echo "34"; echo "35"; echo "36"; echo "37"; echo "38"; echo "39"; echo "40"
# ---- prefilter boundary rows (Guard 1, M4): a boundary character plus a destructive word ------------
X @@ boundary backslash: r\m -rf ~ @@ deny @@ - @@ r\m -rf ~
X @@ boundary single quote: r''m -rf ~ @@ deny @@ - @@ r''m -rf ~
X @@ boundary double quote: r""m -rf ~ (no keyword, no \ ' $ or backtick) @@ deny @@ - @@ r""m -rf ~
X @@ boundary dollar quote: r$''m -rf ~ @@ deny @@ - @@ r$''m -rf ~
X @@ boundary ANSI-C hex: $'\x72m' -rf ~ @@ deny @@ - @@ $'\x72m' -rf ~
X @@ boundary: terraform d\estroy @@ ask @@ - @@ terraform d\estroy
X @@ boundary: terraform d''estroy @@ ask @@ - @@ terraform d''estroy
X @@ boundary: terraform d""estroy @@ ask @@ - @@ terraform d""estroy
X @@ boundary: terraform d"es"troy @@ ask @@ - @@ terraform d"es"troy
X @@ boundary: terraform $'destr\x6fy' @@ ask @@ - @@ terraform $'destr\x6fy'
X @@ boundary: ev\al "rm -rf ~" @@ deny @@ - @@ ev\al "rm -rf ~"
X @@ boundary: ev''al 'r\m -rf ~' @@ deny @@ - @@ ev''al 'r\m -rf ~'
X @@ boundary: git pu\sh -f origin trunk @@ ask @@ @R1@ @@ git pu\sh -f origin trunk
X @@ boundary: git pu""sh --force origin main @@ ask @@ @R1@ @@ git pu""sh --force origin main
X @@ a dollar sign in a benign word before a destroy @@ ask @@ - @@ echo $HOME; terraform destroy
X @@ a single quote in a benign word before a destroy @@ ask @@ - @@ echo 'a'; terraform destroy
X @@ a backslash in a benign word before a destroy @@ ask @@ - @@ echo a\ b; terraform destroy
X @@ a backtick in a benign word before a destroy @@ ask @@ - @@ echo `date`; terraform destroy
X @@ a double quote in a benign word before a destroy @@ ask @@ - @@ echo "x"; terraform destroy
X @@ a dollar sign before a recursive delete of home @@ deny @@ - @@ echo $HOME; rm -rf ~
X @@ a single quote before a recursive delete of home @@ deny @@ - @@ echo 'a'; rm -rf ~
X @@ a backslash before a recursive delete of home @@ deny @@ - @@ echo a\ b; rm -rf ~
X @@ a backtick before a recursive delete of home @@ deny @@ - @@ echo `date`; rm -rf ~
X @@ a keyword only, no boundary character (rm) @@ deny @@ - @@ rm -rf ~
X @@ a keyword only, no boundary character (destroy) @@ ask @@ - @@ terraform destroy
X @@ no keyword and no boundary character @@ none @@ - @@ ls -la
X @@ keywords in benign positions with boundary characters @@ none @@ - @@ echo 'it works' && ls "$HOME"
# ---- git push (D1) ------------------------------------------------------------------------------------
X @@ git push --force origin trunk @@ ask @@ @R1@ @@ git push --force origin trunk
X @@ git push -f origin main @@ ask @@ @R1@ @@ git push -f origin main
X @@ git push -f origin master @@ ask @@ @R1@ @@ git push -f origin master
X @@ git push --force origin refs/heads/trunk @@ ask @@ @R1@ @@ git push --force origin refs/heads/trunk
X @@ git push --force-with-lease origin trunk @@ ask @@ @R1@ @@ git push --force-with-lease origin trunk
X @@ git push --force-with-lease=trunk:abc origin trunk @@ ask @@ @R1@ @@ git push --force-with-lease=trunk:abc origin trunk
X @@ git push --force-if-includes origin trunk @@ ask @@ @R1@ @@ git push --force-if-includes origin trunk
X @@ git push origin +trunk @@ ask @@ @R1@ @@ git push origin +trunk
X @@ git push origin +main @@ ask @@ @R1@ @@ git push origin +main
X @@ git push origin feature:trunk -f @@ ask @@ @R1@ @@ git push origin feature:trunk -f
X @@ git push -f origin HEAD:trunk @@ ask @@ @R1@ @@ git push -f origin HEAD:trunk
X @@ git push origin HEAD:+trunk @@ ask @@ @R1@ @@ git push origin HEAD:+trunk
X @@ git push -fu origin trunk @@ ask @@ @R1@ @@ git push -fu origin trunk
X @@ git push -f origin feature:main @@ ask @@ @R1@ @@ git push -f origin feature:main
X @@ git push --force origin HEAD:main @@ ask @@ @R1@ @@ git push --force origin HEAD:main
X @@ git push -f origin refs/heads/main @@ ask @@ @R1@ @@ git push -f origin refs/heads/main
X @@ git push origin :main @@ ask @@ @R1@ @@ git push origin :main
X @@ git push -o x origin +main @@ ask @@ @R1@ @@ git push -o x origin +main
X @@ git push origin +HEAD while on a feature branch @@ none @@ @R1@ @@ git push origin +HEAD
X @@ git push --delete origin trunk @@ ask @@ @R1@ @@ git push --delete origin trunk
X @@ git push origin --delete main @@ ask @@ @R1@ @@ git push origin --delete main
X @@ git push -d origin main @@ ask @@ @R1@ @@ git push -d origin main
X @@ git push origin :trunk @@ ask @@ @R1@ @@ git push origin :trunk
X @@ git push --force --all origin @@ ask @@ @R1@ @@ git push --force --all origin
X @@ git push --all --force @@ ask @@ @R1@ @@ git push --all --force
X @@ git push --mirror --force @@ ask @@ @R1@ @@ git push --mirror --force
X @@ git push -o x before the remote @@ ask @@ @R1@ @@ git push -o x --force origin trunk
X @@ git push --push-option=x -f origin main @@ ask @@ @R1@ @@ git push --push-option=x -f origin main
X @@ git push --push-option x -f origin main @@ ask @@ @R1@ @@ git push --push-option x -f origin main
X @@ git push -f origin main trunk (several refspecs) @@ ask @@ @R1@ @@ git push -f origin main trunk
X @@ git -C dir push -f origin trunk @@ ask @@ - @@ git -C @R1@ push -f origin trunk
X @@ git -C dir push -f with the current branch default @@ ask @@ - @@ git -C @R2@ push -f
X @@ the second remote's own HEAD @@ ask @@ @R1@ @@ git push -f upstream dev2
X @@ the current branch is the default (trunk): git push --force @@ ask @@ @R2@ @@ git push --force
X @@ the current branch is the default (trunk): git push -f origin @@ ask @@ @R2@ @@ git push -f origin
X @@ the current branch is the default (trunk): --force-with-lease @@ ask @@ @R2@ @@ git push --force-with-lease
X @@ the current branch is the default (trunk): -f origin HEAD @@ ask @@ @R2@ @@ git push -f origin HEAD
X @@ the current branch is the default (trunk): origin +HEAD @@ ask @@ @R2@ @@ git push origin +HEAD
X @@ the current branch is main: git push --force @@ ask @@ @R3@ @@ git push --force
X @@ cd into a repo on trunk, then force push @@ ask @@ - @@ cd @R2@ && git push --force
X @@ git push --force with no repository at all and an explicit main @@ ask @@ - @@ git push --force origin main
X @@ sudo git push -f origin main @@ ask @@ @R1@ @@ sudo git push -f origin main
X @@ doppler run -- git push -f origin main @@ ask @@ @R1@ @@ doppler run -- git push -f origin main
X @@ bash -c 'git push -f origin main' @@ ask @@ @R1@ @@ bash -c 'git push -f origin main'
X @@ a repo whose origin/HEAD is unset: only main and master are default @@ none @@ @R4@ @@ git push --force origin trunk
X @@ git push origin feature-branch @@ none @@ @R1@ @@ git push origin feature-branch
X @@ git push --force-with-lease origin feature-branch @@ none @@ @R1@ @@ git push --force-with-lease origin feature-branch
X @@ git push --force while the current branch is not a default branch @@ none @@ @R1@ @@ git push --force
X @@ git push -f origin HEAD while on a feature branch @@ none @@ @R1@ @@ git push -f origin HEAD
X @@ git push --force origin feature:feature2 @@ none @@ @R1@ @@ git push --force origin feature:feature2
X @@ git push origin trunk (no force) @@ none @@ @R1@ @@ git push origin trunk
X @@ git push -u origin trunk (no force) @@ none @@ @R1@ @@ git push -u origin trunk
X @@ git push (no force) on the default branch @@ none @@ @R2@ @@ git push
X @@ git push --force upstream trunk (trunk is origin's default, not upstream's) @@ none @@ @R1@ @@ git push --force upstream trunk
X @@ git push -f origin dev2 (dev2 is upstream's default, not origin's) @@ none @@ @R1@ @@ git push -f origin dev2
X @@ git push --mirror (no force; D2) @@ none @@ @R1@ @@ git push --mirror
X @@ git push --all (no force) @@ none @@ @R1@ @@ git push --all
X @@ git push origin --delete feature @@ none @@ @R1@ @@ git push origin --delete feature
X @@ git push origin :feature @@ none @@ @R1@ @@ git push origin :feature
X @@ git push -f origin trunk-v2 (a prefix is not the branch) @@ none @@ @R1@ @@ git push -f origin trunk-v2
X @@ git push -f origin mainline @@ none @@ @R1@ @@ git push -f origin mainline
X @@ cd into a feature repo, then force push @@ none @@ - @@ cd @R1@ && git push --force
X @@ git status @@ none @@ @R1@ @@ git status --short
X @@ git log @@ none @@ @R1@ @@ git log --oneline -5
# ---- dead code a static hook cannot see: expected ask or deny, labelled and proven dead --------------
D @@ false && terraform destroy @@ ask @@ - @@ false && terraform destroy
D @@ true || terraform destroy @@ ask @@ - @@ true || terraform destroy
D @@ if false; then terraform destroy; fi @@ ask @@ - @@ if false; then terraform destroy; fi
D @@ while false; do terraform destroy; done @@ ask @@ - @@ while false; do terraform destroy; done
D @@ a ${...} default that never runs @@ ask @@ - @@ x=1; echo ${x:-$(terraform destroy)}
D @@ false && rm -rf ~ @@ deny @@ - @@ false && rm -rf ~
# ---- literal rows: absolute paths, globs against the REAL root, policy asks the shell cannot reproduce
L @@ META-DELETE-TARGET the deletion target: terraform destroy asks @@ ask @@ - @@ terraform destroy
L @@ /bin/rm -rf ~ @@ deny @@ - @@ /bin/rm -rf ~
L @@ /usr/bin/rm -rf ~ @@ deny @@ - @@ /usr/bin/rm -rf ~
L @@ /usr/bin/terraform destroy @@ ask @@ - @@ /usr/bin/terraform destroy
L @@ /usr/bin/env terraform destroy @@ ask @@ - @@ /usr/bin/env terraform destroy
L @@ sudo /bin/rm -rf ~ @@ deny @@ - @@ sudo /bin/rm -rf ~
L @@ sudo -u root /usr/local/bin/terraform destroy @@ ask @@ - @@ sudo -u root /usr/local/bin/terraform destroy
L @@ rm -rf /* (the real root's glob) @@ deny @@ - @@ rm -rf /*
L @@ rm -rf //* @@ deny @@ - @@ rm -rf //*
L @@ cd / && rm -rf * @@ deny @@ - @@ cd / && rm -rf *
L @@ cd / && rm -rf ./* @@ deny @@ - @@ cd / && rm -rf ./*
L @@ cd /tmp && rm -rf ./* (the real /tmp is expanded by a shell, not by the hook) @@ none @@ - @@ cd /tmp && rm -rf ./*
L @@ an unresolvable cd, then a recursive rm @@ ask @@ - @@ cd "$UNKNOWN_DIR" && rm -rf build
L @@ cd - then a recursive rm @@ ask @@ - @@ cd - && rm -rf build
L @@ an unresolvable pushd, then a recursive rm @@ ask @@ - @@ pushd $UNKNOWN_DIR && rm -rf out
L @@ an unresolvable cd, then a force push @@ ask @@ - @@ cd "$UNKNOWN_DIR" && git push --force origin feature
L @@ cd - then a force push @@ ask @@ - @@ cd - && git push -f
L @@ an unresolvable cd, then something else, is not an ask @@ none @@ - @@ cd "$UNKNOWN_DIR" && ls
L @@ an unbalanced single quote @@ ask @@ - @@ echo 'unbalanced
L @@ an unbalanced double quote @@ ask @@ - @@ echo "unbalanced; terraform destroy
L @@ an unterminated substitution @@ ask @@ - @@ echo $(ls
L @@ a heredoc with no delimiter word @@ ask @@ - @@ cat <<
# ---- each prefilter boundary character alone (no rm/destroy/push/eval keyword in the command): the lexer path asks, a skip would not
L @@ prefilter: an unterminated backtick alone @@ ask @@ - @@ echo `ls
L @@ prefilter: an unterminated ${ alone @@ ask @@ - @@ echo ${x
L @@ prefilter: an unterminated <( alone @@ ask @@ - @@ diff <(ls
L @@ prefilter: an unterminated >( alone @@ ask @@ - @@ tee >(cat
# ---- the lexer returns OK with no record: a command whose text (comments removed) mentions a word the guard decides on asks (lexer-empty); a blank, comment-only or keyword-free one does not
L @@ lexer-empty: a bare redirect with no guard keyword is not an ask @@ none @@ - @@ >"out.txt"
L @@ lexer-empty: a bare fd redirect with no guard keyword is not an ask @@ none @@ - @@ 2>&1 # "c"
L @@ lexer-empty: a comment line then a bare redirect with no guard keyword is not an ask @@ none @@ - @@ # note@NL@>"out.txt"
L @@ lexer-empty: > out.log (no quote: the prefilter skips it) is not an ask @@ none @@ - @@ > out.log
L @@ lexer-empty: >> out.log is not an ask @@ none @@ - @@ >> out.log
L @@ lexer-empty: a comment-only command is not an ask @@ none @@ - @@ # just a comment
L @@ lexer-empty: a quoted comment-only command is not an ask @@ none @@ - @@ # only a comment, "quoted" so it reaches the lexer
L @@ lexer-empty: indented comment lines and blank lines are not an ask @@ none @@ - @@ @NL@   # one "q"@NL@@NL@# two
L @@ lexer-empty: a bare redirect whose text mentions git asks @@ ask @@ - @@ >"git.log"
L @@ lexer-empty: a bare redirect whose text mentions destroy asks @@ ask @@ - @@ >"destroy.log"
L @@ lexer-empty: a bare redirect whose text mentions push asks @@ ask @@ - @@ >"push.log"
L @@ lexer-empty: a bare redirect whose text mentions tofu asks @@ ask @@ - @@ >"tofu.log"
L @@ lexer-empty: a bare redirect whose text mentions eval asks @@ ask @@ - @@ >"eval.log"
L @@ lexer-empty: a bare redirect whose text mentions RM in upper case asks (case-insensitive) @@ ask @@ - @@ >"RM.log"
L @@ lexer-empty: a keyword after a mid-line # is still read (only a full-line comment is skipped: "a #b" is not a comment) @@ ask @@ - @@ >"out.txt" # git push
L @@ lexer-empty: a file name that merely contains a keyword (terraform.log) is not an ask @@ none @@ - @@ > terraform.log
L @@ lexer-empty: a file name that merely contains rm (format.log) is not an ask @@ none @@ - @@ > format.log
L @@ lexer-empty: a file name that merely contains rm (confirm.md, appended) is not an ask @@ none @@ - @@ >> confirm.md
L @@ lexer-empty: an input redirect from a file name that starts with rm (rm.txt) is not an ask @@ none @@ - @@ < rm.txt
L @@ lexer-empty: a file name that starts with push (push-notes.md) is not an ask @@ none @@ - @@ > push-notes.md
L @@ lexer-empty: a plain $HOME path with git in a directory name is not an ask @@ none @@ - @@ > $HOME/.config/git/ignore
L @@ lexer-empty: a redirect to a file that IS a keyword (terraform) asks @@ ask @@ - @@ > terraform
L @@ lexer-empty: a keyword only in a comment line before the redirect is not an ask @@ none @@ - @@ # rm -rf ~@NL@>"out.txt"
# ---- a wrapper's chdir option moves the working directory of the command it runs (env -C, --chdir; sudo -D, --chdir), for that command only
L @@ wrapper chdir: env -C / rm -rf * @@ deny @@ - @@ env -C / rm -rf *
L @@ wrapper chdir: env --chdir=/ rm -rf ./* @@ deny @@ - @@ env --chdir=/ rm -rf ./*
L @@ wrapper chdir: env --chdir / rm -rf * (value in the next word) @@ deny @@ - @@ env --chdir / rm -rf *
L @@ wrapper chdir: env --chd=/ rm -rf * (an abbreviation) @@ deny @@ - @@ env --chd=/ rm -rf *
L @@ wrapper chdir: env -iC / rm -rf * (C ends a cluster) @@ deny @@ - @@ env -iC / rm -rf *
L @@ wrapper chdir: env -C/ rm -rf * (value attached) @@ deny @@ - @@ env -C/ rm -rf *
L @@ wrapper chdir: sudo --chdir=/ rm -rf * @@ deny @@ - @@ sudo --chdir=/ rm -rf *
L @@ wrapper chdir: sudo --chdir / rm -rf * (value in the next word) @@ deny @@ - @@ sudo --chdir / rm -rf *
L @@ wrapper chdir: sudo -D / rm -rf * @@ deny @@ - @@ sudo -D / rm -rf *
L @@ wrapper chdir: sudo -nD / rm -rf * (D ends a cluster) @@ deny @@ - @@ sudo -nD / rm -rf *
L @@ wrapper chdir: sudo -D/ rm -rf * (value attached) @@ deny @@ - @@ sudo -D/ rm -rf *
L @@ wrapper chdir: env -C /tmp rm -rf ./x is no decision @@ none @@ - @@ env -C /tmp rm -rf ./x
L @@ wrapper chdir: env -C /tmp moves the cwd away from home: rm -rf ./* is no decision @@ none @@ @HOME@ @@ env -C /tmp rm -rf ./*
L @@ wrapper chdir: sudo -D /tmp moves the cwd away from home: rm -rf ./* is no decision @@ none @@ @HOME@ @@ sudo -D /tmp rm -rf ./*
L @@ wrapper chdir: the move is for the wrapped command only (env -C /tmp true; rm -rf ./* in home still denies) @@ deny @@ @HOME@ @@ env -C /tmp true; rm -rf ./*
L @@ wrapper chdir: an unresolvable env -C directory before a recursive rm asks @@ ask @@ - @@ env -C "$UNKNOWN_DIR" rm -rf build
L @@ wrapper chdir: an unresolvable sudo -D directory before a force push asks @@ ask @@ - @@ sudo -D "$UNKNOWN_DIR" git push --force origin feature
L @@ wrapper chdir: an unresolvable env -C directory before something else is no decision @@ none @@ - @@ env -C "$UNKNOWN_DIR" ls
L @@ wrapper chdir: an unresolvable directory is for the wrapped command only (the next rm is judged normally) @@ none @@ - @@ env -C "$UNKNOWN_DIR" true; rm -rf build
# ---- decide_argv keeps the caller's state: a `--` or a wrapper must not change what the cd effect or the quote sees
X @@ state: cd -- ~ then rm -rf * (a `--` after cd must not hide the cd) @@ deny @@ - @@ cd -- ~ && rm -rf *
X @@ state: pushd -- ~ then rm -rf * @@ deny @@ - @@ pushd -- ~ && rm -rf *
X @@ state: command cd ~ then rm -rf * (a wrapper before cd still moves the simulated cwd) @@ deny @@ - @@ command cd ~ && rm -rf *
X @@ state: a -- word in an earlier command, then rm -rf ./* in home (the later cd-looking word is data) @@ deny @@ @HOME@ @@ ls -- cd /tmp; rm -rf ./*
X @@ state: a bare cd after -- is data, not a cd to home @@ none @@ - @@ ls -- cd; rm -rf ./*
L @@ state: cd -- .. from a child of home reaches home, then rm -rf * @@ deny @@ @HOME@/proj @@ cd -- .. && rm -rf *
L @@ state: cd -- "$X" is an unresolved cd, then rm -rf * @@ ask @@ - @@ cd -- "$UNKNOWN_DIR" && rm -rf *
L @@ state: pushd -- "$X" is an unresolved pushd, then rm -rf out @@ ask @@ - @@ pushd -- "$UNKNOWN_DIR" && rm -rf out
# ---- wrappers (D1's table: sudo doas env command nohup time timeout nice; literal rows where the oracle's own table has no such member)
X @@ wrapper: time -p rm -rf ~ (the lexer drops the reserved word and leaves -p, which is a pseudo-wrapper) @@ deny @@ - @@ time -p rm -rf ~
X @@ wrapper: time -p terraform destroy @@ ask @@ - @@ time -p terraform destroy
L @@ wrapper: /usr/bin/time rm -rf ~ (time as a command word) @@ deny @@ - @@ /usr/bin/time rm -rf ~
L @@ wrapper: command time -p rm -rf ~ @@ deny @@ - @@ command time -p rm -rf ~
L @@ wrapper: env time rm -rf ~ @@ deny @@ - @@ env time rm -rf ~
L @@ wrapper: sudo time -v rm -rf ~ @@ deny @@ - @@ sudo time -v rm -rf ~
L @@ wrapper: sudo time -f %e -o out.txt rm -rf ~ (time's value options are skipped) @@ deny @@ - @@ sudo time -f %e -o out.txt rm -rf ~
L @@ wrapper: /usr/bin/time -o log.txt terraform destroy @@ ask @@ - @@ /usr/bin/time -o log.txt terraform destroy
L @@ wrapper: /usr/bin/time -p rm -rf build is not a delete of home @@ none @@ - @@ /usr/bin/time -p rm -rf build
# ---- short-option clusters whose last letter takes a value shift one more word
L @@ wrapper: sudo -nu root rm -rf / @@ deny @@ - @@ sudo -nu root rm -rf /
L @@ wrapper: sudo -Eu root rm -rf / @@ deny @@ - @@ sudo -Eu root rm -rf /
L @@ wrapper: sudo -Hu root rm -rf / @@ deny @@ - @@ sudo -Hu root rm -rf /
L @@ wrapper: sudo -Su root rm -rf / @@ deny @@ - @@ sudo -Su root rm -rf /
L @@ wrapper: sudo -nHu root rm -rf / @@ deny @@ - @@ sudo -nHu root rm -rf /
L @@ wrapper: sudo -nEu root terraform destroy @@ ask @@ - @@ sudo -nEu root terraform destroy
L @@ wrapper: sudo -uroot rm -rf / (an attached value needs no extra word) @@ deny @@ - @@ sudo -uroot rm -rf /
L @@ wrapper: sudo -nu root ls / is not a delete @@ none @@ - @@ sudo -nu root ls /
L @@ wrapper: env -iu X rm -rf / @@ deny @@ - @@ env -iu X rm -rf /
L @@ wrapper: env -P /usr/bin rm -rf / (-P takes a value) @@ deny @@ - @@ env -P /usr/bin rm -rf /
L @@ wrapper: env - rm -rf ~ (a lone - is -i) @@ deny @@ - @@ env - rm -rf ~
L @@ wrapper: doas -nu root rm -rf / @@ deny @@ - @@ doas -nu root rm -rf /
L @@ wrapper: timeout -vk 5 10 rm -rf ~ @@ deny @@ - @@ timeout -vk 5 10 rm -rf ~
L @@ wrapper: timeout -vs KILL 5 terraform destroy @@ ask @@ - @@ timeout -vs KILL 5 terraform destroy
# ---- env -S runs a string the guard does not analyse: an ask with its own rule id
L @@ wrapper: env -S 'rm -rf /' asks (unparsed) @@ ask @@ - @@ env -S 'rm -rf /'
L @@ wrapper: env -iS 'rm -rf /' asks (a cluster ending in S) @@ ask @@ - @@ env -iS 'rm -rf /'
L @@ wrapper: env --split-string='rm -rf /' asks @@ ask @@ - @@ env --split-string='rm -rf /'
L @@ wrapper: env --split-string 'terraform destroy' asks @@ ask @@ - @@ env --split-string 'terraform destroy'
L @@ wrapper: env --spl 'rm -rf /' asks (an abbreviation of --split-string) @@ ask @@ - @@ env --spl 'rm -rf /'
# ---- the value-taking options of the rewritten wrappers still shift the right number of words
L @@ wrapper: env --unset X rm -rf ~ @@ deny @@ - @@ env --unset X rm -rf ~
L @@ wrapper: env --unset=X rm -rf ~ @@ deny @@ - @@ env --unset=X rm -rf ~
L @@ wrapper: env --chdir /tmp rm -rf ~ @@ deny @@ - @@ env --chdir /tmp rm -rf ~
L @@ wrapper: env -C /tmp rm -rf ~ @@ deny @@ - @@ env -C /tmp rm -rf ~
L @@ wrapper: sudo -g wheel rm -rf ~ @@ deny @@ - @@ sudo -g wheel rm -rf ~
L @@ wrapper: sudo --user root rm -rf ~ @@ deny @@ - @@ sudo --user root rm -rf ~
L @@ wrapper: sudo --user=root rm -rf ~ @@ deny @@ - @@ sudo --user=root rm -rf ~
L @@ wrapper: doas -C /etc/doas.conf rm -rf ~ @@ deny @@ - @@ doas -C /etc/doas.conf rm -rf ~
L @@ wrapper: timeout --signal KILL 5 rm -rf ~ @@ deny @@ - @@ timeout --signal KILL 5 rm -rf ~
L @@ wrapper: timeout -k 5 10 rm -rf ~ @@ deny @@ - @@ timeout -k 5 10 rm -rf ~
L @@ wrapper: nice --adjustment 5 rm -rf ~ @@ deny @@ - @@ nice --adjustment 5 rm -rf ~
L @@ wrapper: nice -n5 rm -rf ~ (an attached value) @@ deny @@ - @@ nice -n5 rm -rf ~
# ---- more wrappers than the guard unwraps is an ask, never a silent allow
L @@ wrapper: eight nested sudo are still unwrapped (deny) @@ deny @@ - @@ sudo sudo sudo sudo sudo sudo sudo sudo rm -rf /
L @@ wrapper: nine nested sudo before rm -rf / ask (wrapper-depth) @@ ask @@ - @@ sudo sudo sudo sudo sudo sudo sudo sudo sudo rm -rf /
L @@ wrapper: twelve nested env before rm -rf / ask (wrapper-depth) @@ ask @@ - @@ env env env env env env env env env env env env rm -rf /
# ---- command names are compared case-insensitively (a case-insensitive filesystem runs RM as rm)
L @@ case: RM -rf ~ @@ deny @@ - @@ RM -rf ~
L @@ case: Rm -rf / @@ deny @@ - @@ Rm -rf /
L @@ case: rM -rf ~ @@ deny @@ - @@ rM -rf ~
L @@ case: Sudo -u x RM -rf ~ @@ deny @@ - @@ Sudo -u x RM -rf ~
L @@ case: GIT push --force origin main @@ ask @@ @R1@ @@ GIT push --force origin main
L @@ case: Terraform destroy @@ ask @@ - @@ Terraform destroy
X @@ case: an argument named RM is not a command (rm -rf RM) @@ none @@ - @@ rm -rf RM
X @@ case: echo RM -rf ~ (arguments, not a command) @@ none @@ - @@ echo RM -rf ~
# ---- spellings inside D1's rules: terraform apply -destroy=<bool> (a Go bool: 1 t T TRUE true True and 0 f F FALSE false False)
L @@ spelling: terraform apply -destroy=1 @@ ask @@ - @@ terraform apply -destroy=1
L @@ spelling: terraform apply -destroy=t @@ ask @@ - @@ terraform apply -destroy=t
L @@ spelling: terraform apply -destroy=T @@ ask @@ - @@ terraform apply -destroy=T
L @@ spelling: terraform apply -destroy=TRUE @@ ask @@ - @@ terraform apply -destroy=TRUE
L @@ spelling: terraform apply -destroy=True @@ ask @@ - @@ terraform apply -destroy=True
L @@ spelling: tofu apply --destroy=1 -auto-approve @@ ask @@ - @@ tofu apply --destroy=1 -auto-approve
L @@ spelling: terraform apply -destroy=true @@ ask @@ - @@ terraform apply -destroy=true
L @@ spelling: terraform apply -destroy=maybe (not a bool: terraform refuses it, the guard asks) @@ ask @@ - @@ terraform apply -destroy=maybe
L @@ spelling: terraform apply -destroy=false @@ none @@ - @@ terraform apply -destroy=false
L @@ spelling: terraform apply -destroy=0 @@ none @@ - @@ terraform apply -destroy=0
L @@ spelling: terraform apply -destroy=f @@ none @@ - @@ terraform apply -destroy=f
L @@ spelling: terraform apply -destroy=F @@ none @@ - @@ terraform apply -destroy=F
L @@ spelling: terraform apply -destroy=FALSE @@ none @@ - @@ terraform apply -destroy=FALSE
L @@ spelling: terraform apply -destroy=False @@ none @@ - @@ terraform apply -destroy=False
L @@ spelling: tofu apply --destroy=false @@ none @@ - @@ tofu apply --destroy=false
# ---- spellings inside D1's rules: git push
L @@ spelling: git push --force --al origin (--al is the unique abbreviation of --all) @@ ask @@ @R1@ @@ git push --force --al origin
L @@ spelling: git push --force --mir origin (an abbreviation of --mirror) @@ ask @@ @R1@ @@ git push --force --mir origin
L @@ spelling: git push --al origin (no force) @@ none @@ @R1@ @@ git push --al origin
L @@ spelling: git push -f origin heads/main @@ ask @@ @R1@ @@ git push -f origin heads/main
L @@ spelling: git push -f origin HEAD:heads/main @@ ask @@ @R1@ @@ git push -f origin HEAD:heads/main
L @@ spelling: git push -f origin heads/trunk (origin's own default) @@ ask @@ @R1@ @@ git push -f origin heads/trunk
L @@ spelling: git push -f origin a glob refspec whose destination is a glob @@ ask @@ @R1@ @@ git push -f origin 'refs/heads/*:refs/heads/*'
L @@ spelling: git push origin +glob:glob @@ ask @@ @R1@ @@ git push origin '+refs/heads/*:refs/heads/*'
L @@ spelling: git push -f origin : (the matching refspec) @@ ask @@ @R1@ @@ git push -f origin :
L @@ spelling: git push origin +: (the forced matching refspec) @@ ask @@ @R1@ @@ git push origin +:
L @@ spelling: git push origin glob:glob (no force) @@ none @@ @R1@ @@ git push origin 'refs/heads/*:refs/heads/*'
L @@ spelling: git push origin : (the matching refspec, no force) @@ none @@ @R1@ @@ git push origin :
L @@ spelling: git push -f origin heads/feature-x @@ none @@ @R1@ @@ git push -f origin heads/feature-x
L @@ spelling: git --config-env x=Y push -f origin main (a separate-argument global option) @@ ask @@ @R1@ @@ git --config-env x=Y push -f origin main
L @@ spelling: git --config-env=x=Y push -f origin main @@ ask @@ @R1@ @@ git --config-env=x=Y push -f origin main
L @@ spelling: git --git-dir=.git push -f origin main (an attached global option takes no extra word) @@ ask @@ @R1@ @@ git --git-dir=.git push -f origin main
L @@ spelling: git --git-dir .git push -f origin main @@ ask @@ @R1@ @@ git --git-dir .git push -f origin main
L @@ spelling: git --exec-path=/x push -f origin main @@ ask @@ @R1@ @@ git --exec-path=/x push -f origin main
L @@ spelling: git -c user.name=x push -f origin main @@ ask @@ @R1@ @@ git -c user.name=x push -f origin main
L @@ spelling: git -c alias.p=push p -f origin main (an alias is NOT DECIDED) @@ none @@ @R1@ @@ git -c alias.p=push p -f origin main
# ---- spellings inside D1's rules: rm targets that are only glob syntax are the contents of / or home
L @@ spelling: rm -rf /** @@ deny @@ - @@ rm -rf /**
L @@ spelling: rm -rf /*/* @@ deny @@ - @@ rm -rf /*/*
L @@ spelling: rm -rf /*/ @@ deny @@ - @@ rm -rf /*/
L @@ spelling: rm -rf /? @@ deny @@ - @@ rm -rf /?
L @@ spelling: rm -rf /[a-z]* @@ deny @@ - @@ rm -rf /[a-z]*
L @@ spelling: rm -rf ~/** @@ deny @@ - @@ rm -rf ~/**
L @@ spelling: rm -rf $HOME/** @@ deny @@ - @@ rm -rf $HOME/**
L @@ spelling: rm -rf ${HOME}/*/* @@ deny @@ - @@ rm -rf ${HOME}/*/*
L @@ spelling: rm -rf ~/*/ @@ deny @@ - @@ rm -rf ~/*/
L @@ spelling: rm -rf ** with home as the working directory @@ deny @@ @HOME@ @@ rm -rf **
L @@ spelling: rm -rf ./*/* with home as the working directory @@ deny @@ @HOME@ @@ rm -rf ./*/*
L @@ spelling: rm -rf ~/*/node_modules (a literal component after the glob) @@ none @@ - @@ rm -rf ~/*/node_modules
L @@ spelling: rm -rf /home/*/x (a literal component after the glob) @@ none @@ - @@ rm -rf /home/*/x
L @@ spelling: rm -rf /*.log (a glob with a literal part is not the contents of /) @@ none @@ - @@ rm -rf /*.log
L @@ spelling: rm -rf ~/.* (a partial glob, a stated residual) @@ none @@ - @@ rm -rf ~/.*
L @@ spelling: rm -rf ~/*.tmp @@ none @@ - @@ rm -rf ~/*.tmp
L @@ spelling: rm -rf ./** outside home is routine @@ none @@ - @@ rm -rf ./**
L @@ spelling: rm -rf '/**' (a quoted ** is a file name) @@ none @@ - @@ rm -rf '/**'
X @@ spelling: rm -rf ~+ is the working directory @@ ask @@ @SUB@ @@ rm -rf ~+
X @@ spelling: rm -rf ~+/build is a child of the working directory @@ none @@ @SUB@ @@ rm -rf ~+/build
# ---- spellings inside D1's rules: the cwd rule compares against the envelope's cwd as well as the simulated one
L @@ spelling: cd .. && rm -rf sub from sub asks (the target is the original working directory) @@ ask @@ @SUB@ @@ cd .. && rm -rf sub
L @@ spelling: cd ~ && rm -rf proj from home/proj asks @@ ask @@ @HOME@/proj @@ cd ~ && rm -rf proj
L @@ spelling: pushd .. then rm -rf sub from sub asks @@ ask @@ @SUB@ @@ pushd .. > /dev/null; rm -rf sub
L @@ spelling: cd .. && rm -rf other from sub is not the working directory @@ none @@ @SUB@ @@ cd .. && rm -rf other
# ---- member rows: one row per member of a wrapper / flag / table the hook handles (a member with no row can be deleted unseen)
X @@ member: terraform apply --destroy @@ ask @@ - @@ terraform apply --destroy
X @@ member: terraform apply --destroy=true @@ ask @@ - @@ terraform apply --destroy=true
X @@ member: command -V is a look-up, rm never runs @@ none @@ - @@ command -V rm -rf ~
L @@ member: command -pv is a look-up cluster (literal: command -p resets PATH) @@ none @@ - @@ command -pv rm -rf ~
X @@ member: git push -f origin develop (develop is not a default branch of any fixture remote) @@ none @@ @R1@ @@ git push -f origin develop
X @@ member: a repo on master with no origin/HEAD: git push --force @@ ask @@ @R5@ @@ git push --force
X @@ member: a repo on master with no origin/HEAD: git push --force-with-lease origin HEAD @@ ask @@ @R5@ @@ git push --force-with-lease origin HEAD
X @@ member: a repo on master with no origin/HEAD: git push (no force) @@ none @@ @R5@ @@ git push
L @@ member: git --work-tree /tmp push -f origin main (a separate-argument global option) @@ ask @@ @R1@ @@ git --work-tree /tmp push -f origin main
L @@ member: git --namespace n push -f origin main @@ ask @@ @R1@ @@ git --namespace n push -f origin main
L @@ member: git --super-prefix p/ push -f origin main @@ ask @@ @R1@ @@ git --super-prefix p/ push -f origin main
L @@ member: git --attr-source HEAD push -f origin main @@ ask @@ @R1@ @@ git --attr-source HEAD push -f origin main
X @@ member: git push --receive-pack x -f origin trunk @@ ask @@ @R1@ @@ git push --receive-pack x -f origin trunk
X @@ member: git push --exec x -f origin trunk @@ ask @@ @R1@ @@ git push --exec x -f origin trunk
X @@ member: git push --receive-pack=x -f origin trunk @@ ask @@ @R1@ @@ git push --receive-pack=x -f origin trunk
L @@ member: git push --del origin main (an abbreviation of --delete) @@ ask @@ @R1@ @@ git push --del origin main
L @@ member: git push --dele origin main @@ ask @@ @R1@ @@ git push --dele origin main
L @@ member: git push --delet origin main @@ ask @@ @R1@ @@ git push --delet origin main
L @@ member: rm --recur ~ (an abbreviation of --recursive) @@ deny @@ - @@ rm --recur ~
L @@ member: rm --rec -f ~ @@ deny @@ - @@ rm --rec -f ~
X @@ member: rm -rf $PWD is the working directory @@ ask @@ @SUB@ @@ rm -rf $PWD
X @@ member: rm -rf ${PWD} is the working directory @@ ask @@ @SUB@ @@ rm -rf ${PWD}
X @@ member: rm -rf "$PWD" is the working directory @@ ask @@ @SUB@ @@ rm -rf "$PWD"
L @@ member: popd && rm -rf build (the directory popd returns to is unknown) @@ ask @@ - @@ popd && rm -rf build
L @@ member: popd; rm -rf build @@ ask @@ - @@ popd; rm -rf build
X @@ member: a bare cd goes to home, then rm -rf ./* @@ deny @@ - @@ cd && rm -rf ./*
X @@ member: cd -P ~ then rm -rf ./* (the -P flag is skipped) @@ deny @@ - @@ cd -P ~ && rm -rf ./*
X @@ member: cd -L ~ then rm -rf ./* @@ deny @@ - @@ cd -L ~ && rm -rf ./*
# ---- stated non-coverage (NOT DECIDED in the header and ADR-274): each is pinned so a change that starts to decide it is a visible choice
X @@ NOT DECIDED: terragrunt destroy @@ none @@ - @@ terragrunt destroy
X @@ NOT DECIDED: pulumi destroy @@ none @@ - @@ pulumi destroy
X @@ NOT DECIDED: xargs rm -rf ~ (xargs is not a wrapper) @@ none @@ - @@ xargs rm -rf ~
# ---- the lexer's quoting forms, decoded: octal, \u, $'..' of a plain name and $"..." in command position
X @@ lexer: octal escape in the command word ($'\162m') @@ deny @@ - @@ $'\162m' -rf ~
X @@ lexer: octal escape in the subcommand word @@ ask @@ - @@ terraform $'\144estroy'
X @@ lexer: \u escape in the command word @@ deny @@ - @@ $'\u0072m' -rf ~
X @@ lexer: \u escape in the subcommand word @@ ask @@ - @@ terraform $'\u0064estroy'
X @@ lexer: $'rm' of a plain name @@ deny @@ - @@ $'rm' -rf ~
X @@ lexer: a locale-quoted command word ($"rm") @@ deny @@ - @@ $"rm" -rf ~
X @@ lexer: a locale-quoted subcommand word ($"destroy") @@ ask @@ - @@ terraform $"destroy"
# ---- a glob in a NON-terminal component: the hook runs with the glob switch off, or these would expand against its own working directory
L @@ glob: rm -rf ~/*/.. reaches home through a glob component @@ deny @@ - @@ rm -rf ~/*/..
L @@ glob: rm -rf */.. from the working tree reaches the working tree @@ ask @@ - @@ rm -rf */..
ROWS

echo "== the ordinary-command corpus (kind C): no decision on any of it =="
run_table 4 4<<'ROWS'
C @@ corpus: ls -la @@ none @@ - @@ ls -la
C @@ corpus: git status --short @@ none @@ @R1@ @@ git status --short
C @@ corpus: git diff --stat HEAD~1 @@ none @@ @R1@ @@ git diff --stat HEAD~1
C @@ corpus: git log --oneline -5 @@ none @@ @R1@ @@ git log --oneline -5
C @@ corpus: git commit -m with a destructive word in the message @@ none @@ @R1@ @@ git commit -m "fix: rm -rf handling and terraform destroy docs"
C @@ corpus: git push origin feature-branch @@ none @@ @R1@ @@ git push origin feature-branch
C @@ corpus: git push -u origin HEAD on a feature branch @@ none @@ @R1@ @@ git push -u origin HEAD
C @@ corpus: git pull --rebase origin trunk @@ none @@ @R1@ @@ git pull --rebase origin trunk
C @@ corpus: git branch -D old-feature @@ none @@ @R1@ @@ git branch -D old-feature
C @@ corpus: git stash list @@ none @@ @R1@ @@ git stash list
C @@ corpus: npm install && npm test @@ none @@ - @@ npm install && npm test
C @@ corpus: npm run build 2>&1 | tail -20 @@ none @@ - @@ npm run build 2>&1 | tail -20
C @@ corpus: docker ps -a @@ none @@ - @@ docker ps -a
C @@ corpus: docker build then run @@ none @@ - @@ docker build -t app . && docker run --rm app
C @@ corpus: a for loop @@ none @@ - @@ for f in *.txt; do echo "$f"; done
C @@ corpus: a case statement @@ none @@ - @@ case "$1" in start) echo go;; stop) echo stop;; esac
C @@ corpus: a [[ ]] test @@ none @@ - @@ [[ -f package.json ]] && echo yes || echo no
C @@ corpus: a here-string mentioning rm -rf @@ none @@ - @@ cat <<< "here string with rm -rf /"
C @@ corpus: grep | wc @@ none @@ - @@ grep -n "TODO" src/app.ts | wc -l
C @@ corpus: find -exec cat @@ none @@ - @@ find src -name '*.log' -exec cat {} \;
C @@ corpus: find by type @@ none @@ - @@ find build -type f -name '*.tmp'
C @@ corpus: mkdir && cp -r @@ none @@ - @@ mkdir -p build/out && cp -r src/. build/out/
C @@ corpus: mv @@ none @@ - @@ mv old.txt new.txt
C @@ corpus: rm file.txt @@ none @@ - @@ rm file.txt
C @@ corpus: rm -f a log @@ none @@ - @@ rm -f build/out.log
C @@ corpus: rm -r a build directory @@ none @@ - @@ rm -r build
C @@ corpus: rm -rf several build outputs @@ none @@ - @@ rm -rf node_modules .next dist
C @@ corpus: rm -rf an absolute child of the working tree @@ none @@ - @@ rm -rf @TREE@/build
C @@ corpus: redirect to /dev/null @@ none @@ - @@ echo "done" > /dev/null
C @@ corpus: export then echo @@ none @@ - @@ export FOO=bar; echo $FOO
C @@ corpus: tail | head @@ none @@ - @@ tail -f log | head -5
C @@ corpus: sed -n @@ none @@ - @@ sed -n '1,10p' file
C @@ corpus: awk @@ none @@ - @@ awk '{print $1}' file
C @@ corpus: curl | jq @@ none @@ - @@ curl -sS https://example.com/health | jq .status
C @@ corpus: terraform fmt -check @@ none @@ - @@ terraform fmt -check
C @@ corpus: terraform validate @@ none @@ - @@ terraform validate
C @@ corpus: terraform plan -out @@ none @@ - @@ terraform plan -out=tfplan
C @@ corpus: terraform apply tfplan (a plain apply, D2) @@ none @@ - @@ terraform apply tfplan
C @@ corpus: a command substitution assignment @@ none @@ - @@ x=$(date +%s); echo "$x"
C @@ corpus: an if test @@ none @@ - @@ if [ -d build ]; then echo built; fi
C @@ corpus: a while read loop @@ none @@ - @@ while read -r l; do echo "$l"; done < file
C @@ corpus: a subshell with cd @@ none @@ - @@ (cd sub && ls)
C @@ corpus: a brace group piped to sort @@ none @@ - @@ { echo a; echo b; } | sort
C @@ corpus: printf with a substitution @@ none @@ - @@ printf '%s\n' "$(pwd)"
C @@ corpus: tar @@ none @@ - @@ tar czf out.tgz src
C @@ corpus: python -c with a destructive string @@ none @@ - @@ python3 -c 'print("rm -rf /")'
C @@ corpus: diff of two process substitutions @@ none @@ - @@ diff <(ls a) <(ls b)
C @@ corpus: a heredoc into cat @@ none @@ - @@ cat <<EOF@NL@hello@NL@EOF
C @@ corpus: make with a clean target @@ none @@ - @@ make clean
C @@ corpus: kubectl get @@ none @@ - @@ kubectl get pods
C @@ corpus: psql -c select @@ none @@ - @@ psql -c 'select 1'
C @@ corpus: echo with a tilde @@ none @@ - @@ echo ~
C @@ corpus: ls of home @@ none @@ - @@ ls ~/projects
C @@ corpus: a sleep and a chmod @@ none @@ - @@ sleep 1; chmod +x script.sh
ROWS

# =====================================================================================================
echo "== literal rows with a HOME the oracle cannot create (a /home path) =="
_saved_home="$HOME_W"
HOME_W_REAL="$HOME_W"
LH() { # LH <label> <want> <home> <command>
  local label="$1" want="$2" home="$3" cmd="$4"
  want_row "$label" || return 0
  ROWS_LIT=$((ROWS_LIT + 1))
  CUR_HOME="$home"
  hook_run "$(mkjson "$cmd" "$TREE")"
  classify
  chk "$label" "$(verdict_of "$want" "$GOT")" "want=$want got=$GOT"
  CUR_HOME="$HOME_W_REAL"
}
_FH="/home/soleur-guard-fixture-user"
LH "/home is an ancestor of the home directory" deny "$_FH" 'rm -rf /home'
LH "/home/* is the contents of an ancestor" deny "$_FH" 'rm -rf /home/*'
LH "a nonexistent home directory is still home" deny "$_FH" "rm -rf $_FH"
LH "the contents of a nonexistent home" deny "$_FH" "rm -rf $_FH/*"
LH "rm -rf ~ with a nonexistent home" deny "$_FH" 'rm -rf ~'
LH "a project under a nonexistent home is not home" none "$_FH" "rm -rf $_FH/projects/x"
LH "another user's home is not this home" none "$_FH" 'rm -rf /home/other-user-dir'
LH "a .. through a nonexistent directory is normalized lexically and still reaches an ancestor of home" deny "$_FH" "rm -rf $_FH/nonexistent-dir/../.."

# an empty or unset HOME: bash resolves ~ through the passwd entry (and $HOME/ is /), so the guard must too
_pwhome="$( ( unset HOME; cd ~ 2>/dev/null && pwd -P ) 2>/dev/null )"
_pw_want=none; [[ -n "$_pwhome" ]] && _pw_want=deny
env_row "unset HOME: rm -rf ~ resolves ~ through the passwd entry (deny when the account has a home directory)" "$_pw_want" "$(mkjson 'rm -rf ~' "$TREE")" HOME=
env_row "unset HOME: rm -rf ~/ resolves ~ through the passwd entry" "$_pw_want" "$(mkjson 'rm -rf ~/' "$TREE")" HOME=
_RMRF="rm -rf"  # held in a variable so the fixture scanner does not read the command text below as a call
env_row "unset HOME: a quoted HOME-slash target is / and is denied" deny "$(mkjson "$_RMRF"' "$HOME/"' "$TREE")" HOME=
env_row "unset HOME: rm -rf \$HOME/* is rm -rf /* and is denied" deny "$(mkjson 'rm -rf $HOME/*' "$TREE")" HOME=
env_row "unset HOME: rm -rf \$HOME alone is rm -rf with no operand: no decision" none "$(mkjson 'rm -rf $HOME' "$TREE")" HOME=

# =====================================================================================================
echo "== the quoted command in the reason is the whole matched simple command (state is not clobbered) =="
quote_row() { # <label> <command> <cwd-template> <expected quoted text>
  want_row_quiet "$1" || return 0
  subst "$3"; hook_run "$(mkjson "$2" "$SUBST_OUT")"
  reason_has "$1" "Matched command: [$4]"
}
quote_row "quote: a wrapper stays in the quoted command (sudo rm -rf /)" 'sudo rm -rf /' - 'sudo rm -rf /'
quote_row "quote: the words before a -- stay in the quoted command (rm -rf -- /)" 'rm -rf -- /' - 'rm -rf -- /'
quote_row "quote: doppler run -- terraform destroy quotes the whole command" 'doppler run -- terraform destroy' - 'doppler run -- terraform destroy'
quote_row "quote: an env wrapper with an option and an assignment" 'env -i FOO=1 terraform destroy' - 'env -i FOO=1 terraform destroy'
rule_row() { # <label> <command> <cwd-template> <rule id>: the reason starts (after the not-run sentence) with the rule id
  want_row_quiet "$1" || return 0
  subst "$3"; hook_run "$(mkjson "$2" "$SUBST_OUT")"
  jqchk "$1" '.hookSpecificOutput.permissionDecisionReason | test("(^|\\. )" + $id + ": ")' --arg id "$4"
}
rule_row "rule id: env -S asks with its own rule id" "env -S 'rm -rf /'" - unparsed-wrapper
rule_row "rule id: env -iS asks with its own rule id" "env -iS 'rm -rf /'" - unparsed-wrapper
rule_row "rule id: nine nested sudo ask with the wrapper-depth rule id" 'sudo sudo sudo sudo sudo sudo sudo sudo sudo ls "x"' - wrapper-depth

# =====================================================================================================
echo "== the bash phase is bounded (the harness kills the hook at 10 s and a killed hook is not a decision) =="
rep 'echo x; ' 1500; _cmd1500="${REP_OUT}rm -rf /"
rep 'echo x; ' 2600; _cmd2600="${REP_OUT}rm -rf /"
rep 'echo x; ' 2600; _cmd2600_late="rm -rf /; ${REP_OUT}"
rep ' --' 40; _cmd40dash="ls${REP_OUT} x; terraform destroy"
_t=""; for _i in $(seq 1 1000); do _t+=" f$_i"; done; _cmd1000rm="rm -rf${_t}; rm -rf ~"
rep ' a' 30000; _cmdwords="ls \"x\"${REP_OUT}"
bound_row "bound: 1500 benign commands then rm -rf / still denies, in under 5 s" deny - "$_cmd1500"
bound_row "bound: 2600 benign commands (above the record cap) then rm -rf / asks with the bound reason, in under 5 s" ask - "$_cmd2600" "^${ASK_LEAD_RX}bound: "
bound_row "bound: rm -rf / first, then 2600 benign commands (above the record cap) still denies" deny - "$_cmd2600_late"
rep 'echo x; ' 2600; _cmd2600_mid="echo a; echo b; echo c; rm -rf /; ${REP_OUT}"
bound_row "bound: rm -rf / after three benign commands, then 2600 more (above the record cap) still denies (the records read are judged)" deny - "$_cmd2600_mid"
bound_row "bound: rm -rf / after a benign command, then a 30000-word command (above the word cap) still denies" deny - "echo a; rm -rf /; ${_cmdwords}"
bound_row "bound: 40 -- words then terraform destroy asks, in under 5 s" ask - "$_cmd40dash"
bound_row "bound: a 1000-target rm line then rm -rf ~ denies, in under 5 s" deny - "$_cmd1000rm"
bound_row "bound: 30000 words in one command (above the word cap) asks with the bound reason, in under 5 s" ask - "$_cmdwords" "^${ASK_LEAD_RX}bound: "
# A bound that trips AFTER an ask-class rule matched keeps that rule's reason (id, lead, the quoted command) and appends the bound
# sentence; it never says the command was "not recognised as destructive" (it was).
rep 'echo "N"; ' 2100; _cmdtf_then_many="terraform destroy; ${REP_OUT}"
rep 'true; ' 2100; _cmdgit_then_many="git push -f origin main; ${REP_OUT}"
bound_row "bound: terraform destroy then 2100 more commands asks with the destroy rule id and the bound sentence, in under 5 s" ask - "$_cmdtf_then_many" "^${ASK_LEAD_RX}infra-destroy: .*Matched command: \[terraform destroy\].*too large to check in full"
jqchk "bound: that ask does not say the command was not recognised as destructive" '.hookSpecificOutput.permissionDecisionReason | contains("not recognised as destructive") | not'
jqchk "bound: that ask still carries the escape hatch and the issues URL" '.hookSpecificOutput.permissionDecisionReason | (contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues"))'
bound_row "bound: git push -f origin main then 2100 more commands asks with the force-push rule id and the bound sentence, in under 5 s" ask - "$_cmdgit_then_many" "^${ASK_LEAD_RX}default-branch-force-push: .*Matched command: \[git push -f origin main\].*too large to check in full"
jqchk "bound: that force-push ask does not say the command was not recognised as destructive" '.hookSpecificOutput.permissionDecisionReason | contains("not recognised as destructive") | not'
# A deep nonexistent target: the longest existing prefix is looked for once, with a depth cap (no per-level probe that grows with the path).
rep '/a' 650; _REP650="$REP_OUT"; _cmddeep650="rm -rf /nonexist${REP_OUT}; rm -rf /"
rep '/a' 100; _cmddeep100="rm -rf /nonexist${REP_OUT}; rm -rf /"
_t=""; for _i in $(seq 1 300); do _t+=" /nx$_i/a/b/c"; done; _cmd300nx="rm -rf${_t}"
bound_row "bound: a 650-component nonexistent rm target then rm -rf / still denies (a deny wins over the depth cap), in under 5 s" deny - "$_cmddeep650"
bound_row "bound: a 650-component nonexistent rm target alone asks with the bound reason, in under 5 s" ask - "rm -rf /nonexist${_REP650}" "^${ASK_LEAD_RX}bound: .*more than 128"
bound_row "bound: a 100-component nonexistent rm target then rm -rf / still denies, in under 5 s" deny - "$_cmddeep100"
bound_row "bound: 300 distinct nonexistent rm targets are judged within the deadline (no decision), in under 5 s" none - "$_cmd300nx"
_t=""; for _i in $(seq 1 2400); do _t+=" /nonexist/f$_i"; done; _cmd2400same="rm -rf${_t}"
bound_row "bound: 2400 nonexistent rm targets under one parent are judged within the deadline (the parent is resolved once), in under 5 s" none - "$_cmd2400same"
# Command-name case folding is fork-free: 1999 capitalised no-op commands then rm -rf / still deny (a `tr` per record turned this into a bound ask), and a PATH with no `tr` still decides RM.
rep "Make 'x'; " 1999; _cmd1999Make="${REP_OUT}rm -rf /"
bound_row "bound: 1999 capitalised commands (Make) then rm -rf / still denies, in under 5 s" deny - "$_cmd1999Make"
env_row "case fold: a PATH with no tr still denies RM -rf ~" deny "$(mkjson 'RM -rf ~' "$TREE")" "PATH=$WORK/farm-notr"
env_row "case fold: a PATH with no tr still asks on TERRAFORM destroy" ask "$(mkjson 'TERRAFORM destroy' "$TREE")" "PATH=$WORK/farm-notr"
env_row "case fold: a PATH with no tr still asks on Git push --force origin main" ask "$(mkjson 'Git push --force origin main' "$R3")" "PATH=$WORK/farm-notr"
env_row "case fold: a PATH with no tr still unwraps Sudo and Env (Sudo Env Terraform destroy)" ask "$(mkjson 'Sudo Env Terraform destroy' "$TREE")" "PATH=$WORK/farm-notr"
env_row "case fold: Doas / NOHUP / Timeout / Nice / Time / Command wrappers with an upper-case name are unwrapped" ask "$(mkjson 'DOAS NOHUP Timeout 5 NICE TIME Command Tofu destroy' "$TREE")" "PATH=$WORK/farm-notr"
env_row "case fold: only the command name is folded (Terraform DESTROY is not terraform destroy: nocasematch is restored)" none "$(mkjson 'Terraform DESTROY' "$TREE")"
env_row "case fold: an unrelated capitalised command (Make with a quoted word, a lexed command) is still no decision" none "$(mkjson 'Make "clean"' "$TREE")" "PATH=$WORK/farm-notr"
# The deadline branches: a private copy of the hook whose deadline is 0 s asks with the bound reason at the FIRST check it
# reaches. There is one check per phase (reading the lexer output, judging the records, deciding one command, walking
# the targets of one rm), so each row neuters the OTHER three in its copy: a row that stays green with its own check
# removed would be covered by a later one.
hook_edit() { # hook_edit <file> <literal anchor> <replacement>: the anchor must occur exactly once; HE_OK turns bad if not
  [[ -n "$FAST" ]] && return 0
  "$PY_BIN" -I -c 'import sys
p, a, r = sys.argv[1:4]
s = open(p).read()
if s.count(a) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(a, r))' "$1" "$2" "$3" 2>/dev/null || HE_OK=bad
}
_DL_READ='if (( SECONDS >= DEADLINE_S )); then BOUND_SOFT="the ${DEADLINE_S} s time limit was reached while reading the lexer output"; BOUND_READ=1; break; fi'
_DL_JUDGE='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the commands"; break; fi'
_DL_DECIDE='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking a command"; return 0; fi'
_DL_RM='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the targets of rm"; return 0; fi'
deadline_row() { # deadline_row <phase> <command> <anchor to neuter>...
  local phase="$1" cmd="$2"; shift 2
  mk_hook_tree "deadline-$phase"; HE_OK=ok
  hook_edit "$HT_HOOK" $'\nDEADLINE_S=6\n' $'\nDEADLINE_S=0\n'
  while [[ $# -gt 0 ]]; do hook_edit "$HT_HOOK" "$1" ':'; shift; done
  chk "bound: deadline ($phase): the edits landed in the private hook copy" "$HE_OK"
  tree_row "bound: deadline ($phase): a hook whose time is up asks instead of finishing" ask "$HT_HOOK" "$(mkjson "$cmd" "$TREE")"
  jqchk "bound: deadline ($phase): the ask carries the bound rule id and says the command was not run" '.hookSpecificOutput.permissionDecisionReason | test("^The guard paused this command and is asking you\\. It has not run yet and runs only if you approve\\. bound: ")'
}
deadline_row reading 'ls "x"; terraform plan' "$_DL_JUDGE" "$_DL_DECIDE" "$_DL_RM"
deadline_row judging 'ls "x"; terraform plan' "$_DL_READ" "$_DL_DECIDE" "$_DL_RM"
deadline_row deciding 'ls "x"; terraform plan' "$_DL_READ" "$_DL_JUDGE" "$_DL_RM"
deadline_row rm-targets 'rm -rf "build"' "$_DL_READ" "$_DL_JUDGE" "$_DL_DECIDE"
# git has four loops (its global options, the flags of push, its refs, its destinations), each with its own clock check: each row keeps ONE of them
_DL_GO='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the options of git"; return 0; fi'
_DL_GF='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the flags of git push"; return 0; fi'
_DL_GR='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the refs of git push"; return 0; fi'
_DL_GD='if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the destinations of git push"; return 0; fi'
deadline_row git-options 'git push -f origin feat "x"' "$_DL_READ" "$_DL_JUDGE" "$_DL_DECIDE" "$_DL_RM" "$_DL_GF" "$_DL_GR" "$_DL_GD"
deadline_row git-flags 'git push -f origin feat "x"' "$_DL_READ" "$_DL_JUDGE" "$_DL_DECIDE" "$_DL_RM" "$_DL_GO" "$_DL_GR" "$_DL_GD"
deadline_row git-refs 'git push -f origin feat "x"' "$_DL_READ" "$_DL_JUDGE" "$_DL_DECIDE" "$_DL_RM" "$_DL_GO" "$_DL_GF" "$_DL_GD"
deadline_row git-dests 'git push -f origin feat "x"' "$_DL_READ" "$_DL_JUDGE" "$_DL_DECIDE" "$_DL_RM" "$_DL_GO" "$_DL_GF" "$_DL_GR"
# and a very wide push is decided in time (the real clock): 15000 refs, a force push to main last, and the same without force
_t=""; for _i in $(seq 1 15000); do _t+=" r$_i"; done; _cmdgit15k="git push -f origin${_t} main"; _cmdgit15kp="git push origin${_t}"
bound_row "bound: git push -f with 15000 refs ending in main is decided (ask) in under 5 s" ask @R1@ "$_cmdgit15k"
bound_row "bound: git push (no force) with 15000 refs is decided (no decision) in under 5 s" none @R1@ "$_cmdgit15kp"

# =====================================================================================================
echo "== a secret in the matched command is redacted from the reason and the systemMessage =="
redact_row() { # <label> <command> <cwd-template> <secret that must be absent> <quoted text that must be present>
  want_row_quiet "$1" || return 0
  subst "$3"; hook_run "$(mkjson "$2" "$SUBST_OUT")"
  jqchk "$1: the secret is absent from the reason and the systemMessage" '[.hookSpecificOutput.permissionDecisionReason, (.systemMessage // "")] | all(contains($s) | not)' --arg s "$4"
  jqchk "$1: the rest of the command is still quoted" '.hookSpecificOutput.permissionDecisionReason | contains($q)' --arg q "$5"
}
redact_row "redact: -var name=value with a password name" 'terraform destroy -var db_password=zq-fake-pw-1 -var region=us-east-1' - zq-fake-pw-1 'terraform destroy -var db_password=<redacted> -var region=us-east-1'
redact_row "redact: an assignment prefix with a SECRET name" 'AWS_SECRET_ACCESS_KEY=zq-fake-key-2 terraform destroy' - zq-fake-key-2 'AWS_SECRET_ACCESS_KEY=<redacted> terraform destroy'
redact_row "redact: --name=value with a token name" 'terraform destroy --api-token=zq-fake-tok-3' - zq-fake-tok-3 'terraform destroy --api-token=<redacted>'
redact_row "redact: URL userinfo with a password" 'git push --force https://someone:zq-fake-pat-4@example.invalid/o/r.git main' @R1@ zq-fake-pat-4 'https://someone:<redacted>@example.invalid/o/r.git main'
redact_row "redact: URL userinfo with no colon is the credential" 'git push --force https://zq-fake-user-5@example.invalid/o/r.git main' @R1@ zq-fake-user-5 'https://<redacted>@example.invalid/o/r.git main'
redact_row "redact: a value with spaces is redacted whole" "DB_PASSWD='zq fake pw 6 two' terraform destroy" - 'pw 6 two' 'DB_PASSWD=<redacted> terraform destroy'
redact_row "redact: a deny carries no secret in systemMessage either" 'API_AUTH=zq-fake-auth-7 rm -rf ~' - zq-fake-auth-7 'API_AUTH=<redacted> rm -rf ~'
redact_row "redact: a name with CRED in lower case" 'cloud_cred=zq-fake-cred-8 terraform destroy' - zq-fake-cred-8 'cloud_cred=<redacted> terraform destroy'
redact_row "redact: a nested -var=name=value spelling" 'terraform destroy -var=db_secret=zq-fake-sec-9' - zq-fake-sec-9 'terraform destroy -var=db_secret=<redacted>'
redact_row "redact: an API_KEY assignment (the key name alone)" 'API_KEY=zq-fake-key-11 terraform destroy' - zq-fake-key-11 'API_KEY=<redacted> terraform destroy'
redact_row "redact: a pass name (-var db_pass=)" 'terraform destroy -var db_pass=zq-fake-pass-12 -var region=us-east-1' - zq-fake-pass-12 'terraform destroy -var db_pass=<redacted> -var region=us-east-1'
redact_row "redact: a pwd name" 'DB_PWD=zq-fake-pwd-13 terraform destroy' - zq-fake-pwd-13 'DB_PWD=<redacted> terraform destroy'
redact_row "redact: a pw name (-var pw=)" 'terraform destroy -var pw=zq-fake-pw-14 -target=module.x' - zq-fake-pw-14 'terraform destroy -var pw=<redacted> -target=module.x'
redact_row "redact: a tok name (-var tok=)" 'terraform destroy -var tok=zq-fake-tok-15 -target=module.x' - zq-fake-tok-15 'terraform destroy -var tok=<redacted> -target=module.x'
redact_row "redact: a bearer name (-var bearer=)" 'terraform destroy -var bearer=zq-fake-bearer-16 -target=module.x' - zq-fake-bearer-16 'terraform destroy -var bearer=<redacted> -target=module.x'
for _f in token password passwd secret api-key auth bearer; do
  redact_row "redact: --$_f takes its value from the NEXT word" "terraform destroy --$_f zq-fake-next-$_f -target=module.x" - "zq-fake-next-$_f" "terraform destroy --$_f <redacted> -target=module.x"
done
redact_row "redact: a credential flag followed by another flag masks nothing (--password --target module.x)" 'terraform destroy --password --target module.x' - 'zq-no-secret-in-this-row' 'terraform destroy --password --target module.x'
redact_row "redact: a credential flag at the end of one command does not mask the first word of the next (state resets per command)" 'terraform destroy --token ; rm -rf ~' - 'zq-no-secret-in-this-row' 'Matched command: [rm -rf ~]'
redact_row "redact: a header word (Authorization: Bearer value) is masked after the colon" "terraform destroy -H 'Authorization: Bearer zq-fake-hdr-17' -target=module.x" - zq-fake-hdr-17 'terraform destroy -H Authorization: <redacted> -target=module.x'
redact_row "redact: git -c http.extraheader=Authorization: Basic value is masked after the colon" 'git -c "http.extraheader=Authorization: Basic zq-fake-basic-18" push --force origin main' @R1@ zq-fake-basic-18 'git -c http.extraheader=Authorization: <redacted> push --force origin main'
redact_row "redact: a Bearer value inside a word without a colon is masked" "terraform destroy -var 'hdr=Bearer zq-fake-bearer-19' -target=module.x" - zq-fake-bearer-19 'terraform destroy -var hdr=Bearer <redacted> -target=module.x'
redact_row "redact: URL userinfo whose password contains a slash" 'git push --force https://someone:zq/fake/pat-20@example.invalid/o/r.git main' @R1@ 'zq/fake/pat-20' 'https://someone:<redacted>@example.invalid/o/r.git main'
redact_row "redact: URL userinfo whose password contains an at sign" 'git push --force https://someone:zq-fake@pat-21@example.invalid/o/r.git main' @R1@ 'pat-21' 'https://someone:<redacted>@example.invalid/o/r.git main'
redact_row "redact: retention, names with no credential word keep their values (WORKSPACE, PLAN_FILE, -var region)" 'WORKSPACE=prod PLAN_FILE=x.tfplan terraform destroy -var region=us-east-1' - 'zq-no-secret-in-this-row' 'WORKSPACE=prod PLAN_FILE=x.tfplan terraform destroy -var region=us-east-1'
redact_row "redact: retention, a value-taking flag that is not a credential flag keeps the next word (--target)" 'terraform destroy --target module.db --var-file prod.tfvars' - 'zq-no-secret-in-this-row' 'terraform destroy --target module.db --var-file prod.tfvars'
# the perl-less scan quotes raw text words: a leading quote must not hide the name, and a quoted value with spaces goes whole
redact_np() { # <label> <command> <secret that must be absent> <quoted text that must be present>
  want_row_quiet "$1" || return 0
  hook_run "$(mkjson "$2" "$TREE")" "PATH=$WORK/farm-noperl"
  jqchk "$1: the secret is absent from the reason" '.hookSpecificOutput.permissionDecisionReason | contains($s) | not' --arg s "$3"
  jqchk "$1: the rest of the segment is still quoted" '.hookSpecificOutput.permissionDecisionReason | contains($q)' --arg q "$4"
}
redact_np "redact (perl-less): a single-quoted -var name=value" "terraform destroy -var 'db_password=zq-fake-pw-22' -var region=us-east-1" zq-fake-pw-22 "db_password=<redacted> -var region=us-east-1"
redact_np "redact (perl-less): a double-quoted name=value" 'terraform destroy -var "db_secret=zq-fake-sec-23" -var region=us-east-1' zq-fake-sec-23 "db_secret=<redacted> -var region=us-east-1"
redact_np "redact (perl-less): a quoted value with spaces goes whole" "terraform destroy -var 'db_password=zq fake pw 24 two' -var region=us-east-1" "pw 24 two" "db_password=<redacted> -var region=us-east-1"
redact_np "redact (perl-less): --token takes the next word" "terraform destroy --token zq-fake-tok-25 -var region=us-east-1" zq-fake-tok-25 "--token <redacted> -var region=us-east-1"
want_row_quiet "redact: a non-secret assignment is quoted as is" && { hook_run "$(mkjson 'REGION=us-east-1 terraform destroy' "$TREE")"; reason_has "redact: a non-secret assignment is quoted as is" 'REGION=us-east-1 terraform destroy'; }
if want_row_quiet "redact: the perl-less scan quotes a segment with its secret redacted"; then
  hook_run "$(mkjson 'terraform destroy -var db_password=zq-fake-pw-10' "$TREE")" "PATH=$WORK/farm-noperl"
  jqchk "redact: the perl-less scan quotes a segment with its secret redacted" '(.hookSpecificOutput.permissionDecisionReason | contains("zq-fake-pw-10") | not) and (.hookSpecificOutput.permissionDecisionReason | contains("db_password=<redacted>"))'
fi

# =====================================================================================================
echo "== the reasons: every one says the command was NOT run; parse-class asks get their own tail =="
hook_run "$(mkjson "echo 'PARSEMARKER_zq unbalanced" "$TREE")"
jqchk "reason: a parse failure starts with the not-run sentence" '.hookSpecificOutput.permissionDecisionReason | startswith("The guard paused this command and is asking you. It has not run yet and runs only if you approve. command-not-parsed: ")'
jqchk "reason: a parse failure tells the agent to fix and resend, not to leave the command alone" '.hookSpecificOutput.permissionDecisionReason | (test("send it again") and test("report the task as blocked"))'
jqchk "reason: a parse failure does not say do not retry or do not rephrase" '.hookSpecificOutput.permissionDecisionReason | (test("(?i)do not retry") or test("(?i)do not rephrase")) | not'
hook_run 'not json {'
jqchk "reason: an unreadable envelope starts with the not-run sentence and its rule id" '.hookSpecificOutput.permissionDecisionReason | startswith("The guard paused this command and is asking you. It has not run yet and runs only if you approve. envelope-unreadable: ")'
jqchk "reason: an unreadable envelope says the fault is in the tool call (no fix-the-quoting tail) and carries the escape hatch and the issues URL" '.hookSpecificOutput.permissionDecisionReason | (test("fault in the tool call") and (test("fix its quoting") | not) and (test("send it again") | not) and contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues"))'
hook_run "$(mkjson "$_cmd2600" "$TREE")"
jqchk "reason: a bound ask tells the agent to split the command" '.hookSpecificOutput.permissionDecisionReason | (test("Split it into smaller commands") and contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues"))'
hook_run "$(mkjson 'terraform destroy' "$TREE")"
jqchk "reason: a destroy ask starts with the not-run sentence" '.hookSpecificOutput.permissionDecisionReason | startswith("The guard paused this command and is asking you. It has not run yet and runs only if you approve. infra-destroy: ")'
hook_run "$(mkjson 'rm -rf ~' "$TREE")"
jqchk "reason: a deny starts with the not-run sentence in the reason and in the systemMessage" '(.hookSpecificOutput.permissionDecisionReason | startswith("This command was NOT run. ")) and (.systemMessage | startswith("This command was NOT run. "))'
jqchk "reason: a deny's systemMessage keeps the escape hatch and the issues URL" '.systemMessage | (contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues"))'

# =====================================================================================================
echo "== an ask speaks to the person first; the agent's instructions follow under their own label =="
hook_run "$(mkjson 'terraform destroy' "$TREE")"
jqchk "ask wording: the reason opens with the sentence for the person (paused, not run yet, runs only on approval)" '.hookSpecificOutput.permissionDecisionReason | startswith($lead + " ")' --arg lead "$ASK_LEAD"
jqchk "ask wording: the agent's part is labelled and opens with the not-run sentence" '.hookSpecificOutput.permissionDecisionReason | contains(" If you are the agent: This command was NOT run. Stop and tell the person")'
jqchk "ask wording: the rule id and the quoted command come BEFORE the agent's label" '.hookSpecificOutput.permissionDecisionReason | (index("infra-destroy: ") < index("If you are the agent:")) and (index("Matched command: [terraform destroy]") < index("If you are the agent:"))'
jqchk "ask wording: the escape hatch and the issues URL still ride the ask" '.hookSpecificOutput.permissionDecisionReason | (contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues"))'
hook_run "$(mkjson 'rm -rf ~' "$TREE")"
jqchk "deny wording: a deny is not addressed to a person who can approve (no paused/asking sentence, no agent label)" '.hookSpecificOutput.permissionDecisionReason | (contains("is asking you") | not) and (contains("If you are the agent") | not) and startswith("This command was NOT run. recursive-delete-home: ")'
# the tail follows the cause: only a quoting problem is fixed by fixing the quoting
hook_run "$(mkjson "echo 'PARSEMARKER_zq unbalanced" "$TREE")"
jqchk "tail by cause: a lexer parse failure (unbalanced quote) tells the agent to fix the quoting and resend" '.hookSpecificOutput.permissionDecisionReason | (test("fix its quoting or heredoc") and test("send it again"))'
_deep20='x'; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do _deep20="echo \$($_deep20)"; done
hook_run "$(mkjson "$_deep20" "$TREE")"
jqchk "tail by cause: a nesting-depth failure tells the agent to simplify or split, not to fix the quoting" '.hookSpecificOutput.permissionDecisionReason | (test("command-not-parsed: ") and test("lexer depth") and test("Split it into smaller commands") and (test("fix its quoting") | not))'
hook_run 'not json {'
jqchk "tail by cause: an unreadable envelope is a harness fault: stop and report, no rewrite advice" '.hookSpecificOutput.permissionDecisionReason | (test("fault in the tool call") and test("stop and tell the person") and (test("fix its quoting") | not))'
hook_run "$(mkjson "env -S 'rm -rf /'" "$TREE")"
jqchk "tail by cause: env -S asks the agent to write the command out so it can be checked, not to leave it alone" '.hookSpecificOutput.permissionDecisionReason | (test("unparsed-wrapper: ") and test("write it out without env -S") and (test("(?i)do not rephrase") | not))'
hook_run "$(mkjson 'sudo sudo sudo sudo sudo sudo sudo sudo sudo ls "x"' "$TREE")"
jqchk "tail by cause: too many wrappers asks the agent to use fewer, not to leave it alone" '.hookSpecificOutput.permissionDecisionReason | (test("wrapper-depth: ") and test("fewer nested wrappers") and (test("(?i)do not rephrase") | not))'
hook_run "$(mkjson 'terraform destroy' "$TREE")"
jqchk "tail by cause: a destroy still says do not retry and do not rephrase" '.hookSpecificOutput.permissionDecisionReason | (test("(?i)do not retry") and test("(?i)do not rephrase"))'

# =====================================================================================================
echo "== the lexer seam: a lexer that fails, lies or says nothing never becomes an allow =="
# A private hook copy whose lib/shell-argv.pl is a stub. The command has a quote so the prefilter does not skip it.
stub_lexer() { # stub_lexer <name> <perl source> -> HT_HOOK
  mk_hook_tree "lexer-$1"
  [[ -n "$FAST" ]] && return 0
  assert_fixture_dir "$WORK"
  printf '%s\n' "$2" > "$WORK/trees/lexer-$1/lib/shell-argv.pl"
}
_LX_ENV="$(mkjson 'ls "x"' "$TREE")"
_LX_RM_ENV="$(mkjson 'rm -rf ~' "$TREE")"
stub_lexer die 'exit 255;'
tree_row "lexer seam: a lexer that dies (exit 255, no output) asks" ask "$HT_HOOK" "$_LX_ENV"
reason_has "lexer seam: a dead lexer reads as no result" 'the lexer produced no result'
stub_lexer silent '# prints nothing and exits 0'
tree_row "lexer seam: a lexer that prints nothing asks" ask "$HT_HOOK" "$_LX_ENV"
stub_lexer alarm 'print "E\0alarm\0"; exit 3;'
tree_row "lexer seam: E alarm asks" ask "$HT_HOOK" "$_LX_ENV"
reason_has "lexer seam: E alarm names the cause" 'lexer alarm'
jqchk "lexer seam: E alarm gets the simplify-or-split tail, not the fix-the-quoting one" '.hookSpecificOutput.permissionDecisionReason | (test("Split it into smaller commands") and (test("fix its quoting") | not))'
stub_lexer crash 'print "E\0crash\0"; exit 3;'
tree_row "lexer seam: E crash asks" ask "$HT_HOOK" "$_LX_ENV"
reason_has "lexer seam: E crash names the cause" 'lexer crash'
jqchk "lexer seam: E crash gets the simplify-or-split tail, not the fix-the-quoting one" '.hookSpecificOutput.permissionDecisionReason | (test("Split it into smaller commands") and (test("fix its quoting") | not))'
stub_lexer garbage 'print "XYZ\0QQ\0";'
tree_row "lexer seam: garbage bytes with no OK ask" ask "$HT_HOOK" "$_LX_ENV"
stub_lexer garbageok 'print "XYZ\0OK\0";'
tree_row "lexer seam: a garbage frame before OK asks (malformed)" ask "$HT_HOOK" "$_LX_ENV"
reason_has "lexer seam: a garbage frame is reported as malformed" 'the lexer output was malformed'
stub_lexer badargc 'print "C\0top\0abc\0OK\0";'
tree_row "lexer seam: a record with a non-numeric word count asks (malformed)" ask "$HT_HOOK" "$_LX_ENV"
stub_lexer truncated 'print "C\0top\0";'
tree_row "lexer seam: a record cut off before its words and OK asks" ask "$HT_HOOK" "$_LX_ENV"
stub_lexer okonly 'print "OK\0";'
tree_row "lexer seam: OK with no record for a command that mentions rm asks (lexer-empty)" ask "$HT_HOOK" "$_LX_RM_ENV"
reason_has "lexer seam: OK with no record carries the lexer-empty rule id and the fix-and-resend tail" "$ASK_LEAD lexer-empty: "
tree_row "lexer seam: OK with no record for a keyword-free command (ls) is not an ask" none "$HT_HOOK" "$_LX_ENV"
tree_row "lexer seam: OK with no record for a comment-only command is not an ask" none "$HT_HOOK" "$(mkjson '# a "comment" only' "$TREE")"
stub_lexer okone 'print "C\0top\0" . "1\0" . "-\0" . "ls\0" . "OK\0";'
# A lexer that silently drops a command must not turn quoting into an allow: with quotes, escapes and $ removed the line is read again,
# so each spelling below (a stub lexer that returns OK and no record stands for the defective lexer) asks, and a plain-variable path does not.
stub_lexer okonly2 'print "OK\0";'
tree_row "lexer-empty (stub): r\"\"m -rf ~ (quotes split the word) asks" ask "$HT_HOOK" "$(mkjson 'r""m -rf ~' "$TREE")"
tree_row "lexer-empty (stub): 'r'm -rf / asks" ask "$HT_HOOK" "$(mkjson "'r'm -rf /" "$TREE")"
tree_row "lexer-empty (stub): a quoted # is not a comment: echo \"a #b\"; rm -rf ~ asks" ask "$HT_HOOK" "$(mkjson 'echo "a #b"; rm -rf ~' "$TREE")"
tree_row "lexer-empty (stub): ev\"\"al x asks" ask "$HT_HOOK" "$(mkjson 'ev""al x' "$TREE")"
tree_row "lexer-empty (stub): a backslash inside the word (r\\m -rf ~) asks" ask "$HT_HOOK" "$(mkjson 'r\m -rf ~' "$TREE")"
tree_row "lexer-empty (stub): an ANSI-C quoted word ($'r''m' -rf ~) asks" ask "$HT_HOOK" "$(mkjson "\$'r''m' -rf ~" "$TREE")"
tree_row "lexer-empty (stub): a \$ that is not a plain variable name joins the word (\${IFS}rm -rf ~) and asks" ask "$HT_HOOK" "$(mkjson '${IFS}rm -rf ~' "$TREE")"
tree_row "lexer-empty (stub): upper case behind a quote (T\"\"ERRAFORM destroy) asks" ask "$HT_HOOK" "$(mkjson 'T""ERRAFORM destroy' "$TREE")"
tree_row "lexer-empty (stub): a whole-word keyword with no quote at all (rm -rf ~, comment text before it) asks" ask "$HT_HOOK" "$(mkjson '# note'$'\n''rm -rf ~' "$TREE")"
tree_row "lexer-empty (stub): a keyword only inside a full-line comment is not an ask" none "$HT_HOOK" "$(mkjson '  # rm -rf ~'$'\n''>"out.txt"' "$TREE")"
tree_row "lexer-empty (stub): a plain \$VAR path with a keyword in a directory name is not an ask" none "$HT_HOOK" "$(mkjson '> $HOME/.config/git/ignore' "$TREE")"
tree_row "lexer-empty (stub): a keyword inside a longer word (platform.log, no quote) is not an ask" none "$HT_HOOK" "$(mkjson '> platform.log' "$TREE")"
tree_row "lexer-empty (stub): a quote with no keyword anywhere is not an ask" none "$HT_HOOK" "$(mkjson '>"out.txt"' "$TREE")"
tree_row "lexer seam: a stub lexer that reports one harmless record is not an ask (the seam is not an always-ask)" none "$HT_HOOK" "$_LX_ENV"
# A read-time bound (the deadline reached while the lexer's output is still arriving) must not discard the records already read:
# the rule table judges them, a deny wins, and only when nothing matched does the answer become a bound ask. The private copy has a
# 2 s deadline and its stub lexer stops for 2.1 s mid-output (whole-second SECONDS: the deadline is crossed after 1 to 2 s).
# Stubs print C records "C\0top\0<argc>\0" then <flag>\0<word>\0 per word.
slow_lexer() { # slow_lexer <name> <perl source>: a stub lexer under a 2 s deadline
  stub_lexer "$1" "\$| = 1; sub nap { select(undef, undef, undef, 2.1); } $2"
  HE_OK=ok; hook_edit "$HT_HOOK" $'\nDEADLINE_S=6\n' $'\nDEADLINE_S=2\n'
  chk "read bound: the 2 s deadline edit landed in the private copy ($1)" "$HE_OK"
}
_SL_RM='print "C\0top\0" . "3\0" . "-\0rm\0-\0-rf\0-\0/\0";'
slow_lexer slow-deny "$_SL_RM nap(); print \"C\\0top\\0\" . \"1\\0\" . \"-\\0echo\\0\" . \"OK\\0\";"
tree_row "read bound: rm -rf / read before the deadline passed still denies (the records read are judged)" deny "$HT_HOOK" "$_LX_ENV"
slow_lexer slow-none 'print "C\0top\0" . "1\0" . "-\0ls\0"; nap(); print "C\0top\0" . "1\0" . "-\0echo\0" . "OK\0";'
tree_row "read bound: nothing matched before the deadline passed asks with the bound reason" ask "$HT_HOOK" "$_LX_ENV"
reason_has "read bound: the ask names the time limit and the bound rule id" "$ASK_LEAD bound: "
# one huge record: a frame-count check inside the read loop bounds it. 2046 complete words (the trip lands on a flag frame) are judged.
slow_lexer slow-rec-flag 'print "C\0top\0" . "2500\0" . "-\0rm\0-\0-rf\0-\0/\0" . ("-\0x\0" x 1497); nap(); print "-\0x\0" x 997; print "OK\0";'
tree_row "read bound: a single huge record cut mid-record (on a flag frame) still denies on the words read" deny "$HT_HOOK" "$_LX_ENV"
slow_lexer slow-rec-text 'print "C\0top\0" . "1\0" . "-\0ls\0"; print "C\0top\0" . "2500\0" . "-\0rm\0-\0-rf\0-\0/\0" . ("-\0x\0" x 1497); nap(); print "-\0x\0" x 997; print "OK\0";'
tree_row "read bound: a single huge record cut mid-record (on a text frame) still denies on the words read" deny "$HT_HOOK" "$_LX_ENV"
# a record cut before its first word is complete is dropped, not judged half-read (an unset word under set -u would abort the hook)
slow_lexer slow-rec-empty 'print(("C\0top\0" . "1\0" . "-\0ls\0") x 201); print "C\0top\0" . "6\0" . ("-\0e\0" x 6); print "C\0top\0" . "40\0"; nap(); print "-\0x\0" x 40; print "OK\0";'
tree_row "read bound: a record cut before its first word is complete is dropped (the earlier records are judged, the answer is a bound ask)" ask "$HT_HOOK" "$_LX_ENV"
reason_has "read bound: a dropped half record still ends in the bound reason" "$ASK_LEAD bound: "

# =====================================================================================================
echo "== the envelope (ADR-156/157): an unreadable envelope asks, a non-Bash tool is not decided =="
env_row "garbage stdin asks" ask 'not json at all {'
env_row "a truncated envelope asks (M2)" ask '{"tool_input":'
env_row "empty stdin asks (M2)" ask ''
env_row "an array command asks" ask '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","~"]}}'
env_row "an object command asks" ask '{"tool_name":"Bash","tool_input":{"command":{"a":1}}}'
env_row "a numeric command asks" ask '{"tool_name":"Bash","tool_input":{"command":42}}'
env_row "a null command asks" ask '{"tool_name":"Bash","tool_input":{"command":null}}'
env_row "a missing command asks" ask '{"tool_name":"Bash","tool_input":{}}'
env_row "a string tool_input asks" ask '{"tool_name":"Bash","tool_input":"terraform destroy"}'
env_row "a NUL byte in the command asks" ask '{"tool_name":"Bash","tool_input":{"command":"ls\u0000; terraform destroy"}}'
env_row "an envelope with no cwd still decides" ask '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}'
env_row "bypassPermissions does not change the decision" ask '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"},"permission_mode":"bypassPermissions","cwd":"/"}'
env_row "a subagent envelope (agent_id) still asks" ask '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"},"agent_id":"sub-1","cwd":"/"}'
env_row "a Write tool carrying terraform destroy is not decided (D1: Bash only)" none '{"tool_name":"Write","tool_input":{"file_path":"/x","content":"terraform destroy"}}'
env_row "Devin's exec is not decided (D2)" none '{"tool_name":"exec","tool_input":{"command":"rm -rf ~"}}'
env_row "the hook never evaluates the command (a command that would create a file)" ask "$(mkjson "touch $WORK/EVALUATED; terraform destroy" "$TREE")"
if [[ -z "$FAST" && "$GOT" == ask && ! -e "$WORK/EVALUATED" ]]; then _x=ok; else _x=bad; fi
if want_row_quiet "the hook never evaluates the command (a command that would create a file)"; then chk "the hook answered and did not execute the command text it was given (ADR-156)" "$_x"; fi
# a bound trip and a deep nesting are parse failures, never allows
_deep='x'; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do _deep="echo \$($_deep)"; done
env_row "a substitution nested past the depth bound asks (a bound trip)" ask "$(mkjson "$_deep" "$TREE")"
# a 100 KB heredoc lexes within the bounds: no decision
_body="$(printf 'line %05d lorem ipsum dolor sit amet consectetur adipiscing\n' $(seq 1 1500))"
env_row "a ~90 KB heredoc lexes within the bounds: no decision (no budget false positive)" none "$(mkjson "cat ${_HD}EOF"$'\n'"$_body"$'\n'"EOF" "$TREE")"
# the prefilter reads the first "command" key; jq reads .tool_input.command: more than one "command" key in the envelope goes to jq
env_row "prefilter: a nested decoy command key before the real one is not skipped" deny '{"tool_name":"Bash","tool_input":{"x":{"command":"ls"},"command":"rm -rf ~"},"cwd":"/var/tmp"}'
env_row "prefilter: an array decoy command key before the real one is not skipped" deny '{"tool_name":"Bash","tool_input":{"x":[{"command":"ls"}],"command":"rm -rf ~"},"cwd":"/var/tmp"}'
env_row "prefilter: a top-level decoy command key before tool_input is not skipped" deny '{"command":"ls","tool_name":"Bash","tool_input":{"command":"rm -rf ~"},"cwd":"/var/tmp"}'
env_row "prefilter: a duplicate command key (jq reads the last) is not skipped" deny '{"tool_name":"Bash","tool_input":{"command":"ls","command":"rm -rf ~"},"cwd":"/var/tmp"}'
env_row "prefilter: a duplicate command key spelled with a \u escape (jq reads the last) is not skipped" deny '{"tool_name":"Bash","tool_input":{"command":"ls","\u0063ommand":"rm -rf ~"},"cwd":"/var/tmp"}'
env_row "prefilter: a command key spelled with a \u escape only is not skipped" deny '{"tool_name":"Bash","tool_input":{"\u0063ommand":"rm -rf ~"},"cwd":"/var/tmp"}'
env_row "prefilter: a \u escape after the command (destroy behind an escaped duplicate) is not skipped" ask '{"tool_name":"Bash","tool_input":{"command":"ls","comman\u0064":"terraform destroy"}}'
env_row "prefilter: a \u escape elsewhere in a benign envelope is decided by jq and allowed" none '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/var/tmp/caf\u00e9"}'
env_row "prefilter: a destroy hidden behind a decoy command key is not skipped" ask '{"tool_name":"Bash","tool_input":{"y":{"command":"ls"},"command":"terraform destroy"}}'
env_row "prefilter: the text command as a value is not a second key (still decided by jq, no decision for ls)" none '{"tool_name":"Bash","description":"command","tool_input":{"command":"ls"}}'
env_row "prefilter: one command key and no keyword is skipped without jq or perl (no notice on stderr)" none '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/var/tmp"}' "PATH=$WORK/farm-none"
if [[ -z "$HOOK_ERR" ]]; then _x=ok; else _x=bad; fi
if want_row_quiet "prefilter: one command key and no keyword is skipped without jq or perl (no notice on stderr)"; then chk "prefilter: that skip printed nothing on stderr (no spawn, no probe)" "$_x" "stderr: ${HOOK_ERR:0:120}"; fi
env_row "a ~90 KB heredoc followed by a real destroy asks" ask "$(mkjson "cat ${_HD}EOF"$'\n'"$_body"$'\n'"EOF"$'\n'"terraform destroy" "$TREE")"

env_row "a JSON array envelope asks (valid JSON that is not an object)" ask '[]'
env_row "a JSON string envelope asks" ask '"x"'
env_row "a JSON number envelope asks" ask '42'
env_row "an envelope with no tool_name is read as Bash (fail toward deciding): terraform destroy asks" ask '{"tool_input":{"command":"terraform destroy"}}'
env_row "an envelope with no cwd uses CLAUDE_PROJECT_DIR (rm -rf .. from a project subdirectory asks for the working directory)" ask '{"tool_name":"Bash","tool_input":{"command":"rm -rf .."}}' "CLAUDE_PROJECT_DIR=$TREE/sub"
# An inherited GIT_DIR must not redirect the hook's own git calls: hook_run strips GIT_* before it starts the hook, so these two rows
# hand GIT_DIR THROUGH (an assignment after the -u list reaches the hook). Repo r1 is on a feature branch, r3 is on main.
env_row "GIT_DIR leak: cwd on a feature branch, GIT_DIR naming a repo on main: git push --force is not decided" none "$(mkjson 'git push --force' "$R1")" "GIT_DIR=$R3/.git"
env_row "GIT_DIR leak (mirror): cwd on main, GIT_DIR naming a repo on a feature branch: git push --force still asks" ask "$(mkjson 'git push --force' "$R3")" "GIT_DIR=$R1/.git"
env_row "GIT_DIR leak (control): the same two pushes with no GIT_DIR decide as before (feature: none)" none "$(mkjson 'git push --force' "$R1")"
env_row "GIT_DIR leak (control): the same two pushes with no GIT_DIR decide as before (main: ask)" ask "$(mkjson 'git push --force' "$R3")"

echo "== the kill switch (D5, Guard 1 M6/row 20) =="
_destroy="$(mkjson 'terraform destroy' "$TREE")"
_rmhome="$(mkjson 'rm -rf ~' "$TREE")"
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently on a destroy" none "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently on a delete of home" none "$_rmhome" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently on garbage stdin (first statement)" none 'not json' SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently with no jq and no perl on PATH" none "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 "PATH=$WORK/farm-none"
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=0 keeps the guard on" ask "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=0
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=0 still denies a delete of home" deny "$_rmhome" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=0
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD empty keeps the guard on" ask "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=true keeps the guard on (only 1 disables)" ask "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=true
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=yes keeps the guard on" ask "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=yes
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=01 keeps the guard on" ask "$_destroy" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=01
env_row "SOLEUR_DISABLE_DESTRUCTIVE_GUARD=' 1' keeps the guard on" ask "$_destroy" "SOLEUR_DISABLE_DESTRUCTIVE_GUARD= 1"
# the switch is read from the harness environment only: a settings file or a .env that sets it is not read
mkdir -p "$WORK/decoy/.claude"
assert_fixture_dir "$WORK"
printf '{"env":{"SOLEUR_DISABLE_DESTRUCTIVE_GUARD":"1"}}\n' > "$WORK/decoy/.claude/settings.json"
printf 'SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1\n' > "$WORK/decoy/.env"
env_row "a project settings file that sets the switch is not read by the hook" ask "$(mkjson 'terraform destroy' "$WORK/decoy")" "CLAUDE_PROJECT_DIR=$WORK/decoy"
env_row "a .env that sets the switch is not read by the hook" ask "$(mkjson 'terraform destroy' "$WORK/decoy")"
# the hook process itself runs with $WORK as its working directory: a switch file placed THERE is the file a hook that read ./.env would find
printf 'SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1\n' > "$WORK/.env"
mkdir -p "$WORK/.claude"
printf '{"env":{"SOLEUR_DISABLE_DESTRUCTIVE_GUARD":"1"}}\n' > "$WORK/.claude/settings.json"
env_row "a .env in the hook's own working directory that sets the switch is not read by the hook" ask "$(mkjson 'terraform destroy' "$TREE")"
env_row "a .claude/settings.json in the hook's own working directory that sets the switch is not read by the hook" ask "$(mkjson 'terraform destroy' "$TREE")"

echo "== degraded paths (D6): a missing dependency scans the raw envelope, never allows silently =="
_ls="$(mkjson 'ls' "$TREE")"
_chain="$(mkjson 'rm -f jq; rm -rf ~' "$TREE")"
_nl="$(mkjson $'ls\nterraform destroy' "$TREE")"
_gp="$(mkjson 'git push --force origin main' "$TREE")"
_gok="$(mkjson 'git push origin feature' "$TREE")"
_rmok="$(mkjson 'rm -rf node_modules' "$TREE")"
# the farms themselves (so a farm that still carries the removed tool cannot make the rows pass for the wrong reason)
_farmchk() { env -i "PATH=$1" "$BASH" -c "command -v $2" >/dev/null 2>&1 && printf present || printf absent; }
if [[ -n "$FAST" ]]; then _a=absent; _b=present; _c=absent; _d=present; else
  _a="$(_farmchk "$WORK/farm-nojq" jq)"; _b="$(_farmchk "$WORK/farm-nojq" perl)"; _c="$(_farmchk "$WORK/farm-noperl" perl)"; _d="$(_farmchk "$WORK/farm-noperl" jq)"; fi
chk "canary: the jq-less PATH has no jq" "$(verdict_of absent "$_a")"
chk "canary: the jq-less PATH still has perl" "$(verdict_of present "$_b")"
chk "canary: the perl-less PATH has no perl" "$(verdict_of absent "$_c")"
chk "canary: the perl-less PATH still has jq" "$(verdict_of present "$_d")"
FJ="PATH=$WORK/farm-nojq"; FP="PATH=$WORK/farm-noperl"
env_row "jq-less: rm -f jq; rm -rf ~ asks (ADR-165: never an implicit allow)" ask "$_chain" "$FJ"
jqchk "jq-less: the hand-built output is a valid envelope with hookEventName" '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "ask"'
jqchk "jq-less: the reason names the missing tool" '.hookSpecificOutput.permissionDecisionReason | test("jq")'
if grep -qi 'jq' <<<"$HOOK_ERR"; then _x=ok; else _x=bad; fi
if want_row_quiet "jq-less: rm -f jq; rm -rf ~ asks (ADR-165: never an implicit allow)"; then chk "jq-less: stderr carries a notice naming jq" "$_x" "stderr: ${HOOK_ERR:0:200}"; fi
env_row "jq-less: terraform destroy asks" ask "$(mkjson 'terraform destroy' "$TREE")" "$FJ"
env_row "jq-less: a destroy after a JSON-escaped newline asks" ask "$_nl" "$FJ"
env_row "jq-less: a force push to main asks" ask "$_gp" "$FJ"
env_row "jq-less: ls exits 0 with no decision" none "$_ls" "$FJ"
env_row "jq-less: a push without force is not decided" none "$_gok" "$FJ"
env_row "jq-less: rm -rf node_modules is not decided" none "$_rmok" "$FJ"
env_row "jq-less: the kill switch is honoured" none "$_chain" "$FJ" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
env_row "perl-less: rm -rf ~ asks, never denies (a dependency failure never denies)" ask "$_rmhome" "$FP"
if grep -qi 'perl' <<<"$HOOK_ERR"; then _x=ok; else _x=bad; fi
if want_row_quiet "perl-less: rm -rf ~ asks, never denies (a dependency failure never denies)"; then chk "perl-less: stderr carries a notice naming perl" "$_x" "stderr: ${HOOK_ERR:0:200}"; fi
env_row "perl-less: terraform destroy asks (the decoded command is scanned)" ask "$(mkjson 'terraform destroy' "$TREE")" "$FP"
env_row "perl-less: a destroy after a decoded newline asks" ask "$_nl" "$FP"
env_row "perl-less: a force push to main asks" ask "$_gp" "$FP"
env_row "perl-less: ls exits 0 with no decision" none "$_ls" "$FP"
env_row "perl-less: a push without force is not decided" none "$_gok" "$FP"
env_row "perl-less: the kill switch is honoured" none "$_rmhome" "$FP" SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
env_row "a perl that exists but dies never turns a delete of home into an implicit allow" ask "$_rmhome" "PATH=$WORK/farm-badperl"
env_row "a perl that dies never turns a destroy into an implicit allow" ask "$(mkjson 'terraform destroy' "$TREE")" "PATH=$WORK/farm-badperl"
# every alternative of the raw-scan table has its own row (jq missing: the command is only a JSON string)
env_row "jq-less: terraform apply -destroy asks (the apply alternative)" ask "$(mkjson 'terraform apply -destroy' "$TREE")" "$FJ"
env_row "jq-less: git push origin +main asks (the +refspec alternative)" ask "$(mkjson 'git push origin +main' "$TREE")" "$FJ"
env_row "jq-less: rm -rf / asks (the root target alternative)" ask "$(mkjson 'rm -rf /' "$TREE")" "$FJ"
env_row "jq-less: rm --recursive ~ asks (the long flag alternative)" ask "$(mkjson 'rm --recursive ~' "$TREE")" "$FJ"
env_row "jq-less: rm -f ~ && echo -r is not decided (& separates the segments, so the -r belongs to echo)" none "$(mkjson 'rm -f ~ && echo -r' "$TREE")" "$FJ"

# The degraded scans are bounded too: a segment is capped at 64 KiB and the clock is read per segment (ask bound), the envelope is
# capped at 256 KiB before anything else runs, and the quoted segment is redacted only as far as the 200 characters that are shown.
_t=""; for _i in $(seq 1 8000); do _t+="terraform a "; done; _cmd96k_miss="${_t}; terraform destroy"; _cmd96k_hit="${_t}destroy"
_t=""; for _i in $(seq 1 5000); do _t+="terraform a "; done; _cmd60k_hit="${_t}destroy"
_t=""; for _i in $(seq 1 100000); do _t+="abcdefg "; done; _cmd800k="echo ${_t}"; _cmd200k="echo ${_t:0:200000}"
bound_row "degraded bound: jq-less, a 96 KB first segment then terraform destroy asks (bound) in under 5 s" ask - "$_cmd96k_miss" "^${ASK_LEAD_RX}bound: " "$FJ"
bound_row "degraded bound: perl-less, a 96 KB first segment then terraform destroy asks (bound) in under 5 s" ask - "$_cmd96k_miss" "^${ASK_LEAD_RX}bound: " "$FP"
bound_row "degraded bound: perl-less, a 60 KB segment that hits asks in under 5 s (the quoted segment is redacted only as far as it is shown)" ask - "$_cmd60k_hit" "^${ASK_LEAD_RX}guard-degraded-perl-missing: " "$FP"
bound_row "degraded bound: an 800 KB benign command asks (bound) in under 5 s, before the prefilter reads it" ask - "$_cmd800k" "^${ASK_LEAD_RX}bound: .*too large to check in full"
bound_row "degraded bound: an 800 KB command asks (bound) with no jq on the PATH as well" ask - "$_cmd800k" "^${ASK_LEAD_RX}bound: " "$FJ"
bound_row "degraded bound: a 200 KB benign command (under the envelope cap) is not an ask, in under 5 s" none - "$_cmd200k"
# the clock is read per segment: a private copy with a 1 s deadline scans 30000 short segments and stops with a bound ask
mk_hook_tree degraded-clock; HE_OK=ok
hook_edit "$HT_HOOK" $'\nDEADLINE_S=6\n' $'\nDEADLINE_S=1\n'
chk "degraded bound: the 1 s deadline edit landed in the private copy" "$HE_OK"
_t=""; for _i in $(seq 1 30000); do _t+="echo x;"; done; _cmd30kseg="${_t} rm -rf /"
tree_row "degraded bound: jq-less, a hook whose clock is nearly up stops scanning 30000 segments and asks" ask "$HT_HOOK" "$(mkjson "$_cmd30kseg" "$TREE")" "$FJ"
reason_has "degraded bound: jq-less, that ask is the bound ask, not the scan's hit" "$ASK_LEAD bound: "
tree_row "degraded bound: perl-less, a hook whose clock is nearly up stops scanning 30000 segments and asks" ask "$HT_HOOK" "$(mkjson "$_cmd30kseg" "$TREE")" "$FP"
reason_has "degraded bound: perl-less, that ask is the bound ask, not the scan's hit" "$ASK_LEAD bound: "
# When jq cannot build the decision output (the shim fails on -nc), a deny stays a deny and an ask stays an ask, the rule id survives, and
# a deny never says it is "asking instead of allowing".
JS="PATH=$WORK/shim-jqnc:$PATH"
env_row "output fallback: a deny stays a deny when jq cannot build the output" deny "$(mkjson 'rm -rf ~' "$TREE")" "$JS"
jqchk "output fallback: that deny keeps its rule id, the not-run sentence and the same text in the systemMessage" '(.hookSpecificOutput.permissionDecisionReason | startswith("This command was NOT run. recursive-delete-home: ")) and (.systemMessage == .hookSpecificOutput.permissionDecisionReason)'
env_row "output fallback: an ask stays an ask when jq cannot build the output" ask "$(mkjson 'terraform destroy' "$TREE")" "$JS"
jqchk "output fallback: that ask keeps its rule id, the person-facing sentence and the matched command" '.hookSpecificOutput.permissionDecisionReason | (startswith($lead + " infra-destroy: ") and contains("Matched command: [terraform destroy]"))' --arg lead "$ASK_LEAD"
env_row "output fallback: a deny whose quoted command holds a double quote stays a deny" deny "$(mkjson "rm -rf ~ 'x\"y'" "$TREE")" "$JS"
jqchk "output fallback: that deny names guard-output-fallback and the rule id, says it is blocked, and never says asking instead of allowing" '.hookSpecificOutput.permissionDecisionReason | (contains("guard-output-fallback") and contains("recursive-delete-home") and contains("blocked") and (contains("asking instead of allowing") | not) and startswith("This command was NOT run. "))'
jqchk "output fallback: that deny repeats the reason in the systemMessage and keeps the escape hatch and the issues URL" '.systemMessage == .hookSpecificOutput.permissionDecisionReason and (.systemMessage | (contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues")))'
env_row "output fallback: an ask whose quoted command holds a double quote stays an ask" ask "$(mkjson "terraform destroy 'x\"y'" "$TREE")" "$JS"
jqchk "output fallback: that ask names guard-output-fallback and the rule id and says it is asking instead of allowing" '.hookSpecificOutput.permissionDecisionReason | (contains("guard-output-fallback") and contains("infra-destroy") and contains("asking instead of allowing") and startswith($lead + " "))' --arg lead "$ASK_LEAD"
env_row "output fallback: a deny whose quoted command holds a backslash stays a deny" deny "$(mkjson "rm -rf ~ 'x\\y'" "$TREE")" "$JS"
env_row "output fallback: a deny whose quoted command holds a tab stays a deny with valid JSON" deny "$(mkjson "rm -rf ~ 'x"$'\t'"y'" "$TREE")" "$JS"
# A jq built without regex support: the envelope fields are read without a regex function, so every lexer-path call still decides.
JR="PATH=$WORK/shim-jqre:$PATH"
if [[ -n "$FAST" ]]; then _a=5; _b=0; _c=0; else
  _a=0; "$WORK/shim-jqre/jq" -n '"a" | test("a")' >/dev/null 2>&1 || _a=$?
  _b=0; "$WORK/shim-jqre/jq" -n '"a" | split("a") | join(" ")' >/dev/null 2>&1 || _b=$?
  _c=0; "$WORK/shim-jqre/jq" -n '"a" | gsub("a"; "b")' >/dev/null 2>&1 || _c=$?
fi
chk "regex-less jq: the shim rejects test() and gsub() (exit 5) and passes split/join (the rows below would pass vacuously otherwise)" "$([[ "$_a" == 5 && "$_c" == 5 && "$_b" == 0 ]] && printf ok || printf bad)" "test=$_a split=$_b gsub=$_c"
env_row "regex-less jq: a delete of home is still denied" deny "$(mkjson 'rm -rf ~' "$TREE")" "$JR"
env_row "regex-less jq: terraform destroy still asks as a destroy" ask "$(mkjson 'terraform destroy' "$TREE")" "$JR"
jqchk "regex-less jq: that ask is the destroy ask, not an unreadable-envelope ask" '.hookSpecificOutput.permissionDecisionReason | (contains("infra-destroy: ") and (contains("envelope-unreadable") | not))'
env_row "regex-less jq: an ordinary lexed command is no decision" none "$(mkjson 'git commit -m "x"' "$TREE")" "$JR"
env_row "regex-less jq: a newline in tool_name and cwd is still flattened (a Bash tool_name with a newline is not Bash)" none '{"tool_name":"Bash\nX","tool_input":{"command":"rm -rf ~"},"cwd":"/var/tmp\n/x"}' "$JR"
echo "== output shape (D4, Phase 3.4, CPO C4) =="
_TRUNC_ARGS="$(printf '%0400d' 0 | tr 0 a)"
hook_run "$(mkjson 'terraform destroy' "$TREE")"
jqchk "ask: hookEventName rides in the same object as the decision (M8)" '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "ask"'
jqchk "ask: the reason quotes the matched command" '.hookSpecificOutput.permissionDecisionReason | contains("terraform destroy")'
jqchk "ask: the reason starts with the person-facing sentence, then a rule id (<id>: <prose>)" '.hookSpecificOutput.permissionDecisionReason | test("^The guard paused this command and is asking you\\. It has not run yet and runs only if you approve\\. [a-z][a-z0-9]*(-[a-z0-9]+)+: ")'
jqchk "ask: the reason carries the escape hatch" '.hookSpecificOutput.permissionDecisionReason | contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1")'
jqchk "ask: the reason carries an issues URL" '.hookSpecificOutput.permissionDecisionReason | test("https://[^ ]+/issues")'
jqchk "ask: the reason tells the agent to stop and not retry, and names the person's own terminal" '.hookSpecificOutput.permissionDecisionReason | (test("(?i)do not retry") and test("(?i)blocked") and test("(?i)terminal"))'
jqchk "ask: the envelope has no top-level systemMessage (the prompt shows the reason)" 'keys == ["hookSpecificOutput"]'
_ID_ASK_TF="$(printf '%s' "$HOOK_OUT" | "$JQ_BIN" -r '.hookSpecificOutput.permissionDecisionReason | capture("^The guard paused this command and is asking you\\. It has not run yet and runs only if you approve\\. (?<id>[a-z][a-z0-9]*(-[a-z0-9]+)+): ").id' 2>/dev/null)"
hook_run "$(mkjson 'rm -rf ~' "$TREE")"
jqchk "deny: hookEventName rides in the same object as the decision (M8)" '.hookSpecificOutput.hookEventName == "PreToolUse" and .hookSpecificOutput.permissionDecision == "deny"'
jqchk "deny: a top-level systemMessage carries the SAME full reason (C4)" '.systemMessage == .hookSpecificOutput.permissionDecisionReason and (.systemMessage | length) > 0'
jqchk "deny: the systemMessage carries the escape hatch" '.systemMessage | contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1")'
jqchk "deny: the systemMessage carries an issues URL" '.systemMessage | test("https://[^ ]+/issues")'
jqchk "deny: the reason quotes the matched command" '.hookSpecificOutput.permissionDecisionReason | contains("rm -rf ~")'
jqchk "deny: the reason starts with the not-run sentence, then a rule id" '.hookSpecificOutput.permissionDecisionReason | test("^This command was NOT run\\. [a-z][a-z0-9]*(-[a-z0-9]+)+: ")'
jqchk "deny: the envelope has exactly the two top-level keys" 'keys == ["hookSpecificOutput","systemMessage"]'
_ID_DENY_RM="$(printf '%s' "$HOOK_OUT" | "$JQ_BIN" -r '.hookSpecificOutput.permissionDecisionReason | capture("^This command was NOT run\\. (?<id>[a-z][a-z0-9]*(-[a-z0-9]+)+): ").id' 2>/dev/null)"
hook_run "$(mkjson 'git push --force origin main' "$R1")"
_ID_ASK_GIT="$(printf '%s' "$HOOK_OUT" | "$JQ_BIN" -r '.hookSpecificOutput.permissionDecisionReason | capture("^The guard paused this command and is asking you\\. It has not run yet and runs only if you approve\\. (?<id>[a-z][a-z0-9]*(-[a-z0-9]+)+): ").id' 2>/dev/null)"
if [[ -n "$_ID_ASK_TF" && -n "$_ID_DENY_RM" && -n "$_ID_ASK_GIT" && "$_ID_ASK_TF" != "$_ID_DENY_RM" && "$_ID_ASK_TF" != "$_ID_ASK_GIT" && "$_ID_DENY_RM" != "$_ID_ASK_GIT" ]]; then _x=ok; else _x=bad; fi
chk "the destroy, delete-home and force-push rules carry three distinct rule ids" "$_x" "ids: tf=$_ID_ASK_TF rm=$_ID_DENY_RM git=$_ID_ASK_GIT"
hook_run "$(mkjson "terraform destroy -target=$_TRUNC_ARGS" "$TREE")"
_c200="terraform destroy -target=${_TRUNC_ARGS}"; _c200="${_c200:0:200}"; _c201="terraform destroy -target=${_TRUNC_ARGS}"; _c201="${_c201:0:201}"
jqchk "the quoted command is truncated at 200 characters (first 200 present)" '.hookSpecificOutput.permissionDecisionReason | contains($c)' --arg c "$_c200"
jqchk "the quoted command is truncated at 200 characters (the 201st is absent)" '.hookSpecificOutput.permissionDecisionReason | contains($c) | not' --arg c "$_c201"
hook_run "$(mkjson "echo 'PARSEMARKER_zq unbalanced" "$TREE")"
jqchk "a lexer failure asks" '.hookSpecificOutput.permissionDecision == "ask"'
jqchk "a lexer failure uses the distinct parse reason" '.hookSpecificOutput.permissionDecisionReason | (contains("could not parse this command") and contains("not recognised as destructive"))'
jqchk "a lexer failure never shows a command it did not match" '.hookSpecificOutput.permissionDecisionReason | contains("PARSEMARKER_zq") | not'
jqchk "a lexer failure still carries the escape hatch and an issues URL" '.hookSpecificOutput.permissionDecisionReason | (contains("SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1") and test("https://[^ ]+/issues"))'
hook_run "$(mkjson 'terraform plan' "$TREE")"
if [[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; then _x=ok; else _x=bad; fi
chk "no decision means no output and exit 0 (not an empty object)" "$_x" "out=${HOOK_OUT:0:80} rc=$HOOK_RC"

# =====================================================================================================
echo "== harness rows (Guard 1): the oracle and the floor can fail =="
# (b) the terraform stub records nothing -> the oracle expectation changes -> the shared comparison reddens.
oracle_derive 'terraform destroy' "$TREE" "$HOME_W"; _orc_normal="$ORC"
oracle_derive 'terraform destroy' "$TREE" "$HOME_W" "$STUB_BROKEN"; _orc_broken="$ORC"
if [[ -n "$FAST" ]]; then _orc_normal=ask; _orc_broken=none; fi
chk "harness (b): with a recording terraform stub the oracle expects ask" "$(verdict_of ask "$_orc_normal")"
chk "harness (b): with a terraform stub that records nothing the oracle expectation turns to none" "$(verdict_of none "$_orc_broken")"
chk "harness (b): that changed expectation reddens against a hook that answers ask" "$(verdict_of bad "$(verdict_of "$_orc_broken" ask)")"
chk "harness (b): the unchanged expectation stays green against a hook that answers ask" "$(verdict_of ok "$(verdict_of "$_orc_normal" ask)")"
# the oracle's plumbing is live: a recursive delete of home was recorded by the rm stub
oracle_derive 'rm -rf ~' "$TREE" "$HOME_W"
if [[ -n "$FAST" ]]; then _x=ok; elif [[ "$ORC" == deny && "$ORC_N" -ge 1 ]]; then _x=ok; else _x=bad; fi
chk "harness: the rm stub recorded the invocation and the rule table read it (oracle plumbing is live)" "$_x" "oracle=$ORC records=$ORC_N"
# The lint that keeps the oracle from running a destructive command can itself fail: every spelling below must be REFUSED (these
# are the shapes a two-space, tab, `then exec`, or absolute-redirect row would have slipped through), and the ordinary look-alikes accepted.
_lint_miss=""
for _s in 'command -p rm -rf ~' 'command  -p rm -rf ~' $'command\t-p rm -rf ~' 'command -pv rm' 'builtin command -p rm' 'env -i /bin/rm -rf ~' \
          'if true; then exec rm -rf ~; fi' 'true && exec rm -rf ~' 'ls; exec rm -rf ~' 'while true; do exec rm -rf ~; done' 'time exec rm -rf ~' \
          'export PATH=/usr/bin; rm -rf ~' 'PATH=/usr/bin rm -rf ~' 'hash -p /bin/rm rm; rm -rf ~' \
          'echo x > /etc/hosts' 'echo x >> /var/tmp/escape' 'echo x >| /var/tmp/escape' 'ls 2>/var/tmp/escape' 'ls &>/var/tmp/escape' \
          'cd / && rm -rf *' 'cd -P / && rm -rf *' 'ls; pushd /tmp && rm -rf *' 'then cd /tmp' '/bin/rm -rf ~' 'ls | /bin/rm -rf ~' '( /bin/rm -rf ~ )' 'FOO=1 /bin/rm'; do
  if safe_to_execute "$_s"; then _lint_miss+=" [${_s//$'\t'/<TAB>}]"; fi
done
if [[ -z "$_lint_miss" ]]; then _x=ok; else _x=bad; fi
chk "harness (lint): the executed-row lint refuses every unsafe spelling (a path reset, command -p in any spacing, exec in command position, an absolute redirect, a cd to an absolute path)" "$_x" "NOT refused:$_lint_miss"
_lint_bad=""
for _s in 'ls -la' 'aws-vault exec p -- terraform destroy' 'git push --exec x -f origin trunk' 'find src -name x -exec cat {} \;' 'echo "done" > /dev/null' 'ls &> /dev/null' 'pushd .. > /dev/null; rm -rf sub' \
          'echo x > @TREE@/out.log' 'cd @TREE@ && rm -rf ../../h/home' 'command -v rm' 'command -V rm -rf ~' 'echo exec rm' 'terraform apply -destroy' 'rm -rf $HOME/*' 'cd ~ && rm -rf ./*' 'echo "a > b"'; do
  safe_to_execute "$_s" || _lint_bad+=" [$_s]"
done
if [[ -z "$_lint_bad" ]]; then _x=ok; else _x=bad; fi
chk "harness (lint): the executed-row lint accepts the ordinary look-alikes (it is not an always-refuse)" "$_x" "wrongly refused:$_lint_bad"
# The wiring: an unsafe row in a COPY of the suite stops it (exit 2, named), and an oracle that disturbs its fixture world stops it (exit 2, named).
if [[ -z "${GUARD_META_COPY:-}" ]] && want_row "harness (lint): an unsafe row and a disturbed fixture world each stop the suite"; then
  assert_fixture_dir "$WORK"
  "$PY_BIN" -I -c 'import sys
src, dst, anchor, new = sys.argv[1:5]
s = open(src).read()
if s.count(anchor) != 1: sys.exit(1)
open(dst, "w").write(s.replace(anchor, new))' "$SELF" "$WORK/meta/unsafe.test.sh" "run_table 3 3${_HD}'ROWS'"$'\n' "run_table 3 3${_HD}'ROWS'"$'\n'"X @@ lint probe @@ none @@ - @@ command  -p rm -rf ~"$'\n' 2>/dev/null; _u_prep=$?
  _unsafe_out="$(env -u DCG_ROWS GUARD_REPO_ROOT="$REPO_ROOT" GUARD_FAST_COUNT=1 GUARD_META_COPY=1 "$BASH" "$WORK/meta/unsafe.test.sh" 2>&1 </dev/null)"; _unsafe_rc=$?
  if [[ "$_u_prep" -eq 0 && "$_unsafe_rc" -eq 2 ]] && grep -q "row 'lint probe' is not safe to execute" <<<"$_unsafe_out"; then _x=ok; else _x=bad; fi
  chk "harness (lint): a suite copy carrying an unsafe row stops with exit 2 and names the row (rc=$_unsafe_rc)" "$_x" "prep=$_u_prep out: $(tail -n 2 <<<"$_unsafe_out" | tr '\n' ' ')"
  "$PY_BIN" -I -c 'import sys
src, dst, anchor, new = sys.argv[1:5]
s = open(src).read()
if s.count(anchor) != 1: sys.exit(1)
open(dst, "w").write(s.replace(anchor, new))' "$SELF" "$WORK/meta/disturb.test.sh" $'  # The oracle must never have touched the world it ran in.\n' $'  rm -f -- "$TREE/.canary"\n  # The oracle must never have touched the world it ran in.\n' 2>/dev/null; _d_prep=$?
  _dist_out="$(env DCG_ROWS='^terraform plan$' GUARD_REPO_ROOT="$REPO_ROOT" GUARD_META_COPY=1 "$BASH" "$WORK/meta/disturb.test.sh" 2>&1 </dev/null)"; _dist_rc=$?
  if [[ "$_d_prep" -eq 0 && "$_dist_rc" -eq 2 ]] && grep -q 'the oracle disturbed its fixture world' <<<"$_dist_out"; then _x=ok; else _x=bad; fi
  chk "harness (lint): a suite copy whose oracle deletes the canary stops with exit 2 (the post-row fixture check fires, rc=$_dist_rc)" "$_x" "prep=$_d_prep out: $(tail -n 2 <<<"$_dist_out" | tr '\n' ' ')"
elif [[ -n "${GUARD_META_COPY:-}" ]]; then
  chk "harness (lint): a suite copy carrying an unsafe row stops with exit 2 and names the row (not run inside the meta copy)" ok
  chk "harness (lint): a suite copy whose oracle deletes the canary stops with exit 2 (not run inside the meta copy)" ok
fi
# (a) delete one expected-ask row from a COPY of this suite: the floor must fail; the control copy must not trip it.
_m="META-DELETE-"; _m+="TARGET"
if [[ -z "${GUARD_META_COPY:-}" ]] && want_row "harness (a): deleting one expected-ask row makes the floor fail"; then
  assert_fixture_dir "$WORK"
  grep -vF "$_m" "$SELF" > "$WORK/meta/mutant.test.sh"
  cp "$SELF" "$WORK/meta/control.test.sh"
  _mut_out="$(env -u DCG_ROWS GUARD_REPO_ROOT="$REPO_ROOT" GUARD_FAST_COUNT=1 GUARD_META_COPY=1 "$BASH" "$WORK/meta/mutant.test.sh" 2>&1 </dev/null)"; _mut_rc=$?
  _ctl_out="$(env -u DCG_ROWS GUARD_REPO_ROOT="$REPO_ROOT" GUARD_FAST_COUNT=1 GUARD_META_COPY=1 "$BASH" "$WORK/meta/control.test.sh" 2>&1 </dev/null)"; _ctl_rc=$?
  if [[ "$_mut_rc" -eq 1 ]] && grep -q 'assertions ran' <<<"$_mut_out"; then _x=ok; else _x=bad; fi
  chk "harness (a): deleting one expected-ask row makes the floor fail (rc=$_mut_rc)" "$_x" "$(tail -n 2 <<<"$_mut_out" | tr '\n' ' ')"
  if ! grep -q 'assertions ran' <<<"$_ctl_out" && grep -q '^cases=' <<<"$_ctl_out"; then _x=ok; else _x=bad; fi
  chk "harness (a): the unmodified control copy does not trip the floor" "$_x" "$(tail -n 2 <<<"$_ctl_out" | tr '\n' ' ')"
elif [[ -n "${GUARD_META_COPY:-}" ]]; then
  chk "harness (a): deleting one expected-ask row makes the floor fail (not run inside the meta copy)" ok
  chk "harness (a): the unmodified control copy does not trip the floor (not run inside the meta copy)" ok
fi
# A reduced run says so: the first line of a DCG_ROWS run is the banner, the summary repeats it, and a run with no seam prints neither.
if [[ -z "${GUARD_META_COPY:-}" ]] && want_row "harness (a2): a reduced run says so on its first line and in its summary"; then
  assert_fixture_dir "$WORK"
  _rr_out="$(env DCG_ROWS='^terraform plan$' GUARD_REPO_ROOT="$REPO_ROOT" GUARD_FAST_COUNT=1 GUARD_META_COPY=1 "$BASH" "$SELF" 2>&1 </dev/null)"
  _rr_full="$(env -u DCG_ROWS -u GUARD_HOOK GUARD_REPO_ROOT="$REPO_ROOT" GUARD_FAST_COUNT=1 GUARD_META_COPY=1 "$BASH" "$SELF" 2>&1 </dev/null)"
  if [[ "$(head -n 1 <<<"$_rr_out")" == '[REDUCED RUN: DCG_ROWS=^terraform plan$ — not the full gate]' ]]; then _x=ok; else _x=bad; fi
  chk "harness (a2): the first line of a DCG_ROWS run is the REDUCED RUN banner naming the selection" "$_x" "first line: $(head -n 1 <<<"$_rr_out")"
  if grep -q '^\[NOT THE FULL GATE: DCG_ROWS=\^terraform plan\$ selects a subset of the rows' <<<"$_rr_out"; then _x=ok; else _x=bad; fi
  chk "harness (a2): the summary of a DCG_ROWS run says it is not the full gate" "$_x" "$(tail -n 3 <<<"$_rr_out" | tr '\n' ' ')"
  if ! grep -q '^\[REDUCED RUN' <<<"$_rr_full" && ! grep -q '^\[NOT THE FULL GATE: DCG_ROWS' <<<"$_rr_full"; then _x=ok; else _x=bad; fi
  chk "harness (a2): a run without DCG_ROWS prints no REDUCED RUN banner" "$_x" "$(head -n 2 <<<"$_rr_full" | tr '\n' ' ')"
elif [[ -n "${GUARD_META_COPY:-}" ]]; then
  chk "harness (a2): the first line of a DCG_ROWS run is the REDUCED RUN banner naming the selection (not run inside the meta copy)" ok
  chk "harness (a2): the summary of a DCG_ROWS run says it is not the full gate (not run inside the meta copy)" ok
  chk "harness (a2): a run without DCG_ROWS prints no REDUCED RUN banner (not run inside the meta copy)" ok
fi

# =====================================================================================================
echo "== summary =="
echo "rows: executed=$ROWS_EXEC literal=$ROWS_LIT dead-code=$ROWS_DEAD (executed rows take their expectation from the recording-stub oracle)"
echo "ask-rate on the ordinary-command corpus: ${CORPUS_ASK}/${CORPUS_N} decided (errors=${CORPUS_ERR})"
if [[ -z "$ROWSEL" ]]; then
  if [[ "$CORPUS_N" -ge 40 ]]; then _x=ok; else _x=bad; fi
  chk "the ordinary-command corpus has at least 40 commands (has $CORPUS_N)" "$_x"
  if [[ -n "$FAST" ]]; then _x=ok; elif [[ "$CORPUS_ASK" -eq 0 && "$CORPUS_ERR" -eq 0 ]]; then _x=ok; else _x=bad; fi
  chk "the ask rate on the ordinary-command corpus is 0 (and no row errored)" "$_x" "ask=$CORPUS_ASK errors=$CORPUS_ERR of $CORPUS_N"
fi
echo "cases=$CHECKED passes=$PASS_COUNT fails=$FAIL_COUNT"
[[ -z "$NOTFULL" ]] || echo "[NOT THE FULL GATE: $NOTFULL]"
if [[ $((PASS_COUNT + FAIL_COUNT)) -ne "$CHECKED" ]]; then
  printf '[FATAL] anti-vacuity: %s verdicts recorded for %s cases\n' "$((PASS_COUNT + FAIL_COUNT))" "$CHECKED" >&2; exit 1
fi
if [[ -n "$ROWSEL" ]]; then
  # Reduced mode (DCG_ROWS, the mutation suite only): the MIN_CASES floor below does not apply to a selection.
  # The selection must have matched at least one row; the verdict is the failure count.
  echo "selected=$SELECTED"
  if [[ "$SELECTED" -lt 1 ]]; then printf '[FATAL] anti-vacuity: DCG_ROWS matched no row\n' >&2; exit 1; fi
  [[ "$FAIL_COUNT" -eq 0 ]]
  exit
fi
MIN_CASES=958
if [[ "$CHECKED" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$CHECKED" "$MIN_CASES" >&2
  exit 1
fi
[[ "$FAIL_COUNT" -eq 0 ]]
