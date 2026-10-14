# Tasks — fix(go): plugin-root resolution for the three `/soleur:go` session gates

Derived from [the plan](../../plans/2026-09-19-fix-go-session-gates-plugin-root-resolution-plan.md) **after** plan review (4 seats; every P0 applied). Issue #8308 (closes); #8283 §2 (refs, resolved); #7453 (NOT folded).

Lane: `cross-domain` (no `spec.md` on this branch — fail-closed default).
Brand-survival threshold: `single-user incident` — CPO sign-off recorded in the plan (approve-with-notes; notes applied). Two declined findings are in [decision-challenges.md](./decision-challenges.md).

## Phase 0 — Measurement (blocking; can invalidate the plan)

- [x] 0.1 Add `knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/arm4-probe/commands/zzzprobe.md`, mirroring the skill probe's quoted-heredoc method so the file records the loader's output, not a paraphrase. Four forms: bare `${CLAUDE_PLUGIN_ROOT}`; the #8061 form `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}`; unbraced `$CLAUDE_PLUGIN_ROOT`; single-quoted `'${CLAUDE_PLUGIN_ROOT}'`.
- [x] 0.2 Run per the probe README recipe (`claude -p --plugin-dir "$(pwd)" --allowedTools "Bash,Skill"`) with a decoy `CLAUDE_PLUGIN_ROOT` live as the control. Run again under the Grok CLI if `command -v grok` succeeds.
- [x] 0.3 Write the delivered bytes to `arm4-probe/arm5-delivered.txt` (machine-readable — row H1 `cmp`s against it; prose in `phase-1-measurement.md` cannot be compared) and the narrative to `phase-1-measurement.md` §Arm 5, including the control line and the Grok cell.
- [x] 0.4 Match a row of the plan's **stop-condition decision table** and take its named action. Two rows are hard stops that write `specs/feat-one-shot-8308-go-gates-plugin-root/phase-0-stop.md`, comment it on #8308 and re-plan without opening a PR. The "probe unrunnable" row writes `deferred-to-AC12` and re-points H1 at that same AC12 capture.

## Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- [x] 1.1 Create `plugins/soleur/test/go-session-gates.test.sh`; source `plugins/soleur/test/test-helpers.sh` **and check `git_fixture_env`'s exit status** (`fixture-env-adoption.test.sh` Guard 5 requires the check, not just the call). Auto-registered by `SUITE_GLOBS` (`scripts/test-all.sh:78`) and walked by `scripts/lint-orphan-test-suites.sh` — no hand registration.
- [x] 1.2 Implement `extract_fence` by copying the fence bookkeeping of `extract_gate_anchor()` in `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` and changing only the inner match — **flag-based**, never `/A/,/B/` (which self-matches and yields an empty body); anchor on the three heading texts, never line numbers. That extractor handles the info string and leading whitespace but not `~~~` or CRLF, so assert go.md uses neither rather than assuming it.
- [x] 1.3 Implement `deliver` — replace only the exact literal `${CLAUDE_PLUGIN_ROOT}`; pin its output against `arm5-delivered.txt`.
- [x] 1.4 Implement `mk_root`, writing **every fixture file from a quoted heredoc** (heredoc bodies are invisible to `plugins/soleur/test/lib/fixture-scan.py`, which is what keeps the two baselines from churning) — fixture; decoy-`evil`; decoy-claiming-`soleur`; payload-absent variants — real `cloud-detect.sh` and `git-repo-readiness-diag.sh` copied, `worktree-manager.sh` stubbed to print `STUB_WORKTREE_MANAGER argv=$*`) and `mk_workspace` (temp git repo, `main`, committed `.mcp.json` differing from the working copy).
- [x] 1.5 Implement `run_gate` composing the repo's two env forms: `env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT -u CLAUDE_PROJECT_DIR HOME="$SCRATCH_HOME" "$BASH_BIN" "$fence"` with `BASH_BIN` from `command -v bash` (`env -u` to unset; the `VAR=value "$BASH_BIN"` prefix from `redact-sentinel.test.sh` to override). Scrub every `DEVIN*` variable, and keep **`HOME` on scratch in every row** so the Devin CLI-cache arm can never reach a developer's real cache.
- [x] 1.5b Adopt the `fixture-relative-assert.test.sh` **triple-check** for verdicts: `pass`/`fail` counters, a per-verdict `VERDICT_LOG` ledger, and an exit-time floor with the ledger as the authority (`grep -c '^FAIL$'`). Use `TMP_ROOT=$(mktemp -d -t …)`, then `: "${TMP_ROOT:?…}"`, then `trap 'rm -rf "$TMP_ROOT"' EXIT`. Cite ADR-188 at H3's skip site and state why it inverts the FAIL-in-CI default (CI does not install the Claude CLI; AC12 carries the real run).
- [x] 1.6 Write rows R1, R2, R3, R3b, R3c, R4, R5, R5b, R5c, R6, R6b, R6c, R7, R8, R9, R10, H1, H2, H3 exactly as the plan's row table specifies — including R10's PASS-count-vs-row-table comparison, the fail-on-fence-count-≠-3 and empty-body rules, R4's ordered `false`/`true` pair (one `true`, measured), and H3's `command -v claude`-derived skip.
- [x] 1.7 Run against unmodified `go.md`; confirm RED on R1–R3, R3b/R3c, R4 (partial), R5b/R5c, R6b/R6c, R8, R9, H3. Capture the run verbatim for `mutation-log.md` — it is the evidence the suite can see the defect it was written for.
- [x] 1.8 Correct `apps/web-platform/test/plugin-root-anchoring.test.ts`: update `ROOT_ASSIGN_LITERAL`; re-verify **every consumer** (`isSafelyAnchored`, P4, P6, P8), not just the constant; keep P1b **whole-file** over `commandFiles()` (fence-scoping would silently narrow an existing guard) and give it the regex predicates `/\$CLAUDE_PLUGIN_ROOT(?!\})/` and `${CLAUDE_PLUGIN_ROOT:`; add P1b's **own** fixture array and positive-control `it` inside the command-surface describe — **not** `ANCHOR_FIXTURES`, whose consumers `G6`/`G6b` are gate-script scanners in the skills describe with a closed tag union asserted by set equality; **raise the `:682` `expect(assertions).toBe(14)` anti-vacuity floor to the new decided-assertion count in the same edit** or the suite is red on arrival; rewrite the header comment's "dual-harness alias" paragraph.
- [x] 1.9 Correct `plugins/soleur/test/workflow-fidelity.test.ts` (rename + new expectations, `not.toContain(':-$CLAUDE_PLUGIN_ROOT')`, `name=soleur` count ≥ 3).
- [x] 1.10 Regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt` and `fixture-dir-operand-assert.baseline.txt` via their suites' `--write-baseline` (both are row-by-row-equality corpora over `git ls-files '*.sh'`, so a new suite necessarily moves them) and **review the regenerated diff line-by-line** rather than accepting it blind.
- [x] 1.11 Confirm 1.8–1.9 are RED against `main`'s `go.md`.

## Phase 1.5 — Architecture record (before the byte change)

- [x] 1.5.1 Add `### Decision 11` to ADR-179 via `soleur:architecture`: the dual-harness order (loader token, `GROK_PLUGIN_ROOT`, Devin cache **only in a non-mutating gate**, never CWD); that arms 2–3 **promote the identity preflight to load-bearing**, which A11 declined to rely on, and why arm 3 is confined; the `SOLEUR_PLUGIN_ROOT_RESOLVE` vocabulary; the Grok precedence outcome Phase 0 measured; the Codex "never search another harness's cache" divergence with its `[ -d ]` scoping; the recorded inconsistency with the 74-file fleet block. **Re-state the option-(a) failure-mode table** — do not append to it.
- [x] 1.5.2 Add amendment item **A15** (A14 is the current last): `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` is a rejected form of the `:-` class; A10 re-cited; the A11 Grok residual restated as open.
- [x] 1.5.3 ADR frontmatter `related:` gains 8308/8283/8061; `related_plans:` gains this plan.
- [x] 1.5.4 Edit `model.c4:423` — the `grokBuild -> plugin` description names the loader-substituted token first and cites decision 11.
- [x] 1.5.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`; `bash plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 2 — go.md

- [x] 2.1 Replace the three `ROOT=` lines with `GATE=<name>` above the opening anchor plus the byte-identical resolver snippet. POSIX only (no `xargs -r`); **never** `set -e`/`set -u`/`set -o pipefail` in these fences.
- [x] 2.2 Rewrite each gate's branch condition to `if [ "$VERIFIED" = true ]`; keep every existing marker string byte-for-byte.
- [x] 2.3 Step 0.5: replace the private `find` with the `[ -d ]`-gated loop over both documented Devin caches (`$HOME/.local/share/devin/cli/plugins/cache`, `/opt/.devin/plugins`), identity-selected, emitting `source=devin-cache`. This arm goes in **Step 0.5 only**.
- [x] 2.4 Step 0: add the session-class gate **inside its own fence** — run `cloud-detect.sh` from the verified root and dispatch only on `local` / `not-local:no-devin-env`; otherwise emit `SOLEUR_SESSION_START_SKIPPED reason=cloud-session`. Keyed on the session classifier, not on `SRC`, because a Devin agent following its INSTRUCTIONS resolves as `plugin-root-token`.
- [x] 2.5 Add the **four** state-keyed sentences after the Step 0.0 fence (only `source=none` on a substituting harness instructs filing a Soleur issue); replace the Step 0 "Preferring GROK_PLUGIN_ROOT…" comment with one naming the arm order and decision 11.
- [x] 2.6 Run every suite with the runner its package actually uses: `bash` for `.test.sh`; `bun test` for `plugins/soleur/**`; `cd apps/web-platform && ./node_modules/.bin/vitest run` for `apps/web-platform/**` (bun test is blocked there by `bunfig.toml`; `npm run -w` fails for lack of a root `workspaces` field).
- [x] 2.7 Apply Guard 1 mutation rows 1–17 and Guard 2 rows 1–7 in a scratch copy; confirm each reddens the named rows and that Guard 1 rows 18–19 and Guard 2 row 8 stay PASS. Write `mutation-log.md` with the Phase 1 red run, per-row results, and the pre/post `lint-guard-contract.py` counts.

## Phase 3 — Verification, issues, PR

- [x] 3.1 AC12 real-harness capture: `claude -p --plugin-dir "$(git rev-parse --show-toplevel)/plugins/soleur" --allowedTools "Bash" "Run each of the /soleur:go Step 0.0, Step 0.5 and Step 0 bash blocks exactly as delivered, then stop."` — commit verbatim as `ac12-capture.txt`.
- [x] 3.2 File three issues: (a) `worktree-manager.sh:82`'s fail-closed banner overstates the guarantee for merged branches with no worktree (lease check at `:2868` is gated on a non-empty path while `:2954` still deletes the remote branch); (b) extend session-start to Devin cloud, gated on (a); (c) the 74-file `soleur-cloud-mode` fleet block resolves the Devin cloud cache by basename with no `name=soleur` check, now inconsistent with go.md.
- [x] 3.3 `python3 scripts/lint-guard-contract.py`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `bash scripts/lint-orphan-test-suites.sh`; `npx markdownlint-cli2` over the changed markdown.
- [x] 3.4 PR body per AC14: `Closes #8308`; the `Refs #8283 — resolves §2` line; `Not folded: #7453`; a `## Changelog` section; links to the three 3.2 issues; the AC12 capture quoted.
- [x] 3.5 `soleur:review` — the `single-user incident` threshold pulls in `user-impact-reviewer`; add `observability-coverage-reviewer` for the layer-7 citation (the plan claims only layer 7's synchronous half and routes the durable half to #7452).
- [x] 3.6 Walk AC1–AC15, ticking only what a command output supports.

## Notes

- Do not fold #7453 (skill-site `${CLAUDE_PLUGIN_ROOT:-…}` migration). Inverse failure, different remedy.
- Do not edit the Codex/Devin/`skills` `go` mirrors — they delegate to `commands/go.md` and carry no gates.
- Do not touch the skills describe in `plugin-root-anchoring.test.ts` or its `G7` floor, so `redact-sentinel.test.sh`'s Test 20 cross-file `T20_FLOOR=18` does not move. (Test 21 in that same suite scans the three SECRET gates, not go.md — it is a regression check here, not coverage of this change.)
- Learning file to write at compound time: directory `knowledge-base/project/learnings/`, topic "a fix for one harness introduced a non-token form, CI pinned it, and the plan's own first draft then reached a destructive dispatch". Pick the date at write time.
