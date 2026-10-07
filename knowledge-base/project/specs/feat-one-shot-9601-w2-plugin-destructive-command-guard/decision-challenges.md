# Decision challenges — W2 plugin destructive-command guard

Plan: `knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md`. Persisted by `plan-review` (headless). Each item is a Taste call the plan-review panel disagreed on or the plan overrode; the plan's default is stated, and the CPO sign-off (Phase 0.3) is the place to overturn any of them. None changes operator-requested scope.

## T1 — Keep a copy of the lexer, or move it (Taste)

- Panel: the DHH and devex seats recommended moving `.claude/hooks/lib/filing-shape.pl` into the plugin and pointing `guardrails.sh` at it; the architecture seat recommended a BEGIN/END-marked byte-identical region.
- Plan default: copy plus a byte-identical marked region, enforced by a test. Reason: ADR-256 binds the original to `cron-bash-allowlist-hook.mjs`; moving it edits the filing gate inside a customer-hook PR.
- Re-open when: the filing gate is next touched (tracked follow-up on the W2 deferral issue).

## T2 — Perl as a runtime dependency versus a bash-only splitter (Taste)

- Panel: the DHH seat called Perl a P0 for a customer plugin; the devex seat asked for the alternative to be priced; the simplicity seat said keep.
- Plan default: Perl, with a priced-and-rejected entry in the Cut List (the grammar rows that decide P1 and P2 are what a bash `xargs`-style splitter already gets wrong, measured on `guardrails.sh`; the lexer is measured to read all of them). Degrades to a raw scan when `perl` is missing (D6).
- Re-open when: a customer reports a perl-less environment, or the CPO prefers a smaller dependency set over fidelity.

## T3 — No decision log, transcript only (Taste)

- Panel: DHH, devex and simplicity seats said cut the local log; the observability layer-7 rule asks for a durable artifact and says stdout alone is a P1.
- Plan default: cut. The harness transcript is the durable artifact. The observability reviewer may re-open at review; the fallback (one append-only line per decision, no command text) is written down in the plan.

## T4 — Devin `exec` coverage deferred (Taste)

- Panel: DHH and simplicity seats said cut the ask-as-deny branch; the spec-flow seat noted it was a dead end for Devin users.
- Plan default: matcher `^Bash$` only, ledger row `skip`, Devin `ask` measurement and `exec` coverage on the follow-up issue. Devin users have no W2 protection until then.

## T5 — Narrower rule set than a general destructive guard (Taste)

- Panel: DHH asked to hold the three charter families; simplicity asked to drop the SQL rule; spec-flow and Kieran asked for more spellings (`cd`, wrappers, `--` suffixes) inside the families.
- Plan default: SQL rule cut (follow-up); spellings of the three families kept (they break P1 with no obfuscation involved); `doppler secrets set` and plain `terraform apply` dropped from spec FR2 and recorded as follow-up candidates. The CPO is asked about each.

## T6 — Kept despite a cut recommendation (Taste)

- `scripts/verify-agent-security-slice1.sh` extension (simplicity seat: cut). Kept because the observability gate needs a command that exists in this PR's tree and reads W2's signal.
- Separate mutation suite (DHH, devex and simplicity seats: fold it in). Kept separate but cut to eight CI rows M1-M8; the rest run once and are recorded.
- ADR-274 (DHH: fold into one amendment). Kept: the vendored-lexer, degrade-posture and decision-set decisions have no existing home; the ADR-157 and ADR-223 amendment lines were dropped.

## T7 — CPO condition C3 satisfied by the ADR, not a filed issue (operator decision, 2026-10-07)

- CPO round 1 required the W2 follow-ups to be a filed tracking issue before merge (C3). The repository's filing gate refuses a roll-up issue without a measured `Fix-Size` (or the `meta/machinery` label, which says "not a user-facing surface" and hides the issue from the operator digest), and a roll-up has no measurable size.
- Operator decision: record the follow-ups in ADR-274 (section "Open follow-ups") and the plan's Non-Goals, per `wg-when-deferring-a-capability-create-a`; do not file. This deviates from the literal wording of C3 and is stated in the PR body. The decision set D1-D9 is unchanged.

## T8 — Prefilter deletion proposed by the simplicity seat, deferred (Taste)

- Panel (post-review, simplicity seat): delete the zero-spawn prefilter. Measured by that seat: about 25 ms saved on the roughly 8% of calls that skip, about 2 ms mean per Bash call, against two defects the review found in it (an unterminated `<(` skipped yet asked by the lexer path, and a first-key read that a decoy `"command"` field could steer).
- Decision: keep and fix. The prefilter is D7 in the CPO-signed set; deleting it reopens D7. Both defects are fixed (exactly one `"command"` text; `<(`, `>(`, `<<` and case variants are boundaries) and the invariant is restated in ADR-274 D7 as "no skipped command can be a D1 command".
- Re-open when: the CPO next reviews the decision set, or a measurement shows the saving is lower than the maintenance cost. Recorded under ADR-274 follow-ups.

## T9 — Wrappers beyond D1 not added, documented as NOT DECIDED (Taste)

- Panel: several seats named command forms that run a destructive command through a word outside D1's wrapper table.
- Decision: not added. The hook header's NOT DECIDED list owns the list of these forms (ADR-274 Residuals points there; nothing is copied here). Reason: each widens the signed set and the false-positive budget; the guard is a seatbelt, not a boundary.
- One of them is a plausible agent habit: a heredoc, pipe or here-string fed to a shell. Left undecided; the follow-up (treat the body as code when the command is a shell without `-c`) is recorded.

## T10 — Unquoted `${CLAUDE_PLUGIN_ROOT}` command paths in `hooks.json` left as the plugin-wide convention (Taste)

- Finding: the new hook is registered as `${CLAUDE_PLUGIN_ROOT}/hooks/destructive-command-guard.sh` without quotes, so a plugin root containing a space breaks it.
- Decision: unchanged. `stop-hook.sh`, `welcome-hook.sh`, `unkept-promise-hook.sh`, `browser-snapshot-credential-guard.sh` and `operator-stage-approval.sh` are registered the same way (checked in `plugins/soleur/hooks/hooks.json`); quoting one entry fixes nothing for the plugin. Recorded as a plugin-wide follow-up in ADR-274.
- Note, 2026-10-07 (fix round 1, R13; the lines above are the earlier record and are not edited): `hooks.json` now registers this hook as `bash "${CLAUDE_PLUGIN_ROOT}/hooks/destructive-command-guard.sh"`, so the unquoted path is no longer left as the convention for THIS hook. The earlier count was also off: four of the ten command strings were already written `bash "${CLAUDE_PLUGIN_ROOT}/hooks/..."` (`codex-session-start`, `devin-session-start`, `compaction-state` twice; checked with `jq -r '.. | .command? // empty' plugins/soleur/hooks/hooks.json`), and five unquoted ones remain (`browser-snapshot-credential-guard`, `operator-stage-approval`, `welcome-hook`, `stop-hook`, `unkept-promise-hook`): a plugin-wide follow-up in ADR-274, not part of this PR.

## T11 — Server-side agents load the plugin outside the hosted env helper; guard left active, cron env unchanged (Taste)

- Finding: twelve functions (eleven `cron-*` and `event-ship-merge`) pass `--plugin-dir plugins/soleur` and build their env with their own `buildSpawnEnv`, so `AGENT_ENV_OVERRIDES` never reaches them; the census and the earlier comments only covered the hosted Agent SDK sessions.
- Decision: no change to any cron env. The guard is active there, an `ask` under `claude -p` blocks, and no D1 command is issued by any of them today (grep of their sources). This is a classification gap, not a demonstrated false positive. Documented in ADR-274 `## Server-side scheduled agents`, the plugin README, the C4 `api` description and the `agent-env.ts` comments. Follow-up: decide per function whether to set the kill switch.
- Note, 2026-10-07 (fix round 1): ADR-274 `## Server-side scheduled agents` now names the skills grepped (the crons run skills, not only prompts), says the non-D1 asks (`bound`, `lexer-empty`, `wrapper-depth`, `unparsed-wrapper`) can also block a headless cron, and points at the vitest census that pins twelve spawn sites and no kill switch in any of them.

## T12 — The hosted "review gate" claim was false for the autonomous default and was corrected (not a Taste call)

- The plan (D8), the README and the ADR-093 addendum said hosted sessions rely on the sandbox and the review gate. `workspaces.bash_autonomous` defaults to `true` for new workspaces (migration 099) and, after a one-time owner acknowledgement, `permission-callback.ts` auto-approves every Bash command that survived `BLOCKED_BASH_PATTERNS`, which does not match `terraform destroy`, `rm -rf` or `git push -f`. Corrected in the README (and its pinned sentence in the hook suite), ADR-274 D8 and C2, a dated append-only note on ADR-093, the `agent-env.ts` comment and the C4 descriptions. The plan's Decision Set text still carries the old phrase by design (its hash is recorded in the PR body).
- Not changed: the decision to disable the guard in hosted sessions. The hosted `ask` path is unmeasured; enabling it there is a follow-up. Whether hosted founders should be protected against these commands in autonomous mode is a product question for the operator.
- Note, 2026-10-07 (fix round 1): the premise correction is item 1 of the re-sign-off list in ADR-274 `## Post-review hardening`, because the CPO signed D8 with the premise "already sandboxed and gated"; the decision is unchanged and the risk the CPO accepted is a different one than the signed text stated.

## T13 — CPO two-round cap spent; post-review hardening disclosed, not re-signed (operator decision needed)

- The CPO signed D1-D10 in two rounds (the cap is in the plan's CPO sign-off step, tasks 0.3.2). The review then changed the shipped hook beyond that text (ADR-274 `## Post-review hardening (2026-10-07)`). The plan's Decision Set text was not edited.
- User-visible changes, in case the operator wants a re-sign-off: listed once, in ADR-274 `## Post-review hardening (2026-10-07)` (the numbered list at its end); not copied here. Everything else is internal.
- Not changed: D1's families, D3's deny set, D5, D6's posture, and the scope of D8/D9 (D8's premise was corrected, see T12).
