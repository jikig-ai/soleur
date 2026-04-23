# Fix MU1 Ops Bugs — Audit Script + Runbook Triple-Fix (#2837, #2838, #2839)

**Type:** bug bundle
**Scope:** ops / infrastructure (no app code, no migrations, no user-facing surface)
**Issues:** [#2837][i2837], [#2838][i2838], [#2839][i2839]
**Found by:** [#2616][i2616] MU1 re-verification cycle (2026-04-23)

## Enhancement Summary

**Deepened on:** 2026-04-23
**Sections enhanced:** Phase 1 (audit-bwrap hash-compare), Phase 3 (cleanup guard), Phase 4 (tests)
**Depth sources:** repo test conventions (`ci-deploy.test.sh`, `disk-monitor.test.sh`, `orphan-reaper.test.sh`), `doppler run` env-var verification, `jq --help` flag verification, `docker inspect --format` verification, `seccomp-bwrap.json` structure inspection.

### Key Improvements

1. Test harness pattern pinned to the existing repo convention (`MOCK_DOCKER_MODE`-driven unified mock, subshell-isolated cases, `PASS/FAIL/TOTAL` counters, hardened `TEST_PATH_BASE` that excludes `~/.local/bin`) — no new pattern is introduced.
2. `DOPPLER_CONFIG` and `DOPPLER_PROJECT` are confirmed set by `doppler run` (empirical verification — `doppler run -p soleur -c dev -- node -e '…'` prints `dev soleur`). The belt-and-suspenders guard is implementable, not hypothetical.
3. Strict-mode safety audited for the audit script: every new comparison uses `[[` (bash conditional), not `[` (POSIX test) — matches the existing `set -euo pipefail` header. The pipe chain `… | jq -cS . | sha256sum` is wrapped to fail the case rather than abort the script on a non-JSON inlined entry.
4. `jq -cS` flag verification performed against the installed `jq` (`jq --help | grep -E 'sort-keys|compact'`) — both flags confirmed present; no version pin required.
5. `docker inspect --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}'` verified against `docker --help` (Go-template formatting is documented standard behavior).
6. "Literal path" detection uses bash `[[ "$entry" == /* ]]` — empirically verified in this deepen pass.

### New Considerations Discovered

- `docker inspect`'s `.HostConfig.SecurityOpt` is an array; Docker stores each `--security-opt X=Y` as one element. The `apparmor=` and `seccomp=` entries are always separate elements — the current literal-contains check over the full JSON array accidentally worked for apparmor only because the profile name is short and has no JSON-escape collisions. The deepened plan uses `{{range … {{println .}}}}` to iterate elements explicitly.
- The test's SYNTH regex uses a v4-UUID hex charset. The project-ref constant (`ifsccnjhymdmidffkzhl`) is 20 lowercase alphanumeric chars (Supabase convention). Both are mechanical coincidences — call this out to avoid a reviewer conflating them.
- The cleanup guard's `new URL(url).hostname` throws synchronously on malformed URLs — the deepened plan moves URL parsing into a try/catch so an empty or malformed URL fails via the `project ref ''` branch rather than an unlabeled `TypeError`.

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

**Sketch (closer to final form — strict-mode safe):**

```bash
# Extract the seccomp entry from HostConfig.SecurityOpt.
# Each --security-opt X=Y becomes a separate array element, so iterate
# with {{println .}} rather than flatten to a JSON string (the old
# literal-contains approach).
#
# `|| true` on the docker pipeline — under set -euo pipefail, a docker
# exit code would abort the script. We want to report a clear FAIL
# message instead. The sed head -n1 pipeline is shell-builtins so it
# won't itself fail on empty input.
SECURITY_OPT_ENTRIES=$(
  docker inspect "$CONTAINER" \
    --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' 2>/dev/null \
    || true
)
SECCOMP_ENTRY=$(printf '%s\n' "$SECURITY_OPT_ENTRIES" | sed -n 's/^seccomp=//p' | head -n1)

if [[ -z "$SECCOMP_ENTRY" ]]; then
  emit_fail "HostConfig.SecurityOpt has no seccomp= entry — custom profile not attached (got: $SECURITY_OPT_ENTRIES)"
elif [[ "$SECCOMP_ENTRY" == /* ]]; then
  # Docker resolves --security-opt seccomp=<path> to inlined JSON at create
  # time. A literal path surviving into HostConfig means the flag wasn't
  # resolved — either an old docker version or the path didn't exist at
  # create time.
  emit_fail "seccomp entry is a literal path, not inlined JSON — Docker did not resolve --security-opt (got: $SECCOMP_ENTRY)"
elif [[ ! -r "$EXPECTED_SECCOMP_PATH" ]]; then
  emit_fail "On-host seccomp profile missing at $EXPECTED_SECCOMP_PATH — deploy state incoherent"
else
  # jq -cS = --compact-output --sort-keys. Canonicalizes whitespace +
  # key ordering so byte-equal JSON content always hashes identically.
  FILE_HASH=$(jq -cS . "$EXPECTED_SECCOMP_PATH" 2>/dev/null | sha256sum | cut -d' ' -f1)
  # Inlined side: wrap jq so a parse failure (inlined entry is non-JSON)
  # lands in the mismatch branch cleanly, not as a pipeline abort.
  INLINED_HASH=$(printf '%s' "$SECCOMP_ENTRY" | jq -cS . 2>/dev/null | sha256sum | cut -d' ' -f1 || true)

  if [[ -z "$FILE_HASH" ]]; then
    # jq failed on the on-host file. That's a deploy corruption, not a drift.
    emit_fail "On-host seccomp profile at $EXPECTED_SECCOMP_PATH is not valid JSON"
  elif [[ "$INLINED_HASH" != "$FILE_HASH" ]]; then
    emit_fail "seccomp drift: inlined profile sha256=${INLINED_HASH:0:12} != on-host sha256=${FILE_HASH:0:12}"
  else
    emit_pass "HostConfig.SecurityOpt seccomp matches on-host profile (sha256=${FILE_HASH:0:12})"
  fi
fi
```

### Research Insights

**Docker `--security-opt seccomp=<path>` resolution (verified in this deepen pass):**

- `docker --help` format option is Go-template-based; `{{range}}` + `{{println .}}` over a `.HostConfig.SecurityOpt` string-array prints one entry per line. Matches existing usage in `ci-deploy.sh`.
- `SecurityOpt` is always an array; each `--security-opt X=Y` becomes its own element. The old check's `docker inspect … --format '{{json .HostConfig.SecurityOpt}}'` returns the *whole array* as a single JSON string, and `[[ "$json" != *"seccomp=<path>"* ]]` accidentally worked for apparmor because the apparmor name never gets re-encoded. For seccomp, Docker resolves the path to inlined JSON at `docker run` time, so the literal path isn't in the output. Confirmed semantics via issue-body evidence (jq-normalized SHA-256 match).

**`jq -cS` flag verification:** `jq --help` lists `-c, --compact-output` and `-S, --sort-keys` as standard flags (verified 2026-04-23). Both have been present since jq 1.4 (2014). No version-pin needed.

**Strict-mode edge cases:**

- `set -euo pipefail` + a failing docker step would abort the whole audit script. Wrapping with `|| true` on `SECURITY_OPT_ENTRIES=$(docker … || true)` ensures we land in the "no seccomp= entry" branch with a clear stderr message.
- `printf '%s' "$VAR" | jq …` preserves exact bytes (no trailing newline). Safer than `echo "$VAR"` which may add one.
- `cut -d' ' -f1` on `sha256sum` output is robust against GNU vs BSD variations (both print `<hash>  <filename>` — the two-space delimiter is preserved by `cut -d' ' -f1`).

**Anti-patterns avoided:**

- `[[ $entry == /etc/* ]]` would require hardcoding the expected path pattern. `[[ $entry == /* ]]` (any absolute path) is strictly stronger — any literal-path form is a failure, regardless of the exact path.
- Using `openssl dgst -sha256` instead of `sha256sum`: sha256sum is in coreutils (always present on Linux hosts); openssl output format varies. Stick with sha256sum.

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

**New guard (illustrative — final file is `mu1-cleanup-guard.mjs`, see below):**

```js
// Dev-Doppler exposes the URL under its Next.js-public name; use it directly.
const DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl"; // Soleur dev Supabase project ref — stable infra.

export function assertDevCleanupEnv(env = process.env) {
  if (env.DOPPLER_CONFIG !== "dev") {
    throw new Error(
      "Refusing to run cleanup: DOPPLER_CONFIG is not 'dev' (got: " +
      (env.DOPPLER_CONFIG || "<unset>") + ")"
    );
  }
  const url = env.NEXT_PUBLIC_SUPABASE_URL || "";
  let actualRef = "";
  try {
    actualRef = new URL(url).hostname.split(".")[0];
  } catch {
    // Malformed or empty URL — drop into the project-ref branch with the
    // empty actualRef so the error message is useful.
  }
  if (actualRef !== DEV_PROJECT_REF) {
    throw new Error(
      "Refusing to run cleanup: Supabase project ref '" + actualRef +
      "' != expected dev ref '" + DEV_PROJECT_REF + "' (url=" + url + ")"
    );
  }
}
```

### Research Insights

**Verified via `doppler run -p soleur -c dev -- node -e '...'` (2026-04-23):**

```text
$ doppler run -p soleur -c dev -- node -e 'console.log(process.env.DOPPLER_CONFIG, process.env.DOPPLER_PROJECT)'
dev soleur
```

`DOPPLER_CONFIG` and `DOPPLER_PROJECT` are injected by `doppler run` and are safe to assert on. They are not user-set in any currently-configured environment on this host (confirmed via `env | grep ^DOPPLER` → empty outside `doppler run`).

**Implementation choices:**

- **Argument-injectable `env`**: the exported function takes `env = process.env` as a default. This makes the Phase 4 test trivial — each case passes a plain object, no `vi.stubEnv`/child-process ceremony.
- **Try/catch around `new URL()`**: Node's `URL` constructor throws `TypeError` on malformed input. Without the catch, an unset `NEXT_PUBLIC_SUPABASE_URL` would surface as an unlabeled `TypeError: Invalid URL` instead of the guard's intended "project ref mismatch" message. The catch preserves the guard's error semantics.
- **No `DOPPLER_ENVIRONMENT` check**: Doppler sets `DOPPLER_CONFIG` (config slug), `DOPPLER_ENVIRONMENT` (environment slug), and `DOPPLER_PROJECT` (project slug). Asserting on `DOPPLER_CONFIG` alone is sufficient because configs are per-project and the config name `dev` unambiguously maps to the dev Supabase URL. Asserting more adds fragility.

**Anti-patterns avoided:**

- Checking `url.includes("ifsccnjhymdmidffkzhl")` — would match if the ref appears anywhere in the URL (e.g., in a path), not just as the hostname prefix. `new URL().hostname.split(".")[0]` is structural.
- Storing the project ref in Doppler — adds secret-rotation ceremony for an immutable value. The constant's grep-stability is its audit trail.

**Supabase JS client compatibility:** The sweep body uses `createClient(url, serviceRoleKey)` + `auth.admin.listUsers({ perPage: 200 })` + `auth.admin.deleteUser(id)`. All three are stable public API (`@supabase/supabase-js` v2, present in the repo since 2024). The existing runbook snippet uses the same shape; no API change needed.

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

**Stub `docker` binary — matches the existing `create_docker_mock` convention (see `ci-deploy.test.sh:107+`):**

```bash
#!/usr/bin/env bash
# test fixture: mock docker. Behavior selected at runtime via env vars.
mode="${MOCK_DOCKER_MODE:-default}"

case "$1" in
  inspect)
    # Expect: docker inspect <container> --format '<template>'
    # Return the fixture file's contents verbatim. Template is ignored in
    # the mock — tests write the desired .HostConfig.SecurityOpt line-
    # iterated form into the fixture directly.
    cat "${DOCKER_INSPECT_FIXTURE:-/dev/null}"
    ;;
  exec)
    # Expect: docker exec <container> bwrap <args>
    cat "${DOCKER_EXEC_FIXTURE:-/dev/null}"
    exit "${DOCKER_EXEC_EXIT:-0}"
    ;;
  *)
    echo "unexpected docker arg: $*" >&2
    exit 99
    ;;
esac
```

### Research Insights

**Test harness convention — verified against `ci-deploy.test.sh`, `disk-monitor.test.sh`, `orphan-reaper.test.sh`:**

Every existing infra test file uses the same skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/<script>.sh"

PASS=0
FAIL=0
TOTAL=0

# Hardened PATH — excludes ~/.local/bin so missing mocks fail loudly.
readonly TEST_PATH_BASE="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# One factory per mocked binary, installed into a mktemp MOCK_DIR.
create_docker_mock() { cat > "$1/docker" << 'MOCK' … MOCK; chmod +x "$1/docker"; }

test_name_describing_behavior() {
  TOTAL=$((TOTAL + 1))
  local description="..."
  local mock_dir; mock_dir=$(mktemp -d)
  create_docker_mock "$mock_dir"
  local output actual_exit
  output=$(
    export PATH="$mock_dir:$TEST_PATH_BASE"
    export MOCK_DOCKER_MODE=...
    export DOCKER_INSPECT_FIXTURE=...
    bash "$SCRIPT_UNDER_TEST" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "expected string"; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (exit=$actual_exit)"; echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

# … all test_* invocations …

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ "$FAIL" -eq 0 ]]  # exit non-zero on any FAIL
```

**Phase 4 MUST follow this exact skeleton** — the `PASS/FAIL/TOTAL` counters, the subshell `output=$(…) && actual_exit=0 || actual_exit=$?` pattern, the `mktemp -d` per-case MOCK_DIR, the `TEST_PATH_BASE` constant excluding `~/.local/bin`. Diverging introduces drift across the infra test surface.

**Fixture files:** store per-case `docker inspect` outputs as small flat files in `apps/web-platform/infra/test-fixtures/audit-bwrap/*.txt`. Each fixture is the literal text that `docker inspect --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}'` would emit — e.g.:

```text
apparmor=soleur-bwrap
seccomp={"defaultAction":"SCMP_ACT_ERRNO",...}
```

The fixture-for-PASS-case must be byte-identical (after jq canonicalization) to a fixture seccomp JSON file also committed in `test-fixtures/audit-bwrap/`. Tests set `EXPECTED_SECCOMP_PATH` to point at that file.

**Node-side guard test:**

The `mu1-cleanup-guard.test.sh` file uses `bash` as the outer harness (matching the rest of the suite) but invokes `node --input-type=module` for the assertion:

```bash
test_config_is_prd_throws() {
  TOTAL=$((TOTAL + 1))
  local description="DOPPLER_CONFIG=prd throws"
  local output actual_exit
  output=$(
    node --input-type=module -e "
      import { assertDevCleanupEnv } from '$SCRIPT_DIR/mu1-cleanup-guard.mjs';
      try {
        assertDevCleanupEnv({ DOPPLER_CONFIG: 'prd', NEXT_PUBLIC_SUPABASE_URL: 'https://ifsccnjhymdmidffkzhl.supabase.co' });
        console.log('no-throw');
      } catch (e) { console.log('threw: ' + e.message); }
    " 2>&1
  ) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "DOPPLER_CONFIG is not 'dev'"; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (exit=$actual_exit, output=$output)"
  fi
}
```

**Why `--input-type=module` via `-e`?** Lets the test pass an injected `env` object directly — no real Doppler invocation, no real env mutation, no race against other tests running under `doppler run`. This makes the 4 cases deterministic and single-process.

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
- `apps/web-platform/infra/mu1-cleanup-guard.mjs` — Phase 4 (vendored guard helper, ESM node module exporting `assertDevCleanupEnv(env = process.env)` + `sweep()`).
- `apps/web-platform/infra/mu1-runbook-cleanup.test.sh` — Phase 4 (guard tests, bash harness + `node --input-type=module -e`).
- `apps/web-platform/infra/test-fixtures/audit-bwrap/valid-seccomp.json` — minimal canonical JSON (~3 lines) used as the on-host stand-in during tests.
- `apps/web-platform/infra/test-fixtures/audit-bwrap/inspect-pass.txt` — `docker inspect` output with valid inlined seccomp (hash matches valid-seccomp.json).
- `apps/web-platform/infra/test-fixtures/audit-bwrap/inspect-drift.txt` — same shape, inlined JSON whitespace-diverges from valid-seccomp.json (proves jq-normalization is load-bearing).
- `apps/web-platform/infra/test-fixtures/audit-bwrap/inspect-no-seccomp.txt` — only `apparmor=` entry, no `seccomp=`.
- `apps/web-platform/infra/test-fixtures/audit-bwrap/inspect-literal-path.txt` — `seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json` (un-resolved).
- `apps/web-platform/infra/test-fixtures/audit-bwrap/inspect-no-apparmor.txt` — only `seccomp=…` entry, no `apparmor=`.

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
- **Risk: bash strict-mode (`set -euo pipefail`) aborts the audit script on an unexpected pipe failure.** Mitigation: audited in the deepened Phase 1 sketch — the docker pipeline is wrapped with `|| true` and every `jq` invocation has `2>/dev/null` + explicit empty-hash fallthrough to emit FAIL rather than abort the script. No `[[ $n -gt $x ]]` numeric comparisons on user-controlled input (per `plan` sharp-edge on strict-mode operator crashes).
- **Risk: the test fixture seccomp JSON drifts from the real `apps/web-platform/infra/seccomp-bwrap.json` source-of-truth.** Mitigation: commit a `test-fixtures/audit-bwrap/valid-seccomp.json` that is a minimal 3-line JSON (not the full 14KB profile), and in the test set `EXPECTED_SECCOMP_PATH` to this fixture. We are testing the hash-compare mechanism, not the profile's contents — a minimal fixture is sufficient and immune to real-profile edits.

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
