## Status refresh after the cc-path drain (PR #3802)

The cc-path / dispatcher cleanup drain landed (closes #3343 + #3344). #3243
stays open with this refreshed status — the original "mirrorWithDebounce
first" target named by the issue body has already been extracted in earlier
work, so the cleanest next step is a different small extraction with its
own ADR.

### What's already done

- `mirrorWithDebounce` extraction — the issue's named "smallest, most
  self-contained" target — landed in **PR #3608** (`fix(cc): V2 Command
  Center hardening — safe-bash module, mirror debounce, idle-reaper,
  wall-clock budget`) and was further consolidated in **PR #3670**
  (`refactor(cc-dispatcher): cluster drain (#3639 + #3640 + #3641 +
  #3642)`). `mirrorWithDebounce` now lives in
  `apps/web-platform/server/observability.ts`; `cc-dispatcher.ts` only
  imports it.

### Where this leaves the decomposition

`cc-dispatcher.ts` is currently ~1900 lines (grew past the issue's
original 937-line snapshot — see `wc -l apps/web-platform/server/cc-dispatcher.ts`).
The remaining concerns identified in the original issue body still
co-exist in the file:

- `realSdkQueryFactory` (~180 lines) → candidate for `cc-query-factory.ts`
- `_ccBashGates` registry + lifecycle → candidate for `cc-bash-gates.ts`
- `PendingPromptRegistry` + reaper → candidate for `cc-singletons.ts`
- `StartSessionRateLimiter` singleton → candidate for `cc-singletons.ts`
- `WORKFLOW_END_USER_MESSAGES` user-copy map + exhaustiveness rail →
  candidate for `cc-workflow-end-messages.ts`

### Next concrete extraction (recommended)

**`cc-workflow-end-messages.ts`** is the smallest unit left. It's a pure
data map plus a TypeScript exhaustiveness rail — ~15 LoC, no behavior
change, near-zero risk. Pulling it first re-establishes the "one PR per
extraction" cadence the issue's AC asks for, with the most reviewable
possible diff. The reaper-interval extraction (`cc-singletons.ts`)
should follow only after `cc-workflow-end-messages.ts` lands clean.

Each extraction PR should:

1. Open an ADR documenting the new module boundary (per the issue's
   original AC).
2. Re-thread types/exports across importers (ws-handler.ts,
   soleur-go-runner test scaffolding, multiple test files).
3. Run the full `apps/web-platform` vitest suite as the regression gate.

### Why this issue stays open as a roadmap pointer

The `deferred-scope-out` + `code-review` labels and the `Post-MVP /
Later` milestone reflect that the decomposition is real work to do — it
just doesn't fit a single PR. Closing this issue now would lose the
multi-PR roadmap; keeping it open as the index issue lets each follow-up
extraction PR cite this issue and tick off one concern at a time.

### Re-evaluation criteria (unchanged)

- A future PR introducing a new concern in this file would exceed
  1100 lines (current ~1900 lines is well past that threshold —
  reinforces the case for the next extraction).
- A test file's boilerplate (importing 5+ helpers from cc-dispatcher)
  signals the orchestration intent has been lost.
- A new contributor reports being unable to navigate the file in an
  onboarding session.
