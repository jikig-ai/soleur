# Tasks — feat-one-shot-8287-operator-bootstrap

Derived from `knowledge-base/project/plans/2026-09-18-feat-ship-operator-bootstrap-wizard-merge-danger-plan.md`.
Phase numbering matches the plan's `## Implementation Phases`. Decision ids (D1-D14) and guard ids
(Guard 1-5) refer to that plan.

> **Superseded in part.** A seven-agent plan review produced `## Plan Review Revisions (R1–R40)` at
> the end of the plan. Tasks below that implement a cut mechanism are struck through in effect —
> read the plan's revisions block before starting. The cut set: the inlined-library/`STAGES`
> architecture and Guard 2 (R6), Guard 1 and the `drain-prs` enum bundle (R9), Guard 5 (R10), three
> of the four characterization suites (R11), the `provision-github.sh` hoist (R12),
> `verify-bootstrap-run.sh --self-test` (R13), `predecessor-wiring.test.sh` as a file (R14), the new
> AGENTS rule (R15), the `Door:` field and the merge hold (R7), and the secret-scrub trap (R5).
> Two ordering corrections also apply: the description-budget bump moves to **Phase 0** (R31,
> otherwise CI is red from Phase 3 on), and the folded-in wiring assertions move to **Phase 7** (R32).
> D2's carve-out set is replaced by a three-class set in which the destructive-write ack takes **no**
> skip variable (R8).


## Phase 0 — Preconditions (no code)

- [ ] 0.1 Confirm `plugins/soleur/skills/flag-bootstrap/` holds only `SETUP.md` and is not a live skill (D5).
- [ ] 0.2 Re-measure the skill-description budget using `components.test.ts`'s own path; fix the bump to the measured delta, not the 54-word estimate (D6).
- [ ] 0.3 Re-derive the free ADR ordinal across every `origin/*` ref, not just `main`. Provisional is ADR-226 (D14).
- [ ] 0.4 Read `scripts/lint-shell-trace-credential-refusal.py` `:74-76`, `:125-128`, `:142-150` in full before touching any prologue (Guard 5).
- [ ] 0.5 Confirm `shellcheck` availability. Measured absent on this host — if still absent, `bash -n` is the syntax gate and no suite may prescribe `shellcheck`.
- [ ] 0.6 Capture the current `--dry-run` stdout of all four `provision-*` scripts as the pre-refactor reference, running from a directory outside the repository.

## Phase 1 — Characterization first (green against today's scripts)

- [ ] 1.1 Write the synthesized DPA fixture register (column 8 `Status` = `dpa-signed`). Required: the DPA gate precedes the `--dry-run` branch in all four and the live register is empty, so every script exits 3 without it.
- [ ] 1.2 `provision-cloudflare/test/provision-cloudflare-characterization.test.sh` — golden `--dry-run` stdout, byte-for-byte.
- [ ] 1.3 `provision-doppler/test/provision-doppler-characterization.test.sh` — golden `--dry-run` stdout.
- [ ] 1.4 Hoist the `if $DRY_RUN` branch in `provision-github.sh` above the four network calls at `:73`, `:85`, `:93-94`, `:100-101`, or emit unresolved placeholders on that path.
- [ ] 1.5 `provision-github/test/provision-github-characterization.test.sh` — golden `--dry-run` stdout, now offline.
- [ ] 1.6 `provision-hetzner/test/provision-hetzner-characterization.test.sh` — golden `--dry-run` stdout with an `hcloud` stub on `PATH`.
- [ ] 1.7 Pin in every suite: the duplicate teardown a successful `--dry-run` emits; that `--help` and bad-argument exits print **no** teardown; that DPA-gate exits (rc 3) **do**.
- [ ] 1.8 Every suite runs with `cwd` outside the repository. Confirm `bash scripts/test-all.sh` reports no live-repo write.
- [ ] 1.9 All four suites green against unmodified scripts. This is the safety net — do not proceed without it.

## Phase 2 — The library, test-first

- [ ] 2.1 Write `plugins/soleur/test/operator-script.test.sh` **before** the library, driving Guards 3 and 4 red first.
- [ ] 2.2 Encode Guard 3's six mutation rows and both harness rows.
- [ ] 2.3 Encode Guard 4's five mutation rows and both harness rows, including the reorder row (TTY check moved after the read) and the no-TTY case under `timeout`.
- [ ] 2.4 Create `plugins/soleur/scripts/lib/operator-script.sh`. Line 1 is `# shellcheck shell=bash`; header states sourcing preconditions and names every call site (D3).
- [ ] 2.5 Extract stage progress, preflight and closing summary from `apps/cla-evidence/infra/bootstrap.sh:57-61,76-88,98-103,110,307-315`.
- [ ] 2.6 Extract the `.env` upsert from `linkedin-setup.sh:443-452`, **corrected to exact-key matching** (the source's `grep -v '^PREFIX_'` is a prefix match and is correct only for a fixed key block).
- [ ] 2.7 `chmod 600` lands **after** the `mv`, never before — `mv` replaces the inode and its mode.
- [ ] 2.8 Extract the stdin-only GitHub secret write and the **separate** argv variable write from `provision-operator-digest-repo.sh:69-96`. The variable helper refuses secret-shaped names.
- [ ] 2.9 Implement the secret registry and the output-scrub trap; stages never print a registered value.
- [ ] 2.10 Implement `open_url` as additive-only (print first, open best-effort, never branch on exit code) per `linkedin-setup.sh:322-333`, adding the **new** WSL arm (`wslview` / `explorer.exe`).
- [ ] 2.11 Implement the total non-interactive path: every prompt has a named skip variable; no TTY plus unset variable emits `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` and exits **64** before reading (D2).
- [ ] 2.12 Implement the run ledger (one JSON line per stage, before and after; names never values) and `SOLEUR_BOOTSTRAP_LIB_MISSING` hard-exit.
- [ ] 2.13 `umask 077` set inside the library.
- [ ] 2.14 Attribution comment on the library.

## Phase 3 — `operator-bootstrap`

- [ ] 3.1 `plugins/soleur/skills/operator-bootstrap/SKILL.md` — the four-step process (scope, map each journey, author stages, verify and hand off), the two carve-outs, the "never hand-edit above the marker" invariant, and the attribution comment.
- [ ] 3.2 `plugins/soleur/skills/operator-bootstrap/template.sh` — library region, `STAGES` marker, one example stage, generated-file header marker.
- [ ] 3.3 `plugins/soleur/skills/operator-bootstrap/scripts/verify-bootstrap-run.sh` with `--self-test` and `--ledger <path> --last`.
- [ ] 3.4 `plugins/soleur/skills/operator-bootstrap/test/regeneration-parity.test.sh` — Guard 2, five mutation rows and both harness rows.
- [ ] 3.5 `plugins/soleur/skills/operator-bootstrap/test/predecessor-wiring.test.sh` — the anti-orphan guard.
- [ ] 3.6 Confirm both new suites land on already-registered `SUITE_GLOBS` and that `bash scripts/lint-orphan-test-suites.sh` reports `0 orphaned` with no `scripts/test-all.sh` diff.

## Phase 4 — The proving consumer

- [ ] 4.1 Refactor `provision-hetzner.sh` onto the library.
- [ ] 4.2 Keep `read -rs` at `:123` **in this file** — `incident/test/redact-sentinel.test.sh` pins it as a required member (D12).
- [ ] 4.3 Duplicate the xtrace-refusal and TLS-strip prologue **above** the `source` line — a `source` line is a counted command under `PROLOGUE_MAX_CMDS = 0` (Guard 5).
- [ ] 4.4 Keep the trap installed below argument validation so usage errors still print no teardown.
- [ ] 4.5 Assert the Phase 1 golden is byte-identical after the refactor.
- [ ] 4.6 Run `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` and confirm Test 24 still sees `provision-hetzner.sh`.

## Phase 5 — `operator-rephrase` and discoverability

- [ ] 5.1 `plugins/soleur/skills/operator-rephrase/SKILL.md` — cites `operator-digest/SKILL.md` §Register rather than restating it; states the delta (single message, synchronous, not bound by the digest's business-consequence rule); names ASD-STE100 as influence with the checkable parts only (D13); no vocabulary source in v1; attribution comment.
- [ ] 5.2 Rewrite `commands/help.md:73-74` to group skills by prefix family, in **all three** harness blocks (Claude, Devin, Grok).
- [ ] 5.3 Add a "start here" line naming `/soleur:go`, and name both new skills.
- [ ] 5.4 Add the `operator-rephrase` back-reference line to `operator-digest/SKILL.md`.

## Phase 6 — Rules, routing parity, naming correction

- [ ] 6.1 `plugins/soleur/skills/brainstorm-techniques/references/phase-boundaries.md` — the ordered five-option tree body, with attribution comment.
- [ ] 6.2 One new Communication rule in `AGENTS.rules.md` (ordering, Continue ruled out first, `/compact` last, cross-referencing the three existing ids, pointing at the reference file) plus its `AGENTS.md` index pointer.
- [ ] 6.3 Amend `hr-multi-step-post-merge-bootstrap-script` (292 bytes) and `hr-ship-message-no-operator-checklist` (361 bytes) to name `soleur:operator-bootstrap`. Ids untouched; trim from `**Why:**` narrative if needed.
- [ ] 6.4 Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` after every rules edit. Baseline `B_ALWAYS=42640` against 46000.
- [ ] 6.5 Run `python3 scripts/lint-rule-ids.py`.
- [ ] 6.6 Add `"drain-prs"` to `enums/go-routes.json`; update the `8` literals at `parse-label.test.sh:111` and `:113` to `9`; add one `drain-prs` golden row to `tasks/go-routing.jsonl` (D4).
- [ ] 6.7 Implement Guard 1 in `plugins/soleur/test/go-routing-golden-path.test.ts` — census parsed from the gated block, five mutation rows, both harness rows, plus the gated-block byte-identity assertion against `origin/main`.
- [ ] 6.8 Correct the `<naming_conventions>` opening statement in `skill-creator/references/skill-structure.md` — minimal, to avoid colliding with #8290 (D7).

## Phase 7 — Ship-side changes

- [ ] 7.1 Add the `## Merge Danger` section to the Phase 6 body template at `ship/SKILL.md:1773` and `:1876`, with the three undo-first fields (D8).
- [ ] 7.2 Quote `deployment-verification-agent`'s rollback line for `**Undo:**`; write `none produced` when review ran degraded.
- [ ] 7.3 Add the evidence-tier text, cross-referencing `ship/SKILL.md:138-175`, `review/SKILL.md:438-450` and `qa/SKILL.md:191,208` rather than competing with them.
- [ ] 7.4 Add the Phase 5.5 hold for `one-way` or blast radius ∈ {`prod-data`, `money`}, reusing the existing gate machinery (D9).
- [ ] 7.5 Name `soleur:operator-bootstrap` at the point `ship` generates an operator step — the predecessor wiring.
- [ ] 7.6 Verify no bullet in the new section leads with a Group-A/B/C/D deny token and that the `Filed:` parse is unperturbed.

## Phase 8 — Manifest, docs, ADR, evidence

- [ ] 8.1 Author `ADR-226-generated-operator-scripts-non-interactive-by-default.md` with the seven Decision points and Alternatives A-E (D14). Re-derive the ordinal first.
- [ ] 8.2 Add the `mattpocock/skills` entry to `plugins/soleur/NOTICE` with upstream URL, "Used in:", "Portions adopted:" and full MIT text.
- [ ] 8.3 Run the `hr-third-party-content-grep-on-undertaking` diff grep before PR-ready.
- [ ] 8.4 Add two `SKILL_CATEGORIES` entries to `plugins/soleur/docs/_data/skills.js`.
- [ ] 8.5 Run `soleur:release-docs`: `bash scripts/sync-readme-counts.sh`, the `plugin.json` description, `npx @11ty/eleventy` verification. `README.md:14` moves from 98 to 100 skills.
- [ ] 8.6 Bump `SKILL_DESCRIPTION_WORD_BUDGET` at `components.test.ts:21` by the measured delta, annotated in the established form.
- [ ] 8.7 Capture the three eval-gate evidence outputs (`--check`, the empty `git diff origin/main -- plugins/soleur/commands/go.md`, and the real-run ungateable-no-op verdict) for the PR body.
- [ ] 8.8 Run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 8.9 Execute every mutation row in all five guard matrices, observe RED, and record the results table for the PR body.
- [ ] 8.10 File the deferred issue for the three remaining provision refactors, with re-evaluation criteria and the sequencing note.
- [ ] 8.11 Comment on #8289 adding the `kb-glossary` scope line for `operator-rephrase`.
- [ ] 8.12 Run `bash scripts/test-all.sh` and confirm it exits 0.

## Notes

- `decision-challenges.md` in this directory carries three User-Challenges (DC-1 rename, DC-2 ASD-STE100 narrowing, DC-3 scope reduction). `ship` Phase 6 renders them and files one `action-required` issue.
- `plugins/soleur/commands/go.md` and `plugins/soleur/lib/workflow-fidelity.ts` are deliberately **not** edited; both non-edits are stated in the PR body with the named invoker.
