---
date: 2026-04-29
category: bug-fixes
tags: [terraform, infra-drift, ci-deploy, cloudflare-access, post-apply-verification, ops-remediation]
related_issues: ["#3019", "#3034", "#2881", "#2874", "#2618"]
related_prs: ["#3022", "#2880"]
related_files:
  - apps/web-platform/infra/server.tf
  - apps/web-platform/infra/ci-deploy.sh
  - knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md
---

# Post-apply verification for `deploy_pipeline_fix` drift: CF Access broke the HTTP-200 contract

## Problem

The 9th `terraform_data.deploy_pipeline_fix` drift remediation (#3019, 2026-04-29) hit a stale acceptance criterion that has been wrong since at least #2618 (8 cycles). The canonical webhook smoke-test:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://deploy.soleur.ai/hooks/deploy-status \
  -H "X-Signature-256: sha256=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" -hex | awk '{print $2}')"
```

documents **Expected: HTTP 200**. As of #3019 it returns **HTTP 403**. The body is a Cloudflare Access challenge page — `deploy.soleur.ai/hooks/*` sits behind `cloudflare_zero_trust_access_application.deploy` (`apps/web-platform/infra/server.tf`). Anonymous probes are rejected at the Access edge before reaching the HMAC validator. Every prior remediation operator presumably ignored the 403 or substituted manually without updating the AC, because the underlying drift fix worked regardless.

## Root cause

The HTTP probe is **proxy-layer** verification (does the public hostname respond + does HMAC validate?) but the thing it's actually trying to confirm is **provisioner-layer** state (did the 4 file provisioners write to disk and did remote-exec restart webhook?). When CF Access landed in front of `/hooks/*`, the proxy-layer signal degraded but the provisioner-layer reality was unaffected — so 8 remediations succeeded with a green AC marker that was actually red.

## Solution

Replace the HTTP probe with a direct provisioner-layer contract:

```bash
LOCAL_HASH=$(sha256sum apps/web-platform/infra/ci-deploy.sh | awk '{print $1}')
ssh -o ConnectTimeout=5 root@<server-ip> \
  "sha256sum /usr/local/bin/ci-deploy.sh && systemctl is-active webhook"
```

- Server-side hash matches `$LOCAL_HASH` → all 4 file provisioners landed correctly (extends to `webhook.service`, `cat-deploy-state.sh`, `hooks.json.tmpl` if you sweep all four).
- `systemctl is-active webhook` returns `active` → remote-exec restart succeeded.

This is a **stronger** contract than the HTTP probe, not weaker: the HTTP probe only proves "webhook is up and HMAC validates"; the file+systemd check proves the exact thing the apply was meant to deliver.

If you genuinely need the HTTP path (e.g., debugging the webhook code itself), inject CF Access service-token headers from `cloudflare_zero_trust_access_service_token.deploy`:

```bash
curl ... \
  -H "CF-Access-Client-Id: $CF_ACCESS_DEPLOY_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_DEPLOY_CLIENT_SECRET" \
  -H "X-Signature-256: ..."
```

Issue #3034 tracks updating the canonical postmerge runbook.

## Key insight

**Verification contracts decay silently when the surface they probe acquires intermediate proxies.** The original probe was correct when there was nothing in front of `/hooks/*`. CF Access landed at some point — TF state shows the resource exists but the commit that introduced it didn't update the post-apply AC across the 8 plans referencing it. **Anti-pattern:** "expected HTTP 200" without specifying what failure mode that 200 is meant to detect. **Better:** name the underlying invariant ("file SHA matches and service is running") and choose the cheapest probe that observes it directly.

## Prevention

- For ops-remediation plans whose verification depends on a public hostname, prefer **direct provisioner-layer probes** (server-side hash, `systemctl is-active`, file mtime) over **proxy-layer probes** (HTTP status, JSON response).
- When adding a Cloudflare Access app or other proxy in front of an existing endpoint, grep `knowledge-base/project/plans/` and `plugins/soleur/skills/postmerge/` for the hostname and update any HTTP-status assertions in the same PR.
- Verify `terraform output` names by running `terraform output` once during deepen-plan; do not infer names from convention. (#3019 plan prescribed `server_ipv4`; actual is `server_ip`.)

**Resolved:** 2026-04-29 — file+systemd contract canonicalized in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` ("When NOT to use this probe") and surfaced from `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" alongside the structural fix from #2881. See plan `knowledge-base/project/plans/2026-04-29-fix-deploy-pipeline-fix-ship-gate-and-postapply-contract-plan.md`.

## Session Errors (PR #3022 session)

- **`terraform output -raw server_ipv4` failed.** Plan inferred output name from convention; actual name is `server_ip`. Recovery: ran `terraform output` to enumerate. Prevention: deepen-plan must enumerate outputs once, not assume.
- **Webhook smoke-test returned 403, not 200.** Plan, 8 prior remediations, and #2874 resolution comment all assert HTTP 200. Recovery: substituted SHA256+systemctl contract; filed #3034. Prevention: this learning + skill route below.
- **Plan acceptance-criteria boxes pre-checked `[x]` at PR-creation time.** Code-quality review caught plan-as-spec drift. Recovery: restructured into `## Resolution Log` table + forward-looking `[ ]` AC. Prevention: ops-remediation plans separate AC (forward-looking) from execution log (actuals).
- **Filed follow-up issue with a placeholder issue number.** I wrote `#3023` in the plan before `gh issue create` returned the real number `#3034`; had to grep+replace. Recovery: trivial. Prevention: file the follow-up first, capture the URL, then reference it.
- **Plan declared `tasks.md` would be created; never created.** Discoverable; review caught it. Prevention: review.
- **Self-contradicting occurrence count (9th vs 10th in same paragraph).** Discoverable; review caught. Prevention: review.

## Cross-references

- Underlying recurring-drift cycle: [`2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`](./2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md)
- Resource definition: `apps/web-platform/infra/server.tf:209-269`
- CF Access app: `apps/web-platform/infra/server.tf` (`cloudflare_zero_trust_access_application.deploy`)
- Structural prevention: #2881 (post-merge `/ship` gate; threshold met by #3019 as the 9th cycle)
