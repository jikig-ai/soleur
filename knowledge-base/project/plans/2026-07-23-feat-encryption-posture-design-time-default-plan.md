---
title: "feat: Encryption-at-rest + in-transit as a design-time DEFAULT across the Soleur workflow"
date: 2026-07-23
type: feature
branch: feat-one-shot-encryption-at-rest-in-transit-design-default
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-140 (provisional ordinal — re-verify against origin/main at /ship)
---

# feat: Encryption-at-rest + in-transit as a design-time DEFAULT

## Enhancement Summary

**Deepened on:** 2026-07-23
**Gates run:** 4.4 (precedent-diff + scheduled-work), 4.45 (verify-the-negative), 4.55 (downtime — does not fire), 4.6 (user-brand — PASS), 4.7 (observability — PASS, all 5 fields non-placeholder, no `ssh`), 4.8 (PAT-shaped — PASS), 4.9 (UI wireframe — does not fire)
**Execution constraint:** the `Task` tool was unavailable in this context, so the per-section research and review fan-outs (Phases 2, 3, 5) could **not** be spawned. Every gate and quality check that is mechanically runnable was run directly; the agent-panel passes were **not** performed and must be supplied by `/plan-review` before `/work`. This is recorded rather than silently skipped.

### Key improvements

1. **D8 added — Layer B scheduler placement was wrong by the canonical pattern.** Phase 4.4's scheduled-work check found 53 Inngest cron functions vs 10 GH Actions crons (ADR-033 makes Inngest canonical) **and** a PreToolUse hook (`.claude/hooks/new-scheduled-cron-prefer-inngest.sh`) that will **DENY** the Write at `/work` time. The plan now argues the two-part exemption explicitly, adds the decisive circularity argument (an encryption verifier must not run on a substrate it audits), and declares the hook's documented override hatch plus a mandatory in-file justification — instead of leaving `/work` to hit the deny and override it silently.
2. **The `hcloud_volume` negative claim is now version-scoped.** "There is no `encrypted` attribute" is pinned to `hetznercloud/hcloud` **v1.63.0** from `.terraform.lock.hcl`, not inferred from two in-repo comments that merely restate each other.
3. **Precedent diff produced for all three pattern-bound behaviors**, with the one deliberate divergence named (this gate is *required* where its lint-script precedent is deliberately *advisory*), and the observation that the two genuinely-LUKS volumes double as the detector's calibration fixture.
4. **A fabricated-looking rule-ID citation was neutralized.** The rejected-alternatives table named a *hypothetical* `hr-*` id for the rule this plan deliberately does not create; it did not resolve against `AGENTS.md` and was structurally indistinguishable from a real citation. Rewritten to `an AGENTS.md hr-* hard rule (no id — the rule is not created)`, so the whole plan now passes the rule-ID resolution sweep with zero unresolved tokens.
5. **AC19's verification command was broken** (`grep -lc` — mutually exclusive flags) and is fixed.
6. **All external citations re-verified live** — 9 issue/PR states, 5 labels, 10 AGENTS rule IDs, and the ADR ordinal derived from a freshly fetched `origin/main`.

### New considerations discovered

- The plan's own detector must certify `git-data-luks.tf` and `workspaces-luks.tf` on day one; if it cannot, it is miscalibrated. This is a stronger day-one signal than any synthetic fixture.
- `hcloud_volume.inngest_redis` being (apparently) plaintext is not just an audit finding — it is the reason Layer B cannot live on Inngest.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Plan Review Revisions — BINDING (2026-07-24, supersedes conflicting text below)

The 7-agent `/plan-review` panel the `single-user incident` threshold mandates (DHH, Kieran,
code-simplicity, architecture-strategist, spec-flow-analyzer, cto-devex, cpo) ran out-of-band
before `/work` (task 8.2b, correctly reordered to run FIRST). Verdict: **unanimous do-not-proceed
as-written.** The research quality held (≈20 factual claims re-verified), but the two load-bearing
specs (the Layer A LUKS detector D2, and the required-check promotion D7) each shipped a defect that
would produce an unbuildable AC or a **false PASS on the exact volume that caused the incident.**

Operator decisions (2026-07-24): **(1) revise in place, narrowed; (2) keep audit-only** — this PR
remediates nothing, findings become tracked issues with a milestone + a parent claim-unlock issue.

**Where this block conflicts with any Decision, AC, TS, or Phase below, THIS BLOCK WINS.** `/work`
implements against these corrections.

### R0 — Scope narrowing (operator decision 1)

- **`constraint-scaffold` (deliverable 6) LEAVES this PR.** It ships as its own product-framed
  follow-up (CPO F6): a founder's repo is a different audience, blast radius, quality bar, and
  recovery model than Soleur's own CI, and it currently has **no tenant invocation path**
  (`constraint-scaffold` only ever runs against `apps/web-platform`; ADR-074 lists tenant emission as
  a future consequence — CPO F4). File the follow-up issue IN this PR's body (Phase 4 milestone,
  `Ref #6588`) so the split cannot drop it. Remove its rows from `## Files to Create` / `## Files to
  Edit` (the two `references/*.template`, `test/encryption-posture.test.sh`, the `SKILL.md` +
  `constraint-scaffold.sh` + `parity.test.sh` edits). Delete Phase 6.4, AC20, AC21. **The follow-up
  issue MUST record the four unresolved design questions the panel raised** so they are decided in
  that PR, not rediscovered: additive `--gate <name>` emit (refuse-if-exists is all-or-nothing today,
  so an already-scaffolded repo exits 66 having emitted nothing — Kieran B5, cto A8); a
  captured-baseline / grandfather path so a first run on a populated repo is GREEN (spec-flow #8);
  the emitted gate is **non-blocking** in a founder repo with **founder-readable** failure strings
  (no `LUKS`/`sslmode`/`luksFormat`/`verify-full` without a plain-language gloss) and a
  `needs-a-migration` class that is never a red gate (CPO F3/F5, cto A3, spec-flow #10/#11); and a
  Hetzner-shaped tree must produce a **reachable** verdict, since D2 proves "storage resource lacking
  an encryption declaration" is structurally unsatisfiable for `hcloud_volume` (spec-flow #9). D7's
  "advisory is no gate" reasoning is **Soleur-repo-only**; it does not transfer to a founder repo,
  where a red gate they cannot clear is the brand-survival deadlock `constraint-scaffold` exists to
  avoid.

### R1 — Layer A detector: volume-identity binding (Kieran B1/B2 — the false-PASS blocker)

The namespace is adversarial: `hcloud_volume.workspaces` (PLAINTEXT, the `#6588` volume) sits beside
`hcloud_volume.workspaces_luks` (LUKS, mapper `workspaces`); same for `git_data`/`git_data_luks`.
Under **any** name- or mount-path similarity join, `/dev/mapper/workspaces` matches the plaintext
`workspaces` at least as well as the encrypted `workspaces_luks`, so a row `store:
hcloud_volume.workspaces, mechanism: luks` citing its sibling's apparatus PASSES — certifying the
exact volume this feature exists to catch. **No string-similarity join is permitted.**

- Every `hcloud_volume` ledger row carries `device_binding`: the Terraform resource address of the
  volume **and** the `hcloud_volume_attachment` that carries it. The detector must reach the LUKS
  citation chain **from that attachment** (attachment → host cloud-init/bootstrap/cutover for that
  host → the `cryptsetup` site on that host), never from a name match.
- **Two-shape LUKS contract** (D2 as written fits only `git_data_luks`, so it FAILS
  `workspaces_luks`, which AC33 requires it to certify — a direct contradiction). Clause (a) accepts a
  `cryptsetup luksFormat|luksOpen` site in **any** file under `apps/*/infra/` — cloud-init, bootstrap,
  **or cutover** — resolving the mapper operand through **at most one** level of `${VAR:-default}`
  shell expansion assigned in the same file (taking the `:-` default literal). Clause (c) accepts an
  fstab-write line **or** a `MAPPER=/dev/mapper/<name>` + `MOUNT=<path>` fail-closed gate pair. Mapper
  equality is asserted AFTER resolution; the resolved expected values are literally `git-data` and
  `workspaces`.
- **New fixtures:** TS-15 = row `store: hcloud_volume.workspaces, mechanism: luks` citing the
  `workspaces_luks` apparatus → **FAIL (citation belongs to a different volume)**. MB-8 = delete the
  volume-identity binding check → TS-15 must red. Without TS-15/MB-8 the battery does not cover the
  plan's headline failure mode.

### R2 — Layer B: Inngest-dispatch hybrid, Sentry plane, measurable-only floor

- **D8 is deleted and rewritten (arch F1, DHH S2b, simplicity #3).** ADR-033's own scope note names
  `scheduled-terraform-drift` as the *correct* shape for a credential-heavy infra cron and warns "Do
  not mis-cite this rejection as a blanket ban on Inngest→workflow_dispatch." Adopt the hybrid:
  `apps/web-platform/server/inngest/functions/cron-encryption-posture-reconcile.ts` owns the schedule
  and `workflow_dispatch`-es `.github/workflows/scheduled-encryption-posture-reconcile.yml` (which
  keeps `on: workflow_dispatch:` only). The `prefer-inngest` hook keys on a `schedule:`/`cron:`
  directive and therefore **never fires** — so **the override marker, the in-file justification block,
  and AC32 are all deleted.** The circularity argument was unsound (a plaintext AOF does not crash
  Inngest — correlation ≈ 0, not 1); the real residual is Inngest-trigger *availability*, already
  covered by `scheduled-inngest-health.yml`. Record that one-line residual in ADR-140.
- **Heartbeat moves to the Sentry plane (arch F8).** All 10 `scheduled-*.yml` use Sentry check-ins;
  `sentry-monitor-iac-parity.test.ts` FAILS a workflow heartbeat with no `sentry_cron_monitor`
  (the `#6374` shape — a workflow ran 14h unseen). Emit a Sentry heartbeat slug
  `scheduled-encryption-posture-reconcile`, add the resource to
  `apps/web-platform/infra/sentry/cron-monitors.tf` (add to `## Files to Edit`; drop the
  `uptime-alerts.tf` Better Stack heartbeat). Routing to Better Stack would ALSO diverge from
  `docs/legal/data-protection-disclosure.md` §(m) — a published legal disclosure, in the PR whose
  purpose is preventing exactly that divergence. Keep the ADR-117 measure-then-arm count-gate.
- **Positive-work floor scoped to the measurable set (arch F3, cto A1, simplicity #2).**
  `luks-monitor.sh` probes ONE volume; the Hetzner API is blind to guest-side LUKS (D2's premise);
  SSH is forbidden. As written Layer B aborts daily forever and its 3-day soak never greens. Add
  `live_verification: available | unavailable:<reason>` to the row schema; the floor counts only
  `available` rows (today: `workspaces_luks`); each `unavailable` row carries its own tracking issue
  and is itself a finding. Building per-volume posture emitters for the other hosts is explicit
  **follow-up scope**, not an implicit assumption. Layer B **shells out** to
  `python3 scripts/lint-encryption-posture.py --report --json` for all ledger parsing (single schema
  owner — arch "Layer A/B split") and files **find-or-update-by-title**, never a fresh P1 daily
  (arch F10).

### R3 — Exceptions get a hard clock (spec-flow #4, DHH S6, arch F5)

`reevaluate_when` is inert; Layer B *reds* when a `tracking_issue` is CLOSED, so the system rewards
leaving tickets open forever and running `drain-labeled-backlog` on the Phase-1 findings would break
the gate. Add `expires_on: YYYY-MM-DD` (≤90 days from acceptance) enforced by **Layer A** (offline,
no network, no issue-state dependency); an expired exception FAILs the required check; renewal is a
dated, reviewable ledger diff. Demote Layer B's `state==CLOSED` check to a **warning**. Add TS-16
(expired exception → FAIL) + MB-9. **Delete `accepted_by`** — in a one-person shop authored by the
agent it is a control with one value (DHH S6); the real acceptance signal is the reviewed PR diff.

### R4 — Required-check promotion is FIVE coupled sites, not three (Kieran B3, cto A6)

D7/Phase 3 miss two: (4) `scripts/ci-required-ruleset-canonical-required-status-checks.json` — whose
`required-checks-canonical-parity.test.sh` asserts set-equality, so adding the name to
`required-checks.txt` alone turns an EXISTING suite RED and fails AC30 with no explanation; and (5)
`.github/actions/bot-pr-with-synthetic-checks/action.yml`, conditionally, per the `#6049`
adjudication. **Arm B is rewritten:** "add to `required-checks.txt`" + "exclude via non-15368
`integration_id`" are contradictory (the parity test's `comm -23` would flag it). The real arm B is
CodeQL's shape — **omit** the name from `required-checks.txt` and pin a non-15368 `integration_id` in
the ruleset + canonical JSON. Add site (4) to `## Files to Edit`; extend AC13 to assert equality
across sites (1)(2)(3)(4) and that the ruleset ABI-count comment equals the `required_check` block
count; rewrite AC14. **CI-job non-vacuity (Kieran H2):** add MB-10 — a `continue-on-error: true` or
trailing `|| true` on the `encryption-posture` job must still leave the known-bad fixture PR's check
RED; nothing else in the plan proves the job can fail.

### R5 — The ledger↔published-disclosure join (CPO F1 + spec-flow #15 — two lenses, same gap)

Layer A joins ledger↔code; Layer B joins ledger↔infra; **nothing joins ledger↔published legal
disclosure** — the exact edge that broke `#6588`. Day-one green end state: `inngest_redis` carries a
`plaintext-exception` row while `privacy-policy.md:519` still asserts LUKS. Add a required
`disclosed_as` field: the `docs/legal/**` `file:anchor` making a public claim about this store, or the
literal `not-publicly-claimed`. **Layer A FAILs** when a `plaintext-exception` (or `cert_verification:
off`) row's `disclosed_as` anchor resolves to text asserting encryption. Add TS-17 + MB-11. This is
the cheapest change with the most direct line to the incident; without it the plan's own claim ("the
ledger is the join the incident lacked", D6) is only two-thirds true. Human legal-copy correction
remains a separate `/soleur:legal-audit` issue (filed from Phase 1.4), but the mechanical join lands
here.

### R6 — In-transit moves to the existing Semgrep surface (cto A2/A4, simplicity #10)

`plugins/soleur/skills/review/references/semgrep-custom-rules.yaml` already exists (bootstrapped by
`ensure-semgrep.sh`, driven by the `semgrep-sast` agent); CodeQL already flags `rejectUnauthorized:
false` for free. D3's fail-closed-on-indeterminate branch would fire on essentially the whole
connection surface — `run-migrations.sh` uses `sslmode=require` against the self-signed Supabase
pooler chain, and 52 non-test sites source their DSN from Doppler at runtime with **no scheme string
in the code at all**. Move the D3 ban-list into `semgrep-custom-rules.yaml` as
`soleur.tls-cert-verification-defeated` + `soleur.postgres-sslmode-unverified` (single shared
`references/encryption-posture-banlist.json`, arch F7). **Delete** from
`lint-encryption-posture.py`: the connection-surface recognizer, the require-list, the
fail-closed-on-indeterminate branch, TS-9..TS-13, MB-6, MB-7. Keep `sslmode=require`-in-ban-list as
the Semgrep rule's intent (with the "do not move to allow-list" comment). **Pre-adjudicate** the
Supabase pooler self-signed-chain exception in the plan with its own tracking issue (the
`byok-*.tenant-isolation.test.ts` `rejectUnauthorized:false` sites are its known instances —
test-path-excluded). The hand-rolled detector keeps ONLY the four-part guest-side LUKS resolver + the
ledger-completeness sweep — the genuinely un-buyable part.

### R7 — Resource-type partition is three-way, not open-ended (arch F6, simplicity #9)

"Unknown type ⇒ FAIL-CLOSED" is undecidable: 44 distinct `resource "…"` types exist, 3 storage-shaped.
As written it either wedges every unrelated infra PR (a new `cloudflare_record` fails) or is theater
(a name heuristic false-positives `hcloud_volume_attachment`). Commit an explicit three-way partition
beside the ledger: `store_classes` (checked), `non_store_types` (seeded from the current 44-type
inventory, explicitly acknowledged), else ⇒ FAIL "add `<type>` to `store_classes` or
`non_store_types`". Add a test asserting a `cloudflare_record` does NOT fail and a novel `*_bucket`
type DOES. This makes AC7 testable as stated.

### R8 — Non-IaC ledger anti-omission + Layer A hermeticity (Kieran B4, arch "hermeticity")

5 of 13 stores (Supabase ×2, Doppler, Better Stack, the R2 state backend, `sessionStore`) have **no
`*.tf` anchor** — deleting their rows silently lowers the floor and the sweep still passes. Compute
the floor from a repo scan + a committed expected-count constant and an explicit `non_iac_stores`
list, not from the ledger; FAIL when actual < expected. AC6 becomes `== 13 stores, == 8 connections`.
Add MB-12 (delete a non-IaC row → must red). **State the hermeticity invariant in ADR-140 and assert
it:** Layer A is offline and credential-free (no `gh api`, tempting because Layer B does it); run the
sweep with no network and require an identical verdict.

### R9 — Attestation staleness (cto A7, spec-flow #17)

7 of ~13 rows are `provider-managed:<attestation>` with a retrieval date nothing re-checks — the
`#6588` shape reproduced inside the ledger. Add `retrieved_on` with a 365-day max enforced by Layer A
(offline: date arithmetic only); Layer B (when it can reach the network) re-fetches the attestation
URL and warns on link-rot. **Before `/work`**, `curl -sI` each of the 7 attestation sources for
public reachability; any behind a login is a step that must route to a bootstrap script per
`hr-multi-step-post-merge-bootstrap-script` (never a hand-run operator step) or a named public
substitute — the blanket "zero operator steps" claim is unverified for these rows.

### R10 — Smaller corrections (apply verbatim)

- **`does_not_defend` restatement rejector (TS-12) is deleted** (DHH S7, simplicity #6): verbatim-only
  match is defeated by rewording — a vacuous grep for a semantic property, the very anti-pattern the
  plan cites elsewhere. **Keep the mandatory field**; a reviewer judges semantics, not a regex.
- **Failure-message contract (spec-flow #1):** the plan defines verdicts but only ONE failure string.
  Add a section enumerating one operator-facing line per reject branch: `FAIL: <what> → <exact next
  command / ledger field>` (precedent: `lint-credential-path-literals.py`). Extend TS-2..TS-17 to
  assert the classification **string**, not just the exit code. Add an AC.
- **Phase 0.3 numeric-max (Kieran H3, DHH S9):** the file is not in numeric order (Check 7 at line
  943). Use `grep -oE '^### Check [0-9]+' … | grep -oE '[0-9]+$' | sort -n | tail -1`; same for the
  `deepen-plan` §4.x probe (guard `4.10` vs `4.1`).
- **AC26 (Kieran H5):** assert AGENTS.md/AGENTS.core.md are **untouched in the diff**, not an absolute
  `B_ALWAYS == 22900` (which reds the moment any sibling PR merges).
- **AC28 (Kieran H1):** add a second assertion — `tests/scripts/test-encryption-posture-reconcile.sh`
  is registered in `scripts/test-all.sh` (the orphan-linter only scans `scripts/*.test.sh`).
- **C4 (arch F9):** also correct `model.c4:415` (the `hetzner -> workspacesVolume` relationship still
  says "plaintext at rest … #6812"); add to Phase 7.2.
- **AC2/AC3/AC18/AC22 (Kieran H4):** give each a runnable anchored-content predicate (AC4's shape),
  not a bare-token grep (`cq-assert-anchor-not-bare-token`).
- **§4.10 template↔validator coupling (Kieran M3, arch F7):** add a `--check-templates` mode to
  `lint-encryption-posture.py` validating the three `plan-issue-templates.md` blocks against
  `encryption-posture-ledger.schema.json` — closes the new pair AND is the generic harness `#4133`
  wants.
- **Task 7.5 (DHH S8):** dropping the principle into the 78 KB `constitution.md` is filing, not
  enforcement; the real enforcement is the skill/agent edits that load. Keep it as a one-line pointer
  only, not as the load-bearing placement.
- **ADR-033 citation (arch F11):** cite by filename, not the bare ordinal (033 collides across three
  files).

### R11 — Audit findings: milestone + parent (operator decision 2, spec-flow #16, CPO F2)

Phase 1.4 findings currently get labels but **no milestone**, so `drain-labeled-backlog` (which
queries `--milestone`) can never see them. Each filed issue MUST carry the Phase 4 milestone and at
least one `*.tf` path in its body (the drain clusters by body paths). File one **parent** issue —
"Encryption posture: zero user-data-bearing plaintext exceptions" (Phase 4 milestone, `Ref #6588`) —
as the **claim-unlock gate**: until it closes, external copy is constrained to the *verifiability*
claim ("we now know and continuously verify what is and isn't encrypted"), never "encrypted by
default from day one." `inngest_redis` and `registry` findings are children. **This PR still
remediates nothing (AC25 stands.)**

## Overview

Make **"encrypted at rest + encrypted in transit"** the enforced default across the Soleur
workflow, so every persistent store and every cross-component connection — in Soleur's own
systems **and** in the systems Soleur builds for its users — carries a declared, *mechanically
verified* encryption posture from the first commit rather than as a retrofit.

The gate is three layers, not one:

| Layer | Where | What it asserts | Blocking? |
|---|---|---|---|
| **Design** | `plan` §2.11 + `deepen-plan` §4.10 | The decision was *made and recorded* (`## Encryption Posture`) | Halts the pipeline |
| **Static (Layer A)** | `scripts/lint-encryption-posture.py` → CI + `preflight` Check 12 | Every store/connection in the repo has a ledger row **whose cited evidence resolves to real code** | **Required check** |
| **Live (Layer B)** | `tests/scripts/lib/encryption-posture-reconcile.sh` + scheduled workflow | The **actual** provider/host state matches the ledger | Fails the schedule → files an issue |

Layer B is not optional polish. A design-time declaration plus a static citation check is still,
ultimately, a set of claims about the repo. **The incident being encoded against was exactly a
claim-vs-reality divergence** — three published legal documents said LUKS while `/mnt/data` was
plaintext ext4. A gate that only reads the repo reproduces that failure with extra steps.

## Problem Statement / Motivation

`hcloud_volume.workspaces` (web-1 `/mnt/data`) was provisioned as plaintext `ext4` while
`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` told data subjects it was
LUKS-encrypted. The gap survived for weeks for two structural reasons:

1. **Nothing at design time forced the encryption decision to be made and recorded.** Every other
   cross-cutting concern the workflow cares about — observability, user-brand impact, GDPR, IaC
   routing, ADR/C4 — has a plan-phase gate. Encryption did not.
2. **Nothing mechanical compared the claim against reality.** The legal docs were prose; the
   volume was a block device; no artifact joined them.

Closing it cost a multi-day cutover: a sole-copy-data write freeze, an operator-accepted
irreversible discard of a 27-minute stranded-write window, and a separate latent `readyz`
peer-gate bug fix (#6879) before the cutover could even certify.

The operator's goal: **no future Soleur user repeats that.** That is why deliverable 6
(`constraint-scaffold`) is the highest-leverage half of this work — it is the only deliverable
that ships the gate into somebody else's codebase.

## Research Reconciliation — Premise vs. Codebase

Run at Phase 0.6 (pre-research premise validation) and Phase 1.7. Every premise the task
description asserts was probed.

| Premise (as stated) | Reality (verified this session) | Plan response |
|---|---|---|
| "The incident issue is CLOSED." | **PARTIALLY STALE.** `#6604` (the `/workspaces` LUKS cutover PR-2 issue) is CLOSED. **`#6588` — the parent P1 security issue — is still OPEN**, as are `#6733`, `#6808`, `#6814`. `gh issue view 6588 --json state` → `OPEN`. | Confirms the "no `Closes` line" instruction, and *strengthens* it: this PR must not close `#6588` either. Audit findings get their own issues; those that fall inside `#6588`'s scope are cross-linked with `Ref #6588`, never `Closes`. |
| "AGENTS budget `B_ALWAYS=22900`, ~100 bytes headroom." | **CONFIRMED.** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1` → `[WARN] B_ALWAYS=22900 >= 20000 (AGENTS.md=6072 + AGENTS.core.md=16828)`. | **No AGENTS rule, no AGENTS pointer.** See Decision D4 — the constraint is *doubly* binding (budget AND loader-class fit). |
| "preflight: a diff adding a persistent store **without an encryption attribute** FAILs." | **THE PREMISE IS WRONG FOR THE STACK IN USE, AND THE CORRECTION IS LOAD-BEARING.** There is **no `encrypted` attribute on `hcloud_volume`** — `apps/web-platform/infra/workspaces-luks.tf` §"SHARP EDGE" and `git-data-luks.tf:11-16` both state it verbatim: *"encryption-at-rest is GUEST-SIDE LUKS, NOT an `hcloud_volume` attribute. There is no hcloud `encrypted` flag."* An attribute-presence detector can **never** pass for a Hetzner volume, or (worse) would be satisfiable by a comment. | The detector keys on the **guest-side LUKS apparatus** — `cryptsetup luksFormat`/`luksOpen` site, the `random_password` key resource, the `doppler_secret` delivery, and a `/dev/mapper/*` mount — resolved as **citations that must actually exist and reference this volume**. See Decision D2. |
| "`plan`/`review`/`preflight` may be eval-gated (`gated-skills.json`)." | **NOT GATED.** `plugins/soleur/skills/eval-harness/gated-skills.json` contains exactly 4 entries: `commands/go.md`, `agents/support/ticket-triage.md`, `skills/brainstorm/references/brainstorm-domain-config.md`, `skills/incident/SKILL.md`. None of `plan`/`review`/`preflight`. | The eval-harness requirement **does not fire**. No eval arm is added. Recorded so a reviewer does not re-litigate. |
| "`constraint-scaffold` already ships a CI gate into a user's product codebase." | **CONFIRMED.** `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` (172 LoC) emits 5 artifacts into `apps/web-platform/` from 5 `references/*.template` files, with 4 self-test suites. ADR-071 (mechanism) + ADR-074 (two-stage recovery). | Deliverable 6 **extends** this generator with a second gate; it does **not** add a sibling skill. See Decision D5 (skill-description budget is at **2366/2366 — zero headroom**). |
| Store types "actually in use". | **ENUMERATED FROM `*.tf`** (see `## One-Time Audit` below): 6 × `hcloud_volume`, 2 × `cloudflare_r2_bucket` declared in-repo, plus the R2 Terraform-state backend, Supabase Postgres (×2 projects), Doppler, Better Stack Logs, and 2 Redis stores. | The detector's resource table covers all declared classes and is extensible via one table in the ledger schema (Decision D6). |
| Task/subagent fan-out for research. | **UNAVAILABLE.** The `Task` tool is not enabled in this planning execution context (`Error: No such tool available: Task`). | All Phase-1/2.5 research and domain assessment was performed **in-orchestrator** by direct file reads and greps. Recorded honestly in `## Domain Review` as `reviewed (in-orchestrator, subagents unavailable)` — not as a clean multi-agent pass. `/plan-review` and `/deepen-plan` re-run with agents available. |

## Proposed Solution

### Decision D1 — The mechanical check is a **script with its own test suite**, not skill prose

`preflight` is an LLM-executed `SKILL.md`. Prose cannot be mutation-verified, and the design
principle is explicit: *every gate added must be mutation-verified non-vacuous — mutate the guard
out and confirm the suite reds.*

So the detector is `scripts/lint-encryption-posture.py`, following the established repo pattern
(`scripts/lint-trap-tempfile-ownership.py`, `scripts/lint-credential-path-literals.py`,
`scripts/lint-agents-rule-budget.py` — each with a `.test.sh` sibling registered in
`scripts/test-all.sh`). `preflight` Check 12 **shells out to it**; the skill prose owns
presentation and the PASS/FAIL/SKIP contract, the script owns the decision.

### Decision D2 — The detector asserts **resolvable evidence**, never a self-asserted attribute

For each store class, the ledger row must name a citation, and the linter must *resolve* it:

> **⚠ SUPERSEDED IN PART by R1 (see the BINDING revisions block above).** The `hcloud_volume` row
> below is corrected there: the join from `hcloud_volume.<name>` to its apparatus MUST go through an
> explicit `device_binding` (resource address + `hcloud_volume_attachment`), never string similarity
> — otherwise a `mechanism: luks` row on the PLAINTEXT `hcloud_volume.workspaces` false-PASSes on its
> encrypted sibling's citations. Clause (a) accepts a `cryptsetup` site in **any** `apps/*/infra/`
> file (cloud-init / bootstrap / **cutover**) with one level of `${VAR:-default}` resolution, and (c)
> accepts an fstab line **or** a `MAPPER=/dev/mapper/<name>`+`MOUNT=` gate pair. R1 wins on conflict.

| Store class | `mechanism` accepted | Evidence the linter **resolves** |
|---|---|---|
| `hcloud_volume` | `luks` | (a) a `cryptsetup luksFormat`/`luksOpen` site in a cloud-init/bootstrap file that names this volume's device or mapper; (b) a `random_password` + `doppler_secret` pair delivering the key; (c) a mount whose source is `/dev/mapper/<name>`. All three must exist; the mapper name in (a) and (c) must match. **[R1: reach these from `device_binding`, not name match; accept the cutover-script + gate-pair shape too.]** |
| `cloudflare_r2_bucket` | `provider-managed:<attestation>` | A named attestation with a retrieval date in the ledger row, **plus** the bucket's `location`/jurisdiction field present in `*.tf`. Bare `"the provider handles it"` is a hard FAIL (literal-string reject on `provider handles`, `handled by the provider`, `encrypted by default` with no attestation name). |
| Supabase Postgres | `provider-managed:<attestation>` | Same, plus the project ref must resolve through the existing `preflight` Check 4 environment-isolation regex (so the row cannot name a project that is not the one in use). |
| Redis (`inngestRedis`, `sessionStore`) | `luks` \| `provider-managed:…` \| `plaintext-exception` | The AOF/RDB path must resolve to a volume that itself has a ledger row (transitive: a Redis store on a plaintext volume is a plaintext store). |
| Any new `*.tf` storage resource | — | **Unknown resource type ⇒ FAIL-CLOSED** with the message "add `<type>` to the ledger schema's `store_classes` table". A new store class can never enter silently. |

### Decision D3 — In-transit is asserted **at the connecting code**, with cert verification proven ON

`in_transit` rows name a `file:anchor` in the *connecting* code. The linter runs a two-sided check
over the connection surface (mirroring `preflight` Check 9's ban-list shape, which is the repo's
established form):

- **Require:** the scheme is TLS-bearing (`https://`, `rediss://`, `wss://`, or a Postgres URL with
  `sslmode=verify-full`).
- **Ban (cert-verification defeats):** `rejectUnauthorized: false`, `NODE_TLS_REJECT_UNAUTHORIZED=0`,
  `--no-check-certificate`, `--insecure`, `curl -k`, `verify=False`, `InsecureSkipVerify`, and
  `sslmode=` values in `{disable, allow, prefer, require}`.
  **`require` is in the ban-list on purpose:** libpq's `sslmode=require` encrypts but does **not**
  verify the certificate, so it satisfies "TLS is on" while failing "cert verification is on". This
  is the in-transit analogue of the `hcloud_volume` attribute trap — the thing that *looks* like the
  check is not the check.
- Anything matching neither require- nor ban-list on a recognized connection surface ⇒
  **FAIL-CLOSED**, per `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`.

### Decision D4 — **No AGENTS.md rule and no AGENTS pointer.** Route into the owning skills/agents

Two independent blockers, both measured this session:

1. **Budget.** `B_ALWAYS = 22900 / 23000` (≈100 bytes headroom). An index pointer line
   (a hypothetical `- [id: hr-<name>] → rest` line — illustrative shape, not a citation) costs ≈50-60 bytes, leaving ≈40. `lint_union`
   couples pointer↔body 1:1, so even a `rest`-class body still charges the always-loaded index.
   Landing at 40 bytes of slack means the next sibling PR trips `[REJECT]` and blocks every commit
   (the #5349 / #6138 failure mode).
2. **Loader-class fit — the decisive one.** This rule's trigger surface spans `*.tf` (→ `infra`
   class → loads `core + rest`) **and** `plugins/*/skills/*/SKILL.md` (→ `.md` → `docs-only` class →
   loads `core + docs-only`). A rule that must fire on *both* can only live in `AGENTS.core.md`,
   which has zero room. Per `2026-05-12-agents-md-trim-loader-class-fit-verification.md`, placing it
   in `rest` would make it a **silent no-op on its own docs-only trigger**.

The insight is domain-scoped — it can only fire on an infra/data-design turn, never an arbitrary
one — so it routes to the owning skills and agents, which is where a domain-scoped rule belongs.
The principle is recorded in **ADR-140** and in `knowledge-base/project/constitution.md`.

### Decision D5 — **Extend** `constraint-scaffold`; do **not** add a sibling skill

Measured this session: the cumulative skill-`description:` budget is **2366 / 2366 words — zero
headroom** (`plugins/soleur/test/components.test.ts:16`, `SKILL_DESCRIPTION_WORD_BUDGET = 2366`).
Every prior new skill required an explicit budget bump against a zero-headroom baseline. Extending
`constraint-scaffold` costs **zero** description words and is the better fit anyway: the emitted
artifact set, the shared runner, the fail-closed contract, and the ADR-074 auto-recovery
dispatcher are all reusable.

`constraint-scaffold`'s `description:` is **not** edited (it already reads generically enough:
*"generating the Layer 1 dependency-cruiser import-boundary gate … into a Next.js product
codebase's CI"*). If /work concludes the description must change to mention the second gate, it
must first re-measure and prescribe an exact sibling trim (`cq-skill-description-budget-headroom`).

### Decision D6 — The **exception ledger** is the SSOT, and it is what makes the gate non-vacuous

`scripts/encryption-posture-ledger.json` is the single machine-readable registry of every
persistent store and cross-component connection, its posture, its evidence citations, and — for
anything not encrypted or not cert-verified — a **named justification plus a tracking issue**.

This choice is load-bearing for two reasons beyond bookkeeping:

- **It replaces git-history scoping.** Per
  `2026-07-20-git-diff-scoped-lint-rules-go-vacuous-in-ci-and-on-merge.md`, a lint that scopes its
  accepted population to "lines added since `merge-base`" goes silent on a `fetch-depth: 1` checkout
  **and again after its own PR merges**. The ledger is a committed artifact, so the repo-sweep mode
  never goes vacuous. The `--diff` mode exists only for preflight's presentation layer and is never
  the sole enforcement path.
- **It is the join the incident lacked.** The legal docs claimed LUKS; the volume was ext4; nothing
  joined them. The ledger is that join, and Layer B is what keeps it honest.

**There is no silencing mechanism.** No `# noqa`, no `--skip`, no `SKIP_*` env var, no allowlist
file. The only way past the gate is a ledger row with `mechanism: plaintext-exception` (or
`cert_verification: off`) carrying `justification`, `accepted_by`, `tracking_issue` (`^#[0-9]+$`),
and `reevaluate_when`. This is tested behaviourally (see TS-6), not by grepping the script for the
absence of a flag — a literal-absence grep is a vacuous sweep for a semantic property
(`2026-07-22-acceptance-grep-of-a-literal-string-is-a-vacuous-sweep-for-a-semantic-property.md`).

### Decision D7 — The gate is a **required check**, not advisory

`scripts/lint-trap-tempfile-ownership.py` is deliberately advisory (ADR-129) and says so in its own
docstring. This gate is **not**: at a `single-user incident` brand-survival threshold, *an advisory
gate is not a weak gate, it is no gate*
(`2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`).
Promotion requires **three** coupled edits in the same PR: the `ci.yml` job, `scripts/required-checks.txt`,
and `infra/github/ruleset-ci-required.tf`. All three are in `## Files to Edit`; an AC asserts the
three-way coupling.

### Decision D8 — ~~Layer B stays a GitHub Actions cron, with the ADR-033 exemption argued and the hook override declared~~ **SUPERSEDED by R2**

> **⚠ THIS DECISION IS DELETED. See R2 in the BINDING revisions block above.** The circularity
> argument was unsound (a plaintext AOF does not crash Inngest; correlation ≈ 0). ADR-033's own scope
> note names `scheduled-terraform-drift` as the *correct* shape for a credential-heavy infra cron and
> warns against mis-citing it as a blanket ban. Layer B adopts the **Inngest-dispatch hybrid**
> (`cron-encryption-posture-reconcile.ts` schedules → `scheduled-encryption-posture-reconcile.yml`
> with `on: workflow_dispatch:` only). The `prefer-inngest` hook never fires, so the override marker,
> the in-file justification block, and **AC32 are all deleted.** The text below is retained only for
> provenance; do NOT implement it.

*(Added by deepen-plan Phase 4.4 — Scheduled-work pattern check.)*

Measured this session: **53** Inngest cron functions (`apps/web-platform/server/inngest/functions/cron-*.ts`) vs **10** `.github/workflows/scheduled-*.yml`. Inngest is the canonical path (ADR-033), and
`.claude/hooks/new-scheduled-cron-prefer-inngest.sh` is a **PreToolUse hook that will DENY** the
Write of a new `scheduled-*.yml` containing a `schedule:`/`cron:` directive. `/work` **will** hit
this. It is decided here rather than left to be discovered and silently overridden.

The gate's two-part exemption test, answered:

- **(a) Is the work purely git/repo-scoped — no app context, no app secrets, no Sentry integration?**
  Yes. Layer B reads the committed ledger, calls provider APIs (Hetzner, Cloudflare, Supabase) and
  the Better Stack Logs API using **infra** credentials from Doppler `prd_terraform`. It uses no app
  secret, no app database session, and no Sentry DSN. Its siblings are
  `scheduled-followthrough-sweeper.yml` and the infra-drift cron, not the app crons.
- **(b) Could it benefit from `step.run` memoization / Inngest replay?** No — and it would be
  actively harmful. A security verdict must be computed whole from current state; a partially
  replayed sweep would report a stale-mixed posture that is neither the old nor the new truth,
  which is the "clean verdict is byte-identical to inspected-nothing" failure the positive-work
  floor exists to prevent.

**The decisive third argument (circularity).** Inngest's durable queue and run-state live on the AOF
at `hcloud_volume.inngest_redis` — a store this very audit covers and which the code enumeration
suggests is plaintext. Hosting the encryption-posture verifier on the substrate it audits means the
verifier goes dark exactly when that substrate is the problem, and cannot run at all when the app is
down. An infra-integrity gate must not depend on the infra it certifies.

**Implementation obligation:** the emitted workflow carries the hook's documented override hatch —
the literal HTML comment `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` near the top of
the YAML — **plus** a comment block restating this three-part justification in the file itself, so a
future reader sees the reasoning at the override site and not only in this plan. Using the hatch
without the in-file justification is a review-blocking defect.

## The `## Encryption Posture` section schema

Mirrors the `## Observability` / `## User-Brand Impact` conventions in
`plugins/soleur/skills/plan/references/plan-issue-templates.md` (fenced YAML, one block, no prose
substitutes). Added to all three detail levels (MINIMAL / MORE / A LOT).

```yaml
at_rest:
  - store:            # resource address or logical name (hcloud_volume.x / cloudflare_r2_bucket.y / supabase.public.z)
    mechanism:        # luks | provider-managed:<named attestation> | app-layer-envelope:<scheme> | plaintext-exception
    evidence:         # mechanically-resolvable citation — file:anchor for LUKS apparatus,
                      # attestation name + URL + retrieval date for provider-managed,
                      # code anchor for an envelope scheme. NEVER "the provider handles it".
    defends_against:  # concretely: what this stops (e.g. "a seized or RMA'd disk; a raw volume snapshot")
    does_not_defend:  # concretely: what it does NOT stop — REQUIRED, see below

in_transit:
  - connection:        # from -> to (e.g. "web-platform server -> Supabase Postgres")
    enforced_at:       # file:anchor of the CONNECTING code that sets the requirement
    tls:               # scheme + minimum version
    cert_verification: # on | off — plus the anchor proving it (sslmode=verify-full / default rejectUnauthorized)
    does_not_defend:   #

exception:            # present ONLY when mechanism is plaintext-exception OR cert_verification is off
  justification:      # named, one sentence, WHY this is accepted
  accepted_by:        # named human or role
  tracking_issue:     # #N — REQUIRED. Never silence.
  reevaluate_when:    # the concrete condition that reopens the decision
```

**`does_not_defend` is mandatory and is the point.** Disk/volume-layer encryption on a managed
provider defends against physical media compromise. It does **not** defend against a leaked
service-role credential, an RLS bypass, an SSRF that reaches the store, or a compromised host on
which the volume is already unlocked. Left unstated, "encrypted at rest" becomes a false assurance
— which is how a legal document ends up over-claiming in the first place. The gate rejects
`does_not_defend` values that are empty, `none`, `n/a`, or that merely restate `defends_against`.

## Detection triggers

`plan` §2.11 fires when the plan introduces **either**:

- **A persistent data store** — volume, database, bucket, object store, queue, cache, backup target,
  or log sink. Detected on `## Files to Create` / `## Files to Edit` matching
  `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`,
  **or** on the plan prose naming a store class from the ledger schema's `store_classes` table.
- **A cross-component or network connection** — a new client construction, a new outbound host, a
  new webhook target, a new log/metrics sink, or a new inter-host link.

Skip silently only when neither fires (a pure UI/copy change, a docs-only plan, a dependency bump).

## User-Brand Impact

- **If this lands broken, the user experiences:** their source code sitting unencrypted on a
  Soleur-provisioned block volume while `docs/legal/privacy-policy.md` (published, and rendered on
  soleur.ai) tells them it is LUKS-encrypted — the exact `#6588` state, reproduced for the next
  user instead of prevented. A second, subtler break: a *false green* — the gate passes on a
  declaration that no live probe ever contradicted, which is strictly worse than no gate because it
  stops anyone looking.
- **If this leaks, the user's data is exposed via:** an unencrypted Hetzner block volume in an RMA /
  decommission / snapshot path; a plaintext Redis AOF containing in-flight job payloads
  (`hcloud_volume.inngest_redis`); or a `sslmode=require` Postgres connection terminated by an
  attacker-presented certificate on a hostile network segment.
- **Brand-survival threshold:** `single-user incident`

  A single user's private source code becoming readable is a single-user incident and, because the
  privacy policy makes an explicit contrary claim, simultaneously a legal-disclosure incident.
  Per plan §2.6 this sets `requires_cpo_signoff: true`, escalates `/plan-review` to the 5-agent
  panel (+`architecture-strategist` +`spec-flow-analyzer`), and requires `user-impact-reviewer` at
  review time.

## Observability

```yaml
liveness_signal:
  what:            "scheduled-encryption-posture-reconcile.yml — Layer B ledger-vs-reality reconciliation; emits a Better Stack heartbeat on a clean reconcile"
  cadence:         "daily at 06:00 UTC (aligned with the existing infra-drift cron window)"
  alert_target:    "operator email via Better Stack heartbeat miss + an auto-filed GitHub issue labelled type/security,priority/p1-high on any divergence"
  configured_in:   ".github/workflows/scheduled-encryption-posture-reconcile.yml + apps/web-platform/infra/uptime-alerts.tf (the betteruptime_* heartbeat root — verified this session as the file carrying the existing beats; ADR-117 measure-then-arm gate)"

error_reporting:
  destination:     "GitHub Actions job annotations (::error::) + an auto-filed issue; the Better Stack heartbeat is the absence detector for the workflow itself failing to run"
  fail_loud:       "the workflow exits non-zero and no heartbeat is sent, so a silently-dead reconcile pages the same way a divergence does"

failure_modes:
  - mode:          "ledger says luks, the live volume is plaintext (the #6588 class)"
    detection:     "Layer B pulls the host's actual mapper state from the EXISTING automated verify surface (luks-monitor.sh self-report to the Better Stack Logs source, source 2457081) and diffs it against the ledger row — no SSH, no dashboard"
    alert_route:   "auto-filed issue type/security + priority/p1-high, cross-linked Ref #6588"
  - mode:          "a new *.tf storage resource merges with no ledger row"
    detection:     "Layer A repo-sweep in ci.yml — a required check; unknown resource type is fail-closed"
    alert_route:   "the PR cannot merge"
  - mode:          "a ledger row cites LUKS apparatus that was later deleted or renamed (citation rot)"
    detection:     "Layer A resolves every citation each run; an unresolvable anchor FAILs. This is the mechanism that stops the ledger degrading into prose."
    alert_route:   "the PR cannot merge"
  - mode:          "an accepted plaintext exception's tracking issue is closed with the exception still live"
    detection:     "Layer B --live queries each exception's tracking_issue via gh api and FAILs on state==CLOSED"
    alert_route:   "auto-filed issue; the exception must be renewed or the store encrypted"
  - mode:          "Layer B itself goes vacuous (probe returns a degraded 200, empty log query, or an unset credential)"
    detection:     "the reconcile script requires a positive-work floor — it must have inspected >= the ledger's declared store count — and treats every could-not-measure outcome as its own ABORTING class evaluated BEFORE the comparison (per 2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md and 2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md)"
    alert_route:   "workflow exits non-zero, heartbeat missed, operator paged"

logs:
  where:           "GitHub Actions run logs for both layers; the Better Stack Logs source (2457081) for the host-side self-reports Layer B reads"
  retention:       "90 days (GH Actions default) / Better Stack Logs source retention"

discoverability_test:
  command:         "python3 scripts/lint-encryption-posture.py --repo-sweep --report && bash tests/scripts/lib/encryption-posture-reconcile.sh --audit"
  expected_output: "'encryption-posture: N stores, M connections, 0 unledgered, 0 unresolvable citations, K accepted exceptions (all with open tracking issues). PASS' followed by the static parity table with no DIVERGENT rows."
```

### Soak follow-through enrollment

Layer B's arming is a post-deploy, time-gated criterion: the reconcile workflow must have fired
**green at least 3 consecutive days** post-merge before its Better Stack heartbeat is armed (the
ADR-117 measure-then-arm pattern — arming an unfed beat produces a dead probe, exactly `#6808`).

- **Script:** `scripts/followthroughs/encryption-posture-reconcile-soak-<issue>.sh` — exit 0 only
  when ≥3 consecutive successful runs exist with `start=` pinned strictly after the deploy SHA.
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/encryption-posture-reconcile-soak-<issue>.sh earliest=<deploy+3d> secrets=BETTERSTACK_API_TOKEN -->` plus the `follow-through` label.
- **Sweeper wiring:** add `BETTERSTACK_API_TOKEN` to `.github/workflows/scheduled-followthrough-sweeper.yml` `secrets=` if not already present.

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `infra/github/ruleset-ci-required.tf` | Add a `required_check { context = "encryption-posture" }` block for the new `ci.yml` job (D7). |
| `apps/web-platform/infra/uptime-alerts.tf` | Add the Layer B heartbeat resource, **count-gated behind the ADR-117 measure-then-arm gate** — never armed at create time. (Path verified this session: `grep -rln 'betteruptime_' --include=*.tf apps/` → `inngest.tf`, `dns.tf`, `uptime-alerts.tf`, `alerts-github-webhook.tf`, `web-probe.tf`; `uptime-alerts.tf` is the heartbeat/monitor root.) |

No new provider, no new no-default variable, no new secret. `BETTERSTACK_API_TOKEN` already exists.
**No `hr-tf-variable-no-operator-mint-default` exposure** — nothing here requires an operator mint.

### Apply path

(b) cloud-init + idempotent bootstrap — **not applicable**; no host config changes. The GitHub
ruleset change applies through the existing `apply-github-infra` path; the Better Stack heartbeat
applies through `apply-web-platform-infra.yml` under its `-target=` allow-list. **Blast radius:
zero downtime**, both are pure `+create` on additive resources.

### Distinctness / drift safeguards

- The ruleset resource already carries the `#6103`-class "a job rename silently un-requires the
  check" warning in its header. The new `required_check` context string must exactly equal the
  `ci.yml` job name; an AC asserts the pair.
- The heartbeat carries `lifecycle { ignore_changes = [paused] }` consistent with the ADR-117 gate,
  so the automated arm PATCH is not reverted by the next apply.
- Per `hr-verify-repo-capability-claim-before-assert` and the ADR-130 pre-apply probe: the
  `betteruptime_*` and `github_repository_ruleset` surfaces are **already exercised** by this repo's
  credentials (both resource families exist in state), so no new API surface is introduced and no
  new scope probe is required. **This is stated as a verified claim, not an assumption** — /work
  must re-confirm with `git grep -n 'betteruptime_\|required_check' -- '*.tf'` before apply.

### Vendor-tier reality check

Better Stack heartbeats are on the existing paid tier (the repo already runs apex, inngest,
registry-disk, and per-host web beats). No new tier gate needed.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-140 — "Encryption posture is a design-time default, enforced by a resolvable-evidence
ledger."** (Provisional ordinal — 138 is the current maximum; `/ship`'s ADR-Ordinal Collision Gate
re-verifies against `origin/main`. **If renumbered, sweep `grep -rn 'ADR-140' knowledge-base/project/{plans,specs}/feat-one-shot-encryption-at-rest-in-transit-design-default/` in the same edit** — a renumber that misses the plan/tasks/ACs leaves an AC verifying a nonexistent file.)

The Decision records: the three-layer model; that a declaration-only gate is rejected because it
reproduces `#6588`; that evidence must be mechanically resolvable rather than asserted; that the
exception path is a ledger row with a tracking issue and never a suppression comment; and — in
`## Alternatives Considered` — the rejected `AGENTS.md` hard-rule placement with the two measured
reasons (D4).

### C4 views

**All three model files were read in full this session** (`model.c4` 558 L, `views.c4` 62 L,
`spec.c4` 54 L) — not grepped for the feature's own noun. Enumeration:

- **(a) External human actors:** none new. `founder`, `emailSender`, `betaContact`, `contributor`
  are already modelled; this change adds no correspondent, reviewer, or recipient.
- **(b) External systems / vendors:** none new. Hetzner (`platform.infra.hetzner`), Cloudflare
  (`cloudflare`, incl. R2), Supabase (`platform.infra.supabase`, `inngestPostgres`), Doppler
  (`doppler`), Better Stack (`betterstack`), zot (`zotRegistry`) are all present.
- **(c) Containers / data stores touched:** `workspacesVolume`, `inngestRedis`, `gitDataStore`,
  `sessionStore`, `supabase`, `inngestPostgres`, `zotRegistry`. **Two gaps found:**
  - `platform.infra.workspacesVolume`'s description is now **falsified** — it states *"PLAINTEXT AT
    REST as of 2026-07-21 while the published privacy policy claims LUKS"* and *"the current mount
    source is the raw /dev/sdb"*. The 2026-07-23 cutover certified `/dev/mapper/workspaces`
    (verify run 30040444418: `ready=true`, `workspace_count=8 expected=8`). **This is a
    correctness edit in scope**, and the corrected description must cite the verify run ID — the
    posture is stated *because a mechanical run measured it*, never because the cutover was
    believed to have worked. (This distinction is the whole feature.)
  - `workspacesVolume` is **modelled but not included in the `containers` view** (`views.c4`'s
    include list carries `gitDataStore` and `sessionStore` but not `workspacesVolume`) — so the
    repo's most sensitive store does not render. **In scope:** add the `include` line.
- **(d) Access relationships:** no ownership/tenancy boundary change.

**Task:** edit `model.c4` (correct `workspacesVolume`; add an at-rest posture clause to
`inngestRedis`, `gitDataStore`, `sessionStore`, `zotRegistry` descriptions **sourced from the audit's
automated pull, not from assumption**) and `views.c4` (`include platform.infra.workspacesVolume`).
Then run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` — an `include` naming
an undefined element fails there, not at `tsc`.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| **An `AGENTS.md` `hr-*` hard rule** (no id — the rule is not created) | Two measured blockers: `B_ALWAYS = 22900/23000` leaves ≈40 bytes after the pointer, and the rule's trigger spans `infra` + `docs-only` loader classes so it would need `core`, which has zero room. In `rest` it would be a **silent no-op on its own docs-only trigger**. (D4) |
| **Layer B as an Inngest cron function** (the ADR-033 canonical path) | Rejected with an explicit two-part exemption test — see **D8**. The decisive argument is circularity: an encryption-posture verifier running on the Inngest substrate depends on `hcloud_volume.inngest_redis`, one of the very stores it audits, and cannot run when the app is down. |
| **A declaration-only gate (plan + deepen-plan + a ledger, no live probe)** | Reproduces `#6588` exactly: the legal docs *declared* LUKS while the volume was ext4. Explicitly rejected by the design principle. Layer B is mandatory. |
| **An attribute-presence detector (`encrypted = true`)** | Structurally impossible for the stack in use — `hcloud_volume` has no `encrypted` attribute (`workspaces-luks.tf` §SHARP EDGE). Would be unpassable, or satisfiable by a comment. (D2) |
| **A new sibling skill (`encryption-scaffold`)** | Skill-description budget is **2366/2366, zero headroom**. Extending `constraint-scaffold` costs zero words and reuses the runner, the fail-closed contract, and the ADR-074 recovery dispatcher. (D5) |
| **`git merge-base`-scoped lint (new-entrants only, the ADR-129 ratchet)** | Goes vacuous on `fetch-depth: 1` **and again after its own PR merges** (`2026-07-20-git-diff-scoped-lint-rules-go-vacuous-in-ci-and-on-merge.md`). The committed ledger provides the same "don't re-litigate accepted debt" property without the history dependency. (D6) |
| **Advisory (non-required) CI job, like `lint-trap-tempfile-ownership`** | At `single-user incident` threshold an advisory gate is no gate. Promoted to required in the same PR via the three coupled edits. (D7) |
| **Remediating the audit findings in this PR** | Explicitly out of scope. Encrypting `hcloud_volume.inngest_redis` or the registry store is a cutover with its own freeze/blast-radius analysis. Findings become separate tracked issues. |

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-measure both budgets and pin the outputs in the PR body:
`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1`
(the `2>&1` is load-bearing — WARN/REJECT print to stderr) and the components test.
0.2 Confirm `gated-skills.json` still excludes `plan`/`review`/`preflight`.
0.3 `grep -n '^### Check ' plugins/soleur/skills/preflight/SKILL.md | tail -1` → confirm max is 11, so the new check is **12**. Same for `deepen-plan` (max 4.9 → new is **4.10**) and `plan` (max 2.10 → new is **2.11**). Never assume a number.
0.4 `python3 -c "import yaml"` → confirmed available; the ledger is nonetheless **JSON** (stdlib-only, no dependency).
0.5 Verify every path in `## Files to Edit` exists (`ls`), and every `knowledge-base/` citation in this plan resolves:
`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'`.

### Phase 1 — Ledger schema + the audit (RED-first, read-only)

1.1 Author `scripts/encryption-posture-ledger.schema.json` — the `store_classes` extension table
    (D2) and the row schema (`at_rest` / `in_transit` / `exception`).
1.2 **Run the one-time audit** (deliverable 8) — read-only, automated sources only, **no dashboard
    eyeball, no SSH** (`hr-no-dashboard-eyeball-pull-data-yourself`, `hr-no-ssh-fallback-in-runbooks`).
    Sources: `terraform show -json` / `terraform state list` against the R2-backed state;
    `git grep` over `*.tf` + connection code; the Cloudflare / Hetzner / Supabase provider APIs;
    the Better Stack Logs source for host self-reports; the `workspaces-luks-verify` workflow's
    recorded run output. Write `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`.
1.3 Seed `scripts/encryption-posture-ledger.json` **from the audit's measured output** — every row's
    posture is what was *measured*, never what was expected. Rows that measure plaintext get
    `mechanism: plaintext-exception` with a real `tracking_issue` (filed in 1.4). **No remediation.**
1.4 File one issue per non-conforming finding (`type/security`, `domain/engineering`, priority per
    sensitivity), `Ref #6588` where in scope — **never `Closes`**.

### Phase 2 — Layer A detector (RED → GREEN, `cq-write-failing-tests-before`)

2.1 Write `scripts/lint-encryption-posture.test.sh` **first**, RED. Fixture matrix in `## Test Scenarios`.
2.2 Implement `scripts/lint-encryption-posture.py` — modes `--repo-sweep` (default), `--diff <pathfile>`,
    `--report`. Fail-closed on every indeterminate outcome. No bypass flag, no env escape.
2.3 Register `scripts/lint-encryption-posture.test.sh` in `scripts/test-all.sh` (required by
    `scripts/lint-orphan-test-suites.sh`).
2.4 **Mutation battery** (see `## Test Scenarios` MB-1..MB-7). Each mutation must red the suite.
    Per `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`, the battery is enumerated
    from the *contract* (one mutation per accept/reject branch), not from what feels likely.

### Phase 3 — Wire Layer A as a required check (D7 — three coupled edits, one commit)

3.1 `.github/workflows/ci.yml` — new `encryption-posture` job, `fetch-depth: 0` **not required**
    (repo-sweep mode has no history dependency — this is the point of D6, and an AC asserts it by
    running the sweep under a simulated shallow checkout).
3.2 `scripts/required-checks.txt` — add `encryption-posture`. **Read the file's AUTO-FABRICATION
    GUARD header first (#6049):** it derives synthetic check-run names, so a *content-scoped* gate
    added here fabricates a green result for bot PRs unless reproduced in the composite action's
    preflight. This gate **is** content-scoped ⇒ it must either be reproduced in
    `.github/actions/bot-pr-with-synthetic-checks/action.yml` Phase-4 **or** excluded from synthesis
    via a non-15368 `integration_id`. **/work must adjudicate this explicitly and record which arm
    it took** — silently adding the name is the failure mode the header exists to prevent.
3.3 `infra/github/ruleset-ci-required.tf` — add the `required_check` block; context string must
    exactly equal the `ci.yml` job name.

### Phase 4 — Layer B live reconciliation

4.1 `tests/scripts/lib/encryption-posture-reconcile.sh` — modes `--audit` (static parity table, no
    credentials) and `--live` (provider APIs + Better Stack Logs). Modelled on
    `tests/scripts/lib/preapply-entrypoint-gate.sh` (ADR-136): default-deny, one fail-closed
    catch-all for every ambiguity, a **control probe** on a known-good target to distinguish
    "credential broken" from "target genuinely absent", and a **positive-work floor** so a clean
    verdict is not byte-identical to "inspected nothing".
4.2 `tests/scripts/test-encryption-posture-reconcile.sh` + register in `scripts/test-all.sh`.
4.3 `.github/workflows/scheduled-encryption-posture-reconcile.yml` — daily; auto-files an issue on
    divergence; emits the heartbeat only on a positive-work clean pass.
4.4 Better Stack heartbeat in Terraform, **count-gated behind the ADR-117 measure-then-arm gate**.
4.5 Follow-through enrollment script + tracker directive (see `## Observability`).

### Phase 5 — Design-time gates (deliverables 1, 2, 4)

5.1 `plugins/soleur/skills/plan/references/plan-issue-templates.md` — add `## Encryption Posture`
    to MINIMAL / MORE / A LOT, placed immediately after `## Observability` in each.
5.2 `plugins/soleur/skills/plan/SKILL.md` — new **§2.11 Encryption Posture Gate** (triggers above),
    placed after §2.10, mirroring §2.9's shape.
5.3 `plugins/soleur/skills/deepen-plan/SKILL.md` — new **§4.10 Encryption Posture Halt (Conditional)**,
    mirroring §4.7's four-step shape (locate → validate fields → telemetry → pass-through). Rejects:
    section absent while trigger fires; any required field empty or matching
    `^\s*<field>:\s*(TODO|TBD|N/A|placeholder)\s*$`; `mechanism` matching the boilerplate ban-list
    (`provider handles`, `handled by the provider`, `encrypted by default` with no attestation name,
    `supports TLS`); `does_not_defend` empty / `none` / `n/a` / a restatement of `defends_against`;
    an `exception` block missing `tracking_issue`.
5.4 `plugins/soleur/skills/preflight/SKILL.md` — **Check 12: Encryption Posture**; add its row to
    the §0.1 fast-path SKIP table. Shells out to the Layer A script. Result contract:
    **PASS** clean sweep; **FAIL** any unledgered store, unresolvable citation, banned in-transit
    token, or exception without a tracking issue; **SKIP** *only* when the cached path-set contains
    zero store-class and zero connection-class paths — i.e. "I do not apply", never "I cannot
    prove it" (`2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`).
5.5 `plugins/soleur/skills/review/SKILL.md` — add the defect-class entry (deliverable 4) to
    `### Defect Classes This Review Reliably Catches`, and a conditional `security-sentinel` spawn
    instruction when the diff touches a store/connection surface. The catalogue entry names the
    *reviewer takeaway* in the established form: for any new persistent store or cross-component
    connection, the spawn prompt MUST instruct an agent to state (a) the concrete at-rest mechanism
    and where its evidence resolves, (b) whether cert verification is provably on at the connecting
    code — checking specifically for `sslmode=require`, which encrypts without verifying — and
    (c) what the mechanism does **not** defend against.

### Phase 6 — Generation-side defaults (deliverables 5, 6)

6.1 `plugins/soleur/agents/engineering/infra/terraform-architect.md` — the existing guidance is
    **AWS-shaped** (`storage_encrypted = true` on RDS, `encrypted = true` on EBS) and does not
    cover the providers actually in use. Add a Hetzner/Cloudflare section: there is no
    `hcloud_volume` encryption attribute, so an encrypted volume means the guest-side LUKS
    apparatus (`random_password` → `doppler_secret` → `cryptsetup luksFormat` in cloud-init →
    `/dev/mapper/*` mount), with the **live-volume guard-inversion trap** called out verbatim
    (`if ! cryptsetup isLuks "$DEV"; then luksFormat` is false on a populated plaintext device and
    **wipes live data** — `workspaces-luks.tf` §"THE ISSUE'S PREMISE WAS WRONG"). Generate encrypted
    by default; require a named justification otherwise.
6.2 `plugins/soleur/agents/engineering/infra/platform-strategist.md` — add encryption posture to the
    Decision Framework as a first-class axis alongside Reproducibility First, so the *strategy* step
    forces the choice before terraform-architect is asked for HCL.
6.3 `provision-hetzner` / `provision-cloudflare` / `provision-doppler` / `provision-github`
    `SKILL.md` — each gains an "Encryption posture" step: emit the ledger row for anything
    provisioned, and refuse to complete without one.
6.4 **`constraint-scaffold` extension (deliverable 6 — highest leverage).** Add
    `references/encryption-posture-gate.template` (the emitted CI workflow) +
    `references/encryption-posture-scan.template` (the emitted scanner) and teach
    `scripts/constraint-scaffold.sh` to emit them alongside the Layer-1 boundary gate. The emitted
    gate is the **portable subset** — it does not assume Hetzner or a ledger; it scans the target
    codebase's IaC + connection code for the D3 ban-list and for storage resources lacking an
    encryption declaration, and fails closed. It inherits `constraint-scaffold`'s existing
    **agent-owns-gates recovery model**: the founder never edits it, and the ADR-074 two-stage
    dispatcher auto-opens a fix PR. Add `test/encryption-posture.test.sh` proving non-vacuity
    (a plaintext bucket FAILs, an encrypted one PASSes, a `rejectUnauthorized: false` FAILs) and
    extend `test/parity.test.sh` to cover the new templates.

### Phase 7 — ADR, C4, docs

7.1 Write ADR-140.
7.2 C4 edits per `### C4 views`; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
7.3 Record the design-time-default principle in `knowledge-base/project/constitution.md`
    (the placement D4 chose in lieu of an AGENTS rule).
7.4 Run `/soleur:gdpr-gate` inline against the plan + diff (plan §2.7 trigger (b) fires:
    `single-user incident` threshold). Per `wg-plan-prescribed-skills-must-run-inline`, this runs
    **in-session at /work**, not deferred.

## Acceptance Criteria

### Pre-merge (PR)

**Design-time gates**

- [ ] AC1 — `## Encryption Posture` exists in all three templates in `plan-issue-templates.md`, each with the full `at_rest` / `in_transit` / `exception` schema. Verify: `grep -c '^## Encryption Posture' plugins/soleur/skills/plan/references/plan-issue-templates.md` == `3`.
- [ ] AC2 — `plan/SKILL.md` contains a `### 2.11.` heading whose body names both trigger classes (persistent store, cross-component connection) and the skip condition.
- [ ] AC3 — `deepen-plan/SKILL.md` contains a `### 4.10.` heading with all four steps (locate / validate / telemetry / pass-through) and an explicit reject list including the boilerplate ban-list and the `does_not_defend` restatement reject.
- [ ] AC4 — `deepen-plan` §4.10 is **behaviourally** verified, not grep-verified: run it against three fixture plans — (i) compliant, (ii) `mechanism: "the provider handles it"`, (iii) `exception` with no `tracking_issue` — and confirm (i) passes and (ii)+(iii) halt with the specific field named.
- [ ] AC5 — `preflight/SKILL.md` has `### Check 12: Encryption Posture` **and** a matching row in the §0.1 fast-path SKIP table. Verify both: `grep -c '### Check 12' …` == 1 and `grep -c '| 12 (Encryption posture)' …` == 1.

**Layer A (load-bearing)**

- [ ] AC6 — `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 on `main` state after Phase 1 seeds the ledger, and reports a non-zero store count (a positive-work floor — a clean verdict must not be byte-identical to "inspected nothing").
- [ ] AC7 — Adding a synthetic `hcloud_volume` / `cloudflare_r2_bucket` / new-unknown-type storage resource to a fixture tree with no ledger row makes the sweep exit **non-zero** in all three cases (the unknown type is fail-closed).
- [ ] AC8 — The mutation battery MB-1..MB-7 (below) is green: **every** mutation reds the suite. A mutation whose removal leaves the suite green is a finding, not a pass.
- [ ] AC9 — **Non-vacuity under a shallow checkout.** Run the sweep in a `git clone --depth 1` of the branch; it must produce the *same* verdict and store count as the full clone. (Directly tests the D6 property.)
- [ ] AC10 — **No bypass exists.** Behavioural matrix: for a known-bad fixture, the sweep exits non-zero under every combination of `{no env, SKIP_ENCRYPTION_POSTURE=1, CI=false, --report}` and under a `# noqa`-style comment on the offending line. (Behaviour, not a literal-absence grep.)
- [ ] AC11 — **`sslmode=require` is rejected.** A fixture connection string using `sslmode=require` FAILs; `sslmode=verify-full` PASSes. (The "encrypts but does not verify" trap.)
- [ ] AC12 — **Citation rot is caught.** Deleting the `cryptsetup luksFormat` site that a `mechanism: luks` row cites makes the sweep exit non-zero with the unresolvable anchor named.

**Required-check promotion (three coupled edits)**

- [ ] AC13 — The `ci.yml` job name, the `scripts/required-checks.txt` entry, and the `infra/github/ruleset-ci-required.tf` `required_check.context` are byte-identical. Verify by extracting all three and asserting equality — not by eyeballing.
- [ ] AC14 — The `#6049` auto-fabrication adjudication is recorded in the PR body: which arm was taken (reproduce in the composite action's Phase-4 preflight, **or** exclude via a non-15368 `integration_id`), with the diff that implements it.

**Layer B**

- [ ] AC15 — `bash tests/scripts/lib/encryption-posture-reconcile.sh --audit` prints the static parity table with zero DIVERGENT rows against the Phase-1 ledger.
- [ ] AC16 — Layer B's could-not-measure path is its own **aborting** class evaluated **before** the comparison: fixtures for (empty credential, HTTP 000, degraded-200-with-empty-body, log query returning zero rows) each exit non-zero and are **distinguishable in the output** from a clean pass.
- [ ] AC17 — The Better Stack heartbeat resource is `count`-gated behind the ADR-117 measure-then-arm gate — `terraform plan` shows **no create** of an armed beat.

**Generation side**

- [ ] AC18 — `terraform-architect.md` states that `hcloud_volume` has no encryption attribute, names the four-part guest-side LUKS apparatus, and reproduces the live-volume guard-inversion data-loss trap.
- [ ] AC19 — All four `provision-*/SKILL.md` files contain an "Encryption posture" step. Verify: `grep -l 'Encryption posture' plugins/soleur/skills/provision-*/SKILL.md | wc -l` == `4`. (`-l` and `-c` are mutually exclusive in GNU grep — use `-l` alone and count lines.)
- [ ] AC20 — `constraint-scaffold.sh` emits both new templates into a fixture Next.js tree; `test/encryption-posture.test.sh` proves non-vacuity (plaintext bucket FAILs, encrypted PASSes, `rejectUnauthorized: false` FAILs); `test/parity.test.sh` covers the new templates.
- [ ] AC21 — `constraint-scaffold`'s `description:` is **unchanged**, OR — if changed — the PR body pins the re-measured budget and the exact sibling trim (`cq-skill-description-budget-headroom`).

**Review + audit**

- [ ] AC22 — `review/SKILL.md` `### Defect Classes This Review Reliably Catches` gains an entry naming the defect and the three-part reviewer takeaway (mechanism+evidence / cert-verification incl. `sslmode=require` / `does_not_defend`).
- [ ] AC23 — `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md` exists, covers **every** store and connection enumerated in `## One-Time Audit`, and each row's posture cites its automated source (terraform state / provider API / code anchor / Better Stack log query). **Zero rows sourced from a dashboard or an SSH session.**
- [ ] AC24 — Every non-conforming audit finding has a filed issue; the PR body lists them as `Ref #N`. **The PR body contains no `Closes` line for `#6588`** (verify: `gh pr view --json body --jq .body | grep -c 'Closes #6588'` == `0`).
- [ ] AC25 — **This PR remediates nothing.** No `*.tf` change alters the encryption posture of any existing store. Verify: `git diff origin/main...HEAD -- '*.tf'` contains no `cryptsetup`, no `random_password` for a LUKS key, and no change to any existing `hcloud_volume` body.

**Budget + hygiene**

- [ ] AC26 — `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1` reports `B_ALWAYS` **unchanged at 22900** — no AGENTS pointer was added.
- [ ] AC27 — `bun test plugins/soleur/test/components.test.ts` passes; the cumulative description budget is unchanged at `2366/2366`.
- [ ] AC28 — `bash scripts/lint-orphan-test-suites.sh` passes (both new `.test.sh` suites registered in `scripts/test-all.sh`).
- [ ] AC29 — ADR-140 exists; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass; `model.c4`'s `workspacesVolume` description no longer asserts plaintext and cites verify run `30040444418`; `views.c4` includes `platform.infra.workspacesVolume`.
- [ ] AC30 — `bash scripts/test-all.sh` full-suite exit gate green.
- [ ] AC32 — **(D8)** `.github/workflows/scheduled-encryption-posture-reconcile.yml` contains **both** the literal override comment `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` **and** an in-file comment block restating the three-part ADR-033 exemption justification. The override without the justification is a review-blocking defect. Verify both with two separate greps against the workflow file.
- [ ] AC33 — The detector certifies the repo's two genuinely-encrypted volumes on day one: `python3 scripts/lint-encryption-posture.py --repo-sweep --report` reports `hcloud_volume.git_data_luks` and `hcloud_volume.workspaces_luks` as `mechanism: luks` with all citations resolved. A detector that cannot certify these two is miscalibrated regardless of how many synthetic fixtures pass.

### Post-merge (operator)

- [ ] AC31 — **Automated.** The follow-through sweeper runs `scripts/followthroughs/encryption-posture-reconcile-soak-<issue>.sh` from `earliest=<deploy+3d>`; on 3 consecutive green reconciles it arms the heartbeat via the ADR-117 PATCH. *No operator action.*

**Automation-feasibility audit:** every candidate operator step was checked against the loaded tool
surface and automated. Terraform applies route through the existing merge-triggered workflows;
issue filing through `gh`; provider state through APIs; the soak through the sweeper. **Zero
genuinely-operator-only steps.**

## Test Scenarios

### Layer A fixture matrix (RED targets)

| ID | Fixture | Expected |
|---|---|---|
| TS-1 | `hcloud_volume` + ledger row `mechanism: luks` + all 3 citations resolve, mapper names match | PASS |
| TS-2 | Same, but the `luksFormat` site is deleted | FAIL — unresolvable citation |
| TS-3 | Same, but the mapper name in the mount ≠ the mapper name in `luksOpen` | FAIL — citation mismatch |
| TS-4 | `cloudflare_r2_bucket` + `mechanism: "provider-managed: the provider handles it"` | FAIL — boilerplate ban-list |
| TS-5 | `cloudflare_r2_bucket` + `provider-managed:<named attestation>` + URL + retrieval date | PASS |
| TS-6 | `mechanism: plaintext-exception`, no `tracking_issue` | FAIL — exception without a tracked issue |
| TS-7 | `mechanism: plaintext-exception` + all four exception fields | PASS |
| TS-8 | New storage resource type absent from `store_classes` | FAIL — fail-closed on unknown type |
| TS-9 | Connection with `sslmode=verify-full` | PASS |
| TS-10 | Connection with `sslmode=require` | FAIL |
| TS-11 | `rejectUnauthorized: false` at a connection site | FAIL |
| TS-12 | `does_not_defend` restates `defends_against` verbatim | FAIL |
| TS-13 | Connection surface matching neither require- nor ban-list | FAIL — fail-closed on indeterminate |
| TS-14 | Zero store/connection paths in the diff (`--diff` mode) | SKIP |

### Mutation battery (AC8) — enumerated from the contract, one per accept/reject branch

| ID | Mutation | Must red |
|---|---|---|
| MB-1 | Delete the unledgered-store branch | TS-1 fixture set (a store with no row now passes) |
| MB-2 | Delete the citation-resolution step (accept the row's word) | TS-2, TS-3 |
| MB-3 | Delete the boilerplate ban-list | TS-4 |
| MB-4 | Delete the `tracking_issue` requirement | TS-6 |
| MB-5 | Change unknown-type handling from FAIL to SKIP | TS-8 |
| MB-6 | Remove `require` from the `sslmode` ban-list | TS-10 |
| MB-7 | Change the indeterminate-connection default from FAIL to PASS | TS-13 |

Per `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr…`: diff **per-case
verdicts** across the mutated and unmutated runs, never suite pass-counts, and pin the
classification string rather than only the exit code.

## One-Time Audit (deliverable 8) — enumerated scope

Enumerated this session from `*.tf` and connection code. Each row's **actual** posture is
determined at Phase 1.2 from automated sources; the "known from code" column is what the repo
already states and is the *hypothesis*, not the finding.

### Persistent stores

| Store | Declared at | Known from code (hypothesis) |
|---|---|---|
| `hcloud_volume.workspaces` (per-host `/workspaces`) | `apps/web-platform/infra/server.tf:1569` | `format = "ext4"`, no LUKS apparatus. Superseded on web-1 by `workspaces_luks`; the resource itself remains. |
| `hcloud_volume.workspaces_luks` | `apps/web-platform/infra/workspaces-luks.tf:184` | Guest-side LUKS (ADR-119). Cutover certified 2026-07-23, verify run 30040444418. |
| `hcloud_volume.git_data` | `apps/web-platform/infra/git-data.tf:196` | Plaintext — the pre-cutover rollback backstop, pending the DL-2 wipe. |
| `hcloud_volume.git_data_luks` | `apps/web-platform/infra/git-data-luks.tf:79` | Guest-side LUKS (ADR-068 3.D). |
| `hcloud_volume.inngest_redis` | `apps/web-platform/infra/inngest-host.tf:288` | **`format = "ext4"`, no LUKS apparatus.** Holds the Inngest queue + run-state AOF — in-flight job payloads. **Likely finding.** |
| `hcloud_volume.registry` | `apps/web-platform/infra/zot-registry.tf:407` | **`format = "ext4"`, no LUKS apparatus.** OCI blobs + cosign signatures. Lower sensitivity (a disposable GHCR mirror) but must be ledgered as an accepted exception, not omitted. |
| `cloudflare_r2_bucket.cla_evidence` | `apps/cla-evidence/infra/bucket.tf:1` | Provider-managed; object-lock apparatus present. Needs a **named attestation**. |
| `cloudflare_r2_bucket.workspaces_luks_header` | `apps/web-platform/infra/workspaces-luks-header.tf:40` | Provider-managed; holds LUKS header escrow. Needs a named attestation. |
| R2 Terraform-state backend | `apps/web-platform/infra/main.tf` backend block | Described in-repo as "R2-backed encrypted bucket" (`doppler-write-token.tf:23`, `ghcr-minter-doppler-token.tf:36`, `inngest-arm-write-token.tf:43`) — **an in-repo claim with no attestation, exactly the class this feature exists to catch.** |
| Supabase Postgres (`prd`) | `platform.infra.supabase` | Provider-managed. Needs attestation + project-ref resolution through `preflight` Check 4. |
| Supabase Postgres (Inngest) | `platform.infra.inngestPostgres` | Same. |
| Session Redis (`sessionStore`) | `model.c4:218` | Modelled as "TLS, requirepass, EU (Phase 4a)" — at-rest posture unstated. |
| Doppler (secrets at rest) | vendor | Provider-managed; needs attestation. |
| Better Stack Logs (source 2457081) | vendor | Log sink — in scope per the task's "log sink" clause. |

### Cross-component connections

| Connection | Enforced at (to verify) |
|---|---|
| web-platform → Supabase Postgres/PostgREST | `apps/web-platform/lib/supabase/{client,server,service,tenant}.ts` |
| web-platform → R2 / S3 | `apps/web-platform/server/providers.ts`, `apps/web-platform/scripts/bootstrap-live-verify.sh` |
| web-platform → Inngest Redis | `inngest-redis.conf` / the Inngest client |
| web hosts → zot registry (`10.0.1.30:5000`) | **Plain HTTP on the private net by design** — `model.c4:268` states integrity comes from cosign digest-pinning, not TLS. **This is a real `cert_verification: off` exception** and must carry a named justification + tracking issue rather than being silently omitted. |
| CI / hosts → Doppler | `doppler run` invocations |
| hosts → Better Stack (heartbeats + Logs) | `luks-monitor.sh`, the heartbeat curls |
| CF Tunnel ingress (deploy./ssh./registry.) | `apps/web-platform/infra/tunnel.tf` |
| web-platform → Anthropic / Stripe / Resend / Sentry | the respective SDK client constructions |

**Rules:** automated sources only — `terraform show -json`, `terraform state list`, provider APIs,
`git grep`, the Better Stack Logs query helper (`betterstack-query.sh`), and recorded workflow run
output. **No dashboard eyeball** (`hr-no-dashboard-eyeball-pull-data-yourself`). **No SSH**
(`hr-no-ssh-fallback-in-runbooks`). Findings → separate issues. **This PR remediates nothing** (AC25).

## Open Code-Review Overlap

Checked via `gh issue list --label code-review --state open` against every path in `## Files to Edit`.

- **#4133** — `follow-through(#4116): Schema parity test for ## Observability block` — touches
  `plan-issue-templates.md` and `deepen-plan/SKILL.md`, both of which this plan edits.
  **Disposition: acknowledge.** #4133 wants a mechanical parity test asserting that the
  `## Observability` schema in the template matches the fields `deepen-plan` §4.7 validates. This
  plan introduces the *same* coupling for `## Encryption Posture` (template ↔ §4.10), so the two
  are the same defect class. Folding in would require designing the generic parity harness, which is
  its own cycle and would grow an already-large PR at a `single-user incident` threshold.
  **Action:** post a note on #4133 recording that a second schema pair now exists, so whoever builds
  the harness covers both. #4133 remains open.
- No other overlaps. All other planned paths returned zero matches.

## Domain Review

**Domains relevant:** engineering, legal, operations

> **Execution note (recorded honestly, not papered over):** the `Task` tool was **not available**
> in this planning context, so domain-leader subagents (`cto`, `clo`, `coo`) could not be spawned.
> The assessments below were produced **in-orchestrator** from direct file reads. They are a
> weaker signal than a real domain-leader pass. `/plan-review` and `/deepen-plan` must run with
> agents available and their findings supersede these.

### Engineering (CTO)

**Status:** reviewed (in-orchestrator, subagent unavailable)
**Assessment:** The load-bearing risk is a *false-green* gate — the repo's own recent learning
corpus is dominated by exactly this class (`2026-07-20-i-fixed-three-unfailable-gates-and-shipped-eight-more`,
`2026-07-21-the-guard-i-shipped-could-never-have-fired-and-my-fake-certified-it`,
`2026-07-22-a-drift-guard-pr-fails-open-in-the-guard-not-the-guarded-code`). Three structural
mitigations are baked into the plan rather than left to review: the mutation battery enumerated
from the contract (MB-1..MB-7), the positive-work floor (AC6, AC16), and the shallow-checkout
non-vacuity test (AC9). The second risk is scope: this is a large PR touching 19 files. It is not
splittable along a safe seam — shipping the design gates without Layer A produces a
declaration-only gate (the rejected alternative), and shipping Layer A without the required-check
promotion produces an advisory gate (also rejected). The C4/ADR work is intrinsic per
`wg-architecture-decision-is-a-plan-deliverable`.

### Legal (CLO)

**Status:** reviewed (in-orchestrator, subagent unavailable)
**Assessment:** The incident being encoded against was, at root, a **published-disclosure
inaccuracy** — three legal documents asserted LUKS while the volume was ext4. The gate therefore
has a compliance dimension beyond engineering hygiene: the ledger is the artifact that lets the
privacy policy's encryption claims be *substantiated* rather than asserted. Two CLO-flavoured
requirements are folded into the plan: (a) `does_not_defend` is mandatory, so a posture cannot
become a false assurance in a data-protection disclosure; (b) the C4 description correction must
cite the verify run ID rather than the belief that the cutover worked — the same discipline the
legal docs lacked. **Not in scope for this PR:** re-auditing the published legal documents against
the audit's findings. That is a `/soleur:legal-audit` run and should be filed as its own issue
from the Phase 1.4 finding set.

### Operations (COO)

**Status:** reviewed (in-orchestrator, subagent unavailable)
**Assessment:** No new vendor, no new recurring expense (`wg-record-recurring-vendor-expense-before-ready`
does not fire — Better Stack heartbeats are on the existing paid tier and the repo already runs
6+ beats). Layer B adds one daily GitHub Actions run. The operational risk is the ADR-117 arming
gap: arming a heartbeat before a beat has been measured produces a dead probe — precisely the live
`#6808` defect (`WORKSPACES_LUKS_HEARTBEAT_URL` unwired after the web-1 cutover). AC17 + the
3-day soak follow-through are the mitigations.

### Product/UX Gate

**Not applicable.** The mechanical UI-surface override does not fire: no path in
`## Files to Create` / `## Files to Edit` matches `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`, and no UI-surface term appears. Product domain assessed **NONE** — this is an
infrastructure/tooling change with no user-facing surface. No wireframe required
(`wg-ui-feature-requires-pen-wireframe` does not fire).

## Files to Create

| Path | Role |
|---|---|
| `scripts/lint-encryption-posture.py` | Layer A detector (D1, D2, D3) |
| `scripts/lint-encryption-posture.test.sh` | TS-1..TS-14 + MB-1..MB-7 |
| `scripts/encryption-posture-ledger.json` | The SSOT ledger (D6) |
| `scripts/encryption-posture-ledger.schema.json` | Row schema + the extensible `store_classes` table |
| `tests/scripts/lib/encryption-posture-reconcile.sh` | Layer B live reconciliation (ADR-136 shape) |
| `tests/scripts/test-encryption-posture-reconcile.sh` | Layer B tests, incl. the could-not-measure matrix |
| `.github/workflows/scheduled-encryption-posture-reconcile.yml` | Layer B scheduler (**R2:** `on: workflow_dispatch:` only) |
| `apps/web-platform/server/inngest/functions/cron-encryption-posture-reconcile.ts` | **R2:** Inngest scheduler that dispatches the Layer B workflow |
| `scripts/followthroughs/encryption-posture-reconcile-soak-<issue>.sh` | 3-day soak probe |
| ~~`plugins/soleur/skills/constraint-scaffold/references/encryption-posture-gate.template`~~ | **R0: MOVED to the constraint-scaffold follow-up PR — not in this PR** |
| ~~`plugins/soleur/skills/constraint-scaffold/references/encryption-posture-scan.template`~~ | **R0: MOVED to follow-up PR** |
| ~~`plugins/soleur/skills/constraint-scaffold/test/encryption-posture.test.sh`~~ | **R0: MOVED to follow-up PR** |
| `knowledge-base/engineering/architecture/decisions/ADR-140-encryption-posture-as-a-design-time-default.md` | ADR |
| `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md` | Audit report (deliverable 8) |
| `knowledge-base/project/specs/feat-one-shot-encryption-at-rest-in-transit-design-default/tasks.md` | Task breakdown |

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/plan/references/plan-issue-templates.md` | `## Encryption Posture` × 3 templates (deliverable 1) |
| `plugins/soleur/skills/plan/SKILL.md` | §2.11 Encryption Posture Gate (deliverable 1) |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | §4.10 Encryption Posture Halt (deliverable 2) |
| `plugins/soleur/skills/preflight/SKILL.md` | Check 12 + §0.1 fast-path row (deliverable 3) |
| `plugins/soleur/skills/review/SKILL.md` | Defect-class entry + conditional spawn (deliverable 4) |
| `plugins/soleur/agents/engineering/infra/terraform-architect.md` | Hetzner/Cloudflare encryption defaults + the guard-inversion trap (deliverable 5) |
| `plugins/soleur/agents/engineering/infra/platform-strategist.md` | Encryption posture as a Decision Framework axis (deliverable 5) |
| `plugins/soleur/skills/provision-hetzner/SKILL.md` | Encryption posture step (deliverable 5) |
| `plugins/soleur/skills/provision-cloudflare/SKILL.md` | Encryption posture step (deliverable 5) |
| `plugins/soleur/skills/provision-doppler/SKILL.md` | Encryption posture step (deliverable 5) |
| `plugins/soleur/skills/provision-github/SKILL.md` | Encryption posture step (deliverable 5) |
| ~~`plugins/soleur/skills/constraint-scaffold/SKILL.md`~~ | **R0: MOVED to follow-up PR** |
| ~~`plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`~~ | **R0: MOVED to follow-up PR** |
| ~~`plugins/soleur/skills/constraint-scaffold/test/parity.test.sh`~~ | **R0: MOVED to follow-up PR** |
| `.github/workflows/ci.yml` | `encryption-posture` job (D7) |
| `scripts/required-checks.txt` | **R4:** register per the CodeQL-shape arm B (omit + non-15368 id) |
| `infra/github/ruleset-ci-required.tf` | `required_check` block + ABI-count comment (D7, **R4**) |
| `scripts/ci-required-ruleset-canonical-required-status-checks.json` | **R4: the 4th coupled site — parity test asserts set-equality** |
| `scripts/test-all.sh` | Register both new `.test.sh` suites |
| `.github/workflows/scheduled-followthrough-sweeper.yml` | `secrets=BETTERSTACK_API_TOKEN_READONLY` for the soak probe (**R2/S2c: read-only**), if needed |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | **R2:** Layer B Sentry heartbeat, ADR-117 count-gated (replaces the `uptime-alerts.tf` Better Stack beat) |
| ~~`apps/web-platform/infra/uptime-alerts.tf`~~ | **R2: replaced by the Sentry plane — not this file** |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Correct `workspacesVolume`; posture clauses on 4 stores |
| `knowledge-base/engineering/architecture/diagrams/views.c4` | `include platform.infra.workspacesVolume` |
| `knowledge-base/project/constitution.md` | The design-time-default principle (in lieu of an AGENTS rule, D4) |

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| **The gate is vacuous** — passes on everything, so nobody looks. The dominant failure class in this repo's recent corpus. | Mutation battery enumerated from the contract (MB-1..MB-7, AC8); positive-work floor (AC6, AC16); shallow-checkout equivalence (AC9); per-case verdict diffing rather than pass-counts. |
| **The ledger degrades into prose** — rows keep saying `luks` after the apparatus is renamed. | Citation resolution runs on **every** sweep; an unresolvable anchor FAILs (AC12). This is the single mechanism that separates this design from the legal-doc failure. |
| **Layer B silently dies**, leaving Layer A as a declaration-only gate. | Heartbeat-miss detection; could-not-measure is its own aborting class evaluated before the comparison (AC16); the 3-day soak before arming (AC17, AC31). |
| **`#6049` auto-fabrication** — adding a content-scoped gate to `required-checks.txt` fabricates a green synthetic for bot PRs. | AC14 forces an explicit adjudication recorded in the PR body. |
| **Required-check promotion partially lands** (job renamed, ruleset stale) — the `#6103` class. | AC13 asserts byte-identity across all three artifacts. |
| **The audit's "provider-managed" rows become the new false assurance.** | `does_not_defend` is mandatory and rejected when empty or a restatement (TS-12); attestations need a name, URL, and retrieval date. |
| **Scope** — 19 edited + 14 created files at a `single-user incident` threshold. | No safe split exists (see CTO assessment). Mitigated by the 5-agent `/plan-review` panel and `user-impact-reviewer` at review, both mandated by the threshold. |
| **ADR-140 ordinal collision** during the pipeline. | `/ship`'s collision gate; and if renumbered, the same-edit sweep of this plan + `tasks.md` + ACs. |
| **The `prefer-inngest` PreToolUse hook DENIES the Layer B workflow Write at `/work` time**, and the implementer overrides it reflexively without recording why. | D8 decides the placement in advance with the two-part exemption answered; the override hatch is declared **together with** a mandatory in-file justification block. AC32 asserts both are present. |
| **`/plan-review` and the deepen-plan agent panels never ran** (Task tool unavailable this session), so the plan has had no adversarial multi-agent read. At `single-user incident` threshold that is a material gap. | `/plan-review` MUST run with agents available before `/work`, at the 5-agent escalated panel the threshold mandates. Recorded in the Enhancement Summary rather than silently omitted. |

## Research Insights (deepen-plan pass, 2026-07-23)

### Precedent diff (Phase 4.4 — pattern-bound behaviors)

Three patterns in this plan have canonical sibling precedents in this repo. Each is adopted rather
than reinvented; divergences are named.

| Pattern | Precedent (`git grep`-located) | This plan | Divergence |
|---|---|---|---|
| **Repo-wide lint script + `.test.sh` + CI job** | `scripts/lint-trap-tempfile-ownership.py` + `.test.sh`, registered in `scripts/test-all.sh`, run from `.github/workflows/ci.yml:134` | `scripts/lint-encryption-posture.py` + `.test.sh`, same registration path | **Deliberate divergence:** the precedent is *advisory* by design (ADR-129, and its docstring says so). This gate is **required** (D7). The divergence is the point, not an oversight. |
| **Fail-closed pre-apply/live gate** | `tests/scripts/lib/preapply-entrypoint-gate.sh` (ADR-136) — default-deny, one catch-all for every ambiguity, a control probe, `--gate`/`--audit` mode split | `tests/scripts/lib/encryption-posture-reconcile.sh` — same shape, `--audit`/`--live` split | **Adopted verbatim in shape.** Adds a *positive-work floor* the precedent does not have, because a posture sweep (unlike an entrypoint probe) has no natural per-item output to count. |
| **Guest-side LUKS apparatus** | `apps/web-platform/infra/git-data-luks.tf` (`random_password` → dedicated Doppler config → `doppler_secret` → `cryptsetup luksOpen --key-file -` in `git-data-bootstrap.sh:91` → `/dev/mapper/git-data`) and `workspaces-luks.tf` | The detector's four-part citation chain for `mechanism: luks` | **Adopted as the detector's contract.** The detector is written *against* these two files, so both must pass on day one — which is also the calibration fixture (a detector that cannot certify the repo's two genuinely-encrypted volumes is miscalibrated). |

**Scheduled-work precedent:** see **D8** — divergence from the ADR-033 canonical Inngest path, argued.

### Verify-the-negative pass (Phase 4.45)

Every negative/absolute claim in this plan was probed against the code rather than asserted.

| Claim | Probe | Verdict |
|---|---|---|
| "There is **no** `encrypted` attribute on `hcloud_volume`." | `grep -A3 'hetznercloud/hcloud' apps/web-platform/infra/.terraform.lock.hcl` → **v1.63.0** (constraint `~> 1.49`); `grep -rn 'encrypted' --include=*.tf apps/web-platform/infra/ \| grep -i volume` → only two comments *asserting the absence*, zero usages. | **CONFIRMED, version-scoped to `hetznercloud/hcloud` v1.63.0.** The claim is pinned to the installed provider, not to memory. If the provider ever adds the attribute, the detector's store-class table is the single place to change. |
| "`sslmode=require` encrypts but does **not** verify the certificate." | libpq documented semantics: `require` = encrypt only; `verify-ca` = verify chain; `verify-full` = verify chain **and** hostname. Cited so a future reader does not "fix" the ban-list. | **CONFIRMED** — and this is why `require` is banned, which is counterintuitive enough to be a Sharp Edge. |
| "`plan`/`review`/`preflight` are **not** eval-gated." | Read `plugins/soleur/skills/eval-harness/gated-skills.json` in full — 4 entries, none of them. | **CONFIRMED** — no eval arm required. |
| "The repo **already** exercises the `betteruptime_*` and `github_repository_ruleset` API surfaces." | `grep -rln 'betteruptime_' --include=*.tf apps/` → 5 files; `infra/github/ruleset-ci-required.tf` exists with 15+ `required_check` blocks. | **CONFIRMED** — no new API surface, so the ADR-130 new-surface credential probe does not fire. (Stated as verified, not assumed — `hr-verify-repo-capability-claim-before-assert`.) |
| "This PR remediates **nothing**." | Enforced as AC25 with a concrete `git diff` predicate rather than left as an intention. | **ENFORCED**, not merely claimed. |
| "There is **no bypass** in the detector." | Deliberately **not** verified by grepping the script for the absence of a flag — that is a vacuous sweep for a semantic property. Verified behaviourally by the AC10 matrix. | **CONVERTED** from an absence-grep to a behavioural assertion. |

### Citation verification (deepen-plan quality checks)

Run live this session; all clean:

- **Issues/PRs** — `#6588` OPEN, `#6604` CLOSED, `#6733` OPEN, `#6808` OPEN, `#6814` OPEN, `#6138` OPEN, `#4133` OPEN, `#6049` CLOSED, `#6103` CLOSED. The `#6049` attribution was checked against the artifact, not just the issue: `scripts/required-checks.txt` carries the literal header `⚠ AUTO-FABRICATION GUARD (#6049)`.
- **Labels** — `type/security`, `domain/engineering`, `priority/p1-high`, `follow-through`, `code-review` all exist (`gh label list`).
- **AGENTS rule IDs** — all 10 cited IDs resolve to active `[id: …]` entries in `AGENTS.md`; none appear in `scripts/retired-rule-ids.txt`. The two id-shaped tokens that did **not** resolve were both *hypothetical* names for the rule this plan deliberately does not create (one in the rejected-alternatives table, one in the D4 byte-cost illustration); both were rewritten to a placeholder shape, so the plan now passes the sweep with zero unresolved tokens.
- **ADR ordinal** — derived from a **freshly fetched** `origin/main` (`git fetch origin main` then `git ls-tree --name-only origin/main …decisions/`) → max is **ADR-138**, so **139** is correct as of this session. Still provisional.
- **`knowledge-base/` paths** — every `.md` citation in this plan resolves on disk except the four this plan creates.

## References & Research

### Internal

- `apps/web-platform/infra/workspaces-luks.tf` §"SHARP EDGE" + §"THE ISSUE'S PREMISE WAS WRONG" — no `hcloud_volume` encryption attribute; the guard-inversion data-loss trap.
- `apps/web-platform/infra/git-data-luks.tf:11-30` — the four-part LUKS apparatus and the rotation-is-a-cutover semantics.
- `tests/scripts/lib/preapply-entrypoint-gate.sh` (ADR-136) — the default-deny fail-closed gate shape Layer B mirrors.
- `plugins/soleur/skills/preflight/SKILL.md` §0.1, Check 4, Check 9 — cached path-set, invariant-vs-informational SKIP, ban-list check shape.
- `plugins/soleur/skills/deepen-plan/SKILL.md` §4.6, §4.7 — the halt shape §4.10 mirrors.
- `plugins/soleur/skills/constraint-scaffold/SKILL.md` — the agent-owns-gates recovery model the emitted gate inherits.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
- `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`
- `knowledge-base/project/learnings/2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`
- `knowledge-base/project/learnings/2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `knowledge-base/project/learnings/2026-07-22-acceptance-grep-of-a-literal-string-is-a-vacuous-sweep-for-a-semantic-property.md`
- `knowledge-base/project/learnings/2026-05-12-agents-md-trim-loader-class-fit-verification.md`
- `knowledge-base/project/learnings/2026-06-15-agents-budget-at-cap-descopes-planned-rule-and-harvest-md-exclusion.md`

### Related issues

`#6588` (parent P1, **OPEN** — `Ref`, never `Closes`), `#6604` (cutover, CLOSED), `#6733`, `#6808`,
`#6814`, `#6138` (AGENTS budget), `#4133` (Observability schema parity — acknowledged overlap),
`#6049` (synthetic-check auto-fabrication guard), `#6103` (required-check rename drift).

## Sharp Edges

- A plan whose `## Encryption Posture` section is empty, contains `TBD`/`TODO`/placeholder text,
  omits `does_not_defend`, or says "the provider handles it" will fail `deepen-plan` §4.10. Fill it
  before requesting deepen-plan or `/work`.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail
  `deepen-plan` §4.6.
- **`hcloud_volume` has no `encrypted` attribute.** Any AC, test, or detector branch written as
  "assert the resource has an encryption attribute" is unimplementable for this stack and must be
  rewritten as the four-part guest-side apparatus check. This is the single most likely place for
  the plan's intent to be lost in translation at `/work`.
- **`sslmode=require` encrypts without verifying.** It belongs in the ban-list, not the require-list.
  A reviewer or implementer who "fixes" this by moving `require` to the allowed set has reintroduced
  the defect.
- **Never point the LUKS idempotence guard at a populated plaintext device.**
  `if ! cryptsetup isLuks "$DEV"; then luksFormat` is false on a populated plaintext volume ⇒
  `luksFormat` ⇒ live user data wiped. Any generated Terraform or emitted template that reproduces
  the guard must reproduce the constraint with it.
- **This PR remediates nothing.** Encrypting `inngest_redis` or the registry volume is a cutover with
  its own freeze and blast-radius analysis, and each gets its own issue. A reviewer asking "why
  didn't you just encrypt it here?" should be pointed at AC25.
