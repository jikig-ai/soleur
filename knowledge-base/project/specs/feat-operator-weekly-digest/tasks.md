---
title: "Tasks: Operator weekly comprehension digest"
issue: 5085
branch: feat-operator-weekly-digest
lane: cross-domain
brand_survival_threshold: single-user incident
plan: ../../plans/2026-06-11-feat-operator-weekly-comprehension-digest-plan.md
---

# Tasks — feat: Operator Weekly Comprehension Digest

Derived from the finalized (plan-review-applied) plan. Substrate: a scheduled `claude-code-action`
workflow in a NEW private repo (`jikig-ai/operator-digest`) invoking a new `operator-digest` skill that
reads public soleur, synthesizes 4 plain-language sections, runs a tuned fail-closed scrub post-step, and
posts a private issue. Brand-critical (single-user incident).

## Phase 0 — Preconditions (probes)
- [ ] 0.1 Confirm `jikig-ai/soleur` PUBLIC + operator `gh` token has org repo-create scope.
- [ ] 0.2 **In-action token probe** (NOT local gh): a throwaway claude-code-action job reads
      `gh issue list -R jikig-ai/soleur --label action-required` via the Bash bridge with `github_token`+`env
      GH_TOKEN` set; assert authorized/non-empty (proves cross-repo read under the in-action token; #3403).
- [ ] 0.3 Enumerate current open `action-required` issues (real signal density for section 4).
- [ ] 0.4 Resolve latest claude-code-action SHA (re-check pin per model-launch-review).
- [ ] 0.5 Measure new-description word count → set the components.test.ts bump value.

## Phase 1 — Skill + tuned scrub gate
- [ ] 1.1 RED: `digest-scrub.sh` test — asserts ABORT on a planted secret-shaped token (positive sentinel) +
      on a non-first-party email; PASS on `@jikigai.com` email + UUID + IPv4; ABORT on grep-error input.
- [ ] 1.2 GREEN: implement `plugins/soleur/skills/operator-digest/scripts/digest-scrub.sh` (secret classes
      hard-abort; email aborts unless first-party allowlist; UUID/IPv4 warn-only; grep exit 2 → abort).
- [ ] 1.3 RED: skill static-contract test — frontmatter present, third-person ≤1024-char description, body
      names the 4 sources + "incident = frontmatter/title/status only, never body" + "write digest.md, do
      NOT post" + "even an all-empty week posts" + "reference the prior week's issue".
- [ ] 1.4 GREEN: author `plugins/soleur/skills/operator-digest/SKILL.md` (≤30-word description; L1+L2;
      deterministic per-section fallback; chief-of-staff register; writes `$GITHUB_WORKSPACE/digest.md`; STOPS).
- [ ] 1.5 Bump `plugins/soleur/test/components.test.ts:15` budget by the exact word count; `bun test
      plugins/soleur/test/components.test.ts` green.

## Phase 2 — Workflow template + provisioning
- [ ] 2.1 RED: workflow-lint test — `id-token: write` present; `show_full_output` ≠ true; `--allowedTools`
      contains `Write` AND NOT `gh issue create`; only `gh issue create` is a GHA `run:` post-step; a
      `digest-scrub.sh` post-step runs OUTSIDE the action; `rm digest.md` present; actions SHA-pinned;
      `plugin_marketplaces` pinned to soleur; no `cat`/`echo` of digest.md or ANTHROPIC_API_KEY.
- [ ] 2.2 GREEN: author `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` from the
      `soleur:schedule` recurring template, hand-edited per Architecture (cross-repo checkout
      `persist-credentials: false`, scrub post-step + withheld-notice + rm, prior-week back-reference,
      `workflow_dispatch:`, drop vestigial label step).
- [ ] 2.3 RED: provision-script test — `gh secret set` reads from stdin (no `--body "$VALUE"` argv leak);
      fails loud if the Doppler value is empty.
- [ ] 2.4 GREEN: author `plugins/soleur/skills/operator-digest/scripts/provision-operator-digest-repo.sh`
      (idempotent `gh repo create` + Doppler→stdin secret + install workflow + `gh workflow enable`).

## Phase 3 — Docs, budget, ADR
- [ ] 3.1 `bash scripts/sync-readme-counts.sh`; both READMEs `--check` green.
- [ ] 3.2 Author ADR via `/soleur:architecture create` (two-repo privilege-separated pipeline).
- [ ] 3.3 PR body `## Changelog`; `semver:minor` label.

## Phase 4 — Pre-merge verification (local)
- [ ] 4.1 Produce a sample `digest.md` from the checked-out repo; assert content-quality (AC5 heuristic:
      not byte-identical to a bare `gh pr list` dump; ≥1 sentence-with-verb per non-empty section; no blank).
- [ ] 4.2 Run `digest-scrub.sh` on a sample built from the REAL current `expenses.md` → exit 0 (no benign
      first-party false-positive); then plant a secret-shaped token → assert abort.
- [ ] 4.3 `grep -nE 'sk_(test|live)_…|ghp_…|sk-ant-…'` across touched markdown returns 0 (structural placeholders).

## Phase 5 — Post-merge (operator-authenticated, automated)
- [ ] 5.1 Run `provision-operator-digest-repo.sh` (creates private repo + Doppler-sourced secret + installs +
      enables the workflow on the default branch).
- [ ] 5.2 `gh workflow run operator-digest.yml -R jikig-ai/operator-digest` → confirm a private digest issue
      (4 sections + prior-week back-reference); conclusion `success`; scrub post-step present in the log.
