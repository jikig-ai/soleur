#!/usr/bin/env bash
set -euo pipefail

# Sequential test runner that isolates test suites to avoid Bun's FPE crash
# when running all tests via recursive directory discovery.
# See: knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md
#
# Per-suite timing: when TEST_TIMING_LOG is set to a writable path, each
# run_suite() invocation appends "<label>\t<elapsed_ms>[\tFAIL]" to that path.
# Elapsed time uses bash 5.0+ EPOCHREALTIME (microsecond precision, no
# coreutils dependency, portable across Linux + Homebrew bash on macOS).
# CI runs ubuntu-latest (bash 5.x). macOS default /bin/bash is 3.2 — install
# bash 5 from Homebrew if you need timing locally; otherwise EPOCHREALTIME
# resolves to empty and elapsed_ms computes 0 silently.

# --- Version Check ---
# Gated on bun being installed so the script runs cleanly in a bun-free
# environment (TEST_GROUP=scripts in CI omits setup-bun by design — the
# scripts shard needs no bun and no node *version pin*: it uses stock
# ubuntu-latest node, unpinned, for the one `node --test` suite below).
if [[ -f .bun-version ]] && command -v bun >/dev/null 2>&1; then
  expected=$(tr -d '[:space:]' < .bun-version)
  actual=$(bun --version)
  if [[ "$actual" != "$expected" ]]; then
    echo "WARNING: Bun $actual installed, expected $expected (from .bun-version)" >&2
    echo "Run: bun upgrade" >&2
  fi
fi

# --- Git Hook Isolation ---
# When invoked as a lefthook pre-commit hook, git sets GIT_DIR, GIT_INDEX_FILE,
# and GIT_WORK_TREE in the environment. These override GIT_CEILING_DIRECTORIES
# and cause test-spawned git commands to operate on the parent repo instead of
# their temp directories. Unsetting them restores normal git discovery behavior.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

# --- Bare Repo Guard ---
# Bare repos contain stale working-tree files that diverge from HEAD.
# Running tests from a bare root produces phantom failures.
# Use a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh
if git rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
  echo "ERROR: Cannot run tests from a bare repository root." >&2
  echo "Stale files at the bare root diverge from HEAD and produce phantom test failures." >&2
  echo "Run from a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh" >&2
  exit 1
fi

# --- Test group selector ---
# TEST_GROUP partitions the suite list across CI matrix shards. Env var wins
# over positional ($1) so GitHub Actions `env:` blocks and `gh workflow run`
# compose without rewriting the call site. Default `all` preserves byte-
# identical behavior for local invocation and any caller that never set this.
#
#   all      every suite, in original order (no-args default)
#   webplat  only apps/web-platform vitest
#   bun      3 named bun tests + plugins/soleur + blog-link-validation
#   scripts  11 pre-suite bash/python + 21 plugins/soleur/test/*.test.sh
#
# See `.github/workflows/ci.yml` test-{webplat,bun,scripts} jobs + the
# synthetic `test` aggregator. See plan
# `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`.
TEST_GROUP="${TEST_GROUP:-${1:-all}}"
case "$TEST_GROUP" in
  all|webplat|bun|scripts) ;;
  *)
    echo "ERROR: TEST_GROUP must be one of: all, webplat, bun, scripts (got: $TEST_GROUP)" >&2
    echo "Usage: bash scripts/test-all.sh [all|webplat|bun|scripts]" >&2
    echo "   or: TEST_GROUP=<value> bash scripts/test-all.sh" >&2
    exit 2
    ;;
esac

want_scripts() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts" ]]; }
want_bun()     { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun"     ]]; }
want_webplat() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "webplat" ]]; }

# --- Run Tests Per Directory ---
failed=0
suites=0

run_suite() {
  local label="$1"; shift
  suites=$((suites + 1))
  local start="$EPOCHREALTIME"
  echo "--- $label ---"
  local status="ok"
  if ! "$@"; then
    status="FAIL"
    failed=$((failed + 1))
  fi
  # Integer math on EPOCHREALTIME ("seconds.microseconds") avoids a coreutils
  # `date +%N` dependency that macOS lacks. 10# forces base-10 parsing of the
  # microseconds substring (a leading zero would otherwise trigger octal).
  # The `*.*` glob guard rejects bash-3.x values (where EPOCHREALTIME is unset
  # and the captured value is empty or non-dotted) and exits elapsed_ms=0
  # gracefully instead of arithmetic-overflowing on `${start#*.}` returning
  # the whole string.
  local end="$EPOCHREALTIME"
  local elapsed_ms=0
  if [[ "$start" == *.* && "$end" == *.* ]]; then
    local start_us=$(( ${start%.*} * 1000000 + 10#${start#*.} ))
    local end_us=$(( ${end%.*} * 1000000 + 10#${end#*.} ))
    elapsed_ms=$(( (end_us - start_us) / 1000 ))
  fi
  if [[ "$status" == "ok" ]]; then
    echo "[ok] $label (${elapsed_ms}ms)"
    printf '%s\t%d\n' "$label" "$elapsed_ms" >> "${TEST_TIMING_LOG:-/dev/null}"
  else
    echo "[FAIL] $label (${elapsed_ms}ms)" >&2
    printf '%s\t%d\tFAIL\n' "$label" "$elapsed_ms" >> "${TEST_TIMING_LOG:-/dev/null}"
  fi
}

# Pre-suite bash/python tests — scripts shard.
if want_scripts; then
  run_suite "tests/hooks/incidents" bash tests/hooks/test_incidents.sh
  run_suite "tests/hooks/emissions" bash tests/hooks/test_hook_emissions.sh
  run_suite "tests/hooks/openhands-guardrails" bash tests/hooks/test_openhands_guardrails.sh
  run_suite "tests/scripts/lint-rule-ids" python3 -m unittest tests.scripts.test_lint_rule_ids
  run_suite "scripts/lint-rule-ids-live" python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
  # Hard-rule body-weakening gate (#6103, ADR-091): hermetic fixtures + a live
  # calibration (base HEAD → zero findings on the committed corpus). The real
  # merge-blocking gate is the standalone `rule-body-lint` ci.yml job with
  # --base <merge-base>; this live line is the calibration + orphan-suite guard.
  run_suite "tests/scripts/lint-rule-bodies" python3 -m unittest tests.scripts.test_lint_rule_bodies
  run_suite "scripts/lint-rule-bodies-live" python3 scripts/lint-rule-bodies.py --check --base HEAD
  # AGENTS B_ALWAYS rule-budget gate — CI-wired in #4599 (was lefthook pre-commit only).
  run_suite "scripts/lint-agents-rule-budget-live" python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
  run_suite "scripts/lint-agents-rule-budget-unit" bash scripts/lint-agents-rule-budget.test.sh
  # The sync guard was lefthook-only, so a --no-verify commit bypassed it and
  # the byte-budget constant drifted across five artifacts unnoticed (#6461).
  # -live asserts the tree is in sync; -unit asserts the guard can still fail.
  run_suite "scripts/lint-agents-compound-sync-live" bash scripts/lint-agents-compound-sync.sh
  run_suite "scripts/lint-agents-compound-sync-unit" bash scripts/lint-agents-compound-sync.test.sh
  run_suite "scripts/lint-infra-no-human-steps" bash scripts/lint-infra-no-human-steps.test.sh
  run_suite "scripts/extract-api-spend" bash scripts/extract-api-spend.test.sh
  run_suite "scripts/domain-model-drift" bash scripts/domain-model-drift.test.sh
  # #6602: exit-code harness for the expenses verify_by expiry gate. Registered
  # explicitly — this runner enumerates by hand and scripts/*.test.sh is NOT in
  # the auto-glob below, so an unregistered suite is an ORPHAN that never gates
  # (the #5417 class). The gate authorizes a fail-loud financial-accuracy alarm,
  # so its arms returning the right exit codes is load-bearing coverage.
  run_suite "scripts/expenses-verify-by-check" bash scripts/expenses-verify-by-check.test.sh
  run_suite "scripts/sentry-issue" bash scripts/sentry-issue.test.sh
  run_suite "scripts/content-publisher" bash scripts/test-content-publisher.sh
  # Registered by #6734. scripts/*.test.sh is NOT covered by any glob here (only
  # scripts/lib/*.test.sh is), so each one must be named explicitly. The first four below
  # had silently never run in any CI job; scripts/lint-orphan-test-suites.sh now fails
  # when a scripts/*.test.sh is missing from this list.
  # NOTE: "scripts/content-publisher" above is the LEGACY test-content-publisher.sh suite;
  # the residue harness below is a different file (content-publisher.test.sh). Both run.
  run_suite "scripts/content-publisher-residue" bash scripts/content-publisher.test.sh
  run_suite "scripts/skill-freshness-aggregate" bash scripts/skill-freshness-aggregate.test.sh
  run_suite "scripts/compound-promote" bash scripts/compound-promote.test.sh
  run_suite "scripts/lint-trap-tempfile-ownership" bash scripts/lint-trap-tempfile-ownership.test.sh
  run_suite "scripts/lint-orphan-test-suites" bash scripts/lint-orphan-test-suites.sh
  run_suite "scripts/cron-artifact-age" bash scripts/cron-artifact-age.test.sh
  run_suite "scripts/watch-live-verify-pass" bash scripts/watch-live-verify-pass.test.sh
  run_suite "scripts/review-reminder-liveness" bash scripts/review-reminder-liveness.test.sh
  run_suite "scripts/zot-restart-loop-alarm" bash scripts/zot-restart-loop-alarm.test.sh
  run_suite "scripts/followthrough-exec-bit" bash scripts/followthrough-exec-bit.test.sh
  # #6757: enforce the ${VAR:?}/${VAR?} ban in follow-through probes. Two explicit run_suite
  # lines because scripts/*.test.sh is NOT auto-globbed here — an unregistered suite is an
  # ORPHAN that gates nothing (#5417/#6734 class; lint-orphan-test-suites.sh FAILs on it).
  # -live runs the guard over the REAL tree (the actual gate); the .test.sh is the mutation
  # proof (both RED directions) that the guard can catch the banned form.
  run_suite "scripts/followthrough-varq-ban-live" bash scripts/lint-followthrough-varq-ban.sh
  run_suite "scripts/followthrough-varq-ban" bash scripts/lint-followthrough-varq-ban.test.sh
  # Was an ORPHAN until #6698 — the suite existed and passed locally but was
  # registered in no runner, so it gated nothing (exactly the class the comment
  # above warns about). It covers the sweeper's path-traversal/symlink rejection
  # AND the closed-set reopen path.
  run_suite "scripts/sweep-followthroughs" bash scripts/sweep-followthroughs.test.sh
  # #6462: exit-code harness for the zot soak's decision arms. Registered explicitly because
  # this runner enumerates suites by hand — an unregistered .test.sh is an ORPHAN that never
  # gates (the #5417 class). The soak authorizes an irreversible PAT revoke, so its arms
  # returning the right codes is not optional coverage.
  run_suite "scripts/zot-soak-6122-arms" bash scripts/followthroughs/zot-soak-6122.test.sh
  # #6616: exit-code harness for the host_name-mislabel follow-through's decision tree (identity,
  # liveness, TRANSIENT-not-PASS). Registered explicitly (orphan-suite class above) — its exit code
  # gates whether the sweeper auto-closes #6616, so a vacuous PASS regression must redden CI.
  run_suite "scripts/hostname-mislabel-web1-6616" bash scripts/followthroughs/hostname-mislabel-web1-6616.test.sh
  # #6475 (D-6): exit-code harness for the ci-deploy Sentry-POST-failure soak probe. Registered
  # explicitly (orphan-suite class above) — its exit code gates whether the sweeper auto-closes
  # #6475, and the probe's whole purpose is to be the fail-loud alarm, so a vacuous PASS (or a
  # false FAIL that pages a green codebase) must redden CI here.
  run_suite "scripts/ci-deploy-sentry-post-fail-6475" bash scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh
  # #6297: exit-code harness for the Anthropic admin-key follow-through. Registered explicitly
  # (orphan-suite class above). Its load-bearing arm is CONTAMINATION: GitHub webhook payloads
  # ship into the same Better Stack source from the same app container, so a substring-matching
  # probe could PASS on an echo of the PR/issue body that merely QUOTES the marker and auto-close
  # #6297 while the key is still unminted. The suite mutation-proves that guard, so a regression
  # to structural matching must redden CI rather than silently false-close a tracker.
  run_suite "scripts/anthropic-admin-key-6297" bash scripts/followthroughs/anthropic-admin-key-6297.test.sh
  # Inngest external-watchdog decision helpers (#6374/#6384/#6407). Registered here in #6407 —
  # these sourceable classifiers/gates were previously orphan suites (run only when invoked
  # manually), so a regression to the watchdog decision logic would have shipped with green CI.
  run_suite "scripts/inngest-liveness-classify" bash scripts/inngest-liveness-classify.test.sh
  run_suite "scripts/inngest-restart-age-gate" bash scripts/inngest-restart-age-gate.test.sh
  run_suite "scripts/inngest-restart-poll-classify" bash scripts/inngest-restart-poll-classify.test.sh
  run_suite "scripts/tunnel-connector-census" bash scripts/tunnel-connector-census.test.sh
  # #6512 Fix 2a: the seccomp-unenforced actionable-alert emitter (sourced by
  # apply-deploy-pipeline-fix.yml). Explicit run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/seccomp-unenforced-alert" bash scripts/seccomp-unenforced-alert.test.sh
  # Dogfood Grok measure/bootstrap (#6545/#6546). Explicit run_suite — scripts/dogfood/
  # is not in the auto-glob; orphan suites are the #5417 class (green CI, zero coverage).
  run_suite "scripts/dogfood/grok-gpu-bootstrap" bash scripts/dogfood/grok-gpu-bootstrap.test.sh
  run_suite "scripts/dogfood/grok-measure" bash scripts/dogfood/grok-measure.test.sh
  # Stock preflight gate (#6453). Registered HERE because nothing auto-discovers
  # tests/scripts/ — the bash *.test.sh glob further down does NOT include it, and
  # infra-validation.yml only lists apps/web-platform/infra/*.test.sh. Without this line
  # the gate that stands between a -replace and a stranded fleet ships with zero coverage.
  run_suite "tests/scripts/stock-preflight-gate" bash tests/scripts/test-stock-preflight-gate.sh
  # Supabase advisor RLS gate (#3366). Registered HERE for the same reason as the
  # line above: nothing auto-discovers tests/scripts/. This is the harness that
  # proves the gate cannot silently pass (a 401 must not parse to a clean 0);
  # without this line that proof runs nowhere and the gate's entire value claim
  # is unverified on every PR — the exact defect the gate exists to catch.
  run_suite "tests/scripts/supabase-advisor-scan" bash tests/scripts/test-supabase-advisor-scan.sh
  # EU residency allow-set parity (#6453 review). {nbg1,fsn1,hel1} is replicated across three
  # terraform validations + the stock gate's default; nothing pinned them together, and the
  # gate's own suite overrides the value to stay hermetic, so the shipped default was asserted
  # nowhere. Drift makes the gate advise a location terraform rejects.
  run_suite "tests/scripts/eu-location-allowset-parity" bash tests/scripts/test-eu-location-allowset-parity.sh
  # betterstack-query.sh hot+archive UNION (#6288). remote() alone is the ~40-minute hot
  # window, so a hot-only query answers `--since 24h` with 40 minutes — no error, just a
  # short answer. That silently starved every soak gate built on it (#6288's needs 2h of
  # span and could never PASS). Hermetic: stubs curl, asserts SQL shape, never live rows.
  run_suite "tests/scripts/betterstack-query-archive" bash tests/scripts/test-betterstack-query-archive.sh
  run_suite "tests/scripts/classifier-regex-parity" bash tests/scripts/test_classifier_regex_parity.sh
  run_suite "tests/scripts/rule-id-regex-parity" python3 -m unittest tests.scripts.test_rule_id_regex_parity
  run_suite "tests/scripts/rule-metrics-aggregate" bash tests/scripts/test-rule-metrics-aggregate.sh
  run_suite "scripts/rule-metrics-aggregate" bash scripts/rule-metrics-aggregate.test.sh
  run_suite "tests/scripts/weakness-miner" bash tests/scripts/test-weakness-miner.sh
  run_suite "tests/scripts/audit-ruleset-bypass" bash tests/scripts/test-audit-ruleset-bypass.sh
  run_suite "tests/scripts/audit-bot-codeql-coverage" bash tests/scripts/test-audit-bot-codeql-coverage.sh
  run_suite "tests/commands/sync-rule-prune" bash tests/commands/test-sync-rule-prune.sh
  run_suite "tests/commands/sync-domain-model" bash tests/commands/test-sync-domain-model.sh
  run_suite "tests/scripts/kb-drift-walker" bash tests/scripts/test-kb-drift-walker.sh
  # Destroy-guard counters (apply-* workflow trio). Pre-existing gap from
  # #4420 closed in #4419 — without these in CI, a PR that mutates a filter
  # to gut its clauses passes review only through CODEOWNERS approval.
  run_suite "tests/scripts/destroy-guard-counter-github" bash tests/scripts/test-destroy-guard-counter.sh
  run_suite "tests/scripts/destroy-guard-counter-sentry" bash tests/scripts/test-destroy-guard-counter-sentry.sh
  run_suite "tests/scripts/destroy-guard-counter-web-platform" bash tests/scripts/test-destroy-guard-counter-web-platform.sh
  # host image/apply coherence preflight (AC10b) — drives the standalone preflight
  # via its test seams (no docker/network/prod write). Registered here alongside
  # the destroy-guard trio: it is the host-agnostic coherence verifier the
  # host_creates HALT's pinned-image chain names (#6575).
  run_suite "tests/scripts/host-image-coherence-preflight" bash tests/scripts/test-host-image-coherence-preflight.sh
  # #6197: inngest-host-replace scoped-recreate destroy-guard (same sourced-gate shape the
  # web2-recreate gate used before #6575 deleted it).
  run_suite "tests/scripts/inngest-host-replace-gate" bash tests/scripts/test-inngest-host-replace-gate.sh
  # registry-host-replace scoped-recreate destroy-guard (5-target; preserves the zot store volume).
  run_suite "tests/scripts/registry-host-replace-gate" bash tests/scripts/test-registry-host-replace-gate.sh
  # registry-region-migrate destroy-guard (#6288; permits the registry's OWN store-volume replace across regions, forbids all out-of-scope destroys).
  run_suite "tests/scripts/registry-region-migrate-gate" bash tests/scripts/test-registry-region-migrate-gate.sh
  # git-data-host-replace scoped-recreate destroy-guard (#6242; 5-target, preserves BOTH data volumes + LUKS passphrase by omission).
  run_suite "tests/scripts/git-data-host-replace-gate" bash tests/scripts/test-git-data-host-replace-gate.sh
  # workspaces-luks-cutover FIRST-PROVISION destroy-guard (#6604). Permits the +create of the
  # five #6593-authored workspaces_luks resources; ABORTs any touch of the live plaintext
  # /mnt/data volume/attachment or the web-1 server, any passphrase re-mint, any destroy/forget,
  # or anything out of scope. Registered HERE — nothing auto-discovers tests/scripts/.
  run_suite "tests/scripts/workspaces-luks-cutover-gate" bash tests/scripts/test-workspaces-luks-cutover-gate.sh
  run_suite "tests/scripts/destroy-guard-regex-parity" bash tests/scripts/test-destroy-guard-regex-parity.sh
  run_suite "tests/scripts/destroy-guard-sentry-scope-guard" bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh
  run_suite "tests/scripts/tenant-integration-gate-verdict" bash tests/scripts/test-tenant-integration-gate-verdict.sh
  # #6589 — the Sentry full-root delete path. These three gate the contract that
  # makes `terraform destroy` reachable at all for infra/sentry/**: the absence of
  # address-scoping in the apply (the #6074/#4929 root cause), the fail-closed
  # aggregator verdict, and the squash-body emulation that decides whether a
  # pre-staged [ack-destroy] will actually reach the merge commit.
  run_suite "tests/scripts/sentry-destroy-counts" bash tests/scripts/test-sentry-destroy-counts.sh
  run_suite "tests/scripts/sentry-full-root-apply" bash tests/scripts/test-sentry-full-root-apply.sh
  run_suite "tests/scripts/sentry-destroy-gate-verdict" bash tests/scripts/test-sentry-destroy-gate-verdict.sh
  run_suite "tests/scripts/sentry-squash-ack-detect" bash tests/scripts/test-sentry-squash-ack-detect.sh
  run_suite "tests/scripts/sentry-create-gate" bash tests/scripts/test-sentry-create-gate.sh
  # Class D (live monitor with no .tf block) is the delete path's other half: the
  # full-root apply can only reclaim a monitor the config once declared. Its whole
  # value is the non-zero exit — registered here because nothing auto-discovers
  # tests/scripts/, and an unregistered suite would leave the gate's fail-closed
  # claim asserted nowhere.
  run_suite "tests/scripts/sentry-monitors-audit-class-d" bash tests/scripts/test-sentry-monitors-audit-class-d.sh
  # md->Slack-mrkdwn converter (scripts/md-to-mrkdwn.mjs). Runs under stock
  # ubuntu-latest node (no setup-node — same bare-`node` precedent as
  # secret-scan.yml). node --test ships in Node >=18.
  run_suite "scripts/md-to-mrkdwn" node --test scripts/md-to-mrkdwn.test.mjs
fi

# Named bun-test entries — bun shard.
if want_bun; then
  run_suite "test/content-publisher" bun test test/content-publisher.test.ts
  run_suite "test/x-community" bun test test/x-community.test.ts
  run_suite "test/linkedin-community" bun test test/linkedin-community.test.ts
  run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
fi

# Vitest in apps/web-platform — webplat shard.
# VITEST_SHARD (e.g., "1/2") is forwarded to vitest --shard for matrix sharding
# in CI. When unset, vitest runs all files. The empty-string suppression via
# ${VAR:+...} keeps local invocation byte-identical.
#
# VITEST_SHARD is passed via env: to the inner bash so the inner shell expands
# it under its own quoting (single-quoted outer, double-quoted inner). This
# blocks shell-injection if a caller ever sets VITEST_SHARD to a value
# containing `;` or `$(…)`. The matrix literal in ci.yml is always `K/N`
# today, but the script is a public surface — defense in depth.
if want_webplat; then
  run_suite "apps/web-platform" env VITEST_SHARD="${VITEST_SHARD:-}" \
    bash -c 'cd apps/web-platform && npm run test:ci -- ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1'
fi

# plugins/soleur bun-test recursion + blog-link-validation — bun shard.
# Co-located because validate-blog-links.sh reads _site/, which
# plugins/soleur/test/seo-aeo-drift-guard.test.ts builds. Under matrix
# sharding (separate runners) there is no race; co-location is a perf
# optimization (build once, reuse) AND defense against any future xargs-P
# attempt that would re-introduce the race within one runner.
if want_bun; then
  run_suite "plugins/soleur" bun test plugins/soleur/
  run_suite "blog-link-validation" bash scripts/validate-blog-links.sh
fi

# Bash *.test.sh glob — scripts shard. (ci-deploy.test.sh runs in infra-validation.yml.)
# .claude/hooks/*.test.sh added 2026-05-15 (#3799 prereq to #3789); covers the
# 8 hook tests that previously only the session-rules-loader entry pulled in.
if want_scripts; then
  for f in plugins/soleur/test/*.test.sh plugins/soleur/skills/*/test/*.test.sh plugins/soleur/scripts/*.test.sh .claude/hooks/*.test.sh apps/cla-evidence/scripts/*.test.sh apps/web-platform/scripts/*.test.sh apps/web-platform/scripts/lib/*.test.sh scripts/lib/*.test.sh; do
    [[ -f "$f" ]] || continue
    run_suite "$f" bash "$f"
  done
fi

echo "=== $((suites - failed))/$suites suites passed ==="
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
