---
title: "arch(registry): decide whether zot_last_err should route through redact() on the SOLEUR_ZOT_DISK path"
date: 2026-09-08
slug: arch-zot-last-err-redact-decision
branch: feat-one-shot-7500-zot-last-err-redact
issue: 7500
closes: 7500
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The `soleur-registry` host emits two independent telemetry streams into the same Better Stack Logs
source. One of them — the `zot-log-shipper.sh` channel — applies a structural, fail-closed header
allowlist before egress. The other — the pre-existing `SOLEUR_ZOT_DISK` disk-pressure reporter —
carries a bounded free-text sample of zot's own log output in its trailing `zot_last_err` field, and
that sample reaches the same destination having passed through payload-integrity sanitization only.

This plan settles, and records as an architecture decision, whether that second stream should adopt
the first one's redaction posture, adopt a narrower one, or deliberately keep the one it has.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the issue cites by number was probed. `#7444` is **MERGED** (2026-08-12T19:38:21Z,
closing `#7440`), so the disclosure correction it carries is live on `main` and this plan builds on
the corrected text rather than the original. `#6122` is open (the parent registry-migration epic),
`#6244` closed. `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` exists and its row 2
carries blocker **B2**, the referral that produced this issue. `ADR-185` exists as
`ADR-185-registry-userdata-headroom-policy.md`. `scripts/lib/zot-telemetry-parse.sh` and
`apps/web-platform/infra/cloud-init-registry.yml` both exist. **No premise was stale, but one cited
FIGURE was** — see the budget correction below.

Mechanism-vs-ADR check: the proposed mechanism ("route the diagnostic sample through the shipper's
`redact()`") was grepped against the ADR corpus. `ADR-184` (the shipper) *establishes* `redact()` and
scopes it explicitly to its own emitter; it does not consider and does not reject extending it. So
this is an unconsidered extension, not a rejected alternative.

### Property List (Phase 0.6b)

The issue proposes a mechanism. Restated as the properties underneath it:

- **P1.** A credential-shaped value present in zot's logs does not leave the host in the clear.
- **P2.** The disk-pressure signal (`pcent`, `fs_size_gb`, `zot_restarts`, `oom_kills`, …) survives
  every failure mode of whatever control satisfies P1.
- **P3.** What the controller *discloses* about this path is true of the path, at the scope claimed.
- **P4.** A crafted log line still cannot spoof the verdict fields downstream consumers key on.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Already covered by |
|---|---|---|
| A new `zot_last_err_redacted=` boolean field | P3 (tell the reader the field was scrubbed) | **`zot_last_err_src` already exists** and is already an enum tagging the sample's provenance (`panic\|error\|warn\|fallback\|none`). A new value is a one-token extension of a field the row already carries; a new field is not needed. Cut. |
| A new shared `write_files` entry holding `redact()`, sourced by both scripts | "single-source the redactor" | Cut on measurement, not taste — see the byte table below. Extraction saves **nothing** (gzip already dedupes the duplicate to +64 B) while adding a file, a path, and a boot-time sourcing dependency on a host with **no in-place execution path** (ADR-096). |
| Extending the decision to `SOLEUR_PRIVATE_NIC`'s `zot_last_err=$NIC_ADDRS` | P1 on the sibling row | Cut: that payload is `ip -4 -o addr show` output — the host's own interface CIDRs. Infrastructure metadata, not request-derived content. No credential or client data can reach it. |

### The budget is NOT the binding constraint — measured, and the issue's figure is stale

The issue frames cost as tight ("ADR-185: 8,000 B headroom … 13,136 B stored"). Measured against the
repo's own instrument, `apps/web-platform/infra/registry-userdata-budget.sh --json`:

| Reading | Value |
|---|---|
| Current stored | **13,692 B** (the issue's 13,136 B is stale by 556 B) |
| `HETZNER_CAP` | 32,768 B |
| `REGISTRY_GZIP_BUDGET` (the operative ceiling) | 20,000 B |
| Room to the budget ceiling | **6,308 B** |

`REGISTRY_GZIP_BUDGET = 20_000` is read from `plugins/soleur/test/cloud-init-user-data-size.test.ts`,
the enforcing gate — not from the ADR's prose. ADR-185's own Consequences section agrees: "Registry
`user_data` may grow to just under **20,000 B stored**." The "8,000 B" in the issue is the *headroom
policy floor*, not the growth allowance, and reading it as the allowance is what makes the budget
look binding when it is not.

**Each option was then measured by inserting it and re-running the same script:**

| Option | Stored | Delta |
|---|---|---|
| Baseline | 13,692 B | — |
| **Tier gate only** (suppress the raw sample on the `fallback` tier) | 13,732 B | **+40 B** |
| Narrow header-shaped scrub (sed rule only) | 13,736 B | **+44 B** |
| Full `redact()` + both constants duplicated into the heartbeat | 13,756 B | **+64 B** |

The tier-gate row was added after review, which correctly pointed out that omitting it left the one
option the plan calls "the best ratio on offer" unmeasured while every rejected option had a number.

**The full structural redactor costs 20 bytes more than the narrow scrub, against 6,308 B of room.**
gzip deduplicates the near-identical block against the copy already in the file, which is why
duplication is nearly free and why extraction into a shared file would save nothing. The cost axis
cannot decide this issue; it must be decided on coverage.

### `redact()` behaviour on real heartbeat inputs — executed, not reasoned about

The issue's "Against" argument is that `redact()` fails closed and a dropped row destroys the
disk-pressure signal. I ran the actual function (`jq` 1.8.1) against the shapes the four tiers
produce:

| Input shape | Result |
|---|---|
| Three concatenated JSON rows (the tier-4 `docker logs --tail 3` shape) | **RC=0** — structural allowlist applied to **all three**; `Cookie`/`X-Api-Key`/`Authorization` → `REDACTED`, `Accept` preserved |
| Mixed JSON row + Go panic frames | RC=0 via the non-JSON backstop; `Cookie` redacted — **and this row was MEASURING THE WRONG THING, see below** |
| Pure Go panic (tier 1 — the highest-value diagnostic) | **RC=0, passes through UNCHANGED** |
| Bare plaintext `Cookie: …` | RC=0, redacted |
| Truncated JSON fragment (journald split) | RC=0, redacted |
| `headers` present but NOT an object | **RC=1 → drop** (the only drop *these fixtures* reached — see the correction below; there are three RC=1 paths) |

So the fail-closed drop is reachable but narrow, and the signal the "Against" argument is most
worried about — a crash trace — is the one input `redact()` does not touch at all.

### The probe above had a defect of exactly the class this plan is about — re-measured

Review caught it, and it is confirmed. The mixed-blob row used a `Cookie` fixture. `Cookie` is on
`CRED_HDRS`, i.e. **on the denylist** — so the backstop redacted it and I recorded a success for a
property (the structural allowlist) that was never exercised. Re-run with an *unanticipated* header
name, which is the only fixture that can tell the two branches apart:

| Input shape | `X-Secret` (not on `CRED_HDRS`) | Branch actually taken |
|---|---|---|
| Single JSON line | redacted | JSON / allowlist |
| Three concatenated JSON rows | redacted | JSON / allowlist |
| **Panic frames + a JSON row** (realistic tier-1 and tier-4 blob) | **LEAKS IN THE CLEAR, RC=0** | non-JSON / **denylist** |
| **JSON row + panic frames** | **LEAKS IN THE CLEAR, RC=0** | non-JSON / **denylist** |

`ZOT_ERR_RAW` is **always a multi-line blob** (`head -n 4`, `head -n 3`, `docker logs --tail 3`), and
`redact()` selects its branch over the *whole* argument. So on a mixed blob the allowlist branch is
**unreachable**, and Option 4's headline property — "full structural allowlist, applied at any depth"
— would have been **false for a realistic input** while the plan asserted it and a `Cookie`-only
fixture kept the suite green. That is the #7440 "nominally present, actually inert" defect,
reproduced inside its own fix.

### Where the tier gate sits, and what it does without `jq`

An earlier draft left the tier gate's placement to a comma in a list, and review showed every
placement breaks something different. **Specified here:**

- **The gate runs FIRST, on `ZOT_ERR_RAW`, before `redact()` and before the sanitizer.** After the sanitizer the quotes are gone and `message` is unextractable *always*, which would silently degrade the gate to "blank tier 4 unconditionally" and make the Risks-table mitigation ("emits the parsed `message` rather than nothing") a false statement in the shipped record.
- **Without `jq`, it degrades CLOSED** — emit `none`, never the raw line. `packages:` is documented non-fatal, so a `jq`-less host is reachable; degrading open would restore ~100% of the measured exposure while the ADR records the gate as removing it. Guard 1 row 7 asserts this.
- **It must not route through the existing empty-guard.** The sanitizer line ends `[ -n "$ZOT_LAST_ERR" ] || { ZOT_LAST_ERR=none; ZOT_ERR_SRC=none; }`. If the gate implements suppression by blanking `ZOT_ERR_RAW`, that trailing `||` resets `ZOT_ERR_SRC=fallback` to `none` — **destroying the very tier tag Phase A is being changed to render**, and collapsing the discriminator `registry-boot-guard.test.sh` exists to protect. Set the value directly; leave `ZOT_ERR_SRC` alone.
- **Three states must stay distinguishable**, because all three would otherwise render the literal `none`: (a) no log output at all (`src=none`), (b) tier-4 suppressed by the gate (`src` **stays** `fallback`), (c) redaction failure (`src` carries `redact_failed`).

### `zot_last_err_src` carries provenance; redaction outcome is a separate dimension

The Cut List rejected a new boolean field because `zot_last_err_src` "already exists". Review is right
that this conflates two orthogonal dimensions: the field's documented meaning is *"which tier produced
the text"*, and a bare `redact_failed` value reports **no tier at all** — on exactly the rows where
redaction misbehaved, losing the discriminator Phase A is simultaneously building a consumer for.
`hr-type-widening-cross-consumer-grep` asks whether the widening is type-*coherent*, not merely
whether consumers exist.

**Resolution:** emit a companion token rather than overloading the enum —
`zot_last_err_src=fallback:redact_failed` (tier, then outcome). Costs a handful of bytes against
6,308 B of measured room, keeps the tier enum pure, and keeps both dimensions readable off-box. If the
implementer instead keeps a flat enum, the ADR must record that provenance is **deliberately
discarded** on redaction failure and why that is acceptable.

**Design consequence, now mandatory: `redact()` is applied PER LINE of `ZOT_ERR_RAW`, never once to
the blob.** Per-line is also the shipper's own contract (`redact "$msg"` is called on one journal
line), so this restores parity rather than inventing a new shape. Guard 1 carries dedicated rows for
it, and the property must not be restated in the ADR or the Art. 30 bracket until they pass.

**[CORRECTED after CTO review]** My probe found one RC=1 path; there are **three**. Besides
`error("nonobj headers")`, the non-JSON backstop returns 1 on its **residual refusal**
(`grep -qiE "($CRED_HDRS)\"?[[:space:]]*:[[:space:]]*[^R[:space:]]"`), and the JSON branch returns 1
on **empty output** (`[ -n "$out" ]`). My fixtures simply did not trigger the latter two. This
*strengthens* the adopted option rather than weakening it: **[MIS-ATTRIBUTION CORRECTED after review.]** An earlier draft cited the shipper's comment about the
residual refusal "discard[ing] a panic trace whose credential had in fact been removed" as evidence
that drop semantics are inherently dangerous. Read in full, that was a defect in an **earlier regex**
(`[^R]` backtracking onto the space), **already repaired** in the shipped form, which excludes the
space via `[^R[:space:]]`. The current drop semantics do **not** inherit it. Option 4's case stands on
the other two RC=1 paths, and a guard row for this path must construct a *genuine* residual rather
than replay a fixed bug.

### The dominant cost is ForceNew, not bytes

`hcloud_server.registry` (`apps/web-platform/infra/zot-registry.tf`) carries `user_data` as ForceNew
and **deliberately** no `lifecycle.ignore_changes = [user_data]`. Its own comment: changing the
render shows `-/+ hcloud_server.registry` "in any UNTARGETED plan, which is the operator's full apply
and the 12h drift detector, i.e. the ONLY apply paths these resources have." ADR-096 makes the host
cloud-init-only. **Consequence for this decision: every option that edits the heartbeat costs a
destroy-then-create of the fleet's sole image-pull path, and the narrow scrub costs exactly the same
as the full redactor on that axis.** The `.tf` also carries a live stock table showing `cpx22`
available on every probe but `cx23` flipping NO→YES inside ~4 hours, which is why the recut runbook
demands a re-probe immediately before firing.

### A second egress the issue never mentions

`scripts/zot-restart-loop-alarm.sh` extracts the raw tail —
`last_err="$(printf '%s\n' "$MAIN" | grep -F "boot_id=$NEWEST_BOOT" | tail -1 | sed -n 's/.* zot_last_err=//p' …)"`
— folds it into `CAUSE`, and `.github/workflows/scheduled-zot-restart-loop.yml` publishes `CAUSE`
verbatim through `gh issue create` / `gh issue comment`. **`jikig-ai/soleur` is a PUBLIC repository**
(`gh repo view` → `"visibility":"PUBLIC"`). So an unredacted sample can be auto-published
world-readable and permanent.

This matters more than the warehouse path it was filed about. The issue bounds severity by reasoning
about **ingress** ("`hcloud_firewall.registry` carries zero inbound rules"); that argument bounds who
can *inject* content into zot's logs, not where the sampled content *goes*. And the cloud-init's own
comment records the measurement that closes the loop: across a real 21-hour, 4.4-restarts/min loop,
the field "carried a cause exactly zero times — every sample was an HTTP 200/401 session line or a
gc/dedupe info line." The public-issue egress therefore fires precisely when the field is likeliest
to carry an HTTP row with headers.

### Scope limit that must not be overclaimed

`redact()`'s allowlist covers the **`headers` object** only. The measured zot log line also carries a
**top-level `"clientIP"`** (`apps/web-platform/infra/zot-log-shipper.test.sh` header, measured
against the pinned digest), which `redact()` does not touch. Adopting `redact()` therefore does not
address `clientIP`, and any disclosure must say so — the counsel audit's blocker **B2** was exactly
this class of error (a host-level assurance that was true of the emitter and false of the host).

### Consumer blast radius

`scripts/lib/zot-telemetry-parse.sh`'s `zot_trusted_region()` is `sort | sed 's/ zot_last_err=.*//'`
— it strips the tail before any `key=value` parse so a crafted sample cannot spoof `boot_id=` /
`exit_code=` / `nic_ok=`. **Therefore `zot_last_err` must keep its name and stay the LAST field.**
That logic is duplicated (not sourced) in `scripts/followthroughs/private-nic-converged-6415.sh` and,
deliberately and with a documented reason, reimplemented in Python in
`scripts/followthroughs/zot-fill-rate-7341.sh`.

Consumers that read the value: only `zot-restart-loop-alarm.sh` (for the public issue body). Every
other consumer — `zot-disk-sample.sh`, `registry-heartbeat-poll.sh`,
`registry-replace-preflight.sh`, the inventory marker assertions — treats the row as a presence or
count control and is indifferent to the value.

**[CORRECTED after CTO review]** An earlier draft of this section claimed
`scripts/zot-disk-sample.sh` was a **live** spoof vector because it splits on whitespace with no
trusted-region cut. That is **wrong**, and the correction matters because it was about to size scope
on a defect that does not exist. Its extractor is
`field() { printf '%s\n' "$LINE" | tr ' ' '\n' | awk -F= -v k="$1" '$1==k {print $2; exit}'; }` —
the `exit` makes it **first-wins**, and every genuine field precedes `zot_last_err` in the emitted
`LINE`, so a `key=value`-shaped token in the tail can never win. The file says so itself: "`zot_last_err`
is the marker's LAST field … so a whitespace split reaches every field ahead of it intact." The vector
is **latent**, conditional on a field ever being placed *after* `zot_last_err` — which is exactly what
Guard 1's trailing-field mutation row exists to prevent. The placeholder still carries no `=`, but as
defence against that latent case, not against a present one.

### Institutional learnings that bear on this

- `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`
  — "at the emit boundary" over-generalises when only one boundary carries the transform. This is the
  B2 class and the reason the scope-limit note above is a deliverable, not a nicety.
- `knowledge-base/project/learnings/2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`
  — a pure comment edit in this very file triggers ForceNew; comments cost bytes.
- `knowledge-base/project/learnings/2026-07-29-a-per-producer-fix-left-seven-siblings-live-and-four-misread-signals.md`
  — a fix applied at one producer leaves siblings live. Argues for producer-side defence.
- `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md` and
  `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — the mutation matrix must be derived from the design and must be able to redden.
- `knowledge-base/project/learnings/2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test.md`
  — assert on the bytes leaving the process, never on a stub's internal consistency.

### Test precedent — no live host required

`apps/web-platform/infra/zot-log-shipper.test.sh` is the template, and it is explicit about the trap:
`local.registry_rationale_strip` is `"/(?m)^[ \t]*#([ \t][^\n]*)?\n/"`, a **blanket whole-line comment
strip that reaches INSIDE `write_files` heredocs**, so any `#`-leading line is deleted from what the
host actually runs while surviving in the repo file a naive test reads. That suite applies the strip,
asserts the result is still valid bash, and then **executes** the script against synthesized PATH
stubs — no host, no network, no docker, no doppler, no root — with paired non-vacuity positive
controls. `apps/web-platform/infra/registry-boot-guard.test.sh` already extracts this file's
`SOLEUR_ZOT_DISK` field set and asserts `zot_last_err` is last.

### Baselines recorded before any edit

- `bash plugins/soleur/test/c4-count-parity.test.sh` → **10 passed, 0 failed** (green baseline; the
  gate is at `plugins/soleur/test/`, not the `apps/web-platform/test/` path the plan skill names).
- Open `code-review` issues touching any planned file: **none** (64 open, zero matches).
- `ADR-211` was probed free across all 76 `origin/*` refs. **No longer needed** — the decision is an
  amendment to `ADR-184`, so this plan claims no new ordinal and carries no collision risk.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for
this branch; the default is also substantively correct, since Engineering, Legal and Product all
returned findings that changed the design.

## Research Reconciliation — Issue Claims vs. Codebase

| Issue claim | Reality (measured this session) | Plan response |
|---|---|---|
| "ADR-185: 8,000 B headroom … the registry payload is currently 13,136 B stored" — framed as a binding constraint | 8,000 B is the headroom **policy floor**, not the growth allowance. The operative ceiling is `REGISTRY_GZIP_BUDGET = 20_000`. Stored measures **13,692 B**, leaving **6,308 B**. Both options cost < 1.1% of that. | Carry the corrected figures into the ADR. Cost is explicitly recorded as **not** a decision input. |
| "Both `user_data` cost and the ForceNew cap constrain any change here" | ForceNew constrains it — but it constrains **every** option identically, so it cannot discriminate between them. `user_data` cost does not constrain it at all. | The ADR separates the two: ForceNew governs *delivery sequencing*, not *option choice*. |
| "Third option: a narrower scrub … rather than the full structural redactor" (framed as the cheaper option) | Narrow = +44 B, full = +64 B. The narrow option's advantage is **20 bytes**. Its disadvantage is that a header-name denylist fails silently on an unanticipated header. | Option 3 is rejected on coverage, and the rejection records that its supposed cost advantage was measured and is negligible. |
| "`redact()` … means a row that cannot be redacted is *dropped*" | True of the shipper, where the row **is** the sample. On the heartbeat the row carries 27 fields and the sample is one of them — so "drop the row" is a design choice, not a property of `redact()`. Measured: 5 of 6 realistic shapes return RC=0, and a Go panic passes through untouched. | Option 4 keeps the redactor and discards only the drop semantics. |
| "`hcloud_firewall.registry` carries zero inbound rules … bounding context" | Correct, and it bounds **ingress**. It does not bound **egress**, and an egress to a **public GitHub issue** exists. | The public-egress path is recorded in the ADR as a co-equal motivation and gets its own control. |

## Open Code-Review Overlap

**None.** 64 open `code-review` issues were queried; zero name any file this plan edits.

## The Decision

### Options weighed

| # | Option | Buys P1 (credential containment) | Buys P2 (disk signal survives) | Stored cost | Verdict |
|---|---|---|---|---|---|
| 1 | Leave as-is | No | Yes | 0 B | **Rejected** — the public-issue egress makes the status quo indefensible independently of the warehouse path the issue was filed about. |
| 2 | Duplicate `redact()`, keep its drop semantics | Yes | **No** — a non-object `headers` sample discards all 26 other fields | +64 B | **Rejected** — trades P2 for P1 when nothing requires the trade. |
| 3 | Narrow header-shaped scrub | Partially — a **denylist** of five header names; silent on any header not anticipated | Yes | +44 B | **Rejected** — buys 20 bytes and gives up the one property (allowlist-by-construction) that makes the sibling emitter defensible. |
| 4 | **Share `redact()`, discard its drop semantics** — on RC=1 set the field to a fixed placeholder and `zot_last_err_src=redact_failed`, ship all other fields | **Yes** — full structural allowlist, applied at any depth | **Yes** — the row is never dropped | +64 B | **ADOPTED** |

**Option 1 is rejected on measurement, not on argument.** The tempting defence of the status quo is
that `head -c 300` already truncates the sample before a header value could survive. Measured against
the real zerolog shape (the one `zot-log-shipper.test.sh` records as measured against the pinned
digest), pushed through the heartbeat's exact sanitizer chain
(`tr '\n\r\t' ' ' | LC_ALL=C tr -cd '\40-\176' | tr -d '"\\'`):

| Token | Offset in the stripped line |
|---|---|
| `clientIP:` | 92 |
| `headers:` | 177 |
| `Cookie:` | 199 |
| the credential value itself | **212** |

Total stripped length 308. **Everything that matters lands inside the 300-byte window** — truncation
removes the trailing `caller:` frame, not the header object. The exposure is real, and the #7272
evidence below is the confirmation that it reached a public surface in practice.

A **fifth** option — a tier gate that suppresses the raw sample on the one tier that produces
essentially all of the exposure and none of the diagnostic value — was surfaced by the CTO review and
is adopted **alongside** Option 4. It is written up under "The tier gate" below, after the guard
contracts, because its justification rests on the measured evidence in "The residual is not
prospective".

Option 4 answers the issue's "Against" argument rather than trading against it: the drop semantics, not the redactor, are what threatened the disk-pressure signal, and the two are separable because the heartbeat's row is not its sample.

Three details make Option 4 cheap rather than clever:

1. **`zot_last_err_src` already exists** as an enum tagging the sample's tier (`panic|error|warn|fallback|none`). `redact_failed` is a sixth value on a field the row already carries — no new field, no new parse.
2. **The shipper already has this taxonomy.** Its drop accounting emits `reason=redact_failed` as a distinct bucket precisely because folding redaction failures into a rate-cap bucket "sent an operator to raise a cap that was never the cause". Option 4 reuses that vocabulary rather than inventing one.
3. **`jq` absence degrades safely.** `redact()` selects its branch with `printf … | jq -e …`; if `jq` is missing the condition is false and the **sed backstop** runs, which still redacts the known credential header names and refuses residuals. `jq` is in `packages:` (verified), and `packages:` is documented non-fatal, so this path is reachable and lands in the safe direction.

### Defence at the producer AND at the sink

The controls are not redundant, and the sub-value of each is nameable:

- **Producer-side** (`zot-disk-heartbeat.sh`) is the architecturally correct control: one change covers every current and future consumer of the field. But it **applies nothing at merge** — the host is cloud-init-only (ADR-096) and the change waits for the next provisioning event.
- **Sink-side** (`zot-restart-loop-alarm.sh`) takes effect on the next scheduled run and costs no infrastructure event.

**[CORRECTED — an earlier draft of this section overstated the sink control's unique coverage.]** It claimed the sink control was "the only control that can reach rows already in the warehouse", implying the full 90-day retention. Measured: the alarm reads `--since "$WINDOW"` with `WINDOW="3h"`, so its retroactive reach is **three hours**, not ninety days. That argument is real but small, and it is not what carries the design.

What does carry it, in order of weight:

1. **Disjoint egresses.** Producer-side covers the Better Stack warehouse, which the sink never touches. Sink-side covers the public GitHub issue, which the producer reaches only after the replace. Neither substitutes for the other, at any point in time.
2. **The unbounded interval.** Phase B is inert until the next `registry-host-replace` — which nothing in this plan schedules, and which the recut runbook deliberately gates behind an immediately-pre-fire stock re-probe. That interval could be days or months. For its whole duration the sink control is the **only** control in force on the **worst** surface: the public, permanent, non-retractable one.
3. ~~**The 3-hour tail.**~~ **WITHDRAWN — falsified.** An earlier draft argued the sink control uniquely covers pre-fix rows still inside the alarm's 3h window. Verified against the code: the publishing arm is `grep -F "boot_id=$NEWEST_BOOT"`-scoped, and Phase B is delivered *only* by a destroy-and-recreate, which necessarily produces a **new `boot_id`**. So the instant Phase B exists on the host, every pre-fix row belongs to a strictly older boot and is unreachable by the publishing arm **by construction**. The two controls do not cover disjoint row populations in time at all. Recorded rather than deleted because this justification was destined for an ADR and a legal register, and a wrong recorded reason is the exact failure mode the defence-in-depth learning is about.

So these are **not** mirrored controls at the same threshold — the shape `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate-document-load-bearing-value.md` warns about. They guard different egresses (point 1) over different intervals (point 2).

A fourth argument — that the sink also faces *markdown / `@mention` / link injection* from an attacker-chosen `User-Agent`, which redaction never addresses — is **true but deliberately out of scope here**: it is a different threat model, in a different file, and **no guard in this plan covers it**. Shipping an unguarded change on a third file is the creep the Guard Contract exists to expose. It goes to the capability-gap issue instead.

## Architecture Decision (ADR/C4)

### ADR — mint a new ADR; amend ADR-184 only with a pointer and an Alternatives row

**[REVERSED TWICE. Draft 1 proposed `ADR-211`. Draft 2 switched to an ADR-184 amendment on the CTO's
advice. Architecture review then falsified the premise of draft 2, and it is back to a new ADR — for
a better reason than draft 1 had.]**

**The premise of the amendment plan was factually false, and I verified it rather than taking either
agent's word.** `grep -rn 'redact()\|CRED_HDRS\|HDR_KEEP' knowledge-base/engineering/architecture/decisions/`
returns **zero hits across the entire ADR corpus**. In ADR-184, `redact` appears exactly twice — in
the §3 heading and in one line of prose about anchoring on the stripped shape. **ADR-184 does not
establish `redact()`.** What its §3 actually records is a two-part sanitizer whose credential half is
"one `Authorization` rule" — a **one-name denylist**. The structural allowlist
(`CRED_HDRS`/`HDR_KEEP`/`redact()`) exists only in `cloud-init-registry.yml`, and the only prose
describing it lives in the **legal** artifacts: the counsel audit and the Art. 30 register.

Two consequences, both load-bearing:

1. **Amending "ADR-184's decision about `redact()`" would have amended a decision it never recorded** — the same false-citation class the principles register flags at AP-024 ("a false citation propagates further than a missing one").
2. **ADR-184 is already stale in an undisclosed way.** Its §3 one-`Authorization`-rule denylist was superseded by the allowlist at some later point and no ADR records the transition. Writing an amendment on top of that would paper over the drift — in a plan whose whole thesis is control-vs-description drift.

**Decision: mint a new ADR.** `ADR-211` was re-probed free across all **77** `origin/*` refs this
session; it remains **provisional** and must be re-probed immediately before merge, with a
`grep -rn 'ADR-211' knowledge-base/project/{plans,specs}/` sweep in the same edit if it moves.

The new ADR is also the right *scope*. What this plan decides is not one extension but five
commitments, and only the first is even adjacent to ADR-184's subject (*"the registry host ships
container logs with a self-contained journald shipper, not a Vector agent"*): (1) a header-object
allowlist on a second emitter; (2) that second copy **degrades where the first drops** — a different
control, not an extended one; (3) a **tier gate** discarding tier-4 samples at source; (4) a
**sink-side publication control** in a GitHub Actions alarm script, a different component on a
different plane with no host involvement; (5) duplication over extraction. Folding (4) into a
host-shipper ADR would mean a future reader asking "why does the restart-loop alarm scrub its output?"
greps the ADR corpus and finds nothing at the component in question.

**ADR-184 still gets edited, but only two things:** a **new** Alternatives row for the redaction
question, and a one-line `## Decision` pointer scoping its §3 sanitizer to the shipper and naming the
new ADR as the sibling-emitter authority. **Do not reuse or overwrite** the existing *"Widen the
reporter's `zot_last_err` field"* row — verified, that row rejects widening on **sampler-coverage**
grounds ("Stays a 5-minute sampler … raises the lower bound without producing a count") and has
nothing to do with redaction.

The new ADR must record: the decision; the five options with **measured** rejection reasons
(including Option 3's 20-byte cost advantage and the tier-gate's +40 B); the per-line application
requirement and the measurement that forced it; the ForceNew delivery constraint and the resulting
inertness; the public-issue egress with the #7272 evidence; **AP-021** (diagnostic honesty — the
alarm publishing `gc successfully completed` under "Decoded cause" is a live AP-021 violation on
`main` and its fix is in scope) and **AP-025** (the chokepoint-over-enumeration reasoning behind
Guard 2); and the scope limit below.

**The scope limit is the ADR's most important sentence, because getting it wrong repeats blocker B2.**
`redact()` is an allowlist over the **`headers` object**, **on its JSON branch only**, **applied
per line**. It does not touch the top-level `clientIP`. The sink-side scrub is, structurally and
permanently, a **denylist** — by the time text reaches `emit_and_exit()` the producer's `tr -d '"\\'`
has destroyed the JSON, so allowlist semantics are unavailable there forever. Both facts must appear
in the ADR and in every disclosure derived from it.

**Re-evaluation triggers:** (1) any change admitting public ingress to `hcloud_firewall.registry` —
this converts `clientIP` into Art. 4(1) personal data on a path this decision does not redact, and
per the CLO its consequence is now a candidate **Art. 33** event rather than an Art. 30 currency
correction, because the egress is world-readable; (2) **any operator workstation or human-operated
device admitted to `10.0.1.0/24`** — the RFC1918 conclusion holds because the range contains only
servers, not because the range is private; (3) any new automated path copying a raw telemetry field
into a public surface.

### C4 views

All three model files were read (`model.c4` 691 lines, `views.c4` 74, `spec.c4` 54), and the enumeration the completeness mandate requires:

- **External human actors:** none new. The data subjects would be zot's clients; today those are the platform's own hosts, already modelled as `hetzner` / `inngest`.
- **External systems:** `zotRegistry`, `betterstack` and `github` are all already declared and already included in both the `context` and `containers` view include-lists.
- **Containers / data stores:** none new; no store is added or moved.
- **Access relationships:** no actor↔surface access relationship changes.

**[REVISED after architecture review.]** The element enumeration above holds — but it answered
"does this change *add* an element?" when the completeness mandate asks "does the model *describe the
system*?". Two gaps follow, and the second is the consequential one:

- The **public-issue egress is not modelled anywhere at all.** The only issue-writing edge in `model.c4` is `api -> github` on *connected repos*; there is no edge for a scheduled workflow filing an issue on `jikig-ai/soleur`, and no `github -> founder` edge, so the alarm's entire operator-notification channel is absent.
- Hanging that egress off `github -> betterstack` would put it on a **read** edge — the wrong direction. The write is `github -> github` (Actions runner → issue tracker).

So **one modelled relationship is added**, and the shape is chosen deliberately: a new `#external`
actor `publicReader` plus `github -> publicReader`, because it makes the **recipient set** visible —
which is the thing this plan's entire severity argument turns on, and which a `github -> github`
self-relationship would hide. Note the plan's own Encryption Posture already enumerates "GitHub issue
bodies on the PUBLIC repo" as an `at_rest` store with `defends_against: nothing`; a permanent,
world-readable, zero-protection store belongs in the model. Adding a relationship is a larger
count-parity risk than a description edit, so AC7 must be re-run after this specifically.

The two existing edge descriptions are also falsified and must be amended:

1. `zotRegistry -> betterstack` documents the `SOLEUR_ZOT_LOG` shipper's redaction posture in detail but says nothing about the `SOLEUR_ZOT_DISK` arm's. Amend to record that the heartbeat's sample is redacted by the same allowlist and degrades rather than drops.
2. `github -> betterstack` describes the restart-loop alarm's **read** of `SOLEUR_ZOT_DISK` but not that the polled `zot_last_err` tail is **re-published verbatim into a public GitHub issue**. That omission is exactly the gap this plan closes; amend the description to name the egress and the scrub at `emit_and_exit()`.

`bash plugins/soleur/test/c4-count-parity.test.sh` is **green at baseline (10 passed, 0 failed)** and this change adds no monitor, workflow or heartbeat, so no embedded cardinality moves. The gate must be re-run after the edits regardless — a description edit can disturb a count-bearing sentence.

### Sequencing

The ADR is authored in this PR with `status: adopting`, because the producer-side half is true only after the next provisioning event delivers it. It flips to `accepted` when the post-replace probe reads a redacted sample back out of the warehouse. It is **not** deferred to its own issue.

## The residual is not prospective — it has already fired, and the outcome is measured

The CLO review demanded a search nobody had run: has a sample **already** been published? It has.
Public issue **#7272** (`[ci/zot-restart-loop] …`, opened 2026-08-04, closed 2026-08-10) carries the
alarm's body plus **~20 follow-up comments, each publishing a `zot_last_err` tail**. What actually
reached the public surface:

| Element published | Verdict |
|---|---|
| The `headers` object — **36 occurrences** of `headers:{` | The theorised exposure **did occur**, 36 times, on a world-readable surface. |
| `Authorization` | **23/23 rendered `[******]`** — **zot's own masking held**. No credential in the clear. |
| `Cookie`, `X-Api-Key` | **0 occurrences.** The clients are `curl/8.5.0` doing htpasswd Basic auth; nothing in the estate sends those headers. |
| `clientIP:10.0.1.30:…` — **13 occurrences** | Published publicly. RFC1918, the tunnel connector — a server in the controller's own estate. |

**So: no credential was exposed, and no personal data was exposed.** No breach-register row is
warranted, and the register's "bounded residual" classification is vindicated as a matter of outcome.

But the *reason* it held is the whole argument for acting. The only thing standing between this
mechanism and a published credential was **zot's own masking of one header name** — precisely the
single point of failure the sibling emitter's allowlist exists in order not to depend on. The Art. 30
record already says the backstop is "defence in depth against a future zot that stops [masking]". On
this path there is no backstop at all, and the empirical record is a live mechanism that published
the header object **36 times** and was saved by an upstream default.

It also **confirms the correlation** the CLO predicted: the publishing arm fires only on a **non-OOM
crash-loop**, and in that state the samples are overwhelmingly HTTP-session lines — i.e. exactly the
header-and-`clientIP`-bearing shape. The narrow trigger and the dangerous shape are positively
correlated, not independent.

### Correction to the issue's framing, and to mine

- The public path carries **two sanitizers and zero redactors**. `.github/workflows/scheduled-zot-restart-loop.yml` defines `strip_log_injection()` (`tr -d '\000-\037\177'` plus Unicode-separator removal) and applies it to `cause`. That is control-character hygiene, **not** redaction, and must be named as such so no reader infers a control from its presence.
- Only **one** arm publishes the tail — the non-OOM crash-loop `else` branch. Every other `CAUSE`/`NIC_CAUSE` string is static operator text or interpolates trusted numeric fields.
- `scripts/zot-restart-loop-alarm.sh` carries a **false in-code assurance**: the comment above the extraction reads "surface the **redacted** log tail" while the next statement extracts the raw tail. Fix it in this PR; leaving it while the register newly records the path as unredacted creates code-vs-register drift no gate can catch.

### Ordering is a disclosure requirement, not an implementation detail

The sanitizer runs `tr -d '"\\'`, which deletes every double quote — so a zerolog row that has passed
through it **is no longer parseable JSON**. `redact()` chooses its branch with
`jq -e 'type=="object" or type=="array"'`. Applied **after** the sanitizer, that test fails and the
**non-JSON backstop** runs — and the backstop is a name **DENYLIST** (`CRED_HDRS`) plus residual
refusal, *not* the allowlist. The Art. 30 §(g) prose sells the opposite property ("a name ALLOWLIST …
so a header this codebase has not anticipated is redacted by construction"), which belongs to the
JSON branch alone.

**Therefore `redact()` MUST be applied to the raw zerolog text BEFORE the sanitizer.** Applying it
after would ship denylist semantics while the register advertises allowlist semantics — a live drift
between the described control and the executing one. This is FR2 below, and it carries a dedicated
mutation row because a naive reading of the final string cannot distinguish the two branches.

### Relationship to #7530

Open issue **#7530** enforces the RFC1918 `clientIP` invariant on the **shipper's** structured field
at readback. This plan covers the **reporter's** sampled free-text field. The measurement above adds
a surface **neither** issue currently covers: `clientIP` reaching a **public GitHub issue** via
`zot_last_err`. This plan's sink-side scrub therefore also masks a non-RFC1918 `clientIP` before
publication — a *publication* control, complementary to and not pre-empting #7530's *assertion*
control. Cross-reference both ways; do not close #7530.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — but a botched producer-side edit
strands `soleur-registry`, which is the fleet's **sole container-image pull path**. `user_data` is
ForceNew with no `ignore_changes`, so a render that exceeds the Hetzner cap is rejected by the API
*after* the destroy has already succeeded. Every host's deploy and every image pull stops until the
host is rebuilt. That is the concrete artifact: deploys hang, and the operator's product stops
shipping.

**If this leaks, the user's workflow is exposed via:** a `zot-push` credential published in a public
GitHub issue. Publication confers the ability to **alter** registry contents; an altered image
executes on every host, including the hosts that process end-user data. That is the supply-chain path
from a service-account credential to end users. It has **not** occurred (measured above — zot's
masking held, and no `Cookie`/`X-Api-Key` was ever present), but the mechanism that would carry it
fired twenty times.

**Brand-survival threshold:** `single-user incident` — ruled by the CPO, on the ladder's own text
rather than on a probability estimate. `none` requires "no credential surface", which is false by
construction here; `aggregate pattern` describes realized repeated impact **and** is a gate
downgrade (it adds no CPO sign-off and `user-impact-reviewer` exits immediately on it). Full
reasoning in the Domain Review.

Stated plainly for `user-impact-reviewer`, which needs artifacts and vectors rather than nouns:
the **artifact** is `zot_last_err.headers.Cookie` / `X-Api-Key` / top-level `clientIP` on the
`SOLEUR_ZOT_DISK` row; the **vector** is that tail folded into `CAUSE` and published verbatim into a
public `jikig-ai/soleur` issue body. Roles reachable: the operator; any self-hosting user whose fleet
pulls from a registry built on this cloud-init template; any end user of a platform host running an
image pulled through a compromised registry.

## Encryption Posture

Detection fires on `cloud-init.*\.ya?ml$`. No store and no cross-component connection is added; the
declarations below describe the surfaces this change touches.

```yaml
at_rest:
  - store: registry OCI store volume (/var/lib/zot)
    mechanism: LUKS2 guest-side full-volume encryption (#6895), passphrase in the isolated
      soleur-registry/prd Doppler config, never in user_data
    evidence: apps/web-platform/infra/registry-luks.test.sh; cryptsetup in packages:;
      /usr/local/bin/registry-luks-open.sh + registry-luks-open.service
    defends_against: Hetzner-side disk seizure or volume reattachment while the host is off
    does_not_defend: anything readable on a running host — the volume is open and zot reads it;
      a root-equivalent compromise of the live host reads plaintext
    disclosed_as: Art. 30 PA-8 (g), the registry-plane TOM
    live_verification: bash apps/web-platform/infra/registry-luks.test.sh
  - store: Better Stack Logs source 2457081
    mechanism: vendor-side encryption at rest; no controller-held key
    evidence: vendor attestation only — NOT a controller technical measure, recorded as such
    defends_against: nothing the controller can attest to
    does_not_defend: vendor-side access, and anything the controller ships in the clear —
      which is exactly why the emit-boundary redaction in this plan is the operative control
    disclosed_as: Art. 30 PA-8 (f)/(g); retention measured at 90 days (#7772)
    live_verification: not controller-verifiable; treated as an assumption, not a measure
  - store: GitHub issue bodies on the PUBLIC repo jikig-ai/soleur
    mechanism: plaintext-exception — none, by design; the surface is world-readable
    evidence: gh repo view --json visibility -> "PUBLIC"; measured content in #7272
    defends_against: nothing
    does_not_defend: everything — no retention bound, not retractable (clones, forks,
      GHArchive, search indices survive deletion)
    disclosed_as: to be added to Art. 30 PA-8 (g) by this plan
    live_verification: gh issue view 7272 --json comments
in_transit:
  - connection: zot-disk-heartbeat.sh -> Better Stack Logs ingest
    tls: HTTPS to the eu-fsn-3 ingest endpoint via curl
    cert_verification: on (curl default; no -k / --insecure on the post() call)
    does_not_defend: content shipped in the clear inside the TLS session — TLS protects the
      hop, never the payload's contents from the destination or its operators
    disclosed_as: Art. 30 PA-8 (g)
  - connection: GitHub Actions runner -> GitHub API (gh issue create/comment)
    tls: HTTPS, gh CLI default
    cert_verification: on
    does_not_defend: the destination is a public web page; transport security is irrelevant
      to the exposure this plan addresses
    disclosed_as: to be added to Art. 30 PA-8 (g)
exception:
  - subject: the public GitHub issue surface (plaintext-exception, above)
    justification: the alarm's issue is the operator-facing incident channel and is
      deliberately public; the remedy is to control WHAT is published, not to encrypt the
      channel. This plan implements that control.
    tracking_issue: 7500
    reevaluate_when: any new automated path copies a raw telemetry field into a public surface
    expires_on: 2027-03-08
```

## Observability

```yaml
liveness_signal:
  what: the SOLEUR_ZOT_DISK row itself — 27 fields including zot_last_err_src
  cadence: every 5 minutes
  alert_target: Better Stack Logs source 2457081; absence alarms via the 900s
    betteruptime disk heartbeat and via scheduled-zot-restart-loop.yml's telemetry-silent arm
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (/etc/cron.d/zot-disk-heartbeat)
error_reporting:
  destination: the row itself. A redaction failure is reported IN-BAND as
    zot_last_err_src=redact_failed, queryable off-box with betterstack-query.sh — mirroring the
    shipper's own reason=redact_failed drop bucket.
  fail_loud: yes — a distinct enum value, never folded into an existing one. The row is still
    delivered, so the failure is observable rather than being reported by absence.
failure_modes:
  - mode: redact() cannot structurally redact a sample (non-object headers)
    detection: count of rows with zot_last_err_src=redact_failed over a window
    alert_route: scheduled-zot-restart-loop.yml already reads this source; a sustained non-zero
      count is a follow-through probe, not a page
  - mode: jq absent on the host (packages: is documented non-fatal)
    detection: redact() falls to the sed backstop automatically; observable as the absence of
      structural redaction on a JSON sample in the readback probe
    alert_route: the readback probe's assertion; degrades in the SAFE direction by construction
  - mode: the scrub is INERT — present but matching nothing (the #7440 class: "redaction that is
      nominally present and actually inert" because it was anchored on the wrong shape)
    detection: CI mutation battery, not runtime. This is the failure runtime cannot see.
    alert_route: the guard contract below; a red mutation row blocks the PR
  - mode: the sink-side scrub is bypassed by a NEW CAUSE-building arm added later
    detection: the guard asserts at the emit_and_exit() chokepoint, so a new arm is covered by
      construction rather than by having been enumerated
    alert_route: CI
logs:
  where: journald on the host (the cron pipes through logger); GitHub Actions run logs; the
    Better Stack rows themselves
  retention: Better Stack 90 days (measured, #7772); journald per the host's journald.conf.d
    drop-in; GitHub issues PERMANENT and not retractable
discoverability_test:
  command: bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh
  expected_output: "ALL TESTS PASSED" with a non-zero assertion count and the mutation battery
    reporting every row RED against a GREEN baseline
```

## Guard Contract

### Guard 1 — producer-side redaction of the diagnostic sample

**Property.** No credential-bearing header value present in zot's log output leaves
`zot-disk-heartbeat.sh` in the clear — **including a header name this codebase has not anticipated,
on every line of a multi-line sample** — and the `SOLEUR_ZOT_DISK` row is emitted on every path,
including every redaction-failure path.

**Assembly.** Three chokepoints, all named, because scoping to one is the defect this gate exists to
catch. (1) The **value** chokepoint: the single `ZOT_LAST_ERR=` assignment, which all four tiers flow
into — the guard quantifies over the assignment, so a fifth tier is covered by construction. (2) The
**per-line** chokepoint: the loop that applies `redact()` to each line of `ZOT_ERR_RAW`. (3) The
**emit** chokepoint: the single `LINE=` assembly and its one `post()` call.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Delete the `redact()` call | RED |
| 2 | Fixture carries `X-Secret` (**not** on `CRED_HDRS`) inside a `headers` object | RED if the implementation is a denylist. The allowlist property, and the one Option 3 cannot buy. A `Cookie` fixture **cannot** discriminate — that is the defect this plan already made once. |
| 2b | **Same `X-Secret` fixture, as a MIXED multi-line blob** (panic frames + a JSON row) | RED unless `redact()` is applied **per line**. Measured: applied to the blob, this leaks `X-Secret` in the clear at RC=0. |
| 2c | Same, as an all-JSON multi-line blob | RED |
| 3 | **REORDER:** move `redact()` to *after* the sanitizer | **RED.** Needs fixture 2 to discriminate — post-sanitizer the quotes are gone, the JSON branch cannot fire, and the denylist backstop lets `X-Secret` through. A `Cookie` fixture stays green through this reorder. |
| 4 | Force RC=1 (non-object `headers`) | Row still emitted; `pcent=`, `boot_id=`, `exit_code=`, `zot_restarts=` present; the tier tag preserved; `zot_last_err` is the placeholder with **no residual of the input**. RED if the row is dropped, and RED if the suite asserts only "it still ships" — that passes a mutant shipping the raw field. *(The three RC=1 paths — `nonobj headers`, residual refusal, empty output — are funnelled through a **single** `\|\| { degrade }` branch, so per-path rows are unnecessary by construction. Writing three handlers is what would make three rows necessary; do not.)* |
| 5 | **Delete the tier gate** | RED — the plan's highest-ratio control must not ship unguarded |
| 6 | Tier-4 header-bearing fixture with the gate present | RED if the raw line ships rather than the parsed `message` |
| 7 | **Remove `jq` from the PATH stub set** | Tier-4 fixture must emit `none` (**degrade closed**), never the raw line. Unspecified degradation here would restore ~100% of the measured exposure while the ADR records the gate as removing it. |
| 8 | **Guard's own dispatch:** zero fixtures | Suite FAILS, never `0 passed, 0 failed` + exit 0 |

**Harness rows.** (a) Delete one assertion from the suite → the assertion floor reddens.
(b) **Must-PASS non-canonical:** a benign **tier-2** line (`level:error` with no `headers` object)
passes through unredacted and the row ships. *(An earlier draft used `gc successfully completed` here
— which is a **tier-4** sample the tier gate suppresses, so the row asserted a behaviour the same plan
removes. Caught at review.)* (c) **Must-PASS:** a tier-1 Go panic — `redact()` introduces **no
substitution**, asserted on `redact()`'s output, **and** the `panic:` header survives to the emitted
line. *(Not "byte-identical at the wire": every sample passes `tr`/`head -c 300` afterwards, so
row-level byte-identity is unsatisfiable by construction.)*

### Guard 2 — sink-side scrub before public publication

**Property.** No credential-bearing header value derived from a warehouse row reaches **any
workflow-visible public surface** — issue body, issue comment, or Actions run log.

**This control is a DENYLIST, permanently, and the plan says so rather than discovering it later.** By
the time text reaches `emit_and_exit()`, the producer's `tr -d '"\\'` has destroyed the JSON, so the
structural allowlist is unavailable at this layer forever. That is an acceptable design — it is the
second layer, not the first — but the ADR and the Art. 30 bracket must **not** describe this layer
with allowlist language, which would be the same overclaim the plan rejects Option 3 for.

**Assembly.** Two layers, deliberately (AP-025: the state predicate is complete by construction; the
interceptor is its complement). (1) **`emit_and_exit()`** in `scripts/zot-restart-loop-alarm.sh` —
every `CAUSE`, `DETAIL`, `NIC_CAUSE` and `NIC_DETAIL` leaves through its `echo "ZOT_ALARM_CAUSE=…"` /
`NIC_ALARM_CAUSE=` lines, so asserting there quantifies over all present and future arms. (2) The
**publication boundary** in `.github/workflows/scheduled-zot-restart-loop.yml`, beside the existing
`strip_log_injection()` — because the script chokepoint protects one consumer of the script's stdout
but not a second *producer* into the workflow's `$out`.

**Scope decision, made here rather than deferred to implementation** (an earlier draft left it as a
"decide deliberately" step, which is precisely the scope-boundary deferral this plan exists to argue
against): the scrub **does** cover `NIC_CAUSE`/`NIC_DETAIL`, because a chokepoint is cheaper than an
exception. But the property **claims nothing** about them — `$NIC_ADDRS` is `ip -4 -o addr show`
output, infrastructure metadata that no credential or client data can reach.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Remove the scrub from `emit_and_exit()` | RED |
| 2 | Add a new arm writing `ZOT_ALARM_CAUSE=` **outside** `emit_and_exit()` | RED. **[CORRECTED — an earlier draft made this "add a new CAUSE-building arm", which the chokepoint design scrubs BY CONSTRUCTION and would therefore go GREEN. A mutation row must name an edit that BREAKS the property; asserting RED on the edit the design makes safe would push an implementer toward the arm-enumeration guard the Assembly forbids.]** |
| 3 | Fixture whose sample carries `Cookie:` | masked in the emitted `ZOT_ALARM_CAUSE=` |
| 3b | Fixture carrying an **unanticipated** header name | Documents the denylist boundary. This row is expected to show the value **surviving**; it exists so the limit is measured and recorded rather than discovered by a regulator. Assert the recorded boundary, not an absolute. |
| 4 | Remove the workflow-boundary assertion | RED |
| 5 | A **second** credential header after a compliant first, in one sample | Both masked — RED if the scrub stops at the first match |
| 6 | **Guard's own dispatch:** zero fixtures | Suite FAILS |

**Harness rows.** (a) Delete an assertion → floor reddens. (b) **Must-PASS:** a `CAUSE` from the OOM
arm (static text plus trusted numeric fields) passes through **unchanged** — the scrub must not
corrupt arms that were never the problem. (c) **Must-PASS, post-Phase-B:** an already-producer-redacted
sample passes the sink scrub **unchanged** (idempotency). Without this row Guard 2 stays green forever
against an input population that stops existing the moment Phase B lands.

### The drift check between the two `redact()` copies

**[REVISED — the byte-equality "lockstep gate" of an earlier draft is cut.]** Review established that
all three FATAL messages live *inside* `redact()`'s body and hardcode `[zot-log-shipper]`, so
byte-equality would force the heartbeat to emit mis-tagged stderr into a channel the plan itself
proves has **no reader** (no `| logger` on that cron, no MTA, no SSH). A gate that dictates dead code
is the gate distorting the design. The copies also sit in the **same file**, ~440 lines apart.

Replace it with a cheap assertion in `registry-boot-guard.test.sh` that covers what byte-equality was
actually for — and covers *more*, since the function body was never the whole control:

- a unique anchor from the jq program (`def scrub: with_entries`) appears **exactly 2×**;
- `CRED_HDRS` and `HDR_KEEP` — **`HDR_KEEP` IS the allowlist**, and a body-only gate would let it drift while staying green — appear exactly 2× and are byte-identical between copies;
- the two call sites differ in **arity by design** (the shipper calls per journal line; the heartbeat calls per line of the sample), so any gate asserting behavioural equivalence from text identity is a proxy. Assert the per-line loop exists on the heartbeat side instead.

Note also the divergent shell options — `zot-log-shipper.sh` opens `set -uo pipefail`, the heartbeat
`set -u`. A future "make them lockstep" edit adding `pipefail` to the heartbeat would turn its
`head -c 300` into rc 141, the exact SIGPIPE hazard the shipper avoids with substring expansion,
silently emptying the field. Record it; do not "fix" it.

## The tier gate — the option nobody listed, and the best ratio on offer

The CTO review surfaced a fifth option that outranks the redaction on risk-removed-per-risk-introduced,
and it is adopted **alongside** Option 4 rather than instead of it.

The four tiers are not equal in either exposure or value. By the cloud-init's own 21-hour crash-loop
measurement, **tier 4 (`fallback`) produced ~100% of the header-bearing samples and ~0% of the
diagnostic value** — every sample was an HTTP-session or gc/info line, and none named a cause.
The #7272 evidence agrees: every published header object came from a routine `HTTP API` or `gc` line.

And the tier is **already discriminated for free** by `ZOT_ERR_SRC`. So: when `ZOT_ERR_SRC=fallback`,
emit the parsed `message` field only (or `none`) rather than the raw line. That removes the dominant
exposure at essentially zero bytes, loses no measured diagnostic, and is orthogonal to redaction.

**Does it remove the need for Option 4? That is an open measurement, and the plan must not pretend
otherwise.** The claim that "tiers 2 and 3 match on `level:error` / `cannot |failed to`, and a zerolog
`HTTP API` line can carry both" is **structurally true but quantitatively unevidenced** — it is an
assertion sitting against a *measurement* (the 21-hour corpus) that says tier 4 produced ~100% of
header-bearing samples, which if literal means tiers 2 and 3 produced ~0%. Review flagged this as the
plan's weakest joint, and it is: that unquantified sentence is the sole justification for +64 B on a
ForceNew payload, a duplicated 45-line function, and a new behavioural suite.

**The probe that settles it**, and it must run before Option 4 is committed to:

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh   --since 720h --grep SOLEUR_ZOT_DISK --limit 5000   | grep -F 'zot_last_err_src=' | grep -vF 'zot_last_err_src=fallback' | grep -cF 'headers:'
```

Count of header-bearing samples on tiers 1-3 over the retention window. **If it returns 0**, the tier
gate alone removes all *measured* exposure and Option 4's redactor should be **deferred** to the soak
follow-through rather than shipped on this ForceNew payload — and #7500 is answered as "tier gate +
sink scrub, redactor pending measurement". **If it returns non-zero**, Option 4 ships as specified.
Either way the answer is measured rather than asserted. Recorded as a Phase B precondition.

### A second, independent bug the tier gate also fixes

**`zot_last_err_src` has zero runtime consumers.** Verified repo-wide: outside the cloud-init that
emits it, the only hits are a field-presence assertion in `registry-boot-guard.test.sh`, plans, and
learnings. Neither `scripts/zot-restart-loop-alarm.sh` nor `scheduled-zot-restart-loop.yml` reads it.

So the alarm publishes `zot_last_err tail: …` into a public issue **with no indication of which tier
produced it** — and the #7272 comments show the result: `gc successfully completed` and
`no digests left, finished` presented under the heading **"Decoded cause"** of a crash loop. That is
precisely the defect the tier tag was added to remove: "naming a cause nobody measured (ADR-166)".
The tag shipped; the consumer never did. Fix it in the same PR — the alarm must render the tier and
must not present a `fallback` sample as a cause.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Backs Option 4, both-sided defence with sink-side first, and duplication over
extraction. Four corrections were verified and folded in: (1) `zot-disk-sample.sh` is first-wins and
therefore *not* a live spoof vector — corrected above; (2) there are **three** RC=1 paths in
`redact()`, not one — `error("nonobj headers")`, the non-JSON backstop's residual refusal, and the
empty-output check — and the shipper's own comment records the residual refusal firing for real and
"discard[ing] a panic trace whose credential had in fact been removed", i.e. landing on the tier-1
input class most worth keeping, which strengthens Option 4; (3) `zot_last_err_src` has zero runtime
consumers; (4) the ADR is an ADR-184 amendment. It also supplied the tier gate above.

Two further findings folded into the design:

- **The heartbeat cron has no `| logger`.** Verified: the shipper's cron ends `2>&1 | logger -t zot-log-shipper`; the heartbeat's ends at the script path. A `>&2` FATAL copied from the shipper would go to cron mail on a deny-all host with no MTA and no SSH — not a signal under `hr-no-ssh-fallback-in-runbooks`. **In-band reporting via `zot_last_err_src` is therefore mandatory, not stylistic.**
- **Extraction loses on blast radius — restated after review, because the first framing was a category error.** An earlier draft argued a shared file "re-couples the observer to the observed". That is wrong: sourcing a shared `redact.sh` does not couple the heartbeat to the *shipper*, it couples both to a *third artifact*, and none of the shipper's failure modes (cursor, rate cap, POST, journald read) travel through a redaction function. The observer/observed decoupling the `log_shipper_*` fields buy is untouched by extraction. **The sound argument is runtime-vs-commit-time coupling:** a missing or broken `source` on this host fails **silently** (`set -u`, no `| logger` on that cron, no in-place execution path) and is repairable only by a destructive replace of the fleet's sole image-pull path, whereas a drift between two committed copies fails as a **red check**. Duplicate + a commit-time drift check trades an unrepairable runtime failure for a pre-merge one. `scripts/lib/zot-telemetry-parse.sh` is the honest counter-precedent and reconciles cleanly: it is sourced by repo scripts on a CI runner, where a missing source fails loudly in seconds.

### Legal (CLO)

**Status:** reviewed
**Assessment:** The Art. 30 §(g) sentence is **true but incomplete** — it bounds *injection* and is
offered as a bound on *severity*, and a public egress defeats the inference. Three corrections were
verified and folded in: the public path carries `strip_log_injection()` (control-character hygiene,
**not** redaction — name it so no reader infers a control from its presence); only the non-OOM arm
publishes the tail; and the ordering constraint is a **disclosure** requirement, because applying
`redact()` post-sanitizer silently swaps allowlist semantics for denylist semantics while the register
advertises the allowlist.

`clientIP` is **not** Art. 4(1) personal data today — but the basis is that `10.0.1.0/24` contains
only servers, not that RFC1918 addresses are categorically non-personal. Art. 33 does not bite on the
current facts (service principals, not natural persons), but the CLO flags that "these are service
principals" is the same shape as a ground already withdrawn in the #7797 determination: Art. 4(12)
reaches unauthorised **alteration**, and a published `zot-push` credential confers the ability to
alter images that execute on hosts which do process personal data. **That is the limb that would
carry an Art. 33 analysis, and it is unstated anywhere.** Also flagged: **no rotation runbook exists
for `zot-pull`/`zot-push`** — the correct incident response to a public publication is rotation, not
issue deletion, because publication is effectively irrevocable.

The CLO's blocking action item — the historical search — was executed and is reported above under
"The residual is not prospective". Its outcome (no credential, no personal data) means **no
breach-register row**, which is also the CLO's explicit instruction: do not add a row for a
prospective residual.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable — no path in `## Files to Edit` or `## Files to Create` matches any
UI-surface term or glob. The mechanical override did not fire. No `.pen` is required.

### Product (CPO) — brand-survival threshold ruling

**Status:** reviewed
**Assessment:** **`single-user incident`.** The ruling turns on the ladder's own text rather than on a
probability argument: `none` requires "no credential surface", which is false by construction here;
`single-user incident` fits the "any sensitive-data surface is at risk" limb on its face. `aggregate
pattern` was rejected for two reasons, the second decisive — it describes *realized, repeated* impact
and is used retrospectively in the corpus, **and it is a gate downgrade**: it adds no CPO sign-off and
`user-impact-reviewer` exits immediately on it. Picking the scarier-sounding tier would buy strictly
fewer eyes.

The CPO also rejected the boilerplate worry directly: this diff hands `user-impact-reviewer` a
concrete artifact (`zot_last_err.headers.Cookie` / `X-Api-Key` / top-level `clientIP`) and a concrete
vector (raw tail → `CAUSE` → public issue body), which is exactly the shape that agent demands.

Two product findings carried forward:

- **The defect class, not the field, is the product signal.** Soleur sells autonomous engineering to founders who cannot audit their own alarm scripts — that is why they bought it. Indie-founder repos default public, so any Soleur-generated cron that folds observed runtime output into an issue, PR body or changelog inherits this exact shape. Filed as the capability gap below.
- **The brand cost is asymmetric to the technical severity.** A `ci/zot-restart-loop` issue carrying a `Cookie` is not primarily a security event; it is a *visible* one, on the surface prospects use to judge whether autonomous engineering is trustworthy. Do not overcorrect by reducing openness — public-by-default is part of the positioning; the conclusion is that the public surface raises the redaction bar.

**Consequences of the ruling, applied to this plan's frontmatter:** `brand_survival_threshold:
single-user incident`, `requires_cpo_signoff: true` (this advisory discharges the product half; the
Art. 30 amendment needs the CLO half), `user-impact-reviewer` at review time, and `gdpr-gate` must run
without being scoped down.

### Capability gap (filed, not fixed here)

There is **no gate covering runtime publication of third-party or system output to a public artifact
by agent-authored automation.** The nearest rule, `hr-third-party-content-grep-on-undertaking`, fires
only when a diff commits an *undertaking about* third-party content and is explicitly pre-merge only —
and no pre-merge grep can catch a string assembled at cron time. Per the CPO this is the second
occurrence of the class (after #7331); the first was caught pre-merge, this one would not have been.
File as a separate issue, engineering-owned, referencing this plan.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/cloud-init-registry.yml` | Phase B. Duplicate `CRED_HDRS`/`HDR_KEEP`/`redact()` into `zot-disk-heartbeat.sh`; call it on the **raw** `ZOT_ERR_RAW` **before** the sanitizer; wrap the call so all three RC=1 paths degrade the field (`zot_last_err=REDACTION_FAILED`, no `=`, no spaces) and set `ZOT_ERR_SRC=redact_failed`; add the tier gate on `ZOT_ERR_SRC=fallback`. The degrade wrapper lives **outside** the shared function body so the two `redact()` bodies stay byte-comparable. |
| `scripts/zot-restart-loop-alarm.sh` | Phase A. Add the scrub at the `emit_and_exit()` chokepoint; bound the length; render `zot_last_err_src` alongside the tail and stop presenting a `fallback` sample as a cause; **fix the false comment** that reads "surface the redacted log tail". |
| `.github/workflows/scheduled-zot-restart-loop.yml` | Phase A. Fence the interpolated `CAUSE` in the issue body so third-party text cannot inject markdown, `@mentions` or links. |
| `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md` | Amend `## Decision` (scope of `redact()`) and add a **new** Alternatives row for the redaction question. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Amend the `zotRegistry -> betterstack` and `github -> betterstack` edge descriptions. |
| `knowledge-base/legal/article-30-register.md` | New dated brackets on PA-8 §(g) and §(c). **Additive only** — quote the 2026-08-12 sentence, never edit it. **A THIRD cell also names #7500** and was not in the CLO's enumeration: the Vendor Mapping row for Better Stack states that "on the `SOLEUR_ZOT_DISK` path it is a payload-integrity sanitizer only (#7500)". That sentence becomes false when this lands. Add a dated bracket there too; do not edit it in place. Route the final cell list through the CLO attestation rather than deciding it here. |
| `apps/web-platform/infra/registry-boot-guard.test.sh` | Extend the field-name-set assertions and add the two-copy drift check. It is a **static template scan** — it cannot assert `redact_failed` is producible; that is Guard 1's job. |
| `.github/workflows/infra-validation.yml` | Register the new infra suite with an explicit `run: bash …` step. Required-check dependency. |
| `scripts/test-all.sh` | Register the new sink suite with a `run_suite` line — `scripts/*.test.sh` is **not** in `SUITE_GLOBS`, and the sibling alarm suite is registered exactly this way. |
| `scripts/zot-restart-loop-alarm.test.sh` | **Already exists** and asserts on `CAUSE` text via `assert_cause_contains`, with fixture emitters that do **not** emit `zot_last_err_src=`. Phase A changes that text, so this suite must be updated or it breaks — and if its assertions are loose enough not to notice, they were never asserting the published text. Also specify the legacy-row rule: what the alarm renders when `zot_last_err_src` is **absent** (every current fixture and every pre-#7247 warehouse row). Fail-open reproduces the ADR-166 defect; decide and record. |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` | Guard 1. **No behavioural suite for the heartbeat exists** — this is new. Built on the `zot-log-shipper.test.sh` template: extract from the template, apply `local.registry_rationale_strip`, assert the stripped result is still valid bash, execute against PATH stubs (`docker`, `curl`, `htpasswd`, `df`, `hostname`, `date`), results-file-derived tally, harness canary, assertion floor. **[CORRECTED — the CTO review asserted this suite would be auto-discovered. It is not.]** `run-registered-suites.sh` derives its suite list by grepping the WORKFLOW for `run: bash apps/web-platform/infra/<name>.test.sh`; its `git ls-files` call is only the **orphan-candidate** source. A new suite MUST be registered with an explicit `run:` step in `.github/workflows/infra-validation.yml` (sibling suites register there — see its `registry-boot-guard.test.sh` and `zot-log-shipper.test.sh` steps). Forgetting it is **merge-blocking**: `.github/scripts/test/test-infra-suite-registration.sh` runs in `guard-script-fixture-tests`, a REQUIRED, merge_group-triggered, path-filter-free check that hard-fails on an unregistered suite. |
| `scripts/zot-restart-loop-alarm-scrub.test.sh` | Guard 2, asserting at the `emit_and_exit()` chokepoint. Same registration requirement — a `run: bash` step must exist or the required gate fails. |
| `scripts/followthroughs/zot-last-err-redact-7500.sh` | The soak probe for AC17. Was named in the ACs but missing from this list. |
| `knowledge-base/legal/audits/2026-09-<n>-clo-<slug>.md` | Phase 5.5 CLO attestation — the diff touches `knowledge-base/legal/`. Tier 3; `docs/legal/**` untouched; no CI gate engaged; TC_VERSION unaffected. |

**Deliberately NOT edited:** `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` (signed and
DISCHARGED — use its §11 annotation pattern if a record is wanted, do not reopen B1–B7);
`knowledge-base/legal/breach-register.md` (no Art. 4(12) fact pattern — the measurement found no
credential and no personal data, and its out-of-scope table already excludes #7440 on this ground);
the shipper's own `redact()` (do not widen it for `clientIP` — that mutates a working, measured
control on the same ForceNew host for no measured gain; `clientIP` enforcement is #7530's).

## Implementation Phases

### Phase A — the public egress (ships immediately, no infrastructure event)

Pure script + workflow change. Takes effect on the next scheduled run. This is the severe surface and
it is not held hostage to Phase B's host replace.

1. Write `scripts/zot-restart-loop-alarm-scrub.test.sh` **first**, from the mutation matrix (RED). Register it in `scripts/test-all.sh` in the same commit.
2. Add the scrub at `emit_and_exit()` and bound the length. Mirror the assertion at the workflow publication boundary (AP-025 — the chokepoint is complete by construction; the interceptor is its complement).
3. Render `zot_last_err_src` **interpolated into `CAUSE`**, not as a new output line: `scheduled-zot-restart-loop.yml` parses only `^ZOT_ALARM_CAUSE=`, so a new `ZOT_ALARM_ERR_SRC=` line would be parsed by nothing, reach no `$GITHUB_OUTPUT`, and never render. Derive the tier from the **same row** as the tail — the tail comes from unsorted `$MAIN` while verdict fields come from sorted `SCOPED`, so `tail -1` on the two streams can land on different rows.
4. Stop presenting a `fallback` sample as a cause, and give `REDACTION_FAILED` the same treatment — publishing it under "Decoded cause" would be the identical ADR-166 defect one value over.
5. Fix the false "redacted log tail" comment — but note it becomes *accurate* once step 2 lands, so the fix is to make the comment describe what the code now does, not to delete a word.
6. Update `scripts/zot-restart-loop-alarm.test.sh` (it exists, asserts on `CAUSE` text, and its fixtures omit `zot_last_err_src=`), including the legacy-row rule for an absent tier tag.

**Two items an earlier draft carried here are CUT, on review:**

- **Non-RFC1918 `clientIP` masking.** Unreachable by construction today (`hcloud_firewall.registry` has zero inbound rules; the measured corpus is 100% `10.0.1.x`), already covered by re-evaluation trigger (1), and **owned by #7530**, which exists to enforce exactly this invariant. Adding a second, differently-placed control would duplicate an open issue's deliverable. Cross-reference #7530; do not implement here.
- **Markdown / `@mention` / link fencing in the workflow.** A genuinely different threat model (injection, not credential leakage), in a third file, that **no guard in this plan covers**. Shipping an unguarded change is the creep the Guard Contract exists to expose. It goes to the capability-gap issue, which is precisely about agent-authored automation publishing runtime output to a public surface.

### Phase B — the producer (rides the next provisioning event)

1. Write `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` **first**, from the mutation matrix (RED).
2. Duplicate `redact()` + constants into the heartbeat; call on raw text before the sanitizer; degrade on all three RC=1 paths; add the tier gate.
3. Add the lockstep byte-equality gate between the two `redact()` bodies.
4. Re-run `registry-userdata-budget.sh` and record the measured stored size.

### Phase C — the record

ADR-184 amendment, the two C4 edge descriptions, the Art. 30 brackets, the CLO attestation, and the
capability-gap issue.

## Acceptance Criteria

Every criterion below encodes a checkable post-condition on file state or command output. Baselines
are pinned so an implementer cannot satisfy an assertion against a number it invented.

### Pre-merge (PR)

1. `bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` → `ALL TESTS PASSED`, non-zero assertion count, harness canary present.
2. Every Guard 1 mutation row (1, 2, 2b, 2c, 3, 4, 5, 6, 7, 8) drives that suite **RED** against a GREEN baseline, each recorded with its measured output. Rows **2b/2c** are the per-line rows and are non-negotiable: the plan's own measurement shows the allowlist branch is unreachable on a mixed blob.
3. Guard 1's three must-PASS rows hold: a benign **tier-2** line ships unredacted; a tier-1 Go panic shows **no substitution at `redact()`'s output** and its `panic:` header survives to the emitted line; `zot_last_err_src` reports the correct tier when redaction is a no-op.
4. `bash scripts/zot-restart-loop-alarm-scrub.test.sh` passes; all six Guard 2 mutation rows RED; all three must-PASS rows hold, including the post-Phase-B idempotency row.
5. The drift check holds: `def scrub: with_entries` appears exactly **2×** in the rendered, strip-applied template; `CRED_HDRS` and `HDR_KEEP` each appear exactly 2× and are byte-identical between copies; the heartbeat side has a per-line loop.
6. **Budget, verified with the enforcing gate and not only the instrument.** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes (this is the gate that owns `REGISTRY_GZIP_BUDGET`), **and** `bash apps/web-platform/infra/registry-userdata-budget.sh --json` reports `stored_bytes` **< 20,000**. Baseline for this branch: **13,692 B**. Note the JSON's `headroom` field is measured against the 32,768 **cap**, not the 20,000 budget — do not quote it as budget room. The PR body records before/after plus the per-option deltas measured in this plan (tier gate **+40 B**, narrow scrub **+44 B**, full `redact()` **+64 B**), each reproducible by inserting the named block and re-running the same script.
7. `bash plugins/soleur/test/c4-count-parity.test.sh` → 10 passed, 0 failed. (Baseline was green; this gate cannot detect that an edge *description* became false — AC12 covers that.)
8. `bash apps/web-platform/infra/registry-boot-guard.test.sh` passes. Note its assertions are **static template scans**, so they can assert the field-name set and the trailing-field invariant but **cannot** assert that `redact_failed` is a producible *value* — that belongs to Guard 1. If the degrade wrapper renames the emitted variable, its `zot_last_err=$ZOT_LAST_ERR"` trailing assertion reddens.
9. **Registration — the required-check dependency.** Both new suites are registered by hand: the infra suite as an explicit `run: bash …` step in `.github/workflows/infra-validation.yml`, the sink suite as a `run_suite` line in `scripts/test-all.sh` (its sibling `scripts/zot-restart-loop-alarm.test.sh` is registered exactly that way; `scripts/*.test.sh` is **not** in `SUITE_GLOBS`). Then `bash scripts/lint-orphan-test-suites.sh` → `orphan test suites: none`. **Baseline today: 410 covered, 0 orphaned** — this is a green ratchet that both new files would otherwise break, and `guard-script-fixture-tests` is a required, path-filter-free check.
10. ADR-211 (ordinal re-probed against all `origin/*` refs immediately before merge) exists and records the decision, the five options with measured rejection reasons, the per-line requirement, AP-021 and AP-025, and the scope limit.
11. ADR-184 carries a **new** Alternatives row for the redaction question plus a one-line `## Decision` pointer scoping its §3 sanitizer to the shipper. The pre-existing "Widen the reporter's `zot_last_err` field" row is byte-unchanged (`grep -cF` on its exact text returns 1, as it does today).
12. **Every Phase-C artifact carries BOTH qualifiers.** The ADR `## Decision`, both `model.c4` edge descriptions, and each Art. 30 bracket state (a) the scope limit — `headers` object, JSON branch, per line, **not** `clientIP`; sink layer is a **denylist** — and (b) a **delivery-state qualifier** naming the next-replace precondition for the producer half. Producer-half sentences are written in conditional tense until the follow-through flips them. This is the plan's most-emphasised requirement and nothing else gates it.
13. Art. 30 amendments are additive: for each of the three cells (PA-8 §(g), PA-8 §(c), the Better Stack Vendor Mapping row), the pre-existing `[2026-08-12 …]` text is present byte-unchanged. Assert with `grep -cF` against the **exact quoted string named in the PR body** for each cell — `grep -c` is BRE and the §(g) text contains `level:error\|fatal`, where `\|` is an alternation, so a non-`-F` grep does not match literally. Pin each expected count in the PR body before editing.
14. No `breach-register.md` row was added — the measured fact pattern found no credential and no personal data.

### Post-merge (operator-free)

15. Phase A takes effect on the next `scheduled-zot-restart-loop.yml` run. No operator action.
16. **Phase B is INERT until the next `registry-host-replace`.** The PR body says so in those words — ADR-184 records the cost of not saying it, where a shipper "sat inert on a host born before it existed" for 45h while a comment claimed delivery.

### Soak-gated close criterion

17. **The probe must be falsifiable against an undelivered host.** An earlier draft asserted "the sample carries no credential-header residual", which the #7272 measurement shows was **already true before any change** (`Cookie`/`X-Api-Key`: 0 occurrences) — it would exit 0 on a host that never received Phase B. `scripts/followthroughs/zot-last-err-redact-7500.sh` instead asserts **both**: (a) the observed `boot_id` differs from the pre-merge baseline recorded in the PR body, and (b) a **Phase-B-only observable** — rows with `zot_last_err_src=fallback` contain no `headers:{` substring at all. (b) is false on every pre-Phase-B row, so the probe reddens on an undelivered host.
18. Because no replace is scheduled, `earliest=` cannot be resolved at merge. The directive ships with `earliest=` set to merge+30d as a **review** date, and the tracker records that ADR-211's `adopting → accepted` flip is blocked on delivery rather than on elapsed time. If no replace has occurred by then, the follow-through re-evaluates rather than closing.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is edited. The change is entirely within `cloud-init-registry.yml`, which
`zot-registry.tf` renders via `base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))`.

### Apply path

**(a) cloud-init-only.** `hcloud_server.registry` carries `user_data` as ForceNew with **no**
`lifecycle.ignore_changes`, and ADR-096 makes the host cloud-init-only with no in-place execution
path. Editing the template arms a `-/+ hcloud_server.registry` in any untargeted plan. Phase B is
therefore **delivered by the next registry host replace and is inert until then** — it is not applied
at merge, and the PR must not imply otherwise.

Blast radius if the replace is fired and the render is over cap: hcloud rejects the CREATE *after* the
destroy succeeds, stranding the fleet's sole image-pull path. AC6 is the gate that prevents it. The
`.tf`'s live stock table shows `cpx22` available on every probe to date, but records `cx23` flipping
NO→YES inside ~4 hours — so the recut runbook's demand for a re-probe **immediately** before firing
stands, and this plan does not schedule a replace.

### Distinctness / drift safeguards

`dev`/`prd` are not in play — `soleur-registry` is a single prd host with an isolated
`soleur-registry/prd` Doppler config admitting exactly the boot secrets. No secret value is added, so
nothing new lands in `terraform.tfstate`. Phase A touches no Terraform-managed resource at all.

### Vendor-tier reality check

Not applicable — no vendor resource is created. Better Stack ingest volume is unchanged: the row count
and cadence are identical, and the tier gate can only make `zot_last_err` shorter.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| The redaction is **inert** — present but matching nothing (the #7440 class, where a rule anchored on the sampler's rendering rather than zot's real output shipped nominally-present, actually-inert redaction) | Guard 1 rows 2 and 3, which use an `X-Custom` fixture that only the structural allowlist catches. An `Authorization`-only fixture cannot discriminate the branches — which is exactly how the shipper's positional regression survived. |
| `redact()` applied post-sanitizer silently degrades to denylist semantics while the register advertises an allowlist | Guard 1 row 3 (REORDER) plus the disclosure wording. The CLO classes this as a live control-vs-description drift, so it is a legal requirement as well as a correctness one. |
| Phase B strands the registry on a future replace | AC6 gates `stored_bytes < 20,000` with the repo's own byte-exact instrument; measured deltas are +64 B (redactor) and ~0 B (tier gate) against 6,308 B of room. |
| The two `redact()` copies drift | The lockstep byte-equality gate (AC5), modelled on the shipper suite's existing T3 lockstep-by-value assertion. |
| A future CAUSE-building arm bypasses the sink scrub | Guard 2 asserts at the `emit_and_exit()` chokepoint, not at an enumerated arm list; row 2 proves it. |
| The tier gate discards a genuine cause that only tier 4 would have carried | Bounded by measurement: across a 21-hour crash loop tier 4 named a cause zero times. The gate emits the parsed `message` rather than nothing, so the tier-4 signal degrades rather than vanishing. |
| Fixing the alarm's cause-rendering changes operator-facing text | Intended — the current text presents `gc successfully completed` as a crash cause, which ADR-166 forbids. |

## GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

Invoked because Phase 2.7's expanded triggers fire — **(b)** the plan declares
`brand_survival_threshold: single-user incident`, and **(d)** it concerns a **new artifact
distribution surface** (a public GitHub issue). The canonical path regex does **not** fire:
`bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh <5 planned files>` reported
`path scan complete — 5 examined, 0 matched`, exit 0. No migration, no `.sql`, no auth path, no API
route is touched. Recorded so a later reader can tell "the gate ran and matched nothing" from "the
gate never ran" — the distinction that sharp edge exists to preserve.

### `GDPR-Chapter-V` — the warehouse processor's Art. 28(3) instrument is unexecuted

**Severity:** Important (pre-existing; **not** caused by this plan)
**Article:** Art. 28(3), Chapter V
**Location:** plan section "Encryption Posture" → `at_rest[Better Stack Logs source 2457081]`
**Pattern matched:** an egress path to a non-EEA-attested vendor whose DPA row is open
**Why this matters:** open issues **#7825** and **#7529** record that Better Stack's Art. 28(3)
instrument and a written EEA location attestation for `data_region eu-central-1a` are outstanding.
This plan does not create that gap and must not be blocked on it — but it **strengthens the case for
the adopted option**: when the processor instrument is unexecuted, controlling what is shipped at the
emit boundary is the only control the controller actually holds.
**What to do:** cross-reference #7825/#7529 from the Art. 30 §(g) bracket. Do not re-litigate.
**Verified independently of the CLO report:** `logs_retention=90` on both sources `2457081` and
`2734275`, measured twice on two endpoint shapes and recorded in
`knowledge-base/legal/audits/2026-09-04-betterstack-source-split-7772.md`. The 90-day figure this
plan relies on is evidenced, not inherited.

### `GDPR-Art-5e` — the public egress has no retention bound

**Severity:** Important
**Article:** Art. 5(1)(e) storage limitation
**Location:** `.github/workflows/scheduled-zot-restart-loop.yml` → `gh issue create --body`
**Pattern matched:** a persistence surface with no retention metadata
**Why this matters:** the Better Stack plane is bounded at 90 days (measured, #7772). A public GitHub
issue has **no retention bound and is not retractable** — clones, forks, GHArchive and search indices
survive deletion. Same field, two egresses, retention differing by "90 days" versus "permanent".
**What to do:** already the plan's Phase A. The Art. 30 §(g) bracket must state the asymmetry
explicitly rather than leaving both egresses under one retention sentence.

### `GDPR-Art-9` — not triggered

**Severity:** n/a. No column, field or sample class in scope matches the Art. 9 special-category list.
The identity model on this plane is the `zot-pull` / `zot-push` **service principals**; the measured
corpus (#7272) contained no natural-person identifier of any kind. **No `Critical` finding, therefore
no operator-acknowledgment escalation and no `compliance-posture.md` row from this gate.**

### Corpus staleness — recorded, not actioned here

The gate emitted `POSTURE_FAIL: gdpr-gate rules >90 days stale` (**121 days**, last verified
2026-05-10). Per the skill's own operator chain this **does not pause the current PR** — the signal is
gate-internal state, a separate work cycle from this diff. It is already-tracked territory: **#7255**
(the `cron_run_stale` binding is inert because its workflow became an Inngest cron, so the
anti-backdating defence is not operating) and **#7857** (follow-through on whether the freshness
attestation actually advances). Per `wg-when-an-audit-identifies-pre-existing`, this plan records the
condition and does **not** fix it.

### Class corroboration

Open `compliance/critical` issue **#7844** — *"side-letter-register publishes a Co-Member's full legal
name in a public repo"* — is the **same class** as this plan's finding: an automated or semi-automated
path publishing unreviewed content to a world-readable repository. That is independent evidence for
the CPO's capability-gap filing above, and the two should cross-reference.

## Plan Review — panel, dispositions, and adjudicated conflicts

**Panel.** `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`,
`kieran-rails-reviewer` — the eng panel escalated to five by the `single-user incident` threshold.
`dhh-rails-reviewer` was **relevance-gated out**: the named panel is explicitly relevance-scanned, this
plan contains no Ruby or Rails, and `code-simplicity-reviewer` covers the overengineering lens
stack-agnostically. Recorded rather than silently skipped.

Domain leaders (`cto`, `clo`, `cpo`) ran earlier at Phase 2.5 and their findings are in
`## Domain Review`.

### Findings that changed the design (all verified against the repo before applying)

| Finding | Source | Disposition |
|---|---|---|
| **`redact()` on a mixed blob takes the DENYLIST branch and leaks an unanticipated header in the clear.** My own probe used a `Cookie` fixture — a denylist name — and read the result as an allowlist success. | spec-flow | **Applied.** Re-measured with `X-Secret`; confirmed. Option 4 is now **per-line**, with dedicated guard rows 2b/2c. This was the plan's single largest defect. |
| **`redact()` appears in ZERO ADRs** — ADR-184 records a one-`Authorization`-rule denylist, not the allowlist. The amendment premise was false. | architecture | **Applied.** Verified by grep. Reversed to a new ADR (ADR-211) + a pointer and Alternatives row on ADR-184. |
| **The 3-hour-window argument is falsified** — the publishing arm is `boot_id=$NEWEST_BOOT`-scoped and a replace always brings a new boot. | architecture | **Applied.** Withdrawn in place; the two-control case now rests on disjoint egresses and unbounded delivery latency. |
| **#7272 counts understated ~5×** — 100 comments, 36 `headers:{`, 13 `clientIP`, not "~20 / twenty / ~7". | kieran | **Applied.** Re-measured with `gh api`. Conclusions unchanged; the numbers were not. |
| **The residual-refusal "discarded a panic trace" claim describes an ALREADY-FIXED regex bug.** | kieran | **Applied.** Mis-attribution corrected in all sites; Option 4's case stands on the other two RC=1 paths. |
| **Guard 2 mutation row 2 was logically inverted** — it asserted RED on the edit the chokepoint design makes safe. | kieran | **Applied.** Rewritten to "writes `ZOT_ALARM_CAUSE=` outside `emit_and_exit()`". |
| **Neither new suite is auto-discovered**; `scripts/*.test.sh` is not in `SUITE_GLOBS`; `lint-orphan-test-suites.sh` is a green ratchet (410/0). | kieran | **Applied.** Both registration surfaces added to Files to Edit; AC9 pins the ratchet. |
| **The byte-equality lockstep gate would force dead code** — the FATAL echoes hardcode `[zot-log-shipper]` and the heartbeat has no reader for stderr. | simplicity | **Applied.** Gate cut, replaced with an anchor-count + constants + arity check that covers *more* (`HDR_KEEP` **is** the allowlist and a body-only gate would let it drift). |
| **Tier-gate placement unspecified; `jq`-absent behaviour unspecified; the empty-guard would destroy the tier tag.** | spec-flow + architecture | **Applied.** Placement, degrade-closed, and the empty-guard hazard all specified. |
| **AC16 was vacuous** — its assertion was already true pre-change. | spec-flow | **Applied.** Rewritten around a boot_id discriminator plus a Phase-B-only observable. |
| **Phase-C artifacts asserted the producer property in present tense** — the B2 class, in the PR guarding against it. | architecture + spec-flow | **Applied** as AC12. |
| **The sink scrub is structurally a denylist, forever.** | spec-flow | **Applied.** Stated in Guard 2 and required in the ADR/Art. 30 wording. |
| **The public-issue egress is unmodelled in C4**, and hanging it on a read edge is the wrong direction. | architecture | **Applied.** One `publicReader` actor + `github -> publicReader`. |
| **The coupling argument was a category error.** | architecture | **Applied.** Restated as runtime-vs-commit-time coupling. |
| **`zot_last_err_src` overload conflates provenance with outcome.** | architecture | **Applied.** Companion token `fallback:redact_failed`. |
| AC9 forbade a string Phase A makes *true*; `grep -c` exits 1 on zero. | kieran | **Applied.** AC cut; Guard 2 row 3 is the real post-condition. |
| AC11 had no oracle and used BRE against `\|`. | kieran | **Applied.** Now names file + cell + `grep -cF` + a pinned count. |
| Field count is **27**, not "~26". | kieran | **Applied.** |
| Missing tier-gate-only measurement row. | simplicity | **Applied.** Measured **+40 B**. |
| `scripts/zot-restart-loop-alarm.test.sh` already exists and is coupled to `CAUSE` text. | kieran + spec-flow | **Applied.** Added to Files to Edit with the legacy-row rule. |

### Conflicts between reviewers, adjudicated

- **The lockstep gate.** `code-simplicity` said delete it (forces dead code, same-file proximity); `architecture` defended it as commit-time coupling. **Resolved in favour of both**: the *goal* (mechanical drift detection) is kept, the *mechanism* (byte-equality) is replaced by an anchor-and-constants check that does not distort the design and covers `HDR_KEEP`, which byte-equality of the function body would have missed.
- **Non-RFC1918 `clientIP` masking.** `code-simplicity` said cut (unreachable, #7530 owns it); `architecture` wanted it as the content-disjointness that justifies two controls. **Cut.** The two-control case does not need it — it rests on disjoint egresses and unbounded delivery — and duplicating an open issue's deliverable is worse than cross-referencing it.
- **Workflow markdown fencing.** `code-simplicity` said separate issue (different threat, no guard covers it); `architecture` wanted an assertion at the publication boundary. **Both honoured**: the *fencing* goes to the capability-gap issue; the *assertion* stays, as Guard 2's second layer.

### Open questions the work phase must answer before implementing

These are recorded rather than guessed, because each changes what gets built:

1. Does the tier gate's `message` extraction handle a **non-JSON** line inside a mixed blob, and by what expression? (Per-line application makes this tractable; the rule still needs writing.)
2. What does the alarm render when `zot_last_err_src` is **absent** — every legacy warehouse row and every current test fixture? Fail-open reproduces the ADR-166 defect; fail-closed discards the tail on legacy rows.
3. Does `redact()` running before `head -c 300` materially shrink the diagnostic budget? The `jq -c` re-serialisation plus `REDACTED` tokens spend window that previously held original text. Measured for `user_data` bytes; **not** measured for sample information content.
4. Confirm the Phase B precondition probe (tier-2/3 header-bearing count over the retention window). If it returns 0, the redactor is deferrable and #7500 is answered by the tier gate plus the sink scrub.
