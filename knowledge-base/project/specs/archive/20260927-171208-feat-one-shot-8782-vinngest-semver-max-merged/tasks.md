---
feature: feat-one-shot-8782-vinngest-semver-max-merged
plan: knowledge-base/project/plans/2026-09-27-ci-vinngest-semver-max-merged-into-main-plan.md
issue: 8782
lane: cross-domain
---

# Tasks — semver-max over `vinngest-v*` tags merged into main (#8782)

## 1. Setup

- 1.1 Re-verify the premise on freshly fetched `origin/main`. This is plan AC5: merged-max = pin = `v1.1.40` at all four sites.

## 2. RED — tests first (`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`)

- 2.1 Replace the literal loop `# Guard 2 row 5: regex parity` with Guard 1: selector byte-equality.
  - 2.1.1 Build an `ENVIRON`-based slicer for the `TARGET=` and `LATEST_TAG=` blocks.
  - 2.1.2 Add the dispatch rows: exactly 1 block per file; 3 lines; contains `tag --merged HEAD --list 'vinngest-v*'`; contains `sort -V`.
  - 2.1.3 Add the equality row with **directional** normalization and a `diff`:
    - writer: `TARGET=`→`SEL=` and `"$REPO_DIR"`→`"$DIR"` only;
    - checker: `LATEST_TAG=`→`SEL=` and `"$SCRIPT_DIR"`→`"$DIR"` only;
    - the failure message names the fix.
  - 2.1.4 Add the consumer-wiring rows:
    - exactly one `LATEST_TAG=` assignment, counted with the slicer's own awk pattern;
    - `grep -cF` shows that both `[[ '$PIN' == '$LATEST_TAG' ]]` and `[[ '$DED_PIN' == '$LATEST_TAG' ]]` appear exactly once.
- 2.2 Change the `assert_refused` helper to `assert_refused <name> <wording> [stage=ancestry]`.
- 2.3 Rewrite the rows whose semantics flip. Keep the existing `v1.1.38\t$DIG_NEW` seeds.
  - 2.3.1 B1 and B2 become exclusion rows:
    - seed `v1.1.37\t$DIG_OLD` explicitly;
    - expect `noop`;
    - no `v1.1.38` in the crane log;
    - an empty gh log;
    - no `refs/heads/soleur/*` branch on origin;
    - pins unchanged.
  - 2.3.2 Reshape B8 so the **target** tag is shadowed:
    - `vinngest-v1.1.38` goes on main;
    - `refs/vinngest-v1.1.38` points at a side commit;
    - expect `opened`, `provenance=bound`, and pins at `v1.1.38`.
  - 2.3.3 B3 becomes `opened` at `v1.1.38`, with auto-merge armed. Add `refs/remotes/origin/pr-newer`.
  - 2.3.4 B7:
    - `assert_refused … 'no vinngest-v* tag is merged into' resolve`, plus the needle `shallow or unreadable`;
    - precondition: `git tag --merged HEAD` prints nothing in the fixture.
  - 2.3.5 B7a becomes an exclusion row:
    - seed `v1.1.37`, expect `noop`;
    - precondition: `--merged` prints exactly `vinngest-v1.1.37`.
  - 2.3.6 B12 and B13:
    - `assert_refused … 'Refusing to author a downgrade' resolve`, plus the needle `Do NOT delete or re-cut`;
    - B12 must carry no delete command;
    - B13 is added coverage only; it already passes today.
- 2.4 Add the new rows:
  - 2.4.1 B9b: a depth-1 clone where the target tag sits below the graft.
    - Precondition: `--merged` omits the tag.
    - Expect `assert_refused … 'cannot decide which vinngest-v* tags are merged'`.
  - 2.4.2 B20: `v1.9.0` → `v1.10.0` is `opened`. Seed both `v1.9.0→DIG_OLD` and `v1.10.0→DIG_NEW`.
  - 2.4.3 B21: pre-release and 4-part names are excluded.
    - The pin digest must equal the seeded digest.
    - Expect `noop`.
    - Check the crane log separately: no `v1.2.0-rc1`, and no `v1.2.0.1`.
- 2.5 Run the suite and record the expected RED lines: the Guard 1 dispatch rows, B1, B2, B3, B7, B7a, B8, B12. The deepen prototype confirmed this set. Commit (Phase-1-only commit for AC4).

## 3. GREEN — writer (`.github/scripts/bump-inngest-bootstrap-pin.sh`)

- 3.1 Move the shallow check above `# --- resolve:`, staying at stage `ancestry`. The wording must not reference `TARGET` or `${tag}` (`set -u`).
- 3.2 Switch the `TARGET=` block to `tag --merged HEAD --list`. Update the empty-target `resolve` message.
- 3.3 Clean up `target_on_main`:
  - keep the peel and the `SIGNED_COMMIT` binding;
  - delete the `merge-base` call and its arms;
  - delete the legacy `TARGET == PIN_TAG` arm.
- 3.4 Replace the downgrade refusal with the unified message at `resolve`, still before `mktemp` and crane.
- 3.5 Wording pass:
  - the deferral message ("differs from" instead of "ahead of");
  - the cross-check notice;
  - `hold_reason`;
  - the header paragraphs.

## 4. GREEN — checker (`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, AC6)

- 4.1 Change the `LATEST_TAG=` block to be byte-identical to the writer's (Guard 1).
- 4.2 Add a shallow/unreadable hint to the empty-set CI arm message.
- 4.3 Relabel "latest published" to "latest … merged into HEAD" in assert labels, comments and the header bullet.
- 4.4 Make the DRIFT diagnostic three-way: off-main tag → delete it; pin above latest → do NOT bump down; otherwise → bump.
- 4.5 Raise `MIN_ASSERTIONS` to the exact green count.

## 5. Docs / ADR / C4

- 5.1 Amend ADR-232:
  - Context ¶, §2, §7, Sequencing;
  - Alternatives: flip the adopted row and add the `origin/main` row and the off-main-signed row;
  - add `## Amendment 2026-09-27 (#8782)`;
  - update Verification;
  - leave the 2026-09-24 amendment verbatim.
- 5.2 Update the runbook `inngest-server.md` §Bootstrap-image release:
  - step 1: rewrite the trap-retired paragraph;
  - step 2: give each stage's meaning;
  - fix the AC6 sentence.
- 5.3 Edit the `github -> soleurMarketplace` edge prose in `model.c4`, then run `bash scripts/regenerate-c4-model.sh`.

## 6. Verify

- 6.1 Suite green (plan AC3).
- 6.2 Lints and censuses pass (plan AC6):
  - `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
  - `fixture-dir-operand-assert.test.sh`
  - `fixture-env-adoption.test.sh`
- 6.3 C4 tests pass (plan AC9).
- 6.4 ADR, runbook and C4 grep ACs pass (plan AC7–AC9).
- 6.5 Push. CI green on `deploy-script-tests` and `pr-quality-guards` (plan AC11). No `.github/workflows` diff.
