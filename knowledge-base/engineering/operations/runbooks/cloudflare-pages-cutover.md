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

> **Plan (ARCHIVED 2026-09-03 by PR5, AC58).** The migration plan this runbook
> implements now lives at
> `knowledge-base/project/plans/archive/20260903-221104-2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`,
> and its two spec dirs at
> `knowledge-base/project/specs/archive/20260903-221104-feat-one-shot-7640-pr4-dns-cutover-pr5-retire-gh-pages`
> and
> `knowledge-base/project/specs/archive/20260903-221155-feat-one-shot-7640-cloudflare-pages-migration`.
> **This runbook is the live artifact** — the plan is history, kept for the
> measurements and rejected alternatives behind each decision here.


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

## Dual-publish: both origins WERE live (PR2 -> PR5) — HISTORY, not current state

> **STATE AS OF 2026-09-03: SINGLE-ORIGIN, Cloudflare Pages only.** PR5 retired
> the GitHub Pages publish leg. This section and `## State after PR2` below are
> the TRANSITION RECORD. If you are here during an incident, the current state
> and the rollback you want are in `### PR5 NARROWED THE ROLLBACK` further down.


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
- **THIS PREDICTION WAS WRONG, and the correction matters for the rollback.**
  This bullet used to say a red GitHub-Pages leg was EXPECTED between the PR4b
  apply and the PR5 merge, because GitHub's custom-domain DNS check would fail
  once the apex `A` records were gone. **Measured 2026-09-03, after the flip:**
  run `33802992407` (`9c9a48505`, >1h post-apply) reported `Deploy to GitHub
  Pages: success`, and so did every other post-apply run. The mechanism is
  `gh api repos/{owner}/{repo}/pages` -> `"build_type": "workflow"`: a
  workflow-source deployment does NOT gate on the custom-domain DNS check, even
  with `https_certificate.state: bad_authz` and `expires_at: 2026-08-16`.
  **This is load-bearing for the rollback, not a footnote.** Because
  `actions/deploy-pages` succeeds while DNS points at Cloudflare, act 2 of the
  three-act rollback ("redeploy so GitHub Pages holds a CURRENT build") is
  executable BEFORE act 3 restores DNS. Had the original prediction held, that
  ordering would have been impossible and the rollback below would be wrong.

  **This does NOT apply in the PR4a->PR4b window.** After PR4a the apex is
  still served by GitHub Pages and GitHub Pages is still the rollback target,
  so a red publish leg there is a real failure on the origin currently serving
  the site — investigate it, do not wave it through.

## State after PR2 (HISTORY — PR2 is long merged; see the state banner above)

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

## Verifying the cutover — CUT0'-CUT9

Run the committed runner, not a checklist. It emits one row per assertion and one
exit code, and it distinguishes three outcomes rather than two:

```bash
# The expected SHA is the one PF-DOCS recorded — the last SUCCESSFUL
# deploy-docs.yml run on main. It is NOT the cutover merge SHA:
# deploy-docs.yml deliberately does not fire on dns.tf, so no build exists at
# the merge SHA and CUT0 read literally would fail all three samples and drive
# a FALSE rollback. That is why the assertion is CUT0', not CUT0.
# The last run whose CLOUDFLARE PAGES leg succeeded — not merely the last run.
# `--limit 1 --json headSha` alone returns the newest run whatever happened to
# it; if its Pages leg failed, CUT0' compares the apex against a SHA that was
# never published, fails all three samples, and drives a FALSE rollback — the
# exact failure CUT0' exists to remove. The run CONCLUSION is also the wrong
# field here: after the cutover the GitHub Pages leg is red by construction
# until PR5, so the run is red while the Pages leg is green.
#
# READ THE STEP, NOT THE JOB. `deploy-docs.yml` declares exactly ONE job, named
# `deploy`; "Cloudflare Pages" is a STEP name inside it (`Deploy to Cloudflare
# Pages`). An earlier form of this block filtered `.jobs[] | select(.name |
# test("Cloudflare Pages"))`, which matches NOTHING at the job level — so
# PF_SHA came back empty on every run, the guard below fired, and the operator
# was told "do NOT proceed" while under the T+20 clock. Measured 2026-09-03:
# job-level filter -> empty; step-level filter -> 223da596f. A derivation that
# cannot produce a value is not a conservative default; it is a blocked
# recovery. If `deploy-docs.yml` is ever split into per-leg jobs, this filter
# moves back up a level — check `gh run view <id> --json jobs --jq
# '.jobs[].name'` before assuming either shape.
# Fail LOUD on a step rename rather than silently empty — silent-empty is the
# defect this block just fixed, and a rename would reintroduce it identically.
grep -q '^      - name: Deploy to Cloudflare Pages$' .github/workflows/deploy-docs.yml \
  || echo "WARNING: deploy-docs.yml no longer declares a step named 'Deploy to Cloudflare Pages'. PF_SHA will come back EMPTY and the guard below will read as 'no successful build'. Fix the filter before proceeding."

PF_SHA=$(gh run list --workflow=deploy-docs.yml --branch main --limit 20 \
           --json databaseId,headSha --jq '.[] | "\(.databaseId) \(.headSha)"' \
  | while read -r id sha; do
      if gh run view "$id" --json jobs \
           --jq '[.jobs[].steps[] | select(.name == "Deploy to Cloudflare Pages")
                                  | select(.conclusion == "success")] | length' \
         | grep -qv '^0$'; then printf '%s\n' "$sha"; break; fi
    done)
[ -n "$PF_SHA" ] || { echo "no deploy-docs run with a successful Cloudflare Pages STEP in the last 20 — do NOT proceed"; }

# CUTOVER_SINCE scopes CUT8 to checks taken AFTER the apply. Without it the
# monitors' rolling window still contains the cutover's own propagation failures
# at T+20, every monitor scores a REGRESSION, and the gate that decides whether
# to perform a SECOND destructive change is biased toward rollback by the very
# outage it is measuring.
export CUTOVER_SINCE="$(date -u -d '-2 minutes' +%Y-%m-%dT%H:%M:%SZ)"   # set once, at the apply

# No nested `doppler secrets get`: prd_terraform already carries SENTRY_ORG,
# SENTRY_AUTH_TOKEN and BETTERSTACK_API_TOKEN_READONLY. The nested read could
# only overwrite a correct value with an empty one, which reads as four
# unverifiable monitors and exit 2 forever.
doppler run -p soleur -c prd_terraform --command \
  "bash apps/web-platform/infra/cutover-verify.sh --expected-sha $PF_SHA"
```

| exit | meaning | what to do |
|------|---------|-----------|
| 0 | every assertion passed | take another sample; three consecutive clean at 60 s |
| 1 | at least one assertion FAILED | the rollback path below |
| 2 | nothing failed, something was UNREACHABLE | **re-run.** An assertion that could not be evaluated is not one that passed, and this is not clearance to proceed |
| 64 | usage error, or the runner refused to start | fix the invocation. This used to share code 2, so a mistyped flag read as "re-run" and an operator under T+20 pressure would retry it forever |

**Do not run it under `bash -x`.** It authenticates with
`curl -H "Authorization: Bearer …"`, and `set -x` traces every argument, so the
Sentry and BetterStack tokens are printed in full. That has already happened once
(#7797).

### CUT8 judges REGRESSION, not absolute health, and you need to know why

`soleur-ai-www` is in an active failure incident *before* this cutover: it records
its own correct `301` as a failure because the `equals 301` assertion declared in
`sentry/uptime-monitors.tf` is not live on the monitor (#7798). Read absolutely,
"all five monitors green" can therefore never be true, and the T+20 rule below
turns any CUT8 failure into a rollback — so a perfectly healthy cutover would be
rolled back on a defect that predates it.

CUT8 compares against `apps/web-platform/infra/cutover-monitor-baseline.txt` and
fails only on a monitor that was healthy at baseline and is unhealthy now. A
monitor that was already red is printed as `pre-existing`. If #7798 is fixed
before the cutover, re-capture the baseline first:

```bash
bash apps/web-platform/infra/cutover-verify.sh --capture-monitor-baseline \
  apps/web-platform/infra/cutover-monitor-baseline.txt
```

### The T+20 budget, and what eats it

The decision point is 20 minutes from the apply. Two things consume that budget
before you get to spend it on judgement:

- **The rollback's apply queues behind the apply it is rolling back.** An earlier
  version of this section said `deploy-docs.yml` and the infra apply share a
  concurrency group. They do not — `deploy-docs.yml` is `group: "pages"` and the
  infra apply is `group: terraform-apply-web-platform-host`. The real queue is
  tighter than that and was not stated: the forward apply and the rollback apply
  are the SAME workflow and therefore the same group, with
  `cancel-in-progress: false`, and that workflow's own comment budgets a worst
  case of preflight 1 + apply 41 + notify 5 = 47 minutes. So at T+20 the rollback
  can be queued behind the tail of the very run you are rolling back.

  The lever is therefore confirming the forward run has actually CONCLUDED
  (`gh run watch`), not pre-baking CI. Still generate the rollback PR at PF8' —
  a green PR is one less thing to wait on — but do not mistake that for the
  thing that clears the queue.
- **Three consecutive clean samples at 60 s is three minutes minimum**, and only
  if the first three are clean. Budget two sampling rounds, not one.

**Hypothesis Z measured FALSE 2026-09-03.** The apex serves from GitHub Pages,
not Cloudflare, so the record swap is what moves the origin. Re-probe with
`apex-origin-probe.sh` within the hour before merging; a Cloudflare verdict
before the merge means the origin moved without the record and the plan shape
changed under the ack — **stop**.

## Rollback

> ### READ THIS BEFORE `### Procedure` — PR5 CHANGED THE ORDER
>
> `### Procedure` below is written for the pre-PR5 world and its **step 1 is the
> DNS revert**. Since PR5 (2026-09-03) the DNS revert is the LAST act, not the
> first: GitHub Pages content is frozen at the last PR4-era build, so doing it
> alone serves stale content under the real domain and `### Procedure` step 3
> will tell you that you are finished.
>
> **Act 0 — PRECONDITION, check before anything else.**
> `grep -c 'ssl *= *"full"' apps/web-platform/infra/seo-config-rules.tf` must
> return `1`. The GitHub Pages origin certificate expired 2026-08-16; that
> Configuration Rule is the ONLY thing keeping the apex on TLS once it points
> back at GitHub Pages. Without it the apex returns **HTTP 526**, and
> `soleur.ai` is HSTS-preloaded, so there is no `http://` fallback. If it is
> missing, restore it before touching DNS (#7799 holds the removal conditions).
>
> **Act 1 — re-add the publish leg** to `.github/workflows/deploy-docs.yml`
> (the three `actions/*-pages*` steps, the `environment:` block, and the
> `pages:`/`id-token: write` grants) and merge it.
>
> **Act 2 — let it run so GitHub Pages holds a CURRENT build.** Acts 1 and 2 are
> ONE merge, not two: `deploy-docs.yml` is inside its own `paths:` filter, so
> merging act 1 fires act 2 automatically. Do not sit waiting for a separate
> trigger. This act IS executable before act 3 — see the measured correction
> under `## Dual-publish` about `build_type: workflow`.
>
> **Act 3 — revert the DNS**, via
> `apps/web-platform/infra/generate-apex-rollback-pr.sh`. Never `git revert`.
> This is `### Procedure` below; start there only once acts 0-2 are done.
>
> **Act 4 — CONDITIONAL.** If `apex-origin-probe.sh` still reports
> `SERVING-FROM-CLOUDFLARE-PAGES` after act 3, the custom-domain ATTACHMENT is
> also routing: revert PR3 too (`### Procedure` step 3, which needs its own
> `[ack-destroy]`). This is why the count is "three, or four" — never a bare
> three.
>
> **The branch restriction PR5 replaced, and how it was measured.** The retired
> deployment environment carried exactly one deployment-branch policy. PR5
> replaced it with a `github.ref == 'refs/heads/main'` conjunct on the job's
> `if:`, because `workflow_dispatch` carries no ref restriction of its own and
> without it a dispatch from any branch would publish that branch to the
> production apex with both build-identity probes reporting MATCH. Re-measure
> with:
>
> ```bash
> gh api repos/{owner}/{repo}/environments/github-pages/deployment-branch-policies \
>   --jq '{total: .total_count, policies: [.branch_policies[] | {name, type}]}'
> # measured 2026-09-03 -> {"total":1,"policies":[{"name":"main","type":"branch"}]}
> ```
>
> **Preconditions measured 2026-09-03, so acts 1-2 are not speculative:**
> `gh api repos/{owner}/{repo}/pages` -> `cname: soleur.ai`,
> `build_type: workflow`. The custom-domain binding SURVIVED the PR4b cutover,
> so act 2 has somewhere to publish to. Re-measure before relying on it.

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

### PF8' — generate the rollback PR immediately, not when you need it

Within minutes of the PR4b merge, and in parallel with the propagation wait:

```bash
bash apps/web-platform/infra/generate-apex-rollback-pr.sh --open-pr
```

Its CI then runs concurrently with the verification window, so at T+20 the
rollback is already green and mergeable. The generator asserts `[ack-destroy]`
landed on its own line in the **branch commit body** before pushing — read the
commit body (`git log -1 --format=%B`), never `gh pr view --json`, because none
of those fields can see a commit body and the ack landing in the squash message
is the single point of failure for the whole rollback.

### If the apply dies mid-replace

The replace is Delete-then-Create at one address, so there is a window in which
the `A` record is gone and the `CNAME` is not yet created. If the apply fails
inside it, the apex has no address at all and resolves NXDOMAIN.

**Re-run the failed job.** The remaining plan is a bare create — the delete has
already happened — so it passes the destroy-guard **unacked** and needs no new
`[ack-destroy]`. Do not reach for the rollback generator here: there is nothing
to move back, because the source address is already gone from state, and the
generated `moved` would no-op exactly as a mismatched forward one would.

### Procedure

1. **Do NOT `git revert` PR4b.** Generate the rollback PR instead:

   ```bash
   bash apps/web-platform/infra/generate-apex-rollback-pr.sh
   ```

   **The generator ships WITH PR4b** (it is that PR's own deliverable). Between
   the PR4a and PR4b merges it does not exist — and it does not need to, because
   nothing is flipped yet and PR4a's rollback is a plain revert (above).

   **If the script is missing mid-incident, the fallback is TWO edits, not one.**
   An earlier version of this runbook showed only the `moved` block. That is
   worse than useless: it moves state into an address that has no `resource`
   block in configuration, and Terraform's response to a state entry with no
   config is to plan it for DESTROY. The result is `1 to destroy, 0 to add` —
   the apex loses its address entirely — and no guard catches it, because
   `apex_move_orphans` counts a `pages_apex` CREATE and this plan has none.

   Delete the `resource "cloudflare_record" "pages_apex"` block and the forward
   `moved` block, then add BOTH of these:

   ```hcl
   moved {
     from = cloudflare_record.pages_apex
     to   = cloudflare_record.github_pages
   }

   resource "cloudflare_record" "github_pages" {
     zone_id = var.cf_zone_id
     name    = "soleur.ai"
     content = "185.199.108.153"
     type    = "A"
     proxied = true
     ttl     = 1
   }
   ```

   Also return `cloudflare_record.www`'s `content` to `"jikig-ai.github.io"`.
   Leave its `name` and `type` alone — `type` is ForceNew, so editing it makes
   www a second replacement racing the apex's.

   Note the reverse `moved` targets a PLAIN address, with no `for_each`. That
   meta-argument was an artifact of the pre-PR4a four-address config; using it
   here would make the rollback a multi-instance move rather than the
   single-address one core serialises.

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
   - `SERVING-FROM-GITHUB-PAGES` — the DNS half is done. **Post-PR5 that is
     "complete" only for AVAILABILITY, and only if acts 1-2 ran first.** If they
     did not, the apex is now serving the frozen last-PR4-era build: go back to
     the acts 0-4 block at the top of `## Rollback` and do acts 1-2, which will
     republish current content to the origin you just pointed at.
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

### PR5 NARROWED THE ROLLBACK: three acts, or four — rationale

**This section describes the state from PR5 (#7640, AC33/AC56) onward.** The
ordering summary now lives at the TOP of `## Rollback` as acts 0-4, because a
correction 150 lines below the procedure it corrects is not a correction. This
section is the rationale behind it.

An earlier revision of this paragraph told the reader to distrust "anything
above that says a DNS-only revert IS the rollback" — a string that appeared
nowhere above it. The claims it meant are `## Dual-publish` ("it is the rollback
target, and it is kept current"), now retitled as history with a state banner,
and `### Procedure` step 1, now preceded by the acts 0-4 block.

PR5 deleted the GitHub Pages publish leg from `deploy-docs.yml` (the three
`actions/*-pages*` steps, the deployment `environment:` block, and the
`pages:`/`id-token: write` grants). Consequences, in the order they bite:

1. **The retained GitHub Pages content is FROZEN** at the last PR4-era build.
   Nothing republishes to it, and nothing re-asserts its `CNAME` file.
2. **Restoring that origin now takes THREE acts, or FOUR** — the canonical
   list is the acts 0-4 block at the top of `## Rollback`; it is not repeated
   here so the two cannot drift. The fourth is conditional: if
   `apex-origin-probe.sh` still reports `SERVING-FROM-CLOUDFLARE-PAGES` after
   the DNS revert, the custom-domain ATTACHMENT is routing independently of the
   record and PR3 must be reverted too. **Never quote a bare "three".**
3. **The apex cutover rollback itself is unchanged and still one act** — the
   generated reverse-`moved` PR. What changed is what that rollback LANDS ON.

So a rollback three weeks after the cutover serves three-week-old docs unless
act 2 runs first. Acceptable for an availability rollback; stated here, in
`deploy-docs.yml`'s own comment, and in the re-evaluation criteria on #7799, so
nobody rediscovers it mid-incident.

**What the pre-PR5 verification actually covered, stated so it is not
over-read.** CUT0'-CUT9 held across three consecutive clean samples at 60 s,
~90 minutes after the apply. Every one of those ten assertions is a
POINT-IN-TIME read (an HTTP code, a header, a redirect code, an MX/TXT set
comparison), so three samples bound FLAPPING and nothing else. They did NOT and
could not observe the class the plan itself calls brand-fatal and
asymmetric-recovering: search-index health. No CUT row, neither build-identity
probe, and none of the five uptime monitors samples crawl or index state, and a
90-minute window cannot contain a Googlebot cycle. If the index degrades, the
signal is Search Console coverage or a sitemap-fetch check — not anything in
this runbook — and the remedy is the three-to-four-act rollback above onto
frozen content, which is precisely what PR5 made more expensive. This is a
disclosed residual, not a defect: same-session merge was chosen for the flap
class and for CI hygiene (a standing red required check on every docs merge is
how real signal gets ignored), not because 90 minutes settled the index class.

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
