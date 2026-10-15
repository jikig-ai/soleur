#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329  # A && B || C is the assertion idiom; jq/sed programs are single-quoted on purpose; row functions are dispatched indirectly
# Suite for plugins/soleur/scripts/delegation-verify.sh -- Guard 1 of the plan's Guard Contract
# (knowledge-base/project/plans/2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md).
#
# THE SEAM: `gh` is a PATH stub that answers ONLY GET-shaped `api repos/...` reads and one `repo view`
# call, keyed on the FULL argv, and refuses every other argv with exit 64 after logging STUB-MISS. The
# suite asserts the log never holds a STUB-MISS and never holds a write-shaped call. There is NO test
# seam in the script: nothing here can make the script answer `valid` except a fixture that really is.
#
# FIXTURES: synthesized (cq-test-fixtures-synthesized-only) under test/fixtures/standing-delegation/.
# Dates are computed at run time so "not past" and "created + 30 days" never rot.
#
# ARMS: control, cases (one per reason token), must-PASS shapes (H2), audit, render, executable
# template (the format reference is instantiated and verified), self-check, tool-missing, zero-write
# audit of the stub log, mutations (marker lines `# mut:<name>` in the script), floor.

set -uo pipefail
export LC_ALL=C

TMP="$(mktemp -d -t dv-suite.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../test/test-helpers.sh
source "$SUITE_DIR/../test/test-helpers.sh"
set +e
assert_fixture_dir "$TMP"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
SUT_REAL="$SUITE_DIR/delegation-verify.sh"
SUT="$SUT_REAL"
FX="$REPO_ROOT/plugins/soleur/test/fixtures/standing-delegation"
REFERENCE="$REPO_ROOT/plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md"

# --- instrument self-test (H1): the assertion helper must be able to FAIL -------------------------
( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }

[[ -f "$SUT_REAL" ]] || { echo "  FAIL: verifier missing: $SUT_REAL"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }
command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 2; }
for f in delegation-valid.md envelope-valid.md envelope-trailing.md envelope-two-sections.md envelope-denylist.md; do
  [[ -s "$FX/$f" ]] || { echo "FATAL: fixture missing: $FX/$f" >&2; exit 2; }
done

# --- time -----------------------------------------------------------------------------------------
addd() { jq -rn --arg d "$1" --argjson n "$2" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY="$(date -u +%Y-%m-%d)"
NOW_ISO="${TODAY}T00:00:00Z"
EXP10="$(addd "$TODAY" 10)"
EXP30="$(addd "$TODAY" 30)"
EXP31="$(addd "$TODAY" 31)"

# --- the gh stub ----------------------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "$*" >> "$d/calls.log"
miss() { echo "STUB-MISS $*" >> "$d/calls.log"; echo "gh stub: unsupported argv: $*" >&2; exit 64; }
fail_mode() {
  case "$(cat "$d/$1" 2>/dev/null)" in
    404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    net) echo "error connecting to api.github.com" >&2; exit 1 ;;
  esac
}
if [ "$*" = "repo view --json nameWithOwner --jq .nameWithOwner" ]; then
  fail_mode mode-repo; cat "$d/repo.txt"; exit 0
fi
[ "$#" -eq 2 ] && [ "$1" = api ] || miss "$@"
p="$2"
case "$p" in
  repos/*/*/issues/comments/*)
    id="${p##*/}"; fail_mode "mode-comment-$id"
    [ -f "$d/comment-$id.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$d/comment-$id.json" ;;
  repos/*/*/collaborators/*/permission)
    l="${p%/permission}"; l="${l##*/}"; fail_mode mode-perm
    [ -f "$d/perm-$l.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$d/perm-$l.json" ;;
  repos/*/*/issues/*)
    n="${p##*/}"; fail_mode mode-issue
    [ -f "$d/issue-$n.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$d/issue-$n.json" ;;
  *) miss "$@" ;;
esac
STUB
chmod +x "$BIN/gh"

# --- scenario builders ----------------------------------------------------------------------------
URL="https://github.com/example-org/example-repo/issues/77#issuecomment-1001"
URL2="https://github.com/example-org/example-repo/issues/88#issuecomment-2002"
SC=0
mk_body() { # <expiry> <date> -> stdout
  sed -e "s/@EXPIRY@/$1/" -e "s/@DATE@/$2/" "$FX/delegation-valid.md"
}
mk_comment() { # <id> <bodyfile> [login] [type] [created] [updated] [issue]
  local id="$1" body="$2" login="${3:-owner-user}" type="${4:-User}" created="${5:-$NOW_ISO}" updated="${6:-}" issue="${7:-77}"
  [[ -n "$updated" ]] || updated="$created"
  jq -n --rawfile body "$body" --arg login "$login" --arg type "$type" --arg c "$created" --arg u "$updated" \
    --arg iu "https://api.github.com/repos/example-org/example-repo/issues/$issue" --argjson id "$id" \
    '{id:$id, body:$body, user:{login:$login, type:$type}, author_association:"MEMBER", created_at:$c, updated_at:$u, issue_url:$iu}' \
    > "$STUB_DIR/comment-$id.json"
}
scn() { # fresh scenario: valid comment 1001 on open issue 77 by an admin
  SC=$((SC + 1)); STUB_DIR="$TMP/scn$SC"; rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"; export STUB_DIR
  echo "example-org/example-repo" > "$STUB_DIR/repo.txt"
  mk_body "$EXP10" "$TODAY" > "$STUB_DIR/body.md"
  mk_comment 1001 "$STUB_DIR/body.md"
  echo '{"permission":"admin"}' > "$STUB_DIR/perm-owner-user.json"
  echo '{"number":77,"state":"open"}' > "$STUB_DIR/issue-77.json"
}
b_sed() { # <sed -E expr>: variant body, must differ from the pristine one
  sed -E "$1" "$STUB_DIR/body.md" > "$STUB_DIR/b.md"
  if cmp -s "$STUB_DIR/body.md" "$STUB_DIR/b.md"; then echo "  FAIL: body variant did not change: $1"; FAIL=$((FAIL + 1)); fi
  mk_comment 1001 "$STUB_DIR/b.md"
}
b_exp() { mk_body "$1" "${2:-$TODAY}" > "$STUB_DIR/b.md"; mk_comment 1001 "$STUB_DIR/b.md" owner-user User "${3:-$NOW_ISO}"; }

# setups reused by cases and by mutation probes
s_nonadmin() { mk_comment 1001 "$STUB_DIR/body.md" other-user; echo '{"permission":"write"}' > "$STUB_DIR/perm-other-user.json"; }
s_bot() { mk_comment 1001 "$STUB_DIR/body.md" owner-user Bot; }
s_edited() { mk_comment 1001 "$STUB_DIR/body.md" owner-user User "$NOW_ISO" "${TODAY}T00:05:00Z"; }
s_noconfirm() { b_sed '/^\*\*Confirmation:\*\*/d'; }
s_shortq() { b_sed '/^> Operator answer/d;s/^> Question shown:.*/> Yes/'; }
s_noscope() { b_sed '/^[0-9]\. /d'; }
s_exclinc() { b_sed 's/, force-push to main//'; }
s_noexp() { b_sed 's/^\*\*Expiry:\*\*.*/**Expiry:** when the epic closes./'; }
s_toolong() { b_exp "$EXP31"; }
s_expired() { b_exp "2026-01-20" "2026-01-01" "2026-01-01T00:00:00Z"; }
s_closed() { echo '{"number":77,"state":"closed"}' > "$STUB_DIR/issue-77.json"; }
s_prissue() { echo '{"number":77,"state":"open","pull_request":{"url":"x"}}' > "$STUB_DIR/issue-77.json"; }
s_wrongissue() { mk_comment 1001 "$STUB_DIR/body.md" owner-user User "$NOW_ISO" "" 78; echo '{"number":78,"state":"open"}' > "$STUB_DIR/issue-78.json"; }
s_apierr() { echo net > "$STUB_DIR/mode-comment-1001"; }
s_issueerr() { echo net > "$STUB_DIR/mode-issue"; }

# --- the envelope repository ----------------------------------------------------------------------
REPO="$TMP/repo"; mkdir -p "$REPO"
mk_env() { sed -e "s|@URL@|$2|g" -e 's/@TRAILSP@/ /' "$FX/$1" > "$REPO/$3"; }
mk_env envelope-valid.md "$URL" env-valid.md
mk_env envelope-valid.md "$URL2" env-valid-b.md
mk_env envelope-trailing.md "$URL" env-trailing.md
mk_env envelope-two-sections.md "$URL" env-two.md
mk_env envelope-denylist.md "$URL" env-deny.md
sed 's/^Rollback: .*/Rollback: none/' "$REPO/env-valid.md" > "$REPO/env-noroll.md"
sed 's/^Rollback: .*/Rollback: N\/A./' "$REPO/env-valid.md" > "$REPO/env-noroll-na.md"
sed 's/^Rollback: .*/Rollback: Unknown/' "$REPO/env-valid.md" > "$REPO/env-noroll-unk.md"
sed '/^Verification:/,/^- bash/d' "$REPO/env-valid.md" > "$REPO/env-incomplete.md"
sed '/^- Gate:/d' "$REPO/env-valid.md" > "$REPO/env-nogate.md"
sed 's|^Delegation: .*|Delegation: https://github.com/example-org/example-repo/issues/77#issuecomment-9999|' "$REPO/env-valid.md" > "$REPO/env-wrongdel.md"
sed 's/^Scope item: 1/Scope item: 9/' "$REPO/env-valid.md" > "$REPO/env-scope9.md"
sed 's/$/\r/' "$REPO/env-valid.md" > "$REPO/env-crlf.md"
printf '# no envelope here\n\nJust prose.\n' > "$REPO/env-none.md"
cp "$REPO/env-valid.md" "$REPO/env-modified.md"
( git_fixture_env "$REPO" && git -C "$REPO" init -q && git -C "$REPO" add -A && git -C "$REPO" commit -q -m "fixture envelopes" ) >/dev/null 2>&1 \
  || { echo "FATAL: fixture repository not built" >&2; exit 2; }
cp "$REPO/env-valid.md" "$REPO/env-uncommitted.md"            # untracked
printf 'Extra line after the commit.\n' >> "$REPO/env-modified.md" # tracked, modified
cp "$REPO/env-valid.md" "$TMP/outside.md"                      # outside any repository

run_v() { # <args...>: rc -> $TMP/rc, stdout -> $TMP/o, stderr -> $TMP/e. Runs in the fixture repository.
  ( cd "$REPO" && git_fixture_env "$REPO" && PATH="$BIN:$PATH" bash "$SUT" "$@" ) >"$TMP/o" 2>"$TMP/e"
  rc=$?
  echo "$rc" > "$TMP/rc"
}
last_rc() { cat "$TMP/rc"; }
no_stub_miss() { ! grep -q 'STUB-MISS' "$STUB_DIR/calls.log" 2>/dev/null; }
expect() { # <name> <rc> <verdict line>
  assert_eq "$2" "$(last_rc)" "$1: rc"
  assert_eq "$3" "$(head -1 "$TMP/o")" "$1: verdict"
  no_stub_miss && { echo "  PASS: $1: no stub miss"; PASS=$((PASS + 1)); } || { echo "  FAIL: $1: gh stub refused an argv"; FAIL=$((FAIL + 1)); }
}
( b=$FAIL; : > "$TMP/o"; echo 0 > "$TMP/rc"; STUB_DIR="$TMP"; expect ctrl 1 "x" >/dev/null; [[ $FAIL -ge $((b + 2)) ]] ) \
  || { printf 'FATAL: expect cannot fail -- dispatch is neutered\n' >&2; exit 2; }

echo "=== Control: a valid delegation ==="
scn; run_v verify --delegation "$URL"
expect "valid" 0 "delegation: valid reason=ok"

echo "=== Arm 1: one row per reason token ==="
scn; b_sed '1d';                                  run_v verify --delegation "$URL"; expect "no-marker" 1 "delegation: invalid reason=no-marker"
scn; b_sed '1s/^/x/';                             run_v verify --delegation "$URL"; expect "marker-not-exact" 1 "delegation: invalid reason=no-marker"
scn; s_bot;                                       run_v verify --delegation "$URL"; expect "bot-author" 1 "delegation: invalid reason=bot-author"
scn; s_nonadmin;                                  run_v verify --delegation "$URL"; expect "not-admin-author" 1 "delegation: invalid reason=not-admin-author"
scn; s_edited;                                    run_v verify --delegation "$URL"; expect "edited" 1 "delegation: invalid reason=edited"
scn; b_sed '/^> /d';                              run_v verify --delegation "$URL"; expect "no-quote" 1 "delegation: invalid reason=no-quote"
scn; s_shortq;                                    run_v verify --delegation "$URL"; expect "quote-too-short" 1 "delegation: invalid reason=quote-too-short"
scn; s_noconfirm;                                 run_v verify --delegation "$URL"; expect "no-confirmation" 1 "delegation: invalid reason=no-confirmation"
scn; b_sed 's/^\*\*Confirmation:\*\*.*/**Confirmation:**/'; run_v verify --delegation "$URL"; expect "empty-confirmation" 1 "delegation: invalid reason=no-confirmation"
scn; s_noscope;                                   run_v verify --delegation "$URL"; expect "no-scope-item" 1 "delegation: invalid reason=no-scope-item"
scn; s_exclinc;                                   run_v verify --delegation "$URL"; expect "excluded-incomplete" 1 "delegation: invalid reason=excluded-incomplete"
scn; b_sed 's/ third-party//;s/anything on or tenant/anything/'; run_v verify --delegation "$URL"; expect "excluded-incomplete-2" 1 "delegation: invalid reason=excluded-incomplete"
scn; s_noexp;                                     run_v verify --delegation "$URL"; expect "expiry-missing" 1 "delegation: invalid reason=expiry-missing"
scn; b_sed 's/^\*\*Expiry:\*\* [0-9-]+/**Expiry:** 2026-13-45/'; run_v verify --delegation "$URL"; expect "expiry-bad-date" 1 "delegation: invalid reason=expiry-missing"
scn; s_toolong;                                   run_v verify --delegation "$URL"; expect "expiry-too-long (+31 d)" 1 "delegation: invalid reason=expiry-too-long"
scn; b_exp "$EXP30";                              run_v verify --delegation "$URL"; expect "expiry exactly +30 d passes" 0 "delegation: valid reason=ok"
scn; s_expired;                                   run_v verify --delegation "$URL"; expect "expired" 1 "delegation: invalid reason=expired"
scn; s_closed;                                    run_v verify --delegation "$URL"; expect "epic-closed" 1 "delegation: invalid reason=epic-closed"
scn; s_prissue;                                   run_v verify --delegation "$URL"; expect "epic-is-pr" 1 "delegation: invalid reason=epic-is-pr"
scn; s_wrongissue;                                run_v verify --delegation "$URL"; expect "wrong-issue" 1 "delegation: invalid reason=wrong-issue"
scn;                                              run_v verify --delegation "https://example.com/x"; expect "bad-url" 1 "delegation: invalid reason=bad-url"
scn;                                              run_v verify --delegation "https://github.com/example-org/example-repo/issues/77"; expect "bad-url (no fragment)" 1 "delegation: invalid reason=bad-url"
scn;                                              run_v verify --delegation "https://github.com/other-org/other-repo/issues/77#issuecomment-1001"; expect "wrong-repo" 1 "delegation: invalid reason=wrong-repo"

echo "=== Arm 1b: unverifiable (exit 2, never a pass) ==="
scn; echo 404 > "$STUB_DIR/mode-comment-1001";    run_v verify --delegation "$URL"; expect "comment-unreadable (404)" 2 "delegation: unverifiable reason=comment-unreadable"
assert_eq "1" "$(grep -c 'issues/comments/1001' "$STUB_DIR/calls.log")" "a definitive 404 is not retried"
scn; s_apierr;                                    run_v verify --delegation "$URL"; expect "api-error (transport)" 2 "delegation: unverifiable reason=api-error"
assert_eq "2" "$(grep -c 'issues/comments/1001' "$STUB_DIR/calls.log")" "a transport error is retried exactly once"
scn; s_nonadmin; echo net > "$STUB_DIR/mode-perm"; run_v verify --delegation "$URL"; expect "api-error (permission lookup)" 2 "delegation: unverifiable reason=api-error"
scn; echo net > "$STUB_DIR/mode-issue";           run_v verify --delegation "$URL"; expect "api-error (issue lookup)" 2 "delegation: unverifiable reason=api-error"
scn; echo net > "$STUB_DIR/mode-repo";            run_v verify --delegation "$URL"; expect "api-error (repo lookup)" 2 "delegation: unverifiable reason=api-error"
scn; jq 'del(.created_at)' "$STUB_DIR/comment-1001.json" > "$STUB_DIR/c.tmp" && cat "$STUB_DIR/c.tmp" > "$STUB_DIR/comment-1001.json"
run_v verify --delegation "$URL"; expect "missing field is unverifiable" 2 "delegation: unverifiable reason=api-error"
scn; mk_comment 1001 "$STUB_DIR/body.md" Example-Org; run_v verify --delegation "$URL"
expect "owner-login author (any case) needs no permission lookup" 0 "delegation: valid reason=ok"
assert_eq "0" "$(grep -c 'collaborators' "$STUB_DIR/calls.log")" "no permission lookup was made for the owner login"

echo "=== Usage errors (exit 2) ==="
scn; run_v;                                       expect "no subcommand (dispatch floor)" 2 "delegation: unverifiable reason=usage"
scn; run_v verify;                                expect "verify without --delegation" 2 "delegation: unverifiable reason=usage"
scn; run_v verify --delegation "$URL" --command "gh pr merge 123 --squash"; expect "--command without --envelope" 2 "delegation: unverifiable reason=usage"
scn; run_v verify --delegation "$URL" --bogus;   expect "unknown flag" 2 "delegation: unverifiable reason=usage"
scn; run_v verify --delegation "$URL" --envelope env-valid.md --command ""; expect "empty --command" 1 "delegation: invalid reason=command-not-in-envelope"

echo "=== Arm 2: the envelope ==="
CMD1='gh pr merge 123 --squash'
SHA1="$(printf '%s' "$CMD1" | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null; } | cut -d' ' -f1)"
scn; run_v verify --delegation "$URL" --envelope env-valid.md --command "$CMD1"
expect "envelope + command" 0 "delegation: valid reason=ok"
assert_eq "verified-command: $CMD1" "$(sed -n 2p "$TMP/o")" "the verified line is printed byte for byte"
assert_eq "verified-sha256: $SHA1" "$(sed -n 3p "$TMP/o")" "its sha256 is printed"
scn; run_v verify --delegation "$URL" --envelope env-valid.md
expect "envelope without --command" 0 "delegation: valid reason=ok"
assert_eq "0" "$(grep -c '^verified-command:' "$TMP/o")" "no --command, no verified-command line"
scn; run_v verify --delegation "$URL" --envelope missing-file.md;   expect "envelope-missing" 1 "delegation: invalid reason=envelope-missing"
scn; run_v verify --delegation "$URL" --envelope env-uncommitted.md; expect "envelope-not-committed (untracked)" 1 "delegation: invalid reason=envelope-not-committed"
scn; run_v verify --delegation "$URL" --envelope env-modified.md;   expect "envelope-not-committed (modified)" 1 "delegation: invalid reason=envelope-not-committed"
scn; run_v verify --delegation "$URL" --envelope "$TMP/outside.md"; expect "envelope-not-committed (outside a repository)" 1 "delegation: invalid reason=envelope-not-committed"
scn; run_v verify --delegation "$URL" --envelope env-none.md;       expect "no section at all" 1 "delegation: invalid reason=envelope-missing"
scn; run_v verify --delegation "$URL" --envelope env-two.md;        expect "parse-ambiguous (two sections, no anchor)" 1 "delegation: invalid reason=parse-ambiguous"
scn; run_v verify --delegation "$URL" --envelope "env-two.md#nonesuch"; expect "anchor matching nothing" 1 "delegation: invalid reason=envelope-missing"
scn; run_v verify --delegation "$URL" --envelope env-wrongdel.md;   expect "envelope-delegation-mismatch" 1 "delegation: invalid reason=envelope-delegation-mismatch"
scn; run_v verify --delegation "$URL" --envelope env-scope9.md;     expect "no-scope-item (envelope names item 9)" 1 "delegation: invalid reason=no-scope-item"
scn; run_v verify --delegation "$URL" --envelope env-incomplete.md; expect "envelope-incomplete (no Verification)" 1 "delegation: invalid reason=envelope-incomplete"
scn; run_v verify --delegation "$URL" --envelope env-nogate.md;     expect "envelope-incomplete (no Gate)" 1 "delegation: invalid reason=envelope-incomplete"
scn; run_v verify --delegation "$URL" --envelope env-noroll.md;     expect "rollback-unnamed (none)" 1 "delegation: invalid reason=rollback-unnamed"
scn; run_v verify --delegation "$URL" --envelope env-noroll-na.md;  expect "rollback-unnamed (N/A.)" 1 "delegation: invalid reason=rollback-unnamed"
scn; run_v verify --delegation "$URL" --envelope env-noroll-unk.md; expect "rollback-unnamed (Unknown)" 1 "delegation: invalid reason=rollback-unnamed"

echo "=== Arm 2b: the command must be a byte-identical FULL line ==="
mism() { # <name> <command>
  scn; run_v verify --delegation "$URL" --envelope env-valid.md --command "$2"
  expect "$1" 1 "delegation: invalid reason=command-not-in-envelope"
  assert_eq "0" "$(grep -c '^verified-command:' "$TMP/o")" "$1: no verified-command line"
}
mism "prefix of a line"        'gh pr merge 123'
mism "substring of a line"     'pr merge 123 --squash'
mism "trailing space"          'gh pr merge 123 --squash '
mism "case change"             'gh pr merge 123 --SQUASH'
mism "double space"            'gh  pr merge 123 --squash'
mism "extension of a line"     'gh pr merge 123 --squash --delete-branch'
mism "whitespace only"         ' '
mism "multi-line argument"     "$(printf 'gh pr merge 123 --squash\ngh workflow run example-release.yml -f target=staging')"
scn; run_v verify --delegation "$URL" --envelope env-valid.md --command "$CMD1" --command "gh pr merge 999 --squash"
expect "one covered and one uncovered command" 1 "delegation: invalid reason=command-not-in-envelope"
assert_eq "0" "$(grep -c '^verified-command:' "$TMP/o")" "an uncovered command suppresses every verified-command line"
scn; run_v verify --delegation "$URL" --envelope env-valid.md --command "$CMD1" --command "gh workflow run example-release.yml -f target=staging"
expect "two covered commands" 0 "delegation: valid reason=ok"
assert_eq "2" "$(grep -c '^verified-command:' "$TMP/o")" "both covered commands are printed"
scn; run_v verify --delegation "$URL" --envelope env-trailing.md --command 'gh pr merge 124 --squash '
expect "the trailing-space line matches itself (second line, not the first)" 0 "delegation: valid reason=ok"
scn; run_v verify --delegation "$URL" --envelope env-trailing.md --command 'gh pr merge 124 --squash'
expect "the same line without its trailing space does not match" 1 "delegation: invalid reason=command-not-in-envelope"
scn; run_v verify --delegation "$URL" --envelope env-crlf.md --command "$CMD1"
expect "a CRLF envelope line is not the LF command" 1 "delegation: invalid reason=command-not-in-envelope"
scn; run_v verify --delegation "$URL" --envelope env-crlf.md
expect "a CRLF envelope still parses" 0 "delegation: valid reason=ok"

echo "=== Arm 2c: the non-delegable denylist (checked before the match) ==="
for c in 'git push origin main' 'gh pr merge 5 --squash --admin' 'terraform apply -auto-approve' 'gh repo delete example-org/example-repo --yes' \
         'rm -rf build' 'doppler secrets set EXAMPLE=1' 'gh secret set EXAMPLE' 'gh api repos/example-org/example-repo/rulesets/1 -X DELETE'; do
  scn; run_v verify --delegation "$URL" --envelope env-deny.md --command "$c"
  expect "denylist: $c" 1 "delegation: invalid reason=non-delegable-command"
done
scn; run_v verify --delegation "$URL" --envelope env-valid.md --command 'echo ok && git push origin main'
expect "denylist applies inside a compound command" 1 "delegation: invalid reason=non-delegable-command"

echo "=== Arm 3: must-PASS shapes that are not the canonical fixture (H2) ==="
scn; run_v verify --delegation "$URL" --envelope "env-two.md#beta" --command 'gh workflow run example-release.yml -f target=staging'
expect "third Scope item, second envelope section selected by #title" 0 "delegation: valid reason=ok"
scn; run_v verify --delegation "$URL" --envelope "env-two.md#alpha" --command "$CMD1"
expect "first section selected by #title" 0 "delegation: valid reason=ok"
scn; sed 's/$/\r/' "$STUB_DIR/body.md" > "$STUB_DIR/crlf.md"; mk_comment 1001 "$STUB_DIR/crlf.md"
run_v verify --delegation "$URL" --envelope env-valid.md --command "$CMD1"
expect "CRLF comment body (web UI) still verifies" 0 "delegation: valid reason=ok"
scn; awk '{ print } /^$/ { print "" }' "$STUB_DIR/body.md" > "$STUB_DIR/blank.md"
mk_comment 2002 "$STUB_DIR/blank.md" owner-user User "$NOW_ISO" "" 88; echo '{"number":88,"state":"open"}' > "$STUB_DIR/issue-88.json"
run_v verify --delegation "$URL2" --envelope env-valid-b.md --command "$CMD1"
expect "extra blank lines, a different comment id and epic" 0 "delegation: valid reason=ok"
scn; mk_comment 1001 "$STUB_DIR/body.md" team-admin; echo '{"permission":"admin"}' > "$STUB_DIR/perm-team-admin.json"
run_v verify --delegation "$URL"; expect "an admin who is not the owner login (organisation repository)" 0 "delegation: valid reason=ok"
scn; run_v verify --delegation "$URL" --envelope env-valid.md --command "$CMD1" --audit
expect "--audit with a live delegation" 0 "delegation: valid reason=ok"

echo "=== Arm 4: --audit skips ONLY expired and epic-closed ==="
scn; s_closed;   run_v verify --delegation "$URL" --audit; expect "audit passes a closed epic" 0 "delegation: valid reason=ok"
scn; s_expired;  run_v verify --delegation "$URL" --audit; expect "audit passes an expired delegation" 0 "delegation: valid reason=ok"
scn; s_edited;   run_v verify --delegation "$URL" --audit; expect "audit still rejects an edited comment" 1 "delegation: invalid reason=edited"
scn; s_toolong;  run_v verify --delegation "$URL" --audit; expect "audit still rejects expiry-too-long" 1 "delegation: invalid reason=expiry-too-long"
scn; s_nonadmin; run_v verify --delegation "$URL" --audit; expect "audit still rejects a non-admin author" 1 "delegation: invalid reason=not-admin-author"
scn; s_prissue;  run_v verify --delegation "$URL" --audit; expect "audit still rejects a pull-request epic" 1 "delegation: invalid reason=epic-is-pr"

echo "=== Arm 5: render (the skill writes the record) ==="
printf 'Shall I carry the example rollout through to the end by myself?\n' > "$TMP/q.txt"
printf 'Yes, go ahead and own it.\n' > "$TMP/a.txt"
printf 'Merge change 123 with `gh pr merge 123 --squash`\nRevert it if it goes wrong\n' > "$TMP/sc.txt"
run_v render --epic 77 --question-file "$TMP/q.txt" --answer-file "$TMP/a.txt" --scope-file "$TMP/sc.txt" --expiry "$EXP10"
assert_eq "0" "$(last_rc)" "render exits 0"
cp "$TMP/o" "$TMP/rendered.md"
assert_eq "<!-- soleur-delegation v1 -->" "$(head -1 "$TMP/rendered.md")" "the rendered record starts with the marker"
scn; mk_comment 1001 "$TMP/rendered.md"
run_v verify --delegation "$URL" --envelope env-two.md#alpha --command "$CMD1"
expect "a rendered record verifies as valid" 0 "delegation: valid reason=ok"
printf 'Line one of a question\n<!-- soleur-delegation v1 -->\nand a closing line that is long enough\n' > "$TMP/q2.txt"
run_v render --epic 77 --question-file "$TMP/q2.txt" --answer-file "$TMP/a.txt" --scope-file "$TMP/sc.txt" --expiry "$EXP10"
assert_eq "1" "$(grep -c '^<!-- soleur-delegation v1 -->$' "$TMP/o")" "a marker inside the question stays quoted (exactly one bare marker line)"
printf 'Hi?\n' > "$TMP/q3.txt"; printf 'Yes\n' > "$TMP/a3.txt"
run_v render --epic 77 --question-file "$TMP/q3.txt" --answer-file "$TMP/a3.txt" --scope-file "$TMP/sc.txt" --expiry "$EXP10"
assert_eq "2" "$(last_rc)" "render refuses a quote under 40 characters"
assert_eq "0" "$(wc -c < "$TMP/o" | tr -d ' ')" "a refused render prints no body"
run_v render --epic 77 --question-file "$TMP/q.txt" --answer-file "$TMP/a.txt" --scope-file "$TMP/sc.txt" --expiry "$EXP31"
assert_eq "2" "$(last_rc)" "render refuses an expiry beyond 30 days"
run_v render --epic 77 --question-file "$TMP/q.txt" --answer-file "$TMP/a.txt" --scope-file "$TMP/sc.txt" --expiry "not-a-date"
assert_eq "2" "$(last_rc)" "render refuses a malformed expiry"
run_v render --epic 77 --question-file "$TMP/q.txt" --answer-file "$TMP/a.txt" --scope-file "$TMP/missing.txt" --expiry "$EXP10"
assert_eq "2" "$(last_rc)" "render refuses a missing scope file"
: > "$TMP/empty.txt"
run_v render --epic 77 --question-file "$TMP/q.txt" --answer-file "$TMP/a.txt" --scope-file "$TMP/empty.txt" --expiry "$EXP10"
assert_eq "2" "$(last_rc)" "render refuses an empty scope"

echo "=== Arm 6: the format reference is executable (templates verify, keywords agree) ==="
extract() { # <heading line> <open fence> <close fence>
  awk -v h="$1" -v o="$2" -v c="$3" '$0 == h { on = 1; next } on && !inb && $0 == o { inb = 1; next } inb && $0 == c { exit } inb { print }' "$REFERENCE"
}
extract '### Delegation record template' '```text' '```' > "$TMP/tpl-delegation.txt"
extract '### Production Envelope template' '````text' '````' > "$TMP/tpl-envelope.txt"
assert_eq "1" "$([[ -s "$TMP/tpl-delegation.txt" ]] && echo 1 || echo 0)" "the delegation template was extracted"
assert_eq "1" "$([[ -s "$TMP/tpl-envelope.txt" ]] && echo 1 || echo 0)" "the envelope template was extracted"
fill() { # <template> <outfile> <url>
  local t; t="$(cat "$1")"
  t="${t//\{EPIC\}/77}"; t="${t//\{DATE\}/$TODAY}"; t="${t//\{EXPIRY\}/$EXP10}"
  t="${t//\{QUESTION\}/Shall I carry the example rollout through to the end by myself?}"
  t="${t//\{ANSWER\}/Yes, go ahead and own it.}"
  t="${t//\{ACT_CLASS_1\}/Merge change 123 with \`gh pr merge 123 --squash\`.}"; t="${t//\{ACT_CLASS_2\}/Revert it if it goes wrong.}"
  t="${t//\{TITLE\}/template merge}"; t="${t//\{URL\}/$3}"; t="${t//\{N\}/1}"
  t="${t//\{COMMAND\}/gh pr merge 123 --squash}"; t="${t//\{BLAST_RADIUS\}/one example service}"
  t="${t//\{GATE\}/pr-merged 120}"; t="${t//\{VERIFICATION_COMMAND\}/bash scripts/example-probe.sh}"
  t="${t//\{ABORT\}/stop before the merge}"; t="${t//\{ROLLBACK\}/revert the squash commit with a new change}"
  t="${t//\{STOP_CONDITIONS\}/the probe fails}"
  printf '%s\n' "$t" > "$2"
}
fill "$TMP/tpl-delegation.txt" "$TMP/inst-delegation.md" "$URL"
fill "$TMP/tpl-envelope.txt" "$REPO/env-template.md" "$URL"
( git_fixture_env "$REPO" && git -C "$REPO" add env-template.md && git -C "$REPO" commit -q -m "template envelope" ) >/dev/null 2>&1
assert_eq "0" "$(grep -cE '\{[A-Z_0-9]+\}' "$TMP/inst-delegation.md" "$REPO/env-template.md" | awk -F: '{ s += $NF } END { print s + 0 }')" "no placeholder survives instantiation (a new placeholder needs a fill rule here)"
scn; mk_comment 1001 "$TMP/inst-delegation.md"
run_v verify --delegation "$URL" --envelope env-template.md --command "$CMD1"
expect "the instantiated templates verify as valid" 0 "delegation: valid reason=ok"
extract '### Excluded anchor keywords' '```text' '```' > "$TMP/kw-doc.txt"
run_v keywords
assert_eq "$(sort "$TMP/kw-doc.txt")" "$(sort "$TMP/o")" "the reference's anchor keywords equal the verifier's"
assert_eq "10" "$(wc -l < "$TMP/kw-doc.txt" | tr -d ' ')" "there are ten anchor keywords"

echo "=== Arm 7: --self-check is offline ==="
scn; run_v --self-check
assert_eq "0" "$(last_rc)" "self-check exits 0"
assert_eq "delegation-verify: ready" "$(head -1 "$TMP/o")" "self-check prints ready"
assert_eq "0" "$(wc -l < "$STUB_DIR/calls.log" 2>/dev/null | tr -d ' ' || echo 0)" "self-check makes no gh call"

echo "=== Arm 8: a missing tool is exit 2, never a pass ==="
MIN="$TMP/minbin"; mkdir -p "$MIN"
for t in bash awk grep sed git cat mktemp date sha256sum shasum openssl tr cut head tail sort rm mkdir dirname basename sleep wc uniq env printf test expr cmp ls tee; do
  p="$(command -v "$t" 2>/dev/null)"; [[ -n "$p" && "$p" == /* ]] && ln -sf "$p" "$MIN/$t"
done
ln -sf "$BIN/gh" "$MIN/gh"
scn
( cd "$REPO" && PATH="$MIN" "$(command -v bash)" "$SUT" verify --delegation "$URL" ) >"$TMP/o" 2>"$TMP/e"; rc=$?; echo "$rc" > "$TMP/rc"
expect "no jq on PATH" 2 "delegation: unverifiable reason=tool-missing"
( cd "$REPO" && PATH="$MIN" "$(command -v bash)" "$SUT" --self-check ) >"$TMP/o" 2>"$TMP/e"; rc=$?
assert_eq "2" "$rc" "self-check without jq is exit 2"

echo "=== Arm 9: every gh call the verifier made was a read ==="
bad=0
for f in "$TMP"/scn*/calls.log; do
  [[ -f "$f" ]] || continue
  n="$(grep -vcE '^(api repos/[A-Za-z0-9_./-]+|repo view --json nameWithOwner --jq \.nameWithOwner)$' "$f")"
  bad=$((bad + n))
done
assert_eq "0" "$bad" "no gh call outside the read-only shapes across all scenarios"
assert_eq "0" "$(cat "$TMP"/scn*/calls.log | grep -cE ' (-X|--method|-f|-F|--field|--raw-field|--input) |^(issue|pr) (comment|edit|close|merge)')" "no write verb or write flag reached gh"

echo "=== Arm 10: mutations (the pristine control first) ==="
MUT="$TMP/mut"; mkdir -p "$MUT"; PRISTINE="$MUT/dv.pristine.sh"; cp "$SUT_REAL" "$PRISTINE"
mutate() { # <name> <sed -E expr>: write $MUT/dv.<name>.sh and prove the mutation LANDED
  sed -E "$2" "$PRISTINE" > "$MUT/dv.$1.sh"
  if cmp -s "$PRISTINE" "$MUT/dv.$1.sh"; then echo "  FAIL: mutation $1 did not land"; FAIL=$((FAIL + 1)); return 1; fi
  echo "  PASS: mutation $1 landed"; PASS=$((PASS + 1))
}
noop() { echo "s/^.*# mut:$1\$/: # mut:$1/"; }
probe() { # <setup-fn> <args...> -> PROBE_OUT="rc|verdict|verified-lines" (no subshell: scenario numbering must advance)
  local fn="$1"; shift
  scn; "$fn"; run_v "$@"
  PROBE_OUT="$(last_rc)|$(head -1 "$TMP/o")|$(grep -c '^verified-command:' "$TMP/o")"
}
crashed() { [[ "$(last_rc)" == 127 ]] || grep -qE 'unbound variable|syntax error|command not found' "$TMP/e"; }
killed() { # <name> <pinned> <setup-fn> <args...>
  local name="$1" pinned="$2" got; shift 2
  SUT="$PRISTINE"; probe "$@"; got="$PROBE_OUT"
  if [[ "$got" != "$pinned" ]]; then echo "  FAIL: $name: the pristine script gives '$got', not the pinned '$pinned'"; FAIL=$((FAIL + 1)); SUT="$SUT_REAL"; return; fi
  SUT="$MUT/dv.$name.sh"; probe "$@"; got="$PROBE_OUT"
  if crashed; then echo "  FAIL: mutant $name CRASHED; a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$got" != "$pinned" ]]; then echo "  PASS: mutant $name killed ('$got')"; PASS=$((PASS + 1))
  else echo "  FAIL: mutant $name SURVIVED ('$got')"; FAIL=$((FAIL + 1)); fi
  SUT="$SUT_REAL"
}
nothing() { :; }
SUT="$PRISTINE"; probe nothing verify --delegation "$URL"; assert_eq "0|delegation: valid reason=ok|0" "$PROBE_OUT" "mutation control: the pristine copy is green"; SUT="$SUT_REAL"
( b=$FAIL; killed ctrl "1|never" nothing verify --delegation "$URL" >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: killed cannot report a survivor\n' >&2; exit 2; }
( b=$FAIL; mutate ctrl 's/zz-no-such-text-zz/y/' >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: mutate cannot report a mutation that did not land\n' >&2; exit 2; }

# 1 author authority
mutate admin "$(noop admin)" && killed admin "1|delegation: invalid reason=not-admin-author|0" s_nonadmin verify --delegation "$URL"
mutate bot "$(noop bot)" && killed bot "1|delegation: invalid reason=bot-author|0" s_bot verify --delegation "$URL"
# 2 dispatch
mutate dispatch "$(noop dispatch)" && killed dispatch "2|delegation: unverifiable reason=usage|0" nothing
# 4 edited
mutate edited "$(noop edited)" && killed edited "1|delegation: invalid reason=edited|0" s_edited verify --delegation "$URL"
# 5 expiry cap and presence
mutate expiry-cap "$(noop expiry-cap)" && killed expiry-cap "1|delegation: invalid reason=expiry-too-long|0" s_toolong verify --delegation "$URL"
mutate expiry-missing "$(noop expiry-missing)" && killed expiry-missing "1|delegation: invalid reason=expiry-missing|0" s_noexp verify --delegation "$URL"
mutate expired "$(noop expired)" && killed expired "1|delegation: invalid reason=expired|0" s_expired verify --delegation "$URL"
# 6 API error never becomes a pass; epic-open
mutate api-error "$(noop api-error)" && killed api-error "2|delegation: unverifiable reason=api-error|0" s_issueerr verify --delegation "$URL"
mutate epic-open "$(noop epic-open)" && killed epic-open "1|delegation: invalid reason=epic-closed|0" s_closed verify --delegation "$URL"
# 7 foreign repository
mutate wrong-repo "$(noop wrong-repo)" && killed wrong-repo "1|delegation: invalid reason=wrong-repo|0" nothing verify --delegation "https://github.com/other-org/other-repo/issues/77#issuecomment-1001"
# 8 confirmation and quote length
mutate confirmation "$(noop confirmation)" && killed confirmation "1|delegation: invalid reason=no-confirmation|0" s_noconfirm verify --delegation "$URL"
mutate quote-len "$(noop quote-len)" && killed quote-len "1|delegation: invalid reason=quote-too-short|0" s_shortq verify --delegation "$URL"
mutate scope "$(noop scope)" && killed scope "1|delegation: invalid reason=no-scope-item|0" s_noscope verify --delegation "$URL"
mutate excluded "$(noop excluded)" && killed excluded "1|delegation: invalid reason=excluded-incomplete|0" s_exclinc verify --delegation "$URL"
# 9 a mismatch must not print a verified-command; 3 exact full-line match only
mutate cmd-match "$(noop cmd-match)" && killed cmd-match "1|delegation: invalid reason=command-not-in-envelope|0" nothing verify --delegation "$URL" --envelope env-valid.md --command "gh pr merge 999 --squash"
mutate prefix 's/\(\$0 ""\) == \(c ""\)/index($0, c) == 1/' && killed prefix "1|delegation: invalid reason=command-not-in-envelope|0" nothing verify --delegation "$URL" --envelope env-valid.md --command "gh pr merge 123"
mutate first-line 's/\(\$0 ""\) == \(c ""\)/NR == 1 \&\& ($0 "") == (c "")/' && killed first-line "0|delegation: valid reason=ok|1" nothing verify --delegation "$URL" --envelope env-trailing.md --command 'gh pr merge 124 --squash '
# 10 denylist, committed, issue binding
mutate denylist "$(noop denylist)" && killed denylist "1|delegation: invalid reason=non-delegable-command|0" nothing verify --delegation "$URL" --envelope env-deny.md --command "git push origin main"
mutate committed "$(noop committed)" && killed committed "1|delegation: invalid reason=envelope-not-committed|0" nothing verify --delegation "$URL" --envelope env-uncommitted.md
mutate issue-bind "$(noop issue-bind)" && killed issue-bind "1|delegation: invalid reason=wrong-issue|0" s_wrongissue verify --delegation "$URL"
mutate epic-pr "$(noop epic-pr)" && killed epic-pr "1|delegation: invalid reason=epic-is-pr|0" s_prissue verify --delegation "$URL"
mutate rollback "$(noop rollback)" && killed rollback "1|delegation: invalid reason=rollback-unnamed|0" nothing verify --delegation "$URL" --envelope env-noroll.md
mutate env-delegation "$(noop env-delegation)" && killed env-delegation "1|delegation: invalid reason=envelope-delegation-mismatch|0" nothing verify --delegation "$URL" --envelope env-wrongdel.md
# 11 --audit may skip ONLY expired and epic-closed
mutate audit-edited 's/\|\| (fail_invalid edited "[^"]*")/|| { (( AUDIT )) || \1; }/' && killed audit-edited "1|delegation: invalid reason=edited|0" s_edited verify --delegation "$URL" --audit

echo "=== Floor: the SUT answered every row ==="
n_calls="$(cat "$TMP"/scn*/calls.log 2>/dev/null | wc -l | tr -d ' ')"
if (( n_calls >= 150 )); then echo "  PASS: gh stub calls $n_calls >= 150"; PASS=$((PASS + 1))
else echo "  FAIL: gh stub calls $n_calls < 150 -- the rows did not drive the script"; FAIL=$((FAIL + 1)); fi

print_results 340
