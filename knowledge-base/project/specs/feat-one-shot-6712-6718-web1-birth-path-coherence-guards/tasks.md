# Tasks — close the unguarded web-1 birth path in warm_standby (Refs #6718, #6712)

Plan: `knowledge-base/project/plans/2026-07-19-fix-warm-standby-web1-birth-halt-plan.md`
Challenges (operator decisions): `./decision-challenges.md` — **UC-1 RESOLVED: Half B cut**
Lane: `cross-domain` · Threshold: `single-user incident` · CPO: SIGN OFF WITH CONDITIONS (C1/C2/C3 folded in)

> **Revision 3.** Half B (#6712 resolver extraction) was **cut** by operator ruling. This is now
> one change: wire the existing `host_creates` HALT into `warm_standby`. **No new files are
> created.** `web2-recreate-preflight.sh` and `scripts/test-all.sh` are **not** touched.

---

## Phase 0 — Preconditions (measure; do NOT inherit)

- [ ] **0.1 [HARD STOP]** Verify `var.web_hosts` holds only `web-1`, and the three `for_each`
      bindings. **Use the regex form — the naive `for_each = var.web_hosts` finds 1 of 4:**
      ```
      awk '/variable "web_hosts"/,/^}/' apps/web-platform/infra/variables.tf | grep -A3 'default = {'
      grep -cE 'for_each[[:space:]]*=[[:space:]]*var\.web_hosts' \
        apps/web-platform/infra/server.tf apps/web-platform/infra/network.tf   # expect 3 and 1
      ```
      If a second key exists → **STOP**; scope the guard to `hcloud_server` only.
- [ ] **0.2** Determine whether `terraform plan -target` on an unresolvable `for_each` key
      **warns** or **errors**. Record the answer — AC9 depends on it. If it errors, the HALT is
      present but **unreachable**, and the PR must not claim closure.
- [ ] **0.3** Baseline cloud-init bytes: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- [ ] **0.4** Confirm baseline as **presence/absence** (not an exact count): warm_standby
      `host_creates` absent, `apply` present.
- [ ] **0.5 [PREMISE FLIPPED — do not inherit the brief]** secret-scan: #6717 **merged**, #6706
      **closed**, main **green**. A red secret-scan on this branch **is ours** — investigate.
      Re-derive: `gh run list --workflow=secret-scan.yml --branch=main --limit 3 --json conclusion,headSha`.
- [ ] **0.6** Assert `workspaces-luks-cutover-gate.sh`'s `positive` set still includes `create`
      (the 4th transitive reacher is closed only incidentally).

## Phase 1 — RED: one structural test

- [ ] **1.1** Add to `tests/scripts/test-destroy-guard-counter-web-platform.sh` (**required**
      shard — NOT `nic-wait-gate.test.sh`, which is advisory-only). Extract the `warm_standby`
      block with **flag-based awk** (never a range — it self-matches), assert **non-emptiness
      first**, then use a **here-string** (never `printf | grep -q` — SIGPIPE under `pipefail`):
  - [ ] 1.1.1 block contains `host_creates=$(echo "$counts" | jq -r`
  - [ ] 1.1.2 **the `^[0-9]+$` validation line contains `host_creates`** ← load-bearing
  - [ ] 1.1.3 block contains `[[ "$host_creates" -gt 0 ]]`
  - [ ] 1.1.4 the HALT's `::error::` text contains a **routing instruction**
- [ ] **1.2** Confirm RED before Phase 2.

> Deleted in revision 2: the parity test (asserts an equivalence Phase 2 deliberately breaks) and
> the missing-key fixture (**impossible** — the jq filter emits the key unconditionally; and a
> fixture proves the bash mirror, not the workflow).

## Phase 2 — GREEN: wire the HALT (~5 lines, `warm_standby` only)

- [ ] **2.1** `host_creates=$(echo "$counts" | jq -r '.host_creates')`
- [ ] **2.2** **Extend the numeric-validation regex to include `host_creates`.** Load-bearing:
      `jq -r` on a missing key yields `null`, and `[[ "null" -gt 0 ]]` resolves an unset name to
      `0` and **passes** — the guard fails **open** without this line.
- [ ] **2.3** Add the `-gt 0` HALT, ordered to mirror `apply` **for parity, not severity**.
- [ ] **2.4** Keep the parse **below** the `set -e` re-enable.
- [ ] **2.5** Remediation text: names this path, gives a **routing instruction**, and states
      explicitly that **there is no bypass on this dispatch** (`[skip-web-platform-apply]` /
      `[ack-destroy]` are merge-commit mechanisms; a `workflow_dispatch` run has no merge commit).
- [ ] **2.6** Do **not** touch `apply`'s guard logic (its remediation *text* is 3.2).

## Phase 3 — Doc coherence (these become FALSE on merge)

- [ ] **3.1** `destroy-guard-filter-web-platform.jq`: correct **all** now-false `host_creates`
      consumer claims. The canonical one is **split across two lines** — normalize newlines
      before asserting.
- [ ] **3.2** `apply` HALT remediation: drop the warm-standby route; **preserve** the
      legitimate-new-web-host break-glass **and** the `[skip-web-platform-apply]` UNWEDGE line;
      **[CPO C1]** record the `hr-fresh-host-provisioning-reachable-from-terraform-apply`
      violation and name the 4.4 issue as owner. Scope any absolute to **web** hosts
      (`inngest_host` exists to birth a host).
- [ ] **3.3** `nic-wait-gate.test.sh`: prose only — "KNOWN GAP … #6718" → closed. No assert changes.
- [ ] **3.4** `apply_target` menu description: stop advertising warm-standby as a live web-2 fan-out.
- [ ] **3.5 [CPO C3]** Reconcile `server.tf`'s "cx33-unrebuildable web-1" vs #6538's
      `hel1 → rebuildable_in_place_today: YES`. Comment-only.

## Phase 4 — Record status; file deferrals

- [ ] **4.1** ADR-114: factual status note — #6718 closed; #6712 **prevented, not verified**,
      resolver deferred.
- [ ] **4.2** ADR-068: factual status note (web-2 retired; both dispatch jobs unrunnable).
- [ ] **4.3** File the `warm_standby` zombie-job issue.
- [ ] **4.4 [CPO C2 — blocking]** File **"web-1 has no executable birth path"** — distinct from
      #6459, trigger **not** gated on it (#6459 is blocked by #6570, itself blocked on vendor
      stock). Record that the cloud-init arming path can now never execute and is never validated.
      **This issue is the vehicle for #6712's substance.**
- [ ] **4.5** Comment on **#6712**: the Operator Decision design record (two-scripts shape, TOCTOU
      reasoning, GHCR-private, digest≠provenance) + cross-link the 4.4 issue. In the issue, not a
      caller-less code comment.

## Phase 5 — Exit gate

- [ ] **5.1** `bash scripts/test-all.sh` (CI shards: `webplat`/`bun`/`scripts`).
- [ ] **5.2** `infra-validation.yml` suites.
- [ ] **5.3** Walk all 17 ACs. **AC9 is the discriminating one** — AC1 and the structural test
      pass identically whether the HALT is reachable or dead.

## PR body

- [ ] `Refs #6718` and `Refs #6712`. **No `Closes`/`Fixes` keyword for ANY issue**, in the PR body
      or any commit body (the squash reads both). `#6441` carries no closing keyword.
- [ ] Do **not** assert web-1 is unreachable from `-target=`. Make **no provenance claim**. Do
      **not** claim #6712 is closed or that a resolver shipped.
- [ ] Record the 0.2 finding (warn vs error) explicitly — AC9.
- [ ] **[AC17] Restate the force-replace gate.** The original sequencing said "#6712 + #6718
      closed"; #6712 now stays open, so that can never clear. New wording:
      **the `warm_standby` `host_creates` HALT is live on `main`, AND the "web-1 has no executable
      birth path" issue (4.4) is filed.** Both objectively checkable.
- [ ] Avoid the literal follow-through token; if unavoidable, add
      `<!-- gate-override: soak-followthrough-enrollment -->` + a one-line justification.
