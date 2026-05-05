---
date: 2026-05-05
category: best-practices
problem_type: workflow_self_leak_false_positive
component: github_actions_workflow + leak_tripwire
related_issues: [3187]
related_prs: [3224]
tags: [github-actions, leak-detection, add-mask, tee, step-output, self-leak, guard-itself-dark]
synced_to: []
---

# Leak Tripwires Must Filter Their Own Mask Registrations Before Scanning

## Why this learning exists

The GitHub App drift-guard workflow (`scheduled-github-app-drift-guard.yml`,
shipped in PR #3224) included a leak tripwire as a blocking post-step:
`exec > >(tee -a "$RUNNER_TEMP/step-output.log") 2>&1` captured the drift
step's stdout/stderr, then a separate step grepped that file for PEM
headers, base64-of-PEM, and JWT segments.

When the workflow was first triggered manually post-merge against
properly-bootstrapped Doppler/GH-Actions secrets, the drift step itself
ran clean ("Drift-guard passed.") — but the tripwire fired and filed a
`security/leak-suspected + ci/guard-broken + priority/p1-high` issue.
This is the "guard-itself-dark" failure mode the workflow was designed
to detect: a guard that ALWAYS-fails on a green run is worse than no
guard, because operators learn to ignore it.

## Root cause

The drift step registers two kinds of `::add-mask::` directives BEFORE
calling out to GitHub's API:

```bash
# Per-PEM-line mask (loop)
while IFS= read -r line; do
  [[ -n "$line" ]] && echo "::add-mask::$line"
done < "$KEY_FILE"

# Minted-JWT mask
echo "::add-mask::$JWT"
```

These are runner-control directives — the runner consumes them and
replaces matched values in the displayed log with `***`. They are NOT
log content.

But `tee -a step-output.log` runs BEFORE the runner consumes the
directives. The runner sees `::add-mask::-----BEGIN RSA PRIVATE KEY-----`
on stdout, registers the mask, and removes the line from displayed
output. `tee` already wrote the raw bytes to the file. So
`step-output.log` ends up containing:

```text
::add-mask::-----BEGIN RSA PRIVATE KEY-----
::add-mask::MIIEowIBAAKCAQEA…
…
::add-mask::-----END RSA PRIVATE KEY-----
::add-mask::eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI…
```

The tripwire grep:

```regex
BEGIN [A-Z ]*PRIVATE KEY|LS0tLS1CRUdJTi[A-Za-z0-9+/]|eyJ[A-Za-z0-9_-]{20,}
```

matches:

- `BEGIN RSA PRIVATE KEY` from PEM-line mask registrations →
  PEM-header pattern
- `eyJ…` from the JWT mask registration → JWT pattern

Result: every green run trips the tripwire. False positive rate: 100%.

## Fix

Pre-filter runner-directive lines (`^::…`) before scanning:

```bash
if grep -v '^::' "$LOG" | grep -E "BEGIN [A-Z ]*PRIVATE KEY|LS0tLS1CRUdJTi[A-Za-z0-9+/]|eyJ[A-Za-z0-9_-]{20,}" >/dev/null; then
  ...
fi
```

The pre-filter is correct because:

1. Lines starting with `::` are workflow commands consumed by the
   runner (`::add-mask::`, `::warning::`, `::error::`,
   `::group::`/`::endgroup::`, `::set-output::`, etc.). They are not
   user-visible log content; the displayed log shows their *effect*
   (mask applied, warning rendered) not the directive itself.
2. A real leak via plain `echo "$JWT"` or `echo "$PRIVATE_KEY"` still
   matches because the leaked bytes appear on a non-`::`-prefixed
   line. The pre-filter only hides values that the workflow has
   already explicitly registered for masking — masking and leaking
   are mutually exclusive intents.
3. An attacker-controlled value that happened to start with `::` cannot
   bypass the filter, because the only inputs to step-output.log are
   the workflow's own commands; there is no untrusted-input path that
   feeds the log directly.

## Generalization

Any leak detector that reads a log captured *before* runner directives
are consumed needs to filter those directives. This applies to:

- `tee` capture inside a GHA step (this case)
- A separate "audit" step that fetches the run's raw API log via
  `gh api repos/.../actions/runs/.../logs` (the API returns the raw
  stdout-as-uploaded form, which still contains directives)
- Self-hosted runners that ship logs to an external SIEM before the
  runner-directive consumer can rewrite them

The general rule: **any log-derived leak detector must distinguish
"workflow control plane" bytes from "data plane" bytes**. The control
plane bytes are part of the channel between the script and the runner;
they are not data the script has emitted to operators. Treating them as
data produces false positives when those directives carry sensitive
values *as their argument* — which is precisely the case for
`::add-mask::`.

## Where to apply this

- Any new GHA workflow with a `tee`-captured step-output log AND a
  post-step grep against that log.
- Reviewing `scheduled-oauth-probe.yml` (precedent for this drift-guard
  pattern) — it uses `tee step-output.log` too. The oauth-probe never
  registers per-line `::add-mask::` for content matching its own grep
  patterns, so the bug doesn't manifest there. But a future PR that
  adds per-secret masking would re-introduce it. Add the same `^::`
  pre-filter defensively.
- The contract test pins the new pre-filter shape via a regex that
  requires the literal `grep -v '^::' "$LOG" |` precede the tripwire
  grep — not the other way around. Order matters: filtering AFTER the
  detection grep would let the directive lines trip the detector.

## Cross-references

- `2026-05-05-extracted-bash-functions-need-self-contained-state.md` —
  sibling learning from PR #3224, Pattern 3 ("co-sign FIRST, file
  scope-out SECOND") and the "guard-itself-dark" framing.
- `2026-05-05-workflow-jwt-mint-silent-failure-traps.md` — sibling
  learning, covers the parent `tee | exec` capture decision and why
  `set -uo pipefail` (no `-e`) is load-bearing.
- `plugins/soleur/skills/review/SKILL.md` §5 — review-finding
  fix-inline default; this learning was captured retroactively because
  the bug only surfaced post-merge during AC21 manual verification.
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md` step 3
  — runbook now instructs operators to rule out the self-leak class
  BEFORE rotating the key.

## Session Errors

Errors enumerated during this session (continued from PR #3224's
post-merge verification):

1. **Drift-guard workflow always-fails on green run via self-leak.**
   First post-merge run (#25374996338) failed on missing-secret bootstrap
   (expected — Doppler had `GITHUB_APP_*` but workflow expected
   `GH_APP_DRIFTGUARD_*`). Recovery: synced via Doppler write +
   `gh secret set`. Second run (#25377012606) drift-checked clean but
   tripwire fired on the workflow's own `::add-mask::` registrations.
   **Prevention:** This learning + the contract test assertion that pins
   the `^::` pre-filter.
2. **Pre-merge contract test did not catch the self-trip.** The test
   asserts the regex strings appear in the workflow body, but never
   ran the tripwire against a synthetic step-output.log containing
   `::add-mask::-----BEGIN…` lines. **Prevention:** add a synthetic
   "tripwire-self-leak" test that constructs a fake log with the
   directive lines and confirms the tripwire does NOT fire — this
   catches the bug at write-time, not at first manual-trigger after
   merge. (Filed as follow-up; not in this PR's scope to keep the fix
   minimal.)
3. **Phase 5.4 preflight passed despite the bug.** Preflight has no
   check that exercises a workflow against a synthetic log. This is a
   structural limit — preflight runs against the deployed prod surface,
   not against newly-added workflow contracts. **Prevention:** none at
   the preflight layer; the right layer is the contract test (item 2).
