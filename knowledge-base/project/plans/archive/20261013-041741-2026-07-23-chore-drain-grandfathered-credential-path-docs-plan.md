---
title: "Drain grandfathered resolvable-credential-path docs (12 files, 30 lines)"
type: chore
issue: 6868
branch: feat-one-shot-6868-drain-credential-path-docs
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
date: 2026-07-23
---

# 🔒 Drain grandfathered resolvable-credential-path docs

## Enhancement Summary

**Deepened on:** 2026-07-23
**Sections enhanced:** Premise Validation, Sharp Edges, Hypotheses (Network-Outage Deep-Dive), Research Insights
**Deepen gates run:** 4.5 network-outage (triggered on `SSH` substring → verified false-positive, telemetry emitted), 4.6 user-brand-impact (PASS — threshold `none` + scope-out), 4.7 observability (SKIP — pure-docs), 4.8 PAT-shape (PASS — clean), 4.9 UI-wireframe (SKIP — no UI surface)

### Key Improvements

1. **Live-probed the self-protection gotcha.** The plan's own proposed neutralized forms were run through the linter: `~/.ssh/`, `~/.ssh/id_<key>`, `~/.doppler/`, `~/.docker/`, and descriptive names all PASS; a `<placeholder>/`-prefixed bare Doppler-pointer filename still HARD-FAILS. This turned the "don't reintroduce the trigger in your own plan" warning from a caution into a validated replacement table.
2. **Caught the plan reintroducing the trigger.** The first draft of this plan itself hard-failed the linter on 3 lines (netrc/Doppler/Docker literals in prose) — fixed, and the plan now scans clean (AC4).
3. **Made the promotion decision (defer) with a concrete #6049 rationale** rather than leaving it open, keeping the IaC/ruleset blast radius out of the sweep PR.

### New Considerations Discovered

- The guard scans plans/specs (only `**/archive/**` excluded), so this PR's own plan + tasks.md are in scope — a class of self-inflicted CI failure unique to this issue.
- The repo-root Doppler project-pointer file is tracked, so the bare-filename resolvability is real, not theoretical.
- Family split of the 30 lines (re-derive exact per-line via the linter): SSH keys 13, Docker config 6, Doppler repo-root pointer 7, Doppler home config 2, netrc 2. Grouping edits by family keeps the neutralized wording consistent.

## Overview

Follow-up to the credential auto-attach hardening (#6864, which neutralized
`preflight/SKILL.md` Check 10 and added `scripts/lint-credential-path-literals.py`).

Claude Code's harness auto-attaches a file into model context whenever a
**locally-resolvable** filesystem path to an existing file appears in loaded
skill/doc prose (it renders as a "Read tool result"). A home-relative path to a
real credential file is therefore a live exfiltration trigger every time the doc
loads. The hot-path offender (`preflight/SKILL.md`, loaded on every ship) is
already neutralized, and the CI guard now **blocks any newly-changed doc** from
reintroducing the trigger (changed-files mode, wired into the `lint-bot-statuses`
job in `ci.yml`).

Historical docs are **grandfathered** — changed-files mode only flags what a PR
touches, exactly like `lint-infra-no-human-steps`. This plan drains the residual
population to zero in one deliberate sweep PR.

**Residual (guard full-scan, hard-fail tier):** 30 hard-fail lines across 12
tracked docs under `knowledge-base/`. **None load on a hot path** the way
`preflight/SKILL.md` did — this is lower-priority hygiene, not an active incident.
The exact line list is regenerable at any time with
`python3 scripts/lint-credential-path-literals.py` (the SSOT — line numbers drift,
so /work re-runs it rather than trusting a frozen list here).

Second, the issue asks whether to promote `lint-bot-statuses` to a **required
check**. This plan makes that decision (defer — see Non-Goals) and keeps it out of
the sweep PR's blast radius.

## Premise Validation

All premises cited by the issue were verified against the live repo:

- `scripts/lint-credential-path-literals.py` **exists** and runs; full-scan
  reports exactly **30 hard-fail lines across the 12 named files** (grep-count 31
  = 30 line-entries + 1 summary line) and **15 advisory** remote-host lines. The
  issue's per-file counts (6/4/3/3/3/2/2/2/2/1/1/1) reconcile exactly.
- The hardening PR **#6864 merged** to `main` (recent commit
  `94c3807a0 fix(preflight): neutralize resolvable credential-file paths in docs
  + add CI guard (#6864)`); `preflight/SKILL.md` Check 10 is neutralized.
- The CI guard is wired at `ci.yml` job `lint-bot-statuses` (step "Lint resolvable
  credential-file paths in docs (changed vs base)") in `--changed` mode.
- `lint-bot-statuses` is **NOT** in `scripts/required-checks.txt` nor the CI
  Required ruleset — the promotion is genuinely open.
- The repo-root Doppler project-pointer file **is tracked** (`git ls-files` hit),
  confirming the bare-filename resolvability the issue warns about is real.
- **No test asserts on the 12 offending docs' contents** (`git grep` over
  `*.test.*` / `test/**` for the doc paths returned nothing) — editing their prose
  is safe.
- **Self-protection probed live:** the plan's own proposed neutralized forms
  (`~/.ssh/`, `~/.ssh/id_<key>`, `~/.doppler/`, `~/.docker/`, descriptive names)
  all PASS the linter; a `<placeholder>/`-prefixed bare Doppler-pointer filename
  still HARD-FAILS (the bare-filename arm matches after any `/`). See Sharp Edges.

## Research Reconciliation — Spec vs. Codebase

No brainstorm or spec preceded this plan (direct one-shot entry). The premise
validation above found **zero divergence** between the issue body and repo reality
— all 12 files, the 30-line count, the guard wiring, and the recipe hold as
stated. No reconciliation table needed.

## User-Brand Impact

**If this lands broken, the user experiences:** a residual resolvable
credential-file path left in a cold historical doc. Because none of the 12 docs
load on a hot path (unlike the already-fixed `preflight/SKILL.md`), the practical
exposure is a dormant trigger that only fires if that specific historical
plan/spec/learning is ever loaded into a future agent session — the changed-files
guard already blocks any *new* introduction.

**If this leaks, the user's credentials are exposed via:** the harness
auto-attaching the real on-disk credential file (SSH private key, the Doppler CLI
token, the Docker config, a netrc file) into a model transcript when a doc naming
its resolvable path is loaded. This sweep removes the residual triggers so the
population reaches zero.

**Brand-survival threshold:** none — the residual is dormant hygiene debt with no
hot-path loader; the active incident vector (`preflight/SKILL.md`) is already
closed and the CI guard prevents regression. `threshold: none, reason: all 30
residual lines are in cold historical docs with no hot-path loader; the active
vector was already neutralized in #6864 and the changed-files guard blocks new
introductions.` (Edited files are `knowledge-base/**/*.md` docs — outside the
preflight Check-6 sensitive-path regex, which targets `apps/**` code + infra +
doppler workflow files — so no CPO sign-off is triggered.)

## Implementation Phases

### Phase 1 — Baseline capture

1. Run `python3 scripts/lint-credential-path-literals.py` and capture the full
   hard-fail list (30 lines / 12 files) as the working set. This is the SSOT;
   do not trust any frozen line list (numbers drift as edits shift lines within a
   file — edit top-of-file lines first, or re-run after each file).
2. Note the advisory count (15) — these `/home/<user>/` and `/root/` remote-host
   lines are **report-only and OUT OF SCOPE**; they must remain untouched.

### Phase 2 — Neutralize per credential family (12 files)

Apply the **validated** canonical replacement table below (every RHS form was
live-tested to produce zero hard-fail). Choose per line the form that best
preserves the original sentence's meaning — a directory form when the sentence is
about "the config lives here", a `<key>` placeholder when a specific file path is
structurally needed, a descriptive name when prose reads naturally.

| Credential family (offending literal, described) | Neutralized replacement (all PASS the guard) |
|---|---|
| SSH private key under `~/.ssh/` (the `id_<key>` family; incl. `$HOME/` form) | `~/.ssh/id_<key>` (placeholder), or `~/.ssh/` (directory), or "an SSH private key" |
| Doppler CLI **home credential** (under `~/.doppler/`) | `~/.doppler/` (directory), or "the Doppler CLI config" |
| Doppler **repo-root project-pointer** file (bare filename) | "the Doppler project-pointer file" / "the repo-root Doppler config pointer" — **NEVER a bare `.doppler.*` literal, not even in a placeholder path** |
| Docker config (under `~/.docker/`; incl. `$HOME/` form) | `~/.docker/` (directory), or "the Docker config" |
| netrc home dotfile | "a netrc credentials file" — **NEVER a resolvable `~/`-prefixed netrc literal** |

Per-file working set (families; exact lines via the Phase-1 re-run):

- `.../plans/2026-03-20-feat-adopt-doppler-secrets-manager-plan.md` (6) — Doppler **repo-root pointer** (headings + prose + a code-fence label reference the bare filename; the fenced `setup:`/`project:` YAML body itself carries no filename and stays as-is)
- `.../plans/2026-05-20-fix-ci-host-ssh-auth-deploy-pipeline-fix-plan.md` (4) — SSH key
- `.../plans/2026-07-17-fix-web-platform-docker-login-erofs-cred-path-plan.md` (3) — Docker config (`$HOME/` form)
- `.../plans/2026-04-03-fix-web-platform-infra-drift-doppler-install-plan.md` (3) — SSH key (incl. `$HOME/` form)
- `.../plans/2026-03-21-infra-scheduled-terraform-drift-detection-plan.md` (3) — SSH key
- `.../plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md` (2) — Doppler **home credential** (`~/.doppler/` config)
- `.../plans/2026-07-04-fix-cosign-verify-private-ghcr-auth-offline-plan.md` (2 hard-fail) — Docker **home** config. **This file also has advisory remote-host (`/home/deploy/...`) Docker-config lines — DO NOT touch those** (report-only, correct as remote-host runbook docs)
- `.../plans/2026-06-08-fix-cron-sandbox-dontask-allowlist-tiered-plan.md` (2) — netrc
- `.../learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` (2) — SSH key
- `.../specs/feat-secrets-manager/tasks.md` (1) — Doppler **repo-root pointer** (a `1.3 Commit` task line references the bare filename)
- `.../plans/2026-04-14-fix-one-shot-verify-deploy-and-apply-tf-plan.md` (1) — SSH key
- `.../learnings/integration-issues/2026-07-05-plan-live-confirmed-anonymous-registry-pull-is-a-cached-creds-false-confirm.md` (1) — Docker **home** config

Meaning-preservation rule: replace **only** the resolvable path token; leave the
surrounding sentence, code semantics, and any non-credential path intact. These
are point-in-time historical records — the descriptive form must keep them
readable as history (e.g., "committed the Doppler project-pointer to the repo
root", "the drift ran `remote-exec` against an SSH private key").

### Phase 3 — Verify to zero

1. `python3 scripts/lint-credential-path-literals.py` → exit 0, "OK: no
   resolvable credential-file path literals" (0 hard-fail; advisory rises 15 → 18
   as three co-located advisories unmask — see AC3; no advisory token edited).
2. `python3 scripts/lint-credential-path-literals.py --changed --base origin/main`
   → exit 0 (the exact CI gate; grandfathering is now moot since residual = 0).
3. `python3 scripts/lint-credential-path-literals.py <this-plan> <tasks.md>` →
   exit 0 (the planning artifacts are themselves in scan scope — see Sharp Edges).
4. `bash scripts/lint-credential-path-literals.test.sh` → pass (linter untouched).
5. `git diff --name-only origin/main` equals exactly the 12 files + the plan +
   `tasks.md` — no collateral edits.

### Phase 4 — Promotion decision (record + defer)

Record the decision (defer — see Non-Goals) and **file a dedicated follow-up
issue** via `gh issue create` for the `lint-bot-statuses` required-check
promotion, so the deferred sub-item is not lost when #6868 closes. Reference the
follow-up number in the PR body.

## Files to Edit

The 12 offending docs (Phase 2) + the two planning artifacts:

1. `knowledge-base/project/plans/2026-03-20-feat-adopt-doppler-secrets-manager-plan.md`
2. `knowledge-base/project/plans/2026-05-20-fix-ci-host-ssh-auth-deploy-pipeline-fix-plan.md`
3. `knowledge-base/project/plans/2026-07-17-fix-web-platform-docker-login-erofs-cred-path-plan.md`
4. `knowledge-base/project/plans/2026-04-03-fix-web-platform-infra-drift-doppler-install-plan.md`
5. `knowledge-base/project/plans/2026-03-21-infra-scheduled-terraform-drift-detection-plan.md`
6. `knowledge-base/project/plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md`
7. `knowledge-base/project/plans/2026-07-04-fix-cosign-verify-private-ghcr-auth-offline-plan.md`
8. `knowledge-base/project/plans/2026-06-08-fix-cron-sandbox-dontask-allowlist-tiered-plan.md`
9. `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`
10. `knowledge-base/project/specs/feat-secrets-manager/tasks.md`
11. `knowledge-base/project/plans/2026-04-14-fix-one-shot-verify-deploy-and-apply-tf-plan.md`
12. `knowledge-base/project/learnings/integration-issues/2026-07-05-plan-live-confirmed-anonymous-registry-pull-is-a-cached-creds-false-confirm.md`

## Files to Create

- `knowledge-base/project/plans/2026-07-23-chore-drain-grandfathered-credential-path-docs-plan.md` (this plan)
- `knowledge-base/project/specs/feat-one-shot-6868-drain-credential-path-docs/tasks.md`
- (GitHub, not a file) a follow-up issue for the `lint-bot-statuses` promotion decision

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `python3 scripts/lint-credential-path-literals.py` exits **0** and prints "OK: no resolvable credential-file path literals" (hard-fail count 30 → 0).
- [ ] **AC2:** `python3 scripts/lint-credential-path-literals.py --changed --base origin/main` exits **0** on the PR branch (the CI gate the `lint-bot-statuses` job runs).
- [ ] **AC3:** No advisory remote-host TOKEN is added, removed, or reworded (`git diff` on the 12 docs shows every `/home/<user>/` and `/root/` `.docker/config.json` line byte-identical on both sides). NOTE: the advisory *line-count* rises 15 → **18** — draining the hard-fail on three co-located lines (`2026-07-17-...erofs...:15/40/63`, which each carry a `$HOME/` hard-fail AND a `/home/deploy/`|`/root/` advisory on the same line) unmasks the advisory the scanner previously suppressed (one hit/line, hard-fail first). This is expected surfacing, not an edit to any advisory line. Advisories are report-only (exit stays 0), so this does not affect AC1/AC2.
- [ ] **AC4:** The plan file and `tasks.md` are themselves clean — `python3 scripts/lint-credential-path-literals.py knowledge-base/project/plans/2026-07-23-chore-drain-grandfathered-credential-path-docs-plan.md knowledge-base/project/specs/feat-one-shot-6868-drain-credential-path-docs/tasks.md` exits **0**.
- [ ] **AC5:** `bash scripts/lint-credential-path-literals.test.sh` passes (linter script unmodified and still green).
- [ ] **AC6:** Each of the 12 docs still reads as coherent history — spot-check that only the resolvable path token changed and no functional code-fence content (e.g. the Doppler `setup:` YAML body, shell commands) was altered.
- [ ] **AC7:** `git diff --name-only origin/main` lists exactly the 12 docs + this plan + `tasks.md` — no collateral files.
- [ ] **AC8:** A follow-up issue for the `lint-bot-statuses` promotion decision exists and is referenced in the PR body.

### Post-merge (operator)

- None. Docs-only change; no deploy, migration, or infra apply. The CI
  `lint-bot-statuses` run on the PR is the verification. `Closes #6868` (the
  drain is the issue's titled deliverable; the promotion sub-item migrates to the
  Phase-4 follow-up issue).

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue names any of the 12 doc paths or the
planning artifacts; this is a self-contained hygiene sweep.)

## Domain Review

**Domains relevant:** none

Security-hygiene docs sweep over historical `knowledge-base/**/*.md` prose. No UI
surface (no `components/**`, `app/**/page.tsx`, or `.tsx` in Files to Edit → the
mechanical UI-surface override does not fire; Product = NONE). No product,
marketing, legal, finance, sales, or support implications — the change removes
resolvable-path tokens from cold historical records and preserves their meaning.
Engineering/tooling only.

## Observability

Skipped — **pure-docs change.** Files to Edit are all `knowledge-base/**/*.md`;
none fall under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or
`plugins/*/scripts/`, and the change introduces no new infrastructure surface.
The regression teeth already exist and are unchanged: `lint-credential-path-
literals.py` (changed-files mode in CI) blocks any future reintroduction; this
sweep merely drains the grandfathered backlog to zero.

## Hypotheses (network-outage gate)

The feature description substring-matches `SSH` (offending literals include SSH
private-key paths, and one target doc is an SSH-auth plan), so the network-outage
gate nominally fires. **N/A in substance:** this plan performs no connectivity
diagnosis and prescribes no sshd / firewall / DNS / service-layer change — it only
neutralizes doc prose. There is no L3→L7 diagnostic to order. No firewall or
egress-IP hypothesis applies.

### Network-Outage Deep-Dive (deepen-plan 4.5)

Trigger matched on the `SSH` substring; the deep-dive confirms it is a
false-positive keyword hit, not a connectivity change. Layer-by-layer:

- **L3 firewall allow-list:** N/A — no host, firewall rule, or egress path is touched.
- **L3 DNS/routing:** N/A — no DNS, CNAME, or routing change.
- **L7 TLS/proxy:** N/A — no HTTPS surface, tunnel, or proxy change.
- **L7 application:** N/A — no sshd, service, or app-layer behavior change.

The only `SSH` in scope is the literal string `~/.ssh/id_<key>` inside historical
doc prose, being neutralized. No verification artifact is required because no
connectivity behavior changes.

## Non-Goals / Deferred

- **Promoting `lint-bot-statuses` to a required check — DEFERRED** to a dedicated
  follow-up issue (filed in Phase 4). Rationale:
  - Adding the job name to `scripts/required-checks.txt` triggers the **#6049
    auto-fabrication guard**: the `bot-pr-with-synthetic-checks` composite action
    posts an unconditional green synthetic check-run for every listed name. But
    `lint-bot-statuses` is a **content-scoped** gate (it scans doc content for
    credential paths + human-step infra) that the action does **not** reproduce in
    its Phase-4 "Secret-safety ceiling" — so a naive promotion would fabricate a
    passing result for bot PRs, defeating the guard. Sound promotion first
    requires either reproducing the changed-files scan in the action's preflight
    OR excluding the check from synthesis via a non-15368 `integration_id`.
  - Promotion also spans the CI Required ruleset canonical JSON
    (`scripts/ci-required-ruleset-canonical-required-status-checks.json`),
    `infra/github/ruleset-ci-required.tf`, and the parity test — an IaC/ruleset
    blast radius entirely orthogonal to a docs sweep. Mixing it in would violate
    the "keep the sweep PR narrow" principle and require auditing every bot-PR-
    creating workflow for synthetic-check updates.
  - `lint-bot-statuses` also bundles **four** checks (synthetic-statuses,
    synthetic-completeness, infra-no-human-steps, credential-path) — promoting the
    job promotes all four, two of which are content-scoped changed-files gates
    with the same fabrication concern. That coupling deserves its own analysis.
- **Advisory remote-host lines** (`/home/<user>/`, `/root/`) — out of scope by
  design; report-only, correct as remote-host runbook documentation.
- **The linter script and its wiring** — unchanged; this is a data drain, not a
  guard change.

## Sharp Edges

- **The plan file and `tasks.md` are themselves in the guard's scan scope.** The
  linter scans all `*.md` under `plugins/**` and `knowledge-base/**` (only
  `**/archive/**` excluded — plans/specs are explicitly NOT excluded). CI runs it
  in changed-files mode, so this very PR's plan + tasks.md are scanned. **Writing
  any raw credential-path literal in the plan or tasks.md hard-fails your own PR.**
  Use only the validated-safe forms (`~/.ssh/`, `~/.ssh/id_<key>`, `~/.doppler/`,
  `~/.docker/`, descriptive names). This plan was authored under that constraint
  and passes AC4.
- **`.doppler.*` bare filename fails even inside a placeholder path.** The
  bare-filename regex arm matches the bare Doppler-pointer filename after ANY
  non-word/dot char, so even a `<placeholder>/`-prefixed bare Doppler-pointer
  filename STILL hard-fails (live-verified). For the repo-root pointer, never emit
  a bare resolvable Doppler-pointer filename at all — use a purely descriptive
  name ("the Doppler project-pointer file").
- **Line numbers drift within a file as you edit.** The Phase-1 list is a
  snapshot; editing an early line shifts every later line's number. Re-run the
  linter after each file (or edit bottom-up) rather than trusting frozen numbers.
- **Do not over-neutralize.** `~/.ssh/` (directory), `~/.doppler/` (directory),
  and `~/.docker/` (directory) forms all PASS — a directory is not an
  auto-attachable file. Do not strip meaning by collapsing to vague prose when a
  safe directory/placeholder form preserves the original path structure.
- **Leave advisory lines alone** even when they sit in a file you are editing
  (e.g. the cosign-verify plan has both hard-fail home-relative `~/.docker/`
  config lines and advisory remote-host `/home/deploy/...` lines). Only the
  hard-fail lines
  are in scope; touching advisory lines widens the diff and the meaning without
  cause.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — this section is filled with a concrete artifact,
  vector, and `threshold: none` reason.

## Test Scenarios

This is a docs change; the "tests" are the guard's own assertions:

1. **Zero residual (full-scan):** after the sweep, full-scan exit 0 / "OK". (AC1)
2. **CI gate green (changed-files):** `--changed --base origin/main` exit 0. (AC2)
3. **Advisory tokens unchanged:** no `/home/<user>/` or `/root/` advisory token edited (count surfaces 15 → 18 via co-located unmasking). (AC3)
4. **Self-clean artifacts:** plan + tasks.md scan exit 0. (AC4)
5. **Linter unregressed:** `lint-credential-path-literals.test.sh` passes. (AC5)
6. **No collateral:** diff limited to the 12 docs + 2 artifacts. (AC7)

## Research Insights

- Guard source: `scripts/lint-credential-path-literals.py`. Hard-fail table
  covers `~/`, `$HOME/`, `${HOME}/` prefixes for SSH keys (`id_ed25519|rsa|ecdsa|
  dsa`), the Doppler home config, netrc, git-credentials, aws/credentials,
  gcloud credentials.db, Docker config — plus the **bare** Doppler-pointer
  filename (resolves via the tracked repo-root pointer). Advisory table = the same
  filenames under `/home/<user>/` or `/root/` (report-only).
- CI wiring: `.github/workflows/ci.yml` job `lint-bot-statuses`, step "Lint
  resolvable credential-file paths in docs (changed vs base)", `--changed` mode
  with `--base origin/$BASE_REF` on PRs.
- `lint-bot-statuses` is absent from `scripts/required-checks.txt` (verified) and
  from the CI Required ruleset — hence advisory today; promotion analysis is in
  Non-Goals.
- Validated-safe replacement forms (live-linted): `~/.ssh/`, `~/.ssh/id_<key>`,
  `~/.doppler/`, `~/.docker/`, and descriptive names all produce zero hard-fail.
- Sibling grandfather precedent: `lint-infra-no-human-steps` (same changed-files
  grandfathering pattern), referenced in the issue.
