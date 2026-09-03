# Runbook — soleur.ai cutover to Cloudflare Pages (ADR-194)

Covers the ADR-194 migration of the marketing/docs site off GitHub Pages, the
rollback path, and content rollback after the deploy mechanism changed.

Every state CHANGE here happens by **merging a pull request** — the applies are
performed by `apply-web-platform-infra.yml` on merge to `main`, and the docs
deploy by `deploy-docs.yml`. There is no console step and nothing to configure
by hand.

The **verification** steps are read-only probe commands you run from a checkout
of this repo (`bash apps/web-platform/infra/...`). They change nothing and are
safe to re-run. Where a step says "run", that is what it means; where it says
"merge", the automation does the rest.

## Sequence

| PR | Contents | Applied by | Reverting it removes |
|---|---|---|---|
| PR1 | Pages project, Actions secrets, www Bulk Redirect, cert-reissue disarmament | apply-web-platform-infra | the substrate |
| PR2 | `deploy-docs.yml` swap to wrangler | deploy-docs | the deploy path |
| PR3 | `cloudflare_pages_domain.apex` + `.www` | apply-web-platform-infra | the custom-domain attachment |
| PR4a | `dns.tf`: shrink the apex `for_each` to ONE key; ship `apex-single-node-replace.test.sh`. **Needs `[ack-destroy]`** (`destroy_count = 3`) | apply-web-platform-infra | reverting RESTORES the three deleted apex A-records (`destroy_count = 0`, so no ack needed) |
| PR4b | `dns.tf`: `moved` block + the `A`->`CNAME` flip on that one address. **Needs `[ack-destroy]`** (`resource_deletes = 1`) | apply-web-platform-infra | **do NOT `git revert` this one** — see the prohibition below |
| PR5 | retire the GitHub Pages publish leg from `deploy-docs.yml` | deploy-docs | reverting RESTORES the GitHub Pages publish leg |

**The cutover is TWO merges, not one.** Cloudflare rejects an `A` and a `CNAME`
coexisting at one name with error `81053`, so four apex deletes dispatched
concurrently with the `CNAME` create is a coin-flip on a live, HSTS-preloaded
apex. Shrinking to one address first means the flip is a single-address REPLACE,
which Terraform core serialises Delete->Create by construction. There is no
pre-pass, no plan-JSON gate and no between-assert to run: the ordering is a
property of the graph, not of a procedure someone has to follow.

Both destructive merges need `[ack-destroy]` on its own line in the SQUASH
BODY (not the subject — GitHub prefixes squash-body subjects with `* `, which
breaks the line anchor). Get it wrong and the apply fails with `dns.tf` on
`main` disagreeing with the zone, and **every subsequent infra merge trips the
same gate** until a new push touching `apps/web-platform/infra/**` carries the
token. `workflow_dispatch` cannot rescue it: `github.event.head_commit` is
absent on a dispatch run, so `HEAD_MSG` is empty and the anchor can never
match.

**Rolling back PR4a is the cheap direction and needs no ack.** Reverting it
plans 3 creates / 0 changes / 0 destroys, so `destroy_count = 0` and the apply
runs unattended. The surviving key is untouched by the revert, so the apex
never stops resolving. That asymmetry with the forward merge is worth knowing
before you need it.

PR4b's `moved.from` index must name PR4a's surviving key **byte-identically**.
A mismatch does not error — Terraform no-ops the move, the apex plans as two
concurrent addresses again, and the hazard returns with no signal anywhere.
`apex-single-node-replace.test.sh` row M3 is the only detection there is.

## Dual-publish: both origins are live

From PR2 until PR5, **every docs merge publishes to both origins** — GitHub Pages
and the `soleur-docs` Cloudflare Pages project — from the same `_site`.

That is deliberate, and the GitHub Pages leg is not vestigial: **it is the
rollback target, and it is kept current precisely so the rollback below lands on
today's site rather than on whatever was published the day PR2 merged.**

Consequences worth knowing before you read the rollback:

- `https://soleur.ai/version.txt` and `https://soleur.ai/CNAME` are publicly
  served static files. Neither is a leak — the first is a commit SHA in a public
  repo, the second is a public hostname.
- The job is a **conjunction**: if either origin fails to publish, or either
  build-identity probe fails, the whole run is red. No leg aborts the others.
- **Between the PR4b apply and the PR5 merge, a red GitHub-Pages leg is EXPECTED
  and benign.** Once the apex `A` records are gone, GitHub's custom-domain DNS
  check fails and that leg cannot succeed. The remedy is to merge PR5, which
  removes the leg — not to debug it, and not to revert PR4b.

  **This does NOT apply in the PR4a->PR4b window.** After PR4a the apex is
  still served by GitHub Pages and GitHub Pages is still the rollback target,
  so a red publish leg there is a real failure on the origin currently serving
  the site — investigate it, do not wave it through.

## State after PR2 (this PR)

`deploy-docs.yml` publishes to the `soleur-docs` Pages project. The apex is
**still GitHub Pages** until PR4b. Consequences, stated so they are not
discovered:

- `soleur.ai` serves the **last GitHub Pages build** and stops advancing. Docs
  merged between PR2 and PR4b are live on `soleur-docs.pages.dev` and not on
  the apex. The longer PR4b is delayed, the staler the public site.
- The post-deploy build-identity probe runs **reporting-only** and targets
  `soleur-docs.pages.dev`, because the apex it will eventually assert about is
  not yet served by this project. PR4b repoints it at `https://soleur.ai/version.txt`
  and removes `continue-on-error`.
- `_site/CNAME` is **expected** to become a publicly served static file
  (`https://soleur-docs.pages.dev/CNAME`). GitHub Pages consumed it; wrangler's
  upload ignore-list does not mention it, so it should upload like any other
  asset. Confirm after the first deploy rather than assuming — at the time of
  writing the project has no deployment to check against:

  ```bash
  curl -sI https://soleur-docs.pages.dev/CNAME
  ```

  Either way it is not a leak: the file contains `soleur.ai`, a public hostname.
  It is recorded here so a later reader does not mistake it for one. `CNAME`
  stays in the build because it is part of the GitHub Pages configuration
  retained for rollback. `.nojekyll` is a 0-byte marker and carries nothing.

## Rollback

### The merge path is the only path

`workflow_dispatch` **cannot** perform the infrastructure rollback. The destroy
gate reads `HEAD_MSG: ${{ github.event.head_commit.message }}`. On a dispatch
run `github.event.head_commit` is absent, `HEAD_MSG` is empty, and the
`[ack-destroy]` regex cannot match. The reverting apply always has
`destroy_count > 0` because it destroys the apex record, so the documented
dispatch escape hatch structurally cannot execute this rollback.

`[ack-destroy]` must therefore reach the **squash commit body**. Put it on its
own line in the BODY of a commit on the revert branch — not the subject, because
GitHub prefixes subjects with `* ` when composing the squash body, which breaks
the line anchor.

### Procedure

1. **Do NOT `git revert` PR4b.** Generate the rollback PR instead:

   ```bash
   bash apps/web-platform/infra/generate-apex-rollback-pr.sh
   ```

   **The generator ships WITH PR4b** (it is that PR's own deliverable). Between
   the PR4a and PR4b merges it does not exist — and it does not need to, because
   nothing is flipped yet and PR4a's rollback is a plain revert (above). If you
   are reading this mid-incident and the script is missing, the reverse block is
   three lines and you can hand-write it:

   ```hcl
   moved {
     from = cloudflare_record.pages_apex
     to   = cloudflare_record.github_pages["185.199.108.153"]
   }
   ```

   What you must NOT do is reach for `git revert` because the generator is
   absent. That is the one path measured to reproduce the outage.

   This is an imperative, not a preference, and it is measured rather than
   reasoned. `git revert` of PR4b deletes the `moved` block along with the DNS
   hunk — and the `moved` block is the entire thing supplying the ordering. The
   reverted plan plans `github_pages[...]` as a CREATE and `pages_apex` as a
   DESTROY at two unrelated addresses, concurrently: the original `81053` hazard,
   in reverse, on an apex that is by then already broken. Terraform cannot derive
   the reverse `moved` block on its own, so the generator writes it.

   Merge the generated PR. It restores the apex DNS record to GitHub Pages and
   requires `[ack-destroy]` in the squash body, exactly as the forward flip did.
2. Confirm which origin is actually serving:
   `bash apps/web-platform/infra/apex-origin-probe.sh`
   It reports `SERVING-FROM-GITHUB-PAGES`, `SERVING-FROM-CLOUDFLARE-PAGES`, or
   an explicit `UNREACHABLE` — it never reports an origin it did not observe.
3. Branch on what step 2 actually reported:
   - `SERVING-FROM-GITHUB-PAGES` — the rollback is complete. Stop here.
   - `SERVING-FROM-CLOUDFLARE-PAGES` — merge the revert of **PR3** as well.
     Custom-domain attachment, not only the DNS record, can establish edge
     routing for a hostname. **That revert destroys two `cloudflare_pages_domain`
     resources, so it needs `[ack-destroy]` in its squash body exactly as step 1
     does.** The probe's contract is that it never reports an origin it did not
     observe, so do not infer this branch from a failure to reach the site.
   - `UNREACHABLE (...)` — you have **not** rolled back; you have lost the site.
     The most likely cause is that the apex is now pointed at a GitHub Pages
     origin whose certificate is expired (`bad_authz`), which surfaces as a 526.
     Confirm `ssl = "full"` is still present in `seo-config-rules.tf` — it is
     what masks that expiry — and if it is, go to step 4.

4. If step 3 did not restore a working origin, the remaining lever is to put the
   apex back on Cloudflare Pages deliberately rather than to keep reverting:
   re-merge PR3, then PR4a, then PR4b **in that order** — never "PR4" as one
   act, which is the four-deletes-racing-one-create shape this whole design
   exists to remove. Treat the incident as forward-fix. Reverting further
   does not help — PR2's revert removes the *publisher*, leaving the apex on
   Pages with nothing deploying to it.

   This is the case PF7 would have measured. The staged split makes the
   *procedure* correct without that measurement (steps 1-3), but it does not
   answer whether detaching a custom domain promptly clears edge routing. If you
   reach this step, record what you observe — that is the measurement.

Step 3 is why the cutover is staged rather than a single merge (five PRs as
the table above enumerates: PR1, PR2, PR3, PR4a, PR4b, PR5 — six rows, because
PR4 is two merges). PR3, PR4a and PR4b each
introduce exactly one **apex**-origin-selecting mechanism, so whichever of the
two is actually selecting the origin, reverting the PR that introduced it
removes it — the procedure is correct without knowing in advance which.

Scope that precisely: it is a claim about the apex, not about every hostname.
PR1 introduced an origin-affecting mechanism of its own — the account-level
`www_canonical` Bulk Redirect answers `www.soleur.ai` ahead of any origin, and
survives every revert in this table. If `www` misbehaves, this procedure is not
the one you want; `seo-bulk-redirects.tf` is.

> **PF7 is retired, and this is why.** An earlier revision of the plan
> scheduled a scratch-custom-domain attach/detach probe in PR2 (D3 open item
> 3(b)) to decide whether a DNS-only revert is sufficient. The 2026-08-20
> staged amendment retires that question **by construction instead of by
> measurement** — the two mechanisms now live in separate reverts, so the
> answer changes nothing about the procedure above. The probe was not run: it
> would have attached and detached a hostname on the live production zone to
> answer a question the sequencing had already made moot. D3's body still
> describes 3(b) as "measured in PR2" and is superseded on that point.

### Rollback content freeze

GitHub Pages serves the **last pre-cutover build** and nothing re-asserts the
`CNAME` file to it once `deploy-docs.yml` stops deploying there. A rollback
three weeks after the cutover serves three-week-old docs. Acceptable for an
availability rollback; stated so nobody is surprised by it.

### The rollback window depends on deferred cleanup staying deferred

`ssl = "full"` must remain in `apps/web-platform/infra/seo-config-rules.tf`.
The GitHub Pages origin certificate is expired by construction
(`cert_state: bad_authz`, expired 2026-08-16, `https_enforced: false` — still
true as of 2026-09-02), so that Configuration Rule is the only reason the apex
resolves over TLS while GitHub Pages is the origin. Removing it before the
migration is verified live removes the rollback target as well.

## Content rollback — how to un-ship a bad docs build

**Re-running a previous green workflow run still works, and is the fastest
path.** An earlier revision of this runbook claimed it did not; that was wrong.
`deploy-docs.yml`'s checkout step pins no `ref:`, so re-running run *N* checks
out run *N*'s commit, rebuilds those bytes, and deploys them to the production
branch. `version.txt` is re-stamped with that older SHA, so the build-identity
probe compares like with like and reports MATCH.

What genuinely changed is the *mechanism underneath*: GitHub Pages redeployed a
stored artifact, whereas this rebuilds from source. A re-run therefore reproduces
the old commit's **inputs**, not its exact bytes — if the build reads anything
live (it does: `_data/github.js` and `_data/communityStats.js` fetch at build
time), the output can differ. For an availability rollback that is fine. For a
byte-exact restore it is not, and the forward path below is the honest option.

Measured at the pinned version (`wrangler 4.124.0`,
`wrangler pages deployment --help`), the available subcommands are:

```
wrangler pages deployment list
wrangler pages deployment create [directory]   (alias for `pages deploy`)
wrangler pages deployment tail [deployment]
wrangler pages deployment delete <deployment-id>
```

**There is no `rollback` and no `promote` subcommand.** A previous deployment
cannot be re-pointed at the production branch from the CLI at this version. So
content rollback is a **forward** operation:

1. Revert the offending docs commit on `main` in a PR.
2. Merging it fires `deploy-docs.yml`, which rebuilds and deploys the corrected
   tree.
3. The post-deploy build-identity probe confirms the served bytes match the new
   commit. Before PR4b that probe is reporting-only, so read its output rather
   than relying on the job's colour.

`wrangler pages deployment delete` removes a deployment but does not select
which one the production branch serves; do not reach for it as a rollback.

## Cutover verification (PR4b)

Run the probe rather than reading a dashboard:

- `bash apps/web-platform/infra/apex-origin-probe.sh` reports
  `SERVING-FROM-CLOUDFLARE-PAGES`.
- `https://soleur.ai/version.txt` equals the SHA of the merge commit that built it.
- `https://www.soleur.ai/` returns `301` to `https://soleur.ai/`.
- `https://www.soleur.ai/pages/legal/privacy-policy.html` still returns `301` to
  `https://soleur.ai/legal/privacy-policy/`. The legal Bulk Redirect rule is
  declared **before** the www rule and first match wins; if the www rule ever
  wins, ten live legal redirects collapse to the bare apex.
- A nonexistent path returns `404` and `/` returns `200`.
