# Decision Challenges — feat-one-shot-6031 (GHCR installation-token minter)

## HALT: Phase 0.1 precondition gate failed — blocked on PR #6011

**Date:** 2026-07-05
**Disposition:** one-shot pipeline halted at `/work` Phase 0, before any build. No minter,
no IaC, no manifest edit was authored. Plan + tasks are committed to the branch (draft PR #6034).

### What the gate checks (plan §Dependency & Sequencing, Phase 0.1)

#6031 is **hard-blocked-by PR #6011** (issue #6005). PR #6011 ships every surface this plan
layers onto and MUST land on `origin/main` first:
- `apps/web-platform/infra/ghcr-read-credential.tf` (the `doppler_secret` resources with `ignore_changes = [value]`)
- the two consumers: `ci-deploy.sh` docker-login + `soleur-host-bootstrap.sh` doppler-get
- `variables.tf` (the interim PAT vars)
- **ADR-086 itself** — the sole authority this plan cites

The plan forbids re-authoring any of these here (double-authoring `ghcr-read-credential.tf` +
ADR-086 collides at merge).

### Observed state on `origin/main` (2026-07-05, verified)

| Check | Result |
|---|---|
| `apps/web-platform/infra/ghcr-read-credential.tf` on origin/main | **ABSENT** |
| `ADR-086-*.md` on origin/main | **ABSENT** (highest ADR on main is ADR-085) |
| PR #6011 state | **OPEN, draft, mergeable=CONFLICTING, mergeStateStatus=DIRTY** |
| issue #6005 state | **OPEN** (closed_by: [6011]) |

PR #6011 is not merged and is not near merge (draft + conflicts).

### Resume criterion

Re-run `/soleur:go 6031` (or `/soleur:one-shot #6031`) **only after PR #6011 has merged to main**.
At resume: `git rebase origin/main` this branch onto post-#6011 main, re-verify Phase 0.1
(both artifacts now present), then proceed to Phase 0.2 (the empirical GHCR go/no-go spike,
which mints a real token and is operator-privileged) and onward.

No decision is required from the operator here — this is a sequencing block, not a design fork.
