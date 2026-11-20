---
title: The plan-gate fixture was a shape the provider never emits, and a per-shape guard lost to five siblings
date: 2026-11-20
category: integration-issues
module: tests/scripts/lib/destroy-guard-filter-web-platform.jq, tests/scripts/lib/deploy-policy-gate.sh, apps/web-platform/infra/tunnel.tf
tags: [terraform, plan-json, policy-gate, cloudflare-access, review-fix-rounds, fixtures, ratchet, draft-ci]
issue: 12937
pr: 12958
---

# Learning: build plan-gate fixtures from a real plan, and gate a resource family by address

## Problem

After the soleur.ai zone moved to another Cloudflare account, the tunnel and its Access gate stayed in the old account. cfargotunnel CNAMEs route only within one account, so the CI zot bridge failed with `websocket: bad handshake`. The fix (ADR-330) re-homes the tunnel slice under new `_soleur` Terraform addresses. It also extends the deploy-policy gate, which refuses an unacknowledged Access policy change in the unattended merge apply.

Review found two gate defects:

1. **The test fixture had a shape the provider never emits.** The gate's GREEN rows used a hand-written plan with `include[0].service_token: [null]` for the token that is unknown at plan time. The locked cloudflare 4.52.7 provider leaves `service_token` out of `after` and sets `after_unknown.include[0].service_token: true`. The gate refused that real shape, so the first merge apply would have halted with the bridge still down. Every suite was green.
2. **The per-shape guard lost to five siblings.** After round 1, the gate counted stray policies by shape. The fix-round security seat then found five sibling shapes it did not count: a module address, an indexed sibling, a reusable policy, a policy on an old app, and a re-created legacy app.

## Solution

- **Real fixture:** captured a real offline `terraform show -json` plan with the locked providers, synthesised its values, and stored it as `tests/scripts/fixtures/tfplan-access-policy-soleur-create.json` (and `…-app-soleur-create.json` for the apps). Added a gate arm for the unknown-include shape.
- **Address allowlist:** replaced the counter with `access_family_table`, a list of every Access app and policy address with a role. Any family change whose address is not in the table, in any module, is unsafe with no ack path. Static row Q12 checks that the table equals the family's `resource` and `removed` blocks across every `*.tf`, so the table cannot drift from the code. The suite header lists the residuals (for example a new ingress hostname with no Access app, filed as #13002).

## Key Insight

A plan-time gate is only as good as the plan it was tested against. Unknown values and nested blocks are where hand-written plan JSON goes wrong. And when a fix round finds sibling shapes of a guard, the guard is keyed on the wrong thing: gate the family by address and pin the list to the code.

## Session Errors

1. **The fixture used a synthetic plan shape** that would have halted the first merge apply. Recovery: a real capture plus a gate arm for it. **Prevention:** routed to `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` (fix-round bullet): build such fixtures from a real `terraform show -json`.
2. **A per-shape guard was bypassed by five siblings.** Recovery: address allowlist plus static table-equals-code row. **Prevention:** same routed bullet.
3. **A fix agent dropped `2>&1` on the Doppler publish lines**, reversing #7133 (Doppler's stderr can carry the config table into a public log). Recovery: a `pub()` helper with `>/dev/null 2>&1` and an explicit `::error::`. **Prevention:** before removing a redirect, run `git log -S'2>&1' -- <file>` and read why it was added.
4. **`apply-web-platform-infra.yml` went over the 490,000-byte size gate** (P1). Recovery: trimmed comments. One fix agent then reported 15 B of headroom against its own 489,500 self-cap; the real gate leaves 515 B. **Prevention:** quote headroom against the gate's own constant, read from the test.
5. **Six repo-wide ratchets went red after round 1** (diagnosis claims, kb-consumers, corpus weight, census sweep shape, web-hosts ceiling, fixture UUID allowlist). **Prevention:** already covered in the review reference ("A fix agent's suite green covers only the files it was given").
6. **While the PR was DIRTY, every `pull_request` workflow was suppressed**, so only 6 checks reported. Recovery: merged `origin/main`. **Prevention:** already covered in review/SKILL.md (read `mergeStateStatus` before reading checks).
7. **The web-hosts IP count was inflated by conflict stages mid-merge.** The real +3 came from fixture IPs after main lowered the ceiling. **Prevention:** already covered in work/SKILL.md (regenerate a whole-repo ratchet only after the merge commit exists).
8. **My verification loop `echo "$(basename $t) RC=$?"` reported `basename`'s exit code**, so the forget suite showed RC=0 while it exited 1. Caught by a re-run. **Prevention:** already covered in work/SKILL.md: run `rc=$?` immediately after the command, then echo.
9. **kb-consumers hit the 600 s limit under host load** (rc 124, 4/31 "failed"). It passed 31/31 with a 1,500 s limit. **Prevention:** an rc of 124 is no verdict, so re-run with a longer bound before reading the counts.
10. **Relying on CI for a draft PR:** draft-light CI skips the heavy families, and `test` is red by design until ready. **Prevention:** already covered (learning 2026-11-11 on draft-light CI); the full battery runs at ready.
11. **`gh issue create` was blocked twice**: first because the body file was in the scratchpad, which the gate cannot read, then because the issue named no user-visible consequence. Recovery: wrote the body in the worktree and added `meta/machinery`. **Prevention:** write issue bodies inside the worktree, and label gate or guard findings `meta/machinery` up front.
12. **The privacy plugin refused a command naming the argv-bearer sweep suite, and the `pgrep -f` hook blocked a call.** **Prevention:** run that suite only through `scripts/test-all.sh`, and use `proc.sh list_runs` instead of `pgrep -f`.
13. **Forwarded from planning:**
    - a plan-write hook flagged Phase 0 wording (resolved with the iac-routing ack);
    - `gh run view --log-failed` output was truncated and `dig` is absent (used REST and DoH);
    - the architecture reviewer's first report was empty (re-asked).

    **Prevention:** one-offs.
14. **Pre-existing reds (not caused by this PR):** the inngest pin (#12985), #12850, #12874, #12853. **Prevention:** tracked.

## Tags
category: integration-issues
module: terraform policy gate
