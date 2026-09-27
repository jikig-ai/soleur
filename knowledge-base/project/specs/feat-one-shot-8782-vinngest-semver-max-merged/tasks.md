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
  - 2.1.3 Add the normalized `diff` equality row. Its failure message must name the fix.
- 2.2 Rewrite the rows whose semantics flip:
  - 2.2.1 B1, B2, B8 become exclusion rows. Seed `v1.1.37\t$DIG_OLD` explicitly. Expect `noop`, no `v1.1.38` in the crane log, no branch, and pins unchanged.
  - 2.2.2 B3 becomes `opened` at `v1.1.38`, with auto-merge armed. Add `refs/remotes/origin/pr-newer`.
  - 2.2.3 B7 becomes a refusal at `resolve`, with the needles `no vinngest-v* tag is merged into` and `shallow or unreadable`. Crane and gh are never called.
  - 2.2.4 B7a becomes an exclusion row. Seed `v1.1.37`, expect `noop`.
  - 2.2.5 B12 and B13 become the unified downgrade refusal at `resolve`, with the needles `Refusing to author a downgrade` and `Do NOT delete or re-cut`. B12 has no delete command, and crane is never called.
- 2.3 Add the new rows:
  - 2.3.1 B9b: a depth-1 clone where the target tag sits below the graft. Assert the precondition that `--merged` omits it. Expect `assert_refused … 'shallow'`.
  - 2.3.2 B20: `v1.9.0` → `v1.10.0` is `opened`.
  - 2.3.3 B21: pre-release and 4-part names are excluded. The pin digest must equal the seeded digest. Expect `noop`.
- 2.4 Run the suite. Record the expected RED lines: the Guard 1 dispatch rows, B1, B2, B3, B7, B7a, B8, B12, B13. Commit (Phase-1-only commit for AC4).

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
