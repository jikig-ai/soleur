# Decision challenges — feat-one-shot-8562-inngest-bootstrap-retrying-unit

## DC-1 (disclosure, user-challenge class): the merge triggers a standard `web-v*` release

**Operator direction:** "NO production writes … the merge itself must not trigger an infra apply or a host replace."

**Finding (measured, surfaced by terraform-architect at plan Phase 2.8):** `.github/workflows/web-platform-release.yml`
fires on `on.push.paths: 'apps/web-platform/**'` (`:13-17`, inner `check_changed` `path_filter: "apps/web-platform/ …"` `:128`)
with no commit-message kill switch (`skip_deploy` is dispatch-only). Any merge touching `apps/web-platform/infra/**` —
which every honest #8562 implementation must, because `cloud-init-inngest.yml` lives there — cuts a `web-v*` release and
rolls UNCHANGED app code to the production web hosts. Precedent under this same backlog brief: #9071 (`3339fb01e0`, infra-only)
ran push run `36407993582` (success) today.

**What it is not:** not an infra apply (suppressed by `[skip-web-platform-apply]`), not a host replace, not a `vinngest-v*` mint,
not a registry replace.

**Default taken (operator's stated direction preserved):** proceed; the brief's enumerated merge consequences (infra apply,
host replace, vinngest mint, registry replace) are all avoided. The `web-v*` release is disclosed in the PR body.

**Operator choice if this is not acceptable:** hold the merge, or accept the release as the standard consequence of any
`apps/web-platform/**` merge. There is no in-repo way to suppress it without a workflow edit (UNTRUSTED-CI, separate PR).

## DC-2 (taste, plan review): items declined or chosen between reviewers

Recorded headless per plan skill §Plan Review; defaults below are what the plan implements.

| # | Proposal (source) | Disposition | Reason |
|---|---|---|---|
| 1 | Fold ADR-257 (provisionally ADR-256; renumbered, 256 was taken) into an ADR-115 amendment (DHH) | Declined | Issue #8562 states the restructure "needs its own ADR"; ADR-115's acceptance is registry-only |
| 2 | Use `systemctl enable --now <timer>` as the single first-boot trigger (DHH, simplicity) | Declined | The explicit `start --no-block` does not depend on elapsed-`OnBootSec` semantics (measured on 261, unmeasured on 255); T12 pins a single trigger |
| 3 | Hardcode `TimeoutStartSec=30min` (DHH) | Declined | A budget figure must be measured (Sharp Edges); 30 min stays as the documented fallback |
| 4 | Drop own-dispatch / harness mutation rows (DHH) | Declined | Required by the Guard Contract gate (plan Phase 2.12) |
| 5 | Power-of-two Sentry page decay (terraform-architect) vs none (DHH, simplicity) | No decay | Rule throttle `frequency_minutes = 23` on one grouped issue already caps paging |
| 6 | Single systemd-only harness (DHH, simplicity) | One file, two tiers | No in-repo precedent for systemd-as-PID-1 in a container; Tier A must survive a Tier B skip |
