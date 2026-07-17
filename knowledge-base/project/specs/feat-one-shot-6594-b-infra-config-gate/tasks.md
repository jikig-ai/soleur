---
title: "PR-B tasks — infra-config gate content assert + recovery + ADR/C4 corrections"
issue: 6594
branch: feat-one-shot-6594-b-infra-config-gate
pr_slice: B
plan: knowledge-base/project/plans/2026-07-17-fix-infra-config-delivery-gate-false-green-plan.md
status: ready
---

# PR-B Task Breakdown (#6594)

Branch-scoped breakdown of the **PR-B** rows of the authoritative plan's `## Files to Edit`
table and its Phases 0.1, 2, 3, 4, 5. **PR-A (tunnel origin-relative ingress pin) is a separate,
already-merged/applied/verified PR — not in this branch's scope.** See the plan for full rationale;
this file is the executable checklist and does not restate the diagnosis.

> **The PR split is a mechanism, not a style choice.** `tunnel.tf` (PR-A) applies via
> `apply-web-platform-infra.yml`; `push-infra-config.sh` (PR-B, Phase 4) applies via
> `apply-deploy-pipeline-fix.yml`. Both share `group: terraform-apply-web-platform-host`
> (`cancel-in-progress: false`) which serializes but does NOT order. Never merge PR-A and PR-B together.

## PR-B Files to Edit (from the plan)

| File | Change |
|---|---|
| `.github/workflows/apply-deploy-pipeline-fix.yml` | Extract gate adjudication to a sourceable script; add content assert **outside** the retry loop |
| `apps/web-platform/infra/infra-config-gate.sh` *(new)* | The extracted, testable adjudicator |
| `apps/web-platform/infra/infra-config-gate.test.sh` *(new)* | Failing test + 3 fixtures |
| `apps/web-platform/infra/push-infra-config.sh` | Bump `redeploy-nonce` (recovery — the ONLY prod write) |
| `knowledge-base/engineering/architecture/decisions/ADR-114-one-tunnel-many-connectors-ingress-must-be-origin-relative.md` | Amend (3 items) |
| `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` | Correct the ONE-connector invariant |
| `apps/web-platform/infra/server.tf` | Fix the comment (server.tf:918-920) falsified by push-infra-config.sh:25-31 |

**Do NOT touch in PR-B:** `apps/web-platform/infra/tunnel.tf` (PR-A). Do not modify the shared plan file.

---

## Premises (measured this session — record, do not re-assert from the issue body)

### P0.1 — the #6416 in-band `hostname` tripwire does NOT exist (MEASURED FALSE → the amendment headline)

Ran, per plan Phase 0.1:
```
grep -rnE 'hostnamectl|/etc/hostname|uname -n|\$\(hostname\)|`hostname`' apps/web-platform/infra/*.tf
```
**Result: the ONLY hit is `apps/web-platform/infra/server.tf:222`, a COMMENT that reads
`# ... NOT runtime $(hostname): cloud-init sets no explicit ...`.** Zero host-identity *assertions*
in any of `server.tf`'s 12 `connection {}` provisioner inlines (server.tf has exactly 12; tunnel.tf
and ci-ssh-key.tf have 1 each and are not the "12").

⇒ **`ADR-068:413`'s claim — "Each of the 12 now carries an in-band `hostname` tripwire (#6416)" — is
FALSE.** This is a *third* instance of the plan's meta-defect (a control recorded as enforced that is
inert), and the most consequential (a wrong-host bridge landing would write web-1's config to web-2
silently). **This becomes the ADR-114 amendment HEADLINE (Phase 5, item 3 / D5).**

### P-runner — the new `.test.sh` will be an ORPHAN unless explicitly wired in

`apps/web-platform/infra/*.test.sh` files are **NOT** run by `scripts/test-all.sh` (see its comment
at lines 156-157) and are **NOT** auto-globbed. `.github/workflows/infra-validation.yml` enumerates
each one BY HAND as an explicit `run: bash apps/web-platform/infra/<name>.test.sh` step (lines
~355-394). **`infra-config-gate.test.sh` must be added as its own explicit step** or it is the
#5417 "green CI, zero coverage" class. "It will be picked up automatically" is false here.

### P-gate-shape — current inline gate (the RED baseline)

`.github/workflows/apply-deploy-pipeline-fix.yml` "Verify infra-config apply succeeded" step:
- retry loop `for attempt in 1 2 3` at ~line 417 (`break`s on first pass = **any-of-3** semantics);
- derives only a **count** today (`EXPECTED_COUNT` at ~line 407 via
  `sed -n '/^FILE_MAP=(/,/^)/p' infra-config-apply.sh | grep -cE '_B64\|'`), never per-file content;
- `hooks.json.tmpl` is a paths trigger (line 71); the real FILE_MAP lives in `infra-config-apply.sh`.

### P-comment — server.tf:918-920 is falsified by push-infra-config.sh:25-31

server.tf:918-920 asserts the `depends_on` edge means "the push never races a mid-flight listener
restart". push-infra-config.sh:25-31 documents **nonce-1**, where that race DID happen. nonce-1 is
the counterexample. (`depends_on` edge landed 2026-06-18 / #5516; nonce-1 race 2026-07-10 / #6313.)

---

## Phase 0.1 — Verify the tripwire premise (DONE above; gate the rest of the work)

- [x] AC-0.1a: grep result recorded (P0.1). Tripwire ABSENT.
- [ ] AC-0.1b: This premise flows into Phase 5 item 3 as the amendment headline.

## Phase 2 — RED (reproduce #6594 with a failing test)

Goal: extract the adjudicator, capture the real payload, and prove the current logic PASSES the
stale-same-count payload (i.e. reproduces the bug) before any fix.

- [ ] **2.1** Create `apps/web-platform/infra/infra-config-gate.sh` — a **sourceable** adjudicator
  extracted from the inline YAML gate. Pure function of (status JSON, repo checkout at the applied
  SHA); no network in the assert path. Emits `::error::content_mismatch:<dest>` naming the diverging
  file.
- [ ] **2.2** Create `apps/web-platform/infra/infra-config-gate.test.sh` with **three fixtures**
  (see Fixture Table). The **stale-same-count** fixture is the captured real #6594 payload from the
  plan (`15/15`, `exit_code=0`, `files_failed=0`, `start_ts=1784233325`,
  `ci-deploy.sh sha256=2208300a…`). Fixtures are synthesized/captured artifacts containing paths and
  hashes only — **no secrets** (`cq-test-fixtures-synthesized-only`; confirm at implementation).
- [ ] **2.3** With only the count logic ported (no content assert yet), run the test and
  **confirm stale-same-count PASSES** — reproducing #6594.

**Acceptance (Phase 2):**
- AC-2a: `infra-config-gate.sh` exists and the inline YAML step sources it (no logic duplicated).
- AC-2b: stale-same-count PASSES pre-fix (bug reproduced), asserted by the test itself.
- AC-2c: assert map derived from **FILE_MAP** rows (`VAR|dest|mode|owner` → `basename(dest)`),
  **NOT** from `files[]` (the handler appends `orphan_hook_command` entries with no repo counterpart).
- AC-2d: the single `hooks.json`/`hooks.json.tmpl` exclusion is **derivable from the template
  property** (repo file is `hooks.json.tmpl`), not hardcoded; asserted to be exactly one exclusion.
- AC-2e: content compared against **the SHA the apply ran from**, not `HEAD`.

## Phase 3 — GREEN (content assert; terminal; wired into a runner)

- [ ] **3.1** Add the content assert **OUTSIDE** the `for attempt in 1 2 3` retry loop. A content
  mismatch is **terminal — never retried** (inside the loop = fresh curl = fresh connector =
  any-of-3, which launders the coin flip into a green).
- [ ] **3.2** All three fixtures behave per the Fixture Table (stale-same-count now FAILs naming the
  file; fresh-correct PASSes; sentinel FAILs, not a silent no-op).
- [ ] **3.3** **Mutation-test each assert** — delete/negate the subject assert and confirm the suite
  reddens. A green suite with the assert removed means the assert tests nothing.
- [ ] **3.4** **Wire the new test into a runner** — add an explicit
  `run: bash apps/web-platform/infra/infra-config-gate.test.sh` step to
  `.github/workflows/infra-validation.yml` (see P-runner). Confirm it is collected (no auto-glob).

**Acceptance (Phase 3):**
- AC-3a: content assert is lexically outside the retry loop; a mismatch exits non-zero once.
- AC-3b: all three fixtures match the Fixture Table post-fix.
- AC-3c: mutation of each assert reddens the suite.
- AC-3d: `infra-config-gate.test.sh` appears as its own `run:` step in infra-validation.yml.

## Phase 4 — Recovery (the plan's ONLY prod write; UNBLOCKED)

**GATING — satisfied:** PR-A (the tunnel `deploy.`/`ssh.` origin-relative pin) was merged, applied,
and VERIFIED on prod 2026-07-17 (CF-API config read-back AND `/hooks/deploy-status` probe both
passed; fail2ban ignoreip SSH apply delivered). **Phase 4 is therefore UNBLOCKED and the merge IS
the authorization** (`hr-prod-host-config-change-immutable-redeploy` is satisfied: this re-delivers
repo-defined files, it does not mutate host config in place).

- [ ] **4.1** Bump the `redeploy-nonce` in `apps/web-platform/infra/push-infra-config.sh` — **that
  file ONLY** (current value `redeploy-nonce: 6178-deliver-missing-cutover-probes-2` at line 35).
  This re-fires `deploy_pipeline_fix` **alone** (absent from `handler_bootstrap`'s trigger set) → no
  bridge, no restart, **no nonce-1 race**.
- [ ] **4.2** No `-replace`, no `workflow_dispatch`, no SSH. The merge auto-applies.

**Acceptance (Phase 4):**
- AC-4a: only `push-infra-config.sh` changed in this phase; diff is a single nonce line.
- AC-4b: **Expect main to be truthfully RED between Phase 3 and Phase 4** — the content assert is
  correctly red against a genuinely stale host until the nonce lands. This is intended; do NOT "fix"
  it. Post-nonce, the gate goes green (or names `ci-deploy.sh` if still `2208300a`).

## Phase 5 — ADR-114 amendment + C4 correction + server.tf comment fix

- [ ] **5.1** Amend `ADR-114-…-origin-relative.md` — **3 items**:
  1. I1 is inert (construction-time gate; `ignore_changes=[user_data]` + #6482).
  2. I2's antecedent discharged for `deploy.` AND `ssh.` (record origin-relative restores availability).
  3. **HEADLINE (per P0.1):** the #6416 in-band `hostname` tripwire is unsubstantiated — MEASURED
     ABSENT this session; `ADR-068:413` and #6440's "safe to run" both carry a false enforcement claim.
  - **Quote and REBUT the fan-out recommendation** at ADR-114 (~line 121-123: *"the cheapest fix …
    needing no `.tf` and no tunnel change"*): fan-out fixes the WRITE, not the READ (`deploy-status`
    / `inngest-liveness` stay coin-flipped), and it presumes web-2 should be converged (#6440's open
    question). Cite by **content anchor**, not bare line number (`cq-cite-content-anchor-not-line-number`).
- [ ] **5.2** Correct the ONE-connector invariant in
  `knowledge-base/engineering/architecture/diagrams/model.c4` — the `technology`/`description` on the
  `tunnel` container (*"exactly ONE connector … INVARIANT (ADR-114 I1, enforced #6425)"*) and the
  Tunnel→host edge, both false in production (2 live connectors, measured). Ensure web-2 is modeled.
  Read all three `.c4` files ({model,views,spec}); cite by content anchor. **Run BOTH C4 tests**
  (`c4-code-syntax.test.ts` + `c4-render.test.ts`) — a `view include` on an undefined element fails
  there, not at `tsc`.
- [ ] **5.3** Fix `apps/web-platform/infra/server.tf:918-920` — the comment claiming the `depends_on`
  edge means *"the push never races a mid-flight listener restart"*. nonce-1 (push-infra-config.sh:25-31)
  is the counterexample. Correct the comment to state the race is real (edge does not close it).

**Acceptance (Phase 5):**
- AC-5a: ADR-114 carries all 3 amendment items; the tripwire falsification is the headline; fan-out
  is quoted and rebutted by content anchor.
- AC-5b: model.c4 invariant + Tunnel→host edge corrected; web-2 modeled; both C4 tests pass.
- AC-5c: server.tf comment no longer asserts the falsified "never races" claim.

---

## Fixture Table (Phase 2/3 — from the plan's "The failing test")

| Fixture | Pre-fix | Post-fix |
|---|---|---|
| **stale-same-count** (the real #6594 payload: 15/15, `exit_code=0`, `files_failed=0`, `start_ts=1784233325`, `ci-deploy.sh sha256=2208300a…`) | **PASS** ← the bug | **FAIL** `content_mismatch:/usr/local/bin/ci-deploy.sh` |
| **fresh-correct** (all delivered hashes == repo files) | PASS | **PASS** (no false-positive) |
| **sentinel** (`{"exit_code":-2,"reason":"no_prior_apply"}` — no `files[]`) | — | **FAIL**, not a silent no-op |

## Sharp edges (carried from the plan)

- Never put the content assert inside the retry loop (fresh curl = fresh connector = any-of-3).
- Expect main RED between Phase 3 and Phase 4 — a true red; do not "fix" it.
- Key the assert off **FILE_MAP**, not `files[]`; compare against the **applied SHA**, not `HEAD`.
- The single `hooks.json` exclusion is derived from the `.tmpl` template property, asserted == 1.
- An unregistered `.test.sh` is an orphan (#5417 class) — wire it into infra-validation.yml explicitly.
- Never hardcode `15` or `10.0.1.10` — both have canonical sources.
