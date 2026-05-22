# Learning: Vector VRL config gates + PII redaction pipeline for SaaS log sinks

**Date:** 2026-05-22
**PR:** #4293
**Issue:** #4273
**Categories:** build-errors, integration-issues, security-issues
**Tags:** vector, vrl, observability, better-stack, gdpr, ci-gates, pii-redaction, adr-029

## Problem

Vector 0.43.1 was already shipping journald + host_metrics to Better Stack Logs (PR #4279, merged 2026-05-21) **without any PII redaction**. The DPD §2.3(m) literally claimed "Better Stack is therefore NOT a sub-processor of personal data under GDPR Article 28 and no SCC/DPA is required" — true when only opaque heartbeats flowed, falsified the moment journald content (carrying pseudonymous `userIdHash`, conversation IDs, error stack traces) crossed the boundary. P0 single-user-incident GDPR gap.

The remediation surfaced six distinct sub-classes of error worth compounding:

1. VRL type-checker behaves differently between **chained-as-one-program** test invocations and **standalone-per-transform** production runs.
2. Vector's TOML loader **preprocesses `${...}` as env-var substitution**, conflicting with VRL regex capture-group references.
3. **PR-time CI gates** must live in workflows whose `on:` includes `pull_request` — gates buried in apply-only workflows never fire at PR time.
4. Better Stack source tokens are **cluster-bound**; cluster region can be verified via authenticated POST probe (cheaper than Playwright dashboard login).
5. Reusing the existing `SENTRY_USERID_PEPPER` across VRL via `get_env_var()` is **byte-equivalent** to TS `crypto.createHmac("sha256", pepper).update(userId).digest("hex")` — single-source-of-truth per ADR-029 §I4.
6. Public legal disclosure prose must **hedge unsigned-DPA status** ("available for execution, tracked in <internal-file>") rather than imply in-force.

## Solution

### 1. VRL chained-vs-standalone type-checker divergence

When testing transforms via `vector vrl --print-object --program "<combined-source>"` with all three transform sources concatenated, the type checker proves field types from upstream writes (e.g., `.pii_scrub_applied = ""` in transform 1 means transform 2 sees `.pii_scrub_applied` as known-string). This rejects `string!(.pii_scrub_applied)` with E620 "this function can't fail" AND rejects `string(.pii_scrub_applied) ?? ""` with E651 "this expression never resolves".

In production, Vector compiles each `[transforms.X]` block as a **standalone VRL program** — upstream typing is `any`, so `string!()` IS the correct coercion.

**Fix:** the test harness must run transforms **sequentially via shell pipeline**, not chained as one program:

```bash
apply_pipeline() {
  local input="$1"
  local tmp1 tmp2
  tmp1=$(mktemp); tmp2=$(mktemp)
  printf '%s\n' "$input" >"$tmp1"
  "$VECTOR_BIN" vrl --input "$tmp1" --print-object "$VRL_DROP" >"$tmp2"
  "$VECTOR_BIN" vrl --input "$tmp2" --print-object "$VRL_STRUCT" >"$tmp1"
  "$VECTOR_BIN" vrl --input "$tmp1" --print-object "$VRL_STRING" >"$tmp2"
  cat "$tmp2"
  rm -f "$tmp1" "$tmp2"
}
```

This matches production wiring exactly. Same `string!()` source compiles in both contexts.

### 2. Vector TOML preprocessor `${...}` vs VRL regex capture-groups

VRL's `replace(msg, pattern, "$1Bearer [redacted]")` expects `${1}` for capture-group reference. But Vector's TOML loader runs **env-var preprocessing** over the entire file before VRL parses, expanding `${1}` as `getenv("1")`. The result:

```
× Failed to load config
× Missing environment variable in config. name = "1"
```

**Fix:** double-dollar to escape Vector's preprocessor: `$${1}Bearer [redacted]`. Vector's preprocessor unwraps `$$` → `$`, then VRL sees `${1}Bearer`. The test harness must mirror this unwrap so the same VRL bytes run in both contexts:

```bash
unescape_vector_toml() {
  python3 -c 'import sys; sys.stdout.write(sys.stdin.read().replace("$$", "$"))'
}
VRL_DROP=$(extract_vrl pii_scrub_drop_userdata | unescape_vector_toml)
```

### 3. PR-time CI gates can't live in apply-only workflows

Initial implementation placed `validate-vector-config` as a job inside `apply-web-platform-infra.yml`. That workflow's `on:` is `push: branches: [main]` only (intentional — terraform-apply must NEVER fire on PR branches). The gate never ran at PR time; `gh pr checks` showed all-green with the gate silently absent.

**Fix:** split validation into its own workflow with both PR + push triggers:

```yaml
# .github/workflows/validate-vector-config.yml
on:
  push:
    branches: [main]
    paths: ["apps/web-platform/infra/vector.toml", ...]
  pull_request:
    paths: ["apps/web-platform/infra/vector.toml", ...]
```

Branch protection requires the new check. Apply workflow's `needs: [preflight, validate-vector-config]` would have been a cross-workflow needs (unsupported in GHA); branch protection is the enforcement.

**Generalization:** when a validation gate must fire at PR time, check the host workflow's trigger list FIRST. If it lacks `pull_request`, extract to a new workflow. Don't try to add `pull_request` to an apply workflow.

### 4. Better Stack cluster verification via authenticated POST probe

Plan §0.4 prescribed Playwright dashboard login to read the source's region (Better Stack source tokens are cluster-bound; sending a token to the wrong cluster returns 401). Cheaper alternative:

```bash
BETTERSTACK_LOGS_TOKEN=$(doppler secrets get BETTERSTACK_LOGS_TOKEN -p soleur -c prd --plain)
for cluster in eu-nbg-2 eu-fsn-3 us-east-1; do
  printf "%s: " "$cluster"
  curl -s -o /dev/null -w "HTTP %{http_code}\n" -m 10 \
    -X POST "https://s${SOURCE_ID}.${cluster}.betterstackdata.com/" \
    -H "Authorization: Bearer $BETTERSTACK_LOGS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '[{"_probe":"region-verify"}]'
done
```

The cluster that returns 202 owns the token. Others return 401. Operator runs locally with Doppler-injected token; no SSH, no dashboard login. Probe payload `{"_probe":"region-verify"}` is tagged for filter-out post-verification.

### 5. ADR-029 §I4 single-pepper VRL reuse — bit-for-bit TS parity

`SENTRY_USERID_PEPPER` (Doppler-held) already feeds the TS `hashUserId` boundary. Reusing it via VRL `get_env_var("SENTRY_USERID_PEPPER")` + `encode_base16(hmac(value, pepper, algorithm: "SHA-256"))` is byte-equivalent to `crypto.createHmac("sha256", pepper).update(userId).digest("hex")` for string `userId` values.

**Asserted in CI** by a three-way parity check (bun → openssl → VRL):

```bash
EXPECTED_HASH=$(printf 'test-user-id' | openssl dgst -sha256 -hmac "$PEPPER" -hex | awk '{print $2}')
TS_HASH=$(bun -e 'import {hashUserId} from "./server/observability"; console.log(hashUserId("test-user-id"))')
[[ "$EXPECTED_HASH" == "$TS_HASH" ]] || exit 1
# Then assert VRL output equals EXPECTED_HASH via vector vrl fixture
```

**Caveat documented in the comment:** parity holds for string `userId`. TS uses `String(rawValue)` for non-string types (arrays, objects); VRL falls back to `""` via `to_string ?? ""`. The pino schema does not emit non-string userId — theoretical divergence with no production occurrence.

### 6. Legal disclosure DPA-prose hedge pattern

When a vendor DPA is unsigned but the processor relationship is in force operationally, public legal disclosure must hedge:

```diff
- DPA: [Vendor DPA](url) (standard EU-region terms; SCCs incorporated).
+ DPA: [Vendor DPA](url) is **available for execution** under standard
+      EU-region terms (SCCs incorporated). The Vendor DPA Status table in
+      `knowledge-base/legal/compliance-posture.md` tracks the signing state;
+      signing is an open operator action under AC15 of PR #4293.
```

Internal status tracker (`compliance-posture.md` Vendor DPA Status table) carries the authoritative `PENDING` status with escalation clause; public disclosure points at it. Prevents an Art. 13(1)(e) "misleading disclosure" exposure while the operator completes the signing flow.

## Key Insight

Five orthogonal gotchas converged on this PR because **observability config (TOML+VRL+regex)** sits at the intersection of three independently-typed worlds: TOML preprocessor (env-var substitution), VRL (typed expression language), and regex (capture-group references using `$`). Each layer treats `${1}` differently. The general pattern: **whenever a config language wraps a typed sub-language, audit the dollar-prefix / brace-syntax / escape-conventions across the layer boundary** before assuming a string round-trips.

Same shape for the chained-vs-standalone gotcha: the **test harness must mirror the production execution topology**, not "simplify by combining". For Vector specifically, this means running `vector vrl` per-transform in sequence, not one `vector vrl` with all transforms concatenated.

For CI gates: **trigger placement is part of the gate's definition**. A gate that should block PRs must live in a workflow that fires on PRs. Hosting it in an apply-only workflow is a silent gate.

## Session Errors

**1. VRL `string!()` E620 + `string()??""` E651 "can't fail" on chained transforms** — Recovery: rewrote test harness to run transforms sequentially via shell pipeline instead of one combined VRL program — Prevention: when adding `vector vrl` fixture tests for multi-transform pipelines, default to sequential per-transform invocation; document the chained-vs-standalone typing divergence in the fixture script header.

**2. VRL `hmac(...)` E104 unnecessary error assignment** — Recovery: removed the error tuple destructuring (`hashed, hmac_err = hmac(...)`); hmac is infallible on string inputs — Prevention: VRL fallible-call audit pattern: for each function call in a new transform, check its return shape in `vector vrl --help` or docs before adding `, err =`.

**3. VRL `$1Bearer` capture-group parsed as variable name** — Recovery: switched to `${1}Bearer` brace form — Prevention: always use the `${N}` brace form for VRL regex capture references; the bare `$N` form only works when the next character is non-alphanumeric.

**4. Vector TOML preprocessor expanded `${1}` as env var named `1`** — Recovery: double-dollar escape `$${1}` + test harness unescape via `python3 -c 'sys.stdout.write(...replace("$$", "$"))'` — Prevention: document TOML-preprocessor escape conventions in the `vector.toml` header comment whenever VRL regex with capture-groups appears.

**5. CI gate in apply-only workflow never fired on PR** — Recovery: split `validate-vector-config` into standalone workflow with `pull_request:` trigger — Prevention: when adding a CI gate that must run at PR time, check the host workflow's `on:` trigger list before placement; apply/deploy workflows are PR-blind by design.

**6. Bun missing in CI runner → fixture step exit 127** — Recovery: added `oven-sh/setup-bun` action + `bun install --frozen-lockfile` in `apps/web-platform` — Prevention: when a fixture script invokes `bun -e` with imports requiring path aliases (`@/server/*`), the CI workflow must include both bun setup AND `bun install` in the package directory; document this in the fixture script header.

**7. Raw U+2028/U+2029 bytes in regex char class** — Recovery: replaced with `\u{2028}\u{2029}` escape form (hard-rule `cq-regex-unicode-separators-escape-only`) — Prevention: hard rule already exists; reinforce by adding a PreToolUse hook that greps Write/Edit content for the literal bytes and rejects in any TOML/YAML/JSON config destination (current hook may only cover source-code files).

**8. OAuth query-param leak on carved-out callback path** — Recovery: added a 5th regex to `pii_scrub_string` redacting `code=`, `state=`, `access_token=`, `id_token=`, `refresh_token=` values; preserved the path discriminator — Prevention: when a PII scrubber has a path carve-out for operator-debugging discriminators, audit each redacted-vs-preserved pair for orthogonal token classes (path-vs-query-param, header-vs-body, etc.).

**9. Public legal prose asserted DPA in force; internal tracker said PENDING** — Recovery: hedged Privacy Policy §5.14 + DPD §2.3(m)(ii) to "available for execution ... tracked in compliance-posture.md ... open operator action under AC15" across source + plugin mirror (4 files) — Prevention: when adding a Vendor disclosure where the DPA is not yet signed, the public-facing prose template MUST point at the internal status tracker instead of asserting in-force; add a pre-commit grep check for `(DPA|SCC).*(incorporated|in force|signed)` across `docs/legal/` and require a corresponding non-PENDING row in `compliance-posture.md` before allowing the assertion.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` §I4 (single-pepper reuse; VRL added as 4th consumer)
- `knowledge-base/project/specs/feat-observability-consolidation-4273/spec.md` `## Plan-Time Corrections` C1-C9
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh` (the canonical sequential-pipeline fixture harness)
- `.github/workflows/validate-vector-config.yml` (the canonical "standalone PR-triggered validation gate" pattern)
- Vector PR vectordotdev/vector#19274 (closed unmerged 2025-01-27) — proof native `better_stack_logs` sink does NOT exist
- Better Stack Vector integration docs: `https://betterstack.com/docs/logs/vector/`
- Prior learning: `2026-04-17-pii-regex-scrubber-three-invariants.md`
- Prior learning: `2026-04-17-log-injection-unicode-line-separators.md`
- Prior learning: `2026-05-16-procedural-deadline-disclosure-is-the-critical-path-not-remediation.md`
- Prior learning: `2026-03-18-dpd-processor-table-dual-file-sync.md`
