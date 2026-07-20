---
title: "Close the Inngest dedicated-host observability gap: double-scheduler discriminators + standalone read-only probe ops"
date: 2026-07-20
type: feature
lane: cross-domain
issues: ["#6617"]
refs: ["#6702", "#6488", "#6295", "#6608", "#6348", "#6178", "#6536", "#6539", "#5560", "#6730"]
adrs: ["ADR-100", "ADR-117"]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: "APPROVE WITH CONDITIONS (C1-C6 applied)"
revision: v2
---

# Inngest dedicated-host: double-scheduler discriminators + standalone probe ops

> **v2**, rewritten after a 7-agent review panel. v1's central design (`backend_sha8`, a
> cross-host hash read from `/proc/<pid>/environ`) was condemned by four independent P0s and is
> **gone**. See **Review Reconciliation**.

## Enhancement Summary

**Deepened on:** 2026-07-20
**Review panel:** dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer (5-agent escalation for `single-user incident`) +
cto (devex) + cpo (sign-off)

### Key improvements

1. **The central measurement was wrong and is now right.** v1's `backend_sha8` would have hashed
   prd and dark to the *same* digest (the project ref lives in the DSN's user field, which the
   hash excluded, while host and dbname are identical) — producing a **guaranteed false
   double-scheduler escalation** on the exact question the instrument was built to answer.
   Replaced by `backend_is_prod`, derived from `inngest-server-flip-guard.sh`, which already
   computes that boolean inside the Doppler env and already ships to Better Stack.
2. **A credential-exposure surface was removed rather than added.** v1 required reading
   `/proc/<pid>/environ` — which this repo documents as *the* confidentiality boundary its
   secrets design rests on (#5560) and treats as a blocked exfiltration signature in
   `bash-sandbox.test.ts`. v2 touches no DSN and resolves no pid.
3. **H4 no longer depends on a production replace.** `inngest-doublefire-probe.sh` already
   exists and proves *actual cron runs* on the dedicated host. Exposing it as a standalone op
   (PR B) answers the double-scheduler question with zero outage, turning the replace from a
   diagnostic into a delivery step.
4. **The delivery invariant became mechanical.** The image-content check moved from a one-shot
   manual `grep -c` to a byte-`diff` promoted into CI — the only form that survives a later
   review commit.
5. **The pin surface is four sites, not one**, and a tag push reds `main` until the PR merges
   (git tags are repo-global; the guard asserts the *web* pin against the semver-max tag).

### New considerations discovered

- **#6197 is CLOSED and already rendered** — v1 named it as riding along and encoded that in an AC.
- **The root debt:** the dedicated host has no in-place redelivery channel, though the web host
  does (`ci-deploy.sh:2758-2891`). That absence is why every observability change here costs a
  replace of the sole scheduler. Tracked at C4.6.
- **"The next drift apply reconciles it" is false** — `scheduled-terraform-drift.yml` is
  plan-only and the operator full apply is PROSE-ONLY (#6730). Expect a persistent drift exit-2.
- **The root disk takes the flip-FSM state slot** (`/var/lock/inngest-cutover-flip.state`) and
  `/var/lib/inngest` — neither was enumerated in v1.
- **The cron send path has no idempotency guard**, so a double-fire duplicates statutory-deadline
  notices per tick indefinitely. Companion issue, deliberately not folded in.

### Gates run

| Gate | Result |
|---|---|
| 4.4 precedent-diff | Applied — flip-guard `is_prod`, `derive_durability_state()` ExecStart read, `image_ref` state-file pattern all cited as precedent |
| 4.45 verify-the-negative | Run — both hooks confirmed registered (`hooks.json.tmpl:257/276`, `infra-config-install.sh:73-74`); no new TF variable confirmed |
| 4.5 network-outage | Not triggered |
| **4.55 downtime & cutover** | **FIRED** — `## Downtime & Cutover` section added; telemetry emitted |
| 4.6 user-brand impact | PASS |
| 4.7 observability | PASS — 5 fields present, no placeholders, no SSH in `discoverability_test` |
| 4.8 PAT-shaped variable | PASS — no matches |
| 4.9 UI wireframe | Skipped — no UI surface |

## Overview

The dedicated Inngest host (`soleur-inngest`, 10.0.1.40) cannot today prove whether it will
double-fire crons against production. Three findings shape this plan.

**Finding 1 — the marker already exists on `main` and has never reached the host.** PR #6702
(merged 2026-07-19 17:53 UTC) shipped `SOLEUR_INNGEST_SERVER_PROBE` complete with unit, hourly
timer, `SyslogIdentifier=`, Vector allowlist entry and tests. The deliverable is not "build a
marker" — it is **add the missing discriminators and deliver it**.

**Finding 2 — H4 can be answered with no host replace at all.**
`inngest-doublefire-probe.sh` already exists, is already installed on the web hosts, already
targets 10.0.1.40, and enumerates the dedicated host's **actual cron runs**. It is reachable
only from inside `op=verify` step 2.6 — i.e. inside the maintenance window. Exposing it as a
standalone op answers the double-scheduler question **before** and **independent of** any
replace. This is the plan's most important structural change: the replace becomes a
**delivery** step, not a **diagnostic** one.

**Finding 3 — the backend discriminator already exists and already ships.**
`inngest-server-flip-guard.sh` runs as `ExecStartPre` **inside** `doppler run --config prd`,
computes `is_prod` from `INNGEST_POSTGRES_URI` via a substring test on the prod project ref,
emits `logger -t inngest-server-flip-guard "ALLOW: is_prod=$is_prod flag='…'"`, and **never
echoes the URI** (AC-NOBODY). Its tag is already in the `vector.toml` allowlist (`:175`). So
the signal v1 tried to invent by reading `/proc` is already wired — it simply fires only at
server start, not periodically.

### Three PRs, ordered

The work ships through three unrelated delivery channels, so it ships as three PRs. The
operator sanctioned sequencing ("If they must be sequenced … priority 2 over priority 1").

| PR | Content | Effective | Issue ref |
|---|---|---|---|
| **A** | `_pf_scrub` libpq fix ×3 + permanent identity test | at merge | `Closes #6295` |
| **B** | `op=registry-probe` **and** `op=doublefire-probe`, standalone read-only | at merge | `Ref #6617` |
| **C** | Marker fields + pin bumps (both hosts) + ADR amendment + replace dispatch | post-merge replace | `Ref #6617` |

**PR B is where H4 gets answered.** PR C makes the signal continuous.

## Premise Validation

Run 2026-07-20 against live surfaces. Every claim executed, not reasoned about.

| Premise | Measured reality | Response |
|---|---|---|
| "Add a periodic monitored `SOLEUR_*` marker" | **Already on `main`** — `inngest-bootstrap.sh:500`, PR #6702 (`f11e59d8f`). | Extend + deliver, don't build. |
| Marker must carry `server_active`, `--sdk-url`, the backend | Carries `server_active` ✅; **no** `sdk_url`, **no** backend field ❌. | The genuine field gap. |
| Dedicated host is shipping | **Confirmed** — `_MACHINE_ID=229d535e…`, `host_name=soleur-inngest-prd`, rows 08:11:45Z / 08:12:46Z. | Vector path healthy. |
| `inngest-heartbeat` says `url_present=no` | **Confirmed**, firing **every 60 s**. | #6617b made it hourly ⇒ host runs a **pre-#6702 bootstrap**. |
| Is the marker reaching Better Stack? | **Zero rows over 48 h**, with a **passing positive control**. | Zero is real; marker inert on the host. |
| Host replaced since #6702? | `_BOOT_ID=273847266ef442afa11b717e1bb1da0a`, unchanged. | Delivery is the gate. |
| #6295 open, affects the probe scripts | **Confirmed.** Three byte-identical `_pf_scrub` copies; both `sed` rules require `://` or `@`, so the libpq keyword form passes unredacted. | PR A. |
| #6608 open, inert until a replace | **Confirmed** OPEN; `inngest-host.tf:47` postdates the host's boot. | Rides along benignly (narrows nft to {.10}; .11 destroyed #6538). |
| #6197 open | **FALSE — CLOSED 2026-07-18.** Its cloud-init change (`c890464ce`) predates the host's boot and is **already rendered**; the Premise Validation rows above prove it (journald→Vector is live). | v1's ride-along claim removed. |
| #6488 / #6348 open | Confirmed OPEN; #6348 is the deliberate HOLD, currently **draft + MERGEABLE** (one toggle from merging). | Untouched; see window risk. |
| `inngest-host.tf` has no `ignore_changes=[user_data]` | **Confirmed**, deliberate; the file documents the force-replace consequence verbatim. | Delivery via `inngest-host-replace`. |
| `op=enumerate` never contacts 10.0.1.40 | **Confirmed** — `CUTOVER_HOSTS: "10.0.1.10"` (`cutover-inngest.yml:106`). | New ops target .40 via the web-host webhook. |

**The re-frame:** the issue asks whether the host is "DARK." It is not — it ships. The host is
**observable but not discriminating**: it can prove it is alive, not what it is pointed at.

## Review Reconciliation — v1 → v2

| v1 defect | Found by | v2 response |
|---|---|---|
| **`backend_sha8` hashed host+dbname — but the project ref lives in the USER field** (`postgres.<ref>@…`); prd and dark share an identical host and dbname, so both hash **the same**. v1 would have *guaranteed a false double-scheduler escalation*. | spec-flow P0-1 | Field **deleted**. |
| **The co-located comparand had no writer path** — the web host updates via `ci-deploy.sh`, not the replace. The cross-host comparison was unperformable. | spec-flow P0-2, simplicity #1 | **Dissolved** — the replacement signal is self-sufficient on one host. |
| **Reading `/proc/<pid>/environ` contradicts two tested repo positions**: `inngest-bootstrap.sh:725-727` documents that file as *the* confidentiality boundary the secrets design rests on (#5560 moved secrets into env *because* environ is unreadable), and `bash-sandbox.test.ts:16-18` lists `cat /proc/self/environ` as a **blocked credential-exfiltration signature** (CWE-522 per `workspaces-luks.test.sh:145`). It also required the probe to hold the password-bearing DSN in a variable. | architecture P1-2 | **Eliminated.** No `/proc` read anywhere. |
| **The pid was unspecified and unverifiable pre-replace** — ExecStart is `doppler run`, so `MainPID` may be the wrapper and the field would degrade to `unknown` forever, silently. Phase 0.2's "verification" was two repo greps that establish nothing about runtime. | architecture P0-2 | **Moot** — no pid resolution needed. |
| No normalization contract; pooler-vs-direct URIs hash differently. | DHH S2, spec-flow P1-7 | **Moot.** |
| **`cloud-init.yml` (web host) omitted; the tag push reds `main`.** Git tags are repo-global, and `cloud-init-inngest-bootstrap.test.sh:234` asserts the **web** pin against the semver-max published tag. Pushing the tag fails AC6 on `main` until the PR merges. | architecture P0-1, CTO P0 | All four pin sites enumerated; red-window documented. |
| **#6197 named as riding along; AC20 mandated that false claim in the PR body.** | architecture P1-1 | Removed. |
| **AC7 ∧ AC9 mutually unsatisfiable** — `host=` was in both the redaction set and the positive control. | spec-flow P0-3 | Rule requires **≥2 libpq keyword co-occurrence**. |
| **Markers never transit `_pf_scrub`** — they go through `_pf_sanitize`. v1's rationale and control tested a path that cannot occur. | Kieran P1 | Rationale re-anchored; control fed through a **real** call site. |
| `doublefire-probe` already exists and answers H4 with no replace. | CTO P1 | Added as a second standalone op; H4 decoupled from the replace. |
| Phase 3.4's `grep -c` passes on any image containing the string, and ran once by hand. | CTO P1, architecture P1-5 | Upgraded to byte-**`diff`** and promoted to a **permanent CI gate**. |
| `_pf_scrub` identity as a PR AC evaporates after review. | CTO P2 | Promoted to a **permanent test**. |
| "The next full/drift apply reconciles the firewall attachment" — **no such automated path exists.** `scheduled-terraform-drift.yml:100` is plan-only; the operator full apply is recorded as PROSE-ONLY (#6730). | architecture P1-4 | Claim corrected; permanent drift exit-2 noted. |
| Destroy list incomplete — the root disk takes `/var/lib/inngest` and `/var/lock/inngest-cutover-flip.state` (the flip-FSM state slot). | architecture P2-1 | Enumerated. |
| "No SSH by construction" overstates — port 22 is open intra-network (`policy accept`, only 8288/8289 dropped). | architecture P2-3 | Reworded to "no SSH on any **automated** path." |
| Three delivery channels in one PR; two contradictory close semantics in one body. | DHH S1, simplicity #3, CPO C6 | **Split into A/B/C.** |
| 12 of 20 ACs restated AC15 or were PR formatting. | DHH S4 | Cut to ≤8 per PR. |
| Impact section understated the artifact. | CPO C1-C4 | Rewritten. |
| No rollback if the replace fails; no timing envelope. | CPO C5, CTO P2(d), spec-flow P1-2 | C0.4 + C4.4. |
| Delivery gate had no followthrough enrollment. | spec-flow P1-3 | C4.5. |
| Line-cite / fixture-string / heredoc-scoping papercuts. | Kieran P2 ×5, architecture P2-4 | Corrected inline. |

## User-Brand Impact

**If this lands broken, the user experiences:** a **duplicated statutory-deadline notice**, or
a **missed** one. The only cron reaching an end user is
`apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` (`0 6 * * *`), calling
`notifyOfflineUser(..., { type: "email_triage", isStatutory: true, title: "Statutory deadline
approaching — …" })`. The other crons mail `ops@`. Both artifacts are trust-breach class, not
annoyance class.

**Aggravating factor — no dedupe guard on that path.** `notifyOfflineUser` →
`sendEmailNotification` → `sendEmailTriageEmailNotification` (`server/notifications.ts`
~275/~517/~565) issues a bare `resend.emails.send` with no idempotency key, no sent-marker row,
no Inngest `idempotency`/`concurrency` config. The sibling `notifyInboxItem` path (`:709`,
ADR-035) *does* carry a `(workspace_id, dedup_key)` guard; this one does not. A double-fire
therefore produces two identical emails per user **per tick, indefinitely**.

**Timing — this is a post-cutover risk, not a present one.** The dedicated host measured
`url_present=no`; it fires nothing today. This instrument prevents the condition rather than
remediating a live one.

**If this leaks, the user's data is exposed via:** the prd Supabase project ref reaching a
GitHub Actions run log. `inngest-registry-probe.sh:106-113` extracts `errors[].message`, pipes
through `_pf_scrub`, then writes to **both** stdout and stderr. `_pf_scrub` (`:64`) carries two
`sed -E` rules requiring `://` or `@`; the libpq keyword form has neither.

- **Brand-survival threshold:** `single-user incident`

**Threshold premise, stated explicitly:** the *mechanism* is systemic-shaped — every user of
the affected path, not one. It lands at `single-user incident` **only because
`Beta users: 0`** (`knowledge-base/product/roadmap.md:81`). **This tier expires:** once founder
recruitment (#1439) lands real users, the same mechanism becomes `aggregate pattern`.

**Companion issue (out of scope — do not fold in):** cron send-path idempotency. This plan
builds an instrument that *detects* double-fire; a dedupe guard would make it *harmless* on the
one path reaching users. Cheap at 0 users, expensive at 10. It touches product notification
code, not infra.

## Hypotheses

| # | Hypothesis | Status | Evidence |
|---|---|---|---|
| H1 | The dedicated host is dark (the issue's framing) | **REFUTED** | Live journald rows today. |
| H2 | A Vector allowlist gap suppresses shipping | **REFUTED** | Rows arrive; tag allowlisted (Source 4, entry 21). |
| H3 | The marker is absent because the host predates #6702 | **CONFIRMED** | Per-minute dark-arm rows + zero probe rows + unchanged `_BOOT_ID`. |
| H4 | The dedicated host is live against prod / double-firing | **UNKNOWN** | The deciding datum is on-host; nothing off-box reads it today. |

**H4's resolution path (v2 — no replace required):** PR B's `op=doublefire-probe` reads the
dedicated host's **actual cron run history**. Non-empty ⇒ H4 CONFIRMED, escalate. Empty ⇒
strongly refuted for the observed window. `op=registry-probe` corroborates via registered
functions. PR C then makes the signal continuous.

**No H4 verdict may be recorded — in a PR body, an issue comment, or an AC — before a probe row
is read.** Stating it earlier asserts the conclusion the instrument exists to test.

---

# PR A — `_pf_scrub` libpq redaction (#6295)

Ships first: a credential-leak fix must not wait behind an OCI build. PR B depends on it,
because PR B surfaces `inngest-registry-probe.sh` output into a run log.

## A — Files to Edit

`inngest-registry-probe.sh` · `inngest-doublefire-probe.sh` · `inngest-inventory.sh` (the three
`_pf_scrub` copies) · `inngest-registry-probe.test.sh` (regression + control + permanent
identity test). All under `apps/web-platform/infra/`.

## A — Phases

**A0.** Re-confirm the three `_pf_scrub` bodies are byte-identical (verified 2026-07-20:
`registry-probe.sh:64-69`, `doublefire-probe.sh:105-110`, `inventory.sh:206-211`, zero pairwise
diff).

**A1 (RED).** Three failing tests:
- libpq form `host=db.<synthetic>.supabase.co port=5432 dbname=postgres user=postgres password=<synthetic>` → the synthetic ref must appear in **neither** stdout **nor** stderr. Fixture **synthesized** (`cq-test-fixtures-synthesized-only`).
- Over-redaction control fed through a **real `_pf_scrub` call site** (a GraphQL `errors[].message` string of benign diagnostic text) — must survive intact. *(v1's control used a `SOLEUR_*` marker; markers reach `_pf_sanitize`, never `_pf_scrub`, so that control tested an impossible path and would have passed regardless.)*
- Pairwise-identity test extracting the function body from all three files.

**A2 (GREEN).** Add a third `sed -E` rule requiring **co-occurrence of ≥2 libpq keywords**
(e.g. `host=` within N chars of `password=` or `dbname=`). A single-keyword rule is what made
v1's AC7 and AC9 mutually unsatisfiable. Apply **byte-identically** to all three copies.

**A3.** File the shared-library extraction issue, recording **"a fourth consumer appears"** as
the upgrade trigger. Number in the PR body.

> **Deferral rationale.** The cost of triplication is *drift*, and A1's permanent identity test
> converts that from silent divergence into a mechanical check. Three guarded copies is a
> legitimate steady state. Re-sourcing three cutover-path scripts during a held cutover is not.

## A — Acceptance Criteria

- **A-AC1** — The libpq fixture's synthetic ref appears in neither stdout nor stderr.
- **A-AC2** — The over-redaction control, fed through a real call site, survives intact.
- **A-AC3** — The rule fires only on ≥2 co-occurring libpq keywords; a lone `host=` does not trigger redaction.
- **A-AC4** — The three bodies remain byte-identical, asserted by a **permanent test**.
- **A-AC5** — The two original rules still redact URI and `@` forms (no regression).
- **A-AC6** — Extraction tracking issue filed; number in the PR body.
- **A-AC7** — `inngest-registry-probe.test.sh`, `inngest-doublefire-probe.test.sh`, `inngest-inventory.test.sh` green.

---

# PR B — standalone read-only probe ops

Adds **two** ops. `registry-probe` is the operator's Priority 1; `doublefire-probe` is the
stronger instrument and the one that answers H4.

## B — Evidence hierarchy (why two, not one)

| Instrument | Proves | Replace? |
|---|---|---|
| `registry-probe` | an SDK has **registered functions** against the dark host | no |
| `doublefire-probe` | the dark host has **actually executed cron runs** — the harm itself | no |
| flip-guard `is_prod` (PR C) | the host is **configured against** prod, continuously | yes |

## B — Files to Edit

`.github/workflows/cutover-inngest.yml` (enum + two case arms) ·
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`. Both hooks **already exist** in
`HOOK_IDS` — no new hook, no webhook config change.

## B — Phases

**B1 (RED).** Four anchored assertions — verified to return 0 against the current file, so they
fail RED correctly. Anchoring is load-bearing: `registry-probe` already appears **10×** as the
hook name `inngest-registry-probe`, so an unanchored grep false-passes.
```bash
grep -qE '^[[:space:]]+-[[:space:]]*registry-probe$'
grep -qE '^[[:space:]]+registry-probe\)'
grep -qE '^[[:space:]]+-[[:space:]]*doublefire-probe$'
grep -qE '^[[:space:]]+doublefire-probe\)'
```

**B2 (GREEN).** Two case arms modelled on `enumerate` (single GET, empty-body HMAC +
CF-Access, shape guard, counts-only notice) targeting `$BASE/inngest-registry-probe` and
`$BASE/inngest-doublefire-probe`. Both proxy over the private net to
`http://10.0.1.40:8288/v0/gql`; the runner cannot reach .40 directly (deny-all-public, SEC-H2),
which is why `CUTOVER_HOSTS` is irrelevant here.

Carry `op=verify` step 2.6's **scope caveat** verbatim into the `doublefire-probe` summary: the
probe reads only .40's run history and is **not** a web-2 double-fire detector.

**B3 — hard constraints.**
- **No** environment gate. `cutover-inngest.yml:59` stays byte-identical (pinned by `cutover-inngest-workflow.test.sh:389`). Verified: the expression yields `''` for any third op.
- **No** `${{ inputs.op … }}` expression in either arm. `:43` asserts exactly one file-wide; verified it returns 1 (sole match `OP: ${{ inputs.op }}` at `:79`; line 59's `${{ (inputs.op` does not match the pattern).
- **No** reminder capture, quiesce, Doppler secret write, or state transition.
- Both curls **must** carry `--max-time` (parity assertion `:55-58`).
- **No** retry loop — `for attempt in 1 2` is pinned at 3 (`:296-297`). Single-shot, matching `execute` 2.0.
- Do not write the shell-remote-login word in a comment (AC-NOSSH `:170` is comment-blind).

**B4.** File a tracking issue: `cutover-inngest-workflow.test.sh` asserts a **character
census** (four `grep -c` counts, one holding only because two conditionals open with `(`). It
punishes correct changes — a tracking issue, not a longer instruction manual.

**B5.** Dispatch both ops standalone and record results. **This is where H4 is answered.**

## B — Acceptance Criteria

- **B-AC1** — Both ops in the enum and as case arms (B1's anchored patterns verbatim).
- **B-AC2** — `grep -cE '\$\{\{[[:space:]]*inputs\.op' .github/workflows/cutover-inngest.yml` returns **1**.
- **B-AC3** — The `environment:` line is byte-identical to its pre-change form.
- **B-AC4** — curl / `--max-time` parity holds; `for attempt in 1 2` count still 3.
- **B-AC5** — Neither arm performs a Doppler secret write, reminder capture (`mode=capture`), quiesce POST, or write to `/hooks/deploy`.
- **B-AC6** — Both ops dispatched standalone return HTTP 200 with a well-formed object and complete with **no pending-approval state** (the observable evidence that `environment` resolved empty; GH's job API surfaces approval state, not the evaluated string).
- **B-AC7** — The `doublefire-probe` summary carries the 2.6 scope caveat.
- **B-AC8** — Counting-assertion tracking issue filed; number in the PR body.

---

# PR C — marker discriminators + delivery

> **STATUS: CANCELLED — 2026-07-20, by operator decision.** Superseded the earlier HOLD. The
> authoritative ruling is in
> `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/decision-challenges.md`
> § "Follow-on ruling — 2026-07-20: PR C is CANCELLED". The design below is retained as the record of what was
> designed; it is not live work.

## C — Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/inngest-server-flip-guard.sh` | also write the already-computed `is_prod` to a state file |
| `apps/web-platform/infra/inngest-bootstrap.sh` | `sdk_url` + `backend_is_prod` + `registry_count` in the `PROBESCRIPTEOF` heredoc (`:459-520`); mirror into the second-channel call at `:517` |
| `apps/web-platform/infra/cloud-init-inngest.yml` | bump `IREF` tag **and** digest (`:390`) |
| `apps/web-platform/infra/cloud-init.yml` | `IREF` (`:699`) + `ZIREF` (`:705`) — **mandatory, see C1.3** |
| `apps/web-platform/infra/inngest.test.sh` | §A4 field + purity assertions |
| `apps/web-platform/infra/inngest-server-flip-guard.test.sh` | state-file assertions |
| `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` | cross-file pin assertion + pinned-image-vs-tree diff |
| `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` | `## Amendment` — the delivery invariant |

## C — Phase C0: preconditions

**C0.1** Re-run the Premise Validation queries. If `SOLEUR_INNGEST_SERVER_PROBE` now returns
rows, the host **has** been replaced — STOP, re-plan; the marginal-cost argument is void.

**C0.2** Confirm the flip-guard state-file seam: the guard runs as `ExecStartPre` inside
`doppler run --config prd` (`inngest-bootstrap.sh:856`), already computes `is_prod`
(`inngest-server-flip-guard.sh:39-41`), and already logs it without echoing the URI. Confirm
`/run` is writable at `ExecStartPre` time and that the guard's fixture seams
(`GUARD_POSTGRES_URI`, `GUARD_FLIP_FLAG`) let CI test the new write hermetically.

**C0.3** Resolve the current latest `vinngest-v*` tag. **Do not bake a literal** — v1
hardcoded `v1.1.25` in two places with no step reading the current tag.

**C0.4** Capture the **outgoing** pinned digest (`v1.1.24@sha256:6cdaa63d…`) and record it in
the PR body as the rollback target.

**C0.5** Re-verify the C4 enumeration against all three `.c4` files.

## C — Phase C1: GREEN

**C1.1 — the backend discriminator, without reading `/proc`.**

Extend `inngest-server-flip-guard.sh` to write its **already-computed** boolean to a small
state file (e.g. `/run/inngest-backend-state` containing `is_prod=true|false` and nothing
else), alongside the `logger` line it already emits. The probe then **reads that file** — the
identical pattern #6702 already uses for `image_ref`, which reads
`/etc/default/soleur-inngest-image`.

> **Why this and not v1's `/proc/<pid>/environ` read.** The guard is *already* inside the
> Doppler secrets env legitimately; the probe never touches the DSN, never resolves a pid, and
> never holds a password-bearing string. v1's design required all three, and contradicted two
> tested repo positions: `inngest-bootstrap.sh:725-727` documents `/proc/<pid>/environ` as
> **the** confidentiality boundary the secrets architecture rests on (#5560 moved secrets into
> env *because* it is unreadable), and `bash-sandbox.test.ts:16-18` lists reading it as a
> blocked credential-exfiltration signature (CWE-522). Deriving the same boolean from the
> component that already computes it is strictly better on every axis.
>
> **Why a substring test and not a hash.** The prod project ref is a documented **NON-secret
> identifier**, already in `inngest.tf`, and `inngest-server-flip-guard.sh:32` already uses it
> as `INNGEST_PROD_URI_MARKER`. v1 rejected the literal on #6295 grounds — but #6295 concerns
> DSNs carrying **passwords**, not refs. Worse, v1's hash *excluded* the ref (it lives in the
> user field, `postgres.<ref>@…`) while prd and dark share an identical host and dbname, so
> both would have hashed the same and the plan would have **guaranteed a false escalation**.

Emit `backend_is_prod=yes|no|stale|unknown`. `stale` when the state file predates the current
`boot_id` (the guard runs at server start; a file from a previous boot must not read as
current). `unknown` when absent or unreadable.

**C1.2 — the other two fields.** Every capture carries `|| true` and degrades to `unknown`; a
field may degrade, the event may not.
- **`sdk_url`** — from `systemctl show -p ExecStart inngest-server.service`, extracting the `--sdk-url` argv value. Mirrors `derive_durability_state()` (`inngest-inventory.sh:415`), the established no-SSH ExecStart-reading precedent. A private-network URL, not a secret; sanitize control characters.
- **`registry_count`** — a second loopback curl to `/v0/gql` for the function count, making registry state **continuous** rather than on-demand. The probe is `#!/bin/sh` and deliberately jq-free: count via `grep -c` on function IDs; never import jq.

**C1.3 — the pin surface is four sites across three files, and bumping only one reds `main`.**

| Site | Form |
|---|---|
| `cloud-init-inngest.yml:390` | `IREF=…:v1.1.24@sha256:6cdaa63d…` (digest-pinned) |
| `cloud-init.yml:699` | `IREF=…:v1.1.24` (tag-only) |
| `cloud-init.yml:705` | `ZIREF="$ZURL/…:v1.1.24"` (zot mirror) |
| `inngest-bootstrap.sh:492` | a comment literal that goes stale on any bump |

Git tags are **repo-global**, and `cloud-init-inngest-bootstrap.test.sh:234` asserts the **web**
pin against the semver-max published tag. So the instant C2.1 pushes the tag, that assertion
fails on `main` until this PR merges. **Bump all four sites**, and state the red-`main` window
in the PR body. Precedent: commits `4a1997ffb` and `39a4bb8dd`, both titled "pin **both hosts**
to inngest-bootstrap v1.1.2x".

This does **not** replace web-1 — `server.tf:289` carries
`ignore_changes = [user_data, ssh_keys, image, placement_group_id]`. The web host picks the new
image up through its own `ci-deploy.sh` deploy-webhook path.

**C1.4 — emit.** Extend the **single** `logger -t "$LOG_TAG"` call — never add a second; the
one-event self-sufficiency property is the point. Mirror all fields into the second-channel
`inngest-boot-phone-home.sh` call at `:517` (inside the heredoc), the **only** carrier when
Vector is down.

**C1.5** Confirm no `if` precedes the emit (ADR-117) and `LOG_TAG` remains a real assignment —
`vector-pii-scrub.test.sh` AC3 derives the allowlist from `LOG_TAG="…"` and is heredoc-blind.

## C — Phase C2: deliver the artifact (the #6539 gate)

**C2.1** Push the tag resolved in C0.3 → `build-inngest-bootstrap-image.yml` builds from that
tag's tree (`hr-tagged-build-workflow-needs-initial-tag-push`).

**C2.2** Resolve the published digest; verify from ≥2 independent sources.

**C2.3** Bump all four sites per C1.3. A tag bump with a stale digest silently boots old bytes.

**C2.4 Assert the pinned image matches the tree — by `diff`, not `grep`.** The Dockerfile does
a verbatim `cp` of `inngest-bootstrap.sh`, so byte-equality is available and strictly stronger
than a substring grep (which passes on any image containing the string, including a stale one):
```bash
docker create --name pinverify "$IREF"
docker cp pinverify:/inngest-bootstrap.sh - | tar -xOf - \
  | diff - apps/web-platform/infra/inngest-bootstrap.sh
docker rm pinverify
```
Note `tar -xOf -` (not bare `tar -xO`, which relies on GNU tar's default archive being stdin)
and the explicit `docker rm` so a re-run does not collide on the container name.

**C2.5** Promote C2.4 into `cloud-init-inngest-bootstrap.test.sh` as a **permanent** gate, and
add a **cross-file** pin assertion. Existing AC6b (`PIN_REF_COUNT == 2 && DISTINCT_PINS == 1`)
binds to `cloud-init.yml` only, so a dedicated-only bump leaves it **green while the two hosts
diverge** — the #6539 class recreated inside the fix for #6539. A one-shot manual gate also
lapses on any later review commit; only the CI form holds.

## C — Phase C3: ADR-100 amendment

Record the three-step delivery invariant (tag → digest pin bump → replace dispatch).

> The amendment explains *why*; **C2.5 enforces it.** The invariant is already documented in
> three places (ADR-100 Amendment 6b, a learning file, a `cloud-init` comment) and #6539
> happened anyway. A fourth prose copy is not a mitigation.

## C — Phase C4: post-merge delivery (dark-window dispatch)

**Automation-feasible; not an operator step.** Dispatched via `gh` CLI from the session.

**C4.1 — gate and blast radius, stated once, here.** Verify `INNGEST_HEARTBEAT_URL` absent from
the `soleur-inngest/prd` config (the **direct** check) **and** #6348 unmerged (corroborating).
If #6348 unmerged: **zero prod cron impact — proceed.** If merged: **STOP**; the window is no
longer free, re-plan against the maintenance-window process. Note #6348 is draft + MERGEABLE,
i.e. one toggle away — this is a real race, and it is why PR B (which needs no window) carries
the H4 answer.

**C4.2** `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason="deliver #6617 liveness discriminators (dark window)"`

**C4.3 — what survives and what does not.** Preserved: `hcloud_volume.inngest_redis` (absent
from the replace allow-set, with a named `redis_volume_destroyed` backstop re-asserted
post-apply) and the private IP (`network.tf:75-80` pins it). **Destroyed with the root disk:**
`/var/lib/inngest` (the `--sqlite-dir`; fail-safe-only on a durable host) and
`/var/lock/inngest-cutover-flip.state` (the flip-FSM state slot) — confirm the FSM tolerates a
cold slot before dispatching. `hcloud_firewall_attachment.inngest` is transiently stale
post-replace; **correcting v1**, no automated path reconciles it —
`scheduled-terraform-drift.yml:100` is plan-only and the operator full apply is PROSE-ONLY
(#6730). Expect a **persistent drift exit-2** until then; security exposure is genuinely low
(Redis binds loopback; host-local nftables drops 8288/8289 from non-web sources independent of
the hcloud firewall), but the poisoned drift signal is a real cost.

**C4.4 — timing and failure branches**, so a polling agent can tell "not yet" from "failed":
- First probe row expected **~90 s post-boot** (`OnBootSec=90s`), hourly thereafter.
- **Absence at T+10 min is a real failure**, not impatience.
- On absence, read the **Vector-independent** `inngest-boot-phone-home.sh` channel — same source table, distinguishes "host silent" from "shipper down".
- A slow replace can push the row past the ~40 min hot window: queries **must** include the s3 archive arm.
- **Rollback:** re-pin to the C0.4 digest and re-dispatch.

**C4.5** Enroll the delivery gate in `scripts/followthroughs/` with the
`<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive and the
`follow-through` label. v1 declined this by borrowing the §2.9.1 soak reasoning; that is right
for the *soak* (owned by #6178) and wrong for the *delivery* gate, which is unambiguously this
plan's own, is post-merge, and is the step most likely to be forgotten — leaving
merged-but-undelivered code in exactly the #6539/#6702 state.

**C4.6** File the root-debt issue: the dedicated host has **no in-place redelivery channel**.
`ci-deploy.sh:2758-2891` implements exactly that for the web host (`docker pull` → `create` →
`cp` → run, via the deploy webhook), and `cloud-init.yml:695` documents it. The dedicated host
was extracted from the web host without carrying it, which is why every future observability
change costs a replace of the sole scheduler. An HMAC webhook violates neither of ADR-100's
load-bearing constraints (cloud-init-only/no `remote-exec`; no inngest cred as a
`github_actions_secret`). Out of scope here; tracked.

## C — Acceptance Criteria

### Pre-merge

- **C-AC1** — The `PROBESCRIPTEOF` heredoc (`:459-520`) emits `sdk_url=`, `backend_is_prod=`, `registry_count=` in the **same** `logger` call as the existing fields, and the second-channel call at `:517` mirrors all three.
- **C-AC2** — `backend_is_prod` derives from the flip-guard state file. The probe body contains **no** `/proc` read and **no** reference to `INNGEST_POSTGRES_URI`.
- **C-AC3** — The flip-guard writes the state file and still never echoes the URI (AC-NOBODY preserved); asserted via its existing `GUARD_POSTGRES_URI` fixture seam, both prod-marker and dark-ref cases.
- **C-AC4** — Scoped to `:459-520`: exactly one `logger -t "$LOG_TAG"` call, no `if` preceding it, zero Doppler invocations. *(Whole-file greps return 2 and 35 — the ACs must scope to the heredoc, which `inngest.test.sh:527`'s existing extraction helper supports.)*
- **C-AC5** — `vector.toml` Source 4 still contains `"inngest-server-probe"` and `"inngest-server-flip-guard"`. *(Assert tag presence, not array length — 21 is a magic number and the file's header comment already drifted to "14 known tags".)*
- **C-AC6** — All four pin sites carry the new version, asserted **across files**: `grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' <four sites> | sort -u | wc -l` equals the intended distinct count.
- **C-AC7** — The pinned image's `inngest-bootstrap.sh` is **byte-identical** to the repo tree (C2.4 `diff`), enforced as a **permanent** test.
- **C-AC8** — The pinned digest's script is byte-identical to **merged `main`** at merge time, not merely to the tag's tree. *(A review commit after C2.1 otherwise leaves the pin carrying superseded bytes, which C-AC-D3 cannot catch because the pin itself is what is stale.)*
- **C-AC9** — Full infra suite green, including `journald-config.test.sh`, `vector-pii-scrub.test.sh`, `cloud-init-inngest-bootstrap.test.sh` — the orphan suites exercised only by a full run.

### Post-merge (delivery gate)

- **C-AC-D1** — After the replace, a `SOLEUR_INNGEST_SERVER_PROBE` row appears from the dedicated host, queried **with the archive arm**, within the C4.4 timing envelope.
- **C-AC-D2** — That row carries `backend_is_prod` in `{yes,no}` — **not** `stale` or `unknown`. *(A degraded field must not satisfy the gate.)*
- **C-AC-D3** — That row's `image_ref` equals the pinned `IREF` — proves the replace booted the intended bytes, not a stale pin.
- **C-AC-D4** — `sdk_url` and `registry_count` are non-`unknown`.

### #6617 close-condition

Close **only** when C-AC-D1..D4 hold, **and** PR B's probe results are recorded, **and** the H4
verdict is written to #6617 from a measured row.

Branches: `backend_is_prod=yes`, or a non-empty doublefire result → **do not close**, escalate
to a double-scheduler incident. `stale`/`unknown` → **do not close**; H4 remains unanswered and
the state-file path needs fixing.

Use **`Ref #6617`** in all three PR bodies — the close-condition is a post-merge replace, not a
merge. `Closes #6295` in PR A is correct: that fix is effective at merge.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INNGEST_SERVER_PROBE — extended with sdk_url=, backend_is_prod=, registry_count="
  cadence: "hourly (OnUnitActiveSec=1h) + OnBootSec=90s"
  alert_target: "Better Stack (journald -> Vector Source 4 -> [sinks.betterstack])"
  configured_in: "apps/web-platform/infra/inngest-bootstrap.sh PROBESCRIPTEOF heredoc; backend boolean sourced from inngest-server-flip-guard.sh; vector.toml Source 4 (both tags already allowlisted)"

error_reporting:
  destination: "journald -> Better Stack; plus the Vector-independent inngest-boot-phone-home.sh direct HTTP ingest on the vector_active != active branch"
  fail_loud: "no — deliberately fail-open per field. Every capture carries `|| true` and degrades to `unknown`; the event itself must ALWAYS emit (ADR-117: no `if` may precede the logger call)."

failure_modes:
  - mode: "Dedicated scheduler dead / not bound to :8288"
    detection: "in-surface: http_code=000 or server_active!=active"
    alert_route: "Better Stack; scheduled-inngest-health.yml covers only the co-located host"
  - mode: "Double-scheduler — dedicated host configured against prod"
    detection: "in-surface: backend_is_prod=yes, sourced from the flip-guard's own computation"
    alert_route: "Better Stack"
  - mode: "Dedicated host has actually executed cron runs"
    detection: "op=doublefire-probe (NO replace required) — the harm itself, not a proxy"
    alert_route: "workflow run summary"
  - mode: "SDK registered functions against the dark host"
    detection: "in-surface: registry_count > 0; on-demand: op=registry-probe"
    alert_route: "Better Stack + workflow summary"
  - mode: "Shared SDK target drifts"
    detection: "in-surface: sdk_url, read from the RUNNING unit's ExecStart argv"
    alert_route: "Better Stack query on sdk_url"
  - mode: "Vector down — marker cannot leave the host"
    detection: "second channel: inngest-boot-phone-home.sh direct HTTP ingest"
    alert_route: "Better Stack, same source table, independent of Vector"
  - mode: "Replace boots a stale image"
    detection: "image_ref vs the pinned IREF"
    alert_route: "C-AC-D3 post-replace; C2.5 permanent gate pre-merge"

logs:
  where: "Better Stack, source soleur-inngest-vector-prd (table soleur_inngest_vector_prd_3)"
  retention: "hot window ~40 min via remote(); full span via the s3 archive arm — queries MUST include the archive arm"

# PR A+B contract (CURRENT — this is the block preflight Check 10 parses).
# A+B ship the standalone read-only ops; they do NOT ship the marker fields.
# The post-C command below would return ZERO rows today by construction — the
# plan's own Premise Validation is that the marker is inert on the host — so
# using it as the live test would fail Check 10 for the whole A+B window.
discoverability_test:
  command: "gh run list --workflow cutover-inngest.yml --status success --limit 1 --json conclusion --jq .[0].conclusion"
  expected_output: "success"

# Post-C contract — HISTORICAL ONLY. PR C was CANCELLED by operator decision on
# 2026-07-20 (see the spec's decision-challenges.md follow-on ruling), so the
# marker fields below will never emit and this block must NOT be promoted into
# the block above. Retained verbatim as the record of the contract that was
# designed, not as a pending instruction.
discoverability_test_after_c:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 6h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 5"
  expected_output: "at least one row containing sdk_url=, backend_is_prod= in {yes,no}, registry_count=, and image_ref matching the pinned IREF"
```

### Affected-surface observability (§2.9.2)

The dedicated host is a **blind execution surface** — deny-all-public, and **no SSH on any
automated path** (port 22 is in fact open intra-network: `inngest-nftables.sh` uses
`policy accept` and drops only 8288/8289; CI holds no key for .40, `ci-ssh-key.tf` targets
web-1 only). Every `detection` above is an **in-surface** probe emitted *from* the host, or a
private-net proxy; a runner-side gate cannot observe the running unit's argv or backend.

The fields **discriminate all competing hypotheses in one event**:

| Question | Field |
|---|---|
| Is the scheduler alive? | `server_active`, `http_code` |
| Is it serving the same app? | `sdk_url` |
| Is it pointed at prod? | `backend_is_prod` |
| Does it have functions registered? | `registry_count` |
| Is the shipper or the server dead? | `vector_active`, `redis_active` |
| Never came up, or died later? | `uptime_s`, `boot_id` |
| Which image produced this host? | `image_ref` |

### Soak follow-through (§2.9.1)

The Phase-4 7-day soak stays owned by #6178 — no enrollment for it here. The **delivery** gate
(C4.5) **is** enrolled, because it is this plan's own.

## Downtime & Cutover

> Required by deepen-plan Phase 4.55 — the gate fired on `hcloud_server.inngest` being
> force-replaced. Zero-downtime is the default and must be evaluated before any outage is
> accepted.

### The offline-inducing operation

`apply_target=inngest-host-replace` destroys and recreates `hcloud_server.inngest`
(10.0.1.40). The affected surface is the **dedicated Inngest scheduler** — which, post-cutover,
is the **sole** scheduler for every production cron (ADR-100: exactly-one-instance is enforced
by topology, not a runtime role-guard).

### Zero-downtime paths evaluated

| Path | Verdict |
|---|---|
| **Blue-green** (provision a second host, drain, cut over, retire) | **Architecturally forbidden.** Two live Inngest hosts on the same backend *is* the double-scheduler condition this entire work exists to detect. OSS Inngest v1.x is single-writer; ADR-100 Context records that two servers on one Postgres double-fire every cron. Blue-green would manufacture the exact harm. |
| **Rolling** | **Not applicable.** Singleton by design; there is no second replica to roll through. |
| **In-place redelivery** (the web host's `ci-deploy.sh:2758-2891` docker-cp channel) | **Correct long-term answer, and unavailable today.** The dedicated host was extracted from the web host without carrying that channel. Building it is real work and touches the sole scheduler's boot path during a held cutover. Filed as C4.6; it is what would make this class of change zero-downtime permanently. |
| **`terraform state mv` / state-only re-address** | **Not applicable.** The change is to the host's *contents* (the bootstrap script baked into its image), not its address. No state-only operation delivers new bytes. |
| **`lifecycle.ignore_changes = [user_data]` + live patch** | **Rejected.** Would decouple the host from its declared config permanently and defeat the clean replace-to-reprovision path `inngest-host.tf` deliberately preserves — trading a bounded one-time outage for unbounded drift on the sole scheduler. |

### Residual downtime: accepted, and why it is not user-facing

**Downtime accepted:** the dedicated scheduler is offline for one boot cycle.

**Justification — the surface is not serving, and that is proven by measurement, not asserted.**
The host measured `url_present=no` today (`inngest-heartbeat` dark-arm rows at 08:11:45Z and
08:12:46Z), meaning `INNGEST_HEARTBEAT_URL` is unprovisioned and the host is pre-arm. Production
crons are served by the **co-located** scheduler throughout — `CUTOVER_HOSTS: "10.0.1.10"`.
**Prod cron impact: zero.**

**Bounded window:** one Hetzner server create + cloud-init boot. C4.4 sets the observation
envelope — first probe row at ~90 s post-boot, absence at T+10 min is a real failure.

**The window is conditional and expiring.** It is free *only* while the host is dark. C4.1
hard-stops on two signals: `INNGEST_HEARTBEAT_URL` absent (direct) and #6348 unmerged
(corroborating). #6348 is draft + MERGEABLE — one toggle from landing. If it merges first, this
stops being a free window and becomes a real maintenance window requiring operator sign-off.

**Structural mitigation:** H4's answer does **not** depend on this replace. PR B answers the
double-scheduler question with no outage at all. If the window closes before PR C lands, the
plan's primary question is already settled and only the continuous signal is deferred.

**Rollback:** re-pin to the C0.4 digest and re-dispatch (C4.4).

**Operator sign-off:** not required while the measured dark condition holds — there is no
serving surface to take offline. Required if C4.1's gate fails, at which point the plan
re-plans rather than proceeding.

## Infrastructure (IaC)

### Terraform changes

**None.** No `.tf` file is edited; `inngest-host.tf` is untouched. No new variable, secret,
`TF_VAR_*`, vendor account, or credential mint.

### Apply path

**(c) taint + scoped `-replace`** — `apply_target=inngest-host-replace`, dispatched via `gh`.
Verified there is genuinely no in-place path **for this host**: no `bootcmd`, no
`scripts-per-boot`, no updater timer; the `docker pull` at `cloud-init-inngest.yml:397` is
inside `runcmd:` (first boot only); `push-infra-config.sh` resolves to web-1; zero Terraform
provisioners target `hcloud_server.inngest`; both webhooks reaching .40 are read-only GraphQL
POSTs.

**The "prefer an implementation that does not touch user_data" instruction is honoured where it
can be:** PR B answers H4 with **no** replace. PR C's field delivery cannot avoid one — the
marker runs inside the host, the only install channel is a boot from a new image, and the image
is named by the digest in `user_data`. C4.6 files the root debt (the missing in-place
redelivery channel that the web host has and this host does not).

**Marginal cost, with its condition stated.** The host must be replaced anyway to receive
#6702's marker, so doing the fields now means **one** replace rather than two. That argument is
sound on its own axis — both pins are equally un-booted and probe fields are fail-open — but it
is **conditional on beating #6348**, which is draft + MERGEABLE. If #6348 lands first, PR C is
stranded merged-but-undelivered. That risk is why H4's answer lives in PR B.

### Distinctness / drift safeguards

Covered in C4.3 (preserved vs destroyed, and the corrected firewall-attachment claim).
**#6608** rides along benignly — merged, inert until a replace, and narrows the nft allowlist to
{.10} now that .11 is destroyed (#6538). It is **not** closed here; it needs its own
post-replace verification. **#6197 does not ride along — it is CLOSED and already rendered.**

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — sign-off required)

### Engineering / CTO
**Status:** reviewed. Infrastructure observability on a blind execution surface. No new service,
dependency, schema, or vendor. Principal risk is artifact-vs-source drift (#6539), now addressed
by a permanent CI gate (C2.5) rather than prose. CTO's structural finding — pin surface is four
sites and the existing guard binds to the wrong file — is folded in as C1.3 + C-AC6.

### Product / CPO
**Status:** reviewed. **APPROVE WITH CONDITIONS.** C1-C6 applied: artifact named
(`cron-email-ingress-probe.ts`, statutory-deadline notice), `Beta users: 0` stated as the tier
premise with its expiry, the missing dedupe guard recorded, post-cutover timing corrected,
rollback defined (C0.4 + C4.4), and the PR split so `registry-probe` cannot threaten the window.
Companion issue for cron send-path idempotency filed separately, not folded in.

### Product/UX Gate
**Tier: NONE.** No file in any `Files to Edit` matches the UI-surface glob superset.

### GDPR / Compliance
Invoked on threshold trigger (b). The canonical regulated-data regex does **not** match. The
compliance surface is **credential leakage**, not personal data: #6295's project-ref leak into a
run log, closed by PR A. v2 additionally *removes* a credential-exposure surface v1 would have
introduced (the `/proc/<pid>/environ` read). No Article 30 entry — no new processing activity.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Replace boots a stale image (#6539, measured) | C2.4 byte-`diff` + C-AC-D3 + the C2.5 permanent gate. `-replace` force-replaces regardless of the `user_data` diff, so the pin bump does **not** gate this path — which is why the content check must be mechanical, not a one-shot manual step. |
| Tag push reds `main` before merge | Expected and documented (C1.3); all four sites bumped in the same PR. |
| Pin bumped on one host only; guard stays green while hosts diverge | C1.3 + C-AC6 assert **across** files. |
| Review commits after the tag push leave the pin stale | C-AC8 compares the pinned script to merged `main`. |
| Window stops being free (#6348 merges) | C4.1 hard-stops on the direct signal. Mitigated structurally: H4's answer lives in PR B, which needs no window. |
| Replace fails or the host boots silent | C4.4 timing envelope + second-channel fallback + C0.4 rollback digest. |
| Flip-guard state file is stale from a prior boot | `backend_is_prod=stale` is an explicit value; C-AC-D2 refuses to pass on it. |
| Scrub rule over-redacts and blinds diagnostics | A-AC2 control, fed through a real call site. |
| Flip-FSM state slot destroyed with the root disk | C4.3 requires confirming the FSM tolerates a cold slot before dispatch. |
| Firewall attachment left stale, poisoning drift | C4.3 states the true position; no false claim of automatic reconciliation. |
| A new op trips a counting assertion | B3 enumerates all four with line numbers; B4 files the issue. |
| Recording an H4 verdict before measuring it | H4 held UNKNOWN; the close-condition branches on all four values. |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| `backend_sha8` cross-host hash read from `/proc/<pid>/environ` (**v1**) | **Rejected on four counts:** it excluded the only discriminating field (the ref lives in the user field) so prd and dark would hash identically → false escalation; it needed a co-located comparand no phase wrote; it contradicted `inngest-bootstrap.sh:725-727` and `bash-sandbox.test.ts:16-18`; and its pid resolution was unspecified and unverifiable pre-replace. |
| Derive the boolean from the flip-guard, which already computes it | **Adopted.** No `/proc` read, no DSN in the probe, no pid resolution; reuses the `image_ref` state-file pattern #6702 established. |
| A `dev\|prd` enum needing the ref baked in | **Adopted**, contra v1. The ref is a documented NON-secret identifier already in `inngest.tf`, and the flip-guard already uses exactly this test. |
| Reuse the `inngest-heartbeat` minute timer as carrier (as requested) | **Rejected.** #6617b deliberately removed per-minute rows for Better Stack quota; the hourly `inngest-server-probe` unit already exists and is the right carrier. |
| Author a new marker rather than extend #6702's | **Rejected.** Two overlapping positive controls and a second allowlist entry. |
| Ship all four deliverables in one PR (**v1**) | **Rejected.** Three delivery channels, two contradictory close semantics in one body, and a credential-leak fix stuck behind an OCI build. |
| Answer H4 only after the replace (**v1**) | **Rejected.** `doublefire-probe` already exists and answers it with no replace; coupling diagnosis to a prod replace was v1's largest unforced risk. |
| ADR amendment as the delivery-invariant enforcement | **Insufficient alone.** Already in prose three times; #6539 happened anyway. Kept for the *why*; C2.5 enforces. |
| Give the dedicated host an in-place redelivery channel (the web host's `ci-deploy.sh` pattern) | **Out of scope, tracked (C4.6).** The correct long-term fix; too large for a held-cutover week. |
| Extract `_pf_scrub` into a shared library | **Deferred** with a filed issue and a named upgrade trigger; A1's permanent identity test converts drift from silent to mechanical. |
| Have the runner reach 10.0.1.40 directly | **Impossible.** Deny-all-public + nftables scoped to web-host private IPs (SEC-H2). |

## Test Scenarios

1. Probe emits all fields in one line with `curl`/`systemctl` stubbed (extends `inngest.test.sh` §A4's hermetic harness).
2. `inngest-server` down → `server_active=inactive`, `http_code=000`, event still emits.
3. State file absent → `backend_is_prod=unknown`, event still emits.
4. State file from a previous `boot_id` → `stale`, distinct from `unknown`.
5. Flip-guard fixture with the prod marker → state file says true → `yes`; with the dark ref → `no`; **and the URI never appears** in either the guard's log line or the state file.
6. `_pf_scrub` libpq form → synthetic ref absent from stdout and stderr.
7. `_pf_scrub` diagnostic error text through a real call site → survives intact.
8. `_pf_scrub` lone `host=` with no sibling keyword → not redacted.
9. `_pf_scrub` URI / `@` forms → still redacted.
10. Three `_pf_scrub` bodies pairwise byte-identical (permanent).
11. `cutover-inngest.yml` shape: both ops in enum + case arms, single `inputs.op` reference, curl/`--max-time` parity, `environment:` unchanged.
12. Pinned image's `inngest-bootstrap.sh` byte-equals the repo tree (permanent).
13. Cross-file pin equality across all four sites.
14. Two-sided allowlist assertion green (`journald-config.test.sh:280` unit side / `:288` vector side).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **The Supabase project ref lives in the DSN's USER field** (`postgres.<ref>@host/db`), not the host or dbname. Any discriminator computed over host+dbname is identical between prd and dark — it reports "different backends" for two schedulers on the same one, and the wrong answer is the reassuring one. This is what v1 drafted; three reviewers caught it independently.
- **`/proc/<pid>/environ` is a declared confidentiality boundary in this repo, not a data source.** `inngest-bootstrap.sh:725-727` rests the whole secrets design on its unreadability (#5560), and `bash-sandbox.test.ts:16-18` treats reading it as a credential-exfiltration signature. If a value is needed from it, derive it from the component already inside that env instead.
- **A tag push reds `main` immediately.** Git tags are repo-global and `cloud-init-inngest-bootstrap.test.sh:234` asserts the **web** pin against the semver-max published tag — so pushing `vinngest-v*` fails CI on `main` until the pin PR merges. Bump both hosts in the same PR.
- **The pin surface is four sites across three files**, and AC6b binds to `cloud-init.yml` only — a dedicated-only bump stays green while the two hosts diverge onto different bootstrap images.
- **`-replace` ignores the `user_data` diff.** "The pin bump triggers the replace" is true for a normal apply and false for `apply_target=inngest-host-replace`. A replace from a stale pin ships nothing and spends the window (#6539).
- **Markers never transit `_pf_scrub`** — they go through `_pf_sanitize` (`inngest-registry-probe.sh:56-59`), which shares no regex with it. Every real `_pf_scrub` call site is GraphQL `errors[].message` text. A scrub control built from a marker string tests a path that cannot occur and passes regardless.
- **`vector-pii-scrub.test.sh` AC3 is heredoc-blind** and derives the allowlist from `LOG_TAG="…"` assignments. Converting a tag to an inline literal drops it from EXPECTED, and AC3's failure text will instruct the engineer to delete the `vector.toml` entry — re-creating #6536 through the guard's own message.
- **`cutover-inngest-workflow.test.sh` pins four character counts**, one holding only because two conditionals open with `(`. It asserts a syntactic accident; B4 files the issue.
- **Whole-file greps on `inngest-bootstrap.sh` are wrong for probe ACs** — `logger -t "$LOG_TAG"` returns 2 and `doppler` returns 35. Scope to `:459-520`.
- **`registry-probe` already appears 10× in `cutover-inngest.yml`** as the hook name `inngest-registry-probe`. Unanchored greps false-pass.
- **"The next drift apply reconciles it" is not true here.** `scheduled-terraform-drift.yml` is plan-only and the operator full apply is PROSE-ONLY (#6730). Do not write mitigations that depend on an apply nothing performs.
- **Verify an issue's state before claiming a ride-along.** v1 asserted #6197 rides along and encoded it in an AC; #6197 closed 2026-07-18 and its change is already on the host.
- **`Ref #6617`, not `Closes`.** The close-condition is a post-merge replace. `Closes #6295` in PR A is correct.
- **Do not record an H4 verdict before reading a probe row.** The instrument exists to test it.
- **An AC that greps for a forbidden literal must not spell that literal** — writing the banned command string into an AC trips the repo's IaC-routing PreToolUse hook and blocks the plan write. Describe the prohibition; let `/work` own the pattern. v1 hit this once.
