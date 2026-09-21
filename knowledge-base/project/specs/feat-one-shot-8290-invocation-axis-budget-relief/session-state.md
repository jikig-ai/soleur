# Session State

## Carry-Forward (from bundle 3 / #8289 ship phase)

Source: `.session-notes/carry-forward-errors-8289-ship.md` (bare-root, persistent). Items verbatim.

### Errors

1. **The archive reference sweep keyed on the full path and certified a miss.**
   After `git mv`-ing the spec dir I swept with the full `knowledge-base/project/specs/...`
   path and reported "residual hits: 0", while the learning still cited the bare `specs/...`
   form. Caught only by re-grepping the directory NAME with no prefix.
   **Prevention:** sweep on the SUBJECT (the moved directory's basename), then read every hit
   and decide each. A residual-zero count is evidence about a string, never about a claim.

2. **I asserted a CI mechanism twice without parsing the workflow.**
   Claimed 14 absent required contexts were "downstream of `detect-changes`". `yaml.safe_load`
   showed `needs: None` on seven of them; the real cause was a queued workflow run. My first
   check used awk and matched comment prose containing `needs:`, producing confident garbage.
   **Prevention:** a claim about a job graph is answered by parsing the YAML, never by
   grep/awk over a file whose comments discuss the same keys.

3. **I compared local-time and UTC timestamps and changed strategy on the result.**
   `git log --format=%ci` is local (+0200); the GitHub API is UTC. I read 19:40/19:45 and
   17:40/17:45 as four merges, concluded main churned every 2-5 min, and stopped a working
   auto-resync monitor. Same two commits. Refuted by observing that every PR merged that day
   carried 2-3 `Merge origin/main` commits and zero GitHub auto-update commits.
   **Prevention:** normalise before comparing (`%cI`, or `TZ=UTC`). Never derive a RATE from
   two sources without checking they share a timezone.

4. **The repo-global-ratchet blind spot fired SIX times on one branch, three during ship.**
   `MARKER_RE` (git-lock-marker-telemetry), the harness-parity census, and eval-harness's
   registry-completeness DEDUP scan each caught a sentinel / invocation form / marker literal
   my change introduced. Every one lives in a suite that names none of my files.
   **Prevention (structural):** before the first push of a ship phase, run the repo-global
   enumerators regardless of what the diff touches — `bun test plugins/soleur/`, the webplat
   `repo-wide` project, and every `*.test.sh` that `git grep`s or `find`s across
   `plugins/soleur/`. "Suites that mention the diff" is the wrong population for this class.

5. **My own commit prose contained a CI-skip token, and the squash merge made it live.**
   #8405's squash message (67,884 bytes) carried the token at line 658 — inside prose ruling
   it OUT as the cause of an earlier outage. Every push-triggered workflow was suppressed for
   the merge: post-merge CI, the version bump, the build/publish + deploy chain. Runs were
   ABSENT not queued; `dynamic`-event runs fired normally; sibling merges released fine.
   **Now gated** by PR #8457 (`scripts/lint-squash-ci-directives.sh` + runbook
   `knowledge-base/engineering/operations/runbooks/squash-ci-directive-skip.md`), so this item
   is durably captured in the repo and does not depend on this file.

6. **Reverting a file left the PR body citing it, and two body scanners caught me in one PR.**
   (a) "…keyword closed #5463 twice" set `closingIssuesReferences: [5463]` while explaining
   that GitHub's parser is negation-blind. Fixed in body AND commit message; verified on the
   FIELD. (b) `Block PR body citing files not in diff` went red on a single unbackticked
   `ship/SKILL.md` in a heading — a file I had reverted after ADR-229's ratchet refused it.
   **Prevention:** when a file is reverted mid-flight, re-scan the body for it. Run the gate's
   own extractor locally rather than guessing which citation it found.

7. **I staged the only copy of these notes in `/tmp`, and a space reclaim deleted them.**
   `/tmp` is tmpfs (16G) and was exhausted, which also killed the Bash tool outright — every
   command returned exit 1 including `echo`, while Read kept working.
   **Prevention:** scratch output belongs in `/tmp`; anything meant to survive a session does
   not. Write carry-forward notes to a persistent path (this file's directory) or commit them.
   Diagnostic value: a total Bash failure with a working Read tool means the shell cannot
   initialise — check `df -h /tmp` first, not the workspace.

8. **A new test file passed a repo-global ratchet locally only because it was untracked.**
   `guard-vacuity-floor` walks `git ls-files`. My battery scored green pre-commit and pushed
   the mutant-construction ratchet 15 -> 16 once tracked. The floor itself was fine; the
   sentinel was uppercase `ANTI-VACUITY:` and `classify_mutant` matches a case-SENSITIVE
   vocabulary, so a correctly-firing floor booked as unconstructible debt.
   **Prevention:** stage-then-run for any new test file — a local green on an untracked suite
   proves nothing about population-based ratchets. And when adding an anti-vacuity floor, copy
   the house sentinel (`FATAL: anti-vacuity: only N assertion(s) executed, floor is M.`)
   verbatim; the phrasing is load-bearing.

**Meta-pattern worth its own learning:** three times in one session I wrote prose ABOUT a
parser trap and triggered that trap (CI-skip token, auto-close keyword, bare path citation).
The fix is not to stop writing about traps — it is to run the trap's own detector over the
prose before shipping it. #8457 automates that for the first of the three.

## Plan (soleur:plan, 2026-09-21)

- Plan: `knowledge-base/project/plans/2026-09-21-refactor-invocation-axis-budget-relief-plan.md`
- Tasks: `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/tasks.md`
- Decision challenges: `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/decision-challenges.md` (DC-1..DC-8)
- Key planning facts:
  - The flip set is 12 (266 words / 1,733 B), not 16.
  - `B_ALWAYS` Δ is 0 B by construction. The live headroom is 1,080 B, which makes ADR-151's recorded 1,453 B stale.
  - A plan-time probe on Claude Code 2.1.278 showed three things: flagged plugin skills leave the listing, the Skill tool refuses them, and a headless slash still runs them.
  - W0 (TUI, Devin) runs FIRST, and a failure triggers the W0-STOP profile.
  - B5 is a pre-registered generation-surface A/B. An EXTEND lands in a follow-up PR.

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-21-refactor-invocation-axis-budget-relief-plan.md
- Status: complete (plan + 9-seat plan-review + deepen)
- Post-plan collision re-probe (closes: 8290): only merged #8405 (cites, closes #8289) — clear.

### Errors
- deepen-plan Phase 4.7 observability gate fired (.ts/.cjs in Files-to-Edit); replaced prose with 5-field schema.
- Three agent outputs corrected: trigger-cron wrongly marked flip-safe (bare-name grep refuted); stale 1800-word budget cited; one wrong learning filename.
- Pre-commit hook regenerated knowledge-base/INDEX.md + KB tag files (outside plans/specs — hook-owned, expected).

### Decisions
- Flip 12 skills, not 16: flag-bootstrap is not a skill; trigger-cron, invoice, flag-list stay model-invocable (pinned by invocation-axis.test.ts with reasons).
- B_ALWAYS delta measured 0 bytes (skill descriptions are a different budget); live headroom 1,080 B vs ADR-151's stale 1,453. Real saving 266 words / 1,733 B of description listing; cap 2561 -> 2295. New ADR (provisional 236) + ADR-151 addendum.
- Upstream-bug preflight first (interactive CLI + Devin); if flagged skills hide from the user, drop the flip and ship `Ref #8290`.
- B5 pre-registered A/B (4 "Never ..." rules, 10pt MWE, $60 cap); improvement -> separate PR for operator ack; no effect -> no-list entry; inconclusive -> ADR + issue only.
- Repo-global ratchets as a mandatory staged step before first push; never scripts/test-all.sh; never close #8292.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst x2, learnings-researcher, functional-discovery, claude-code-guide, cto/cpo/coo/clo, 9-seat plan-review panel, security-sentinel, git-history-analyzer, pattern-recognition-specialist.

## Work Phase (soleur:work, 2026-09-21) — PAUSED at Phase 3 step 5 (paid B5 run)

- Status: Phases 0, 1, 2 done and committed; Phase 3 offline build done; Phase 4 partly done. Nothing pushed.
  - 5b6587e2a invocation axis: 12 flips, invocation-axis.test.ts (Guard 1, 29 ack rows), budget 2561 -> 2295, keep-pins, hand-off rewordings, go.md/help.md notes.
  - cbef8b7ae skill-creator B6 (authoring-levers.md, markdown-heading census, NOTICE). AC-S2 allowlist: audit-skill.md:144 "Tag-only body" (the inverted anti-pattern).
  - e57323bc8 W0 evidence (w0/) + ADR-151 addendum.
  - 04af23e5b B5 offline eval (battery 58/58; promoted in guard-vacuity-floor, ledger 47).
  - ADR-236 committed as a DRAFT: its "Positive-phrasing rewrite" alternatives row reads `B5_ROW_PENDING` and MUST be filled from the verdict before push.
- W0 verdict: PASS (no W0-STOP). Claude Code 2.1.278 honours the key; Devin 3000.10.31 lists flagged skill `[user]`; Codex 0.155.1 ignores it (inert). W0-f: haiku 11 with-desc before and after, so ADR records "no observed listing benefit on 200k-window models".
- Guard 1 mutation matrix: all rows as tabled (guard1-matrix.txt).
- Follow-up filed: #8486 (agent-drivable operator scripts).
- Pre-push ratchet runs so far (at 04af23e5b): `bun test plugins/soleur/` rc=0 (3205 pass / 0 fail); vitest repo-wide was still running (/var/tmp/ratchets-8290/vitest.rc).

### Errors
- Doppler CLI could not read its token: `failed to unlock correct collection '/org/freedesktop/secrets/aliases/default'` (system keyring locked), so ANTHROPIC_API_KEY was unavailable and the paid B5 run could not start. Operator chose to unlock the keyring and resume in a fresh session.
- Plain `/soleur:<name>` in plugin skill prose is RED under harness-parity-tree (ADR-226). Hand-offs in plugins/soleur use canonical `soleur:<name>` + "the operator types"; runbooks (outside the census) keep the slash form.
- lefthook's bun-test hook runs scripts/test-all.sh (operator-forbidden); every commit on this branch uses `LEFTHOOK_EXCLUDE=bun-test`.
- A stream-json parser crashed after its raw file was deleted; re-ran the probe. Prevention: never delete the raw capture until the condensed evidence is verified.

### Remaining (in order)
1. Find ANTHROPIC_API_KEY in Doppler (`doppler me` first), then from plugins/soleur/skills/eval-harness:
   `mkdir -p ~/.cache/soleur-8290 && ANTHROPIC_MAX_TOKENS=300 npx promptfoo eval -c promptfooconfig-rule-phrasing.yaml --repeat 3 -o ~/.cache/soleur-8290/b5-eval-raw.json`
   then `node scripts/rule-phrasing-verdict.cjs ~/.cache/soleur-8290/b5-eval-raw.json --repeat 3`. Cap $60 (fallback --repeat 2 and pass --repeat 2 to the verdict).
2. Write verdict + intermediates + module sha256 + tokens/cost into b5-eval-results.md (gitleaks first); branch per plan Phase 3 step 7 / D6 (REJECT/CEILING -> no-list entry gated on typed confirmation; INCONCLUSIVE -> ADR row + revisit_if issue, no entry; EXTEND -> separate follow-up PR for @deruelle; INVALID/ABORTED -> one rerun then split B5).
3. Fill ADR-236's B5 row; run `bash scripts/check-adr-ordinals.sh` (236 was free on all origin refs).
4. Phase 5 ratchet list (plan §Phase 5) after staging, before the FIRST push; never scripts/test-all.sh.
5. soleur:review (9-seat panel) -> resolve findings -> soleur:qa -> soleur:compound -> soleur:ship (PR #8484, closes 8290 only; never close #8292; Phase 6 ordinal re-check).

## Work Phase (resumed 2026-09-21, second session)

- Doppler: the system keyring file `~/.local/share/keyrings/Default_keyring.keyring` is rejected by
  gnome-keyring-daemon ("invalid or unrecognized format"), so `doppler` cannot read its token from the
  keyring. Worked around by passing the CLI token via `DOPPLER_TOKEN` + an empty `--config-dir`. The
  keyring file itself is not repaired (operator-side).
- The first smoke test hit "credit balance is too low" on the shared Anthropic key (the same key in `ci`
  and all eight `prd*` configs). Better Stack showed the same error in the prod web-platform container
  on 2026-09-19. The operator topped up the credit.
- B5 run: INCONCLUSIVE, $48.85, 648 rows, 0 errors. `ANTHROPIC_MAX_TOKENS` changed from 300 to 3000
  before the run (smoke evidence). ADR-236 row filled; follow-up #8497 filed; no no-list entry.

### Errors
- `ps -eo args` printed the Doppler CLI token, which was passed as `--token` in argv. Switched to the
  `DOPPLER_TOKEN` env var. The operator should revoke and reissue the "omarchy" CLI token.
- The pre-registered 300-token cap silently emptied thinking-model answers. Prevention: smoke-test any
  paid grid with 1 task per arm per model and check the output length before the full run.
