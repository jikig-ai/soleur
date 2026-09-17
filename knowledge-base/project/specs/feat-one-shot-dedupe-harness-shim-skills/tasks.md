# Tasks — remove duplicate /soleur:go, /soleur:help, /soleur:sync slash-menu entries

Derived from
`knowledge-base/project/plans/2026-09-17-fix-duplicate-soleur-slash-command-entries-plan.md`.

**Decision: option (b′)** — add `user-invocable: false` to the three shared shims so they
stop rendering in the Claude Code slash menu while remaining model-invocable. **Nothing is
deleted in this PR.** Deleting them (option a′) is the eventual end state but is deferred:
it would remove `Skill(soleur:go)`, which `apps/web-platform/server/prompt-injection-wrap.ts:25`
dispatches on **every** Command Center message, and it would delete the only Devin skills
root ever measured to load.

Because nothing is deleted, the skill count stays **98**, `SKILL_DESCRIPTION_WORD_BUDGET`
stays **2442**, and the cloud-mode marker fleet stays **67**. Those three reverts belong to
the follow-up, not here.

## Phase 1 — Preconditions

- [ ] 1.1. Install bun pinned to `.bun-version` (**1.3.14**). `command -v bun` is empty in
      this environment, and `scripts/test-all.sh` gates its bun shard on it — without bun
      the plugin suite, including the new guard, is silently skipped.
- [ ] 1.2. Confirm `bun --version` equals `.bun-version`.
- [ ] 1.3. From the **worktree root** (not the bare repo root), establish a green baseline:
      `bun test plugins/soleur/test/components.test.ts plugins/soleur/test/devin-cloud-mode.test.ts plugins/soleur/test/codex-plugin.test.ts plugins/soleur/test/devin-plugin.test.ts`
- [ ] 1.4. Record the four counters AC2 asserts are **unchanged**: 98 skills, budget 2442,
      marker fleet 67, `bash scripts/sync-readme-counts.sh --check` green at 98.
- [ ] 1.5. Re-confirm the two premises the decision rests on:
      `grep -n 'Invoke /soleur:go' apps/web-platform/server/prompt-injection-wrap.ts`
      returns the postamble, and `plugins/soleur/devin/skills/{go,help,sync}/SKILL.md` exist.

## Phase 2 — Write the guard FIRST, drive it RED (no fix yet)

- [ ] 2.1. `plugins/soleur/test/helpers.ts`: add `discoverSkillsIn(root)` with
      `discoverSkills() = discoverSkillsIn("skills")`, and expose each discovered skill's
      `user-invocable` frontmatter value.
- [ ] 2.2. Extract the pure function `collidingNames({ commandNames, skillRoots })`.
- [ ] 2.3. Pin it with **synthesized** fixtures (`cq-test-fixtures-synthesized-only`):
      a manifest-contributed collision → flags; a manifest path duplicating `./skills` →
      does **not** flag; an empty `skills` array → flags nothing and does not throw;
      a non-user-invocable skill colliding with a command stem → does **not** flag.
- [ ] 2.4. Add the live-tree shell in its **own** `describe("plugin slash-name uniqueness")`
      block in `components.test.ts` — not inside the Kebab-case block — implementing
      clause (a) within-manifest duplicate names, clause (b) user-invocable skills disjoint
      from command stems, clause (c) `.claude-plugin/plugin.json` declares no `skills` key.
      Discover manifests by **glob** over `plugins/soleur/.*-plugin/plugin.json`, never by
      enumerating the three that exist today.
- [ ] 2.5. Add the cross-file guard-presence assertion (mutation row M8's mechanism).
- [ ] 2.6. **Run against the unmodified tree — it MUST fail**, naming `go`, `help`, `sync`
      under clause (b). That is M1 for free. If it passes today, the guard is wrong; stop.

## Phase 3 — Apply the fix

- [ ] 3.1. Add `user-invocable: false` to the frontmatter of each of
      `plugins/soleur/skills/{go,help,sync}/SKILL.md`, with a one-line comment naming why.
- [ ] 3.2. Do **not** add the key to `plugins/soleur/{codex,devin}/skills/*` — those are the
      harness entry points and must stay user-invocable.
- [ ] 3.3. Re-run the guard → GREEN.
- [ ] 3.4. Confirm the four Phase 1.4 counters are unchanged.
- [ ] 3.5. **Do not commit or push before this phase completes** — Phase 2 leaves the tree
      deliberately RED, and both CI and `grok-pre-push-gate.sh:125` would block.

## Phase 4 — Walk the mutation matrix

- [ ] 4.1. M1 — remove `user-invocable: false` from `skills/go/SKILL.md` → RED naming `go`.
- [ ] 4.2. M2 — create `plugins/soleur/commands/flag-bootstrap.md` (valid frontmatter) →
      **GREEN**; `skills/flag-bootstrap/` has no `SKILL.md` so it is not a skill.
- [ ] 4.3. M3 — create `plugins/soleur/commands/qa.md` → RED naming `qa`.
- [ ] 4.4. M4 — with M3 in place, also create `commands/review.md` → RED naming **both**.
- [ ] 4.5. M5 — add `"skills": ["./devin/skills"]` to
      `plugins/soleur/.claude-plugin/plugin.json` → RED via clause (c). Check
      `plugins/soleur/test/plugin-version-fallback.test.ts` for co-firing.
- [ ] 4.6. M6 — create `plugins/soleur/devin/skills/review/SKILL.md` duplicating
      `skills/review/` → RED via clause (a). This is the skills-vs-skills class.
- [ ] 4.7. M7 — feed `collidingNames()` empty inputs → RED against the bounded floor
      `{ commands: >= 3, skills: >= 90, roots: >= 1 }`, never a silent pass.
- [ ] 4.8. M8 — delete the guard's `describe` block → RED in the **other** file.
- [ ] 4.9. Record per row: the `git diff` hunk **with its line range**, the reddening test's
      name, and a failure-message excerpt. Apply each as a line-scoped hunk, never a
      file-wide `s///`. Revert each before the next.

## Phase 5 — Per-harness journey checks

- [ ] 5.1. Grok — `plugins/soleur/commands/{go,help,sync}.md` each carry a frontmatter
      `name:` matching their stem; `bun test plugins/soleur/test/grok-inspect-contract.test.ts`
      passes.
- [ ] 5.2. Codex — `node scripts/codex-plugin-smoke.mjs` passes. This is the only mechanical
      proof in the repo that a per-harness `skills` root registers; run it, do not reason.
- [ ] 5.3. Devin — `bun test plugins/soleur/test/devin-plugin.test.ts` passes, and the PR
      body states plainly that this is an **on-disk existence check, not a discovery
      probe**. No Devin equivalent of the Codex smoke test exists.
- [ ] 5.4. Command Center — confirm `plugins/soleur/skills/go/SKILL.md` still exists and no
      file under `apps/web-platform/` is modified.

## Phase 6 — ADR-224

- [ ] 6.1. Re-derive the next free ADR ordinal against **freshly-fetched `origin/main`**
      (provisional today: ADR-224, with ADR-223 the highest claimed across all 83
      `refs/remotes/origin/*`). Re-check immediately before merge.
- [ ] 6.2. Write ADR-224 — harness-neutral component-placement rule. **Harness-qualify every
      clause**: Claude Code's `skills` key is additive; Codex's measured behaviour is
      replace-default. Do not amend ADR-215, whose §Verification records the opposite
      semantics and would self-contradict.
- [ ] 6.3. Append a one-line pointer from ADR-215 §Consequences to ADR-224. Leave ADR-215's
      `98` figures at lines 34 and 49 **unchanged**.

## Phase 7 — Battery and follow-ups

- [ ] 7.1. `bash scripts/test-all.sh` green, satisfying AC10: `bun --version` equals
      `.bun-version` **and** the bun shard reports a non-zero executed-test count, both
      captured in the PR body.
- [ ] 7.2. File the (a′) follow-up issue: build `scripts/devin-plugin-smoke.*` mirroring
      `codex-plugin-smoke.mjs`; once `devin/skills/` is **proven** to register, delete the
      three shared shims and land the already-measured reverts (README 98→95, budget
      2442→2400, marker fleet 67→65, the smoke-script comment) plus the repoint of the three
      `apps/web-platform` dispatch sites.
- [ ] 7.3. File one `type/chore` issue for the stale literals: `model.c4:117`
      ("61 workflow skills"), `docs/_data/skills.js:11` ("4 categories, 91 skills"),
      `knowledge-base/engineering/grok-onboarding.md:62` ("67 Soleur agents" against 68).
- [ ] 7.4. Verify AC1–AC12. AC13 is post-merge and operator-facing.
