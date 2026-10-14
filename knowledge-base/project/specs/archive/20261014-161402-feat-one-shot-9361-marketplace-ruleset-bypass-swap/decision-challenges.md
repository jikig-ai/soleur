# Decision challenges: #9361 marketplace ruleset bypass swap

Plan-review findings that argue the operator's stated scope should change. The operator's direction is the default and is what the plan implements; these are surfaced for ship to render, not applied.

## 2026-10-04 DC-1 (user-challenge): also remove the `known-gap-9361` annotation in this PR

- Operator direction: the scope list names `infra/github/*.tf`, the canonical JSON and the test fixtures; the boundary says no agent `--admin` merge on a PR touching `.github/workflows`.
- Challenge (architecture-strategist P1, spec-flow-analyzer, CTO): after the swap the annotation in `.github/workflows/apply-github-infra.yml` ("bypass actor is still soleur-ai ... do not re-set any key") is stale and would misdirect on the likeliest remaining 409 causes.
- Plan response: kept out of scope (Deferral 2, hard trigger immediately after #9361 is closed); the recovery decision table in the plan tells the reader the annotation is stale. If the owner wants it in this PR, the merge must then avoid agent `--admin`.

## 2026-10-04 DC-2 (user-challenge): move the `main.tf` legacy-arm removal to its own PR

- Operator direction: remove the dead legacy-mode arm in `infra/github/main.tf` in this PR.
- Challenge (DHH P1): the PR plan job exercises only TOKEN mode, so the INFRA-mode arm is first run in the production apply.
- Plan response: kept in this PR; the INFRA-mode arm is semantically unchanged (the ternaries already resolved to the infra variables), a scratch probe measured the "neither set" behavior (fails loudly, no ambient-token fallback), and Phase 3 step 5 adds the INFRA-mode probe before merge. Recovery table: a plan/provider-config error reverts the `main.tf` hunk alone.

## 2026-10-04 DC-3 (taste): omit `commit_author`/`commit_email` so GitHub attributes the commit to the App

- Operator direction: change both to `soleur-infra[bot]`.
- Challenge (architecture-strategist P2): hand-written author fields are informational, not proof of identity.
- Plan response: kept as asked; the diff also guarantees the file is an in-place update (the D5 evidence commit). The plan treats the author string as informational only and bases write evidence on the apply result plus the new commit.

## 2026-10-04 DC-4 (taste): ADR / C4 / runbook edits in a follow-up PR after the evidence

- Challenge (DHH P1, CTO P2): the docs assert the swap before the apply proves it.
- Plan response: kept in this PR (Phase 2.10 makes recorded architecture a deliverable of the change that falsifies it; the freshness gate also forces the regenerated model); the ADR entry is shortened to 2-4 lines and states the swap is declared, not evidence.
