---
date: 2026-07-15
type: fix
scope: observability(infra)
issue: 6462
branch: feat-one-shot-6462-zot-soak-denominator
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: APPROVED WITH CONDITIONS C1–C4 (2026-07-15)
blocks: ADR-096 tasks 5.3–5.5 (irreversible GHCR retirement — rotates AND revokes the PAT)
---

# fix(observability): give the zot soak a denominator — make fresh-boot GHCR service visible

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for this branch.
>
> **This plan was cut roughly in half by a 6-agent review panel.** Two structural errors it originally contained (a dark-launch gate built on a false premise; a denominator arm that is mathematically degenerate) are recorded in `## Reversed During Planning` rather than quietly deleted — the *reasons* they were wrong are the most transferable content here.

## Overview

`scripts/followthroughs/zot-soak-6122.sh` is the gate that authorizes ADR-096 tasks 5.3–5.5. Those tasks are **irreversible**: they rotate *and revoke* the GHCR PAT. After them, a fleet that still needs GHCR can pull from neither registry, with no rollback.

The gate counts **bad events**. It has no **denominator**. `FALLBACKS == 0` therefore means *"no GHCR service was reported"* — not *"none occurred"*. #6452 added the missing numerator terms; **adding numerator terms cannot close a denominator gap.**

### The three holes, and the two lines that close them

| # | Hole (verified) | Closed by |
|---|---|---|
| 1 | **Probe-miss emits nothing — the DOMINANT path.** `cloud-init.yml:516`: if the `/v2/` probe misses, `REF` stays the GHCR ref, the pull at `:523` succeeds first try, and the emit guard `[ "$N" -ge 2 ] && [ "$REF" != "$IMAGE_REF" ]` (`:534`) never fires. Fleet is GHCR-served; Sentry sees nothing. | `stage:"app_ghcr_served"` — a new **5th FAIL signal** |
| 2 | **No fresh-boot liveness beacon.** No `app_zot` counterpart to `inngest_zot` (`:697`) → "0 fallbacks" is indistinguishable from "no boot happened". | `stage:"app_zot"` — mirrors `inngest_zot` |
| 3 | **Fresh boots can't prove the flip was exercised.** `_emit` writes only `{stage,image_ref,host_id,detail}` (`:334`) — no `feature`/`op`/`registry` — so a boot can never feed the `registry:"zot"` sample arm. | The soak's new arm counts the **bare** boot query directly (D2) |

**The mechanism — one line in the boot path.** The stage is **quoted**, matching the sibling emit at `:537` (`"app_ghcr_fallback" warning`) so both op-contract pins read the same form:

```sh
if [ "$REF" = "$IMAGE_REF" ]; then _emit "app image served by GHCR" "app_ghcr_served" warning; else _emit "app image served by zot" "app_zot" info; fi
```

After the pull loop, `REF == IMAGE_REF` **iff GHCR served** (covering *both* the probe-miss path *and* the post-fallback path, since `:535` reassigns `REF="$IMAGE_REF"`); `REF != IMAGE_REF` **iff zot served**. Exactly one beacon per successful boot.

**And one arm in the soak** — placed **after** the `FALLBACKS > 0` exit at `:218`, so an operator hitting a real fallback still gets the per-signal breakdown that `:216` exists to give:

```sh
APP_ZOT=$(sentry_count 'stage:"app_zot"')
[[ "$APP_ZOT" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: Sentry query 'app_zot' failed — retry next sweep." >&2; exit 2; }
if (( APP_ZOT < MIN_BOOTS )); then
  echo "FAIL(no-freshboot-evidence): 0 fallbacks, but only $APP_ZOT zot-served fresh boot(s) since $START (need >=$MIN_BOOTS). The fleet is UNOBSERVED, not clean. Most likely cause: this cloud-init predates START — merge + recreate a web host inside the window."; exit 1
fi
```

That is the whole denominator. It converges naturally as hosts recreate, imports no cross-file invariant, no window collision, and no human adjudication.

> ### ⚠ `MIN_BOOTS` is a NEW knob, default **1** — do NOT reuse `MIN_SAMPLE`
>
> This is the difference between a gate and a wall. `MIN_SAMPLE` (default 3, `:108`) means *zot-served pulls per image* and is dominated by **rolling deploys** — frequent. `count(app_zot)` counts **fresh host boots** only, which are *rebuild-triggered, not periodic* — and the soak header's own live measurement is **9 `bootstrap_complete` events in total, ever** (`:35`). Requiring ≥3 full web-host recreates inside a soak window, when **nothing in this plan or #6122 schedules a single rebuild**, makes the gate **permanently unpassable** — `exit 1` daily, forever. A gate that structurally cannot pass gets bypassed, which is worse than no gate.
>
> So: `MIN_BOOTS="${ZOT_SOAK_MIN_BOOTS:-1}"`, validated with the same `^[1-9][0-9]*$` guard as `:116` (an unvalidated knob is the vacuous-pass hole that guard exists to close). **One** zot-served fresh boot is sufficient evidence for what this arm actually proves: *the beacon emits, and the flip was exercised on the boot path.* Proving the flip at volume is the existing sample arm's job, and it keeps `MIN_SAMPLE`.
>
> #6122 should schedule ≥1 deliberate web recreate inside the soak window as an explicit 5.x step (Phase 7.3).

---

## Reversed During Planning

Two decisions were carried for most of planning and then falsified. Both are recorded because each is a *general* trap.

### ✗ REVERSED — the `[ -n "$ZURL" ]` "dark-launch gate" (former D5)

**The idea:** wrap the beacon in `[ -n "$ZURL" ]` so it stays silent pre-cutover, preventing the new 5th alarm filter from paging the founder on every web-host recreate. It mirrored `ci-deploy.sh:627-628`'s real precedent.

**Falsified three independent ways — `ZOT_REGISTRY_URL` is already set:**

1. `zot-registry.tf:185-191` — `doppler_secret.zot_registry_url`, project `soleur`, config `prd`, `value = local.registry_endpoint` (`10.0.1.30:5000`), and `:180-184` says *"TF owns the values → NO ignore_changes"*. `cloud-init.yml:514` reads exactly that secret.
2. The issue's own "34 of 38 `probe_unreachable`" evidence comes from `zot_gate_degraded_event`, which `ci-deploy.sh:780-783` **returns before** when the URL is unset. Those events *are* the proof it is set.
3. **`ADR-096:139-145` — the very lines this plan amends — states it outright:** *"the two cloud-init fresh-boot signals gate on `ZURL` + a `/v2/` probe with no `ZOT_ACTIVE` at all — so all three go live as soon as `ZOT_REGISTRY_URL` is set in Doppler `prd`, before the flip."*

**Two lessons.** (a) The gate is **always-open**: it would have prevented nothing while an AC certified that it did — *a false assurance is worse than no gate*. (b) Worse, it would have created **asymmetric gates on a numerator and its denominator** (ACCOUNTED gated, `bootstrap_complete` unconditional) → a permanent unclearable shortfall **by construction**. The plan mis-sold that as a feature. *Configured ≠ cutover* was the conflation underneath it all.

### ✗ REVERSED — the `accounted == expected ⇒ TRANSIENT on shortfall` arm (former D4)

This is the issue's own literal minimum-closure wording, and it is **mathematically degenerate**. Four independent proofs:

1. **Dead by construction.** `app_ghcr_served` becomes a `FAIL_QUERIES` entry. The soak `exit 1`s when `FALLBACKS > 0` (`:210-218`), and `FALLBACKS` sums every entry. So **every line after `:218` has `count(app_ghcr_served) == 0` as a precondition** → `ACCOUNTED = count(app_zot) + count(app_ghcr_served)` is *identically* `count(app_zot)`. The addition is arithmetic theater.
2. **Or it masks a real FAIL.** Placed *before* the `FALLBACKS` exit: 10 boots, 3 GHCR-served, 2 beacons dropped → `ACCOUNTED=8 < EXPECTED=10` → `exit 2` TRANSIENT instead of `exit 1` FAIL. It downgrades the exact signal this PR exists to raise. **Both placements are wrong.**
3. **It saturates into a false PASS.** `sentry_count` uses `per_page=100` and counts `.data | length` with **no pagination** (`:146`, `:158`) — every count is `min(true, 100)`. Harmless for the existing `> 0` tests; **load-bearing** the moment you compare two counters. Real ACCOUNTED=100 / EXPECTED=150 → reported 100 vs 100 → no shortfall → **false PASS on the arm whose only job is catching an unobserved fleet.** `START` is absolute and the window grows unbounded — a *when*, not an *if*.
4. **Its only unique domain is its own worst failure.** What it catches that the floor doesn't is *partial* beacon loss (`MIN_BOOTS <= ACCOUNTED < EXPECTED`) — precisely what a fail-open `_emit` produces by design. With `START` absolute, one dropped beacon poisons the window **permanently**: TRANSIENT daily, forever. A gate that structurally cannot pass gets bypassed.

**The floor dominates it on every non-degenerate case, with a *better* exit code.** Beacon dark (typo, DSN unresolved, curl fails, cloud-init never reached the fleet) → `app_zot == 0` → `exit 1` **FAIL**, not TRANSIENT. And `MIN_BOOTS` (1) is far below the 100 saturation ceiling, so the floor is **immune to proof 3**.

**On deviating from the issue:** `accounted == expected` is a proposed **mechanism** for the goal *"never PASS on an unobserved fleet"*. This plan meets that goal, better. The mechanism was specified before `app_ghcr_served` existed to make the probe-miss path loud — once the FAIL query carries hole 1, the denominator's remaining job is narrow: **prove the emitter is alive**, which is exactly `count(app_zot) >= MIN_BOOTS`. **This deviates from the issue's literal text and is surfaced as a User-Challenge** in `specs/<branch>/decision-challenges.md` for operator ratification — not silently omitted.

Cutting it dissolves: `bootstrap_complete`/EXPECTED, the `START` collision, the non-convergence flaw, the ADR sequencing precondition, the #6122 hard gate, an AC, 2 Risks rows, and 2 Alternatives rows.

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Response |
|---|---|---|
| cloud-init user_data headroom is comfortable | **FALSE, and both sources are stale.** The test's own comment says "~21.06 KB" (`cloud-init-user-data-size.test.ts:59`); a research pass reported ~21,106 B. **Measured live: 21,716 B vs a 21,800 B budget = 84 B.** | Design driven by measurement. See **Byte Budget** — the full design was applied to a scratch copy and **measured passing**. |
| "Bake the beacon into `soleur-host-bootstrap.sh` for 0 user_data cost" | **Impossible.** The app seed pull runs **pre-bootstrap** — `soleur-host-bootstrap.sh` is *extracted from the image the pull fetches* (`:546-561`). A baked helper cannot cover the pull that fetches it (`:55-58` says so). | Inline is the only option; the byte budget is load-bearing, not a preference. |
| The soak documents **six** ways the fleet can be GHCR-served (`:46-63`) | **There is a SEVENTH, and it is fatal.** See D3. | Not fixed here. **Machine-enforced** via the C1 blocker arm + filed as a P1. |
| Hole 1 is web-only | The inngest path (`:695-698`) has the same shape, **but** its block is gated `%{ if web_colocate_inngest ~}`, `default = false` (`variables.tf:356-360`) → **dead code on the real fleet**. `FAIL_QUERIES[freshboot]` is a structurally dead query today. | D3 — out of scope, evidence-backed. |

---

## Byte Budget — the binding constraint

`plugins/soleur/test/cloud-init-user-data-size.test.ts` asserts the base64gzip'd rendered `user_data` < `WEB_GZIP_BUDGET = 21_800`. Measured live (by forcing the assertion to report):

| Variant | Size | vs budget |
|---|---|---|
| **baseline (main)** | **21,716** | 84 B headroom |
| bare code line only | 21,760 | fits, +44 B |
| code line + 1 terse comment | 21,808 | **blows by 8 B** |
| ✅ **VERIFIED — trim+merge the `:525-533` comment → 5 lines, + the beacon, + 2 comment lines** | **≈21,720** | **≈80 B headroom — PASSES** (real test: `23 pass / 0 fail`) |

**The line gzips to only ~44 B** — every token it uses (`_emit`, `$IMAGE_REF`, `$REF`) already exists nearby. The cost is entirely in the **comment**. Dropping the reversed `ZURL` gate gives ~24 B back.

**Strategy — trim-first (the #6396 precedent: "Comments trimmed first"). It goes net ≈neutral; no re-baseline needed.**

1. **Trim + merge the 9-line comment at `:525-533`** — it already explains the `REF`/`IMAGE_REF` relationship the new line depends on. Merging documents *both* emits and reclaims what the new line costs.
2. Insert the code line.
3. **Re-measure**: force `WEB_GZIP_BUDGET = 1` in a *temp copy*, `bun test`, read `Received:`. Then run the real test.
4. **Only if trimming cannot recover it**: modest re-baseline `21_800 → 21_900` with a `#6462` rationale, in the `#6396` shape (`:65-67`). Baking is not available (see Reconciliation) — the circumstance `:55-58` sanctions a re-baseline for.

> **Do NOT** raise the budget without attempting step 1. The budget's job is to be a re-inlining tripwire; raising it on reflex retires the tripwire.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a total platform outage with no rollback. This gate is the only artifact authorizing ADR-096 5.3–5.5, which rotates **and revokes** the GHCR PAT. A false-PASS retires GHCR while the fleet is still GHCR-served → fresh hosts pull from **neither** registry. Separately, a defect in the emit line lands in `cloud-init.yml` — the boot path — where a `set -e` abort or a templatefile parse error means **fresh hosts do not boot at all**.

**If this leaks, the user's data is exposed via:** nothing. The beacon carries `{stage, image_ref, host_id, detail}` — no Art. 4 personal data. `host_id` is a machine identifier (`:315`); `detail` is a capped, quote-stripped docker error captured **pre-app-start**, when no user session has touched the host.

**Brand-survival threshold:** `single-user incident`

*CPO ruling (upheld):* correct, and for a reason worth stating — **the taxonomy is a gate-routing label, not a severity ladder.** `aggregate pattern` *sounds* broader for a fleet-wide blast radius but **removes** the per-PR sign-off (`plan/SKILL.md:431`). The operative question is *"can this single PR, landing broken, hurt a user?"* A malformed line in `cloud-init.yml` means no host boots. Yes.

---

## Hypotheses

**Gate fired mechanically** (`hr-ssh-diagnosis-verify-firewall`) on the token `probe_unreachable` — a signal *name*, not a network symptom. Telemetry emitted. **No network-layer fix is proposed at any layer**, so no L3/L7 hypothesis is advanced: this plan does not touch the probe, the gate, or the pull — it adds one emit *after* the pull has resolved. Diagnosing *why* the probe misses is #6416 / #6288. Making the miss countable is this plan.

---

## Decisions

### D1 — The insertion point IS the fix

**Exact:** between `cloud-init.yml:542` (`: > /run/soleur-stage-detail`) and `:544` (`IMAGE_REF="$REF"`).

- **After `:542`** so `_emit`'s `DETAIL` tag reads the *cleared* file, not a stale `ghcr_login_ok`.
- **Before `:544`** because `:544` reassigns `IMAGE_REF="$REF"`, **destroying the discriminator**. One line later and the comparison is always-true.

**Verified exhaustively** (all four paths through `:522-544`):

| Path | `REF` at loop exit | Emit | Correct? |
|---|---|---|---|
| probe miss (`:516`) | `== IMAGE_REF` | `app_ghcr_served` | ✅ **the dominant silent path** |
| probe hit, zot pull OK | `!= IMAGE_REF` | `app_zot` | ✅ |
| probe hit, zot fails ≥2 → flip (`:534-537`) | `== IMAGE_REF` | `app_ghcr_served` | ✅ also emits `app_ghcr_fallback` → 2 FAIL events, **1** beacon |
| `N≥5` → `exit 1` (`:539`) | — | none | ✅ boot dies; nothing to account |

`REF` cannot collide with `IMAGE_REF` on the zot branch — `:517` prefixes `$ZURL/`. **`set -e` safe**: a false `if` condition never trips errexit, and `_emit` ends `( … ) || true` (`:339`). `_emit` is in scope at `:542` — `runcmd` is ONE `/bin/sh` (`:456`), proven by the existing `_emit` call at `:537`.

**Pin the ordering by a test — on the CALL FORM, not the bare token.** ⚠ A naive `indexOf("app_ghcr_served") < indexOf('IMAGE_REF="$REF"')` is **defeated by this plan's own comment-merge**: the merged rationale sits *above* `:542` and must name the beacon, so `indexOf` would return the *comment's* offset and the pin would pass even if the code line sat below `:544` — the exact failure it exists to catch. Pin `'"app_ghcr_served" warning'` (the op-contract test already knows this class at `:151`). `IMAGE_REF="$REF"` is unique to `:544`, so the right operand is safe.

**Accepted wart (comment it, don't fix it):** `_emit` tags `image_ref` from `$IMAGE_REF` (`:334`), still the **GHCR** ref at the insertion point — so the `app_zot` beacon carries `image_ref: ghcr.io/…`, the wrong registry on the event asserting zot served it. Harmless to the gate (only `stage:` is queried); misleading forensics. A temp var costs bytes the budget cannot fund.

### D2 — Keep the emit BARE

Hole 3 could be closed by prefixing the boot emit with `feature`/`op`/`registry`. **Rejected:**

1. The bare-vs-prefixed asymmetry is documented as deliberate in three places (soak `:28-41`, op-contract `:218-224`, ADR-096) and **proven live**: `stage:"bootstrap_complete"` → 9 events; the same query prefixed → 0. Prefixing makes a query match **zero events forever** — silently restoring the blindness the gate exists to catch.
2. It changes `_emit`'s tag schema, pinned at op-contract `:143`, and `_emit` is shared with the `on_err` **fatal** path.
3. It cannot fit in the byte budget.

The soak counts the bare query directly instead. Complexity lands in the never-executed, zero-blast-radius script rather than the boot path — honoring the issue's own rationale for a separate PR.

> **Do NOT sum the boot query into `ZOT_WEB`** (a plan-v2 idea, cut). It is (a) **dead** — post-`FALLBACKS`-exit the floor already guarantees `ZOT_WEB >= count(app_zot) >= MIN_BOOTS`; (b) a **false-PASS route** — a dark beacon leaves `ZOT_WEB = rolling + 0`, which rolling deploys alone push past `MIN_SAMPLE` → PASS on an unobserved fleet; and (c) **unsound** — `sentry_count` returns the *string* `TRANSIENT` (`:151`), and `$(( ))` resolves that bare word as unset → **0**, destroying the sentinel (the hazard `:109-115` already documents).

### D3 — 🔴 The dedicated inngest host: a SEVENTH GHCR-served path, and it is fatal

Surfaced during planning. **Bigger than #6462 and not fixable here.**

- `cloud-init-inngest.yml:330` hard-pins `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.19` — **no zot path, no probe, no fallback**.
- `:337-343` is **fail-closed**: `[ "$pull_rc" -eq 0 ] || { echo "FATAL…"; exit "$pull_rc"; }`.
- `:254` logs into `ghcr.io` with the **baked** `GHCR_READ_TOKEN`.
- It reports via `inngest-boot-phone-home.sh`, **not** the Sentry `stage:` schema → **the soak is structurally blind to it**.
- `cloud-init-inngest-bootstrap.test.sh:58-59` **enforces** the `ghcr.io` ref in CI.
- The image **is** mirrored to zot (`zot-entry-gate.sh:56`) — the host just never asks.

**Consequence: 5.3 revokes the PAT ⇒ the next fresh inngest-host boot 401s ⇒ `exit $pull_rc` ⇒ the host never comes up — while this soak reports PASS.**

**Out of scope to fix** (different host, different file, #6122 Phase 5 scope; the colocate block is default-off so beaconing it would be near-dead code). **But not merely disclosed** — see C1. Prose is what #6462 exists to reject.

### D4 — 🔒 C1: machine-enforce the D3 blocker in the exit code (CPO condition, blocking)

**The plan's original instinct was to answer D3 with a NOT-COVERED bullet, an ADR sentence, and a filed issue. That is prose — and #6462's own thesis is that prose is not a fix:** *"That amendment is a disclosure, not a fix — this issue is the fix."*

**The soak's exit code IS the authorization artifact.** A gate that returns `exit 0` while a known-fatal path is open is not more trustworthy for carrying a comment about it. The deliverable of this PR is not "a denominator" — it is **a gate you can trust**.

So: while the D3 tracking issue is **OPEN**, the soak **must not `exit 0`**. Feasible and cheap — `GH_TOKEN` is **already exported** by `scheduled-followthrough-sweeper.yml:56`, and `zot-mirror-connector-6416.sh` already establishes `gh api` use in this probe class (declare `secrets=SENTRY_AUTH_TOKEN,GH_TOKEN`).

Shape (place immediately before the final PASS):

```sh
BLOCKER=<D3 issue number>
st=$(gh issue view "$BLOCKER" --json state --jq .state 2>/dev/null)
[[ "$st" == "OPEN" || "$st" == "CLOSED" ]] || { echo "TRANSIENT: cannot read #$BLOCKER state" >&2; exit 2; }
if [[ "$st" == "OPEN" ]]; then
  echo "FAIL(blocked): soak criteria hold, but #$BLOCKER is OPEN — the dedicated inngest host pulls GHCR fail-closed with no zot path, so 5.3 (PAT revoke) would leave it unable to boot. Not authorized."; exit 1
fi
```

`exit 1` (FAIL), not 2 — the criteria *are* met; the retirement is *blocked*. TRANSIENT means "the probe could not run" (`:89`), which is not the case.

### D5 — Denominator source: the beacon itself, nothing else

`count(stage:"app_zot") >= MIN_BOOTS`. No second emitter, no `bootstrap_complete`, no cross-file invariant.

- **Converges naturally** as hosts recreate — the thing a soak *is*.
- **Immune to the `per_page=100` saturation** that killed the counter-comparison (`MIN_BOOTS` = 1 ≪ 100).
- **Imports no `START` constraint.** A wider window only counts *more* `app_zot`; a late-landing beacon just means the floor takes longer to satisfy. The `START` collision the counter-comparison created **does not exist here**.
- Catches every case the reversed arm caught, with a **stronger** exit code (`exit 1` FAIL, not TRANSIENT).

---

## Architecture Decision (ADR/C4)

### ADR — amend ADR-096

Lines ~114-145 currently name #6462 as an **open** sufficiency gap and declare the soak "necessary but not sufficient". The amendment must:

- Record the fresh-boot **web** beacon + the liveness floor.
- **Not claim sufficiency.** Residuals survive: **#6437** (Sentry-dark) and **D3** (the 7th path). Status stays **Adopting**.
- **C3 — state coverage as an explicit `5 of 7` ratio.** Do **not** flip "NOT COVERED 2/2 → COVERED". Coverage went **4/6 → 5/7**: the count of known-uncovered paths *went up*. A reader of the gate's own header must see that, not infer it.
- Sweep `:114` "same four signals" → five.
- Note: *between merge and cutover, a web-host recreate that misses the probe fires `zot_mirror_fallback_rate` — expected, same root cause as #6416, do not investigate separately.*

### C4 views — enumerated, and deliberately NOT edited

All three model files were **read in full** (not grepped for the feature noun). Enumeration:

| Element / edge | Status |
|---|---|
| External human actors (`founder`, `emailSender`, `betaContact`, `contributor`) | Already modeled; **none added** — this change is machine-to-machine |
| `zotRegistry` (`model.c4:258`), `ghcr` (`:254`) | Already modeled, in `view context` (`views.c4:14`) + `view containers` (`:36`) |
| `hetzner = container "Compute"` (`model.c4:180`) — the cloud-init boot path | Already modeled; its description already names the fresh-boot pull |
| `hetzner -> zotRegistry` (`:386`), `hetzner -> ghcr` (`:387`) | Already modeled |
| **`sentry` external system + `hetzner -> sentry`** | **Absent — and absent for the whole plane, on `main`, today.** |

**Decision: do not edit `.c4` in this PR.** This is a reasoned deferral, not an unsupported "None":

1. **The edge is already true on `main`.** `_emit` has POSTed to Sentry from the boot path for four live signals (`runcmd_start`, `on_err` fatal, `app_ghcr_fallback`, plus `bootstrap_complete` via `_sentry_emit`). This PR adds a **5th call site on an existing emitter** — it introduces no edge.
2. **The rule doesn't reach it.** `wg-architecture-decision-is-a-plan-deliverable` scopes to an ownership/tenancy boundary move, a new substrate/trust boundary, or a reversal/extension of an ADR. A 5th call site is none.
3. **Half a plane is worse than none.** Shipping `sentry` with exactly one inbound edge asserts a *falsehood* — a reader infers the webapp doesn't report to Sentry — where silence asserted nothing. Uniformly-absent is a legible gap.

**Recorded as debt** in the ADR-096 amendment: *the Sentry plane (`hetzner -> sentry`, `webapp -> sentry`) is unmodeled in C4; model it whole in a docs-only PR.*

---

## GDPR / Compliance Gate

**Invoked** (trigger (b): threshold = `single-user incident`). **Verdict: no blocker, no Art. 30 amendment, no DPIA.** The beacon is a **5th call site on an existing emitter** carrying byte-identical tags. Sentry is already a named processor in **PA-8 — Operational Telemetry & Breach-Detection Logs** (`article-30-register.md:153`, DE region, Functional Software GmbH, SCCs). No Art. 4 personal data: `host_id` is a machine identifier; PA-8 `:159` already treats job-scoped signals as *"operational metadata, not Art. 4 personal data"*. PA-8's re-verification trigger is scoped to `cloud-init.yml`'s *daemon.json block* (`:303-310`) — this edit is in the runcmd region, so it does not fire.

*Forward-looking (note in the amendment):* PA-8 `:159` records that Sentry's **Logs product is NOT enabled**. This beacon is an event POST to `/api/<proj>/store/` (`:335`), not a Logs channel. Keep it there.

---

## Infrastructure (IaC)

No new infrastructure, no new secret, no new vendor, no operator step.

**Terraform changes:** `cloud-init.yml` (rendered via `base64gzip(templatefile(...))` from `server.tf`); `sentry/issue-alerts.tf` (5th `tagged_event`). No new variables, no `TF_VAR_*`, no Doppler mint.

**Apply path:** `cloud-init.yml` auto-applies on merge via `apply-web-platform-infra.yml` (path filter `apps/web-platform/infra/**`), but is **inert on running hosts** (`ignore_changes`) — effective **only on fresh rebuild**. Blast radius at apply: zero. At next rebuild: total if malformed → hence the render AC. `issue-alerts.tf` applies via `apply-sentry-infra.yml`, already `-target=`-scoped to this resource (op-contract `:246-248`) — no `-target=` list change.

**Drift safeguards:** the op-contract test derives the alarm's watched set and the soak's FAIL set independently and asserts equality (`:200-209`); the soak's runtime cardinality floor (`:181-184`) must move 4→5 in lockstep (CI parses; the sweeper executes — both must agree).

**Vendor-tier:** no tier gate; the alert resource exists and is applied.

---

## Observability

```yaml
liveness_signal:
  what: "stage:\"app_zot\" (zot-served fresh boot) + stage:\"app_ghcr_served\" (GHCR-served fresh boot) — exactly one per successful boot"
  cadence: "once per fresh host boot (rebuild-triggered, not periodic)"
  alert_target: "sentry_issue_alert.zot_mirror_fallback_rate → IssueOwners → ActiveMembers (reaches the solo founder, no SSH)"
  configured_in: "apps/web-platform/infra/cloud-init.yml (emit) + apps/web-platform/infra/sentry/issue-alerts.tf (page)"

error_reporting:
  destination: "Sentry (org jikigai-eu, de.sentry.io) via the baked-DSN _emit store API"
  fail_loud: "false — _emit is deliberately fail-open (never blocks boot). The soak's MIN_BOOTS floor is what makes a dark emit LOUD: a beacon that never POSTs drives app_zot to 0 → exit 1 FAIL → the retirement stays blocked."

failure_modes:
  - mode: "Fresh boot served by GHCR because the /v2/ probe missed (the DOMINANT path — today emits nothing)"
    detection: "stage:\"app_ghcr_served\" — emitted IN the boot path, outside the probe gate"
    alert_route: "zot_mirror_fallback_rate (5th filter) → page; soak FAIL_QUERIES[appserved] → exit 1"
  - mode: "Fresh boot served by GHCR after a zot pull failure"
    detection: "stage:\"app_ghcr_fallback\" (existing) AND stage:\"app_ghcr_served\" (new)"
    alert_route: "same alarm (both filters) → page; soak counts both → exit 1"
  - mode: "The beacon is dark (typo'd stage, DSN unresolved, curl fails, cloud-init never reached the fleet, ZOT_REGISTRY_URL regressed)"
    detection: "count(stage:\"app_zot\") < MIN_BOOTS — no second emitter needed; a dark beacon cannot manufacture evidence"
    alert_route: "soak liveness floor → exit 1 FAIL (never PASS on an unobserved fleet)"
  - mode: "5.3 retires GHCR while the dedicated inngest host still pulls it fail-closed (the 7th path, D3)"
    detection: "the C1 blocker arm reads the D3 issue's OPEN state via gh"
    alert_route: "soak → exit 1 FAIL(blocked) — the gate cannot authorize while the blocker is open"

logs:
  where: "Sentry events (90d rolling, PA-8 (f)). Boot-path journald is NOT a fallback — hr-no-ssh-fallback-in-runbooks."
  retention: "Sentry 90 days"

discoverability_test:
  command: "SENTRY_AUTH_TOKEN=<tok> GH_TOKEN=<tok> ZOT_SOAK_START=2026-07-15T00:00:00 bash scripts/followthroughs/zot-soak-6122.sh; echo \"exit=$?\""
  expected_output: "Prints per-signal counts including app-served=<n>, plus 'zot-served fresh boots=<n> (need >=1)'. exit 0 PASS / 1 FAIL / 2 TRANSIENT. NO ssh."
```

### Affected-surface observability (§2.9.2)

The fresh-boot path **is** a blind surface — pre-app, pre-doppler, unreachable without SSH. Both requirements met:

- **In-surface probe:** emitted **from the boot path itself** (`_emit`, baked DSN, fires pre-doppler/pre-docker). A host-side gate structurally cannot observe which registry a boot chose.
- **Discriminates all competing hypotheses in one event:** `app_zot` vs `app_ghcr_served` splits zot-served from GHCR-served on the same path, in one emit, with `image_ref` + `host_id`. With the existing `app_ghcr_fallback`, the three signals disambiguate **probe-miss** (served, no fallback) from **zot-pull-failure** (fallback + served) from **healthy** (zot) — the discrimination the soak's per-signal FAIL message (`:211-216`) needs to route remediation.

### Soak Follow-Through Enrollment (§2.9.1)

**Required — and it is the only query in this PR that will ever execute.** The soak itself is *not enrolled and never has been* (`:65-82`: *"no query in this file has ever executed, and THIS PR DOES NOT CHANGE THAT"*); it will not run until #6122 pins the cutover UTC. So the soak's floor **cannot self-verify**. Meanwhile a typo'd stage name is silently dark — #6462's own defect class reproduced inside its own fix.

- **Script:** `scripts/followthroughs/accounted-beacon-live-6462.sh` (new, mode `100755`, ~30 lines). PASS iff `count(stage:"app_zot") + count(stage:"app_ghcr_served") >= 1` since deploy — a real fresh boot emitted the beacon. **TRANSIENT while `count(stage:"bootstrap_complete") == 0`** (no fresh boot yet ⇒ not a data point — the sibling's rule, `zot-mirror-connector-6416.sh:135-138`). *This is the one place `bootstrap_complete` earns its keep.*
- **Directive** on #6462: `<!-- soleur:followthrough script=scripts/followthroughs/accounted-beacon-live-6462.sh earliest=<deploy+7d> secrets=SENTRY_AUTH_TOKEN -->` + the `follow-through` label.
- **Secrets:** `SENTRY_AUTH_TOKEN` — already wired in `scheduled-followthrough-sweeper.yml`. No new secret.
- The soak (`zot-soak-6122.sh`) stays **unenrolled** — #6122 owns the cutover UTC and the enrollment decision. This PR must not change that.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — threshold-triggered)

Other six domains: not relevant (no user-facing surface, pricing, contract, copy, or support flow). The Legal/regulated-data angle is handled by the GDPR Gate (verdict: no personal data).

**Product/UX Gate: NONE.** Mechanical UI-surface scan of `## Files to Edit` / `## Files to Create`: **zero** matches against the UI-surface term list or glob superset. No `.pen` required (`wg-ui-feature-requires-pen-wireframe` does not fire).

**CPO sign-off: APPROVED WITH CONDITIONS.** C1 (machine-enforce the D3 blocker → **D4**), C2 (file the D3 issue *before* the ADR cites it → Phase 6 step 0), C3 (header states `5 of 7` → ADR section), C4 (the shortfall message must not offer "re-pin `START` forward" — the header warns a late `START` is a false-PASS route; **moot: the arm is cut**). All four accepted.

---

## Open Code-Review Overlap

**None.** Queried all 62 open `code-review` issues; none references `cloud-init.yml`, `zot-soak-6122.sh`, `issue-alerts.tf`, the op-contract test, or `ADR-096`.

---

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/cloud-init.yml` | **+1 code line** between the `:542`/`:544` literals, **and trim+merge the `:525-533` comment** to fund its rationale (Byte Budget step 1). |
| `scripts/followthroughs/zot-soak-6122.sh` | `FAIL_QUERIES[appserved]='stage:"app_ghcr_served"'`; cardinality floor `!= 4` → `!= 5` (condition **and** message); **the new `MIN_BOOTS` knob** (`MIN_BOOTS="${ZOT_SOAK_MIN_BOOTS:-1}"`, validated `^[1-9][0-9]*$` per `:116`) **+ the `app_zot >= MIN_BOOTS` liveness floor**; **the C1 blocker arm**; `secrets=` gains `GH_TOKEN`; header: `NOT COVERED 2/2` → the **5-of-7** ratio (C3) incl. the 7th path; sweep "FOUR watched signals" 4→5 (`:9-44`, ~6 places — read each hit, do not blind-replace). |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | 5th `tagged_event`: `key = "stage"`, `value = "app_ghcr_served"`. Keep `filter_match = "any"` + `value = 0`. **Also update the enumerating comment at `:1334-1335`.** |
| `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` | `alarm.size` 4→5 (`:203`); `soakFailQueries().size` 4→5 (`:204`); flat **bare** whole-query pin `soakQueryFor("app_ghcr_served") === 'stage:"app_ghcr_served"'`; emit-**call-form** pin; `value = "app_ghcr_served"` tf pin. |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | **New leg: pin the emit ORDERING on the CALL FORM** — `indexOf('"app_ghcr_served" warning') < indexOf('IMAGE_REF="$REF"')` (mirrors the AC5 `verifyIdx < runIdx` idiom). **Not** the bare token — the merged comment defeats it (D1). |
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | Amend ~`:114-145` (see ADR section) incl. the 5-of-7 ratio, the C4-debt note, the expected-page note. Status stays **Adopting**. |
| `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` | `:24`, `:108` enumerate the signal set → 4→5 sweep. |
| `apps/web-platform/infra/ci-deploy.sh` | `:872` comment names "two pull-fallback signals" → three. **Comment only.** |

## Files to Create

| File | Purpose |
|---|---|
| `scripts/followthroughs/accounted-beacon-live-6462.sh` | Proves the beacon fires on a real fresh boot — the only query in this PR that will ever execute (mode `100755`). |

## Issues to File (`wg-when-deferring-a-capability-create-a`)

| Issue | Content |
|---|---|
| **Dedicated inngest host hard-pins a GHCR ref with no zot path — blocks ADR-096 5.3** | D3 verbatim: `cloud-init-inngest.yml:330` + fail-closed `:337-343` + CI enforcement (`cloud-init-inngest-bootstrap.test.sh:58-59`) + already-mirrored (`zot-entry-gate.sh:56`). Labels: `priority/p1-high`, `domain/engineering`, `observability`. Link as a retirement precondition on #6122. **Its number is hard-wired into the soak's C1 blocker arm.** Closes when the inngest host pulls zot-primary with a GHCR fallback **and** reports on the Sentry `stage:` schema. |

---

## Implementation Phases

> **Phase order is load-bearing.** The emit (the contract) precedes its consumers. Atomic merge ≠ atomic per-phase TDD.

### Phase 0 — Preconditions

1. Re-measure the baseline: force `WEB_GZIP_BUDGET = 1` in a **temp copy**, `bun test`, read `Received:`. **Expect 21,716.** If it differs, main moved — re-derive the Byte Budget.
2. Confirm the insertion anchors are still the `: > /run/soleur-stage-detail` / `IMAGE_REF="$REF"` **literals** (anchor on literals, not line numbers — ADR-096 mandates it).
3. Confirm `set -e` is active (`:462`) and `_emit` returns 0.
4. `gh issue view 6462 --json state` → OPEN.

### Phase 1 — File the D3 blocker issue **FIRST** (C2)

Its number is cited by the ADR amendment **and hard-wired into the C1 blocker arm** — it must exist before either references it.

### Phase 2 — RED (`cq-write-failing-tests-before`)

Add the op-contract pins for the 5th signal (`alarm.size` 5, `soakFailQueries().size` 5, the bare whole-query pin, the call-form pin, the tf pin). **Run → RED** (nothing emits `app_ghcr_served` yet).

### Phase 3 — The emit (the contract)

1. **Trim + merge the `:525-533` comment first.**
2. Insert the single code line between the literals, with the merged rationale (note the `image_ref` wart).
3. **Run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`** → PASS (~21,720). If over, re-measure and use Byte Budget step 4.
4. Add the **call-form** ordering pin leg.
5. **Render-verify the templatefile** — a parse error means no host boots:
   `printf 'templatefile("%s", { <full var map> })\n' "$PWD/apps/web-platform/infra/cloud-init.yml" | terraform -chdir="$(mktemp -d)" console`
   Confirm no `%{` introduced (even in comments) and any shell `${VAR}` is `$${VAR}`.
6. `bash apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` + `cloud-init-inngest-bootstrap.test.sh`.

### Phase 4 — The alarm filter

Add the 5th `tagged_event` + update the `:1334-1335` comment. `terraform validate` / `fmt -check` in `apps/web-platform/infra/sentry/`.

### Phase 5 — The soak

1. `FAIL_QUERIES[appserved]='stage:"app_ghcr_served"'` (**bare**).
2. Cardinality floor `!= 4` → `!= 5` — condition **and** message.
3. **Declare the new knob** beside `MIN_SAMPLE` (`:108`): `MIN_BOOTS="${ZOT_SOAK_MIN_BOOTS:-1}"`, validated with the same `^[1-9][0-9]*$` guard as `:116` (an unvalidated knob is the vacuous-pass hole that guard exists to close). **It is a NEW knob — do not reuse `MIN_SAMPLE`** (see the Overview callout: `MIN_SAMPLE`=3 counts rolling-deploy pulls; `count(app_zot)` counts fresh boots, of which there have been 9 *ever* → a 3-floor is a permanently unpassable wall).
4. **The liveness floor**, after the `FALLBACKS` exit, before/beside the sample arm: guard `APP_ZOT` as a string **before** any arithmetic (`:151` returns `TRANSIENT`), then `(( APP_ZOT < MIN_BOOTS ))` → `exit 1`.
5. **The C1 blocker arm**, immediately before the final PASS → `exit 1` FAIL(blocked).
6. `secrets=` in the header directive gains `GH_TOKEN`.
7. Header: the **5-of-7** ratio (C3), the 7th path, the C4/#6437 residuals. Sweep 4→5 prose.
8. `bash -n` + `shellcheck` if available.

### Phase 6 — GREEN + the follow-through probe

1. Op-contract test → **GREEN**.
2. Create `accounted-beacon-live-6462.sh`, `chmod 755`; `bash scripts/followthrough-exec-bit.test.sh`.
3. Stub-harness test for the soak arms (see AC7).

### Phase 7 — ADR + runbook + comments

1. Amend ADR-096 (5-of-7, no sufficiency claim, C4 debt, expected-page note, 4→5 at `:114`).
2. `zot-registry-revert.md` `:24`/`:108` 4→5; `ci-deploy.sh:872` comment.
3. Comment on #6122 linking the D3 issue as a retirement precondition, and record CPO's two #6122 recommendations: **(a) rotate ≠ revoke** — rotating the exposed PAT closes the TR5 security driver *now*, reversibly, with no gate; only *revoke* needs the soak. **(b)** consider a reversible **GHCR-dark rehearsal** (set `GHCR_READ_TOKEN` invalid, recreate a web host + an inngest host) as the real authorization gate — it proves *"the fleet boots without GHCR"* directly instead of enumerating signals, and would have caught D3 in one run.

### Phase 8 — Exit gate

1. **`bash scripts/test-all.sh`** — the only gate that catches orphan suites.
2. Add the `follow-through` label + directive to #6462.

---

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — the beacon is in the right place, pinned by a test on the CALL FORM.** A leg in `cloud-init-user-data-size.test.ts` asserts `indexOf('"app_ghcr_served" warning') < indexOf('IMAGE_REF="$REF"')`. **Not** the bare token (the merged comment sits above `:542` and would satisfy it vacuously — D1).
2. **AC2 — the byte budget holds and trim-first was attempted.** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes; the diff shows the `:525-533` comment trimmed/merged.
3. **AC3 — the templatefile renders.** The `terraform console` render (Phase 3.5) exits 0.
4. **AC4 — the op contract holds at 5.** `bun test apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` passes with `alarm.size === 5` and `soakFailQueries().size === 5`.
5. **AC5 — the new query is BARE (the prefix trap).** `soakQueryFor("app_ghcr_served") === 'stage:"app_ghcr_served"'`, asserted in the test. Prefixing matches zero events forever.
6. **AC6 — the runtime floor moved in lockstep.** `grep -c '${#FAIL_QUERIES\[@\]} != 5'` == 1 **and** `grep -c '!= 4'` == 0. (CI parses source; the sweeper executes — this gap is the bug class this issue is about.)
7. **AC7 — the arms return the right codes.** A shell stub harness overriding `sentry_count` asserts: dark beacon (`app_zot=0`, no fallbacks) → **`exit 1`** (FAIL, *never* 0, *never* 2); `app_zot >= MIN_BOOTS` + D3 issue OPEN → **`exit 1`** FAIL(blocked); `app_zot >= MIN_BOOTS` + blocker CLOSED + sample OK → `exit 0`.
7b. **AC7b — the liveness floor is a gate, not a wall.** `MIN_BOOTS` is its own knob defaulting to **1**: `grep -c 'MIN_BOOTS="${ZOT_SOAK_MIN_BOOTS:-1}"'` == 1, and the floor's comparison names `MIN_BOOTS`, **not** `MIN_SAMPLE` (`grep -c 'APP_ZOT < MIN_SAMPLE'` == 0). A 3-floor on fresh-boot count — 9 such events *ever* — is `exit 1` daily forever, and a gate that structurally cannot pass gets bypassed. The knob is validated `^[1-9][0-9]*$` (an unvalidated knob is a vacuous-pass hole). **Distinct from AC8:** the pre-existing *sample* arm keeps `MIN_SAMPLE`.
8. **AC8 — the insufficient-sample arm keeps `exit 1`.** `grep -c 'FAIL(insufficient-sample)'` == 1, arm still `exit 1` — the only detector for the #6437 Sentry-dark mode. **Do not "fix" it to TRANSIENT.**
9. **AC9 — no arithmetic on an unguarded count.** Every `sentry_count` result is string-guarded (`=~ ^[0-9]+$`) **before** any `(( ))` / `$(( ))` use — `:151` returns the bare word `TRANSIENT`, which arithmetic silently coerces to **0** (the hazard `:109-115` documents). Verify by reading each new call site.
10. **AC10 — the D3 blocker is tracked AND enforced.** The issue exists with `priority/p1-high`, is linked from #6122, **and its number appears in the soak's C1 arm** (`grep -c '<N>' scripts/followthroughs/zot-soak-6122.sh` ≥ 1). A deferral without a tracking issue is invisible; a known-fatal path without an exit-code gate is prose.
11. **AC11 — ADR-096 does not over-claim (the repeat-offence gate).** The amended region contains `#6437`, names the **7th** path, and states coverage as **5 of 7** — not "COVERED". Status still `Adopting`. *ADR-096 already had to publicly correct one over-claim; this AC exists so it does not happen twice.*
12. **AC12 — the follow-through probe is enrolled and executable.** `test -x scripts/followthroughs/accounted-beacon-live-6462.sh`; `bash scripts/followthrough-exec-bit.test.sh` passes; #6462 carries the `follow-through` label + directive.
13. **AC13 — full suite green.** `bash scripts/test-all.sh` exits 0.

### Post-merge (operator)

*None.* `cloud-init.yml` + `issue-alerts.tf` auto-apply via their path-filtered workflows; the follow-through probe is swept daily; the beacon's live proof is the probe's job.

> The **cutover** and pinning `ZOT_SOAK_START` are **not** steps of this PR — they belong to #6122. This PR is a precondition of that work, not part of it.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The emit line breaks the boot path** (a `set -e` abort or templatefile parse error = no host boots). | `if/else` is `set -e`-safe (a false condition never trips errexit); `_emit` always returns 0 (`:339`); the existing `_emit` at `:537` proves scope. AC3 render-verifies. Inert on running hosts, so the apply itself is zero-risk. |
| **Prefixing the new query darkens it forever.** | AC5 pins the whole query string as **bare**. The op-contract flat-pin leg exists for exactly this and is deliberately duplicated, not looped. |
| **The ordering pin passes vacuously** because the merged comment names the beacon above `:542`. | AC1 pins the **call form** (`'"app_ghcr_served" warning'`), not the bare token. |
| **A count is used in arithmetic while holding `TRANSIENT`** → coerced to 0 → false PASS. | AC9. This is why the `ZOT_WEB` sum was cut (D2). |
| **A 7th GHCR-served path makes 5.3 fatal** regardless of this fix. | Not papered over: the **C1 blocker arm** (D4) makes `exit 0` impossible while the D3 issue is open; plus the 5-of-7 header, the ADR amendment, and a tracked P1 (AC10/AC11). |
| **Shipping a beacon that never fires** (typo → dark → #6462's own defect class, inside its fix). | `accounted-beacon-live-6462.sh` proves it fires on a real fresh boot — the only query in this PR that executes. |

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **`accounted == expected ⇒ TRANSIENT on shortfall`** (the issue's literal wording) | Degenerate four ways; strictly dominated by the `MIN_BOOTS` floor, which has a *better* exit code and is saturation-immune. See `## Reversed During Planning`. **Surfaced as a User-Challenge.** |
| **Gate the emit on `[ -n "$ZURL" ]`** to avoid pre-cutover pages | Premise false — ZURL is already set (3 proofs, incl. `ADR-096:139-145`). Always-open ⇒ protects nothing while an AC certifies it does; and it would asymmetrically gate a numerator against its denominator. |
| **Prefix the boot emit** with `feature`/`op`/`registry` | Breaks a deliberate, live-proven asymmetry; changes `_emit`'s schema (shared with the fatal path); cannot fit the byte budget. → **D2** |
| **Sum the boot query into `ZOT_WEB`** | Dead (the floor subsumes it), a false-PASS route (dark beacon + rolling deploys ⇒ PASS), and unsound (`TRANSIENT` → 0). → **D2** |
| **Bake the beacon into `soleur-host-bootstrap.sh`** (0 user_data) | **Impossible** — the seed pull runs pre-bootstrap; bootstrap is extracted *from the image the pull fetches*. |
| **Add `sentry` to C4** | Pre-existing debt (the edge is true on `main` for 4 signals); the rule doesn't reach a 5th call site; half a plane asserts a falsehood where silence asserted nothing. → **C4 section** |
| **Accept + document pre-cutover alarm pages** | Largely moot: `registry:"zot-gate-degraded"` already fires on the same `probe_unreachable` condition on 34/38 rolling deploys. Fresh boots are far rarer — a small increment on an already-firing alarm, root-caused to #6416. |
| **Re-model the contract as `alarm ⊆ soak`** | Semantically defensible (windowed decision vs continuous pager) but rewrites a defended contract and needs its own ADR — for a problem measurement showed is much smaller than it looked. Keep in reserve. |

---

## Non-Goals

- **Diagnosing why the `/v2/` probe misses** (34/38 `probe_unreachable`). → #6416, #6288.
- **Closing the #6437 Sentry-dark mode.** The sample arm remains its only detector — which is why AC8 keeps it at `exit 1`.
- **Adding zot to the dedicated inngest host** (the 7th path). → the D3 issue / #6122 Phase 5. This PR *blocks on* it (C1) rather than fixing it.
- **Modeling the Sentry plane in C4.** Recorded as debt; belongs in a docs-only PR that models it whole.
- **Enrolling `zot-soak-6122.sh` / pinning `ZOT_SOAK_START`.** → #6122 owns the cutover.
- **Performing the cutover or any part of 5.3–5.5.** This PR makes the gate trustworthy; it does not open it.
- **Rotating the exposed PAT, or building the GHCR-dark rehearsal.** CPO recommendations recorded on #6122 (Phase 7.3) — both are #6122 scope.
