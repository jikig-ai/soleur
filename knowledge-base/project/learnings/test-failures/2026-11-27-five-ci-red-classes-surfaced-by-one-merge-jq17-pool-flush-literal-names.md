# Learning: one origin/main merge surfaced five latent CI red classes — jq 1.7.1 parse, pool-flush discipline, literal-name conventions, ratchet baselines, ADR ordinal provisionality

## Problem

PR #12958 (`feat-one-shot-12937-zot-bridge-handshake`, the #12937 CF-tunnel re-home) went red on `deploy-script-tests` shards 1/4 and 4/4, `lint-bot-statuses`, and `guards-ruleset` after staying green on its pre-merge head. Each red was a *different* latent class that only this combination of branch + fresh main could expose:

1. `jq: error: syntax error, unexpected '+', expecting '}' at <top-level>, line 48` — the branch's `build_plan()` jq program in `cf-account-migrate-job.test.sh` concatenates array generators inside an object literal: `resources: [polrefs | to_entries[] | {...}] + [(...) | {...}] + [...]`. Local jq **1.8.2** accepts this; the ubuntu-24.04 runner's jq **1.7.1** rejects it (its own hint: "May need parentheses around object key expression"). The program parsed green locally for days — the version skew made local verification blind.
2. `pool: no setup added or removed a sandbox top-level or bin/ entry while rows were queued (...changed at: 00152)` — main had rewritten the suite for pooled execution (`_pool_run`/`_pool_flush`, shared-state snapshot per batch). The conflict splice kept the branch's bare `printf '\n[tunnel]...'` headers, so the top-level `mkdir $SBX/mirror-tunnel` between queued `red` rows tripped the snapshot diff. Only `section()` (which flushes the pool first) is safe before shared-state writes.
3. `S4 structure: uses the library before it sources it` + `2>/dev/null on a script's bc_curl` + `population ... unclassified` — the two new library-user scripts (`cf-access-deploy-token-mint.sh`, `cf-tunnel-host-predelete.sh`) defined bc_*-calling functions textually *before* `source .../bearer-curl.sh`, discarded stderr (which swallows the `SOLEUR_CREDENTIAL_REFUSED` marker), and were not in `S4_SCRIPT_MANIFEST`.
4. `web-1 private-IP literal count 325 exceeds the ceiling 318` — branch fixtures used the prod `10.0.1.10` literal; the #12910 convention pins new peer fixtures to web-3/`10.0.1.12`.
5. `NEW ADR ordinal collision ... ADR-330` — main's `ADR-330-completion-floors` claimed the ordinal the branch's tunnel ADR had picked when 330 was free.

## Solution

- **jq:** wrapped the concatenation in parens: `resources: ([gen1] + [gen2] + [gen3])`. Verified against a downloaded jq-1.7.1 binary, not just the local 1.8.2 — when a CI failure smells like parser skew, reproduce with the *runner's* version (`/tmp/jq171`), not the dev machine's.
- **Pool flush:** converted the four `[tunnel]`/`[forget]`/`[scope probes]`/`[tunnel mutants]` headers from `printf` to `section` — identical output, but `_pool_flush` drains queued rows before the subsequent top-level `$SBX` writes. Batch integrity then held across all 14 batches.
- **bc_curl literal names:** the suite's counts, name-match and replay all key on `bc_curl [A-Za-z]` — a `bc_curl "$P"` call is *invisible* to every structural check (it neither counts nor gets name-verified). Swapped `"$P"` → the literal script basenames in all three call sites, hoisted `source` above the first textual bc_* line (`refuse()` moved first since the top-level `|| refuse setup` arm runs at load time), dropped the stderr discards, and added both scripts to `S4_SCRIPT_MANIFEST` + `S4_REPLAY_FILES` with floor re-baselines (13→16, 26→29).
- **IP ratchet:** swapped the seven branch-added `10.0.1.10` literals to `10.0.1.12` (synthesized fixtures, self-consistent), dropped one comment literal in `verify-tunnel-ingress-origin.sh`, re-measured 314 and re-baselined `IP_CEIL=314` with an appended provenance comment — the ratchet's own contract ("a later PR that removes a literal lowers the ceiling in the same commit").
- **ADR renumber:** `git mv` tunnel ADR → `ADR-331`, updated the in-file title and every tunnel-side citation (runbooks ×3, domains ledger, tasks, plan, learnings); left completion-floors citations at 330. `check-adr-ordinals` green.
- **lint-bot-statuses:** the two flagged deferred-operator sentences were already sanctioned by the workflow — wrapped them in `lint-infra-ignore` regions (hoisted out of the table cell; mid-table HTML comments break rendering).

## Key Insight

**A merge does not just combine diffs — it combines invariants.** Each suite in this repo encodes conventions as executable checks (pool-flush discipline, literal-name extraction, source-before-use ordering, literal ratchets, provisional ordinals). Content that was green on one side can violate the *other side's* newly-introduced check — and, worse, content written to *dodge* a check's literal patterns (a `"$P"` name, an unparenthesized generator) silently escapes the check entirely. Two durable habits: (a) after merging an execution-model change, audit every top-level statement between queued work for shared-state writes; (b) treat "parses/passes locally" as inconclusive whenever the runner's tool version differs — reproduce with the runner's version.

## Session Errors

1. **Trusted local jq (1.8.2) as the oracle for a CI parse error (1.7.1).** — Recovery: downloaded jq-1.7.1, reproduced the exact CI error, applied the parens fix. — Prevention: for a syntax/parse failure that reproduces only in CI, diff `tool --version` runner-vs-local first; the runner's binary is the oracle.
2. **Merge splice kept bare `printf` headers under main's new pooled execution.** — Recovery: `printf`→`section` on the four headers. — Prevention: when a merge brings a serial→pooled rewrite, grep the merged file for every top-level write to shared state that is not preceded by a flush.
3. **New scripts used `bc_curl "$P"` — invisible to all structural checks.** — Recovery: literal basenames. — Prevention: `bc_curl`'s first arg is a census key; use the literal filename, never a variable (the suite cannot see expansions).
4. **New library-user scripts not in S4_SCRIPT_MANIFEST / replay files.** — Recovery: added + floor re-baselines. — Prevention: a `source .../bearer-curl.sh` line in a new script is itself the signal that the manifest and floors need touching in the same diff.
5. **`source` placed after first textual bc_* use (function-library layout).** — Recovery: hoisted source (and `refuse`, which the `|| refuse` arm needs at load time) above the first bc_* line. — Prevention: the check is textual-order, not call-order — sourcing lazily inside `main()` reads as unsourced.
6. **`2>/dev/null` / `>&1` on bc_curl.** — Recovery: removed. — Prevention: stderr is the refusal-marker channel; discard stdout only.
7. **Branch fixtures used the prod web-1 literal.** — Recovery: web-3/`10.0.1.12` per #12910, IP_CEIL re-baselined to the measured count. — Prevention: synthesized peer fixtures never carry prod literals; re-measure before moving a ceiling.
8. **Branch-picked ADR ordinal collided at merge.** — Recovery: renumber to ADR-331 with citation sweep. — Prevention: a branch-picked ordinal is provisional until merge (prior learning #7162); re-check against freshly-fetched `origin/main` before landing.
9. **`2>/dev/null` terraform console rc=124 timeouts in web-hosts-generic under parallel suite load.** — Recovery: standalone re-run green; CI had flagged only the ratchet. — Prevention: rc=124 in a `timeout`-wrapped console row under heavy parallelism is contention, not logic — re-run in isolation before debugging.
10. **`cancel-superseded` CI flake (GitHub API stream error).** — Recovery: self-resolved on next push. — Prevention: none — transient infra, one-off.
11. **(Forwarded, pre-compaction) `git stash` attempted in the worktree — hook-blocked.** — Recovery: hook deny; edits made in place. — Prevention: already hook-enforced (`hr-never-git-stash-in-worktrees`).

## Null-Guardrail Findings (Phase 1.5 step 3.6)

- **`bc_curl <non-literal>` silently escapes every structural check.** The S4 regexes require `bc_curl [A-Za-z]`; a `bc_curl "$VAR"` or `bc_curl ${X}` call is skipped by the count, the name check AND the replay extraction — a library call the suite structurally cannot see. **Rule violated: none (null guardrail).** Existing enforcement: `unwired` — the population grep *finds* the sourcing script, but per-statement checks are literal-keyed. Proposed: fail on `bc_curl ` followed by `"`/`$` (name must be a literal census key) — filed as issue, see Route-to-Definition below.
- **jq-version parity between dev and runner.** Covered by CI (the suite fails closed on the runner), but local verification diverges silently. Documented here; a runner-version pin note is a doc fix, not a guard.

## Prevention Strategies

- For CI-only parse/syntax failures: `tool --version` on the runner first; reproduce with that binary before touching code.
- For pooled test suites: headers and any top-level shared-state write must follow a flush — `section()`, `verdict`, or `run_job` all flush; bare `printf` does not.
- For suite conventions: read the *extractor regexes* (the `[A-Za-z]` literal-key patterns), not just the pass/fail messages — they define what the suite can see.
- ADR ordinals on a branch are provisional; the ordinal gate is the merge-time check, not the pick-time check.

## Route-to-Definition

- Issue filed: `bc_curl` non-literal name escapes the argv-bearer sweep's structural checks (proposed regex tightening, deferred-scope-out).
- jg-version parity + pool-flush discipline: documented in this learning; no definition edit proposed (covered by CI and the suite's own header comments).

## Tags

category: test-failures
module: apps/web-platform/infra + tests/scripts
refs: #12937, #12958, #12985, #12910, #7162
