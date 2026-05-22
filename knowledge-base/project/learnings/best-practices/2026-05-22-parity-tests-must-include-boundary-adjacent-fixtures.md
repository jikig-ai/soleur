---
date: 2026-05-22
category: best-practices
tags: [parity-test, regex, cross-language, test-design, review]
related_prs: [4323, 4320]
related_files:
  - apps/web-platform/lib/supabase/resolve-ref.ts
  - apps/web-platform/scripts/lib/supabase-ref-resolver.sh
  - apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts
---

# Parity tests across languages MUST include boundary-adjacent fixtures

## Problem

PR #4323 ported a bash regex resolver into a TS sibling and locked the
"identical behavior" contract with a 6-fixture parity test. The bash form's
fast-path regex was `[a-z0-9]+` (one-or-more, pre-existing from PR #4320);
the new TS form used `[a-z0-9]{20}` (length-anchored). The TS choice matched
both implementations' header comments documenting the canonical
subdomain-bypass guard `^[a-z0-9]{20}\.supabase\.co$`, so the author wrote
the parity fixtures around 20-char canonical refs.

Every parity fixture passed. Five of ten review agents independently flagged
the drift:

- bash `https://abc.supabase.co` → returns `"abc"` (rc=0)
- TS `https://abc.supabase.co` → returns `null`

The parity test passed because **no fixture exercised a sub-20-char or
21-char host**. The contract the test was supposed to lock in was silently
violated on its first commit.

## Root cause

A parity test whose fixtures stay strictly inside the "happy zone" gives
false confidence on the very boundary the implementations are supposed to
agree on. The 6 fixtures (canonical, trailing-slash, custom-domain via
CNAME, subdomain-bypass attempt, uppercase, empty) covered:

- Branch coverage (fast path / CNAME fallback / early-return on empty)
- Security guard (subdomain-bypass)
- Case-sensitivity guard (uppercase)

But none covered the length anchor. The regex header comment claimed
`{20}` was the guard; the bash code used `+`. The test would have caught
the drift if it had used a single 19-char fixture.

## Solution

Add boundary-adjacent fixtures for every quantifier the regex declares:

```typescript
// Length-anchor fixtures — both sides MUST require exactly 20 chars on
// the fast path. Without these, a bash regex of `[a-z0-9]+` would
// silently accept off-spec hosts the TS form rejects.
{ name: "sub-20-char host rejected", url: "https://abc.supabase.co", expected: null, ... },
{ name: "21-char host rejected", url: "https://abcdefghijklmnopqrstu.supabase.co", expected: null, ... },
```

And tighten the bash regex to match the documented contract:

```bash
# Before:
sed -nE 's#^https?://([a-z0-9]+)\.supabase\.co/?$#\1#p'
# After:
sed -nE 's#^https?://([a-z0-9]{20})\.supabase\.co/?$#\1#p'
```

## Key insight (generalizable)

**When authoring cross-language parity tests, derive fixtures from the
regex's own quantifiers and character classes — not from the
implementation author's intuition about "interesting cases."**

For each regex element, write at least one fixture that:

| Element | Boundary fixtures required |
|---|---|
| `{N}` exact-length | N-1 chars, N chars, N+1 chars |
| `{N,M}` range | N-1, N, M, M+1 |
| `[a-z]` character class | one char outside the class (`A`, `0`, `-`) |
| `^` / `$` anchors | leading/trailing whitespace, embedded newline |
| `+` / `*` quantifier | empty input (for `*`), single char (for both) |
| Alternation `(a|b)` | each branch, plus one non-matching alternative |

Apply this **before** writing the implementation, not after. Header
comments documenting "the regex is `^[a-z0-9]{20}...$`" are a hypothesis
about the implementation; the implementation is the contract. Compare
line-by-line; never trust the header.

## Detection cost vs. fix cost

- **Detection at code review:** 5 agents independently flagged it. Caught
  during the same /one-shot run.
- **Detection at runtime:** Latent. The subdomain-bypass guard would have
  held (it lives on the CNAME slow path with the correct `{20}` anchor),
  but a test-fixture leak with a short ref bypassed the bash CI gate that
  the workflow's upstream URL validator (line 411, also `{20}`-anchored)
  happens to compensate for. A future caller bypassing the upstream
  validator would have desynced silently.
- **Fix cost:** 2 fixtures + 1 regex character = 1 commit, ~10 lines.

## Why multi-agent review caught this

Five orthogonal lenses all reached the same finding by independent paths:

1. `pattern-recognition-specialist`: noticed convention drift across siblings.
2. `security-sentinel`: traced the subdomain-bypass guard's reachability
   and found the fast-path skipped it.
3. `data-integrity-guardian`: read both implementations and the parity
   test, computed the divergent outputs by hand.
4. `code-quality-analyst`: flagged "duplicate code with subtle drift."
5. `test-design-reviewer`: scored the suite against Farley's 8 properties
   and found "Necessary" lacking — the test claims an invariant its
   fixtures cannot prove.

This is the modal pattern for `pre-existing-becomes-load-bearing-this-PR`
findings: the bash regex was acceptable in isolation (no other
implementation to disagree with); the TS sibling made the drift visible
and consequential. Per
`knowledge-base/project/learnings/2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md`,
mirroring an existing brittle pattern "for symmetry" is exacerbation, not
preservation — fix inline, do not file `pre-existing-unrelated`.

## Sharp edges

- The bash header comment claimed the regex was already `{20}`-anchored.
  Trusting that comment in the TS port and writing 20-char-only fixtures
  was the failure mode. The bash form had drifted from its own
  documentation at some earlier date; nobody noticed because no TS sibling
  existed to disagree with it.
- A parity contract is only as strong as the boundary cases the fixtures
  exercise. Adding "canonical works on both sides" tests is necessary but
  not sufficient.
- Each quantifier in the regex implies at least 3 fixtures (under, exact,
  over) for any non-`?` quantifier. The test author's job is to enumerate
  these mechanically, not select "interesting" ones.

## Session Errors

1. **PreToolUse `security_reminder_hook.py` false-positive on the RegExp prototype method `<re>.test/<re>.match-equivalent`** — the substring matcher matches the bare 4-letter method name regardless of namespace, conflating a regex method call with the `child_process` shell-spawn primitive. The same hook also matches code-evaluation and innerHTML primitives by bare name. **Recovery:** rewrote to `url.match(CANONICAL_URL_RE)`. The Write tool itself flagged when this learning document mentioned the literal substring of any of these primitives, which is why this entry uses paraphrases. **Prevention:** narrow the hook's pattern to require a namespace prefix or start-of-identifier boundary so it does not fire on regex method calls. Consider scoping all such substring rules to namespace boundaries.
2. **Initial parity test fixtures missed length-anchor boundary** — 5 of 10 review agents flagged the bash/TS regex drift after the test passed. **Recovery:** tightened bash regex + added 2 length-anchor fixtures + tightened assertion (rc + stdout asserted independently per data-integrity-guardian F2). **Prevention:** when porting a regex to another language, mechanically enumerate fixtures from the regex's quantifiers (see the "Key insight" table above) BEFORE writing the parity test. Apply this rule at plan-time, not at review-time.
