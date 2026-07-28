# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-28-perf-ci-in-image-verify-copy-exclusion-plan.md`
- Status: complete (v3 — plan-review + deepen applied)
- Paused at operator request after plan; `/work` not yet started.

### Errors
None. All deepen-plan halt gates (4.5–4.10) passed; KB citations, rule IDs, and GitHub labels verified to resolve.

### Decisions
- **The fix specified in issue #7007 was falsified and replaced.** `GLOBIGNORE` filters only the
  top-level `/src/*` glob expansion, so `/src/infra` survives the filter and `cp -r` recurses into
  it carrying `.terraform`. Independently re-verified by the parent pipeline on a synthetic fixture:
  `node_modules` excluded, but `dest/infra/.terraform/providers/big.bin` still copied; dotfiles
  (`.dotfile`) did survive, so that half of the issue's reasoning held. Replacement:
  `tar -C "$SRC" --exclude=./node_modules --exclude=.terraform -cf - . | tar -C "$DEST" --no-same-owner -xf -`,
  which also covers the not-yet-initialised second terraform root at `infra/sentry/`.
  Recorded as a User-Challenge in `decision-challenges.md` since it departs from a literally-specified fix.
- **Ship the copy as one file** (`apps/web-platform/scripts/lib/in-image-copy-src.sh`) called by both
  helpers, rather than two pasted blocks. `/src` is a mount of `apps/web-platform`, so
  `/src/scripts/lib/…` is reachable in-container. Deletes a marker-extraction/`sed`/`eval` test
  harness, a byte-identity drift pin, and an apostrophe hazard, and lets `set -o pipefail` live in a
  scope with zero blast radius on the canary's `curl | bash`.
- **Verification ladder without a paid turn:** hermetic suite auto-registered via the existing
  `apps/web-platform/scripts/lib/*.test.sh` glob (the only detector — the exclusions are no-ops on a
  cold CI checkout), plus an in-image rehearsal proving parity, root ownership, and `npm ci` success.
  The paid end-to-end path is explicitly NOT run; the PR body must say so rather than claim it.
- **Declined to expand the CI trigger regexes** — cost corrected from two paid Haiku turns to one,
  with the canary half structurally inert due to a second internal regex in `sdk-bump-sandbox-gate.sh`.
- **Two self-corrections applied:** the v1 `PIPESTATUS` guard was dead code under `set -e`, and the
  v2 tar-anchoring comment was empirically false (`--exclude` is `--no-anchored`; `./node_modules` is
  root-only only because of the `.` member root).

### Measured effect
In the pinned `node:22-slim` image against a warm tree: **22.96 s / 2.3 GB → 0.48 s / 35 MB**,
whole-tree parity clean.

### Open findings surfaced (not yet fixed)
- Neither CI gate's trigger regex names the helper scripts, so the change ships with zero CI
  coverage unless the new hermetic suite is added.
- `sdk-bump-sandbox-gate.sh` captured its verify command as `"$(… 2>/dev/null | tail -1 || true)"`,
  making a copy FATAL invisible. One redirect deleted inline; the residual ack-fallback posture is
  filed as a scope-out rather than claimed as fail-loud.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Plan review: `code-simplicity-reviewer`, `kieran-rails-reviewer`, scoped strong-model consult (opus)
- Deepen: `learnings-researcher`, claim-verification pass (sonnet), `test-design-reviewer`, `architecture-strategist`
- Empirical probes: synthetic-fixture `GLOBIGNORE`/`tar` A/B, `docker run` against the pinned
  `node:22-slim` digest (tar version, parity diff, ownership, before/after wall clock), tar anchoring
  control, producer-failure `PIPESTATUS` discrimination
