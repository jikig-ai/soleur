#!/usr/bin/env bash
# Static-contract test for the operator-digest skill (SKILL.md, #5085, plan §Phase 1 / AC1).
#
# The skill is the load-bearing synthesizer (LLM-as-script): there is no TS/bash
# synthesizer to unit-test, so the only mechanically-verifiable surface is the
# SKILL.md contract itself. This test asserts the prose carries every guardrail the
# plan makes load-bearing, so a future edit cannot silently drop one:
#   - frontmatter: third-person `description` (the components.test.ts voice/budget
#     gates cover word-count + char-limit; this asserts presence + third person here too).
#   - body names all FOUR data sources.
#   - L2 control: incident section built from frontmatter/title/status ONLY, never the PIR body.
#   - the agent WRITES digest.md and does NOT post (the gated post-step is the only poster).
#   - even an all-empty week still posts (deterministic fallback, never blank).
#   - each digest references the prior week's issue (in-band liveness loop).
#
# Exit codes: 0 = all contract assertions pass; 1 = a contract assertion failed; 2 = SKILL.md missing.
#
# Authoring note: assertions that match a multi-word ADJACENCY (`X.{0,N}Y`) match per
# PHYSICAL line — grep never crosses a newline, but Markdown soft-wraps freely. Keep the
# `X … Y` clause on ONE line in SKILL.md. A GREEN-fail on only the adjacency assertions is
# a line-wrap signal (fix the prose wrap), not a missing-prose signal (do not widen `{0,N}`).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="${SCRIPT_DIR}/../skills/operator-digest/SKILL.md"

if [[ ! -r "$SKILL" ]]; then
  echo "FAIL: SKILL.md not found at ${SKILL}" >&2
  echo "=== operator-digest-skill: 0 passed, 1 failed (SKILL.md missing) ===" >&2
  exit 2
fi

pass=0
fail=0

# assert_grep <PCRE-or-ERE-flags> <description> <pattern>
# Uses grep -iqE (case-insensitive ERE) over the whole file unless overridden.
assert() {
  local desc="$1" pattern="$2"
  if grep -iqE -- "$pattern" "$SKILL"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL: ${desc} — pattern not found: ${pattern}" >&2
  fi
}

# refute <description> <pattern> — must NOT be present.
refute() {
  local desc="$1" pattern="$2"
  if grep -iqE -- "$pattern" "$SKILL"; then
    fail=$((fail+1))
    echo "FAIL: ${desc} — pattern should be absent but matched: ${pattern}" >&2
  else
    pass=$((pass+1))
  fi
}

# --- Frontmatter: third-person description ---
assert "frontmatter name is operator-digest" '^name:[[:space:]]+operator-digest[[:space:]]*$'
assert "description is third-person (starts with 'This skill')" '^description:[[:space:]]*"?This skill'

# Description char limit (≤1024) — mirror the components.test.ts SKILL_DESCRIPTION_CHAR_LIMIT gate.
desc_line="$(grep -m1 -E '^description:' "$SKILL" || true)"
desc_val="${desc_line#description:}"
desc_len="${#desc_val}"
if (( desc_len <= 1024 )); then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "FAIL: description exceeds 1024 chars (${desc_len})" >&2
fi

# --- Body names all FOUR data sources ---
assert "source 1: merged PRs (gh pr list)"       'gh pr list'
assert "source 2: expenses/money ledger"         'expenses\.md'
assert "source 3: post-mortems / PIRs"           'post-mortem'
assert "source 4: action-required issues"        'action-required'

# --- §4 triage render (staleness contract #6836): de-pollute + age + cap ---
# The old §4 was a flat `--json title,url` dump: age invisible, decision-challenge +
# content chores drowning the genuine asks. The contract fetches age+labels, excludes
# the noise classes from the action list, surfaces per-item age, and caps the tail.
assert "§4 harvest fetches createdAt (age signal)"  '\-\-json.*createdAt'
assert "§4 harvest fetches labels (de-pollute)"     '\-\-json.*labels'
assert "§4 de-pollutes decision-challenge"          'decision-challenge'
assert "§4 de-pollutes content chores"              'content-publisher'
assert "§4 keeps content-starvation visible"        'content-starvation'
assert "§4 surfaces per-item age in days"           '[Aa]ge in days|days.*(old|open)|in days'
assert "§4 caps the action list"                    '\+N more'

# --- L2 control: incident from frontmatter/title/status ONLY, never body ---
# Order-independent: a correct reword ("status, frontmatter, title") must not falsely fail.
for kw in frontmatter title status; do
  assert "incident control names '${kw}'" "$kw"
done
assert "incident never reads the PIR body"       'never.*body|not.*the.*body|never the body'

# --- Write-not-post contract ---
assert "writes digest.md"                        'digest\.md'
assert "does NOT post (agent stops)"             'do NOT post|does not post|without posting|STOP'

# --- Deterministic fallback: even an all-empty week posts, never blank ---
assert "even an all-empty week still posts"      'empty.*(week|still).*post|even an all-empty week|all-empty week still posts'
assert "fallback section is never blank"         'never blank|never leave.*blank|not blank'

# --- In-band liveness: reference the prior week's issue ---
assert "references the prior week's issue"       'prior week|last week'

# --- Negative: the agent must not be told to create issues itself ---
refute "agent is not instructed to 'gh issue create'" 'gh issue create'

# --- Regression guard: data reads must use the List API, never --search. GitHub's Search API
# returns EMPTY for a cross-repo query under the in-action App-installation token (#3403 class),
# which would silently render "Nothing shipped" / "first digest" every week. Comment lines that
# document "NOT --search" are allowed; an actual `gh pr/issue list ... --search` command is not. ---
if grep -E 'gh (pr|issue) list' "$SKILL" | grep -vE '^[[:space:]]*#' | grep -q -- '--search'; then
  fail=$((fail+1)); echo "FAIL: a 'gh pr/issue list' command uses --search (breaks cross-repo under the in-action token)" >&2
else
  pass=$((pass+1))
fi

# --- Velocity metrics (#5986): shipping cadence (§1) + cost trend (§2), aggregate-only ---
# The metrics are prose instructions the LLM-as-script synthesizer executes at runtime; this
# static gate asserts each load-bearing framing rule is present so a future edit cannot drop one.

# Cadence: a qualitative shipping-cadence band folded into §1, compared to recent weeks,
# defaulting to "about the same" on doubt. No exact multiplier/ratio (that would be false rigor).
# Anchor to the unique §1 lead ("Shipping cadence") — the bare word "cadence" also
# matches the L3 guardrail and §2 "billing cadence", so it would not independently guard §1.
assert "cadence band present in §1"                          'shipping cadence'
assert "cadence compares to recent weeks / defaults typical" 'recent weeks|about the same|typical'

# Cost trend: §2 emits a this-week direction line + a coarse run-rate anchor (suppressed on doubt).
assert "cost trend: coarse run-rate anchor"                  'run-rate'
assert "run-rate rendered as a coarse dollar figure"         'roughly \$|about \$'

# Read-integrity suppression: a doubtful read must never become a confident metric.
assert "cadence never emits a false 'quieter' on a doubtful read"    'never.{0,40}quieter'
assert "run-rate anchor suppressed on ambiguous cadence / read error" 'suppress.{0,80}(anchor|ambiguous)|anchor.{0,80}suppress'

# Run-rate status filter is a FAIL-SAFE ALLOWLIST (only active/accruing-with-actual), never a denylist.
assert "run-rate counts ONLY active rows (allowlist)"        'only.{0,60}active'
assert "run-rate allowlist also admits accruing-with-actual" 'accruing'

# No per-contributor noise (the #5986 issue AC). Two guards:
#  (a) command-anchored refute — no §1 --json field list may include an `author` field;
#  (b) a company-aggregate guard-line exists.
# (a) is anchored to the real `--json` command line(s) and strips comment lines. It is worded so
# the guard-note prose ("never add an `author` field to the §1 `gh pr list --json` list", where
# `author` precedes `--json`) cannot false-trip it — only `--json <fields>,author` (author AFTER
# the field list) matches.
if grep -E -- '--json' "$SKILL" | grep -vE '^[[:space:]]*#' | grep -qiE -- '--json[[:space:]]*[a-zA-Z,]*author'; then
  fail=$((fail+1)); echo "FAIL: a --json field list includes 'author' — re-introduces per-contributor noise (#5986 AC)" >&2
else
  pass=$((pass+1))
fi
assert "velocity metrics are company-aggregate only"         'company-aggregate|aggregate-only|aggregate only'

# No vanity output: raw counts/percentages/arrows forbidden as the metric; consequence-framing required.
# The consequence assertion anchors to the NEW L3 phrasing ("stated as a business consequence") — the
# bare word "consequence" already lives in the pre-feature Register, so it would guard nothing new.
assert "vanity guard: forbids raw counts / percentages / arrows" 'percentage|arrow|raw count'
assert "vanity guard: mandates business-consequence framing"     'stated as a business consequence'

echo "=== operator-digest-skill: ${pass} passed, ${fail} failed ===" >&2
[[ "$fail" == 0 ]]
