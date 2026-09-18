# Tasks: revive the #7490 follow-through, qualify the `claude plugin update` docs, route the comparator residual upstream

Plan: `knowledge-base/project/plans/2026-09-18-fix-7490-followthrough-revive-and-plugin-update-form-plan.md`
Closes: #7490 · semver:patch · lane: cross-domain (no spec.md — fail-closed default)

## Phase 0: Preconditions (measure, do not assume)

- [ ] 0.1 Record `claude --version`, `claude plugin update --help | head -3`, `claude plugin marketplace update --help | head -3` for the PR body (CLI-verification gate)
- [ ] 0.2 `curl -fsSL --max-time 15 https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json | jq -r .name` → must print `soleur-marketplace`
- [ ] 0.3 Re-census fenced-only open `follow-through` trackers; confirm the set is still {7490, 7985, 6678, 6617, 6488, 5813}
- [ ] 0.4 Baseline green: `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/sweep-followthroughs.test.sh`
- [ ] 0.5 Re-measure the Guard 1 census (files, refs, misses) and set `MIN_REFS` from it (plan-time: 32 refs / 22 files / 1 miss → floor 28)
- [ ] 0.6 Census directive-less-but-fenced trackers (plan-time: 19) — the false-positive blast radius Guard 2 must keep at zero

## Phase 1: Stream A — docs (RED → GREEN)

- [ ] 1.1 RED: rewrite the sync-remedy assertions in `tests/commands/test-sync-producer-reachability.sh` to pin every command `sync.md` emits; run — must fail
- [ ] 1.2 GREEN: edit `plugins/soleur/commands/sync.md` to the generic runtime form (`claude plugin update soleur@<marketplace>` + `claude plugin list`); re-run — green
- [ ] 1.3 Edit `README.md` §Updating (both commands qualified, `soleur-marketplace`; one sentence for the direct-repository path)
- [ ] 1.4 Edit `plugins/soleur/README.md` §Known Issues marketplace-update section (same)
- [ ] 1.5 Edit `plugins/soleur/docs/pages/getting-started.njk` "Updating later?" callout (copy only — no structural tags added)
- [ ] 1.6 Edit `plugins/soleur/docs/pages/claude-code-plugins.njk` FAQ prose + JSON-LD `text` (keep both byte-identical)
- [ ] 1.7 Edit the three published blog posts (`2026-03-16-…`, `2026-03-17-…`, `2026-04-30-…`)
- [ ] 1.8 Edit `knowledge-base/project/README.md` and `ADR-178-shared-bash-primitives-ship-in-plugin.md` (one line each)
- [ ] 1.9 Edit the 14 echo lines across 10 SKILL.md files to the generic runtime form (literal strings; no `$VAR`)
- [ ] 1.10 Verify AC1, AC2, AC3, AC5; run the docs build and verify AC6

## Phase 2: Guard 1 — repo-path lint (RED → GREEN)

- [ ] 2.1 Write `scripts/lint-followthrough-repo-paths.test.sh` first, one named assertion per Guard 1 matrix row (1–10); it must fail (lint absent)
- [ ] 2.2 Write `scripts/lint-followthrough-repo-paths.sh` — `[TARGET_DIR]` arg, `MIN_REFS` floor with a test-only override, `*.test.sh` excluded, `:-` and `source` arms, exit 0/1/2, blind spots in the header
- [ ] 2.3 Confirm the live-tree row is RED on the untouched `plugin-delivery-canary-7490.sh`
- [ ] 2.4 Repoint `REPORTS=` to the archive path; live-tree row GREEN (AC7)
- [ ] 2.5 Register both files in `scripts/test-all.sh` beside the `followthrough-varq-ban` lines
- [ ] 2.6 Run the repointed probe under the `env -i` form and record the output (AC8)

## Phase 3: Guard 2 — sweeper LOUD fenced verdict (RED → GREEN)

- [ ] 3.1 Add/re-pin the sweeper test rows (Guard 2 matrix 1–15), mirroring `t_g3_m1_missing_secret_is_loud` and the G3-M3 sed-mutation harness; run — RED
- [ ] 3.2 Edit `parse_directive`: unified `^ {0,3}(```|~~~)` predicate, `fenced_seen` on a directive opener inside a fence, `END` emits `fenced_directive_count` and `unbalanced_fence`
- [ ] 3.3 Edit `run_one`: meta arms, loud branch gated on open mode, actor-gated dedup, `FENCED_DIRECTIVE=1`, `::error::`, DRY_RUN short-circuit, separate `FENCED_FILE` list
- [ ] 3.4 Edit `main`: collect all three run-level flags, print every annotation, then one `exit 1`
- [ ] 3.5 GREEN; re-run the G3 suite to confirm `MISSING_SECRET` behaviour is unchanged (AC10, AC11)

## Phase 4: Guard 3 — producers agree with the consumer

- [ ] 4.1 `.claude/hooks/ship-soak-followthrough-gate.test.sh`: fenced-only + indented-fence rows (RED) → strip fences in the gate's enrollment loop (GREEN)
- [ ] 4.2 Mirror the same strip into the ship SKILL.md enrollment-gate bash
- [ ] 4.3 `.claude/hooks/follow-through-directive-gate.test.sh`: fenced-only row asserting the new deny reason (RED) → hook edit (GREEN)
- [ ] 4.4 Remove the ```` ```html ```` fence from the ship follow-through issue-body template; add the "unfenced, column 0" note (AC12)
- [ ] 4.5 `followthrough-convention.md`: unfenced sentence in §Author workflow step 4 + a Placement row in `## Directive fields` (AC12)
- [ ] 4.6 Run AC13

## Phase 4.5: Repair the two broken sibling probes before enrolling them

- [ ] 4.5.1 `inngest-doublefire-reading-6617.sh`: `--comments --json comments` → `--json comments`; measure before/after (plan-time: rc 2 → rc 0 PASS)
- [ ] 4.5.2 `gh-pages-cert-reissue-6657.sh`: give the null/absent `https_certificate.state` its own arm distinct from the API-error TRANSIENT; record the measured API response in the header

## Phase 5: Unfence the six bodies (live mutation, measured first)

- [ ] 5.1 For each of 7985, 6678, 6617, 6488, 5813, 7490: run the probe under `env -i` and record rc + last line
- [ ] 5.2 Edit each body: remove only the two fence lines; add `secrets=GH_TOKEN` where the probe calls `gh` and the clause is absent (#7490, #7985, #6617, #5813); bump #7490's `earliest` to `2026-09-21T00:00:00Z`
- [ ] 5.3 `diff` each body before/after — no other line may change — then `gh issue edit N --body-file`
- [ ] 5.4 Verify AC14 and AC14b on the live bodies
- [ ] 5.5 Post the AC16 comment on #7985 with the measured FAIL semantics
- [ ] 5.6 Record the `### Unfenced trackers` table for the PR body (AC15)
- [ ] 5.7 Dry run: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`; read the log (AC17)

## Phase 6: Stream C — upstream

- [ ] 6.1 Re-run `bash scripts/upstream-report-scrub.sh` on the posting record (AC18)
- [ ] 6.2 Operator gate — interactive: present the composed body verbatim and ask for explicit approval before any post; headless: write `decision-challenges.md` in the 5-line informational frame (no `Operator`/`Post-merge`/`Follow-up` bullets) and leave the log `_pending_` (AC20)
- [ ] 6.3 If approved and posted: record the comment URL and the as-posted re-scrub result in the posting log (AC19)
- [ ] 6.4 Comment on #8253 recording the 4th upstream-ask recurrence (AC21)
- [ ] 6.5 File the tracking issue for the general per-verdict sweeper dedup (Not-in-scope item)

## Phase 7: Cross-cutting

- [ ] 7.1 `bash scripts/test-all.sh` full battery green (AC22)
- [ ] 7.2 Plan-path resolution check (AC23)
- [ ] 7.3 PR body: `Closes #7490`, `semver:patch`, diff-scope list, Phase 0 CLI output, `### Unfenced trackers` table (AC24)
