---
feature: feat-one-shot-6435-zot-soak-blind-signals
issue: 6435
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-15-fix-zot-soak-blind-to-two-fallback-signals-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — zot soak: close the 2-of-4 signal blindness

Derived from the plan (v3, post plan-review). **Read the plan first** — several tasks below invert
the "obvious" fix, and the reasons are recorded there, not here.

**PR body must use `Ref #6122` (never an auto-close keyword next to 6122)** — the parent stays open
through Phase-5. `Closes` is valid only for the child, 6435.

## Phase 0 — Make the probe runnable and honest (gates everything)

**Rule for what belongs here:** a fold-in earns its slot when the work you are already shipping
unmasks it. Phase 0 makes this file's exit codes reachable for the first time in its life.

- [ ] 0.1 `chmod +x scripts/followthroughs/zot-soak-6122.sh`; `git add`; confirm
      `git ls-files -s …` prints **100755** (25/26 siblings already are; this is the only outlier).
      ⚠ **Do not claim "exit 126 → TRANSIENT"** — `sweep-followthroughs.sh:173-176` rejects a
      non-executable script at an `[[ ! -x ]]` guard *before* `env -i`, via `fail()` which is
      `printf … >&2` only. No run, no exit code, **no comment on the tracker**. Silent.
- [ ] 0.2 ⚠ Add a CI check that **every** `scripts/followthroughs/*.sh` is 100755. Fixing one file and
      hoping is this plan's own defect class. Mutation-prove it (chmod a sibling, see RED, revert).
- [ ] 0.3 Token arm: replace `: "${SENTRY_AUTH_TOKEN:?…}"` (`:29`) with the sibling's loop
      (`zot-mirror-connector-6416.sh:62-71`). `followthrough-convention.md:24` forbids the `:?` form
      by name (aborts status 1 = FAIL when the truth is "could not run").
- [ ] 0.4 START guard:
      `[[ "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "TRANSIENT: START is unpinned ($START)" >&2; exit 2; }`
      Today's safety rests on Sentry 400ing the raw placeholder — an unverified vendor behaviour.

## Phase 1 — RED: the cross-artifact parity leg

Extend `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`.
Baseline verified green: **5 tests**, vitest v4.1.0.

- [ ] 1.1 Read the soak via `join(here, "../../../scripts/followthroughs/zot-soak-6122.sh")`
      (**three** levels up — `../../` resolves to `apps/` and does not exist). Precedent for a
      repo-root read already exists in this file at `:82`.
- [ ] 1.2 Extract the **alarm** side: slice to `filters_v2 = [ … ]` (NOT the resource block) and
      collect `(key, value)` per `tagged_event`. Verified to yield exactly:
      `registry:ghcr-fallback`, `registry:zot-gate-degraded`, `stage:inngest_ghcr_fallback`,
      `stage:app_ghcr_fallback`.
- [ ] 1.3 Extract the **soak** side: match `FB_` assignment lines only
      (`/^\s*FB_[A-Z_]+=\$\(sentry_count\s+'([^']*)'\)/m`), then pull `([a-z_]+):"([^"]+)"` from each.
      **`FB_`/`ZOT_` partition is load-bearing** — sample lines yield two pairs each and would
      corrupt the set. Filter to keys present in the alarm's key set; assert each `FB_` line
      contributes exactly one surviving pair.
- [ ] 1.4 Assert **derived** set-equality: `expect(soakFailSet()).toEqual(alarmFilterSet())`.
      **Do NOT introduce a canonical/`WATCHED` list** — it is a third source of truth and was cut at
      review. Derived equality gives the "5th signal breaks the test" tripwire for free.
- [ ] 1.5 ⚠⚠ Pin the **whole query string** for **ALL FOUR** signals — flat, one assertion each.
      A pair projection structurally discards the prefix, so this is the only thing catching the trap:
      - `soakQueryFor("ghcr-fallback")` === `feature:supply-chain op:image-pull registry:"ghcr-fallback"`
      - `soakQueryFor("zot-gate-degraded")` === `feature:supply-chain op:image-pull registry:"zot-gate-degraded"`
      - `soakQueryFor("inngest_ghcr_fallback")` === `stage:"inngest_ghcr_fallback"`  ← **BARE**
      - `soakQueryFor("app_ghcr_fallback")` === `stage:"app_ghcr_fallback"`          ← **BARE**

      **This is a P0 correction.** Earlier revisions pinned only two, because the pin set was
      inherited from the issue title's "2 of 4 signals" narrative instead of derived from the file.
      **There are TWO bare-`stage` queries** — `:58` was pinned by nothing, and prefixing it left the
      whole suite GREEN while the soak silently stopped counting inngest fresh-boot fallbacks.
      **Keep the four flat** — a loop hides a missing one; that is how this survived 3 revisions.
- [ ] 1.6 Confirm **RED on current main** before Phase 2.

## Phase 2 — GREEN: count all four

- [ ] 2.1 ⚠ Refactor the FAIL set to a declared associative array so a query is **declared, guarded,
      and summed by the same loop** — "run but never counted" becomes *unrepresentable*:

      ```bash
      declare -A FAIL_QUERIES=(
        [rolling]='feature:supply-chain op:image-pull registry:"ghcr-fallback"'
        [gate]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'
        [freshboot]='stage:"inngest_ghcr_fallback"'
        [appboot]='stage:"app_ghcr_fallback"'
      )
      declare -A COUNTS; FALLBACKS=0
      for k in "${!FAIL_QUERIES[@]}"; do
        n=$(sentry_count "${FAIL_QUERIES[$k]}")
        [[ "$n" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: Sentry query '$k' failed" >&2; exit 2; }
        COUNTS[$k]=$n; FALLBACKS=$(( FALLBACKS + n ))
      done
      ```

      Deletes the separate guard loop, the hand-maintained sum, and ~4 would-be ACs/tests. Gives
      Phase 1 a contiguous block to parse. (`declare -A` needs bash 4+; fine under the sweeper's
      `#!/usr/bin/env bash` + pinned FHS PATH on CI Linux.)
      ⚠ **`[appboot]` and `[freshboot]` are BARE stage. NEVER prefix them.** Verified live: prefixed
      `stage:` → 0 where bare → 9. Comment the asymmetry as deliberate.
- [ ] 2.2 Keep the remediation split in the FAIL message via `COUNTS`: gate-degraded = zot never
      *attempted* (→ #6416/#6288); ghcr-fallback = attempted and *failed* (→ pull path). Per-signal
      counts, not just the total.
- [ ] 2.3 ⚠ `sentry_count` (`:52`): make a non-array `.data` an error —
      `jq -r 'if (.data|type)=="array" then (.data|length) else error("no data array") end'`.
      **Why `:53` doesn't already cover it:** `:53` is `[[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "TRANSIENT"`,
      so a jq *failure* → TRANSIENT — but `'{}' | .data|length//0` → **`0`**, which is numeric and
      sails through as a **counted zero**. Verified. (`// 0` is dead code; `length` never returns null.)
      **Do NOT add a rationale about the empty string** — `:53` already makes it unreachable; three
      revisions of this plan got that wrong.
- [ ] 2.5 Rewrite the header (`:9-11`, `:18`) to **disclaim** what the gate cannot see — all six
      bullets in plan Phase 2.4, including: fresh-boot coverage is PARTIAL (probe-miss emits
      nothing); no `app_zot` liveness; FAIL set is 4-of-5; no query has ever executed; **necessary,
      not sufficient, for 5.3–5.5**. Anchor on emit names, not line numbers.

## Phase 3 — Do NOT change the sample arm ⚠

- [ ] 3.1 **`:76-79` must keep `exit 1`.** An earlier revision proposed `exit 2` (TRANSIENT), citing
      `followthrough-convention.md:25` and the sibling's thin-data shape — **and it would have
      shipped.** The reasoning assumed the only route to `(fallbacks==0 && sample<3)` is "not enough
      deploys yet". It is not: the Sentry-dark mode (`ci-deploy.sh:776/777/780-783` — three early
      returns *before every* `zot_gate_degraded_event` call site) emits **nothing**, so `FALLBACKS=0`
      with no degrade event, and **the sample arm is the only detector**. TRANSIENT would make a
      silently-unconfigured fleet report "retry next sweep" forever.
      Encode the reason as a **code comment at `:76`** — plan prose dies at merge; the comment doesn't.

## Phase 4 — ADR-096 amendment

- [ ] 4.1 Fix `:112-113` — the parity claim is false. Replacement must say the gate FAILs on ≥1 of the
      **same four signals**, and must explicitly state: window/threshold parity **not** pinned; FAIL
      set is **4-of-5** (Sentry-dark, #6437); fresh-boot coverage **partial**; therefore the soak is
      **necessary but not sufficient** for 5.3–5.5.
      **Do not write "the gate now matches the alarm" and stop** — that sentence is the third
      generation of this same bug.
- [ ] 4.2 Fix `:14` — "zero ghcr-fallback" → "zero fallback events across all four watched signals".
- [ ] 4.3 Record that the claim was false from #6278 until this PR (correct, don't silently edit).

## Phase 5 — Deferrals (3 only; trimmed from 8 at review — an issue for a documented non-problem is backlog debt)

- [ ] 5.1 **NEW issue — fresh-boot web observability gap + no denominator** (largest residual;
      **blocks 5.3–5.5**): probe-miss emits nothing (`cloud-init.yml:515-517`); no `app_zot` liveness
      (inngest has one at `:697`); `_emit` tags can't satisfy the sample arm; and the probe counts bad
      events but never deploys/boots. Minimum closure: an unconditional per-boot "accounted" beacon
      **outside** every probe gate + `app_zot` + a soak arm asserting `accounted == expected` ⇒
      TRANSIENT on shortfall (the sibling's denominator). **Not folded in:** `cloud-init.yml` is the
      boot path — own PR, own review, own rollout. Link from #6122 as a retirement precondition.
- [ ] 5.2 **Comment on #6437** — FAIL set is 4-of-5; attach the three-early-return trace.
- [ ] 5.3 **Comment on #6122** — enrollment premature (`registry:"zot"` = 0/30d; cutover hasn't
      happened). ⚠ Record that **`ZOT_SOAK_START` is dead code**: `sweep-followthroughs.sh:194` runs
      the probe under `env -i` with only `secrets=`-named vars, so pinning `START` is a **PR editing
      `:38`**, not a config change. Do not hand the operator a knob that isn't wired.

*Deliberately NOT filed: `per_page=100` saturation (harmless; live max 40); `issue-alerts.tf:1384` tag
enumeration (GDPR Suggestion — fold into 2.4 if free); Sentry-absent-from-C4 (this PR adds zero
systems); #6427 (already tracked, no collision).*

## Phase 6 — Verify

- [ ] 6.1 ⚠ Run every AC with **`/usr/bin/grep`**, not bare `grep` — the session's `grep` is a
      **ugrep shell function**; CI is **GNU grep 3.12**, and they diverge on this plan's own ACs.
      Re-run everything; do not trust the plan's transcript.
- [ ] 6.2 Mutation evidence, all RED: (a) delete an array entry; (b) add a 5th `tagged_event`;
      (c) prefix `app_ghcr_fallback`; **(d) prefix `inngest_ghcr_fallback`** ⚠ — (d) is the P0 that
      was GREEN before the fix, so it is the most important one. Record in the PR body.
- [ ] 6.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`
      → Test Files 1 passed, count > 5 (baseline verified: 5, vitest v4.1.0).
- [ ] 6.4 `bash scripts/sweep-followthroughs.test.sh` still green.
- [ ] 6.5 Full suite: `bash scripts/test-all.sh`.
- [ ] 6.6 Auto-close scan over the PR body **and** every commit body before each write:
      `/usr/bin/grep -oniE '\b(close[sd]?|fixe?[sd]?|resolve[sd]?) +#[0-9]+'`. **6122 must never
      appear** next to an auto-close keyword.
- [ ] 6.7 Stage explicit paths — **never `git add -A`**. Phase 0 stages a *mode* change, easy to lose.
