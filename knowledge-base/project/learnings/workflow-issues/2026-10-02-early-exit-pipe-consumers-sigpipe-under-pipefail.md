# Learning: early-exiting pipe consumers are a scale-dependent SIGPIPE trap under `set -o pipefail`

## Problem

`emit-review-trailer.sh --fix-round` computes the effective reviewed head with:

```bash
git log --format='...' HEAD | awk 'NF == 1 { print $1; exit }'
```

On a 6-commit fixture this is invisible — `git log`'s whole output fits one stdio flush delivered at exit, so git returns 0 before awk's close matters. On the real repo (tens of thousands of commits), awk exits after line ~1 while git still has history to write; the next flush gets EPIPE, git dies 141, `pipefail` propagates it, and `set -e` kills the script mid-workflow. The test suite greens either way — it is structurally incapable of reproducing the failure. The targeted fix-round review (the seat agent's static read, not the suite) is what caught it; a live run on the real history would have been a silent 141.

Sibling instance, same class: `git log | grep -q` idempotence checks exit at first match — bounded inputs today, same latent trap. And a second, subtler variant: filtering "attestation commits" by `review:`-prefixed SUBJECT breaks when the repo's own fix-commit convention is `review: <summary> (P<N>)` — attestation and fix commits share the subject vocabulary. Filter on the trailer key (`%(trailers:key=Reviewed-*,valueonly)` empty/non-empty) instead; the subject is prose, the trailer is the machine-read field.

## Solution

Three coupled fixes in `emit-review-trailer.sh`:

1. **Bound the walk to the range it serves** — `git log "${FIX_SINCE}..HEAD"` instead of `HEAD`: the walk never outgrows the round's own commits, so the SIGPIPE shape cannot arise.
2. **Consume all input** — `awk 'NF == 1 && $1 ~ /^[0-9a-f]{40}$/ && !found { found = $1 } END { print found }'` — no early `exit`; the sha-anchored field test also refuses trailer *values* on continuation lines (a `full N/N agents` value can't be mistaken for a commit).
3. **Fall back to `FIX_SINCE`, not `HEAD`, on an all-attestation range** — falling back to HEAD points at the prior attestation commit, rotating the recorded `Reviewed-Fix-Range` on every call and never deduping; `since..since` is the honest empty range.

## Key Insight

`cmd | early-exiting-consumer` under `set -o pipefail` is GREEN ON FIXTURES and 141 ON REAL HISTORY — a scale-dependent failure invisible to any test that runs against small generated data. When a script produces input for a consumer that can stop early (`head`, `awk exit`, `grep -q`), either bound the producer's input or make the consumer read to EOF. And when picking "the commit that matters," filter on the field that machine-reads it (trailer keys), never on a subject string a human convention also uses.

## Session Errors

Errors this session that compose the inventory (all resolved; each is its own species):

1. ADR-265 ordinal collision with main (#9401) — found by panel review, fixed by renumber to ADR-267.
2. `model.likec4.json` regenerated as empty — tmp file copied before population; regenerated.
3. Dead `source_seen` variable (shellcheck); `RISK_TIER_KEY`/`FIX_*_KEY` missed the xtrace credential guard — lint-bot-statuses.
4. `harness-parity` census: bare leaf ids in doc prose — canonical `soleur:…` ids required even in examples.
5. Plugin-root anchoring: CWD-controllable `bash plugins/...` anchors in a token-free reference doc → `<plugin-root>` placeholder convention.
6. New floor-bearing suite in a deferred directory → guard-vacuity-floor ledger; promoted.
7. Fix-round idempotence keyed on the left edge only → second rounds swallowed (found by pattern seat).
8. SIGPIPE-under-pipefail + subject-vs-trailer filtering + fallback-to-HEAD rotation (found by fix-round-2 verifier; this learning).
9. Skill-body budget overrun on ship/SKILL.md — resolved by NOT extending `KNOWN_TRAILER_KEYS` (the detector's own criterion is "a consumer reads the key"; the new keys carry none — ADR-127 posture).

## Tags

category: workflow-issues
module: plugins/soleur/skills/review
