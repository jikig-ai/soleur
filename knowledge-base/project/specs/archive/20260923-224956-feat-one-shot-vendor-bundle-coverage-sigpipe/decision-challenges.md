# Decision Challenges — feat-one-shot-vendor-bundle-coverage-sigpipe

Recorded by `soleur:plan-review` (headless). By default the plan follows the operator's stated direction. Each item below was surfaced for the operator to decide and was not applied automatically.

## 1. Drop the helper and the TS7 regression block (User-Challenge)

- **Source:** soleur:engineering:review:dhh-rails-reviewer (P1)
- **Proposal:** Hoist `glob_items="$(grep -E … || true)"` above the TS4 loop and use herestrings at the call sites. Drop `glob_item_contains`, the TS7 fixture block and the floor bump. Prove the fix once at /work time by restoring the pipe and looping the suite.
- **Why it challenges the operator's direction:** The brief explicitly asks for a shipped regression check: a >64 KiB lefthook-shaped fixture with the needle on line 1. Dropping it removes scope the operator requested.
- **Plan disposition:** Keep the operator's direction. TS7 stays, trimmed to 2 `assert_eq` rows. The helper stays because it is the only way TS7 can exercise the same code the TS4 loop runs (P4).

## 2. TS3 membership as a native bash test instead of a grep herestring (Taste)

- **Source:** soleur:engineering:review:dhh-rails-reviewer (P2)
- **Proposal:** `[[ " ${NONCONFORMING[*]:-} " == *" incident "* ]]`
- **Plan disposition:** Keep the herestring form. The brief names the herestring convention (#7240 / the grep-q-pipe-guard header), and the conversion is for consistency, not a live race. This is a matter of taste either way.
