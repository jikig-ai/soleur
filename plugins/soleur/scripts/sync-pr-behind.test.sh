#!/usr/bin/env bash
# Suite for plugins/soleur/scripts/sync-pr-behind.sh -- specifically its regenerable-conflict
# arm (#8377, ADR-230).
#
# ── SCOPE, STATED HONESTLY ──────────────────────────────────────────────────────────────────
# This covers the branch the resolver added and the two outcomes the caller must distinguish:
#   resolver rc 0      -> the merge is already committed; DO NOT merge again; push; succeed.
#   resolver non-zero  -> today's behaviour, unchanged: exit 6 with a clean tree.
# It does NOT cover the gh-polling loop, the BEHIND cap, or exit 7 -- those predate this change
# and have no suite; adding one is not this PR's subject. Saying so beats implying otherwise by
# a suite name that suggests whole-script coverage.
#
# ── HOW THE SEAM IS BUILT ───────────────────────────────────────────────────────────────────
# `gh` is a PATH stub that reports OPEN DIRTY once, then OPEN CLEAN. The stub REFUSES a request
# it did not expect (exit 64) rather than answering every question identically -- a fake that
# answers regardless of argv puts the seam above everything the caller's request shape encodes,
# so a caller querying the wrong thing would still read the right fixture.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sync-pr-behind.sh"

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$SUT" ]] || { echo "[FATAL] SUT not found at $SUT" >&2; exit 1; }

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

SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

MODEL="knowledge-base/engineering/architecture/diagrams/model.likec4.json"
SRC="knowledge-base/engineering/architecture/diagrams/model.c4"
_git() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# mkfix <name> <conflict-kind> — a repo with a real `origin` remote (a local bare clone, so the
# push path is exercised for real rather than stubbed) and a conflict of the requested kind.
mkfix() {
  local name="$1" kind="$2"
  local root="$SANDBOX/$name"; assert_fixture_dir "$root"
  local up="$root/upstream.git" wt="$root/wt"
  mkdir -p "$up" "$wt"
  git init -q --bare "$up"

  mkdir -p "$wt/knowledge-base/engineering/architecture/diagrams" \
           "$wt/plugins/soleur/scripts" "$wt/scripts"
  printf 'first\nx\nlast\n' > "$wt/$SRC"
  printf '{"v":"base"}\n' > "$wt/$MODEL"
  printf 'readme base\n' > "$wt/README.md"
  # BOTH scripts are COPIED INTO THE FIXTURE, and for sync-pr-behind.sh that is mandatory,
  # not stylistic: it resolves its own repo root from ${BASH_SOURCE[0]}/../../.. and `cd`s
  # there. Run from the tracked path it would operate on the REAL repository regardless of
  # this fixture -- measured: the first run of this suite reported the developer's own branch
  # name and exited 6 against the live worktree. Copying it makes that walk land in $wt.
  cp "$SCRIPT_DIR/sync-pr-behind.sh" "$wt/plugins/soleur/scripts/"
  cp "$SCRIPT_DIR/resolve-regenerable-conflicts.sh" "$wt/plugins/soleur/scripts/"
  cat > "$wt/scripts/regenerate-c4-model.sh" <<STUB
#!/usr/bin/env bash
set -euo pipefail
R="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
printf '{"from":"%s|%s"}\n' "\$(head -1 "\$R/$SRC")" "\$(tail -1 "\$R/$SRC")" > "\$R/$MODEL"
STUB
  chmod +x "$wt/scripts/regenerate-c4-model.sh"
  _git "$wt" init -q -b main
  _git "$wt" remote add origin "$up"
  _git "$wt" add -A >/dev/null; _git "$wt" commit -q -m base
  _git "$wt" push -q origin main

  _git "$wt" checkout -q -b feature
  sed -i 's/^last$/last-FEATURE/' "$wt/$SRC"
  printf '{"v":"feature"}\n' > "$wt/$MODEL"
  [[ "$kind" == "unresolvable" ]] && printf 'readme FEATURE\n' > "$wt/README.md"
  _git "$wt" add -A >/dev/null; _git "$wt" commit -q -m feature
  _git "$wt" push -q -u origin feature

  _git "$wt" checkout -q main
  sed -i 's/^first$/first-MAIN/' "$wt/$SRC"
  printf '{"v":"main"}\n' > "$wt/$MODEL"
  [[ "$kind" == "unresolvable" ]] && printf 'readme MAIN\n' > "$wt/README.md"
  _git "$wt" add -A >/dev/null; _git "$wt" commit -q -m main
  _git "$wt" push -q origin main
  _git "$wt" checkout -q feature

  # STRICT gh stub: answers only the query the SUT is expected to make, refuses anything else.
  mkdir -p "$root/bin"
  cat > "$root/bin/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1 $2" != "pr view" ]]; then
  echo "STUB-MISS: unexpected gh invocation: $*" >&2; exit 64
fi
for a in "$@"; do [[ "$a" == "state,mergeStateStatus" ]] && found=1; done
if [[ -z "${found:-}" ]]; then
  echo "STUB-MISS: gh pr view without the expected --json fields: $*" >&2; exit 64
fi
n="$(cat "${GH_CALLS:?}" 2>/dev/null || echo 0)"; echo $((n + 1)) > "$GH_CALLS"
if [[ "$n" -eq 0 ]]; then echo "OPEN DIRTY"; else echo "OPEN CLEAN"; fi
GH
  chmod +x "$root/bin/gh"
  printf '%s' "$root"
}

run_sut() {
  # SPLIT, not `local root="$1" wt="$root/wt"`: within one `local` statement the later
  # assignment does not see the earlier name, so under `set -u` that form aborts the function
  # with "root: unbound variable" -- and the caller reads the empty output as a SUT that
  # printed nothing, which looks exactly like the bug this suite is here to detect.
  local root="$1"
  local wt="$root/wt"
  local out rc=0
  out="$(cd "$wt" && GH_CALLS="$root/gh.calls" PATH="$root/bin:$PATH" \
        bash "$wt/plugins/soleur/scripts/sync-pr-behind.sh" 123 2>&1)" || rc=$?
  printf '%s\n%s' "$out" "$rc"
}
sut_rc()  { tail -n1 <<<"$1"; }
sut_out() { sed '$d' <<<"$1"; }

# RELOCATION SELF-TEST. The failure mode this guards is silent and total: a SUT that walks
# to the real repo answers every case from a tree the fixture never built, and the verdicts
# look ordinary. Require the fixture's own branch name in the output before reading anything.
_rt_root="$(mkfix relocation resolvable)"
_rt_out="$(sut_out "$(run_sut "$_rt_root")")"
if ! grep -q 'branch: feature' <<<"$_rt_out"; then
  printf '[FATAL] relocation self-test: the SUT did not report the fixture branch.\n' >&2
  printf '        It is operating on some other repository, so every case below is void.\n' >&2
  printf '        got: %s\n' "$_rt_out" >&2
  exit 1
fi

echo "=== sync-pr-behind: regenerable-conflict arm ==="

# ── rc 0: the conflict is regenerable -> merged, regenerated, pushed ───────────────────────
echo ""
echo "--- resolver rc 0: merge is completed and pushed ---"
root="$(mkfix ok resolvable)"; wt="$root/wt"
res="$(run_sut "$root")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "exits 0 on a regenerable conflict" \
  || fail "exited $(sut_rc "$res"): $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'regenerable conflict resolved' <<<"$(sut_out "$res")"; then
  pass "reports that the regenerable path was taken"
else
  fail "the regenerable arm is invisible in the output: $(sut_out "$res")"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ "$(cat "$wt/$MODEL")" == *'first-MAIN|last-FEATURE'* ]] \
  && pass "the artifact was regenerated from the MERGED sources" \
  || fail "artifact is $(cat "$wt/$MODEL") — regen did not see the merged tree"
CASES_RUN=$((CASES_RUN + 1))
# The merge must have reached the REMOTE: this is what distinguishes "resolved" from
# "resolved locally and silently not pushed", and the resolver deliberately never pushes.
if _git "$root/upstream.git" rev-parse feature >/dev/null 2>&1 \
   && [[ "$(_git "$wt" rev-parse feature)" == "$(_git "$root/upstream.git" rev-parse feature)" ]]; then
  pass "the merge commit was pushed (the caller owns the push, not the resolver)"
else
  fail "the remote feature ref does not match local HEAD — the merge was never pushed"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(_git "$wt" status --porcelain)" ]] && pass "the worktree is clean afterwards" \
  || fail "worktree dirty: $(_git "$wt" status --porcelain)"

# ── non-zero: a non-regenerable conflict is refused exactly as before ──────────────────────
echo ""
echo "--- resolver non-zero: unchanged exit 6, tree untouched ---"
root="$(mkfix bad unresolvable)"; wt="$root/wt"
head_before="$(_git "$wt" rev-parse HEAD)"
res="$(run_sut "$root")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "6" ]] && pass "exits 6 on a non-regenerable conflict" \
  || fail "expected exit 6, got $(sut_rc "$res"): $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(_git "$wt" rev-parse HEAD)" == "$head_before" ]] && pass "HEAD did not move" \
  || fail "HEAD moved on a conflict that should have been refused"
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(_git "$wt" status --porcelain)" ]] && pass "the tree is clean (merge aborted)" \
  || fail "tree left dirty: $(_git "$wt" status --porcelain)"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'manual resolution required' <<<"$(sut_out "$res")"; then
  pass "reports that manual resolution is required"
else
  fail "the refusal is not reported: $(sut_out "$res")"
fi
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'STUB-MISS' <<<"$(sut_out "$res")"; then
  fail "the gh stub was called in a way it did not expect — the fixture is not exercising the real request shape"
else
  pass "no STUB-MISS: the SUT queried gh exactly as the stub expects"
fi

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"
_min_cases=10
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "sync-pr-behind: all $passes assertions passed"
