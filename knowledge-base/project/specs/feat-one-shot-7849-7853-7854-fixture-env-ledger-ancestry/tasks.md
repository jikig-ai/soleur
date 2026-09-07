# Tasks — feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry

Derived from `knowledge-base/project/plans/2026-09-07-fix-fixture-env-ledger-ancestry-plan.md`
(post-review revision). Closes #7849, #7853, #7854.

Phases are **dependency-ordered, not file-grouped**: 1 changes a contract 2 consumes; 4 changes a
predicate its mirrors follow. Do not reorder.

---

## 1. Setup — measure before changing (plan Phase 0)

- [x] 1.1 Run `INCIDENTS_REPO_ROOT=<main checkout> bash scripts/rule-metrics-aggregate.sh --dry-run`
      read-only; record rc and the orphan id list verbatim into `measurements.md`.
- [x] 1.2 Re-derive the orphan set under the proposed predicate
      (`test("^(hr|wg|cq|rf|pdr|cm)-")`) over the raw merged corpus. **Reconcile against 1.1** — the
      panel's independent derivation gave 30-before/5-after, this plan's gave 23-before. Proceed on
      neither number alone.
- [x] 1.3 Record fabricated-row counts by the two fixture markers (`gh pr merge 123`,
      `apps/web-platform/lib/auth/foo.ts`) over active + both `.gz` archives. Baseline 143 / 0.
- [x] 1.4 Confirm the one-hop ancestry delta with the `measurements.md` M-4 probe.
- [x] 1.5 Confirm the five chokepoint registrations at their content anchors, and **measure each
      one's reach**: how many `.claude/hooks/*.test.sh`, `tests/**` and `.github/scripts/test/*.sh`
      suites pass through one. Planning reads: 6/46, 2/84, 0/13. These become Guard 3's outside-set
      floor.
- [x] 1.6 Probe whether an env export in vitest `globalSetup` reaches worker children under **both**
      `pool: "forks"` and `WEBPLAT_TEST_USE_THREADS=1`. Fallback is `test.env` — never `setupFiles`.
- [x] 1.7 Read `git-env-list-parity.test.sh` in full (four extractors, three comparisons, one
      hardcoded three-file scrub loop).
- [x] 1.8 Establish `cq-rule-ids-are-immutable`'s scope: does it bind hook-telemetry emitter
      literals, or only `[id: …]` tags in AGENTS.md? Decides task 5.5.
- [x] 1.9 Enumerate every `.github/workflows/**` `run:` step matching
      `hook-git-env-coverage.test.sh`'s `RUNNER_RE`. Known: `skill-security-scan-corpus.yml`,
      `tenant-integration.yml`.

## 2. The shell fixture chokepoint (plan Phase 1) — contract change, precedes §3

- [x] 2.1 Create `plugins/soleur/test/lib/git-fixture-env.sh`: **one** `GIT_LOCATION_VARS` array read
      by both the tripwire loop (moved verbatim from `test-helpers.sh`, escape and announcement
      byte-for-byte) and `git_fixture_env <dir>`. No `git_fixture` wrapper — but see 2.1.2.
- [x] 2.1.1 The ceiling refuses `/`, non-absolute, and any path containing `:` — and **exports
      nothing before it validates**. A partial env is the silent degradation this file exists to
      prevent.
- [x] 2.1.2 **Signing must still be neutralised** (deepen-plan D-1, measured): config globals do NOT
      reach a repo-local `commit.gpgsign=true` — the commit fails with `gpg failed to sign the data`.
      The builder exports `GIT_CONFIG_COUNT=1` / `GIT_CONFIG_KEY_0=commit.gpgsign` /
      `GIT_CONFIG_VALUE_0=false` (measured to override the repo-local value), set as overrides
      **after** the prefix sweep. **Apply the same three to the TS `gitFixtureEnv()`** — every suite
      task 3.2 converts calls it without `gitFixture()`, so they have no signing protection today.
- [x] 2.2 Create `plugins/soleur/test/git-fixture-env-shell.test.sh` (producer for AC2 and Guard 1
      M3/M4). Register in `scripts/test-all.sh` as `run_suite "<label>" bash <path>` — **path last,
      after `bash`**.
- [x] 2.3 `test-helpers.sh` sources the new file instead of inlining the tripwire.
- [x] 2.4 Repoint `git-env-list-parity.test.sh`'s `shell_list()` at the new file, matching the
      **array literal**. Keep three comparisons — do not add a fourth.
- [x] 2.5 Add `.github/scripts/test/run-all.sh` plus every task-1.9 workflow step to the parity
      test's existing scrub loop, and add an **entry-point count floor**. Leave
      `hook-git-env-coverage.test.sh`'s `RUN_LINES` floor alone (it counts lefthook `run:` commands).

## 3. Adopt the helpers (plan Phase 2)

- [x] 3.1 `test/pre-merge-rebase.test.ts` → `gitFixtureEnv()`. Same commit as task 4.1.
- [x] 3.2 Convert the zero-env vitest population under `apps/web-platform/test/**`:
      `cc-reprovision-git-discriminator`, `worktree-config-seed`, `git-config-atomic`,
      `server/inngest/rule-body-gate-recursion-invariant` (the `git()` helper **and** the `python3`
      spawn), `helpers/context-queries-fixture.ts` **and** the sibling site in
      `context-queries-hook.test.ts`, `server/inngest/cron-safe-commit` (`tgit()` and the two bare
      `git init` calls).
- [x] 3.3 Convert the four `tests/**` shell suites, each with a `git_fixture_env "$d" || { …; exit 1; }`
      guard: `tests/hooks/test_hook_emissions.sh` (delete its partial 3-var unset),
      `tests/hooks/test_openhands_guardrails.sh`, `tests/scripts/test-weakness-miner.sh` (delete its
      9-var scrub), `tests/scripts/test-lint-supabase-deprecated-endpoints.sh`.
- [x] 3.3.1 **Pair every conversion with a ledger reconciliation in the same commit.** Sourcing the
      helper brings a suite inside a chokepoint, so its emitter invocations are redirected;
      `test_hook_emissions.sh` asserts on emitted rows and sets no root today.
- [x] 3.4 Convert `.github/scripts/test/test-check-settings-integrity.sh` and
      `test-infra-suite-registration-mutations.sh`.
- [x] 3.5 Route `apps/web-platform/infra/workspaces-luks-loopback.test.sh`'s `mk_repo()` through
      `git_fixture_env`; resolve the helper from a repo root computed once and assert it absolute and
      non-degenerate before sourcing (elevated-privilege context).
- [x] 3.6 Add the 9-var `unset` to `.github/scripts/test/run-all.sh` as the **first**
      line-start-anchored `unset GIT_` in the file.
- [x] 3.7 Create `plugins/soleur/test/fixture-env-adoption.test.sh` — two derivations (git-spawn
      sites by invocation shape; helper-call sites), each with a non-empty floor, difference set
      empty **and printed**, plus a declared waiver list for the six `workspace*`/`mu1-integration`
      suites and `agent-ready-git-worktree.test.ts`. Register it.

## 4. Ledger containment (plan Phase 3)

- [x] 4.1 Sandbox the three leaks by exporting, not per-call: `gdpr-gate-self-test.test.sh` (create a
      `mktemp -d`, export before Case A), `gdpr-gate.test.ts` (`beforeAll` **and** the `spawnSync`
      env), `test/pre-merge-rebase.test.ts` (the shared `Bun.spawn` env object).
- [x] 4.1.1 Follow `.claude/hooks/lib/test-incident-sandbox.sh`'s shape (deepen-plan D-6): `mkdir -p
      "$d/.claude"`, export the path a **second** time as `SOLEUR_TEST_INCIDENT_ROOT` so a suite can
      read back its own emitted rows (this is what makes 3.3.1 a two-line change), and **compose**
      the EXIT trap rather than clobbering it. Do **not** redirect `CLAUDE_PROJECT_DIR` alongside the
      sink — that helper's header records the measured harm.
- [x] 4.2 Add the fail-loud sandbox export to the five chokepoints: derive
      `${INCIDENTS_REPO_ROOT:-$(mktemp -d)}`, **assert non-empty and absolute**, abort with a named
      message otherwise. An empty value reads as unset and silently restores the real sink.
- [x] 4.3 Add the same export as a belt at `scripts/test-all.sh` and `.github/scripts/test/run-all.sh`
      (the latter carries `set -uo pipefail` but **no `-e`** — deepen-plan D-3 — so a failing
      `mktemp` does not abort it and the guard is load-bearing there).
- [x] 4.4 Verify `INCIDENTS_REPO_ROOT` survives `gitFixtureEnv()` / `git_fixture_env`, and assert it
      in a test rather than relying on `gitCleanEnv()`'s prefix sweep being read correctly.
- [x] 4.5 Verify `tests/scripts/test-rule-metrics-aggregate.sh`,
      `scripts/rule-metrics-aggregate.test.sh` and `tests/hooks/test_incidents.sh` still pass under
      the new default.
- [x] 4.6 Widen `incident-sandbox-coverage.test.sh`'s assembly: emitter set (sources the lib **or**
      defines `emit_incident`, reaching the Python mirror); suite set derived from **invocation
      shapes, not name mentions** (a name-mention derivation self-includes the guard); each hop with
      a non-empty floor; **print the outside set** with a ratcheted floor; state hop 2's known false
      negative in the header.
- [x] 4.7 Add the python arm: every `tests/**/*.py` test file imports `_git_fixture_env` (the import
      *is* the chokepoint under `python3 -m unittest`), with a floor.
- [x] 4.8 Clean up the 143 fabricated rows reversibly and in-session: copy the active ledger to
      `.claude/.rule-incidents-synthetic-quarantine.jsonl`, `grep -v` the two markers, **measure
      before and after in the same command**, archives untouched. Record counts for the PR body.

## 5. The orphan gate's discriminator (plan Phase 4)

- [x] 5.1 Reconcile task 1.1/1.2 and pin the surviving orphan set.
- [x] 5.2 Replace all nine exemption stanzas in `scripts/rule-metrics-aggregate.sh` with
      `map(select(test("^(hr|wg|cq|rf|pdr|cm)-")))`.
- [x] 5.2.1 Preserve: `select(.rule_id != null)` **before** the reduce; **no apostrophes** in any
      comment inside the single-quoted jq program; the `hook_input_fault_count` LOAD-BEARING PAIR.
- [x] 5.3 Confirm a genuinely orphan section-prefixed id still exits rc=5.
- [x] 5.4 Simplify `rule-incident-marker-capture.sh`'s `_valid_rule()` to "a real AGENTS id, or an id
      with no section prefix", and change its companion assertion in
      `rule-incident-marker-capture.test.sh` from per-prefix `startswith("<p>")` greps to a
      shared-regex check.
- [x] 5.5 Handle the five mis-prefixed `cq-` hook ids per task 1.8. **Closed on a DIFFERENT basis
      than this line states.** Four are RETIRED and are exempted by clause 2. The fifth,
      `cq-pencil-collapse-auto-recover`, carries one exact exemption — and NOT because "the
      immutability rule binds" (T1.8 established it does not bind emitter literals). The real reason
      is that five rows carrying that id sit in the `.gz` archives the aggregator merges, so deleting
      the exemption at rename time returns the gate to `rc=5`. It is a two-step change whose second
      step has a real precondition; deferred as #7889 item 7.
- [x] 5.6 Regenerate `knowledge-base/project/rule-metrics.json` **as its own commit**, with the
      `--dry-run` diff for the PR body.

## 6. The ancestry-walk disagreement (plan Phase 5)

- [x] 6.1 Delete the independent 8-hop walk and the `E2E` variable from
      `.claude/hooks/memory-backstop.test.sh`.
- [x] 6.2 **Rewrite** the rationale comment above it with the measured reason — do not merely delete
      it, or the next reader restores the walk.
- [x] 6.3 Restructure: snapshot → invoke → snapshot → read the log line; assert **unconditionally**
      that the hook exits 0 and leaks no busctl job object path.
- [x] 6.4 Gate the adoption assertions on **`outcome != "applied"`**, not on one reason string (the
      hook has eleven decline reasons; `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` and `concurrent_apply` must
      skip, not fail). Print the hook's reason verbatim plus the standalone remedy.
- [x] 6.5 Invoke the hook with `CLAUDE_PROJECT_DIR` at a scratch dir and **`CLAUDE_CODE_EXECPATH`
      unset** — the first stops the nag stamp landing in the real checkout, the second removes the
      predicate that would adopt a `node` ancestor under an npm-global install.
- [x] 6.5.1 **Read the log line back from that same scratch path** (deepen-plan D-2). `_repo_root()`
      derives BOTH `log_file` and `stamp_file` from `CLAUDE_PROJECT_DIR`, while the e2e arm today
      reads `.claude/.memory-backstop.jsonl` relative to CWD — redirecting without moving the read
      makes the new gate parse a stale line from the real checkout's previous run.
- [x] 6.6 Extend the synthetic `/proc` fixture: 10-process chain, non-zero at hop 9, zero at hop 8,
      **plus a negative case** for a generic-interpreter `CLAUDE_CODE_EXECPATH`.
- [x] 6.7 Add the `MAX_WALK_HOPS` mutation row to
      `.claude/hooks/memory-backstop-mutation-battery.sh`. **Do NOT register the battery in
      `scripts/test-all.sh`** (deepen-plan D-5): ADR-161 keeps it out of CI's glob deliberately — it
      needs a live user bus. AC19 asserts the row exists and passes when the battery is run by hand.
- [x] 6.8 Post the one-line note on issue #7208.

## 7. Documentation, ADR, C4, deferrals (plan Phase 6)

- [x] 7.1 Write `ADR-205` — **one** decision (the telemetry-id namespace contract plus the chokepoint
      redirect). Re-derive the ordinal across every `origin/*` ref immediately before merge; on
      renumber, sweep this branch's plan, tasks and specs in the same edit.
- [x] 7.2 Add the one-clause Hook Engine amendment to
      `knowledge-base/engineering/architecture/diagrams/model.c4`; run `c4-code-syntax.test.ts` and
      `c4-render.test.ts`.
- [x] 7.3 Correct the false comment in `tests/hooks/test_incidents.sh` (its helper does not export
      `INCIDENTS_REPO_ROOT`; isolation is by lib-copy).
- [x] 7.4 File the six deferral issues (verify each label exists with `gh label list --limit 200`
      first).

## 8. Verification (the plan's Acceptance Criteria)

- [ ] 8.1 AC1–AC3: parity suite, the helper's suite, the adoption guard.
- [ ] 8.2 AC4: `bash scripts/test-all.sh` clean — **force the relevance-gated `run-all.sh` arm**
      (touch a `GITHUB_SCRIPTS_SUITE_PATHS` member or set `TEST_GROUP=scripts`);
      `SOLEUR_ALLOW_FULL_GATE=1` does not override relevance gating.
- [ ] 8.3 AC5–AC9: entry-point ratchet; containment at **both derived roots**, asserting existence
      and count, for the battery **and** each of the three suites standalone; the fail-loud
      `mktemp` case; the coverage guard's floors and printed outside set; the env pass-through.
- [ ] 8.4 AC10–AC14: aggregator clean **against a frozen snapshot**; the injected-orphan rc=5 case;
      the exact `startswith(` count of 3; the marker-capture suite; the regenerated metrics file.
- [ ] 8.5 AC15–AC20: the memory-backstop suite in both shapes; the opt-out skip; the invocation
      assertion and absent nag stamp; the synthetic depth and execpath cases; the mutation battery;
      the deleted-walk and rewritten-comment greps.
- [ ] 8.6 AC21–AC24: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (**not**
      `npm run -w`) plus the C4 suites; the ADR ordinal; the deferral issues, #7208 note and comment
      correction; the PR body's three `Closes` lines and the Phase 4.8 ledger counts.
