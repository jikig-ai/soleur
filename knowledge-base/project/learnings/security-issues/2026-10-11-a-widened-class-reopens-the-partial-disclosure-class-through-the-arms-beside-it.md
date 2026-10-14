---
module: "System"
date: 2026-10-11
problem_type: security_issue
component: tooling
symptoms:
  - "GitHub's rotated ~390-520-char ghs_ installation tokens (b64token alphabet) were rejected or partially masked by every vendored-shape sentinel in the repo"
  - "Widening a token class to [A-Za-z0-9._~+/=-] silently re-opened partial disclosure through a second door: generic-shape arms running BEFORE the GitHub arms could match mid-body on the newly-admitted non-word bytes, shatter the gh*_ run, and leak the post-hit tail"
  - "The repo-wide stale-class census itself could not see the defect class it was built to kill (7-extension pathspec, first-class-only judge, *ghs* substring allowlist, silently-dying arms)"
root_cause: logic_error
resolution_type: code_fix
severity: high
status: open
tags: [credential-redaction, github-token, ghs-rotation, partial-disclosure, census, regex-ordering]
---

# Troubleshooting: a widened credential class reopens partial disclosure through the arms beside it

## Problem

GitHub rotated `ghs_` installation tokens from a ~40-char base62 shape to a ~390-520-char
b64token alphabet (`[A-Za-z0-9._~+/=-]`). Every sentinel pinning the old shape had to move to the
canonical alphabet (ADR-280) — and the sweep itself kept exhibiting the same defect class in new
clothes: each lens that verified "the class is now canonical" missed that the *machinery around
the class* (arm order, other arms, the census's own corpus) could still strand a tail.

## Environment

- Module: repo-wide credential-shape pins (redactors, detectors, validators, doc pins)
- Date: 2026-10-11 (issue #9999, PR #10051)

## Symptoms

- `TOKEN_FORMAT_RE` warned on every issued installation token (`{30,128}` ceiling + narrower class).
- A legacy `ghs_[A-Za-z0-9]` redaction arm masked only the base62 *prefix* — `<github-server>._~+/=-<tail>` left credential bytes in the log.
- The `SECRET_QUERY_PATTERNS` exfil tripwire in `cron-bash-allowlist-hook.mjs` carried the stale class — invisible because the census swept only 7 extensions.
- Proven live in review: a 395-char fixture containing `AB12CDEF.1.2.3.4.xyzzy42` mid-body was masked as `<github-server><iban>.<ip>.xyzzy42` under generic-first arm ordering — the tail leaked.

## What Didn't Work

**Attempted 1: enumerate the sites by hand.** A static six-site list missed every bracketed-prefix
(`gh[pousr]_`), alternation (`(ghp|gho|ghu|ghs|ghr)_`), and factored-prefix (`gh(?:p|o)_`) spelling,
plus `.py`/`.mjs` carriers. *Why it failed:* the enumeration repeated the same shape-assumption the
bug lived in.

**Attempted 2: a census arm per literal spelling.** The first census still judged only the first
`[…]` of a two-segment `github_pat_[X]{22}_[Y]{59,}` literal, required the 7 canonical bytes in
fixed order, treated a `-` inside `A-Z` as a member dash, and let a `*ghs*` substring allowlist
exempt oblique `gh[su]_` spellings. *Why it failed:* guard machinery built in the same session as
the fix inherits the same blind spots — it needs its own review surface (per-arm liveness, exact-
literal slots, dead-slot detection, discrimination rows in both directions).

## Solution

1. **Canonical class everywhere** the pattern judges a credential *value* — `[A-Za-z0-9._~+/=-]` —
   across redactors, detectors, validators, workflow sed recipes, and the two lockstep/parity pairs
   (byte-identical edits where a parity test pins them).
2. **GitHub arms run FIRST** in every sequential redactor (`run-scan.sh`, `redact-engine.py`,
   `main-health-monitor.yml`, `live-verify/redact.ts`) — a lower-priority generic arm (IPv4, IBAN,
   UUID, stripe, env_var, AWS prefix) matching mid-body on `.`/`/`/`=` would split the run and leak
   the tail. The regression fixture embeds `AB12CDEF.1.2.3.4.xyzzy42` mid-body so a reorder goes RED.
3. **Drop trailing `\b`** on the GitHub mask arms — the canonical class ends in non-word bytes
   (`=`, `+`, `/`), where `\b` demands a word char and strands the tail. Leading `\b` stays.
4. **Guard-3 census**: 17-extension corpus, five arms (literal / two-segment `github_pat_` /
   alternation / bracketed-prefix / `|`-gated factored-prefix), a classifier that judges *every*
   `[…]` span in a hit (range-stripped, order-agnostic, alnum-half required), an exact-literal
   allowlist with dead-slot detection, per-arm rc + hit floors, and a remedy-bearing fail line.
5. **Documented-narrower dispositions are slots, not comments** — `legacy-bash-scanner.sh` fixture,
   `deepen-plan`/`plan-sharp-edges` vendor citations, `git-auth.ts`'s verbatim vendor regex all
   sit in `_ghs_census_allow()` and the suite asserts each slot discharged ≥1 hit.
6. **Known-cost items documented at the site**: kb-search's slug false-positive (`ghs_<slug>` →
   refusal, `--no-paraphrase` recovers) and the PII gate's deliberate over-exclusion posture.

## Why This Works

The rotation's actual failure was never "the class was narrow" — it was that every *shape
assumption* in the system was load-bearing in a different place: the value class, the arm order,
the boundary anchor, the census corpus, the allowlist key. Fixing the class while leaving the
order and the machinery intact reproduces the leak through a different door. The fix therefore
pairs every widened arm with a discriminating proof (a fixture that fails under the *old* order,
not just under the old class) and a census that fails closed on its own blind spots.

## Session Errors

**The plan's static site enumeration missed 4+ same-class sites** (bracketed-prefix, `.py`, `.mjs`
carriers).
- **Recovery:** the Guard-3 census caught them at integration; they were folded in.
- **Prevention:** never enumerate a regex-shape migration by a single literal grep — sweep with one
  arm per known spelling family and let the corpus report the work list.

**Orphaned `else` left by a mid-file replacement in the census test** (syntax error).
- **Recovery:** `bash -n` flagged it; removed the orphan.
- **Prevention:** `bash -n` immediately after any multi-branch edit in a `.test.sh` file.

**Semgrep broken on the host: orphaned `~/.local/bin/semgrep` shim, then a semgrep-core IPC crash
under the Python wrapper.**
- **Recovery:** `uv tool install --force` repaired the shim; the deterministic gate ran via
  `semgrep-core` directly, per file.
- **Prevention:** tracked as queue item #9964 (`ensure-semgrep.sh` must verify semgrep *runs*, not
  just resolves).

**The inter-arm ordering hazard was invisible to every panel seat until the coverage consult**
named the absent defect class.
- **Recovery:** reordered arms + inter-arm probe fixture.
- **Prevention:** in any redactor, ask "which *earlier* arm can match inside this arm's match" — the
  coverage-consult question, not the per-seat one.

**The first inter-arm probe fixture lacked word boundaries** (`…4AB…` adjacency → no `\b`, arms
didn't fire — the test would have green-washed a reorder).
- **Recovery:** `.` separators added; the old-order leak was demonstrated live before trusting the
  fixture.
- **Prevention:** prove the fixture discriminates by running it through the broken shape, not just
  the fixed one.

**The `_rest` advance in the classifier silently relied on a `BASH_REMATCH` clobber.**
- **Recovery:** replaced with `${_rest#*\]}` index advance.
- **Prevention:** never consume `BASH_REMATCH` after a later `=~` in the same loop — capture it
  before the inner match or advance structurally.

## Prevention

- Any credential-shape migration must sweep **one arm per prefix spelling** (literal, `gh[…]`,
  `(a|b)_`, `gh(?:…)`, escaped junctions) across **all** carrier extensions — and the sweep must
  live in the tree as a census, not run once and die.
- In a sequential redactor, **specific-prefix arms precede generic-shape arms**; a fixture must
  embed sub-pattern bait mid-body to prove the order is load-bearing.
- Trailing `\b` after a class that admits non-word bytes is a leak, not a boundary.
- An allowlist keyed on file+substring inherits the file as an exemption scope; key on the
  **exact literal** and assert every slot discharged a hit.

## Related Issues

- See also: [a credential guard modeled on the vendor format refused the vendor's next format](../test-failures/2026-10-11-a-credential-guard-modeled-on-the-vendor-format-refused-the-vendors-next-format.md) — the #9972 incident this arc follows through on.
- See also: [redaction by subtraction fails open on a non-matching pattern](2026-08-04-redaction-by-subtraction-fails-open-on-a-non-matching-pattern.md) — same partial-disclosure family, detection side.
- See also: [redaction fix must sweep all render sinks not just the new path](2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path.md) — the sink-enumeration half of this learning.
