# Tasks — perf(ci): in-image verify copy exclusion (#7007)

Derived from `knowledge-base/project/plans/2026-07-28-perf-ci-in-image-verify-copy-exclusion-plan.md`
(v2, post plan-review). Read the plan's §Mechanism before starting — the issue's own proposed
`GLOBIGNORE` fix was measured to be wrong and must not be reinstated.

## 1. Setup / preconditions

- [ ] 1.1 Re-read both helpers; confirm `cp -r /src /build && cd /build` is still present. Anchor
      on content, not on `:42` / `:39`.
      - `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`
      - `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh`
- [ ] 1.2 `docker info >/dev/null` — needed for the L2 rehearsal (tasks 4.x). If unavailable, say so
      explicitly in the PR body; do not skip silently.
- [ ] 1.3 Choose the warm `/src` for the rehearsal. This worktree has `node_modules` but **not**
      `infra/.terraform`; `/home/jean/git-repositories/jikig-ai/soleur/apps/web-platform` has both.
      Mount that path (a measurement, not a source read).
- [ ] 1.4 Confirm `apps/web-platform/scripts/lib/` exists and `scripts/test-all.sh` still globs
      `apps/web-platform/scripts/lib/*.test.sh` in the `want_scripts` block (it does today — the
      dir already holds `supabase-ref-resolver.sh` + `.test.sh`, the exact shape being added).

## 2. RED — failing test before the fix

- [ ] 2.1 Create `apps/web-platform/scripts/lib/in-image-copy-src.sh` with a **deliberately naive**
      body: `set -euo pipefail`, arg parsing, `mkdir -p "$DEST"; cp -r "$SRC"/. "$DEST"/`.
- [ ] 2.2 Create `apps/web-platform/scripts/lib/in-image-copy-src.test.sh`. Shape mirrors
      `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`: `set -eu`, `SCRIPT_DIR` resolution,
      `T="$(mktemp -d)"` + `trap 'rm -rf "$T"' EXIT` (owning trap required —
      `scripts/lint-trap-tempfile-ownership.py` rule (c)), `pass`/`fail` counters with `fail()`
      returning 0, single `[[ "$FAIL" -eq 0 ]] || exit 1` chokepoint. All fixtures synthesized
      inline (`cq-test-fixtures-synthesized-only`).
- [ ] 2.3 Build the fixture tree exactly as listed in the plan's Phase 1 (dotfiles, `package.json`,
      `package-lock.json`, `scripts/sandbox-canary.mjs`, `infra/main.tf`,
      `infra/.terraform.lock.hcl`, `infra/.terraform/providers/big.bin`,
      `infra/sentry/.terraform.lock.hcl`, `infra/sentry/.terraform/x/y.bin`,
      `node_modules/pkg/index.js`, `test/fixtures/node_modules/keepme.txt`).
- [ ] 2.4 Write the 7 assertions:
      1. positive control — fixture contains `node_modules`, `infra/.terraform`,
         `infra/sentry/.terraform`, and every dotfile
      2. run the real artifact: `bash "$SCRIPT_DIR/in-image-copy-src.sh" "$SRC" "$DST"` exits 0
      3. destination lacks `node_modules`, `infra/.terraform`, `infra/sentry/.terraform`
      4. `diff -rq --exclude=node_modules --exclude=.terraform "$SRC" "$DST"` exits 0, **plus** an
         explicit check that `test/fixtures/node_modules/keepme.txt` exists (the `diff --exclude`
         masks it)
      5. producer-failure control: `bash in-image-copy-src.sh "$T/does-not-exist" "$DST3"` exits
         non-zero **and** stderr contains `FATAL:`
      6. both helpers migrated: neither matches `cp -r /src /build`, both match
         `in-image-copy-src.sh` (grep by explicit path, not a directory pathspec)
      7. `bash -n` clean on both helpers and on `in-image-copy-src.sh`
- [ ] 2.5 Run the suite. It MUST go RED on **assertion 3** (`node_modules` present). Record the
      transcript for the PR body. A RED that only reports a missing file or marker does not count.

## 3. GREEN — apply the fix

- [ ] 3.1 Replace the naive body of `in-image-copy-src.sh` with the plan's §Mechanism body
      (`set -euo pipefail`, `mkdir -p "$DEST"`, `if ! tar -C "$SRC" --exclude=./node_modules
      --exclude=.terraform -cf - . | tar -C "$DEST" --no-same-owner -xf -; then` … `FATAL` …
      `exit 1; fi`) and the full header comment. Keep the comment: it records why not `GLOBIGNORE`,
      why the anchoring is asymmetric, why the archive root must stay `.`, why `--no-same-owner`,
      and why `pipefail` lives here and not in the callers.
- [ ] 3.2 In `sandbox-canary-verify-in-image.sh`, replace `cp -r /src /build && cd /build` with
      `bash /src/scripts/lib/in-image-copy-src.sh /src /build` + `cd /build`. No `'` in the new
      lines (they sit inside `docker run … bash -c '…'`).
- [ ] 3.3 Same replacement in `plugin-root-propagation-verify-in-image.sh`.
- [ ] 3.4 Add the "`/build` is a filtered copy of `/src` — see `scripts/lib/in-image-copy-src.sh`"
      sentence to **both** helper headers. One-sided is drift.
- [ ] 3.5 Re-run the suite: all 7 assertions pass. Record the GREEN transcript.

## 4. L2 rehearsal (unpaid, in the pinned image)

- [ ] 4.1 Run the plan's AC6 command verbatim against the warm `/src`: parity `diff -rq` clean,
      `/build/node_modules` and `/build/infra/.terraform` absent.
- [ ] 4.2 In the same container, `cd /build && npm ci --no-audit --no-fund` exits 0 (AC7). **This
      has never been run** and is the highest-fidelity check available without paying.
- [ ] 4.3 Capture the A/B wall clock + `/build` size for the PR body.

## 5. Exit gate

- [ ] 5.1 `bash scripts/test-all.sh scripts` — the gate's own invocation over the whole shard, not
      a hand-picked file list.
- [ ] 5.2 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 5.3 The live form used by `scripts/lint-trap-tempfile-ownership.test.sh` for the new
      `mktemp` caller.
- [ ] 5.4 AC1's grep pair, run **after** `git add` (`git grep` is tracked-only).

## 6. Ship

- [ ] 6.1 PR body: `Closes #7007`; the A/B table; the RED→GREEN transcripts; and the explicit
      statement that the **paid** end-to-end path (`ANTHROPIC_API_KEY` + a real Haiku turn) was
      **not run**, with the reason (both scripts are creds-gated, and neither CI gate's trigger
      regex matches the changed files).
- [ ] 6.2 `/ship` folds
      `knowledge-base/project/specs/feat-one-shot-7007-in-image-verify-copy-exclusion/decision-challenges.md`
      into the PR body and files the `action-required` issue (UC-1: the issue's own proposed fix
      was falsified; UC-2: the trigger-set expansion was declined).
- [ ] 6.3 No operator checklist / operator-action headings in the PR body — there are none, and the
      tokens trip `ship-operator-step-gate.sh`.
