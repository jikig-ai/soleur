# Tasks — feat-one-shot-10017-mktemp-tmp-leak

Derived from `knowledge-base/project/plans/2026-10-12-fix-mktemp-tmp-leak-plan.md`.
Issue: #10017 (carries `Closes #9341` per decision-challenges ruling).

## Phase 1 — Authoritative census + disposition ledger

- [ ] 1.1 Extend `scripts/lint-trap-tempfile-ownership.py` with a
  population-list mode (`--census-files`) printing every class-b
  (`*.sh`, `mktemp`, zero `trap … EXIT|RETURN`) and rule-e member path,
  derived from the same `census_all`/`Tree` pass that counts them.
- [ ] 1.2 Extend `scripts/lint-trap-tempfile-ownership.test.sh` for the
  new mode — list-count == `--census` count; a member fixture appears;
  an escape-annotated member still lists (census counts escapes).
- [ ] 1.3 Run the listing scoped to `plugins/soleur/**`, `scripts/**`,
  `.claude/hooks/**` (plus `tests/scripts/lib/git-data-birth-readiness-gate.sh`
  for direction 2) and write the disposition ledger to
  `knowledge-base/project/specs/feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`
  — per file: run-context, disposition, basis.
- [ ] 1.4 Mandatory ledger rows: the six #9341 candidates; #6752's three
  sites (`scripts/learning-retrieval-bench.sh`, `scripts/weekly-analytics.sh`,
  `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`);
  landmines `.claude/hooks/lib/session-state.sh` and
  `apps/web-platform/infra/workspaces-cutover.sh` = `do-not-touch` with
  #6752's verbatim rationale.

## Phase 2 — Session-scoped trap sweep

- [ ] 2.1 For every ledger row dispositioned `trap-*`: add the owning
  trap per ADR-129 (EXIT at top level; RETURN in functions; extend an
  existing cleanup function — never a second `trap … EXIT`; parent-scope
  registration for `$( )` helpers; provably-absolute `rm` operand).
- [ ] 2.2 Remove any `lint-trap-ownership: ok` annotation the fix makes
  stale; add the annotation only where the disposition is
  `annotate-bounded`.
- [ ] 2.3 Per fixed file, extend its own `*.test.sh` with a residue
  assertion (private `TMPDIR`, zero new base entries; owning EXIT trap
  placed BEFORE `source test-helpers.sh`).
- [ ] 2.4 Register runnable fixed producers as leaves in
  `tests/scripts/test-scratch-residue.sh` where the harness supports it.

## Phase 2b — Prose-instructed allocation sweep (plan amendment)

- [ ] 2b.1 Enumerate `mktemp`-instructing lines in `plugins/soleur/**/*.md`
  and `.claude/hooks/*.md` into the ledger's prose section with a
  disposition each (`add-cleanup-instruction` / `bounded-persistence`).
- [ ] 2b.2 Apply the `add-cleanup-instruction` amendments (post-consumption
  `rm`, or paired `trap … EXIT` where the artifact is same-call); keep every
  fenced example's existing trap guidance intact.

## Phase 3 — `rung2-archive.*` producer fix

- [ ] 3.1 Probe: verify a `RETURN` trap set inside a function fires when
  the function runs under `$( )` (the :1912 call shape).
- [ ] 3.2 `tests/scripts/lib/git-data-birth-readiness-gate.sh:1440` —
  add self-disarming `trap … RETURN` (`trap - RETURN` inside the
  handler) with `/*`-rooted operand assertion before `rm -rf "$_tmp"`;
  cover all return paths.
- [ ] 3.3 Drop the `.soleur-owned` marker write; rewrite the
  `lint-trap-ownership: ok` comment so it no longer claims the dir
  deliberately outlives the call.
- [ ] 3.4 Extend `tests/scripts/test-git-data-birth-readiness-gate.sh`
  with a no-residue assertion on the hash path (success AND error arms).

## Phase 4 — Belt-and-braces residual reaper

- [ ] 4.1 Create `scripts/soleur-tmp-purge.service` +
  `scripts/soleur-tmp-purge.timer` (optional user units, daily
  `soleur-tmp-purge.sh --apply` + `--drain`, mirroring
  `tmpfs-guard.{service,timer}`).
- [ ] 4.2 Create `scripts/tmp-leak-census-probe.sh` (Check-10-safe probe:
  prints `ratchet-ok` iff `--census` ≤ highwater).
- [ ] 4.3 Extend runbook
  `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`
  — install steps for the new units + the evaluated systemd-tmpfiles
  alternative note: `e`/`d` accept globs but `e` cleans a matched dir's
  *contents*, not the top-level entry shells — the literal route cannot
  express the count-shaped fix, and a bare `d /tmp`/`e /tmp` sweep is
  the rejected shared-base trade; the purge timer is the belt.

## Phase 5 — Ratchet + verification

- [ ] 5.1 Decrement `scripts/lint-trap-tempfile-ownership.highwater` by
  the exact number of files leaving the class-b population.
- [ ] 5.2 `python3 scripts/lint-trap-tempfile-ownership.py
  --check-highwater` green; print final census count for the PR body.
- [ ] 5.3 Verify zero edits to the two landmine files
  (`git diff --quiet origin/main...HEAD -- <paths>`).
- [ ] 5.4 PR body: `Closes #10017`, `Closes #9341` (per
  decision-challenges ruling), `Refs #6752 #6760 #7004`; `## Changelog`
  section.
