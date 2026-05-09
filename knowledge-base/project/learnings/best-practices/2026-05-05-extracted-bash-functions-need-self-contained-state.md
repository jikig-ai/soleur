---
date: 2026-05-05
category: best-practices
problem_type: contract_test_extractability
component: github_actions_workflow + vitest_contract_test
related_issues: [3187, 3224, 3236]
related_prs: [3224, 3181]
tags: [github-actions, vitest, contract-test, bash, extractFunctionBody, workflow-injection-defense, dedup-search, scope-out-protocol]
synced_to: []
---

# Three Review-Cycle Patterns From PR #3224 — Extracted-Function Self-Containment, Phrase-Tight Dedup, Co-Sign Order

## Why this learning exists

PR #3224 (GitHub App drift-guard) went through an 11-agent review cycle
that produced 27 findings. Most were straightforward fix-inline edits
that map cleanly onto existing learnings. Three of them surfaced
patterns that were NOT obvious from the existing canon and broke
something during the fix-apply phase. This learning documents those
three so the next workflow + contract-test author catches them at
write-time, not at "the test you wrote five minutes ago is now red."

The three patterns are independent — they could each have their own
learning file, but they all surfaced in the same review cycle and
share a structural shape ("the contract was correct in isolation but
broke when one side changed without the other"). A single learning
captures the meta-pattern.

## Pattern 1 — `extractFunctionBody`-extracted bash functions cannot reference script-level constants

### Symptom

A Vitest contract test extracts a bash function from a workflow YAML
via `extractFunctionBody(yaml, "mint_jwt")` and runs it via
`spawnSync('bash', ['-c', script])`. The function depends on a script-
level constant (e.g., `readonly JWT_BACKDATE_S=60`) defined OUTSIDE
the function. The test fails with an off-by-N arithmetic mismatch —
typically `expected X to be greater than X` because the expected
delta evaluated to zero.

### Root cause

`extractFunctionBody` is a regex helper that captures only the body
between `<name>() {` and the matching `}` at the same indent. It does
NOT capture the surrounding script's `readonly` / `local` / `export`
declarations. When the test re-spawns the function in isolation,
those constants are undefined.

Bash without `set -u` treats undefined vars as empty strings.
`$((now - JWT_BACKDATE_S))` then evaluates as `$((now - ))` →
`$((now))` (empty arithmetic = 0). The function returns valid-looking
output but with the wrong values, and the test's range assertions
catch it (or worse, equality assertions hide it because both sides
evaluate the same wrong way).

### Fix

Make every constant the function depends on a function-local. For
bash:

```bash
mint_jwt() {
  set -o pipefail
  # Constants are local so the contract test can extract and re-run
  # this function in isolation without depending on script-level state.
  local backdate_s=60
  local lifetime_s=540
  local now header payload unsigned signature
  now=$(date +%s)
  payload=$(jq -nc \
    --argjson iat "$((now - backdate_s))" \
    --argjson exp "$((now + lifetime_s))" \
    ...)
  ...
}
```

### How to verify at write-time

After defining a workflow function the contract test will extract:

```bash
# Pull the function body and re-run it in isolation:
yq '.jobs.<job>.steps[<n>].run' <workflow>.yml | \
  awk '/^[[:space:]]*<name>\(\) \{/,/^[[:space:]]*\}/' | \
  bash -c "$(cat); <name>"
```

If the function references any variable that doesn't appear in the
extracted body, the run will produce wrong output. Catching this
locally beats catching it in CI.

### Generalization

Any test that extracts and re-runs a slice of production code in
isolation is implicitly asserting "this slice is self-contained." If
the slice depends on caller-side state (env vars, script constants,
imported modules), the assertion is false and the test fails — but
the failure mode looks like a logic bug in the slice, not a
boundary-violation in the test harness. **Generalization:** when
designing the harness, decide whether the slice is "pure function
under test" (assert self-contained) or "fragment exercising
caller state" (use a wider extraction or mock the caller). Don't
mix.

This applies equally to:
- Bash function extraction (this case)
- Python function-under-test extracted via AST visitor
- TypeScript function transpiled and re-executed via `vm.Script`
- SQL function bodies extracted via `pg_get_functiondef` and run
  outside their parent migration

## Pattern 2 — Phrase-tight dedup-search vs token-tight dedup-search

### Symptom

A scheduled CI workflow files tracking issues with title prefix
`[ci/auth-broken] GitHub App drift-guard fired`. Dedup search uses
`gh issue list --label ci/auth-broken --search 'in:title "drift-guard"'`.
Today this is fine because no other workflow files issues with
`drift-guard` in the title. A future PR adds a `terraform-drift-guard`
or `cf-drift-guard` workflow with the same `ci/auth-broken` label —
auto-close-on-green of one workflow now eats tracking issues filed
by the other.

### Root cause

GitHub's `in:title` search is substring-y in the way operators expect
in 2026 (it's actually anchored-token-y under the hood, but the
practical effect for natural-language prefixes is substring-match).
A bare token like `drift-guard` matches any title containing those
characters. Tightening to a full phrase like `"GitHub App drift-guard"`
is an O(0)-cost defense against a future cross-workflow collision
that `cancel-in-progress: false` does NOT prevent (concurrency is
within-workflow only).

### Fix

Use the longest workflow-unique phrase as the dedup key:

```bash
# Bad (collides with future workflows that also use ci/auth-broken):
gh issue list --label ci/auth-broken --search 'in:title "drift-guard"'

# Good (phrase is unique to THIS workflow's title prefix):
gh issue list --label ci/auth-broken --search 'in:title "GitHub App drift-guard"'
```

The contract test's dedup-search assertion must track the phrase
change. Regex like `/in:title\s+["']*drift-guard/` is too rigid for
the new phrase — it expects `drift-guard` immediately after the
quote, but the new phrase has `GitHub App ` between them. Update
the test regex when you tighten the dedup search.

### How to verify at write-time

Before merging a new scheduled workflow that files tracking issues,
list every other workflow's title prefix and confirm yours is unique:

```bash
grep -rh 'ISSUE_TITLE=' .github/workflows/scheduled-*.yml | sort -u
```

If two prefixes share a token, expand both to their longest unique
phrase before either is merged.

### Generalization

Dedup search keys are an implicit contract between siblings. The
contract is "every workflow's dedup key is unique." Bare tokens
satisfy the contract today (when there's only one workflow); full
phrases satisfy it for any future expansion. Cost difference: zero.
Default to the phrase form whenever you can — bare tokens are a
liability the moment someone adds a sibling.

## Pattern 3 — Co-sign FIRST, file scope-out SECOND

### Symptom

The review skill's second-reviewer gate explicitly says "Before
creating a scope-out issue under any criterion, invoke
code-simplicity-reviewer via Task." I filed issue #3236 with the
`deferred-scope-out` label and full body, THEN invoked
code-simplicity-reviewer. The agent returned `CONCUR` so the filing
stood — but the protocol order was violated.

The CONCUR was lucky. The agent's prompt explicitly says "Default to
rejecting the scope-out filing" — a DISSENT would have required
closing the just-filed issue (visible to operators in the issue
stream), reopening the inline-fix path, and explaining the noise.

### Root cause

The temptation is to file first because:
1. Filing is mechanical (gh issue create with --body-file).
2. Co-signing is a multi-step Task invocation that takes ~30s.
3. After co-sign returns CONCUR, you'd have to re-paste the issue
   body anyway.

This optimization treats the filing as the "real" work and the
co-sign as a rubber stamp. The protocol exists precisely because
single-agent rationalization of a scope-out is a recurring failure
mode (per the review skill's own learning at
`2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`).

### Fix

Always invoke `code-simplicity-reviewer` as a Task BEFORE running
`gh issue create --label deferred-scope-out`. The agent's CONCUR or
DISSENT first line is the gate; only run `gh issue create` after
seeing CONCUR.

If DISSENT, the disposition flips to fix-inline; close the loop with
the in-PR fix the agent recommended, no issue is filed.

### How to verify at write-time

Self-check before any `gh issue create --label deferred-scope-out`:

1. Has the conversation contained a Task invocation of
   `code-simplicity-reviewer` (or `pr-review-toolkit:code-simplifier`)
   in the last ~10 turns whose subject matches this finding?
2. Does that invocation's reply begin with `CONCUR`?

If either answer is no, do not run `gh issue create` yet. Invoke the
agent first.

### Generalization

Any "second-reviewer required" gate is structurally identical: the
gate exists because the path of least resistance bypasses it. Filing
issue → invoking agent feels equally valid as invoking agent → filing
issue when both end with the same artifacts. The order matters only
when the agent dissents, but THAT is the case the gate is for. Always
do the gated-input action first; the gated-output action second.

## Where to apply this

- **Pattern 1:** authoring any contract test that uses
  `extractFunctionBody`, AST visitors, or `vm.Script` to slice
  production code. The `oauth-probe-contract.test.ts` and
  `github-app-drift-guard-contract.test.ts` are the existing
  precedents.
- **Pattern 2:** authoring any new `scheduled-*.yml` workflow that
  files tracking issues with a label shared by sibling workflows.
- **Pattern 3:** any `gh issue create --label deferred-scope-out`
  invocation, anywhere.

## Cross-references

- `2026-05-05-workflow-jwt-mint-silent-failure-traps.md` — sibling
  learning from PR #3224 plan-review (gh api/Bearer, base64 -A
  newline, failure() under continue-on-error).
- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — the
  source of the second-reviewer gate.
- `2026-05-04-cross-check-stylistic-review-recommendations-against-drift-guards.md` —
  related: review-recommendation cross-checking against existing
  guards.
- AGENTS.md `rf-review-finding-default-fix-inline` — fix-inline
  default that scope-outs deviate from.
- Review skill `plugins/soleur/skills/review/SKILL.md` §5 —
  scope-out criteria + second-reviewer gate.

## Session Errors

Errors enumerated during this compound's Phase 0.5:

1. **Vitest invocation from wrong cwd** — `cd apps/web-platform && npx vitest` from inside `apps/web-platform/` failed with "No such file or directory". Recovery: remove the redundant `cd`. **Prevention:** check `pwd` before `cd`-prefixed commands.
2. **JWT contract test failure: extracted bash function couldn't reference script-level constants** — see Pattern 1. Recovery: move constants inside `mint_jwt` as `local`. **Prevention:** Pattern 1 codifies this into a write-time check.
3. **Contract test dedup-search regex break after tightening workflow** — see Pattern 2. Recovery: update test regex. **Prevention:** Pattern 2 makes "update test when tightening dedup" explicit.
4. **Initial GREEN-phase JWT test bug: `createPublicKey(publicKey)` rejected the KeyObject** — `createPublicKey()` expects a private KeyObject (extracts public half), not a public KeyObject. Recovery: pass `publicKey` directly to `cryptoVerify`. **Prevention:** Node `crypto` API contract — `createPublicKey()` is "I have a private key, give me the public" not "wrap this public key." For an existing public KeyObject, use it directly.
5. **Initial RED-phase regex bug: `BEGIN [A-Z ]+PRIVATE KEY` missed PKCS#8** — `+` requires ≥1 char between `BEGIN ` and `PRIVATE`; PKCS#8 has zero. Recovery: `+` → `*`. **Prevention:** when designing a class-of-strings regex, always exercise positive controls for EVERY known variant in the class (RSA, PKCS#8, EC, OPENSSH, ENCRYPTED, DSA) at write-time, not at review-time.
6. **Security-reminder hook blocked first workflow Write of session** — advisory hook fires once per session via `sys.exit(2)` and saves state. Retry succeeded; not a true error. **Prevention:** none needed — hook is working as designed.
7. **Filed scope-out issue #3236 BEFORE invoking code-simplicity-reviewer co-sign** — see Pattern 3. Recovery: invoked agent retroactively; got lucky CONCUR. **Prevention:** Pattern 3 codifies the order. Could also strengthen the review skill's text to use an unambiguous "MUST" with a write-time self-check; proposed in Phase 1.5.
