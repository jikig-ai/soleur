# Acceptance record — #7555 (zot HTTP deadlines)

Every pre-merge AC from the plan, with the command run and its output. Re-derived at
implementation rather than restated from the plan (plan-quoted numbers are preconditions).

| AC | Command | Result |
|---|---|---|
| 1 | `bash plugins/soleur/test/reusable-release-degraded-pointer.test.sh` | 21/21 — every loop-derived `copy_*` reason + `verify` emits the upload pointer with all three anchors |
| 2 | same suite (separate assertions) | `bridge`/`crane_install` still emit the host-health pointer AND not the upload pointer — separately falsifiable |
| 3 | same suite, AC3 section | each of the three `BETTERSTACK_QUERY_*` absent individually → FAILED READ, never a no-samples measurement; plus an error-payload-on-exit-0 arm |
| 4 | `grep -rn 'zot_mirror_diagnosis' --include=*.yml --include=*.sh` | 3 invocations (1 in `reusable-release.yml`, 2 in `cf-tunnel-registry-bridge/action.yml`) + 1 `declare -F` guard. Both action.yml sites already pass an explicit non-measurement string; `reusable-release.yml` was the sole outlier |
| 5 | `bash scripts/zot-mirror-diagnosis.test.sh` | 54 passed, `MIN_ASSERTIONS=50` floor unchanged |
| 6 | `bash apps/web-platform/infra/zot-log-shipper.test.sh` | 164 passed, `>= 150` floor and `CANARY_OK` intact |
| 7 | `bash apps/web-platform/infra/zot-config-deadlines.test.sh` | 8/8 against the **rendered** config via `registry-userdata-budget.sh` |
| 8 | same suite, negative control | pinned digest rejects `zzzboguskey`: `'HTTP' has invalid keys: zzzboguskey` |
| 9 | Guard 2 battery row 1 | widened `JQ_TICK` + unwidened `read -r` → RED |
| 10 | shipper suite T19 | 17 ordinary 5xx rows then a panic trace → the panic still ships |
| 11 | three mutation batteries | Guard 1 7/7, Guard 2 7/7, Guard 3 8/8 — each against a green control, each mutation asserted to have LANDED against a pristine backup |
| 12 | `bash scripts/lint-diagnosis-claims.sh` | OK — 1 unmeasured causal claim, baseline 1, `.highwater` unmodified |
| 13 | `bash apps/web-platform/infra/registry-userdata-budget.sh --json` | `stored_bytes=13412 cap=32768 headroom=19356` — above the ADR-185 floor of 8000 |
| 14 | `python3 scripts/lint-guard-contract.py <plan>` | 1 plan, 3 guard entries |
| 15 | `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` | OK, 5 files |
| 16 | `actionlint` + `bash tests/scripts/test-registry-replace-preflight.sh` | dispatcher clean; 15/15 with synthesized red readings for P0/P1/P3 |
| 17 | the plan's own scoped `grep` | no `<new-issue>` / `<tracker>` placeholder in shipped files |
| 18 | PR body | `Closes #7555` + `Ref #7341`; does not carry `Closes #7341` |

## Deviations from the plan, and why

1. **AC-adjacent, Guard 1's family split.** The plan enumerated `copy_*`/`verify` and
   `bridge`/`crane_install`. `sign` is a live `degraded()` reason in **neither**, so a two-arm
   branch would have let it silently inherit whichever pointer was written first — the exact
   defect being fixed. Added a third arm that emits BOTH and asserts NEITHER.

2. **Phase 3 pre-check module.** The plan said reuse `scripts/registry-pull-path-health.sh`.
   Measured: it is the pre-*destroy* gate for `registry-luks-recut`, renders a verdict only by
   executing a restore rehearsal (it pushes images), and its pass condition concerns an *empty*
   store — while this replace preserves the volume. Routed to the `cto` agent per the
   architectural-fork hard gate; it ruled for a read-only preflight and noted the plan's own cited
   authority already prescribes one. Plan Phase 3 carries a superseded marker; ADR-190 carries the
   negative decision.

3. **GHCR-fallback comment sweep.** The plan named `variables.tf`. Sweeping by CLAIM rather than
   by file found two more live twins in `apply-web-platform-infra.yml`, which a prior change had
   explicitly recorded as left behind. Their dependent "non-release-blocking" clauses were false
   for the same reason and were corrected with them.

4. **ADR ordinal 189 → 190.** A sibling branch claimed 189 nine minutes after this branch did. By
   the plan's rule the later claimant renumbers, but yielding costs one sweep and contesting risks
   stalling a P1 behind an ordinal dispute.

## Pre-existing defect found and repaired in passing

`is_cap_exempt` matches the PARSED zerolog `message` field, which is empty for any line that is
not zot JSON — and a Go panic is written to stderr as plaintext. So the four crash arms #7444 R12
added (`panic:`, `fatal error`, `runtime error`, `[signal`) could never match the input they were
added for, leaving the crash class droppable at the cap during exactly the crash flood R12 exists
to survive. Verified against `origin/main`. The existing suite missed it because its panic
fixtures wrap the panic text *inside* a JSON `message` field. Repaired by falling back to the raw
line only when the parsed message is empty, which keeps the #7444 F-5 whole-line bypass closed by
construction; both directions are pinned by T19.

## Not verifiable pre-merge

AC19-21 grade the replace and the soak. They are owned by the #7556 follow-through probe
(`earliest=2026-08-21`), not by this PR. Merging fires a release against the **still-un-replaced**
host; that run is explicitly not evidence for or against this change.
