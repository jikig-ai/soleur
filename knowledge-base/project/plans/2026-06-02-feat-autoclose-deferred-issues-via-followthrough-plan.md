---
title: Auto-close deferred/timed GitHub issues via the follow-through system
type: feat
date: 2026-06-02
branch: feat-one-shot-followthrough-autoclose-deferred
lane: procedural
brand_survival_threshold: none
status: planned
refs:
  - "#3950"
  - "#3859"
  - "#4178"
  - "#4226"
  - PR #4784
---

# feat: Auto-close deferred/timed GitHub issues via the follow-through system

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Overview boundary, Implementation (probe shapes), Risks (precedent-diff), Acceptance Criteria

### Key Improvements

1. **Precedent-diff: stale-sweeper vs follow-through sweeper boundary documented.**
   `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
   (PR #4452/#4457) already exists and closes `deferred-scope-out` issues blindly
   at 90 days inactivity UNLESS they carry `do-not-autoclose`. This feature is the
   COMPLEMENT, not an overlap: the follow-through sweeper closes on *verified*
   script exit 0 and ignores `do-not-autoclose` entirely. #3950 carries all three
   labels — `do-not-autoclose` exempts it from the blind 90d close precisely
   because its closure needs verification, which this feature now provides.
2. **All cited gate line-ranges in `review/SKILL.md` re-verified live** (484/528/550/561/577/605)
   so the bounded-edit ACs are mechanically checkable.
3. **All `#N`/PR citations resolved live** via `gh` (states + titles confirmed).
4. **Probe-shape contract grounded** against the closest precedent
   `scripts/followthroughs/manifest-drift-suppress-deletion-4178.sh` (server-side
   `gh run list --created '>='` filter).

### New Considerations Discovered

- The follow-through sweeper does NOT consult `do-not-autoclose` (verified: grep
  returns nothing in `scripts/sweep-followthroughs.sh` and the Inngest monitor).
  This is correct and load-bearing — verification IS the gate. The plan now makes
  this explicit so the multi-agent review does not flag apparent double-coverage.
- No new scheduled job is introduced (Inngest cron count = 34, reuses the existing
  `cron-follow-through-monitor.ts` + sweeper). ADR-033 scheduled-work gate is N/A.

## Overview

Deferred-scope-out / `do-not-autoclose` issues carry a **re-evaluation trigger**
(date / counter / event-grep / dependency) that today is human-read prose. Nobody
revisits them, so they rot open. The repo already ships a complete
**follow-through** auto-close substrate:

- `.github/workflows/scheduled-followthrough-sweeper.yml` (daily cron) →
- `scripts/sweep-followthroughs.sh` (parses the `<!-- soleur:followthrough script=… earliest=… [secrets=…] -->`
  directive on every open `follow-through`-labelled issue, runs the named script,
  and closes on exit 0 / comments-FAIL on exit 1 / retries on any other exit) and
- the equivalent Inngest function `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`.

This feature **wires deferred-scope-out issues into that substrate** with two
minimal moves and zero new infrastructure:

1. **First instance** — add `scripts/followthroughs/cla-evidence-hardening-3950.sh`,
   the machine-verified close gate for already-open issue **#3950** ("review:
   cla-evidence scripts hardening bundle"). This proves the substrate auto-closes
   a real deferred-scope-out.
2. **Generalize the filing flow** — extend the review skill so that *future*
   deferred-scope-out filings with a concrete trigger ALSO apply the
   `follow-through` label and emit a directive + a generated verification script,
   mapping each of the four trigger shapes to an exit-code probe. Document the
   trigger→verification mapping in the existing convention runbook.

Scope is deliberately MINIMAL. No AGENTS.core.md rule (the always-loaded budget is
already over the 22 KB cap — enforce via skill instructions only). REUSE the
existing precondition gate (`.claude/hooks/follow-through-directive-gate.sh`) and
the sweeper's directive parser — do NOT duplicate validation. #3950 is NOT
auto-closed or body-edited in this PR; the label+directive are added post-merge,
and the sweeper then closes it (see Post-merge operator steps).

## Research Reconciliation — Spec vs. Codebase

Premise validation (all cited artifacts confirmed on the worktree HEAD):

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| Follow-through infra exists (sweeper workflow + script + Inngest fn) | All three EXIST and consume the `follow-through` label + directive. Exit 0=close / 1=FAIL / other=transient confirmed at `scripts/sweep-followthroughs.sh:220-263`. | Reuse verbatim; add only the new verification script + skill docs. |
| 4 cla-evidence hardening markers exist in-tree | All 4 confirmed: `_cf-admin-token.sh`✓, `_r2-endpoint.sh`✓, `gdpr-override.sh:305,410` contains `env -u CF_ADMIN_TOKEN doppler run`✓, `inspect-evidence.sh:118` has `tombstone)`✓. | Script asserts these 4 markers (part a). |
| PR #4784 merged 2026-06-02T09:14:45Z | Confirmed: `state=MERGED mergedAt=2026-06-02T09:14:45Z`. | Use this exact cutoff for the post-merge green-run probe (part b). |
| Post-merge green `cla-evidence.yml` runs exist | 3+ success runs at 09:26–09:38Z (all AFTER 09:14:45Z). | Probe returns exit 0 today; correct PASS state. |
| #3950 needs the `follow-through` label | #3950 ALREADY has `follow-through` + `deferred-scope-out` + `do-not-autoclose` + `code-review`. Body has prose "Re-evaluation target" (line 54) but NO machine directive. | Post-merge: add directive only (label already present). |
| Runbook `followthrough-convention.md` to be created | It ALREADY EXISTS (66 lines). | EDIT (append §Trigger→Verification mapping), do not create. |
| §Re-evaluation Trigger section to edit in review-todo-structure.md | EXISTS at lines 47-53 with anchor `{#re-evaluation-trigger}` (four trigger forms enumerated). | Annotate each of the 4 forms with its verification probe (single bounded section). |
| Directive precondition gate exists | `.claude/hooks/follow-through-directive-gate.sh` EXISTS (PreToolUse Bash hook on `gh issue create --label follow-through`). | Reuse; skill instructions reference it, no duplication. |

No stale premises. No "build vs fix" ambiguity — every named artifact is present.

## User-Brand Impact

**If this lands broken, the user experiences:** a deferred-scope-out issue that
fails to auto-close (stays open past its trigger) or auto-closes prematurely on a
false PASS. Blast radius is internal backlog hygiene — no user-facing surface,
endpoint, or data path is touched.

**If this leaks, the user's data is exposed via:** N/A. The new script reads only
the public repo tree (file existence + grep markers) and the repo's own GitHub
Actions run history via `gh`. No secrets, no PII, no customer data. The sweeper
already runs the new script under `env -i` with a narrow allowlist (the script
declares no `secrets=`, so it gets only `PATH`+`HOME`+`GH_TOKEN`).

**Brand-survival threshold:** none — internal tooling/backlog automation, no
sensitive-path touch (verified: no edits under schemas, migrations, auth flows,
API routes, or `.sql`).

## Risks & Mitigations — Precedent Diff (deepen-plan Phase 4.4)

This feature touches the **deferred-scope-out auto-close** surface, where a
canonical sibling already exists. The precedent-diff is load-bearing because a
reviewer will otherwise flag apparent double-coverage.

| Dimension | `cron-stale-deferred-scope-outs.ts` (existing, PR #4452/#4457) | follow-through sweeper (this feature wires into) |
|---|---|---|
| Close trigger | **Time** — 90 days inactivity (`STALE_WINDOW_MS`) | **Verification** — script exit 0 |
| Label consumed | `deferred-scope-out` | `follow-through` + `<!-- soleur:followthrough -->` directive |
| Kill switch | `do-not-autoclose` EXEMPTS (skips close) | **No kill-switch check** — verification IS the gate (grep of `scripts/sweep-followthroughs.sh` + the Inngest monitor returns zero `do-not-autoclose` references) |
| Verdict shape | binary close-or-skip | exit 0=close / 1=FAIL-comment / *=transient-retry |
| Runtime | Inngest cron (`cron-stale-deferred-scope-outs`) | existing `cron-follow-through-monitor.ts` + GHA `scheduled-followthrough-sweeper.yml` |

**Complementarity (not overlap):** an issue carrying BOTH `deferred-scope-out` +
`do-not-autoclose` (like #3950) is *deliberately exempt* from the blind 90-day
close — it was kept open precisely because its closure requires verification, not
the passage of time. Adding `follow-through` + a directive gives it the *verified*
close path the kill-switch was protecting. The two sweepers never both close the
same issue: the stale-sweeper skips any `do-not-autoclose` issue; the
follow-through sweeper closes only on its script's exit 0. No new code is needed in
either sweeper — they already consume their respective labels generically.

**No precedent for the verification SCRIPT pattern is novel** — it is modeled
verbatim on two committed siblings (`manifest-drift-suppress-deletion-4178.sh` for
the `gh run list --created '>='` event-grep probe; `sentry-checkins-3859.sh` for
the docblock + exit-semantics shape). `set -uo pipefail` (not `-e`) matches both.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `scripts/followthroughs/cla-evidence-hardening-3950.sh` exists, is
      executable (`chmod +x`), starts with `#!/usr/bin/env bash` and `set -uo pipefail`.
- [ ] **AC2** The script's part (a) **regression assertion** fails (exit 1) if ANY
      of the 4 markers is missing: `apps/cla-evidence/scripts/_cf-admin-token.sh`
      exists, `apps/cla-evidence/scripts/_r2-endpoint.sh` exists,
      `apps/cla-evidence/scripts/gdpr-override.sh` contains the literal
      `env -u CF_ADMIN_TOKEN doppler run`, and
      `apps/cla-evidence/scripts/inspect-evidence.sh` contains a `tombstone)` case.
      Verify by temporarily renaming one marker file and confirming exit 1.
- [ ] **AC3** The script's part (b) **no-regression probe** runs
      `gh run list --workflow=cla-evidence.yml --status success --json conclusion,createdAt`
      and returns **exit 0** iff ≥1 success run has `createdAt > 2026-06-02T09:14:45Z`
      (the #4784 merge), **exit 2 (transient)** if no post-merge success run exists yet,
      and **exit 2 (transient)** on `gh` API/network failure. Running the script
      locally today (against live run history) prints PASS and exits 0.
- [ ] **AC4** `shellcheck scripts/followthroughs/cla-evidence-hardening-3950.sh`
      is clean (shellcheck 0.10.0 confirmed installed at `~/.local/bin/shellcheck`).
- [ ] **AC5** The script declares **no `secrets=`** dependency (uses only `gh`,
      satisfied by the sweeper's existing `GH_TOKEN` env). No edit to
      `.github/workflows/scheduled-followthrough-sweeper.yml` env block is required —
      verify the sweeper already sets `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` (line 56).
- [ ] **AC6** `plugins/soleur/skills/review/references/review-todo-structure.md`
      §Re-evaluation Trigger (`{#re-evaluation-trigger}`, lines 47-53) is edited as a
      **single bounded section**: each of the 4 trigger forms gains a one-line
      `→ verification:` annotation mapping it to its exit-code probe (per the
      §Implementation table). The four existing trigger definitions, the **Rejected
      phrasings** bullet, and the phishing-vector bullet are PRESERVED verbatim.
- [ ] **AC7** `plugins/soleur/skills/review/SKILL.md` §5 gains a **single bounded
      subsection** (placed inside the existing `When filing:` block, after the
      `--body-file` bullet at line 561) instructing: when a scope-out passes CONCUR
      with a concrete trigger, ALSO (a) add `--label follow-through`, (b) scaffold
      `scripts/followthroughs/<slug>-<issue>.sh` from the stub template mapping the
      trigger shape to its probe, and (c) embed the `<!-- soleur:followthrough … -->`
      directive in the issue body. The instruction explicitly defers directive
      validation to `.claude/hooks/follow-through-directive-gate.sh` (no duplicated
      checks). The **cost-of-filing gate** (lines 484-518), the **mechanical
      pre-CONCUR auto-flip** (495-499), the **four scope-out criteria** (528-550),
      and the **CONCUR second-reviewer gate** (577-605) are UNCHANGED.
- [ ] **AC8** `git diff origin/main -- plugins/soleur/skills/review/SKILL.md` touches
      ONLY the new subsection (no edits between lines 484-550 or 577-605). Mechanical
      check: `git diff origin/main -- plugins/soleur/skills/review/SKILL.md | grep '^-'`
      returns zero deletions inside the gate ranges.
- [ ] **AC9** `knowledge-base/engineering/ops/runbooks/followthrough-convention.md`
      gains a `## Trigger → verification mapping` section documenting all 4
      trigger→probe shapes (date / dependency / event-grep / counter) with the exit-code
      contract. Existing sections (Why / Author workflow / Directive fields / Security
      guarantees / Operator reference) PRESERVED.
- [ ] **AC10** Skill description-budget check: this PR adds NO `description:` edit to
      any `plugins/soleur/skills/*/SKILL.md` (only body edits to review/SKILL.md).
      Confirm `bun test plugins/soleur/test/components.test.ts` still passes (no
      cumulative-word-count regression).
- [ ] **AC11** PR body uses **`Ref #3950`** (NOT `Closes #3950`) — #3950 is closed
      post-merge by the sweeper, not at PR merge. PR body includes a `## Changelog`
      section (per plugins/soleur versioning) and a `semver:minor` label (new
      verification script + skill capability).
- [ ] **AC12** No AGENTS.core.md / AGENTS.rest.md / AGENTS.docs.md rule is added
      (verify `git diff origin/main -- 'AGENTS*.md'` is empty).
- [ ] **AC13** No edit to `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
      or `scripts/sweep-followthroughs.sh` or `cron-follow-through-monitor.ts` (the
      two sweepers are reused, not modified). Verify `git diff origin/main --name-only`
      contains none of these three paths.

### Post-merge (operator — automatable via gh CLI, NOT manual)

- [ ] **POST1** Once the script is on `main`, add the directive to #3950's body via
      `gh issue edit 3950 --body-file <tmp>` appending:
      `<!-- soleur:followthrough script=scripts/followthroughs/cla-evidence-hardening-3950.sh earliest=2026-06-02T09:14:45Z secrets=GH_TOKEN -->`.
      `secrets=GH_TOKEN` is REQUIRED — the sweeper's `env -i` sandbox strips it
      otherwise and the gh-probe silently never closes (review P1). The
      `follow-through` label is already present (no `gh issue edit --add-label`
      needed). **Automation:** single `gh` call — bake into `/ship` post-merge
      verification, do NOT punt to a human.
- [ ] **POST2** Trigger one sweep to confirm auto-close:
      `gh workflow run scheduled-followthrough-sweeper.yml` (or `-f dry_run=true`
      first). Expected: sweeper runs the script (exit 0 today), comments PASS, and
      closes #3950. **Automation:** `gh workflow run` — bake into `/ship`.

## Implementation Phases

### Phase 1 — First-instance verification script (`scripts/followthroughs/cla-evidence-hardening-3950.sh`)

Model on `scripts/followthroughs/manifest-drift-suppress-deletion-4178.sh` (the
`gh run list --created '>=<ISO>'` green-run probe — closest precedent for part b)
and `scripts/followthroughs/sentry-checkins-3859.sh` (header/exit-semantics shape).
`set -uo pipefail` (NOT `set -e` — the precedent scripts intentionally omit `-e` so
a failed probe maps to a verdict rather than an uncaught abort).

**Header block** (mirror precedent docblocks): purpose, exit semantics
(0=PASS/close, 1=FAIL/stay-open, *=TRANSIENT/retry), "No secrets required (uses the
sweeper's default GH_TOKEN)", close criteria, and a note that the script does NOT
edit #3950.

**Part (a) — hardening-marker regression assertion (in-tree):**
```bash
# Resolve repo root so the script works regardless of sweeper CWD.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
CLA="$ROOT/apps/cla-evidence/scripts"
missing=0
[[ -f "$CLA/_cf-admin-token.sh" ]] || { echo "FAIL: missing _cf-admin-token.sh"; missing=1; }
[[ -f "$CLA/_r2-endpoint.sh"   ]] || { echo "FAIL: missing _r2-endpoint.sh"; missing=1; }
grep -qF 'env -u CF_ADMIN_TOKEN doppler run' "$CLA/gdpr-override.sh"   || { echo "FAIL: gdpr-override.sh lost CF_ADMIN_TOKEN scrub"; missing=1; }
grep -qE '^[[:space:]]*tombstone\)' "$CLA/inspect-evidence.sh"        || { echo "FAIL: inspect-evidence.sh lost tombstone) case"; missing=1; }
if [[ "$missing" -ne 0 ]]; then echo "exit: FAIL (hardening regression)"; exit 1; fi
```
- Use `grep -qF` for the fixed CF_ADMIN_TOKEN literal (no regex metachar surprises);
  use `grep -qE '^[[:space:]]*tombstone\)'` for the case arm (escape the `)`).
- A missing-marker file that breaks `grep` (file absent) is caught by the `-f`
  existence checks first, so the greps only run on present files.

**Part (b) — no-regression green-run probe (post-#4784):**
```bash
MERGE_CUTOFF="2026-06-02T09:14:45Z"   # PR #4784 mergedAt (verified)
RUNS_JSON=$(gh run list --workflow=cla-evidence.yml --status success \
  --created ">=${MERGE_CUTOFF}" --limit 20 \
  --json conclusion,createdAt 2>/dev/null)
gh_rc=$?
if [[ "$gh_rc" -ne 0 ]]; then echo "TRANSIENT: gh run list exit $gh_rc"; exit 2; fi
if [[ -z "$RUNS_JSON" || "$RUNS_JSON" == "[]" ]]; then
  echo "TRANSIENT: no post-merge success run yet"; exit 2
fi
n=$(printf '%s' "$RUNS_JSON" | jq 'length' 2>/dev/null || echo 0)
if [[ "$n" -ge 1 ]]; then echo "PASS: $n post-merge green cla-evidence run(s)"; echo "exit: PASS"; exit 0; fi
echo "TRANSIENT: parsed 0 post-merge green runs"; exit 2
```
- **Probe design note (per the precedent + Sharp Edges):** the ARGUMENTS text
  says "else exit 2 (transient)" for the no-post-merge-run case — followed here.
  Rationale: absence of a post-merge green run is a *wait-for-next-tick* condition,
  not a hardening FAIL. Hardening regression (part a) is the only exit-1 path. Using
  `--created ">=${MERGE_CUTOFF}"` lets `gh` filter server-side (precedent
  manifest-drift-4178 line 32-38) rather than client-side date math.
- `gh_rc=$?` is captured on the line immediately after the assignment (valid under
  `set -uo pipefail` without `-e`; precedent does the same at 4178:40).

**Ordering:** part (a) runs FIRST (cheap, no network, catches the only FAIL case);
part (b) runs only if (a) passes. This means a hardening regression reports FAIL even
when CI is green — the stricter signal wins.

**`chmod +x`** the script (the directive gate + sweeper both reject non-executable
scripts: gate line 210-221, sweeper line 173-176).

### Phase 2 — Generalize the deferred-scope-out filing flow

**2a. `plugins/soleur/skills/review/references/review-todo-structure.md` §Re-evaluation Trigger (lines 47-53, single bounded edit):**

Append a `→ verification:` clause to each of the 4 existing trigger forms (do NOT
restructure the list — extend each numbered item). Mapping:

| Trigger form (existing) | `→ verification:` probe (new annotation) | Exit contract |
|---|---|---|
| 1. Date — `Re-evaluate by YYYY-MM-DD` | directive `earliest=<date>T00:00:00Z` + trivial `exit 0` body (the `earliest` gate alone defers closure until the date) | sweeper auto-closes on/after the date |
| 4. Dependency — `Re-evaluate when #N lands` | `state=$(gh issue view N --json state --jq .state); [[ "$state" == CLOSED ]] && exit 0 \|\| exit 2` | exit 0 when #N closed, else transient (wait) |
| 3. Event-grep — `Re-evaluate when <pattern> matches in <corpus>` | `gh run list --workflow X --status success --created ">=cutoff"` (or `gh issue list`/Sentry grep) nonempty ? `exit 0` : `exit 2` | exit 0 on first match, else transient |
| 2. Counter — `Re-evaluate when <counter> exceeds <threshold>` | a `gh`/SQL/grep count check: `[[ "$count" -ge "$threshold" ]] && exit 0 \|\| exit 2` | exit 0 when threshold met, else transient |

Add a one-line pointer: "Full mapping + script-scaffolding contract:
`knowledge-base/engineering/ops/runbooks/followthrough-convention.md` §Trigger → verification mapping."

**2b. `plugins/soleur/skills/review/SKILL.md` §5 (single bounded subsection, inserted after line 561 inside `When filing:`):**

New subsection `**Auto-wire deferred-scope-outs into the follow-through sweeper.**`
Content (instruction-level only):
- When a scope-out passes the CONCUR gate AND its `Re-eval by:` trigger is a date /
  dependency / event-grep / counter form, the filing ALSO:
  1. adds `--label follow-through` to the `gh issue create` invocation (alongside
     `--label deferred-scope-out`);
  2. scaffolds `scripts/followthroughs/<slug>-<issue-or-pr>.sh` by `cp`-ing
     `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` and
     replacing the TODO body with the probe for its trigger shape (per the table in
     `review-todo-structure.md` §Re-evaluation Trigger / the runbook §Trigger →
     verification mapping), then `chmod +x`;
  3. embeds the `<!-- soleur:followthrough script=… earliest=… [secrets=…] -->`
     directive in the issue body.
- **Validation is NOT re-implemented here.** The `gh issue create --label
  follow-through` call is intercepted by `.claude/hooks/follow-through-directive-gate.sh`,
  which fails-closed if the directive is missing/malformed, the script path escapes
  `scripts/followthroughs/`, the script is absent/non-executable, or `earliest`
  doesn't parse. Compose the directive + scaffold the script BEFORE the `gh issue
  create` call so the gate passes.
- **Chicken-and-egg note:** the script must exist on disk (committed in the same PR /
  on the branch) before `gh issue create` runs, because the gate's existence check
  (line 198) and the sweeper's (line 169) both require it. For review-time filings
  the script lands in the review PR's branch; the directive's `earliest=` should be
  set to the trigger date (date form) or `now` (dependency/event-grep/counter forms,
  which self-gate via the probe).
- One-line back-reference to the runbook for the full contract.

**Guardrails (must NOT regress — verified ranges):** do not touch the cost-of-filing
gate (484-518), the auto-flip (495-499), the four criteria (528-550), the bundling
instruction (567-575), or the CONCUR gate (577-605). The new subsection is purely
additive AFTER the existing `When filing:` bullets.

### Research Insights — `earliest=` semantics per probe shape

The directive's `earliest=` is a hard wall-clock gate (`scripts/sweep-followthroughs.sh:181`
skips the issue until `now >= earliest`), evaluated BEFORE the script runs. This
splits the four trigger shapes into two `earliest=` strategies:

- **Date trigger** — set `earliest=<trigger-date>T00:00:00Z`. The `earliest` gate
  IS the verification; the script body can be a trivial `exit 0` (the date passing
  is the close-criterion). No probe needed.
- **Dependency / event-grep / counter triggers** — the *script* self-gates (returns
  exit 2/transient until the dependency closes / the run appears / the counter
  trips). Here `earliest=` should be the filing date (run from the next sweep
  onward); the script is responsible for the wait via its exit-2 path. Do NOT set a
  far-future `earliest=` for these — that would double-gate and delay verification
  unnecessarily.

For #3950 specifically: the trigger is event-grep (a green post-merge cla-evidence
run). `earliest=2026-06-02T09:14:45Z` (the #4784 merge) is correct — verification
can begin the moment the directive lands, and the script's exit-2 path covers the
brief window before the first post-merge green run is indexed by `gh`.

**Anti-pattern guard (from `2026-05-12` directive-enforcement incident class):** the
directive gate rejects a `gh issue create --label follow-through` whose `script=`
file does not exist on disk. When the review skill scaffolds the script at filing
time, it MUST `cp` + customize + `chmod +x` the file BEFORE the `gh issue create`
call — the same in-branch ordering #3950's script follows.

### Phase 3 — Document the trigger→verification mapping in the runbook

**`knowledge-base/engineering/ops/runbooks/followthrough-convention.md` — append a
new `## Trigger → verification mapping` section** (after `## Directive fields`, before
`## Security guarantees`, or at the natural position — additive only). Content:

- A table of the 4 trigger shapes → exit-code probe (the same mapping as Phase 2a,
  expanded with a concrete copy-pasteable script body per shape).
- The script-scaffolding contract: `cp` the stub template, fill the probe, `chmod +x`,
  set `earliest=` (date → trigger date at T00:00:00Z; dependency/event-grep/counter →
  filing date, since the probe self-gates).
- A "First deferred-scope-out instance" note pointing at
  `scripts/followthroughs/cla-evidence-hardening-3950.sh` (#3950) as the worked example
  (mirrors the existing "First user: #3859" note at line 66).
- Reiterate: validation lives in `.claude/hooks/follow-through-directive-gate.sh` +
  the sweeper parser; the convention does not re-validate.

## Files to Create

- `scripts/followthroughs/cla-evidence-hardening-3950.sh` (executable, shellcheck-clean) — Phase 1.

## Files to Edit

- `plugins/soleur/skills/review/references/review-todo-structure.md` — §Re-evaluation
  Trigger (lines 47-53): per-form `→ verification:` annotation + runbook pointer. Phase 2a.
- `plugins/soleur/skills/review/SKILL.md` — §5: one additive `Auto-wire …` subsection
  after line 561. Phase 2b.
- `knowledge-base/engineering/ops/runbooks/followthrough-convention.md` — new
  `## Trigger → verification mapping` section + first-instance note. Phase 3.

**Not edited (verified, per scope constraints):** `.github/workflows/scheduled-followthrough-sweeper.yml`
(no new secret), `scripts/sweep-followthroughs.sh` (reuse parser), `.claude/hooks/follow-through-directive-gate.sh`
(reuse gate), `AGENTS*.md` (no new rule), #3950's body (post-merge only),
`apps/cla-evidence/**` (read-only assertion target).

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200`
then `jq` over each planned file path. The only planned file that exists as an edit
target AND could appear in an open issue is the review skill pair. #3950 itself is the
worked-example target (not an overlap — it is intentionally Ref'd, not Closed, and the
plan creates its verification script). **Disposition: None to fold in.** #3950 is
handled by design (script created here, directive + close happen post-merge).
(Implementer: re-run the overlap query at /work time against the live backlog and
record the result; the corpus may have shifted since planning.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an infrastructure/tooling +
internal-docs change. No user-facing surface (mechanical escalation scan: no new
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`). No Product/UX,
Legal, Marketing, Finance, Sales, Support, or Ops-provisioning implications. The
CTO lens (the only arguably-relevant domain) is satisfied inline by the
Research Reconciliation + Sharp Edges sections (reuse-existing-gate, exit-code
contract, single-section edit boundaries).

## GDPR / Compliance Gate

Skipped — no regulated-data surface touched. The new script reads the public repo
tree + the repo's own Actions run history (no PII, no auth flow, no schema, no
migration, no API route, no `.sql`). None of the (a)-(d) expanded triggers fire:
no LLM/external-API processing of operator data, brand-survival threshold is `none`,
no new cron reading from learnings/specs (the sweeper already exists and is
unchanged), and no new artifact-distribution surface.

## Infrastructure (IaC)

Skipped — no new infrastructure. No server, systemd unit, cron job, vendor account,
DNS record, TLS cert, secret, firewall rule, or monitoring webhook is introduced.
The sweeper workflow and its cron already exist and are unchanged; the new script
runs inside the existing sweep with no new `secrets=` clause. Pure code+docs change
against an already-provisioned surface (detection scan of the plan draft + feature
description matched zero IaC trigger phrases).

## Observability

The follow-through substrate IS the observability layer for this feature — the
sweeper logs every run and surfaces no-directive issues to `$GITHUB_STEP_SUMMARY`
(`scripts/sweep-followthroughs.sh:316-325`).

```yaml
liveness_signal:
  what: daily scheduled-followthrough-sweeper run evaluates #3950's script
  cadence: daily (existing cron in scheduled-followthrough-sweeper.yml)
  alert_target: workflow run page + GITHUB_STEP_SUMMARY no-directive section
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: sweeper logs verdict (PASS/FAIL/TRANSIENT) as an issue comment on #3950; no-directive issues bubble to GITHUB_STEP_SUMMARY
  fail_loud: true  # FAIL comments on the issue; TRANSIENT retries next sweep; PASS closes
failure_modes:
  - mode: hardening regression (a marker disappears from cla-evidence)
    detection: script part (a) exit 1
    alert_route: sweeper posts "### Sweeper run: FAIL" comment on #3950, leaves open
  - mode: cla-evidence CI red after a future change
    detection: script part (b) finds no post-merge green run → exit 2
    alert_route: sweeper posts TRANSIENT comment, retries next sweep (no false close)
  - mode: gh API/network failure during probe
    detection: gh_rc != 0 → exit 2
    alert_route: TRANSIENT comment, retry next sweep
logs:
  where: GitHub Actions run logs for scheduled-followthrough-sweeper + issue-comment trail on #3950
  retention: GitHub default (90d logs; issue comments permanent)
discoverability_test:
  command: gh run list --workflow=cla-evidence.yml --status success --created ">=2026-06-02T09:14:45Z" --json createdAt --jq 'length'
  expected_output: an integer ≥1 (proves the part-b probe returns PASS today); NO ssh
```

## Test Scenarios

1. **Hardening present (today):** run `bash scripts/followthroughs/cla-evidence-hardening-3950.sh`
   locally → prints PASS, exits 0 (markers present + post-merge green run exists).
2. **Hardening regression:** temporarily `mv apps/cla-evidence/scripts/_r2-endpoint.sh /tmp/`,
   re-run → exit 1 (FAIL). Restore the file. (Verifies AC2.)
3. **No post-merge green run (simulated):** set `MERGE_CUTOFF` to a far-future
   timestamp in a throwaway copy → exit 2 (transient), NOT exit 0. (Verifies the
   transient-vs-pass boundary.)
4. **shellcheck:** `shellcheck scripts/followthroughs/cla-evidence-hardening-3950.sh` → clean. (AC4.)
5. **Directive-gate dry test:** compose the #3950 directive in a temp body file and
   confirm `.claude/hooks/follow-through-directive-gate.sh` would PASS it (script
   exists + executable + path under `scripts/followthroughs/` + `earliest` parses).
   Existing test surface: `plugins/soleur/test/ship-followthrough-directive.test.sh`.
6. **Sweeper parser test:** `scripts/sweep-followthroughs.test.sh` still passes
   (no parser change, but confirm the new script is a valid target shape).
7. **Skill-budget:** `bun test plugins/soleur/test/components.test.ts` passes (AC10).

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Add a new AGENTS rule (`hr-`/`wg-`) to enforce auto-wiring | Always-loaded budget is over the 22 KB cap (scope constraint). Skill-instruction enforcement + the existing directive gate already provide mechanical + instruction coverage. |
| Auto-close #3950 in this PR | Premature — the script must be on `main` for the sweeper to find it. Auto-close belongs to the sweeper post-merge (the whole point of the substrate). |
| `Closes #3950` in PR body | Would auto-close at merge before the sweeper verifies — false-resolved state. Use `Ref #3950` (per ops-remediation Sharp Edge + `wg-use-closes-n-in-pr-body-not-title-to`). |
| Duplicate directive validation in the review skill | The precondition gate already validates; duplicating risks drift between two parsers (the gate inlines the awk parser specifically to stay in sync with the sweeper). |
| Extend the sweeper/Inngest function for deferred-scope-outs | Unnecessary — they already consume the `follow-through` label + directive generically. Deferred-scope-outs become follow-throughs by carrying the same label+directive; no code change to the consumers. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is
  filled; threshold = none with a sensitive-path scope-out reason.)
- The new script's part (b) MUST exit **2 (transient)**, never 1 (FAIL), when no
  post-merge green run exists — otherwise the sweeper would comment FAIL on a
  perfectly healthy issue and the operator would get spurious noise. Only the
  hardening-marker regression (part a) is a FAIL. Verified against the ARGUMENTS
  exit-code spec.
- `gh run list --created ">=<ISO>"` is server-side filtered (precedent #4178); do
  NOT re-implement client-side date comparison — it is both slower and a fabrication
  risk (timezone/format bugs). Probe verified to return ≥1 today.
- The script must be `chmod +x` AND committed before the directive references it —
  both the directive gate (line 198-221) and the sweeper (line 169-176) reject a
  missing/non-executable script. For #3950 the directive is added post-merge AFTER
  the script is on `main`.
- §5 SKILL.md edit must be additive-only inside `When filing:`. Run
  `git diff origin/main -- plugins/soleur/skills/review/SKILL.md` and confirm zero
  deletions in lines 484-550 and 577-605 (the gate ranges) — the multi-agent review
  will reject any regression to the cost-of-filing or CONCUR gates.
- `inspect-evidence.sh` `tombstone)` marker: grep with `^[[:space:]]*tombstone\)`
  (anchored + escaped paren). A bare `grep tombstone` would also match a comment or
  a string literal and produce a false PASS if the case arm were removed but the word
  remained elsewhere.
- Use `Ref #3950` not `Closes #3950` (auto-close-at-merge would falsely resolve before
  the sweeper verifies).
