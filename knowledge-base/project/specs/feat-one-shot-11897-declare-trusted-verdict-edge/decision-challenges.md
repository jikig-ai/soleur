# Decision Challenges — feat-one-shot-11897-declare-trusted-verdict-edge

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Declare vs accept for `scripts/inngest-a5-a6-owner-ask-10136` ↔ `scripts/lib/trusted-verdict.sh` | technical | pending - assumed: declared edge — suite executes the real lib via the SUT probe (`source "$libdir/trusted-verdict.sh"` at .sh:177); verified by scratch-worktree ratchet `exit=0 live=1510 baseline=1510`; consistent with prior CTO precedent (#11771 → #11781, "ambiguity resolves to the stricter default") |
