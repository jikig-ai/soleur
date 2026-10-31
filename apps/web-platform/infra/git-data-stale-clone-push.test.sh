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
#        deliberately instead of by accident. The overwritten tip is not lost to the user: the
#        session-start overlay now preserves a store tip it declines to adopt on a rescue branch
#        (ensure-workspace-repo.ts, #11704).
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

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/stale-clone-push.XXXXXX")" || { echo "FATAL: no scratch root" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'rm -rf -- "$ROOT"' EXIT INT TERM

HOOK_SHA_BEFORE="$(sha256sum "$HOOK_SRC" | cut -d' ' -f1)"

# A constructed git environment: nothing is inherited (env -i), so no GIT_* location variable, no
# developer config and no host signing setup can reach the fixture or the hook.
mkdir -p "$ROOT/home" "$ROOT/data-root"
GIT_ENV=(env -i
  "PATH=$PATH"
  "HOME=$ROOT/home"
  "GIT_CONFIG_GLOBAL=/dev/null"
  "GIT_CONFIG_NOSYSTEM=1"
  "GIT_TERMINAL_PROMPT=0"
  "GIT_CEILING_DIRECTORIES=$ROOT"
  "GIT_AUTHOR_NAME=Fixture" "GIT_AUTHOR_EMAIL=fixture@example.com"
  "GIT_COMMITTER_NAME=Fixture" "GIT_COMMITTER_EMAIL=fixture@example.com"
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
expect_contains "confinement snapshot covers the peer sidecar generation" "1" "$SNAP_BEFORE"
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

# --- the bound hook was never modified by this suite ----------------------------------------------
expect_eq "bound hook digest unchanged by the run" "$HOOK_SHA_BEFORE" "$(sha256sum "$HOOK_SRC" | cut -d' ' -f1)"

total=$((passes + fails))
MIN_ASSERTIONS=23
if [[ "$total" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: ran only %s assertions (<%s) - the suite did not execute fully\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "git-data-stale-clone-push: ${passes} passed, ${fails} failed (${total} assertions)"
[[ "$fails" -eq 0 ]]
