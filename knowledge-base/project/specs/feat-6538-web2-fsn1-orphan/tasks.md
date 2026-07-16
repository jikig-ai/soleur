---
feature: web-2 retire (fsn1 orphan)
date: 2026-07-16
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-16-chore-retire-web-2-fsn1-orphan-plan.md
refs: [6538, 6463]
---

# Tasks — retire soleur-web-2

Derived from plan **v2** (post 6-agent review). Two PRs; **PR A ships first and is
independent**. `Ref` never `Closes` — the remediation runs post-merge.

---

## PR A — register + ledger accuracy (this branch, PR #6568, docs-only)

Everything below is true **today**, independent of the retire. No gates, no sequencing.

- [ ] **A1.1** — `knowledge-base/legal/article-30-register.md`: correct web-2's locative
      `hel1 → fsn1` (live since #6393; §5(2) accuracy defect). Reconcile **all four**
      clauses — PA-1 (d)/(e) and PA-2 (d)/(e). *(Not two: v1 undercounted.)*
- [ ] **A1.2** — Verify AC-A1: `grep -cE 'web-2.*(CX33|hel1)' knowledge-base/legal/article-30-register.md` == 0
- [ ] **A2.1** — `knowledge-base/legal/compliance-posture.md`: same locative correction.
      **Do NOT delete the TS-1 row** (*"cross-tenant write threat class"*, #5274, OPEN,
      soak-gated) — a live compliance record.
- [ ] **A2.2** — Verify AC-A2: `grep -c 'cross-tenant write threat class' knowledge-base/legal/compliance-posture.md` >= 1
- [ ] **A3.1** — `knowledge-base/operations/expenses.md`: web-1 `15.37 → ~9.17`, spec
      `160 GB → 80 GB` (cx33 = €8.49 / 80 GB — ledger prices the same SKU two ways).
- [ ] **A3.2** — `expenses.md`: registry `CX33 / 9.17 → CX23 / ~5.93` (#6497/#6463).
- [ ] **A3.3** — `expenses.md`: `grok-dogfood` — booked `approved-not-billing` / "Not
      born" but **verified LIVE** (cx33, hel1, created 2026-07-16, 1 of 5 capped slots).
      Fix the row. Do not route a known-false row to #6460.
- [ ] **A3.4** — Leave web-2's three rows intact (the host exists until PR B).
- [ ] **A4.1** — `knowledge-base/finance/cost-model.md`: Product COGS currently omits
      web-2, registry, inngest (~$50/mo). Add them.
- [ ] **A4.2** — Carry the standard `VERIFY actual draw on the next Hetzner invoice` caveat.
- [ ] **A5.1** — `bash scripts/test-all.sh` green (the real runner per `package.json`).
- [ ] **A5.2** — PR body: `Ref #6538` / `Ref #6463`. **Never `Closes`.**
- [ ] **A5.3** — `/soleur:review` → `/soleur:ship`.

---

## PR B — the destroy (new branch; **blocked on the Open Decision**)

### ⛔ B-GATE — resolve before ANY B-phase work

- [ ] **B-GATE.1** — Resolve §Open Decision: `proxy-tls.tf` reads
      `ip_addresses = [for h in values(var.web_hosts) : h.private_ip]` and
      `dns_names = concat(keys(var.web_hosts), ...)` — both **ForceNew**. Removing web-2
      **replaces the cert** and rotates `PROXY_TLS_CERT`/`KEY` in Doppler `prd`, the value
      the proxying client pins as `ca:` with `rejectUnauthorized: true`. It contains no
      `web-2` literal → invisible to the sweep, the ACs, and the measurement.
      Options: (1) bring cert + 2 doppler secrets into scope (rotates the pinned CA under
      a running web-1 that baked the old cert at container start); (2) accept + document a
      permanent 12h drift alarm; (3) decouple the cert from `var.web_hosts`.
- [ ] **B-GATE.2** — Route to `/soleur:deepen-plan` (mandated at `single-user incident`;
      its data-integrity + security triad is the right lens for a pinned-CA rotation).

### B0 — Preconditions

- [ ] **B0.1** — Re-run BOTH measurements (baseline + web-2-removed) over the exact
      push-apply scope. Stock/state are time-varying; a stale measurement is not evidence.
      Record verbatim → AC-B1.
- [ ] **B0.2** — Reference sweep with the **corrected** paths (v1 greped two zero-hit
      tokens and missed the guard directory):
      `git grep -n 'web-2\|web_2\|web\["web-2"\]' apps/web-platform/infra .github/workflows tests/ scripts/ plugins/soleur/test/`
      Capture the hit-set to a file — AC-B4 **diffs against it**. (Measured: 311 hits / 45 files.)
- [ ] **B0.3** — Confirm **no `apply-web-platform-infra` run is in flight** — the R2
      backend has no state lock (`use_lockfile = false`).
- [ ] **B0.4** — Do **NOT** join the `web-1-swap` concurrency group (would red-CI
      `web-1-swap-concurrency-parity.test.sh`: named allow-list + exactly 4 occurrences).
      Moot under local-apply — no job exists.

### B1 — Extend the existing gate (RED first, `cq-write-failing-tests-before`)

- [ ] **B1.1** — RED: extend `tests/scripts/test-destroy-guard-counter-web-platform.sh`
      (the **real** exerciser — there is no `test-web2-recreate-gate.sh`). Synthesized
      fixtures only.
- [ ] **B1.2** — RED cases that MUST fail: web-1 touch; non-web-2 volume destroy;
      server-only partial (**the measured shape**); firewall-attachment **delete**;
      unparseable/empty plan JSON.
- [ ] **B1.3** — RED case that MUST pass: **retry-after-partial** (3 of 4 remaining).
- [ ] **B1.4** — GREEN: add `web2_retire_allow` to
      `tests/scripts/lib/destroy-guard-filter-web-platform.jq` with **five** addresses:
      `hcloud_server.web["web-2"]`, `hcloud_server_network.web["web-2"]`,
      `hcloud_volume_attachment.workspaces["web-2"]`, `hcloud_volume.workspaces["web-2"]`,
      **`hcloud_firewall_attachment.web`**. *(The 5th is a v1 P0 miss — the measured "1 to
      change". Omitting it wedges the gate permanently.)*
- [ ] **B1.5** — GREEN: `out_of_scope == 0` (necessary, **not sufficient** — it passes the
      partial shape) **plus four named per-address destroy counters**, not a bare
      `length == 4`. Pin the volume counter to the exact address (a bare
      `hcloud_volume.*` count would let **web-1's** volume satisfy it).
- [ ] **B1.6** — GREEN: `firewall_attachment_ok` — exactly one `update`, **never delete**
      (a delete strips web-1's firewall).
- [ ] **B1.7** — GREEN: **idempotent-retry shape** — subset-of-allow-set with `>= 1`
      member and each counter `<= 1`. **NOT strict equality** (v1 P0: terraform applies
      sequentially and can die after 1 of 4; strict equality fails closed on retry,
      stranding a half-retired state).
- [ ] **B1.8** — If a new suite file is added, **register it in `scripts/test-all.sh`**
      (it registers suites explicitly — otherwise the gate never runs in CI).

### B2 — Fix the destroy-HALT error text (safety prerequisite)

- [ ] **B2.1** — The `destroy_count` HALT currently says *"Add a line containing exactly
      '[ack-destroy]' … or revert the trigger commit."* A concurrent merge in **our**
      window hits this and would authorize the partial destroy. Make it name
      `[skip-web-platform-apply]` and warn `[ack-destroy]` may be **partial**.
      *(In PR B, not #6575 — we create the hazard, we carry the mitigation.)*

### B3 — var removal

- [ ] **B3.1** — Remove the `"web-2"` key + its cross-DC rationale comment from
      `var.web_hosts`.
- [ ] **B3.2** — Implement the B-GATE decision for `proxy-tls`.
- [ ] **B3.3** — `terraform fmt -check` + `terraform validate` clean.

### B4 — ADR + C4

- [ ] **B4.1** — **Amend ADR-068** (do not mint a new ordinal; §(c) survives). Record:
      standby retired; HA deferred to active-active-N (#6459) whose hosts must be **born
      in hel1 inside `web_spread`**; git-data (#6570) is the gating blocker.
- [ ] **B4.2** — Add both rejected options to `## Alternatives Considered` with the
      measured cost (€8.49 vs €35.49) + stock (cx33 orderable in one DC) evidence.
- [ ] **B4.3** — `model.c4`: correct the **two** falsified descriptions —
      `betterstack -> hetzner` (*"web-2 warm standby has NO standing uptime coverage…"*)
      and `tunnel -> zotRegistry` (the *"#6416: web-2 was not…"* clause → past tense).
      No element/actor/view changes (enumeration in the plan).
- [ ] **B4.4** — Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### B5 — Register + ledger strikes

- [ ] **B5.1** — Art. 30 + `compliance-posture.md`: **record the retirement** with a dated
      amendment note referencing #6538 — do **not** silently strike (good Art. 30 practice
      keeps the audit trail; the token must survive).
- [ ] **B5.2** — `expenses.md`: remove web-2's three rows.

### B6 — Merge, apply, verify, close

- [ ] **B6.1** — `/soleur:review` → `/soleur:ship`. Squash commit MUST carry
      `[skip-web-platform-apply]` **on its own line**. Keep the squash single-purpose (the
      token suppresses **all** guards for that merge).
- [ ] **B6.2** — Produce the saved plan locally: `-target` the 5 addresses, `-out=tfplan`.
- [ ] **B6.3** — Run the gate: `terraform show -json tfplan | jq -f tests/scripts/lib/destroy-guard-filter-web-platform.jq`.
- [ ] **B6.4** — **Show the operator the gate verdict AND the exact apply command; wait for
      explicit per-command go-ahead** (`hr-menu-option-ack-not-prod-write-auth` —
      per-command; menu acks and prior approvals do NOT extend). Then apply in-session.
      Confirm-then-run — **never** a checklist handed over.
- [ ] **B6.5** — ⏱ **Time-box: 1 hour.** If go-ahead has not arrived, **revert PR B**
      (re-add the `web_hosts` key) — state/config re-converge and the window closes.
- [ ] **B6.6** — Verify (self-pull, `hr-no-dashboard-eyeball-pull-data-yourself`):
      `servers?name=soleur-web-2` → 0; `volumes?name=soleur-web-platform-data-web-2` → 0;
      total servers → 4.
- [ ] **B6.7** — `terraform state list | grep -c 'web-2'` == 0.
- [ ] **B6.8** — web-1 still serving: `app.soleur.ai` probe 200 **and** Better Stack shows
      `host=soleur-web-platform` shipping. *(Do NOT use the Hetzner `created` field as a
      reboot proxy — it never changes on reboot.)*
- [ ] **B6.9** — A subsequent no-op merge runs push-apply to completion (no HALT).
- [ ] **B6.10** — `gh issue close 6538 6463` with the decision recorded. Unblock #6575.

---

## Follow-ups (filed; out of scope here)

- **#6570** — git-data pinned to `cax11`, orderable 0/3 EU DCs. Root blocker of
  active-active. **Next brainstorm.**
- **#6571** — `web_spread` empty AND unreachable-by-design.
- **#6574** — the push-apply `-target` allow-list is a fiction. Standing hazard.
- **#6575** — dead web-2 dispatch sweep. Lands immediately **after** B6 verifies —
  not before (those dispatches are web-2's documented recovery path until it is gone).
- **#6460** — fleet-capacity-audit + `fleet-sku-orderability-audit`.
