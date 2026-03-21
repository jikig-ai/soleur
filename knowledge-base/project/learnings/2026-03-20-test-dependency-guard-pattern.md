# Learning: Conditional test skipping for missing shell dependencies

## Problem

Tests that invoke bash scripts via Bun.spawnSync fail with exit 127 when the script's dependencies (jq) are missing. This blocks git push for ALL branches via the pre-push hook, even for developers who don't work on the affected feature.

## Solution

1. Probe dependency at module scope: `const HAS_JQ = Bun.spawnSync(["jq", "--version"]).exitCode === 0`
2. Create a named alias: `const describeIfJq = HAS_JQ ? describe : describe.skip`
3. Wrap ALL dependent describe blocks (including indirect ones that call scripts which internally require jq)
4. Add CI fail-fast: `if (!HAS_JQ && process.env.CI) throw new Error(...)`
5. For bash tests, add `command -v jq || exit 0` guard at script top

## Key Insight

When a bash script calls `require_jq` in main() before dispatching, ALL tests that invoke the script need the guard — not just direct jq callers. The dependency is transitive through main(). Review agents caught that ralph-loop.test.sh had the same jq dependency but no guard, which would have reintroduced the same class of failure.

## Related Learnings

- `2026-03-10-require-jq-startup-check-consistency.md` -- ensuring jq is available in scripts (script-side); this learning covers the test-side complement
- `2026-03-18-bun-test-segfault-missing-deps.md` -- same symptom class (test infrastructure failures from missing dependencies), different root cause (node_modules vs shell tools)
- `2026-03-18-stop-hook-jq-invalid-json-guard.md` -- jq failure modes under set -euo pipefail (runtime guard, not test guard)

## Tags

category: test-failures
module: test-infrastructure
