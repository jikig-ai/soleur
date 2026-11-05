#!/usr/bin/env bash
# `constraint-scaffold.sh --refresh-stage-a` (ADR-071 amendment 2026-11-05, tracker #12146).
#
# The mode re-emits exactly one file, apps/web-platform/.github/workflows/fix-constraints-stage-a.yml,
# and only when the existing bytes are an exact, ledger-listed historical emission of the template
# (references/fix-constraints-stage-a.emitted.sha256). Anything else is refused with exit 75 and the
# file is left byte-identical. This suite drives the mode through twelve cases against hermetic
# `git init` fixtures (CONSTRAINT_SCAFFOLD_REPO_ROOT); the real apps/web-platform tree is never touched.
# A case that varies the ledger or the template runs a per-case SANDBOX COPY of scripts/ and
# references/ (the script derives REF_DIR from its own location, so the repo-root override alone
# cannot move the ledger).
#
# Runs in the scripts shard (scripts/test-all.sh globs plugins/soleur/skills/*/test/*.test.sh).
# Accumulate-then-exit; every command substitution that can fail is guarded so `set -e` cannot
# abort before a verdict is recorded. Portable to bash 3.2 / BSD userland: no mapfile, no stat,
# no realpath, no \b.
set -euo pipefail
# A self-invoked suite builds sandboxes under TMPDIR; default it to the roomy tmpfs-free path.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SKILL="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold"
REAL_SCRIPTS="$SKILL/scripts"
REAL_REFS="$SKILL/references"
OLD_FIXTURE="$SKILL/test/fixtures/stage-a.v1.0.236.emitted"
FIX_A_REL="apps/web-platform/.github/workflows/fix-constraints-stage-a.yml"
WF_DIR_REL="apps/web-platform/.github/workflows"

passes=0
fails=0
# The INDEPENDENT row counter (ADR-193 #2): incremented at every call site, never inside
# pass()/fail(), so a stubbed fail() drops a verdict without dropping its count.
cases=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }
# Instrument self-test (direction, not only presence). Reported with printf >&2 + exit 1.
fail "instrument self-test (expected — proves fail() records a FAILURE)" >/dev/null
pass "instrument self-test (expected — proves pass() records a PASS)" >/dev/null
if [[ "$fails" != "1" || "$passes" != "1" ]]; then
  printf '[FATAL] HELPER CONTROL BROKEN: after one fail() and one pass(), fails=%s passes=%s (want 1/1)\n' "$fails" "$passes" >&2
  exit 1
fi
passes=0; fails=0

# Verdict helpers. chk records one row from a command's exit status. rcis records a row for the
# exit code AND remembers whether it matched, so the state rows that follow it (bytes unchanged,
# no leftover) are recorded as FAILURES when the code was wrong: "bytes unchanged" is trivially
# true when nothing ran at all, which would make the RED run report false greens.
RC=0
OUT=""
ERR=""
RC_OK=0
chk() { local label="$1"; shift; cases=$((cases + 1)); if "$@"; then pass "$label"; else fail "$label"; fi; }
rcis() {
  local label="$1" want="$2"
  cases=$((cases + 1)); RC_OK=0
  if [[ "$RC" == "$want" ]]; then RC_OK=1; pass "$label (rc $RC)"; else fail "$label (want rc $want, got $RC; stdout: $(printf '%s' "$OUT" | tail -n 2 | tr '\n' ' '))"; fi
}
state() { local label="$1"; shift; cases=$((cases + 1)); if [[ "$RC_OK" == 1 ]] && "$@"; then pass "$label"; else fail "$label"; fi; }

# assert_fixture_dir: the CANONICAL copy (byte-for-byte; fixture-dir-operand-assert.test.sh pins it).
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

TMPROOT="$(mktemp -d)"
assert_fixture_dir "$TMPROOT"
cleanup() { assert_fixture_dir "$TMPROOT"; rm -rf -- "$TMPROOT"; }
trap cleanup EXIT
mkdir -p "$TMPROOT/tmp"
# Hermetic git environment for the fixtures (the repo's chokepoint, #7849).
# shellcheck source=../../../test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
mkdir -p "$TMPROOT/anchor"
git_fixture_env "$TMPROOT/anchor" || { echo "FATAL: git_fixture_env refused $TMPROOT/anchor" >&2; exit 1; }

sha_of() {
  local h
  if command -v sha256sum >/dev/null 2>&1; then h="$(sha256sum "$1")"; else h="$(shasum -a 256 "$1")"; fi
  printf '%s' "${h%% *}"
}
same_bytes() { cmp -s "$1" "$2"; }
mode_of() { local l; l="$(ls -l "$1")"; printf '%s' "${l:0:10}"; }
inode_of() { local l; l="$(ls -i "$1")"; l="${l# }"; printf '%s' "${l%% *}"; }
# Ledger data rows, parsed the way the script parses them: first field of every non-comment line.
ledger_hashes() { awk '/^[[:space:]]*#/ || !NF {next} {print $1}' "$1"; }
fresh_emission() { sed "s|__TARGET_DIR__|apps/web-platform|g" "$1/fix-constraints-stage-a.template"; }
has_forty_hex() { grep -Eq '(^|[^0-9a-f])[0-9a-f]{40}([^0-9a-f]|$)' "$1"; }
has_action_ref() { grep -Fq 'claude-code-action@' "$1"; }

# --- Base fixture: a Next.js-shaped app with the scaffold's artifacts committed -------------------
BASE="$TMPROOT/base"
mkdir -p "$BASE/apps/web-platform/app" "$BASE/apps/web-platform/components" "$BASE/apps/web-platform/server" \
         "$BASE/apps/web-platform/scripts" "$BASE/$WF_DIR_REL"
git -C "$BASE" init -q
git -C "$BASE" config user.email "test@example.com"
git -C "$BASE" config user.name "test"
printf 'node_modules\n' > "$BASE/.gitignore"
printf 'module.exports = {};\n' > "$BASE/apps/web-platform/next.config.js"
printf '{ "dependencies": { "next": "15.0.0" } }\n' > "$BASE/apps/web-platform/package.json"
printf 'export default function Page() { return null; }\n' > "$BASE/apps/web-platform/app/page.tsx"
printf '"use client";\nexport const G = () => "g";\n' > "$BASE/apps/web-platform/components/g.tsx"
printf 'export const APP = "fixture";\n' > "$BASE/apps/web-platform/server/config.ts"
printf 'sentinel-config\n' > "$BASE/apps/web-platform/.dependency-cruiser.cjs"
printf 'sentinel-runner\n' > "$BASE/apps/web-platform/scripts/constraint-gates.sh"
printf 'sentinel-baseline\n' > "$BASE/apps/web-platform/.dependency-cruiser-known-violations.json"
printf 'sentinel-gates-workflow\n' > "$BASE/$WF_DIR_REL/constraint-gates.yml"
printf 'sentinel-stage-b\n' > "$BASE/$WF_DIR_REL/fix-constraints-stage-b.yml"
cp "$OLD_FIXTURE" "$BASE/$FIX_A_REL"
git -C "$BASE" add -A
git -C "$BASE" commit -q -m "seed app and scaffold artifacts"

# new_case <name>: a fresh copy of the base fixture. Prints the path.
new_case() { local fx="$TMPROOT/$1"; cp -R "$BASE" "$fx"; printf '%s' "$fx"; }
commit_all() { assert_fixture_dir "$1"; git -C "$1" add -A; git -C "$1" commit -q -m "${2:-change}"; }
# new_sandbox <name>: a per-case copy of scripts/ and references/ so a case can vary the ledger or
# the template. Prints the scripts dir to run.
new_sandbox() { local sb="$TMPROOT/sb-$1"; mkdir -p "$sb"; cp -R "$REAL_SCRIPTS" "$sb/scripts"; cp -R "$REAL_REFS" "$sb/references"; printf '%s' "$sb"; }

# run_refresh <fixture> [<scripts-dir>]: sets RC, OUT (stdout), ERR (stderr).
run_refresh() {
  local fx="$1" sd="${2:-$REAL_SCRIPTS}"
  RC=0
  OUT="$(CONSTRAINT_SCAFFOLD_REPO_ROOT="$fx" TMPDIR="$TMPROOT/tmp" bash "$sd/constraint-scaffold.sh" --refresh-stage-a 2>"$TMPROOT/err")" || RC=$?
  ERR="$(cat "$TMPROOT/err")"
}
no_leftover() { local fx="$1"; compgen -G "$fx/$WF_DIR_REL/.fix-constraints-stage-a.*" >/dev/null && return 1; [[ ! -e "$fx/.git/constraint-scaffold.lock" ]]; }
no_temp() { ! compgen -G "$1/$WF_DIR_REL/.fix-constraints-stage-a.*" >/dev/null; }
out_has() { grep -Fq -- "$1" <<<"$OUT"; }
out_lacks() { ! grep -Fq -- "$1" <<<"$OUT$ERR"; }
out_has_line() { grep -Eq -- "$1" <<<"$OUT"; }
fresh_real="$TMPROOT/fresh-real"
fresh_emission "$REAL_REFS" > "$fresh_real"

# --- 1. Refresh the v1.0.236 fixture (clean, committed, under umask 077) --------------------------
FX="$(new_case c1)"
old_umask="$(umask)"; umask 077
run_refresh "$FX"
umask "$old_umask"
rcis "1a refresh of the v1.0.236 emission" 0
state "1b bytes equal the fresh emission of the template" same_bytes "$FX/$FIX_A_REL" "$fresh_real"
state "1c mode is 0644 (mktemp's 0600 must not leak)" test "$(mode_of "$FX/$FIX_A_REL")" = "-rw-r--r--"
state "1d no leftover temp file or lock directory" no_leftover "$FX"

# --- 2. Already current: never consults the ledger -------------------------------------------------
FX="$(new_case c2)"
cp "$fresh_real" "$FX/$FIX_A_REL"
commit_all "$FX" "current"
SB="$(new_sandbox c2)"
rm -f "$SB/references/fix-constraints-stage-a.emitted.sha256"
: > "$TMPROOT/ref2"; touch -t 200001010000 "$TMPROOT/ref2" "$FX/$FIX_A_REL"
ino_before="$(inode_of "$FX/$FIX_A_REL")"
run_refresh "$FX" "$SB/scripts"
rcis "2a already-current file with the ledger removed" 0
chk "2a' says already current" out_has "already current"
state "2b not rewritten (backdated mtime not advanced)" test ! "$FX/$FIX_A_REL" -nt "$TMPROOT/ref2"
state "2c not rewritten (inode unchanged)" test "$(inode_of "$FX/$FIX_A_REL")" = "$ino_before"

# --- 3. Edited copy: refused, file untouched, user's content never printed ------------------------
TOKEN="sk-""ant-api03-ZZZZ$(printf 'Z%.0s' 1 2 3 4 5 6 7 8)SYNTH"
FX="$(new_case c3)"
{ cat "$OLD_FIXTURE"; printf '# edited by a founder: %s\n' "$TOKEN"; } > "$FX/$FIX_A_REL"
cp "$FX/$FIX_A_REL" "$TMPROOT/c3.before"
commit_all "$FX" "edited"
run_refresh "$FX"
rcis "3a edited copy is refused" 75
state "3b bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$TMPROOT/c3.before"
state "3c report shows template-side lines" out_has_line '^> '
state "3c' report never prints the existing side or the planted token" out_lacks "$TOKEN"
state "3c'' report has no existing-side line" test -z "$(grep -E '^< ' <<<"$OUT" || true)"
state "3d no leftover" no_leftover "$FX"

# --- 4. Final newline stripped: exact bytes, not normalised text ----------------------------------
FX="$(new_case c4)"
printf '%s' "$(<"$OLD_FIXTURE")" > "$FX/$FIX_A_REL"
cp "$FX/$FIX_A_REL" "$TMPROOT/c4.before"
commit_all "$FX" "no newline"
run_refresh "$FX"
rcis "4a stripped final newline is refused" 75
state "4b bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$TMPROOT/c4.before"

# --- 5. Guards before the write (destination always holds ledger-member bytes) --------------------
dirty_other() { printf 'dirty\n' >> "$1/$WF_DIR_REL/constraint-gates.yml"; }
hold_lock() { mkdir -p "$1/.git/constraint-scaffold.lock"; printf '%s\n' "$$" > "$1/.git/constraint-scaffold.lock/pid"; }
lock_pid_is_mine() { [[ "$(cat "$1/.git/constraint-scaffold.lock/pid" 2>/dev/null || true)" == "$$" ]]; }

FX="$(new_case c5a)"; dirty_other "$FX"
run_refresh "$FX"
rcis "5a dirty tree" 67
state "5a' bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$OLD_FIXTURE"

FX="$(new_case c5b)"; hold_lock "$FX"
run_refresh "$FX"
rcis "5b live lock on a clean tree (positive control that the lock is reached)" 69
state "5b' bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$OLD_FIXTURE"
state "5b'' the other run's lock was not taken over" lock_pid_is_mine "$FX"

FX="$(new_case c5c)"; dirty_other "$FX"; hold_lock "$FX"
run_refresh "$FX"
rcis "5c dirty tree plus live lock (tree check precedes the lock)" 67

FX="$(new_case c5d)"; dirty_other "$FX"
mkdir -p "$TMPROOT/outside5d"; cp "$OLD_FIXTURE" "$TMPROOT/outside5d/target"
rm -f "$FX/$FIX_A_REL"; ln -s "$TMPROOT/outside5d/target" "$FX/$FIX_A_REL"
run_refresh "$FX"
rcis "5d symlinked destination on a dirty tree (symlink check precedes the tree check)" 75

FX="$(new_case c5e)"
assert_fixture_dir "$FX"
git -C "$FX" rm -q --cached "$FIX_A_REL"
git -C "$FX" commit -q -m "untrack stage a"
run_refresh "$FX"
rcis "5e untracked but byte-valid destination (must be reviewable with git diff)" 67
state "5e' bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$OLD_FIXTURE"

# --- 6. Existence precedes everything, and takes no lock ------------------------------------------
FX="$(new_case c6a)"; dirty_other "$FX"; hold_lock "$FX"; rm -f "$FX/$FIX_A_REL"
run_refresh "$FX"
rcis "6a stage-a absent on a dirty tree with a live lock" 70
state "6d the mode took no lock (the pre-created lock is untouched)" lock_pid_is_mine "$FX"

FX="$(new_case c6b)"; rm -f "$FX/apps/web-platform/.dependency-cruiser.cjs"; commit_all "$FX" "no config"
run_refresh "$FX"
rcis "6b config absent" 70

FX="$(new_case c6c)"; dirty_other "$FX"; hold_lock "$FX"
rm -f "$FX/$FIX_A_REL"; ln -s "$TMPROOT/does-not-exist-6c" "$FX/$FIX_A_REL"
run_refresh "$FX"
rcis "6c dangling-symlink destination" 70

# --- 7. Ledger anchored to the template; no downgrade ---------------------------------------------
want_hash="$(sha_of "$fresh_real")"
cases=$((cases + 1))
if grep -Fxq -- "$want_hash" <<<"$(ledger_hashes "$REAL_REFS/fix-constraints-stage-a.emitted.sha256" 2>/dev/null || true)"; then
  pass "7a the CURRENT template's emission is in the ledger"
else
  fail "7a the current template's emission ($want_hash) is NOT in references/fix-constraints-stage-a.emitted.sha256 — append a row only if the template keeps the frozen Stage A to Stage B interface and contents: read; regenerate with the command in the ledger header"
fi

FX="$(new_case c7b)"
SB="$(new_sandbox c7b)"
{ cat "$REAL_REFS/fix-constraints-stage-a.template"; printf '# ledger-rank-older\n'; } > "$SB/references/fix-constraints-stage-a.template"
{ cat "$REAL_REFS/fix-constraints-stage-a.template"; printf '# ledger-rank-newer\n'; } > "$TMPROOT/tpl-newer"
sed "s|__TARGET_DIR__|apps/web-platform|g" "$SB/references/fix-constraints-stage-a.template" > "$TMPROOT/em-older"
sed "s|__TARGET_DIR__|apps/web-platform|g" "$TMPROOT/tpl-newer" > "$TMPROOT/em-newer"
printf '# synthetic two-row ledger for the downgrade case\n%s  older\n%s  newer\n' "$(sha_of "$TMPROOT/em-older")" "$(sha_of "$TMPROOT/em-newer")" \
  > "$SB/references/fix-constraints-stage-a.emitted.sha256"
cp "$TMPROOT/em-newer" "$FX/$FIX_A_REL"; commit_all "$FX" "newest era installed"
run_refresh "$FX" "$SB/scripts"
rcis "7b installed file newer than the plugin's template is refused" 75
state "7b' bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$TMPROOT/em-newer"
state "7b'' says the installed file is newer" out_has "newer than this plugin"
state "7b''' prints no diff on a downgrade refusal" test -z "$(grep -E '^[<>] ' <<<"$OUT" || true)"

# --- 8. Ledger unusable: fail closed ---------------------------------------------------------------
for variant in removed no-data-rows comment-only; do
  FX="$(new_case "c8-$variant")"
  SB="$(new_sandbox "c8-$variant")"
  ledger="$SB/references/fix-constraints-stage-a.emitted.sha256"
  case "$variant" in
    removed)      rm -f "$ledger" ;;
    no-data-rows) printf '\n   \n\n' > "$ledger" ;;
    comment-only) printf '# only a comment\n# and another\n' > "$ledger" ;;
  esac
  run_refresh "$FX" "$SB/scripts"
  rcis "8 ledger $variant refuses the stale fixture" 75
  state "8 ledger $variant leaves the bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$OLD_FIXTURE"
done

# --- 9. Symlink and hash-tool arms -----------------------------------------------------------------
FX="$(new_case c9a)"
mkdir -p "$TMPROOT/outside9a"; cp "$OLD_FIXTURE" "$TMPROOT/outside9a/target"
rm -f "$FX/$FIX_A_REL"; ln -s "$TMPROOT/outside9a/target" "$FX/$FIX_A_REL"; commit_all "$FX" "symlinked stage a"
run_refresh "$FX"
rcis "9a symlinked destination file (clean tree)" 75
state "9a' the symlink target is unchanged" same_bytes "$TMPROOT/outside9a/target" "$OLD_FIXTURE"
state "9a'' no diff printed" test -z "$(grep -E '^[<>] ' <<<"$OUT" || true)"

FX="$(new_case c9b)"
assert_fixture_dir "$FX"
git -C "$FX" mv apps/web-platform/.github .github
ln -s ../../.github "$FX/apps/web-platform/.github"
commit_all "$FX" "symlinked .github parent"
run_refresh "$FX"
rcis "9b symlinked parent directory (physical dir must equal the target's workflows dir)" 75
state "9b' the pointed-at file is unchanged" same_bytes "$FX/.github/workflows/fix-constraints-stage-a.yml" "$OLD_FIXTURE"

FX="$(new_case c9c)"
FAKE="$TMPROOT/fakebin"; mkdir -p "$FAKE"
for tool in sha256sum shasum; do
  cat > "$FAKE/$tool" <<'FAKE'
#!/usr/bin/env bash
# Strict fake: the only accepted shapes are `sha256sum FILE` and `shasum -a 256 FILE`; both emit an
# EMPTY digest. Any other argv exits 64 so a changed call shape in the script is a loud failure here.
case "$(basename "$0"):$#:${1:-}:${2:-}" in
  sha256sum:1:*) printf '\n'; exit 0 ;;
  shasum:3:-a:256) printf '\n'; exit 0 ;;
  *) echo "fake hash tool: unexpected argv: $*" >&2; exit 64 ;;
esac
FAKE
  chmod +x "$FAKE/$tool"
done
RC=0
OUT="$(PATH="$FAKE:$PATH" CONSTRAINT_SCAFFOLD_REPO_ROOT="$FX" TMPDIR="$TMPROOT/tmp" bash "$REAL_SCRIPTS/constraint-scaffold.sh" --refresh-stage-a 2>"$TMPROOT/err")" || RC=$?
ERR="$(cat "$TMPROOT/err")"
rcis "9c empty digest from the hash tool is an error, never a ledger match" 69
state "9c' bytes unchanged" same_bytes "$FX/$FIX_A_REL" "$OLD_FIXTURE"

# --- 10. A refresh writes the one file and nothing else -------------------------------------------
FX="$(new_case c10)"
SNAP="$TMPROOT/snap10"; mkdir -p "$SNAP"
others="apps/web-platform/.dependency-cruiser.cjs apps/web-platform/scripts/constraint-gates.sh apps/web-platform/.dependency-cruiser-known-violations.json $WF_DIR_REL/constraint-gates.yml $WF_DIR_REL/fix-constraints-stage-b.yml"
n=0; for f in $others; do n=$((n + 1)); cp "$FX/$f" "$SNAP/$n"; done
run_refresh "$FX"
rcis "10a refresh succeeds" 0
state "10a' the destination changed" test ! "$(sha_of "$FX/$FIX_A_REL")" = "$(sha_of "$OLD_FIXTURE")"
n=0; untouched=1; for f in $others; do n=$((n + 1)); same_bytes "$FX/$f" "$SNAP/$n" || untouched=0; done
state "10b stage-b, gates workflow, config, runner and baseline are byte-unchanged" test "$untouched" = 1

# --- 11. No pin literal in the script or the ledger -----------------------------------------------
POS="$TMPROOT/pos11"
{ printf 'uses: anthropics/claude-code-action@'; printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; printf '\n'; } > "$POS"
chk "11a positive control: the helpers find a 40-hex string" has_forty_hex "$POS"
chk "11a' positive control: the helpers find an action reference" has_action_ref "$POS"
chk "11 inputs exist (grep rc 2 is not a pass)" test -f "$REAL_SCRIPTS/constraint-scaffold.sh" -a -f "$REAL_REFS/fix-constraints-stage-a.emitted.sha256"
chk "11b constraint-scaffold.sh carries no action reference" test ! "$(has_action_ref "$REAL_SCRIPTS/constraint-scaffold.sh" && echo y || echo n)" = y
chk "11b' constraint-scaffold.sh carries no 40-hex string" test ! "$(has_forty_hex "$REAL_SCRIPTS/constraint-scaffold.sh" && echo y || echo n)" = y
chk "11c the ledger carries no action reference" test ! "$(has_action_ref "$REAL_REFS/fix-constraints-stage-a.emitted.sha256" && echo y || echo n)" = y
chk "11c' the ledger carries no 40-hex string" test ! "$(has_forty_hex "$REAL_REFS/fix-constraints-stage-a.emitted.sha256" && echo y || echo n)" = y

# --- 12. Frozen Stage A to Stage B interface and privilege (asserted on the CURRENT template) -----
TPL="$REAL_REFS/fix-constraints-stage-a.template"
TPL_CODE="$TMPROOT/tpl-code"; grep -vE '^[[:space:]]*#' "$TPL" > "$TPL_CODE" || true
on_block() { awk '/^on:/{p=1;next} p&&/^[^ \t]/{exit} p' "$TPL_CODE"; }
triggers="$(on_block | grep -E '^  [a-z_]+:' | sed 's/:.*//; s/^  //' | sort | tr '\n' ' ' || true)"
perm_block="$(awk '/^permissions:/{p=1;next} p&&/^[^ \t]/{exit} p' "$TPL_CODE" | grep -v '^[[:space:]]*$' || true)"
chk "12a name is fix-constraints-stage-a (Stage B filters on it)" grep -Fxq 'name: fix-constraints-stage-a' "$TPL"
chk "12b artifact name prefix fix-constraints-patch- is kept" grep -Fq 'name: fix-constraints-patch-' "$TPL"
chk "12b' artifact name prefix fix-constraints-giveup- is kept" grep -Fq 'name: fix-constraints-giveup-' "$TPL"
chk "12c triggers are pull_request (+ workflow_dispatch for manual retry) only; got: $triggers" test "$triggers" = "pull_request workflow_dispatch "
chk "12d top-level permissions are exactly contents: read" test "$perm_block" = "  contents: read"
chk "12e no write scope and no id-token anywhere in the template body" test -z "$(grep -E '^[[:space:]]+(id-token|[a-z-]+):[[:space:]]*write[[:space:]]*$' "$TPL_CODE" || true)"

# --- Accounting -------------------------------------------------------------------------------------
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  printf '  A row was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  echo "refresh-stage-a.test.sh: $passes passed, $fails failed ($cases rows)"
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1). The literal sits directly above the `if`. -----------------------
MIN_ROWS=63
if [[ "$cases" -lt "$MIN_ROWS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= %d.\n' "$cases" "$MIN_ROWS" >&2
  printf '  Rows were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  echo "refresh-stage-a.test.sh: $passes passed, $fails failed ($cases rows)"
  exit 1
fi

echo "refresh-stage-a.test.sh: $passes passed, $fails failed ($cases rows)"
[[ "$fails" -eq 0 ]]
