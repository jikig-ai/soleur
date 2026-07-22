# Tasks — close the unguarded web-1 birth path in warm_standby (Refs #6718, #6712)

Plan: `knowledge-base/project/plans/2026-07-19-fix-warm-standby-web1-birth-halt-plan.md`
Challenges (operator decisions): `./decision-challenges.md` — **UC-1 RESOLVED: Half B cut**
Lane: `cross-domain` · Threshold: `single-user incident` · CPO: SIGN OFF WITH CONDITIONS (C1/C2/C3 folded in)

> **Revision 3.** Half B (#6712 resolver extraction) was **cut** by operator ruling. This is now
> one change: wire the existing `host_creates` HALT into `warm_standby`. **No new files are
> created.** `web2-recreate-preflight.sh` and `scripts/test-all.sh` are **not** touched.

---

## Results (2026-07-20) — read these before re-deriving anything

| Task | Outcome |
|---|---|
| **0.1** | **PASS, no STOP.** `web_hosts` default = `{ "web-1" = … }` only. Regex counts: `server.tf` **3**, `network.tf` **1** — as predicted, the naive grep finds 1 of 4. |
| **0.2** | **WARNS — does NOT error.** Measured on Terraform **v1.10.5**, credential-free local repro: `-target` on an unresolvable `for_each` key → exit **0**, `No changes`, generic targeting warning only. **⇒ the HALT is reachable; AC9 resolves to the *warn* arm; the PR may claim closure.** |
| **0.3** | 27 pass; **zero cloud-init bytes added** (change is workflow + comments only). |
| **0.4** | Baseline at `origin/main`: `warm_standby` `host_creates` **absent (0)**, `apply` **present (8)**. Presence/absence, not a magic count. |
| **0.5** | **Premise flip confirmed.** main green (`9c6a139f`, `48b8bc4a`); branch red at `301c20a1`. **The red was ours** — the `rename-guard (allowlist destinations)` job, triggered by the plan-file rename. Fixed with a `Rename-Allowed-By` trailer, *not* waved through. |
| **0.6** | **PASS.** `workspaces-luks-cutover-gate.sh`'s `positive` set still includes `create` (`:91`). |
| **4.3** | **Already filed — #6575** ("sweep the dead web-2 dispatch surface"). No duplicate created. It independently corroborates the 0.2 no-op finding. |
| **4.4** | **Filed — #6730** ("web-1 has no executable birth path"). Distinct from #6459, trigger not gated on it. |
| **4.5** | Posted — issue comment on #6712. |
| **5.1** | **`bash scripts/test-all.sh` → 193/193 suites passed, exit 0**, on the shipping commit `5dcee934`. Our suite: **49 passed, 0 failed**. (An earlier run recorded 48 — it predated T51e and was re-run rather than reported as-is.) |
| **5.2** | **CI green on `5dcee934` (= PR headSha): 68 pass, 4 skipping, 0 fail.** Includes `deploy-script-tests`, `infra-validate-required`, `plan (apps/web-platform/infra)`, and the formerly-red `rename-guard (allowlist destinations)`. |
| **5.3** | All 17 ACs walked. **AC9 — the discriminating one — resolves to the *warn* arm.** |

**AC3 was resting on eyeball and is now asserted (T51e).** T51a–d assert only CONTENT; all four pass
with the lines in any order. T51e pins the ordering by line offset. **The mutation battery found a
bug in the new test rather than confirming it:** M1 (delete the `set -e` re-enable) initially
produced no T51e line, no summary line, and **exit 0** — the four `ln_*` assignments lacked
`|| true`, so a non-matching grep exited 1 under `set -euo pipefail` and aborted the suite mid-run,
making the anchor-absent branch unreachable dead code. A broken extractor would have passed CI as a
silent green. Guarded; both M1 and M2 now fail cleanly and restore to 49/0.

**Byproduct of 0.2 (filed, not fixed):** because unresolvable targets are silently dropped,
`warm_standby`'s "additive 6-target set" is really a **3-target set**. This does not weaken the
HALT — `hcloud_server.web["web-1"]` is still transitively in the graph via the surviving
`hcloud_server_network.web["web-1"]` target, which is what the tripwire counts.

**Coherence bug found while doing 3.2:** the `apply` HALT's remediation routed web-host births to
`warm-standby` — a dispatch that after #6538 targets a retired host and after this PR HALTs.
Following it would have produced a second HALT, not a host. That was the last named exit; its
closure is what made 4.4/#6730 a blocking deliverable rather than a nicety.

---

## Phase 0 — Preconditions (measure; do NOT inherit)

- [x] **0.1 [HARD STOP]** Verify `var.web_hosts` holds only `web-1`, and the three `for_each`
      bindings. **Use the regex form — the naive `for_each = var.web_hosts` finds 1 of 4:**
      ```
      awk '/variable "web_hosts"/,/^}/' apps/web-platform/infra/variables.tf | grep -A3 'default = {'
      grep -cE 'for_each[[:space:]]*=[[:space:]]*var\.web_hosts' \
        apps/web-platform/infra/server.tf apps/web-platform/infra/network.tf   # expect 3 and 1
      ```
      If a second key exists → **STOP**; scope the guard to `hcloud_server` only.
- [x] **0.2** Determine whether `terraform plan -target` on an unresolvable `for_each` key
      **warns** or **errors**. Record the answer — AC9 depends on it. If it errors, the HALT is
      present but **unreachable**, and the PR must not claim closure.
- [x] **0.3** Baseline cloud-init bytes: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- [x] **0.4** Confirm baseline as **presence/absence** (not an exact count): warm_standby
      `host_creates` absent, `apply` present.
- [x] **0.5 [PREMISE FLIPPED — do not inherit the brief]** secret-scan: #6717 **merged**, #6706
      **closed**, main **green**. A red secret-scan on this branch **is ours** — investigate.
      Re-derive: `gh run list --workflow=secret-scan.yml --branch=main --limit 3 --json conclusion,headSha`.
- [x] **0.6** Assert `workspaces-luks-cutover-gate.sh`'s `positive` set still includes `create`
      (the 4th transitive reacher is closed only incidentally).

## Phase 1 — RED: one structural test

- [x] **1.1** Add to `tests/scripts/test-destroy-guard-counter-web-platform.sh` (**required**
      shard — NOT `nic-wait-gate.test.sh`, which is advisory-only). Extract the `warm_standby`
      block with **flag-based awk** (never a range — it self-matches), assert **non-emptiness
      first**, then use a **here-string** (never `printf | grep -q` — SIGPIPE under `pipefail`):
  - [x] 1.1.1 block contains `host_creates=$(echo "$counts" | jq -r`
  - [x] 1.1.2 **the `^[0-9]+$` validation line contains `host_creates`** ← load-bearing
  - [x] 1.1.3 block contains `[[ "$host_creates" -gt 0 ]]`
  - [x] 1.1.4 the HALT's `::error::` text contains a **routing instruction**
- [x] **1.2** Confirm RED before Phase 2.

> Deleted in revision 2: the parity test (asserts an equivalence Phase 2 deliberately breaks) and
> the missing-key fixture (**impossible** — the jq filter emits the key unconditionally; and a
> fixture proves the bash mirror, not the workflow).

## Phase 2 — GREEN: wire the HALT (~5 lines, `warm_standby` only)

- [x] **2.1** `host_creates=$(echo "$counts" | jq -r '.host_creates')`
- [x] **2.2** **Extend the numeric-validation regex to include `host_creates`.** Load-bearing:
      `jq -r` on a missing key yields `null`, and `[[ "null" -gt 0 ]]` resolves an unset name to
      `0` and **passes** — the guard fails **open** without this line.
- [x] **2.3** Add the `-gt 0` HALT, ordered to mirror `apply` **for parity, not severity**.
- [x] **2.4** Keep the parse **below** the `set -e` re-enable.
- [x] **2.5** Remediation text: names this path, gives a **routing instruction**, and states
      explicitly that **there is no bypass on this dispatch** (`[skip-web-platform-apply]` /
      `[ack-destroy]` are merge-commit mechanisms; a `workflow_dispatch` run has no merge commit).
- [x] **2.6** Do **not** touch `apply`'s guard logic (its remediation *text* is 3.2).

## Phase 3 — Doc coherence (these become FALSE on merge)

- [x] **3.1** `destroy-guard-filter-web-platform.jq`: correct **all** now-false `host_creates`
      consumer claims. The canonical one is **split across two lines** — normalize newlines
      before asserting.
- [x] **3.2** `apply` HALT remediation: drop the warm-standby route; **preserve** the
      legitimate-new-web-host break-glass **and** the `[skip-web-platform-apply]` UNWEDGE line;
      **[CPO C1]** record the `hr-fresh-host-provisioning-reachable-from-terraform-apply`
      violation and name the 4.4 issue as owner. Scope any absolute to **web** hosts
      (`inngest_host` exists to birth a host).
- [x] **3.3** `nic-wait-gate.test.sh`: prose only — "KNOWN GAP … #6718" → closed. No assert changes.
- [x] **3.4** `apply_target` menu description: stop advertising warm-standby as a live web-2 fan-out.
- [x] **3.5 [CPO C3]** Reconcile `server.tf`'s "cx33-unrebuildable web-1" vs #6538's
      `hel1 → rebuildable_in_place_today: YES`. Comment-only.

## Phase 4 — Record status; file deferrals

- [x] **4.1** ADR-114: factual status note — #6718 closed; #6712 **prevented, not verified**,
      resolver deferred.
- [x] **4.2** ADR-068: factual status note (web-2 retired; both dispatch jobs unrunnable).
- [x] **4.3** File the `warm_standby` zombie-job issue.
- [x] **4.4 [CPO C2 — blocking]** File **"web-1 has no executable birth path"** — distinct from
      #6459, trigger **not** gated on it (#6459 is blocked by #6570, itself blocked on vendor
      stock). Record that the cloud-init arming path can now never execute and is never validated.
      **This issue is the vehicle for #6712's substance.**
- [x] **4.5** Comment on **#6712**: the Operator Decision design record (two-scripts shape, TOCTOU
      reasoning, GHCR-private, digest≠provenance) + cross-link the 4.4 issue. In the issue, not a
      caller-less code comment.

## Phase 5 — Exit gate

- [x] **5.1** `bash scripts/test-all.sh` (CI shards: `webplat`/`bun`/`scripts`).
- [x] **5.2** `infra-validation.yml` suites.
- [x] **5.3** Walk all 17 ACs. **AC9 is the discriminating one** — AC1 and the structural test
      pass identically whether the HALT is reachable or dead.

## PR body

- [x] `Refs #6718` and `Refs #6712`. **No `Closes`/`Fixes` keyword for ANY issue**, in the PR body
      or any commit body (the squash reads both). `#6441` carries no closing keyword.
- [x] Do **not** assert web-1 is unreachable from `-target=`. Make **no provenance claim**. Do
      **not** claim #6712 is closed or that a resolver shipped.
- [x] Record the 0.2 finding (warn vs error) explicitly — AC9.
- [x] **[AC17] Restate the force-replace gate.** The original sequencing said "#6712 + #6718
      closed"; #6712 now stays open, so that can never clear. New wording:
      **the `warm_standby` `host_creates` HALT is live on `main`, AND the "web-1 has no executable
      birth path" issue (4.4) is filed.** Both objectively checkable.
- [x] Avoid the literal follow-through token; if unavoidable, add
      `<!-- gate-override: soak-followthrough-enrollment -->` + a one-line justification.
