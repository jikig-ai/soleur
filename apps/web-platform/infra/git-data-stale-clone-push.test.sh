#!/usr/bin/env bash
#
# Characterization (#11704): what a STALE CLONE can and cannot do through the REAL git-data
# writer-side fence. Real `git push` into a bare repository whose `hooks/pre-receive` is a byte-copy
# of the BOUND hook (git-data-pre-receive.sh, read-only here: this suite never edits it, and checks
# its digest before and after).
#
#   CH1  a stale clone pushing refs/heads/* into a PEER's namespace (or the canonical refs/heads/*)
#        is rejected with the hook's namespace text; every ref outside the pusher's own namespace is
#        byte-identical afterwards.
#   CH2  a push at a lease generation below the stored max is rejected with the hook's
#        `stale lease generation` text; the ref and the sidecar are unchanged.
#   CH3  a stale clone holding the CURRENT generation is ACCEPTED and `--force` overwrites its OWN
#        namespace tip. This is the ACCEPTED, TRACKED RESIDUAL (#11716): the fence orders writers by
#        generation, not by ref ancestry. The row pins today's behaviour so a future fix flips it
#        deliberately instead of by accident. The session-start overlay (ensure-workspace-repo.ts,
#        #11704) preserves a store tip it declines to adopt only on a FRESH graft; CH3's clone is
#        already live, so nothing here protects the overwritten tip.
#   T1   the replication push (git-data-replication.ts, CTO F12 + T1b) is TWO steps from a `--depth 1`
#        clone with push-options: the overlay's rescue branch `soleur-store-tip-<12 hex>` ALONE first,
#        then the rest with `--atomic --force`. --atomic only covers a ref the store rejects INSIDE
#        the ref transaction (a refname conflict): `main` then stays unchanged, where without it
#        `main` is forced first. It does NOT cover the shallow "remote failed to report status"
#        class; the rescue-first push is what keeps the old store tip referenced there (the second
#        push is forced to fail, the old tip stays on the rescue ref, a same-generation retry lands).
#        The flat rescue name cannot collide with a plain head such as `soleur` (the old
#        `soleur/store-tip-<sha>` could).
#
# STOP RULE: if any row shows a write OUTSIDE the pusher's own namespace, this suite stops with
# exit 3 and a STOP line. It must not be "fixed" by adjusting an assertion; report it instead.
#
# Run: bash apps/web-platform/infra/git-data-stale-clone-push.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="${SCRIPT_DIR}/git-data-pre-receive.sh"

# The CANONICAL copy (plugins/soleur/test/test-helpers.sh), byte-for-byte: the fixture roots below
# are command-substitution results, so the writes into them need the absoluteness guard. #7652
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
case "$SCRIPT_DIR" in
  "") echo "FATAL: SCRIPT_DIR is empty" >&2; exit 2 ;;
  /*) : ;;
  *)  echo "FATAL: SCRIPT_DIR is RELATIVE" >&2; exit 2 ;;
esac
[[ -f "$HOOK_SRC" ]] || { echo "FATAL: bound hook not found at $HOOK_SRC" >&2; exit 2; }
command -v flock >/dev/null 2>&1 || { echo "FATAL: flock missing; the hook cannot run" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git missing" >&2; exit 2; }

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }
expect_eq() { # <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass; else fail "$1: expected '$2', got '$3'"; fi
}
expect_contains() { # <label> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then pass; else fail "$1: expected output to contain '$2', got: $3"; fi
}

# Instrument self-test: drive each verdict-owning helper with a matching and a MISMATCHING case and require the counters to move the
# right way (a helper disarmed to `pass` leaves fails flat). Counters are unwound so the floor below stays exact; reported by printf + exit.
_p0=$passes; _f0=$fails; _inst_bad=""
probe() { # <name> <want passes delta> <want fails delta> <helper> args...
  local name="$1" wp="$2" wf="$3" p f
  shift 3
  p=$passes; f=$fails
  "$@" >/dev/null 2>&1
  if (( passes - p != wp || fails - f != wf )); then _inst_bad="$_inst_bad $name"; fi
}
probe eq-match 1 0 expect_eq i a a
probe eq-mismatch 0 1 expect_eq i a b
probe contains-match 1 0 expect_contains i b abc
probe contains-mismatch 0 1 expect_contains i x abc
passes=$_p0; fails=$_f0
if [[ -n "$_inst_bad" ]]; then
  printf '[FATAL] instrument self-test: helper(s) did not move the verdict counters as required:%s\n' "$_inst_bad" >&2
  exit 1
fi

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/stale-clone-push.XXXXXX")" || { echo "FATAL: no scratch root" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'rm -rf -- "$ROOT"' EXIT INT TERM

HOOK_SHA_BEFORE="$(sha256sum "$HOOK_SRC" | cut -d' ' -f1)"

# The shared fixture git environment (prefix sweep of inherited GIT_*, discovery ceiling, config hermeticity, identity); then the two
# additions this suite needs: a HOME under the scratch root and the hook's cutover-freeze root.
mkdir -p "$ROOT/home" "$ROOT/data-root"
# shellcheck source=../../../plugins/soleur/test/lib/git-fixture-env.sh
source "${SCRIPT_DIR}/../../../plugins/soleur/test/lib/git-fixture-env.sh" || { echo "FATAL: cannot load git-fixture-env.sh" >&2; exit 2; }
git_fixture_env "$ROOT" || { echo "FATAL: git_fixture_env refused $ROOT" >&2; exit 2; }
GIT_ENV=(env
  "HOME=$ROOT/home"
  # the hook's cutover-freeze sentinel resolves under this root, never under the host's /mnt/git-data
  "GIT_DATA_ROOT=$ROOT/data-root")

gitd() { # <dir> <git args...>
  local d="$1"
  shift
  assert_fixture_dir "$d"
  "${GIT_ENV[@]}" git -C "$d" "$@"
}

commit_file() { # <dir> <file> <body> -> prints the new HEAD
  local d="$1" f="$2" body="$3"
  assert_fixture_dir "$d"
  printf '%s\n' "$body" >"$d/$f"
  gitd "$d" add -- "$f" >/dev/null
  gitd "$d" commit -q -m "add $f" >/dev/null
  gitd "$d" rev-parse HEAD
}

# push <clone> <refspec> <lease-gen> <worktree-id>; prints combined output, returns git's rc
push_as() {
  local d="$1" spec="$2" gen="$3" wt="$4"
  gitd "$d" push --force "$STORE" "$spec" \
    "--push-option=lease-gen=${gen}" "--push-option=worktree-id=${wt}" 2>&1
}

OWN="own-wt"
PEER="peer-wt"
own_ref="refs/soleur/worktrees/${OWN}/heads/main"
peer_ref="refs/soleur/worktrees/${PEER}/heads/main"

# --- fixture: origin (A), a stale clone at A, origin moves to B, a fresh clone, a peer ------------
ORIGIN="$ROOT/origin"
STORE="$ROOT/store.git"
STALE="$ROOT/stale"
FRESH="$ROOT/fresh"
PEERCLONE="$ROOT/peerclone"
mkdir -p "$ORIGIN"
gitd "$ORIGIN" init -q -b main >/dev/null
commit_file "$ORIGIN" a.txt "a" >/dev/null
"${GIT_ENV[@]}" git clone -q --depth 1 "file://$ORIGIN" "$STALE" >/dev/null 2>&1   # the stale clone: shallow, at A
commit_file "$ORIGIN" a.txt "b" >/dev/null                                           # origin moves on
"${GIT_ENV[@]}" git clone -q --depth 1 "file://$ORIGIN" "$FRESH" >/dev/null 2>&1
"${GIT_ENV[@]}" git clone -q --depth 1 "file://$ORIGIN" "$PEERCLONE" >/dev/null 2>&1
FRESH_TIP="$(commit_file "$FRESH" fresh.txt "fresh work")"
PEER_TIP="$(commit_file "$PEERCLONE" peer.txt "peer work")"
STALE_TIP="$(commit_file "$STALE" stale.txt "stale work")"

# --- the store: a bare repo with the REAL bound hook installed as a read-only copy -----------------
mkdir -p "$STORE"
gitd "$STORE" init -q --bare >/dev/null
gitd "$STORE" config receive.advertisePushOptions true
gitd "$STORE" config receive.shallowUpdate true
assert_fixture_dir "$STORE"
mkdir -p "$STORE/hooks"
assert_fixture_dir "$STORE/hooks"
cp -- "$HOOK_SRC" "$STORE/hooks/pre-receive"
chmod 0755 "$STORE/hooks/pre-receive"
expect_eq "installed hook is a byte copy of the bound hook" \
  "$HOOK_SHA_BEFORE" "$(sha256sum "$STORE/hooks/pre-receive" | cut -d' ' -f1)"

# the hook strings asserted below are the hook's own; a wording change fails here, loudly
if grep -q "outside this worktree's namespace" "$HOOK_SRC"; then pass; else fail "hook source no longer carries the namespace rejection text"; fi
if grep -q "stale lease generation" "$HOOK_SRC"; then pass; else fail "hook source no longer carries the stale-generation rejection text"; fi

# --- seed through the hook: own namespace at generation 3, peer namespace at generation 1 ---------
out="$(push_as "$FRESH" "+refs/heads/*:refs/soleur/worktrees/${OWN}/heads/*" 3 "$OWN")" || { echo "FATAL: seeding the own namespace was rejected: $out" >&2; exit 2; }
out="$(push_as "$PEERCLONE" "+refs/heads/*:refs/soleur/worktrees/${PEER}/heads/*" 1 "$PEER")" || { echo "FATAL: seeding the peer namespace was rejected: $out" >&2; exit 2; }
expect_eq "seed: own tip" "$FRESH_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "seed: peer tip" "$PEER_TIP" "$(gitd "$STORE" rev-parse "$peer_ref")"

# Everything OUTSIDE the pusher's own namespace, plus the peer's fence sidecar: the confinement
# snapshot. A write outside the own namespace changes this text.
outside_snapshot() {
  gitd "$STORE" for-each-ref --format='%(refname) %(objectname)' | sed -n "\#^refs/soleur/worktrees/${OWN}/#!p"
  cat "$STORE/fence/${PEER}.gen" 2>/dev/null
}
SNAP_BEFORE="$(outside_snapshot)"
# anti-vacuity: the confinement snapshot really covers the peer's ref and fence sidecar
expect_contains "confinement snapshot covers the peer ref" "$peer_ref $PEER_TIP" "$SNAP_BEFORE"
expect_eq "peer sidecar holds exactly generation 1" "1" "$(tr -d '[:space:]' <"$STORE/fence/${PEER}.gen")"
expect_eq "confinement snapshot ends with the peer sidecar generation (exact)" "1" "$(printf '%s\n' "$SNAP_BEFORE" | tail -n 1 | tr -d '[:space:]')"
confined_or_stop() { # <row>
  local now
  now="$(outside_snapshot)"
  if [[ "$now" != "$SNAP_BEFORE" ]]; then
    echo "STOP: $1 changed state OUTSIDE the pusher's own namespace. Do not adjust the assertion; report this." >&2
    printf '%s\n' "--- before" "$SNAP_BEFORE" "--- after" "$now" >&2
    exit 3
  fi
}

# --- CH1: cross-namespace writes from a stale clone are rejected ---------------------------------
out="$(push_as "$STALE" "+refs/heads/*:refs/soleur/worktrees/${PEER}/heads/*" 3 "$OWN")"; rc=$?
confined_or_stop "CH1 (peer namespace)"
expect_eq "CH1 peer-namespace push is rejected (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_contains "CH1 rejection carries the hook's namespace text" "outside this worktree's namespace" "$out"
expect_eq "CH1 peer tip byte-identical" "$PEER_TIP" "$(gitd "$STORE" rev-parse "$peer_ref")"

out="$(push_as "$STALE" "+refs/heads/*:refs/heads/*" 3 "$OWN")"; rc=$?
confined_or_stop "CH1 (canonical refs/heads/*)"
expect_eq "CH1 canonical-namespace push is rejected (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_contains "CH1 canonical rejection carries the namespace text" "outside this worktree's namespace" "$out"
expect_eq "CH1 no canonical refs/heads/main was created" "" "$(gitd "$STORE" for-each-ref 'refs/heads/')"
expect_eq "CH1 own tip untouched by the rejected pushes" "$FRESH_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"

# --- CH2: a stale generation is rejected ---------------------------------------------------------
out="$(push_as "$STALE" "+refs/heads/*:refs/soleur/worktrees/${OWN}/heads/*" 2 "$OWN")"; rc=$?
confined_or_stop "CH2"
expect_eq "CH2 stale-generation push is rejected (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_contains "CH2 rejection carries the hook's stale-generation text" "stale lease generation 2 < stored max 3" "$out"
expect_eq "CH2 own tip unchanged" "$FRESH_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "CH2 own sidecar generation unchanged" "3" "$(tr -d '[:space:]' <"$STORE/fence/${OWN}.gen")"

# --- CH3: a stale clone at the CURRENT generation overwrites its OWN namespace (accepted, #11716) --
out="$(push_as "$STALE" "+refs/heads/*:refs/soleur/worktrees/${OWN}/heads/*" 3 "$OWN")"; rc=$?
confined_or_stop "CH3"
expect_eq "CH3 same-generation stale-clone push is ACCEPTED (rc=0) - accepted residual #11716" "0" "$rc"
expect_eq "CH3 the stale clone's tip now holds the own-namespace ref (overwrite, tracked #11716)" \
  "$STALE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "CH3 the overwritten tip is not the previous one" "1" "$([[ "$(gitd "$STORE" rev-parse "$own_ref")" != "$FRESH_TIP" ]] && echo 1 || echo 0)"
expect_eq "CH3 peer tip still byte-identical (confined to the own namespace)" "$PEER_TIP" "$(gitd "$STORE" rev-parse "$peer_ref")"

# --- T1: the replication push (git-data-replication.ts, CTO F12 + T1b) -------------------------------------
# What production sends: `push --force [--atomic] <store> refs/heads/*:refs/soleur/worktrees/<wt>/heads/*` plus both push-options,
# from a `--depth 1` clone that carries `main` and the overlay's rescue branch holding the old store tip. The rows up to the
# "two-step" block below pin what --atomic alone does: it covers a ref rejected INSIDE the ref transaction (a refname conflict).
push_wild() { # <clone> <lease-gen> <worktree-id> [extra push flags...]; prints combined output, returns git's rc
  local d="$1" gen="$2" wt="$3"
  shift 3
  gitd "$d" push --force "$@" "$STORE" "+refs/heads/*:refs/soleur/worktrees/${wt}/heads/*" \
    "--push-option=lease-gen=${gen}" "--push-option=worktree-id=${wt}" 2>&1
}
T1CLONE="$ROOT/t1clone"
"${GIT_ENV[@]}" git clone -q --depth 1 "file://$ORIGIN" "$T1CLONE" >/dev/null 2>&1
T1_TIP="$(commit_file "$T1CLONE" t1.txt "replicated work")"
gitd "$T1CLONE" fetch -q --depth 1 "$STORE" "$own_ref" >/dev/null 2>&1
STORE_TIP="$(gitd "$T1CLONE" rev-parse FETCH_HEAD)"
RESCUE="soleur-store-tip-${STORE_TIP:0:12}"
rescue_ref="refs/soleur/worktrees/${OWN}/heads/${RESCUE}"
gitd "$T1CLONE" branch "$RESCUE" "$STORE_TIP"
expect_eq "T1 fixture: the clone is shallow (a --depth 1 push client)" "true" "$(gitd "$T1CLONE" rev-parse --is-shallow-repository)"
expect_eq "T1 fixture: the store tip the rescue branch holds is the CH3 tip" "$STALE_TIP" "$STORE_TIP"
expect_eq "T1 fixture: the rescue name is the flat soleur-store-tip-<12 hex>" "1" \
  "$([[ "$RESCUE" =~ ^soleur-store-tip-[0-9a-f]{12}$ ]] && echo 1 || echo 0)"

# A refname conflict is a rejection inside the ref transaction, the only class --atomic covers (a store head living UNDER the
# rescue name's path).
gitd "$STORE" update-ref "${rescue_ref}/blocker" "$STORE_TIP"
out="$(push_wild "$T1CLONE" 3 "$OWN" --atomic)"; rc=$?
confined_or_stop "T1 (atomic, rescue ref rejected)"
expect_eq "T1 atomic push with a rejected rescue ref fails (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_eq "T1 atomic: store main is UNCHANGED when the rescue ref is rejected (old store tip stays referenced)" \
  "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1 atomic: the rescue ref was not created" "" "$(gitd "$STORE" rev-parse -q --verify "$rescue_ref" || true)"

# Control: the SAME push without --atomic moves main first (why --atomic is there); the control proves the row above can fail.
out="$(push_wild "$T1CLONE" 3 "$OWN")"; rc=$?
confined_or_stop "T1 (non-atomic control)"
expect_eq "T1 control: without --atomic the rejected rescue ref still lets main move (the defect --atomic closes)" \
  "$T1_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
gitd "$STORE" update-ref "$own_ref" "$STORE_TIP"
gitd "$STORE" update-ref -d "${rescue_ref}/blocker"

# Positive: a store head named `soleur` (the old slash name's collision) does not block the flat rescue name.
gitd "$STORE" update-ref "refs/soleur/worktrees/${OWN}/heads/soleur" "$STORE_TIP"
out="$(push_wild "$T1CLONE" 3 "$OWN" --atomic)"; rc=$?
confined_or_stop "T1 (atomic positive)"
expect_eq "T1 atomic positive: a --depth 1 push with push-options beside a store head named soleur is ACCEPTED (rc=0)" "0" "$rc"
expect_eq "T1 atomic positive: store main advanced to the clone's tip" "$T1_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1 atomic positive: the rescue ref holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"
expect_eq "T1 atomic positive: the store head named soleur is untouched" "$STORE_TIP" "$(gitd "$STORE" rev-parse "refs/soleur/worktrees/${OWN}/heads/soleur")"

# --- T1b: rescue-ref-first, then the rest (the transient "failed to report status" class) ----------------------------
# --atomic cannot help when the second push fails for a reason outside the ref transaction, so production pushes the rescue ref ALONE
# first. Reset the store to the pre-replication state, push the rescue ref only, then FORCE the second push to fail with a store-side
# `update` hook (a flag file arms it; the bound pre-receive hook is untouched), and require that the old tip stays referenced.
gitd "$STORE" update-ref "$own_ref" "$STORE_TIP"
gitd "$STORE" update-ref -d "$rescue_ref"
gitd "$STORE" update-ref -d "refs/soleur/worktrees/${OWN}/heads/soleur"
FAIL_MAIN="$ROOT/fail-main-flag"
HOOK_UPDATE="$STORE/hooks/update"
assert_fixture_dir "$FAIL_MAIN"
assert_fixture_dir "$HOOK_UPDATE"
printf '#!/bin/sh\n[ -e "%s" ] && case "$1" in */heads/main) echo "forced failure of the main update" >&2; exit 1;; esac\nexit 0\n' "$FAIL_MAIN" >"$HOOK_UPDATE"
chmod 0755 "$HOOK_UPDATE"
out="$(gitd "$T1CLONE" push --force --atomic "$STORE" "+refs/heads/soleur-store-tip-*:refs/soleur/worktrees/${OWN}/heads/soleur-store-tip-*" \
  "--push-option=lease-gen=3" "--push-option=worktree-id=${OWN}" 2>&1)"; rc=$?
confined_or_stop "T1b (rescue-first push)"
expect_eq "T1b step 1: the rescue ref alone, from a --depth 1 clone with push-options, lands (rc=0)" "0" "$rc"
expect_eq "T1b step 1: the rescue ref holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"
expect_eq "T1b step 1: store main is untouched by the rescue-only push" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
: >"$FAIL_MAIN"
out="$(push_wild "$T1CLONE" 3 "$OWN" --atomic)"; rc=$?
confined_or_stop "T1b (second push forced to fail)"
expect_eq "T1b step 2: the forced failure rejects the second push (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_contains "T1b step 2: the failure is the forced one" "forced failure of the main update" "$out"
expect_eq "T1b step 2: store main is unchanged" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1b step 2: the old store tip is still referenced from a soleur-store-tip-* ref" "$rescue_ref" \
  "$(gitd "$STORE" for-each-ref --contains "$STORE_TIP" --format='%(refname)' "refs/soleur/worktrees/${OWN}/heads/soleur-store-tip-*")"
expect_eq "T1b step 2: the old store tip is still reachable (commit object present)" "0" "$(gitd "$STORE" cat-file -e "${STORE_TIP}^{commit}" 2>/dev/null; echo $?)"
rm -f "$FAIL_MAIN"
out="$(push_wild "$T1CLONE" 3 "$OWN" --atomic)"; rc=$?
confined_or_stop "T1b (retry at the same generation)"
expect_eq "T1b retry: the second push at the SAME generation succeeds (rc=0)" "0" "$rc"
expect_eq "T1b retry: store main advanced to the clone's tip" "$T1_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1b retry: the rescue ref still holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"

# --- the bound hook was never modified by this suite ----------------------------------------------
expect_eq "bound hook digest unchanged by the run" "$HOOK_SHA_BEFORE" "$(sha256sum "$HOOK_SRC" | cut -d' ' -f1)"

total=$((passes + fails))
MIN_ASSERTIONS=46
if [[ "$total" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: ran only %s assertions (<%s) - the suite did not execute fully\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "git-data-stale-clone-push: ${passes} passed, ${fails} failed (${total} assertions)"
[[ "$fails" -eq 0 ]]
