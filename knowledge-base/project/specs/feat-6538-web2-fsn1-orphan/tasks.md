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

- [x] **A1.1** — `knowledge-base/legal/article-30-register.md`: correct web-2's locative
      `hel1 → fsn1` (live since #6393; §5(2) accuracy defect). Reconcile **all four**
      clauses — PA-1 (d)/(e) and PA-2 (d)/(e). *(Not two: v1 undercounted.)*
- [x] **A1.2** — Verify AC-A1 (predicate corrected — the first draft false-failed on the
      *correct* text, since "web-2 CX33 in `fsn1`" matches `web-2.*CX33` and the relocation
      history legitimately contains `hel1`). Mutation-tested anchor:
      `grep -cE 'web-2[^.;]{0,25}(in|\(CX33,) \`hel1\`' <file>` == **0** (RED=2 on a reverted copy)
      AND `grep -cE 'web-2[^.;]{0,45}\`fsn1\`' <file>` == **6**.
      *(Count corrected 2026-07-16: the plan said **4** — the four clauses PA-1 (d)/(e) +
      PA-2 (d)/(e) — but the as-written file has **6**, because the annex row and PA-8(e)
      were added after the AC was drafted. The file is right; the AC was a stale
      plan-prose tally. Re-derived from the as-written file, command published above.)*
- [x] **A2.1** — `knowledge-base/legal/compliance-posture.md`: same locative correction.
      **Do NOT delete the TS-1 row** (*"cross-tenant write threat class"*, #5274, OPEN,
      soak-gated) — a live compliance record.
- [x] **A2.2** — Verify AC-A2: `grep -c 'cross-tenant write threat class' knowledge-base/legal/compliance-posture.md` >= 1
- [x] **A3.1** — `knowledge-base/operations/expenses.md`: web-1 `15.37 → ~9.17`, spec
      `160 GB → 80 GB` (cx33 = €8.49 / 80 GB — ledger prices the same SKU two ways).
- [x] **A3.2** — `expenses.md`: registry `CX33 / 9.17 → CX23 / ~5.93` (#6497/#6463).
- [x] **A3.3** — `expenses.md`: `grok-dogfood` — booked `approved-not-billing` / "Not
      born" but **verified LIVE** (cx33, hel1, created 2026-07-16, 1 of 5 capped slots).
      Fix the row. Do not route a known-false row to #6460.
- [x] **A3.4** — Leave web-2's three rows intact (the host exists until PR B).
- [x] **A4.1** — `knowledge-base/finance/cost-model.md`: Product COGS currently omits
      web-2, registry, inngest (~$50/mo). Add them.
- [x] **A4.2** — Carry the standard `VERIFY actual draw on the next Hetzner invoice` caveat.
### A6 — PUBLIC legal docs (emergent; NOT in plan v2 — added 2026-07-16)

The v2 plan scoped PR A to the **internal** register + ledger and never contemplated that
the **public** docs users read also pin the hosting locative to Helsinki and name web-2.
They have been inaccurate since #6393 (2026-07-13) — the same Art. 5(2) accuracy defect
A1 fixes internally, on a far more exposed surface. Operator decision (2026-07-16): state
the plane at the **EU** level rather than re-pin to two DCs, so the claim survives PR B
and active-active-N (#6459) instead of rescheduling the defect.

- [x] **A6.1** — 40 live claims corrected across `docs/legal/{gdpr-policy,privacy-policy,data-protection-disclosure}.md`,
      the 3 Eleventy mirrors, and `knowledge-base/legal/data-processing-agreement-template.md`
      (§11.1 + Schedule 2). Hosting **plane** → EU; **workspace data / user-serving host /
      per-turn telemetry stay `Helsinki, Finland`** (specific AND true).
- [x] **A6.2** — The **6 dated `Previous:` changelog entries left verbatim.** They were
      true when written (#6393 moved web-2 *after* them); rewriting a dated legal record
      falsifies it. New `**Last Updated:**` entry prepended; prior demoted to `Previous:`.
- [~] **A6.3** — **UNWOUND at review (2026-07-16).** I removed the git-data-host assertion
      (it is false — verified live: 5 servers, no `soleur-git-data`, no git-data volume),
      but that host was the **antecedent** of the LUKS/cross-host safeguard clauses in the
      same sentences. Removing it left those clauses **dangling** — no longer describing a
      phantom host, now reading as claims about **live** workspace storage, which is plain
      ext4. That made a false Art. 32 claim *worse*. `pattern-recognition-specialist` caught
      it; `user-impact-reviewer`, `security-sentinel` and `code-quality-analyst` converged.
      PR A is now **purely the locative fix**; the whole #5274-Phase-3 claim family is left
      exactly as on main. Operator decided to keep the claim published and make it true by
      encrypting → **#6588** (P1), CTO-routed; recorded at `decision-challenges.md` DC-1
      with a 2026-07-23 re-raise trigger.
- [x] **A6.4** — **`terms-and-conditions.md` deliberately untouched**, byte-identical to
      main. Any non-cosmetic edit is Tier 2 *clarifying* → **BUMP REQUIRED** under the
      CLO-signed `knowledge-base/legal/tc-version-bump-policy.md`, forcing every user to
      re-accept. Its claim is defensible as written (web-2 never served the Web Platform).
      `TC_VERSION` 2.4.0 + `TC_DOCUMENT_SHA` untouched.
- [x] **A6.5** — Repinned the **3** changed SHAs in `apps/web-platform/lib/legal/legal-doc-shas.ts`.
      *(Note: that map has **no `terms-and-conditions` key** — the T&C SHA lives in
      `apps/web-platform/lib/legal/tc-version.ts` as `TC_DOCUMENT_SHA` and is load-bearing:
      it is written to the WORM consent ledger.)*
- [x] **A6.6** — Verified with the **real gates**, not by inspection:
      `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0;
      `vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts` → 19/19.
      The consistency gate caught a real miss: the mirrors carry a `page-hero` `<p>` (line
      11) with its **own** `Last Updated` date, asserted equal to source.
- [x] **A6.7** — Locative check is **anchored + mutation-tested**, not a bare
      `grep -c 'Helsinki'` — which false-matches the correction notes' own quoted-historical
      prose (`cq-assert-anchor-not-bare-token`; hit for real here). Strips double-quoted
      spans + skips `**Last Updated:**` lines. GREEN on corrected files; **RED (3 hits)**
      when `gdpr-policy.md` is reverted to main.

### A5 — exit

- [x] **A5.1** — `bash scripts/test-all.sh` green — **178/178 suites, exit 0** (2026-07-16).
      *(Read the runner's own summary + `EXIT=$?`, not the harness's background-task
      notification: that reports the trailing command's exit and is always 0.)*
- [x] **A5.2** — PR body: `Ref #6538` / `Ref #6463`. **Never `Closes`.**
- [x] **A5.3a** — `/soleur:review` done: 7 agents, 13 findings (5 P1 / 5 P2 / 3 P3);
      9 fixed inline (`18860da14`), 3 filed (#6584, #6585, #6588). Suite re-run green
      178/178 after the fixes.
- [ ] **A5.3b** — `/soleur:compound` → `/soleur:ship` (**operator go-ahead required** —
      publishes a rewritten privacy policy; outward-facing).
- [x] **A5.4** — **Threshold stays `single-user incident`; NOT `none`.** The pre-A6 PR was
      internal-docs-only and `none` would have been right. A6 edits the **public privacy
      policy + GDPR policy + DPD** — that IS the user surface, and it changes what users
      are told about where their data lives. `user-impact-reviewer` must fire.

---

## PR B — the destroy (new branch; **B-GATE CLEARED 2026-07-17 — unblocked**)

### ✅ B-GATE — RESOLVED (ADR-118). B0–B6 may proceed.

- [x] **B-GATE.1** — plan §Resolved Decision (was §Open Decision) — **resolved: Option 1** — bring the cert +
      `doppler_secret.proxy_tls_cert` into PR B's scope and re-mint inside the supervised
      operator-local apply. `proxy-tls.tf` is **unchanged (zero-line diff)** — the existing
      for-expressions already compute the right answer. Rationale + rejected alternatives:
      **ADR-118** (`knowledge-base/engineering/architecture/decisions/ADR-118-proxy-cert-sans-track-the-cluster-roster.md`).
      **Two corrections to this task's own prior text:** (a) only **`PROXY_TLS_CERT`**
      rotates — **not** `PROXY_TLS_KEY` (`tls_private_key.proxy_server` has zero
      `var.web_hosts` dependency, so it is never replaced); (b) the "rotates the pinned CA
      under a running web-1" risk is **vacuous** — the proxy path is dark behind three
      independent locks, and server cert + client CA are the same PEM from the same env var
      on the same host, so a stale host verifies against itself; skew needs two hosts and
      the destroy leaves one.
- [x] **B-GATE.2** — Routed to `/soleur:deepen-plan` → CTO ruling → ADR-118 (2026-07-17).
- [x] **B-GATE.3** — Sibling issue filed: **#6596** — `terraform-target-parity.test.ts`
      exempts the proxy cert because it *"ride[s] the same cluster apply"*, but **no
      cluster-apply job exists**; that apply is an operator ritual, not automation. Mirror of
      #6574 (*in the graph, claimed out* ↔ *out of the graph, claimed in*). P3, not a blocker
      for B0–B6 — the proxy path is dark, so this is claim-vs-reality, not a live outage.

### B0 — Preconditions

- [ ] **B0.1** — Re-run BOTH measurements (baseline + web-2-removed) over the exact
      push-apply scope. Stock/state are time-varying; a stale measurement is not evidence.
      Record verbatim → AC-B1. **ADR-118: two shapes, do not conflate.** The push-apply-scope
      measurement is **unchanged** (`0 to add, 1 to change, 1 to destroy`) — the cert is
      unreachable from that scope (`-target` is transitive on *dependencies*, not
      *dependents*). The **B3 local-apply** shape changes (a cert replace is
      `1 to add, 0 to change, 1 to destroy` → the destroy count increments). **Measure both;
      encode neither** — a predicted counter repeats the v1 P0 miss the 5th address cost once.
- [ ] **B0.2** — Reference sweep with the **corrected** paths (v1 greped two zero-hit
      tokens and missed the guard directory):
      `git grep -n 'web-2\|web_2\|web\["web-2"\]' apps/web-platform/infra .github/workflows tests/ scripts/ plugins/soleur/test/`
      Capture the hit-set to a file — AC-B4 **diffs against it**. (Measured: 311 hits / 45 files.)
- [ ] **B0.2b** — **Derivation sweep (ADR-118 — B0.2 cannot find what created the B-GATE).**
      `proxy-tls.tf` has **zero** `web-2` literals; it couples by *derivation*, so B0.2,
      AC-B4 and the measurement all missed it at once. A token grep enumerates *mentions*, not
      *dependents*: `git grep -ln 'var\.web_hosts' apps/web-platform/infra` → **9 files**
      (measured 2026-07-17). Audit every dependent for ForceNew-on-membership-change **and for
      host-count assumptions**; AC-B4 diffs against this set too. The nine: `server.tf`,
      `network.tf`, `dns.tf`, `placement-group.tf`, `proxy-tls.tf`, `variables.tf`,
      **`web-hosts-fanout-parity.test.sh`**, **`tests/web-hosts-eu-pin.tftest.hcl`**,
      **`scripts/deploy-status-fanout-verify.sh`**.
      ⚠️ The last three were missed by this step's own first draft (six listed from memory
      instead of running the command) — the ADR-118 lesson recurring inside its own
      remediation. **Run the sweep, don't recall it**; if it returns >9, audit the extras.
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
      unparseable/empty plan JSON; **`doppler_secret.proxy_tls_cert` `delete`** (must be
      `update`-only — a delete strips `PROXY_TLS_CERT` from Doppler `prd`); **any
      `tls_private_key.proxy_server` change** (that is a key rotation → halt) *(both ADR-118)*.
- [ ] **B1.3** — RED cases that MUST pass: **retry-after-partial** (3 of 4 remaining); and
      **cert-replaced-but-Doppler-update-not-yet-applied** — Terraform applies sequentially
      and can die between the two, so the `<= 1` / subset-not-equality shape must hold for the
      new counters too *(ADR-118)*.
- [ ] **B1.4** — GREEN: add `web2_retire_allow` to
      `tests/scripts/lib/destroy-guard-filter-web-platform.jq` with **seven** addresses
      *(5 + the 2 added by ADR-118)*:
      `hcloud_server.web["web-2"]`, `hcloud_server_network.web["web-2"]`,
      `hcloud_volume_attachment.workspaces["web-2"]`, `hcloud_volume.workspaces["web-2"]`,
      **`hcloud_firewall_attachment.web`**, **`tls_self_signed_cert.proxy_server`**
      (replace: delete+create), **`doppler_secret.proxy_tls_cert`** (update-in-place).
      *(The 5th is a v1 P0 miss — the measured "1 to change". Omitting it wedges the gate
      permanently.)* **`tls_private_key.proxy_server` is deliberately ABSENT** — it must never
      plan a change; assert that with a fixture, don't assume it. Adding the two cert
      addresses cannot weaken the gate: membership is exact-equality via
      `IN(.address; web2_allow[])` over a disjoint resource-type space.
- [ ] **B1.4b** — GREEN: two new counters mirroring `firewall_attachment_ok` *(ADR-118)*:
      `cert_replaced` (`<= 1`, delete+create only) and `doppler_cert_ok` (exactly one
      `update`, **never `delete`**). `host_creates` is **not** tripped — it is type-scoped to
      `hcloud_server`/`hcloud_volume`, so the cert's create does not fire the mirrored wedge.
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
- [ ] **B3.2** — Implement the B-GATE decision for `proxy-tls` — **ADR-118, Option 1**.
      **`proxy-tls.tf` must end byte-identical to `main`** (a zero-line diff — the existing
      for-expressions already compute the right answer; if that file changed, the wrong option
      was implemented). The work is entirely in the gate (B1.4/B1.4b) and the `-target` list
      (B6.2). **Do NOT hardcode/pin the SAN list** — that was rejected Option 3: it falsifies
      `terraform-target-parity.test.ts`'s exclusion rationale in place, and at the 3.D cutover
      a new host gets no SAN → TLS verification fails on the live path **with the drift
      detector blinded**.
- [ ] **B3.3** — `terraform fmt -check` + `terraform validate` clean.
- [ ] **B3.4** — **Fix `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` — PR B
      red-CIs it otherwise.** A *second* `var.web_hosts`-derived coupling (same class as the
      cert), CI-registered at `.github/workflows/infra-validation.yml:434`. **Measured**
      against a simulated B3.1: baseline `3 passed, 0 failed`; with web-2 removed →
      `EXIT=1` (4 failures). Two edits, both required:
      1. Three workflow literals move in lockstep with the roster —
         `web-platform-release.yml:563`, `apply-web-platform-infra.yml:710` and `:974`:
         `WEB_HOST_PRIVATE_IPS: "10.0.1.10,10.0.1.11"` → `"10.0.1.10"`.
      2. The test's own hardcoded 2-host floor — `if [ "$tf_n" -lt 2 ]; then fail "… — parser
         drift"` → `-lt 1`. Fixing only the literals still leaves `3 passed, 1 failed`, and it
         fails blaming *parser drift* rather than the roster — fix the message too.
      ⚠️ **#6575 ordering trap:** apply-workflow copies #1/#2 live in the
      `warm_standby`/`web_2_recreate` jobs #6575 deletes after B6, and
      `check_all_copies "$APPLY_WORKFLOW" … 2` pins `min_copies=2` → deletion trips
      `expected >=2 copies, found 0`. #6575 must lower `min_copies` in the same PR.
- [ ] **B3.5** — Re-run `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` → exit 0.

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

- [x] **B5.1** — Art. 30 + `compliance-posture.md`: **record the retirement** with a dated
      amendment note referencing #6538 — do **not** silently strike (good Art. 30 practice
      keeps the audit trail; the token must survive). *(Done 2026-07-17: dated `[… UPDATE …]`
      bracket notes on the Hetzner sub-processor rows in both files; historical `fsn1` text
      retained; the Better Stack `eu-fsn-3` decoy explicitly disambiguated.)*
- [x] **B5.2** (executed in B6.11) — `expenses.md`: remove web-2's three rows. **DEFERRED to B6.11 (post-destroy
      verify).** The rows are a *current-billing* record, not a desired-state config: web-2
      bills until the destroy lands, and `knowledge-base/finance/cost-model.md`'s own note
      (2026-07-16) states web-2's rows *"leave COGS when the destroy lands, which will return
      ~$10.59/mo."* The rows already self-document this (row note: *"removed when the destroy
      lands; they remain here while the host still exists and still bills"*). Removing them at
      B5 — before the operator-gated, 1h-time-boxed, revertable B6.4 apply — would make the
      ledger under-report real spend and drift from cost-model.md. So the removal + the
      cost-model COGS recompute happen together at B6.11, gated on B6.6's destroy verify.
- [ ] **B5.3** — **DEFERRED to PR-3 of #6604 (operator decision 2026-07-17).** The public
      "current EU data centres" notes share a sentence/row with the frozen LUKS / "traffic
      between the hosts" / "served across hosts" claim family (DC-1). That family stays
      **untouched** pending the `/workspaces` LUKS cutover: the cutover *mechanism* merged
      (#6610, 2026-07-17) but has **not been dispatched** — no `workspaces_luks` volume is
      live and no git-data host exists (verified via Hetzner API 2026-07-17), so the published
      LUKS claim is still not-yet-true and DC-1 still binds. #6604's own tasks scope the legal
      flip (present-tense LUKS + SHA re-pin + clause-site rewrite) to **PR-3**, opened after
      the cutover soak passes. The operator's Helsinki-only, topology-hidden wording (hide the
      per-workspace git-data host; drop the German-DC mention; GDPR-clean since the public
      notice need not enumerate hosts) lands **there**, in one coherent pass with the LUKS
      flip — NOT half-done in B5 against a frozen, phantom antecedent (the PR-A failure mode).
      No SHA re-pin in PR B (the public docs do not change here).
      **[original B5.3 text retained below for the PR-3 executor:]** **PUBLIC legal docs (added 2026-07-16 — PR A gap; v2 plan never
      contemplated that the public docs name web-2).** PR A restated the hosting plane at
      the **EU** level, so the structural claim (*"hosted on Hetzner data centres in the
      EU"*) **survives the destroy untouched**. But each doc carries **one** "current EU
      data centres" note that names web-2/`fsn1` explicitly; those go stale the moment the
      host dies. Update that single note per doc — 3 canonical + 3 Eleventy mirrors:
      `docs/legal/{gdpr-policy,privacy-policy,data-protection-disclosure}.md` and
      `plugins/soleur/docs/pages/legal/` — plus the `knowledge-base/legal/data-processing-agreement-template.md`
      Schedule 2 row and §11.1 EEA list. **Then repin the 3 SHAs** in
      `apps/web-platform/lib/legal/legal-doc-shas.ts` and re-run
      `bash apps/web-platform/scripts/check-tc-document-sha.sh` (must exit 0) +
      `vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts`.
      ⚠️ **Mirrors carry a `page-hero` `<p>` on line 11 with its OWN `Last Updated` date**
      — the consistency test asserts hero-vs-body-vs-source date equality and WILL fail if
      you update the body only (it caught exactly this in PR A).
      ⚠️ **Do NOT touch `docs/legal/terms-and-conditions.md`** — PR A deliberately left it
      byte-identical to main. Any non-cosmetic edit is Tier 2 "clarifying" under the
      CLO-signed `knowledge-base/legal/tc-version-bump-policy.md` → **BUMP REQUIRED** →
      forces every user to re-accept. Its claim is already true post-destroy.
      ⚠️ **Do NOT rewrite the dated `Previous:` changelog entries** — they were true when
      written. Add a NEW `**Last Updated:**` entry and demote the current one.
- [~] **B5.4** — Anchored verification of the public-doc edits. **DEFERRED to PR-3 with B5.3**
      (no public-doc edits ship in PR B). Instruction preserved for the PR-3 executor: verify
      with an anchored check (NOT a bare `grep -c 'Helsinki'`, which **false-matches the
      correction notes' own quoted-historical prose** — PR A hit this;
      `cq-assert-anchor-not-bare-token`). Strip double-quoted spans and skip
      `**Last Updated:**` lines before asserting. Mutation-test it: reverting one doc to
      its pre-fix state MUST go RED.

### B6 — Merge, apply, verify, close

- [ ] **B6.1** — `/soleur:review` → `/soleur:ship`. Squash commit MUST carry
      `[skip-web-platform-apply]` **on its own line**. Keep the squash single-purpose (the
      token suppresses **all** guards for that merge).
- [ ] **B6.2** — Produce the saved plan locally: `-target` the **6** addresses *(5 + the one
      added by ADR-118)*, `-out=tfplan`:
      ```
      -target='hcloud_server.web["web-2"]'
      -target='hcloud_server_network.web["web-2"]'
      -target='hcloud_volume_attachment.workspaces["web-2"]'
      -target='hcloud_volume.workspaces["web-2"]'
      -target=hcloud_firewall_attachment.web
      -target=doppler_secret.proxy_tls_cert          # ADR-118
      ```
      One new target suffices — `-target` is transitive on **dependencies**, so
      `doppler_secret.proxy_tls_cert` pulls in `tls_self_signed_cert.proxy_server` →
      `tls_private_key.proxy_server` (a graph no-op; not replaced). **Do NOT add
      `-target=doppler_secret.proxy_tls_key`** — the key does not rotate, and naming it invites
      the false belief that it does. Note the `-target` list (6) and `web2_retire_allow` (7)
      are **different lists**: the allow-list names everything that *appears* in the plan; the
      `-target` list names only what must be *reached*.
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
- [x] **B6.10** — `gh issue close 6538 6463` with the decision recorded. Unblock #6575.
- [x] **B6.11** — **Ledger removal (moved from B5.2), gated on B6.6's destroy verify.** Only
      after `servers?name=soleur-web-2` → 0: remove web-2's three rows from
      `knowledge-base/operations/expenses.md` (host CX33 `$9.17` + volume 20 GB `$1.24` +
      Primary IPv4 `$0.54`; amounts per #6602, NOT the plan's stale `$0.88` volume). Then
      recompute `knowledge-base/finance/cost-model.md`: drop web-2's three COGS line items
      (rows ~173–175) and the ~$10.95/mo they carry (9.17 + 1.24 + 0.54; the doc's older
      "~$10.59" predates the #6602 volume-FX correction), and re-derive the COGS total,
      break-even, and margin figures the note gates on. Re-run
      `bash scripts/expenses-verify-by-check.sh` (exit 0; 16 → 13 markers) and
      `bash scripts/expenses-verify-by-check.test.sh`. If B6.5 reverts, this reverts with it.

---

## Follow-ups (filed; out of scope here)

- **#6584** — gate `expenses.md` `active` rows against the `cost-model.md` tables. The
  root cause of this cycle's repeated under-counts: nothing couples the two, so COGS
  drifted **$141.08 → $200.11 (+42%)** on rows that were already billing. Also carries the
  volume-FX (~$0.35) + missing web-1/registry IPv4 (~$1.08) gaps. *(Net-flow: consolidated
  3 candidates into 1 tracker — same subsystem, same root cause.)*
- **#6585** — the public Eleventy legal mirrors are stale vs canonical and are **missing
  disclosure bullets** (Turn summaries, `workspace_activity`, `kb_files`, workspace-logo,
  message-attachments, BYOK-audit-log, beta-CRM). The published privacy policy discloses
  *less* processing than the canonical — the exposed direction. `check-tc-document-sha.sh`
  defers body-equivalence for the 8 non-T&C docs; that deferral has aged badly. Remediate,
  **then turn the gate on**. Pre-existing; not introduced by this branch.

- **#6570** — git-data pinned to `cax11`, orderable 0/3 EU DCs. Root blocker of
  active-active. **Next brainstorm.**
- **#6571** — `web_spread` empty AND unreachable-by-design.
- **#6574** — the push-apply `-target` allow-list is a fiction. Standing hazard.
- **#6575** — dead web-2 dispatch sweep. Lands immediately **after** B6 verifies —
  not before (those dispatches are web-2's documented recovery path until it is gone).
- **#6460** — fleet-capacity-audit + `fleet-sku-orderability-audit`.
