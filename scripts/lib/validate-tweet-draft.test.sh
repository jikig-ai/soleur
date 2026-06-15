#!/usr/bin/env bash
# Tests for scripts/lib/validate-tweet-draft.sh — the skill-owned structural
# assertion for feature-tweet drafts (#5021). Proves the gate is NOT the Liquid
# linter: it validates required frontmatter fields + the canonical thread
# heading, independent of lint-distribution-content.sh.
#
# #5022 — feature-tweet now cross-posts to X AND Bluesky, so the gate additionally
# requires a `bluesky` channel token and a non-empty `## Bluesky` section.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/lib/validate-tweet-draft.sh"
pass=0
fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label ${detail}" >&2
  fi
}

_write() {
  local f; f=$(mktemp)
  printf '%s\n' "$1" > "$f"
  echo "$f"
}

RUN_RC=0
RUN_OUT=""
_run() {
  local f="$1"
  RUN_RC=0
  RUN_OUT=$(bash "$SCRIPT" "$f" 2>&1) || RUN_RC=$?
}

VALID='---
title: "Workspaces now read your real codebase"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#4997"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Your AI team now operates on your actual codebase -- not a blank workspace.

## Bluesky

Your AI team now operates on your actual codebase -- open, file-based, no black box.'

_expect_pass() {
  local label="$1" body="$2"
  local f; f=$(_write "$body")
  _run "$f"; rm -f "$f"
  if [[ "$RUN_RC" == "0" ]]; then _report "$label" ok
  else _report "$label" fail "rc=$RUN_RC out='$RUN_OUT'"; fi
}

_expect_reject() {
  local label="$1" body="$2"
  local f; f=$(_write "$body")
  _run "$f"; rm -f "$f"
  # Require the validator's own `invalid:` marker — NOT just any non-zero exit —
  # so a missing/broken script (rc=127) cannot pass these vacuously.
  if [[ "$RUN_RC" != "0" && "$RUN_OUT" == *invalid* ]]; then _report "$label" ok
  else _report "$label" fail "rc=$RUN_RC out='$RUN_OUT'"; fi
}

_expect_pass "valid draft passes" "$VALID"

# Missing/empty title
_expect_reject "rejects empty title" "${VALID/title: \"Workspaces now read your real codebase\"/title: \"\"}"
_expect_reject "rejects missing title" "${VALID/title: \"Workspaces now read your real codebase\"/type2: x}"

# Wrong status (must be draft — never write straight-through)
_expect_reject "rejects status: scheduled" "${VALID/status: draft/status: scheduled}"
_expect_reject "rejects missing status" "${VALID/status: draft/notes: none}"

# channels must include x
_expect_reject "rejects channels without x" "${VALID/channels: x, bluesky/channels: bluesky}"
# channels must include bluesky (#5022)
_expect_reject "rejects channels without bluesky" "${VALID/channels: x, bluesky/channels: x}"

# channels in YAML inline-list / quoted forms still satisfy BOTH token requirements
_expect_pass "accepts channels: [x, bluesky] inline list" "${VALID/channels: x, bluesky/channels: [x, bluesky]}"
_expect_pass "accepts channels: \"x, bluesky\" quoted" "${VALID/channels: x, bluesky/channels: \"x, bluesky\"}"
_expect_reject "rejects channels: [bluesky] (no x)" "${VALID/channels: x, bluesky/channels: [bluesky]}"
_expect_reject "rejects channels: [x] (no bluesky)" "${VALID/channels: x, bluesky/channels: [x]}"

# Missing X thread heading (explicit fixture — avoids bash `/` substitution quirks)
NO_HEADING='---
title: "x"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#1"
---

## Discord

Some body but no X thread heading.

## Bluesky

A bluesky post body.'
_expect_reject "rejects missing ## X/Twitter Thread heading" "$NO_HEADING"

# Missing ## Bluesky heading (#5022) — valid X thread + bluesky channel, no section
NO_BLUESKY_HEADING='---
title: "x"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#1"
---

## X/Twitter Thread

A valid X thread body.'
_expect_reject "rejects missing ## Bluesky heading" "$NO_BLUESKY_HEADING"

# ## Bluesky heading present but empty body (#5022)
EMPTY_BLUESKY='---
title: "x"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#1"
---

## X/Twitter Thread

A valid X thread body.

## Bluesky
'
_expect_reject "rejects empty ## Bluesky body" "$EMPTY_BLUESKY"

# Unterminated frontmatter (opening --- but no closing fence) must fail closed —
# otherwise the extractor treats the whole file as frontmatter and a malformed
# draft passes the gate (#5017 review: pattern-recognition).
UNTERMINATED='---
title: leaked
status: draft
channels: x, bluesky

## X/Twitter Thread

real body content with no closing frontmatter fence'
_expect_reject "rejects unterminated frontmatter" "$UNTERMINATED"

# X heading present but empty body
EMPTY_THREAD='---
title: "x"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#1"
---

## X/Twitter Thread
'
_expect_reject "rejects empty thread body" "$EMPTY_THREAD"

# Missing file
_run "/nonexistent/path/$$.md"
if [[ "$RUN_RC" != "0" && "$RUN_OUT" == *invalid* ]]; then _report "rejects missing file" ok
else _report "rejects missing file" fail "rc=$RUN_RC out='$RUN_OUT'"; fi

echo "=== validate-tweet-draft: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
