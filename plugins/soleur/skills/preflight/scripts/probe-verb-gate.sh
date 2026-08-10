#!/usr/bin/env bash
# preflight Check 10 — probe-verb gate (the runtime of record).
#
# Usage:  probe-verb-gate.sh "<discoverability_test.command>"
#   exit 0  -> accepted, no output
#   exit 1  -> rejected, reason on stdout
#   exit 2  -> usage error
#
# WHY THIS IS A FILE AND NOT INLINE BASH IN SKILL.md. The Form-A parser
# (parse-form-a.awk) is a real file precisely so the P1/P2/P3 harness can execute
# the production runtime instead of regex-scraping prose. This gate was
# originally inlined in SKILL.md with a hand-maintained TypeScript mirror and no
# executable parity check — and two parser asymmetries shipped green inside the
# very PR that created the mirror (a Form B command kept its markdown
# indentation, so the verb was ""; a Form A block scalar kept a leading `#`, so
# the verb was "#"). Content pins on the allowlist literal cannot detect
# behavioural drift. So: one file, executed by both the runtime and the tests.
#
# WHAT THIS GATE IS, STATED HONESTLY (ADR-173 Layer 2, revised).
# It is SCHEMA VALIDATION on the `command:` field — "is this an executable
# command, and one Check 10's PATH can run?" — NOT a security control and NOT a
# legibility control.
#
# It cannot be a security control, and the reason is structural: this gate's own
# sanctioned remedy is "wrap it in a repo-relative script" => `bash scripts/x.sh`,
# which is arbitrary in-sandbox code execution. Every shape it could reject is
# strictly WEAKER than the remedy it prescribes. Step 10.5 additionally runs
# `bash -c "$CMD"`, so every probe already IS an inline program. A rule that
# rejected `python3 -c` while printing instructions to use `bash scripts/x.sh`
# would be rejecting a spelling, not a capability.
#
# What it measurably DOES buy: 34 entries in the plan corpus are prose in a
# `command:` field ("Sentry issue search feature:…", "Open Sentry → Issues → …").
# Those become a named FAIL at authoring time instead of an opaque rc=127 at ship
# time. That value comes entirely from the bare verb list.
#
# The allowlist is a CORPUS-FREQUENCY list, not a capability list. `awk`, `sed`
# and `find` are absent because they fall below the >=2-use threshold — not
# because they are uniquely dangerous. `git` is present and IS a full execution
# vector (`git -c alias.x='!cmd' x` runs arbitrary commands); so is
# `bash <script>`. ADR-173 records both as worked examples that an allowlist
# entry is an authority grant. Authority is bounded by Step 10.5's sandbox, and
# by nothing here.
set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: probe-verb-gate.sh <command>" >&2
  exit 2
fi

# Ten verbs, each with >=2 uses in the measured corpus (see ADR-173 §Layer 2 for
# the extraction method and the count). `sh` was cut: it has ZERO uses, the same
# evidence on which `dig` and `getent` were excluded.
PROBE_VERB_ALLOWLIST=' curl bash grep rg jq python3 node bun printf git '

CMD="$1"

# --- Normalization (one place, before anything reads the verb) --------------
# Form B prints fenced lines VERBATIM, keeping markdown indentation; Form A's
# inline rule can leave a leading `#` comment line from a block scalar. Both
# produced a nonsense verb ("" and "#") and a FAIL whose message named remedies
# that could not apply. Normalizing once here fixes both asymmetries in the same
# place, and is what the TypeScript mirror's `.trimStart()` was doing unilaterally
# — the divergence that made the bug invisible to the suite.
# Drop full-line `#` comments and blank lines.
CMD="$(printf '%s' "$CMD" | sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d')"
# Trim leading and trailing whitespace.
CMD="${CMD#"${CMD%%[![:space:]]*}"}"
CMD="${CMD%"${CMD##*[![:space:]]}"}"

# Match against a QUOTE-STRIPPED copy: bash resolves `"doppler"`, `\doppler` and
# `dopp""ler` to the same binary, but a bare-token comparison does not see
# through the quote characters. Strip them from a COPY only — never from the
# string that would be executed.
CMD_DEQ="${CMD//[\"\'\\]/}"
PROBE_VERB="${CMD_DEQ%%[[:space:]]*}"

if [[ -z "$PROBE_VERB" ]]; then
  echo "discoverability_test.command is empty after normalization — no command could be parsed. See plan-issue-templates.md §Observability for the canonical schema."
  exit 1
fi

# NOTE: there is deliberately NO path-shaped exemption. An earlier revision
# skipped the allowlist whenever the first token contained a `/`, which made
# `./doppler secrets get FOO` and the prose entry `gh/Sentry query for …` both
# ACCEPT while a bare `gh` rejected 124 times. That exemption is what made the
# printed phrase "deny-by-default" false; removing it is what makes it true.
if [[ "$PROBE_VERB_ALLOWLIST" != *" $PROBE_VERB "* ]]; then
  # The literal is space-padded so the `*" $v "*` membership test works; the
  # message prints the TRIMMED form so it is byte-identical to the TypeScript
  # mirror's, which the parity harness asserts.
  ALLOWLIST_DISPLAY="${PROBE_VERB_ALLOWLIST#"${PROBE_VERB_ALLOWLIST%%[![:space:]]*}"}"
  ALLOWLIST_DISPLAY="${ALLOWLIST_DISPLAY%"${ALLOWLIST_DISPLAY##*[![:space:]]}"}"
  echo "discoverability_test.command starts with \`$PROBE_VERB\`, which is not on the probe-verb allowlist ($ALLOWLIST_DISPLAY). Either wrap the probe in a repo-relative script committed in this same PR (\`bash scripts/<name>.sh …\`), or — if the probe genuinely cannot run without credentials — declare \`credentials_required\` on the discoverability_test block so Check 10 skips it explicitly. To permit a new verb for everyone, add it to PROBE_VERB_ALLOWLIST in a reviewed PR; every entry is an authority grant."
  exit 1
fi

exit 0
