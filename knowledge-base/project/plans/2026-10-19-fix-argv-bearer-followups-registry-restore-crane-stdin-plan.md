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
the next registry recut dispatch (`apply-web-platform-infra.yml:3642` calls the engine).

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
4. The engine refuses to run traced while a registry credential is in the environment.
5. The umbrella accurately shows what is done, and each deferred lead has an owner and a trigger.

**Cut List.** (mechanism -> property -> what already covers it)

- Rewriting the 14 `CAUSE` echoes -> none of the five -> cut, deferred (#10529).
- A shared `::add-mask::` shape helper and repo-wide sweep -> none -> cut, deferred (#10530).
- A new CI workflow for `bash:3.2` -> none -> cut, deferred (#10532); the opt-in row already exists.
- A sweeper change for refusal visibility -> none -> cut, deferred (#10531).
- Widening scanner S6 (htpasswd) to cover login commands -> property 1 -> S6 is bound to htpasswd, its workflow identity and allowlist; a separate stage S8 buys the same property without distorting S6 (CTO ruling).
- A permanent opt-in real-binary crane row -> property 3 -> never runs in CI and gates nothing; replaced by a one-off pinned-binary check in the work phase, output pasted in the PR body (plan-review ruling: mechanical).
- A long ADR-280 addendum restating deferrals and umbrella status -> property 5 -> the four issues and #9757 own those; a 3-5 line addendum records S8 only.
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
   `-u <user>`, `--insecure` and `--password-stdin`. It exits 64 (with a stderr line naming the refused shape, not the
   value) on `-p`, `--password`, `--password=*` or a glued `-p*`, and when `--password-stdin` is absent. It reads the
   password with `pw=$(cat)` from stdin (only in this arm). **`run_engine` (and the battery's `run_suite`/`mutate` runner)
   must redirect the engine's own stdin from `/dev/null`:** in the pipeline form the stub's stdin is the `printf` pipe, but
   a mutation that drops the feeder leaves the stub inheriting the harness stdin, and `cat` would block on an open CI
   stdin instead of seeing EOF. The `REJECT_ME` sentinel check stays, on the stdin value. The
   `printf '%s\n' "$*" >> "$CALLS"` line is unchanged: with no password on argv it can no longer record one.
2. **New suite rows:** (a) one row: the token value appears nowhere in the CALLS log, `login.err` or the engine's
   combined output, for both the sink and GHCR logins (synthetic tokens only, per `cq-test-fixtures-synthesized-only`);
   (b) the existing `REJECT_ME` rows re-pointed at stdin (a sink login the stub rejects exits 5, a GHCR login exits 2);
   (c) xtrace: `bash -x` with only `ZOT_PUSH_TOKEN` set exits 78 before any network call and prints no token; the same
   with only `GHCR_TOKEN` set; one `env SHELLOPTS=xtrace` row; and with neither set the traced run still reaches the usage
   error (the lint's own "unset case still runs" rule). No separate `BASH_ENV` row (same `case "$-"` line).
   There is **no permanent real-binary row**: it would be opt-in, never run in CI and gate nothing. Instead, in the work
   phase, fetch the pinned crane `v0.20.2` release into the scratchpad once and run
   `printf '%s' <synthetic> | crane auth login 127.0.0.1:5000 -u <user> --password-stdin --insecure` against a temp
   `DOCKER_CONFIG`; check `config.json` decodes to `user:password` byte for byte and record the output in the PR body.
   That settles "the flag exists in the pinned version" before the first live recut.
3. **Mutation battery** (`tests/scripts/test-registry-gate-mutation-battery.sh`): rewrite the E01 anchor (~429) and the
   explanatory comment (~349) to the new pipeline line (E01 must still be killed); add three engine mutations: E-new-A
   (revert to `-p "$X"` / drop `--password-stdin`, one mutation: both are killed by the same stub arm), E-new-B (drop the
   `printf` feeder, so the stub reads EOF and the sentinel path breaks), E-new-C (delete the xtrace refusal). Each must
   be killed. The added runtime is noted in the PR body (the battery is the repo's most expensive suite).
4. **Scanner stage S8** in `tests/scripts/test-argv-bearer-sweep.sh` (after S7, same skeleton as S6): see Guard Contract.
   The new rows and the `EXPECTED_TESTS` bump (currently 823, `tests/scripts/test-argv-bearer-sweep.sh` ~7642) are
   **measured from the run after the final row set is fixed**, with a history comment line in the existing ledger style.

### Phase 2 (GREEN): the engine

`scripts/registry-restore-from-ghcr.sh`:

1. Immediately after `set -uo pipefail` (Rule A: before any command other than `set`/`shopt`), add the refusal in the
   **multi-line** form the lint accepts. The lint's regexes are line-anchored (`XTRACE_ARM` needs `*x*)` at the start of its
   own line), and the one-line `case "$-" in *x*) ...` spelling fails it (measured by the Kieran seat on a scratch copy).
   Model it on `scripts/registry-pull-path-health.sh` (~112):

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

   Then run
   `python3 scripts/lint-shell-trace-credential-refusal.py scripts/registry-restore-from-ghcr.sh` and require 0 violations.
   Document exit 78 in the header exit table (lines ~62-75) as "traced invocation only": the apply workflow's restore step
   (`apply-web-platform-infra.yml` ~3672) has no arm for 78, so it would land in the loud `*)` "unenumerated exit" arm; that
   is acceptable (nothing traces the step today, and the workflow cannot be edited without firing the production apply).
2. Replace both logins (lines 558 and 567):
   `if ! printf '%s' "$ZOT_PUSH_TOKEN" | $CRANE auth login "$TARGET" -u "$ZOT_PUSH_USER" --password-stdin $SINK_TLS_FLAG \`
   (the existing continuation with the `>"$WORK/login.out" 2>"$WORK/login.err"` redirects stays) `; then die 5 ...` and the
   GHCR equivalent keeping `die 2`. `printf` is a builtin, so the token never reaches any argv. Not a here-string and not
   process substitution (a here-string is a temp file on bash < 5.1, which would put the secret on disk). The engine runs
   `set -uo pipefail` without `-e` and the pipeline is inside `if !`, so a failed or SIGPIPE'd (141) login still takes the
   die arm; no `|| true`. Honest scope of those die arms: real `crane auth login` only stores credentials and never
   contacts the registry, so they fire for a crane without the flag or an unwritable `DOCKER_CONFIG`; a rejected credential
   surfaces later as DENIED at `digest`/`copy` and is classified to exit 5 by the existing `classify()`.
3. Update the stale comment block above (~529-545) so it no longer describes `-p`.
4. Delete line 40 (`scripts/registry-restore-from-ghcr.sh`) from
   `scripts/lint-shell-trace-credential-refusal.baseline.txt` in the same commit, so the baseline drawdown is real.

### Phase 3: bookkeeping and the decision record

1. `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`: a 3-5 line addendum: the stdin rule now covers
   registry login verbs and stage S8 enforces it; link the four deferral issues once (#10529-#10532). Do not restate
   umbrella status or triggers there (the issues and #9757 own them). No new decision, so no new ADR and no C4 change.
2. Umbrella #9757: **re-fetch the body immediately before editing**, then one edit by line (never a blind whole-body
   replace) with `gh issue edit`: tick items 1, 2 and 4; split the "Found by the S2 review" bullet so (a)-(e) are ticked
   and (f), (g), (h) point at #10531, #10529, #10532, and (b)'s repo-wide remainder at #10530; tick item 5 now as
   "PR #<N> (pending merge)". The line-level evidence lives in the PR body (it says "Ref #9757"), not in a separate
   comment. The issue stays open: closing it is the operator's call.

### Files to Edit

- `scripts/registry-restore-from-ghcr.sh`
- `tests/scripts/test-registry-restore-from-ghcr.sh`
- `tests/scripts/test-registry-gate-mutation-battery.sh`
- `tests/scripts/test-argv-bearer-sweep.sh`
- `scripts/lint-shell-trace-credential-refusal.baseline.txt`
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`

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
- **Threshold decision (challengeable):** aggregate pattern, not single-user incident: the credentials are platform registry tokens on an ephemeral runner, and the change removes an exposure rather than adding a data path; it is the same tier the sibling combined plan (2026-10-12) used.

## Observability

```yaml
liveness_signal:
  what: the apply workflow's registry restore step reports its exit code and a ::error:: line per classified failure (exit 5 credential unusable, exit 2 source unavailable)
  cadence: per registry recut dispatch
  alert_target: the dispatching operator's workflow run page and the restore step summary
  configured_in: .github/workflows/apply-web-platform-infra.yml:3672 (exit-code case) and scripts/registry-restore-from-ghcr.sh die()
error_reporting:
  destination: GitHub Actions run log via ::error:: annotation
  fail_loud: "::error::registry-restore-from-ghcr: could not authenticate to the sink ..." with exit 5; "... ghcr.io ..." with exit 2; the xtrace refusal prints "[FATAL] refusing to trace with a live credential set" with exit 78
failure_modes:
  - mode: a crane without --password-stdin is pinned or fetched
    detection: login exits non-zero, the die arm prints the last 300 bytes of login.err (value-free) and exits 5 or 2
    alert_route: failed workflow step annotation
  - mode: the token reaches argv again (a later edit reintroduces -p)
    detection: stage S8 of tests/scripts/test-argv-bearer-sweep.sh turns RED in CI, and the suite row asserting the token is absent from the recorded argv
    alert_route: failed required CI check on the PR
  - mode: the engine is run traced with a credential
    detection: exit 78 with a value-free message
    alert_route: failed workflow step annotation
logs:
  where: GitHub Actions run log (the restore step); the engine writes no file outside its private scratch dir, removed on exit
  retention: GitHub Actions log retention
discoverability_test:
  command: grep -c -e 'CRANE auth login .* --password-stdin' scripts/registry-restore-from-ghcr.sh
  expected_output: 2
  # A source-text smoke check only (0 before this change, 1 after a sink-only edit, 2 after both). The absence of -p on argv is S8's verdict, not this grep's.
```

## Guard Contract

### Guard 1 — S8: no registry login command carries a password on argv

**Property.** No tracked, non-test, non-comment registry login invocation (`crane auth login`, `$CRANE auth login`,
`docker login`, `$DOCKER_BIN login`, `podman login`) passes a password as an argument.

**Assembly.** The population is **derived**, not listed. The verb alternation must match the engine's own spelling, which
is a variable: `(crane|docker|podman|\$\{?[A-Z_]*(CRANE|DOCKER|PODMAN)[A-Z_]*\}?"?)([[:space:]]+auth)?[[:space:]]+login` (a
literal `crane auth login` pattern finds zero sites in the engine, measured: both converted lines read `$CRANE auth login`).
`git grep -nIE --untracked` over `scripts apps .github plugins`, minus `*.test.sh` and `*.md`; backslash-continuation lines
are joined before testing (the real tree has one: `apps/web-platform/infra/cloud-init-inngest.yml:1878-1879`, where
`"$DOCKER_BIN" login "$ZOT_EP" \` is followed by `-u ... --password-stdin`); comment text is dropped. An *invocation* is
the verb followed by a host token and at least one option, which excludes log strings such as `docker login <url> ok`. A
site is bad if its options hold `-p`, `--password` (any spelling: space, `=`, glued `-p"$X"`). The scan is a function of a
root, so mutation rows run the same text on a scratch repository. Measured at plan time on the real tree: **11 invocation
sites in 6 files**, 9 already `--password-stdin` (action.yml:372; `apply-web-platform-infra.yml` 2804, 3550, 4894, 5331;
`ci-deploy.sh:1377`; `cloud-init-inngest.yml` 971 and 1878; `cloud-init.yml:522`) and the engine's 2 `$CRANE` lines. The work
phase re-measures both numbers with the scan itself and pins them as the floor (sites AND files), not a remembered figure.
Named blind spots (stated, not hidden): a login through a variable whose name carries none of CRANE/DOCKER/PODMAN, `eval`
or a `bash -c` string, and `tests/` (outside the scan roots on purpose, so the stub and the battery do not self-flag). No
allowlist: there is no residual to carry, so none is built.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Engine site reverted to `-p "$X"` | RED |
| 2 | `--password "$X"` and `--password=$X` (long forms) | RED |
| 3 | glued `-p"$X"` | RED |
| 4 | `-p` on a backslash-continuation line (the `$DOCKER_BIN` shape) | RED |
| 5 | `--password-stdin` present together with `-p` (precondition met, property fails) | RED |
| 6 | A SECOND member after a compliant first: a new scratch file holding `docker login -p` | RED |
| 7 | Dispatch: scan roots broken or the verb renamed so fewer sites than the measured floor are seen (including 0) | RED (a scan that reports "0 checked" is never green) |
| 8 | Verb-regex blindness: rename `$CRANE` in the engine to a name the alternation does not carry | RED (the floor sees 9, not 11) |

**Harness rows.** One edit to the SUITE that must drive it RED: narrow the verb alternation in the stage to the literal
`crane|docker|podman` (no variable form); the floor row must then go RED, proving the floor is live against exactly the
miss the review found. Must-PASS inputs that are not the canonical: a comment-only mention of `crane auth login -p`; a
compliant site with the flags in a different order and an extra `--insecure`; the real-tree continuation shape
(`"$DOCKER_BIN" login "$H" \` then `-u u --password-stdin`); and a log string `docker login $URL ok` (not an invocation).

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
| ADR-280 addendum (3-5 lines) | "widen the scanner corpus (or add a stage) in the same change so the gate arrives green" | inferred: the new stage extends a documented rule, and the ADR's scanner description would otherwise go stale |
| #9757 body edit and comment | "Umbrella #9757 ... must STAY OPEN" | inferred: the body's checklist is the ledger; evidence must be recorded or the next reader repeats this premise check |
| deferral issues #10529-#10532 | "file a tracked deferral issue for anything that is not (with a re-evaluation trigger)" | asked |

### Split Assessment

- Subsystems touched: 3 (scripts, tests, knowledge-base)
- Planned files: 6 | Estimated changed lines: ~250 (engine ~30, stub+suite ~70, battery ~30, S8 ~110, baseline 1, ADR addendum ~5)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] The S8 scan (run by `tests/scripts/test-argv-bearer-sweep.sh`) reports no login invocation with `-p`/`--password`; both engine sites carry `--password-stdin` fed by `printf '%s' "$..." |` (the scan, not a hand grep, is the verdict, per the sharp edge on scanner-scope parity).
- [ ] `bash tests/scripts/test-registry-restore-from-ghcr.sh` passes (baseline measured: 85 passed, 0 failed, ~67 s) with the new rows added; the token value is absent from the CALLS log and `login.err`.
- [ ] `bash tests/scripts/test-registry-gate-mutation-battery.sh` kills the re-anchored E01 and the three new engine mutations (E-new-A, E-new-B, E-new-C), with the runner's stdin from `/dev/null`.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` passes with stage S8 and a measured, history-commented `EXPECTED_TESTS` increase; all 8 mutation rows are RED, the harness row (verb alternation narrowed) turns the floor RED, and the must-pass rows are GREEN; the floor is the re-measured pair (sites AND files) from the scan, expected 11 sites in 6 files unless main moved.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` is clean and the full-repo run still passes with the baseline line removed.
- [ ] `bash -x scripts/registry-restore-from-ghcr.sh ...` with `ZOT_PUSH_TOKEN` set exits 78 and prints no token; the refusal is the multi-line form and `python3 scripts/lint-shell-trace-credential-refusal.py scripts/registry-restore-from-ghcr.sh` reports 0 violations.
- [ ] The invoking step (`apply-web-platform-infra.yml` ~3642) and its environment set neither `SHELLOPTS` nor `BASH_ENV` nor `-x` (read the step; a traced run would now exit 78 where it used to proceed).
- [ ] A one-off run of the pinned crane `v0.20.2` (`printf '%s' <synthetic> | crane auth login ... --password-stdin --insecure` against a temp `DOCKER_CONFIG`) stored `user:password`; the output is pasted in the PR body.
- [ ] `git diff --name-only origin/main...HEAD` (merge-base form) contains no path under `apps/web-platform/infra/` and not `.github/workflows/apply-web-platform-infra.yml` or `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (the apply workflow's whole push-path list), so the merge fires no production apply. The pipeline-written files (the generated knowledge-base index if regenerated, `specs/<branch>/session-state.md`, this plan and `tasks.md`) are the only other allowed paths beyond Files to Edit.
- [ ] New bash code was run once in an `ubuntu:24.04` container (CI parity) before the first push.
- [ ] #9757 stays open: items 1, 2, 4 and leads (a)-(e) ticked in one re-fetched, line-level body edit; (f), (g), (h) and (b)-wide point at #10531, #10529, #10532, #10530; item 5 ticked as "PR #<N> (pending merge)"; the line-level evidence is in the PR body.
- [ ] The PR body says "Ref #9757" and contains no closing keyword for it.
- [ ] `plugins/soleur/test/c4-count-parity.test.sh` is green (backs the "no C4 impact" claim).
- [ ] Ship stops at a ready PR; the CI verdict for the ready head is read with `ci-head-verdict.sh` (a red `test` row can belong to the draft run, ADR-276); merge only through the queue on the operator's go-ahead.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent, 2026-10-19, ruled all technical forks (see `knowledge-base/project/specs/feat-one-shot-9757-argv-bearer-followups/decision-challenges.md`): defer leads (b)-wide, (f), (g), (h); new stage S8; stdin stub; `printf | crane auth login --password-stdin`; bookkeeping by body edit plus comment; xtrace refusal settled by the gate. No product, legal, marketing, finance, sales, operations or support implication: an internal credential-handling hardening of a CI script.

## Test Scenarios

- Given the sink credential `REJECT_ME`, when the engine logs in (token on stdin), then it exits 5 and never copies (this proves the engine's die arm against the stub; real crane rejects a bad credential later, at `digest`/`copy`). (integration)
- Given a GHCR credential the stub rejects, when the engine logs in, then it exits 2. (integration)
- Given a synthetic token, when the engine runs to completion, then the token string is absent from the CALLS log, `login.err` and the engine output. (integration)
- Given `bash -x` (or `env SHELLOPTS=xtrace`) and `ZOT_PUSH_TOKEN` set, when the engine starts, then it exits 78 with no token in the output; given only `GHCR_TOKEN`, the same; given neither token set, the traced run reaches the usage error. (integration)
- Given an engine that regresses to `-p "$TOKEN"`, when the stub runs, then it exits 64 and the suite fails. (regression)
- Given each S8 mutation 1-8, when the scan runs on a scratch repo, then it is RED; given the must-pass inputs, then GREEN. (unit)

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
