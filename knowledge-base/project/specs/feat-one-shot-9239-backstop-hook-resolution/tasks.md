# Tasks: memory-backstop version-independent hook resolution (#9239)

Plan: `knowledge-base/project/plans/2026-09-29-fix-backstop-hook-version-resolution-plan.md`

Execution order: Phase 1 (failing tests), Phase 2 (hook + resolver + payload), Phase 3 (wiring,
guards, docs), Phase 4 (ADR/C4). Contract-before-consumer ordering: the `BACKSTOP_REVISION`
marker and ledger fields land in the hook (2.1) before the resolver consumes them (2.2).

## Phase 1: Failing tests first

- [ ] 1.1 Write `.claude/hooks/memory-backstop-resolve.test.sh`: fixture candidate dirs under
      `TMPDIR` (managed/plugin/checkout layouts); revision parsing incl. absent/non-numeric
      marker -> 0; precedence + tie-break (checkout wins ties); `bash -n` demotion to next
      candidate; atomic publish (`tmp`+`mv`, mode 0755, `lib/log-rotation.sh` carried);
      publish serialized under `flock` with in-lock re-check; never-sourcing assertion (grep
      the shim for `source`/`.` of candidate paths -> none); exit 0 on every fixture failure;
      `--print-resolution` emits `resolved=<path> revision=<n>` read-only.
- [ ] 1.2 Extend `.claude/hooks/memory-backstop.test.sh`: pin `_repo_root`'s existing
      `CLAUDE_PROJECT_DIR` preference under a fake managed-dir exec; ledger carries `schema:2`,
      `backstop_revision`, `resolved_from`, `repaired`; `repair_stale_scopes` fixture arm
      (stubbed `systemctl`/`busctl` on PATH, unit list as argument — no env seams) asserting
      `SetUnitProperties` fires only on mismatched scopes and BindsTo is never written; live
      arm repairs a deliberately-miscapped `soleurtest-*` scope; `live_mark` placement per
      #8008 guidance (mark at emission, not reachability).
- [ ] 1.3 Write `plugins/soleur/test/backstop-parity.test.ts` (Guards 2+3: byte-equal vendored
      copy, `BACKSTOP_REVISION` marker present, settings.json binds the resolver).
- [ ] 1.4 Extend `.claude/hooks/memory-backstop-mutation-battery.sh`: mutant stripping
      `BACKSTOP_REVISION` (resolver demotes to rev 0); mutant dropping `TasksMax` from the
      repair call (repair-verify arm reddens).

## Phase 2: Hook + resolver + payload

- [ ] 2.1 `.claude/hooks/memory-backstop.sh`: `readonly BACKSTOP_REVISION=1` + header bump
      contract beside the cap constants (~line 78); `MAX_REPAIR=32` beside `MAX_SWEEP`;
      `repair_stale_scopes()` called inside the flock after `sweep_unadopted_agents`
      (`systemctl --user list-units` enumeration of `soleur-agent-*.scope`, per-scope
      `systemctl show` cap readback, runtime-only `busctl SetUnitProperties` on mismatch,
      never BindsTo); ledger `schema:2` + `backstop_revision`/`resolved_from`/`repaired`
      fields (read `${SOLEUR_BACKSTOP_RESOLVED_FROM:-}` defensively — empty when run
      directly).
- [ ] 2.2 Write `.claude/hooks/memory-backstop-resolve.sh` per plan M1: candidate enumeration
      (checkout, `${XDG_DATA_HOME:-$HOME/.local/share}/soleur/hooks/`, Claude plugin-cache
      glob, Devin plugin-cache glob), grep-only revision extraction, max-revision selection
      with precedence-order ties, `bash -n` demotion, serialized atomic self-publish
      BEFORE exec, `SOLEUR_BACKSTOP_RESOLVED_FROM`/`_REVISION` exports, `exec bash "$winner"`,
      `--print-resolution` mode, `RESOLVER_REVISION=1` marker, unconditional `exit 0` with
      `systemMessage` JSON on total failure (jq-guarded, printf fallback).
- [ ] 2.3 `cp .claude/hooks/memory-backstop.sh plugins/soleur/hooks/memory-backstop.sh`,
      `chmod 0755`; do NOT register it in `plugins/soleur/hooks/hooks.json` (payload only);
      regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt`.

## Phase 3: Wiring, guards, docs

- [ ] 3.1 `.claude/settings.json`: SessionStart command -> `bash
      "$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop-resolve.sh`.
- [ ] 3.2 `scripts/check-backstop-revision.sh` (Guard 1: hook in merge-base diff implies
      `BACKSTOP_REVISION=` line differs; tempfile diff capture; explicit `NO-OP` verdict when
      untouched; missing-script failure propagates) + invoke step in
      `.github/workflows/pr-quality-guards.yml`.
- [ ] 3.3 `.claude/hooks/README.md`: resolution-order section, managed path, ledger schema:2
      fields, revision-bump contract for local edits (an un-bumped local edit loses
      resolution to a newer installed copy).

## Phase 4: Decision record

- [ ] 4.1 Author ADR-261 (provisional — re-verify next-free ordinal against `origin/main` at
      ship time) "version-independent hook resolution via managed-path newest-copy
      selection" via `soleur:architecture`; record rejected alternatives (systemd --user
      timer sweeper, per-checkout-only status quo, source-for-version).
- [ ] 4.2 Update `model.c4` `hooks` container description for the resolution boundary
      (+ optional `soleurManagedHooks` element/`views.c4` edge if it reads better);
      run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Verification

- [ ] V.1 `bash .claude/hooks/memory-backstop-resolve.test.sh` and
      `bash .claude/hooks/memory-backstop.test.sh` green (live arm marks or skips loudly).
- [ ] V.2 `bun test plugins/soleur/test/backstop-parity.test.ts` green; plugin suite green
      (no component-census regression from the vendored file).
- [ ] V.3 `bash scripts/check-backstop-revision.sh` — NO-OP/pass on the branch once it only
      adds the marker (the marker introduction IS the revision change; from then on every
      hook-diff must carry a bump).
- [ ] V.4 markdownlint clean on the plan, tasks.md, README, ADR.
- [ ] V.5 Tick AC1-AC12 in the plan; the PR body uses `Closes #9239`.
