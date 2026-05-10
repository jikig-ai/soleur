# Feature: Content-Vendoring Pin Policy (gosprinto follow-up, #3517)

## Problem Statement

Soleur's `gdpr-gate` skill (PR #3501) lifted 5 active reference files from `gosprinto/compliance-skills` (MIT) at pinned commit `7b58d68461cb1fc033a063e34cc9de63d0b4144b` (NOTICE-recorded). No policy exists for what happens when upstream pushes a security-relevant update to any of those files. Without a policy:

- Stale rules ship as authoritative narrative claims via the gate's weave-don't-append output. Operators may merge a regulated-data PR on a false-clean signal — single-user incident.
- Silent local edits to lifted bytes can drift the actual content from the NOTICE attribution (MIT breach risk: attribution to bytes that no longer match).
- Holding out a "GDPR gate" while running known-stale rules is a GDPR Art. 5(2) accountability breach.
- This is the first content-vendor pin in the repo; without a general policy, the second lift will rebuild the same machinery.

## Goals

- **G1.** Detect upstream drift on the 5 lifted files weekly with audit trail.
- **G2.** Re-vendor security-relevant upstream changes within 14 days via auto-PR (`git merge-file --diff3`).
- **G3.** Prevent silent local edits to lifted bytes via pre-commit gate.
- **G4.** Surface staleness to the operator at runtime when the cron pipeline fails (≥30d → advisory-only banner; ≥90d → `compliance/critical` row).
- **G5.** Write the policy content-vendoring-general so the next lift adds a registry row, not a redesign.
- **G6.** Plug into `compliance-posture.md` Active Compliance Items table for `compliance/critical` co-labeled rows.

## Non-Goals

- **NG1.** Not converting the 5 lifted files into a git submodule (forces all-or-nothing pull; Soleur's EU extensions to `fields.md` and `data-in-transit.md` would need re-applying after every pull).
- **NG2.** Not adopting Renovate/Dependabot for content vendoring (default-deny scope per learning `2026-03-20-renovate-enabled-managers-scoping.md`; weekly bespoke cron is targeted).
- **NG3.** Not phasing automation to Phase 4 exit (CPO's original recommendation; user chose build-now). Staleness gate is the user-protection layer; cron is the convenience.
- **NG4.** Not promising a public SLO yet (operator-facing wording stays internal until Phase 4 exit; at that point the staleness banner already enforces the SLO at runtime).
- **NG5.** Not lifting the 3 fold-layer files (`auth-sessions.md`, `frontend.md`, `testing-seeding.md`) in this work (that's the v2 follow-up tracked separately per the gdpr-gate plan AC-PM-2).
- **NG6.** No new agent or MCP server.

## Functional Requirements

### FR1: Content-vendoring policy doc

A general policy document at `knowledge-base/engineering/policies/content-vendoring.md` covering: when to lift / NOTICE schema / drift detection / severity classification / re-vendor procedure / pre-vendor diff scan / a registry table. First registry row: gosprinto/compliance-skills @ `7b58d68`, 5 files, EU extensions noted, `last-verified: 2026-05-10`.

### FR2: NOTICE frontmatter

`plugins/soleur/skills/gdpr-gate/NOTICE` gains YAML frontmatter with at minimum: `upstream`, `pinned-commit`, `last-verified` (YYYY-MM-DD), `registry: knowledge-base/engineering/policies/content-vendoring.md`. Existing markdown body retained for human readability.

### FR3: Weekly drift workflow

`.github/workflows/scheduled-content-vendor-drift.yml` modeled on `scheduled-skill-freshness.yml`. Cron `0 9 * * MON`. Reads the registry → for each entry, `gh api repos/<owner>/<repo>/contents/<path>?ref=main --jq .sha` → compares to pinned blob SHA. On drift:
- Severity classifier (regex over upstream diff): security-relevant → 14-day SLA + auto-PR (`vendor/pin-drift` + `compliance/critical` co-label). Otherwise → batched (`vendor/pin-drift` only, quarterly review).
- Special cases: license file delta → `vendor/license-changed` + `compliance/critical`, 7-day SLA. Repo archived → `vendor/upstream-archived` + open fork-or-drop ADR issue.
- `CAP_PER_RUN`: prevent issue/PR storms.
- Idempotent: search existing issues by title before creating new.

### FR4: Auto-PR via 3-way merge

When severity-relevant drift is detected, the workflow checks out a branch from main, runs `git merge-file --diff3 <ours-extended.md> <upstream-old.md> <upstream-new.md>` per affected file, pushes the branch, opens a PR. CI fails if `grep -l '<<<<<<<' <files>` finds conflict markers. NOTICE updates: bumped pinned commit SHA, blob SHAs, `last-verified` date.

### FR5: Pre-commit lefthook gate

New `vendor-pin-integrity` stanza in `lefthook.yml` (sibling to existing `gdpr-gate-advisory` at lines 94-119). Glob: any registry-listed lifted file path. Computes `git hash-object` per file, compares to NOTICE-recorded blob SHA, fails if mismatch.

### FR6: Runtime staleness check in gdpr-gate

`plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` reads `last-verified` from NOTICE frontmatter on every invocation. Behavior:
- `today - last-verified ≤ 30 days`: no banner.
- `30 < days ≤ 90`: prepends to all output: `⚠ gdpr-gate rules <N> days stale (last verified <DATE>) — output is advisory only and may miss recently-patched detection rules. Refresh: see knowledge-base/engineering/policies/content-vendoring.md`.
- `> 90 days`: also writes a row to `knowledge-base/legal/compliance-posture.md` Active Compliance Items table (`vendor/pin-drift` + `compliance/critical` co-labels) and exits with non-zero `posture` field if invoked through compliance-posture-aware tooling. Operator invocation continues advisory.

### FR7: Compliance-posture integration

New "Vendored Code Provenance" section in `knowledge-base/legal/compliance-posture.md`, sibling to "Vendor DPA Status". Format mirrors existing tables. Drift-detection issues co-labeled `compliance/critical` land in the existing "Active Compliance Items" table per the operator-ack contract documented at lines 39-50 (gate writes only to Active Compliance Items, never directly to the Vendor sections).

### FR8: Pre-vendor diff scan

Re-vendor procedure (in policy doc) requires inspecting the upstream diff for: telemetry calls, vendor-branded links, hosted-service references rendered to user output, third-party-domain URLs the gate would emit. Any hit blocks the auto-PR (escalates to a `vendor/license-changed`-style review). Implemented as a script `plugins/soleur/skills/gdpr-gate/scripts/vendor-diff-scan.sh` invoked by FR3's workflow.

## Technical Requirements

### TR1: Use `git hash-object` not `sha256sum`

The NOTICE records git blob SHAs (output of `git hash-object`). The lefthook gate (FR5) and drift workflow (FR3) MUST use `git hash-object <path>` to compute SHAs for comparison, not `sha256sum`. They are different algorithms; mixing them produces silent false-positive drift.

### TR2: NOTICE frontmatter parser

The runtime staleness check (FR6) must read NOTICE frontmatter in <50ms (it runs on every gdpr-gate invocation). Use bash + `awk` or `sed` for the frontmatter parse — no Python/Node startup cost. Cache the parsed `last-verified` date for the lifetime of the invocation.

### TR3: Workflow security posture

`scheduled-content-vendor-drift.yml` MUST follow `cq-pg-security-definer-search-path-pin-pg-temp` analogue for workflows: pin all action SHAs (per `2026-02-27-github-actions-sha-pinning-workflow.md`); minimal `permissions:` block (`contents: write`, `pull-requests: write`, `issues: write` only); no `pull_request_target` trigger.

### TR4: Auto-PR commit signing

Auto-generated re-vendor PRs MUST commit via the standard CI bot identity used by `pr-auto-close-scanner.yml` and similar workflows. Do not skip GPG signing or hooks (per `wg-never-skip-hooks` analogue in commit-commands).

### TR5: 3-way merge inputs

For each lifted file f under re-vendor:
- `ours-extended` = current `plugins/soleur/skills/gdpr-gate/<path>` (HEAD on main)
- `upstream-old` = `gh api repos/goSprinto/compliance-skills/contents/<upstream-path>?ref=<NOTICE-pinned-sha>` (the SHA we pinned)
- `upstream-new` = same path at upstream HEAD

`git merge-file --diff3 <ours> <old> <new>` with `<old>` as the base. Output overwrites `<ours>` in place; conflict markers grep gates the PR.

### TR6: Idempotent staleness banner

The runtime banner (FR6) must not double-prepend. If gdpr-gate output already contains the banner string (e.g., piped through itself), skip the prepend. Test: run gdpr-gate twice on the same input; banner appears once.

### TR7: Test coverage

- Unit: severity classifier regex matches expected `+` table-row insertions, `[CRITICAL]`, `MUST`, `Art. \d+`, `§\s*\d+`; rejects prose-only edits.
- Unit: NOTICE frontmatter parser handles missing `last-verified` (treat as stale immediately).
- Unit: lefthook gate detects edits to lifted files via fixture with mismatched blob SHA.
- Integration: dry-run the drift workflow against a synthetic upstream diff; assert correct label set and PR title.
- Integration: 3-way merge produces clean output for a fabricated EU-extension + upstream-prose-edit case; produces conflict markers for a fabricated EU-extension + upstream-table-row-touching-extended-row case.

### TR8: AGENTS.md / hr-rule placement

Do NOT add a new AGENTS.md hard rule for this. The lefthook gate, drift workflow, and runtime banner are all enforced (gate-level / runtime); they fall under the placement-gate's `[hook-enforced:]` or `[skill-enforced:]` category and stay scoped to the policy doc and the gdpr-gate skill's own AGENTS-loading. Rationale: AGENTS.md is at 4.7 rules/day burn rate (#2865) and this is exhaustively enforced by the artifacts themselves.

### TR9: User-brand threshold inheritance

Per `hr-weigh-every-decision-against-target-user-impact`, this plan inherits `Brand-survival threshold: single-user incident` from the brainstorm's `## User-Brand Impact` block. Plan Phase 2.6 must restate the threshold and Phase 2.7 must invoke `/soleur:gdpr-gate` against the diff (the gate's own scripts are being modified — recursive but valid).

## Acceptance Criteria

- AC1. `knowledge-base/engineering/policies/content-vendoring.md` exists, contains the registry table, and lists gosprinto as the first row with all 5 lifted files.
- AC2. NOTICE has YAML frontmatter parseable by the runtime check; `last-verified: 2026-05-10`.
- AC3. `.github/workflows/scheduled-content-vendor-drift.yml` runs on `workflow_dispatch` (for manual test) and weekly cron; manual dispatch on a synthetic drift produces an issue + branch + PR with the right labels.
- AC4. Lefthook `vendor-pin-integrity` stanza fires on `git commit` touching any registry-listed lifted file; modifying a single byte in `references/leakage-vectors.md` without bumping NOTICE SHA fails the commit.
- AC5. Running `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` with NOTICE `last-verified` set to 35 days ago prepends the banner; with 95 days ago, also writes the compliance-posture.md row.
- AC6. `compliance-posture.md` "Vendored Code Provenance" section exists, lists gosprinto, cross-links the registry.
- AC7. All tests in TR7 pass.
- AC8. PR is co-labeled `compliance/critical` (regulated-data surface modification triggers user-impact-reviewer per `hr-weigh-every-decision-against-target-user-impact`).
