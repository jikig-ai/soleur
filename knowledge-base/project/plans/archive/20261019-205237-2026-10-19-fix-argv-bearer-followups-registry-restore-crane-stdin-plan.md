---
title: "security: argv-bearer follow-ups, registry-restore crane login off argv and the residual review leads"
type: fix
date: 2026-10-19
slug: argv-bearer-followups-registry-restore-crane-stdin
branch: feat-one-shot-9757-argv-bearer-followups
issue: 9757
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix(security): argv-bearer follow-ups, registry-restore crane login off argv and the residual review leads

Ref #9757 (the umbrella stays OPEN: this plan and its PR use "Ref", never a closing keyword).

## Enhancement Summary

**Deepened on:** 2026-10-19 (after plan-review by DHH, Kieran and code-simplicity; then security-sentinel,
test-design-reviewer, observability-coverage-reviewer and spec-flow-analyzer; a CTO ruling on six forks; gates 4.5-4.12
run: user-brand, observability, PAT, UI, encryption, guard-contract lint, scope check).

### Key improvements

1. **The scanner would have missed the file it exists for.** The engine spells the converted lines `$CRANE auth login`
   (a variable); a literal `crane` pattern finds zero sites. S8 now carries a variable-aware verb alternation, a strict
   invocation rule (host token, option span cut at the first shell operator, flags-before-host covered), a per-file
   continuation join, and a floor measured at 11 sites in 6 files.
2. **The xtrace refusal must be the multi-line `case` block.** The lint's regexes are line-anchored; the one-line form
   fails it (verified on a scratch copy of the engine; the multi-line form reports 0 violations).
3. **The suite could not tell a wrong feeder from a right one.** The stub now records the stdin value it read to a side
   file (`$CALLS.stdin`, host/user/password with distinct synthetic tokens per login) and the suite asserts the exact
   token reached each login; the GHCR login, previously unexercised, gets new rows; a wrong-variable feeder mutation is
   added.
4. **First live use is the pre-destroy D10 rehearsal, not the recut.** `registry-pull-path-health.sh:570` runs this engine
   (invoked from `apply-web-platform-infra.yml` ~2845 and ~3051) before any destroy, so a login failure aborts the gate
   and destroys nothing.
5. **Small hardening on lines this PR already edits** (CTO ruling): `unset` of the four credential names after login,
   `tr '\r\n'` in the login-failure tails, truthful `die` wording plus two runbook rows.

### New considerations discovered

- The stale ADR-280 sentence (line ~466) that says the engine "sits outside every corpus" is false after this PR and is
  edited, not just supplemented.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` pins per-file counts for the engine, the restore suite and
  the sweep suite; the new code can move them.
- The battery's pre-flight anchor audit aborts (rc 2) when an anchor does not resolve, so its RED proof is that abort;
  Phases 1 and 2 land in one push.
- S8 is full-run-only on future PRs (CTO D1): the affected-test array does not name its population and editing it would arm
  every PR-gated battery.

## Overview

Umbrella #9757 tracks the leftovers of the argv-credential sweep. The brief listed five unticked items. A re-read of
`origin/main` (310eab957f) shows that most of them were already converted by later merged PRs, so the umbrella body is
stale. The live code work is **item 5** (`scripts/registry-restore-from-ghcr.sh` puts the sink and GHCR passwords on
`crane auth login -p` argv) together with the two gates that edit drags in (the xtrace-refusal baseline and the argv
scanner corpus). Everything else is either evidence-only (already done), or a review lead the CTO ruled should be
deferred to a tracked issue with a re-evaluation trigger.

**Production hold (stated plainly).** Nothing in this plan edits `apps/web-platform/infra/**` or
`.github/workflows/apply-web-platform-infra.yml`, the only push paths of the production apply
(`apply-web-platform-infra.yml` `on.push.paths`), so merging does not fire the production apply. The brief's warning
about item 1 is moot because item 1 is already done. The pipeline still stops at a ready PR: no merge and no dispatch
of anything production-facing without the operator's per-command go-ahead. The first live use of the new login form is
the D10 VERDICT rehearsal, which runs this engine against a throwaway zot **before** any destroy
(`registry-pull-path-health.sh:570`, reached from `apply-web-platform-infra.yml` ~2845 and ~3051); the recut restore step
(`apply-web-platform-infra.yml` ~3642) is the second caller. A login failure in the rehearsal aborts the gate and destroys nothing.

## Research Reconciliation: brief vs. codebase

| Brief / umbrella claim | Reality on main (evidence) | Plan response |
|---|---|---|
| Item 1: `registry-probe` and `doublefire-probe` arms pass `WEBHOOK_SECRET` to `openssl dgst -hmac` | Converted. `scripts/cutover-inngest.sh` lines 1363/1406/1579/... all use the canonical `HMAC_KEY="$WEBHOOK_SECRET" python3 -I` line; `grep -n dgst scripts/cutover-inngest.sh` is empty. Census allowance exists (`cutover-inngest-workflow.test.sh` GUARD 1, ~1940). PR #10086 (merged 2026-10-12). | Evidence only. Tick on #9757. No `apps/web-platform/infra/**` edit, so no production-apply trigger. |
| Item 2: `2>/dev/null` hides Better Stack reader refusal in `scheduled-inngest-health.yml` / `git-data-cutover.yml` | Converted. `scheduled-inngest-health.yml` ~935-955 captures `BS_ERR`, greps the `SOLEUR_CREDENTIAL_REFUSED` marker and emits `::warning::#9757 dedicated-host arm ...`; `git-data-cutover.yml` ~555-580 does the same per attempt. Introduced by S3 (#9811) and #10086. | Evidence only. Tick on #9757. |
| Item 3(a): `-H @-` with unvalidated `$tok`; own `--config -` with raw `$SIG` | Converted. `cutover-inngest.sh` ~575-593 shape-checks (`_bearer_ok`) before mask and feed; ~3160-3168 checks `SIG` and the Access pair before `--config -`. | Evidence only. |
| 3(b): seven unguarded `::add-mask::` in `cutover-inngest.sh` | Converted there (`_mask_ok`/`_bearer_ok` at ~2512-2603, ~3318). About 40 other sites repo-wide are unguarded (a wider class than the lead named). | cutover-inngest.sh: evidence only. Repo-wide sweep deferred: **#10530**. |
| 3(c): `write-env` not concurrency-safe; `soleur_op_env_upsert` validates only CR/LF | Converted by #10185: locked atomic `_wenv_write` (mkdir owner-pid lock, no flock for macOS), and `soleur_op_env_upsert` now rejects every control character (`soleur_op_has_control_char`, `operator-script.sh` ~1065). | Evidence only. Note the lead asked for `flock`; the shipped design deliberately avoids it (bash 3.2/macOS). |
| 3(d): agent-run markdown teaching argv `openssl dgst -hmac` | Converted. `ship/SKILL.md` ~1107 and `deploy-status-debugging.md` ~13 carry the python3 env-prefix form and a stdin-config curl; stage S7 guards the class. | Evidence only. |
| 3(e): `MARKER_RE` comment lists four emitters, `x-setup.sh` is a fifth | Already fixed (the brief's "verify whether fixed" hunch holds). `git-lock-marker-telemetry.ts` lines 143-148 list six community scripts including `x-setup.sh`. | Evidence only; no `apps/web-platform/**` edit, so no tsc/vitest cycle. |
| 3(f): Cloudflare Access pair probes pin TRANSIENT on shape drift | True: `infra-config-activation-7220.sh` and `infra-config-fatal-channel-7220.sh` exit 2 with the marker. | Deferred: **#10531** (fix belongs in the sweeper). |
| 3(g): response bodies echoed to the public log | Half done: JSON-shape-failure arms use `_body_head` (#10086); 14 non-200 `CAUSE` arms still echo the flattened body (deliberate, #5492). `add-mask` for `PG`/`HB` is guarded now. | Deferred: **#10529**. |
| 3(h): bash 3.2 coverage for `hmac-sha1-b64.sh` | Partly done: `community-argv.test.sh` ~2800-2880 runs the 67-case oracle and the write-env lock path under `bash:3.2`, opt-in via `COMMUNITY_ARGV_DOCKER=1`; no CI job sets it. | Deferred: **#10532** (operator-accepted opt-in shape, C5 of the earlier combined spec). |
| Item 4: `inspect-evidence.sh` xtrace refusal; tracking issue closed | Present on main: `apps/cla-evidence/scripts/inspect-evidence.sh` lines 17-26 (`case "$-"` ... exit 78); #10089 closed 2026-10-12 (#10086). Sibling worktree `feat-one-shot-9756-cla-evidence-sigv4-argv` read-only inspection: no tracked changes, one untracked scratch file (`scripts/.h1probe.*.sh`); no overlap. | Evidence only. Worktree untouched. |
| Item 5: `crane auth login ... -p` at ~558 and ~567 | **Still open** at exactly those lines of `scripts/registry-restore-from-ghcr.sh`. Stub at `tests/scripts/test-registry-restore-from-ghcr.sh` ~241-260 parses `-u`/`-p` and logs `$*` (the token reaches the CALLS file). | The work of this PR. |
| (implied) Item 5 is a plain two-line edit | Not plain: the engine is listed in `scripts/lint-shell-trace-credential-refusal.baseline.txt` line 40, and `ci.yml` runs the lint with `--changed`, so editing the file forces the xtrace refusal. `tests/scripts/test-registry-gate-mutation-battery.sh` anchors the literal old login line (E01, ~429; comment ~349). | Added to scope as required by the gates. |

## Research Insights

**Premise Validation.** Cited by reference: #9757 (open, body stale), #10089 (closed), #10086/#9811/#10185/#10504
(merged), #10119/#10322 (merged), plus the file/line citations above. Each was checked with `git grep`/`sed` on the
worktree (identical to `origin/main`). Held: items 5 and leads (f)-(h) are real. Stale: items 1, 2, 4 and leads (a)-(e).

**ADR corpus.** `ADR-280` (credentials reach curl on stdin config) is the governing decision; this work extends its
rule to `crane` and adds nothing architectural. No ADR rejects `--password-stdin`.

**Property List.**

1. No registry login command (`crane auth login`, `$CRANE auth login`, `docker login`, `$DOCKER_BIN login`, `podman login`) in tracked non-test code carries a password in its argument list.
2. The engine's login still fails closed: any non-zero login (a crane without the flag, an unwritable config) takes the die arm (exit 5 for the sink, 2 for GHCR). Real credential rejection is classified downstream at `digest`/`copy`; the stub's `REJECT_ME` rows prove the die arm, not the registry.
3. The suite proves property 1 against the real login call, and fails if the token ever reaches the recorded argv.
4. The engine refuses to run traced while a registry credential is in the environment, and drops the credential names from its environment after login (children inherit nothing). Stated limit: credentials still rest base64 in `$WORK/dockercfg/config.json` until the EXIT trap's `rm -rf`.
5. The umbrella accurately shows what is done, and each deferred lead has an owner and a trigger.

**Cut List.** (mechanism -> property -> what already covers it)

- Rewriting the 14 `CAUSE` echoes -> none of the five -> cut, deferred (#10529).
- A shared `::add-mask::` shape helper and repo-wide sweep -> none -> cut, deferred (#10530).
- A new CI workflow for `bash:3.2` -> none -> cut, deferred (#10532); the opt-in row already exists.
- A sweeper change for refusal visibility -> none -> cut, deferred (#10531).
- Widening scanner S6 (htpasswd) to cover login commands -> property 1 -> S6 is bound to htpasswd, its workflow identity and allowlist; a separate stage S8 buys the same property without distorting S6 (CTO ruling).
- A permanent opt-in real-binary crane row -> property 3 -> never runs in CI and gates nothing; replaced by a one-off pinned-binary check in the work phase, output pasted in the PR body (plan-review ruling: mechanical).
- A long ADR-280 addendum restating deferrals and umbrella status -> property 5 -> the four issues and #9757 own those; a 3-5 line addendum records S8 only.
- An engine-side control-character guard on the tokens -> none -> deferred to #10530 (CTO D2: tokens arrive single-line via `doppler --plain` inside `$(...)` or workflow env; the guard would run after the destroy and could turn a working recut into exit 5).
- Editing `scripts/lib/test-affected-paths.sh` so S8 selects on PRs -> none -> not adopted (CTO D1): it arms every PR-gated battery; S8 rides the full run on main.
- An S8 clause for a `/usr/bin/printf` or `echo` feeder -> none -> not adopted; stated as a named limit (the feeder could itself carry the token on argv).
- An opt-in whole-line identity pin, an allowlist and an `echo`-feeder clause in S8 -> property 1 -> the derived scan with a measured floor plus the stub's exit 64 already cover them; they would turn S8 red on harmless edits.

**Institutional learnings applied** (`knowledge-base/project/learnings/`):

- `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-...`: the stub must refuse any argv it does not model (exit 64) and the suite must assert the value never reaches the recorded argv.
- `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed`: the crane stub must keep modelling `DOCKER_CONFIG`/auth as real behaviour; the login stays load-bearing.
- `2026-09-04-i-shipped-the-defect-class-my-guard-existed-to-forbid`: assert the property (no value in the trace), not just that the guard exits 78; test `-x`, `env SHELLOPTS=xtrace`, id-only and secret-only modes.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-...`: derive the scanned population, never a hand list; use a floor plus an exact site set.
- `2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute-...`: run the new bash suite once in `ubuntu:24.04` before pushing (CI bash 5.2 differs from the dev host).

**External facts, verified.** go-containerregistry `cmd/crane/cmd/auth.go` (Context7, 2026-10-19): `crane auth login`
has `--password-stdin`; with it the command `io.ReadAll(os.Stdin)`, trims one trailing `\n` then one `\r`, requires a
username/password, and stores credentials via the Docker config store **without contacting the registry**. The repo
pins crane `v0.20.2` (`apply-web-platform-infra.yml` ~2813 and ~3555); the work phase's one-off run re-checks the flag against
that exact version. Installed `crane` is not available locally (`which crane` is empty), so the work phase fetches the
pinned release into the scratchpad for the row.

**Open Code-Review Overlap.** Files this plan edits matched against open `code-review` issues: none match
(`scripts/registry-restore-from-ghcr.sh`, the three `tests/scripts/` files, the baseline file, ADR-280). The only hit in
the wider candidate set is #8593 on `scheduled-inngest-health.yml`, a file this plan does not edit (**Acknowledge**:
different concern, stays open).

## Proposed Solution

### Phase 1 (RED first): tests and the scanner stage, failing against today's engine

1. **Stub redesign** (`tests/scripts/test-registry-restore-from-ghcr.sh` ~241-260). `auth login` accepts only a host,
   `-u <user>`, `--insecure` and `--password-stdin`. It exits 64 (with a stderr line naming the refused shape, never the
   value) on `-p`, `--password`, `--password=*` or a glued `-p*`, and when `--password-stdin` is absent. It reads the
   password with `pw=$(cat)` from stdin, trims one trailing `\n` then one `\r` as real crane does, and appends one line
   `host<TAB>user<TAB>password` to a side file `$CALLS.stdin` (synthetic tokens only; the stub never prints the password
   on any path). The `REJECT_ME` sentinel check stays, on the stdin value. **`run_engine` (and the battery's runner)
   must redirect the engine's own stdin from `/dev/null`:** in the pipeline form the stub's stdin is the `printf` pipe,
   but a mutation that drops the feeder leaves the stub inheriting the harness stdin and `cat` would block on an open CI
   stdin instead of seeing EOF. The `printf '%s\n' "$*" >> "$CALLS"` line is unchanged: with no password on argv it can
   no longer record one.
2. **New suite rows** (all unconditional, so the row total is environment-independent):
   - (a) positive control: with distinct tokens per login (`ZOT_PUSH_TOKEN` and `GHCR_TOKEN` differ and neither equals the
     user), `$CALLS.stdin` holds exactly `<target>\t<zot user>\t<zot token>` and `ghcr.io\t<ghcr user>\t<ghcr token>`.
     This is what kills a wrong-variable feeder; the old stub only checked "non-empty";
   - (b) the token values appear nowhere in the CALLS log, `login.err` or the engine's combined output;
   - (c) **new** GHCR rows (the suite never set `GHCR_USER`/`GHCR_TOKEN` before): a happy path and a rejected GHCR
     credential that exits 2; the existing sink `REJECT_ME` row stays and exits 5;
   - (d) a CR-in-stderr fixture: a stub login that emits `\r::add-mask::x` on stderr produces a `die` message with no CR
     (the `tr '\r\n'` change);
   - (e) post-login environment: the stub, when handling a post-login `copy`, records whether any of
     `ZOT_PUSH_TOKEN GHCR_TOKEN DOPPLER_TOKEN GH_TOKEN_FOR_ENGINE` is set; the row asserts none is (the `unset`);
   - (f) xtrace, with `GHCR_USER=`, `GHCR_TOKEN=`, `ZOT_PUSH_TOKEN=` set or unset **explicitly** per row (an ambient
     `GHCR_TOKEN` in a runner shell must not flip a row), a distinctive token such as `ztok-xtrace-1`, stdin from
     `/dev/null`: `bash -x` with only `ZOT_PUSH_TOKEN` exits 78 before any network call; the same with only `GHCR_TOKEN`;
     neither set, the traced run reaches the usage error; the token is absent from combined output. No separate
     `SHELLOPTS` or `BASH_ENV` row: they resolve to the same `$-` test.
   There is **no permanent real-binary row** (opt-in, never run in CI, gates nothing). Instead the work phase fetches the
   pinned crane `v0.20.2` release into the scratchpad and runs, against a temp `DOCKER_CONFIG`: the happy path
   (`printf '%s' <synthetic> | crane auth login 127.0.0.1:5000 -u <user> --password-stdin --insecure`; `config.json`
   decodes to `user:password`, mode recorded with `stat -c %a`, and it sits under the scratch dir), plus three failure
   shapes with a sentinel token (unwritable `DOCKER_CONFIG`, empty stdin, missing username), grepping each stderr for the
   sentinel. This also settles whether real login contacts the registry (the `die` wording below depends on it). The
   output goes in the PR body.
3. **Mutation battery** (`tests/scripts/test-registry-gate-mutation-battery.sh`). Anchors must use the single-quoted
   `'\''%s'\''` form (the battery's pre-flight anchor audit only reads single-quoted anchors and aborts the whole run with
   rc 2 on a stale one). Re-anchor E01 on the whole login head (`if ! printf '%s' "$ZOT_PUSH_TOKEN" | $CRANE auth login
   "$TARGET"` replaced by `if ! true "$TARGET"`, so "auth skipped" is deterministic and not a SIGPIPE race) and fix the
   comment at ~349. Add engine mutations, each of which must be killed: E-new-A1 (sink line reverted to `-p "$X"`),
   E-new-A2 (GHCR line reverted to `-p "$X"`), E-new-B (drop the `printf` feeder; stdin is `/dev/null`, the sentinel path
   breaks), E-new-D (wrong-variable feeder: `$ZOT_PUSH_USER` into the sink login; killed by row (a)), E-new-C1 (the xtrace
   condition line `if [ -n "${GHCR_TOKEN:+x}${ZOT_PUSH_TOKEN:+x}" ]; then` mutated to `if false; then`), E-new-C2 (the
   GHCR operand dropped from that condition; killed by the GHCR-only row). **The battery's RED proof is its pre-flight abort
   against the unmodified engine, run locally; Phases 1 and 2 therefore land in ONE push** (a Phase-1-only push sends a red
   full CI run including the heavy battery). Added runtime: each mutation re-runs the restore suite (measured ~67 s here;
   the committed weight in `scripts/suite-durations.tsv` is 12 s, `suite-durations-heavy.tsv` has the battery at 491 s):
   reconcile the two figures before writing the PR-body note.
4. **Scanner stage S8** in `tests/scripts/test-argv-bearer-sweep.sh` (after S7, S6's skeleton but a per-file pass for the
   continuation join, not S6's per-line loop): see Guard Contract. Its mutation base repo copies **all** files the floor
   counts (a partial base trips the floor and makes every mutation RED for the wrong reason); reasons are asserted by
   string (`bad:<file>`, `floor`), as S6 does. Procedure for `EXPECTED_TESTS` (currently 823, ~7642): run once with the
   final row set (rows are unconditional), require 823 plus the S8 row count to equal the measured total, add a
   `823 -> N at #9757 (stage S8 ...): measured (N passed, 0 failed)` history line.

### Phase 2 (GREEN): the engine

`scripts/registry-restore-from-ghcr.sh`:

1. Immediately after `set -uo pipefail` (Rule A: before any command other than `set`/`shopt`), add the refusal in the
   **multi-line** form the lint accepts. The lint's regexes are line-anchored (`XTRACE_ARM` needs `*x*)` at the start of its
   own line), and the one-line `case "$-" in *x*) ...` spelling fails it (measured on a scratch copy; the multi-line form
   reports 0 violations). Model it on `scripts/registry-pull-path-health.sh` (~112):

   ```bash
   case "$-" in
     *x*)
       if [ -n "${GHCR_TOKEN:+x}${ZOT_PUSH_TOKEN:+x}" ]; then
         printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
         exit 78
       fi
       ;;
   esac
   ```

   Then run `python3 scripts/lint-shell-trace-credential-refusal.py scripts/registry-restore-from-ghcr.sh` and require 0
   violations. Document exit 78 in the header exit table (lines ~62-75) as "traced invocation only": the apply workflow's
   restore step (`apply-web-platform-infra.yml` ~3672) has no arm for 78, so it would land in the loud `*)` "unenumerated
   exit" arm after the engine's own `[FATAL]` line; acceptable (nothing traces the step today, and the workflow cannot be
   edited without firing the production apply).
2. Replace both logins (lines 558 and 567):
   `if ! printf '%s' "$ZOT_PUSH_TOKEN" | $CRANE auth login "$TARGET" -u "$ZOT_PUSH_USER" --password-stdin $SINK_TLS_FLAG \`
   (the existing continuation with the `>"$WORK/login.out" 2>"$WORK/login.err"` redirects stays) `; then die 5 ...` and the
   GHCR equivalent keeping `die 2`. `printf` is a builtin, so the token never reaches any argv. Not a here-string and not
   process substitution (a here-string is a temp file on bash < 5.1, which would put the secret on disk). The engine runs
   `set -uo pipefail` without `-e` and the pipeline is inside `if !`, so a failed or SIGPIPE'd (141) login still takes the
   die arm; no `|| true`. **Reword both `die` texts** to say the login command itself failed locally (a crane without
   `--password-stdin`, or an unwritable `DOCKER_CONFIG`), not a registry verdict, because the workflow's exit-5/2
   annotations point the operator at credential-rotation and `packages: read` runbooks that do not apply; word it
   conditionally until the one-off pinned-crane run confirms that real `crane auth login` never contacts the registry, and
   confirm the suite's `REJECT_ME` stub text does not assert the old wording. Use `tr '\r\n' '  '` (not `tr '\n' ' '`) in
   `last_err` and in both login-failure tails.
3. **After the GHCR login block** (~line 571) add `unset ZOT_PUSH_TOKEN GHCR_TOKEN DOPPLER_TOKEN GH_TOKEN_FOR_ENGINE` so the
   dozens of `crane` children do not inherit them (CTO D3). Verified: the engine reads `ZOT_PUSH_TOKEN` only at ~137 and
   ~558 and `GHCR_TOKEN` only at ~566-567; the other two names are step env that the engine never references; `unset` of an
   unset name is safe under `set -u`; the workflow's exit-3 retry loop starts a fresh process each time. Stated limit: the
   engine's own initial `/proc/<pid>/environ` still holds them.
4. Update the stale comment block above (~529-545) so it no longer describes `-p`.
5. Delete line 40 (`scripts/registry-restore-from-ghcr.sh`) from
   `scripts/lint-shell-trace-credential-refusal.baseline.txt` in the same commit, so the baseline drawdown is real.

### Phase 3: bookkeeping and the decision record

1. `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`:
   **edit the false sentence at ~line 466** (it says the engine "sits outside every corpus ... tracked on #9757") and add a
   3-5 line addendum: the stdin rule now covers registry login verbs; stage S8 enforces it, with its corpus (whole tracked
   tree minus the named exclusions) and its named blind spots (a feeder that itself carries the token on argv, command
   names carrying none of CRANE/DOCKER/PODMAN, concatenated commands); S8 selects on the full run only, not on PRs (the
   affected-test array does not name its population and editing it arms every PR-gated battery); link the four deferral
   issues once (#10529-#10532). No new decision, so no new ADR and no C4 change.
2. `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` (not under the apply workflow's push paths):
   add two rows to the "Restore exit codes" table (~484-495): exit 5/2 carrying the new "login failed locally" text, and
   exit 78 (traced invocation only; remove `-x`/`SHELLOPTS`/`BASH_ENV`).
3. Umbrella #9757: **re-fetch the body immediately before editing**, then one edit by line (never a blind whole-body
   replace) with `gh issue edit`: tick items 1, 2 and 4; split the "Found by the S2 review" bullet so (a)-(e) are ticked
   and (f), (g), (h) point at #10531, #10529, #10532, and (b)'s repo-wide remainder at #10530; annotate item 5 "in progress:
   PR #<N>" **unticked**, and tick it only after the merge is verified (the ship post-merge step does it with
   `gh issue edit`). The remaining unticked items are why the issue stays open. The line-level evidence lives in the PR
   body (it says "Ref #9757"), not in a separate comment. Closing the issue is the operator's call. Also comment once on
   #10530 that the engine's two token sites were reviewed and left out of this PR (tokens arrive single-line; control-char
   guard deferred there).

### Files to Edit

- `scripts/registry-restore-from-ghcr.sh`
- `tests/scripts/test-registry-restore-from-ghcr.sh`
- `tests/scripts/test-registry-gate-mutation-battery.sh`
- `tests/scripts/test-argv-bearer-sweep.sh`
- `scripts/lint-shell-trace-credential-refusal.baseline.txt`
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` (two exit-code rows)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (only if the per-file counts for the engine, the restore suite or the sweep suite move; regenerate deliberately with that suite's `--write-baseline`)

### Files to Create

- None. S8 and the new rows live in existing suites; `knowledge-base/project/specs/feat-one-shot-9757-argv-bearer-followups/{decision-challenges.md,tasks.md}` are planning artifacts.

Verified paths: every file above exists on `origin/main` (`git ls-files`); `scripts/test-all.sh` already registers
`tests/scripts/registry-restore-from-ghcr` (line 6138) and `tests/scripts/argv-bearer-sweep` (line 6274), so no
registration edit is needed and no new suite appears in the affected-test declarations.

## Architecture Decision (ADR/C4)

No architectural decision is made: this applies ADR-280's existing rule (credentials ride stdin, never argv) to a
second tool and extends its scanner. The ADR task is an **addendum** to ADR-280 (Phase 3.1), not a new ADR, so no
ordinal is claimed. C4: no element, actor, external system, data store or access relationship changes. Checked against
all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the engine is a
CI script invoked by the apply workflow against the already-modelled zot registry and GHCR edges; no new actor, vendor
or relationship is introduced, and no derived cardinality moves (the work touches no workflow count, monitor count or
heartbeat slug). The work phase re-runs `plugins/soleur/test/c4-count-parity.test.sh` to back the "no C4 impact" claim.

## User-Brand Impact

- **If this lands broken, the user experiences:** a registry recut (the post-destroy restore of the pinned image set into zot) failing at login with exit 5 or 2, so a host replace or recut stalls; a downtime-adjacent operator event, not a user-data event. A crane without `--password-stdin`, or an unwritable `DOCKER_CONFIG`, fails closed at login rather than restoring anonymously (a merely wrong credential is rejected later, at `digest`/`copy`).
- **If this leaks, the user's workflow is exposed via:** the zot push token or GHCR token sitting on `crane`'s argv (`/proc/<pid>/cmdline`) and in `bash -x` traces on a CI runner, readable by co-tenant processes or captured in logs. The tokens guard the platform's own image registry, not customer data.
- **Brand-survival threshold:** `aggregate pattern`
- **Second-order surfaces, scoped out (review 2026-10-19):** the new exit 78 is a fail-closed abort path (only on a traced run, which the apply workflow never does); the credentials still rest base64 in `$DOCKER_CONFIG/config.json` until the EXIT trap and remain in the engine's own initial `/proc/<pid>/environ`; and `${ZOT_PUSH_USER}`, `${GHCR_USER}`, `${TARGET}` are non-secret values now flattened centrally by `die()`.
- **Threshold decision (challengeable):** aggregate pattern, not single-user incident: the credentials are platform registry tokens on an ephemeral runner, and the change removes an exposure rather than adding a data path; it is the same tier the sibling combined plan (2026-10-12) used.

## Observability

```yaml
liveness_signal:
  what: the restore callers report the engine exit code with a ::error:: line per classified failure (exit 5, exit 2, and the traced-run [FATAL] line with exit 78)
  cadence: per D10 rehearsal and per registry recut dispatch
  alert_target: the dispatching operator's workflow run page (workflow run log, layer 6) and the restore step summary
  configured_in: .github/workflows/apply-web-platform-infra.yml (rehearsal ~2845 and ~3051 via scripts/registry-pull-path-health.sh:570; restore step exit-code case ~3636-3700) and die() in scripts/registry-restore-from-ghcr.sh
error_reporting:
  destination: GitHub Actions run log via ::error:: annotation (workflow run log, layer 6)
  fail_loud: "::error::registry-restore-from-ghcr: ... login failed locally ..." with exit 5 (sink) or 2 (GHCR); the xtrace refusal prints "[FATAL] refusing to trace with a live credential set" and exits 78, landing in the workflow's unenumerated-exit arm
failure_modes:
  - mode: a crane without --password-stdin is pinned or fetched, or DOCKER_CONFIG is unwritable
    detection: the login exits non-zero, the die arm prints the last 300 bytes of login.err (CR/LF flattened, value-free) as an ::error:: line in the workflow run log (layer 6) and exits 5 or 2
    alert_route: failed workflow step annotation in the workflow run log (layer 6); runbook registry-luks-recut-6929.md exit-code table
  - mode: the token reaches argv again (a later edit reintroduces -p)
    detection: stage S8 of tests/scripts/test-argv-bearer-sweep.sh turns RED on the full CI run on main (it does not select on PRs), and the suite row asserting the stdin value and the argv log
    alert_route: failed CI job in the workflow run log (layer 6)
  - mode: the engine is run traced with a credential
    detection: exit 78 with a value-free [FATAL] line in the workflow run log (layer 6), then the unenumerated-exit ::error:: arm
    alert_route: failed workflow step annotation in the workflow run log (layer 6); runbook exit-78 row
logs:
  where: GitHub Actions run log (the rehearsal and restore steps); the engine writes no file outside its private scratch dir, removed by the EXIT trap
  retention: GitHub Actions log retention
discoverability_test:
  command: grep -c -e '^ *if ! printf .*CRANE auth login .* --password-stdin' scripts/registry-restore-from-ghcr.sh
  expected_output: 2
  # A source-text smoke check only, anchored to code lines (comments cannot match): 0 before this change, 2 after both edits. The absence of -p on argv is S8's verdict, not this grep's.
```

## Guard Contract

### Guard 1 — S8: no registry login command carries a password on argv

**Property.** No tracked, non-test, non-comment registry login invocation (`crane auth login`, `$CRANE auth login`,
`docker login`, `$DOCKER_BIN login`, `podman login`) passes a password as an argument.

**Assembly.** The population is **derived** by exclusion over the whole tracked tree, not listed by root: `git ls-files`
minus `*.test.sh`, `tests/` and `knowledge-base/`; `.md` joins only under `plugins/` (S7 treats agent-run markdown as a
surface; CTO D5). A per-file pass joins backslash-continuation lines (the real tree has one, `cloud-init-inngest.yml:1878-1879`:
`"$DOCKER_BIN" login "$ZOT_EP" \` then `-u ... --password-stdin`), drops comment text, then matches:
verb = `(crane|docker|podman|\$\{?[A-Za-z_]*(crane|docker|podman)[A-Za-z_]*(\[[@*]\])?\}?"?)` case-insensitively, optional
global flags between the binary and the subcommand (`docker --config "$D" login`, `crane --insecure auth login`), then
`([[:space:]]+auth)?[[:space:]]+login`. A literal `crane` pattern finds zero sites in the engine (measured: both converted
lines read `$CRANE auth login`). An *invocation* is the verb, **exactly one host token** (bare, or single/double-quoted),
then at least one option token; the option span is cut at the first `|`, `&&`, `||`, `;`, `>` or `)` so a trailing
`mkdir -p` cannot trip it. A site is **bad** when any option token is `-p`, `--password`, `--password=<v>` or a glued
`-p<non-dash>`, **in any order relative to the host** (`login -p "$X" -u u host` is bad); `--password-stdin` never matches.
The strict host-token rule matters: a loose "any later token starting with `-`" also matches
`scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh:156` (a `grep -qE` pattern) and reads 12 sites in 7 files.
Measured at plan time on the real tree with the strict rule over `scripts apps .github plugins`: **11 sites in 6 files** (re-measured at work time with the tokenising scanner: **12 sites in 7 files**, the plan-time count having missed `plugins/soleur/skills/deploy/references/hetzner-setup.md:37`), 9
already `--password-stdin` (action.yml:372; `apply-web-platform-infra.yml` 2804, 3550, 4894, 5331; `ci-deploy.sh:1377`;
`cloud-init-inngest.yml` 971 and 1878; `cloud-init.yml:522`) and the engine's 2 `$CRANE` lines. The work phase re-measures
both numbers with the scan itself over the final root set and pins them as the floor (sites AND files). Named blind spots
(stated, not hidden): a command whose name carries none of crane/docker/podman (skopeo, oras, regctl, buildah, nerdctl,
cosign are not in the alternation: no site exists today), a command built by concatenation or `eval`, a **feeder that
itself carries the token on argv** (`/usr/bin/printf '%s' "$T" |`, `echo "$T" |` stay green), and the excluded trees.
No allowlist: there is no residual to carry, so none is built. S8 selects on the full run only (CTO D1).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Engine site reverted to `-p "$X"` | RED, reason `bad:scripts/registry-restore-from-ghcr.sh` |
| 2 | `--password "$X"` and `--password=$X` (long forms), one loop row | RED, `bad:` |
| 3 | glued `-p"$X"` and `-pXYZ` before the host | RED, `bad:` |
| 4 | `-p` on a backslash-continuation line (the `$DOCKER_BIN` shape) | RED, `bad:` |
| 5 | `--password-stdin` present together with `-p` (precondition met, property fails) | RED, `bad:` |
| 6 | flags before the host: `login -p "$X" -u u host`; and global flags before the subcommand: `docker --config d login -p ...` | RED, `bad:` |
| 7 | A SECOND member after a compliant first: a new scratch file holding a compliant `docker login` plus one with `-p` | the compliant one GREEN and counted, the `-p` one RED |
| 8 | Dispatch/floor, one parameterised loop: scan roots broken; the verb renamed (`$CRANE` to a name the alternation misses); one site file removed | RED, reason `floor` with the exact site count (including 0) |

**Harness rows.** One edit to the SUITE that must drive it RED: narrow the verb alternation in the stage to the literal
`crane|docker|podman` (no variable form, case-sensitive); the floor row must go RED at 8 of 11 sites, proving the floor is
live against exactly the miss the review found. A **baseline-GREEN control row** (reasons empty, 11 sites in 6 files on the
post-fix tree). Must-PASS inputs that are not the canonical, **drawn from real-tree lines**: the `action.yml:91`
description and `:397` `::error::docker login to zot ...` echo; the `ci-deploy.sh:2440`/`:2451` logger lines
(`docker login $URL ok` / `FAILED class=...`); the `followthroughs` grep pattern at `:156`; the `zot-registry.tf:162`
comment (`docker login -p ... / htpasswd`); the quoted token list at
`.github/scripts/test/test-check-inngest-bootstrap-build.sh:143`; a compliant site with the flags reordered and an extra
`--insecure`; a compliant `--password-stdin` with `&& mkdir -p x` after it; `--password-stdin` placed before the host.

**Anchor.** The stored values are the floor (sites and files). They live in the same test file, so one diff can edit both
the value and the thing it protects; the stage proves consistency, not integrity. What must also move for a weakening to
pass: the `EXPECTED_TESTS` row-count floor at the foot of the file (a deleted S8 row drops the measured total below it and
fails with `ANTI-VACUITY FLOOR`), plus the reviewer-visible S8 literal rows. Because the scan reads the **real tree**,
weakening the engine (re-adding `-p`) is caught without touching any stored value.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "cutover-inngest HMAC sites: in scripts/cutover-inngest.sh, the registry-probe and doublefire-probe arms pass WEBHOOK_SECRET to `openssl dgst -hmac`." [brief] | Research Reconciliation row 1; Phase 3.2 tick | mapped (already done on main, evidence only) |
| 2 | "Better Stack reader stderr callers: scheduled-inngest-health.yml (`2>/dev/null` makes exit 2 read as `__UNREADABLE__`) and git-data-cutover.yml (`2>/dev/null \|\| true`) must surface the stderr" [brief] | Reconciliation row 2; Phase 3.2 | mapped (already done, evidence only) |
| 3 | "Triage each sub-item inline: fix what is in scope, and file a tracked deferral issue for anything that is not (with a re-evaluation trigger)." [brief] | Reconciliation rows 3(a)-(h); issues #10529-#10532; decision-challenges.md | mapped |
| 4 | "apps/cla-evidence/scripts/inspect-evidence.sh: bind the R2 pair behind the xtrace refusal. ... first verify on main whether the refusal already exists; if it does, record evidence only." [brief] | Reconciliation row "Item 4"; Phase 3.2 | mapped (refusal exists, evidence only; sibling worktree inspected read-only) |
| 5 | "`crane auth login --password-stdin` fed from `printf '%s'`; update the stub in tests/scripts/test-registry-restore-from-ghcr.sh to read stdin; widen the scanner corpus (or add a stage) in the same change so the gate arrives green." [brief] | Phase 1 (stub, rows, battery, stage S8), Phase 2 (engine) | mapped |
| 6 | "Umbrella #9757 (argv-bearer follow-ups) must STAY OPEN: the PR body uses \"Ref #9757\", never \"Closes\"." [brief] | Phase 3.2; Acceptance Criteria | mapped |
| 7 | "Do NOT merge or dispatch anything production-facing without the operator's per-command go-ahead; stop at a ready PR and report that hold plainly." [brief] | Overview production-hold paragraph; decision-challenges.md final row | mapped |
| 8 | "Premise check first: re-read main (the previous brief was stale) and verify each item is still unconverted before editing." [brief] | Research Reconciliation table | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/registry-restore-from-ghcr.sh` login edits | "`crane auth login --password-stdin` fed from `printf '%s'`" | asked |
| `tests/scripts/test-registry-restore-from-ghcr.sh` stub and rows | "update the stub in tests/scripts/test-registry-restore-from-ghcr.sh to read stdin" | asked |
| `tests/scripts/test-argv-bearer-sweep.sh` stage S8 | "widen the scanner corpus (or add a stage) in the same change so the gate arrives green" | asked |
| `tests/scripts/test-registry-gate-mutation-battery.sh` E01 anchor and new mutations | "so the gate arrives green" | inferred: the battery anchors the literal old login line, so the change turns it red unless re-anchored |
| xtrace refusal in the engine + `scripts/lint-shell-trace-credential-refusal.baseline.txt` line 40 | "so the gate arrives green" | inferred: the baseline lists the engine and CI runs the lint with `--changed`, so editing the file requires the refusal |
| one-off pinned-crane check (work phase, output in the PR body) | "`crane auth login --password-stdin`" | inferred: the first live use is a rarely-run production recut; a single run retires the flag-exists risk before it |
| runbook exit-code rows, `unset` after login, `tr '\r\n'`, truthful `die` wording | "widen the scanner corpus (or add a stage) in the same change so the gate arrives green" | inferred: small hardening on lines this PR already edits, CTO-ruled (D3, D4, D6) 2026-10-19; each is independently revertable |
| ADR-280 addendum (3-5 lines) | "widen the scanner corpus (or add a stage) in the same change so the gate arrives green" | inferred: the new stage extends a documented rule, and the ADR's scanner description would otherwise go stale |
| #9757 body edit and comment | "Umbrella #9757 ... must STAY OPEN" | inferred: the body's checklist is the ledger; evidence must be recorded or the next reader repeats this premise check |
| deferral issues #10529-#10532 | "file a tracked deferral issue for anything that is not (with a re-evaluation trigger)" | asked |

### Split Assessment

- Subsystems touched: 3 (scripts, tests, knowledge-base; the conditional fixture baseline is under plugins/ and only if counts move)
- Planned files: 7 (+1 conditional baseline) | Estimated changed lines: ~330 (engine ~40, stub+suite ~100, battery ~45, S8 ~130, baseline 1, ADR ~8, runbook ~4)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] The S8 scan (run by `tests/scripts/test-argv-bearer-sweep.sh`) reports no login invocation with `-p`/`--password`; both engine sites carry `--password-stdin` fed by `printf '%s' "$..." |`. The scan, not a hand grep, is the verdict; its floor is the re-measured pair (expected 11 sites in 6 files unless main moved).
- [ ] `bash tests/scripts/test-registry-restore-from-ghcr.sh` passes (baseline measured: 85 passed, 0 failed) with the new rows (a)-(f): exact stdin value per login, token absent from argv log/`login.err`/output, new GHCR rows, CR fixture, post-login environment, xtrace rows.
- [ ] `bash tests/scripts/test-registry-gate-mutation-battery.sh` passes with E01 re-anchored in single-quoted form and E-new-A1, A2, B, C1, C2, D all killed, the runner's stdin from `/dev/null`, and its pre-flight anchor audit reporting M/M with the larger M.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` passes with stage S8: mutations 1-8 RED with their asserted reasons, the harness row turns the floor RED, the baseline-GREEN control and the real-tree must-pass rows are GREEN; `EXPECTED_TESTS` equals 823 plus the S8 row count and the measured total, with a history line.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` is clean, the full-repo run still passes with the baseline line removed, and the engine alone reports 0 violations (multi-line refusal form).
- [ ] `bash -x scripts/registry-restore-from-ghcr.sh ...` with `ZOT_PUSH_TOKEN` set exits 78 and prints no token.
- [ ] Every caller of the engine was read for `-x`/`SHELLOPTS`/`BASH_ENV`: the rehearsal path (`registry-pull-path-health.sh:570`, invoked at `apply-web-platform-infra.yml` ~2845 and ~3051) and the restore step (~3642). None sets them.
- [ ] A one-off run of the pinned crane `v0.20.2` against a temp `DOCKER_CONFIG` stored `user:password` (file mode recorded, under the scratch dir), three failure shapes with a sentinel token leaked nothing to stderr, and whether real login contacts the registry is recorded; the output is pasted in the PR body.
- [ ] `git diff --name-only origin/main...HEAD` (merge-base form) contains no path under `apps/web-platform/infra/` and not `.github/workflows/apply-web-platform-infra.yml` or `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (the apply workflow's whole push-path list), so the merge fires no production apply. The only paths beyond Files to Edit are the pipeline-written ones (the generated knowledge-base index if regenerated, `specs/<branch>/session-state.md`, this plan and `tasks.md`).
- [ ] `bash plugins/soleur/test/fixture-relative-assert.test.sh` is green (baseline regenerated deliberately and listed in Files to Edit only if counts moved).
- [ ] New bash code was run once in an `ubuntu:24.04` container (CI parity) before the first push; Phases 1 and 2 land in one push.
- [ ] #9757 stays open: items 1, 2, 4 and leads (a)-(e) ticked in one re-fetched, line-level body edit; (f), (g), (h) and (b)-wide point at #10531, #10529, #10532, #10530; item 5 annotated "in progress: PR #<N>" unticked and ticked only after the merge is verified; the line-level evidence is in the PR body.
- [ ] The PR body says "Ref #9757", contains no closing keyword for it, states that S8 selects on the full run only, and notes the added battery runtime.
- [ ] `plugins/soleur/test/c4-count-parity.test.sh` is green (backs the "no C4 impact" claim).
- [ ] Ship stops at a ready PR; the CI verdict for the ready head is read with `ci-head-verdict.sh` (a red `test` row can belong to the draft run, ADR-276); merge only through the queue on the operator's go-ahead. After the operator-approved merge, the next D10 rehearsal log (agent-read, no SSH) shows no `[FATAL]`, a green step and `restored=N`.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent, 2026-10-19, ruled all technical forks (see `knowledge-base/project/specs/feat-one-shot-9757-argv-bearer-followups/decision-challenges.md`): defer leads (b)-wide, (f), (g), (h); new stage S8; stdin stub; `printf | crane auth login --password-stdin`; bookkeeping by body edit plus comment; xtrace refusal settled by the gate. No product, legal, marketing, finance, sales, operations or support implication: an internal credential-handling hardening of a CI script.

## Test Scenarios

- Given distinct synthetic tokens for the sink and GHCR, when the engine logs in, then the stub's stdin side file holds exactly each host, user and token (a wrong-variable feeder fails). (integration)
- Given the sink credential `REJECT_ME`, when the engine logs in (token on stdin), then it exits 5 and never copies; given a GHCR credential the stub rejects, it exits 2. These prove the engine's die arms against the stub; real crane rejects a bad credential later, at `digest`/`copy`. (integration)
- Given a synthetic token, when the engine runs to completion, then the token string is absent from the CALLS log, `login.err` and the engine output. (integration)
- Given `bash -x` and only `ZOT_PUSH_TOKEN` set (explicit env), it exits 78 with no token in the output; given only `GHCR_TOKEN`, the same; given neither, the traced run reaches the usage error. (integration)
- Given a stub login that emits `\r::add-mask::x` on stderr, the `die` message contains no CR. (integration)
- Given a post-login `copy`, the stub's environment holds none of `ZOT_PUSH_TOKEN GHCR_TOKEN DOPPLER_TOKEN GH_TOKEN_FOR_ENGINE`. (integration)
- Given an engine that regresses to `-p "$TOKEN"`, when the stub runs, then it exits 64 and the suite fails. (regression)
- Given each S8 mutation 1-8 on the all-files scratch base, when the scan runs, then it is RED with the asserted reason; given the baseline-GREEN control and the real-tree must-pass inputs, then GREEN. (unit)

## Sharp Edges

- The engine's pipeline form depends on `set -uo pipefail` **without** `-e`. If `-e` is ever added, a failed login inside `if !` still behaves, but the xtrace and die arms must be re-checked.
- A here-string (`<<<`) or process substitution for the password is a temp file on bash < 5.1 and puts the secret on disk; keep the `printf` pipe.
- Rule A of the xtrace lint demands the refusal precede every command other than `set`/`shopt`: place it before `TARGET=""` and the `die()` definition.
- Adding rows to `test-argv-bearer-sweep.sh` without raising `EXPECTED_TESTS` still passes; raising it without adding rows reds. Measure the delta from the run and add the history comment line.
- The engine's own login spelling is `$CRANE auth login` (a variable, for the test seam). Any scan keyed on the literal `crane` sees zero engine sites and would stay green over the file it exists for; S8's floor row and mutation 8 exist for that.
- The xtrace lint's regexes are line-anchored: the refusal must be the multi-line `case` block; the one-line spelling fails the lint.
- A stub that reads stdin (`cat`) blocks on an inherited open stdin when a mutation drops the `printf` feeder; the runners redirect the engine's stdin from `/dev/null`.
- The umbrella body edit must re-fetch first: another PR may have edited the checklist since planning.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.

## References

- Umbrella: #9757; tracker #9597; related #7797, #10089 (closed), #10119/#10322 (htpasswd stdin), #10185, #10086, #9811.
- ADR-280, ADR-276 (draft-run CI verdicts). Prior spec: `knowledge-base/project/specs/feat-one-shot-9757-argv-bearer-sweep-combined/`.
- Deferral issues filed this run: #10529 (CAUSE echoes), #10530 (repo-wide add-mask), #10531 (sweeper refusal visibility), #10532 (bash 3.2 in CI).
