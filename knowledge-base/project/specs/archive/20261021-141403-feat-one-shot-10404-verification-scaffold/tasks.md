---
title: "Tasks — feat: verification-scaffold (issue #10404)"
plan: knowledge-base/project/plans/2026-10-21-feat-verification-scaffold-guardrail-corpus-plan.md
branch: feat-one-shot-10404-verification-scaffold
---

# Tasks

## Phase 1 — Audit + manifest (AC1, AC11 seed)

- 1.1 Enumerate corpus: `.claude/hooks/*.sh` non-test (55) + `scripts/lint-*`
  (excluding `.test.sh`, `.baseline.txt`, `.highwater`) via `git ls-files`.
- 1.2 Classify each entry `generic` / `generic-after-extraction` /
  `soleur-coupled` with one-line rationale citing concrete couplings.
- 1.3 Write `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md`.
- 1.4 Write `references/guards.tsv` (name, verdict, surfaces, template,
  default_mode, deps, source_files, v1|v2); v1 set: secret-scan, commit-on-main,
  block-stash, orphan-test (+ block-rm-rf only if self-contained per audit).

## Phase 2 — Templates + emitted docs (AC2, AC3, AC8)

- 2.1 `references/guards/secret-scan-hook.sh.template` — self-contained
  PreToolUse hook; `ask` on real findings, warn+allow (advisory) /
  deny+remediation (enforce) on tool errors; MODE= line.
- 2.2 `references/guards/commit-on-main-hook.sh.template` — thin wrapper over
  emitted `precommit-guard.sh`.
- 2.3 `references/guards/precommit-guard.sh.template` +
  `wrapper-boundary.sh.template` — near-verbatim emit of
  `plugins/soleur/scripts/precommit-guard.sh` + `scripts/lib/wrapper-boundary.sh`
  with a stamped default-branch config line (SpecFlow #1).
- 2.4 `references/guards/block-stash-hook.sh.template` — chain-boundary
  `git stash` regex; MODE= line.
- 2.5 `references/guards/orphan-test-check.sh.template` — `git ls-files
  '*.test.sh'` producer vs declared registration surfaces + reason-required
  exclusion manifest; zero-producer = loud fail, zero-suites = pass+notice.
- 2.6 `references/guards/verification-gates.yml.template` — CI jobs for
  secret-scan (gitleaks-action pinned by SHA) + orphan-test;
  `continue-on-error: true` in advisory.
- 2.7 `references/gitleaks.toml.template` — emitted only when absent.
- 2.8 `references/verification-readme.template` — installed inventory,
  advisory→enforce promotion per artifact (one-line flip + ≥1 clean run),
  uninstall, POSIX requirement.

## Phase 3 — Generator (AC2–AC7)

- 3.1 `scripts/verification-scaffold.sh`: flags `--target/--guards/--all/
  --mode/--dry-run/--list/--uninstall/--headless`; git-work-tree precondition
  (SpecFlow #2); mkdir lock in git common dir.
- 3.2 Emit engine: refuse overwrite (no `--force`); create `.claude/hooks/`,
  `.github/workflows/`, `scripts/verification/` when absent (SpecFlow #3);
  settings.json jq-merge (absent→create, malformed→refuse, dedupe on command
  string); repo-root workflow emit; marker-keyed doc block last.
- 3.3 Default-branch detection → stamp emitted config (SpecFlow #1).
- 3.4 TMPDIR-detached-worktree bite-proof per installed guard (TMPDIR-inside-
  repo refused; pass→inject-fail→revert-pass; logs kept on failure).
- 3.5 Trap-based self-cleanup armed before first write (exit-site table per
  Guard 5); `--uninstall` idempotent (SpecFlow #5).

## Phase 4 — Tests, registration, docs (AC1, AC4–AC12)

- 4.1 `test/generator.test.sh`: flags, refusals, re-run dedupe, settings merge,
  mode flips, malformed inputs, dir-creation, `--uninstall`, dry-run.
- 4.2 `test/bite-proof.test.sh`: per-guard pass→fail→pass on fixture repo
  (secret fixture, orphan suite fixture, main-checkout commit fixture).
- 4.3 `test/manifest.test.sh`: guards.tsv↔templates↔audit census (git-ls-files
  driven); precommit-guard template↔source one-hunk parity (placeholder
  renders to `main|master`); emitted-content grep
  (zero SOLEUR_/knowledge-base//plugins-soleur runtime refs; zero egress).
- 4.4 Registrations: `docs/_data/skills.js` ("Workflow"), cursor stub via
  `sync-cursor-name-map.ts`, `components.test.ts` budget bump (+~20),
  `regenerate-shard-manifest.py --incremental --write`, README 103→104,
  content-strategy entry.
- 4.5 `SKILL.md`: third-person description (~20 words), usage, modes, emitted
  table, agent-owns-gates model, POSIX note.
- 4.6 ADR (provisional ADR-295) + `model.c4`/`views.c4` `verificationscaffold`
  component; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Verify

- 5.1 Run touched shards (`scripts/test-all.sh` touched-shard exit gate):
  scripts shard + plugin test shard.
- 5.2 AC battery re-check (AC1–AC12); lint-guard-contract.py on the plan.
- 5.3 `git status` clean; plan + tasks + decision-challenges committed.
