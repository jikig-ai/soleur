---
title: "fix(observability): close the zot soak's 2-of-4 signal blindness before it false-PASSes the GHCR-retirement gate"
date: 2026-07-15
issue: 6435
branch: feat-one-shot-6435-zot-soak-blind-signals
lane: cross-domain
type: bug
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(observability): zot-soak-6122.sh is blind to 2 of 4 fallback signals

Spec lacks valid `lane:` (no `spec.md` on this branch) — defaulted to `cross-domain` (TR2 fail-closed).

> **v4 — cut to ~⅓ of v3 on the simplicity panel's finding that the plan's own length was a
> correctness risk:** the single most important instruction in it (Sharp Edge 1) sat at line 670 of
> 708, and 708 lines of assurance around a ~30-line diff is *"a claim broader than its pin"* — this
> plan's own thesis, turned on itself. Revision archaeology removed; conclusions kept. Four review
> agents each falsified a claim this plan asserted; where that changes an instruction it is marked
> **⚠**, because those are the places an implementer's intuition will be wrong too.

## THE ONE THING TO GET RIGHT ⚠

**`stage:"app_ghcr_fallback"` must be queried BARE. `registry:"zot-gate-degraded"` must be PREFIXED.**

```bash
FAIL_QUERIES=(
  [gate]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'   # HAS feature/op
  [appboot]='stage:"app_ghcr_fallback"'                                       # has NEITHER
)
```

`ci-deploy.sh`'s jq payload carries `feature`+`op`; `cloud-init.yml:334`'s `_emit` writes only
`{stage,image_ref,host_id,detail}`. **Proven live:** `stage:"bootstrap_complete"` → **9**;
`feature:supply-chain op:image-pull stage:"bootstrap_complete"` → **0**. Control:
`registry:"zot-gate-degraded"` → **40** both bare and prefixed.

"Normalizing" these to a common prefix makes the fresh-boot query match **zero events forever** —
silently restoring the exact blindness this PR removes, inside the PR that removes it. Phase 1 pins
the **whole query string** so this cannot regress.

## Overview

`zot-soak-6122.sh` gates the **irreversible** retirement of GHCR (ADR-096 5.3–5.5; 5.5 rotates *and
revokes* the PAT — after it, a fleet still needing GHCR can pull from neither registry, with no
rollback). It runs four Sentry queries but counts only **two** of the **four** signals its companion
alarm (`sentry_issue_alert.zot_mirror_fallback_rate`) watches. `registry:"zot-gate-degraded"` and
`stage:"app_ghcr_fallback"` are counted by nothing; Sentry tag matching is exact, so the
`registry:"zot"` sample queries don't catch them either.

**The gate is, as committed, both inert and blind.** #6435 filed the blindness. The inertness is new
here: the script is mode **100644** — the only one of 26 probes that isn't 100755. ⚠ The sweeper
rejects it at an `[[ ! -x "$script" ]]` guard (`sweep-followthroughs.sh:173-176`) that runs **before**
the `env -i` exec, calling `fail()` — which is `printf … >&2` (`:30`) and nothing else — then
`return 0`. So: **no run, no exit code, no comment on the tracker, no TRANSIENT bucket.** The issue is
left open silently, discoverable only by eyeballing the sweeper job's stderr — an
`hr-no-dashboard-eyeball-pull-data-yourself` surface. **No query in this file has ever executed.**

*(An earlier revision claimed "exit 126 → TRANSIENT → retry forever". That 126 was real but came from
this plan's own hand-rolled reproduction, not from the sweeper's path — the sweeper never reaches
`env`. The conclusion — `chmod +x` is necessary — is unchanged; the mechanism was wrong, and the truth
is **worse**: a TRANSIENT comment would at least be visible on the issue.)*

Deliverables: (0) make it runnable and honest; (1) pin the FAIL set to the alarm; (2) count all four;
(3) stop the ADR claiming more than is pinned.

House pattern for this defect class: PR #6451 (merged 2026-07-15), recorded in
[`2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`](../learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md).

## What this plan does NOT fix

**The probe has no denominator.** `FALLBACKS == 0` means *"no GHCR service was reported"*, not *"none
occurred"*. The sibling probe has one — it enumerates workflow runs and turns any run it cannot
account for into TRANSIENT (`zot-mirror-connector-6416.sh:111-132`). **Adding numerator terms — all
this plan does — cannot close that.** Three residual holes, each deferred with an owner:

1. **Sentry-dark rolling deploys** — `ci-deploy.sh:776/777/780-783` returns *before every*
   `zot_gate_degraded_event` call site when `doppler` is absent, `DOPPLER_TOKEN` is unset, or
   `ZOT_REGISTRY_URL` is unset. Journald only. Caught **only** by the sample arm. → **#6437**.
2. ⚠ **Fresh-boot probe-miss** — the *dominant* path (34/38 live events) emits **nothing**.
   `cloud-init.yml:515-517`: if the `/v2/` probe misses, `REF` stays the GHCR ref, the pull succeeds
   first try, and the emit's guard (`REF != IMAGE_REF`, `:536`) never fires. So `FB_APPBOOT` catches
   only the *minority* branch. → new issue.
3. **No fresh-boot liveness** — no `app_zot` (inngest has one at `:697`), and `_emit` tags cannot
   satisfy the sample arm, so "0 fresh-boot fallbacks" ≡ "no fresh boot happened". → same issue.

**Consequence: this gate is necessary but NOT sufficient to authorize 5.5.** This plan makes it
strictly better and its claims honest. It does not make it sufficient — and the ADR must say so.

## When the defect bites

- **Today:** exit 126 (not executable). Even fixed, `START` is the literal `<POST_CUTOVER_UTC>` →
  Sentry 400 → exit 2. Verdict is **TRANSIENT**, and fail-safety rests on Sentry's date parser, which
  nothing verifies.
- **Total degradation (if START were pinned):** `FB_*=0` *and* `ZOT_*=0` → the sample arm FAILs.
- ⚠ **The bite window — intermittent degradation:** healthy deploys accumulate `ZOT_* >= MIN_SAMPLE`
  while degraded deploys stay invisible → both arms pass → **PASS** → GHCR retired → PAT revoked.
  The sample arm is a floor on *good* evidence, not a ceiling on *bad* — **except** for the
  Sentry-dark mode, where it is the only ceiling. That exception is why Phase 3c exists.

## User-Brand Impact

**If this lands broken, the user experiences:** a total, unrecoverable deploy outage — every rolling
deploy and fresh boot hard-fails at `pull_image_with_fallback`, with no rollback and no way back to
GHCR without minting a credential under incident pressure.

**If this leaks, the user's workflow is exposed via:** nothing. Verified at the emitters by the
Phase-2.7 gate (result: **no findings**): the probe requests `field=title&field=timestamp` and reads
only `.data | length`, never dereferencing a row. `host_id` is a Hetzner VM instance-id, not a natural
person. `_emit`'s free-form `detail` is structurally unreachable on an `app_ghcr_fallback` event
(emit at `N>=2`; `pull_err` append at `N>=5`, which exits into `on_err` emitting `stage=pull`).

**Brand-survival threshold:** `single-user incident` — **because of Phase 4**, not because the guarded
action is irreversible. (That weaker argument was rejected at review: by it, every test guarding an
irreversible action inherits the threshold and it stops discriminating.) Status quo is a *known-false*
parity claim, documented in #6435. A broken landing is a *believed-true* one, because this PR writes
the assurance into ADR-096. Combined with the prefix trap — which reads as coverage in the header, the
ADR, and the runbook while matching zero events forever — **a broken landing is strictly worse than
status quo.**

## Architecture Decision (ADR/C4)

**Amend ADR-096** (status *Adopting*; factual correction, no new ordinal).

- ⚠ **:112-113** — *"`zot-soak-6122.sh` FAILs this gate on >=1 fallback, so any threshold above 0 is
  strictly less sensitive than the gate it pre-warns"* is **false**: the alarm fires on any of 4, the
  gate on any of 2. Replacement must say the gate FAILs on ≥1 of the **same four signals**, and must
  state: window/threshold parity **not** pinned (the alarm is 1h-rolling per-issue-group; the soak is
  a flat count over `START..now`); FAIL set is **4-of-5**; fresh-boot coverage **partial**; therefore
  **necessary but not sufficient** for 5.3–5.5.
  **Do not write "the gate now matches the alarm" and stop** — that is the third generation of this
  same bug, and the first draft of this rewrite made exactly that mistake.
- **:14** — "zero ghcr-fallback" → "zero fallback events across all four watched signals".
- Record that the claim was false from #6278 until this PR (correct; don't silently edit).
- Anchor on **emit names, not line numbers** (ADR-096:128-129 mandates it; #6447 is line-rot live).

**C4: no impact.** All three `.c4` files read; externals enumerated. GHCR (`model.c4:254`), zot
(`:258`), Better Stack (`:262`) modeled; no actor, container, or access relationship changes
(`hetzner -> zotRegistry` `:386`, `-> ghcr` `:387`, `github -> tunnel` `:368` untouched). **Sentry is
not modeled** — a pre-existing, cross-cutting gap (the soak already queries it at `:57-61`), not
introduced here; deferred.

## Observability

```yaml
liveness_signal:
  what: PASS/FAIL/TRANSIENT verdict + per-signal counts to the sweeper comment
  cadence: daily via scheduled-followthrough-sweeper.yml, gated by earliest=
  alert_target: sweeper comments on the tracker; sentry_issue_alert.zot_mirror_fallback_rate pages
                IssueOwners→ActiveMembers on the same four signals at >0/1h
  configured_in: scripts/followthroughs/zot-soak-6122.sh + apps/web-platform/infra/sentry/issue-alerts.tf
error_reporting:
  destination: sweeper issue comment; Sentry for the underlying signals
  fail_loud: true — non-200, unset token, unpinned START, or a non-numeric count all exit 2
failure_modes:
  - mode: gate degraded (probe_unreachable/creds_absent/login_failed) → fleet silently on GHCR
    detection: registry:"zot-gate-degraded" — NEW here
    alert_route: soak FAIL (exit 1) + the issue-alert pages
  - mode: fresh web-host misses zot AFTER a successful probe → GHCR serves
    detection: stage:"app_ghcr_fallback" — NEW here (minority branch only; see §What this plan does NOT fix)
    alert_route: soak FAIL + the issue-alert pages
  - mode: rolling deploy attempts zot, fails, GHCR serves
    detection: registry:"ghcr-fallback" (existing)
    alert_route: soak FAIL + the issue-alert pages
  - mode: fresh inngest host misses zot, GHCR serves
    detection: stage:"inngest_ghcr_fallback" (existing)
    alert_route: soak FAIL + the issue-alert pages
  - mode: SENTRY-DARK (doppler/DOPPLER_TOKEN/ZOT_REGISTRY_URL absent) — emits nothing at all
    detection: NOT in the FAIL set and cannot be. Caught ONLY by the insufficient-sample arm.
               Owned by #6437; journald → Better Stack is its only positive signal
    alert_route: soak FAIL via the sample arm — which is why Phase 3c does not downgrade it
  - mode: fresh-boot probe-miss → GHCR serves silently (DOMINANT, 34/38)
    detection: NONE — no emit exists. Deferred (new issue); named in the header + ADR
    alert_route: none. This is why the gate is not sufficient for 5.5
  - mode: soak query set drifts from the alarm's filter set (THIS bug, recurring)
    detection: the Phase 1 parity leg + the four flat whole-query pins — fails CI, not prod
    alert_route: CI red on PR
  - mode: probe file is not executable
    detection: sweep-followthroughs.sh:173-176 rejects it BEFORE exec; fail() prints to stderr ONLY —
               no comment, no exit code, no TRANSIENT bucket. SILENT today. Phase 0.2's CI check moves
               detection to PR time, where it is visible
    alert_route: (today) none — sweeper job-log stderr only. This row is the gap, not the coverage
  - mode: probe runs but cannot report (token unset / Sentry unreachable / START unpinned)
    detection: exit 2 TRANSIENT; the sweeper comments TRANSIENT and retries
    alert_route: tracker stays open; never a PASS
logs:
  where: sweeper issue comment; GH Actions job log. Emits: Sentry + `logger -t ci-deploy` → Better Stack
  retention: Sentry per-project; GH Actions ~90d
discoverability_test:
  command: |
    cd apps/web-platform && ./node_modules/.bin/vitest run \
      test/sentry-zot-mirror-fallback-alert-op-contract.test.ts
  expected_output: "Test Files 1 passed" — incl. the parity leg. NO ssh.
```

## Implementation Phases

### Phase 0 — Make the probe runnable and honest

The unifying rule for what belongs here: **a fold-in earns its slot when the work you are already
shipping unmasks it.** Phase 0 makes this file's exit codes reachable for the first time in its life,
so every arm that reports a verdict must be correct *before* it can run.

- **0.1 Exec bit.** `chmod +x`; confirm `git ls-files -s …` prints **100755**.
- **0.2 ⚠ Guard the class, not the instance.** Add a CI check that **every** `scripts/followthroughs/*.sh`
  is mode 100755 (today: 25/26; `zot-soak-6122.sh` is the sole outlier). Fixing one file and hoping is
  this plan's own defect class — a probe that doesn't pin the thing it names. Cheaper than a bespoke
  AC and closes it forever.
- **0.3 Token arm.** Replace `: "${SENTRY_AUTH_TOKEN:?…}"` (`:29`) with the sibling's loop
  (`zot-mirror-connector-6416.sh:62-71`). `followthrough-convention.md:24` forbids the `:?` form **by
  name**: it aborts with status **1** = FAIL when the truth is "the probe could not run".
- **0.4 START guard.** `[[ "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "TRANSIENT: START is unpinned ($START)" >&2; exit 2; }`.
  Today's safety rests on Sentry 400ing the raw placeholder — an unverified vendor behaviour. Own it.
  *(This proves `START` is a timestamp, not that it is the **right** one — see Risks.)*

### Phase 1 — RED: the parity leg

Extend `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`. Baseline
verified green: **5 tests**, vitest v4.1.0. Its 5 legs pin the emit sites (×2), `issue-alerts.tf`
(×2), and the workflow (×1). **The soak is the third artifact and the only unpinned consumer** — that,
not "a 5th signal might come", is why this leg is justified. Both needed patterns already exist in the
file: block slicing (`:63-67`) and a repo-root read (`:82`).

- **1.1** Read via `join(here, "../../../scripts/followthroughs/zot-soak-6122.sh")` — **three** levels
  up (`../../` lands at `apps/` and does not exist; verified).
- **1.2** Alarm side: slice to `filters_v2 = [ … ]` (**not** the resource block) and collect
  `(key,value)` per `tagged_event`. ⚠ A value-only regex over the *resource* block returns the right
  4 today **only incidentally** (`event_frequency`'s `value = 0` is unquoted; `actions_v2` uses
  `target_type`) and over-collects on the first quoted filter added. Verified to yield exactly:
  `registry:ghcr-fallback`, `registry:zot-gate-degraded`, `stage:inngest_ghcr_fallback`,
  `stage:app_ghcr_fallback`.
- **1.3** Soak side: parse the **`FAIL_QUERIES` array block** (Phase 2) and pull `([a-z_]+):"([^"]+)"`
  from each entry — exactly one pair per entry, because only the signal tag is quoted
  (`feature:supply-chain`/`op:image-pull` are bare). Verified.
- **1.4 Derived set-equality:** `expect(soakFailSet()).toEqual(alarmFilterSet())`. **No canonical
  list** — a `WATCHED` constant is a third source of truth, not a parity test; cut at review. Derived
  equality gives the "5th signal breaks the test" tripwire for free.
- **1.5 ⚠⚠ Pin the whole query string for ALL FOUR signals — flat, one assertion each.** This is the
  only assertion that catches the prefix trap (a pair projection structurally discards the prefix):

  ```ts
  expect(soakQueryFor("ghcr-fallback")).toBe('feature:supply-chain op:image-pull registry:"ghcr-fallback"');
  expect(soakQueryFor("zot-gate-degraded")).toBe('feature:supply-chain op:image-pull registry:"zot-gate-degraded"');
  expect(soakQueryFor("inngest_ghcr_fallback")).toBe('stage:"inngest_ghcr_fallback"');   // BARE
  expect(soakQueryFor("app_ghcr_fallback")).toBe('stage:"app_ghcr_fallback"');           // BARE
  ```

  > **⚠ This paragraph is the correction of a P0 that review found in this plan's own primary fix.**
  > Earlier revisions pinned only **two** queries — `app_ghcr_fallback` and `zot-gate-degraded` —
  > because the *issue title* says "2 of 4 signals" and the pin set was inherited from that narrative
  > instead of re-derived from the file. **There are TWO bare-`stage` queries, not one:** `:58`
  > `stage:"inngest_ghcr_fallback"` carries the identical asymmetry and was pinned by nothing.
  > Reviewer implemented the plan faithfully and mutated `:58` to
  > `feature:supply-chain op:image-pull stage:"inngest_ghcr_fallback"`: **suite GREEN.** Consequence
  > — the soak silently stops counting inngest fresh-boot fallbacks → `FALLBACKS=0` → **PASS** → GHCR
  > retired → PAT revoked. That is #6435 exactly, reintroduced *through its own fix*, on the signal
  > family this plan flags as most dangerous.
  >
  > **Keep these four flat.** Do not "simplify" them into a loop over a table: four flat assertions
  > make a missing one obvious at a glance; a table hides it, which is how the P0 survived three
  > revisions and four reviewers. *Duplication beats cleverness in a pin.*
- **1.6** Confirm RED on current `main` before Phase 2. Then mutation-prove, recording each in the PR
  body: (a) delete an array entry; (b) add a 5th `tagged_event`; (c) prefix the `app_ghcr_fallback`
  query; **(d) prefix the `inngest_ghcr_fallback` query** ⚠ (the P0 above — this one went GREEN
  before the fix, so it is the single most important mutation in the set).

### Phase 2 — GREEN: count all four

- **2.1 ⚠ Refactor the FAIL set to a declared associative array**, so a query is **declared, guarded,
  and summed by the same loop** — "run but never counted" becomes *unrepresentable* rather than
  policed:

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
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: Sentry query '$k' failed (window $START..$END)" >&2; exit 2; }
    COUNTS[$k]=$n; FALLBACKS=$(( FALLBACKS + n ))
  done
  ```

  This deletes the separate guard loop, the hand-maintained sum, and four would-be ACs/tests. It also
  gives Phase 1 a **contiguous block** to parse instead of scattered assignments — structurally
  killing the vacuity risk, since a header comment cannot live inside the array. (`declare -A` needs
  bash 4+; the sweeper runs `#!/usr/bin/env bash` under a pinned FHS PATH — fine on CI Linux.)
- **2.2 Keep the remediation split** in the FAIL message via `COUNTS`: gate-degraded = zot never
  *attempted* (→ #6416/#6288); ghcr-fallback = attempted and *failed* (→ pull path). Per-signal
  counts, not just the total.
- **2.3 ⚠ `sentry_count` (`:52`): make a non-array `.data` an error.**
  `jq -r 'if (.data|type)=="array" then (.data|length) else error("no data array") end'`.
  **Why `:53` does not already cover this:** `:53` is
  `[[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "TRANSIENT"`, so a jq *failure* becomes TRANSIENT —
  but `'{}' | .data|length//0` yields **`0`**, which is numeric, so it sails through `:53` as a
  **counted zero**. Verified. With the fix, `{}` → jq rc 5 → empty → `:53` → TRANSIENT.
  *(`// 0` is dead code — `length` never returns null.)*
- **2.4 Rewrite the header** (`:9-11`, `:18`) to state: the four signals + their emitters (by **emit
  name**); that the FAIL set is pinned by the op-contract test; ⚠ **the prefix asymmetry** (this must
  live in the code, not only in the plan); that fresh-boot coverage is **partial** (probe-miss emits
  nothing) and has no `app_zot` liveness; and that the gate is **necessary, not sufficient**, for
  5.3–5.5. This satisfies #6435's stated scope — *"add the two signals **or** justify their exclusion
  in the header"* — by doing both.

### Phase 3 — Do NOT change the sample arm ⚠

**`:76-79` must keep `exit 1`.** An earlier revision proposed `exit 2` (TRANSIENT), citing
`followthrough-convention.md:25` and the sibling's thin-data shape — *and it would have shipped.* The
reasoning assumed the only route to `(fallbacks==0 && sample<3)` is "not enough deploys yet". It is
not: the Sentry-dark mode emits **nothing**, so `FALLBACKS=0` with no degrade event, and **the sample
arm is the only detector**. TRANSIENT would make a silently-unconfigured fleet report "retry next
sweep" forever. Encode the reason as a code comment at `:76` (AC6 pins it) — plan prose dies at merge.

### Phase 4 — ADR-096 amendment

Apply the :14 / :112-113 corrections above, **including the narrowing**.

### Phase 5 — Deferrals

| Deferred | Re-evaluation |
|---|---|
| ⚠ **Fresh-boot web observability gap + no denominator** (new issue; **blocks 5.3–5.5**) | Probe-miss emits nothing (`cloud-init.yml:515-517`); no `app_zot` (`:697` has the inngest counterpart); `_emit` tags can't satisfy the sample arm. Minimum closure: an unconditional per-boot "accounted" beacon **outside** every probe gate + `app_zot` + a soak arm asserting `accounted == expected` ⇒ TRANSIENT on shortfall — the sibling's denominator. **Not folded in: this is `cloud-init.yml`, the boot path** — highest blast radius in the repo, effective only on rebuild. Trading a bounded observability gap for an unbounded availability risk inside a probe fix is a bad trade. Link from #6122 as a retirement precondition |
| **Comment on #6437** | FAIL set is 4-of-5; attach the three-early-return trace |
| **Comment on #6122** | Enrollment is premature (`registry:"zot"` = 0/30d — the cutover hasn't happened). ⚠ Record that **`ZOT_SOAK_START` is dead code**: `sweep-followthroughs.sh:194` runs the probe under `env -i` with only `secrets=`-named vars, so pinning `START` is a **PR editing `:38`**, not a config change. Do not hand the operator a knob that isn't wired |

*Not filed (deliberately — an issue for a documented non-problem is backlog debt): `per_page=100`
saturation (harmless for `>0` and `>=3`; live max 40); the `issue-alerts.tf:1384` tag enumeration
(GDPR-gate Suggestion, advisory, fold into 2.4 if free); Sentry-absent-from-C4 (this PR adds zero
systems); #6427 (already tracked, no collision — 5.3 darkens three signals per ADR-096:124-131, and
`ci-deploy.sh:871-878` addresses the stop-push half; both are right).*

## Acceptance Criteria

> ⚠ **Use `/usr/bin/grep` in every AC below, explicitly.** `grep` in an interactive agent session here
> is a **ugrep 7.5.0 shell function** (`type grep` → "grep is a function"), while CI runs **GNU grep
> 3.12**. They diverge *on this plan's own ACs* — review found a pattern returning **1 under GNU grep
> and 0 under ugrep**. An agent that "verifies" an AC in-session can therefore see a false RED (or a
> false GREEN) that CI will not reproduce. This footgun invalidated part of this plan's own
> verification pass before review caught it.

### Pre-merge (PR)

1. `git ls-files -s scripts/followthroughs/zot-soak-6122.sh` → **100755**.
   *(Do NOT assert "exits 2 instead of 126" — the sweeper never execs a non-executable file; it
   rejects it at `sweep-followthroughs.sh:173-176` and prints to stderr only. The 126 is only
   reachable from a hand-rolled `env -i` harness, not from the real path.)*
2. The new CI check (0.2) fails when **any** `scripts/followthroughs/*.sh` is not 100755
   (mutation-proven against a deliberately chmod-ed sibling, then reverted).
3. ⚠ `FAIL_QUERIES` has 4 entries; **both** bare-`stage` values are exactly
   `stage:"inngest_ghcr_fallback"` and `stage:"app_ghcr_fallback"` (no prefix), and **both**
   `registry:` values are prefixed. Negative control, portable form:
   `/usr/bin/grep -cE "feature:[^']*stage:\"(app|inngest)_ghcr_fallback\"" …` → **0**.
   *(Do **not** use `[^\x27]` — GNU grep ERE has no `\x` escape, so it means "not backslash/x/2/7" and
   matches by luck. Use `[^']*` inside double quotes. `grep -c` **exits 1** on a 0 count — never chain
   with `&&`.)*
4. `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`
   → Test Files 1 passed, count **> 5**; mutation evidence for 1.6 **(a)(b)(c)(d)** in the PR body —
   **(d) is mandatory**, it is the P0 that went GREEN before this revision.
5. `/usr/bin/grep -cE ':\?SENTRY_AUTH_TOKEN|SENTRY_AUTH_TOKEN:\?' …` → **0** *(1 today)*;
   `/usr/bin/grep -c '// 0' …` → **0**; the `START` guard is present — assert it with an ERE
   (`/usr/bin/grep -cE 'START.*=~.*\^\[0-9\]\{4\}'` → **1**).
   *(⚠ **Not** BRE: in `grep -c '…\^\[0-9\]\{4\}'` the `\{4\}` binds to the preceding `\]`, so the
   pattern means `[0-9]]]]` and returns **0** against a correct implementation — verified under both
   GNU grep and ugrep. This plan shipped that broken AC for one revision.)*
6. ⚠ The sample arm still exits **1**, and carries the comment explaining why. *(Stops a future author
   "fixing" it to TRANSIENT and disarming the only detector for #6437's dark mode.)*
7. ADR-096: `grep -c 'FAILs this gate on >=1 fallback' …` → **0**; the replacement names all four
   signals **and** states window/threshold parity is not pinned.
8. `bash -n` clean; `bash scripts/sweep-followthroughs.test.sh` green; `bash scripts/test-all.sh` green.
9. Auto-close scan over the PR body **and** every commit body before each write:
   `grep -oniE '\b(close[sd]?|fixe?[sd]?|resolve[sd]?) +#[0-9]+'`. **6122 must never appear next to an
   auto-close keyword** (it stays open through Phase-5); 6435 is the only number one may precede.

### Post-merge (operator)

None. The soak's first live run is gated by `earliest=` and by the cutover, both owned by #6122.

## Domain Review

**Domains relevant:** Engineering, Legal (gate-triggered only)

### Engineering
**Status:** reviewed (CTO + code-simplicity + spec-flow + scoped `fable` consult)
**Assessment:** Applied — parity test rescoped to pin the *whole query string* (a value-only
extraction could not catch the plan's own #1 sharp edge); `WATCHED` cut as a third source of truth;
alarm extraction rescoped to `filters_v2` `(key,value)` pairs; the sample-arm `exit 1→2` fold-in
**cut** (it would have disarmed the only detector for the Sentry-dark mode); `ALARM_ONLY` cut
(an empty extensibility point that inverts its own purpose — a deleted test shows as a deletion, an
`ALARM_ONLY` entry reads as config); FAIL set refactored to a declared array, deleting 7 policing
artifacts; Phase 0 generalized to a CI check over all 26 probes; deferrals 8 → 3; document cut ~⅔.
Complexity: small (hours).

### Product
**Status:** **NONE.** Mechanical UI-surface override checked and did not fire — no path in *Files to
Edit* matches `components/**/*.tsx`, `app/**/page.tsx`, or any UI glob. No wireframe required.

### Legal
**Status:** reviewed (`/soleur:gdpr-gate`) — **no findings** (0 Critical, 0 Important, 1 Suggestion).
Invoked under expansion trigger **(b)** (declared threshold), *not* the canonical regulated-data
regex, which matches no edited path. Verified at the emitters, not from the tf comment. No new
processing activity → no Art. 30 entry; no Art. 9 risk; no lawful-basis gap. Nothing written to
`compliance-posture.md`. *Advisory only — not legal review.*

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| ⚠ **No query in this script has ever run** — non-executable *and* `START` unpinned *and* `stage:"app_ghcr_fallback"` has never emitted (0/90d; absent from the live `stage` tag-value list). "Validate the anchor against a real emit" is **unsatisfiable** | Validate against the **emitter** (`cloud-init.yml:334` writes `tags.stage` from `$2`; `:537` passes the literal) **and** against live Sentry using a stage value that *does* exist (bare → 9, prefixed → 0). Then let the parity test carry what a live emit cannot — that is why the test is the primary fix |
| **Parity is consumer↔consumer**: if the shared literal or query *shape* were wrong, alarm and soak would be blind together and the test green | The existing legs already pin the **emit sites** (`:37-45`); 1.5 pins the *shape* against the emitter's real tag schema; the live bare-vs-prefixed proof validates it against real traffic |
| ⚠ **`START` mis-pinned LATE is a false-PASS route** — it excludes flip-day fallbacks while the remaining days still clear `ZOT_* >= 3` (trivially met). The 1.8-vs-flip asymmetry makes this *worse*: the two new signals are live from task 1.8, so a late pin is exactly when they read 0, and the script cannot tell "0 because healthy" from "0 because out of window" | 0.4 proves `START` is a timestamp, **not that it is the right one** — say so rather than implying otherwise. Nothing asserts `START <= cutover_utc`; folded into the #6122 enrollment comment, since only the cutover PR knows the true UTC. Honest statement: **the window bound is operator-asserted and unverified** |
| Adding signals makes the soak harder to pass; an early `START` false-FAILs on pre-flip events | **Accept — the asymmetry is the point.** A false-FAIL costs a soak restart; a false-PASS costs an irreversible retirement. But *a gate that cannot pass gets bypassed* — hence 0.4's legible message |
| **Partial Sentry outage defeats the FAIL set** — every FAIL-side emit is fail-open by construction, and `ci-deploy.sh:878` records `zot-gate-degraded` as the highest-volume signal, i.e. first shed | Out of scope (the emit sites' fail-open contract is deliberate — telemetry must never block a boot). 2.3 closes the probe-side half; the emit-side half is #6437's. **Named in the ADR** rather than left implicit |
| `MIN_SAMPLE=3` is not a fleet-coverage claim (3 pulls to the *same* host passes; `host_id` is tagged but unused) | One comment line at the constant; folded into the denominator issue |

## Files to Edit

- `scripts/followthroughs/zot-soak-6122.sh` — mode 100755; token arm; START guard; `FAIL_QUERIES`
  array + 2 new signals; `sentry_count` hardening; header rewrite; sample-arm comment
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — the parity leg
- `knowledge-base/engineering/architecture/decisions/ADR-096-…-zot.md` — :14 + :112-113
- CI: the followthrough exec-bit check (0.2)

**Read-only — each a named residual with an owner:** `apps/web-platform/infra/ci-deploy.sh`
`:776/777/780-783` (Sentry-dark → **#6437**); `apps/web-platform/infra/cloud-init.yml` `:515-517`,
`:697` (fresh-boot gap → new issue; **boot path** — own PR, own rollout).

## Files to Create

None (plus the CI check, wired into an existing workflow).

## Open Code-Review Overlap

**None.** All 62 open `code-review` issues checked against every path in *Files to Edit* — zero body
matches.

## Sharp Edges

1. ⚠ **The prefix asymmetry** — see §THE ONE THING TO GET RIGHT. Pinned by 1.5's **four flat**
   assertions, not by a one-shot grep. **There are TWO bare-`stage` queries, not one** — `:58`
   `inngest_ghcr_fallback` as well as the new `app_ghcr_fallback`.
1b. ⚠ **Derive the pin set from the FILE, never from the issue's framing.** The P0 above — the fix
   reintroducing the filed bug on the most dangerous signal family — happened because the pin set was
   inherited from the issue title's *"2 of 4 signals"* narrative and never re-derived by grepping the
   script. Three revisions and four review agents missed it; only implementing the plan and mutating
   `:58` exposed it. The issue names the *defect*; the file names the *surface*. Generalization of the
   repo's paraphrase-without-verification rule to a plan's own **assertion set**, not just its cited
   facts.
2. **Never `toContain` against the whole soak file** — 2.4 puts both literals in the header comment, so
   a whole-file assertion passes with the queries deleted. The array block (2.1) makes this
   structural: a comment cannot be inside the array.
3. **Derive, don't declare** — a canonical list in the test is a third source of truth.
4. **Scope the alarm extraction to `filters_v2`, on `(key,value)` pairs** — resource-block value-only
   scoping is *incidentally* correct today and will go RED for an unrelated reason later, which is how
   tests get deleted.
5. ⚠ **Do NOT "fix" the sample arm to TRANSIENT** (Phase 3) — it is the only detector for #6437's dark
   mode. An earlier revision proposed exactly that, with a citation that appears to mandate it.
6. **Adding numerator terms cannot close a denominator gap.** Reach for the sibling's `// "absent"`
   pattern, not a sixth query.
7. ⚠ **`sentry_count:53` already normalizes to `^[0-9]+$` or `TRANSIENT`** — so the empty string cannot
   escape it, and a loop-side guard is *not* "strictly stronger". Three successive revisions of this
   plan got that rationale wrong because a one-line contract 20 lines up was invisible under the
   volume. **Read `:52-53` before reasoning about any count's error path.**
8. **`bash -n` and `bash script.sh` both mask the exec-bit bug** — `bash -n` passes on a
   non-executable file; `bash script.sh` bypasses the bit. Verify with `env -i … "$script"`, the
   sweeper's real shape. Nothing caught this for the life of the file.
