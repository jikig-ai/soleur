#!/usr/bin/env bash
# Tests for scripts/lib/scratch-root.sh.
#
# The contract under test is mostly NEGATIVE: the resolver must FAIL LOUDLY rather than
# hand back something unusable. A silent empty return is the dangerous case — it makes
# `export TMPDIR=""` fall back to the tmpfs while every root-scoped assertion reads
# clean, which is the compounding false-green this module exists to prevent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/scratch-root.sh"

TMP_ROOT=$(mktemp -d -t scratchroottest.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Run the resolver in a CHILD shell so each case gets a clean environment. Capturing via
# `$( )` here is safe because we want the child's stdout; the exit code comes back in $?.
# Sets RESOLVE_OUT / RESOLVE_RC / RESOLVE_ERR in the CALLER's scope. Deliberately not
# usable as `x=$(resolve ...)`: command substitution would run this in a subshell and
# discard the variable assignments — the exact defect this PR exists to fix, which this
# harness hit twice while being written.
resolve() { # resolve <env assignments...>
  RESOLVE_OUT=$(env "$@" bash -c 'source "'"$LIB"'"; soleur_scratch_root' 2>"$TMP_ROOT/err")
  RESOLVE_RC=$?
  RESOLVE_ERR=$(cat "$TMP_ROOT/err")
}

echo "scratch-root.test.sh"

# --- 1. happy path: explicit override is honoured --------------------------------------
want="$TMP_ROOT/explicit"
resolve "SOLEUR_SCRATCH_ROOT=$want" "HOME=$TMP_ROOT"
if [[ "$RESOLVE_RC" -eq 0 && "$RESOLVE_OUT" == "$want" && -d "$want" ]]; then
  pass "explicit SOLEUR_SCRATCH_ROOT is honoured and created"
else
  fail "explicit override — rc=$RESOLVE_RC got='$RESOLVE_OUT'"
fi

# --- 2. derives from XDG_CACHE_HOME ----------------------------------------------------
resolve "XDG_CACHE_HOME=$TMP_ROOT/xdg" "HOME=$TMP_ROOT"
if [[ "$RESOLVE_RC" -eq 0 && "$RESOLVE_OUT" == "$TMP_ROOT/xdg/soleur/tmp" ]]; then
  pass "derives \$XDG_CACHE_HOME/soleur/tmp"
else
  fail "XDG derivation — rc=$RESOLVE_RC got='$RESOLVE_OUT'"
fi

# --- 3. falls back to \$HOME/.cache when XDG is unset -----------------------------------
resolve "HOME=$TMP_ROOT/home" --unset=XDG_CACHE_HOME
if [[ "$RESOLVE_RC" -eq 0 && "$RESOLVE_OUT" == "$TMP_ROOT/home/.cache/soleur/tmp" ]]; then
  pass "falls back to \$HOME/.cache/soleur/tmp"
else
  fail "HOME fallback — rc=$RESOLVE_RC got='$RESOLVE_OUT'"
fi

# --- 4. RELATIVE XDG_CACHE_HOME is refused, never resolved against CWD -----------------
#        This is the dangerous one: a relative value would put the root inside whatever
#        directory the caller happens to be in — frequently the repo working tree — and a
#        caller's `rm -rf` would then delete tracked files.
resolve "XDG_CACHE_HOME=relative/path" "HOME=$TMP_ROOT"
if [[ "$RESOLVE_RC" -ne 0 && -z "$RESOLVE_OUT" && "$RESOLVE_ERR" == *"not absolute"* ]]; then
  pass "a RELATIVE XDG_CACHE_HOME is refused loudly (never resolved against CWD)"
else
  fail "relative XDG — expected loud failure, rc=$RESOLVE_RC got='$RESOLVE_OUT'"
fi

# --- 5. a root inside the repo is refused ----------------------------------------------
repo_root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$repo_root" ]]; then
  resolve "XDG_CACHE_HOME=$repo_root/.scratch-probe" "HOME=$TMP_ROOT"
  if [[ "$RESOLVE_RC" -ne 0 && -z "$RESOLVE_OUT" && "$RESOLVE_ERR" == *"inside the repo"* ]]; then
    pass "a resolved root inside the repo working tree is refused"
  else
    fail "in-repo root — expected refusal, rc=$RESOLVE_RC got='$RESOLVE_OUT'"
  fi
  rm -rf -- "$repo_root/.scratch-probe" 2>/dev/null || true
else
  pass "in-repo check skipped (not in a git repo)"
fi

# --- 6. neither HOME nor XDG set ⇒ loud failure, never an empty success ------------------
resolve --unset=HOME --unset=XDG_CACHE_HOME --unset=SOLEUR_SCRATCH_ROOT
if [[ "$RESOLVE_RC" -ne 0 && -z "$RESOLVE_OUT" ]]; then
  pass "no HOME and no XDG ⇒ non-zero, empty stdout (never a silent /tmp fallback)"
else
  fail "unset-env case — expected failure, rc=$RESOLVE_RC got='$RESOLVE_OUT'"
fi

# --- 7. an unwritable target is refused -------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  ro="$TMP_ROOT/readonly"; mkdir -p "$ro"; chmod 0500 "$ro"
  resolve "XDG_CACHE_HOME=$ro/nested" "HOME=$TMP_ROOT"
  if [[ "$RESOLVE_RC" -ne 0 && -z "$RESOLVE_OUT" ]]; then
    pass "an uncreatable/unwritable root is refused loudly"
  else
    fail "unwritable root — expected failure, rc=$RESOLVE_RC got='$RESOLVE_OUT'"
  fi
  chmod 0700 "$ro"
else
  pass "unwritable-root check skipped (running as root)"
fi

# --- 8. NEVER silently falls back to the shared tmp root --------------------------------
#        The property is CONTAINMENT in the configured base, not "the path does not start
#        with /tmp". Asserting the latter would be a fixture artifact here: this harness's
#        own scratch lives under /tmp, so a HOME pointed inside it legitimately derives a
#        /tmp/... path. What must never happen is the resolver ignoring the configured
#        base and handing back the shared tmp root itself (or $TMPDIR) — that is the
#        silent fallback which would send bulk writes back onto the RAM disk while every
#        root-scoped assertion still read clean.
resolve "HOME=$TMP_ROOT/home2" --unset=XDG_CACHE_HOME
shared_tmp="${TMPDIR:-/tmp}"; shared_tmp="${shared_tmp%/}"
if [[ "$RESOLVE_RC" -eq 0 \
      && "$RESOLVE_OUT" == "$TMP_ROOT/home2/.cache/soleur/tmp" \
      && "$RESOLVE_OUT" != "$shared_tmp" \
      && "$RESOLVE_OUT" != "/tmp" ]]; then
  pass "a successful resolve is contained in the configured base, never the shared tmp root"
else
  fail "containment — rc=$RESOLVE_RC got='$RESOLVE_OUT'"
fi

# --- 9. the resolver does NOT mutate TC_TMPDIR (ADR-133 instrumentation) ----------------
#        test-contention.sh binds TC_TMPDIR at source time to watch the tmpfs. Repointing
#        it would silently blind the instrumentation to the mount it exists to observe.
out=$(env "HOME=$TMP_ROOT" "TC_TMPDIR=/tmp" bash -c \
  'source "'"$LIB"'"; soleur_scratch_root >/dev/null; printf "%s" "${TC_TMPDIR:-UNSET}"' 2>/dev/null)
if [[ "$out" == "/tmp" ]]; then
  pass "TC_TMPDIR is left untouched (ADR-133 instrumentation stays pointed at the tmpfs)"
else
  fail "TC_TMPDIR was mutated to '$out'"
fi

# --- 10. the resolver does NOT export TMPDIR --------------------------------------------
#         Redirecting every child is the caller's decision, not this module's.
out=$(env "HOME=$TMP_ROOT" --unset=TMPDIR bash -c \
  'source "'"$LIB"'"; soleur_scratch_root >/dev/null; printf "%s" "${TMPDIR:-UNSET}"' 2>/dev/null)
if [[ "$out" == "UNSET" ]]; then
  pass "TMPDIR is not exported (redirection stays the caller's decision)"
else
  fail "TMPDIR was exported as '$out'"
fi

echo
if (( fails > 0 )); then echo "FAILED: $fails"; exit 1; fi
echo "All scratch-root tests passed."
