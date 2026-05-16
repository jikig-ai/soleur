---
date: 2026-05-11
category: best-practices
module: scripts/lint-bot-synthetic-completeness.sh
problem_type: latent-config-parser-bug
related_pr: 3543
related_issues: [3542, 2719]
discoverable: lint-failure
---

# Adding the First Multi-Word Required Check Exposed a Latent Strip-All-Whitespace Bug

## Problem

`scripts/required-checks.txt` is the canonical config consumed by
`scripts/lint-bot-synthetic-completeness.sh` (the `lint-bot-statuses` CI gate).
Every prior required check (`test`, `dependency-review`, `e2e`, `cla-check`)
was a single bareword. When PR #3543 added `skill-security-scan PR gate` —
the first multi-word check name — the lint started failing with:

```text
FAIL: .github/workflows/scheduled-content-publisher.yml is missing
synthetic check-runs for: skill-security-scanPRgate
```

The error message was diagnostic but suspicious: the workflows obviously
contained `-f name="skill-security-scan PR gate"`, yet the lint claimed they
were missing a check whose name had no internal spaces.

## Root Cause

The config-line parser at `scripts/lint-bot-synthetic-completeness.sh:32`
stripped *all* whitespace:

```bash
line="${line%%#*}"
line="$(echo "$line" | tr -d '[:space:]')"
```

This was correct for the only check names that had ever shipped (all
single-word) but collapsed `skill-security-scan PR gate` to
`skill-security-scanPRgate` before passing it to the grep pattern. The grep
then searched workflows for the impossible string `-f name=skill-security-scanPRgate`
and failed every file.

## Solution

Trim only the leading and trailing whitespace; preserve internal:

```bash
line="${line%%#*}"
line="${line#"${line%%[![:space:]]*}"}"
line="${line%"${line##*[![:space:]]}"}"
```

Then ERE-escape the check name before interpolation into the grep pattern
(defense against future regex meta in check names, though current names use
only `[A-Za-z0-9 _-]`):

```bash
escaped=$(printf '%s' "$check_name" | sed 's/[][\.^$*+?(){}|/\\]/\\&/g')
grep -qE "\-f name=${escaped}([[:space:]]|$)" "$file" || \
  grep -qE "\-f name=\"${escaped}\"" "$file"
```

The quoted-form grep alternative is what catches `-f name="skill-security-scan PR gate"`
in the workflow YAML — workflows must quote multi-word names because bash
splits on whitespace by default.

## Key Insight

**Whitespace-stripping config parsers are fragile against multi-word values
they have not yet seen.** Single-word values mask the bug forever; the first
multi-word value flips the parser from "trim noise" semantics to "destroy
information" semantics with no warning.

The general guidance: **trim leading/trailing whitespace only** (using the
parameter-expansion idiom above, or `read -r line | xargs`); never reach for
`tr -d '[:space:]'` unless the field is documented to be whitespace-free by
schema. A non-narrow trim is invisible until a config value that needs the
internal whitespace shows up.

The dual fix — preserve internal whitespace **and** escape regex meta when
interpolating user-controlled strings into regex — is the canonical pattern.
Either alone leaves a footgun.

## Why the Discoverability Exit Applies

This bug was caught by exactly the verification step in the plan (running
`bash scripts/lint-bot-synthetic-completeness.sh` after the Phase 2 workflow
edits). The lint failed loudly with the impossible string
`skill-security-scanPRgate` in the error message. A future contributor
adding a second multi-word required check would hit the same loud failure.

Per `wg-every-session-error-must-produce-either`'s discoverability exit:
when an agent discovers the constraint via a clear error, a learning file
alone suffices — no AGENTS.md rule needed. The learning is here to short-
circuit the next debugging round; the lint script itself is now resilient.

## Secondary Lesson: `bash -n` Does Not Lint YAML

The deepened plan AC §111 prescribed `bash -n .github/actions/bot-pr-with-synthetic-checks/action.yml`
as a syntax check. But `action.yml` is a YAML composite action with bash
embedded inside `run:` strings — `bash -n` parses the file as bash and
fails at the YAML header (`description: >` triggers a syntax error).

The correct local verification for embedded shell blocks in a YAML composite
action is:

1. `yamllint <file>` (or `actionlint <file>` for GitHub Actions semantics).
2. `bash -c '<extracted snippet>'` for the shell logic in isolation. In our
   case: `bash -c 'for c in test dependency-review e2e "skill-security-scan PR gate"; do echo "[$c]"; done'`
   confirms the quoted multi-word token survives word-splitting (4
   iterations, not 6 + a runtime bug).

This is feedback for plan/deepen-plan templates: when the AC's verification
step targets a YAML file with embedded shell, prescribe `yamllint`/`actionlint`
+ `bash -c '<snippet>'`, not `bash -n` on the YAML.

## Session Errors

1. **Pre-existing lint config-parser bug exposed by first multi-word check** —
   Recovery: switched `tr -d '[:space:]'` → parameter-expansion trim that
   preserves internal whitespace; added ERE-escape on the resulting regex.
   Prevention: see "Solution" and "Key Insight" above. Discoverable via lint
   failure → learning suffices, no AGENTS.md rule needed.

2. **`bash -n` on YAML file** — Recovery: tested embedded loop via
   `bash -c '<snippet>'`. Prevention: see "Secondary Lesson" — plan AC
   templates should prescribe `yamllint`/`actionlint` + `bash -c` for
   embedded-shell YAML, not `bash -n`.

## Tags

category: best-practices
module: scripts/lint-bot-synthetic-completeness.sh
related: scripts/required-checks.txt, .github/actions/bot-pr-with-synthetic-checks/action.yml
