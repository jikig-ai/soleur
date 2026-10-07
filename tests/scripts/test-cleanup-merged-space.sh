#!/usr/bin/env bash
# test-cleanup-merged-space.sh — #9677: the opt-in Docker builder-cache prune, the
# effective-space report (SOLEUR_CLEANUP_SPACE), and the cleanup-merged wrapper that places
# both after the cleanup lock is released (worktree-manager.sh).
#
# Every external is a PATH shim (docker, findmnt, df, snapper; the real timeout is used); nothing outside
# TESTROOT is touched. Fixtures are synthesized (cq-test-fixtures-synthesized-only).
#
# MUTATION ROWS this suite must redden (checked by hand when the suite is edited):
#   M1 make docker_builder_prune `return 1` on timeout AND drop the wrapper's `|| warn` -> W3 reddens (set -e)
#   M2 add `--all` to the image prune call                      -> D2 reddens
#   M3 print the Docker marker when the opt-in is unset         -> D1 reddens
#   M4 call `snapper` for the snapshot hint                     -> S4 reddens
#   M5 run Docker before the cleanup lock is released           -> W5 reddens
#   M6 drop `space_begin`, or take it after the inner function  -> W6a / W7a redden
#   M7 swap the builder/images labels, or drop the remote-daemon refusal -> D7 / D8 redden
#   M8 treat only rc 124 (not 137) as a timeout                 -> D9 reddens
#   M9 point the cleanup-merged dispatch at the bare inner function -> W7c reddens
#
# AUTHORING CONSTRAINTS (work/SKILL.md): never `producer | grep -q` under pipefail — grep a
# FILE; `cases` increments at the CALL SITE; deliberately-nonzero commands in `$(...)` need
# `|| true`.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

pass_n=0; fails=0; cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t cleanup-merged-space.XXXXXXXX)"
# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# it); do not reword.
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
cleanup() { assert_fixture_dir "$TESTROOT"; rm -rf "$TESTROOT"; }
trap cleanup EXIT

[[ -f "$WM" ]] || { echo "ERROR: worktree-manager.sh missing at $WM" >&2; exit 1; }

# --- shims -------------------------------------------------------------------------
SHIMS="$TESTROOT/shims"; CALLS="$TESTROOT/docker-calls.log"; SNAPPER_CALLS="$TESTROOT/snapper-calls.log"
DFSTATE="$TESTROOT/df-state"
mkdir -p "$SHIMS"

cat > "$SHIMS/docker" <<'STUB'
#!/usr/bin/env bash
# Replays the real CLI's output SHAPES: `builder prune` ends `Total:  <size>`, `image prune`
# prints `Total reclaimed space: <size>`. Anything outside the contract exits 64 AND is logged.
printf '%s\n' "$*" >> "${DOCKER_CALLS:?}"
case "$1 ${2-}" in
  "info "*)         [[ -n "${FAKE_DOCKER_INFO_FAIL:-}" ]] && exit 1; exit 0 ;;
  "system df"*)     [[ -n "${FAKE_DOCKER_DF_FAIL:-}" ]] && exit 3; echo "TYPE  TOTAL  ACTIVE  SIZE  RECLAIMABLE"; echo "Build Cache  3  0  1.2GB  1.2GB"; exit 0 ;;
  "builder prune")  # an ignored TERM survives exec, so `timeout -k` must escalate to KILL (rc 137)
                    [[ -n "${FAKE_DOCKER_IGNORE_TERM:-}" ]] && { trap '' TERM; exec sleep 30; }
                    [[ -n "${FAKE_DOCKER_SLEEP:-}" ]] && sleep "$FAKE_DOCKER_SLEEP"
                    echo "Deleted build cache objects:"; echo "abc123"; echo "Total:  1.2GB"; exit 0 ;;
  "image prune")    echo "Total reclaimed space: 300MB"; exit 0 ;;
  *)                exit 64 ;;
esac
STUB
cat > "$SHIMS/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FINDMNT_ARGV:-/dev/null}"
[[ -n "${FAKE_FSTYPE:-}" ]] || exit 1
printf '%s\n' "$FAKE_FSTYPE"
STUB
cat > "$SHIMS/snapper" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SNAPPER_CALLS:?}"
exit 0
STUB
# df shim: a stateful counter so the 2nd call (the AFTER reading) differs from the 1st.
# POSIX `df -Pk <path>` shape: header + one row; column 4 is Available (KB).
cat > "$SHIMS/df" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DF_ARGV:-/dev/null}"
n=$(cat "${DF_STATE:?}" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$DF_STATE"
IFS=' ' read -r first second <<<"${FAKE_DF_AVAIL_KB:-1000 1500}"
avail="$first"; [[ "$n" -ge 2 ]] && avail="$second"
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/fake 4000 $((4000 - avail)) $avail 50% /"
STUB
chmod +x "$SHIMS"/*

# A PATH with the real tools the script needs but WITHOUT timeout/gtimeout (for the
# no-timeout arm): symlinks to an explicit allowlist of binaries.
MINBIN="$TESTROOT/minbin"; mkdir -p "$MINBIN"
for b in bash env sh awk sed grep tr date id mkdir rm cat head tail sort wc find stat basename dirname mktemp printf sleep uname ls cp mv tee cut expr readlink flock git; do
  p="$(command -v "$b" 2>/dev/null || true)"; [[ -n "$p" && -x "$p" ]] && ln -sf "$p" "$MINBIN/$b"
done

mkdir -p "$TESTROOT/space-path" "$TESTROOT/state" "$TESTROOT/snapper-conf"

# run <env assignments...> -- <bash snippet>: runs the snippet in a clean env with the script
# sourced (its main is guarded), shims first on PATH.
run() {
  local -a envs=(); while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
  : > "$CALLS"; : > "$SNAPPER_CALLS"; : > "$TESTROOT/df.argv"; : > "$TESTROOT/findmnt.argv"; rm -f "$DFSTATE"
  env -i PATH="${RUN_PATH:-$SHIMS:$PATH}" HOME="$TESTROOT" XDG_STATE_HOME="$TESTROOT/state" \
    DOCKER_CALLS="$CALLS" SNAPPER_CALLS="$SNAPPER_CALLS" DF_STATE="$DFSTATE" \
    DF_ARGV="$TESTROOT/df.argv" FINDMNT_ARGV="$TESTROOT/findmnt.argv" \
    SOLEUR_SPACE_PATH="$TESTROOT/space-path" SOLEUR_SNAPPER_CONFIG_DIR="$TESTROOT/snapper-conf" \
    "${envs[@]}" bash -c "source '$WM' >/dev/null 2>&1 || true; $1" 2>&1 || true
}
calls_file_has() { grep -qE -- "$1" "$CALLS"; }
calls_count() { grep -c . "$CALLS" || true; }

echo "=== test-cleanup-merged-space ==="

# --- D: docker_builder_prune ------------------------------------------------------
# D1 unset -> nothing runs, nothing prints.
out="$(run -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
cases=$((cases + 1)); [[ "$(calls_count)" == "0" && "$out" != *SOLEUR_DOCKER_PRUNE* ]] \
  && pass "D1 opt-in unset: no docker call, no marker" || fail "D1: calls=$(calls_count) out=$out"

# D2 =apply with a worktree removed: EXACTLY the three contract calls, none of the forbidden ones.
out="$(run SOLEUR_DOCKER_PRUNE=apply -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
cases=$((cases + 1)); [[ "$(calls_count)" == "3" ]] && calls_file_has '^info$' \
  && calls_file_has '^builder prune -f --filter until=24h$' && calls_file_has '^image prune -f --filter until=24h$' \
  && pass "D2a apply: info + builder prune + image prune, each with until=24h" || fail "D2a calls: $(cat "$CALLS") out=$out"
cases=$((cases + 1)); ! calls_file_has '(volume|container|system prune|--all| -a( |$)|^image prune -a)' \
  && pass "D2b apply: never volume/container/system prune/-a/--all" || fail "D2b forbidden call: $(cat "$CALLS")"
cases=$((cases + 1)); [[ "$out" == *"SOLEUR_DOCKER_PRUNE mode=apply"* ]] \
  && pass "D2c apply marker names the mode" || fail "D2c marker: $out"

# D3 =1 is a dry run: read-only calls only, labelled an upper bound.
out="$(run SOLEUR_DOCKER_PRUNE=1 -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
cases=$((cases + 1)); ! calls_file_has 'prune' && calls_file_has '^system df' \
  && pass "D3a =1: reads only (system df), no prune" || fail "D3a calls: $(cat "$CALLS")"
cases=$((cases + 1)); [[ "$out" == *"mode=dry-run"* && "$out" == *"upper bound"* && "$out" == *'build_cache="Build Cache  3  0  1.2GB  1.2GB"'* ]] \
  && pass "D3b =1: dry-run marker labelled an upper bound, carrying the build-cache row in its field" || fail "D3b marker: $out"

# D3c a failing `system df` is a named skip, not a silent build_cache=unknown.
out="$(run SOLEUR_DOCKER_PRUNE=1 FAKE_DOCKER_DF_FAIL=1 -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
cases=$((cases + 1)); [[ "$out" == *"skipped reason=df-failed rc=3"* && "$out" != *"mode=dry-run"* ]] \
  && pass "D3c a failing system df -> skipped reason=df-failed rc=3" || fail "D3c: $out"

# D4 unrecognised values never run docker.
for v in yes true 0 Apply; do
  out="$(run SOLEUR_DOCKER_PRUNE="$v" -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
  cases=$((cases + 1)); [[ "$(calls_count)" == "0" && "$out" == *"skipped reason=invalid-value"* ]] \
    && pass "D4 value '$v' -> invalid-value, no docker call" || fail "D4 '$v': calls=$(calls_count) out=$out"
done

# D5 clean skips with a named reason; the run still exits 0 (the helper returns 0).
out="$(RUN_PATH="$MINBIN" run SOLEUR_DOCKER_PRUNE=apply -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune; echo RC=$?')"
cases=$((cases + 1)); [[ "$out" == *"reason=docker-missing"* && "$out" == *"RC=0"* ]] \
  && pass "D5a no docker on PATH -> docker-missing, rc 0" || fail "D5a: $out"
out="$(run SOLEUR_DOCKER_PRUNE=apply FAKE_DOCKER_INFO_FAIL=1 -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune; echo RC=$?')"
cases=$((cases + 1)); [[ "$out" == *"reason=daemon-unreachable"* && "$out" == *"RC=0"* ]] && ! calls_file_has 'prune' \
  && pass "D5b daemon down -> daemon-unreachable, no prune, rc 0" || fail "D5b: $out calls=$(cat "$CALLS")"
# no timeout/gtimeout: a MINBIN that carries docker but neither timeout binary.
ln -sf "$SHIMS/docker" "$MINBIN/docker"
out="$(RUN_PATH="$MINBIN" run SOLEUR_DOCKER_PRUNE=apply -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune; echo RC=$?')"
cases=$((cases + 1)); [[ "$out" == *"reason=no-timeout"* && "$out" == *"RC=0"* ]] \
  && pass "D5c no timeout/gtimeout -> no-timeout (never a misleading daemon-unreachable)" || fail "D5c: $out"
rm -f "$MINBIN/docker"
out="$(run SOLEUR_DOCKER_PRUNE=apply FAKE_DOCKER_SLEEP=3 SOLEUR_DOCKER_TIMEOUT_S=1 -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune; echo RC=$?')"
cases=$((cases + 1)); [[ "$out" == *"reason=timeout"* && "$out" == *"RC=0"* ]] \
  && pass "D5-timeout a prune past the bound -> reason=timeout, rc 0" || fail "D5-timeout: $out"

# D6 opted in but nothing was removed -> named skip, never silent.
out="$(run SOLEUR_DOCKER_PRUNE=apply -- '_SOLEUR_CLEANED_COUNT=0; docker_builder_prune')"
cases=$((cases + 1)); [[ "$out" == *"reason=no-worktree-removed"* && "$(calls_count)" == "0" ]] \
  && pass "D6 opted in, no worktree removed -> no-worktree-removed" || fail "D6: $out"

# D7 Docker's own totals are echoed verbatim, never parsed.
out="$(run SOLEUR_DOCKER_PRUNE=apply -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
cases=$((cases + 1)); [[ "$out" == *'builder="Total:  1.2GB"'* && "$out" == *'images="Total reclaimed space: 300MB"'* ]] \
  && pass "D7 each docker total line appears verbatim in ITS OWN labelled field (builder/images not swapped)" || fail "D7: $out"

# D8 a remote daemon is never pruned; a local unix:// socket is.
for h in tcp://10.0.0.5:2375 ssh://ops@build-host; do
  out="$(run SOLEUR_DOCKER_PRUNE=apply DOCKER_HOST="$h" -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
  cases=$((cases + 1)); [[ "$(calls_count)" == "0" && "$out" == *"skipped reason=remote-daemon"* ]] \
    && pass "D8 DOCKER_HOST=$h -> remote-daemon, no docker call" || fail "D8 '$h': calls=$(calls_count) out=$out"
done
out="$(run SOLEUR_DOCKER_PRUNE=apply DOCKER_HOST=unix:///var/run/docker.sock -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune')"
cases=$((cases + 1)); [[ "$(calls_count)" == "3" ]] \
  && pass "D8b a local unix:// DOCKER_HOST still prunes" || fail "D8b: calls=$(calls_count) out=$out"

# D9 a Docker CLI that ignores TERM is escalated to KILL by `timeout -k` (rc 137), and 137 must read
# as a timeout, not as a failed prune with a bare number.
out="$(run SOLEUR_DOCKER_PRUNE=apply FAKE_DOCKER_IGNORE_TERM=1 SOLEUR_DOCKER_TIMEOUT_S=1 -- '_SOLEUR_CLEANED_COUNT=1; docker_builder_prune; echo RC=$?')"
cases=$((cases + 1)); [[ "$out" == *"reason=timeout"* && "$out" != *"prune-failed"* && "$out" == *"RC=0"* ]] \
  && pass "D9 a prune that ignores TERM (killed, rc 137) is reported as a timeout" || fail "D9: $out"

# --- S: report_cleanup_space ----------------------------------------------------------
# S1 signed delta + logical bytes.
out="$(run FAKE_DF_AVAIL_KB='1000 1500' FAKE_FSTYPE=ext4 -- '_SPACE_BEFORE_KB=; space_begin; _SPACE_LOGICAL_BYTES=4096; report_cleanup_space')"
cases=$((cases + 1)); [[ "$out" == *"SOLEUR_CLEANUP_SPACE"* && "$out" == *"logical_bytes=4096"* && "$out" == *"df_delta_bytes=512000"* ]] \
  && pass "S1 logical bytes beside the measured df delta (500 KB freed)" || fail "S1: $out"
cases=$((cases + 1)); [[ "$(grep -c . "$TESTROOT/df.argv" || true)" == "2" ]] \
  && [[ "$(sort -u "$TESTROOT/df.argv")" == "-Pk $TESTROOT/space-path" ]] \
  && grep -qx -- "-no FSTYPE --target $TESTROOT/space-path" "$TESTROOT/findmnt.argv" \
  && pass "S1b df and findmnt are asked about the configured space path, with the portable flags" \
  || fail "S1b argv: df=[$(cat "$TESTROOT/df.argv")] findmnt=[$(cat "$TESTROOT/findmnt.argv")]"
# S2 a negative delta prints as is.
out="$(run FAKE_DF_AVAIL_KB='1500 1000' FAKE_FSTYPE=ext4 -- 'space_begin; _SPACE_LOGICAL_BYTES=10; report_cleanup_space')"
cases=$((cases + 1)); [[ "$out" == *"df_delta_bytes=-512000"* ]] \
  && pass "S2 negative delta is printed signed" || fail "S2: $out"
# S3 btrfs + snapper config -> pinning hint; ext4 -> none; no findmnt -> unknown.
: > "$TESTROOT/snapper-conf/root"
out="$(run FAKE_FSTYPE=btrfs -- 'space_begin; report_cleanup_space')"
cases=$((cases + 1)); [[ "$out" == *"fstype=btrfs"* && "$out" == *"snapshots=snapper"* && "$out" == *"snapper snapshots"* && "$out" == *"never deletes snapshots"* ]] \
  && pass "S3a btrfs + snapper config -> snapshots=snapper and the pinning hint" || fail "S3a: $out"
out="$(run FAKE_FSTYPE=ext4 -- 'space_begin; report_cleanup_space')"
cases=$((cases + 1)); [[ "$out" == *"snapshots=none"* && "$out" != *"never deletes snapshots"* ]] \
  && pass "S3b ext4 -> snapshots=none, no hint" || fail "S3b: $out"
out="$(run -- 'space_begin; report_cleanup_space')"
cases=$((cases + 1)); [[ "$out" == *"fstype=unknown"* && "$out" == *"snapshots=unknown"* ]] \
  && pass "S3c no findmnt output -> unknown, never a guess" || fail "S3c: $out"
rm -f "$TESTROOT/snapper-conf/root"
out="$(run FAKE_FSTYPE=btrfs -- 'space_begin; report_cleanup_space')"
cases=$((cases + 1)); [[ "$out" == *"snapshots=none"* ]] \
  && pass "S3d btrfs without a snapper config -> snapshots=none" || fail "S3d: $out"
# S4 never invokes snapper.
: > "$TESTROOT/snapper-conf/root"
out="$(run FAKE_FSTYPE=btrfs -- 'space_begin; report_cleanup_space')"
cases=$((cases + 1)); [[ ! -s "$SNAPPER_CALLS" ]] \
  && pass "S4 the snapper binary is never executed" || fail "S4 snapper called: $(cat "$SNAPPER_CALLS")"

# S5 space-report is read-only and has no baseline.
before="$(find "$TESTROOT/space-path" "$TESTROOT/state" -type f 2>/dev/null | sort | tr '\n' ' ')"
out="$(env -i PATH="$SHIMS:$PATH" HOME="$TESTROOT" XDG_STATE_HOME="$TESTROOT/state" DOCKER_CALLS="$CALLS" DF_STATE="$DFSTATE" \
  SOLEUR_SPACE_PATH="$TESTROOT/space-path" SOLEUR_SNAPPER_CONFIG_DIR="$TESTROOT/snapper-conf" FAKE_FSTYPE=btrfs \
  bash "$WM" space-report 2>&1 || true)"
after="$(find "$TESTROOT/space-path" "$TESTROOT/state" -type f 2>/dev/null | sort | tr '\n' ' ')"
cases=$((cases + 1)); [[ "$out" == *"SOLEUR_CLEANUP_SPACE"* && "$out" == *"logical_bytes=-"* && "$out" == *"df_delta_bytes=-"* ]] \
  && pass "S5a space-report prints the marker with no baseline ('-')" || fail "S5a: $out"
cases=$((cases + 1)); [[ "$before" == "$after" ]] \
  && pass "S5b space-report writes no files" || fail "S5b tree changed: [$before] -> [$after]"

# --- W: the wrapper (placement: after the cleanup lock, guarded, printed on early returns) ----
# W1 the inner function returns early (lock contended) -> the space line still prints once.
out="$(run -- 'cleanup_merged_worktrees() { echo INNER-EARLY-RETURN; return 0; }; cleanup_merged_run; echo RC=$?')"
cases=$((cases + 1)); n="$(printf '%s\n' "$out" | grep -c 'SOLEUR_CLEANUP_SPACE' || true)"
[[ "$n" == "1" && "$out" == *"RC=0"* ]] \
  && pass "W1 early inner return -> exactly one SOLEUR_CLEANUP_SPACE, rc preserved" || fail "W1 n=$n out=$out"
# W2 an inner FAILURE aborts under set -e exactly as the bare dispatch did: nothing after it runs.
out="$(run -- 'cleanup_merged_worktrees() { return 7; }; cleanup_merged_run; echo AFTER-INNER-FAILURE')"
cases=$((cases + 1)); [[ "$out" != *"AFTER-INNER-FAILURE"* && "$out" != *"SOLEUR_CLEANUP_SPACE"* ]] \
  && pass "W2 an inner failure aborts under set -e (errexit semantics preserved, report skipped)" || fail "W2: $out"
# W3 a failing Docker step does not abort the report (guarded).
out="$(run SOLEUR_DOCKER_PRUNE=apply FAKE_DOCKER_SLEEP=3 SOLEUR_DOCKER_TIMEOUT_S=1 -- 'set -euo pipefail; cleanup_merged_worktrees() { _SOLEUR_CLEANED_COUNT=1; return 0; }; cleanup_merged_run; echo RC=$?')"
cases=$((cases + 1)); [[ "$out" == *"reason=timeout"* && "$out" == *"SOLEUR_CLEANUP_SPACE"* && "$out" == *"RC=0"* ]] \
  && pass "W3 a timed-out Docker prune under set -euo pipefail still prints the report, rc 0" || fail "W3: $out"
# W4 Docker runs when the inner removed a worktree, and not otherwise.
out="$(run SOLEUR_DOCKER_PRUNE=apply -- 'cleanup_merged_worktrees() { _SOLEUR_CLEANED_COUNT=2; return 0; }; cleanup_merged_run')"
cases=$((cases + 1)); calls_file_has '^builder prune' && pass "W4a wrapper prunes after a removal" || fail "W4a: $(cat "$CALLS")"
out="$(run SOLEUR_DOCKER_PRUNE=apply -- 'cleanup_merged_worktrees() { return 0; }; cleanup_merged_run')"
cases=$((cases + 1)); [[ "$(calls_count)" == "0" && "$out" == *"no-worktree-removed"* ]] \
  && pass "W4b wrapper skips Docker when nothing was removed, and says so" || fail "W4b: $out calls=$(cat "$CALLS")"
# W5 Docker runs only after the inner function has returned (the cleanup lock is released by
# its RETURN trap): the inner echoes a sentinel, the docker shim's first call must come later.
out="$(run SOLEUR_DOCKER_PRUNE=apply -- 'cleanup_merged_worktrees() { _SOLEUR_CLEANED_COUNT=1; echo INNER-DONE; return 0; }; cleanup_merged_run')"
cases=$((cases + 1)); a="$(printf '%s\n' "$out" | grep -n 'INNER-DONE' | head -1 | cut -d: -f1)"; b="$(printf '%s\n' "$out" | grep -n 'SOLEUR_DOCKER_PRUNE' | head -1 | cut -d: -f1)"
[[ -n "$a" && -n "$b" && "$a" -lt "$b" ]] \
  && pass "W5 the Docker marker prints after the inner (lock-holding) function finished" || fail "W5 order a=$a b=$b: $out"

# W6 the wrapper's wiring, driven with the REAL helpers: the inner stub plays a drain that freed bytes
# (it sets the accumulator and the removal count the way the real function does). The baseline must
# be taken BEFORE it (else the delta reads '-'), must not be taken AFTER it (else the accumulator is
# reset to 0), and a stale removal count from an earlier run must not arm Docker.
out="$(run FAKE_DF_AVAIL_KB='1000 1500' FAKE_FSTYPE=ext4 SOLEUR_DOCKER_PRUNE=1 -- 'cleanup_merged_worktrees() { _SPACE_LOGICAL_BYTES=777; _SOLEUR_CLEANED_COUNT=1; return 0; }; cleanup_merged_run')"
cases=$((cases + 1)); [[ "$out" == *"logical_bytes=777"* && "$out" == *"df_delta_bytes=512000"* ]] \
  && pass "W6a the baseline is taken before the inner function: bytes kept, df delta measured" || fail "W6a: $out"
d="$(printf '%s\n' "$out" | grep -n 'SOLEUR_DOCKER_PRUNE' | head -n 1 | cut -d: -f1)"; r="$(printf '%s\n' "$out" | grep -n 'SOLEUR_CLEANUP_SPACE logical' | head -n 1 | cut -d: -f1)"
cases=$((cases + 1)); [[ -n "$d" && -n "$r" && "$d" -lt "$r" ]] \
  && pass "W6b the Docker marker precedes the space report (the report names the Docker outcome)" || fail "W6b order d=$d r=$r: $out"
out="$(run SOLEUR_DOCKER_PRUNE=apply -- '_SOLEUR_CLEANED_COUNT=5; cleanup_merged_worktrees() { return 0; }; cleanup_merged_run')"
cases=$((cases + 1)); [[ "$(calls_count)" == "0" && "$out" == *"no-worktree-removed"* ]] \
  && pass "W6c a stale removal count from before the run does not arm Docker" || fail "W6c: $out calls=$(cat "$CALLS")"

# W7 wiring that no behavioural stub can see — the real inner function and the real dispatch — pinned
# on the comment-stripped SOURCE, anchored on the statement form.
fn_body() { awk -v n="$1" '$0 ~ "^" n "\\(\\) \\{" {f=1} f {print} f && /^}/ {exit}' "$WM" | sed 's/^[[:space:]]*#.*$//'; }
order="$(fn_body cleanup_merged_run | grep -oE '^[[:space:]]*(space_begin|cleanup_merged_worktrees|docker_builder_prune|report_cleanup_space)' | tr -d ' \t' | tr '\n' ',')"
cases=$((cases + 1)); [[ "$order" == "space_begin,cleanup_merged_worktrees,docker_builder_prune,report_cleanup_space," ]] \
  && pass "W7a the wrapper runs baseline, inner, Docker, report — each exactly once, in that order" || fail "W7a order: $order"
cases=$((cases + 1)); [[ "$(fn_body cleanup_merged_worktrees | grep -cE '^[[:space:]]*_SOLEUR_CLEANED_COUNT=\$\{#cleaned\[@\]\}$')" == "1" ]] \
  && pass "W7b the real inner function publishes its removal count to the wrapper (the Docker gate's only input)" || fail "W7b: removal-count assignment missing or duplicated"
arm="$(awk '/^[[:space:]]*cleanup-merged\)$/ {getline nxt; sub(/^[[:space:]]+/, "", nxt); print nxt}' "$WM" | tr '\n' ',')"
cases=$((cases + 1)); [[ "$arm" == "cleanup_merged_run," ]] \
  && pass "W7c the cleanup-merged subcommand dispatches to the wrapper, not the bare inner function" || fail "W7c dispatch arm: $arm"

echo ""
echo "test-cleanup-merged-space: $pass_n passed, $fails failed ($cases cases)"
# Instrument check: the suite must have executed its assertions.
[[ "$cases" -ge 43 ]] || { echo "FAIL: only $cases cases executed (floor 43)" >&2; exit 1; }
[[ $((pass_n + fails)) -eq "$cases" ]] || { echo "FAIL: pass+fail ($((pass_n + fails))) != cases ($cases) — a verdict was lost" >&2; exit 1; }
exit $(( fails > 0 ? 1 : 0 ))
