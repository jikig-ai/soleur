# Decision Challenges — feat-one-shot-6031 (GHCR installation-token minter)

## OPEN: ADR-088 arm-(b) infeasibility — App installation token cannot pull private GHCR

**Date:** 2026-07-05 (post-merge of #6034 + #6067)
**Status:** OPEN — blocks the #6031 cutover; minter DISABLED pending resolution.

### Finding (high confidence, verified live)

A **GitHub App installation token cannot `docker pull`** the private, repo-linked GHCR
container packages (`ghcr.io/jikig-ai/soleur-web-platform`, `soleur-inngest-bootstrap`),
even with every documented precondition satisfied:

- Package **linked to** `jikig-ai/soleur` (verified via `GET /orgs/.../packages/container/...`).
- App installation `repository_selection: all` (covers `soleur`).
- App manifest `packages: read` granted + org-owner re-consent accepted (AC10 ✅ — a mint
  returns `permissions: {"packages":"read"}`).
- Token minted via `POST /app/installations/{id}/access_tokens` with
  `{"permissions":{"packages":"read"}}`, also tried `repositories:["soleur"]`.

Result: `docker login ghcr.io -u x-access-token -p <token>` **succeeds**, but
`docker pull ...:<tag>` returns **`denied`** (on `:latest` and a real tag `v0.198.2`).

**Contrast:** a user **classic PAT** (`deruelle`, `read:packages`) pulls fine, and the
Actions **`GITHUB_TOKEN`** (a different app's installation token) pulls fine. So package
pull is granted to *users* and the *repo's own Actions*, but **not** to a third-party
GitHub App installation token — the arm-(b) risk the plan's Phase-0 flagged as plan-defining.

### Implication

Everything in ADR-088 works — the minter, IaC, manifest grant, the scoped mint (AC10) —
**except the one load-bearing requirement**: the minted token cannot pull. If a GitHub App
installation token is categorically unable to pull private repo-linked GHCR packages, the
control-plane-minter mechanism cannot deliver a usable host-pull credential, and ADR-088 is
infeasible as designed.

### Incident note (self-inflicted, recovered)

The minter was triggered manually BEFORE the pull path was validated. It overwrote the
working classic PAT in Doppler `prd` `GHCR_READ_TOKEN` (`ghp_…`/`deruelle`) with a
non-pulling installation token, which would have failed the next host `docker pull`.
Recovered by restoring the pre-write value from Doppler's config-log diff and **revoking**
the `ghcr-minter-write` service token so the running cron cannot re-clobber. Prod was never
down (`/health` 200 throughout). **Lesson:** never fire a credential-writing cron against
prod before its output is end-to-end validated. The exposed PAT should be rotated.

### Options

- **(a) Retain the machine-account/user classic PAT (ADR-087 D1)** — works today; PAT
  creation is browser-only → does not scale to zero-touch multi-tenant (ADR-088's reason).
- **(b)** Find a GHCR path to grant an App installation package-read (unknown if any exists).
- **(c)** Make the packages `internal` — reduces supply-chain isolation.
- **(d) Escalate to GitHub support** to confirm the limitation + supported path.

### Recommendation

**(d) escalate + (a) keep the PAT interim.** Do NOT revoke the interim PAT (AC13 stays
open). Keep #6031 OPEN. Minter DISABLED (`GHCR_MINTER_DISABLED=true` + env kill-switch;
sentry monitor removed) via the disable PR.

### GitHub-support question

> Private GHCR container package `ghcr.io/<org>/<pkg>`, linked to repo `<org>/<repo>`. An
> org-owned GitHub App with `packages: read`, installed on the org with access to all repos.
> We mint an installation token via `POST /app/installations/{id}/access_tokens` with
> `{"permissions":{"packages":"read"}}` (also tried `repositories:["<repo>"]`).
> `docker login ghcr.io -u x-access-token -p <token>` **succeeds**, but `docker pull …:<tag>`
> returns **`denied`**. A user classic PAT (`read:packages`) and the Actions `GITHUB_TOKEN`
> both pull the same package. **Is a GitHub App installation token supported for pulling
> private, repo-linked GHCR container packages? If so, what configuration grants it? If not,
> what is the supported control-plane path to grant a machine identity pull access to
> private container packages without a user PAT?**

---

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
