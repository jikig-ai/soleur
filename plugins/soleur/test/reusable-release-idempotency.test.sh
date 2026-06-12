#!/usr/bin/env bash
# Verifies the stuck-draft-release deadlock fix in
# .github/workflows/reusable-release.yml (#4902).
#
# Background: the release pipeline creates GitHub Releases as `--draft` (a draft
# materializes NO git tag), then a Finalise step flips `--draft=false` to publish.
# If a transient failure orphans a draft, the OLD idempotency check
# (`gh release view "$TAG"` -> exists=true -> skip) found the orphaned draft on
# every later run and skipped re-creation FOREVER, freezing the git-tag baseline
# and the computed BUILD_VERSION. The fix makes idempotency draft-aware: a draft
# yields exists=false + draft_exists=true so the Finalise step re-publishes it
# (self-heal). The logic is prefix-agnostic (v / web-v / telegram-v).
#
# This test removes the live GitHub API from the assertion path by executing the
# REAL `Check idempotency` run-block (extracted verbatim from the workflow) under
# a deterministic `gh` stub, then statically asserts the create/finalise gating
# wiring. Run via:  bash plugins/soleur/test/reusable-release-idempotency.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}
# Explicit if/then/else (not `cond && pass || fail`) keeps this shellcheck-clean
# (no SC2015) and matches the sibling concurrent-ship.test.sh convention.
assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc -> got '$got', want '$want'"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extract the `Check idempotency` step's `run:` block verbatim from the workflow.
# awk walks from the step's `- name: Check idempotency` to the next `- name:`,
# captures the lines after `run: |`, and dedents to the block-scalar base indent.
# Keeping the workflow as the single source of truth (no copy-paste of the logic)
# means this test exercises the REAL shell that ships.
# ---------------------------------------------------------------------------
extract_run_block() {
  local step_name="$1"
  # Buffer the block, then dedent by the MINIMUM leading-whitespace across all
  # non-blank run lines (not the first line's indent) so a future edit that
  # reorders the block cannot silently over-dedent and corrupt the shell.
  # index() (literal substring), not a dynamic regex: step names contain
  # regex metachars like "(release)" which a `$0 ~` match would treat as a
  # group and never find.
  awk -v target="$step_name" '
    index($0, "- name: " target) && /^[[:space:]]*- name: / { instep=1; next }
    instep && /^[[:space:]]*- name: / { exit }
    instep && /^[[:space:]]*run: \|/ { inrun=1; next }
    inrun {
      lines[n++] = $0
      if ($0 !~ /^[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        if (base == 0 || RLENGTH < base) base = RLENGTH
      }
    }
    END { for (i = 0; i < n; i++) print substr(lines[i], base + 1) }
  ' "$WF"
}

IDEMPOTENCY_BLOCK="$TMP/idempotency.sh"
extract_run_block "Check idempotency" > "$IDEMPOTENCY_BLOCK"

if [[ ! -s "$IDEMPOTENCY_BLOCK" ]]; then
  fail "could not extract 'Check idempotency' run block from $WF"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# The extracted block calls `jq` (the workflow's idempotency step parses
# `--json isDraft`). Fail with a clear cause on a jq-less runner instead of a
# confusing `<unset>` mismatch in the published/draft scenarios.
if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required to run this test (the idempotency block parses gh --json output)"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Deterministic `gh` stub. Behavior is driven by MOCK_GH_STATE:
#   absent     -> release does not exist
#   published  -> release exists, isDraft=false
#   draft      -> release exists (orphaned), isDraft=true
# Records create/edit invocations to $GH_TRACE so callers can assert side effects.
# ---------------------------------------------------------------------------
GH_STUB_DIR="$TMP/bin"
mkdir -p "$GH_STUB_DIR"
cat > "$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# args: release <subcmd> <tag> [flags...]
sub="${2:-}"
case "$sub" in
  view)
    has_json=0
    for a in "$@"; do [[ "$a" == "--json" ]] && has_json=1; done
    case "$MOCK_GH_STATE" in
      published)
        if [[ "$has_json" == 1 ]]; then echo '{"isDraft":false}'; fi
        exit 0 ;;
      draft)
        if [[ "$has_json" == 1 ]]; then echo '{"isDraft":true}'; fi
        exit 0 ;;
      *) exit 1 ;;  # absent
    esac ;;
  edit)
    printf 'edit %s\n' "$*" >> "$GH_TRACE"
    exit 0 ;;
  create)
    printf 'create %s\n' "$*" >> "$GH_TRACE"
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$GH_STUB_DIR/gh"

# Run the extracted idempotency block for one scenario; echo the resulting
# `exists` and `draft_exists` outputs as "<exists> <draft_exists>".
run_idempotency() {
  local state="$1" tag="$2"
  local out="$TMP/gho.$$.$RANDOM"
  : > "$out"
  MOCK_GH_STATE="$state" \
  GH_TRACE="$TMP/trace.$$" \
  GITHUB_OUTPUT="$out" \
  TAG="$tag" \
  PATH="$GH_STUB_DIR:$PATH" \
    bash "$IDEMPOTENCY_BLOCK" >/dev/null 2>&1
  local e d
  e=$(grep -E '^exists=' "$out" | tail -1 | cut -d= -f2)
  d=$(grep -E '^draft_exists=' "$out" | tail -1 | cut -d= -f2)
  echo "${e:-<unset>} ${d:-<unset>}"
}

echo "=== reusable-release idempotency (draft-aware self-heal) tests ==="
echo ""

# ---------------------------------------------------------------------------
# T1: decision matrix (the core of #4902). Lane-agnostic via web-v tag.
# ---------------------------------------------------------------------------
echo "T1: Check idempotency decision matrix"

assert_eq "absent   -> exists=false draft_exists=false" \
  "$(run_idempotency absent "web-v0.101.100")" "false false"
assert_eq "published -> exists=true  draft_exists=false" \
  "$(run_idempotency published "web-v0.101.100")" "true false"
assert_eq "draft     -> exists=false draft_exists=true (self-heal; must NOT lock the pipeline)" \
  "$(run_idempotency draft "web-v0.101.100")" "false true"

# ---------------------------------------------------------------------------
# T2: lane-agnostic (AC6) — identical decision for v / web-v / telegram-v in the
# draft scenario (no prefix-specific branch leaked into the logic).
# ---------------------------------------------------------------------------
echo "T2: lane-agnostic draft decision"
for tag in "v0.5.0" "web-v0.101.100" "telegram-v0.3.0"; do
  assert_eq "draft($tag) -> false true" "$(run_idempotency draft "$tag")" "false true"
done

# ---------------------------------------------------------------------------
# T3: create-step gating (AC2/AC4) — create must NOT fire when an orphaned draft
# already exists (gh release create errors on an existing tag); it is gated on
# both exists==false AND draft_exists==false.
# ---------------------------------------------------------------------------
echo "T3: Create step gated on draft_exists == 'false'"
create_if=$(awk '
  /- name: Create GitHub Release \(as draft\)/ { f=1; next }
  f && /^[[:space:]]*if:/ { print; exit }
' "$WF")
if grep -qE "idempotency\.outputs\.draft_exists == 'false'" <<<"$create_if"; then
  pass "create if: requires draft_exists == 'false'"
else
  fail "create if: must gate on draft_exists == 'false' (got: ${create_if:-<none>})"
fi

# ---------------------------------------------------------------------------
# T4: finalise-step self-heal gate (AC2) — Finalise must publish when EITHER a
# new draft was created OR an orphaned draft exists.
# ---------------------------------------------------------------------------
echo "T4: Finalise step re-publishes orphaned drafts"
finalise_if=$(awk '
  /- name: Finalise release \(publish draft\)/ { f=1; next }
  f && /^[[:space:]]*if:/ { print; got=1 }
  f && got && /draft_exists/ { print }
  f && /^[[:space:]]*env:/ { exit }
' "$WF")
if grep -qE "idempotency\.outputs\.draft_exists == 'true'" <<<"$finalise_if"; then
  pass "finalise if: includes draft_exists == 'true' disjunct (self-heal)"
else
  fail "finalise if: must publish when draft_exists == 'true' (got: ${finalise_if:-<none>})"
fi

# ---------------------------------------------------------------------------
# T5: immutable-release flow preserved (AC3) — create step still uses --draft.
# ---------------------------------------------------------------------------
echo "T5: --draft create flow preserved"
create_block=$(awk '
  /- name: Create GitHub Release \(as draft\)/ { f=1 }
  f { print }
  f && /Created draft release/ { exit }
' "$WF")
if grep -qE -- '--draft$' <<<"$create_block"; then
  pass "create step still passes --draft (immutable-upload flow intact)"
else
  fail "create step must keep --draft (immutable-release 422 mitigation)"
fi

# ---------------------------------------------------------------------------
# T6: notify-on-self-heal (#4902) — Email + Slack notify must ALSO fire on the
# orphaned-draft re-publish path (the prior run died before notify, so this is
# the first successful announcement). Pins the behavior so a future edit can't
# silently revert it to create-only. The Sentry-audit step deliberately stays
# create-only (asset upload, not announcement) and is NOT asserted here.
# (Release notifications moved Discord -> Slack in #5079.)
# ---------------------------------------------------------------------------
echo "T6: Email + Slack notify fire on the self-heal path"
for step in "Email notification (release)" "Post to Slack (release)"; do
  notify_if=$(awk -v s="- name: $step" '
    index($0, s) && /^[[:space:]]*- name: / { f=1; next }
    f && /^[[:space:]]*if:/ { capture=1 }
    f && capture { print }
    f && capture && /^[[:space:]]*(continue-on-error|env|uses|with|run):/ { exit }
  ' "$WF")
  if grep -qE "idempotency\.outputs\.draft_exists == 'true'" <<<"$notify_if"; then
    pass "'$step' if: includes draft_exists == 'true' disjunct"
  else
    fail "'$step' must notify on self-heal (got: ${notify_if:-<none>})"
  fi
  # Pin the FULL gate, not just the self-heal disjunct: dropping the
  # released == 'true' branch would silently kill notifications on every
  # NORMAL release while this suite stays green.
  if grep -qE "create_release\.outputs\.released == 'true'" <<<"$notify_if"; then
    pass "'$step' if: includes released == 'true' disjunct (normal path)"
  else
    fail "'$step' must notify on normal releases (got: ${notify_if:-<none>})"
  fi
done

# ---------------------------------------------------------------------------
# T7: Slack payload contract (#5079) — execute the REAL "Post to Slack
# (release)" run-block under a curl stub and assert: (a) empty webhook skips
# without calling curl; (b) the payload is valid JSON with mrkdwn
# single-asterisk bold and unfurl_links=false; (c) Slack control chars in the
# release notes are entity-escaped (mass-ping / disguised-link suppression,
# the allowed_mentions equivalent of the old Discord payload).
# ---------------------------------------------------------------------------
echo "T7: Slack payload contract"

SLACK_BLOCK="$TMP/slack.sh"
extract_run_block "Post to Slack (release)" > "$SLACK_BLOCK"

if [[ ! -s "$SLACK_BLOCK" ]]; then
  fail "could not extract 'Post to Slack (release)' run block from $WF"
else
  cat > "$GH_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Records the -d payload to $CURL_TRACE and returns HTTP 200.
prev=""
for a in "$@"; do
  if [[ "$prev" == "-d" ]]; then printf '%s' "$a" > "$CURL_TRACE"; fi
  prev="$a"
done
echo -n "200"
STUB
  chmod +x "$GH_STUB_DIR/curl"

  NOTES="$TMP/notes.md"
  # Fixture mixes (a) injection-bait (<Suspense>, &, <!channel>) and (b) GFM
  # formatting (**bold**, [docs](url)) so T7 asserts BOTH the escape guarantee
  # AND the GFM->mrkdwn conversion the converter now performs.
  printf -- '- fix: handle <Suspense> boundary & retries <!channel> for <@U1>\n' > "$NOTES"
  printf -- 'Some **bold** text and a [docs](https://x.io) link.\n' >> "$NOTES"

  run_slack() {
    local webhook="$1"
    : > "$TMP/curl-trace"
    # cd to REPO_ROOT so the step's repo-root-relative `node
    # scripts/md-to-mrkdwn.mjs` resolves exactly as it does in CI (run: blocks
    # execute from $GITHUB_WORKSPACE = repo root). Trace/notes paths are
    # absolute, so the cd is safe.
    ( cd "$REPO_ROOT" && \
      SLACK_RELEASES_WEBHOOK_URL="$webhook" \
      TAG="web-v1.2.3" \
      VERSION="1.2.3" \
      COMPONENT_DISPLAY="Web Platform" \
      RELEASE_NOTES_FILE="$NOTES" \
      GITHUB_SERVER_URL="https://github.com" \
      GITHUB_REPOSITORY="jikig-ai/soleur" \
      CURL_TRACE="$TMP/curl-trace" \
      PATH="$GH_STUB_DIR:$PATH" \
        bash "$SLACK_BLOCK" >/dev/null 2>&1 )
  }

  # (a) empty webhook -> skip, curl never invoked
  run_slack ""
  assert_eq "empty webhook -> exit 0, no curl call" \
    "$? $(wc -c < "$TMP/curl-trace" | tr -d ' ')" "0 0"

  # (b)+(c) configured webhook -> payload shape + escaping
  run_slack "https://hooks.example.invalid/stub"
  payload=$(cat "$TMP/curl-trace")
  if jq -e . >/dev/null 2>&1 <<<"$payload"; then
    pass "payload is valid JSON"
  else
    fail "payload is not valid JSON (got: ${payload:-<empty>})"
  fi
  assert_eq "unfurl_links disabled" "$(jq -r '.unfurl_links' <<<"$payload")" "false"
  text=$(jq -r '.text' <<<"$payload")
  case "$text" in
    "*Web Platform v1.2.3 released!*"*) pass "mrkdwn single-asterisk bold header" ;;
    *) fail "header must use *single asterisk* bold (got: ${text:0:60})" ;;
  esac
  if [[ "$text" == *"&lt;!channel&gt;"* && "$text" == *"&lt;Suspense&gt;"* && "$text" == *"&amp; retries"* ]]; then
    pass "Slack control chars (&, <, >) entity-escaped in notes body"
  else
    fail "notes body must escape & < > (got: $text)"
  fi
  case "$text" in
    *"<!channel>"*) fail "raw <!channel> must never reach the payload" ;;
    *) pass "no raw mass-ping sequence in payload" ;;
  esac
  case "$text" in
    *"Full release notes: https://github.com/jikig-ai/soleur/releases/tag/web-v1.2.3"*) pass "release URL present and last" ;;
    *) fail "release URL missing from message tail" ;;
  esac

  # (c2) GFM -> mrkdwn conversion: the changelog body is converted, not just
  # escaped. **bold** -> *bold*, [docs](url) -> <url|docs>, and the literal
  # GFM markers must NOT survive in the payload.
  if [[ "$text" == *"Some *bold* text"* ]]; then
    pass "GFM **bold** converted to *bold* in payload"
  else
    fail "GFM **bold** must convert to *bold* (got: $text)"
  fi
  if [[ "$text" == *"<https://x.io|docs>"* ]]; then
    pass "GFM [docs](url) converted to <url|docs> in payload"
  else
    fail "GFM link must convert to <url|label> (got: $text)"
  fi
  case "$text" in
    *"**bold**"*) fail "literal GFM **bold** must not survive conversion" ;;
    *) pass "no literal GFM bold markers in payload" ;;
  esac

  # (c3) Keystone fail-closed invariant on the FULL payload .text: regardless
  # of how a mention was crafted, the converted output contains zero
  # <! / <@ / <# / <subteam^ sequences (the single backstop against every
  # injection-smuggling path). [P1-C]
  # NOTE: the mention-prefix alphabet (! @ # subteam^) is mirrored in
  # scripts/md-to-mrkdwn.test.mjs (the `/<(!|@|#|subteam\^)/` keystone regex)
  # and in ci-workflow-authoring.md's mapping table — keep all three in sync if
  # Slack adds a new mention prefix. (The converter itself escapes EVERY `<` in
  # text nodes, so a drifted alphabet here weakens detection, not the defense.)
  case "$text" in
    *"<!"*|*"<@"*|*"<#"*|*"<subteam^"*)
      fail "keystone: payload must contain no <! <@ <# <subteam^ (got: $text)" ;;
    *) pass "keystone: payload free of smuggled-mention sequences" ;;
  esac

  # (d) AC5: converter crash -> fallback to the sed-escaped plain body, step
  # stays green. Stub `node` to exit non-zero and run the block under
  # `bash -eo pipefail` (errexit, as CI does) to prove the `if ! BODY=$(...)`
  # form does NOT mask the failure — a bare `BODY=$(node ...)` assignment
  # would abort the step under -e and the fallback would never fire.
  cat > "$GH_STUB_DIR/node" <<'NODESTUB'
#!/usr/bin/env bash
exit 1
NODESTUB
  chmod +x "$GH_STUB_DIR/node"
  : > "$TMP/curl-trace"
  ( cd "$REPO_ROOT" && \
    SLACK_RELEASES_WEBHOOK_URL="https://hooks.example.invalid/stub" \
    TAG="web-v1.2.3" \
    VERSION="1.2.3" \
    COMPONENT_DISPLAY="Web Platform" \
    RELEASE_NOTES_FILE="$NOTES" \
    GITHUB_SERVER_URL="https://github.com" \
    GITHUB_REPOSITORY="jikig-ai/soleur" \
    CURL_TRACE="$TMP/curl-trace" \
    PATH="$GH_STUB_DIR:$PATH" \
      bash -eo pipefail "$SLACK_BLOCK" >/dev/null 2>&1 )
  fallback_rc=$?
  rm -f "$GH_STUB_DIR/node"
  assert_eq "AC5: converter crash keeps release step green (exit 0)" "$fallback_rc" "0"
  fallback_text=$(jq -r '.text' <<<"$(cat "$TMP/curl-trace")")
  if [[ "$fallback_text" == *"&lt;!channel&gt;"* ]]; then
    pass "AC5: fallback sed-escaped body remains injection-safe"
  else
    fail "AC5: fallback body must be sed-escaped (got: $fallback_text)"
  fi
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
