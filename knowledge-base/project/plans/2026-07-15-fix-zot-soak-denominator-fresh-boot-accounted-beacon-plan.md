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

## Enhancement Summary

**Deepened on:** 2026-07-15
**Deepened after:** a laptop crash killed the planning session; the plan survived only as an untracked file. Committed to #6479 first, then rebased onto `origin/main` (4 commits behind — which turned out to matter).
**Research agents used:** verify-the-negative sweep · citation/rule-ID verification · observability-coverage-reviewer · test-design-reviewer · code-simplicity-reviewer · learnings-researcher · architecture-strategist *(died on an API error mid-run — see Coverage Gaps)*

**Gates:** 4.6 User-Brand Impact ✅ · 4.7 Observability 5-field ✅ · 4.8 PAT-shaped variable ✅ · 4.9 UI-wireframe ✅ (non-UI) · 4.5 Network-outage — **fired** (8 trigger tokens), dispositioned by `## Hypotheses` (no network-layer fix is proposed at any layer), telemetry emitted · 4.55 Downtime & Cutover — **not triggered**, verified not assumed: `lifecycle { ignore_changes = [user_data, …] }` (`server.tf:241-243`) sits inside `hcloud_server.web` (`:99`-`:248`) and so covers every `for_each` host.

### What held up

The **mechanism is sound** and the citations are clean. A verify-the-negative sweep of 10 load-bearing absolute claims returned **10/10 CONFIRMS with zero line-number drift** — `_emit`'s `( … ) || true` (`:339`) really cannot propagate nonzero; `set -e` really is active at the insertion point; `REF`/`IMAGE_REF` really is a sound discriminator; the anchors really are unique and adjacent. A citation pass found **no fabricated or retired rule IDs, no false attributions, no drifted file:line cites** across an unusually large sample.

### Key improvements

1. **The AC set was rebuilt — it could not detect its own feature's absence.** AC1 passed on a beaconless tree (`indexOf` → `-1`, and `-1 < 31470`), and no other AC covered existence, so the whole pre-merge set was satisfiable with the one code line missing. Added the existence pin + both `toBeGreaterThan(-1)` guards (mirroring `cloud-init-user-data-size.test.ts:312-316` *in full* rather than its last line), added AC1b's `toHaveLength(1)`, and moved the legs into Phase 2 so they actually go RED.
2. **AC7's harness was infeasible as specified.** `sentry_count` is defined at `:142` top-level with no source-and-override seam, so the prescribed stub loses. Re-specified on the seam that exists (PATH-stub `curl` + `gh`), proven working end-to-end.
3. **AC9 — the plan's worst hazard (`TRANSIENT` → 0 → false PASS → PAT revoked) — was guarded by an eyeball.** Folded into AC7's harness as a real assertion (HTTP 500 → `exit 2`).
4. **Every grep AC was unscoped, and the plan quotes its own patterns.** Repo-wide, `!= 4` matches 4 files. Scoped them all; qualified the generic patterns.
5. **AC6 checked half its own change** — the message (`:182`) says `expected 4` and contains no `!= 4`.
6. **`MIN_BOOTS` dropped from knob to hardcoded `== 0`.** Legal range is `{1}`, and since near-term runs are manual (`:113-115`), a knob is a **bypass surface** on a gate authorizing an irreversible act.
7. **Two Files-to-Edit rows were mis-specified as numeral sweeps when both are semantic** — see the `ci-deploy.sh` and `zot-registry-revert.md` rows. Both would have made an operator-facing artifact *lie*.
8. **The byte budget — the plan's self-declared "binding constraint" — was void.** Re-derived: 116 B headroom, not 84.
9. **Closing #6500 is itself the authorization act.** Now warned on both sides.
10. **D3's evidence was corrected** before #6500 was filed; two of six claims were false.

### New considerations discovered

- **`appserved ⊇ appboot`** — every path emitting `app_ghcr_fallback` also emits `app_ghcr_served`, so one bad boot contributes **2** to `FALLBACKS`. Harmless to the verdict, misleading to a reader. Commented (Phase 5.7).
- **The `image_ref` wart's justification expired** with the byte budget. Decision kept; reason rewritten (boot-path risk ≫ a cosmetic tag).
- **Nothing schedules a rebuild**, so the floor and the follow-through probe may both sit without evidence indefinitely. Escalated to #6122 as an explicit ask.

### Coverage gaps (stated, not hidden)

- **architecture-strategist died on an API error** and returned no findings. C1's architecture was independently covered by the simplicity reviewer (which weighed and rejected the repo-local-`grep` alternative); the ADR/C4 dimensions carry only the original panel's review.
- The **Byte Budget Δ column** remains a carried estimate against the old baseline; only the 21,784 baseline is measured. Phase 3 step 3 re-measures.
- **`stage:"bootstrap_complete"` → 9 events** is a live-Sentry claim, unverifiable from a static tree; the soak header (`:35`) documents it and is the only source.

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
if (( APP_ZOT == 0 )); then
  echo "FAIL(no-freshboot-evidence): 0 fallbacks, but NO zot-served fresh boot since $START. The fleet is UNOBSERVED, not clean. Most likely cause: this cloud-init predates START — merge + recreate a web host inside the window."; exit 1
fi
```

That is the whole denominator. It converges naturally as hosts recreate, imports no cross-file invariant, no window collision, and no human adjudication.

> ### ⚠ The floor is a HARDCODED `== 0` — NOT `MIN_SAMPLE`, and NOT a new knob either
>
> **Half of this callout (do not reuse `MIN_SAMPLE`) is the load-bearing part. Read it first.**
>
> **1 — Never reuse `MIN_SAMPLE`. This is the difference between a gate and a wall.** `MIN_SAMPLE` (default 3, `:108`) means *zot-served pulls per image* and is dominated by **rolling deploys** — frequent. `count(app_zot)` counts **fresh host boots** only, which are *rebuild-triggered, not periodic* — and the soak header's own live measurement is **9 `bootstrap_complete` events in total, ever** (`:35`). Requiring ≥3 full web-host recreates inside a soak window, when **nothing in this plan or #6122 schedules a single rebuild**, makes the gate **permanently unpassable** — `exit 1` daily, forever. A gate that structurally cannot pass gets bypassed, which is worse than no gate.
>
> **2 — But do not make it a knob either (revised at deepen; the earlier draft prescribed `MIN_BOOTS="${ZOT_SOAK_MIN_BOOTS:-1}"`).** A knob's value is its *range*, and this one's legal range is exactly `{1}`:
> - `0` → the vacuous-pass hole (the floor stops being a floor).
> - `>1` → the permanently-unpassable wall proven in (1).
>
> A knob with one legal value is a **constant wearing a costume** — plus a default, a `^[1-9][0-9]*$` guard, a validation branch, and an AC leg to defend the costume.
>
> **Worse, it is a bypass surface on a gate that authorizes an irreversible act.** Note `:113-115` — the soak's own comment on `MIN_SAMPLE` — records that *"the sweeper's `env -i` cannot forward this var, but … enrollment is deferred, so every near-term run is a **manual** one where it IS settable — exactly when the retirement decision gets made."* So env knobs on this script **are** reachable by the person making the call. `ZOT_SOAK_MIN_BOOTS=0` would silently disarm the denominator at precisely the moment it matters. A hardcoded `== 0` has no such surface.
>
> **Why `MIN_SAMPLE` legitimately stays a knob and this does not:** `MIN_SAMPLE`'s range is genuinely open (3, 5, 10 are all meaningful evidence thresholds), so its guard closes a real hole. This floor's range is not. Do not "mirror the sibling" for symmetry — the sibling earns its shape.
>
> **What the floor actually proves,** and why `1` is sufficient: *the beacon emits, and the flip was exercised on the boot path.* One zot-served fresh boot proves both. Proving the flip **at volume** is the existing sample arm's job, and it keeps `MIN_SAMPLE`.
>
> #6122 should schedule ≥1 deliberate web recreate inside the soak window as an explicit 5.x step (Phase 7.3) — otherwise the floor has no evidence to converge on.

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
4. **Its only unique domain is its own worst failure.** What it catches that the floor doesn't is *partial* beacon loss (`1 <= ACCOUNTED < EXPECTED`) — precisely what a fail-open `_emit` produces by design. With `START` absolute, one dropped beacon poisons the window **permanently**: TRANSIENT daily, forever. A gate that structurally cannot pass gets bypassed.

**The floor dominates it on every non-degenerate case, with a *better* exit code.** Beacon dark (typo, DSN unresolved, curl fails, cloud-init never reached the fleet) → `app_zot == 0` → `exit 1` **FAIL**, not TRANSIENT. And the floor (1) is far below the 100 saturation ceiling, so the floor is **immune to proof 3**.

**On deviating from the issue:** `accounted == expected` is a proposed **mechanism** for the goal *"never PASS on an unobserved fleet"*. This plan meets that goal, better. The mechanism was specified before `app_ghcr_served` existed to make the probe-miss path loud — once the FAIL query carries hole 1, the denominator's remaining job is narrow: **prove the emitter is alive**, which is exactly `count(app_zot) >= 1`. **This deviates from the issue's literal text and is surfaced as a User-Challenge** in `specs/<branch>/decision-challenges.md` for operator ratification — not silently omitted.

Cutting it dissolves: `bootstrap_complete`/EXPECTED, the `START` collision, the non-convergence flaw, the ADR sequencing precondition, the #6122 hard gate, an AC, 2 Risks rows, and 2 Alternatives rows.

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Response |
|---|---|---|
| cloud-init user_data headroom is comfortable | **Was FALSE at plan time; now PARTLY TRUE — main moved.** The test's own comment says "~21.06 KB" (`cloud-init-user-data-size.test.ts:59`); a research pass reported ~21,106 B. Plan-time measurement: 21,716 B vs a 21,800 B budget = 84 B. **Re-measured post-rebase 2026-07-15: 21,784 B vs a 21,900 B budget = 116 B.** | Design driven by measurement. See **Byte Budget** — re-derived after the rebase; headroom *grew*, and the design is no longer budget-bound. |
| "Bake the beacon into `soleur-host-bootstrap.sh` for 0 user_data cost" | **Impossible.** The app seed pull runs **pre-bootstrap** — `soleur-host-bootstrap.sh` is *extracted from the image the pull fetches* (`:546-561`). A baked helper cannot cover the pull that fetches it (`:55-58` says so). | Inline is the only option; the byte budget is load-bearing, not a preference. |
| The soak documents **six** ways the fleet can be GHCR-served (`:46-63`) | **There is a SEVENTH, and it is fatal.** See D3. | Not fixed here. **Machine-enforced** via the C1 blocker arm + filed as a P1. |
| Hole 1 is web-only | The **colocated** inngest path (`:695-698`) has the same shape, **but** its block is gated `%{ if web_colocate_inngest ~}`, `default = false` (`variables.tf:373-377`, re-verified) → **dead code on the real fleet**. `FAIL_QUERIES[freshboot]` is a structurally dead query today. The **dedicated** host (`inngest-host.tf:181`, unconditional) is the live one — and is GHCR-only. | D3 — out of scope, evidence-backed. |

---

## Byte Budget — no longer the binding constraint (re-derived 2026-07-15 post-rebase)

> ### ⚠ RE-DERIVED — main moved under this section; the old numbers are void
>
> This section was written against `WEB_GZIP_BUDGET = 21_800` / baseline **21,716** (84 B headroom). **Both moved before this branch rebased.** `e333a9384` (*"de-pool web-2 from the shared Cloudflare Tunnel"*, #6426 PR A) re-baselined the budget `21_800 → 21_900` **and** grew `cloud-init.yml` — a change this plan does not own and did not anticipate.
>
> **Re-measured on the rebased tree** (forcing `WEB_GZIP_BUDGET = 1` in a temp copy → `Received: 21784`, `22 pass / 1 fail` = the forced failure only):
>
> | | plan-time | **now** | Δ |
> |---|---|---|---|
> | budget | 21,800 | **21,900** | +100 |
> | baseline | 21,716 | **21,784** | +68 |
> | **headroom** | 84 B | **116 B** | **+32 B** |
>
> **The consequence is a reversal.** The row below claiming *"code line + 1 terse comment → **blows by 8 B**"* is **false against the current baseline**: at ~+92 B it lands at ≈21,876 and **fits, with ~24 B to spare**. Every variant now fits. The design is **not budget-bound** — the trim+merge is now a *preference*, not a necessity.

`plugins/soleur/test/cloud-init-user-data-size.test.ts` asserts the base64gzip'd rendered `user_data` < `WEB_GZIP_BUDGET = 21_900`.

| Variant | Δ vs baseline | Projected size | vs 21,900 budget |
|---|---|---|---|
| **baseline (rebased main)** | — | **21,784** *(measured)* | 116 B headroom |
| bare code line only | +44 | ≈21,828 | fits, ~72 B spare |
| code line + 1 terse comment | +92 | ≈21,876 | **fits, ~24 B spare** *(was: blows by 8 B)* |
| trim+merge the `:525-533` comment + beacon + 2 comment lines | +4 | ≈21,788 | fits, ~112 B spare |

> ⚠ **The Δ column is carried from the plan-time measurement against the OLD baseline — it is an estimate, not a measurement.** gzip is context-sensitive, so the deltas can shift when surrounding bytes change. Only the **21,784 baseline** is measured on the current tree. Phase 3 step 3 re-measures the real variant; treat the projections as a sanity range, not a result.

**The line gzips to only ~44 B** — every token it uses (`_emit`, `$IMAGE_REF`, `$REF`) already exists nearby. The cost is entirely in the **comment**.

**Strategy — trim-first anyway (the #6396 precedent: "Comments trimmed first"), but for *hygiene*, not survival.**

1. **Trim + merge the 9-line comment at `:525-533`** — it already explains the `REF`/`IMAGE_REF` relationship the new line depends on. Merging documents *both* emits and reclaims what the new line costs. **Now optional on byte grounds** — keep it because it leaves the tripwire meaningful and the rationale in one place, not because the budget forces it.
2. Insert the code line.
3. **Re-measure**: force `WEB_GZIP_BUDGET = 1` in a *temp copy*, `bun test`, read `Received:`. Then run the real test. **This is the only number that counts.**
4. **Do NOT re-baseline.** The former step 4 (`21_800 → 21_900`) is **already spent** — #6426 took it, for its own unrelated reasons. Burning it again (`21_900 → 22_000`) on a change with 116 B of headroom would be exactly the reflex the note below warns against. If the measured variant somehow does not fit, that is a signal to shrink the change, not the tripwire.

> **Do NOT** raise the budget. The budget's job is to be a re-inlining tripwire; raising it on reflex retires the tripwire. With 116 B of headroom for a ~44 B line, there is no case for touching it.
>
> **Lesson worth keeping:** this section was the plan's self-declared *"binding constraint"*, and it was invalidated by an unrelated PR between planning and implementation. Byte-budget arithmetic has a short shelf life — **re-measure at implementation time; never trust a carried number** (which is exactly why Phase 0 step 1 exists).

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

**Accepted wart (comment it, don't fix it).** `_emit` tags `image_ref` from `$IMAGE_REF` (`:334`), still the **GHCR** ref at the insertion point — so the `app_zot` beacon carries `image_ref: ghcr.io/…`, the wrong registry on the event asserting zot served it.

*Re-verified at deepen, and the justification was rewritten — the old one has expired:*
- **The wart is real.** `_emit:334` interpolates `"$IMAGE_REF"` directly; it does **not** read `/run/soleur-image-ref` (which `:543` populates with the correct served ref).
- **It is genuinely gate-harmless.** `image_ref` appears in `zot-soak-6122.sh` only inside **comments** (`:26`, `:40`) — never in a query. And the *real* pulls do use the correct ref: `:642`, `:660`, `:780` all read `/run/soleur-image-ref`. The damage is one misleading Sentry tag; forensics only.
- ⚠ **The old reason — *"a temp var costs bytes the budget cannot fund"* — is now FALSE.** The byte budget was re-derived post-rebase: 116 B of headroom (see Byte Budget). A temp var is affordable. **Keep the wart anyway, for the real reason:** the insertion site is `cloud-init.yml`'s boot path, the highest-blast-radius file in the repo — a malformed line means **no host boots at all** — and the defect it would fix is a cosmetic tag on an event nothing queries. That trade is not worth taking on this PR. Recorded explicitly so a future reader who notices the headroom does not "fix" it and reintroduce boot-path risk for a comment.

### D2 — Keep the emit BARE

Hole 3 could be closed by prefixing the boot emit with `feature`/`op`/`registry`. **Rejected:**

1. The bare-vs-prefixed asymmetry is documented as deliberate in three places (soak `:28-41`, op-contract `:218-224`, ADR-096) and **proven live**: `stage:"bootstrap_complete"` → 9 events; the same query prefixed → 0. Prefixing makes a query match **zero events forever** — silently restoring the blindness the gate exists to catch.
2. It changes `_emit`'s tag schema, pinned at op-contract `:143`, and `_emit` is shared with the `on_err` **fatal** path.
3. It cannot fit in the byte budget.

The soak counts the bare query directly instead. Complexity lands in the never-executed, zero-blast-radius script rather than the boot path — honoring the issue's own rationale for a separate PR.

> **Do NOT sum the boot query into `ZOT_WEB`** (a plan-v2 idea, cut). It is (a) **dead** — post-`FALLBACKS`-exit the floor already guarantees `ZOT_WEB >= count(app_zot) >= 1`; (b) a **false-PASS route** — a dark beacon leaves `ZOT_WEB = rolling + 0`, which rolling deploys alone push past `MIN_SAMPLE` → PASS on an unobserved fleet; and (c) **unsound** — `sentry_count` returns the *string* `TRANSIENT` (`:151`), and `$(( ))` resolves that bare word as unset → **0**, destroying the sentinel (the hazard `:109-115` already documents).

### D3 — 🔴 The dedicated inngest host: a SEVENTH GHCR-served path, and it is fatal

Surfaced during planning. **Bigger than #6462 and not fixable here.**

> **Re-verified against `main` 2026-07-15 (post-rebase).** Line numbers below are the *current* ones — the originals had drifted. Two claims this section originally carried were **falsified** on re-verification and are corrected in place; see the struck bullets. The D3 conclusion is **unchanged and strengthened**.

- `cloud-init-inngest.yml:337` hard-pins `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.19` — **no zot path, no probe, no fallback**. A case-insensitive sweep for `zot|ZURL|ZIREF|/v2/|soleur-boot-emit` across the whole file returns **0 hits**.
- `:349` is **fail-closed**: `[ "$pull_rc" -eq 0 ] || { echo "FATAL: OCI pull failed rc=$pull_rc" >&2; exit "$pull_rc"; }`.
- `:260` logs into `ghcr.io` with the **baked** `GHCR_READ_TOKEN` (written at render time from the templatefile var, `:245`). The login is fail-**open** (`set +e`, `:256` — emits `ghcr-login-FAILED` and continues), so **a revoked PAT degrades silently into a 401 at the fail-closed pull → FATAL**. Fail-open login feeding a fail-closed pull is what makes this abrupt rather than diagnosable.
- It reports via `inngest-boot-phone-home.sh` (`:107-122`) to **Better Stack** (`:121`), **not** the Sentry `stage:` schema → **the soak is structurally blind to it**. `cloud-init-inngest.yml` contains **zero** `soleur-boot-emit` calls. *Doubly moot:* the host never attempts zot, so it could not emit `inngest_ghcr_fallback` even if it were wired to Sentry.
- ~~`cloud-init-inngest-bootstrap.test.sh:58-59` enforces the `ghcr.io` ref in CI.~~ **FALSE — corrected.** That test's `CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"` (`:25`) points at the **colocated** block (which already has `ZIREF`), *not* the dedicated file its filename implies. The only test reading the dedicated file (`inngest-host.test.sh:20`) has **zero** `ghcr`/`IREF`/`zot` assertions. **No CI test governs the dedicated file at all** — so nothing blocks the fix. Do not claim a test does.
- ~~The image **is** mirrored to zot (`zot-entry-gate.sh:56`).~~ **Overstated — corrected.** `:56` is a pre-flip go/no-go gate that checks `manifest_resolves` (`:48-54`) and **blocks the flip on a miss**. It establishes that zot is *expected* to carry the image, not that it does today.
- **Tag skew (new, same root cause as the falsified claim).** The dedicated host pins `v1.1.19` (`:337`); the colocated block pins `v1.1.20` (`cloud-init.yml:693,699`). The AC6b pin-consistency guard (`cloud-init-inngest-bootstrap.test.sh:251-254`) only counts refs in `cloud-init.yml`, so **the dedicated pin is ungoverned and has silently fallen a version behind**. The file has no CI owner.

**Liveness — the load-bearing check.** `hcloud_server.inngest` (`inngest-host.tf:181`) is **unconditional**: no `count`, no `for_each`, no variable gate; rendered at `:201` and wired into the fleet (`network.tf:76`, firewall `:303`, volume `:274`) at 10.0.1.40. Contrast the colocated block, which *is* dead (`variables.tf:373-377`, `web_colocate_inngest` `default = false`). **A fresh dedicated inngest host boots this GHCR-only path today.**

**Consequence: 5.3 revokes the PAT ⇒ the next fresh inngest-host boot 401s ⇒ `exit $pull_rc` ⇒ the host never comes up — while this soak reports PASS.**

**Out of scope to fix** (different host, different file, #6122 Phase 5 scope; the colocate block is default-off so beaconing it would be near-dead code). **But not merely disclosed** — see C1. Prose is what #6462 exists to reject.

### D4 — 🔒 C1: machine-enforce the D3 blocker in the exit code (CPO condition, blocking)

**The plan's original instinct was to answer D3 with a NOT-COVERED bullet, an ADR sentence, and a filed issue. That is prose — and #6462's own thesis is that prose is not a fix:** *"That amendment is a disclosure, not a fix — this issue is the fix."*

**The soak's exit code IS the authorization artifact.** A gate that returns `exit 0` while a known-fatal path is open is not more trustworthy for carrying a comment about it. The deliverable of this PR is not "a denominator" — it is **a gate you can trust**.

So: while the D3 tracking issue is **OPEN**, the soak **must not `exit 0`**. Feasible and cheap — `GH_TOKEN` is **already exported** by `scheduled-followthrough-sweeper.yml:56`, and `zot-mirror-connector-6416.sh` already establishes `gh api` use in this probe class (declare `secrets=SENTRY_AUTH_TOKEN,GH_TOKEN`).

Shape (place immediately before the final PASS):

```sh
BLOCKER=6500   # filed 2026-07-15 — the D3 blocker; see Phase 1
st=$(gh issue view "$BLOCKER" --json state --jq .state 2>/dev/null)
[[ "$st" == "OPEN" || "$st" == "CLOSED" ]] || { echo "TRANSIENT: cannot read #$BLOCKER state" >&2; exit 2; }
if [[ "$st" == "OPEN" ]]; then
  echo "FAIL(blocked): soak criteria hold, but #$BLOCKER is OPEN — the dedicated inngest host pulls GHCR fail-closed with no zot path, so 5.3 (PAT revoke) would leave it unable to boot. Not authorized."; exit 1
fi
```

`exit 1` (FAIL), not 2 — the criteria *are* met; the retirement is *blocked*. TRANSIENT means "the probe could not run" (`:89`), which is not the case.

**The unreadable case must stay `exit 2`, never 0.** The `[[ "$st" == "OPEN" || "$st" == "CLOSED" ]]` guard is the load-bearing line: a gate must never read *"I could not measure"* as *"the measurement is false."* That inversion is the shape behind every P1 in `knowledge-base/project/learnings/2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`. Here it would PASS the gate during a GitHub API outage while the 7th path is still live. AC7 pins it.

> ### ⚠ Closing #6500 IS the authorization act — surfaced at deepen
>
> The arm reads issue **state**, not fixedness. `closed-as-not-planned`, a partial fix, or routine backlog tidying all flip the soak from `exit 1 FAIL(blocked)` toward `exit 0` — and `exit 0` is what authorizes the **irreversible** PAT rotate-and-revoke. The plan states #6500's close condition but never said that *closing it is the act*. Both sides now carry the warning: a comment beside `BLOCKER=6500` in the soak, and a pinned note on #6500 itself (posted 2026-07-15).
>
> This is the residual risk of proxying a code condition through an issue's state, and it is accepted deliberately: #6500's close condition is two-part (*pulls zot-primary with a GHCR fallback* **and** *reports on the Sentry `stage:` schema*), and a repo-local `grep` on `cloud-init-inngest.yml` — the token-free, network-free alternative — can only ever test the first half.

### D5 — Denominator source: the beacon itself, nothing else

`count(stage:"app_zot") >= 1` — a hardcoded floor, no knob (see the Overview callout).. No second emitter, no `bootstrap_complete`, no cross-file invariant.

- **Converges naturally** as hosts recreate — the thing a soak *is*.
- **Immune to the `per_page=100` saturation** that killed the counter-comparison (the floor is 1 ≪ 100).
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
  fail_loud: "false — _emit is deliberately fail-open (never blocks boot). The soak's zero-evidence floor is what makes a dark emit LOUD: a beacon that never POSTs drives app_zot to 0 → exit 1 FAIL → the retirement stays blocked."

failure_modes:
  - mode: "Fresh boot served by GHCR because the /v2/ probe missed (the DOMINANT path — today emits nothing)"
    detection: "stage:\"app_ghcr_served\" — emitted IN the boot path, outside the probe gate"
    alert_route: "zot_mirror_fallback_rate (5th filter) → page; soak FAIL_QUERIES[appserved] → exit 1"
  - mode: "Fresh boot served by GHCR after a zot pull failure"
    detection: "stage:\"app_ghcr_fallback\" (existing) AND stage:\"app_ghcr_served\" (new)"
    alert_route: "same alarm (both filters) → page; soak counts both → exit 1"
  - mode: "The beacon is dark (typo'd stage, DSN unresolved, curl fails, cloud-init never reached the fleet, ZOT_REGISTRY_URL regressed)"
    detection: "count(stage:\"app_zot\") == 0 — no second emitter needed; a dark beacon cannot manufacture evidence"
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
| `scripts/followthroughs/zot-soak-6122.sh` | `FAIL_QUERIES[appserved]='stage:"app_ghcr_served"'`; cardinality floor `!= 4` → `!= 5` (condition **and** message); **the `(( APP_ZOT == 0 ))` liveness floor** (hardcoded — **no knob**, see the Overview callout); **the C1 blocker arm**; `secrets=` gains `GH_TOKEN`; header: `NOT COVERED 2/2` → the **5-of-7** ratio (C3) incl. the 7th path; sweep "FOUR watched signals" 4→5 (`:9-44`, ~6 places — read each hit, do not blind-replace). |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | 5th `tagged_event`: `key = "stage"`, `value = "app_ghcr_served"`. Keep `filter_match = "any"` + `value = 0`. **Also update the enumerating comment at `:1334-1335`.** |
| `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` | `alarm.size` 4→5 (`:203`); `soakFailQueries().size` 4→5 (`:204`); flat **bare** whole-query pin `soakQueryFor("app_ghcr_served") === 'stage:"app_ghcr_served"'`; emit-**call-form** pin; `value = "app_ghcr_served"` tf pin. |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | **New leg: pin the emit ORDERING on the CALL FORM** — `indexOf('"app_ghcr_served" warning') < indexOf('IMAGE_REF="$REF"')` (mirrors the AC5 `verifyIdx < runIdx` idiom). **Not** the bare token — the merged comment defeats it (D1). |
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | Amend ~`:114-145` (see ADR section) incl. the 5-of-7 ratio, the C4-debt note, the expected-page note. Status stays **Adopting**. |
| `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` | ⚠ **NOT a 4→5 sweep — the two sites are semantically different (corrected at deepen).** `:108` **is** a genuine four-signal enumeration of the alarm's watched set → 4→5 is correct there. **`:22-25` is NOT**: it is a deliberate **three**-signal list (`ghcr-fallback` / `inngest_ghcr_fallback` / `app_ghcr_fallback`) under the predicate *"a host **tried** zot and failed"*, and `zot-gate-degraded` is excluded on purpose because its semantics differ. `app_ghcr_served`'s **dominant path is probe-miss — zot was never attempted**, which is the `zot-gate-degraded` semantic, not tried-and-failed. Adding it to `:22-25` files it under a predicate that is **false for it** and tells an operator, *mid-incident*, to chase the pull path when the fault is the probe. It belongs in the **second** bullet (`:26-28`, "zot unreachable") or nowhere. |
| `apps/web-platform/infra/ci-deploy.sh` | ⚠ **Re-cited and re-scoped at deepen — the old `:872` cite was wrong AND the edit was mis-specified.** `:872` is `zot_gate_degraded_event probe_unreachable` inside the `/v2/` probe, not a signal enumeration. The real text is **`:963-969`**, the `RETIREMENT TRIPWIRE (#6285)` block — the comment telling a future reader which signals survive task 5.3, *the exact irreversible action this plan gates*. **And it is not a "two → three" numeral bump:** the sentence reads *"they fire on the zot MISS, before any GHCR pull, so 'stop GHCR push' does not darken them either"* — a survival claim that is **FALSE for `app_ghcr_served`**, which fires *after* the pull loop resolves, and whose dominant probe-miss path sees the GHCR pull **succeed**. Post-5.3 that path emits no `app_ghcr_served` at all: it takes `N>=5 → exit 1` and the host dies beacon-less (D1 row 4). Appending a third name to a sentence whose predicate does not hold for it makes the tripwire **lie**. Needs a distinguishing clause, not a numeral. **Comment only** — but load-bearing comment. |

## Files to Create

| File | Purpose |
|---|---|
| `scripts/followthroughs/accounted-beacon-live-6462.sh` | Proves the beacon fires on a real fresh boot — the only query in this PR that will ever execute (mode `100755`). |

## Issues to File (`wg-when-deferring-a-capability-create-a`)

> ✅ **Filed 2026-07-15 as #6500.** Milestone `Post-MVP / Later`. Wired into the C1 arm (D4) as `BLOCKER=6500`.

| Issue | Content |
|---|---|
| **#6500 — Dedicated inngest host hard-pins a GHCR ref with no zot path — blocks ADR-096 5.3** | D3 as re-verified: `cloud-init-inngest.yml:337` (GHCR-only, 0 zot hits file-wide) + fail-closed pull `:349` + fail-open baked-token login `:260` + Better-Stack-not-Sentry reporting `:107-122` + **live, unconditional host** (`inngest-host.tf:181`) + **no CI owner** (`cloud-init-inngest-bootstrap.test.sh:25` reads `cloud-init.yml`, not this file) + resulting **tag skew** (v1.1.19 vs colocated v1.1.20). Labels: `priority/p1-high`, `domain/engineering`, `observability`. Link as a retirement precondition on #6122. **Its number is hard-wired into the soak's C1 blocker arm.** Closes when the inngest host pulls zot-primary with a GHCR fallback **and** reports on the Sentry `stage:` schema. <br>⚠ **Do NOT claim CI enforces the GHCR ref** — that premise was falsified on re-verification (see D3). Nothing blocks the fix. |

---

## Implementation Phases

> **Phase order is load-bearing.** The emit (the contract) precedes its consumers. Atomic merge ≠ atomic per-phase TDD.

### Phase 0 — Preconditions

1. Re-measure the baseline: force `WEB_GZIP_BUDGET = 1` in a **temp copy**, `bun test`, read `Received:`. **Expect 21,784** against a **21,900** budget (✅ done 2026-07-15 post-rebase — main *had* moved; the Byte Budget was re-derived, headroom 84 → 116 B). If it differs again, main moved again — re-derive before proceeding.
2. Confirm the insertion anchors are still the `: > /run/soleur-stage-detail` / `IMAGE_REF="$REF"` **literals** (anchor on literals, not line numbers — ADR-096 mandates it).
3. Confirm `set -e` is active (`:462`) and `_emit` returns 0.
4. `gh issue view 6462 --json state` → OPEN.

### Phase 1 — File the D3 blocker issue **FIRST** (C2) — ✅ **DONE: #6500**

Its number is cited by the ADR amendment **and hard-wired into the C1 blocker arm** — it must exist before either references it.

**Filed 2026-07-15 as #6500** (`priority/p1-high`, `domain/engineering`, `observability`; milestone `Post-MVP / Later`, matching #6122/#6462). Use **6500** in the C1 arm (D4) and the ADR amendment.

> **Premise re-verification changed the issue's content** (see the D3 note). Two of the six original evidence claims did not survive: CI does **not** enforce the GHCR ref on the dedicated file (nothing governs it at all), and `zot-entry-gate.sh:56` *requires* the mirror rather than proving it. The conclusion held and strengthened — the host is live and unconditional (`inngest-host.tf:181`). Remaining step: link #6500 as a retirement precondition on #6122 (Phase 7.3).

### Phase 2 — RED (`cq-write-failing-tests-before`)

Add the op-contract pins for the 5th signal (`alarm.size` 5, `soakFailQueries().size` 5, the bare whole-query pin, the call-form pin, the tf pin). **Run → RED** (nothing emits `app_ghcr_served` yet).

**Also add AC1's legs HERE — moved from Phase 3 step 4 at deepen.** The existence pin, both `toBeGreaterThan(-1)` guards, the ordering assert, and AC1b's `toHaveLength(1)`. This matters: on today's tree the *unguarded* ordering assert goes **GREEN with no beacon** (`-1 < 31470`), so writing it in Phase 3 — after the emit lands — means it never goes RED and never proves it can fail. Writing it in Phase 2 surfaces the vacuity immediately: the existence leg must go **RED** now, and if the ordering leg passes while existence fails, the guards are missing.

### Phase 3 — The emit (the contract)

1. **Trim + merge the `:525-533` comment first.**
2. Insert the single code line between the literals, with the merged rationale (note the `image_ref` wart).
3. **Run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`** → PASS (projected ≈21,788 with the trim+merge; ≈21,876 without — both under 21,900). **Re-measure rather than trusting either projection.** If it somehow does not fit: shrink the comment. **Do not raise the budget** (Byte Budget step 4).
4. AC1's legs were written in **Phase 2** — re-run them here; they must flip RED → GREEN. (Do **not** author them at this step: on a beaconless tree the unguarded ordering assert passes, so a pin written after the emit never proves it can fail.)
5. **Render-verify the templatefile** — a parse error means no host boots:
   `printf 'templatefile("%s", { <full var map> })\n' "$PWD/apps/web-platform/infra/cloud-init.yml" | terraform -chdir="$(mktemp -d)" console`
   Confirm no `%{` introduced (even in comments) and any shell `${VAR}` is `$${VAR}`.
6. `bash apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` + `cloud-init-inngest-bootstrap.test.sh`.

### Phase 4 — The alarm filter

Add the 5th `tagged_event` + update the `:1334-1335` comment. `terraform validate` / `fmt -check` in `apps/web-platform/infra/sentry/`.

### Phase 5 — The soak

1. `FAIL_QUERIES[appserved]='stage:"app_ghcr_served"'` (**bare**).
2. Cardinality floor `!= 4` → `!= 5` — condition **and** message. ⚠ **Two separate literals.** The condition is `${#FAIL_QUERIES[@]} != 4` (`:181`); the message (`:182`) says **`expected 4`** and does *not* contain the string `!= 4`. Sweeping only the condition leaves the operator-facing message on the irreversible gate saying "expected 4" while the condition requires 5. AC6 pins both.
3. **The liveness floor**, after the `FALLBACKS` exit, before/beside the sample arm: guard `APP_ZOT` as a string **before** any arithmetic (`:151` returns `TRANSIENT`), then `(( APP_ZOT == 0 ))` → `exit 1`. **Hardcode the floor — do NOT add a knob and do NOT reuse `MIN_SAMPLE`** (Overview callout: `MIN_SAMPLE`=3 counts rolling-deploy pulls and would be a permanently unpassable wall; a knob's only legal value here is `1`, and it would be a bypass surface since near-term runs are manual per `:113-115`).
4. **The C1 blocker arm**, immediately before the final PASS → `exit 1` FAIL(blocked). Use `BLOCKER=6500`.
5. `secrets=` in the header directive gains `GH_TOKEN`.
6. Header: the **5-of-7** ratio (C3), the 7th path, the C4/#6437 residuals. Sweep 4→5 prose.
7. **Comment the `FALLBACKS` subsumption** (found at deepen): every path that emits `app_ghcr_fallback` **also** emits `app_ghcr_served` (D1 row 3), so `appserved ⊇ appboot` and one bad boot now contributes **2** to `FALLBACKS` and double-fires the alarm. Harmless to the verdict (both `> 0` → FAIL) but a future reader will misread `FALLBACKS` as an event count. One clause in the `FAIL_QUERIES` comment: *`appserved ⊇ appboot` — `FALLBACKS` is a tripwire sum, not an event count; the two stay separate for remediation routing.*
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

> ### ⚠ The AC set was REBUILT at deepen. Read this first.
>
> A test-design pass proved **AC1 passed on a tree with no beacon in it at all** — and that no other AC covered existence, so **the entire pre-merge AC set was satisfiable with this plan's central deliverable absent from `cloud-init.yml`.** Demonstrated, not theorised:
>
> ```
> indexOf('"app_ghcr_served" warning') = -1     (does not exist)
> indexOf('IMAGE_REF="$REF"')          = 31470
> AC1 as written  (-1 < 31470)         => TRUE  <-- PASSES WITH NO BEACON
> ```
>
> `indexOf` returns `-1` on a miss and `-1` is less than every real offset. A typo'd stage, a renamed stage, or the line never being written all satisfied it. It failed *safe* in prod (`app_zot=0` → the floor → `exit 1` forever), so it would not have caused the outage — it would have shipped the PR **dead**, and #6462's whole thesis is that a gate certifying something it did not check is the defect.
>
> **The plan reasoned about vacuity better than any of its checks did.** It reversed two whole arms for being degenerate and caught that a bare-token pin would be defeated by its own comment-merge — then shipped an AC a missing file satisfies. The rigor was aimed at the design, not at the verification. That asymmetry is fixed below.

1. **AC1 — the beacon EXISTS and is in the right place.** Two legs, because ordering alone is vacuous:
   - **Existence** (the leg the earlier draft omitted): `expect(cloudInit).toContain('"app_ghcr_served" warning')`. This mirrors the identical in-repo pin at `sentry-zot-mirror-fallback-alert-op-contract.test.ts:195` (`expect(cloudInit).toContain(\`"app_ghcr_fallback" warning\`)`), whose own comment (`:192-193`) already records *why* the bare stage would be vacuous.
   - **Ordering**, guarded: `expect(servedIdx).toBeGreaterThan(-1)` **and** `expect(refIdx).toBeGreaterThan(-1)` **before** `expect(servedIdx).toBeLessThan(refIdx)`. This mirrors `cloud-init-user-data-size.test.ts:312-316` **in full** — the earlier draft copied its last line and dropped the two `toBeGreaterThan(-1)` guards that make it non-vacuous.
   - Pin the **call form** (`'"app_ghcr_served" warning'`), never the bare token: the merged comment sits above `:542` and names the beacon (D1). Verified: `IMAGE_REF="$REF"` is **unique** in `cloud-init.yml` (`:544`; the other two `IMAGE_REF=` at `:313`/`:463` are `='${image_name}'`), and `:534-545` contains no `${...}` interpolation, so raw text == rendered text and `indexOf`-returns-first is safe.
   - ⚠ **This leg belongs in Phase 2 (RED), not Phase 3.** On today's tree it goes GREEN with no beacon — which is exactly how the `-1` bug survived to review. Adding it after the emit lands means it never goes RED and never proves it can fail.

1b. **AC1b — the ordering pin cannot be defeated by quoting.** `expect(block.match(/"app_ghcr_served" warning/g)).toHaveLength(1)`. If a future comment quotes the emit call verbatim, `indexOf` silently returns the comment's offset and the pin passes while the code line sits below `:544`. Today four separate paragraphs *ask* a reader not to do that; this line makes CI say it. Self-enforcing beats narrated.
2. **AC2 — the byte budget holds, and it was not raised.** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes **with `WEB_GZIP_BUDGET` still at `21_900`** — `git diff` touches no budget constant (`grep -c 'WEB_GZIP_BUDGET = ' <diff>` == 0). There is 116 B of headroom for a ~44 B line; a re-baseline here would retire the tripwire, and #6426 already spent the `21_800 → 21_900` step for unrelated reasons. Trim+merge of `:525-533` is expected but **no longer byte-mandatory** (see Byte Budget) — its absence is a style call, a budget bump is not.
3. **AC3 — the templatefile renders.** The `terraform console` render (Phase 3.5) exits 0.
4. **AC4 — the op contract holds at 5.** `bun test apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` passes with `alarm.size === 5` and `soakFailQueries().size === 5`.
5. **AC5 — the new query is BARE (the prefix trap).** `soakQueryFor("app_ghcr_served") === 'stage:"app_ghcr_served"'`, asserted in the test. Prefixing matches zero events forever.
> ⚠ **SCOPE EVERY GREP AC TO `scripts/followthroughs/zot-soak-6122.sh`.** The earlier draft left AC6/AC7b/AC8 unscoped, and **this plan quotes their patterns in its own prose**, so a repo-wide run matches the plan itself and can never pass. Measured today: `!= 4` → **4 files** (the soak, this plan, and two unrelated plans); `FAIL(insufficient-sample)` → **2** (soak + this plan). Scoped, each is unique and satisfiable. A pattern with no file argument is not an assertion — it is a judgment call at verification time, which is how a gate authorizing an irreversible PAT revoke gets waved through. AC10 already scoped correctly; the rest now match it.

6. **AC6 — the runtime floor moved in lockstep, condition AND message.** Against `scripts/followthroughs/zot-soak-6122.sh` only:
   - `grep -c '${#FAIL_QUERIES\[@\]} != 5'` == 1 and `grep -c '${#FAIL_QUERIES\[@\]} != 4'` == 0 — use the **qualified** pattern, not bare `!= 4`, which is dangerously generic even when scoped.
   - `grep -c 'expected 5'` == 1 **and** `grep -c 'expected 4'` == 0. The message (`:182`) says `expected 4` and does **not** contain `!= 4`, so a condition-only sweep leaves the gate's operator-facing text contradicting its own condition. This leg is the half the earlier draft missed.
   
   (CI parses source; the sweeper executes — this gap is the bug class this issue is about.)
7. **AC7 — the arms return the right exit codes, proven by a harness that actually works.** ⚠ **The earlier draft specified "a shell stub harness overriding `sentry_count`". That is INFEASIBLE and was proven so:** `sentry_count` is defined at `:142` at top level, which overwrites any pre-export; there is no `BASH_SOURCE` guard, no `main()`, and the script `exit`s at top level (`:234`), so there is no source-and-override seam. `export -f`, `BASH_ENV`, and pre-definition all lose to `:142`. As written this AC would have been quietly downgraded at implementation to "I read it and it looks right" — the exact failure class this plan exists to reject.
   
   **Use the seam that exists: PATH-stub `curl`** (dispatch on the `query=` in the URL), plus **PATH-stub `gh`** for the C1 arm (otherwise AC7 hits the network in CI). Verified working end-to-end against the real script, real `jq` parse path included. Assert:
   - dark beacon (`app_zot=0`, no fallbacks) → **`exit 1`** (FAIL — *never* 0, *never* 2)
   - `app_zot >= 1` + `gh` reports #6500 **OPEN** → **`exit 1`** FAIL(blocked)
   - `app_zot >= 1` + #6500 **CLOSED** + sample OK → **`exit 0`**
   - **HTTP 500 → `sentry_count` yields the bare word `TRANSIENT` → `exit 2`, never 0** (this is AC9, folded in — see below)
   - `gh` unreadable / non-OPEN-non-CLOSED → **`exit 2`** TRANSIENT, never 0. *A gate must never read "I could not measure" as "the measurement is false"* — the failure shape behind every P1 in `knowledge-base/project/learnings/2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`.
7b. **AC7b — the floor is a gate, not a wall, and not a knob.** Against the soak only: `grep -c 'APP_ZOT == 0'` == 1, and **no knob is introduced** — `grep -c 'ZOT_SOAK_MIN_BOOTS'` == 0. ⚠ **The earlier draft's negative grep (`grep -c 'APP_ZOT < MIN_SAMPLE'` == 0) was near-vacuous** — it pinned one spelling, evaded by `[[ -lt ]]`/`((APP_ZOT<MIN_SAMPLE))`/`$MIN_SAMPLE`, and was **already 0** before a line was written. A negative grep for a string nobody would write is not a test. The *semantic* is proven by AC7's harness instead: a `MIN_SAMPLE`-reuse bug yields `1 < 3` → `exit 1` on a healthy fleet, which the harness catches. **Distinct from AC8:** the pre-existing *sample* arm legitimately keeps `MIN_SAMPLE`.
8. **AC8 — the insufficient-sample arm keeps `exit 1`.** Against the soak only: `grep -c 'FAIL(insufficient-sample)'` == 1, arm still `exit 1` — the only detector for the #6437 Sentry-dark mode. **Do not "fix" it to TRANSIENT.**
9. **AC9 — no arithmetic on an unguarded count. FOLDED INTO AC7 — do not verify by reading.** Every `sentry_count` result is string-guarded (`=~ ^[0-9]+$`) **before** any `(( ))` / `$(( ))` use — `:151` returns the bare word `TRANSIENT`, which arithmetic silently coerces to **0** (the hazard `:109-115` documents, and `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md` generalises: *"bash arithmetic is a thin wrapper around C `long`… if unset, it evaluates to `0`"*). ⚠ **The earlier draft guarded the single worst bug in the plan — `TRANSIENT` → 0 → false PASS → PAT revoked — with an eyeball** ("verify by reading each new call site"), while documenting the hazard three times. AC7's `curl` stub makes it a real test for free: HTTP 500 → assert `exit 2`. The plan's most-documented hazard becomes the gate's own exit code. Reading each new call site remains a *review* step, not the AC.
10. **AC10 — the D3 blocker is tracked AND enforced.** **#6500** exists with `priority/p1-high` (✅ filed), is linked from #6122, **and its number is wired into the soak's C1 arm**: `grep -c 'BLOCKER=6500' scripts/followthroughs/zot-soak-6122.sh` == 1. ⚠ Pin `BLOCKER=6500`, not bare `6500` — a bare-number grep matches a byte count, a line number, or a timestamp fragment. A deferral without a tracking issue is invisible; a known-fatal path without an exit-code gate is prose.
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
| **`accounted == expected ⇒ TRANSIENT on shortfall`** (the issue's literal wording) | Degenerate four ways; strictly dominated by the zero-evidence floor (`APP_ZOT == 0`), which has a *better* exit code and is saturation-immune. See `## Reversed During Planning`. **Surfaced as a User-Challenge.** |
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
