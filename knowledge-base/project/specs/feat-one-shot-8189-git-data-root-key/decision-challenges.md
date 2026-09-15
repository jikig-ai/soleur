# Decision challenges — feat-one-shot-8189-git-data-root-key

Recorded headless during planning (plan Phase 4.5 / Plan Review). `ship` renders these into the PR body
and files an `action-required` issue where needed.

## DC-1 — Dedicated R2 bucket cut (User-Challenge against ADR-220 D2.1 / #8189 scope)

- **Stated direction:** #8189 and ADR-220 D2 require a dedicated R2 bucket with its own token for the new
  Terraform root.
- **Change:** the new root uses the shared `soleur-terraform-state` bucket with its own state key.
- **Why:** no credential in the repo can mint a bucket-scoped Cloudflare token (ADR-130 rejects holding
  `API Tokens:Edit`), so the bucket token could only be minted by hand, which the task's constraints
  forbid; and `CF_API_TOKEN_R2` in `prd_terraform` is account-wide, so a dedicated bucket would be readable
  by the same credential holders anyway (measured 200 on two buckets).
- **Cost of being wrong:** none added — the separate root still keeps the key out of web-platform state.
- **Default kept:** the separate Terraform root (the operator's stated direction) is implemented.

## DC-2 — Blocker 2 mechanism deferred to a follow-up (within the operator's stated allowance)

- **Stated direction:** resolve #8189's blockers in the same PR, or file tracked follow-ups only after
  inline triage.
- **Change:** the nonexistent `soleur-web` / `soleur-drain` unit calls are deleted and every real mode
  (`dry_run=false`, `rollback=true`, `confirm_wipe=true`) refuses before any remote call; the real
  freeze/reload/rollback redesign (and the `prd` flag write token it needs) is filed as F2.
- **Why:** there are no real unit names to substitute; the correct mechanism is a redesign on which plan
  review found three P0 and six P1 hazards, and the CTO recommends a different freeze model. The #8189
  close criterion (a dry run reading `role=git-data-auth verdict=ok`) needs none of it.
- **Cost of being wrong:** the first real cutover waits for F2 (it also waits for F1 and #7226).

**v3 update:** plan review went further than DC-2's first form: the unreachable cutover body (rsync,
repoint, canary, wipe, freeze, flip, rollback) is deleted rather than kept behind a refusal, and the
`dry_run` / `rollback` / `confirm_wipe` inputs are removed. The dispatch is a reviewer-gated read-only proof
until F2. Git history and F2's body keep the design and every review finding.

## DC-3 — Doppler OIDC identity not used (ADR-220 fallback taken)

- **Stated direction:** OIDC-first token delivery.
- **Change:** a Terraform-minted read token in a repo secret, used only by a job behind a reviewer-gated,
  `main`-only environment approval, with a reference lint.
- **Why:** Doppler service-account identities require the Team or Enterprise plan; the workplace is on the
  Developer plan (config inheritance was measured denied on 2026-07-05). `/work` Phase 0 re-probes.

## DC-4 — No window-scoped read credential (Taste, ADR-220 D3)

- **Stated direction:** ADR-220 D3 / #8189: the read credential exists only for a cutover window.
- **Change:** no `access_window_open` toggle; the read token persists until a reviewed PR `-replace`s or
  removes it.
- **Why:** `doppler_service_token` has no expiry attribute, and closing a window would revoke the token
  only — the public key stays authorized on the host until a replace after a rotation, and the private key
  stays in state and Doppler (CTO C1-a, CLO). The toggle bought no property in the plan's list.

## DC-5 — `web-1-swap` membership moves to F2 (User-Challenge against blocker 4's wording)

- **Stated direction:** "No web-1-swap vs git-data concurrency guard — add one."
- **Change:** this PR adds the git-data half (`git-data-state` on the cutover workflow and on the new
  root-key apply); `web-1-swap` membership lands in F2 on the job that drains web-1.
- **Why:** after this PR the dispatch mutates nothing on web-1. A job waiting on `web-1-swap` can cancel a
  pending release deploy (#8167) — a real harm bought for no protection.

## DC-6 — Reuse `web-platform-infra-apply` instead of a new `git-data-cutover` environment (Taste)

- **Change:** the cutover job and the root-key apply declare the existing Terraform-managed environment
  (reviewer, `main`-only policy).
- **Why:** removes the auto-create-unprotected hazard of a new environment name, a preflight job and an
  environment-assert script. Its `can_admins_bypass: true` / `prevent_self_review: false` are stated in
  ADR-220 and in the Article 30 TOM limits.

## DC-7 — Keep the Doppler hop (reviewer suggestion not taken)

- **Suggestion (code-simplicity):** publish the private key directly as a repo secret; a repo secret
  holding a Doppler token has the same reach.
- **Kept:** AP-008 (secrets live in Doppler) and the operator's "environment-bound read credential"
  direction; ADR-220 explicitly rejected a repo secret holding the key.
