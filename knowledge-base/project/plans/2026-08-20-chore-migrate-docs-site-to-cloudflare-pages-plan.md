---
title: "Migrate the marketing/docs site off GitHub Pages to Cloudflare Pages (ADR-194)"
date: 2026-08-20
slug: chore-migrate-docs-site-to-cloudflare-pages
branch: feat-one-shot-7640-pr4-dns-cutover-pr5-retire-gh-pages
prior_branches: [feat-one-shot-7640-cloudflare-pages-migration]
issue: 7640
closes: 7640
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Migrate the marketing/docs site off GitHub Pages to Cloudflare Pages

## Enhancement Summary

**Deepened:** 2026-09-03 (PR4/PR5 pass) — the ordering mechanism was **redesigned**, not
annotated. Four reviewers (a strong-model advisor consult, architecture-strategist,
spec-flow-analyzer, kieran-rails-reviewer) plus the deepen-plan halt gates. Three findings
falsified load-bearing choices made earlier in the same pass:

1. **Hypothesis Z is FALSE (measured).** Attachment does not move the origin; the record does.
   The swap is a genuine cutover and the residual-downtime path is the plan of record.
2. **The two-pass merge-path pre-pass is dead.** `git revert` of the cutover PR deletes the
   pre-pass steps along with the DNS hunk (`on: push` runs the workflow from the merged ref),
   so the rollback would have run unordered against an already-failing apex. Its shape gate
   also refused both the completion *and* the rollback of a half-converged state. Replaced by
   collapsing the transition onto **one resource address**, where Terraform core supplies the
   ordering — four artifacts and an eleven-row mutation battery dissolved.
3. **`git revert` is forbidden for the flip (measured).** It drops the `moved` block that
   supplies the atomicity, yielding two unrelated addresses and reproducing `81053` in reverse.
   The rollback is a **generated** reverse-`moved` PR.

Also corrected in this pass: **CUT0 was unsatisfiable** (`deploy-docs.yml` deliberately does not
fire on `dns.tf`, so `version.txt` never holds the merge SHA — it would have forced a false
rollback at T+20); AC23 is red-by-construction until PR5 and is satisfied by the per-leg table;
`apex-origin-probe.sh` lacks a cache-buster while being the rollback's branch selector; AC38
named a nine-row range against an eleven-row matrix; and a second `discoverability_test:` block
would have been silently ignored by the preflight parser.

**Deepened:** 2026-08-20. Eight review agents (terraform-architect, architecture-strategist,
spec-flow-analyzer, code-simplicity-reviewer, kieran, CTO, a strong-model advisor consult) plus
the deepen-plan halt gates. The plan was **restructured**, not annotated — four findings
falsified load-bearing choices in the first draft.

### What changed and why

1. **The www→apex mechanism was wrong.** The first draft put the 301 in a Pages `_redirects`
   file. Cloudflare documents domain-level redirects as **unsupported**, citing the exact
   shape proposed; the repo's own canonical-host build gate would have rejected the file's
   contents on every build; and the guard's chokepoint assertion would have landed outside
   `infra-validation.yml`'s path filter, so the guard would have passed by never running.
   Three independent failures behind one plausible line. Replaced with account Bulk Redirects
   — the mechanism Cloudflare's own www-redirect guide prescribes and one this repo already
   has wired.
2. **One merge could not produce the plan's own verification order.** `apply-web-platform-infra.yml`
   and `deploy-docs.yml` fire on the same push with no ordering edge, so the apex would point at
   a Pages project with zero deployments, or the deploy would read a secret Terraform had not
   yet created. Restructured into **three sequenced PRs, IaC first**.
3. **A deferred item could not be deferred.** `cron-gh-pages-cert-state` runs `cron: "0 3 * * *"`
   and its issue body instructs firing the reissue routine — which, post-cutover, de-proxies
   **www** and then **cannot restore it** (`restore` fails closed at `1/5` records). Disarmament
   is now an in-scope deliverable (D2); deletion stays deferred.
4. **The cutover is a gap, not a swap.** A removed resource and its replacement are unrelated
   graph nodes, so Terraform dispatches the deletes and the create concurrently — a coin flip
   between a clean apply and error `81053` on the live apex, with a recordless window that
   negative-caches for 1800 s. Gate 4.55 then forced the question the draft never asked: is the
   outage necessary at all? Probably not — **Hypothesis Z** (custom-domain attachment, not the
   record, selects the origin) is now the plan of record, with the two-pass apply demoted to a
   measured fallback.

### Also corrected

- `ci.yml` runs `lint-encryption-posture.py --repo-sweep`, which **fail-closes on unknown
  resource types**; neither Pages type is in the ledger. Adding `cf-pages.tf` would have
  reddened CI deterministically.
- The new apex record's Terraform address was never named — and `-target=cloudflare_record.github_pages`
  must be **retained**, or the destroy is never planned.
- Acceptance criteria that could not pass a correct implementation: `grep -c` exits 1 on zero
  matches; a bare `grep -c 'default'` returns 1 on a correct no-default variable; a bare
  action-name grep returns 2 because of a comment.
- A guard was a costume (no runner, two rows resolving to "a reviewer notices") — cut.
- A `_headers` file would have imposed a 4-hour deploy-staleness window on non-content-hashed
  filenames — cut; the cache-control change is now deliberate.
- Five monitors, not four: `soleur_changelog_deep` is the only deep-path apex monitor and
  guards exactly the Pages directory-index risk. `soleur_acme_probe` goes **vacuous**, not
  merely misdescribed.
- The apex carries live Protonmail `MX` and four `TXT` records that no criterion protected —
  a silent mail break invisible to every uptime monitor. Baseline captured; CUT9 added.
- The origin-provenance probe **failed open**, printing the success verdict for an unreachable
  site (an AP-021 violation). Hardened and verified across all four arms.
- `workflow_dispatch` structurally cannot carry `[ack-destroy]`, so the documented escape hatch
  cannot perform the rollback. The revert PR is now pre-opened.

### Confirmed as sound (probed, no change)

An apex CNAME **does** coexist with apex `MX`/`TXT` at Cloudflare — CNAME flattening is what
makes it legal, and the conflict set never includes `MX`/`TXT`. This was the highest-flagged
structural risk and it is not a risk; CUT9 still asserts it, because the failure would be silent.


## Overview

ADR-194 (accepted 2026-08-20, commit `2635b1c3a`) records that the docs-site hosting
arrangement holds two requirements that cannot both be satisfied: `domains.md` mandates
`proxied = true` for the HSTS preload commitment, and GitHub Pages refuses certificate
issuance or renewal for a proxied host (`is_https_eligible: false`). The origin
certificate therefore expires every ~90 days by construction and cannot self-heal.
Serving the same Eleventy build from Cloudflare Pages removes the origin certificate from
the picture entirely — there is no origin leg to validate — and the failure class stops
existing rather than being managed.

This plan delivers **the migration mechanism and the live DNS cutover**, sequenced as
three PRs on this branch's work item (see `## Delivery Sequencing`). Deletion of the
certificate-reissue subsystem, retirement of the ACME carve-out, and the return of the
zone to `ssl = "strict"` are **out of scope**. `ssl = "full"` in `seo-config-rules.tf`
stays in place throughout — it is what keeps the site up today, and it is also what makes
the rollback viable.

The build pipeline is untouched above the last three steps of `deploy-docs.yml`: Eleventy
and all six gates stay authoritative over what gets published.

**One deferred item is promoted into scope.** The certificate-reissue routine is retained
but must be **disarmed** in this work. Deletion and disarmament have different deadlines:
the hazard is *created* by the cutover, so it cannot be closed by a later PR. See
`## Design Decision D2`.

## Delivery Sequencing

`apply-web-platform-infra.yml` fires on merge to `main` touching
`apps/web-platform/infra/**` and runs **one** targeted apply. `deploy-docs.yml` fires on
the same push for its own path set. They have no ordering edge. A single PR carrying
`cf-pages.tf`, `deploy-docs.yml` and the `dns.tf` cutover therefore cannot produce the
verification order this plan asserts, and produces two guaranteed-bad interleavings:

- the apply finishes first → the apex points at a Pages project with **zero deployments**,
  and Cloudflare serves its own error page at `soleur.ai`;
- `deploy-docs.yml` starts first → it reads a GitHub Actions secret Terraform has not
  created yet, resolves it to empty, and fails on wrangler auth — with DNS already moved.

This is a technical fork, not an operator question, so it is decided here: **three
sequenced PRs, IaC first.** Scope is unchanged — the same work item still delivers the
mechanism and the cutover.

| PR | Contents | Fires | Gate before the next PR |
|---|---|---|---|
| **PR1 — substrate** | `cf-pages.tf` (project, apex domain, two `github_actions_secret`), `main.tf` alias, `variables.tf`, the www Bulk Redirect (`seo-bulk-redirects.tf`), the cert-reissue disarmament, `-target=` allow-list, guard rewrite, ADR/C4/docs. **No `dns.tf`, no `deploy-docs.yml`.** | apply-infra | PF1-PF4 |
| **PR2 — deploy path** | `deploy-docs.yml` only — wrangler leg added **alongside the retained GitHub Pages leg** (dual-publish), build-identity stamp, two probes, publish-verdict step, workflow self-trigger, rename. **`environment:` and `permissions:` RETAINED.** | deploy-docs | PF5, PF6, PF8 (PF7 retired) |
| **PR3 — attach** | `cloudflare_pages_domain.apex` + `.www` **alone** | apply-infra | PR3-GATE (below) — **not** PF9, which is PR4's `dns.tf` plan shape |
| **PR4 — record swap** | *(shape superseded 2026-09-03 — see D5)* the `dns.tf` hunk, delivered as **two merges**: PR4a shrinks the apex `for_each` to one key (`destroy_count = 3`), PR4b adds a `moved` block and flips that one address to a `CNAME` (`resource_deletes: 1`). Both carry `[ack-destroy]` | apply-infra | CUT0′-CUT9 |
| **PR5 — retire GH Pages leg** | `deploy-docs.yml` only: delete the three Pages actions, `environment:`, `pages:`/`id-token:` write, and the verdict step's GH-Pages arm. **Probe B survives.** | deploy-docs | AC33, AC34 |

**Amended 2026-09-02 (PR2) — the sequence is FIVE PRs, and PR2 dual-publishes.**
PR2 originally swapped the publish verb, deleting the GitHub Pages leg. That would
have converted GitHub Pages from a warm standby into a cold one: at ~1 docs
merge/day (measured 14 in 14 days) the revert target this plan retains
DNS-detached would be days stale by PR4, which is the stale-build outcome
`## User-Brand Impact` calls brand-fatal. Both origins now publish every run; the

> **Added 2026-09-03 (#7640 PR4a review).** Three artifact+vector pairs the
> section did not name, all specific to the PR4a->PR4b window rather than to the
> flip:
>
> - **`soleur.ai` origin-pull with no retry target.** Four proxied `A` records
>   let Cloudflare retry a second origin address on a connection failure; one
>   does not. `185.199.108.153` is itself anycast, and all four sit inside the
>   single announced prefix `185.199.108.0/22`, so what is given up is per-VIP
>   retry, not per-PoP redundancy — a BGP withdrawal took all four together
>   anyway. The residual is a 522 on an HSTS-preloaded apex, where the visitor
>   has no `http://` fallback. Reversible in one revert (3 creates, 0 destroys,
>   no ack); the window is bounded by the standing constraint in `tasks.md`.
> - **Search index, which does not recover symmetrically.** A crawl-time 522
>   during that window costs crawl budget and can deindex the only marketing
>   surface a prospect meets pre-signup. The DNS is instantly reversible; the
>   index recovers on Google's schedule, not the operator's.
> - **The `[ack-destroy]` gate is COUNT-based, not SHAPE-based.** It authorizes
>   whatever the plan contains within `-target` scope, and the apex MX/TXT
>   records (Protonmail, SPF, the verification TXTs) are all in that allow-list.
>   The diff cannot reach them — the change is one hunk inside
>   `cloudflare_record.github_pages`, and a `for_each` key removal destroys only
>   instances of its own address — but PF9a is the SHAPE assertion and it is read
>   by inspection, not enforced. Re-read the actual merge-time plan output
>   immediately before typing the token, with the same discipline the plan
>   already applies to PF-Z2 and PF-R8b. A silent mail break is invisible to
>   every uptime monitor in this repo.
GitHub Pages leg retires in PR5, after CUT0-CUT9 hold. This also makes the apex a
legitimate hard gate at PR2 (Probe B), which the swap could not do until PR4.
**PF7 is retired by construction** — see D3's supersession note.

**Amended 2026-08-20 (#7640) — the cutover is SPLIT, and the rollback property is
completed rather than weakened.** PR1 originally attached both custom domains. Under
the plan's own Hypothesis Z ("the apex begins serving from Pages at the moment of
attachment") that would move the apex origin to a project with ZERO deployments, on
merge, with the verifying measurement scheduled after the mutation. The attachments
now land in PR3 and the record swap in PR4, which is correct under BOTH branches of Z
rather than only the preferred one: whichever of the two actually selects the origin,
reverting the PR that introduced it removes it. That retires D3's open item 3(b) by
construction instead of by measurement.

The property that was load-bearing was never "one file" — it was that the revert
removes exactly the cutover and leaves the substrate intact. `cloudflare_pages_project`,
both Actions secrets and the Bulk Redirect stay in PR1/PR2 and survive every revert, so
the original hazard ("reverting would destroy the Pages project along with the DNS
record") is not engaged. PR3 is 0 destroys and needs no `[ack-destroy]`; only PR4 does.

PR3 and PR4 being single-hunk commits is what makes each rollback a surgical
`git revert`. If `cf-pages.tf` and `dns.tf` shared a squashed commit, reverting would
destroy the Pages project along with the DNS record, leaving the apex pointed at nothing.

PR1 also touches `apps/web-platform/infra/sentry/cron-monitors.tf`, so its merge fires **two**
apply workflows: `apply-web-platform-infra.yml` and `apply-sentry-infra.yml`. They are separate
Terraform roots sharing no resource, so no ordering edge is required and neither interleaving is
bad. The sentry-root plan is an **update, 0 destroys** — `sentry-destroy-required` passes without
`[ack-destroy]`, and PR1's merge commit message must **not** carry `[skip-sentry-apply]`.

**PR1 must come first, not last.** Shipping the workflow before the substrate would swap
`deploy-docs.yml` away from GitHub Pages while GitHub Pages is still the live origin —
dark-shipping the docs site and reddening `main` on every docs push for the whole interval.

### Resume status — 2026-09-03, this branch delivers PR4 and PR5

| PR | State | Evidence |
|---|---|---|
| PR1 — substrate | **MERGED** (2026-08) | `cf-pages.tf`, `seo-bulk-redirects.tf` present on `main`; the six new addresses are in `apply-web-platform-infra.yml`'s allow-list (`-target=cloudflare_pages_project.docs` … `-target=cloudflare_record.pages_apex`) |
| PR2 — dual-publish deploy path | **MERGED** 2026-09-02 | `pages-build-identity-probe.sh` + `.test.sh` on `main`; `cloudflare-pages-cutover.md` exists |
| PR3 — custom-domain attach | **MERGED** 2026-09-03 | the "Measure the apex origin (ADR-194 Hypothesis Z)" step exists in the merge-apply job |
| **PR4a + PR4b — the DNS cutover** | **this branch** | `apps/web-platform/infra/dns.tf` is byte-identical to `main` — `cloudflare_record.github_pages` (4 × `A`) and `cloudflare_record.www` (CNAME → `jikig-ai.github.io`) are unchanged. Delivered as two merges per D5; **PR4b is the one that closes #7640** |
| **PR5 — retire the GitHub Pages publish leg** | **this branch, after PR4** | AC33/AC34 |

**Only PR4b closes #7640.** #7640 stays OPEN through PR1-PR3 and through PR4a; the `closes:` line belongs on PR4b's body, and PR5 carries `Ref #7640` (it merges
*after* the closure, and a second `Closes` on an already-closed issue is noise). PR5's own
tracking is AC33/AC34 on this plan.

**Do NOT archive this plan until PR5 has merged and AC34 holds.** The archive step
(`archive-kb.sh`) is a PR5 task, not a PR4 one.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Result |
|---|---|---|
| ADR-194 is accepted and merged | frontmatter + body + `git log --oneline -1 2635b1c3a` | **HOLDS** — `status: accepted`, commit on this branch |
| Issue #7640 open, targets this work | `gh issue view 7640 --json state,title,labels` | **HOLDS** — OPEN, `type/chore`, `priority/p2-medium` |
| Provider supports both Pages resources at the pin | `terraform providers schema -json`, `cloudflare/cloudflare 4.52.7` | **HOLDS** — schemas recorded below |
| `seo_page_redirects` is at the Free cap | 10 rules counted in the resource; Cloudflare availability table: Single Redirects Free = **10 rules per zone** | **HOLDS** — 10/10 |
| "Retiring the ACME carve-out frees the rule the www redirect needs" | Rule 10 read verbatim | **FALSE** — R1 |
| The www→apex 301 is GitHub-Pages-owned | `curl -sSI https://www.soleur.ai/` | **HOLDS** — `301`, `location: https://soleur.ai/`, carries `x-github-request-id` / `via: 1.1 varnish` / `x-fastly-request-id` |
| No `cloudflare_pages_*` resource or `wrangler` usage exists | repo sweep | **HOLDS** — greenfield |
| No `Pages:Edit`-scoped token exists | token ledger in `variables.tf` | **HOLDS** — six tokens, none Pages-scoped |
| Pages `_redirects` can express a www→apex redirect | Cloudflare `_redirects` docs | **FALSE** — R7, the decisive finding |
| `cloudflare_pages_domain` "manages no DNS" | provider schema exposes no DNS attributes | **UNSAFE INFERENCE** — R8 |

### Premise Validation — PR4/PR5 resume pass (2026-09-03)

Re-run at the start of this branch. Everything cited by reference in the resume brief was
probed; nothing was carried on prose.

| Cited premise | Probe | Result |
|---|---|---|
| #7640 is OPEN and is what PR4 closes | `gh issue view 7640 --json state,title` | **HOLDS** — `OPEN`, title matches ADR-194 |
| PR1/PR2/PR3 merged; none touched `dns.tf` | `cat apps/web-platform/infra/dns.tf` on this branch's base | **HOLDS** — `cloudflare_record.github_pages` still `for_each` over the four `185.199.10[89].153` / `.110` / `.111` `A` IPs; `cloudflare_record.www` still `content = "jikig-ai.github.io"`. The cutover file is untouched |
| The six PR1 addresses, **including `cloudflare_record.pages_apex`**, are already in the merge-apply allow-list | `grep -n -- '-target=' .github/workflows/apply-web-platform-infra.yml` | **HOLDS, AND IT IS THE BLOCKER** — `cloudflare_record.github_pages`, `.www`, `.github_pages_challenge`, `cloudflare_pages_project.docs`, `cloudflare_pages_domain.apex`, `.www`, `cloudflare_record.pages_apex` are all present in the single `terraform plan -out=tfplan` of the push-triggered `apply` job. So merging PR4 as-is plans the four deletes, the create and the www update **into one concurrent apply**. See D5 |
| **Hypothesis Z is FALSE** (resume brief item 1) | PR3's post-apply `apex-origin-probe.sh` step returned `SERVING-FROM-GITHUB-PAGES` | **CARRIED, AND PERISHABLE.** Attachment alone does not move the origin; the record selects it. PR4 is a genuine cutover and D4's hazard is live. Re-probed by PF-Z2 immediately before merge — the probe's verdict vocabulary is `SERVING-FROM-GITHUB-PAGES` / `SERVING-FROM-CLOUDFLARE-PAGES` (rc 0) / `UNREACHABLE (…)` (rc 2), so an `UNREACHABLE` is a distinct third answer and must never be read as either origin |
| **R8 is clean** (resume brief item 2) | PR3-G2, measured post-attach | **CARRIED, AND PERISHABLE.** `soleur.ai` → exactly 4 proxied `A` + MX/TXT; `www.soleur.ai` → exactly 1 proxied `CNAME` at `jikig-ai.github.io`. So `cloudflare_record.pages_apex` is a **CREATE, not an import**, and PF9's shape holds: 4 deletes + 1 create + 1 in-place `www` update, `destroy_count = 4`. Re-probed by PF-R8b immediately before merge |
| The two-pass template exists in this repo | `awk` over `apply-web-platform-infra.yml` job names + `ls tests/scripts/lib/` | **HOLDS** — `workspaces_luks_recut` (:3974) and `registry_luks_recut` (:2904) are the template: typed `confirm` guard → scoped `terraform plan -out=tfplan` → `terraform show -json` → a **sourced** gate from `tests/scripts/lib/<name>-gate.sh` → apply the saved plan → post-apply `jq` backstops read from the SAVED plan. `registry_luks_recut` additionally carries `needs: registry_pull_path_gate` — a two-**job** sequencing edge under one dispatch, which is the ordering primitive this plan reuses |
| Gate libraries call the shared fail-closed preamble | `cat tests/scripts/lib/plan-gate-preamble.sh` | **HOLDS** — `plan_gate_assert_readable` / `_classifiable` / `_numeric`. A new gate that does not **CALL** all three is the documented lower tier that fails OPEN. `test-plan-gate-preamble.sh` runs the anchored derivation on every CI run |
| `tests/scripts/test-*.sh` suites are auto-discovered | `grep -n 'for f in\|glob' scripts/test-all.sh`; `grep -n 'recut-gate' scripts/test-all.sh` | **FALSE — and this is the orphan-suite trap.** `tests/scripts/` is **absent from `SUITE_GLOBS` entirely** (`scripts/test-all.sh:1062-1064` says so in as many words); every sibling is registered by an explicit `run_suite` line (`:1527`, `:1618`). A new battery that is not registered there **never runs** |
| `.github/workflows/apply-web-platform-infra.yml` edits fire `infra-validation.yml` | `sed -n '1,100p' .github/workflows/infra-validation.yml` | **HOLDS** — the path is listed in the `pull_request.paths` set (added by #7025). So a workflow-shape guard living under `apps/web-platform/infra/*.test.sh` and invoked from `infra-validation.yml` genuinely fires on a PR that edits only the apply workflow. This is the R10 path-filter class, checked rather than assumed |
| The `[ack-destroy]` gate is line-anchored | `grep -n 'ack-destroy' .github/workflows/apply-web-platform-infra.yml` | **HOLDS** — `:770` is `[[ "$HEAD_MSG" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]`, reading `github.event.head_commit.message`. Empty on a `workflow_dispatch` run, which is what makes D3 item 2 true |
| `ssl = "full"` is guarded by a **separate** open PR | `gh pr list --state open` | **HOLDS** — **PR #7753** (`fix-7749-ssl-full-guard`), *"guard the ssl=full rule holding the apex up, and fix a removal condition that could never be met"*. Its work is **NOT** co-located here. It touches `apps/web-platform/infra/seo-config-rules.tf`, which PR4 does not, so there is no textual conflict; AC7 is already a resource-level assertion rather than an empty-diff one, so #7753's comment rewrite cannot falsify it. The only coupling is apply-ordering, handled by PF-SSL |
| This branch already has an open PR | `gh pr list --state open` | **HOLDS** — **#7780**, `WIP: feat-one-shot-7640-pr4-dns-cutover-pr5-retire-gh-pages` |
| `model.c4` already describes the cutover | `grep -n -i 'pages' knowledge-base/engineering/architecture/diagrams/model.c4` | **HOLDS, IN THE FUTURE TENSE** — the `github` element reads *"ALSO — **until** the #7640 cutover — the HOST of the marketing/docs site"* and the `cloudflare` element reads *"**from** #7640/ADR-194, the HOST"*. Both are true-in-advance descriptions written by PR1. PR4 is the moment they become past/present tense; the `letsencrypt` element's *"From the cutover…"* clause is the same shape. See `### C4 views` |

**Re-probed fresh on 2026-09-03, immediately before finalising — measured, not inherited.**
Both perishable inputs were re-run rather than carried from PR3's transcript:

| Probe | Result |
|---|---|
| `apps/web-platform/infra/apex-origin-probe.sh` | **`SERVING-FROM-GITHUB-PAGES`, rc 0.** Hypothesis Z is still FALSE; the record still selects the origin |
| Apex DNS records | **exactly 4 proxied `A`** at `185.199.108.153` / `.109.153` / `.110.153` / `.111.153`, plus **2 MX and 4 TXT, all unproxied and outside the blast radius** |
| `www.soleur.ai` | **exactly 1 proxied `CNAME`** at `jikig-ai.github.io` |

So `cloudflare_record.pages_apex` is a **create, not an import**, and the four-`A` starting shape
PR4a shrinks from is confirmed live. Note the apex TXT count (4) against the plan's 2026-08-20
baseline, which recorded three values plus known drift — a further reason CUT9 compares
**normalised sets** from a committed fixture rather than bytes from prose (Phase 4.7).

**PF8's pre-opened revert is UNMET, and it is unmeetable as written.** PF8 says *"the revert
PR for PR3 is open, green and mergeable"* before the cutover merges. Under the four-PR
amendment the cutover is PR4, and a revert of PR4 **cannot exist before PR4 merges**: a
branch off `main` carrying the reverse of a diff `main` does not yet have is a no-op, and
`git revert <sha>` has no `<sha>` to name. This is not an oversight to work around, it is a
structural consequence of making the cutover merge-triggered — which D3 requires, because a
`workflow_dispatch` structurally cannot perform the rollback. PF8 is therefore **restated as
PF8′** (see Phase 4), which moves the pre-open from *before the merge* to *before the
decision point*, inside the propagation window that already has to elapse. It is automated
in PR4b's merge steps, never an operator action.

**Resolved, not deferred — and the mechanism changed under measurement.** PF8′ was first drafted
as `git revert -n <merge-sha>`. That is now **forbidden**: measured, a revert of the flip drops
the `moved` block that supplies the atomicity and yields two unrelated addresses dispatched
concurrently — the reverse-direction `81053`, on an apex that is already broken. PF8′ is
therefore a **generated reverse-`moved` rollback PR** (Phase 4b.2, AC70). The operator's
constraint to keep the revert as a **TWO-STEP** shape is preserved in substance: step 1 is the
generated reverse PR for PR4b, step 2 is reverting PR3 only if the origin probe still reports
`SERVING-FROM-CLOUDFLARE-PAGES`.

### Property List (Phase 0.6b)

- **P1** — the docs site serves over HTTPS at `soleur.ai` with no origin certificate that can expire.
- **P2** — `www.soleur.ai` keeps returning a host- and path-preserving `301` to `soleur.ai`.
- **P3** — every existing build gate stays authoritative over what reaches production.
- **P4** — an unmatched path returns HTTP `404` with the site's own 404 page.
- **P5** — response headers the site depends on are preserved, or the regression is measured and deliberate.
- **P6** — the cutover is reversible by a procedure written and rehearsed before it fires.
- **P7** — the existing uptime monitors keep passing without edits, including `sentry_uptime_monitor.soleur_changelog_deep` (`https://soleur.ai/changelog/`), the only deep-path apex monitor and the one that catches "root serves 200 but every other page 404s" — precisely the Pages directory-index risk profile.
- **P8** — the apex keeps resolving mail (MX) and verification (TXT) records unchanged.
- **P9** — no retained subsystem can mutate the post-cutover DNS topology in a way it cannot undo.

**Added for PR4/PR5 (2026-09-03).**

- **P10** — at no instant during the apex transition, **in either direction**, does `soleur.ai`
  carry both an `A` record and a `CNAME`, and at no instant is the transition dispatched such
  that the create could precede the destroy. This is a property about **order and about the
  window**, not about counts: a plan whose shape is exactly right can still violate it.
- **P11** — the rollback lever is the same kind of act as the cutover lever (a merge), so the
  procedure an engineer executes under pressure is the one they already watched succeed.
- **P12** — every guard this work adds is reachable from a CI invocation that actually runs on
  a PR touching the file it guards, and appears in a suite the runner enumerates.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property | Why it is cut |
|---|---|---|
| A rule for the www 301 **inside `seo_page_redirects`** | P2 | The zone phase is at 10/10 (Cloudflare's own availability table: Free = 10 rules/zone), one user-defined ruleset per `(zone, phase)`, and Rule 10 cannot be evicted. The account Bulk Redirects product already in this repo buys P2 on a separate quota. |
| Retire the ACME carve-out "to free the slot" | a free rule slot | The carve-out is an inline `and not (…)` **clause inside Rule 10's expression**, not a rule. Retiring it frees **zero** slots. |
| `_redirects` in the build artifact | P2 | **Impossible.** Cloudflare Pages documents "Domain-level redirects" as *unsupported*, with the exact shape proposed as the counter-example. It would also fail this repo's own canonical-host build gate (R7). |
| `_headers` for `Access-Control-Allow-Origin` / `X-Content-Type-Options` | P5 | Measured: Cloudflare Pages sets both by default, and the zone's `security_header { nosniff = true }` sets `nosniff` independently. |
| `_headers` for static-asset `Cache-Control` | P5 | Cut on measurement. `_site/css/style.css` is **not content-hashed** (`eleventy.config.js` is a straight directory passthrough), so restoring `max-age=14400` would impose a 4-hour deploy-staleness window on a site that redeploys on every merge. Pages' `must-revalidate` default is the better behaviour. P5 is satisfied by declaring the change deliberate, which it now is. |
| A new mechanism for `404.html` | P4 | Pages honours a root `404.html` natively; the existing `test -f _site/404.html` gate already asserts the artifact. |
| A standing "origin provenance" guard | P6 | It has no runner, no file and no CI job, and two of its four mutation rows resolve to "a human notices in review". The property is a one-shot *transition* property; it is kept as cutover assertion CUT2, and its durable half is already covered structurally by the DNS rows of Guard 1. |
| `platform.docsSite` C4 container + a deploy edge | model accuracy | The docs site was unmodelled before this change and the change does not make that silence false. Silence is not falsehood. Recorded in the C4 enumeration as checked-and-declined, and carried to the deferred issue. |
| A hand-held rollback patch file + a byte-identity rehearsal | P6 | `git revert` derives the same hunk mechanically and cannot drift; a held patch is a second source of truth for `dns.tf`. The byte-identity rehearsal tests `git apply`, not the rollback. Replaced by a rehearsal that tests the load-bearing premise instead (D3). |

**Cut for PR4/PR5 (2026-09-03).** Each was proposed by the resume brief's own framing or by
the obvious reading of D4, and each is removed here rather than researched, designed or
reviewed.

| Mechanism proposed | Property | Why it is cut |
|---|---|---|
| A dedicated `apply_target=docs-apex-cutover` **dispatch job**, mirroring `workspaces-luks-recut` shape-for-shape | P10 | It buys P10 and **destroys P11**. To stop the merge from doing the concurrent apply, the three record addresses would have to leave the push allow-list — at which point the *revert* merge is inert too, and D3's one-merge rollback becomes a second dispatch under incident. D3 item 2 already establishes that a dispatch cannot carry `[ack-destroy]`. The template is still followed; only its *trigger* differs. See D5 |
| `depends_on` between the deletes and the create | P10 | Already refuted in D4 and re-verified: `depends_on` cannot reference a resource that has left the configuration. Recorded so it is not re-proposed |
| `create_before_destroy` on `cloudflare_record.pages_apex` | P10 | Inverts the hazard rather than removing it — creating the CNAME first is the shape Cloudflare rejects with `81053`. The correct order is destroy-first, which is what the provider does *not* guarantee across unrelated nodes |
| Shrinking the recordless window with a lower TTL | P10 | Proxied records are fixed at 300 s and the window is negative-cached against the **SOA minimum (1800 s)**, not the record TTL. There is no TTL to lower on the failure path |
| A path-filter or commit-message predicate to decide "is this the cutover merge?" | P10 | A predicate over the *diff* is a chokepoint outside the mechanism it guards — the R7/R10 class this plan already rejected once. The predicate is taken from the **plan document itself**, so it is structurally impossible for a cutover to reach the apply without passing through it |
| A held rollback `dns.tf` patch, pre-committed on a branch, to satisfy PF8 before the merge | P6, P11 | Same reason the original Cut List rejected a held patch: it is a second source of truth for `dns.tf`. PF8′ derives the revert with `git revert` from the merge commit, which cannot drift |
| A new ADR for the two-pass ordering | model accuracy | The decision lives inside ADR-194's scope and is an **amendment** to it, not a new record. A new ordinal is also the collision surface this repo has been bitten by three times; amending costs none |
| **The whole two-pass merge-path pre-pass** (a scoped plan + a plan-JSON shape gate + a destroy pass + a between-assert + a create pass, inserted into the push `apply` job) | P10 | **Cut on measurement, after being designed in full.** Three findings each disqualify it independently. (a) `git revert` of the cutover PR **deletes the pre-pass steps along with the DNS hunk**, because `on: push` runs the workflow file from the merged ref — so the rollback would run unordered anyway, and a rollback mechanism the rollback itself removes is not a mechanism. (b) Its three-verdict gate **refuses both the forward completion AND the rollback** of a half-converged state: after pass 1 the re-plan is `0 deletes, 1 create` (not FORWARD, not NOOP) and the revert is `4 creates, 0 deletes` (not REVERSE) — so the gate blocks recovery in the only state where recovery matters, while the apex is NXDOMAIN. (c) `-target` is transitive, so `content = cloudflare_pages_project.docs.subdomain` pulls the Pages project into the scoped plan; the gate's own out-of-scope rule then **aborts every ordinary infra merge**, and relaxing it lets an unguarded project diff apply mid-cutover. Replaced by making the transition one resource address (D5). |
| A dedicated `apply_target=docs-apex-cutover` **dispatch job** | P10 | Buys the ordering and **destroys P11**: to stop the merge doing the concurrent apply the three addresses must leave the push allow-list, at which point the revert merge is inert too. Also `github.event.head_commit` is absent on a dispatch run, so the merge-shaped `[ack-destroy]` cannot be evaluated. (Recorded honestly: the repo's dispatch template uses a typed `confirm` input, which is a *stronger* ack — the row that decides this is P11, not the ack.) |
| `git revert` as the rollback for the flip | P6, P11 | **Measured false.** It drops the `moved` block that supplies the atomicity, yielding two unrelated addresses (`1 to add, 0 to change, 1 to destroy` across `github_pages[…]` and `pages_apex`) dispatched concurrently — the reverse-direction `81053`, on an apex that is already broken. Replaced by a scripted reverse-`moved` generator, which stays mechanical rather than becoming a second source of truth. |

### Measured empirical baseline (2026-08-20, `curl -sSI`)

| Header | `https://soleur.ai/` (GH Pages) | `/css/style.css` | Cloudflare Pages default | Verdict |
|---|---|---|---|---|
| `access-control-allow-origin` | `*` | `*` | `*` | preserved |
| `x-content-type-options` | `nosniff` | `nosniff` | `nosniff` | preserved (also zone-set) |
| `strict-transport-security` | `max-age=63072000; includeSubDomains; preload` | — | zone setting, not Pages | preserved — `cloudflare_zone_settings_override` is untouched |
| `referrer-policy` | absent | absent | `strict-origin-when-cross-origin` | added by Pages; improvement |
| `cache-control` (HTML) | `max-age=600` | — | `public, max-age=0, must-revalidate` | **deliberate change** (Cut List) |
| `cache-control` (assets) | — | `max-age=14400` | `public, max-age=0, must-revalidate` | **deliberate change** — faster deploy propagation on non-hashed filenames |
| `x-github-request-id`, `via: 1.1 varnish`, `x-fastly-request-id`, `x-served-by`, `x-proxy-cache` | present | present | absent | the cutover discriminator (CUT2) |

Apex mail/verification baseline, captured for P8 (`dig +short soleur.ai MX` / `TXT`):

```
MX:  10 mail.protonmail.ch.   20 mailsec.protonmail.ch.
TXT: "v=spf1 include:_spf.protonmail.ch ~all"
     "protonmail-verification=669dab6390579ccb6db592dca20dbd199bacce2d"
     "google-site-verification=zbo0JKaBz4mZwUq9sv_gXtmw5RmiN6dw_O8bqK2nq6s"
     "google-site-verification=HiasMKe0J0IzSe3nX2Ers0pYMAJ2vRvj6BxKEjJ1szk"
```

Note: two `google-site-verification` TXT values are live; `dns.tf` declares one. Pre-existing
drift, out of scope, recorded so the P8 comparison is not misread as caused by this change.

### Verified schemas — `cloudflare/cloudflare 4.52.7`

```
cloudflare_pages_project
  account_id         required
  name               required
  production_branch  required          <- required EVEN for direct upload
  subdomain          computed          <- "<name>.pages.dev"
  domains, created_on computed
  optional max-1 blocks: build_config, deployment_configs, source

cloudflare_pages_domain
  account_id, project_name, domain  required
  status                            computed

cloudflare_list -> item { value { redirect { … } } }
  source_url, target_url           required
  status_code, include_subdomains  optional
  subpath_matching                 optional   <- present at this pin
  preserve_path_suffix             optional   <- present at this pin
  preserve_query_string            optional

cloudflare_record
  name, type, zone_id  required
  content / value      optional+computed   (this repo uses `content`)
  proxied, ttl         optional
```

For a direct-upload project, omit the `source` block (it is the git integration) and still
set `production_branch = "main"`.

### Verified quotas (Cloudflare availability table)

- Single Redirects (zone `http_request_dynamic_redirect`): **Free = 10 rules per zone.** Confirms the cap.
- Bulk Redirects (account): **Free = 15 rules, 5 lists, 10,000 URL redirects across lists.**
  The repo uses 1 list (12 items) and 1 rule — ample headroom for a second list and a second rule.

### Verified Bulk Redirect parameter semantics

`subpath_matching` + `preserve_path_suffix` on source `www.soleur.ai/` → a request to
`www.soleur.ai/item` redirects to the target with `/item` appended. Scheme may be omitted,
in which case the redirect applies to both `http` and `https`. `include_subdomains` would
extend the match to hosts *left of* `www.soleur.ai` and is **not** wanted here.
**Matching precedence between two entries that could both match is undocumented** — which
is why D1 uses a separate list plus explicit rule ordering rather than relying on it.

### Verified CLI form — `wrangler pages deploy` (measured 2026-08-20)

```
$ npx --yes wrangler@latest pages deploy --help
wrangler pages deploy [directory]
POSITIONALS  directory
OPTIONS      --project-name --branch --commit-hash --commit-message --commit-dirty
             --skip-caching --no-bundle --upload-source-maps
```

Published version at measurement time: `wrangler 4.124.0`. Auth via `CLOUDFLARE_API_TOKEN`
+ `CLOUDFLARE_ACCOUNT_ID`; permission **Account → Cloudflare Pages → Edit**.

<!-- verified: 2026-08-20 source: npx --yes wrangler@latest pages deploy --help -->

### Applicable institutional learnings and principles

| Source | Takeaway | Why it binds |
|---|---|---|
| ADR-130 | Same API family → widen; distinct API surface → mint narrow. Zone→account escalation must be stated. | The Pages token decision |
| ADR-136 | A `kind = "zone"`/`"root"` ruleset owns its phase entrypoint as a whole-list replacement | No new phase is introduced; the account `http_request_redirect` entrypoint is already Terraform-owned, so the create-from-absent discriminator does not match |
| AP-019 (principles register) | The cert-reissue routine's off-Terraform mutation is sanctioned **because** it is "transient, self-reverting, single-attempt, human-gated" | The self-reverting clause becomes provably false post-cutover — D2 |
| AP-021 (CI-enforced) | A verdict must never collapse "could not check" into a definite answer | The origin-provenance probe must emit a third `UNREACHABLE` verdict |
| AP-023 (CI-enforced) | An anti-vacuity floor reports with `printf >&2` + `exit 1`, and the case counter increments **at the call site**, never inside both verdict helpers | The guard being rewritten has exactly the banned shape today |
| `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` | Never `name = "@"` at the apex | The apex CNAME |
| `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` | v4 block syntax; registry `latest` shows v5 | All new HCL |
| `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` | A `-target=` allow-list is asserted on by several artifacts | Applied — but see R9: the two suites first assumed cannot see these resource types |
| `domains.md` §HSTS Preload Commitment | New Terraform records must be `proxied = true` | Both new records are proxied |

### CI-verification gate (#2566)

Every prescribed CLI invocation is verified: `wrangler pages deploy` by live `--help`;
the provider schemas by `terraform providers schema -json` at the pin; the header and DNS
baselines by live `curl`/`dig`; the origin-provenance probe by execution across all four
arms (below). No invocation is carried from memory.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| **R1.** "Retiring the ACME carve-out frees exactly the rule the www redirect needs." | The carve-out is an inline `and not (…)` clause **inside Rule 10's expression**. Retiring it frees zero rules. Only deleting Rule 10 frees a slot, which requires re-enabling zone `always_use_https` — the deferred cleanup. | D1 rebuilds the 301 outside that ruleset. ADR-194 is amended to correct its own reasoning. |
| **R2.** `dns.tf`: "There is no `cloudflare_page_rule` / `cloudflare_list` / `http_request_redirect` resource anywhere in this repo." | **Stale since 2026-06-09.** `seo-bulk-redirects.tf` declares `cloudflare_list.legal_redirects` (12 items, 10 of them legacy legal paths) and `cloudflare_ruleset.bulk_redirects` (`kind = "root"`, `http_request_redirect`, account-scoped). | The comment is rewritten to enumerate **all three** redirect substrates and which is authoritative for what — a comment naming one substrate rots the same way this one did. |
| **R5.** `sentry_uptime_monitor.soleur_www` keeps working unchanged. | Confirmed — asserts `301` on a URL that does not move. `soleur_acme_probe` also still holds (Pages serves `404.html` at 404), but it becomes **vacuous**, not merely misdescribed: its stated property is "ACME carve-out regression detector" for Rule 10, and today the 404 comes from a passthrough to the GitHub Pages origin. Post-cutover the 404 comes from Cloudflare Pages' own `404.html` regardless of Rule 10's state, so the assertion is a permanent pass with zero coupling to the thing it guards — while Rule 10 and its carve-out are explicitly retained in scope. | Monitors unedited; the `soleur_acme_probe` description is corrected (comment-only), and **the loss of its property is recorded against the deferred-cleanup issue** — a guard losing its property is a different finding from a stale description. |
| **R6.** The DNS change is destructive. | > **Superseded 2026-09-03 (D5).** This row describes the pre-D5 single-merge shape — *"4 deletes + 1 create, plus an in-place update of www; PR3 carries the ack"* — and both the counts and the PR are wrong now. The cutover is two merges: **PR4a** plans 3 deletes / 0 creates (`destroy_count = 3`) and **PR4b** plans one delete+create at ONE address (`resource_deletes = 1`). `name`/`type` are still ForceNew, and `destroy_count > 0` still fails the apply without `[ack-destroy]` — which **PR4a and PR4b each carry**, not PR3. | PF9a / PF9b; each destructive merge carries its own ack. |
| **R7.** "`_redirects` can host the www→apex 301." | **False, three ways.** (a) Cloudflare documents "Domain-level redirects" as *unsupported*, citing the exact shape. (b) The repo's own canonical-host build gate greps `_site/` recursively for `https://www\.soleur\.ai($\|[^a-zA-Z0-9.-])` — the `_redirects` line matches, failing every build. (c) A hostless source would match the apex too and loop. | Option A is removed entirely, not held as a fallback. D1 selects Bulk Redirects. |
| **R8.** "`cloudflare_pages_domain` manages no DNS." | The claim is **true for the Terraform path**, but an earlier draft proved it from the *provider schema* — a schema exposing no DNS attribute shows the resource has no DNS field, not that the API has no side effect. The correct citation is the provider documentation at the pin: *"A DNS record for the domain is not automatically created. You need to create a `cloudflare_record` resource for the domain you want to use."* The **dashboard** flow does auto-create (*"the CNAME record will be added automatically after you confirm your DNS record"*), so the two paths genuinely differ. | Claim retained, citation corrected to the provider docs. PF3 keeps a cheap confirmation probe — had the claim been false, the failure would have arrived as error `81053` from a direction nobody was watching. |
| **R9.** "`terraform-target-parity.test.ts` and `test-destroy-guard-counter-web-platform.sh` are the orphan suites to sweep." | Neither can see a `cloudflare_pages_*` resource. The parity test's predicate is a `terraform_data` resource with **both** an SSH `connection` block and a `provisioner` block, and it self-documents as one-directional. The destroy-guard counter's five nested-block clauses cover other `cloudflare_*` types; Pages resources have no nested-block surface. | AC14 becomes a **direct grep** of the `-target=` lines. Delegating to suites that structurally cannot see the resources would have passed vacuously. |
| **R10.** The canonicalizer guard's CI registration. | Found: `.github/workflows/infra-validation.yml`, step `Run www-apex-canonicalizer drift-guard`, in `deploy-script-tests` (no `needs:`, no `if:`). Its `pull_request: paths` includes `apps/*/infra/**`. | Under D1 every rewritten assertion lives under `apps/web-platform/infra/**`, so the guard's trigger already covers them. Had the `_redirects` design survived, the chokepoint assertion would have sat in `eleventy.config.js`, outside the filter — the guard would have passed by never running. A fourth reason Option A was wrong. |

## Open Code-Review Overlap

Checked 2026-08-20 against 64 open `code-review` issues, matching every path in
`## Files to Edit` / `## Files to Create`. **None.**

## User-Brand Impact

- **Brand-survival threshold:** `single-user incident` — one prospective user meeting a dark
  or wrong `soleur.ai` is brand-fatal, and the apex is HSTS-preloaded so it cannot fall back
  to HTTP. Mirrors the `brand_survival_threshold` frontmatter field; stated here too because
  a reader of this section should not have to scroll to the frontmatter to learn it.

**If this lands broken, the user experiences:** `https://soleur.ai` serving a Cloudflare
error page, a Pages "no deployment" page, a stale build, or NXDOMAIN — the public
marketing and documentation site, the only surface a prospective user meets before signing
up, dark or wrong. The 2026-08-16 precedent (#6691) was an ~8h15m apex outage from the same
host. Because `soleur.ai` is HSTS-preloaded, a broken apex cannot even fall back to HTTP.

**Named precisely for PR4 (2026-09-03), now that Hypothesis Z is measured FALSE:** the NXDOMAIN
arm above is not hypothetical and is not merely a race. The transition passes through a state
where `soleur.ai` carries no address record, and a resolver that queries inside it
negative-caches the answer against the zone SOA minimum of **1800 s** — so a visitor can meet a
dark apex for up to half an hour *after* the record exists, with no HTTP fallback available to
them. Bounding that window to two API calls is the entire purpose of D5, and the reason the
ordering is a blocker rather than a refinement.

**A second, quieter blast radius:** the apex also carries the company's Protonmail `MX` and
four `TXT` records. The A→CNAME transition touches that name. A silent mail break would be
invisible to every uptime monitor. P8/CUT9 exist for this.

**If this leaks, the user's workflow is exposed via:** a Cloudflare API token scoped to
`Account → Cloudflare Pages → Edit` reaching CI. That token is a **site-content replacement
primitive** — whoever holds it can publish arbitrary content at `soleur.ai` under the real
domain and the real certificate. It is minted narrow (Pages only; no DNS, no rulesets, no
zone settings), never echoed, and reaches the workflow auto-masked. `deploy-docs.yml`
triggers on `push: [main]`, `workflow_run` and `workflow_dispatch` — **no `pull_request`**,
so there is no fork exposure. That absence is load-bearing and is recorded in the scope
ledger so a later author does not add one.

**Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true`. CPO sign-off is required at plan time before `/work` begins —
carried by the Phase 2.5 assessment. `user-impact-reviewer` is invoked at review time.

## Design Decision D1 — where the www→apex 301 lives

The ARGUMENTS asked whether the www redirect can be added within the Free cap **without**
retiring the ACME carve-out. **It can — but not inside `seo_page_redirects`.**

**Why not there:** the ruleset holds exactly 10 rules (9 SEO 301s + Rule 10, the HTTPS
catch-all) against a documented Free cap of 10 for `http_request_dynamic_redirect`, and
Cloudflare permits one user-defined ruleset per `(zone, phase)`. Rule 10 upgrades **every
proxied host in the zone** to HTTPS, protecting cross-subdomain credentials on
`app.soleur.ai` and `deploy.soleur.ai` (caught by `user-impact-reviewer` in PR #3974); it
cannot be evicted. Consolidating rules 1-8 needs `regex_replace()` / `substring()`, which
are Business-tier. And the carve-out is not a rule, so retiring it frees nothing (R1).

**Chosen: Cloudflare Bulk Redirects**, which is also what Cloudflare's own www-redirect
guide prescribes for a Pages project. It is a separate product on a different phase
(`http_request_redirect`, account-level) with its own quota, already wired in this repo,
with the token scope already granted post-#5092.

**The www DNS shape — a deliberate divergence from Cloudflare's own recipe.** Cloudflare's
guide points www at `192.0.2.1` (RFC 5737 TEST-NET-1, a black hole) and leaves it off the
Pages project, so the Bulk Redirect is the only thing that can answer. This plan instead
**keeps `www.soleur.ai` attached to the Pages project as a second custom domain**, with the
Bulk Redirect in front of it. Cloudflare documents the precedence that makes this work:
*"In case of duplicates, Bulk Redirects will run in front of your Pages project."*

The two designs differ only in their **failure mode**, and that is the whole reason for the
divergence:

| If the redirect ever stops firing | `192.0.2.1` (CF's recipe) | attached to the project (chosen) |
|---|---|---|
| What www serves | Cloudflare 522 — a hard, user-visible edge error | the site itself — duplicate content |
| Detection | `sentry_uptime_monitor.soleur_www` (asserts `301`) | the same monitor, equally |
| Severity | a broken host on an HSTS-preloaded domain | an SEO annoyance for one monitor interval |

Both are caught by the same monitor within one confirmation period, so detection is a wash —
and a 522 is strictly worse for a visitor than a second copy of the page. The
duplicate-content risk is also already covered a second time by the canonical-host build gate
and by the apex `<link rel="canonical">` the site emits.

Consequences of the chosen shape: `www` stays a proxied `CNAME` (so the change is an
**in-place update**, not a replace — this matters for the plan-shape assertion), it satisfies
the `domains.md` HSTS mandate, and Universal SSL's one-label wildcard `*.soleur.ai` covers it.

**Implementation — a separate list and a second, explicitly ordered rule:**

```hcl
resource "cloudflare_list" "www_canonical" {
  provider   = cloudflare.rulesets
  account_id = var.cf_account_id
  name       = "www_canonical"
  kind       = "redirect"
  item {
    value {
      redirect {
        source_url            = "www.soleur.ai/"   # scheme omitted -> matches http AND https
        target_url            = "https://soleur.ai/"
        status_code           = 301
        subpath_matching      = "enabled"
        preserve_path_suffix  = "enabled"
        preserve_query_string = "enabled"
        include_subdomains    = "disabled"  # would match hosts LEFT of www.soleur.ai; not wanted
      }
    }
  }
}
```

plus a **second** `rules { }` block in `cloudflare_ruleset.bulk_redirects`, declared
**after** the existing `legal_redirects` rule.

**Why a separate list rather than a 13th item in `legal_redirects`:** Cloudflare does not
document matching precedence between two list entries that could both match, and every
existing item carries `include_subdomains = "enabled"` — so `www.soleur.ai/pages/legal/
privacy-policy.html` already matches an apex item today. Adding a www catch-all to the same
list would make which entry wins depend on undocumented behaviour. Rules **within a
ruleset** evaluate in declaration order with first-match-wins, which this repo already
relies on and documents (`seo-rulesets.tf`: *"Positioned LAST so specific path rules above
match first and avoid double-redirect chains"*). Ordering the legal rule first and the www
rule second makes precedence explicit and testable. Free-tier headroom is ample (15 rules,
5 lists).

**T-WWW is a blocking pre-cutover check:** the ten legacy `/pages/legal/<slug>.html` paths
requested **on the www host** must still `301` to their `/legal/<slug>/` targets and not
collapse to the bare apex.

**Rejected: `_redirects` in the build artifact.** Cloudflare documents domain-level
redirects as unsupported and cites this exact shape; the repo's canonical-host build gate
would reject the file's contents on every build; and the guard's chokepoint assertion would
have landed in `eleventy.config.js`, outside `infra-validation.yml`'s path filter (R7, R10).

**What is NOT touched:** Rule 10, its ACME carve-out clause, `always_use_https = "off"`,
and `ssl = "full"`.

## Design Decision D2 — disarming the cert-reissue routine (promoted into scope)

Deleting the certificate-reissue subsystem is deferred. **Leaving it armed is not the same
decision**, and the hazard is created by this work, so it must be closed by this work.

**The mechanism, read from the source:**

- `cron-gh-pages-cert-reissue.ts` registers on `[{ event: "cron/gh-pages-cert-reissue.manual-trigger" }]`
  — event-only, reachable through the allowlisted `POST /api/internal/trigger-cron`.
- `cron-gh-pages-cert-state.ts` registers on `{ cron: "0 3 * * *" }` — **a live daily
  schedule**. Post-cutover the GitHub Pages certificate can never recover (it is
  DNS-detached by design), so it stays wedged permanently and this job files a `[cert-poll]`
  issue **every day, forever**, whose body reads *"cert wedged … ACME cannot self-heal this
  state; fire `cron/gh-pages-cert-reissue.manual-trigger`"*. It hands an autonomous agent a
  daily, authoritative instruction to run the routine below. Likelihood is not "low" — it is
  the retained system's designed steady-state output.

> **MEASURED 2026-08-20, not predicted.** The origin certificate for `soleur.ai`
> already EXPIRED — `notAfter=Aug 16 13:53:34 2026 GMT`, verified against
> `185.199.108.153` with SNI `soleur.ai` — and `gh api repos/jikig-ai/soleur/pages`
> reports `https_certificate.state = "bad_authz"` with `is_https_eligible: false`,
> i.e. wedged in the state that cannot self-heal. `[cert-poll]` issue **#6691** has
> been OPEN since 2026-07-19 with **35 comments**, last written **2026-08-20T03:00:27Z**.
>
> So the self-escalating daily loop is not a post-cutover forecast this PR pre-empts —
> it is 33 days old and ran this morning. And `certEscalation`'s `CERT_WARN_DAYS = 21`
> / `CERT_CRITICAL_DAYS = 7` are both long since crossed (`daysUntilExpiry = -4`), so
> disarming forfeits NO future warning: the watcher has nothing left to warn about.
>
> `curl -sSI https://soleur.ai/` returns **200** solely because the `ssl = "full"`
> Configuration Rule (commit `0b4a446fc`, "restore soleur.ai (apex 526)") is masking a
> dead origin certificate. That rule is not a constraint we merely tolerate — it is
> currently the single point of failure keeping the site reachable, which raises the
> urgency of PR2-PR4 rather than arguing for keeping a dead watcher armed.
- Every precondition passes post-cutover: `assertStuckState` accepts `bad_authz`, and
  `checkReissuePreconditions` requires the ACME apex path to return `404`, which Cloudflare
  Pages does.
- `resolveProbeOnly` defaults to `true`, but **probe-only still performs the DNS flip** —
  `setRecordsProxied(deps, records, false)` runs unconditionally; only the cname toggle is skipped.
- `listToggleRecords()` queries exactly `[apex, "A"]` and `[www, "CNAME"]`. Post-cutover the
  apex is a CNAME, so the `type=A` query returns nothing — **the apex is untouched**, and
  the plan's original fear was misdirected. The **www** record is what gets `proxied = false`,
  dropping HSTS, Rule 10's HTTPS upgrade, WAF and bot management on a host `domains.md`
  mandates be proxied.
- **It cannot undo this.** `restoreStateInner` opens with
  `if (records.length < EXPECTED_TOGGLE_RECORDS)` where `EXPECTED_TOGGLE_RECORDS = 5`
  (4 apex A + 1 www CNAME). Post-cutover the read returns fewer, so it throws *"refusing to
  restore a subset"*, `retries: 1` exhausts, `onFailure` calls the same restore and throws
  again, and it pages `proxy_restore_failed`. The routine's own fail-loud safety guarantee is
  what makes the de-proxying **one-way**.

**In-scope deliverable (additive; no deletion):**

1. Add a **topology precondition** to `checkReissuePreconditions` that reads the live apex
   record type and returns a non-benign terminal outcome unless it is `A`. The routine then
   refuses to run against the post-cutover topology instead of half-running against it.
2. Disable the `cron` trigger on `cron-gh-pages-cert-state`, retaining its manual-trigger
   arm. This closes the self-escalating daily loop.
3. Record in the principles register that **AP-019's justification is void** until (1) lands:
   the "self-reverting to the Terraform-declared steady state" clause is provably false
   post-cutover.

4. Set `enabled = false` on `sentry_cron_monitor.scheduled_gh_pages_cert_state` in
   `apps/web-platform/infra/sentry/cron-monitors.tf`. Disarming the Inngest schedule (item 2)
   RELOCATES the daily-noise loop rather than closing it: that monitor carries
   `checkin_margin_minutes = 240` and `failure_issue_threshold = 1`, so with no check-ins it
   opens a missed-check-in issue every day from PR1's merge. `enabled = false` is an in-place
   update on the pinned provider (`jianyuan/sentry 0.15.4` exposes `enabled`, bool,
   optional+computed) — **0 destroys, so no `[ack-destroy]`, and the resource, its schedule and
   its margins stay in config as the re-arm recipe.** Deleting the block was considered and
   rejected: it spends the cutover PR's destroy gate on the substrate PR, breaks the code->IaC
   parity guard while the handler's manual-trigger arm still heartbeats, and makes re-arming a
   resource re-creation instead of the inverse of one boolean.

This is a phase step with files and acceptance criteria (AC25-AC27, AC27a-AC27e), not a
risk-table note.

## Design Decision D3 — rollback

Rollback is a revert of the **PR4** commit — one hunk, one file — merged with
`[ack-destroy]`. (**Corrected 2026-09-03:** this read "PR3" under the superseded
three-PR numbering. PR3 is now the `cloudflare_pages_domain` attach, and reverting it
is NOT the DNS rollback — pointing an operator at it mid-incident sends them to the
wrong lever, with no CI failure to catch the mistake. The cutover runbook's table is
authoritative.) Three things make that real rather than aspirational:

1. **The revert PR is opened, green and mergeable *before* PR3 merges.** Under a
   `single-user incident` threshold the dominant cost is not authoring the revert, it is
   waiting out required CI on the revert PR. Pre-opening moves that wait from during the
   incident to before it, and rollback becomes one merge.
2. **`workflow_dispatch` cannot perform this rollback.** The destroy gate reads
   `HEAD_MSG: ${{ github.event.head_commit.message }}`; on a dispatch run
   `github.event.head_commit` is absent, `HEAD_MSG` is empty, and the
   `[ack-destroy]` regex cannot match. The reverting apply always has `destroy_count > 0`
   (it destroys the apex CNAME), so the documented manual escape hatch structurally cannot
   execute it. The merge path is the **only** path, and the runbook says so.
3. **The rehearsal tests the premise, not the patch.** Asserting that a reverse diff
   reproduces the original file tests `git`. The load-bearing, genuinely unverified claims
   are: (a) GitHub Pages **still serves** `soleur.ai` after being DNS-detached — nothing
   re-asserts the `CNAME` file to GitHub Pages after `deploy-docs.yml` stops deploying
   there, so the self-healing mechanism is gone; (b) a DNS-only revert is **sufficient** —
   `cloudflare_pages_domain.apex` remains attached to `soleur.ai` on the same account, and
   Pages custom-domain attachment establishes edge routing for that hostname, so the revert
   may also require destroying that resource. **(b) is measured in PR2 against a scratch
   custom domain on the same project, before the cutover** — it is the one item that could
   otherwise require re-derivation under pressure.

> **Superseded 2026-09-02 (PR2, #7640) — item 3(b) is retired by construction, and PF7
> was not run.** The body above is left intact as the record of what was believed when it
> was written. The four-PR amendment in *Delivery Sequencing* moved the custom-domain
> attachment into PR3 and the record swap into PR4, so each origin-selecting mechanism now
> lives in its own revert. The rollback procedure is therefore correct without knowing in
> advance which of the two selects the origin: revert PR4, run
> `apps/web-platform/infra/apex-origin-probe.sh`, and revert PR3 as well if it still
> reports `SERVING-FROM-CLOUDFLARE-PAGES`. Measuring 3(b) would have meant attaching and
> detaching a hostname on the live production zone to answer a question the sequencing had
> already made moot, so the probe was deliberately skipped rather than silently dropped.
> The procedure that replaces it is written into
> `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`.

**Rollback content freezes.** GitHub Pages will serve the last pre-cutover build. A rollback
three weeks later serves three-week-old docs. Acceptable for an availability rollback;
stated so nobody is surprised.

**The rollback window depends on the deferred cleanup staying deferred** — specifically on
`ssl = "full"` remaining in place, because the GitHub Pages origin certificate is expired by
construction. This is added to the deferred issue's re-evaluation criteria.

## Design Decision D4 — ordering the apex swap (the gap, not the swap)

The apex transition is **not** a swap. `cloudflare_record.github_pages[*]` leaves the config
and `cloudflare_record.pages_apex` enters it. Those are unrelated graph nodes: no dependency
edge exists between them, and `depends_on` **cannot** create one, because it cannot reference
a resource that is no longer in the configuration. Terraform therefore dispatches the four
deletes and the one create **concurrently** at default parallelism. Two consequences, both
missing from an earlier draft of this plan:

1. **The create can lose the race and hard-fail the apply.** Cloudflare rejects a CNAME at a
   name that still carries `A` records — `An A, AAAA or CNAME record already exists with that
   host. (Code: 81053)`, HTTP 400. If the create is dispatched before all four deletes land,
   the apply dies mid-flight on the live public apex. A plan-*shape* assertion (PF9) cannot
   catch this: shape is not order.
2. **Between the last delete and the create, the apex carries no address record at all.** This
   is a gap, not a swap. Resolvers querying in that window get NODATA/NXDOMAIN and
   **negative-cache it against the zone SOA minimum (1800 s)** — an order of magnitude longer
   than the 300 s positive TTL a proxied record uses, and a harder user-visible failure than
   stale-but-working. "Both origins serve the same content during propagation" is only true
   for resolvers that never observe the gap.

**Chosen: a two-pass targeted apply inside one workflow run** — a destroy pass
(`-target=cloudflare_record.github_pages`) followed by a create pass
(`-target=cloudflare_record.pages_apex`). This bounds the recordless window to the latency of
two API calls rather than to Terraform's scheduler, and it is IaC-native: the repo already
carries this shape in `apply-web-platform-infra.yml`'s dedicated `apply_target=` dispatch jobs,
with a `confirm` typo-guard and an id-pin (the `workspaces-luks-recut` / `registry-luks-recut`
jobs are the template).

**`-target=cloudflare_record.github_pages` must be RETAINED in the allow-list, not removed.**
The instinct once the block leaves config is to delete the line as dead. Doing so means the
destroy is never planned: the four `A` records stay live and in state, and every subsequent
create attempt hits 81053 forever. Both the old and the new address must be present during
the cutover apply.

**PF-ORDER** is added to the pre-flight set: the cutover job asserts the destroy pass completed
(the four records are gone from state) **before** the create pass is dispatched.

> **D4 addendum, 2026-09-03 (PR4) — the hazard is SYMMETRIC, and the earlier draft only saw
> one half of it.** Everything above reasons about the forward direction: four `A` deletes,
> one `CNAME` create. The **reverse** direction — which is the rollback, the one act that
> runs while the site is already broken — has the identical shape mirrored: one `CNAME`
> delete and four `A` creates, again unrelated graph nodes, again dispatched concurrently,
> and Cloudflare rejects an `A` at a name that still carries a `CNAME` for the same reason
> it rejects the converse. D3 promised *"rollback is one merge"* and, as configured, that
> merge is a coin flip between a clean restore and `81053` **on an apex that is already
> failing**. The ordering mechanism is therefore not a cutover convenience — it is the
> thing that makes the rollback real, and it must be **direction-aware**: destroy pass
> first in both directions, whichever record is leaving.
>
> **Resolved 2026-09-03 by D5, and the resolution is not the one this addendum expected.**
> Making the transition a single resource address means Terraform core orders **both**
> directions for free — there is no "destroy pass" to sequence, in either direction. The
> addendum's finding stands and was load-bearing: it is what ruled out every mechanism that
> ordered only the forward direction. What changed is that the answer turned out to be
> removing the second address rather than sequencing two of them.

## Design Decision D5 — the apex transition is ONE resource, ordered by Terraform core

**This is PR4's one hard blocker.** D4 chose a two-pass apply and AC29 asserted it; **AC29 was
filed under `### PR1` and never delivered**. Verified on this branch's base:
`apply-web-platform-infra.yml`'s push-triggered `apply` job runs **one**
`terraform plan -out=tfplan` whose `-target=` allow-list already contains
`cloudflare_record.github_pages`, `cloudflare_record.www` **and** `cloudflare_record.pages_apex`
(PR1 added the last one). So merging the cutover as-is dispatches four deletes and one create
concurrently — exactly the state D4 was written to prevent.

**The decision: stop making it two resources.** The hazard exists *only* because the four `A`
records and the new `CNAME` are different resource addresses, with no dependency edge and no way
to create one. Collapse the transition onto a **single address** and Terraform core serialises
Delete→Create inside one graph node, for free, with no bespoke machinery at all.

### The shape — two ordinary merges through the UNCHANGED apply path

| | Change | Measured plan | Ack |
|---|---|---|---|
| **PR4a — shrink** | `cloudflare_record.github_pages`'s `for_each` goes from `toset([4 GitHub Pages IPs])` to `toset(["185.199.108.153"])` | 3 deletes, 0 creates | `[ack-destroy]` (destroy_count = 3) |
| **PR4b — flip** | a `moved` block re-addressing the survivor to `cloudflare_record.pages_apex`, plus `type` `A`→`CNAME` and the `content` change on that one address; plus `www`'s in-place `content` update | **1 to add, 0 to change, 1 to destroy** at the single address `cloudflare_record.pages_apex`, actions `["delete","create"]` | `[ack-destroy]` (destroy_count = 1) |

PR4a is order-irrelevant: three pure deletes with no create to race, and the apex never stops
resolving. PR4b is a **single-node replace**, so core orders it and the recordless window is one
provider API round-trip — not a runner-step boundary, and far tighter than the plan+apply cycle
the rejected pre-pass would have inserted.

**Both merges must be separate.** Folding the shrink into the flip does not work: the three
remaining deletes would be unrelated nodes racing `pages_apex`'s create, so the `CNAME` create
could still be dispatched while `A` records survive at `soleur.ai`. The split is required, not
stylistic.

### Measured, not reasoned (2026-09-03, provider 4.52.7 / Terraform 1.10.5)

Probed on a scratch root with a `filesystem_mirror` onto this repo's initialised provider
directory and hand-written state, `terraform plan -refresh=false`:

| Claim | Measurement |
|---|---|
| `type` is ForceNew | **CONFIRMED** — `~ type = "A" -> "CNAME" # forces replacement`; `Plan: 1 to add, 0 to change, 1 to destroy`. R6 asserted this and never probed it; it is now measured, and the caveat is deleted. |
| `moved` + a ForceNew change in one plan is clean at 1.10.5 | **CONFIRMED** — the move is applied to state first, the diff computed at the new address: `# cloudflare_record.pages_apex must be replaced` / `# (moved from cloudflare_record.github_pages["185.199.108.153"])`. One node, default lifecycle, core-serialised Delete→Create. |
| The plan grades as a 1-destroy through the REAL guard | **CONFIRMED** — `terraform show -json` piped through `tests/scripts/lib/destroy-guard-filter-web-platform.jq` gives `resource_deletes: 1, nested_deletes: 0, reboot_updates: 0, host_creates: 0`. |
| A died-mid-replace apply is recoverable with **zero** bespoke machinery | **CONFIRMED** — a bare create of `cloudflare_record.pages_apex` scores `resource_deletes 0`; the jq's five `nested_deletes` clauses cover `cloudflare_ruleset` / `_tunnel_cloudflared_config` / `_zone_settings_override` / `_notification_policy` / `_access_policy` and **not** `cloudflare_record`; `reboot_updates` and `host_creates` are both `select(.type == "hcloud_server")`; and the pre-apply entrypoint gate's own header states that of every `cloudflare_*` class in this root exactly one is IN scope — `cloudflare_ruleset`. So `destroy_count = 0`, no ack, the apply proceeds. **Re-running the failed job IS the recovery.** |

### Precedent diff — `moved` in this repo (deepen-plan Phase 4.4)

The `moved`-block pattern is **not novel here**, and the precedent is in this same Terraform
root: `apps/web-platform/infra/placement-group.tf:22-40` carries four `moved` blocks doing the
singleton ↔ `for_each`-key re-address, with the discipline stated in its own comment —
*"`moved` blocks re-address the EXISTING state … WITHOUT destroy/recreate … `terraform plan`
MUST show `0 to destroy` before apply. Keys are IMMUTABLE post-migration (never rename
`for_each` keys)."*

| | `placement-group.tf` precedent | This plan (PR4b) |
|---|---|---|
| Direction | singleton → `for_each["web-1"]` | `for_each["185.199.108.153"]` → singleton |
| Expected destroys | **0** — a pure re-address | **1** — the re-address is paired with a ForceNew `type` change, so the plan is a genuine replace |
| Key discipline | keys immutable post-migration | the `from` index is pinned to PR4a's surviving key and asserted (AC68), because a mismatch **no-ops silently** |

The divergence is deliberate and is the whole point: the precedent uses `moved` to avoid a
replace, and this plan uses it to **collapse a replace onto one address** so core will order it.
Same primitive, opposite intent — recorded so a reviewer reading the precedent does not flag the
non-zero destroy count as a violation of it.

### The targeting gotcha — and what it does to AC46

**MEASURED:** with only `-target=cloudflare_record.pages_apex`, Terraform **hard-errors**:

```
Error: Moved resource instances excluded by targeting
```

A `moved` block requires **both** endpoints in the `-target` set. The allow-list carries both
today, and re-running with `-target=cloudflare_record.pages_apex -target=cloudflare_record.github_pages`
plans cleanly. So **AC46's rationale is upgraded, not merely retained**: D4 said keeping
`-target=cloudflare_record.github_pages` matters because *"otherwise the destroy is never
planned"*. Under this design the consequence is sharper — **otherwise the apply ERRORS OUT**.
The line-anchored grep already in AC46 is the right guard for it; only the justification changes.

### The rollback is NOT `git revert` — and this is the finding that nearly shipped

Claim: *"revert PR4b and the reverse is the same single-node replace."* **MEASURED FALSE, and it
fails in the worst direction.** With state at `pages_apex` (CNAME) and config reverted to the
`github_pages` `for_each` **without a moved block**:

```
# cloudflare_record.github_pages["185.199.108.153"] will be created
# cloudflare_record.pages_apex will be destroyed
Plan: 1 to add, 0 to change, 1 to destroy
```

Two unrelated addresses, concurrent dispatch, an `A` arriving at a name that still carries a
`CNAME` — **the original `81053` hazard, reproduced on an apex that is already broken.**
`git revert` deletes the `moved` block along with everything else, and the atomicity *is* the
moved block, so the revert throws away exactly the property the rollback needs.

**Therefore PF8′ is a rollback-PR GENERATOR, not `git revert`.** The reverse PR must carry a
**reverse moved block** — `from = cloudflare_record.pages_apex`,
`to = cloudflare_record.github_pages["185.199.108.153"]` — plus the inverse `type`/`content`
flip. `git revert` cannot derive that. The generator is a scripted, unit-testable transformation
of PR4b's own diff (swap `from`/`to`, swap `type`/`content`), so it stays **mechanical** and does
not become the second source of truth for `dns.tf` that the Cut List rejected a held patch over.

**The runbook must say, in bold, that `git revert` is the WRONG lever for PR4b.** This is the
single most dangerous residual sharp edge in the whole migration: the obvious, muscle-memory
action reproduces the outage it is meant to fix.

### What this design costs, stated honestly

- It does **not** dissolve all machinery. It trades a plan-JSON shape gate, a mutation battery,
  a workflow-order guard and a between-assert for **one rollback-PR generator plus a small
  static guard**. That is materially less, and the rollback becomes atomic in **both**
  directions for the first time — but it is not zero.
- **A residual mid-replace window remains.** If the provider's Delete lands and the Create fails
  (token, 429/5xx, CNAME-at-apex validation), the apex is recordless. The window is now
  provider-internal rather than runner-step-wide, and recovery is the unacked bare create above.
  Acceptable, and the runbook carries the line.
- **Between PR4a and PR4b the apex has one `A` record instead of four.** All four are GitHub
  anycast and `185.199.108.153` is itself globally anycast, so the survivor is not a single
  machine; what is given up is Cloudflare's origin-level failover across the four when one is
  unreachable from a given colo. Keep the window inside one session. P2.

### Why the merge-path pre-pass was rejected

An earlier version of this decision inserted an ordered three-apply pre-pass, a plan-JSON shape
gate and a between-assert into the push `apply` job. It is recorded in the Cut List with the
measured reasons; the three that individually disqualified it were: a `moved`/`-target`-shaped
**scope contradiction** that would have aborted every ordinary infra merge; a gate that
**refuses both the completion and the rollback** of a half-converged state, i.e. it blocks
recovery in the only state where recovery matters; and the fact that **`git revert` would delete
the pre-pass steps themselves**, so the rollback would run unordered anyway. The last one is
fatal on its own and applies to any mechanism that lives in the same commit as the change it
orders.

## Downtime & Cutover

**Trigger.** The deploy/router class fires: the apex record swap takes the public serving
surface through a state where it has no address record. An earlier draft treated that window
as something to *bound* (D4's two-pass apply). This gate requires evaluating a **zero-downtime
path first**, and defaulting to it.

**The offline-inducing operation, precisely.** `cloudflare_record.github_pages[*]` (4 × `A`)
must be gone before `cloudflare_record.pages_apex` (`CNAME`) can exist — Cloudflare rejects a
CNAME at a name still carrying `A` records (error `81053`). Between the last delete and the
create, `soleur.ai` has no address record: resolvers get NODATA/NXDOMAIN and negative-cache it
against the zone SOA minimum (**1800 s**), six times the 300 s positive TTL a proxied record
uses. On an HSTS-preloaded domain there is no HTTP fallback. Affected surface: the public
marketing and documentation site, `single-user incident` threshold.

### Zero-downtime path — evaluated, and MEASURED FALSE (2026-09-03)

> **Hypothesis Z is FALSE. Measured, not argued.** PR3 attached **both** custom domains
> (`cloudflare_pages_domain.apex` and `.www`) and the post-apply `apex-origin-probe.sh` step
> returned **`SERVING-FROM-GITHUB-PAGES`**. Attachment alone does not move the origin; the
> DNS record is what selects it. Everything below is retained as the record of what was
> believed and of the experiment that settled it — the argument was reasonable and the
> measurement was cheap, which is the whole point of having run it.
>
> **Consequences, all of them live:**
> 1. The record swap **is** the cutover. PR4 is a genuine transition of the public serving
>    surface, not a cosmetic tidy-up, and it cannot be deferred.
> 2. **D4's hazard is live**, and D5 is the blocker that must ship with it.
> 3. The **residual-downtime path below is the plan of record**, not a fallback. Its three
>    stated conditions — a bounded window, the pre-opened revert, and CUT0-CUT9 gating
>    "done" — are now requirements rather than caveats.
> 4. The gate that forced the question still earned its place: it cost one probe to learn
>    that the outage is necessary, and the alternative was optimising an outage nobody had
>    asked whether they needed.
>
> **It is perishable.** Z was measured once, on 2026-09-03, against a live third-party edge.
> **PF-Z2 re-runs `apex-origin-probe.sh` immediately before PR4 merges.** If it has flipped
> to `SERVING-FROM-CLOUDFLARE-PAGES`, the apex is *already* on Pages and PR4's plan shape has
> changed underneath the operator's `[ack-destroy]` — stop and re-derive. `UNREACHABLE` is a
> third answer and blocks the merge; it is never read as either origin.

**Hypothesis Z (as written 2026-08-20, now falsified).** For a hostname attached to a Pages project as a custom domain, Cloudflare's
edge routes by **Host header to the project**, and the DNS record's *content* is not what
selects the origin — the record only has to exist and be **proxied** so the edge terminates the
request. Two documented behaviours point this way: Cloudflare warns that pointing a CNAME at a
Pages site *without* first attaching the custom domain yields a **522** (i.e. attachment is what
establishes routing, and its absence is what breaks it), and Bulk Redirects are documented to
run *"in front of your Pages project"* for an attached hostname.

If Z holds, the cutover is **zero-downtime by construction and the record swap is not the
cutover at all**:

1. PR1 attaches `soleur.ai` as a Pages custom domain while the four `A` records still point at
   GitHub Pages. The record stays proxied throughout; nothing is deleted.
2. The apex begins serving from Pages at the moment of attachment — verified by CUT0
   (`version.txt` equals the deployed SHA) and CUT2 (no GitHub-origin headers).
3. The `A`→`CNAME` change becomes **cosmetic tidy-up** — correcting the record to express what
   is already true — and can be scheduled independently of the cutover, or deferred entirely.
4. Rollback is *detaching the custom domain*, which is faster than a revert PR and does not
   touch DNS at all.

**PF-Z (blocking, measured in PR1, before PR3 is written).** Attach the apex custom domain and,
without changing any DNS record, measure: does `https://soleur.ai/version.txt` return the
deployed SHA, and do the GitHub-origin headers disappear? This is a **reversible** probe — detach
restores the prior state — and it is measured on the real hostname, so it settles Z rather than
arguing it. PF7's detach measurement is the same experiment run backwards and the two share one
result.

### Residual-downtime path — THE PLAN OF RECORD (Z falsified 2026-09-03)

Attachment alone does **not** move the origin, so the record swap is genuinely the cutover and
D4's two-pass targeted apply applies: destroy pass, **assert** the four records are gone from
both state and the live zone, create pass. That bounds the recordless window to the latency of
two API calls rather than to Terraform's scheduler. D5 says where that runs.

**This path is accepted only with, and all four are now requirements:** the bounded window
stated (target: under 5 s between passes, measured and printed to `$GITHUB_STEP_SUMMARY` by
the between-assert step so the claim is a reading rather than an aspiration); the cutover run
inside a declared maintenance window at a low-traffic hour; the revert PR open and green
before the decision point (**PF8′**); and the CUT0-CUT9 verification set gating "done".

**The window is bounded but not zero, and that is disclosed.** Between the destroy pass and
the create pass, resolvers that query `soleur.ai` get NODATA and negative-cache it against the
zone SOA minimum of **1800 s**. A visitor who resolves inside a ~5 s window can therefore see
a dead apex for up to 30 minutes even after the record exists, and HSTS preload forbids an
HTTP fallback for them. This is the residual cost of the cutover; it is why the maintenance
window is at a low-traffic hour, and it is why the window is measured rather than assumed.

**Why this gate earned its place here:** the earlier draft had already chosen the residual-downtime
path and optimised it, without ever asking whether the outage was necessary. It probably is not.

## Token Decision — ADR-130 decision test applied

**Axis 1 — least privilege.** Cloudflare Pages is reached at `/accounts/<id>/pages/projects`,
not `/zones/<id>/rulesets`. Different resource class entirely. ADR-130 names this case:
*"Where the marginal capability … reaches a different resource class entirely (R2 object
storage, zone settings), mint the narrow alias instead."* Folding Pages:Edit into
`cf_api_token_rulesets` would attach a site-content replacement primitive to a token five
`.tf` files and the pre-apply entrypoint gate already consume.

**Axis 2 — the root-var hazard.** A new alias needs a new no-default root variable, and
Terraform resolves all root variables **before** `-target` pruning, so an unprovisioned
`TF_VAR_cf_api_token_pages` fails the *whole* merge-triggered apply. Real, and a sequencing
cost, not a reason to widen.

**Decision: MINT a narrow alias `cf_api_token_pages`** (Account → Cloudflare Pages → Edit,
that permission only). The zone→account escalation is stated explicitly per ADR-130's #5092
note: this token is account-scoped because Pages is an account-level product, and it carries
no zone permission of any kind. The retained-scope probe set does not apply — it is scoped to
`cf_api_token_rulesets`, and a mint mutates no existing token. The new token gets its own
first-use probe instead.

**Publication.** The value must reach `deploy-docs.yml`. Two in-repo patterns exist:
`github_actions_secret` (seven instances) and a Doppler CLI read (`tunnel.tf`). This plan
uses `github_actions_secret` for the token **and** for the account id, because the workflow
runs in the Playwright container and the alternative adds a Doppler install to it. Recorded
honestly: the cited `kb-drift.tf` precedent publishes a *Doppler service token* — a scoped,
independently revocable credential — whereas this publishes the terminal Cloudflare
credential itself. The consequence is that after this change the token exists in **three**
places (Doppler `prd_terraform`, `terraform.tfstate` on R2, GitHub Actions secrets), one
rotation. That fan-out is named in the scope ledger and in `## Encryption Posture`, and a
Doppler-service-token indirection is recorded on the deferred issue as the tighter shape.

**Expiry.** Mint with **no expiry**, and state that in the scope ledger. `event-cf-token-expiry-check`
covers `CF_API_TOKEN` only; a freshly minted token with an expiry and no monitor is a ~90-day
time bomb that reds every docs deploy.

**Naming.** Doppler `CF_API_TOKEN_PAGES` → `TF_VAR_cf_api_token_pages` → Actions
`CLOUDFLARE_API_TOKEN_PAGES` → workflow `env: CLOUDFLARE_API_TOKEN`. Only the last is forced
(by wrangler); the divergence is noted at both sites.

## Implementation Phases

### Phase 0 — Pre-flight (blocking)

1. **Provision the Pages token.** `/work` drives the Cloudflare dashboard through Playwright
   to mint a token named `Pages edit — soleur-docs`, scoped to Account → Cloudflare Pages →
   Edit and nothing else, **with no expiry**, then writes it to Doppler `soleur/prd_terraform`
   as `CF_API_TOKEN_PAGES`.

   ```
   automation-status: MEASURED 2026-08-20 — OPERATOR-ONLY (vendor bot-detection).

   playwright-attempt: navigated https://dash.cloudflare.com/profile/api-tokens and
   https://dash.cloudflare.com/login (Playwright MCP, persistent profile, Chrome with
   --disable-blink-features=AutomationControlled already set); reached CAPTCHA/bot-detection
   class expressed as an ASSET-LAYER BLOCK — the HTML shell is served but every JS bundle
   fails net::ERR_FAILED (cf-unauthenticated-app, cf-ModalManager, cf-initGates,
   cf-accountHooks, cf-templatesPreview, cf-TooltipProvider), so the SPA never boots and the
   accessibility tree is a single 16-byte `- alert` node. No login form, no challenge widget
   and no OTP prompt is ever rendered, so there is nothing to drive up to.

   DISCRIMINATED, not assumed: https://example.com/ renders fully in the SAME browser with a
   live context and zero console errors, and a fresh browser instance reproduces the
   dash.cloudflare.com failure identically. So it is neither a network fault nor tool
   instability — it is specific to Cloudflare's dashboard under automation.

   Also exhausted, so nobody re-derives it:
     - API mint: all 9 CF_API_TOKEN_* in Doppler prd_terraform return 403 on
       GET /user/tokens; none can mint. No global API key exists in any of the 13 configs.
     - agent-browser CLI: daemon wedges ("Resource temporarily unavailable (os error 11)"
       after 5 retries) across 4 attempts including `close`.
     - soleur:provision-cloudflare: requires `read -s` on an INTERACTIVE terminal and is
       documented "MUST run on the operator's local machine" — the agent Bash tool is
       non-interactive by construction (hr-the-bash-tool-runs-in-a-non-interactive).
     - soleur:cf-token-scope: requires Playwright MCP dashboard automation (same block) and
       is a WIDEN of an existing token, not a mint.

   ✅ DONE 2026-08-20 — operator minted the token; verified without printing the value:
     - AC30 presence: `doppler secrets get CF_API_TOKEN_PAGES -p soleur -c prd_terraform` exit 0
     - AC12 ADR-130 retained-scope probe pair: pages/projects -> 200, zones/rulesets -> 403
       (the 403 is the load-bearing half — a 200 there would mean an over-scoped mint)
     - /user/tokens/verify: status=active, expires_on absent (no expiry, per the ledger)
     - project name free: 0 existing Pages projects on the account, `soleur-docs` not taken
     - chain proof: `doppler run --name-transformer tf-var` resolves TF_VAR_cf_api_token_pages,
       so the merge-triggered apply will not fail at root-variable resolution

   OPERATOR ACTION (the only remaining path): Cloudflare dashboard -> My Profile -> API
   Tokens -> Create Token -> Custom token; permission Account : Cloudflare Pages : Edit and
   NOTHING else; TTL none. Write the value to Doppler soleur/prd_terraform as
   CF_API_TOKEN_PAGES. Do NOT paste the value into an agent session
   (hr-never-paste-secrets-via-bang-prefix). AC30 then asserts presence pre-merge.
   ```

2. **First-use scope probe** (re-run any time the token is rotated):

   ```bash
   TOK=$(doppler secrets get CF_API_TOKEN_PAGES -p soleur -c prd_terraform --plain)
   ACCT=$(doppler secrets get CF_ACCOUNT_ID     -p soleur -c prd_terraform --plain)
   ZONE=$(doppler secrets get CF_ZONE_ID        -p soleur -c prd_terraform --plain)
   printf 'pages    -> '; curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
     -H "Authorization: Bearer $TOK" "https://api.cloudflare.com/client/v4/accounts/$ACCT/pages/projects"
   printf 'rulesets -> '; curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
     -H "Authorization: Bearer $TOK" "https://api.cloudflare.com/client/v4/zones/$ZONE/rulesets"
   ```

   Expected `pages -> 200`, `rulesets -> 403`. A `200` on the second line means the token is
   over-scoped and must be re-minted narrower.
3. **Assert the project name is free.** Using the token from step 1, `GET /accounts/$ACCT/pages/projects`
   must not list `soleur-docs`.
4. **Confirm the token resolves through Terraform** before PR1 merges: `TF_VAR_cf_api_token_pages`
   must be readable from `prd_terraform`. Until it is, PR1 cannot merge — an unprovisioned
   no-default root variable fails every apply on this root, not just this resource.
5. Baselines are already captured in Research Insights (headers, apex MX/TXT). Re-capture
   immediately before PR3 and record both in the PR body.

### Phase 1 — PR1: substrate

1. **`apps/web-platform/infra/cf-pages.tf`** (new):

   ```hcl
   resource "cloudflare_pages_project" "docs" {
     provider          = cloudflare.pages
     account_id        = var.cf_account_id
     name              = "soleur-docs"
     production_branch = "main"   # required by the v4 schema even for direct upload, and the
                                  # SOLE determinant of whether a deploy reaches the custom
                                  # domain or a preview alias. Must equal deploy-docs.yml's
                                  # --branch. Guard 1 M7 asserts the two agree.
     # No `source` block: `source` is the git integration. Omitting it is what makes this a
     # direct-upload project, which is what keeps the six gates authoritative.
   }

   resource "cloudflare_pages_domain" "apex" {
     provider     = cloudflare.pages
     account_id   = var.cf_account_id
     project_name = cloudflare_pages_project.docs.name
     domain       = "soleur.ai"
   }
   ```

   plus two `github_actions_secret` resources publishing `CLOUDFLARE_API_TOKEN_PAGES` and
   `CLOUDFLARE_ACCOUNT_ID_PAGES`, following the `kb-drift.tf` shape, each carrying a rotation-policy
   header comment.

   plus `cloudflare_pages_domain.www` for `www.soleur.ai`, per D1 — the Bulk Redirect runs in
   front of the project, and attaching www makes the redirect's failure mode duplicate content
   rather than a hard 522.
2. **`main.tf`**: a `cloudflare` provider alias `pages` bound to `var.cf_api_token_pages`,
   following the `r2` / `rulesets` alias shape, with a pointer to the scope ledger rather than
   a second enumeration.
3. **`variables.tf`**: declare `cf_api_token_pages`, `sensitive = true`, **no default**
   (`hr-tf-variable-no-operator-mint-default`). Its description is the scope ledger: the exact
   permission, no-expiry, the Doppler location, the three storage locations, the four names for
   one value, the consuming resources and workflow, the ADR-130 mint rationale, and the fact
   that `deploy-docs.yml` has no `pull_request` trigger.
4. **`seo-bulk-redirects.tf`**: add `cloudflare_list.www_canonical` and a second, explicitly
   ordered `rules { }` block per D1. Landing this **before** the DNS cutover is safe and
   deliberate: the Bulk Redirect matches on the `www.soleur.ai` host at the edge regardless of
   where www's DNS points, so it produces the same `301` the site already serves today. It is
   effectively a no-op until the cutover, and it means P2 is already live and measurable when
   PR3 fires.
5. **Cert-reissue disarmament** per D2: the apex-topology precondition, the `cron-gh-pages-cert-state`
   schedule removal, and the AP-019 status note in the principles register.
6. **`.github/workflows/apply-web-platform-infra.yml`**: extend the `-target=` allow-list with
   **all six** new addresses — `cloudflare_pages_project.docs`, `cloudflare_pages_domain.apex`,
   `cloudflare_pages_domain.www`, the two `github_actions_secret` addresses, and
   `cloudflare_list.www_canonical` — and in PR3, `cloudflare_record.pages_apex`. Every declared
   `github_actions_secret` in this root is individually target-listed today; an untargeted
   resource is silently never applied. **`-target=cloudflare_record.github_pages` stays** (D4):
   removing it once the block leaves config means the destroy is never planned.
7. **Rewrite `www-apex-canonicalizer.test.sh`** per Phase 4.
8. **Docs**: the ADR-194 amendment, the `domains.md` resolution note, the three C4 description
   corrections, the `soleur_acme_probe` description fix, and the deferred-cleanup issue.

**PR1 gates (PF1-PF4):**

| # | Assertion |
|---|---|
| PF1 | `terraform state list` shows `cloudflare_pages_project.docs` and `cloudflare_pages_domain.apex` |
| PF2 | Both `github_actions_secret` resources exist — `gh secret list` shows `CLOUDFLARE_API_TOKEN_PAGES` and `CLOUDFLARE_ACCOUNT_ID_PAGES` |
| PF3 | **R8 probe**: `GET /zones/$ZONE/dns_records?name=soleur.ai` shows **no new record** created by the custom-domain attachment. If Cloudflare auto-created one, the `dns.tf` design becomes an `import` rather than a create, and PR3 changes shape before it is written |
| PF4 | `curl -sSI https://www.soleur.ai/` still returns `301` to the apex — the Bulk Redirect landed without disturbing the live behaviour — **and** T-WWW passes on the ten legacy legal paths |

### Phase 2 — PR2: the deploy path

1. **`deploy-docs.yml`**: replace **only** the three terminal steps (`actions/configure-pages`,
   `actions/upload-pages-artifact`, `actions/deploy-pages`) with:

   ```yaml
   - name: Install wrangler (exact version, no floating tag)
     run: npm install --no-save wrangler@4.124.0
   - name: Deploy to Cloudflare Pages
     env:
       CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN_PAGES }}
       CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID_PAGES }}
     run: npx wrangler pages deploy _site --project-name=soleur-docs --branch=main
          --commit-hash="${GITHUB_SHA}" --commit-dirty=false
   ```

   The exact-version, `--no-save` form mirrors the step ~130 lines above it
   (`npm install --no-save playwright@1.60.0 http-server@14`) and its explicit
   "no `^`, no `~`, no floating tag" comment. `npx --yes wrangler@<major>` would re-resolve
   from npm at every deploy, outside the lockfile and invisible to dependency review, while
   holding a token that can replace every byte of `soleur.ai`.
2. **Build-identity stamp**: emit `_site/version.txt` containing `${GITHUB_SHA}` during the
   build, and add `test -f _site/version.txt` to the build-verification gate.
3. **Post-deploy custom-domain probe** (a new step, not one of the six gates): after the
   deploy, `curl https://soleur.ai/version.txt` and fail the job unless it equals
   `${GITHUB_SHA}`. This is the detector for the plan's highest-ranked risk — a deploy that
   lands on a preview alias leaves the custom domain serving the previous build while the
   workflow is green. (Superseded 2026-09-02: under dual-publish both probes are hard
   gates from PR2; the reporting-only mode described here was never shipped.) Against
   `https://soleur-docs.pages.dev/version.txt`, since the apex is still GitHub Pages.
4. **Leftovers**: rename the workflow (it is `Deploy Documentation to GitHub Pages`); remove
   the `environment: { name: github-pages, url: ${{ steps.deployment.outputs.page_url }} }`
   block, whose `url` now resolves from a deleted step id and which gates the job on a
   `github-pages` environment it no longer deploys to; drop `permissions: pages: write` and
   `id-token: write`; keep `contents: read`, the `concurrency` group and the monitor
   pause/resume block.
5. **`_site/CNAME` and `_site/.nojekyll` become publicly served static files** on Pages
   (GitHub Pages consumed them). Harmless; recorded in the runbook so `https://soleur.ai/CNAME`
   is not later mistaken for a leak. `CNAME` stays in the build because it is part of the
   GitHub Pages configuration retained for rollback.
6. **Create the cutover runbook**, `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`:
   pre-flight set, cutover verification, the rollback path, the `[ack-destroy]`-on-the-merge-commit
   mechanics, and the fact that `workflow_dispatch` cannot perform the rollback (D3). It also
   carries **content rollback** — how to roll back a bad docs build now that re-running a
   previous green workflow run is no longer the mechanism. Verify the
   `wrangler pages deployment` subcommand shape at the pinned version before writing it; it was
   not in the `--help` capture.

**PR2 gates (PF5-PF8):**

| # | Assertion |
|---|---|
| PF5 | `https://soleur-docs.pages.dev/version.txt` equals the merge SHA — the build is live on the **production** branch of the project |
| PF6 | A nonexistent path on `*.pages.dev` returns `404`; `/` returns `200` |
| PF7 | **D3(b) probe**: attach a scratch custom domain to the project, then detach it, and observe whether edge routing for that hostname persists. This decides whether a DNS-only revert is sufficient or whether the rollback must also destroy `cloudflare_pages_domain.apex`. The runbook is written to match the measured answer |
| PF8 | The revert PR for PR3 is open, green and mergeable, with `[ack-destroy]` positioned to land in the squash message |

### Phase 3 — PR3/PR4: attach, then the DNS cutover

> **Superseded 2026-09-02 (PR2).** This section predates the four-PR amendment in
> *Delivery Sequencing* and its five-PR extension. PR3 attaches the custom domains;
> PR4 swaps the DNS record; PR5 retires the GitHub Pages publish leg. Read the
> sequencing table, not this heading, for what lands where.

**Pre-flight: PF1-PF8 all hold, plus:**

| # | Assertion |
|---|---|
| PF9 | `terraform plan` shows exactly: 4 `cloudflare_record.github_pages[*]` deletes, 1 `cloudflare_record.pages_apex` create, 1 **in-place update** of `cloudflare_record.www` (`destroy_count` = 4, not 5) — and **zero** changes to `cloudflare_ruleset.seo_page_redirects`, `cloudflare_ruleset.seo_config_settings`, `cloudflare_zone_settings_override.soleur_ai`, or the apex MX/TXT records |
| PF10 | The merge commit message carries a line containing exactly `[ack-destroy]` |
| PF-ORDER | The cutover runs as **two targeted passes** (D4): the destroy pass completes and the four `cloudflare_record.github_pages[*]` records are gone from state **before** the `cloudflare_record.pages_apex` create pass is dispatched. Asserted on the sequence, not the counts — a shape assertion cannot see order, and an unordered apply can hit Cloudflare error `81053` mid-flight on the live apex |

**The change** — `apps/web-platform/infra/dns.tf`, and nothing else in this PR:

- Remove `cloudflare_record.github_pages` (the `for_each` over four GitHub Pages `A` IPs) and
  add **`cloudflare_record.pages_apex`** — the address is named here deliberately, because an
  unnamed address is one nobody adds to the `-target=` allow-list: `name = "soleur.ai"`
  (**never** `@`), `type = "CNAME"`,
  `content = cloudflare_pages_project.docs.subdomain` (a resource reference, not a literal),
  `proxied = true`, `ttl = 1`.
- Retarget `cloudflare_record.www`'s `content` to `cloudflare_pages_project.docs.subdomain`.
  `name` and `type` are unchanged, and `content` is **not** ForceNew, so this is an **in-place
  update**, not a replace.
- Leave `cloudflare_record.github_pages_challenge` (TXT) in place — part of the GitHub Pages
  configuration retained DNS-detached for rollback.
- Rewrite the contract comment to enumerate all three redirect substrates and name the new
  owner of the 301 (R2).
- **Both the old and new record addresses must be in the `-target=` allow-list during this
  apply**, or a targeted apply could create the CNAME without the four `A` deletes in scope —
  which Cloudflare rejects, since a CNAME cannot coexist with `A` records at the same name.

**Post-cutover verification — the site is not cut over until all hold.** Because the plan's
own propagation estimate is ~5 minutes of mixed resolution (proxied TTL is fixed at 300 s),
a single sample would legitimately fail on a healthy cutover. Each assertion is therefore
**3 consecutive clean samples at 60 s intervals, beginning 5 minutes after the apply**, with
transport failure reported as a distinct `UNREACHABLE` verdict rather than folded into either
answer (AP-021).

| # | Assertion |
|---|---|
| CUT0 | `https://soleur.ai/version.txt` equals the merge SHA — **binds the apex to the current build**. Closes preview-alias, stale-deployment, wrong-project and did-the-deploy-land in one predicate |
| CUT1 | `https://soleur.ai/` returns `200` |
| CUT2 | The response carries **none** of `x-github-request-id`, `x-github-edge-region`, `via: 1.1 varnish`, `x-fastly-request-id`, `x-served-by`, `x-proxy-cache`. `server: cloudflare` is deliberately not used — it is true before *and* after |
| CUT3 | `https://www.soleur.ai/` returns `301` to `https://soleur.ai/`, with no GitHub-origin header |
| CUT4 | `https://www.soleur.ai/agents/` returns `301` to `https://soleur.ai/agents/` — path preservation, not a bare-apex collapse |
| CUT5 | A nonexistent path returns `404` |
| CUT6 | `strict-transport-security: max-age=63072000; includeSubDomains; preload` still present |
| CUT7 | T-WWW: the ten legacy `/pages/legal/<slug>.html` paths on the **www** host still `301` to their `/legal/<slug>/` targets |
| CUT8 | All **five** monitors green through one full check interval: `soleur_apex`, `soleur_www`, `soleur_changelog_deep`, `soleur_acme_probe`, and `betteruptime_monitor.soleur_apex`. `soleur_changelog_deep` is load-bearing here — a trailing-slash directory-index regression on Pages would leave the root at 200 while every other page 404s |
| CUT9 | **`dig soleur.ai MX` and `dig soleur.ai TXT` return byte-identical sets to the Phase 0 baseline** — the apex A→CNAME transition did not disturb mail routing or domain verification |

> **CUT0 IS UNSATISFIABLE AS WRITTEN — corrected 2026-09-03 (PR4).** CUT0 says
> *"`https://soleur.ai/version.txt` equals **the merge SHA**"*. It was written when the cutover
> PR also published. It no longer does: `deploy-docs.yml`'s `on.push.paths` deliberately
> excludes `dns.tf`, and the workflow's own comment says so in as many words — *"PR4 is dns.tf
> only and so still does not fire this workflow, which is required — a publish racing the DNS
> apply would have the apex probe measuring mid-propagation and reporting a false MISMATCH on
> the cutover PR."* So after PR4's merge `version.txt` still holds the SHA of the **last
> `deploy-docs.yml` run**, and CUT0 read literally fails all three samples and drives a **false
> rollback at T+20** — the exact outcome the path filter was designed to prevent, reintroduced
> by an assertion that was not updated alongside it.
>
> **The invariant CUT0 is actually for** is *"the apex serves the build the Pages project
> currently holds"*, and the merge SHA was only ever a proxy for it. Corrected form:
>
> **CUT0′** — `https://soleur.ai/version.txt?cb=<nonce>` equals the SHA recorded by PF-DOCS
> (the `headSha` of the last successful `deploy-docs.yml` run on `main`, which PF-DOCS already
> asserts equals `main`'s tip). The cache-buster is not optional: the apex measured
> `cache-control: max-age=600`, `age: 279`, `x-cache: HIT` on 2026-09-02, and Probe B carries
> one for this measured reason. **AC23 then becomes the assertion that a NEW build reaches the
> apex** — it dispatches `deploy-docs.yml` explicitly and checks `version.txt` moves.

> **AC23 is red-by-construction between PR4 and PR5 — clarified 2026-09-03.** Post-cutover the
> `actions/deploy-pages` leg fails GitHub's custom-domain DNS check (the apex `A` records are
> gone), and AC31's publish-verdict step is a **conjunction** that `exit 1`s unless every leg
> is `success`. So AC23's dispatched run is guaranteed red **overall**. AC23 is satisfied by
> the **per-leg table** in `$GITHUB_STEP_SUMMARY` showing the wrangler leg and Probe B
> `success`, never by the run conclusion — and the runbook must say so, because nothing else
> distinguishes this benign red from a real publish failure at the moment someone reads it.

**Decision point.** If CUT0′-CUT9 are not all green by **T+20 minutes** from the apply, merge
the pre-opened revert PR. Rolling back is the default action on ambiguity. Do not debug forward
on a live public surface.

**Who decides, and the T+20 budget — corrected 2026-09-03.** This paragraph previously read
*"the decider is the engineer running the cutover"* while `### Phase 4` labels the same merge
steps *"none is an operator action"*. One decision, two actors, and the operator-shaped reading
also trips `lint-infra-no-human-steps.py`. It is resolved in favour of automation: the **session
driving the cutover** samples CUT0′-CUT9 through a committed script and merges the revert PR on
a failing verdict; no human approval is interposed, and the branch is mechanical rather than
judgemental. **CUT0′-CUT9 therefore need a runner** — a committed
`apps/web-platform/infra/cutover-verify.sh` emitting a per-assertion table and a single exit
code, for the same reason `apex-origin-probe.sh` and `pages-build-identity-probe.sh` exist:
an inline ten-assertion × three-sample probe with a credentialed monitor read (CUT8) is not
runnable, and "recorded with measured output" asserts a transcript rather than a gate.

**T+20 is a budget, and the queue is inside it.** The rollback merge must acquire
`concurrency: terraform-apply-web-platform-host` with `cancel-in-progress: false`, shared with
`apply-deploy-pipeline-fix.yml` and the recut jobs. The workflow's own arithmetic gives a
**47-minute** worst case for one run (preflight 1 + apply 41 + notify 5), and materially longer
if a `*-luks-recut` chain holds the group. So "rollback is one merge" can mean *one merge plus
a queue wait that exceeds the entire decision budget*. This is disclosed here and in the
runbook next to the decision point; it is a reason to declare the maintenance window at an hour
when no other infra work is in flight, not a reason to change the lever.

### Phase 4 — the DNS cutover, as two merges (this branch)

**Superseding the resume brief's inputs, explicitly.** Two of the inputs this work started from
are changed by D5's measurements. They are not silently absorbed:

1. **PF9 changes shape.** The brief specified one merge at *"4 deletes + 1 create + 1 in-place
   www update, `destroy_count = 4`"*. That shape is abandoned because it is the shape that
   cannot be ordered: four deletes and one create in one window are unrelated graph nodes by
   construction, and no assertion over that plan can make the create wait. PF9 becomes a
   **per-merge** assertion — `destroy_count = 3` on PR4a, `resource_deletes: 1` on PR4b
   (measured through the real `destroy-guard-filter-web-platform.jq`, not asserted).
2. **PF8's unmet pre-opened revert is RESOLVED, not deferred.** It becomes the **generated
   reverse-`moved` rollback PR**. The operator asked to keep PR3's revert as a **two-step**
   shape; that is preserved in substance — step 1 is the generated reverse PR for PR4b, step 2
   is reverting PR3 only if the origin probe still reports Cloudflare. The mechanism changed;
   the constraint did not.
3. **PF-ORDER survives, relocated.** Its intent was *"assert on the sequence, not on counts."*
   Under D5 there is no sequence left to assert dynamically — core enforces it at one address.
   The intent is honoured by the **static** assertion that `create_before_destroy` is not set on
   the apex record (Guard 2, M1), which is exactly what stops P10 from being
   structurally-satisfied-but-unasserted.

**Order within the branch is load-bearing.** PR4a must merge and converge before PR4b is
written, because PR4b's `moved.from` index must name the key PR4a actually left behind.

#### PR4a — shrink the apex to one `A` record

**4a.1** — `apps/web-platform/infra/dns.tf`: `cloudflare_record.github_pages`'s `for_each`
becomes `toset(["185.199.108.153"])`. Nothing else changes; `cloudflare_record.www` and
`cloudflare_record.github_pages_challenge` are untouched.

**4a.2** — Guard 2 ships **here**, not with PR4b, and its H3 harness row is why: the guard must
be green on the PR4a shape (one instance, no `moved` block, no `pages_apex`) or it blocks PR4a's
own CI and every unrelated infra PR in the window between the two merges.

**4a.3** — the runbook gains the two-merge procedure and the `git revert` prohibition **before**
the first destructive merge, not after.

| # | PR4a pre-flight |
|---|---|
| PF9a | `terraform plan` shows exactly 3 deletes of `cloudflare_record.github_pages[*]`, **0 creates**, and zero changes to `www`, the `_challenge` TXT, `seo_page_redirects`, `seo_config_settings`, `zone_settings_override` or the apex MX/TXT. `destroy_count = 3` |
| PF10a | The merge commit message carries `[ack-destroy]` on its own line |
| PF-APEX | After the apply, the apex still resolves and still serves: `apex-origin-probe.sh` returns `SERVING-FROM-GITHUB-PAGES`, and `https://soleur.ai/` returns 200 across 3 samples |

#### PR4b — flip the survivor to a `CNAME`

**4b.1** — `dns.tf`: add the `moved` block
(`from = cloudflare_record.github_pages["185.199.108.153"]`, `to = cloudflare_record.pages_apex`),
declare `cloudflare_record.pages_apex` with `name = "soleur.ai"` (**never** `@`),
`type = "CNAME"`, `content = cloudflare_pages_project.docs.subdomain` (a resource reference —
this survives, because there is no scoped pre-pass plan to drag the project into),
`proxied = true`, `ttl = 1`; retarget `cloudflare_record.www`'s `content` to the same reference;
leave `github_pages_challenge` in place; rewrite the contract comment **in dot-notation**
(AC43's caution).

**www stays a `CNAME` — CTO ruling, Camp B, and now measured.** `type` is ForceNew at provider
4.52.7, so an `A` at `www` would be a *second* replacement racing the first and would move
PR4b's `destroy_count` to 2. Guard 2 M4 rejects it.

**4b.2 — the rollback-PR generator**, committed and unit-tested. It transforms PR4b's own diff
into the reverse PR: swap the `moved` block's `from`/`to`, return `type` to `"A"`, return
`content` to the surviving IP literal. **Its strongest test is that the generated `dns.tf` is
byte-identical to `dns.tf` as PR4a left it** — a state that actually existed, so the assertion
is checkable rather than self-referential.

**4b.3** — the three design-independent deliverables of 4.7 below.

| # | PR4b pre-flight |
|---|---|
| PF9b | `terraform plan` shows **one** address, `cloudflare_record.pages_apex`, with actions `["delete","create"]` and the `(moved from …)` annotation; plus the in-place `www` update. Through `destroy-guard-filter-web-platform.jq`: `resource_deletes: 1, nested_deletes: 0, reboot_updates: 0, host_creates: 0`. Zero changes to the rulesets, zone settings and apex MX/TXT |
| PF-MOVED | The `moved.from` index literal is **byte-identical** to the `for_each` key PR4a left behind. **This fails SILENTLY if violated** — Terraform no-ops a move against absent state, so `pages_apex` would plan as a bare create while the real survivor plans as a separate delete: two addresses, concurrent, hazard restored, no error. Asserted mechanically (Guard 2 M3), never by eye |
| PF-TARGET | **Both** `-target=cloudflare_record.pages_apex` and `-target=cloudflare_record.github_pages` are in the allow-list, line-anchored. Measured: a `moved` block with only one endpoint targeted produces `Error: Moved resource instances excluded by targeting` — the apply **hard-errors** |
| PF10b | `[ack-destroy]` on its own line in the merge commit message (`destroy_count = 1`) |
| PF-Z2 | `apex-origin-probe.sh` returns `SERVING-FROM-GITHUB-PAGES` (rc 0). A flip to `SERVING-FROM-CLOUDFLARE-PAGES` means the origin moved without the record and the plan shape has changed under the ack — **stop**. `UNREACHABLE` blocks the merge |
| PF-R8b | Apex returns exactly the surviving `A` + MX/TXT and **no `CNAME`**; `www` returns exactly one proxied `CNAME` |
| PF-SSL | `seo-config-rules.tf` still carries exactly one `ssl = "full"` rule. **PR #7753 owns that rule's guard; its work is not co-located here** |
| PF-DOCS | `gh run list --workflow=deploy-docs.yml --branch main --limit 1` is `success` with both build-identity probes `success` and `headSha == main`'s tip |
| PF-SYM | The symmetry probe: on a scratch name in the zone, create a `CNAME`, attempt an `A`, record the error code, delete. **It matters MORE under this design, not less** — a mistaken `git revert` lands directly in the reverse-direction failure, and the error code should be measured before anyone meets it during an incident |
| PF-DEFER | The deferred-cleanup issue is verified to exist by number (`gh issue view`), or filed |

**4.7 — three design-independent deliverables** (required whichever mechanism ships):

- **`apex-origin-probe.sh` needs a cache-buster, and it is the rollback's branch selector.** It
  requests `${APEX_PROBE_URL:-https://soleur.ai/}` with no cache-busting query string, while
  Probe B carries one for a measured reason (the apex returned `cache-control: max-age=600`,
  `age: 279`, `x-cache: HIT` on 2026-09-02). Its `SERVING-FROM-CLOUDFLARE-PAGES` arm is a
  **residual** verdict — "200, and no GitHub marker" — so a cached response, or any
  Cloudflare-served 200 error page, reads as Cloudflare and routes the session into the
  second destroy during an active incident. Add the buster; keep the three verdicts and both
  AP-021 `UNREACHABLE` arms exactly as they are.
- **`apps/web-platform/infra/cutover-verify.sh`** — the committed runner for CUT0′-CUT9. Emits a
  per-assertion table and one exit code, with `UNREACHABLE` distinct from a failed assertion.
- **CUT9's baseline moves out of prose into a fixture.** It currently lives only in
  `### Measured empirical baseline (2026-08-20)`, which PR5 **archives** — so the rollback's
  mail-safety comparison would point at a moved document. It is also stale; "byte-identical
  **sets**" conflates bytes with sets; `dig +short TXT` ordering is not stable; and the plan
  records live drift (two `google-site-verification` values, one declared). Commit a sorted,
  normalised fixture beside `cutover-verify.sh` and compare **sets**.

**Merge steps for PR4b (automated; none is an operator action):**

1. Merge PR4b with `[ack-destroy]` on its own line.
2. **PF8′ — generate and open the rollback PR immediately.** Run the 4b.2 generator against the
   merge diff, push, `gh pr create` with `[ack-destroy]` positioned for its own squash message.
   **NOT `git revert`** — measured, that produces a two-address concurrent plan and reproduces
   `81053` in the reverse direction. Its CI runs concurrently with the propagation wait.
3. Wait 5 minutes, then run `cutover-verify.sh` for CUT0′-CUT9 under the 3-consecutive-clean-
   samples-at-60 s rule.
4. **Decision point at T+20.** On any failure, merge the generated rollback PR; then re-probe
   the origin and revert PR3 as a second step **only if** it still reports
   `SERVING-FROM-CLOUDFLARE-PAGES`. Do not debug forward on a live public surface.
5. Close #7640 (`Closes #7640` in PR4b's body).

### Phase 5 — PR5: retire the GitHub Pages publish leg

Merged **after** CUT0′-CUT9 all hold, in the same session as PR4 (AC34). Scope is the
`deploy-docs.yml` publish path **only** — this is *not* the ADR's `### What gets deleted`
list, every item of which stays deferred to the cleanup issue, `ssl = "full"` most of all.

**5.1** — delete the three GitHub Pages actions (`actions/configure-pages`,
`actions/upload-pages-artifact`, `actions/deploy-pages`), the `environment: github-pages`
block, and the `pages: write` / `id-token: write` permissions. Remove the publish-verdict
step's GitHub-Pages arm; the wrangler leg and **Probe B survive** — post-PR4, Probe B is CUT0
made permanent, asserting on every run that the apex serves the current build through
Cloudflare Pages.

**5.2 — flip the tense in `model.c4`.** The `github` element says *"until the #7640 cutover"*,
the `cloudflare` element says *"from #7640/ADR-194"*, and the `letsencrypt` element says
*"From the cutover…"*. All three were written by PR1 as true-in-advance descriptions; PR4 is
when they become true, and leaving them in the anticipatory tense is the doc-rot this plan
corrects elsewhere. Enumeration for the C4 completeness mandate is in
`### C4 views` below.

**5.3 — record what PR5 costs.** PR5 is the point at which the rollback stops being one merge.
After it, the GitHub Pages content **freezes at the last PR4-era build**, and restoring the
site to that origin requires re-adding the publish leg *and* a redeploy *and* the DNS revert —
three acts, not one. State this in the runbook explicitly, next to the rollback procedure, and
add it to the deferred-cleanup issue's re-evaluation criteria. AC34's "same session, after
CUT0′-CUT9 hold" is the mitigation; the disclosure is what makes it a decision rather than a
surprise.

**5.4 — archive the plan.** `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`,
committed as `plan: archive cloudflare-pages migration`. **PR5 only.** Archiving at PR4 would
move the document an incident would need out from under the runbook that cites it.

## Files to Edit

**PR1** — `scripts/encryption-posture-ledger.json`; `apps/web-platform/infra/main.tf`, `variables.tf`, `seo-bulk-redirects.tf`,
`www-apex-canonicalizer.test.sh`, `sentry/uptime-monitors.tf` (comment only);
`apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts`,
`cron-gh-pages-cert-state.ts`; `.github/workflows/apply-web-platform-infra.yml`;
`knowledge-base/engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md`;
`knowledge-base/engineering/architecture/principles-register.md`;
`knowledge-base/operations/domains.md`;
`knowledge-base/engineering/architecture/diagrams/model.c4`

**PR2** — `.github/workflows/deploy-docs.yml`

**PR3** — `apps/web-platform/infra/cf-pages.tf` (the two `cloudflare_pages_domain` resources
alone). *(Corrected 2026-09-03: this row read `dns.tf` under the superseded three-PR
numbering. `dns.tf` is PR4's file and PR3 must not touch it.)*

**PR4a — shrink** —
`apps/web-platform/infra/dns.tf` (`for_each` down to one key);
`.github/workflows/infra-validation.yml` (register Guard 2);
`knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`.

**PR4b — flip** —
`apps/web-platform/infra/dns.tf` (the `moved` block + the `CNAME` flip + the `www` retarget);
`apps/web-platform/infra/apex-origin-probe.sh` (cache-buster, 4.7);
`knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`;
`knowledge-base/engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md`
(the ordering amendment + the Z-falsified record).

**No edit to `.github/workflows/apply-web-platform-infra.yml`.** Its allow-list already carries
both `moved` endpoints (verified 2026-09-03), which is exactly what PF-TARGET requires — and
under D5 there are no pre-pass steps to add. `scripts/test-all.sh` is likewise untouched:
Guard 2 lives under `apps/web-platform/infra/` and is reached from `infra-validation.yml`, so
the `tests/scripts/` orphan-registration hazard does not arise.

**PR5** —
`.github/workflows/deploy-docs.yml`;
`knowledge-base/engineering/architecture/diagrams/model.c4` (tense flip on the `github`,
`cloudflare` and `letsencrypt` element descriptions);
`knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md` (the
rollback-narrowing disclosure, 5.3);
plus the `archive-kb.sh` move of this plan (5.4).

## Files to Create

- `apps/web-platform/infra/cf-pages.tf` (PR1)
- `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md` (PR2)
- `apps/web-platform/infra/apex-single-node-replace.test.sh` (PR4a) — Guard 2, a **static**
  assertion over `dns.tf` + the apply allow-list. No plan JSON, no fixtures, no credentials
- `apps/web-platform/infra/cutover-verify.sh` (PR4b) — the committed CUT0′-CUT9 runner
- `apps/web-platform/infra/cutover-mx-txt-baseline.txt` (PR4b) — CUT9's sorted, normalised
  fixture, replacing the prose baseline PR5 archives
- `apps/web-platform/infra/generate-apex-rollback-pr.sh` + its `.test.sh` (PR4b) — the
  reverse-`moved` rollback-PR generator and its unit tests. **`git revert` cannot do this job**
  (D5, measured), and this script is what stands in for it

**Cut from an earlier draft of this same pass**, with the pre-pass they served:
`tests/scripts/lib/apex-cutover-order-gate.sh`, `tests/scripts/test-apex-cutover-order-gate.sh`,
`tests/scripts/fixtures/apex-cutover-*.json`, and
`apps/web-platform/infra/apex-cutover-order-workflow.test.sh`. Four artifacts and an eleven-row
mutation battery dissolved when the transition became one resource address.

**Glob verification (2026-09-03):** `apps/web-platform/infra/dns.tf`,
`.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/infra-validation.yml`,
`.github/workflows/deploy-docs.yml`, `scripts/test-all.sh`, `tests/scripts/lib/`,
`tests/scripts/fixtures/`, `apps/web-platform/infra/apex-origin-probe.sh`, the cutover runbook,
`ADR-194-…​.md` and `model.c4` were each read or listed during this pass, and `placement-group.tf`
was read for the `moved` precedent. Every Files-to-Create path was checked and **none exists**:
`apex-single-node-replace.test.sh`, `cutover-verify.sh`, `cutover-mx-txt-baseline.txt`,
`generate-apex-rollback-pr.sh` and its `.test.sh`.

**Not edited, deliberately:** `eleventy.config.js` and `views.c4`. Both were in an earlier
draft; the `_headers`/`_redirects` cut and the C4 container cut removed the need. Their absence
also removes two hazards — the `infra-validation.yml` path-filter gap (R10) and the #7332
both-endpoints-must-be-included rule.

**Glob verification:** every Files-to-Edit path was read or listed during research; the two
Files-to-Create paths do not exist.

## Acceptance Criteria

Verification commands are written exit-safe: `grep -c` **exits 1 on zero matches**, so a bare
`grep -c … returns 0` would abort under `set -e` rather than pass. Each count assertion below
uses `$(grep -c … || true)` compared with `[ "$n" = "0" ]`, or `! grep -q`.

### PR1

- **AC1** — `cf-pages.tf` declares `cloudflare_pages_project.docs` with `production_branch = "main"` and no `source` block: `! grep -q 'source {' apps/web-platform/infra/cf-pages.tf`.
- **AC2** — `terraform validate` passes in `apps/web-platform/infra/` (the catch for v4-vs-v5 schema drift and any `ExactlyOneOf` violation).
- **AC3** — two `cloudflare_pages_domain` resources are declared (apex and www): `grep -c 'resource "cloudflare_pages_domain"' apps/web-platform/infra/cf-pages.tf` equals `2`.
- **AC4** — `variables.tf` declares `cf_api_token_pages` with `sensitive = true` and no `default`. Anchor on the **assignment**, not the word: `awk '/variable "cf_api_token_pages"/,/^}/' apps/web-platform/infra/variables.tf | grep -cE '^\s*default\s*=' || true` equals `0`. A bare `grep -c 'default'` returns `1` on a correct implementation, because the repo's convention for this exact variable shape is a description ending *"No default (hr-tf-variable-no-operator-mint-default)"* — verified against the `cf_api_token_dns_edit` precedent.
- **AC5** — the `-target=` allow-list contains all six new addresses **and still contains `cloudflare_record.github_pages`** (D4). Asserted by a **direct grep of `.github/workflows/apply-web-platform-infra.yml`**, one assertion per address — not by delegating to `terraform-target-parity.test.ts` or `test-destroy-guard-counter-web-platform.sh`, neither of which can see a `cloudflare_pages_*` or `github_actions_secret` resource (R9). Both suites are still run, but as regression checks, not as evidence for this property.

  **AC5 addendum — 2026-08-20 (#7640), measured.** Each of the seven assertions MUST be
  LINE-ANCHORED, not a bare substring grep. Measured against the as-written workflow, the
  bare form `grep -c -- '-target=cloudflare_record.github_pages'` returns **2**, because
  `-target=cloudflare_record.github_pages_challenge` contains it as a prefix — so an AC5
  written as `[ "$(grep -c ...)" = 1 ]` FAILS on a correct file, and the natural "fix" is to
  loosen the assertion rather than anchor it. Use the terminated form, which returns 1:
  `grep -cE '^[[:space:]]+-target=cloudflare_record\.github_pages \\$' <workflow>`.
  This is not specific to that one address: `cloudflare_pages_project.docs` and
  `cloudflare_pages_domain.www` are prefix-vulnerable to any future sibling in exactly the
  same way, so all seven use the anchored form (`cq-assert-anchor-not-bare-token`).
- **AC6** — `seo-rulesets.tf` is unchanged: `git diff --stat origin/main -- apps/web-platform/infra/seo-rulesets.tf` is empty. Rule 10 and its ACME carve-out clause survive verbatim.
- **AC7** — `seo-config-rules.tf` still contains exactly one `ssl = "full"` Configuration Rule: `grep -c 'ssl *= *"full"' apps/web-platform/infra/seo-config-rules.tf` equals `1`. **Asserted at the resource level, not as an empty diff.** An empty-diff assertion would forbid correcting the rule's `REMOVAL CONDITION` comment, which instructs deleting the block once `gh api repos/jikig-ai/soleur/pages` reports an issued certificate — a condition the cutover makes permanently unsatisfiable, because DNS is detached and the certificate can never issue. Locking that comment in place is the same doc-rot this plan corrects elsewhere; the comment is updated and the rule is not.
- **AC8** — none of the deferred-deletion artifacts are removed. Per-path existence check, never an aggregate count:
  `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts`,
  `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts`,
  `apps/web-platform/server/cert-reissue-marker.ts` (note: `server/`, **not** `server/inngest/functions/`),
  `apps/web-platform/infra/cf-cert-reissue-token.tf`,
  `knowledge-base/engineering/operations/runbooks/gh-pages-cert-renewal.md`.
  The `CF_API_TOKEN_DNS_EDIT` secret and `doppler_secret.cf_api_token_dns_edit` are likewise untouched.
- **AC9** — `plugins/soleur/docs/CNAME` still exists and reads exactly `soleur.ai`.
- **AC10** — the rewritten `www-apex-canonicalizer.test.sh` exits `0` on the branch, and **each of Guard 1's mutation rows M1-M10, including the lettered variants M4b, M5a/M5b, M7a/M7b drives it to a non-zero exit**, and harness row H1 fails while H2 passes. (The row count is stated as the explicit range, not a bare number — an earlier draft said "three" against a six-row matrix, which would have let the guard ship with its chokepoint and vacuity rows unexercised.)
- **AC11** — the guard's anti-vacuity floor conforms to **AP-023**: it reports with `printf >&2` + `exit 1` rather than through the suite's own `fail`, and the case counter increments **at the call site**, not inside both verdict helpers. The current file has the banned shape (`TOTAL=$((TOTAL + 1))` inside both `pass()` and `fail()`), so this is a required change, not a preserved property. `scripts/guard-vacuity-floor.test.sh` passes.
- **AC12** — the Phase 0 token probe records `pages -> 200` and `rulesets -> 403`, and `TF_VAR_cf_api_token_pages` resolves from Doppler `prd_terraform`. Asserted by re-running the probe, not by the presence of text in a PR body.
- **AC13** — `terraform plan` shows zero changes to `seo_page_redirects`, `seo_config_settings`, `zone_settings_override`, and the apex MX/TXT records.
- **AC14** — ADR-194 carries the R1 correction in `## Decision` and names the considered options in `## Alternatives Considered`.
- **AC25** — `cron-gh-pages-cert-reissue.ts` refuses to run when the live apex record type is not `A`, asserted by a unit test that stubs the record read with a `CNAME` and expects the non-benign terminal outcome.
- **AC26** — `cron-gh-pages-cert-state.ts` no longer registers a `cron` trigger: `! grep -q 'cron: "0 3 \* \* \*"' apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts`, with the manual-trigger arm retained.
- **AC27** — the principles register records that AP-019's "self-reverting" justification is void until the topology precondition is live.
- **AC27a** — `sentry_cron_monitor.scheduled_gh_pages_cert_state` carries `enabled = false`, and the PR-time sentry-root plan reports **0 destroys** (`sentry-destroy-required` green with no `[ack-destroy]` on PR1).
- **AC27b** — the monitor's `schedule`, `checkin_margin_minutes`, `max_runtime_minutes` and both thresholds are unchanged from `main` (asserted by diff), so re-arming is a single-attribute flip.
- **AC27c** — `routine-metadata-parity.test.ts` is green: every `ROUTINE_METADATA.description` is <= 160 chars, including the disarmed cert-state entry.
- **AC27d** — `sentry-monitor-iac-parity.test.ts` is green **with no new `DISABLED_CRON_SLUG_EXEMPTIONS` entry** — the structural proof the monitor was disabled, not deleted.
<!-- lint-infra-ignore start: AC27f describes an AUTOMATED merge step (a `gh issue close`
     invocation in PR1's merge steps), not a human-run infra step. It trips the linter only
     because it QUOTES the imperative that the filed comment must carry — "must NOT be
     fired" is text destined for a GitHub issue body, addressed to whoever reads that
     backlog, not an instruction to the operator. -->
- **AC27f** — `[cert-poll]` issues #6691 and #6657 are closed with a comment naming this work as superseding and explicitly instructing that `cron/gh-pages-cert-reissue.manual-trigger` must NOT be fired. Asserted by `gh issue view 6691 --json state` returning `CLOSED`. Automated in the merge steps, never an operator action.
<!-- lint-infra-ignore end -->
- **AC30 (BLOCKING, pre-merge)** — `doppler secrets get CF_API_TOKEN_PAGES -p soleur -c prd_terraform --plain` exits `0`. Asserted BEFORE the PR is marked ready, not after: `cf_api_token_pages` has no default and Terraform resolves every root variable before `-target` pruning, so an absent secret freezes the ENTIRE `apps/web-platform/infra` root — blocking every unrelated infra change behind a red apply, across all three workflows that plan this root (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, and the 12-hourly `scheduled-terraform-drift.yml`).
- **AC27e** — `cron-inngest-cron-watchdog.ts`'s cadence comment no longer cites `scheduled-gh-pages-cert-state` as a live constraint, and names `scheduled-community-monitor @ 0 8 * * *` as the surviving AC10 basis.
- **AC28** — `scripts/encryption-posture-ledger.json` classifies both new resource types, and `python3 scripts/lint-encryption-posture.py --repo-sweep` exits `0`. The `cloudflare_pages_project` `stores[]` row carries a `provider-managed:<AttestationName>` mechanism with an `attestation_url` and a `retrieved_on` within 365 days — the validator rejects a bare "provider-managed encryption at rest" string.
- **AC29** — the cutover apply is expressed as two targeted passes with the sequence asserted between them (PF-ORDER), and `-target=cloudflare_record.github_pages` is still present in the allow-list.

### PR2

- **AC15** — `deploy-docs.yml` publishes the same `_site` to **both** origins. The three GitHub Pages actions are **retained byte-identical to `main`**: `grep -cE '^\s*uses: actions/(configure-pages|upload-pages-artifact|deploy-pages)@' .github/workflows/deploy-docs.yml` equals `3`, and `git diff origin/main -- .github/workflows/deploy-docs.yml` contains no `-` line matching `uses: actions/.*pages`. The wrangler leg is added alongside: `grep -c 'wrangler pages deploy' .github/workflows/deploy-docs.yml` equals `1`. **Superseded 2026-09-02 (PR2).** The original AC15 required those three to reach `0`. Deleting the GitHub Pages leg before the apex moves would freeze the public apex at the last GitHub Pages build for the whole PR2→PR4 interval (measured: 14 docs-touching commits in 14 days, ~1/day), degrading this plan's own rollback target to a stale build — the outcome `## User-Brand Impact` classifies as brand-fatal. A rollback that lands in a brand-fatal state is not a rollback. The zero-assertion moves to AC33 and is owned by PR5.
- **AC16** — the five build gates other than build-verification are byte-unchanged, asserted by diffing each gate's step block against `origin/main`. The `permissions:` and `environment:` blocks are likewise **byte-unchanged** — they are retained (AC18). Permitted hunks in `deploy-docs.yml` are exactly: the workflow `name:`; one added line in `on.push.paths` (AC36); the container comment; the build step (build-identity stamp); one additive `test -f` line in build-verification; and the terminal-steps range, where the wrangler install/deploy steps, both build-identity probes and the publish-verdict step are **inserted around** the retained GitHub Pages trio. **Superseded 2026-09-02 (PR2):** the original enumeration was wrong in both directions — it omitted two hunks this plan's own Phase 2 items 2 and 4 mandate (the build stamp, the container-comment rewrite), and it named the `permissions:`/`environment:` blocks as edit sites when they are now retention sites.
- **AC17** — wrangler is pinned exactly: `grep -c 'wrangler@4\.124\.0' .github/workflows/deploy-docs.yml` equals `1`, and `grep -c 'wrangler@latest\|npx --yes wrangler' … || true` equals `0`.
- **AC18** — the `environment:` block is **retained and functional** through PR4: `grep -c 'name: github-pages' .github/workflows/deploy-docs.yml` equals `1`, and its `url:` still resolves from a live step id — `grep -c 'id: deployment' .github/workflows/deploy-docs.yml` equals `1`. `permissions:` retains `pages: write` and `id-token: write`, each carrying a comment naming PR5/AC33 as its removal point so neither reads as a leftover standing privilege. **Superseded 2026-09-02 (PR2)** — the original required `github-pages` to be absent. The removal assertion is AC33.
- **AC19** — **two** post-deploy build-identity probes exist and **both fail the job on a SHA mismatch**, each exercised by a run where the expected SHA is deliberately wrong (`apps/web-platform/infra/pages-build-identity-probe.test.sh`, case M2). Arms per AP-021, in `pages-build-identity-probe.sh`: `200 + match` → rc 0; `200 + mismatch` → rc 1; non-2xx → rc 3 (ABSENT); no HTTP response → rc 2 (UNREACHABLE, the only tolerated arm). **Probe A** targets `https://soleur-docs.pages.dev/version.txt` — measured 2026-09-02 this returned `522`, which is what a zero-deployment Pages project looks like and is the ABSENT arm firing correctly. **Probe B** targets `https://soleur.ai/version.txt?cb=${GITHUB_SHA}` with a 10×15s window. The cache-buster is load-bearing: the apex measured `cache-control: max-age=600`, `age: 279`, `x-cache: HIT`, `via: 1.1 varnish`, so an un-busted probe would read a cached body and report MISMATCH on a healthy deploy.
- **AC20** — `https://soleur-docs.pages.dev/version.txt` equals the merge SHA (PF5).
- **AC21** — the cutover runbook exists, states that `workflow_dispatch` cannot perform the rollback, carries the content-rollback procedure, and **records the PF7 disposition** — namely that the detach measurement was deliberately NOT taken because the four-PR split retires D3 item 3(b) by construction, together with what to do if the rollback reaches the case PF7 would have measured. **Superseded 2026-09-02 (PR2):** the original required the runbook to record "the PF7 detach measurement", a deliverable that by this plan's own amendment no longer exists.

- **AC31 (PR2)** — the bimodal failure is resolved by **conjunction**, never by abort-on-first. Each publish step carries `continue-on-error: true` and a step `id:`; the wrangler leg and both probes carry `if: always()`; a terminal publish-verdict step reads `steps.<id>.outcome` for all four legs and exits 1 unless every one is `success`, printing a per-leg table to `$GITHUB_STEP_SUMMARY`. **`outcome`, not `conclusion`** — `continue-on-error` rewrites `conclusion` to `success`, so a verdict reading it would pass vacuously.

- **AC32 (PR2)** — the runbook carries a **dual-publish** section stating: both origins publish every run; the GitHub Pages leg is the rollback target and is kept current for that reason; `https://soleur.ai/version.txt` and `/CNAME` are publicly served static files and are not leaks; and that a `deploy-docs.yml` run occurring **between the PR4 apply and the PR5 merge** may go red on the GitHub-Pages leg alone (GitHub's custom-domain DNS check fails once the apex `A` records are gone) — expected and benign, remedied by merging PR5, not by debugging.

- **AC33 (PR5)** — the GitHub Pages publish path is retired: the three-action grep equals `0`; `! grep -q 'github-pages'`; `! grep -qE '^\s*(pages|id-token): write'`; the verdict step's GitHub-Pages arm is removed. **Probe B survives** — post-PR4 it asserts the apex serves the current build through Cloudflare Pages, i.e. CUT0 made permanent.

- **AC34 (PR5)** — PR5 merges **after CUT0-CUT9 all hold**, in the same session as PR4, and its own merge run of `deploy-docs.yml` is green with Probe B MATCH.

- **AC35 (PR2)** — `https://soleur.ai/version.txt` equals the PR2 merge SHA (the apex sibling of AC20), sampled with the cache-busting query string.

- **AC36 (PR2)** — the workflow self-trigger exists: `grep -cF '.github/workflows/deploy-docs.yml' .github/workflows/deploy-docs.yml` returns `1` from inside `on.push.paths`, and `gh run list --workflow=deploy-docs.yml --json headSha` contains PR2's merge SHA. Asserted on an actual run, not on the YAML alone.

### PR3 — the attach, and its gate

**PR3-GATE.** The Delivery Sequencing cell previously cited *"PF9 (R8 probe + origin headers
matching the branch PF-Z established)"*. All three components were unusable: PF9 is PR4's
`dns.tf` plan shape (4 deletes + 1 create); the R8 probe is PF3, assigned to PR1 where the
attachment did not exist so it was structurally unrunnable; and PF-Z was never measured. The
cell named three things that do not exist. Replaced by:

| # | Assertion | When |
|---|---|---|
| PR3-G1 | The last `deploy-docs.yml` run on `main` is `success` with both build-identity probes `success`, and its `headSha` is `main`'s tip. `gh run list --workflow=deploy-docs.yml --branch main --limit 1 --json conclusion,headSha`. **This is what makes the attach safe** — "the Pages project is current" is a per-run property, and merging PR3 does not fire `deploy-docs.yml`, so without this the apex could adopt a stale build under Z-true. | pre-merge, blocking |
| PR3-G2 | **R8, measured for the first time.** `GET /zones/$ZONE/dns_records?name=soleur.ai` returns exactly the four `A` records and no new `CNAME`; `?name=www.soleur.ai` returns exactly the one `CNAME`. This is PF3 relocated to the only PR where it can run. **PR4 cannot be written until this is measured** — if the attach auto-creates a record, `cloudflare_record.pages_apex` becomes an `import`, not a `create`, and PF9's expected shape changes under the operator's `[ack-destroy]`. | post-apply, blocking |
| PR3-G3 | Which branch of Z obtains: the post-apply step in `apply-web-platform-infra.yml` records `apex-origin-probe.sh`'s verdict. Reporting-only — both verdicts are legitimate. Pair it with `curl -s 'https://soleur.ai/version.txt?cb=<nonce>'` equalling the SHA Probe B last asserted, because `SERVING-FROM-CLOUDFLARE-PAGES` is a residual verdict and alone cannot distinguish "the right project at the right build" from "not GitHub". | post-apply, reporting |

### PR3 (superseded numbering below)

- **AC22** — CUT0 through CUT9 all hold under the 3-sample rule, recorded with measured output.
- **AC23** — a `workflow_dispatch` run of `deploy-docs.yml` publishes a change and `https://soleur.ai/version.txt` reflects the new SHA. (Asserted by an explicitly dispatched run, not by waiting on an unrelated future commit — `cq-ac-must-not-depend-on-concurrent-sessions`.)
- **AC24** — the deferred-cleanup issue exists and carries its re-evaluation criteria, including that `ssl = "full"` must remain in place while the rollback window is open.

### PR4 — the DNS cutover (PR4a shrink, PR4b flip)

**Numbering note.** AC22/AC23/AC24 sit under the heading *"PR3 (superseded numbering below)"*
and are **PR4's** — written when PR3 was the cutover. They are not renumbered
(`cq-rule-ids-are-immutable` in spirit: a cited id that moves is worse than one oddly placed),
but they are claimed here. **AC29 likewise sits under `### PR1` and was never delivered there.**

**AC29 is RETIRED, not carried.** It asserted *"the cutover apply is expressed as two targeted
passes with the sequence asserted between them (PF-ORDER)"*. Under D5 there are no targeted
passes: ordering comes from Terraform core at a single resource address. AC29's **intent** —
that the ordering property be asserted rather than assumed — is discharged by AC63 (no
`create_before_destroy`) and AC64 (the moved-index pin). Retiring it explicitly is the point;
an AC left standing against a mechanism that no longer exists is the AC29 failure repeating.

**Also retired with the pre-pass:** AC37, AC38, AC39, AC40, AC41, AC42 and AC54 as drafted
earlier in this pass. They asserted the plan-JSON gate, its battery, its `test-all.sh`
registration, the workflow-order guard, the two-plane between-assert and the inter-pass
duration. None of those artifacts exists under D5. AC38's own defect — naming M1-M9 against an
eleven-row matrix — is recorded in `## Sharp Edges` rather than lost with it.

#### PR4a — pre-merge

- **AC63** — `dns.tf`'s `cloudflare_record.github_pages` `for_each` is exactly
  `toset(["185.199.108.153"])`, and `cloudflare_record.www` and
  `cloudflare_record.github_pages_challenge` are byte-unchanged from `origin/main`
  (`git diff origin/main -- apps/web-platform/infra/dns.tf` shows no `-` line matching either).
- **AC64** — `terraform plan` shows exactly 3 deletes, **0 creates**, `destroy_count = 3`, and
  zero changes to the rulesets, zone settings and apex MX/TXT (PF9a).
- **AC65** — Guard 2 (`apex-single-node-replace.test.sh`) ships in **PR4a** and is green on the
  PR4a shape (harness row H3). It is registered in `infra-validation.yml`, anchored on the
  invocation rather than a file-wide substring:
  `grep -cE '^\s*run: bash apps/web-platform/infra/apex-single-node-replace\.test\.sh$' .github/workflows/infra-validation.yml`
  equals `1`. **Measured:** the file-wide form returns **2** for the sibling guard
  (a `paths:`-block comment at `:77` plus the run line at `:1071`), so a correct, well-commented
  registration would fail a file-wide `equals 1` — the same bare-token class as AC5's
  `_challenge` collision.
- **AC66** — every row of Guard 2's matrix drives it red: **M1-M9**, plus harness rows **H1
  (must fail), H2 (must pass, reflowed) and H3 (must pass, PR4a shape)**. Stated as the explicit
  range, re-derived from the matrix rather than recalled.

#### PR4b — pre-merge

- **AC67 (the ordering property, asserted rather than assumed — PF-ORDER relocated)** —
  `cloudflare_record.pages_apex` carries **no** `create_before_destroy`. Asserted on the
  resource block, not the file:
  `n=$(awk '/resource "cloudflare_record" "pages_apex"/,/^}/' apps/web-platform/infra/dns.tf | grep -c 'create_before_destroy' || true); [ "$n" = "0" ]`.
  This is the whole of what keeps Terraform core's Delete→Create serialisation in place; adding
  the flag silently restores the `81053` hazard and nothing else in CI would notice.
- **AC68 (the silent-failure pin)** — the `moved` block's `from` index literal is byte-identical
  to the `for_each` key PR4a left behind, asserted mechanically by Guard 2 M3. **A mismatch does
  not error** — Terraform no-ops a move against absent state, so `pages_apex` would plan as a
  bare create while the survivor plans as a separate delete: two addresses, concurrent, hazard
  restored, **no signal**. This AC exists because nothing else in the system can see it.
- **AC69** — `terraform plan` shows **one** address, `cloudflare_record.pages_apex`, actions
  `["delete","create"]`, carrying the `(moved from cloudflare_record.github_pages["…"])`
  annotation; plus the in-place `www` update. Through the real filter
  (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`):
  `resource_deletes: 1, nested_deletes: 0, reboot_updates: 0, host_creates: 0` (PF9b).
- **AC46 (upgraded rationale, unchanged command)** — **both** endpoint targets are present,
  line-anchored:
  `grep -cE '^[[:space:]]+-target=cloudflare_record\.github_pages \\$' .github/workflows/apply-web-platform-infra.yml`
  equals `1`, and likewise for `-target=cloudflare_record\.pages_apex \\$`.
  **The rationale changes and is stronger than D4's.** D4 said keeping the old address matters
  *"or the destroy is never planned"*. Measured: a `moved` block with only one endpoint in the
  `-target` set makes the apply **hard-error** with `Error: Moved resource instances excluded by
  targeting`. The bare-substring form returns **2** because of the `_challenge` prefix sibling,
  so the anchor is load-bearing (AC5 addendum, measured).
- **AC43** — `cloudflare_record.pages_apex` is declared with `name = "soleur.ai"` (never `@`),
  `type = "CNAME"`, `content = cloudflare_pages_project.docs.subdomain`, `proxied = true`,
  `ttl = 1`. **The resource reference survives this design** — there is no scoped pre-pass plan
  to drag `cloudflare_pages_project.docs` into a `-target` scope, so the literal-vs-reference
  trade the pre-pass forced does not arise. **Caution:** Phase 4b.1 rewrites the contract
  comment; keep it in **dot-notation** (`cloudflare_record.github_pages`), because a comment
  quoting the declaration verbatim would false-fail the `github_pages` absence grep.
- **AC44 (Camp B)** — `cloudflare_record.www` is still `type = "CNAME"`; only `content` changed.
  `awk '/resource "cloudflare_record" "www"/,/^}/' apps/web-platform/infra/dns.tf | grep -cE '^\s*type\s*=\s*"CNAME"'`
  equals `1`, and that block has no `type = "A"`. **Verified 2026-09-03:** the resource name
  matches exactly once and the awk range does not self-close (the opening line does not match
  `/^}/`). `type` is ForceNew at 4.52.7 (measured), so an `A` here would be a second replacement
  racing the first.
- **AC70 (the rollback-PR generator)** — it exists, is unit-tested over PR4b's real diff, and its
  strongest assertion holds: the generated `dns.tf` is **byte-identical to `dns.tf` as PR4a left
  it**. The reverse block's `from`/`to` are swapped, `type` returns to `"A"`, `content` returns
  to the surviving IP literal.
- **AC71 (`git revert` is forbidden, in the imperative, at the step)** — the runbook's rollback
  **step itself** — not a notes section — states that `git revert` is the WRONG lever for PR4b,
  and why: measured, it produces
  `# cloudflare_record.github_pages["185.199.108.153"] will be created` /
  `# cloudflare_record.pages_apex will be destroyed`, two unrelated addresses dispatched
  concurrently, reproducing `81053` **on an apex that is already broken**. The obvious,
  muscle-memory action is the dangerous one, which is exactly why the prohibition goes where the
  hand reaches, not where the reader browses.
- **AC48 (`ssl = "full"` stays)** — `grep -c 'ssl *= *"full"' apps/web-platform/infra/seo-config-rules.tf`
  equals `1`, and `git diff --stat origin/main -- apps/web-platform/infra/seo-config-rules.tf`
  is **empty** — PR4 does not touch that file. **PR #7753 owns that rule's guard; its work is
  not co-located here and the setting is not removed.**
- **AC49** — PF-Z2, PF-R8b and PF-SYM are run within the hour before PR4b merges and their
  measured output recorded. Asserted by re-running the probes, never by text in a PR body.
- **AC59** — the `## Observability` `discoverability_test.expected_output` flips from
  `SERVING-FROM-GITHUB-PAGES` to `SERVING-FROM-CLOUDFLARE-PAGES` **in PR4b's own hunk**.
- **AC61** — `apex-origin-probe.sh` requests a cache-busted URL
  (`grep -cE 'cb=|cache-bust' apps/web-platform/infra/apex-origin-probe.sh` `>= 1`), and its
  three-verdict vocabulary plus both AP-021 `UNREACHABLE` arms are unchanged from `main`.
- **AC62** — `cutover-verify.sh` exists, reports `UNREACHABLE` distinctly from a failed
  assertion, and CUT9's baseline is a committed sorted fixture rather than prose in a document
  PR5 archives.
- **AC50** — the runbook records: the two-merge procedure; the `git revert` prohibition at the
  rollback step; the **two-step** rollback (generated reverse PR → probe → revert PR3 only if
  still `SERVING-FROM-CLOUDFLARE-PAGES`); PF8′; the residual mid-replace window and its recovery
  (*"if the apply dies mid-replace, re-run the failed job — the plan is a bare create and passes
  the destroy-guard unacked"*); the concurrency-queue cost against the T+20 budget; and
  `Hypothesis Z measured FALSE 2026-09-03` in place of the PF7 wording.
- **AC51** — ADR-194 carries the amendment: Z falsified with its measurement, **single-address
  replace ordered by Terraform core** (not a two-pass apply), the `git revert` finding, and the
  rejected alternatives with the one fact that disqualifies each. **An amendment, no new
  ordinal.**
- **AC52 (PF-DEFER)** — the deferred-cleanup issue is verified to exist by number before PR4b is
  marked ready, or filed. **A 2026-09-03 `gh issue list` search did not surface it**; an
  unverified issue reference is not evidence (`hr-before-asserting-github-issue-status`).

#### Post-merge (automated, in PR4b's merge steps — none is an operator action)

- **AC53 (PF8′)** — within minutes of the merge, the **generator** produces an open rollback PR
  carrying `[ack-destroy]` for its own squash message, green and mergeable **before the T+20
  decision point**. **This is PF8 resolved, not deferred** — the pre-opened revert the brief
  asked for, with a mechanism that survives measurement. Assert the ack by reading the branch's
  commit body (`git log -1 --format=%B`), **not** by `gh pr view --json state,mergeable`: none
  of those fields can see a commit or PR body, and the ack landing in the squash body is the
  single point of failure for the entire rollback.
- **AC60 (the ack-wedge criterion — the sibling of AC30)** — after **each** of PR4a and PR4b,
  the `[ack-destroy]` line is verified to have landed in the squash body:
  `git log -1 --format=%B <merge-sha>` matches `(^|\n)\[ack-destroy\]($|\n)`. The squash message
  does not exist until merge time, so PF10 is an intention and this is the fact. If the ack
  misses, the apply aborts with the destroys still pending — and **every subsequent merge
  touching `apps/web-platform/infra/**`, by anyone, on any unrelated change, re-plans the same
  destroys and aborts too**, serialized behind `concurrency: terraform-apply-web-platform-host`.
  That is a repo-wide infra freeze, the class AC30 exists to prevent for a missing `TF_VAR_*`.
  **Remediation, stated so nobody derives it under pressure:** push a commit to `main` whose
  message carries `[ack-destroy]` on its own line — the guard reads the pushed head commit, so
  the next apply proceeds.
- **AC22 (claimed for PR4b)** — CUT0′ through CUT9 all hold under the 3-consecutive-clean-
  samples-at-60 s rule beginning 5 minutes after the apply, run by `cutover-verify.sh`, with
  `UNREACHABLE` reported as a distinct verdict.
- **AC23 (claimed for PR4b)** — a `workflow_dispatch` run of `deploy-docs.yml` publishes and
  `https://soleur.ai/version.txt?cb=<nonce>` moves to the new SHA. **Satisfied by the per-leg
  table, never by the run conclusion** — post-cutover the GitHub Pages leg necessarily fails
  GitHub's custom-domain DNS check and AC31's verdict step is a conjunction, so the run is red
  overall by construction until PR5.

### PR5 — retire the GitHub Pages publish leg

- **AC33** — (as written above) the three-action grep equals `0`; `! grep -q 'github-pages'`;
  `! grep -qE '^\s*(pages|id-token): write'`; the verdict step's GitHub-Pages arm is removed;
  **Probe B survives**.
  **Exit-safety correction 2026-09-03 — AC33 is the one in-scope AC that violates this
  section's own preamble.** The three-action grep returns `3` today, and `grep -c` **exits 1**
  when the count reaches `0`, so `grep -c … equals 0` aborts under `set -e` on a *correct*
  PR5. Use the guarded form:
  `n=$(grep -cE '^\s*uses: actions/(configure-pages|upload-pages-artifact|deploy-pages)@' .github/workflows/deploy-docs.yml || true); [ "$n" = "0" ]`.
  The two `! grep -q` forms are already sound — measured: `github-pages` has exactly one hit
  (`deploy-docs.yml:51`) and the write permissions are at `:38-39`.
- **AC34** — PR5 merges **after** CUT0-CUT9 all hold, in the same session as PR4, and its own
  merge run of `deploy-docs.yml` is green with Probe B MATCH.
- **AC55** — the two genuinely **anticipatory** phrasings in `model.c4` are in the completed
  tense, asserted by command:
  `n=$(grep -cF 'until the #7640 cutover' knowledge-base/engineering/architecture/diagrams/model.c4 || true); [ "$n" = "0" ]`
  and the same for `From the cutover`; and
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
  **Scoped down 2026-09-03.** An earlier draft also named the `cloudflare` element's
  *"from #7640/ADR-194"* — measured at `model.c4:250`, that string is a **provenance
  citation** ("this role arrived via #7640"), not anticipatory tense. Stripping it would
  delete a content anchor the repo's own citation convention wants kept
  (`cq-cite-content-anchor-not-line-number`). Only `:236` (*"until the #7640 cutover"*) and
  `:297` (*"From the cutover…"*) are in scope.
- **AC56** — the runbook states that PR5 **narrows the rollback**: the GitHub Pages content
  freezes at the last PR4-era build, and restoring that origin afterwards takes three acts
  (re-add the publish leg, redeploy, revert DNS), not one. The same line is added to the
  deferred-cleanup issue's re-evaluation criteria.
- **AC57** — `Ref #7640` in PR5's body, **not** `Closes` — #7640 is already closed by PR4, and
  a second closer is noise.
- **AC58** — the plan is archived by `archive-kb.sh` **in PR5 and not before**, and the runbook
  cites the archived path.

Repo-wide: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits `0`
(the gate's own invocation, not a hand-enumerated path list), and
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.

## Domain Review

**Domains relevant:** Engineering, Marketing, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Risk concentrates in sequencing, and the three-PR split is what makes the
plan's own verification order physically achievable. The `production_branch` / `--branch`
coupling is the subtlest trap — two independent magic strings in HCL and YAML with no
compiler between them; Guard 1 M7 now covers it. The deferred cert-reissue subsystem was the
one item that becomes *actively dangerous* rather than merely stale at cutover, and it is now
an in-scope deliverable. `npx --yes wrangler@<major>` was the single unpinned vendor surface
in a workflow that publishes the public site, against a workflow that digest-pins its
container; it is now exact-pinned via the repo's own adjacent precedent.

### Marketing (CMO / SEO)

**Status:** reviewed
**Assessment:** Canonical direction stays apex, enforced by three independent mechanisms that
all survive: the Bulk Redirect 301, the canonical-host build gate, and
`sentry_uptime_monitor.soleur_www`. The SEO redirect corpus is untouched, so no indexed URL
changes shape. Path preservation on the www 301 is load-bearing (CUT4) — a bare collapse to
the apex would turn every indexed www deep link into the "Page with redirect" cluster in
Search Console. The static-asset `Cache-Control` change is now a deliberate accepted change
rather than a regression to reverse: because filenames are not content-hashed, Pages'
`must-revalidate` default propagates a docs fix immediately where GitHub Pages' 4-hour window
would not.

### Operations (COO)

**Status:** reviewed
**Assessment:** No new vendor and no new recurring cost. Cloudflare is already both vendor and
sub-processor; Pages Free is `$0` at 500 builds/month (direct-upload consumes none), 100 custom
domains, 20,000 files, 25 MiB per file. No expense-ledger entry required. The operational
surface shrinks by one certificate lifecycle. One new operational obligation is created and
named: the Pages token now exists in three places with a single rotation.

### Product/UX Gate

**Tier:** none
**Rationale:** the mechanical UI-surface override does not fire. No path in Files to
Edit/Create matches the glob superset in `ui-surface-terms.md` — no `.njk`, `.html`, `.tsx`,
`.vue`, `.svelte`, `.astro`, no `components/**`, no `app/**/page.tsx`. `404.njk` is verified,
not edited. The rendered site is byte-identical; only the host serving it changes. No wireframe
required.

### GDPR / Compliance (Phase 2.7)

**Assessment:** skipped with reason. The canonical regulated-data regex does not match — no
`.sql`, no `supabase/migrations/`, no auth flow, no API route. None of the four expansion
triggers fire: no new LLM/external-API processing of session-derived data; the
`single-user incident` threshold here is an availability threshold, not a personal-data one;
no new cron or workflow reads `learnings/` or `specs/`; no new artifact-distribution surface —
the docs site is already public. Recorded for completeness: visitor request logs move from
GitHub's edge to Cloudflare's; both are existing sub-processors under the current DPA set, so
no Article 30 entry and no DPA change is triggered. ADR-194 reaches the same conclusion
independently.

## Infrastructure (IaC)

### Terraform changes

| File | Change | Provider / alias | PR |
|---|---|---|---|
| `cf-pages.tf` (new) | `cloudflare_pages_project.docs`, `cloudflare_pages_domain.apex`, two `github_actions_secret` | `cloudflare.pages` (new), `github` | 1 |
| `main.tf` | `cloudflare` alias `pages` bound to `var.cf_api_token_pages` | — | 1 |
| `variables.tf` | `cf_api_token_pages` — sensitive, no default, description is the scope ledger | — | 1 |
| `seo-bulk-redirects.tf` | `cloudflare_list.www_canonical` + a second ordered rule | `cloudflare.rulesets` | 1 |
| `dns.tf` | apex `A`×4 → apex `CNAME` (`cloudflare_record.pages_apex`); www `content` retargeted to the Pages project, staying a proxied `CNAME` (**in-place update**, not a replace) | default `cloudflare` | 3 |

Provider pin unchanged: `cloudflare/cloudflare ~> 4.0` (4.52.7). All new HCL uses **v4 block
syntax**; registry `latest` documents v5 attribute-set syntax and must not be copied.
Terraform `>= 1.7`.

Sensitive variable `TF_VAR_cf_api_token_pages` from Doppler `soleur/prd_terraform` key
`CF_API_TOKEN_PAGES` via `--name-transformer tf-var`. No default, and Terraform resolves all
root variables before `-target` pruning, so it must be live before PR1 merges.

### Apply path

**Path (b): existing auto-applied root, extended.** `apply-web-platform-infra.yml` fires on
merge touching `apps/web-platform/infra/**` and applies against the `-target=` allow-list. No
new Terraform root, no new backend — R2 already exists in this root (`use_lockfile = false`;
the shared GitHub Actions concurrency group is the sole serializer).

Blast radius is concentrated in PR3: a **4-delete + 1-create + 1-in-place-update** plan on the public
apex. Expected exposure is the proxied-record propagation window (TTL fixed at 300 s), during
which both origins serve identical content because the GitHub Pages configuration is retained
and the Pages project is already live and verified. That overlap is the reason PR1/PR2 precede
PR3 rather than sharing a merge.

`destroy_count > 0` fails the apply without a `[ack-destroy]` line in the merge commit —
expected and correct. PF9 is what makes acking it safe, by pinning the exact plan shape first.

**Amended 2026-09-03 (PR4) — the apply path is path (b) EXTENDED WITH AN ORDERED SEQUENCE, and
the blast-radius paragraph above was written under the three-PR numbering.** Two corrections:

1. The 4-delete + 1-create + 1-in-place-update plan is **PR4's**, not PR3's. PR3 is
   0 destroys and needs no `[ack-destroy]`.
2. *"Both origins serve identical content during the propagation window"* is true only for
   resolvers that never observe the **gap**. With Hypothesis Z falsified, the transition passes
   through a state where the apex carries no address record at all; a resolver querying inside
   that window gets NODATA and negative-caches it for up to 1800 s. D5's ordered pre-pass is
   what bounds the gap to two API calls; the overlap argument does not cover it.

The path stays path (b) — no new Terraform root, no new backend, no dispatch surface, and the
merge remains the human authorization (`hr-menu-option-ack-not-prod-write-auth`). What is new
is that a **single logical change is applied as three scoped applies with an assertion between
the first and the second**, inside one workflow run. Everything else on this root is unaffected:
the pre-pass's scoped plan is a no-op on every merge that is not the cutover or its revert, and
it exits without applying anything.

### Distinctness / drift safeguards

- `name = "soleur.ai"`, never `@` — the API normalizes `@` to FQDN and `name` is ForceNew.
- `content = cloudflare_pages_project.docs.subdomain` is a resource reference, so Terraform holds the edge.
- PF3 probes whether the custom-domain attachment auto-created a DNS record (R8); if it did, `dns.tf` becomes an `import`, not a create.
- No new ruleset phase, so ADR-136's pre-apply entrypoint gate is not newly engaged; the account `http_request_redirect` entrypoint is already Terraform-owned, so the create-from-absent discriminator does not match there either.
- The token value lands in `terraform.tfstate` (R2, encrypted at rest, credentials distinct from every Cloudflare API token in this root).
- `seo_page_redirects`, `seo_config_settings`, `zone_settings_override` and the apex MX/TXT records are asserted unchanged (AC6, AC7, AC13, CUT9).

### Encryption-posture ledger (a fail-closed CI gate this plan must satisfy)

`.github/workflows/ci.yml` runs `python3 scripts/lint-encryption-posture.py --repo-sweep`,
which scans `apps/*/infra/**/*.tf` for every `resource "<type>"` and partitions each type into
`store_classes` or `non_store_types` in `scripts/encryption-posture-ledger.json`. An unknown
type is a deterministic failure:

```
FAIL: unknown resource type <type> (at <addr>) -> add <type> to store_classes or non_store_types
```

Neither `cloudflare_pages_project` nor `cloudflare_pages_domain` is in that ledger today
(verified). **Creating `cf-pages.tf` therefore reddens CI on both new types until the ledger
is updated**, and no other gate in this plan would have surfaced it.

Both are classified in `scripts/encryption-posture-ledger.json` in PR1:

- `cloudflare_pages_project` → **`store_classes`**. It is a persistent store of published
  bytes; classifying it as a non-store would be a false statement about what it holds. Its
  `stores[]` row must satisfy the validator's shape, which the `## Encryption Posture` prose
  above does **not** yet meet: a `provider-managed:<AttestationName>` mechanism requires an
  `attestation_url` **and** a `retrieved_on` no older than 365 days. A bare "provider-managed
  encryption at rest" string is a literal reject.
- `cloudflare_pages_domain` → **`non_store_types`**. It is a hostname attachment; it holds no
  bytes.

### Vendor-tier reality check

Cloudflare Pages Free: 500 builds/month (direct-upload consumes none), 1 concurrent build,
20,000 files, 25 MiB max file, 100 custom domains, unlimited bandwidth. Bulk Redirects Free:
15 rules, 5 lists, 10,000 URL redirects. Single Redirects Free: 10 rules per zone (the cap this
plan works around). The site is well inside every limit. No `count = var.*_paid_tier` gate needed.

## Observability

```yaml
liveness_signal:
  what: sentry_uptime_monitor.soleur_apex (GET https://soleur.ai/ asserts 200),
        sentry_uptime_monitor.soleur_www (GET https://www.soleur.ai/ asserts 301),
        sentry_uptime_monitor.soleur_changelog_deep (GET https://soleur.ai/changelog/ asserts
        2xx — the only DEEP-PATH apex monitor, guarding "root serves 200 but every other page
        404s"), sentry_uptime_monitor.soleur_acme_probe (asserts 404), and the independent
        second source betteruptime_monitor.soleur_apex
  cadence: 300 s (Sentry, 300 s confirmation) / 180 s (Better Stack)
  alert_target: Sentry issue alert -> notify_email IssueOwners with ActiveMembers
        fallthrough; Better Stack -> managed recipient email. Two independent vendors
        by design (observability layer: vendor uptime probes, ADR-031).
  configured_in: apps/web-platform/infra/sentry/uptime-monitors.tf,
        apps/web-platform/infra/uptime-alerts.tf

error_reporting:
  destination: deploy-docs.yml fails the job on a non-zero wrangler exit AND on a
        post-deploy custom-domain SHA mismatch; the workflow's Sentry cron monitor
        (apps/web-platform/infra/sentry/cron-monitors.tf) opens an issue on a missed or
        failed check-in.
  fail_loud: true — the monitor pause/resume block runs its resume under `if: always()`,
        so a failed deploy never strands soleur-ai-www paused.

failure_modes:
  - mode: deploy lands on a preview alias because --branch != production_branch, so the
        custom domain keeps serving the previous build while CI is green
    detection: the post-deploy probe reads https://soleur.ai/version.txt (the CUSTOM
        DOMAIN, not *.pages.dev) and compares it to ${GITHUB_SHA}. A content-identity
        predicate, not a header proxy — a header proxy is present on every deployment of
        the project including a stale one, so it cannot discriminate.
    alert_route: deploy-docs.yml job failure.
  - mode: www stops 301-ing
    detection: sentry_uptime_monitor.soleur_www asserts 301, not 2xx. Under D1's chosen
        design www IS attached to the Pages project, so a missing redirect serves a duplicate
        copy of the site at 200 — which is exactly what the 301 assertion catches, within one
        confirmation period. (The rejected 192.0.2.1 variant would hard-fail instead; both are
        caught by this same monitor, which is why the failure-mode severity, not detectability,
        decided D1.) Second and third nets: the canonical-host build gate and the apex
        <link rel="canonical">.
    alert_route: Sentry issue alert -> email.
  - mode: the retained cert-reissue routine fires post-cutover and de-proxies www one-way
    detection: the D2 apex-topology precondition refuses the run and emits a non-benign
        terminal outcome; the existing proxy_restore_failed page remains as backstop.
    alert_route: Sentry issue alert -> email.
  - mode: apex serves from the wrong origin after a partial rollback
    detection: the origin-provenance probe below, which distinguishes three states
        (GitHub / Cloudflare / UNREACHABLE) rather than folding transport failure into a
        definite answer (AP-021).
    alert_route: run on demand; CUT2 is the cutover-time gate.
  - mode: token revoked -> every docs deploy fails
    detection: wrangler exits non-zero; the workflow's Sentry cron monitor opens an issue.
        event-cf-token-expiry-check covers CF_API_TOKEN only, which is why this token is
        minted with NO expiry — recorded in the scope ledger and on the deferred issue.
    alert_route: Sentry cron monitor -> issue -> email.
  - mode: apex mail/verification records disturbed by the A->CNAME transition
    detection: CUT9 compares dig MX/TXT against the recorded Phase 0 baseline.
    alert_route: cutover gate; rollback on mismatch.

logs:
  where: GitHub Actions run logs for the deploy path; Cloudflare Pages deployment history;
        Sentry issues for monitor failures.
  retention: GitHub Actions 90 days; Sentry per org plan; Cloudflare Pages deployment
        history retained by Cloudflare.

discoverability_test:
  command: bash apps/web-platform/infra/apex-origin-probe.sh
  expected_output: "SERVING-FROM-GITHUB-PAGES"
```

**Amended 2026-08-25.** The command was inline and preflight Check 10 could not run it, in
two independent ways. Structurally it carried `$(`, `|` and `;`, which Check 10's shell-active
token reject refuses before execution — the sanctioned remedy is a repo-relative script, so the
probe now lives at `apps/web-platform/infra/apex-origin-probe.sh` and is committed rather than
ad-hoc. Semantically its `expected_output` asserted the POST-cutover origin, so on a four-PR
migration every run before the cutover reported a mismatch: the check could only ever fail
until the last PR landed.

`expected_output` therefore tracks the CURRENT stage and is `SERVING-FROM-GITHUB-PAGES` through
PR1-PR3. **PR4 flips it to `SERVING-FROM-CLOUDFLARE-PAGES` as part of the cutover hunk** — that
flip is the cutover's own assertion, and until it happens an unexpected Cloudflare verdict means
the origin moved without the record swap, which is exactly what we want to hear about.

The plan previously recorded that an earlier ad-hoc version of this probe "failed open, printing
the success verdict for an unreachable site" and had been "hardened and verified across all four
arms". That hardening existed only as this sentence — no script was committed. It is now real
and re-verified: live -> `SERVING-FROM-GITHUB-PAGES` rc 0; bad host -> `UNREACHABLE (transport)`
rc 2; reachable non-200 -> `UNREACHABLE (status not 200)` rc 2; shellcheck clean.

The probe is unauthenticated, runs from any laptop or runner, reaches no private network, and
its first token is `bash` (on the preflight Check 10 allowlist). `credentials_required` is
deliberately absent — which origin serves the apex is fully observable from a public request.

**Verified across all four arms, 2026-08-20:** GitHub-Pages apex → `SERVING-FROM-GITHUB-PAGES`;
a live Cloudflare Pages host → `SERVING-FROM-CLOUDFLARE-PAGES`; an unreachable host →
`UNREACHABLE (transport)`; a reachable non-200 → `UNREACHABLE (status not 200)`. The naive
one-liner without the status capture printed `SERVING-FROM-CLOUDFLARE-PAGES` for an unreachable
host — a fail-open that collapses "could not check" into the *success* verdict, the worse
direction under AP-021.

### PR4/PR5 additions (2026-09-03, rewritten for the single-node-replace design)

The earlier draft of this block described the pre-pass's failure modes, and two of its
`alert_route` lines were **wrong even for that design** — they claimed the apex "still carries
its four A records" on a between-assert failure, when the between-assert ran *after* the destroy
pass. Both the mechanism and the errors are gone; what follows is written against what D5
actually ships.

```yaml
failure_modes:
  - mode: the apply dies mid-replace on PR4b — the provider's Delete lands, the Create fails
        (token expiry, CF 429/5xx, CNAME-at-apex validation). The apex carries no address
        record; HSTS preload forbids an HTTP fallback; NODATA negative-caches against the
        1800 s SOA minimum
    detection: the apply job fails; notify-apply-failure opens the standard notification.
        cutover-verify.sh's CUT1 reports the apex non-200 within one sampling round.
    alert_route: apply-job failure. RECOVERY IS RE-RUNNING THE FAILED JOB — measured: the
        re-plan is a BARE CREATE of cloudflare_record.pages_apex, which scores
        resource_deletes 0 through destroy-guard-filter-web-platform.jq, is not in the jq's
        five nested_deletes classes, is not an hcloud_server, and is OUT of the pre-apply
        entrypoint gate's scope. So it applies with NO ack and no bespoke machinery. The
        runbook carries this line verbatim.
  - mode: someone later adds create_before_destroy to cloudflare_record.pages_apex, silently
        restoring the 81053 hazard by inverting the order Terraform core would otherwise
        guarantee
    detection: Guard 2 row M1, a static assertion over the resource block, run from
        infra-validation.yml on any PR touching apps/*/infra/**.
    alert_route: PR-time CI failure, before merge.
  - mode: PR4b's moved.from index does not match the for_each key PR4a left behind
    detection: Guard 2 row M3. THIS IS THE ONLY DETECTION THERE IS — Terraform does not error,
        it no-ops the move against absent state, and the plan then carries two addresses
        (a bare create plus a separate delete) with the concurrency hazard restored and no
        signal whatsoever.
    alert_route: PR-time CI failure, before merge.
  - mode: a moved endpoint leaves the apply allow-list
    detection: Guard 2 rows M5/M6, line-anchored so the github_pages_challenge prefix sibling
        cannot satisfy them. Measured consequence if it reaches an apply:
        `Error: Moved resource instances excluded by targeting` — a hard error, not a mis-plan.
    alert_route: PR-time CI failure, before merge.
  - mode: the [ack-destroy] line misses the squash body on PR4a or PR4b, and the pending
        destroys then abort EVERY subsequent infra merge repo-wide
    detection: AC60 reads the merge commit body directly (git log -1 --format=%B).
    alert_route: apply-job failure on this and every following infra merge, serialized behind
        concurrency: terraform-apply-web-platform-host. Remediation: push a commit to main whose
        message carries [ack-destroy] on its own line.
  - mode: a rollback is attempted with `git revert` instead of the generator
    detection: AC71 puts the prohibition in the runbook's rollback STEP, in the imperative.
        Measured plan for the revert: two unrelated addresses, 1 create + 1 destroy, dispatched
        concurrently — the reverse-direction 81053, on an apex that is already broken.
    alert_route: there is no automated detector for a human-or-agent choosing the wrong lever.
        This is the residual risk the runbook wording is carrying, and it is stated as such
        rather than papered over.
  - mode: post-PR4b, a deploy-docs.yml run goes red on the GitHub Pages leg alone because
        GitHub's custom-domain DNS check fails once the apex A record is gone
    detection: the publish-verdict step's per-leg table in $GITHUB_STEP_SUMMARY names WHICH leg
        failed, so the benign case is distinguishable from a real publish failure.
    alert_route: expected and benign between PR4b and PR5 (AC32). Remedied by merging PR5.
```

The single `discoverability_test.command` above begins with `bash`, on preflight Check 10's
`PROBE_VERB_ALLOWLIST`, and is a repo-relative committed script reaching no private network and
needing no credential — so `credentials_required` is deliberately absent.

**There is deliberately NO second `discoverability_test:` block.** An earlier draft added one.
Measured against the live parser: `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`
does `print; exit` on the **first** `command:`, and preflight's EXPECTED awk does the same on
the first `expected_output:`, both fed the whole `## Observability` block — and
`preflight/SKILL.md` names the hazard outright ("two `discoverability_test` sub-blocks could
confuse it"). A second block is **declared-verifiable and never executed**: precisely the gap
Check 10 exists to close, reproduced inside the section that declares the check.

## Encryption Posture

```yaml
at_rest:
  - store: Cloudflare Pages asset store (the deployed _site bundle)
    mechanism: provider-managed encryption at rest on Cloudflare object storage
    evidence: Cloudflare SOC 2 Type II / ISO 27001 attestations, already relied on for the
      existing R2 buckets in this root (soleur-terraform-state, soleur-workspaces-luks-header)
    defends_against: physical media compromise and offline disk access at the provider
    does_not_defend: anyone holding CF_API_TOKEN_PAGES, who can read and REPLACE the
      published bundle; and any public reader, since every byte in this store is
      deliberately public content
    disclosed_as: public marketing/documentation content, no personal data
    live_verification: curl -sSI https://soleur.ai/ returns 200 over TLS from Cloudflare's edge
  - store: terraform.tfstate on R2 (now also holds the Pages token value)
    mechanism: R2 provider-managed encryption at rest; bucket credentials distinct from every
      Cloudflare API token in this root
    evidence: backend block in main.tf; ADR-006
    defends_against: media compromise; credential separation bounds blast radius from a leaked
      CF API token
    does_not_defend: anyone holding the R2 S3-compatible access keys
    disclosed_as: infrastructure state containing sensitive variable values
    live_verification: unchanged by this plan
  - store: GitHub Actions secrets (CLOUDFLARE_API_TOKEN_PAGES, CLOUDFLARE_ACCOUNT_ID_PAGES)
    mechanism: GitHub-managed encryption at rest, auto-masked in logs
    evidence: seven existing github_actions_secret resources in this root
    defends_against: casual log exposure; read-back through the API
    does_not_defend: a compromised runner, or a workflow edit adding a pull_request trigger.
      deploy-docs.yml has NO pull_request trigger today and that absence is load-bearing.
    disclosed_as: CI deploy credential
    live_verification: gh secret list shows both names
    NOTE: after this change the token exists in THREE places — Doppler prd_terraform,
      terraform.tfstate on R2, and GitHub Actions secrets — under a single rotation. Named
      here and in the scope ledger; a Doppler-service-token indirection that would collapse
      this to one is recorded on the deferred issue.

in_transit:
  - connection: visitor browser -> Cloudflare edge (soleur.ai / www.soleur.ai)
    tls: TLS 1.3, Cloudflare-managed zone certificate
    cert_verification: "on"
    does_not_defend: an attacker holding CF_API_TOKEN_PAGES serves malicious content over a
      perfectly valid certificate — TLS attests the host, never the content
    disclosed_as: HTTPS everywhere, HSTS preloaded
  - connection: Cloudflare edge -> origin
    tls: n/a — ELIMINATED for the docs hosts by this change. Cloudflare Pages is served by
      Cloudflare, so after cutover there is no external origin leg. This is the posture
      improvement the migration buys: `ssl = "full"` exists precisely because the
      edge->GitHub-Pages leg presents an expired certificate.
    cert_verification: "n/a"
    does_not_defend: n/a
    disclosed_as: n/a
  - connection: GitHub Actions runner -> Cloudflare API (wrangler upload)
    tls: TLS 1.3 to api.cloudflare.com, default certificate verification
    cert_verification: "on"
    does_not_defend: a compromised runner or a leaked token
    disclosed_as: CI deploy path, token auto-masked
  - connection: GitHub Actions runner -> Cloudflare API (PR4's between-assert read of
      /zones/$CF_ZONE_ID/dns_records)
    tls: TLS 1.3 to api.cloudflare.com over curl's default verification — NO --insecure, and
      no custom CA bundle. Added by PR4; a READ, never a write. It is a second consumer of a
      connection this root already makes through the Terraform provider, not a new egress
      destination.
    cert_verification: "on"
    does_not_defend: a compromised runner. It also does not defend against a token whose scope
      is wider than the read needs — the read reuses the existing zone-scoped token rather than
      minting another, which is the narrower of the two available choices but not a least-
      privilege read-only credential.
    disclosed_as: CI ordering assertion on public DNS records; the response carries no personal
      data and the record contents are publicly resolvable by anyone

exception:
  - subject: the `ssl = "full"` Configuration Rule on soleur.ai + www.soleur.ai
    justification: PRE-EXISTING and explicitly retained by operator decision. It keeps the site
      up while the current origin certificate is expired, and it is what keeps the ROLLBACK
      viable — GitHub Pages' certificate is expired by construction, so a revert lands on an
      origin that only serves because of this rule. Removing it is part of the deferred
      cleanup. That it becomes inert for these hosts post-cutover (no origin leg remains) is a
      claim to MEASURE during that cleanup, not to assert here.
    tracking_issue: the deferred-cleanup issue filed in PR1 — UNVERIFIED as of 2026-09-03; a
      `gh issue list` search did not surface it, so AC52 (PF-DEFER) requires PR4 to verify it
      by number with `gh issue view` and file it if absent. A tracking_issue named only as a
      description is not a tracking issue.
    reevaluate_when: the site is verified serving from Cloudflare Pages across a full
      certificate cycle AND the rollback window is formally closed
    expires_on: 2026-11-20
```

## Guard Contract

### Guard 1 — `www-apex-canonicalizer.test.sh` (rewritten)

**Property.** The `www.soleur.ai → 301 → soleur.ai` redirect, and the apex's binding to the
Pages project, cannot be silently lost by any single edit to the substrate that produces them.

**Assembly.** The property quantifies over the **chain** that produces the live behaviour, not
over a snapshot of current facts — the existing guard's defect is precisely that it asserts
five literal GitHub-Pages facts, which this migration falsifies wholesale. The chain has five
links and the guard must assert all five:

1. the redirect declaration — the `www.soleur.ai/` item in `cloudflare_list.www_canonical`, with `subpath_matching` and `preserve_path_suffix` both `"enabled"` and `include_subdomains` `"disabled"`;
2. the **binding chokepoint** — the second `rules { }` block in `cloudflare_ruleset.bulk_redirects` whose `from_list.name` references that list, declared **after** the `legal_redirects` rule. A list nothing binds is inert, and a rule ordered before the legal rule silently changes which redirect wins;
3. the DNS substrate — the apex is a proxied `CNAME` at the Pages project **and www is a proxied `CNAME` at that same project**, per D1's deliberate divergence from Cloudflare's `192.0.2.1` recipe. The arm must REJECT a surviving `CNAME` at `jikig-ai.github.io` (www left on the retired origin) **and** any `A` record including `192.0.2.1` (www left the project — which deletes D1's chosen failure mode *and* turns the PR4 swap into a ForceNew replace, `destroy_count = 5`, contradicting R6 and PF9). An earlier draft read *"www is a proxied `A` at the black-hole address"*: residue of the rejected recipe, contradicting D1, ADR-194, R6 and PF9 in this same document. The guard and its mutation fixture were written from that draft; corrected 2026-09-03.
4. the **cross-file deploy coupling** — `deploy-docs.yml`'s `--branch` equals `cf-pages.tf`'s `production_branch`;
5. the **cross-file project coupling** — `deploy-docs.yml`'s `--project-name` equals `cloudflare_pages_project.docs`'s `name`.

Links 4 and 5 are two independent magic strings in HCL and YAML with no compiler between them,
and link 4 is the highest-ranked risk in this plan: editing `--branch` leaves every other
assertion green while the custom domain silently serves a stale build. Both must be asserted by
**cross-reading the two files**, never by matching two independent literals.

All five assertion targets live under `apps/web-platform/infra/**` or `.github/workflows/`,
both inside `infra-validation.yml`'s `pull_request: paths`, so the guard actually **runs** on a
PR that mutates any of them. This is a live constraint, not a nicety: under the rejected
`_redirects` design, link 2 would have sat in `eleventy.config.js`, outside that filter, and
the chokepoint mutation would have passed by never running.

**Disclosed honestly: the guard runs but does not block.** Its only CI invocation is the
`Run www-apex-canonicalizer drift-guard` step in `infra-validation.yml`'s `deploy-script-tests`
job, and that job is **advisory** — it is not in `ruleset-ci-required.tf`, so it is a
visible-red signal rather than a merge gate. This plan does **not** silently rely on it as a
blocking control. Two things follow: the ten-path www assertion is additionally carried as a
cutover gate (CUT7), which is blocking by procedure; and promoting `deploy-script-tests` to a
required check is recorded on the deferred-cleanup issue as a separate decision with its own
blast radius, not smuggled in here.

**Mutation matrix.** Each row must drive the guard to a non-zero exit.

| # | Mutation | Why it must redden |
|---|---|---|
| M1 | Delete the www item from `cloudflare_list.www_canonical` (leaving the list present) | the declaration is gone; a list-existence check alone would pass |
| M2 | Remove the second `rules { }` block from `cloudflare_ruleset.bulk_redirects` (leaving the list intact) | **the chokepoint row** — the declaration survives but nothing binds it, so the live 301 dies with every other assertion green |
| M3 | Reorder the two rules so the www rule precedes the legal rule | first-match-wins means the ten legacy legal paths on www would collapse to the bare apex |
| M4 | Repoint the apex `cloudflare_record` at any host other than the Pages project | the apex leaves the project |
| M5 | Flip `proxied = false` on either the apex or the www record | breaks the `domains.md` HSTS mandate and the edge path the redirect depends on |
| M6 | **Second-member row** — add a *second* redirect list and bind it with a third rule while leaving M1/M2 intact | a guard that stops at the first matching list or rule cannot see a divergent second declaration |
| M7 | **Cross-file row** — change `--branch` in `deploy-docs.yml` so it no longer equals `production_branch` (and, separately, `--project-name`) | the plan's highest-ranked risk; every in-file assertion stays green while the custom domain serves a stale build |
| M8 | **Own-dispatch row** — replace the guard's assertion list with an empty list | a guard reporting `0 assertions checked` and exiting `0` is vacuous |

**Harness rows.**

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Delete the M2 case from the guard's case list | the anti-vacuity floor must fail — a suite that silently shrinks is exactly what this row detects. Per **AP-023** the floor reports with `printf >&2` + `exit 1`, **not** through the suite's own `fail()`, and the case counter increments **at the call site**, never inside both verdict helpers. The file being rewritten has the banned shape today, so preserving its structure and bolting a floor on top would satisfy M8 on paper and be vacuous in fact |
| H2 | **Must-PASS, non-canonical**: reformat `seo-bulk-redirects.tf` with different internal whitespace, reorder unrelated list items, and reflow the `dns.tf` contract comment | must still exit `0` — the guard asserts content anchors, not byte-equality with a canonical file. A guard that rejects everything is as broken as one that accepts everything |

Carry forward the existing header note: *"A2/A3 grep the `cloudflare_record` resource name. A
future v4→v5 bump renames `cloudflare_record` → `cloudflare_dns_record`."* It applies unchanged
to the rewritten assertions.

### Guard 2 — `apex-single-node-replace.test.sh` (ships in **PR4a**)

**Write the matrix before the guard.** A matrix derived from finished code tests the code that
exists; this one is derived from the property.

**Why this guard is small.** An earlier draft specified a plan-JSON shape gate, an eleven-row
mutation battery over synthesized fixtures, and a workflow-order guard over the apply job's step
sequence. **All three are cut** (see the Cut List). Under D5 the ordering is supplied by
Terraform core's single-node replace semantics, so there is no sequence to assert and no plan
document to grade. What is left is the risk that a later edit **silently removes the property
core is providing** — and that is a static question about `dns.tf`, answerable without a plan,
without credentials and without fixtures.

**Property.** *The apex transition is expressed as exactly one Terraform resource address whose
replacement Terraform core will serialise: `cloudflare_record.pages_apex` carries no
`create_before_destroy`, is reached from the old address by a `moved` block whose endpoints are
both in the apply allow-list, and `www` remains a `CNAME` so it can never become a second
ForceNew replacement racing the first.*

**Assembly.** Structural, never a member list. The chokepoint is
`apps/web-platform/infra/dns.tf` — there is exactly one file in this root that declares apex
address records, and the guard quantifies over **every `cloudflare_record` block in it whose
`name` resolves to the apex** (`"soleur.ai"`), not over an enumerated list of the addresses this
cutover happens to touch. A future sibling apex record added by anyone is caught by the
quantifier rather than by someone remembering to extend a list. The second half of the assembly
is `.github/workflows/apply-web-platform-infra.yml`'s allow-list, because a `moved` block whose
endpoints are not both targeted **hard-errors the apply** (measured) — so the guard asserts both
endpoint literals are present there, which is AC46 generalised from one address to the pair.
**Reachability:** `.github/workflows/infra-validation.yml`, beside the `www-apex-canonicalizer`
invocations, whose `pull_request.paths` already covers both `apps/*/infra/**` and
`.github/workflows/apply-web-platform-infra.yml` (verified 2026-09-03).

**Mutation matrix.** Every row must drive the guard to a non-zero exit.

| # | Mutation | Why it must red |
|---|---|---|
| M1 | Add `lifecycle { create_before_destroy = true }` to `cloudflare_record.pages_apex` | **The core row.** It silently restores the original hazard: the `CNAME` create would be dispatched *before* the `A` delete, which is the one ordering Cloudflare rejects with `81053`. Nothing else in CI notices |
| M2 | Delete the `moved` block, leaving both the old and new resource declarations | Two unrelated addresses again — the exact plan measured as `1 to add … 1 to destroy` across two addresses, dispatched concurrently |
| M3 | Change the `moved` block's `from` index to an IP that is **not** the surviving `for_each` key | **The silent-failure row (NEW-P1).** Terraform does **not** error: the move is a no-op against absent state, so `pages_apex` plans as a bare create while the real survivor plans as a separate delete — two addresses, concurrent, hazard restored, **with no signal at all**. This is the highest-value row in the matrix precisely because nothing else can see it |
| M4 | Change `cloudflare_record.www`'s `type` to `"A"` | Camp B: `type` is ForceNew (measured), so `www` becomes a *second* replacement racing the first, and `destroy_count` moves to 2 on PR4b |
| M5 | Remove `-target=cloudflare_record.github_pages` from the apply allow-list | **Measured consequence:** `Error: Moved resource instances excluded by targeting` — the apply does not merely mis-plan, it hard-errors. The prefix-vulnerable `_challenge` sibling means this row must be checked with the line-anchored form |
| M6 | Remove `-target=cloudflare_record.pages_apex` from the allow-list | The other endpoint of the same pair; a guard that checks only the old address passes this |
| M7 | **Second-member row** — add a *second* apex `cloudflare_record` (any `name = "soleur.ai"` `A` record) alongside a correct `pages_apex` | A guard that stops at the first matching apex block, or that only checks the addresses it expects by name, passes this while the zone would again carry `A`-and-`CNAME` at one name |
| M8 | **Own-dispatch row** — replace the guard's assertion list with an empty list | A guard reporting `0 assertions checked` and exiting `0` is vacuous |
| M9 | **Own-dispatch row, second form** — remove the guard's invocation line from `infra-validation.yml` | A guard nobody runs is a guard that passes by never running. This is the `www-apex-canonicalizer` chokepoint lesson applied to the guard's own registration |

**Harness rows.** Mutations of the SUITE, not of the system under test.

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Delete the M1 case from the guard's case list | **MUST FAIL.** The anti-vacuity floor conforms to AP-023: it reports through `printf >&2` + `exit 1` rather than the suite's own `fail`, and the case counter increments **at the call site**, not inside both verdict helpers. `scripts/guard-vacuity-floor.test.sh` passes |
| H2 | **Must-PASS, non-canonical**: reflow `dns.tf`'s contract comment, reorder unrelated resource blocks, and change whitespace inside the `moved` block | **MUST PASS** — the guard asserts content anchors, not byte-equality with a canonical file. Without a must-PASS input that differs from the canonical in a way the contract explicitly permits, the RED rows cannot distinguish a correct guard from one that rejects everything |
| H3 | **Must-PASS, pre-PR4b state**: `dns.tf` exactly as PR4a leaves it — one `github_pages` instance, no `moved` block, no `pages_apex` | **MUST PASS.** The guard must be green on `main` between the two merges, or it blocks PR4a's own CI and every unrelated infra PR in the window. A guard that only accepts the post-cutover shape is a guard that cannot ship first |

**Guard 1 is unchanged by PR4 and must stay green.** Its DNS arm already rejects a surviving
`CNAME` at `jikig-ai.github.io` for `www` and any `A` at `www`; PR4b is the change that finally
satisfies the first of those, so a red Guard 1 after the flip means the hunk is wrong, not that
the guard is stale.

**The rollback-PR generator gets its own tests, and they are not optional.** It is the lever the
incident path depends on, and D5 measured that the obvious alternative (`git revert`) reproduces
the outage. Unit-test the transformation over PR4b's real diff: the reverse block's `from`/`to`
are swapped, `type` returns to `"A"`, `content` returns to the surviving IP literal, and the
generated file is byte-identical to `dns.tf` as PR4a left it. That last assertion is the strong
one — it makes the generator's output checkable against a state that actually existed.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-194** — do not renumber, do not create a new ADR. This plan *implements* an accepted
decision and corrects two lines of its reasoning:

1. `## Decision` — correct the free-slot premise (R1): the ACME carve-out is an inline clause of Rule 10, not a rule, so retiring it frees zero slots. Record that the 301 is rebuilt on a different product entirely, so the cap does not bind.
2. `## Alternatives Considered` — add the three considered mechanisms (a rule in `seo_page_redirects`; a Pages `_redirects` file; account Bulk Redirects) with the measured reason each was rejected or chosen, including that Cloudflare documents domain-level `_redirects` as unsupported.
3. Record that the ADR's "cleanup once live" list contains one item — the cert-reissue routine — whose *disarmament* could not be deferred with its deletion, and why.
4. Add pointers to the deferred-cleanup issue and the cutover runbook.

No new ADR ordinal is claimed, so there is no ordinal-collision exposure.

**Added for PR4 (2026-09-03) — a second amendment, still to ADR-194, still no new ordinal.**
The ordering decision is architectural under `wg-architecture-decision-is-a-plan-deliverable`:
it changes the **dispatch boundary** of the merge-apply path that every infra change in this
root traverses. A future engineer reading only the ADR and the C4 would be misled about how an
apex transition executes. It is an amendment rather than a new record because it decides *how*
ADR-194's already-accepted migration is applied, not *whether*; and amending costs no ordinal,
which is the collision surface this repo has been bitten by three times.

5. `## Decision` — record that **Hypothesis Z was measured FALSE on 2026-09-03**: with both
   custom domains attached, `apex-origin-probe.sh` returned `SERVING-FROM-GITHUB-PAGES`.
   Attachment does not select the origin; the DNS record does. The record swap **is** the
   cutover, and the residual-downtime path is the plan of record rather than a fallback.
6. `## Decision` — record the ordering mechanism as a **single-address replace ordered by
   Terraform core**, delivered as two merges (shrink the apex `for_each` to one key, then a
   `moved` block plus the `A`→`CNAME` flip on that one address). **Not** a two-pass targeted
   apply — that earlier formulation is superseded here, with its measured reasons. Record that
   `type` is ForceNew at provider 4.52.7 (measured), so the flip is a genuine single-node
   replace that core serialises Delete→Create.
7. `## Alternatives Considered` — add, each with the one fact that disqualifies it: the
   merge-path two-pass pre-pass (revert deletes it; its gate blocks its own recovery;
   `-target` transitivity aborts unrelated merges); the `apply_target=` dispatch job (destroys
   the same-lever rollback); `depends_on` (cannot reference a resource that has left the
   configuration); `create_before_destroy` (inverts the hazard); a lower TTL (the window is
   negative-cached against the SOA minimum, not the record TTL); and **`git revert` as the
   rollback** (measured: reproduces `81053` in reverse).

### C4 views

All three model files were read: `model.c4` (691 lines), `views.c4` (74), `spec.c4` (54). The
enumeration the completeness mandate requires:

| Category | Element | Modelled? | Action |
|---|---|---|---|
| External system | `github` | yes; in `context` + `containers` | **amend description** — it carries the Pages-cert-admin `PUT /pages` role as a live concern; post-cutover that path is DNS-detached |
| External system | `cloudflare` | yes; in both views | **amend description** — it becomes the docs-site host, a role it does not carry today |
| External system | `letsencrypt` | yes; described as *"ACME CA issuing the GitHub Pages custom-domain TLS cert for soleur.ai/www"* | **amend description** — that becomes false for the live site; scope it to the retained, DNS-detached path |
| External system | `publicResolvers` | yes; described via the cert-reissue DNS-propagation gate | **no edit** — the routine is retained, so the description stays true |
| Container | the Eleventy docs/marketing site | **not modelled** anywhere in `model.c4` | **not added** — it was unmodelled while on GitHub Pages and remains unmodelled after; this change does not make that silence false, and silence is not falsehood. Recorded on the deferred issue |
| External human actor | public site visitor / search crawler | not modelled (`founder`, `emailSender`, `betaContact`, `contributor` only) | **not added** — same disposition; recorded here so the next author sees it was checked, not missed |
| Access relationship | GitHub Actions → Cloudflare Pages content upload | not modelled | **not added** — `github` and `cloudflare` are already in both view include lists and the model already says they talk; a second parallel edge would need disambiguation from the existing read-only rulesets-GET edge, work created entirely by the addition |
| Access relationship | `api -> cloudflare` (cert-reissue proxied flip) | yes | **amend description** — add that the routine is gated on apex topology per D2 |

Only `model.c4` is edited; `views.c4` is untouched, which removes the #7332
both-endpoints-must-be-included hazard entirely. `c4-code-syntax.test.ts` and
`c4-render.test.ts` remain the gates.

**Re-checked for PR4/PR5 (2026-09-03), against all three files.** The enumeration above still
holds — no external actor, external system, container or access relationship is introduced by
PR4 or PR5 that was not already checked. PR4 introduces no new element: the ordered pre-pass is
a step sequence inside a workflow, and CI-drives-Terraform is already modelled. What PR4/PR5 do
introduce is a **tense** problem, which is a correctness problem, not an addition:

| Element | Current description (written by PR1) | Action, and when |
|---|---|---|
| `github` | *"ALSO — **until** the #7640 cutover — the HOST of the marketing/docs site…"* | **PR5** — flip to the completed tense. The clause is true-in-advance today and becomes false the moment PR4's apply lands |
| `cloudflare` | *"and, **from** #7640/ADR-194, the HOST of the marketing/docs site, a role it did NOT carry before"* | **PR5** — same flip, other direction |
| `letsencrypt` | *"SCOPE CORRECTED … **From the cutover** soleur.ai/www are served by Cloudflare Pages…"* | **PR5** — same flip; the retained/DNS-detached scoping is already correct and stays |
| `api -> cloudflare` (cert-reissue proxied flip) | already amended by PR1 with the D2 apex-topology gate | **no edit** — the gate now actually fires, which is what the description already says |

The flip is scheduled for **PR5, not PR4**, deliberately: PR4 can be reverted, and a model that
has already declared the cutover past would then be describing a state the rollback undid. PR5
merges only after CUT0-CUT9 hold, which is the point at which the past tense is true.

### Sequencing

The ADR amendment, the C4 corrections and the principles-register AP-019 note all ship in
**PR1**, ahead of the cutover — the statements they correct become false at the moment PR3
lands, and the disarmament they describe must exist before then.

**Issue closure is PR4's alone** (amended 2026-08-20 — was "PR3's" before the cutover split;
the attach and the record swap are now separate PRs, and the ATTACH is not the resolution).
The frontmatter `closes: 7640` names the work item, not the merge that resolves it. Only
**PR4** carries `Closes #7640` in its body; **PR1, PR2 and PR3 cite `Refs #7640`** and must not
use a closing keyword. Closing earlier would mark the migration done while the apex A-records
still point at GitHub Pages, and would retire the tracking issue the remaining PRs are
sequenced against.

Note this stayed correct only by being re-read: the four-PR split moved the cutover without
touching this paragraph, which is the propagation-miss shape — a decision changes and the
sentence that depended on it keeps asserting the old one.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `terraform validate` after adding `cf-pages.tf` and the new list/rule | exit `0` |
| T2 | `cloudflare_pages_project` declared without `production_branch` | `terraform validate` fails — confirms the schema requirement empirically |
| T3 | Guard 1 mutation rows M1-M8 | each drives a non-zero exit |
| T4 | Guard 1 harness rows H1, H2 | H1 fails via the AP-023 floor; H2 passes |
| T5 | `scripts/guard-vacuity-floor.test.sh` against the rewritten guard | passes |
| T6 | `wrangler pages deploy _site --project-name=soleur-docs --branch=main` | lands on the **production** deployment; `https://soleur-docs.pages.dev/version.txt` equals the SHA |
| T7 | Deploy with `--branch=some-other-branch` | lands on a preview alias and the custom domain keeps serving the previous build — confirms the trap is real before it can bite in production |
| T8 | The post-deploy probe with a deliberately wrong expected SHA | fails the job |
| T9 | `curl -sS -o /dev/null -w '%{http_code}' https://soleur-docs.pages.dev/no-such-path` | `404` |
| T10 | PF3: attach the apex custom domain, then list zone DNS records | no record auto-created, or the create is detected and `dns.tf` becomes an import |
| T11 | PF7: attach and detach a scratch custom domain | edge-routing persistence measured; the runbook's rollback matches the answer |
| T12 | T-WWW / CUT7: the ten legacy legal paths on the **www** host | still `301` to `/legal/<slug>/`, not collapsed to the bare apex |
| T13 | The origin-provenance probe across four arms | GitHub / Cloudflare / UNREACHABLE(transport) / UNREACHABLE(non-200) — already executed, results in Observability |
| T14 | D2: stub the apex record read with a `CNAME` and invoke the reissue preconditions | non-benign terminal outcome; no DNS mutation attempted |
| T14b | `python3 scripts/lint-encryption-posture.py --repo-sweep` after adding `cf-pages.tf` **without** a ledger entry | FAILS with `unknown resource type cloudflare_pages_project` — confirms the gate is real before relying on the ledger fix |
| T14c | The same sweep after the ledger entry lands | exit `0` |
| T14d | The cutover apply rehearsed as a single unordered pass against a scratch zone | reproduces error `81053` or a recordless window — confirms D4's premise rather than assuming it |
| T15 | `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` | exit `0` |
| T16 | `c4-code-syntax.test.ts` + `c4-render.test.ts` | pass |
| T17 | `dig soleur.ai MX` / `TXT` before and after PR3 | byte-identical sets |
| T18 | CUT0-CUT9 under the 3-sample rule | all hold |
| T19 | Guard 2 over the PR4a shape (one `for_each` key, no `moved`, no `pages_apex`) — harness row H3 | exits `0`. It must be green on `main` between the two merges or it blocks every unrelated infra PR |
| T20 | Guard 2 over each of M1-M9 | every mutation returns non-zero, including M3 (the moved-index mismatch), which nothing else in the system can detect |
| T21 | Guard 2 over a reflowed-but-correct `dns.tf` (H2) | exits `0` — the guard asserts content anchors, not byte-equality |
| T22 | `terraform plan` for PR4a | exactly 3 deletes, 0 creates, `destroy_count = 3`; apex still resolves after the apply |
| T23 | `terraform plan` for PR4b | one address, actions `["delete","create"]`, the `(moved from …)` annotation, plus the in-place `www` update; through `destroy-guard-filter-web-platform.jq`: `resource_deletes: 1, nested_deletes: 0, reboot_updates: 0, host_creates: 0` |
| T24 | PR4b's plan with only ONE `moved` endpoint in `-target` | `Error: Moved resource instances excluded by targeting` — the measured hard-error PF-TARGET guards |
| T25 | A bare create of `cloudflare_record.pages_apex` (the died-mid-replace re-plan) through the real destroy-guard filter and the pre-apply entrypoint gate | `resource_deletes 0`, out of scope for the entrypoint gate; applies unacked. **This is the recovery path, and it is tested rather than hoped for** |
| T26 | The rollback-PR generator over PR4b's real diff | the generated `dns.tf` is byte-identical to `dns.tf` as PR4a left it |
| T27 | `git revert` of PR4b's merge (a NEGATIVE test, run once and recorded — never as a rollback) | two addresses, `1 to add, 0 to change, 1 to destroy`, concurrent — the reverse-direction hazard AC71 forbids |
| T28 | PF-SYM: on a scratch name, create a `CNAME`, attempt an `A`, record the error code, delete | `81053` measured rather than assumed, in the direction a mistaken revert would hit |
| T29 | PF-Z2 / PF-R8b immediately before PR4b merges | `SERVING-FROM-GITHUB-PAGES` rc 0; apex = surviving `A` + MX/TXT, no `CNAME`; `www` = one proxied `CNAME` |
| T30 | `cutover-verify.sh` against the healthy pre-cutover apex | direction-agnostic assertions pass; `UNREACHABLE` is a distinct verdict from a failed assertion |
| T31 | PF8′: after PR4b merges, the generated rollback PR | open, green, mergeable before T+20, with `[ack-destroy]` verified by reading the branch's commit body |
| T32 | Post-PR5: a `deploy-docs.yml` run | green, Probe B MATCH, no GitHub Pages leg present |
## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Deploy lands on a preview alias; custom domain serves stale content while CI is green | medium | high | `production_branch` pinned in HCL, `--branch` pinned in YAML, Guard 1 M7 asserts they agree, and the post-deploy probe reads `version.txt` on the **custom domain**. T7 exercises the failure deliberately |
| Apex CNAME create lands while the four `A` deletes are out of `-target` scope | low | **total outage — NXDOMAIN, and HSTS preload forbids an HTTP fallback** | Both old and new addresses in the allow-list; PF9 pins the exact plan shape before the ack |
| `cloudflare_pages_domain` auto-creates a DNS record that collides with the Terraform-managed one | medium | medium | PF3 probes it in PR1, before PR3 is written. The ordering design no longer rests on the schema inference (R8) |
| A DNS-only revert does not restore GitHub Pages because the Pages custom domain still routes the hostname | medium | **high — rollback does not roll back** | PF7 measures it on a scratch domain before the cutover; the runbook is written to the measured answer |
| `TF_VAR_cf_api_token_pages` absent at merge → every apply on this root fails | medium | high | Phase 0 step 4 makes it a merge precondition for PR1 |
| The retained cert-reissue routine de-proxies live www, one-way | **high — it is the retained system's designed steady-state output** | high | D2: apex-topology precondition, the daily cron disabled, AP-019 status recorded. AC25-AC27 |
| CUT assertions fail during the legitimate ~5-minute mixed-resolution window | high without mitigation | medium — a false rollback | 3 consecutive clean samples at 60 s, starting 5 minutes after the apply; transport failure is a distinct verdict |
| Rollback MTTR dominated by CI on the revert PR | certain without mitigation | high at this threshold | The revert PR is pre-opened, green and mergeable before PR3 merges (PF8) |
| `workflow_dispatch` cannot carry `[ack-destroy]`, so the documented escape hatch cannot roll back | certain | high if discovered mid-incident | Stated in the runbook; the merge path is the only path |
| Apex MX/TXT disturbed by the A→CNAME transition — invisible to every uptime monitor | low | **high — silent mail loss** | Baseline captured in Phase 0; CUT9 compares; PF9 asserts zero planned changes to those records |
| Bulk Redirect precedence between the legal rule and the www rule | low | medium | Separate list plus explicit rule ordering, not intra-list precedence (undocumented); CUT7/T12 assert the ten legal paths on www |
| Pages token exists in three places under one rotation | certain | medium | Named in the scope ledger and Encryption Posture; rotation-policy comment on both `github_actions_secret` resources; Doppler-service-token indirection recorded on the deferred issue |
| Content rollback (a bad docs build) is no longer "re-run a green workflow run" | certain | medium | The runbook carries the Pages deployment-rollback procedure, with the subcommand shape verified at the pinned wrangler version |
| Rollback serves frozen, pre-cutover content | certain | low | Stated in D3; acceptable for an availability rollback |

**Added for PR4/PR5 (2026-09-03).** Two rows above are stale and are corrected here rather than
edited in place, so the record of what was believed survives: the *"Apex CNAME create lands while
the four `A` deletes are out of `-target` scope"* row rates the likelihood **low** on the strength
of PF9 — but PF9 is a **shape** assertion and cannot see order, so the real likelihood of an
ordering failure with all six addresses in one concurrent apply was a coin flip. The *"A DNS-only
revert does not restore GitHub Pages"* row cites PF7, retired by construction.

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The apex transition is dispatched as two unrelated graph nodes and the create loses the race | **was ~50% as configured** | `81053` mid-flight on the live public apex; HSTS forbids an HTTP fallback | **Removed, not mitigated.** D5 collapses the transition onto one resource address, so Terraform core serialises Delete→Create. Guard 2 M1 keeps it that way |
| Someone adds `create_before_destroy` to `pages_apex`, silently inverting the order core guarantees | medium — it looks like a safety improvement | restores the `81053` hazard with nothing else in CI noticing | AC67 + Guard 2 M1, a static assertion over the resource block |
| **PR4b's `moved.from` index does not match PR4a's surviving key** | medium — two merges, one literal, no compiler between them | **fails SILENTLY**: the move no-ops against absent state, the plan becomes two addresses again, and there is no error to see | AC68 + Guard 2 M3. This is the highest-value row in the matrix precisely because nothing else can detect it |
| **A rollback is attempted with `git revert`** | **high — it is the obvious, muscle-memory action** | measured: two unrelated addresses, concurrent, reverse-direction `81053` **on an apex that is already broken** | AC70's generator + AC71's prohibition in the runbook's rollback **step**, in the imperative. Residual risk is a human or agent choosing the wrong lever; there is no automated detector and the plan says so |
| A `moved` endpoint leaves the apply allow-list | low | measured: `Error: Moved resource instances excluded by targeting` — a hard error, not a mis-plan | AC46 (both endpoints, line-anchored — the bare form returns 2 because of the `_challenge` prefix sibling) + Guard 2 M5/M6 |
| The apply dies mid-replace: Delete lands, Create fails | low-medium | apex recordless, negative-cached to 1800 s | **Recovery needs no machinery** and is measured: the re-plan is a bare create scoring `resource_deletes 0`, out of the entrypoint gate's scope, applying unacked. Re-run the failed job. Runbook line + T25 |
| `[ack-destroy]` misses the squash body on either merge | medium — the runbook already warns GitHub prefixes subjects with `* ` | **repo-wide infra freeze**: every later merge re-plans the pending destroys and aborts, serialized behind the shared concurrency group | AC60 reads the merge body directly; remediation (push a commit carrying the ack) is stated so nobody derives it under pressure |
| Rollback MTTR dominated by the shared apply mutex | certain | the queue can exceed the whole T+20 budget — 47 min worst case for one run, longer behind a recut chain | Disclosed in `## Downtime & Cutover` and the runbook beside the decision point; declare the window when no other infra work is in flight |
| Between PR4a and PR4b the apex has one `A` instead of four | certain | loses Cloudflare's origin-level failover across the four when one is unreachable from a colo; all four are GitHub anycast and the survivor is itself anycast, so it is not a single machine | Keep the window inside one session; stated rather than discovered |
| `www` is "simplified" to an `A` record | medium — it is the natural-looking tidy-up | `type` is ForceNew (measured), so `www` becomes a second replacement racing the first | CTO ruling (Camp B); AC44; Guard 1's DNS arm; Guard 2 M4 |
| Z is re-measured stale, or the origin moved between PR3 and PR4 | low | the plan shape changes under the operator's ack | PF-Z2 + PF-R8b within the hour before merge; `UNREACHABLE` blocks rather than defaulting |
| PR4 and PR #7753 (`ssl = "full"` guard) race on the same auto-applied root | medium | a confusing interleaved apply, not a broken one | PF-SSL; PR4 does not touch `seo-config-rules.tf`; AC48 asserts an empty diff **and** the resource-level count, so #7753's comment rewrite cannot falsify it |
| CUT0 read literally drives a **false rollback** | **was certain** — `deploy-docs.yml` deliberately does not fire on `dns.tf`, so `version.txt` never holds the merge SHA | a healthy cutover rolled back at T+20 | CUT0′ asserts the invariant (the apex serves the build the project holds), cache-busted, against PF-DOCS's recorded SHA |
| PR5 narrows the rollback and nobody notices | certain | afterwards the GitHub Pages content is frozen and restoring it takes three acts, not one | AC56 discloses it in the runbook and on the deferred-cleanup issue; AC34 keeps PR5 behind CUT0′-CUT9 |
| The deferred-cleanup issue AC24 cites was never filed | **unknown — a 2026-09-03 search did not surface it** | AC24 is claimed against a reference that may not exist | AC52 (PF-DEFER): verify by number, or file it in PR4 |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- **`production_branch` is required even for a direct-upload project**, and it is not cosmetic: it is the sole determinant of whether a deploy reaches the custom domain or a preview alias. It must equal `--branch` in the workflow, and nothing but Guard 1 M7 checks that.
- **The ACME carve-out is a clause, not a rule.** Any future plan that budgets a rule slot by retiring it is budgeting a slot that does not exist.
- **Cloudflare Pages `_redirects` cannot express a domain-level redirect.** The obvious `https://www.example.com/* https://example.com/:splat 301` shape is the documented counter-example. It would also have failed this repo's own canonical-host build gate, and it would have placed the guard's chokepoint assertion outside `infra-validation.yml`'s path filter. Three independent failures behind one plausible-looking line.
- **A provider schema that exposes no DNS attributes does not mean the API creates no DNS record.** `cloudflare_pages_domain` looked inert by schema; Cloudflare documents that it auto-creates the CNAME when the zone is on the same account. Schema inference is not service behaviour — probe it (R8).
- **`grep -c` exits 1 when the count is zero**, so an acceptance criterion of the form "`grep -c … returns 0`" aborts under `set -e` instead of passing. Use `$(… || true)` with an explicit comparison, or `! grep -q`.
- **`server: cloudflare` is present both before and after this cutover**, because Cloudflare already proxies the GitHub origin. Any "are we on Pages yet?" check keyed on it discriminates nothing. The header discriminator is the **absence** of the GitHub/Fastly origin markers — and the durable check is the build-identity probe, not a header at all.
- **A probe that folds transport failure into a definite verdict is worse than one that fails closed.** The naive origin-provenance one-liner prints the *success* answer for an unreachable site. AP-021 forbids collapsing "could not check" into an answer; the shipped form emits a third `UNREACHABLE` verdict, verified across all four arms.
- **An anti-vacuity floor that reports through the suite's own `fail()` is vacuous** (AP-023), because neutering `fail()` silences both the assertion rows and the floor meant to notice. The file being rewritten has exactly that shape today.
- **`workflow_dispatch` cannot satisfy the `[ack-destroy]` gate**, because `github.event.head_commit` is absent on that event. The documented manual escape hatch structurally cannot perform a destructive rollback.
- **A `-target=` allow-list is the apply predicate, not sweep hygiene.** An untargeted resource is declared and never created, and nothing fails until something downstream reads it. Every `github_actions_secret` in this root is individually target-listed.
- **Delegating a `-target=` assertion to `terraform-target-parity.test.ts` passes vacuously** for any non-SSH resource: its predicate is a `terraform_data` resource with both an SSH `connection` block and a `provisioner` block, and it self-documents as one-directional.
- **A removed resource and its replacement are unrelated graph nodes.** `depends_on` cannot reference a resource that has left the configuration, so Terraform dispatches the deletes and the create concurrently. For a record type where the old and new cannot coexist (CNAME over `A`), that is a coin flip between a clean apply and error `81053` mid-flight on a live apex — and the interval between them is a window where the name has *no* address record at all. NXDOMAIN negative-caches against the zone SOA minimum (1800 s), six times the 300 s positive TTL a proxied record uses. Order it explicitly; a plan-shape assertion cannot see order.
- **An apex CNAME coexists with apex `TXT` and `MX` at Cloudflare.** The conflict set is exactly CNAME-over-`A`/`AAAA`/`CNAME` and `A`/`AAAA`-over-`CNAME`; `MX` and `TXT` are never in it, and CNAME flattening is what makes an apex CNAME legal at all. The zone's five apex `TXT`/`MX` records survive untouched. This was the plan's highest-flagged structural risk and it is **not** a risk — but CUT9 still asserts it, because a silent mail break is invisible to every uptime monitor.
- **Do not touch the zone's CNAME-flattening setting.** It runs the default *Flatten CNAME at root*. Someone adding an apex CNAME is exactly the person who might flip it to *Flatten all CNAMEs* — which would flatten the three ProtonMail DKIM CNAMEs and the unproxied `api.soleur.ai` Supabase record, breaking DKIM and Supabase certificate validation. The apex CNAME needs no such change.
- **Pointing DNS at a Pages project before the custom domain is attached is a hard 522, not a soft 404.** Cloudflare: *"Manually adding a custom CNAME record pointing to your Cloudflare Pages site — without first associating the domain … will result in your domain failing to resolve at the CNAME record address, and display a 522 error."* The `depends_on` direction in this plan is the correct one, and the cost of reversing it is an edge error on the apex.
- **`cloudflare_pages_domain.status` reads `pending`/`initializing` for a while after apply.** It is computed, so it produces no diff — but `scheduled-terraform-drift.yml` runs a full plan every 12 h, and a drift reviewer should not chase it.
- **`ssl = "flexible"` on a Pages custom domain is a documented redirect loop.** This zone is not exposed: `seo-config-rules.tf` scopes `flexible` to `(http.host eq "app.soleur.ai")` and `full` to the docs hosts. Recorded as *checked*, because "we didn't touch it" is a weaker guarantee than "we read the expression."
- **`grep -c` counts lines, not tokens, and a repo convention can put the searched word in prose.** `grep -c 'default'` inside a Terraform variable block returns `1` on a *correct* no-default variable here, because the house style ends the description with "No default (hr-…)". Anchor on `^\s*default\s*=`.
- `dns.tf`'s contract comment asserting repo-wide absence of `cloudflare_list` / `http_request_redirect` resources has been stale since 2026-06-09. Comments that assert repo-wide absence rot silently; the rewrite states what the substrate **is**, across all three redirect owners, and the guard asserts it.

**Added for PR4/PR5 (2026-09-03).**

- **An assertion that a mechanism EXISTS is not an assertion that it was BUILT, and an AC filed under the wrong PR is the shape that hides the difference.** AC29 said *"the cutover apply is expressed as two targeted passes with the sequence asserted between them"* and sat under `### PR1`. PR1 merged green. PR2 merged green. PR3 merged green. Nothing in the repo expresses two targeted passes, because the AC was never in the scope of the PR that would have been graded against it — the criteria list is per-PR and a reviewer reads the section they are reviewing. The cheapest gate is mechanical: an AC whose subject is a file the PR does not touch belongs to a different PR, and the `## Files to Edit` list is where that shows up. Here AC29's subject is `.github/workflows/apply-web-platform-infra.yml`'s **step sequence**, and PR1's Files-to-Edit named that file only for its `-target=` allow-list.
- **When a transition hazard is stated in one direction, write the other one down before deciding it does not apply.** D4 reasoned carefully about four `A` deletes preceding one `CNAME` create and never asked what the reverse looks like. The reverse is the rollback — one `CNAME` delete and four `A` creates, the same unrelated-graph-nodes problem, the same `81053`, executed on an apex that is *already* failing. A hazard that is symmetric under a direction flip and is only mitigated in one direction leaves the mitigation absent from the exact run where it matters most. Cheapest gate: for any ordering constraint, write the sentence with the two operands swapped and check whether it is still true.
- **`tests/scripts/` is not covered by any glob in `scripts/test-all.sh`** — the file says so explicitly in its own `SUITE_GLOBS` comment, and every sibling battery is reached by a hand-written `run_suite` line. A new `tests/scripts/test-*.sh` that nobody registers runs never, reports nothing, and leaves the runner exiting 0. **Doubly so here:** every declared glob matches the `*.test.sh` *suffix*, while these files use a `test-*` *prefix*, so even adding `tests/scripts/` to the array would not match them. Registration is not bookkeeping; it is the only reachability path, and it needs its own acceptance criterion. *(This plan ended up placing Guard 2 under `apps/web-platform/infra/` and reaching it from `infra-validation.yml` instead, so the hazard does not apply to what it ships — recorded because the next author will reach for `tests/scripts/` by default.)*
- **A guard's registration site decides whether it can ship first.** Guard 2 asserts a property of the POST-flip `dns.tf`, but it ships in PR4a and must be green on the PR4a shape — one `for_each` key, no `moved` block, no `pages_apex`. A guard written only against the finished state blocks its own introducing PR and every unrelated infra PR in the window between the two merges. Harness row H3 exists solely to force that question at design time, and it is the row a matrix derived from finished code would never contain.
- **A gate that SOURCES `plan-gate-preamble.sh` without CALLING it is the documented lower tier that fails open**, and a presence-grep cannot see the difference, because every retrofitted gate carries the literal inside its own `declare -F` re-source guard. Anchor on the call: `grep -cE '^\s*plan_gate_assert_readable'`. This is the same class as `cq-assert-anchor-not-bare-token`, on a file whose whole purpose is to stop a gate from reading "I could not check" as "it is fine".
- **The cheapest way to order two operations is to stop having two operations.** D4 spent its
  whole length on how to sequence four deletes against one create, and an entire pre-pass, shape
  gate, mutation battery and workflow-order guard were designed to enforce that sequence. The
  answer was to collapse the transition onto **one resource address** and let Terraform core's
  single-node replace do it — four artifacts and an eleven-row matrix dissolved. When a plan is
  building machinery to order operations on unrelated graph nodes, the prior question is whether
  the nodes have to be unrelated. Here they did not: a `moved` block was all it took.
- **A mechanism that lives in the same commit as the change it protects is deleted by that
  change's revert.** `on: push` runs the workflow file **from the merged ref**, so a rollback
  merge that reverts the ordering steps runs unordered — the mechanism is absent in exactly the
  run that needs it most. This disqualifies *any* same-commit guard for a reversible destructive
  change, and it is the single finding that killed the pre-pass design outright. State the
  merged-ref fact explicitly; it is load-bearing and was nowhere written.
- **`git revert` is not a universal inverse.** It inverts a *diff*, not a *transition*. When
  atomicity is supplied by a directive the diff introduced — a `moved` block, a `lifecycle`
  rule, a migration's ordering hint — reverting deletes the directive and the inverse transition
  runs unprotected. Measured here: the revert of the apex flip plans two unrelated addresses and
  reproduces `81053` in the reverse direction, on an apex that is already broken. Where this is
  true, the rollback must be *generated*, not reverted — and the prohibition belongs in the
  runbook's rollback **step**, in the imperative, because the wrong lever is the one muscle
  memory reaches for.
- **A shape gate over a transition refuses the half-finished state by construction.** Enumerate
  FORWARD and REVERSE and you have implicitly declared every intermediate state illegal —
  including the one the mechanism itself produces when it dies between steps. The measured
  consequence here was that both the completion (`0 deletes, 1 create`) and the rollback
  (`4 creates, 0 deletes`) failed the gate while the apex was NXDOMAIN. Grade the **end state**,
  or provide explicit resume verdicts; `workspaces-luks-recut-gate.sh`'s recovery arm exists for
  exactly this reason and is the sibling to copy.
- **`-target` is transitive, and a resource reference in an attribute pulls its referent into
  scope.** `content = cloudflare_pages_project.docs.subdomain` means any `-target` of that record
  drags the Pages project into the scoped plan's `resource_changes` — so an out-of-scope rule
  reading "no other addresses" aborts every ordinary merge, and relaxing it lets an unguarded
  project diff apply mid-cutover. Under a design with no scoped pre-pass the reference is free;
  under one with a scoped plan it is a trap. The attribute did not change — the surrounding
  mechanism decided whether it was safe.
- **A `moved` block hard-errors under `-target` unless BOTH endpoints are targeted.** Measured:
  `Error: Moved resource instances excluded by targeting`. On a `-target`-scoped apply path this
  turns a stale allow-list from "the destroy is never planned" into "the apply does not run at
  all" — a louder failure, but only if someone knew to keep both lines.
- **A `moved` block whose `from` does not exist fails SILENTLY.** Terraform no-ops the move
  rather than erroring, so a mistyped or drifted index yields a bare create at the new address
  and a separate delete at the old one — two nodes, concurrent, with the hazard fully restored
  and nothing to see. Any two-step migration that pins a literal in step 2 to state produced by
  step 1 needs a mechanical assertion on that literal; eyes are not sufficient because there is
  no error to notice.
- **A pre-flight that cannot be satisfied at the time it is scheduled is not a strict pre-flight, it is an unmet one.** PF8 asked for a revert PR open and green *before* the cutover merged; a revert of an unmerged commit has no commit to revert and a branch carrying the reverse of a diff `main` does not have is a no-op. Three PRs shipped past it. When a pre-flight is structurally unmeetable, restate it against the constraint (PF8′ moves the pre-open from *before the merge* to *before the decision point*, into a window that already has to elapse) rather than quietly carrying it forward as satisfied.
- **A true-in-advance description is a correctness debt with a due date.** `model.c4` currently reads *"until the #7640 cutover"* and *"from #7640/ADR-194"* — accurate today, false the moment PR4 applies, and invisible to `c4-code-syntax.test.ts`, which validates syntax rather than tense. Schedule the flip with the PR that makes it true (PR5, after CUT0′-CUT9 hold), not with the PR that makes it *likely* — a model that has declared the cutover past is wrong in exactly the state a rollback produces.
