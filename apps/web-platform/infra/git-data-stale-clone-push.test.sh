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
#   T1   the replication push (git-data-replication.ts, CTO F12 + T1b + F19..F21) is TWO steps from a
#        `--depth 1` clone with push-options: the overlay's rescue branches `soleur-store-tip-<12 hex>`
#        ALONE first (`--force --atomic`), then, once step 1 is confirmed, the pushed LOCAL rescue
#        branches are deleted best-effort (`update-ref -d <ref> <sha>`, F21), then the rest with
#        `--force` and NO `--atomic` (F20). Step 1's --atomic covers a ref the store rejects INSIDE
#        the ref transaction (a refname conflict): none of the rescue refs of that push lands.
#        Step 2 is per-ref: a partial rejection (main landed, a ref such as a local `fix` against a
#        store head `fix/x` rejected) exits non-zero, which production reports loudly (no success
#        marker). The shallow "remote failed to report status" class is covered by the rescue-first
#        order, not by --atomic: the step-2 push is forced to fail, the old tip stays on the rescue
#        ref, a same-generation retry lands. The flat rescue name cannot collide with a plain head
#        such as `soleur` (the old `soleur/store-tip-<sha>` could).
#        The refspecs and the two argument lists are read from the production source (see
#        src_refspec below), not copied: a drift in either fails here.
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
# The probe is itself a verdict-owning helper: disarmed together with expect_eq/expect_contains (its comparison gutted, `_inst_bad`
# never set) it would leave the block above green. Feed it a DELIBERATELY WRONG expectation (a matching expect_eq moves passes by 1
# and fails by 0, so asking for 0/1 is false) and require that it flags it. Reported by printf + exit 1, not through the helpers.
_inst_bad=""
probe deliberately-wrong 0 1 expect_eq i a a
_probe_flagged="$_inst_bad"
passes=$_p0; fails=$_f0; _inst_bad=""
if [[ -z "$_probe_flagged" ]]; then
  printf '[FATAL] instrument self-test: probe accepted a deliberately wrong expectation (probe is disarmed)\n' >&2
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
# EXPLICIT ALLOWLIST (env -i): the builder above sanitizes the shell, but a command that inherits the shell would still inherit
# everything the builder does not know about (a developer's GIT_SSH, a proxy, a TERM-dependent pager...). Nothing is inherited: git
# and the bound hook see exactly the variables listed here, all taken from the builder's own exports (or fixed values).
GIT_ENV=(env -i
  "PATH=$PATH"
  "LC_ALL=C"
  "HOME=$ROOT/home"
  "GIT_CEILING_DIRECTORIES=$GIT_CEILING_DIRECTORIES"
  "GIT_CONFIG_NOSYSTEM=$GIT_CONFIG_NOSYSTEM"
  "GIT_CONFIG_GLOBAL=$GIT_CONFIG_GLOBAL"
  "GIT_ATTR_NOSYSTEM=$GIT_ATTR_NOSYSTEM"
  "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
  "GIT_TERMINAL_PROMPT=$GIT_TERMINAL_PROMPT"
  "GIT_AUTHOR_NAME=$GIT_AUTHOR_NAME" "GIT_AUTHOR_EMAIL=$GIT_AUTHOR_EMAIL"
  "GIT_COMMITTER_NAME=$GIT_COMMITTER_NAME" "GIT_COMMITTER_EMAIL=$GIT_COMMITTER_EMAIL"
  "GIT_CONFIG_COUNT=$GIT_CONFIG_COUNT" "GIT_CONFIG_KEY_0=$GIT_CONFIG_KEY_0" "GIT_CONFIG_VALUE_0=$GIT_CONFIG_VALUE_0"
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

# --- T1: the replication push (git-data-replication.ts, CTO F12 + T1b + F19..F21) --------------------------------
# What production sends, as TWO pushes from a `--depth 1` clone with push-options (both attach the lease generation and worktree id):
#   step 1 (only when a local `soleur-store-tip-*` branch exists): `push --force --atomic <store> <rescue refspec>`;
#   then the pushed local rescue branches are deleted best-effort (`update-ref -d <ref> <sha>`, F21);
#   step 2: `push --force <store> <heads refspec> <tags refspec>`, with NO --atomic (F20).
# The refspecs and both argument lists are EXTRACTED from the production source below (comment-stripped, anchored), not copied, so a
# drift in either side fails here. This suite models the git transport only: the 60 s timeouts, the single transient retry, the
# loud failure report and the success marker are pinned by test/git-data-replication.test.ts.
REPL_TS="${SCRIPT_DIR}/../server/git-data-replication.ts"
[[ -f "$REPL_TS" ]] || { echo "FATAL: production source not found at $REPL_TS" >&2; exit 2; }
src_code() { sed -E 's#^[[:space:]]*(//|\*|/\*).*$##' "$1"; }   # drops whole-line comments, so a comment cannot satisfy an extract
src_refspec() { # <file> <key> -> the template literal under `key:` with ${worktreeId} replaced by the own worktree id
  local v n
  v="$(src_code "$1" | sed -nE 's#^[[:space:]]+'"$2"': `([^`]+)`,?[[:space:]]*$#\1#p')"
  n="$(printf '%s\n' "$v" | grep -c .)"
  if [[ "$n" != 1 ]]; then echo "FATAL: expected exactly one '$2:' refspec literal in $1, found $n" >&2; exit 2; fi
  v="${v//\$\{worktreeId\}/$OWN}"
  if [[ "$v" == *'${'* ]]; then echo "FATAL: refspec '$2' still carries an unresolved template placeholder: $v" >&2; exit 2; fi
  printf '%s' "$v"
}
src_args() { # <file> <const> -> the normalized argument list of `const <name> = [ ... ];`
  src_code "$1" | tr '\n' ' ' | sed -nE 's#.*const '"$2"' = \[([^]]*)\];.*#\1#p' | tr -s ' ' | sed -E 's/, *$//; s/ +$//'
}
PUSH_HEADS="$(src_refspec "$REPL_TS" heads)"
PUSH_TAGS="$(src_refspec "$REPL_TS" tags)"
PUSH_RESCUE="$(src_refspec "$REPL_TS" rescue)"
expect_eq "T1 parity: the heads refspec is the production one" "refs/heads/*:refs/soleur/worktrees/${OWN}/heads/*" "$PUSH_HEADS"
expect_eq "T1 parity: the tags refspec is the production one" "refs/tags/*:refs/soleur/worktrees/${OWN}/tags/*" "$PUSH_TAGS"
expect_eq "T1 parity: the rescue refspec is the flat soleur-store-tip-* production one" \
  "refs/heads/soleur-store-tip-*:refs/soleur/worktrees/${OWN}/heads/soleur-store-tip-*" "$PUSH_RESCUE"
expect_eq "T1 parity: production step 2 is push --force <remote> heads tags push-options and carries NO --atomic (F20)" \
  '"push", "--force", "git-data", refspecs.heads, refspecs.tags, ...pushOptions' "$(src_args "$REPL_TS" pushArgs)"
expect_eq "T1 parity: production step 1 is push --force --atomic <remote> rescue push-options (--atomic kept on step 1)" \
  '"push", "--force", "--atomic", "git-data", refspecs.rescue, ...pushOptions' "$(src_args "$REPL_TS" rescuePushArgs)"

push_rescue() { # <clone> <lease-gen> [--no-atomic]; production step 1 (the --no-atomic arm is a CONTROL); combined output, git's rc
  local d="$1" gen="$2" atomic=(--atomic)
  [[ "${3-}" == "--no-atomic" ]] && atomic=()
  gitd "$d" push --force "${atomic[@]}" "$STORE" "$PUSH_RESCUE" \
    "--push-option=lease-gen=${gen}" "--push-option=worktree-id=${OWN}" 2>&1
}
push_main() { # <clone> <lease-gen> [--atomic]; production step 2 (the --atomic arm is a CONTROL: production carries none)
  local d="$1" gen="$2"
  shift 2
  gitd "$d" push --force "$@" "$STORE" "$PUSH_HEADS" "$PUSH_TAGS" \
    "--push-option=lease-gen=${gen}" "--push-option=worktree-id=${OWN}" 2>&1
}
rescue_listing() { # <clone> -> "<full sha> <refname>" per local rescue branch (production's listing)
  gitd "$1" for-each-ref --format='%(objectname) %(refname)' 'refs/heads/soleur-store-tip-*'
}
delete_pushed_rescue() { # <clone> -> production's best-effort compare-and-delete of each listed rescue branch
  local sha ref
  while read -r sha ref; do
    [[ -n "$ref" ]] || continue
    gitd "$1" update-ref -d "$ref" "$sha" || true
  done < <(rescue_listing "$1")
}
ref_or_empty() { # <git dir> <ref> -> the sha, or empty when the ref does not exist
  gitd "$1" rev-parse -q --verify "$2" || true
}

T1CLONE="$ROOT/t1clone"
"${GIT_ENV[@]}" git clone -q --depth 1 "file://$ORIGIN" "$T1CLONE" >/dev/null 2>&1
T1_TIP="$(commit_file "$T1CLONE" t1.txt "replicated work")"
gitd "$T1CLONE" fetch -q --depth 1 "$STORE" "$own_ref" >/dev/null 2>&1
STORE_TIP="$(gitd "$T1CLONE" rev-parse FETCH_HEAD)"
RESCUE="soleur-store-tip-${STORE_TIP:0:12}"
rescue_ref="refs/soleur/worktrees/${OWN}/heads/${RESCUE}"
soleur_head="refs/soleur/worktrees/${OWN}/heads/soleur"
gitd "$T1CLONE" branch "$RESCUE" "$STORE_TIP"
expect_eq "T1 fixture: the clone is shallow (a --depth 1 push client)" "true" "$(gitd "$T1CLONE" rev-parse --is-shallow-repository)"
expect_eq "T1 fixture: the store tip the rescue branch holds is the CH3 tip" "$STALE_TIP" "$STORE_TIP"
expect_eq "T1 fixture: the rescue name is the flat soleur-store-tip-<12 hex>" "1" \
  "$([[ "$RESCUE" =~ ^soleur-store-tip-[0-9a-f]{12}$ ]] && echo 1 || echo 0)"

# --- T1a: step 1's --atomic. A refname conflict is a rejection INSIDE the ref transaction, the one class --atomic covers. Two rescue
# branches are pushed together; a store head living UNDER the first one's path (`<rescue>/blocker`) conflicts with it.
RESCUE2="soleur-store-tip-111111111111"
rescue2_ref="refs/soleur/worktrees/${OWN}/heads/${RESCUE2}"
gitd "$T1CLONE" branch "$RESCUE2" "$T1_TIP"
gitd "$STORE" update-ref "${rescue_ref}/blocker" "$STORE_TIP"
out="$(push_rescue "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1a (atomic step 1, one rescue ref rejected)"
expect_eq "T1a step 1 (--atomic) with one rescue ref rejected fails (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_eq "T1a step 1 (--atomic): the OTHER rescue ref did not land either (all-or-nothing)" "" "$(ref_or_empty "$STORE" "$rescue2_ref")"
expect_eq "T1a step 1 (--atomic): the rejected rescue ref was not created" "" "$(ref_or_empty "$STORE" "$rescue_ref")"
expect_eq "T1a step 1: store main is untouched (the old store tip stays referenced)" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
# Control: the SAME push without --atomic lets the non-conflicting rescue ref land; it proves the all-or-nothing rows above can fail.
out="$(push_rescue "$T1CLONE" 3 --no-atomic)"; rc=$?
confined_or_stop "T1a (non-atomic control)"
expect_eq "T1a control: without --atomic the push still reports the rejection (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_eq "T1a control: without --atomic the non-conflicting rescue ref lands (what --atomic on step 1 prevents)" \
  "$T1_TIP" "$(ref_or_empty "$STORE" "$rescue2_ref")"
gitd "$STORE" update-ref -d "$rescue2_ref"
gitd "$STORE" update-ref -d "${rescue_ref}/blocker"
gitd "$T1CLONE" branch -q -D "$RESCUE2"

# --- T1c: the happy two-step, and the post-push local cleanup (F21). A store head named `soleur` (the old slash name's collision)
# does not block the flat rescue name.
gitd "$STORE" update-ref "$soleur_head" "$STORE_TIP"
expect_eq "T1c: exactly one local rescue branch is listed before step 1" "1" "$(rescue_listing "$T1CLONE" | grep -c .)"
out="$(push_rescue "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1c (step 1)"
expect_eq "T1c step 1: a --depth 1 push of the rescue ref with push-options beside a store head named soleur is ACCEPTED (rc=0)" "0" "$rc"
expect_eq "T1c step 1: the rescue ref holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"
expect_eq "T1c step 1: store main is untouched by the rescue-only push" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
# F21: after the CONFIRMED step 1 the pushed local rescue branches are deleted, compare-and-delete on the listed sha.
gitd "$T1CLONE" branch "$RESCUE2" "$T1_TIP"
gitd "$T1CLONE" update-ref -d "refs/heads/${RESCUE2}" "$STORE_TIP" >/dev/null 2>&1; cas_rc=$?
expect_eq "T1c F21 compare-and-delete: a delete with a stale expected sha FAILS (rc!=0)" "1" "$([[ $cas_rc -ne 0 ]] && echo 1 || echo 0)"
expect_eq "T1c F21 compare-and-delete: ... and leaves a branch that moved since the listing alone" "$T1_TIP" "$(ref_or_empty "$T1CLONE" "refs/heads/${RESCUE2}")"
gitd "$T1CLONE" update-ref -d "refs/heads/${RESCUE2}" "$T1_TIP"
delete_pushed_rescue "$T1CLONE"
expect_eq "T1c F21: the pushed local rescue branch is gone after step 1" "" "$(ref_or_empty "$T1CLONE" "refs/heads/${RESCUE}")"
expect_eq "T1c F21: the store copy of the rescue head REMAINS (it persists, no prune)" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"
expect_eq "T1c F21: the next session lists no local rescue branch, so step 1 is not issued again" "0" "$(rescue_listing "$T1CLONE" | grep -c .)"
out="$(push_main "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1c (step 2)"
expect_eq "T1c step 2: the non-atomic main push is ACCEPTED (rc=0)" "0" "$rc"
expect_eq "T1c step 2: store main advanced to the clone's tip" "$T1_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1c step 2: the rescue ref still holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"
expect_eq "T1c step 2: the store head named soleur is untouched" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$soleur_head")"
expect_eq "T1c step 2: no second rescue ref appeared (the deleted local branch is not re-carried)" "1" \
  "$(gitd "$STORE" for-each-ref --format='%(refname)' "refs/soleur/worktrees/${OWN}/heads/soleur-store-tip-*" | grep -c .)"

# --- T1d (CTO F20): step 2 is NOT atomic. A stale store head `fix/x` plus a later local branch `fix` refname-conflict. Without --atomic
# `main` lands and only `fix` is rejected; git exits non-zero, which production reports loudly (`git-data replication push failed`, no
# retry, no success marker). The --atomic arm below is the CONTROL: the shape of the defect the ruling removed (main never lands).
gitd "$STORE" update-ref "$own_ref" "$STORE_TIP"
fix_head="refs/soleur/worktrees/${OWN}/heads/fix"
gitd "$STORE" update-ref "${fix_head}/x" "$STORE_TIP"
gitd "$T1CLONE" branch fix "$T1_TIP"
out="$(push_main "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1d (step 2, partial rejection)"
expect_eq "T1d step 2 (no --atomic): a partial rejection exits non-zero (production's loud failure path)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_eq "T1d step 2 (no --atomic): main LANDED despite the rejected fix ref" "$T1_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1d step 2 (no --atomic): the conflicting fix head was not created" "" "$(ref_or_empty "$STORE" "$fix_head")"
expect_eq "T1d step 2 (no --atomic): the stale store head fix/x is untouched" "$STORE_TIP" "$(gitd "$STORE" rev-parse "${fix_head}/x")"
gitd "$STORE" update-ref "$own_ref" "$STORE_TIP"
out="$(push_main "$T1CLONE" 3 --atomic)"; rc=$?
confined_or_stop "T1d (atomic control)"
expect_eq "T1d control (--atomic on step 2): the same push fails (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_eq "T1d control (--atomic on step 2): main NEVER lands while the stale head blocks (the defect F20 removed)" \
  "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
gitd "$STORE" update-ref -d "${fix_head}/x"
gitd "$T1CLONE" branch -q -D fix

# --- T1b: rescue-ref-first, then the rest (the transient "failed to report status" class) ----------------------------
# The shallow-clone transient class can fail the SECOND push for a reason outside the ref transaction, so production pushes the rescue
# ref ALONE first. Reset the store to the pre-replication state, push the rescue ref only (step 1), then FORCE step 2 to fail with a
# store-side `update` hook (a flag file arms it; the bound pre-receive hook is untouched), and require that the old tip stays
# referenced. The forced failure rejects `main` whether or not step 2 carries --atomic, so this row does not pin --atomic (T1a and
# T1d do); it pins the ORDER: the old tip is in the store before main is touched.
gitd "$STORE" update-ref "$own_ref" "$STORE_TIP"
gitd "$STORE" update-ref -d "$rescue_ref"
gitd "$STORE" update-ref -d "$soleur_head"
gitd "$T1CLONE" branch "$RESCUE" "$STORE_TIP"
FAIL_MAIN="$ROOT/fail-main-flag"
HOOK_UPDATE="$STORE/hooks/update"
assert_fixture_dir "$FAIL_MAIN"
assert_fixture_dir "$HOOK_UPDATE"
printf '#!/bin/sh\n[ -e "%s" ] && case "$1" in */heads/main) echo "forced failure of the main update" >&2; exit 1;; esac\nexit 0\n' "$FAIL_MAIN" >"$HOOK_UPDATE"
chmod 0755 "$HOOK_UPDATE"
out="$(push_rescue "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1b (rescue-first push)"
expect_eq "T1b step 1: the rescue ref alone, from a --depth 1 clone with push-options, lands (rc=0)" "0" "$rc"
expect_eq "T1b step 1: the rescue ref holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"
expect_eq "T1b step 1: store main is untouched by the rescue-only push" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
delete_pushed_rescue "$T1CLONE"
: >"$FAIL_MAIN"
out="$(push_main "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1b (second push forced to fail)"
expect_eq "T1b step 2: the forced failure rejects the second push (rc!=0)" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
expect_contains "T1b step 2: the failure is the forced one" "forced failure of the main update" "$out"
expect_eq "T1b step 2: store main is unchanged" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1b step 2: the old store tip is still referenced from a soleur-store-tip-* ref" "$rescue_ref" \
  "$(gitd "$STORE" for-each-ref --contains "$STORE_TIP" --format='%(refname)' "refs/soleur/worktrees/${OWN}/heads/soleur-store-tip-*")"
expect_eq "T1b step 2: the old store tip is still reachable (commit object present)" "0" "$(gitd "$STORE" cat-file -e "${STORE_TIP}^{commit}" 2>/dev/null; echo $?)"
rm -f "$FAIL_MAIN"
out="$(push_main "$T1CLONE" 3)"; rc=$?
confined_or_stop "T1b (retry at the same generation)"
expect_eq "T1b retry: the second push at the SAME generation succeeds (rc=0)" "0" "$rc"
expect_eq "T1b retry: store main advanced to the clone's tip" "$T1_TIP" "$(gitd "$STORE" rev-parse "$own_ref")"
expect_eq "T1b retry: the rescue ref still holds the old store tip" "$STORE_TIP" "$(gitd "$STORE" rev-parse "$rescue_ref")"

# --- the bound hook was never modified by this suite ----------------------------------------------
expect_eq "bound hook digest unchanged by the run" "$HOOK_SHA_BEFORE" "$(sha256sum "$HOOK_SRC" | cut -d' ' -f1)"

total=$((passes + fails))
MIN_ASSERTIONS=69
if [[ "$total" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: ran only %s assertions (<%s) - the suite did not execute fully\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
echo "git-data-stale-clone-push: ${passes} passed, ${fails} failed (${total} assertions)"
[[ "$fails" -eq 0 ]]
