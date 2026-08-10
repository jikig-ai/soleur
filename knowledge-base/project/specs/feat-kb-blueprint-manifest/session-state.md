# Session state — feat-kb-blueprint-manifest (#7332 / PR #7336)

**Last updated:** 2026-08-09 (resume session) · tree clean · rebased onto `origin/main`

> ⚠️ Everything in `### Decisions` is INTENT unless marked VERIFIED. Probe each
> outward-facing claim before treating it as done (`gh issue view`, `ls`, re-run the
> command). This section is written mid-flight and a crash leaves claims without acts.

## Where this is

PR #7336, labels `semver:minor` + `secret-scan-allow-rename`. Scope is PR 1 only (CLI
producers); PR 2 (manifest + dashboard) is deferred and scoped in the plan. Issue #7332
stays OPEN — the PR body deliberately uses `Ref`, not `Closes`, because the issue's
subject is the *manifest*, which PR 2 delivers. **VERIFIED this session:** `gh issue view
7332` → `OPEN`.

## What the resume session did (all VERIFIED)

1. **Rebased `--onto origin/main`, not plain.** The branch was cut on top of
   `feat-alpha-onboarding-motion`, whose 8 commits had merged as the *squashed* #7328. A
   plain rebase replayed them and conflicted repeatedly. Correct form:
   `git rebase --onto origin/main b63bab198 feat-kb-blueprint-manifest`. Backup branch
   `backup-pre-rebase-b00f17260` still exists locally.
2. **Restored `feat-alpha-onboarding-motion/spec.md`**, which this branch net-deleted
   (worktree reuse). Invisible until the creating commits were dropped as already-merged.
3. **Regenerated `model.likec4.json`** — the rebase conflict had 1149 `"id"`s on main vs
   1163 on the branch with neither a superset. Re-derived via
   `scripts/regenerate-c4-model.sh`; `c4-model-freshness.test.sh` green.
4. **Reconciled ADR-171 against #7342 — CONFIRMED, and amended.** See below.
5. **Regenerated the Grok compat stub + `agents.manifest.json`**, stale since the layer-7
   agent edit. `grok-inspect-contract.test.ts` was the only real suite failure.
6. **Shipped `scripts/lint-shell-capture-exit.py`** + unit suite + baseline, registered in
   `scripts/test-all.sh`. 25/25 unit assertions; 216 baselined findings.
7. **Three learnings** committed under `knowledge-base/project/learnings/2026-08-09-*`.

## The ADR-171 / #7342 reconciliation — CONFIRMED, not reversed

`e9a44b055` (#7342) determines the controller/processor split for alpha-tester repository
data. ADR-171 claim 3's consent argument is the sole load-bearing reason for the layer-7
decision (the plan's second reason was measured and refuted during review), so this
mattered. Outcome, recorded in ADR-171 as new claim **3a**:

- **Confirmed.** The determination's §2 machine/key/purpose test puts a Soleur-owned sink
  serving Soleur's purpose in **Posture C — CONTROLLER**. Its §1 limb (ii) records a live
  instance that is this case almost verbatim: reading a tester's `knowledge-base/` tree
  "to measure knowledge-base growth as a **Jikigai** product metric."
- **Amended (1) — the credential limb.** The old unqualified "makes Soleur a data
  controller" missed that §2 enters **Posture B — PROCESSOR** (Art. 28(3) instrument
  required *before* processing) the moment content reaches a Jikigai machine, credential
  **or account**, and that it "fires without anyone noticing, because no file moves."
- **Amended (2) — a second independent reason.** The determination's §4 egress evidence
  rests on "**no automatic or background telemetry; all egress is explicitly
  operator-invoked**", which is what holds up §4(a)'s finding that the published position
  "remains TRUE within its scope." A Soleur-owned default sink would falsify it directly.
  Layer 7 is therefore no longer carried by the consent argument alone.
- **Amended (3) — status.** `draft-requires-counsel-review`, disposition **BLOCKED**
  pending §11; **C9** requires a re-run before tester #2, which would make 3a stale.
- **Also named:** this ADR's own baseline measurement of `2my8r9ry2t-wq/Skouer` is itself
  a Posture C act — the processing recorded as **PA-35**.

## Do this next

1. **`/soleur:ship`** — marks ready, which is when CI first runs on any of these commits.
   Expect to iterate.

## Landmines a fresh session will otherwise re-derive

- **`extensions.worktreeConfig` on the shared bare `.git/config` wedges EVERY worktree at
  once** when `config.worktree` files are empty. Hit this session; recovery is in
  `plugins/soleur/skills/git-worktree/SKILL.md` Sharp Edges and the 2026-08-09 learning.
- **`.claude/settings.json` has no PostToolUse `Bash` matcher**, so the local CLI is
  unmirrored — but `plugins/soleur/**` IS vendored into the prod image and executed there
  under the `Bash` marker extractor. **Layer 7 is a property of the EXECUTION surface, not
  the file's location.** Corrected in three places; do not "fix" it back.
- **`npx -y <pkg>@<version>` ignores a global install** (verified with a control), so
  `ci.yml`'s `npm install -g likec4` does nothing for the producer suite.
- **`test-scripts` now needs `setup-bun`** — added, with a guard
  (`scripts-shard-runtime-coverage.test.sh`). The old predicate `grep -l '^bun '` is
  column-1 anchored and cannot see a call inside a function body; do not restore it.
- **The relationship gate reads `edges.length`, NOT the rendered count.** `likec4 export
  json .` renders the whole directory, so the merged count is dominated by any
  hand-authored `model.c4`.
- **`kb-coverage.md` is a STATE snapshot; stdout is the RUN log.** Do not reintroduce
  count flags — an absent `--c4-elements` silently became `0`.
- Registering a new `plugins/soleur/test/*.test.sh` is auto-globbed into the scripts
  shard; a new `tests/scripts/test-*.sh` is NOT — it needs an explicit `run_suite` line.
- **`apps/web-platform` fails locally with `vitest: not found`** — this worktree has no
  `node_modules` and the PR touches zero files under `apps/web-platform`. Environmental.

## Known-open, none blocking

`writeIfAbsent`'s filename-only spec.c4 check; `init`'s check-then-create race; the
`mktemp` cross-device non-atomicity in `init_register`/`write_row`; `loadComponentDir`
unguarded against a FIFO named `*.md`; register created at mode 0600. All recorded in the
review commit messages with reproductions.

Three unreferenced Pencil scratch exports (`PcBtk-`, `f5zF3-`, `xLu1a-`) remain in the PR
diff; main already carries the curated numbered set. Left in place deliberately — removing
them was not in scope.
