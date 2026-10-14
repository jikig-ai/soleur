# Tasks — Cloudflare Pages migration (#7640)

Plan: **ARCHIVED 2026-09-03** to
`knowledge-base/project/plans/archive/20260903-221104-2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`
(the live path this line used to cite no longer exists — see AC58).

> **STATUS, recorded 2026-09-03 at archive time.** Every checkbox below is
> UNTICKED and that is a bookkeeping gap, not a statement about the work: PRs
> 1-3 all shipped. **The boxes are deliberately left as they are** rather than
> bulk-ticked, because ticking a claim nobody verified is worse than leaving an
> honest gap — this file is being archived, not resumed.
>
> What actually landed, by merge commit on `main`:
>
> | PR | commit | subject |
> |---|---|---|
> | PR1 | `a05ae1f77` | Cloudflare Pages substrate (#7649) |
> | PR2 | `3244be4f5` | dual-publish through the cutover window (#7751) |
> | PR3 | `2a589e9f4` | attach the custom domains (#7771) |
> | (guard) | `171338cd7` | guard the `ssl = "full"` rule holding the apex up (#7753) |
> | PR4a | `428e1ec78` | shrink the apex to one address (#7780) |
> | PR4b | `99eeebfef` | flip the apex to a CNAME (#7793) |
> | PR5 | this PR | retire the GitHub Pages publish leg |
>
> Deliverables verified present at archive time: `cf-pages.tf` (2
> `cloudflare_pages_domain` attachments), `seo-bulk-redirects.tf`.
>
> PR4/PR5 were tracked in a SEPARATE spec dir
> (`feat-one-shot-7640-pr4-dns-cutover-pr5-retire-gh-pages`), archived alongside
> this one. **Precisely:** that dir's Phases 1-2 were maintained as the work went;
> 2.11 and all of Phases 3-4 were still unticked on `origin/main` and were ticked
> retroactively by PR5 against verified evidence. "Maintained" overstated it.

Delivery is **three sequenced PRs, IaC first** (plan §Delivery Sequencing). A single merge
cannot produce the verification order the plan asserts.

## Phase 0 — Pre-flight (blocking; nothing starts until this closes)

- [ ] 0.1 Mint the narrow `Pages:Edit` token via Playwright, **no expiry**; record a
      `playwright-attempt:` evidence line. Write to Doppler `soleur/prd_terraform` as
      `CF_API_TOKEN_PAGES`. (`automation-status: UNVERIFIED` — attempt before any handoff.)
- [ ] 0.2 Run the first-use scope probe. Require `pages -> 200`, `rulesets -> 403`.
      A `200` on the second line means re-mint narrower.
- [ ] 0.3 Assert the project name `soleur-docs` is free.
- [ ] 0.4 Confirm `TF_VAR_cf_api_token_pages` resolves from `prd_terraform`. PR1 cannot
      merge until it does — an unprovisioned no-default root var fails every apply on this root.
- [ ] 0.5 Re-capture the header and apex `MX`/`TXT` baselines; record in the PR body.

## Phase 1 — PR1: substrate (fires apply-infra only)

- [ ] 1.1 Create `apps/web-platform/infra/cf-pages.tf`: `cloudflare_pages_project.docs`
      (`production_branch = "main"`, no `source` block), `cloudflare_pages_domain.apex`,
      `cloudflare_pages_domain.www`, and two `github_actions_secret` (token + account id),
      each with a rotation-policy header comment.
- [ ] 1.1b **PF-Z (blocking, plan §Downtime & Cutover)** — with the apex custom domain attached
      and **no DNS record changed**, measure whether `https://soleur.ai/` already serves from
      Pages (SHA match on `version.txt`, GitHub-origin headers gone). If yes, the cutover is
      zero-downtime and PR3's record swap is cosmetic tidy-up. If no, PR3 uses the two-pass
      apply. Reversible: detaching restores the prior state.
- [ ] 1.2 `main.tf` — add the `cloudflare` provider alias `pages`.
- [ ] 1.3 `variables.tf` — declare `cf_api_token_pages`, sensitive, **no default**;
      description is the scope ledger (permission, no-expiry, three storage locations,
      four names for one value, no `pull_request` trigger on the consumer).
- [ ] 1.4 `seo-bulk-redirects.tf` — add `cloudflare_list.www_canonical` (one item:
      `subpath_matching`/`preserve_path_suffix`/`preserve_query_string` enabled,
      `include_subdomains` **disabled**) and a **second** `rules {}` block in
      `cloudflare_ruleset.bulk_redirects`, declared **after** the legal-redirects rule.
- [ ] 1.5 `scripts/encryption-posture-ledger.json` — classify `cloudflare_pages_project`
      into `store_classes` (with `attestation_url` + `retrieved_on` ≤ 365 days) and
      `cloudflare_pages_domain` into `non_store_types`. Without this, `ci.yml`'s
      `lint-encryption-posture.py --repo-sweep` fails closed on both new types.
- [ ] 1.6 Cert-reissue **disarmament** (plan §D2): add an apex-topology precondition to
      `cron-gh-pages-cert-reissue.ts` that refuses when the apex record type is not `A`;
      remove the `cron` trigger from `cron-gh-pages-cert-state.ts` (retain manual-trigger);
      record the AP-019 status in the principles register.
- [ ] 1.7 `apply-web-platform-infra.yml` — add the six new `-target=` addresses
      (`cloudflare_pages_project.docs`, `cloudflare_pages_domain.apex`,
      `cloudflare_pages_domain.www`, two `github_actions_secret`, `cloudflare_list.www_canonical`)
      and, in PR3, `cloudflare_record.pages_apex`.
      **Retain `-target=cloudflare_record.github_pages`** (plan §D4) — removing it once the
      block leaves config means the destroy is never planned. Assert by direct grep, NOT via
      `terraform-target-parity.test.ts` (which cannot see these resource types and passes
      vacuously).
- [ ] 1.8 Rewrite `www-apex-canonicalizer.test.sh` against the five-link chain, with an
      AP-023-conformant anti-vacuity floor (`printf >&2` + `exit 1`; counter increments at
      the call site, never inside both verdict helpers).
- [ ] 1.9 Docs: ADR-194 amendment, `domains.md` resolution note, three `model.c4`
      description corrections, `soleur_acme_probe` description fix, deferred-cleanup issue.
- [ ] 1.10 Gates PF1-PF4 (state, secrets, the R8 DNS-side-effect probe, live www 301 + the
      ten legal paths).

## Phase 2 — PR2: deploy path (fires deploy-docs only)

- [ ] 2.1 `deploy-docs.yml` — swap **only** the three terminal steps for
      `npm install --no-save wrangler@4.124.0` + `npx wrangler pages deploy _site
      --project-name=soleur-docs --branch=main --commit-hash=$GITHUB_SHA --commit-dirty=false`.
- [ ] 2.2 Emit `_site/version.txt` containing `${GITHUB_SHA}`; add `test -f` to the
      build-verification gate.
- [ ] 2.3 Add the post-deploy custom-domain probe (fails the job on SHA mismatch).
- [ ] 2.4 Leftovers: rename the workflow, remove the `environment: github-pages` block,
      drop `pages: write` / `id-token: write`, rewrite the stale Pages-actions comment.
- [ ] 2.5 Create the cutover runbook, including content rollback and the fact that
      `workflow_dispatch` cannot carry `[ack-destroy]`.
- [ ] 2.6 Gates PF5-PF8 (production-branch identity, 404, the custom-domain **detach**
      measurement, the pre-opened revert PR).

## Phase 3 — PR3: cutover (fires apply-infra; `[ack-destroy]`)

- [ ] 3.1 `dns.tf` — remove `cloudflare_record.github_pages`; add
      `cloudflare_record.pages_apex` (`name = "soleur.ai"`, never `@`); retarget
      `cloudflare_record.www`'s `content` (in-place update); rewrite the contract comment
      to name all three redirect substrates.
- [ ] 3.2 Express the apply as **two targeted passes** — destroy, assert, then create
      (plan §D4, PF-ORDER).
- [ ] 3.3 Pre-flight PF9, PF10, PF-ORDER.
- [ ] 3.4 Verify CUT0-CUT9 under the 3-consecutive-samples rule. Roll back at T+20 min
      if not all green.
