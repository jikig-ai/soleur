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
# wiring. T6b/T7b (#7256) pin the BLOCKED-release Slack notifier on the parsed workflow.
# Run via:  bash plugins/soleur/test/reusable-release-idempotency.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# REUSABLE_RELEASE_WF is a TEST-ONLY hook so a mutation proof can edit a COPY of the
# workflow (#7256); CI never sets it, and the real run must have it unset.
WF="${REUSABLE_RELEASE_WF:-$REPO_ROOT/.github/workflows/reusable-release.yml}"

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

if [[ -n "${REUSABLE_RELEASE_WF:-}" ]]; then
  echo "NOTE: REUSABLE_RELEASE_WF override active -> $WF"
fi
# T6b/T7b read the workflow through PyYAML; without it every helper call is an opaque
# `<rc=1>` mismatch, so name the cause once instead.
if ! python3 -I -c 'import yaml' 2>/dev/null; then
  fail "PyYAML is required (python3 -c 'import yaml') for T6b/T7b"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

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

# ---------------------------------------------------------------------------
# T6b (#7256): the BLOCKED-release Slack notifier. The success step carries a
# plain `if:` (implicit success()), so a release job that fails (zot mirror gate)
# skips it; a failure-gated SIBLING announces the blocked release. Everything is
# read from the PARSED workflow (yaml.safe_load): comments are structurally
# excluded and every `if:` is compared as a whole value, never grepped for a
# token. A missing step / empty lookup / YAML error is an explicit FAIL.
# ---------------------------------------------------------------------------
echo "T6b: BLOCKED-release Slack notifier gate (#7256)"

STEP_OK="Post to Slack (release)"
STEP_BLOCKED="Post to Slack (release BLOCKED)"
STEP_EMAIL_FAILED="Email notification (release FAILED)"

# wf_step_field <step name> <field> -- prints the field of the step whose name is
# EXACTLY <step name>. Fields: if (whitespace-collapsed), env.<KEY>,
# continue-on-error, run. Exit 3 = step not found, 4 = field absent.
wf_step_field() {
  WF_PATH="$WF" STEP="$1" FIELD="$2" python3 -I -c '
import os, sys, yaml
doc = yaml.safe_load(open(os.environ["WF_PATH"]))
steps = []
for job in (doc.get("jobs") or {}).values():
    steps.extend(job.get("steps") or [])
hits = [s for s in steps if s.get("name") == os.environ["STEP"]]
if len(hits) != 1:
    sys.exit(3)
st, f = hits[0], os.environ["FIELD"]
if f.startswith("env."):
    v = (st.get("env") or {}).get(f[4:])
else:
    v = st.get(f)
if v is None:
    sys.exit(4)
print(" ".join(str(v).split()) if f == "if" else v)
' 2>/dev/null
}

# wf_slack_census -- names of every step whose structure references the releases
# webhook secret, sorted, one per line. Derived from the parsed workflow so a
# THIRD notifier with a plain `if:` cannot appear unnoticed.
wf_slack_census() {
  WF_PATH="$WF" python3 -I -c '
import json, os, yaml
doc = yaml.safe_load(open(os.environ["WF_PATH"]))
names = []
for job in (doc.get("jobs") or {}).values():
    for s in job.get("steps") or []:
        if "secrets.SLACK_RELEASES_WEBHOOK_URL" in json.dumps(s):
            names.append(str(s.get("name")))
print("\n".join(sorted(names)))
' 2>/dev/null
}

# wf_step_index <name> -- 0-based position of the step with EXACTLY that name in its job.
wf_step_index() {
  WF_PATH="$WF" STEP="$1" python3 -I -c '
import os, sys, yaml
doc = yaml.safe_load(open(os.environ["WF_PATH"]))
for job in (doc.get("jobs") or {}).values():
    for i, s in enumerate(job.get("steps") or []):
        if s.get("name") == os.environ["STEP"]:
            print(i); sys.exit(0)
sys.exit(3)
' 2>/dev/null
}

# wf_ref_check <name> -- "refs=<sorted ids>;unresolved=<ids no step defines>" for every
# `steps.<id>.` token in that step's `if:` and `env:`. An id that no step defines resolves to
# the empty string in Actions, so a renamed id silently blanks the value (T7b sets env directly
# and cannot see it).
wf_ref_check() {
  WF_PATH="$WF" STEP="$1" python3 -I -c '
import json, os, re, sys, yaml
doc = yaml.safe_load(open(os.environ["WF_PATH"]))
for job in (doc.get("jobs") or {}).values():
    steps = job.get("steps") or []
    ids = {s.get("id") for s in steps if s.get("id")}
    for s in steps:
        if s.get("name") == os.environ["STEP"]:
            blob = json.dumps([s.get("if"), s.get("env")])
            refs = sorted(set(re.findall(r"steps\.([A-Za-z0-9_-]+)\.", blob)))
            print("refs=" + ",".join(refs) + ";unresolved=" + ",".join(r for r in refs if r not in ids))
            sys.exit(0)
sys.exit(3)
' 2>/dev/null
}

# wf_env_keys <name> -- sorted env keys of the step, comma-joined (an extra key is a wiring change).
wf_env_keys() {
  WF_PATH="$WF" STEP="$1" python3 -I -c '
import os, sys, yaml
doc = yaml.safe_load(open(os.environ["WF_PATH"]))
for job in (doc.get("jobs") or {}).values():
    for s in job.get("steps") or []:
        if s.get("name") == os.environ["STEP"]:
            print(",".join(sorted((s.get("env") or {}).keys()))); sys.exit(0)
sys.exit(3)
' 2>/dev/null
}

GATE_INFLIGHT="steps.check_changed.outputs.changed == 'true' && (steps.create_release.outputs.released == 'true' || steps.idempotency.outputs.draft_exists == 'true')"

assert_eq "success announcer gate unchanged (P3, byte-for-byte)" \
  "$(wf_step_field "$STEP_OK" if || echo "<rc=$?>")" "$GATE_INFLIGHT"
assert_eq "BLOCKED notifier gate: !cancelled() && failure() && release-in-flight (P1, P2)" \
  "$(wf_step_field "$STEP_BLOCKED" if || echo "<rc=$?>")" "!cancelled() && failure() && $GATE_INFLIGHT"
assert_eq "failure email gate unchanged (P4)" \
  "$(wf_step_field "$STEP_EMAIL_FAILED" if || echo "<rc=$?>")" "failure()"
assert_eq "BLOCKED notifier is continue-on-error" \
  "$(wf_step_field "$STEP_BLOCKED" continue-on-error || echo "<rc=$?>")" "True"
assert_eq "Slack census: exactly the success announcer and the BLOCKED notifier" \
  "$(wf_slack_census | tr '\n' '|')" "$STEP_BLOCKED|$STEP_OK|"

# Env wiring: T7b sets env directly and cannot see a mis-wired `env:` line.
for pair in \
  "MIRROR_REASON=\${{ steps.zot_mirror.outputs.mirror_reason }}" \
  "TOKEN_VERDICT=\${{ steps.token_preflight.outputs.verdict }}" \
  "TAG=\${{ steps.version.outputs.tag }}" \
  "VERSION=\${{ steps.version.outputs.next }}" \
  "SLACK_RELEASES_WEBHOOK_URL=\${{ secrets.SLACK_RELEASES_WEBHOOK_URL }}" \
  "COMPONENT_DISPLAY=\${{ inputs.component_display }}" \
  "RUN_URL=\${{ github.server_url }}/\${{ github.repository }}/actions/runs/\${{ github.run_id }}"; do
  key="${pair%%=*}"
  assert_eq "BLOCKED notifier env.$key wiring" \
    "$(wf_step_field "$STEP_BLOCKED" "env.$key" || echo "<rc=$?>")" "${pair#*=}"
done
assert_eq "BLOCKED notifier env key set is exactly the seven wired keys" \
  "$(wf_env_keys "$STEP_BLOCKED" || echo "<rc=$?>")" \
  "COMPONENT_DISPLAY,MIRROR_REASON,RUN_URL,SLACK_RELEASES_WEBHOOK_URL,TAG,TOKEN_VERDICT,VERSION"
assert_eq "BLOCKED notifier: every steps.<id> it reads is defined by a step" \
  "$(wf_ref_check "$STEP_BLOCKED" || echo "<rc=$?>")" \
  "refs=check_changed,create_release,idempotency,token_preflight,version,zot_mirror;unresolved="
# T7b runs the block under `bash`; a `shell:` override would change what Actions runs.
assert_eq "BLOCKED notifier carries no shell: override" \
  "$(wf_step_field "$STEP_BLOCKED" shell || echo "<rc=$?>")" "<rc=4>"

# Position: `failure()` is evaluated when the step is reached, so the notifier only works
# AFTER every step that can fail the release, and `released` is only set by create_release.
idx_blocked=$(wf_step_index "$STEP_BLOCKED" || echo -1)
idx_finalise=$(wf_step_index "Finalise release (publish draft)" || echo 999999)
idx_teardown=$(wf_step_index "Tear down cloudflared registry bridge" || echo 999999)
idx_create=$(wf_step_index "Create GitHub Release (as draft)" || echo 999999)
if [[ "$idx_blocked" -gt "$idx_finalise" && "$idx_blocked" -gt "$idx_teardown" && "$idx_blocked" -gt "$idx_create" ]]; then
  pass "BLOCKED notifier runs after create_release, teardown and Finalise"
else
  fail "BLOCKED notifier misplaced (blocked=$idx_blocked finalise=$idx_finalise teardown=$idx_teardown create=$idx_create)"
fi

# The in-flight predicate is defined by Finalise and shared by the announcers; derive parity
# from the real steps rather than trusting one literal copied into two of four sites.
assert_eq "Finalise gate == in-flight predicate" \
  "$(wf_step_field "Finalise release (publish draft)" if || echo "<rc=$?>")" "$GATE_INFLIGHT"
assert_eq "Email (release) gate == in-flight predicate" \
  "$(wf_step_field "Email notification (release)" if || echo "<rc=$?>")" "$GATE_INFLIGHT"

# ---------------------------------------------------------------------------
# T7b (#7256): execute the BLOCKED step's REAL run block (parsed, so the dedent is
# faithful) under the curl stub, `bash -eo pipefail` as CI runs it. Unambiguous
# sentinels: ordinary prose or the remedy sentence could contain "bridge"/"live".
# ---------------------------------------------------------------------------
echo "T7b: BLOCKED-release Slack payload contract (#7256)"

BLOCKED_BLOCK="$TMP/slack-blocked.sh"
wf_step_field "$STEP_BLOCKED" run > "$BLOCKED_BLOCK" || : > "$BLOCKED_BLOCK"

if [[ ! -s "$BLOCKED_BLOCK" ]]; then
  fail "could not extract '$STEP_BLOCKED' run block from $WF (step missing or no run:)"
else
  cat > "$GH_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Records argv (one per line) to $CURL_ARGV and the -d payload to $CURL_TRACE, and
# returns HTTP $CURL_CODE (default 200) -- or exits non-zero when CURL_FAIL=1,
# simulating a transport failure. Real curl has already printed -w "%{http_code}" (000)
# by then, so the stub does too -- otherwise a doubled `|| echo 000` fallback is invisible.
if [[ "${CURL_FAIL:-0}" == 1 ]]; then echo -n "000"; exit 7; fi
printf '%s\n' "$@" > "${CURL_ARGV:-/dev/null}"
prev=""
for a in "$@"; do
  if [[ "$prev" == "-d" ]]; then printf '%s' "$a" > "$CURL_TRACE"; fi
  prev="$a"
done
echo -n "${CURL_CODE:-200}"
STUB
  chmod +x "$GH_STUB_DIR/curl"

  # run_blocked <webhook> <mirror_reason> <token_verdict> [curl_fail] [curl_code]
  # (stdout of the block lands in $TMP/out-b; curl argv in $TMP/argv-b)
  run_blocked() {
    : > "$TMP/curl-trace-b"; : > "$TMP/argv-b"; : > "$TMP/out-b"
    ( cd "$REPO_ROOT" && \
      SLACK_RELEASES_WEBHOOK_URL="$1" \
      MIRROR_REASON="$2" \
      TOKEN_VERDICT="$3" \
      CURL_FAIL="${4:-0}" \
      CURL_CODE="${5:-200}" \
      CURL_ARGV="$TMP/argv-b" \
      TAG="web-v1.2.3" \
      VERSION="9.8.7" \
      COMPONENT_DISPLAY="Web Platform" \
      RUN_URL="https://github.com/jikig-ai/soleur/actions/runs/42" \
      CURL_TRACE="$TMP/curl-trace-b" \
      PATH="$GH_STUB_DIR:$PATH" \
        bash -eo pipefail "$BLOCKED_BLOCK" > "$TMP/out-b" 2>&1 )
  }

  # (a) empty webhook -> rc 0, curl never invoked
  run_blocked "" "zz_stage_7256" "zz_verdict_7256"
  assert_eq "BLOCKED: empty webhook -> exit 0, no curl call" \
    "$? $(wc -c < "$TMP/curl-trace-b" | tr -d ' ')" "0 0"

  # (b) canonical: both reason and verdict set
  run_blocked "https://hooks.example.invalid/stub" "zz_stage_7256" "zz_verdict_7256"
  rc_b=$?
  payload_b=$(cat "$TMP/curl-trace-b")
  assert_eq "BLOCKED: configured webhook -> exit 0" "$rc_b" "0"
  if jq -e . >/dev/null 2>&1 <<<"$payload_b"; then
    pass "BLOCKED: payload is valid JSON"
  else
    fail "BLOCKED: payload is not valid JSON (got: ${payload_b:-<empty>})"
  fi
  assert_eq "BLOCKED: unfurl_links disabled" "$(jq -r '.unfurl_links' <<<"$payload_b" 2>/dev/null)" "false"
  text_b=$(jq -r '.text' <<<"$payload_b" 2>/dev/null)
  # VERSION (9.8.7) is deliberately NOT a substring of TAG (web-v1.2.3), so a dropped
  # version slot cannot hide behind the tag.
  for want in "Web Platform v9.8.7 release BLOCKED" "the GitHub release was NOT published" \
    "(the draft is kept)" "zot mirror stage" "zz_stage_7256" "zz_verdict_7256" \
    "https://github.com/jikig-ai/soleur/actions/runs/42" "Re-run failed jobs" "web-v1.2.3"; do
    if [[ "$text_b" == *"$want"* ]]; then
      pass "BLOCKED: message contains '$want'"
    else
      fail "BLOCKED: message must contain '$want' (got: ${text_b:0:200})"
    fi
  done
  case "$text_b" in
    *"released!"*) fail "BLOCKED: message must never claim 'released!'" ;;
    *) pass "BLOCKED: message never claims 'released!'" ;;
  esac
  # ADR-166: GHCR tags and the image are pushed BEFORE the mirror gate, so the message
  # must not say nothing was published.
  case "$text_b" in
    *"nothing was published"*) fail "BLOCKED: message must not claim 'nothing was published' (ADR-166)" ;;
    *) pass "BLOCKED: message never claims 'nothing was published'" ;;
  esac
  # The request itself: the stub records argv, so a wrong URL/header/timeout/protocol is visible.
  assert_eq "BLOCKED: curl target is the webhook (last argv)" \
    "$(tail -n 1 "$TMP/argv-b")" "https://hooks.example.invalid/stub"
  for want in "Content-Type: application/json" "--max-time" "--proto" "=https" "-d" "-s"; do
    if grep -qxF -- "$want" "$TMP/argv-b"; then
      pass "BLOCKED: curl argv carries '$want'"
    else
      fail "BLOCKED: curl argv must carry '$want' (got: $(tr '\n' ' ' < "$TMP/argv-b"))"
    fi
  done
  # The webhook is masked, and the raw value is printed nowhere else.
  if grep -qxF "::add-mask::https://hooks.example.invalid/stub" "$TMP/out-b"; then
    pass "BLOCKED: webhook is ::add-mask::ed"
  else
    fail "BLOCKED: webhook must be ::add-mask::ed (stdout: $(head -c 200 "$TMP/out-b"))"
  fi
  assert_eq "BLOCKED: raw webhook appears only in the add-mask line" \
    "$(grep -cF "https://hooks.example.invalid/stub" "$TMP/out-b")" "1"

  # (c) must-PASS non-canonical input (plugin release): both empty -> registry
  # lines suppressed, message still sent.
  run_blocked "https://hooks.example.invalid/stub" "" ""
  rc_c=$?
  text_c=$(jq -r '.text' <<<"$(cat "$TMP/curl-trace-b")" 2>/dev/null)
  assert_eq "BLOCKED (plugin shape): exit 0" "$rc_c" "0"
  if [[ "$text_c" == *"release BLOCKED"* && "$text_c" != *"zot mirror stage"* \
    && "$text_c" != *"unmeasured"* && "$text_c" != *"outside the mirror step"* ]]; then
    pass "BLOCKED (plugin shape): sent, registry lines suppressed"
  else
    fail "BLOCKED (plugin shape): must send without registry lines (got: ${text_c:0:200})"
  fi

  # (d) only one var set -> the other renders its fallback, no empty backticks
  run_blocked "https://hooks.example.invalid/stub" "zz_stage_7256" ""
  text_d=$(jq -r '.text' <<<"$(cat "$TMP/curl-trace-b")" 2>/dev/null)
  if [[ "$text_d" == *"zz_stage_7256"* && "$text_d" == *"unmeasured"* && "$text_d" != *'``'* ]]; then
    pass "BLOCKED: reason only -> verdict renders 'unmeasured'"
  else
    fail "BLOCKED: reason only must render verdict fallback (got: ${text_d:0:200})"
  fi
  run_blocked "https://hooks.example.invalid/stub" "" "zz_verdict_7256"
  text_e=$(jq -r '.text' <<<"$(cat "$TMP/curl-trace-b")" 2>/dev/null)
  # A successful mirror also leaves mirror_reason empty (only degraded() writes it), so the
  # fallback must not claim the stage was "not reached" -- the job did not measure that.
  if [[ "$text_e" == *"zz_verdict_7256"* && "$text_e" == *"outside the mirror step"* \
    && "$text_e" != *"not reached"* && "$text_e" != *'``'* ]]; then
    pass "BLOCKED: verdict only -> reason renders a non-committal fallback"
  else
    fail "BLOCKED: verdict only must render reason fallback (got: ${text_e:0:200})"
  fi

  # (e) entity-escape: & < > in a free-form reason must not reach Slack raw
  run_blocked "https://hooks.example.invalid/stub" 'a&b<!channel>' 'v&<x>'
  text_f=$(jq -r '.text' <<<"$(cat "$TMP/curl-trace-b")" 2>/dev/null)
  if [[ "$text_f" == *"a&amp;b&lt;!channel&gt;"* && "$text_f" == *"v&amp;&lt;x&gt;"* \
    && "$text_f" != *"<!channel>"* ]]; then
    pass "BLOCKED: & < > in MIRROR_REASON and TOKEN_VERDICT entity-escaped"
  else
    fail "BLOCKED: MIRROR_REASON and TOKEN_VERDICT must be entity-escaped (got: ${text_f:0:200})"
  fi

  # (f) transport failure keeps the step green (|| echo 000 tail)
  run_blocked "https://hooks.example.invalid/stub" "zz_stage_7256" "zz_verdict_7256" 1
  rc_g=$?
  assert_eq "BLOCKED: curl transport failure -> step still exits 0" "$rc_g" "0"
  # curl's own -w already printed 000 on a real transport failure, so the fallback must not
  # double it (`|| echo 000` printed 000000).
  if grep -qxF "::warning::Slack notification failed (HTTP 000)" "$TMP/out-b"; then
    pass "BLOCKED: transport failure warns with HTTP 000"
  else
    fail "BLOCKED: transport failure must warn 'HTTP 000' (stdout: $(head -c 200 "$TMP/out-b"))"
  fi

  # (g) non-2xx answer keeps the step green and warns with the real code
  run_blocked "https://hooks.example.invalid/stub" "zz_stage_7256" "zz_verdict_7256" 0 500
  rc_h=$?
  assert_eq "BLOCKED: HTTP 500 -> step still exits 0" "$rc_h" "0"
  if grep -qxF "::warning::Slack notification failed (HTTP 500)" "$TMP/out-b"; then
    pass "BLOCKED: HTTP 500 warns with the real code"
  else
    fail "BLOCKED: HTTP 500 must warn 'HTTP 500' (stdout: $(head -c 200 "$TMP/out-b"))"
  fi
fi

# Anti-vacuity floor (#7256): without it, deleting the T6b/T7b sections (or neutering the
# assertion helpers) leaves a suite that prints `passed` and exits 0. Reported by printf +
# exit, never through the fail() it backstops. Ratchet MIN_ASSERTIONS in the same commit as
# any added assertion; slack in a floor is attack budget.
ASSERTED=$((PASS + FAIL))
MIN_ASSERTIONS=77
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %d assertions ran, expected >= %d - the suite was stranded, not clean.\n' \
    "$ASSERTED" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
