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
worktree) before drafting. No divergence found.

| Premise (as stated) | Codebase reality | Plan response |
| --- | --- | --- |
| Host-gateway `:8288` rule at ~line 150 | ✅ exact match at `cron-egress-nftables.sh:150` | Insert new rule immediately after |
| Canonical dedicated IP `10.0.1.40` | ✅ `inngest-host.tf:33 inngest_private_ip = "10.0.1.40"` | Use literal `10.0.1.40` |
| `cron-egress-allowlist.txt` is DNS-resolved (bare IP can't go there) | ✅ header: "One hostname per line … resolves these to IPv4 on a systemd timer" | Do NOT touch allowlist.txt |
| CIDR file is GitHub-only | ✅ `cidr allowlist (github git LB ranges)` comment at `:152` | Do NOT touch CIDR file |
| Script in `server.tf` host-scripts bundle | ✅ `"cron-egress-nftables.sh"` in the `server.tf` bundle list | Document apply path (see Infrastructure section) |
| Egress test suite asserts `:8288` | ✅ `cron-egress-firewall.test.sh:154` greps generic `'tcp dport 8288 accept'` | Add a **positive** assertion for the dedicated-host rule |
| Runtime enforcement asserts `:8288` | ✅ `cron-egress-postapply-assert.sh:54` greps generic `'dport 8288 accept'` | Add a dedicated-host runtime sentinel (see below) |
| Suite is ~195 tests, must stay green | ✅ tests tallied by PASS/FAIL counters; **no exact rule-count / `add rule` enumeration exists** | New assertions only *raise* the count; nothing to re-baseline |

**Premise Validation (Phase 0.6):** #6178 is cited **contextually, NOT `Closes`** (it is an
epic; this PR is one step on its critical path). ADR-100 is a contextual citation. No cited
blocker/issue is stale; all cited file paths and symbols exist on the branch. No external
premise was found to be stale.

## User-Brand Impact

**If this lands broken, the user experiences:** after the cutover host-recreate, either
(a) the rule is **missing/malformed** and the whole `nft -f -` transaction fails on the
fresh host, leaving `SOLEUR-EGRESS` unloaded and container egress broken fleet-wide; or
(b) the rule is absent and `inngest.send()` POSTs to `10.0.1.40:8288` are silently dropped,
so **scheduled reminders and cron-driven events never fire** for every user with a
schedule. This is precisely the failure this PR exists to prevent.

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
  the delivery-context paragraph (see Infrastructure section). PR is opened **ready, not
  draft** — SAFE TO MERGE NOW.

### Post-merge (operator)

- [ ] **AC9** — none required by this PR itself. This PR is inert until the separate
  `INNGEST_BASE_URL` repoint (#6348) merges at flip-step 2.4 and the cutover host-recreates
  (steps 1–3) deliver the new bundle. **Merge-ordering constraint:** this PR MUST merge
  **before** the cutover host-recreates so the fresh hosts carry the `10.0.1.40:8288` allow.
  (Automation: not applicable — no operator action; the constraint is a sequencing note for
  the cutover runbook, not a step this PR executes.)

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
  guarantees the accept wins over the terminal drop.
- **Keep the host-gateway rule** — leaving the dead-post-cutover rule is harmless, keeps
  the PR minimal + reversible; pruning it is a separate optional follow-up.

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

This change edits a host-scripts bundle member that is **already** Terraform-managed — no
new infrastructure, no operator SSH, no manual dashboard step. The 2.8 IaC-routing triggers
(`firewall`/`systemctl`/host-config) fire, but the resolution is "already IaC; document the
apply path," not "route through a new Terraform resource."

### Terraform changes

- **None to `*.tf`.** `cron-egress-nftables.sh` is delivered via the `server.tf`
  host-scripts bundle (it is listed in the bundle alongside `cron-egress-resolve.sh`,
  `cron-egress-postapply-assert.sh`, etc.). Because this PR changes **no** `*.tf` file,
  `apply-web-platform-infra.yml` does **not** fire on merge, and it is not a
  deploy-pipeline-fix trigger.

### Apply path

- **cloud-init on RECREATE + SSH re-provision on `server_id` change.** The bundle reaches a
  host two ways: (a) cloud-init delivers it to a **fresh** host at first boot; (b)
  `terraform_data.cron_egress_firewall` SSH-re-provisions `web-1` when its `server_id`
  changes. Merging this PR does **not** push the script to running hosts — it lands when
  `web-2`/`web-1` are **recreated** (cutover steps 1–3).
- **Merge-ordering constraint (load-bearing):** this PR MUST merge **before** the cutover
  host-recreates, so the recreated hosts carry the `10.0.1.40:8288` allow. The rule is
  **inert/harmless** until the app is actually repointed — nothing dials `10.0.1.40:8288`
  until the separate `INNGEST_BASE_URL` repoint PR **#6348** merges at flip-step 2.4.
- **Blast radius / downtime:** none from this merge (no recreate triggered). On the eventual
  recreate, the rule loads inside the same atomic `nft -f -` transaction as the rest of
  `SOLEUR-EGRESS` — a malformed rule would fail the whole transaction (caught by the static
  test suite pre-merge and by the host post-apply assertion at deploy time).

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
> `cron-egress-nftables.sh` is a `server.tf` host-scripts bundle member. It reaches hosts on
> **RECREATE** (cloud-init delivers the bundle to fresh hosts; `terraform_data.cron_egress_firewall`
> SSH-re-provisions `web-1` on `server_id` change). It is **not** in the merge-triggered
> auto-apply `-target` set, so merging does **not** push it to running hosts — it lands when
> `web-2`/`web-1` are recreated (cutover steps 1–3).
>
> **Therefore this PR MUST merge BEFORE the cutover host-recreates** so the recreated hosts
> allow `10.0.1.40:8288` egress. The accept rule is **inert/harmless** until the app is
> actually repointed — nothing dials `10.0.1.40:8288` until the separate `INNGEST_BASE_URL`
> repoint PR **#6348** merges at flip-step 2.4.
>
> **SAFE TO MERGE NOW.** Purely additive egress allowance to a private host that nothing
> currently dials; no host recreate triggered by this merge (`cron-egress-nftables.sh` is not
> a `*.tf` file, so `apply-web-platform-infra.yml` does not fire; it is not a
> deploy-pipeline-fix trigger). P1 on the cutover critical path. Open ready, not draft.
