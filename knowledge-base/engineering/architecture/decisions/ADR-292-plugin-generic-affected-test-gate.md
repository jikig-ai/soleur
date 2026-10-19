# ADR-292: The plugin ships a stack-agnostic affected-test gate; the repo-local runner is the override

- Status: adopting (renumbered 288→292 at merge-time re-probe: origin/main now carries ADR-288..291 from concurrent PRs)
- Date: 2026-10-15
- Extends: ADR-242 (plugin payload boundary), ADR-183 (full-suite-at-ship ordering), ADR-179 (plugin-root identity resolution)
- Issue: #9307 deliverable 2

## Context

`soleur:work`, `soleur:ship`, `soleur:review`, `soleur:test-fix-loop` and `grok-pre-push-gate.sh` all prescribed `bash scripts/test-all.sh --affected` — a file that exists only in the Soleur repository. In a Soleur-guided session inside a user's own repository the prescribed gate either fails on a missing script or degenerates into an improvised command with no selection contract. The incident that opened #9307 (a >30 min serial, over-selected gate) was fixed for the Soleur repo by deliverable 1; deliverable 2 is the half that reaches every other repository.

## Decision

Ship `plugins/soleur/scripts/affected-tests.sh` as the single gate entry point and point every call site at it.

- **Dispatch precedence:** `.soleur-test-gate.json` `test_command` → a repo runner that advertises the `--print-selection` capability (case-label/usage-table registration, never free text) → stack adapters (nx/turbo, JS/TS vitest `related` or jest `--findRelatedTests`, Python pytest/testmon/xdist, Go `go list` reverse-dependency closure). A foreign `scripts/test-all.sh` is never invoked with Soleur flags. The capability probe runs **before** the gate's own base resolution and global/inert classification — a capability-positive runner owns the diff decision, so a resolved runner is always delegated to (`--affected`; `--full` only on operator request). Gate-side classification, `--base`, and the no-base-ref refusal are the adapter arm's alone.
- **Exit contract** through one `finish()` site: 0 pass-or-inert, 1 failure, 4 refused (bad config, no base ref, no stack, vacuous `test_command`, missing toolchain, runner refusal), 6 budget-deferred-to-CI, 7 no suite detected. Multi-stack aggregation is worst-of `1 > 4 > 6 > 0`; delegated-runner codes map in (`4`→`runner-refused`, `3`→`runner-signal`).
- **Fail toward coverage:** an empty selection on a non-inert diff runs the full command with `reason=empty-selection`; a narrowed gate never reports green on an undecidable or empty selection.
- **Budget semantics:** `budget_seconds` (default 900) is enforced only when a CI test workflow is detected or `budget_ci: true` — deferring to a CI that does not exist would ship an unverified change. On expiry: rc 6 `AFFECTED_GATE_BUDGET_DEFERRED`; a failure observed before expiry wins (rc 1). The default is sized for unknown repos; this repo's measured ~22-minute affected run would trip it every time, so the repo commits `.soleur-test-gate.json` with `budget_seconds: 2400` — sizing to its own measured battery is exactly what the config exists for.
- **rc 6/7 consumers pass with a note, they do not block.** `grok-pre-push-gate.sh` maps rc 6 to a pass annotated "the detected CI test workflow is the authoritative gate" and rc 7 to a pass annotated as disclosed non-coverage — the block-vs-pass decision is deliberate: rc 6 means a CI test gate exists to carry the authority (blocking the push on a budget artefact would teach operators to bypass the gate), and rc 7 is a disclosure, not a verdict of coverage.
- **Parallelism model per repo kind:** user repos get the native runner's parallel workers (`--maxWorkers`, `-n`, `-p`, `--parallel`) capped by `max(1, ncpu/2)/(1 + running gate processes)`; the Soleur bash runner stays serial — ADR-133's verdict does not transfer between hosts and #8231 remains gated on its green-baseline precondition (evaluated 2026-10-15: does not hold — #7376 open, the #7454 deferral stands, and the dominant local cost is now the affected pre-pass per the 2026-10-09 measurement).
- **Cloud behavior:** the gate resolves its libraries by `BASH_SOURCE` and needs no plugin root — `CLAUDE_PLUGIN_ROOT` may be unset (the ADR-179 resolver remains a `commands/go.md` concern; an earlier in-gate copy was diagnostic-only dead weight and was removed). A shallow clone gets one bounded deepen before `reason=no-base-ref`. The gate reads the user's repo and runs the user's test command — no secrets read, no production mutation. Trust boundary, stated plainly: gate-spawned test commands execute REPO-CONTROLLED code with the agent's environment, and toolchain probes execute local binaries found on PATH — the gate is an orchestrator of code the repo already owns, not a sandbox around it.
- **Wording:** output and PR bodies say "affected-suite gate passed", never "tests verified"; CI stays the authoritative merge gate (ADR-183 scoping applies unchanged — for repos with no Soleur runner this gate IS the local evidence layer, not the merge gate).

## Build-versus-buy verdict: `toolchain` plugin (melodic-software, MIT)

Time-boxed read of `melodic-software/claude-code-plugins` `plugins/toolchain`: a repo-agnostic polyglot verification skill (`/toolchain:check`, `/toolchain:lint`) that detects changed ecosystems and resolves per-ecosystem build/test/lint commands through a tracked `.claude/ecosystems/<ECO>.yaml` config written by `/toolchain:setup`.

**Reject with reasons.** (a) It selects by *changed ecosystem*, not by *affected test* — there is no dependency-closure selection (no vitest `related`, no `go list` rdeps), so a source diff runs the whole ecosystem suite. (b) Its override surface requires a setup-written ecosystems config; our contract is a committed one-file `.soleur-test-gate.json` with fail-closed validation. (c) None of the load-bearing properties exist there: no capability probe onto a repo runner, no fail-toward-coverage on empty/undecidable selections, no CI-gated wall-clock budget, no `ran=X of=N skipped=Y` reporting contract. (d) Vendoring would buy command resolution we already get from the adapters while importing a config model the plan's cut list rejected. MIT terms would permit adoption-with-attribution; there is nothing to adopt.

## Consequences

- Every skill call site names one entry point; repos with no runner get adapters, repos with a capability-positive runner delegate, repos with a `test_command` override bypass selection.
- The gate is a local evidence layer only; the PR-merge authority stays with CI's required `test` context.
- The Soleur-repo behavior is NOT unchanged-modulo-indirection: delegation moves base resolution, inert classification (an all-docs diff no longer exits `NO_TESTS_AFFECTED` gate-side — `test-all.sh`'s own always-on ratchets still run), and global/empty-diff handling (`--full` is now sent only when the operator asked) into the runner, which is strictly better informed. Adapter-arm semantics (the inert/global tables, `reason=empty-selection`, `no-base-ref`) apply only where no capable runner exists.
