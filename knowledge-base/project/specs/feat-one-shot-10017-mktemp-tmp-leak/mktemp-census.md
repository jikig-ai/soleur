# mktemp census + disposition ledger — #10017

Enumerated by `python3 scripts/lint-trap-tempfile-ownership.py --census-files`
(the listing is derived from the same `census_all` pass that counts it — list
and count cannot diverge) on branch `feat-one-shot-10017-mktemp-tmp-leak`.

- Class-b (shell) population at census time: **70** (highwater 70).
- Rule-e (literal `/tmp`|`/var/tmp` base) population: **5** (4 of them outside
  the enumerated dirs).
- Rule-d (py/ts) population: **0**; excluded-tests: 15 (runner-root-owned).

## Class-b members under the enumerated dirs

`plugins/soleur/**`, `scripts/**`, `.claude/hooks/**` — every member gets a row.

| File | Run context | Disposition | Basis |
|---|---|---|---|
| `.claude/hooks/brand-hex-commit-gate.test.sh` | test suite, session+CI | trap-EXIT | suite root + `-p` routing; per-case `rm` only on happy path |
| `.claude/hooks/cla-signed-author-gate.test.sh` | test suite, session+CI | trap-EXIT | same |
| `.claude/hooks/context-reviewed-gate.test.sh` | test suite, session+CI | trap-EXIT | same |
| `.claude/hooks/lib/freeze-lock.test.sh` | test suite, session+CI | trap-EXIT | same |
| `.claude/hooks/pencil-collapse-guard.test.sh` | test suite, session+CI | trap-EXIT | per-case `rm` exists; abort path uncovered |
| `.claude/hooks/phase-surface-hint.test.sh` | test suite, session+CI | trap-EXIT | same |
| `.claude/hooks/security_reminder_hook.test.sh` | test suite, session+CI | trap-EXIT | same |
| `.claude/hooks/ship-unpushed-commits-gate.test.sh` | test suite, session+CI | trap-EXIT | 12+ allocs; same |
| `.claude/hooks/skill-context-queries.test.sh` | test suite, session+CI | trap-EXIT | same |
| `plugins/soleur/scripts/lib/operator-script.sh` | sourced library | annotate-bounded | existing `lint-trap-ownership: ok` — sourced lib; EXIT trap would REPLACE the consumer's (`on_exit`/`cleanup`); every path removes the temp explicitly (#8178 rationale) |
| `plugins/soleur/scripts/lib/session-state.sh` | sourced library | do-not-touch | existing annotation: an EXIT trap re-arms the release-on-success bug; fd-held locks; ~34 consumers (#6752-verified landmine — the plan's `.claude/hooks/lib/session-state.sh` name was wrong; this file is the landmine) |
| `plugins/soleur/scripts/sync-pr-behind.sh` | session-run script | annotate-bounded | both sites already `lint-trap-ownership: ok`; `rm -f` on every path of both functions; residual is one file per kill mid-window |
| `plugins/soleur/scripts/taste-profile-update.sh` | operator/agent-run script | annotate-bounded | allocates `${profile}.tmp.XXXXXX` BESIDE the profile (not /tmp); `mv` on success, `rm -f` on render failure — adds the missing annotation |
| `plugins/soleur/skills/community/scripts/x-setup.sh` | operator-run setup | trap-RETURN | function-local `mktemp` moved into place by `mv`; self-disarming RETURN trap covers every early-return path |
| `plugins/soleur/skills/community/scripts/discord-setup.sh` | operator-run setup | trap-RETURN | same shape |
| `plugins/soleur/skills/community/scripts/linkedin-setup.sh` | operator-run setup | trap-RETURN | same shape |
| `plugins/soleur/skills/community/scripts/bsky-setup.sh` | operator-run setup | trap-RETURN | same shape |
| `plugins/soleur/skills/eval-harness/test/extract-block.test.sh` | test suite | trap-EXIT | suite root |
| `plugins/soleur/skills/rclone/scripts/check_setup.sh` | operator-run doctor | restructure | `mktemp` appears only inside a double-quoted `echo` of install instructions — a DATA mention the census counts; convert the echo to a single-quoted `echo` so no live `mktemp` token exists |
| `plugins/soleur/skills/skill-security-scan/scripts/lib.sh` | sourced library | annotate-bounded | `stdin_to_tempfile` contract: caller owns cleanup — verified all 5 `check-*.sh` callers register `trap 'rm -f "$tmp"…' EXIT`; adds the annotation |
| `plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh` | operator/agent-run script | trap-EXIT | `tmp_manifest` is `mv`'d into place on success; trap covers the failure window |
| `plugins/soleur/test/pencil-adapter-auth-hard-fail.test.sh` | test suite | trap-EXIT | suite root |
| `plugins/soleur/test/ralph-loop.test.sh` | test suite | trap-EXIT | suite root |
| `plugins/soleur/test/resolve-git-root.test.sh` | test suite | trap-EXIT | suite root (10 allocs) |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` | mutation battery | normalize-trap | already HAS an owning EXIT trap (`trap 'restore_all … rm -rf "$WORK"'`) written multi-line; the line-scoped `TRAP_EXIT` predicate cannot see it — flatten to a single `trap '…' EXIT` line, same semantics |
| `scripts/audit-bot-codeql-coverage.sh` | CI + session-run audit | trap-EXIT | `tmpf` is `mv`'d to the telemetry dir on success; trap covers the alloc→mv window |
| `scripts/dogfood/grok-gpu-bootstrap.test.sh` | test suite | trap-EXIT | suite root |
| `scripts/dogfood/grok-measure.sh` | operator-run bench | trap-EXIT | `raw` is read then dropped; never removed |
| `scripts/domain-model-drift.test.sh` | test suite | trap-EXIT | 10+ repo allocs under one suite root |
| `scripts/file-upstream-ask-8160.sh` | one-shot filing tool | annotate-bounded | `mktemp -d` output dir IS the deliverable (existing annotation; also a rule-e member — the literal `/tmp` base is deliberate) |
| `scripts/lib/git-data-boot-signal-poll.sh` | sourced library | annotate-bounded | sourced; existing annotation; `.soleur-owned` marker feeds Reaper 3 |
| `scripts/lib/trusted-verdict.sh` | sourced library | annotate-bounded | sourced; existing annotation; every return path `rm -f`s |
| `scripts/lib/tweet-eligibility.test.sh` | test suite | trap-EXIT | suite root |
| `scripts/lib/validate-tweet-draft.test.sh` | test suite | trap-EXIT | suite root |
| `scripts/lint-agents-rule-budget.test.sh` | test suite | trap-EXIT | suite root (7 allocs) |
| `scripts/review-reminder-liveness.test.sh` | test suite | trap-EXIT | suite root |
| `scripts/seccomp-unenforced-alert.test.sh` | test suite | trap-EXIT | suite root |
| `scripts/sentry-issue.test.sh` | test suite | trap-EXIT | suite root |
| `scripts/test-content-publisher.sh` | test suite | trap-EXIT | suite root (8 allocs) |
| `scripts/watch-live-verify-pass.sh` | session-run watcher | trap-EXIT | `body` is `rm -f`'d on the normal path only (the script runs `set -uo` without `-e`, so no intermediate early-exit — the residual window is a signal/kill mid-run); THE ship-phase watcher from the issue's evidence |
| `scripts/watch-live-verify-pass.test.sh` | test suite | trap-EXIT | suite root |

## Mandatory rows

| File | Run context | Disposition | Basis |
|---|---|---|---|
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | sourced gate lib (CI + local test-all) | trap-RETURN (Phase 3) | sole `rung2-archive.*` producer; `_tmp` consumed only inside `_git_data_rung2_hash_at_sha`, sole caller `$( )` at :1913 — self-disarming `RETURN` trap with `/*`-rooted operand assertion; drop `.soleur-owned` marker write; per CTO ruling |
| `plugins/soleur/scripts/lib/session-state.sh` | sourced library | do-not-touch | #6752 verified: EXIT trap re-arms the release-on-success bug; residual is one ~150B file per SIGKILL in a two-statement window |
| `apps/web-platform/infra/workspaces-cutover.sh` | cutover orchestrator | do-not-touch | #6752 verified: the EXIT trap IS the LUKS rollback path; it already carries `trap cleanup EXIT` so it is not a census member — a speculative edit risks the irreversible cutover |
| `scripts/learning-retrieval-bench.sh` (#6752 site) | operator-run bench | already-clean (verified) | every stray alloc (`:530`, `:564`, `:673`) is `rm -f`'d on all paths or lives under `TMP_ROOT` (owning EXIT trap :1168) |
| `scripts/weekly-analytics.sh` (#6752 site) | CI workflow | already-clean (verified) | `response_file` rm'd on all 5 paths; `_preflight_file` trapped then disarmed+rm'd |
| `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` (#6752 site) | session-run scaffold | already-clean (verified) | `trap '_wt_cleanup' EXIT` is the single owner (:230) |
| `scripts/lint-rule-bodies.py` (#9341 candidate) | lint | not-a-member (verified) | `mktemp` appears only inside a shell-string the lint executes; no py-level allocation → rule-d clean |
| `scripts/lint-workflow-local-action-checkout.py` (#9341 candidate) | lint | not-a-member (verified) | same — `mktemp` is prose in a comment, not an allocation |
| #9341 candidates present in census | — | mapped | community `x/discord/linkedin/bsky-setup.sh` (trap-RETURN), `audit-bot-codeql-coverage.sh` (trap-EXIT), `run-self-test.sh` (trap-EXIT) — all six named candidates dispositioned |

## Rule-e members under the enumerated dirs

| File | Disposition | Basis |
|---|---|---|
| `scripts/file-upstream-ask-8160.sh` | annotate-bounded | literal `/tmp` base is the deliverable contract (operator sends the artifacts); existing annotation covers it |

## Prose-instructed allocations (agent-executed; plan amendment Phase 2b)

`mktemp` call sites in skill/agent prose ARE producers — the agent runs them
in its own shell during pipelines (the incident's 28–34KB resync-script
copies and drafted-commit-message files). Each gets a disposition; edits are
instruction text only.

| Site | Disposition | Basis |
|---|---|---|
| `plugins/soleur/skills/ship/SKILL.md` (~8 sites: PR_BODY_FILE, BODY_FILE, `_ps`, TMP_TITLE/TMP_BODY/TMP_COMMITS, gate log, follow-through bodies) | add-cleanup-instruction | body/scratch files are consumed by a `gh` call or diff in the same step — instruction gains `rm -f` at the consumption point |
| `plugins/soleur/skills/ship/SKILL.md:466` detached battery log | bounded-persistence | `mktemp -p "${TMPDIR:-/var/tmp}"` — `/var/tmp`, not the tmpfs `/tmp` class; the log must outlive the detached run it records |
| `plugins/soleur/skills/preflight/SKILL.md:100,112` | already-clean → re-rooted under signed `soleur-run` root | both allocs already pair with `trap 'rm -f "$PR_BODY_FILE" "$COMBINED"' EXIT` (:102) |
| `plugins/soleur/skills/qa/SKILL.md:61,97` | add-cleanup-instruction | QA_LOG / playwright-install log — removed at QA teardown |
| `plugins/soleur/skills/merge-pr/SKILL.md:210` | add-cleanup-instruction | changelog ours/theirs scratch consumed by the merge diff |
| `plugins/soleur/skills/plan/SKILL.md:382` | add-cleanup-instruction | ISSUES_JSON consumed by the same step's read |
| `plugins/soleur/skills/incident/SKILL.md:289` | already-clean → re-rooted under signed `soleur-run` root | `DRAFT` already carries `trap 'rm -f "$DRAFT"' EXIT INT TERM HUP` |
| `plugins/soleur/skills/legal-generate/SKILL.md:138` | already-clean → re-rooted under signed `soleur-run` root | same draft-gate shape, already trapped |
| `plugins/soleur/skills/questionnaire-generate/SKILL.md:145` | already-clean → re-rooted under signed `soleur-run` root | same draft-gate shape, already trapped |
| `plugins/soleur/skills/schedule/SKILL.md:481` | add-cleanup-instruction | MERGE_ERR read for diagnostics then droppable |
| `plugins/soleur/skills/content-writer/SKILL.md:138` | already-clean → re-rooted under signed `soleur-run` root | end step already `rm -rf`s the scratch dir |
| `plugins/soleur/skills/model-launch-review/SKILL.md:100` | add-cleanup-instruction | npm-pack scratch dir removed after extraction check |
| `plugins/soleur/skills/architecture/references/likec4-reference.md:113` | add-cleanup-instruction | anonymous `$(mktemp)` → named `$_c4_out`, consumed then `rm -f` |
| `plugins/soleur/skills/rclone/SKILL.md`, `reproduce-bug/SKILL.md:73`, `admin-ip-refresh/references/…:117`, `.claude/hooks/README.md` | already-clean → re-rooted under signed `soleur-run` root | rclone self-`rm -rf`, README `rm -rf "$R"`, admin-ip `shred -u` trap; reproduce-bug deletes at its Phase-9 checklist |
| `plugins/soleur/skills/work/references/work-scratch-sandboxes.md:52,124` | bounded-persistence | `/var/tmp` seat sandboxes — not the tmpfs `/tmp` class; lifetime is the seat's, owned by the seat protocol |

## Out-of-enumeration class-b members (no edits — recorded for completeness)

`apps/**`, `.github/**`, `tests/**` (except the rung-2 producer above) — 28
members. Bounded CI/test files and infra scripts outside the issue's
enumerated dirs; each is a candidate for a later sweep if it proves
session-run. The census ratchet keeps them fenced meanwhile.

## Already-owned seeds (plan listed as "untrapped"; census disproves)

`.claude/hooks/git-commit-secret-scan.sh`, `pre-merge-auto-close-scan.sh`,
`ship-operator-step-gate.sh`, `ship-soak-followthrough-gate.sh`,
`memory-backstop-mutation-battery.sh` — each carries an owning
`trap … EXIT INT TERM` covering its allocations. No edit; the ledger
corrects the seed list. (`ship-soak-followthrough-gate.sh:161`
`_plan_stripped` is `rm -f`'d on both branches — verified.)

## Prose-site disposition follow-up (review rulings)

Per the CTO ruling row in `decision-challenges.md` (schema-root routing over a
signed-prefix allowlist), every prose-instructed alloc above now places the
artifact inside a `mktemp -d -t soleur-run.$$.XXXXXXXX` root — the `rm` stays
the primary cleanup, and the signed root makes a missed `rm` reaper-eligible
(`schema:<pid>` attribution; bare `tmp.*` stays protected). The normative
pattern lives in `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`.
