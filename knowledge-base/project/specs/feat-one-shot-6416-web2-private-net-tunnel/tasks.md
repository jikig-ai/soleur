# Tasks — fix: web-2 private-net attachment + tunnel connector determinism (#6416)

---
lane: cross-domain
issue: 6416
plan: knowledge-base/project/plans/2026-07-15-fix-web2-private-net-attach-and-tunnel-connector-homogeneity-plan.md
brand_survival_threshold: single-user incident
---

> Derived from the **v2** plan (post 5-agent panel + advisor consult). Read the plan's
> `## Architecture Decision` and the `v2:` correction blocks before starting — four v1 claims were
> falsified by measurement, and the traps are documented there.
>
> **Do NOT** repoint `server.tf`'s `connection { host }` blocks. They must keep dialing web-1's
> **public** IP or the bridge's `-d "$SERVER_IP"` NAT rule stops matching and every provisioner dies.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm live state read-only: `hcloud server describe soleur-web-2 -o json | jq '.private_net'` → expect `[]`; `soleur-web-platform` → `10.0.1.10`. **If web-2 is already attached, STOP and re-scope** (stale premise).
- [ ] 0.2 `cloudflared tunnel info soleur-web-platform` → record the connector count (expect 2). Attach the output to the PR body.
- [ ] 0.3 Re-verify `ADR-113` is still next-free against `origin/main`. If not, renumber **and sweep** the plan + this file + AC8/AC9 in the same edit.

## Phase 1 — Restore the attachment (agent-run; no new Terraform)

- [ ] 1.1 Dispatch: `gh workflow run apply-web-platform-infra.yml -f apply_target=warm-standby -f reason="#6416 restore web-2 private-net attach"`, then `gh run watch`.
- [ ] 1.2 Capture the **attach proof** log line: `attach proof OK: hcloud_server_network.web["web-2"] present in state`. → **AC12**
- [ ] 1.3 **On RED, apply the escalation rule:** read the *attach-proof step's* outcome FIRST. The attach-proof step runs BEFORE the verify step, so a RED job with a green apply means **the attach LANDED**. Dispatch `web-2-recreate` **only if the APPLY failed** — never if only the VERIFY failed (a reflexive recreate `-replace`s the host and destroys a good attach).
- [ ] 1.4 Prove **packets, not state**: `hcloud server describe soleur-web-2 -o json | jq -r '.private_net[0].ip'` → `10.0.1.11`, **and** ≥5 consecutive registry-bridge runs succeed. A fresh host can boot with its NIC down while the control plane says "attached" (soft reboot is the remediation). → **AC13**

## Phase 2 — `host_creates` guard (RED first)

- [ ] 2.1 **RED:** add the counter test using the **existing** `tests/scripts/fixtures/tfplan-hcloud-server-create.json` (it *is* `hcloud_server.web["web-2"]` at `actions: ["create"]`). **Do not author a new fixture.** Prove the suite fails before the jq change. → **AC1**
- [ ] 2.2 Add the additive `host_creates` key to `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (type-scoped `hcloud_server`/`hcloud_volume`, `actions == ["create"]` exactly) + header doc (6th → 7th surface).
- [ ] 2.3 Assert no double-count against `tfplan-hcloud-server-location-replace.json`: `host_creates == 0`, `resource_deletes == 1`. → **AC1**
- [ ] 2.4 **Resolve T18** (`tests/scripts/test-destroy-guard-counter-web-platform.sh:335-343`). It currently asserts PASS on a per-PR web-2 create and calls it "a legit new host" — the exact belief this plan overturns. Update the assertion, name, and comment. → **AC2**
- [ ] 2.5 Thread `host_creates` through `_run_gate` (`:101-124`, currently emits `rdel:ndel:rupd:dcount:rc` — **3 counters + a derived sum + rc**, not 5). This widens **~54 counter-string sites across T1–T28**, including the T10 **comparison at `:235`** (`:238` is only the failure message). Add a **second, ack-independent rc source**.
- [ ] 2.6 Wire the HALT into the `apply` job **outside** the `destroy_count` sum (no `[ack-destroy]` bypass), mirroring `reboot_updates` at `:445-450`. → **AC4**
- [ ] 2.7 Add `host_creates` to the numeric parse validation at `apply-web-platform-infra.yml:424-427` — omitting it ships a **fail-open** guard. → **AC3**
- [ ] 2.8 Write the **per-type** `::error::` remediation: web-2 → `apply_target=warm-standby`; inngest → `apply_target=inngest-host`; **registry and a new web-3 have NO dispatch path** → operator-local full apply **before** the code merges. → **AC4**
- [ ] 2.9 Confirm `plugins/soleur/test/terraform-target-parity.test.ts` needs **no** change (its exclusion sets become true, not aspirational).

## Phase 2c — Wrong-host tripwire (ships with Phase 1)

- [ ] 2c.1 Add a **fail-closed `hostname` assertion** to the SSH-provisioner preflight in `apps/web-platform/infra/server.tf`: each `terraform_data.*` declared for web-1 asserts in-band that the shell it reached **is** `soleur-web-platform`; mismatch → abort red.
- [ ] 2c.2 **Do NOT touch `connection { host }`** (see the header warning).
- [ ] 2c.3 Note the priced objection in the PR body: this converts a silent ~50% wrong-host write into a loud ~50% apply failure. A red apply beats a green lie. Bounded re-dial retry is the escape hatch if it bites.

## Phase 3 — Un-mask the CI signal (ADR-096-consistent)

- [ ] 3.1 In `.github/workflows/reusable-release.yml`: **drop `zot_mirror`'s `if:` gate**; run it unconditionally and branch **internally** on `steps.zot_bridge.outcome == 'failure'`. This preserves `steps.zot_mirror.outputs.mirror_status` — the id the Slack append at `:846` reads — and inherits the existing `degraded()` emitter. → **AC5**
- [ ] 3.2 Branch on `== 'failure'`, **NOT** `!= 'success'` (`zot_bridge` is itself gated on the build, so a build failure leaves it `skipped` — which must stay silent).
- [ ] 3.3 Re-materialize the emitter's inputs: recompute `ZOT` (a shell local at `:746`), re-declare `IMAGE` (step-scoped `env:` at `:680`; available as `inputs.docker_image`), and pass a **sentinel `rc`** — a composite `uses:` action exposes no numeric exit code.
- [ ] 3.4 Verify `continue-on-error: true` is still on both steps by **reading them** (not `grep -c`, which returns 7 file-wide). → **AC6**
- [ ] 3.5 Fix `.github/actions/cf-tunnel-registry-bridge/action.yml:3-5` — stale twice: "the web host's cloudflared" (singular) and `http://10.0.1.30:5000` (should be `tcp://`).

## Phase 4 — Architecture record

- [ ] 4.1 Author **ADR-113** via `/soleur:architecture`: the `localhost:`-category-error finding; **I1** as a **runtime** precondition (it is falsified by construction as an apply-time one — the token is granted at server-create, the attach always lands after); **I2**; the per-hostname anti-pattern; both candidate implementations. Status `adopting`. **Cite** ADR-068:378-384's rejection of per-host tunnels — do not re-decide it.
- [ ] 4.2 Amend **ADR-008** → `superseded-in-part` (precedent: ADR-043). Two staleness proofs: single-host `localhost:` routes, and its claimed `app.` route does not exist.
- [ ] 4.3 Amend **ADR-068** → **extend the already-stated finding** (`:354-357` states connector nondeterminism verbatim) to `ssh.`/`registry.`. Do **not** frame it as an omission. **Also correct its stale count** at `:383`: "the 11 SSH provisioners" → **12** (measured: 12 `terraform_data.*` `connection { host }` blocks in `server.tf`; a 13th, `deploy_pipeline_fix`, has none).
- [ ] 4.4 **ADR-096:** leave `## Decision` unchanged (precedent, vindicated). An optional non-blocking note on its falsified singular-connector premise is permitted. → **AC9**
- [ ] 4.5 `model.c4`: amend the `platform.infra.tunnel` description + add `tunnel -> zotRegistry`, `hetzner -> tunnel`, `github -> tunnel`. No new `include` needed (all three are already in the `containers` view). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`. → **AC8**
- [ ] 4.6 Correct the `tunnel.tf:58-63` misattribution comment (comment-only; no resource diff).
- [ ] 4.7 File the **audit** issue: "Audit web-1 vs web-2 for the 12 provisioner-applied host configs — Terraform state may be false." Labels `type/bug`, `priority/p1-high`, `domain/engineering`. Unblocked by Phase 2c. → **AC10**
- [ ] 4.8 File the **I2** issue: "Deterministic tunnel origin for host-specific routes (ADR-113 I2)." Must carry candidate (b) as the leading shape; the `-d "$SERVER_IP"` NAT rework + a new TF output for the private address + two-listener/two-NAT-rule requirement if (a); ADR-068's prior rejection; `WEB_HOST_PRIVATE_IPS` single-sourcing; the `ssh.`-retirement follow-up; the ADR-082 stale `monitored = false` note. → **AC10**

## Phase 4b — File the adjacent findings (file, do not execute)

- [ ] 4b.1 Issue: "`hcloud_firewall_attachment` does not attach before first boot — a per-PR-born host boots unfirewalled" (provider 1.63.0 docs). Labels `type/bug`, `priority/p2-medium`, `domain/engineering`.
- [ ] 4b.2 Issue: "The 12h drift detector always alarms — exit 2 is the permanent steady state" (10+ `terraform_data` resources permanently show "will be created"). Labels `type/bug`, `priority/p2-medium`, `domain/engineering`.

## Phase 5 — Hygiene + enrollment

- [ ] 5.1 Remove the two stale `-target`s at `apply-web-platform-infra.yml:370-371` (`cloudflare_record.web_host`, `betteruptime_monitor.web_host` — both resources deleted per `dns.tf:22-27`). → **AC7**
- [ ] 5.2 Write `scripts/followthroughs/zot-mirror-connector-6416.sh` (exit 0 when ≥7 days after the P1 apply show zero `zot mirror degraded` across ≥3 releases; `start=` pinned strictly after the deploy). Mirror `reconcile-ff-only-sentry-4977.sh`. → **AC11**
- [ ] 5.3 Add the `soleur:followthrough` directive + `follow-through` label to the tracker; confirm `secrets=BETTERSTACK_API_TOKEN` is wired in `.github/workflows/scheduled-followthrough-sweeper.yml`. → **AC11**

## Phase 6 — Verify + ship

- [ ] 6.1 `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` green.
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (**not** `npm run -w` — the repo root declares no `workspaces`), and `./node_modules/.bin/vitest run <path>` for any `apps/web-platform/test/**` suite.
- [ ] 6.3 Walk every AC. **Run each verification command** — do not assert what it returns (v1's AC6 returned 7, not 2; its "retro-proof" measured 0). Use `|| true` on `grep -c` (it exits 1 on zero matches and would abort a `set -e` script on success).
- [ ] 6.4 PR body: use **`Ref #6416`**, not `Closes` — the restore is an apply-time action and `Closes` would auto-close at merge before state is proven. Close via `gh issue close 6416` after AC12/AC13/AC14.
- [ ] 6.5 PR body must explain the **T18 change** (it looks like weakening a test; it is the codified belief being overturned).
- [ ] 6.6 `/soleur:ship` — re-verify the ADR ordinal at the collision gate.
