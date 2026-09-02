# Runbook — soleur.ai cutover to Cloudflare Pages (ADR-194)

Covers the ADR-194 migration of the marketing/docs site off GitHub Pages, the
rollback path, and content rollback after the deploy mechanism changed.

Every step here happens by **merging a pull request**. The applies are performed
by `apply-web-platform-infra.yml` on merge to `main`; the docs deploy is
performed by `deploy-docs.yml`. There is no console step and no shell step in
this runbook.

## Sequence

| PR | Contents | Applied by | Reverting it removes |
|---|---|---|---|
| PR1 | Pages project, Actions secrets, www Bulk Redirect, cert-reissue disarmament | apply-web-platform-infra | the substrate |
| PR2 | `deploy-docs.yml` swap to wrangler | deploy-docs | the deploy path |
| PR3 | `cloudflare_pages_domain.apex` + `.www` | apply-web-platform-infra | the custom-domain attachment |
| PR4 | the `dns.tf` record swap | apply-web-platform-infra | the DNS record |

## State after PR2 (this PR)

`deploy-docs.yml` publishes to the `soleur-docs` Pages project. The apex is
**still GitHub Pages** until PR4. Consequences, stated so they are not
discovered:

- `soleur.ai` serves the **last GitHub Pages build** and stops advancing. Docs
  merged between PR2 and PR4 are live on `soleur-docs.pages.dev` and not on the
  apex. The longer PR4 is delayed, the staler the public site.
- The post-deploy build-identity probe runs **reporting-only** and targets
  `soleur-docs.pages.dev`, because the apex it will eventually assert about is
  not yet served by this project. PR4 repoints it at `https://soleur.ai/version.txt`
  and removes `continue-on-error`.
- `_site/CNAME` and `_site/.nojekyll` are now **publicly served static files**
  (`https://soleur-docs.pages.dev/CNAME`). GitHub Pages consumed them; Pages
  does not. This is not a leak — `CNAME` contains the public hostname. It is
  recorded here so a later reader does not mistake it for one. `CNAME` stays in
  the build because it is part of the GitHub Pages configuration retained for
  rollback.

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

1. Merge the pre-opened revert of **PR4**. This restores the apex DNS record to
   GitHub Pages. Requires `[ack-destroy]`.
2. Confirm which origin is actually serving:
   `bash apps/web-platform/infra/apex-origin-probe.sh`
   It reports `SERVING-FROM-GITHUB-PAGES`, `SERVING-FROM-CLOUDFLARE-PAGES`, or
   an explicit `UNREACHABLE` — it never reports an origin it did not observe.
3. If it still reports `SERVING-FROM-CLOUDFLARE-PAGES`, merge the revert of
   **PR3** as well. Custom-domain attachment, not only the DNS record, can
   establish edge routing for a hostname.

Step 3 is why the cutover is four PRs rather than three. Each PR introduces
exactly one origin-selecting mechanism, so **whichever one is actually
selecting the origin, reverting the PR that introduced it removes it.** The
procedure is correct without knowing in advance which of the two it is.

> **PF7 is retired, and this is why.** An earlier revision of the plan
> scheduled a scratch-custom-domain attach/detach probe in PR2 (D3 open item
> 3(b)) to decide whether a DNS-only revert is sufficient. The 2026-08-20
> four-PR amendment retires that question **by construction instead of by
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

Re-running a previous green workflow run is **no longer the mechanism**. The
previous mechanism was GitHub Pages redeploying a stored artifact; wrangler
uploads from the runner's `_site`, so a re-run rebuilds from whatever the
workflow checks out.

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
   commit. Before PR4 that probe is reporting-only, so read its output rather
   than relying on the job's colour.

`wrangler pages deployment delete` removes a deployment but does not select
which one the production branch serves; do not reach for it as a rollback.

## Cutover verification (PR4)

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
