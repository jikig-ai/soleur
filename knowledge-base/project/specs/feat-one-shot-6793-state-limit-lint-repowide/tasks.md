---
issue: 6793
lane: single-domain
plan: knowledge-base/project/plans/2026-07-22-chore-gh-search-state-limit-lint-repowide-plan.md
---

# Tasks — extend gh `--search`/`--state` lint repo-wide + `-L`/`--limit` truncation coverage

Derived from the finalized (deepened) plan. Closes #6793. Net issue flow −1.
**Re-derive every call-site line number at execution time — the plan warns line numbers drift.**

## Phase 0 — Preconditions

- [ ] 0.1 Re-run the extractor regex across the D1 allowlist to re-derive the current
  violation set: `git grep -nE 'gh (pr|issue) list\b[^`\n]*--search'` over
  `plugins/soleur/{skills,commands,agents}/**`, `scripts/**/*.sh`,
  `plugins/soleur/skills/**/scripts/*.sh`, `.claude/hooks/**/*.sh`, `.openhands/hooks/**/*.sh`,
  `.github/workflows/**/*.{yml,yaml}`, `.github/actions/**/*.{yml,yaml}`,
  `knowledge-base/engineering/operations/runbooks/**/*.md` — minus `--state`/`--limit`-carrying
  lines and `#`-comment lines. Compare against the D4 list.
- [ ] 0.2 Confirm `plugins/soleur/skills/one-shot/SKILL.md:55` still holds the
  `linked:issue #<N>` probe verbatim (the D2(b) exemption target).
- [ ] 0.3 Confirm `REPO_ROOT = resolve(PLUGIN_ROOT, "../..")` resolves to repo root from
  `plugins/soleur/test/`.

## Phase 1 — Extend the lint (RED first) — `plugins/soleur/test/components.test.ts`

- [ ] 1.1 Add `REPO_ROOT` and a D1 INCLUDE-glob corpus builder: multi-glob scan (skills, commands,
  agents `.md`; repo-root `scripts/*.sh` + `skills/**/scripts/*.sh`; hooks; workflows/actions
  `*.{yml,yaml}`; runbooks), dedup by path, `!**/*.test.sh` guard, per-file surface-type tag.
- [ ] 1.2 Extend the extractor to skip comment lines (first non-space `#`) for `.sh` and
  `.yml`/`.yaml` surfaces (markdown fence tracking unchanged). Keep the line-bounded capture
  `\bgh (?:pr|issue) list\b[^`\n]*` — NEVER newline-spanning (launder-by-neighbor, 2026-07-20).
- [ ] 1.3 Add `findUnlimitedProbes` (D2): flag search probes lacking `-L`/`--limit` UNLESS
  (a) existence-drill (`.[0]`/`// empty`/`first(`/`--limit 1`) AND no post-search `select(`/narrowing,
  OR (b) `--search` matches the bounded shape `linked:issue\s+#`. No waiver framework.
- [ ] 1.4 Add synthesized negative controls (`cq-test-fixtures-synthesized-only`), written failing
  first (`cq-write-failing-tests-before`):
  - flags a stateless probe / a no-limit enumeration probe;
  - **D2-soundness control:** a `select`-after-search probe WITH a trailing `.[0]`/`// empty` is FLAGGED;
  - accepts a pure existence drill (no narrowing), `--limit 1`, explicit `-L`, and the `linked:issue #<N>` shape;
  - accepts an unbounded query that merely contains a similar token only when it truly has `-L` (anchor on `linked:issue\s+#`).
- [ ] 1.5 Widen corpus assertions to the repo-wide surface: "both classes represented" (markdown
  inline+fenced subset) + "wider than plugin-local" (scanned file count > `discoverSkills().length`).
  Do NOT add a post-exemption "≥1 unlimited representative" assertion (self-contradiction).

## Phase 2 — Bring genuine violations into compliance (GREEN)

Re-derive lines at execution; apply the minimal explicit-flag edit:

- [ ] 2.1 `scripts/rule-prune.sh` — add `--state all` + generous `-L` to the dedup probe.
- [ ] 2.2 `scripts/content-publisher.sh` — add generous `-L` (select-after-truncation fail-open fix).
- [ ] 2.3 `plugins/soleur/commands/sync.md` — make the described dedup `--state open` explicit.
- [ ] 2.4 `plugins/soleur/skills/ux-audit/SKILL.md` — add explicit `-L` to the hash-dedup probe.
- [ ] 2.5 `plugins/soleur/agents/engineering/review/deployment-verification-agent.md` — add
  `--state all` + `-L` to the incident-signal probe.
- [ ] 2.6 `knowledge-base/engineering/operations/runbooks/inngest-server.md` — add `--state all`
  + `-L` to the `head:bot-fix/` probe.
- [ ] 2.7 `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — add explicit
  `--state` (the `$CANONICAL_TITLE` dedup) and `-L` (the `created:<window>` enumeration).
- [ ] 2.8 Verify `git diff --exit-code -- plugins/soleur/skills/one-shot/SKILL.md` shows NO change
  (byte-identical fixture preserved via the D2(b) exemption).
- [ ] 2.9 `findStatelessProbes(corpus)` and `findUnlimitedProbes(corpus)` both return `[]`.

## Phase 3 — Corpus + docs

- [ ] 3.1 In-code comment block documenting each detector's assertion dimension (state presence /
  state non-contradiction / limit-presence-or-existence-drill-without-narrowing / bounded-shape
  exemption) so prose-in-code matches the checks (2026-05-16 dimension-drift discipline).

## Verification protocol (mutation battery — /work, not a merged post-condition)

Baseline un-mutated suite GREEN first; each mutation must turn the suite RED:
- [ ] M1 revert capture to newline-spanning `[^`]*` → launder test RED.
- [ ] M2 drop the narrowing clause → D2-soundness control GREEN-when-should-be-RED; drop the
  existence/bounded exemptions → false-positives on safe probes.
- [ ] M3 narrow scan back to `skills/**/*.md` under PLUGIN_ROOT → "wider than plugin-local" RED.
- [ ] M4 drop `findUnlimitedProbes` from the corpus offender assertion → unlimited-class RED.
(M1/M2/M4 are also encoded as permanent synthesized negative-control tests.)

## Ship gate

- [ ] `bash scripts/test-all.sh` (or `cd plugins/soleur && bun test test/components.test.ts`) GREEN.
- [ ] PR body uses `Closes #6793` (net issue flow −1). Do NOT reference `#5095`/`#5097` as closed.
