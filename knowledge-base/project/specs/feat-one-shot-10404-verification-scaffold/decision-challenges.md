# Decision Challenges — #10404 verification-scaffold

Persisted because this plan ran headless (one-shot pipeline on Devin CLI — no AskUserQuestion).
Per the pipeline contract, technical forks are ruled in-process by the CTO role
(`plugins/soleur/agents/engineering/cto.md`, Rule interface) and recorded here.

## Decision Classes

| # | Decision | Class | Status | Ruling |
|---|----------|-------|--------|--------|
| 1 | Phase split: single PR (audit + scaffold) vs two PRs | technical | ruled | Single PR — Ruled by CTO agent, 2026-10-21 |
| 2 | Delivery surface: hooks only / CI only / both | technical | ruled | Both — hooks for the agent surface, CI as the load-bearing floor |
| 3 | Advisory-first mechanics | technical | ruled | Per-guard mode flag (`advisory` default) + `continue-on-error` CI jobs; promotion is a one-line flip per artifact |
| 4 | v1 guard set | technical | ruled | secret-scan, commit-on-main, block-stash, orphan-test (audit confirms; block-rm-rf as audit-permitted stretch) |
| 5 | Extraction model: verbatim copies vs generic templates | technical | ruled | Templates — every candidate carries Soleur couplings; `precommit-guard.sh` is the sole near-verbatim emit |
| 6 | Audit artifact location | technical | ruled | `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md` + machine `references/guards.tsv` |
| 7 | Bite-proof scope | technical | ruled | Per-guard inject→observe→revert in a TMPDIR worktree, mirroring constraint-scaffold, scaled to non-compiling guards |
| 8 | User-brand threshold | technical | ruled | `single-user incident` → `requires_cpo_signoff: true`; CPO ran in-process at plan Phase 2.5 |
| 9 | CPO sign-off at plan time | operator (brand) | surfaced | `single-user incident` threshold sets `requires_cpo_signoff: true`; plan-time CPO assessment ran in-process — operator countersignature cannot be collected headless; `ship` renders this row |

## CTO rulings (verbatim blocks)

### Item 1 — Phase split

Decision: Single PR — audit document, guard templates, generator, tests, and registrations
ship together.

Rationale: (a) The audit's only consumer is the scaffold it selects for — landing it alone
leaves an unactioned artifact on `main` and splits a single logical change across two review
cycles. (b) Precedent: every closed sibling of epic #10397 shipped exactly one PR (#10401→
#10727, #10402→#10735, #10403→#10738). (c) The audit doc is co-versioned with the manifest
the generator consumes; two PRs would let them drift between merge and follow-up. (d) Size is
bounded: ~1 audit doc + ~1 generator + ~6 templates + ~4 test suites + registration edits —
comparable to constraint-scaffold's single-PR landing (PR #5770 lineage).

Rejected alternatives: Two-PR split (audit first, scaffold second) — rejected: splits an
atomic design decision, second PR loses the "why this set" context in review.

Dissent: The issue body permits a split "if the audit output is large"; if the audit balloons
past ~500 lines of per-entry rationale, the split remains available as a work-phase escape,
recorded here rather than decided blindly.

### Item 2 — Delivery surface

Decision: Both surfaces — emit `.claude/hooks/` PreToolUse hooks (agent surface) AND a
`.github/workflows/` CI job set (load-bearing floor).

Rationale: The issue asks for "hooks/CI" (both). The hook surface is what makes the guard
fire inside the user's agent sessions — the plugin user's actual workflow — while CI is the
load-bearing floor for pushes and non-agent commits (the repo's own
`git-commit-secret-scan.sh` header: "CI re-scans on every push as the load-bearing gate").
Either alone leaves a hole: hooks miss humans/CI; CI misses the pre-commit moment.

Rejected alternatives: Hooks-only (no floor for non-agent commits); CI-only (misses the
agent-session surface that is the plugin's reason to exist).

Dissent: None material — dual-surface matches both the issue text and the repo's own
two-layer deployment of the same guards.

### Item 3 — Advisory-first mechanics

Decision: Per-guard mode flag with `advisory` default: hooks emit a visible warning and
`permissionDecision: allow` (secrets guard: `ask`) and CI jobs carry
`continue-on-error: true`; promotion = flip the mode line / drop `continue-on-error`,
documented in the emitted README. A `--mode enforce` install flag exists for repos that want
blocking from day one, but the DEFAULT is advisory.

Rationale: `wg-dark-launch-deploy-gates` (AGENTS.rules.md:80) requires deploy-gating checks
to ship non-blocking and be observed before they gate. Learnings
`2026-09-23-arming-an-advisory-gate...` (promotion re-reads lenient branches as bypasses) and
`2026-07-16-advisory-first...` (advisory must be mechanically defined) require the advisory
posture to be a real, testable behavior — warn-and-allow with the SAME detection predicates
as enforce — not a weakened guard. Secrets get `ask` not silent `allow`: a secret-shaped
finding surfaced-and-decided beats silently allowed, and `ask` is still non-blocking.

Rejected alternatives: (a) Deny-by-default hooks — violates advisory-first for the surface
most likely to block an agent mid-session. (b) Two artifact sets (advisory + enforce
templates) — doubles maintenance for a one-line semantic. (c) `ask` everywhere — noisy on
low-severity guards; reserved for the secret-scan.

Dissent: A purist read of "advisory-first" could argue ALL hooks should warn-and-allow with
no `ask`; `ask` was chosen only for the highest-severity guard where a miss is a credential
leak.

### Item 4 — v1 guard set

Decision: v1 = `secret-scan` (hook + CI + default `.gitleaks.toml` emitted only when absent),
`commit-on-main` (hook wrapper around an emitted guard script), `block-stash` (hook),
`orphan-test` (CI + runner script), plus `block-rm-rf` only if the audit confirms a
self-contained generic arm. Everything else is audit-classified `v2` or `soleur-coupled`.

Rationale: AC floor = "at least the secret-scan + orphan-test + commit-guard set".
`plugins/soleur/scripts/precommit-guard.sh` is already self-contained ("Self-contained by
design: no jq, no .claude/hooks/lib vendoring" — its own header) and ships in the plugin with
`scripts/lib/wrapper-boundary.sh` — the commit-guard is a near-verbatim emit.
`block-stash` is a ~15-line regex arm (`guardrails.sh:471-486`) trivially standalone.
`lint-trap-tempfile-ownership.py` (1603 lines, SOLEUR_SCRATCH_SESSION_ROOT-keyed) and the
full `lint-orphan-test-suites.sh` (1276 lines, six Soleur registration surfaces) are
generic-after-heavy-extraction — the orphan-test v1 ships a SCOPE-REDUCED generic variant
(see Item 5), not a port.

Rejected alternatives: (a) Ship the full ~40-lint corpus — scope explosion; most are
Soleur-coupled (legal registers, doppler descriptions, rule-id budgets). (b) Defer
orphan-test to v2 — the AC names it in the minimum set.

Dissent: `block-rm-rf` is the audit's call, not the issue's; the AC minimum does not require
it. Kept conditional, not committed.

### Item 5 — Extraction model

Decision: Templates, not copies — `references/guards/*.template` are standalone generic
implementations (self-contained single files, no `lib/hook-input.sh`, no `emit_incident`, no
KB pointers), informed by but not vendored from the repo sources. Exception:
`precommit-guard.sh` + `lib/wrapper-boundary.sh` emit near-verbatim because they were
already designed self-contained.

Rationale: Every candidate carries Soleur couplings the census measured
(`lint-orphan-test-suites.sh` 16 hits keyed on `scripts/test-all.sh`/`TEST_GROUP`/
`apps/web-platform/infra/`; the hook corpus depends on `lib/hook-input.sh` +
`lib/incidents.sh`). Verbatim copy ships those couplings into user repos where they
dead-reference. Templates also carry the provenance problem forward honestly: the audit doc
maps template → repo source, and a `test/parity.test.sh`-style guard (constraint-scaffold
precedent) pins template↔source predicate parity where it matters.

Rejected alternatives: Verbatim vendoring (ships dead references); runtime library emission
(adds an install-footprint and a shared-lib drift surface for 3-5 guards).

Dissent: A template drift risk exists — the generic orphan-test variant could diverge from
the repo original's detection quality. Mitigated by recording expected-detection fixtures in
the skill's own test suite rather than asserting output equality.

### Item 6 — Audit artifact location

Decision: `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md`
(human doc: every `.claude/hooks/*.sh` non-test + `scripts/lint-*` entry classified
generic / generic-after-extraction / soleur-coupled with one-line rationale) plus
`references/guards.tsv` (machine manifest: name, surfaces, template, mode default, deps,
source-file provenance) that the generator iterates.

Rationale: Co-versioned with the skill that consumes it; ships to plugin users so "why is
X not included" is self-documenting; satisfies AC1 durably (committed, reviewable).

Rejected alternatives: `knowledge-base/` only (does not ship with the plugin; divorces the
audit from its consumer); manifest-only (loses the per-entry rationale AC1 requires).

Dissent: None.

### Item 7 — Bite-proof scope

Decision: Per-guard inject→observe→revert cycle inside a detached-HEAD worktree under
`$TMPDIR` (constraint-scaffold's bite-proof shape, adapted): stage a synthetic secret →
secret-scan fires; create an unregistered `*.test.sh` → orphan-check fires; feed a
`git commit` stdin payload on a main-checkout fixture → commit-guard denies/asks. No probes
are ever committed in the user's tree.

Rationale: constraint-scaffold's #8288/`SKILL.md` bite-proof establishes that an emitted
gate must be proven pass→fail→pass on the installed tree, and its TMPDIR-worktree technique
is directly reusable; the learning `2026-08-01` requires the proof to observe the guard's
behavior, not its presence.

Rejected alternatives: Presence-check only (file exists → vacuous); full per-guard
pass→fail→pass on the user's live tree (hook guards read stdin payloads, not files — the
fixture-stdin shape is what the repo's own `*.test.sh` files already use).

Dissent: None.

### Item 8 — User-brand threshold

Decision: `single-user incident` → `requires_cpo_signoff: true` in the plan frontmatter and
`soleur:engineering:review:user-impact-reviewer` at review time.

Rationale: The scaffold WRITES into a user's repository — a defective emit can wedge a
user's CI (workflow exposure) or a hole in the shipped secret-scan template can allow a
credential to land in a user's git history (data exposure). Same threshold
constraint-scaffold carried (`2026-06-30` learning header: "Threshold: single-user
incident").

Rejected alternatives: `aggregate pattern` — underestimates a per-user emit into a mutable
surface; `none` — contradicts the write-into-user-repo blast radius.

Dissent: None.

## Plan-review panel (in-process, 2026-10-21 — no Task substrate on Devin CLI)

5-agent eng panel (single-user-incident threshold) + named panel, run as sequential
in-process lenses over the plan file; spec-flow-analyzer ran at Phase 3 (findings
recorded in the plan's `## SpecFlow Findings`).

| Seat | Findings | Disposition |
|---|---|---|
| dhh-rails-reviewer | Plan mirrors constraint-scaffold's proven generator/template/bite-proof shape — convention-following. Flag surface (`--target/--guards/--all/--mode/--dry-run/--list/--uninstall/--headless`) is on the generous side but each flag maps to an AC; no mechanism answers no ask. | no change |
| kieran-rails-reviewer | P1: SpecFlow #1 stamped the per-repo default branch into emitted `precommit-guard.sh` while AC11 asserted `cmp` byte-parity with the plugin source — the canonical script hardcodes `main|master` (line 107), so stamping breaks the anchor. P2: `jq` is not guaranteed on a Claude Code user's host; `node` is. | applied — `@DEFAULT_BRANCHES@` placeholder with one-hunk parity (renders byte-identical under `main|master`); node-first/jq-fallback merge |
| code-simplicity-reviewer | Per-mechanism check against the Scope Check ask list: every mechanism maps to an asked or guard-required item; `--all` is justified day-one because guards.tsv ships v2 rows; `--uninstall` justified by the User-Brand Impact warn-noise path. No cut candidates. | no change |
| architecture-strategist | New trust boundary (emitted hook code executing on every Bash call in a customer session) is flagged and ADR-bound; `verificationscaffold` C4 component preserves modeling parity with `constraintscaffold`. Settings.json merge blast-radius is fail-closed. | no change |
| spec-flow-analyzer | 7 resolutions recorded in `## SpecFlow Findings` (Phase 3). | recorded |
| Named panel — cpo | User-facing capability; emitted VERIFICATION.md/README block carries the legibility contract; sign-off row rendered at ship (decision 9). | recorded |
| Named panel — cmo | content-strategy.md entry in scope (sibling pattern). | no change |
| Named panel — cto (devex) | Sibling-mechanism reuse minimizes install friction; no new concepts for operators. | no change |

| 10 | Mode mechanism: install-time `--mode advisory|enforce` flag vs runtime `SOLEUR_GUARDS_MODE` env var | technical | ruled | Ruled in-session, 2026-10-21: `--mode` install flag — mode is stamped into the emitted artifacts at install; a runtime env var is invisible to CI and ungreppable, the flag makes the mode a reviewable property of the emitted files |
| 11 | `SOLEUR_*` internal variable names inside the near-verbatim `precommit-guard.sh`/`wrapper-boundary.sh` emit | technical | ruled | Ruled in-session, 2026-10-21: rename to `VERIFICATION_*` at emit — cosmetic coupling that would mislead user-repo maintainers; byte-parity test compares against a rename-normalized copy |
