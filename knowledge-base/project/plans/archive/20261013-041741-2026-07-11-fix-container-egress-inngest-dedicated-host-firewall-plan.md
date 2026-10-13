---
title: "fix: allow container egress to the dedicated Inngest host (:8288)"
date: 2026-07-11
type: fix
branch: feat-one-shot-fix-container-egress-inngest-firewall
epic: "#6178"
adr: "ADR-100 (contextual citation, NOT Closes)"
priority: P1
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# 🐛 fix: allow container egress to the dedicated Inngest host (:8288)

## Enhancement Summary

**Deepened on:** 2026-07-11
**Mandatory gates run:** 4.5 network-outage (fired — `firewall` keyword; telemetry emitted),
4.55 downtime/cutover (fired — corrected), 4.6 user-brand (pass), 4.7 observability (pass),
4.8 PAT-shaped var (pass — none), 4.9 UI-wireframe (skip — no UI surface).
**Review agents:** architecture-strategist (IaC/delivery), general-purpose (test-assertion
shell verification). Proportionate focused set for a trivially-mechanical single-rule change.

### Key improvement (load-bearing correction)

1. **The task's delivery-path premise was factually WRONG and is corrected.** The task stated
   merging "does not push to running hosts; lands only on recreate; `apply-web-platform-infra.yml`
   does not fire." Verified against the repo: the workflow triggers on the **path-glob**
   `apps/web-platform/infra/**` (not `*.tf`), `terraform_data.cron_egress_firewall` **is** in the
   `-target` set and folds the loader into its `config_hash`, so **merging re-provisions web-1 and
   restarts its live firewall**. The **code change is unchanged and correct**; the Downtime,
   Infrastructure (IaC), Delivery Context, and AC8/AC9 sections were rewritten to the true model,
   and the correction is recorded in `decision-challenges.md` for `ship` to surface.
2. **Conclusion survives:** still SAFE TO MERGE NOW (zero-downtime — gap-free restart + inert
   rule) and still MUST merge before the cutover recreates. web-1/web-2 asymmetry acknowledged.

### Verified (no change needed)

- All prescribed **test-assertion edits are shell-correct** (ERE paren-safety, line-order grep,
  awk-block placement, `SENTINEL_COUNT>=15` floor, UNGUARDED-command meta-check, `nft list`
  render form). No exact rule-count assertion exists to re-baseline.
- Rule **placement is correct** (first-match-wins; earlier drops are `dport 53`-scoped).
- `10.0.1.40` is the canonical IP (`inngest-host.tf:33`); wrong-mechanism rejections
  (allowlist.txt / CIDR file) are right; IPv6 is genuinely N/A (loader IPv4-only + bypass guard).

## Overview

The web-platform container runs behind a **default-DROP** nftables allowlist (the
`SOLEUR-EGRESS` chain in `apps/web-platform/infra/cron-egress-nftables.sh`).
Container→external traffic traverses `FORWARD → DOCKER-USER → SOLEUR-EGRESS`; anything
not explicitly accepted hits the terminal `counter drop`.

Today the **only** `:8288` accept is for the docker host-gateway (`$BRIDGE_GW`) — the
**old co-located loopback Inngest path**:

```
# cron-egress-nftables.sh:150 (current)
add rule ip filter SOLEUR-EGRESS ip daddr $BRIDGE_GW tcp dport 8288 accept comment "soleur-egress: host-gateway inngest"
```

The epic #6178 / ADR-100 cutover repoints the app's `INNGEST_BASE_URL` to the **dedicated
host** `http://10.0.1.40:8288` — a *different* host on the Hetzner private net
(`inngest-host.tf:33 → inngest_private_ip = "10.0.1.40"`; web hosts are `.10/.11`, so the
dedicated Inngest host's own ingress nftables already accepts from `10.0.1.10,10.0.1.11`
— the missing rule is purely on the **web side's egress**).

Post-cutover, a container→`10.0.1.40:8288` packet matches **nothing** in `SOLEUR-EGRESS`:

- not the host-gateway rule (`$BRIDGE_GW` ≈ `172.17.0.1`, not `10.0.1.40`),
- not `@soleur_egress_allow` (populated from `cron-egress-allowlist.txt`, which is a
  **hostname** list DNS-resolved by `cron-egress-resolve.sh` — a bare private IP cannot
  be expressed there),
- not `@soleur_egress_allow_cidr` (GitHub git-LB CIDR ranges only).

→ it falls through to the default `counter drop`. **Every `inngest.send()` event POST is
silently dropped → missed reminders/crons.**

The gap hides from the cutover gate because `op=verify` only checks registry-non-empty
(registration is **inbound** to the app, unaffected by egress filtering) and the host-side
probes (`inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`) run **on the host**,
whose egress is unfiltered.

**The fix is minimal and additive:** one accept rule for `10.0.1.40:8288`, mirroring the
existing host-gateway rule, placed immediately after it (before the allowlist and default
drop). This is **P1 on the cutover critical path**.

## Research Reconciliation — Spec vs. Codebase

All premises in the task description were verified against `origin/main` state (this
worktree) before drafting. **One divergence found** (the delivery-path premise — row marked
⚠️ below; corrected by the deepen-plan architecture review).

| Premise (as stated) | Codebase reality | Plan response |
| --- | --- | --- |
| Host-gateway `:8288` rule at ~line 150 | ✅ exact match at `cron-egress-nftables.sh:150` | Insert new rule immediately after |
| Canonical dedicated IP `10.0.1.40` | ✅ `inngest-host.tf:33 inngest_private_ip = "10.0.1.40"` | Use literal `10.0.1.40` |
| `cron-egress-allowlist.txt` is DNS-resolved (bare IP can't go there) | ✅ header: "One hostname per line … resolves these to IPv4 on a systemd timer" | Do NOT touch allowlist.txt |
| CIDR file is GitHub-only | ✅ `cidr allowlist (github git LB ranges)` comment at `:152` | Do NOT touch CIDR file |
| Script in `server.tf` host-scripts bundle | ✅ `"cron-egress-nftables.sh"` in the `server.tf` bundle list | Document apply path (see Infrastructure section) |
| ⚠️ "Not in merge-triggered `-target` set; merging does not push to running hosts; lands only on RECREATE" (task claim) | ❌ **WRONG.** `apply-web-platform-infra.yml:69-70` triggers on path-glob `apps/web-platform/infra/**` (not `*.tf`); `terraform_data.cron_egress_firewall` **is** in the `-target` set (`:593`) and folds the loader into `config_hash` (`server.tf:1074-1088`) → merge re-provisions **web-1** + restarts its live firewall (`cron-egress-postapply-assert.sh:48`) | **Corrected** the Infrastructure / Downtime / Delivery-Context sections to the true model. Code change unchanged; still safe (gap-free restart + inert rule); recorded as a decision-challenge for `ship` |
| Egress test suite asserts `:8288` | ✅ `cron-egress-firewall.test.sh:154` greps generic `'tcp dport 8288 accept'` | Add a **positive** assertion for the dedicated-host rule |
| Runtime enforcement asserts `:8288` | ✅ `cron-egress-postapply-assert.sh:54` greps generic `'dport 8288 accept'` | Add a dedicated-host runtime sentinel (see below) |
| Suite is ~195 tests, must stay green | ✅ tests tallied by PASS/FAIL counters; **no exact rule-count / `add rule` enumeration exists** | New assertions only *raise* the count; nothing to re-baseline |

**Premise Validation (Phase 0.6):** #6178 is cited **contextually, NOT `Closes`** (it is an
epic; this PR is one step on its critical path). ADR-100 is a contextual citation. No cited
blocker/issue is stale; all cited file paths and symbols exist on the branch. No external
premise was found to be stale.

## Network-Outage Deep-Dive (L3→L7)

The `firewall` trigger fires the network-outage gate. This plan is a **proactive fix**, not
an outage *diagnosis* — the root cause is **structurally certain** from reading the ruleset
(the `SOLEUR-EGRESS` chain is first-match-wins with a terminal `counter drop`; a container→
`10.0.1.40:8288` packet matches no accept rule → deterministic drop). No packet capture is
needed. The L3→L7 discipline (`hr-ssh-diagnosis-verify-firewall`) is satisfied below, in
order, with the L3 layer identified as the causal one **before** any application-layer claim:

1. **L3 — firewall allow-list (THE causal layer).** Verified by reading
   `cron-egress-nftables.sh:141–154`: the only `:8288` accept is `ip daddr $BRIDGE_GW`
   (host-gateway ≈ `172.17.0.1`); there is **no** `ip daddr 10.0.1.40` accept before the
   terminal `counter drop` (line 154). `10.0.1.40` cannot be in `@soleur_egress_allow`
   (hostname/DNS-resolved) nor `@soleur_egress_allow_cidr` (GitHub ranges). This is the gap.
   **Fix = add the L3 accept rule.** Artifact: the ruleset excerpt in the Overview + Research
   Reconciliation table.
2. **L3 — DNS / routing.** N/A by construction — the target is a **bare private IP**
   (`10.0.1.40`), so there is no DNS resolution step. Private-net routing between the web
   hosts (`10.0.1.10/.11`) and the Inngest host (`10.0.1.40`) is established: the Inngest
   host's OWN ingress nftables already accepts from `10.0.1.10,10.0.1.11`
   (`inngest-host.tf` `web_host_private_ips`), so the return path and reachability are proven
   — the only missing half is the **web-side egress** allow. [verified: opt-out with artifact]
3. **L7 — TLS / proxy.** N/A — the cutover URL is plain HTTP (`http://10.0.1.40:8288`) over
   the private net; no TLS, SNI, CDN, or proxy in path. [opt-out: no HTTPS surface]
4. **L7 — application.** Post-cutover, the drop surfaces at the app's `inngest.send()` POST.
   Critically, **absence of a lower-layer signal is the signal**: the host-side probes
   (`inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`) run on the host with
   *unfiltered* egress, so they never see the container's dropped packet — which is exactly
   why the gap hides from `op=verify`. The in-band signal that WILL fire is the nft
   `egress-blocked:` drop-log (line 153) → `cron-egress-alarm` → Sentry (see Observability).

**Conclusion:** single-layer L3 fix; no sshd/service-layer hypothesis applies (no SSH symptom
— this is container egress, not operator SSH). The L3 rule is the necessary and sufficient fix.

## Downtime & Cutover

> **[Corrected at deepen-plan — the task's original delivery premise was factually wrong;
> verified against the repo. See the Delivery Context section for the full corrected model.]**

**Merging DOES fire an apply and DOES re-provision web-1 — but no host is recreated and the
change is gap-free + inert, so it is zero-downtime.** The trigger for
`apply-web-platform-infra.yml` is the path-glob `apps/web-platform/infra/**`
(`apply-web-platform-infra.yml:69-70`), **not** `*.tf` — all three edited files match, so the
merge fires the workflow. `terraform_data.cron_egress_firewall` is in the merge-triggered
`-target` set (`apply-web-platform-infra.yml:593`) and folds `cron-egress-nftables.sh` into its
`config_hash` (`server.tf:1074-1088`), so the edit replaces the resource → its `remote-exec`
re-provisions **web-1** (`server.tf` `host = hcloud_server.web["web-1"]`) → the delivered
post-apply assertion restarts the `cron-egress-firewall` service
(`cron-egress-postapply-assert.sh:48`), installing `10.0.1.40:8288` into the **live** nft
ruleset on web-1 on merge.

Why this is still zero-downtime and safe:
- **No host recreate.** `terraform_data` replace ≠ `hcloud_server` replace; `hcloud_server.web`
  is excluded from the `-target` set. Only the firewall *service* restarts.
- **Gap-free restart.** The loader resolves its allowlist sets (Phase 2) **before** flushing +
  re-adding rules (Phase 3), and `die`s before the flush if resolve fails — leaving the
  existing ruleset intact. There is no window where the container has no egress rules.
- **Inert rule.** Nothing dials `10.0.1.40:8288` until the separate `INNGEST_BASE_URL` repoint
  (#6348) merges at flip-step 2.4, so the newly-live rule on web-1 changes no behavior.
- **web-1/web-2 asymmetry (harmless, acknowledged).** The SSH re-provision path is hardwired
  to **web-1 only** (`server.tf` `server_id`/`host = web["web-1"]`). web-2 receives the rule
  only when it is next recreated (baked host-scripts bundle via cloud-init). The interim
  divergence is harmless because the rule is inert. The cutover recreates (steps 1–3) converge
  both hosts.

The cutover host-recreates themselves (separate PRs, blue-green per ADR-100 / #5887) are out of
scope here.

## User-Brand Impact

**If this lands broken, the user experiences:** (a) if the rule is **malformed**, the
`nft -f -` transaction fails — caught pre-merge by the static test suite, and on a running
host (web-1 on merge) the loader `die`s **before** the flush so the existing ruleset stays
intact (no egress outage), with a loud `ASSERT-FAILED: firewall-restart` in the apply log; on
a **fresh** host a failed load would leave `SOLEUR-EGRESS` unloaded, but the host is not
serving until provisioning completes. (b) if the rule is **absent** post-cutover,
`inngest.send()` POSTs to `10.0.1.40:8288` are silently dropped, so **scheduled reminders and
cron-driven events never fire** for every user with a schedule — precisely the failure this PR
exists to prevent.

**If this leaks, the user's data is exposed via:** N/A — this rule *permits outbound* to a
single internal private host:port (`10.0.1.40:8288`). It moves no user data, touches no
schema/auth/API surface, and cannot widen a public exposure (the dedicated host is
deny-all-public and only accepts from the web hosts).

**Brand-survival threshold:** `aggregate pattern` — a broken/missing egress rule fails
event delivery **fleet-wide** (all containers on all recreated web hosts), which is an
aggregate delivery regression rather than a single-user data incident. Reason the diff
touches an infra path but stays below `single-user incident`: purely additive egress
allowance to a private control-plane host, no user-data/auth/PII surface, fully covered by
the egress test suite + host post-apply assertion.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `cron-egress-nftables.sh` contains the new rule
  `add rule ip filter SOLEUR-EGRESS ip daddr 10.0.1.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host (#6178)"`,
  placed **immediately after** the existing host-gateway `:8288` accept (line ~150) and
  **before** the allowlist/CIDR accepts and the terminal default drop.
- [ ] **AC2** — the existing host-gateway `:8288` accept rule is **retained unchanged**
  (this PR does not prune the dead-post-cutover rule; that is an optional follow-up).
- [ ] **AC3** — `cron-egress-firewall.test.sh` gains a **positive** assertion that the
  dedicated-host rule is present in the loader, AND a **line-order** assertion that the
  dedicated-host accept precedes the default-drop rule (mirroring the existing
  `RESOLVE_LINE < DROP_LINE` pattern at lines 142–148).
- [ ] **AC4** — `bash apps/web-platform/infra/cron-egress-firewall.test.sh` exits 0 with
  the new assertions reported as PASS (total test count rises from ~195; the pre-existing
  `SENTINEL_COUNT >= 15` floor and allowlist-host-count (23) assertions stay green).
- [ ] **AC5** — `cron-egress-postapply-assert.sh` gains a dedicated-host runtime sentinel
  (`nft list chain ip filter SOLEUR-EGRESS | grep -q '10.0.1.40 tcp dport 8288 accept' || { echo 'ASSERT-FAILED: dedicated-inngest-8288-accept'; exit 1; }`)
  placed inside the assertion block next to the existing `inngest-8288-accept` sentinel, so
  a recreated host that is missing the rule **fails post-apply loudly** (closing the
  "hides from the cutover gate" hole). The new line is sentinel-guarded, keeping the
  `firewall.test.sh` UNGUARDED-command meta-check green.
- [ ] **AC6** — `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` exits 0
  (no `:8288` ruleset assertions live there; run to confirm no regression).
- [ ] **AC7** — every other test file referencing `cron-egress`
  (`git grep -l cron-egress apps/web-platform/infra/*.test.sh`) is run and stays green:
  `ci-deploy.test.sh` (its `8288` refs are loopback registry/health mocks + the
  `ghcr.io`-absent-from-allowlist check — unrelated to the SOLEUR-EGRESS ruleset) and
  `soleur-host-bootstrap-observability.test.sh` (enforce-probe parity guard — no `:8288`
  rule refs). Neither needs a change.
- [ ] **AC8** — PR body says **"part of epic #6178"** (Ref, **NOT** `Closes`) and includes
  the **corrected** delivery-context paragraph (see Delivery Context section): merging fires
  `apply-web-platform-infra.yml`, re-provisions **web-1** and restarts its live firewall
  (gap-free, inert rule), web-2 gets the rule on recreate. PR is opened **ready, not draft** —
  SAFE TO MERGE NOW.

### Post-merge (operator)

- [ ] **AC9** — no operator action required. On merge, the infra apply delivers the rule to
  **web-1** (SSH re-provision + gap-free firewall restart) automatically; **web-2** receives
  it on its next recreate (baked bundle). The rule is **inert** on both until the separate
  `INNGEST_BASE_URL` repoint (#6348) merges at flip-step 2.4. **Merge-ordering constraint:**
  this PR MUST merge **before** the cutover host-recreates so the recreated hosts bake the
  `10.0.1.40:8288` allow. (Automation: not applicable — no operator action; the apply is
  automatic and the constraint is a sequencing note for the cutover runbook.)

## Implementation Phases

### Phase 1 — Add the egress accept rule (the fix)

**File:** `apps/web-platform/infra/cron-egress-nftables.sh`

Insert immediately **after** line 150 (the host-gateway `:8288` accept), **before**
line 151 (the allowlist accept):

```
add rule ip filter SOLEUR-EGRESS ip daddr 10.0.1.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host (#6178)"
```

Rationale for placement and mechanism (do **not** deviate):
- **Literal `10.0.1.40`** — the canonical dedicated Inngest private IP (`inngest-host.tf:33`).
  A bare private IP cannot be a hostname in `cron-egress-allowlist.txt` (DNS-resolved) and
  is not a GitHub CIDR — the explicit nft rule is the correct mechanism.
- **Position** — after the host-gateway accept keeps the two `:8288` rules adjacent and
  documents the old→new relationship; being before the allowlist/CIDR/default-drop rules
  guarantees the accept wins over the terminal drop. (Chain is first-match-wins; the only
  earlier `drop` rules at `:147`/`:149` are `dport 53` DNS-exfil drops that cannot match a
  `dport 8288` packet — verified at deepen-plan.)
- **Keep the host-gateway rule** — leaving the dead-post-cutover rule is harmless, keeps
  the PR minimal + reversible; pruning it is a separate optional follow-up.
- **Drift-coupling comment (nicety).** Add an inline comment on the new rule cross-referencing
  the source of truth, e.g. `# 10.0.1.40 = inngest-host.tf:33 inngest_private_ip (bash
  literal; if that IP changes, update this rule + inngest-registry-probe.sh +
  inngest-doublefire-probe.sh together)`. The IP is a bash literal, not injected from the
  Terraform local, so an IP change must update the loader rule and the two probe scripts in
  lockstep.

### Phase 2 — Extend the static egress test suite (write assertions first)

**File:** `apps/web-platform/infra/cron-egress-firewall.test.sh`

1. **Positive presence assertion** — add after the existing host-gateway assertion
   (line 154). Use `grep -qE` (the `assert_grep` helper) with a **paren-safe** pattern
   (stop the pattern before the `(#6178)` — an unescaped `(` is an ERE group; see Sharp
   Edges):
   ```sh
   assert_grep "dedicated inngest host :8288 accept (#6178)" \
     'ip daddr 10\.0\.1\.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host' "$LOADER"
   ```
2. **Line-order assertion** — mirror the `RESOLVE_LINE < DROP_LINE` block (lines 142–148):
   ```sh
   DEDICATED_LINE="$(grep -n 'ip daddr 10\.0\.1\.40 tcp dport 8288 accept' "$LOADER" | head -1 | cut -d: -f1)"
   DROP_RULE_LINE="$(grep -n 'counter drop comment "soleur-egress: default drop"' "$LOADER" | head -1 | cut -d: -f1)"
   if [[ -n "$DEDICATED_LINE" && -n "$DROP_RULE_LINE" && "$DEDICATED_LINE" -lt "$DROP_RULE_LINE" ]]; then
     PASS=$((PASS + 1)); echo "  PASS: dedicated inngest host accept precedes the default drop (line $DEDICATED_LINE < $DROP_RULE_LINE)"
   else
     FAIL=$((FAIL + 1)); echo "  FAIL: dedicated inngest host accept must precede the default drop (dedicated=$DEDICATED_LINE drop=$DROP_RULE_LINE)"
   fi
   ```

Note: the existing generic `'tcp dport 8288 accept'` assertion at line 154 is **retained**
(it still validates the host-gateway rule survives). There is **no** exact `add rule`
count / ruleset-enumeration assertion in this file, so nothing needs re-baselining — the
new assertions only raise the PASS total.

### Phase 3 — Harden the runtime post-apply enforcement

**File:** `apps/web-platform/infra/cron-egress-postapply-assert.sh`

The existing generic sentinel at line 54 (`grep -q 'dport 8288 accept'`) passes even when
**only** the host-gateway rule is present — it does **not** catch a host missing the
dedicated rule. Add a specific sentinel next to it, inside the assertion block (before the
`echo host-egress-ok` success marker so it is counted by `firewall.test.sh`'s
`SENTINEL_COUNT` extractor):

```sh
nft list chain ip filter SOLEUR-EGRESS | grep -q '10.0.1.40 tcp dport 8288 accept' || { echo 'ASSERT-FAILED: dedicated-inngest-8288-accept'; exit 1; }
```

This makes a recreated host that is missing the rule **fail its post-apply assertion
loudly** — directly closing the "hides from the cutover gate" hole. The new `nft list`
line carries its own `ASSERT-FAILED` sentinel, satisfying `firewall.test.sh`'s
UNGUARDED-command meta-check; the added sentinel raises `SENTINEL_COUNT` 15→16 (still `>=15`).

### Phase 4 — Run the full referencing test set

```sh
bash apps/web-platform/infra/cron-egress-firewall.test.sh          # core suite — must be green, new PASSes reported
bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh     # no :8288 rule assertions — confirm no regression
# every file referencing cron-egress:
git grep -l cron-egress apps/web-platform/infra/*.test.sh
#   → ci-deploy.test.sh, cron-egress-enforce-probe.test.sh,
#     cron-egress-firewall.test.sh, soleur-host-bootstrap-observability.test.sh
bash apps/web-platform/infra/ci-deploy.test.sh
bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh
```

All must exit 0. `ci-deploy.test.sh` and `soleur-host-bootstrap-observability.test.sh` are
run for completeness — their `cron-egress`/`8288` references are unrelated to the
`SOLEUR-EGRESS` ruleset (loopback registry mocks, allowlist `ghcr.io`-absence check,
enforce-probe parity guard) and need no edit.

## Files to Edit

- `apps/web-platform/infra/cron-egress-nftables.sh` — add the `10.0.1.40:8288` accept rule (Phase 1).
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — add presence + line-order assertions (Phase 2).
- `apps/web-platform/infra/cron-egress-postapply-assert.sh` — add dedicated-host runtime sentinel (Phase 3).

## Files to Create

- None.

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue touches these three infra files — checked
against the plan's Files-to-Edit list.)

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The `systemctl restart` / SSH re-provision references in this plan DESCRIBE the EXISTING
     Terraform-managed delivery mechanism (terraform_data.cron_egress_firewall's remote-exec,
     server.tf:1069-1178) — they are NOT new manual operator steps. No operator SSH, no manual
     provisioning is introduced; this PR only edits a bundled host script already delivered by
     Terraform + cloud-init. Phase 2.8 reviewed; opt-out is correct. -->

This change edits a host-scripts bundle member that is **already** Terraform-managed — no
new infrastructure, no operator SSH, no manual dashboard step. The 2.8 IaC-routing triggers
(`firewall`/`systemctl`/host-config) fire, but the resolution is "already IaC; document the
apply path," not "route through a new Terraform resource."

### Terraform changes

- **None to `*.tf` — but the merge still fires the infra apply (corrected).** No `*.tf` file
  is edited. However, `apply-web-platform-infra.yml` triggers on the **path-glob**
  `apps/web-platform/infra/**` (`apply-web-platform-infra.yml:69-70`), **not** on `*.tf`, so
  all three edited files (`cron-egress-nftables.sh`, `cron-egress-firewall.test.sh`,
  `cron-egress-postapply-assert.sh`) match and the workflow **does fire on merge**.
- `cron-egress-nftables.sh` is folded into `terraform_data.cron_egress_firewall.config_hash`
  (`server.tf:1074-1088`), and that resource is in the merge-triggered `-target` set
  (`apply-web-platform-infra.yml:593`). Editing the loader changes the hash → the
  `terraform_data` resource **replaces** → its `remote-exec` re-provisions the running host.
  (The plan's own test asserts this target is present: `cron-egress-firewall.test.sh:138`.)

### Apply path

- **On merge: `-target` SSH apply re-provisions web-1 + restarts its live firewall.** The
  replaced `terraform_data.cron_egress_firewall` runs its `remote-exec` against **web-1**
  (`server.tf` `host = hcloud_server.web["web-1"]`); the delivered post-apply assertion
  restarts `cron-egress-firewall.service` (`cron-egress-postapply-assert.sh:48`), which
  re-executes the new loader and installs `10.0.1.40:8288` into the **live** nft ruleset on
  web-1. This path is **web-1-only** — the SSH re-provision is hardwired to web-1
  (`server.tf` `server_id`/`host`).
- **On recreate (cutover steps 1–3): baked host-scripts bundle via cloud-init.** Fresh hosts
  (web-2, and web-1 when recreated) get the rule from the `server.tf` host-scripts bundle
  (integrity-checked via `host_scripts_content_hash`). This is how **web-2** receives the
  rule (the merge's SSH path never touches web-2).
- **Merge-ordering constraint (load-bearing):** this PR MUST merge **before** the cutover
  host-recreates, so the recreated hosts bake the `10.0.1.40:8288` allow. The rule is
  **inert/harmless** until the app is actually repointed — nothing dials `10.0.1.40:8288`
  until the separate `INNGEST_BASE_URL` repoint PR **#6348** merges at flip-step 2.4.
- **Blast radius / downtime:** the merge restarts the **live** `cron-egress-firewall.service`
  on web-1 (see `## Downtime & Cutover` — zero-downtime because the restart is gap-free by
  construction and the rule is inert). No `hcloud_server` recreate is triggered. The rule
  loads inside the atomic `nft -f -` transaction; a malformed rule fails the whole
  transaction (caught by the static test suite pre-merge; on the host the loader `die`s
  before flushing, leaving the existing ruleset intact, and the post-apply assertion fails
  loudly). If a **truly no-op** merge is ever required, the mechanism is
  `[skip-web-platform-apply]` on its own line in the merge commit
  (`apply-web-platform-infra.yml:51,155`) — this plan does **not** use it, because delivering
  the inert rule to web-1 on merge is harmless and desirable (web-1 is ready before cutover).

### Distinctness / drift safeguards

- The rule is a static literal in a bundled script — no `terraform.tfstate` secret exposure,
  no `dev != prd` divergence (the same bundle ships to all web hosts). `10.0.1.40` is pinned
  to `inngest-host.tf:33`'s `inngest_private_ip`; if that IP ever changes, this rule and the
  three inngest probe scripts that also hardcode it must move together (out of scope here).

## Observability

```yaml
liveness_signal:
  what: successful container→10.0.1.40:8288 inngest.send() event POSTs (post-cutover)
  cadence: every reminder/cron trigger + every event emit
  alert_target: nft "egress-blocked:" drop log → cron-egress-alarm → Sentry (fires on ANY default-drop hit); plus inngest.send() rejections surfaced by the app error path
  configured_in: cron-egress-nftables.sh (log prefix line 153) + cron-egress-alarm.sh/@.service + cron-egress-resolve.sh drop-prefix grep
error_reporting:
  destination: Sentry (egress-blocked drop log mirrored via the existing cron-egress-alarm path); host post-apply ASSERT-FAILED surfaces in the deploy/cloud-init log
  fail_loud: true — a missing/absent rule produces "egress-blocked:" journald log lines on every dropped POST AND fails cron-egress-postapply-assert.sh at deploy (new dedicated-inngest-8288-accept sentinel, Phase 3)
failure_modes:
  - mode: rule absent on a recreated host (bundle not delivered / edit lost)
    detection: cron-egress-postapply-assert.sh new sentinel `dedicated-inngest-8288-accept` fails at post-apply (no ssh — surfaces in deploy log); at runtime, container→10.0.1.40:8288 hits default drop → nft "egress-blocked:" log → cron-egress-alarm → Sentry
    alert_route: deploy/cloud-init log + Sentry (egress-blocked)
  - mode: malformed rule → whole `nft -f -` transaction fails on recreate
    detection: static suite (cron-egress-firewall.test.sh) fails pre-merge; on host, SOLEUR-EGRESS chain absent → postapply-assert docker-user-jump/default-drop sentinels fail
    alert_route: CI (pre-merge) + deploy log (post-apply)
  - mode: rule present but INNGEST_BASE_URL still points elsewhere (pre-#6348)
    detection: expected/inert state — nothing dials 10.0.1.40:8288 yet; no signal expected
    alert_route: n/a (inert by design until flip-step 2.4)
logs:
  where: journald `egress-blocked:` prefix → vector.service → Better Stack (existing pipeline); CI stdout for the test suite
  retention: per existing cron-egress log retention (unchanged)
discoverability_test:
  command: bash apps/web-platform/infra/cron-egress-firewall.test.sh
  expected_output: "PASS: dedicated inngest host :8288 accept (#6178)" and "PASS: dedicated inngest host accept precedes the default drop" (NO ssh — verifies the rule is present in the delivered loader artifact)
```

## Architecture Decision (ADR/C4)

**Skipped — no architectural decision.** This PR is a config implementation of a decision
already recorded in ADR-100 (the Inngest dedicated-host cutover, epic #6178). It adds one
allow rule to an existing firewall chain; it introduces no new ownership/tenancy boundary,
no new substrate, no resolver/trust-boundary change, and reverses no existing ADR. The
dedicated Inngest host and its web-host↔host relationship are already part of the
ADR-100/#6178 architecture. A competent engineer reading the existing ADRs + C4 would not
be misled about the system after this ships. (Skip test per Phase 2.10 satisfied.)

## Domain Review

**Domains relevant:** none (infrastructure / tooling change).

Single-domain infrastructure change (nftables egress rule + its test/enforcement
assertions). No user-facing surface (no `components/**`, no `app/**/page.tsx`), no product,
legal, finance, marketing, sales, or support implications. Product/UX Gate: **NONE** — no
UI-surface file in Files-to-Edit; the mechanical UI-surface override did not fire.
GDPR/Compliance Gate (2.7): **skipped** — no regulated-data surface (no schema, migration,
auth flow, API route, or `.sql`), and none of the (a)–(d) expansion triggers fire (no
LLM/external-API processing of user data, threshold is `aggregate pattern` not
single-user-incident, no learnings/specs read, no new distribution surface).

## Research Insights (deepen-plan)

### Precedent-diff (Phase 4.4)

The new rule has a **direct in-file precedent** — the adjacent host-gateway `:8288` accept it
is placed after. The two are identical except for the destination address, which is the
strongest possible precedent (a verbatim mirror of a proven-working rule in the same chain):

```
# precedent (cron-egress-nftables.sh:150, existing, proven)
add rule ip filter SOLEUR-EGRESS ip daddr $BRIDGE_GW  tcp dport 8288 accept comment "soleur-egress: host-gateway inngest"
# new (mirror — same chain, same dport, same verb; only daddr differs)
add rule ip filter SOLEUR-EGRESS ip daddr 10.0.1.40   tcp dport 8288 accept comment "soleur-egress: dedicated inngest host (#6178)"
```

No novel pattern is introduced. The test-assertion precedent is likewise mirrored from the
existing `RESOLVE_LINE < DROP_LINE` line-order block (`cron-egress-firewall.test.sh:142-148`)
and the existing `inngest-8288-accept` runtime sentinel (`cron-egress-postapply-assert.sh:54`).

### Delivery-model correction (architecture-strategist)

Full evidence trail is in the Downtime & Cutover, Infrastructure (IaC), and Delivery Context
sections. Key file:line evidence: `apply-web-platform-infra.yml:69-70` (path-glob trigger),
`:593` (`-target=terraform_data.cron_egress_firewall`), `server.tf:1074-1088` (config_hash
folds the loader), `cron-egress-postapply-assert.sh:48` (live firewall restart),
`cron-egress-firewall.test.sh:138` (the suite's own assertion that the target is present).

### Test-assertion verification (general-purpose)

All Phase 2/3 edits confirmed shell-correct against the real files: `assert_grep` uses
`grep -qE --` (ERE, `--`-guarded); the paren-safe pattern is a clean substring that cannot
match the retained host-gateway rule; the line-order greps pick the unique default-drop line;
the new postapply sentinel lands inside the awk-extracted block (`chmod +x …` → `echo
host-egress-ok`), carries its own `ASSERT-FAILED` (passes the UNGUARDED check), and keeps
`SENTINEL_COUNT` above its `>=15` floor (actual current count ~17). The other three cron-egress
test files have no SOLEUR-EGRESS `:8288` ruleset assertion → no edit needed.

## Test Scenarios

- **Positive:** loader contains `ip daddr 10.0.1.40 tcp dport 8288 accept` before the
  default drop → `firewall.test.sh` PASS (presence + order).
- **Regression guard:** host-gateway `:8288` rule still present → existing generic
  assertion (line 154) stays green.
- **Runtime enforcement:** recreated host missing the rule → `postapply-assert.sh` new
  sentinel `ASSERT-FAILED: dedicated-inngest-8288-accept` → deploy fails loudly.
- **Meta-assertion safety:** new post-apply sentinel keeps `SENTINEL_COUNT` `>= 15` and
  passes the UNGUARDED-command check (the new `nft list` line carries its sentinel).
- **No-regression:** `enforce-probe.test.sh`, `ci-deploy.test.sh`,
  `soleur-host-bootstrap-observability.test.sh` all exit 0 unchanged.

## Sharp Edges

- **Paren-safety in the ERE assertion.** `assert_grep` uses `grep -qE` (extended regex).
  The rule comment is `… dedicated inngest host (#6178)`; an unescaped `(` is an ERE group
  opener. The Phase 2 assertion pattern therefore **stops before the paren** (matches up to
  `… dedicated inngest host`) — do not include `(#6178)` literally in a `-E` pattern without
  escaping. Escape the dots in `10\.0\.1\.40` for exactness (unescaped also matches, but
  escaped is precise).
- **Post-apply sentinel must sit inside the awk-extracted assertion block.** `firewall.test.sh`
  extracts the block up to `echo host-egress-ok` and counts `ASSERT-FAILED:` lines. Place the
  new Phase 3 sentinel **before** that success marker (next to the existing `inngest-8288-accept`
  sentinel) or it will not be counted and the UNGUARDED check may flag the new `nft list` line.
- **`nft list` render form.** The runtime grep targets `'10.0.1.40 tcp dport 8288 accept'` —
  nft renders `ip daddr 10.0.1.40` verbatim, so the substring matches. Do not over-anchor.
- **This is inert until #6348.** Nothing dials `10.0.1.40:8288` until the `INNGEST_BASE_URL`
  repoint merges — a green suite here does NOT exercise live egress; that is by design.
- **A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold will
  fail `deepen-plan` Phase 4.6.** This plan's section is filled with a concrete threshold.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Add `10.0.1.40` to `cron-egress-allowlist.txt` | It is a **hostname** list DNS-resolved by `cron-egress-resolve.sh`; a bare private IP cannot be expressed there. Wrong mechanism. |
| Add `10.0.1.40/32` to `cron-egress-allowlist-cidr.txt` | That file is scoped to **GitHub git-LB CIDR ranges** (comment at `:152`); a private-host IP does not belong there. Wrong mechanism. |
| Also prune the dead host-gateway `:8288` rule now | Out of scope — leaving it is harmless and keeps the PR minimal + reversible. Optional follow-up. |
| Repoint `INNGEST_BASE_URL` in this PR | Separate concern (#6348, flip-step 2.4). This PR only opens the egress path so the repoint is safe when it lands. |

## Delivery Context (for the PR body)

> Part of epic #6178 (ADR-100 Inngest dedicated-host cutover). **Ref, not Closes.**
>
> **Delivery on merge (corrected model):** `cron-egress-nftables.sh` is a `server.tf`
> host-scripts bundle member AND is folded into `terraform_data.cron_egress_firewall`'s
> `config_hash` (`server.tf:1074-1088`). `apply-web-platform-infra.yml` triggers on the
> path-glob `apps/web-platform/infra/**` (`:69-70`) — **not** `*.tf` — so **merging this PR
> fires the infra apply.** The edit changes the config hash → `terraform_data.cron_egress_firewall`
> (in the merge-triggered `-target` set, `:593`) replaces → its `remote-exec` re-provisions
> **web-1** and restarts `cron-egress-firewall.service`, installing `10.0.1.40:8288` into the
> **live** nft ruleset on web-1. **web-2** receives the rule only on its next recreate (baked
> bundle via cloud-init). No `hcloud_server` is recreated by this merge.
>
> **SAFE TO MERGE NOW** — the live firewall restart on web-1 is **zero-downtime**: the loader
> resolves its allowlist sets before flushing/re-adding rules and `die`s before the flush if
> resolve fails (existing rules stay intact — no egress gap), and the new rule is
> **inert/harmless** because nothing dials `10.0.1.40:8288` until the separate `INNGEST_BASE_URL`
> repoint PR **#6348** merges at flip-step 2.4.
>
> **This PR MUST merge BEFORE the cutover host-recreates** so the recreated hosts bake the
> `10.0.1.40:8288` allow. P1 on the cutover critical path. Open ready, not draft.
>
> (If a truly no-op merge is ever required, `[skip-web-platform-apply]` on its own line in the
> merge commit suppresses the apply — not used here, since delivering the inert rule to web-1
> on merge is harmless and gets web-1 ready ahead of cutover.)
