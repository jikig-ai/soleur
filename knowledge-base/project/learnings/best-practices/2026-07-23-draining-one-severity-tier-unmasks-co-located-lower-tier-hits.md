# Learning: draining a linter's higher-severity tier unmasks co-located lower-tier hits

## Problem

`lint-credential-path-literals.py` reports **one verdict per line, hard-fail
first** (`_first_match` checks `HARD_FAIL_RES`, and on a hit `continue`s — the
advisory check for that line never runs). Issue #6868's drain plan asserted
`AC3: advisory count stays 15` while neutralizing the 30 hard-fail lines.

Three lines in `2026-07-17-fix-web-platform-docker-login-erofs-cred-path-plan.md`
(15, 40, 63) each carried BOTH a `$HOME/.docker/config.json` hard-fail AND a
`/home/deploy/` or `/root/` `.docker/config.json` advisory on the **same physical
line**. The advisory was always present but **masked** by the hard-fail. Draining
the hard-fail surfaced it → advisory line-count rose **15 → 18**, so the
plan-quoted AC3 invariant was wrong.

## Solution

- Re-derive the count from the as-written files, not the plan prose
  (`plan-quoted numbers are preconditions to verify, not facts`). Post-sweep:
  18 advisory lines (`grep -c advisory` returns 19 — the OK summary line also
  contains the word).
- Re-key AC3 from a count-invariance claim to a **token-invariance** claim: prove
  every `/home/<user>/` and `/root/` advisory token is byte-identical on both
  sides of `git diff` (`git diff origin/main...HEAD | grep '<advisory-token>'`
  shows matched `-`/`+` pairs). Only the co-located hard-fail token changed; no
  advisory line was edited. That is the property the plan actually cared about;
  the count was a proxy that the scanner's one-hit-per-line semantics break.

## Key Insight

**Any drain-the-higher-tier sweep against a first-match-wins scanner will change
the lower-tier count whenever the two tiers can co-occur on one line** — the
lower-tier hit was suppressed, not absent, and draining the higher tier unmasks
it. Assert on the token diff (what you actually did / didn't touch), never on the
lower tier's total, and expect the total to move by exactly the number of
co-located lines drained.

## Session Errors

- **Plan draft tripped its own guard (forwarded, near-miss).** The plan + tasks.md
  are in the linter's scan scope; the first draft hard-failed on 3 raw credential
  literals. **Prevention:** already in the plan's Sharp Edges — author self-scanned
  artifacts with only the guard-safe forms (`~/.ssh/id_<key>`, `~/.doppler/`,
  descriptive names) and re-ran the linter on the plan itself (AC4).
- **AC3 advisory-count precondition was stale (15 vs actual 18).** **Prevention:**
  this learning — re-derive counts from disk and assert token-invariance, not a
  total.
- **Minimal-token neutralization lost coherence in paired command blocks (2 P3s
  at review).** `ssh_key_path=…id_ed25519.pub` (kept) next to
  `ssh_private_key_path=…id_<key>` (neutralized) read as a mismatched keypair; a
  file-path var equated to a directory form read imprecisely. **Prevention:** when
  neutralizing ONE token inside a tightly-coupled command/example, sweep the
  sibling tokens in the same block for coherence (neutralize the paired `.pub`
  base too — public keys are un-gated so they don't re-trip the guard).

## Tags
category: best-practices
module: lint-credential-path-literals
