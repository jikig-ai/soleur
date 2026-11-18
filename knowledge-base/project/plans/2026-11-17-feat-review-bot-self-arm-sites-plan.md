---
title: review: bot self-arm sites bypass the review-evidence arm check (repo-wide arm walker + domain-surface control)
date: 2026-11-17
slug: review-bot-self-arm-sites-bypass-review-evidence-arm-check
branch: feat-one-shot-12739
issue: 12739
---

# Plan: bot self-arm sites bypass the review-evidence arm check

## Overview

Implement GitHub issue #12739 per CTO ruling 2026-11-17: close the hole where bot-authored PRs self-arm auto-merge without the review-evidence arm check. Two deliverables: (1) a repo-wide arm walker (`review-evidence-arm-walker.test.sh`) that scans every merge site and requires either an arm-check invocation or a ledger row; (2) a domain-surface control where the bot refuses to self-arm on sensitive surfaces, leaving the PR unarmed with `needs-review`. Plus ADR-328, an exemption ledger seeded with three legacy sites, and hook re-arm text. #12712 is explicitly out of scope.

## Premise Validation

Issue #12739 is OPEN with no closing PR. The three named bot sites exist on this branch (verified: `.github/scripts/bump-inngest-bootstrap-pin.sh`, `.github/actions/bot-pr-with-synthetic-checks/action.yml`, `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`). ADR-327 is the latest; next is ADR-328. No existing `review-evidence-exemption-ledger.yml`. `arm-check-sites.test.sh` exists and documents R3 (repo-wide walker) as a stated residual. No collision pre-check hits expected for #12739.

## Property List (from CTO ruling)

1. Every merge site in the repo is either arm-check-gated or listed in the exemption ledger (no silent bypass).
2. Bot-authored PRs touching domain surfaces are never self-armed; they carry `needs-review`.
3. The arm check canonical text and its head-binding are preserved (A1/A1-noH/A3 invariants).
4. Ledger governance is CTO-only; rows carry (site, surface, reason closed set, owner, added, ruling).
5. Ordering: ADR → ledger → walker test red → bot-site edits → hook text → walker green.

## Cut List

- No new runtime bot code beyond the three named sites' arm-gate edits and the domain-surface refusal predicate (R4) — the walker is a text guard, not a runtime enforcer.
- No changes to #12712 scope.
- No modification of the canonical arm-check fence (A3 pin) — only references/links.

## Research Insights

- Existing `arm-check-sites.test.sh` is the model: fixed site list SITES/LINK_ONLY, A1 floor, NOH regex, canonical fence pin, EXPECTED_LEDGER. The new walker generalizes to repo-wide scan of merge tokens.
- Merge tokens to scan (per R3): `gh pr merge`, `gh_app`/`gh app` pr merge, `enablePullRequestAutoMerge`, REST merge endpoint (`/pulls/.../merge`), `enqueuePullRequest`, `enableAutoMergeSquash`, `--admin`, plain `--squash`.
- Domain surfaces (R4): `infra/`, `.github/workflows/`, `cloud-init*`, migrations, terraform, auth/secrets/validation code.
- ADR numbering: 328 next.
- Hook `.claude/hooks/pre-merge-rebase.sh` contains re-arm guidance; bundle text pointing at `review-evidence-comment.md#arm-check` and main/master carve-out link to #8791.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-328-server-side-bot-self-arm-and-the-agent-review-merge-gate.md`
- `knowledge-base/engineering/review-evidence-exemption-ledger.yml`
- `plugins/soleur/test/review-evidence-arm-walker.test.sh` (or repo `test/`? Place alongside arm-check-sites.test.sh under plugins/soleur/test/) — walker scanning all merge sites
- Possibly a domain-surface predicate helper referenced by bot sites.

## Files to Edit

- `.github/scripts/bump-inngest-bootstrap-pin.sh` — gate auto-arm on domain-surface check / ledger
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — same
- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` — same
- `.claude/hooks/pre-merge-rebase.sh` — re-arm text pointing at arm-check + carve-out link #8791
- `plugins/soleur/test/arm-check-sites.test.sh` — add walker reference / residual R3 cleared note (minimal)

## Implementation Phases (R7 order)

1. ADR-328 (R5) — write decision doc.
2. Exemption ledger (R3) — create with three legacy-pre-gate rows.
3. Walker test red — implement scanner; expect failures on un-gated bot sites.
4. Bot-site edits (R4) — add domain-surface refusal + arm-gate; ledger rows where exempt.
5. Hook text (R6).
6. Walker test green — re-run; all merge sites gated or ledgered.

## Scope Check

- Ask mapping: issue #12739 + CTO ruling. All R3-R7 covered. #12712 excluded.
- Item provenance: all items derived from ruling; no inferred extras beyond walker implementation.

## Domain Review

Engineering + Security relevant (auth/secrets surfaces). No UI → Product NONE.

## User-Brand Impact

- **If this lands broken, the user experiences:** bot-authored PRs self-arm and merge without review evidence, shipping unreviewed changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** unreviewed infra/workflow/auth changes merging autonomously.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** bot self-arm on sensitive surfaces is a single-operator incident class, not aggregate.

## Observability

```yaml
liveness_signal:
  what: Walker test pass/fail in CI
  cadence: per-PR
  alert_target: CI failure
  configured_in: plugins/soleur/test/review-evidence-arm-walker.test.sh
error_reporting:
  destination: GitHub Actions
  fail_loud: non-zero exit
failure_modes:
  - mode: un-gated merge site
    detection: walker test red
    alert_route: PR author
logs:
  where: CI logs
  retention: 90 days
discoverability_test:
  command: bash plugins/soleur/test/review-evidence-arm-walker.test.sh
  expected_output: "0 failures"
```

## Guard Contract

### Guard 1 — review-evidence-arm-walker

**Property.** Every merge site in the repo is either arm-check-gated or listed in the exemption ledger.

**Assembly.** All files matched by merge-token scan (gh pr merge, gh_app pr merge, enablePullRequestAutoMerge, REST merge endpoint, enqueuePullRequest, enableAutoMergeSquash, --admin, plain --squash).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add an un-gated `gh pr merge --squash` site | RED |
| 2 | Add a site invoking the arm check | GREEN |
| 3 | Add a ledger row for a new site | GREEN |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "repo-wide arm walker + domain-surface control" | walker test + R4 predicate | mapped |
| 2 | "ADR-328 first" | ADR-328 | mapped |
| 3 | "ledger seed three sites" | ledger | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| walker | "repo-wide arm walker" | asked |
| ledger | "exemption ledger" | asked |
| ADR | "create ADR" | asked |

### Split Assessment

- Subsystems touched: 4 — .github, apps, plugins, knowledge-base
- Planned files: 8 | Estimated changed lines: 400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] ADR-328 exists with status active, decision + alternatives.
- [ ] Ledger exists with 3 seed rows + schema (site, surface, reason closed set, owner, added, ruling); governance note CTO-only.
- [ ] Walker test exists and scans all merge tokens listed; exits 0 on clean tree.
- [ ] Three bot sites either invoke arm check or have ledger rows.
- [ ] Domain-surface refusal leaves PR unarmed + needs-review label.
- [ ] Hook re-arm text references review-evidence-comment.md#arm-check and #8791 carve-out.
- [ ] Walker test passes (green) after edits.
- [ ] #12712 untouched.
