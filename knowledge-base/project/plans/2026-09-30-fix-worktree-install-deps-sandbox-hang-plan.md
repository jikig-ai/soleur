---
title: "fix: worktree-manager create/feature hangs indefinitely on dependency install when the package registry is unreachable"
type: fix
date: 2026-09-30
slug: fix-worktree-install-deps-sandbox-hang
branch: feat-one-shot-9269-sandbox-install
issue: 9269
closes: 9269
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: worktree-manager create/feature hangs indefinitely on dependency install when the package registry is unreachable

## Enhancement Summary

**Deepened on:** 2026-09-30
**Sections enhanced:** Hypotheses (4.5 deep-dive), Proposed Solution (timeout array shape + rc 124/137 semantics + probe-before-banner ordering), Acceptance Criteria (vitest runner correction), References (verified commands).

### Key Improvements

1. Corrected the timeout mechanism to the repo's canonical bash-3.2-safe array shape (`install_to=()` + `${install_to[@]+"${install_to[@]}"}`, `.claude/hooks/git-commit-secret-scan.sh:151-154`) — a bare binary-name string would have reintroduced the missing-tool class the fix exists to solve on stock macOS.
2. Pinned bound-expiry exit semantics: `timeout` reports **124** on TERM expiry and **137** when `-k` escalates to SIGKILL — a 124-only check would misclassify kill-escalated timeouts as ordinary failures.
3. Corrected the verification command for the telemetry suite: `apps/web-platform` runs **vitest**, and `bunfig.toml` `pathIgnorePatterns = ["**"]` makes `bun test` inert in that package — `bun test` would have reported "filter did not match" on a green suite.
4. Probe ordering: the registry probe fires BEFORE the `Installing dependencies (…)` banner, so a skipped arm never prints a started-then-skipped pair.

### New Considerations Discovered

- The sentinel drift guard (`git-lock-marker-telemetry.test.ts` :261-384) mechanically enumerates `SOLEUR_*` sentinels from skill scripts AND SKILL.md prose — the `MARKER_RE` edit is a hard dependency of both the script change and its documentation.
- The bash 4+ `declare -A`/`local -A` memoization idiom is already used in the script (:2693, :3274), so the per-host probe cache needs no portability fallback beyond what the file already assumes.
- Two open `code-review` scope-outs touch this file/class (#8496 acknowledge, #8659 fold-in-as-authoring-guidance for the new suite's trap ordering).

## Overview

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` runs `install_deps` unconditionally inside `create`/`feature` with no timeout and no opt-out. In a network-restricted sandbox that denies egress to `registry.npmjs.org:443` (the #9269 incident: Devin cloud egress deny, ~100 retries until the caller killed the process), the package manager retries until the caller kills it, halting the pipeline and leaving a worktree with no installed dependencies.

This plan bounds every install arm with (a) a bounded connectivity preflight that names the blocked host and (b) a command-level `timeout` so an install can never hang indefinitely; preserves the existing warn-and-continue semantics so creation still completes and reports a documented usable state; adds an explicit opt-out (`--no-install` global flag / `SOLEUR_WORKTREE_SKIP_INSTALL=1`); and adds regression coverage as a new suite in `plugins/soleur/test/worktree-manager-*.test.sh`. All work lands inside `install_deps` — the single chokepoint both call sites already share — so `create` (worktree-manager.sh:2081) and `feature` (worktree-manager.sh:2219) are covered by construction.

## Problem Statement / Motivation

- `install_deps()` (worktree-manager.sh:1653) is invoked unconditionally from `create_worktree` (:2081) and `create_for_feature` (:2219). Both install commands (`"${root_install_cmd[@]}"` at :1697, `"${install_cmd[@]}"` at :1749) run with **no timeout** — a denied/stalled egress retries at the package manager's own cadence indefinitely.
- The failure mode observed in #9269: `bun`/`npm` retried `registry.npmjs.org:443` roughly 100 times inside a denied sandbox, exceeded the caller's 120 s budget, was backgrounded, and had to be killed by hand — after which the pipeline's later steps ran in a worktree with no `node_modules`.
- Every install failure arm today warns and continues (e.g. :1700, :1752), but an **unbounded hang** is worse than a failed install: it looks like a stalled pipeline, not a skipped step, and carries no diagnostic naming the cause.
- There is no opt-out. In sandboxed/CI contexts where deps are provisioned another way, `create`/`feature` cannot skip install at all.
- The hook-required-binary enumeration at :1757–1779 exists *because* silent warn-and-continue was under-diagnosed (#8580); the fix keeps that contract and extends it: a skipped or unreachable install must still say so, on stdout, in a greppable marker, because stderr is invisible under `claude --bg`.

## Hypotheses

Phase 1.4 trigger fired (the feature description contains `unreachable`, `timeout`, `network-restricted`; `hr-ssh-diagnosis-verify-firewall`). Layer-by-layer status for the reported incident — this plan is not diagnosing a live outage (the cause is already known), so each entry states verified/not-verified against the issue's evidence:

- **L3 — firewall/egress allow-list:** VERIFIED as the root cause. The issue's captured denial is `deny network-outbound registry.npmjs.org:443` at the Devin sandbox egress layer — an allow-list decision, not a service fault. No `sshd`/fail2ban/app-layer hypothesis is in scope; the fix is to *detect and bound* this condition, not to repair the network.
- **L3 — DNS/routing:** VERIFIED-not-applicable-by-evidence. The sandbox denied the TCP connect; DNS resolution succeeded or was bypassed by the sandbox policy. Either way the observable symptom (connection denied) is upstream of DNS correctness. Not verified independently — the issue's denial log is the artifact.
- **L7 — TLS/proxy:** NOT VERIFIED and correctly out of scope. The connection never reached the handshake; TLS config cannot be implicated.
- **L7 — application:** VERIFIED as the defect under repair: the package manager's retry-until-success behavior is the application layer; it was reached and it looped.

### Network-Outage Deep-Dive (deepen-plan 4.5 — fired on `unreachable`/`timeout` triggers)

Layer-by-layer verification status for the plan's own mechanism, not the incident (the incident's layers are above):

- **L3 firewall/egress:** the plan's runtime probe IS the L3 check — `curl --proto '=https' --connect-timeout 5 --max-time 8` against the resolved registry host. Verified locally: rc=0/`http_code=200` on healthy egress (2026-09-30). A denied egress yields a fast nonzero rc and the `reason=registry-unreachable` marker names the host — the diagnostic the issue asked for.
- **L3 DNS/routing:** deliberately out of probe scope — a DNS failure surfaces as the same curl rc!=0 and the same marker (the host is still correctly named as unreachable-from-here; DNS-vs-deny discrimination is an operator diagnostic the marker enables, not one the script must resolve).
- **L7 TLS/proxy:** `--proto '=https'` + cert verification on; a TLS-layer failure also yields rc!=0 → the arm skips with the host named. The probe never authenticates (public registry metadata GET, no credentials on the wire).
- **L7 application:** the package managers' own retry behavior stays untouched — the plan wraps it (bounded) rather than reconfigures it; no package-manager flags change.

Gap note: a registry that accepts TCP+TLS but stalls mid-response still passes the probe — covered by the `install_to` bound (P1), which is why both layers ship together.

## Research Insights

**Premise validation** (Phase 0.6 — checked live 2026-09-30): Issue #9269 is `OPEN`, label `type/bug`, no `closedByPullRequestsReferences` (`gh issue view 9269 --json state,title,closedByPullRequestsReferences`). Cited anchors verified on `origin/main` and this branch: `install_deps()` at `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:1653`, call sites at :2081 (`create_worktree`) and :2219 (`create_for_feature`). `grep -n 'timeout\b\|curl\b\|registry' worktree-manager.sh` over the install path confirms **no timeout, no probe, no opt-out** exists today. No stale premises; the issue's mechanism names match the code.

**Property list** (Phase 0.6b) — the observable outcomes this change must buy:

- P1: No invocation of `create`/`feature` can run an unbounded dependency install — every arm is wrapped in a bounded wait.
- P2: When the resolved package-registry host is unreachable, the install arm is skipped *fast* (a bounded preflight, not a hung retry loop) and a diagnostic names the blocked host on stdout.
- P3: Worktree creation still completes and reports a usable state — warn-and-continue is preserved; a skipped/bounded install leaves the worktree on disk, leased, with the hook-dep enumeration still reporting which binaries are missing.
- P4: An explicit opt-out exists that skips dependency install entirely, via env var (`SOLEUR_WORKTREE_SKIP_INSTALL=1`, the `=="1"` convention of `SOLEUR_DISABLE_SESSION_STATE`) and a global flag (`--no-install`, parsed beside `--yes`/`--update-local-main`).
- P5: Regression coverage exists in the `plugins/soleur/test/worktree-manager-*.test.sh` family for the opt-out, the unreachable-registry skip, the timeout bound, and the unaffected happy path.
- P6: Any new `SOLEUR_*` stdout sentinel emitted from `plugins/soleur/skills/*/scripts/*.sh` is registered in `apps/web-platform/server/git-lock-marker-telemetry.ts` `MARKER_RE` — the drift-guard test `extractor matches every SOLEUR_* sentinel emitted by any plugin skill script or SKILL.md` enforces this mechanically.

**Cut list** (Phase 0.6b) — mechanisms considered and cut before research:

- Retry-with-backoff inside `install_deps` → buys no property; a denied egress does not become reachable by retrying, and retries are exactly the behavior being bounded. Cut.
- Detecting "am I in a Devin/Claude sandbox" to auto-skip → environment-sniffing buys P1/P2 indirectly and fragilely; the connectivity probe answers the actual question (can the registry be reached) on every platform. Cut.
- Plumbing a `--no-install` equivalent through `one-shot`'s call site → the env var already reaches `bash` spawns without a SKILL.md edit; a flag is the CLI surface and the env var is the pipeline surface. Piping the flag through one-shot adds no property the env var lacks. Cut; noted as follow-up-shaped if wanted.
- A bash-only watchdog (`cmd & pid=$!; sleep` loop) to replace `timeout` → strictly worse than the platform binary, and `gtimeout`/`timeout` covers the supported hosts; the no-timeout fallback arm stays warn-only. Cut.

**Relevant file paths (verified against `origin/main`):**

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - `install_deps()` :1653 — root arm :1663–1704 (`bun install --frozen-lockfile --cwd` :1673 carrying `# lint-workflow-install-sites: allow-bun`; `npm ci --ignore-scripts --prefix` :1685); apps loop :1709–1755 (bun :1723 `allow-bun`, npm :1730, yarn :1737); hook-dep enumeration :1757–1779.
  - Call sites :2081 (`create_worktree`), :2219 (`create_for_feature`) — both unconditional, both after `copy_env_files`.
  - Globals `YES_FLAG` :151, `UPDATE_LOCAL_MAIN` :156; flag parse loop at file tail (~:4140); `show_help` ~:4099; `main()` dispatch :4058.
  - Conventions: stdout sentinels `echo "SOLEUR_…"` (e.g. `SOLEUR_FEATURE_PUSH_FAILED` :2239, `SOLEUR_WORKTREE_SLUG_COLLISION` :1947); `headless_or_stderr warn "…"` for human lines; `_sanitize_marker_field` :1417 for marker field values; `set -euo pipefail` :29.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — `MARKER_RE` :134 (ingest allowlist), `WEDGE_RE` :309 (paged class), MIRRORED-NOT-PAGED rationale comments :153–305.
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — sentinel drift guard :261–384 derives the emitted set by scanning `plugins/soleur/skills/*/scripts/*.sh` + `skills/*/SKILL.md`.
- `plugins/soleur/test/worktree-manager-hook-deps.test.sh` — sibling suite: fixture builder `new_repo`, `run_create` driver (stdout/stderr to separate files), PATH-stubbed `npm`, `SOLEUR_SESSION_STATE_ROOT` override, M7a token constraint (compose `node_modules/.bin/$HOOK_BIN`, never the literal).
- `plugins/soleur/test/test-helpers.sh` :32–77 — incident-sandbox ownership; a suite that installs `trap … EXIT` after sourcing replaces the composed trap (#8659 class). The fix-in-the-suite is `export INCIDENTS_REPO_ROOT="$TEST_DIR/incidents"` (absolute, inside the suite's own tmpdir) **before** sourcing helpers.
- `scripts/test-all.sh` :97 — `plugins/soleur/test/*.test.sh` is a glob-registered suite path; a new file there is covered by `lint-orphan-test-suites.sh` without an explicit entry.
- `scripts/lint-workflow-install-sites.sh` — scans `plugins/**/*.sh` for install invocations; the two existing `bun install` lines carry per-line `allow-bun` waivers that must stay colocated with the invocation text they waive.
- `plugins/soleur/skills/git-worktree/SKILL.md` :96–118 — documents `create` args and `--update-local-main`; the flag/env belong here too. SKILL.md is inside the drift guard's scan set, so naming a `SOLEUR_*` sentinel in its prose requires the same `MARKER_RE` coverage.

**Applicable learnings:**

- `2026-08-12-i-reused-a-monitored-marker-name-and-inherited-its-paging-severity.md` — mint a NEW sentinel name (`SOLEUR_WORKTREE_INSTALL_SKIPPED`), never reuse an existing one; the new name gets an explicit classification (mirrored-not-paged) instead of inheriting paging by accident.
- `2026-08-09-parity-of-form-is-not-parity-of-cover-…` — "the fix lands once in the chokepoint" is exactly why both call sites are covered by editing `install_deps`, not by duplicating guards at :2081/:2219.
- `2026-05-04-plan-precedent-search-must-include-lib-helpers.md` — precedent search included `plugins/soleur/scripts/lib/*.sh`: no existing reachability/timeout helper to reuse (grep: `curl`, `/dev/tcp`, `timeout ` — none in lib); `deploy-arm.sh:155` is the nearest curl precedent (`--proto '=https' --max-time`).
- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — two-stage `--json` then `jq --arg` used for the overlap query.
- #8659 (open scope-out, see below) — the new suite sets `INCIDENTS_REPO_ROOT` before sourcing test-helpers.

**Related issues/PRs:** #9269 (this fix); #8580 (hook-dep enumeration the fix must keep working); #8490/#8493 (marker telemetry layer the new sentinel registers into); #7415 (`_sanitize_marker_field` was introduced there — commit f50003946a — for slash-bearing branch names; the field-allowlist convention it established is what `host=`/`arm=`/`endpoint=` reuse). The stderr-invisible-under-`--bg` rationale for stdout sentinels is documented in `worktree-manager.sh`'s own comments (~:607/:675/:1078, per #5934), not a single issue.

**External research:** skipped (Phase 1.6) — self-contained bash fix; every convention is determined by the repo itself (marker registry, flag parse, test family). Community discovery (1.5): no uncovered stack signatures. Functional overlap (1.5b, assessed inline — no Task-spawning capability exists in this subagent process): no community artifact applies to a repo-internal worktree script; nothing to install.

**Open code-review overlap query** (Phase 1.7.5, run against 87 open `code-review` issues): two hits name this file — #8496 and #8659; dispositions in `## Open Code-Review Overlap`.

**Research Reconciliation — Spec vs. Codebase:** the issue text is a bug report, not a spec; its claims were checked against `origin/main` and all held (anchors above). One correction of scope, not a contradiction: the issue's "(b) preserve warn-and-continue" phrasing implies per-arm skip; the chokepoint design makes "skip install entirely" a single early gate, and warn-and-continue is preserved *per arm* (an unreachable `apps/foo` registry does not prevent `apps/bar` from installing — arms probe their own resolved host).

## Proposed Solution

Edit `install_deps()` in place so the three behaviors are properties of the chokepoint, not of the call sites:

1. **Opt-out (P4).** New global `SKIP_INSTALL=false` beside `YES_FLAG`/`UPDATE_LOCAL_MAIN` (:151–156). Set true when `[[ "${SOLEUR_WORKTREE_SKIP_INSTALL:-}" == "1" ]]` (the `== "1"` convention from `session-state.sh:27`) or when the global flag parser sees `--no-install` (added to the loop at file tail alongside `--yes`/`--update-local-main`). At the top of `install_deps`, when set: `echo "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out"` on stdout + `headless_or_stderr warn` naming the recovery path (re-run installs inside the worktree when network permits), skip both install blocks, still run the hook-dep enumeration (it reports the resulting state honestly). Document `--no-install` in `show_help` Global Flags and in `git-worktree/SKILL.md`.

2. **Bounded connectivity preflight (P2).** New helpers inside the same file, immediately above `install_deps`:
   - `_install_registry_host <dir> <runtime>` — resolves the host each arm actually installs from: `npm` → `npm --prefix "$dir" config get registry 2>/dev/null` (respects project `.npmrc` under prefix + user config — the registry npm will really use); `bun` → `registry=` in `$dir/bunfig.toml`, else `$dir/.npmrc`, else `$worktree_path/.npmrc` (and `$worktree_path/bunfig.toml`, added in review), else default; `yarn` → `.yarnrc` `registry` else `registry.yarnpkg.com`. Defaults: `registry.npmjs.org` (npm, bun), `registry.yarnpkg.com` (yarn). Host extraction strips scheme, userinfo, path (`${u#*://}` → `${h##*@}` → `${h%%/*}`); the PORT is preserved (implementation deviation, recorded post-review — a port-bearing private registry probed without it would misreport unreachable, and `host:port` IPv6 literals survive the strip). `_sanitize_marker_field` applied at emission for marker safety.
   - `_registry_reachable <host>` — memoized per host (implementation: space-separated `host=rc` string memo, NOT `declare -A` — a top-level `declare -A` would break bash 3.2 for every subcommand since the script's only assoc-array uses are inside cleanup-path functions, not `create`), `command -v curl` gate (absent → return 0, the timeout still bounds), then `curl --proto '=https' --connect-timeout "${SOLEUR_WORKTREE_REGISTRY_PROBE_SECS:-5}" --max-time "${SOLEUR_WORKTREE_REGISTRY_PROBE_MAX_SECS:-8}" -sS -o /dev/null "https://$host/"` — rc-based (any HTTP response, even 4xx, proves reachability; `-f` deliberately absent). `deploy-arm.sh:155` is the in-repo `--proto '=https'` precedent.
   - On probe failure per arm: `echo "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=<sanitized> arm=<label>"` + `headless_or_stderr warn` naming the host and the recovery action for that arm; skip the arm's command; continue.
   - **Ordering:** the probe runs BEFORE the arm's `Installing dependencies (…)` banner is printed — a skipped arm must never emit a started-then-skipped pair (the banner claims work began; the skip says it did not).

3. **Command-level timeout (P1).** Use the repo's canonical timeout-resolution shape — an ARRAY, not a binary-name string, per `.claude/hooks/git-commit-secret-scan.sh:151-154`: `install_to=(); if command -v timeout >/dev/null 2>&1; then install_to=(timeout -k 15 "${SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS:-300}"); elif command -v gtimeout >/dev/null 2>&1; then install_to=(gtimeout -k 15 …); fi` and invoke via `${install_to[@]+"${install_to[@]}"}` — bash 3.2 (stock macOS `/bin/bash`) treats an EMPTY array as unbound under `set -u`, and this script runs `set -euo pipefail` (:29), so the `${a[@]+…}` expansion is load-bearing, not style. `-k 15` sends KILL after the TERM grace so a TERM-ignoring child still dies. Wrap both invocations: `install_output=$({ ${install_to[@]+"${install_to[@]}"} "${cmd[@]}"; } 2>&1)`. **Exit semantics (verified against the hook's own comment at :157-160):** `timeout` reports **124** when the bound expires via TERM and **137** when the bound escalated to SIGKILL — the timeout arm MUST accept `rc -eq 124 || rc -eq 137`; a 124-only check silently misclassifies kill-escalated timeouts as ordinary install failures. On a bound hit: `SOLEUR_WORKTREE_INSTALL_SKIPPED reason=timeout arm=<label> secs=<n>` + warn naming the arm and the recovery action; continue (warn-and-continue). Other nonzero rc: existing `install failed` warn path unchanged. Empty `install_to` (no timeout binary — macOS without coreutils) → run unwrapped with a once-per-call `headless_or_stderr warn` that the bound is unavailable (the preflight still covers the reported incident class).

   Implementation shape that keeps the diff small: a private `_run_install <label> <runtime> <dir> <cmd...>` helper holding probe+timeout+run+report, called by both the root block and the apps loop — it also removes the near-duplicate run/report bodies at :1694–1703 and :1747–1754. Existing output strings (`Installing dependencies (<runtime>)…`, `Dependencies installed`, `<x> install failed -- run …` shape) are kept verbatim: `worktree-manager-hook-deps.test.sh` A2 asserts `Dependencies installed`, and the hook-dep enumeration warning at :1777 is unchanged.

4. **Telemetry registration (P6).** `SOLEUR_WORKTREE_INSTALL_SKIPPED` is a new stdout sentinel → add `SOLEUR_WORKTREE_INSTALL_SKIPPED\b.*` to `MARKER_RE` in `git-lock-marker-telemetry.ts` with a MIRRORED-NOT-PAGED comment (warn-and-continue: creation proceeds, the worktree is usable — same class as `SOLEUR_GIT_CONFIG_MASK_SKIP`/`SOLEUR_TRANSPORT_DIAG`; NOT added to `WEDGE_RE`). Add a test row in `git-lock-marker-telemetry.test.ts` asserting `extractGitLockMarkers("SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=registry.npmjs.org arm=root-npm")` returns 1 marker with `wedged: false`.

5. **Regression suite (P5).** New file `plugins/soleur/test/worktree-manager-install-bounded.test.sh`, modeled on `worktree-manager-hook-deps.test.sh` (fixtures synthesized, `assert_fixture_dir`, `git_fixture_env`, `SOLEUR_SESSION_STATE_ROOT`, separate stdout/stderr capture, PATH-stubbed package managers). **#8659 compliance:** `export INCIDENTS_REPO_ROOT="$TEST_DIR/incidents"` + `mkdir -p` before sourcing `test-helpers.sh`, so the suite's own `trap 'rm -rf "$TEST_DIR"' EXIT` does not replace a composed trap. M7a: never spell the hook binary or `.bin/` path literally — compose from `HOOK_BIN`.

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| `timeout` only, no preflight | Satisfies P1 but not P2 — the denied-sandbox case still burns the whole per-arm timeout before diagnosing, and nothing names the blocked host. The issue's own Expected clause asks for "detect … fail fast … naming the blocked host". |
| Preflight only, no timeout | Satisfies P2 for the reported case but leaves reachable-but-stalled installs unbounded (P1 fails) — e.g. registry accepts the TCP connect then stalls mid-transfer. Both layers are cheap; the issue licenses "and/or" and the belt-and-suspenders split assigns each layer a distinct failure class. |
| Check `DEVIN`/sandbox env vars and skip | Environment sniffing answers "what platform" not "is the registry reachable"; an allowed-sandbox or a broken dev host is misclassified either way. |
| Guard at both call sites instead of inside `install_deps` | Duplicates the logic and re-opens the parity-of-form-not-cover defect class (the script's own comments at :2029–2035 document why the chokepoint placement matters). |
| Abort creation on unreachable registry | Violates requirement (b) — warn-and-continue is load-bearing: the worktree is created, leased, and usable; installs are re-runnable inside it. |
| Marker `printf` instead of `echo` | The drift guard's `SENTINEL_RE` matches both; `echo` is this file's convention. |

## Technical Considerations

- **All arms covered (req d):** root `bun`/`npm` (:1663–1704) and every `apps/*/` iteration's `bun`/`npm`/`yarn` (:1709–1755). Both call sites share `install_deps`, so `create`/`feature` coverage is structural, not duplicated.
- **Install arms in THIS repo:** root `package-lock.json` → npm arm; `apps/web-platform/package-lock.json` → npm arm; `plugins/soleur/docs/package.json` is not under `apps/` (unscanned); `spike/` is not under `apps/` either. The bun/yarn arms exist for tenant repos and stay covered by code path even though no in-repo fixture exercises them — the suite stubs binaries/lockfiles to reach them.
- **Private registry / proxy edge cases:** the npm arm resolves via `npm config get registry`, honoring `.npmrc`/`--prefix`; `curl` honors `http_proxy`/`https_proxy` env, matching package managers that read env proxies. Package managers configured via file-only proxy settings can diverge — bounded by the timeout arm and correctable via the opt-out.
- **Portability:** `timeout` is GNU coreutils (present on this host at `/usr/bin/timeout`); macOS without coreutils hits the no-TIMEOUT_BIN warn-once arm. `curl` is a documented dependency class already used by sibling plugin scripts.
- **`set -euo pipefail`:** every probe/resolve invocation must be guarded (`|| true`, `if !` arms, or the `if cmd; then` idiom the file already uses). `declare -A` memoization is bash-4+ — the script already uses bash features (`local -a`, `[[ ]]`) and is executed via `bash`.
- **Marker-field hygiene:** `host=`, `arm=`, `path=` values pass through `_sanitize_marker_field` (:1417) — spaces/`/` in a derived hostname would break downstream field parsing otherwise.
- **Hook-dep enumeration stays unconditional:** on opt-out and on skipped arms it correctly reports missing hook binaries — that is the documented-usable-state contract from #8580, extended not weakened.
- **`create_for_feature` ordering:** `install_deps` runs before the `git push -u` at :2230; on a fully denied sandbox, the push arm already warns-and-continues (`SOLEUR_FEATURE_PUSH_FAILED` :2239) — no change needed; noted so the failure map is complete.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — new `SKIP_INSTALL` global; `--no-install` in the flag loop and `show_help`; `_install_registry_host` + `_registry_reachable` + `_run_install` helpers; `install_deps` opt-out gate and per-arm probe/timeout; keep `allow-bun` waiver comments colocated with their `bun install` lines.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — add `SOLEUR_WORKTREE_INSTALL_SKIPPED\b.*` to `MARKER_RE` + a MIRRORED-NOT-PAGED classification comment.
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — mirrored-not-paged test row for the new sentinel.
- `plugins/soleur/skills/git-worktree/SKILL.md` — document `--no-install` / `SOLEUR_WORKTREE_SKIP_INSTALL` and the `SOLEUR_WORKTREE_INSTALL_SKIPPED` sentinel (this file is inside the drift guard's SKILL.md scan — DOMAIN_RE includes `SOLEUR_WORKTREE_`, so the registration above is a hard dependency of documenting it).

## Files to Create

- `plugins/soleur/test/worktree-manager-install-bounded.test.sh` — the regression suite (auto-registered via the `plugins/soleur/test/*.test.sh` glob in `scripts/test-all.sh`; `lint-orphan-test-suites.sh` verified to cover that glob).

## User-Brand Impact

- **If this lands broken, the user experiences:** `worktree-manager.sh create`/`feature` — the entry point of every one-shot/work pipeline — failing, hanging differently, or silently skipping installs on healthy networks; every agent session that needs a worktree is degraded.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the probe emits a host name and a path (both sanitized, no credentials) to stdout; the install surface is unchanged otherwise.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches apps/web-platform/server/git-lock-marker-telemetry.ts — a one-token regex alternation plus a comment/test row in an observe-only log mirror — and a dev-tooling script; no serving surface, auth, billing, or user-data path is reachable from either file.`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_WORKTREE_INSTALL_SKIPPED stdout sentinel (reason=opt-out|registry-unreachable|timeout) emitted by install_deps during create/feature; absence during a healthy create means installs ran or were skipped by lockfile rules"
  cadence: "per create/feature invocation"
  alert_target: "session terminal + per-PID headless log via headless_or_stderr; mirrored to session telemetry once MARKER_RE registers it"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (install_deps) + apps/web-platform/server/git-lock-marker-telemetry.ts:134"

error_reporting:
  destination: "stdout sentinel (greppable under claude --bg) + stderr/log warn line; server-side mirror via git-lock-marker-telemetry extractGitLockMarkers"
  fail_loud: "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=<h> arm=<a> on stdout; a warn line naming the blocked host on stderr/log"

failure_modes:
  - mode: "registry unreachable (sandbox deny)"
    detection: "bounded curl probe rc!=0 -> SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=<blocked host>"
    alert_route: "session terminal / orchestrating agent reading stdout"
  - mode: "install hangs while registry is reachable"
    detection: "timeout(1) rc=124 -> SOLEUR_WORKTREE_INSTALL_SKIPPED reason=timeout arm=<a> secs=<n>"
    alert_route: "session terminal / orchestrating agent reading stdout"
  - mode: "opt-out set (SOLEUR_WORKTREE_SKIP_INSTALL=1 or --no-install)"
    detection: "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out"
    alert_route: "session terminal / run log"
  - mode: "timeout binary absent (no coreutils)"
    detection: "once-per-call warn 'install bound unavailable' + unwrapped run"
    alert_route: "session terminal / run log"

logs:
  where: "terminal stdout/stderr; under headless harness the headless_or_stderr per-PID log at $LOG_DIR/$PPID.log"
  retention: "session lifetime"

discoverability_test:
  command: "grep -n 'SOLEUR_WORKTREE_INSTALL_SKIPPED' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  expected_output: "SOLEUR_WORKTREE_INSTALL_SKIPPED"
```

## Encryption Posture

```yaml
at_rest: []
# No new persistent store. One new outbound connection: the curl preflight probe,
# an unauthenticated GET to the package-registry host the install was already
# going to contact — egress that exists today, bounded earlier.
in_transit:
  - connection: "worktree-manager.sh install_deps -> https://<resolved-registry-host>/"
    enforced_at: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:_registry_reachable"
    tls: "https only — curl --proto '=https' forbids downgrade (deploy-arm.sh:155 precedent)"
    cert_verification: "on (curl default; no -k/--insecure)"
    does_not_defend: "a hostile-but-reachable registry content response — the probe verifies reachability, not payload integrity; lockfile integrity remains the package manager's job"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

The deliverable includes a new assertion-based suite (`worktree-manager-install-bounded.test.sh`) that exists to catch regressions of three contract points — one guard entry covers it.

### Guard 1 — bounded/skippable install contract

**Property.** For every install arm reachable in `install_deps` (root bun/npm, apps/* bun/npm/yarn), the install command cannot run unbounded (timeout wrap), cannot run when opted out (`--no-install`/`SOLEUR_WORKTREE_SKIP_INSTALL=1`), and cannot run un-diagnosed when its registry host is unreachable (preflight + `SOLEUR_WORKTREE_INSTALL_SKIPPED` marker + named host), while `create`/`feature` still exit 0 with the worktree on disk.

**Assembly.** The single chokepoint is `install_deps()` — both call sites (`create_worktree` :2081, `create_for_feature` :2219) dispatch through it, so the assembly is the function's three member sets: the opt-out gate at its head, the per-arm probe+timeout in `_run_install`, and the unconditional hook-dep enumeration. Members outside the chokepoint are the flag-parse loop (feeds the opt-out) and `MARKER_RE` in `git-lock-marker-telemetry.ts` (feeds the marker's downstream visibility). A new install invocation added outside `install_deps` would escape the property — the `lint-workflow-install-sites.sh` assembly scan (which already covers `plugins/**/*.sh` for install invocations) is the structural backstop for that.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `install_to` wrap from `_run_install` (command runs bare), or narrow the rc check to `124` only (137 SIGKILL-escalation slips through as "install failed") | RED — the hang arm (stub `npm` sleeping past `SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS=2`) finishes far over bound / misclassified |
| 2 | Make `_registry_reachable` `return 0` unconditionally (guard's own dispatch — a probe that can never fail) | RED — denied-egress arm asserts the `reason=registry-unreachable` marker is emitted |
| 3 | Check only the env var (or only the flag) in the opt-out gate | RED — the other opt-out arm's suite case fails |
| 4 | Rename the emitted sentinel without touching `MARKER_RE` | RED — `git-lock-marker-telemetry.test.ts` drift guard enumerates emitted `SOLEUR_*` names from the script itself |
| 5 | Move the skip check after the first install arm (opt-out gate misplaced — second-member row: an arms loop that consults the gate per-iteration still exits 0 while running the first arm) | RED — opt-out arm asserts NO install stub was invoked, not merely that the run finished |
| 6 | Must-PASS: `SOLEUR_WORKTREE_SKIP_INSTALL=0` (set but not `=1`) with reachable registry + stub npm | PASS — truthiness is `=="1"`-gated, and a non-canonical env value proves the gate is not "any set value skips" |
| 7 | Must-PASS: reachable registry, working stub npm, no env/flag | PASS — the happy path (`Dependencies installed`, hook-dep present marker) is unaffected by the new layers |

**Anchor.** The marker-registration half of the property is anchored outside this diff's discretion: the drift-guard test mechanically enumerates emitted sentinel names from the shipped script (`readdirSync` over `plugins/soleur/skills/*/scripts/*.sh` + `SENTINEL_RE`), so the producer and the registry cannot silently diverge — the test is the enumerator, not a hand-maintained list.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a bug fix inside a dev-tooling shell script plus a one-line telemetry-mirror alternation. Assessed inline against `brainstorm-domain-config.md` Assessment Questions (no Task-spawning capability in this subagent process — `Reviewed-Coverage: sequential-fallback`): no user-facing pages/flows (Product — the mechanical UI-surface override does not fire: no Files-to-Edit/Create match `components/**/*.tsx`/`app/**/page.tsx`/`layout.tsx` or the ui-surface term list), no legal docs or regulated-data surfaces (Legal), no content/brand (Marketing), no vendor/procurement (Operations), no pipeline (Sales), no budgeting (Finance), no support workflows (Support), no architectural or new-infrastructure decision (Engineering — a bug fix on an existing script is normal implementation; the CTO assessment question targets significant architecture/infrastructure changes).

## Acceptance Criteria

- [ ] **AC1** — `SOLEUR_WORKTREE_SKIP_INSTALL=1 worktree-manager.sh create <branch>` and `worktree-manager.sh --no-install create <branch>` both create the worktree, skip every install arm, print `SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out` on stdout and a human warn naming how to install inside the worktree afterwards, and exit 0.
- [ ] **AC2** — With the registry host unreachable (probe fails), each install arm emits `SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=<blocked-host> arm=<label>` on stdout, prints a warn naming the host, skips that arm's install command without retrying it, and `create`/`feature` still complete with exit 0 and the worktree on disk.
- [ ] **AC3** — Every install arm's command is wrapped via the array pattern `install_to=(timeout|gtimeout -k 15 ${SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS:-300})` invoked as `${install_to[@]+"${install_to[@]}"}` (empty array = no bound, macOS-safe under `set -u`); a stalled install is killed and reported (`reason=timeout` marker + warn) on `rc -eq 124 || rc -eq 137`; any other nonzero rc still takes the existing `install failed` warn path.
- [ ] **AC4** — The preflight probe resolves the registry host per arm (npm via `npm --prefix <dir> config get registry`; bun via `bunfig.toml`/`.npmrc` or `registry.npmjs.org`; yarn via `.yarnrc` or `registry.yarnpkg.com`), is curl-gated and memoized per host, and uses `curl --proto '=https' --connect-timeout … --max-time …` with no `-f` (any HTTP response = reachable).
- [ ] **AC5** — `SOLEUR_WORKTREE_INSTALL_SKIPPED` is added to `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` and is NOT in `WEDGE_RE` (mirrored-not-paged); `apps/web-platform/test/git-lock-marker-telemetry.test.ts` carries a row asserting `wedged: false`.
- [ ] **AC6** — New suite `plugins/soleur/test/worktree-manager-install-bounded.test.sh` covers: opt-out via env var, opt-out via flag, unreachable-registry skip (host named in marker), timeout bound (`SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS` set low), happy path unaffected, and the `feature` subcommand path. It sets `INCIDENTS_REPO_ROOT` inside its own tmpdir before sourcing `test-helpers.sh` (#8659 pattern), composes `node_modules/.bin/$HOOK_BIN` paths rather than literal tokens (M7a), and exits 0.
- [ ] **AC7** — `--no-install` and `SOLEUR_WORKTREE_SKIP_INSTALL` are documented in `show_help` Global Flags and in `plugins/soleur/skills/git-worktree/SKILL.md`.
- [ ] **AC8** — `bash plugins/soleur/test/worktree-manager-install-bounded.test.sh` exits 0; `bash plugins/soleur/test/worktree-manager-hook-deps.test.sh` still passes 13/13 (output strings unchanged); `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts` green (vitest is the package's runner — `package.json` `"test": "vitest"`, and `apps/web-platform/bunfig.toml` `pathIgnorePatterns = ["**"]` makes `bun test` inert there — NEVER prescribe `bun test`/`npm run -w` for this package); `bash scripts/lint-workflow-install-sites.sh` and `bash scripts/lint-orphan-test-suites.sh` green.

## Test Scenarios

- **Given** a fixture repo with `package-lock.json`, a PATH-stub `npm` that records invocations, and `SOLEUR_WORKTREE_SKIP_INSTALL=1`, **when** `create` runs, **then** the worktree exists, the stub recorded zero invocations, stdout carries `reason=opt-out`, and rc=0.
- **Given** the same fixture with `--no-install` on the command line, **when** `create` runs, **then** identical observable outcome (proves the flag and env var feed one gate).
- **Given** a PATH-stub `curl` that exits non-zero for `registry.npmjs.org` and a PATH-stub `npm` that records invocations, **when** `create` runs on a lockfile repo, **then** the npm stub is never invoked, stdout carries `SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable` with `host=registry.npmjs.org`, stderr/log names the blocked host, worktree exists, rc=0.
- **Given** a PATH-stub `npm` that `sleep`s longer than `SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS=2`, **when** `create` runs, **then** the suite's wall clock stays under a bounded ceiling, stdout carries `reason=timeout`, rc=0, worktree exists.
- **Given** `SOLEUR_WORKTREE_SKIP_INSTALL=0` (set, non-`1`), **when** `create` runs with a working stub npm, **then** install runs normally (`Dependencies installed`) — the gate is `=="1"`, not "any set".
- **Given** `feature <name>` (not `create`) with the opt-out set, **when** the worktree is created, **then** no install runs and the skip marker prints — covering the second call site behaviorally, not just structurally.
- **Given** a lockfile repo where curl succeeds but the install command exits non-zero, **when** `create` runs, **then** the existing `install failed` warn path is unchanged.
- **Local verification:** `bash plugins/soleur/test/worktree-manager-install-bounded.test.sh` — expect suite ledger `0 failed`, rc=0.

## Open Code-Review Overlap

2 open scope-outs touch files in this plan's edit list (`gh issue list --label code-review --state open`, 87 issues queried 2026-09-30):

- **#8496** `review: cleanup-merged never gh-queries [gone] branches that have no worktree` — same file (`worktree-manager.sh`), different function (`cleanup_merged_worktrees`). **Acknowledge:** unrelated function; folding it in would merge two separable changes. Left open.
- **#8659** `review: 33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs` — affects how the NEW suite is written, not the script. **Fold in (as authoring guidance):** the new suite sets `INCIDENTS_REPO_ROOT` to a dir inside its own `TEST_DIR` before sourcing `test-helpers.sh`, so it does not become a 34th instance of the flagged pattern. The scope-out itself stays open.

## Success Metrics

- In a denied-egress sandbox, `worktree-manager.sh --yes create <branch>` completes in seconds (preflight-bound), prints the blocked host by name, exits 0, and leaves a leased worktree whose missing-deps state is visible via the hook-dep enumeration — the pipeline halts on the *diagnostic*, not on a killed process.
- No `create`/`feature` run can exceed `SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS` (+ kill grace) inside any single install arm.
- `SOLEUR_WORKTREE_INSTALL_SKIPPED` is mirrored by `extractGitLockMarkers` and never classified `wedged: true`.

## Dependencies & Risks

- **Private-registry divergence:** a repo installing from an internal registry that curl cannot reach but the package manager can (file-only proxy config) gets a false `registry-unreachable` skip. Mitigated: per-arm host resolution reads the package manager's own config where cheap; the timeout + opt-out are the recovery surface; the warn names the probed host so the misdiagnosis is visible.
- **`timeout` absence (macOS sans coreutils):** warn-once + unwrapped run — degraded to pre-fix behavior on that host for hangs (preflight still bounds the denied case). Acceptable: this repo's pipeline hosts run Linux; the alternative (bash watchdog) was cut (see Cut list).
- **False-skip on flaky egress:** a transient probe failure skips that arm while another arm's registry may still be reachable — per-arm probing (not a global short-circuit) keeps the skip scoped; re-running the install inside the created worktree is the documented recovery.
- **`npm config get registry` cost:** one subprocess per npm arm (~tens of ms) — bounded and only when a lockfile-routed arm actually runs.
- **Marker cardinality:** `host=`/`arm=`/`reason=` values are sanitized via `_sanitize_marker_field`; `arm=` enumerates `root`/`app:<name>` shapes only — no unbounded user input reaches the marker.

## References & Research

- Issue: #9269 (`gh issue view 9269` — OPEN, `type/bug`; incident: Devin egress deny on `registry.npmjs.org:443`, ~100 retries, killed by the caller).
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — `install_deps` :1653; call sites :2081/:2219; globals :151–156; flag loop + `show_help` at file tail; `_sanitize_marker_field` :1417; marker/`headless_or_stderr` conventions :2239.
- `plugins/soleur/scripts/lib/session-state.sh` — `headless_or_stderr` :595; `SOLEUR_DISABLE_SESSION_STATE` `=="1"` convention :27; `SOLEUR_SESSION_STATE_ROOT` override :33.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — `MARKER_RE` :134, `WEDGE_RE` :309, MIRRORED-NOT-PAGED comment class :153–305.
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — sentinel drift guard :261–384 (scan set: `plugins/soleur/skills/*/scripts/*.sh` + `skills/*/SKILL.md`; DOMAIN_RE includes `SOLEUR_WORKTREE_`).
- `plugins/soleur/test/worktree-manager-hook-deps.test.sh` — suite conventions (fixtures, `run_create`, PATH stubs, M7a).
- `plugins/soleur/test/test-helpers.sh` :32–77 — incident sandbox + composed EXIT trap (#8659).
- `scripts/test-all.sh` :97 — `plugins/soleur/test/*.test.sh` glob registration; `scripts/lint-orphan-test-suites.sh` verifies.
- `scripts/lint-workflow-install-sites.sh` — `plugins/**/*.sh` assembly scan; keep `allow-bun` waivers colocated.
- `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` — L3→L7 framing used in `## Hypotheses` (fired on `unreachable`/`timeout` triggers).
- `.claude/hooks/git-commit-secret-scan.sh` :147-175 — canonical `timeout`→`gtimeout`→empty-array pattern (bash-3.2-safe `${a[@]+"${a[@]}"}`) + the documented 124/137 bound-expiry exit semantics.
- curl precedent: `plugins/soleur/scripts/deploy-arm.sh:155` (`--proto '=https' --max-time`); `npm --prefix <dir> config get registry` verified live on npm 11.19.1 → `https://registry.npmjs.org/`; `curl --proto '=https' … https://registry.npmjs.org/` verified rc=0 on a healthy host.
- Test-runner verification (catalogue lines 47-48): `apps/web-platform/package.json` `"test": "vitest"`; `bunfig.toml` `pathIgnorePatterns = ["**"]` blocks `bun test` in that package; `vitest.config.ts:87` include glob `test/**/*.test.ts` matches the suite this plan edits.

## Sharp Edges

- The drift guard derives the emitted-sentinel set from the script text itself — write `echo "SOLEUR_WORKTREE_INSTALL_SKIPPED …"` exactly once per reason arm; renaming it without updating `MARKER_RE` reddens `git-lock-marker-telemetry.test.ts`, and naming it in `SKILL.md` prose requires the same registration (the scan covers both).
- Do not reuse an existing sentinel name for this condition (`SOLEUR_FEATURE_PUSH_FAILED`, `SOLEUR_GIT_REPO_DIAG`): reusing a monitored name inherits its paging classification silently — mint the new name and pin its classification explicitly (learning `2026-08-12`).
- The flag loop treats every unrecognized arg as positional — `--no-install` must be consumed there or it reaches `create` as a branch name.
- `install_deps` runs under `set -euo pipefail` inside functions that callers invoke unguarded in places — every probe/resolution must be guarded; an unguarded failing `npm config get` would abort the whole `create` on an unrelated credential/config error.
- The `hook-deps` suite asserts `"Dependencies installed"` and the hook-dep warn line — keep those strings byte-identical.
- Keep the `# lint-workflow-install-sites: allow-bun` comments on the lines that invoke `bun install` — the waiver is per-line.
- On `feature`, the worktree is pushed after install; a fully-denied sandbox also fails that push — already handled (`SOLEUR_FEATURE_PUSH_FAILED`); do not "fix" it into the install marker or conflate the two reasons.
- `timeout` is absent on stock macOS — use the canonical `install_to=()` / `command -v timeout || gtimeout` / `${install_to[@]+"${install_to[@]}"}` shape from `.claude/hooks/git-commit-secret-scan.sh:151-154`, never a bare `timeout` string (catalogue line 3). Bound expiry is rc **124 or 137** (SIGKILL escalation under `-k`), not 124 only (:157-160 in the same file).
- `curl` probes pin `--connect-timeout`/`--max-time` (catalogue line 121) — never an unbounded network call; `-f` is deliberately absent (any HTTP response, even an error status, proves reachability).
- A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail `deepen-plan` Phase 4.6; a plan missing `## Observability`/`## Guard Contract` while detection fires fails 4.7/4.11 — all three are present above.
