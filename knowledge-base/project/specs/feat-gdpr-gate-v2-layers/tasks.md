---
title: gdpr-gate v2 — task breakdown
plan: knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-v2-layers-and-repo-scan-plan.md
issue: 3518
date: 2026-05-10
status: ready
---

# Tasks: gdpr-gate v2 layers + repo-scan mode

Derived from `2026-05-10-feat-gdpr-gate-v2-layers-and-repo-scan-plan.md`. Phase numbering matches plan §"Implementation Phases".

## Phase 1 — Layer file lifts (auth-sessions, frontend, testing-seeding)

- 1.1 Fetch `auth-sessions.md` from `gh api` at commit `7b58d68461cb1fc033a063e34cc9de63d0b4144b`; verify blob SHA `71dd9d01fe55d3e58f8b35f1cf745d47ba5f0985`.
- 1.2 Write `references/layers/auth-sessions.md` with `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->` as line 1; append Art. 32(1)(b) confidentiality footer.
- 1.3 Repeat 1.1–1.2 for `frontend.md` (blob `5f39e08fe2404759d7cbdbdea54a4f6210b91b8f`); footer = ePrivacy/TTDSG strict-opt-in.
- 1.4 Repeat 1.1–1.2 for `testing-seeding.md` (blob `a2f299418a5f85246fd2203475d89106936f7a72`); footer = Art. 32 pseudonymization.
- 1.5 Run vendor-surface scrub on all 3 lifted files; assert zero matches.
- 1.6 Update `NOTICE`: add 3 new rows; update lift-date footer; remove the v1 "NOT lifted in v1" line; add `## Soleur-authored layers` section.

## Phase 2 — `legal-consent.md` archive-then-rewrite

- 2.1 `mkdir -p plugins/soleur/skills/gdpr-gate/references/legacy/`.
- 2.2 `git mv references/legal-consent.md references/legacy/legal-consent-v1-prose.md`.
- 2.3 Prepend archive provenance header to legacy file.
- 2.4 Author fresh `references/legal-consent.md` with `<!-- Soleur-authored — see NOTICE -->`, `## When This Layer Loads` section, and 5 check blocks LC-01..LC-05.

## Phase 3 — SKILL.md edits

- 3.1 Add `--repo-scan` mention in opening section (lines 6-12).
- 3.2 Reorganize `## Reference layers:` into "Active layers (with check_id markers)" + "Reference catalogues" subsections.
- 3.3 Insert new section `## --repo-scan mode` between Disclaimer and Path globs (canonical).
- 3.4 Extend FR4 table note to cover layer-id checks across all 7 active layers.
- 3.5 Add 2 sharp-edges: historical-migration tracked-not-amended; bash-regex locale (`LC_ALL=POSIX`).

## Phase 4 — `path-denylist.txt` + `repo-scan.sh`

- 4.1 Create `scripts/path-denylist.txt` with the 7 patterns from plan §"Path deny-list".
- 4.2 Verify each pattern via `git ls-files | grep -E '<pattern>' | head -n 3`; record evidence in PR body.
- 4.3 Create `scripts/repo-scan.sh` (≤300 lines, pure bash):
  - 4.3.1 `set -euo pipefail` + `LC_ALL=POSIX`.
  - 4.3.2 Source `path-denylist.txt`.
  - 4.3.3 Extract canonical regex from `SKILL.md` (awk on "Path globs (canonical)" heading + first fenced line); exit 1 if not found.
  - 4.3.4 Parse `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` with two-clause defense + CI refusal.
  - 4.3.5 Emit candidate paths to stdout; emit `# blocked: <path>` / `# bypass: <path>` to stderr.

## Phase 5 — Tests

- 5.1 Create `plugins/soleur/test/gdpr-gate-repo-scan.test.ts` with 7 cases (D1, D3.bypass-typo, D3.bypass-coincidental-match, D3.ci-refusal, D4, Sentinel, Canonical-regex source-of-truth).
- 5.2 Extend `plugins/soleur/test/gdpr-gate.test.ts`:
  - 5.2.1 Add 3 entries to `LIFTED_REFS`.
  - 5.2.2 Add `SOLEUR_AUTHORED_LAYERS` array.
  - 5.2.3 Add NOTICE-row parity + uniqueness assertion.
  - 5.2.4 Add Soleur-authored header assertion for `legal-consent.md`.
  - 5.2.5 Add layer-shape assertion (`LC-01:` + `## When This Layer Loads`).
  - 5.2.6 Add legacy-archive assertion.

## Phase 6 — Verification + lint

- 6.1 `bun test plugins/soleur/test/components.test.ts` — green.
- 6.2 `bun test plugins/soleur/test/` — full suite green.
- 6.3 `python3 scripts/lint-rule-ids.py` — passes.
- 6.4 `lefthook run pre-commit` — gdpr-gate-advisory regression-clean.
- 6.5 Manual smoke: `/soleur:gdpr-gate --repo-scan` against current worktree. Confirm AC-SMOKE.

## Phase 7 — Plan/work/ship integration

- 7.1 Verify `git diff main...HEAD -- AGENTS.md lefthook.yml .gitleaks.toml` is empty (AC-NO-AGENTSMD, AC-NO-LEFTHOOK).
- 7.2 PR body uses `Closes #3518` on its own line, `## Changelog` section, `semver:minor` semantics.

## Deferral Tracking (file at plan exit)

- D1: per-check_id severity fixtures (full coverage) — Post-MVP / Later.
- D2: submodule support for `--repo-scan` — Post-MVP / Later.
- D3: `--repo-scan-path=<glob>` scoped variant — Post-MVP / Later.
- D4: automated `path-denylist.txt` ↔ `.gitleaks.toml` parity sync — Post-MVP / Later.
