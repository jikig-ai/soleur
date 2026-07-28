# Tasks — perf(ci): in-image verify copy exclusion (#7007)

Derived from `knowledge-base/project/plans/2026-07-28-perf-ci-in-image-verify-copy-exclusion-plan.md`
**v3** (post plan-review + deepen). Read the plan's §Mechanism before starting.

Two things the plan measured that you must not re-derive from memory:

- The issue's own `GLOBIGNORE` fix **does not work** for `infra/.terraform`. Do not reinstate it.
- `tar --exclude` is `--no-anchored` by default — a slash does **not** anchor a pattern.
  `--exclude=./node_modules` is root-only only because the archive is created with `.` as its
  member root. Do not change that `.`.

## 1. Setup / preconditions

- [x] 1.1 Re-read both helpers; confirm `cp -r /src /build && cd /build` is still present. Anchor on
      content, not on `:42` / `:39`.
- [x] 1.2 `docker info >/dev/null` — needed for tasks 5.x. If unavailable, say so explicitly in the
      PR body; do not skip silently.
- [x] 1.3 Choose the warm `/src`. This worktree has `node_modules` but **not** `infra/.terraform`;
      `/home/jean/git-repositories/jikig-ai/soleur/apps/web-platform` has both. Mount that path.
- [x] 1.4 Read `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` — the directory's
      source-don't-execute convention. The new file deliberately diverges (executed, positional
      args, file-scope `set -euo pipefail`) because sourcing would leak `pipefail` into the canary
      caller's `curl … | bash`. That divergence must be **stated in the new file's header**, not
      left implicit, or a reviewer will "harmonise" it back.

## 2. RED — failing test before the fix

- [x] 2.1 Create `apps/web-platform/scripts/lib/in-image-copy-src.sh` (mode 644) with a
      **deliberately naive** body: `set -euo pipefail`, arg parsing, `mkdir -p "$DEST"`,
      `cp -r "$SRC"/. "$DEST"/`.
- [x] 2.2 Create `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` (mode 644). Shape mirrors
      `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`: `set -eu`, `SCRIPT_DIR` resolution,
      `T="$(mktemp -d)"` + `trap 'rm -rf "$T"' EXIT` (owning trap required —
      `scripts/lint-trap-tempfile-ownership.py` RULE (c)), `pass`/`fail` counters with `fail()`
      returning 0, single `[[ "$FAIL" -eq 0 ]] || exit 1` chokepoint. Fixtures synthesized inline.
      Two bash footguns: wrap deliberately-nonzero commands in command substitutions with
      `|| true` / `if ! …` / `|| rc=$?`; never `producer | grep -q` under `pipefail`.
- [x] 2.3 Define the shared arrays once (assertions 1/3/4 all read them, so they cannot drift), each
      with a minimum-cardinality guard:
      `EXCLUDED_PATHS=( node_modules infra/.terraform infra/sentry/.terraform )` (≥3) and
      `SURVIVE_PATHS=( .gitignore .env.example .nvmrc .dockerignore .service-role-allowlist
      .dependency-cruiser.cjs package.json package-lock.json scripts/sandbox-canary.mjs
      infra/main.tf infra/.terraform.lock.hcl infra/sentry/.terraform.lock.hcl
      test/fixtures/node_modules/keepme.txt )` (≥13). Build the fixture from them: every survivor
      gets distinct non-empty content; every excluded dir gets a file.
- [x] 2.4 Write the 8 assertions:
      1. positive control — every EXCLUDED_PATHS and SURVIVE_PATHS entry exists in the fixture; both
         arrays meet their floors
      2. run the real artifact: `bash "$SCRIPT_DIR/in-image-copy-src.sh" "$SRC" "$DST"` exits 0
      3. every EXCLUDED_PATHS entry absent from `$DST` — **SKIP, not pass, if 2 failed** (an empty
         `$DST` satisfies every absence check)
      4. `diff -rq --exclude=node_modules --exclude=.terraform "$SRC" "$DST"` exits 0 **and**
         `cmp "$SRC/$p" "$DST/$p"` for every SURVIVE_PATHS entry (`cmp`, not `test -e` — truncation
         is the headline failure mode). SKIP if 2 failed
      5. producer-failure control: plant a `chmod 000` file in the fixture `$SRC`, run the script,
         assert non-zero exit **and** `FATAL:` on stderr. Guard with `[ "$(id -u)" -ne 0 ]` and emit
         a **loud SKIP** if root. Do **not** use a missing `$SRC` — measured, it passes with or
         without `pipefail` and therefore pins nothing
      6. both helpers contain the exact literal `bash /src/scripts/lib/in-image-copy-src.sh /src /build`,
         and neither matches `^[[:space:]]*cp -[aRrP]`. A bare `in-image-copy-src.sh` grep is
         vacuous — the mandated header sentence names the file
      7. `bash -n` clean on both helpers and on `in-image-copy-src.sh`
      8. both helpers pin the same `node:22-slim@sha256:…` digest
- [x] 2.5 Run the suite. Expected RED set is **{3, 5, 6}**, with **3 load-bearing** (the genuine
      behavioural failure). Record the transcript.

## 3. GREEN — apply the fix

- [x] 3.1 Replace the naive body of `in-image-copy-src.sh` with the plan's §Mechanism body and its
      full header comment. The header must record: the `Use:` line, both callers, the pinning test
      + auto-discovery glob, the source-vs-execute divergence and why, the exclusion rationale, the
      **corrected** anchoring rule (`--no-anchored` default; `./` is root-only because of the `.`
      member root), `--no-same-owner`, and why `pipefail` lives here.
- [x] 3.2 In `sandbox-canary-verify-in-image.sh`, replace `cp -r /src /build && cd /build` with
      `bash /src/scripts/lib/in-image-copy-src.sh /src /build` + `cd /build`. No `'` in the new
      lines.
- [x] 3.3 Same replacement in `plugin-root-propagation-verify-in-image.sh`.
- [x] 3.4 Add the header sentence to **both** helpers: `/build` is a filtered copy of `/src` (naming
      `scripts/lib/in-image-copy-src.sh`), and `$APP_DIR` must therefore carry that file
      (`SANDBOX_CANARY_APP_DIR` / `PLUGIN_ROOT_PROBE_APP_DIR` are overridable).
- [x] 3.5 In `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, delete `2>/dev/null` from
      `verdict_json="$(bash -c "$VERIFY_CMD" 2>/dev/null | tail -1 || true)"`. Nothing else on that
      line changes — `|| true` stays (see 6.2). Safe: `$( )` captures stdout only, and
      `sdk-bump-sandbox-gate.test.sh` injects `SDK_GATE_VERIFY_CMD` without asserting on stderr.
- [x] 3.6 Add the one-line addendum to ADR-079's Fidelity note: `/build` is now a filtered copy, so
      whoever next regenerates the fixture with `--capture` knows; the exclusions are outside the
      argv projection surface.
- [x] 3.7 Re-run the suite: 8/8 pass. Record the transcript.

## 4. Mutation proof (do not skip — this is what makes R5 tested rather than asserted)

- [x] 4.1 In a scratch copy, delete `set -o pipefail` from `in-image-copy-src.sh` and re-run the
      suite. Assertion 5 must go RED. Restore. Record the transcript.

## 5. L2 rehearsal (unpaid, in the pinned image)

- [x] 5.1 Run the plan's AC6 command verbatim against the warm `/src`: parity `diff -rq` clean,
      `/build/node_modules` and `/build/infra/.terraform` absent, and every `stat -c "%U %n"` line
      reads `root` (this is what pins R8).
- [x] 5.2 In the same container, `cd /build && npm ci --no-audit --no-fund` exits 0 (AC7). **Never
      run before** — the only check that exercises the gate rather than the filter.
- [x] 5.3 Capture the A/B wall clock + `/build` size for the PR body.

## 6. Exit gate

- [ ] 6.1 `bash scripts/test-all.sh scripts` — the gate's own invocation over the whole shard.
- [x] 6.2 File scope-out SO-1 (canary gate degrades a verify failure to an ack-fallback rather than
      reddening; only the diagnosability half is fixed inline). Verify each label exists via
      `gh label list --limit 200` before use: `deferred-scope-out`, `domain/engineering`,
      `priority/p3-low`, `type/chore`.
- [x] 6.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [x] 6.4 The live form used by `scripts/lint-trap-tempfile-ownership.test.sh` for the new `mktemp`
      caller.
- [x] 6.5 AC1's grep pair, run **after** `git add` (`git grep` is tracked-only).

## 7. Ship

- [ ] 7.1 PR body: `Closes #7007`; the A/B table; all three transcripts (RED / GREEN /
      pipefail-mutation); the SO-1 issue number; and the explicit statement that the **paid**
      end-to-end path (`ANTHROPIC_API_KEY` + a real Haiku turn) was **not run**, with the reason
      (both helpers are creds-gated, and neither CI gate's trigger regex matches the changed files —
      nor does `sdk-bump-sandbox-gate.sh`'s own internal `capture_trigger` regex).
- [ ] 7.2 `/ship` folds
      `knowledge-base/project/specs/feat-one-shot-7007-in-image-verify-copy-exclusion/decision-challenges.md`
      into the PR body and files the `action-required` issue (UC-1: the issue's proposed fix was
      falsified; UC-2: the trigger-set expansion was declined).
- [ ] 7.3 No operator checklist / operator-action headings in the PR body — there are none, and the
      tokens trip `ship-operator-step-gate.sh`.
