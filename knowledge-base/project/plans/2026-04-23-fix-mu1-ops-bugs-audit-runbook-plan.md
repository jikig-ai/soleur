# Fix MU1 Ops Bugs — Audit Script + Runbook Triple-Fix (#2837, #2838, #2839)

**Type:** bug bundle
**Scope:** ops / infrastructure (no app code, no migrations, no user-facing surface)
**Issues:** [#2837][i2837], [#2838][i2838], [#2839][i2839]
**Found by:** [#2616][i2616] MU1 re-verification cycle (2026-04-23)

[i2837]: https://github.com/jikig-ai/soleur/issues/2837
[i2838]: https://github.com/jikig-ai/soleur/issues/2838
[i2839]: https://github.com/jikig-ai/soleur/issues/2839
[i2616]: https://github.com/jikig-ai/soleur/issues/2616

## Overview

Three independent bugs surfaced during a single MU1 re-verification cycle.
All three sit in the MU1 verification pipeline (audit script +
runbook); fixing them together is cheaper than three separate PRs
because they share reviewers, context, and re-verification cost. None
of the three touches app code, migrations, user-facing surfaces, or
security boundaries (we are tightening the audit, not loosening any
control).

| # | Bug | Surface | Severity |
|---|-----|---------|----------|
| #2837 | `audit-bwrap-uid.sh` check 2 literal-path match fails on every valid deploy (Docker inlines seccomp JSON) | `apps/web-platform/infra/audit-bwrap-uid.sh` | P2 — false-positive P0 signal |
| #2838 | Runbook Step 3 assumes `~/soleur/` checkout on prod host; no such checkout exists | `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` | P3 — invocation unusable as documented |
| #2839 | Cleanup sweep uses `SUPABASE_URL` (empty in dev) + regex `/(^|\.)dev\./` which misses project-ID hostnames | same runbook, Step 2 cleanup snippet | P3 — backstop unusable |

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue bodies) | Reality (verified 2026-04-23) | Plan response |
|---|---|---|
| #2837: seccomp profile lives on host only | Source-of-truth is in repo at `apps/web-platform/infra/seccomp-bwrap.json`; `ci-deploy.sh` bind-mounts it to `/etc/docker/seccomp-profiles/soleur-bwrap.json` on the host | Hash-compare inlined JSON against the on-host file (Option 3 from #2837) — on-host copy is the deploy contract, matches prod reality without requiring audit script to know the repo path |
| #2838: script only reachable via repo checkout | Confirmed — `find / -name audit-bwrap-uid.sh` on prod returns nothing; neither deploy nor image bakes it in | Update runbook to use stdin-piped form (`ssh <host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh`) — Option 1 from #2838. Option 2 (deploy script to host) is deferred to #2606 (already tracks CI wiring) |
| #2839: env var is `SUPABASE_URL`, guard regex checks `dev.` | Confirmed — dev Doppler exposes only `NEXT_PUBLIC_SUPABASE_URL`; actual URL is `https://ifsccnjhymdmidffkzhl.supabase.co` (no `dev` token); Doppler has NO `SUPABASE_DEV_PROJECT_REF` today | Switch env var to `NEXT_PUBLIC_SUPABASE_URL`. Derive project ref from URL hostname (first DNS label) and assert against a hard-coded constant `ifsccnjhymdmidffkzhl` (dev project ref is stable infra state, not a rotating secret — no new Doppler var needed). Assert `process.env.DOPPLER_CONFIG === "dev"` as belt-and-suspenders |

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (2026-04-23) against both target paths; no matches.

## Hypotheses

Not applicable. All three bugs are directly observable and reproducible
from the runbook:

- #2837: `docker inspect soleur-web-platform --format '{{json .HostConfig.SecurityOpt}}'` on prod shows inlined JSON, not the path. Literal-string match against `seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json` cannot match; false FAIL is deterministic.
- #2838: `find / -name audit-bwrap-uid.sh` on prod returns empty. SSH `cd soleur && …` fails with `No such file or directory`. Deterministic.
- #2839: `doppler run -p soleur -c dev -- node -e 'console.log(process.env.SUPABASE_URL)'` prints empty; `NEXT_PUBLIC_SUPABASE_URL` resolves to `https://ifsccnjhymdmidffkzhl.supabase.co`, which fails the regex `/(^|\.)dev\.|-dev\.|dev-/`. Deterministic.

## Goals

1. `audit-bwrap-uid.sh` check 2 reports PASS on a correctly-deployed container (matches reality) and FAIL on genuine drift (either the custom seccomp/apparmor is missing OR the inlined seccomp JSON diverges from the on-host file).
2. The runbook Step 3 command works verbatim against a prod host with no additional setup. Runbook Step 2 cleanup snippet runs to completion under `doppler run -p soleur -c dev --` without false blast-radius refusals.
3. No new Doppler vars, no new infra resources, no migrations, no app code changes. No loosening of any existing security control.

## Non-Goals

- Deploying the audit script to the prod host (tracked separately by [#2606][i2606] — CI wiring).
- Rewriting check 2's apparmor detection (the apparmor side of check 2 uses a literal profile **name** match, not a path — Docker preserves names in `HostConfig.SecurityOpt[0]`, so that half of check 2 is working correctly today).
- Adding new assertions (e.g., profile freshness, version tagging). Out of scope for a bug bundle; file follow-up issues if desired.

[i2606]: https://github.com/jikig-ai/soleur/issues/2606

## Implementation Phases

### Phase 1 — Audit script: replace literal-string check with content-signature check (#2837)

**File:** `apps/web-platform/infra/audit-bwrap-uid.sh`

**Current behavior (lines 95–109):**

```bash
SECURITY_OPT_JSON=$(docker inspect "$CONTAINER" --format '{{json .HostConfig.SecurityOpt}}' 2>/dev/null || echo 'null')

if [[ "$SECURITY_OPT_JSON" != *"$EXPECTED_APPARMOR"* ]]; then
  emit_fail "HostConfig.SecurityOpt missing $EXPECTED_APPARMOR (got: $SECURITY_OPT_JSON)"
else
  emit_pass "HostConfig.SecurityOpt includes $EXPECTED_APPARMOR"
fi

if [[ "$SECURITY_OPT_JSON" != *"$EXPECTED_SECCOMP"* ]]; then
  emit_fail "HostConfig.SecurityOpt missing $EXPECTED_SECCOMP (got: $SECURITY_OPT_JSON)"
else
  emit_pass "HostConfig.SecurityOpt includes $EXPECTED_SECCOMP"
fi
```

**New behavior:**

- Keep the apparmor check as-is (literal-name match is correct — Docker preserves profile names).
- Replace the seccomp literal-path check with a two-step assertion:
  1. Extract the inlined seccomp JSON from `HostConfig.SecurityOpt` (each element is a distinct `seccomp=<json>` entry; find the one starting with `seccomp=`, strip the prefix).
  2. jq-normalize both the inlined JSON and the on-host file at `/etc/docker/seccomp-profiles/soleur-bwrap.json`, sha256 each, compare.
- FAIL cases:
  - No `seccomp=` entry found → custom seccomp not attached.
  - On-host file missing → deploy state is incoherent.
  - Hashes differ → drift between inlined runtime profile and host artifact.
- INFO: on PASS, print the matched sha256 prefix so the audit log traces which profile was attached.

**Sketch (illustrative — not verbatim final code):**

```bash
# Extract the seccomp entry from HostConfig.SecurityOpt (may be inlined JSON or literal path).
SECCOMP_ENTRY=$(
  docker inspect "$CONTAINER" \
    --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' 2>/dev/null \
    | sed -n 's/^seccomp=//p' \
    | head -n1
)

if [[ -z "$SECCOMP_ENTRY" ]]; then
  emit_fail "HostConfig.SecurityOpt has no seccomp= entry — custom profile not attached"
elif [[ ! -r "$EXPECTED_SECCOMP_PATH" ]]; then
  emit_fail "On-host seccomp profile missing at $EXPECTED_SECCOMP_PATH — deploy state incoherent"
else
  FILE_HASH=$(jq -cS . "$EXPECTED_SECCOMP_PATH" | sha256sum | cut -d' ' -f1)
  INLINED_HASH=$(printf '%s' "$SECCOMP_ENTRY" | jq -cS . 2>/dev/null | sha256sum | cut -d' ' -f1)
  if [[ "$INLINED_HASH" != "$FILE_HASH" ]]; then
    emit_fail "seccomp drift: inlined profile sha256=${INLINED_HASH:0:12} != on-host sha256=${FILE_HASH:0:12}"
  else
    emit_pass "HostConfig.SecurityOpt seccomp matches on-host profile (sha256=${FILE_HASH:0:12})"
  fi
fi
```

**New constant:** `EXPECTED_SECCOMP_PATH="/etc/docker/seccomp-profiles/soleur-bwrap.json"` (replaces `EXPECTED_SECCOMP`, which is now only referenced by the comment in `## Failure Remediation`).

**Robustness notes:**

- `jq -cS .` — compact + sort-keys, deterministic canonical form. Prevents whitespace/key-order false positives.
- `sed -n 's/^seccomp=//p' | head -n1` — Docker allows multiple `--security-opt seccomp=…` flags (last wins). Take the first `seccomp=` entry; if prod ever passes more than one, the drift detector will still catch a mismatch.
- `jq … 2>/dev/null` on the inlined side: if the entry is a literal path (Docker default) rather than inlined JSON, jq exits non-zero, the hash is the hash of empty input, and the comparison fails cleanly. Explicit handling: if the entry starts with `/`, emit `FAIL: seccomp entry is a literal path, not inlined JSON — Docker did not resolve --security-opt` before hashing.

### Phase 2 — Runbook Step 3: switch to stdin-piped SSH invocation (#2838)

**File:** `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`

**Current (lines 120–122):**

```bash
ssh <prod-host> "cd soleur && bash apps/web-platform/infra/audit-bwrap-uid.sh"
```

**New:**

```bash
# From any Soleur worktree or the bare repo root (the script is read locally, piped to prod).
ssh <prod-host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh
```

**Also add a one-line note** under the command explaining the form and pointing to [#2606][i2606] for the CI-wiring follow-up:

> The script is streamed via stdin — there is no repo checkout on the prod host by design. [#2606][i2606] tracks automating this invocation in CI.

**Adjust footer markdown-link definitions** if `[i2606]:` is not already present in the runbook (it is — line 224 references it as `[#2606](https://github.com/jikig-ai/soleur/issues/2606)`, already in-line link form; keep consistent with the existing style, no new reference definition needed).

**Adjust `CONTAINER` override note:** The script's existing header already documents `CONTAINER=soleur-web-platform-canary bash .../audit-bwrap-uid.sh`. With the stdin form, the override becomes `ssh <host> "CONTAINER=soleur-web-platform-canary bash -s" < …`. Add this as a sub-bullet in the runbook.

### Phase 3 — Runbook Step 2: fix cleanup-sweep guard (#2839)

**File:** `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` (lines 97–114)

**Current guard (lines 98–102):**

```js
const url = process.env.SUPABASE_URL || "";
if (!/(^|\.)dev\.|-dev\.|dev-/.test(url)) {
  throw new Error("Refusing to run cleanup against non-dev Supabase URL: " + url);
}
```

**New guard:**

```js
// Dev-Doppler exposes the URL under its Next.js-public name; use it directly.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl"; // Soleur dev Supabase project ref — stable infra.
const host = url ? new URL(url).hostname : "";
const actualRef = host.split(".")[0];
if (process.env.DOPPLER_CONFIG !== "dev") {
  throw new Error("Refusing to run cleanup: DOPPLER_CONFIG is not 'dev' (got: " + (process.env.DOPPLER_CONFIG || "<unset>") + ")");
}
if (actualRef !== DEV_PROJECT_REF) {
  throw new Error("Refusing to run cleanup: Supabase project ref '" + actualRef + "' != expected dev ref '" + DEV_PROJECT_REF + "' (url=" + url + ")");
}
```

**Why both checks (Doppler config AND project-ref constant)?** Belt-and-suspenders. The Doppler-config check prevents running under `-c prd` by accident even if someone later widens the URL constant. The project-ref check prevents running under `-c dev` against a forked/wrong-URL environment. Either trip is a hard abort — there is no "override" flag, consistent with `cq-destructive-prod-tests-allowlist`.

**Why a hard-coded constant, not a Doppler var?** The dev project ref is stable infrastructure (we would create a new project, not rename the ref). Adding a Doppler var just to hold a value that never changes would add deploy-rotation cost with zero safety benefit. If the ref ever *does* change, both this runbook snippet and the test's `SYNTH` allowlist will need updating together (same commit) — a constant makes the coupling explicit.

**One docs-consistency edit:** line 94 currently says *"re-asserts the Supabase URL looks like a non-prod project"*. Rewrite to match the new implementation: *"hard-asserts (a) DOPPLER_CONFIG = dev, (b) the project ref in NEXT_PUBLIC_SUPABASE_URL matches the dev project ref"*.

### Phase 4 — Tests

Two new tests, both in `apps/web-platform/infra/`, matching the existing
`<script>.test.sh` convention (see `ci-deploy.test.sh`,
`orphan-reaper.test.sh`, etc.). Pure bash, no framework.

**`apps/web-platform/infra/audit-bwrap-uid.test.sh`** (new file):

- **Harness:** mock `docker` by prepending a stub to `PATH` that returns canned `docker inspect` outputs from per-case fixture files.
- **Cases:**
  1. PASS case: inlined seccomp JSON matches a temp file on disk → exit 0.
  2. FAIL case: inlined JSON differs (add a whitespace-insensitive variant to prove jq-normalization is load-bearing) → exit 1 with `seccomp drift` in stderr.
  3. FAIL case: no `seccomp=` entry in SecurityOpt → exit 1 with `has no seccomp= entry` in stderr.
  4. FAIL case: inlined is a literal path (simulating Docker not resolving the flag) → exit 1 with `literal path, not inlined JSON` in stderr.
  5. FAIL case: apparmor missing → exit 1 (regression guard on the apparmor-side path we intentionally did not touch).
  6. Each test isolates `EXPECTED_SECCOMP_PATH` to a tempdir via env override.

**Env override support in `audit-bwrap-uid.sh`:** change `EXPECTED_SECCOMP_PATH` to `EXPECTED_SECCOMP_PATH="${EXPECTED_SECCOMP_PATH:-/etc/docker/seccomp-profiles/soleur-bwrap.json}"` so the test can point it at a fixture without modifying the script. Only the test relies on this override; prod invocations use the default.

**Env override support for `docker exec` in check 1:** Already handled via mock-docker stub (the stub returns whatever exit code/output the fixture dictates for `docker exec …`).

**Stub `docker` binary (sketch):**

```bash
#!/usr/bin/env bash
# test fixture: mock docker
case "$1 $2" in
  "inspect --format") cat "${DOCKER_INSPECT_FIXTURE:-/dev/null}" ;;
  "exec *")           cat "${DOCKER_EXEC_FIXTURE:-/dev/null}"; exit "${DOCKER_EXEC_EXIT:-0}" ;;
  *)                  echo "unexpected docker arg: $*" >&2; exit 99 ;;
esac
```

**`apps/web-platform/infra/mu1-runbook-cleanup.test.sh`** (new file):

- **Purpose:** lock the three guard invariants in the new cleanup snippet (#2839).
- **Approach:** extract the cleanup snippet's guard block into a vendored helper (`apps/web-platform/infra/mu1-cleanup-guard.mjs`), `require`/`import` it from the test, exercise four fixtures:
  1. `DOPPLER_CONFIG=dev`, correct URL → no throw.
  2. `DOPPLER_CONFIG=prd`, correct URL → throw with `DOPPLER_CONFIG`.
  3. `DOPPLER_CONFIG=dev`, wrong URL (prod project ref) → throw with `project ref`.
  4. `DOPPLER_CONFIG=dev`, empty URL → throw with `project ref ''`.

**Why vendor the snippet as `mu1-cleanup-guard.mjs`?** A runbook snippet
that only ever runs via copy-paste is impossible to regression-test.
Moving it to a real file that the runbook *sources* is the minimum
change that makes the guard testable without adding ceremony. The
runbook Step 2 becomes:

```bash
doppler run -p soleur -c dev -- node -e '
  import("./apps/web-platform/infra/mu1-cleanup-guard.mjs").then(({ assertDevCleanupEnv, sweep }) => {
    assertDevCleanupEnv();  // throws per Phase 3 guard rules
    sweep();
  });
'
```

If this re-entry cost is judged too high, an acceptable simplification
is to keep the guard inline in the runbook and skip the node-side test
(rely on Phase 5 manual verification only). Plan review should decide.
**Default choice: vendor the guard.** A backstop we cannot test drifts
again.

### Phase 5 — Manual re-verification (post-implementation, pre-merge)

Run the full runbook end-to-end against prod, record outputs. This is
the gating verification that the bundle closes all three issues:

- [ ] **#2837 check:** `ssh <prod-host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh` returns exit 0, prints three `PASS:` lines including the new seccomp hash line.
- [ ] **#2838 check:** same command above works from `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-mu1-ops-bugs-2837-2838-2839/` without first cloning onto the host.
- [ ] **#2839 check:** the new runbook Step 2 cleanup snippet, run under `doppler run -p soleur -c dev --`, completes with either `0 synthetic users deleted` or the expected synthetic-user count. Confirm throw-paths by temporarily setting `DOPPLER_CONFIG=prd` (don't actually run the sweep) and observing the guard throws.
- [ ] **Regression check:** rerun `./node_modules/.bin/vitest run test/mu1-integration.test.ts` from `apps/web-platform/` — must still be 4 passed / 2 skipped (no test changes).

## Files to Edit

- `apps/web-platform/infra/audit-bwrap-uid.sh` — Phase 1 (check 2 rewrite + env override for test harness).
- `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` — Phase 2 (Step 3 stdin invocation) + Phase 3 (Step 2 cleanup guard).

## Files to Create

- `apps/web-platform/infra/audit-bwrap-uid.test.sh` — Phase 4 (audit script tests, bash).
- `apps/web-platform/infra/mu1-cleanup-guard.mjs` — Phase 4 (vendored guard helper, ESM node module).
- `apps/web-platform/infra/mu1-runbook-cleanup.test.sh` — Phase 4 (guard tests, bash + node -e fixtures).

## Files NOT to Edit (explicit)

- `apps/web-platform/infra/ci-deploy.sh` — the seccomp path constant lives here too (lines 260, 309) but is correct and unrelated.
- `apps/web-platform/infra/seccomp-bwrap.json` — deploy artifact, unchanged.
- `apps/web-platform/test/mu1-integration.test.ts` — unchanged; the new cleanup guard is for the post-crash sweep path only, not the test's own `finally`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 4 tests pass locally: `bash apps/web-platform/infra/audit-bwrap-uid.test.sh` and `bash apps/web-platform/infra/mu1-runbook-cleanup.test.sh` both exit 0.
- [ ] `shellcheck apps/web-platform/infra/audit-bwrap-uid.sh` clean (currently clean on main; don't regress).
- [ ] `node --check apps/web-platform/infra/mu1-cleanup-guard.mjs` passes.
- [ ] `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` leaves the file clean (run on the specific path per `cq-markdownlint-fix-target-specific-paths`).
- [ ] `grep -n 'SUPABASE_URL' knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` returns no hits on the bare `SUPABASE_URL` form inside Step 2 (only `NEXT_PUBLIC_SUPABASE_URL`).
- [ ] `grep -n 'cd soleur' knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` returns zero hits.
- [ ] PR body includes `Closes #2837`, `Closes #2838`, `Closes #2839` each on their own line in the body (not title).

### Post-merge (operator)

- [ ] Run the full MU1 runbook verbatim against prod (all four steps). Phase 5 checklist above, output attached to the PR as a comment. If the new audit script ever fails on prod after this PR merges, the failure is a real regression — no more false-positives to triage around.
- [ ] No change to [#2606][i2606]'s scope (CI-wiring follow-up remains open; this PR does not close it).

## Test Scenarios

Covered under Phase 4 above. Summary:

| Scenario | Expected |
|----------|----------|
| Valid deploy (inlined seccomp matches on-host) | audit exit 0, 3 PASS lines |
| Seccomp drift (inlined ≠ on-host) | audit exit 1, `seccomp drift` in stderr |
| Seccomp flag dropped (no `seccomp=` entry) | audit exit 1, `no seccomp= entry` in stderr |
| On-host file removed | audit exit 1, `deploy state incoherent` in stderr |
| Apparmor dropped | audit exit 1, same as today (regression guard) |
| Cleanup guard under `-c dev` + correct URL | no throw |
| Cleanup guard under `-c prd` | throw with `DOPPLER_CONFIG` |
| Cleanup guard under `-c dev` + wrong project ref | throw with `project ref` |
| Cleanup guard under `-c dev` + empty URL | throw with `project ref ''` |

## Alternative Approaches Considered

| Alternative | Why rejected |
|-------------|-------------|
| #2837 Option 1: `grep Seccomp /proc/1/status` for mode-2 | Doesn't distinguish Docker default from custom; weaker than hash compare |
| #2837 Option 2: marker-string grep (`"soleur #1557"`) | Brittle against profile edits that remove comments; hash compare is strictly stronger |
| #2838 Option 2: deploy script to `/opt/soleur/bin/` | Useful but scope-creep for a bug-fix PR; [#2606][i2606] already tracks the CI-side equivalent. Tag-along deploy infra doesn't belong in a three-line runbook fix |
| #2839 new Doppler var `SUPABASE_DEV_PROJECT_REF` | Adds deploy ceremony for a value that is structurally immutable; hard-coded constant + DOPPLER_CONFIG double-check is equivalent safety with less surface |
| #2839 skip guard entirely, rely on Doppler config scoping | Violates `cq-destructive-prod-tests-allowlist`: destructive ops against shared state MUST hard-assert identifiers |

## Risks

- **Risk: future seccomp profile edits change the hash, breaking check 2 until the file is re-deployed.** Mitigation: the check is comparing inlined-runtime vs on-host; both are deploy artifacts, so a profile edit that makes it to the host WITHOUT restarting the container will (correctly) FAIL check 2 until the container is restarted — this is desired behavior (detects "profile edited but not redeployed" regressions).
- **Risk: hard-coded project ref `ifsccnjhymdmidffkzhl` drifts if dev Supabase is ever reprovisioned.** Mitigation: the value is tagged with a comment; grep-stable; and the runbook explicitly notes the coupling to the test's SYNTH regex. Reprovisioning is a rare enough event that a one-line update during that migration is acceptable.
- **Risk: vendoring the cleanup guard changes the invocation shape of Step 2.** Mitigation: the new form is still a single `doppler run -p soleur -c dev -- node -e '…'` command — same cognitive shape as today. The import line adds 2 lines of ceremony, which is the cost of making the guard testable.

## Research Insights

- **Seccomp deploy contract** — verified via `grep -n seccomp apps/web-platform/infra/ci-deploy.sh`: `ci-deploy.sh:260` and `:309` bind `/etc/docker/seccomp-profiles/soleur-bwrap.json` into the container via `--security-opt seccomp=<path>`. The host-side file is the deploy artifact; it is (per the issue body) byte-identical to the inlined JSON when the deploy is healthy.
- **Doppler dev state** — verified via `doppler secrets --project soleur --config dev`: `NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are present; `SUPABASE_URL` and `SUPABASE_DEV_PROJECT_REF` are not. Guard re-write must handle current state without requiring new secrets.
- **No code-review overlap** — `gh issue list --label code-review --state open` against the two target file paths returned zero matches on 2026-04-23.
- **Test framework reconciliation** — the repo has no bats/pytest. Existing infra tests all follow the `<script>.test.sh` pattern (`ci-deploy.test.sh`, `orphan-reaper.test.sh`, `resource-monitor.test.sh`, `disk-monitor.test.sh`). New tests follow the same convention.
- **CLI verification** — this plan embeds four shell/CLI invocations that will land in the runbook: `ssh <host> "bash -s" < <path>`, `doppler run -p soleur -c dev -- node -e '…'`, `docker inspect --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}'`, and `jq -cS .`. All four are standard POSIX/vendor-documented forms used elsewhere in the repo. No fabricated tokens. Per `cq-docs-cli-verification`, these are not "new" invocations requiring `<!-- verified: … -->` annotation — they are already in active use (`doppler run -p soleur -c dev` on line 79 of the runbook today; `ssh "bash -s"` is a standard stdin-streaming SSH idiom; `jq -cS` documented in `jq` manual; `docker inspect --format` used in `apps/web-platform/infra/ci-deploy.sh`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — three ops/infrastructure bug fixes in audit tooling and a runbook. No product surface, no marketing impact, no security boundary change (strictly tightening detection, not loosening controls). No new dependencies, no migrations, no user-facing copy.

## Cross-references

- Plan: this file
- Issues: [#2837][i2837], [#2838][i2838], [#2839][i2839]
- Parent verification cycle: [#2616][i2616]
- Related MU1 plan: `knowledge-base/project/plans/2026-04-18-ops-verify-signup-workspace-provisioning-plan.md`
- Runbook under edit: `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`
- Audit script under edit: `apps/web-platform/infra/audit-bwrap-uid.sh`
- Follow-up (not in scope): [#2606][i2606] — CI wiring for the audit script
- Roadmap row: `knowledge-base/product/roadmap.md` Pre-Phase 4 MU1
