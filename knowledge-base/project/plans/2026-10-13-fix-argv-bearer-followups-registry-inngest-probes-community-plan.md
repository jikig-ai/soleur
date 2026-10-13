---
title: "fix(security): argv-bearer sweep follow-ups (registry htpasswd, inngest heartbeat, probe scripts, community write-env, marker comment)"
type: fix
date: 2026-10-13
slug: argv-bearer-followups-registry-inngest-probes-community
branch: feat-one-shot-10119-10120-10091-10092-10093-argv-bearer-followups
issue: 10119
closes: [10119, 10120, 10091, 10092, 10093]
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix(security): argv-bearer sweep follow-ups

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Five open follow-ups of the argv-bearer sweep (umbrella #9757, which stays OPEN until all five land; every PR body says
`Ref #9757`, never `Closes #9757`, and carries `Closes #N` only for the issues that PR completes) are planned together and
grouped into three pull requests, the fewest that respect the production-apply boundary each file carries:

| PR | Issues closed | Content | What its merge fires | Ends at |
|---|---|---|---|---|
| **A** (this branch) | #10091, #10092, #10093 (skill-markdown part only) | community `write-env` lock + temp-in-target-dir + `mv -f`; `soleur_op_env_upsert` control-character check; `MARKER_RE` comment; six markdown snippets off argv; new battery stage S7 | `web-platform-release.yml` only (a routine app release; plugin non-test files and one `apps/web-platform/server` comment). No infra apply. | normal pipeline (review, QA, ship) |
| **B** | #10119 (and the registry-heartbeat part of #10093, which this PR does not close #10093 for) | `cloud-init-registry.yml`: htpasswd off argv (3 sites), `install -m 600`, two heartbeat curls on `--config -`; battery S6 allowlist deleted, new registry-heartbeat row; rendered-boot-block execution row | **an unattended production registry host replace** (`registry-host-replace-dispatch.yml` push trigger), plus the push apply and the app release | **a green, ready PR with a hand-over note; not merged by the pipeline** |
| **C** | #10120, #10093 (closes it: the last part) | `inngest-bootstrap.sh` heartbeat (re-implemented from `b48247d559`), the three probe scripts, battery S6-HB allowlist deleted | push apply (web-1 SSH re-delivery of three scripts), `mint-inngest-bootstrap-tag.yml` (auto tag, image build, auto pin-bump PR), the app release | **a ready PR with GuardA red by design; not merged by the pipeline** |

Merge order (ruled by the CTO agent, see Decision Classes): A at any time; **B fully settled (replace finished, registry healthy,
heartbeat green) before C is merged**, because C's merge triggers an image build that mirrors to the registry. Each PR body states
"B before C, wait for B healthy". `#10093` is closed by PR C only (its last open part); A and B reference it with `Ref #10093`.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issues | Reality on `origin/main` (2026-10-13) | Plan response |
|---|---|---|
| #10091: `linkedin-setup.sh` is a deferred, unvalidated writer | `linkedin-setup.sh` already carries the byte-identical `_wenv_*` block and calls `_wenv_validate` (done by #10086). All four setup scripts validate. | #10091 reduces to the write path (lock, temp in target dir, `mv -f`) and the lib validator. |
| #10091: extend `soleur_op_env_upsert` to "the same allow-list the setup scripts use" | `soleur_op_env_upsert` already builds a sibling temp (`mktemp "${env_file}.tmp.XXXXXX"`) and `mv`s it (atomic); it is the sink for arbitrary operator-entered credentials (`template.sh`), which legitimately contain `$ " ' space ! # ?`. The setup-script allow-list protects a different sink (curl's stdin config). | **Deviation, CTO-ruled:** the lib check becomes CR/LF plus `[[:cntrl:]]` under `LC_ALL=C` (value-free marker), not the exact allow-list. Recorded as a Decision Class row (user-challenge flavoured: it narrows the issue's wording). |
| #10092: comment lists four emitters, `x-setup.sh` is the fifth | Emitters by grep over `plugins/`: `discord-community.sh`, `discord-setup.sh`, `bsky-community.sh`, `bsky-setup.sh`, `x-setup.sh`, `linkedin-setup.sh` (six). | Comment names all six; comment-only; `MARKER_RE` text unchanged (`SOLEUR_CREDENTIAL_REFUSED\b.*` already matches). |
| #10120: rebase `b48247d559` onto main | `inngest-bootstrap.sh` changed after that commit (#10073, #10128). `git apply --check` of the format-patch against current `HEAD` succeeds (measured), but a clean apply on a baked carrier proves nothing about the heartbeat block's neighbours. | Re-implement guided by the commit (CTO ruling), then re-run the whole battery; the commit is the recipe, not a cherry-pick. |
| #10120 AC5: on the inngest host, check `/proc/<pid>/cmdline` during a tick | That needs host access, and `hr-no-ssh-fallback-in-runbooks` forbids an SSH step. The new script also reaches the host only at a later image deploy or replace. | Replace AC5 with: static argv-free proof (stub rows + dash row), mint run success, pin-bump PR opened, Better Stack heartbeat still arriving once the image deploys, no `SOLEUR_CREDENTIAL_REFUSED` row. Deviation recorded. |
| #10120: "the tag mint is a production apply, hand it to the operator" | `mint-inngest-bootstrap-tag.yml` fires automatically on a push to `main` touching `apps/web-platform/infra/inngest*`; the build has no `push: tags` trigger (ADR-232 A5) and its `bump-cloud-init-pin` job holds `infra-privileged` (refuses a tag-ref run); a tag must sit on a `main` commit (#8775). A pre-merge tag and a pre-merge pin bump are impossible. | PR C cannot carry the bump. Hand-over = merge it (after B settles), then watch the auto mint and the auto pin-bump PR. No manual tag push. |
| #10093: "shrink the allowlist in the sweep's guard row" | `S6H_ALLOW` has 4 entries (three probe scripts and `inngest-bootstrap.sh`), `S6H_ALLOW_CEIL=4`; the registry heartbeat curls are in no population (stage comment: NOT COVERED). | C deletes all four entries (ceiling 4 to 0). B adds a derived registry-heartbeat row (CTO ruling), because the registry is the highest-value untested site. |
| #10093 names four markdown snippets | `git grep` over `plugins/**/*.md` finds more: `agents/engineering/infra/infra-security.md` (8 Cloudflare curls), `agents/engineering/review/deployment-verification-agent.md` (1 table cell), `skills/skill-creator/references/api-security.md:10` (a deliberate BAD example), and prose mentions in `flag-delete`/`flag-list` SKILL.md. | CTO ruling: convert the four named plus the two agent files in PR A; S7 census row with a residual allowlist holding `api-security.md` (+ any prose that stays). Two files beyond the issue text: recorded in Scope Check as `inferred`. |
| #10119: `htpasswd-stdin.test.sh` already measured the contract | Exists on main (263 lines, merged by #10086) with ubuntu and httpd digests; `registry-userdata-budget.sh` measured now: stored 21,500 B vs `REGISTRY_GZIP_BUDGET` 21,600 (headroom ~100 B), cap 32,768. | Reuse its rows; add the rendered-boot-block row there. Budget measured before and after; shortfall paid inside the same file, never by raising the constant. |
| `deploy-script-tests` GuardA is green | Measured green on main now (250/250, pin `vinngest-v1.1.52`). | Baseline recorded; PR C reds it by design (precedent: #10073, #9944). Not a required check (#9081 open). |

## Research Insights

**Premise Validation (Phase 0.6).** `gh issue view` on #10119, #10120, #10091, #10092, #10093 and #9757: all OPEN, none closed by a PR.
Cited paths all exist on `origin/main` (21 checked, including both suites, the battery, the lib and the four community scripts).
Stale: #10091's "linkedin deferred" premise (done) and the "four emitters" count (six). No ADR rejects `htpasswd -i`, stdin config for
heartbeats or a lib control-character check (ADR-280 `adopting` carries the mechanism; its 2026-10-12 addendum already records the
heartbeat-guard deviations). Local branch `keep/9757-inngest-heartbeat-argv` exists with `b48247d559` (446-line patch, 3 files).

**Property List (Phase 0.6b).**

1. No heartbeat URL (registry two, inngest one, three probe scripts) and no zot htpasswd password is an argument of any process.
2. A malformed stored heartbeat URL makes zero requests and logs one value-free `SOLEUR_CREDENTIAL_REFUSED` line (rate-limited on the 60 s inngest unit).
3. Concurrent `write-env` runs lose no key and duplicate none; `.env` is never observable half-written, never wider than mode 600, and never replaced across a filesystem.
4. `soleur_op_env_upsert` refuses a value holding a control character without refusing any legitimate credential.
5. No agent-run markdown teaches a bearer or apikey header on curl's argument list; a recurrence is a RED battery row.
6. The registry host replace and the inngest tag mint are never fired by a pipeline merge; each is a named hand-over.

**Cut List (Phase 0.6b).**

- *A shared heartbeat library* → cut: checkout-less hosts cannot source one (prior plan Cut List); inline `_hb_url_ok` copies exist.
- *Runtime shape guard on the two registry heartbeat curls* → cut (CTO): the URL is a provider-generated Terraform attribute, not operator input; the guard spends scarce gzip bytes.
- *Porting the setup-script allow-list into the lib* → cut (CTO): wrong sink; would refuse real vendor credentials.
- *A persistent `.env.lock` file* → cut (planner, within the CTO's option b): a lock file persists as an untracked artifact in a consumer's repo; lock an fd opened on the target directory instead, mkdir fallback removed on every exit path.
- *A lock in `soleur_op_env_upsert`/`env_reset`* → not asked (the lib already writes atomically; #10091 targets the setup scripts' delete-then-append window). Not deferred, not planned.
- *A pre-merge tag mint or pin bump for #10120* → impossible (#8775, ADR-232 A5); see Reconciliation.
- *A lexer-grade markdown scanner* → cut: one `git grep` pattern with an allowlist, the S4 hmac census is the precedent.

**Relevant learnings** (institutional search, 25 hits; applied below): the 2026-10-06 sweep ratchet learning (process substitution, shape guard, ratchet); 2026-10-11 inline-copy parity learning (pin the contract, not only the copies); `2026-03-13-shell-script-defensive-patterns` (pair `mktemp` with a trap; `grep` rc 1 vs 2); `2026-05-12-cross-session-lock-lease-bash-primitives` (flock / pidfile owner identity); `2026-07-03-cloud-init-32kb-cap` and `2026-07-07-arc-closes-premature-and-subcap-guard-headroom-consumed` (budget headroom is consumed silently; `${var}` in a comment of a templatefile still interpolates); `2026-10-11-env-u-cant-scrub-a-function-three-shell-traps` (`grep -q` SIGPIPE under pipefail, `VAR=x func`); `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern` (no `|| true` that hides a heartbeat failure). Gaps (no precedent): lib `.env` concurrency, `MARKER_RE` emitter comments.

## Problem Statement / Motivation

Same exposure class as the swept sites: a secret is readable by every local user in `/proc/<pid>/cmdline` for the life of a child
process, and (registry heartbeat URLs) additionally through the Hetzner metadata API because they are baked into `user_data`.
The `.env` writer race is a local-tooling integrity defect (measured earlier: parallel runs left duplicate keys), included because
it sits in the same umbrella and rides the same PR as the markdown and comment changes at no extra production cost.

## User-Brand Impact

- **If this lands broken, the user experiences:** a false credential refusal in a converted heartbeat script stops a liveness beat, which pages "host down" for the git-data link, the zot consumer, the inngest consumer or the private NIC; a boot-block mistake in the registry template leaves zot unlaunched on the replaced host (the registry is the sole image pull path, so a degraded registry reads as a deploy outage); a broken `write-env` leaves a founder's `.env` unchanged with a clear refusal (it fails closed).
- **If this leaks, the user's workflow is exposed via:** a local reader of `/proc/<pid>/cmdline` seeing a Better Stack heartbeat URL (spoof "alive"), a zot pull/push password (read or write of the private image registry), or a Sentry/Supabase bearer typed by an agent from a skill snippet into a visible command.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** each site is a same-host local-reader exposure of a rotatable credential with no user data on the path; unchanged from the parent plan.

## Proposed Solution

### PR A — community write-env, lib validator, marker comment, markdown snippets (this branch)

**A1 (#10091), setup scripts.** Add ONE new helper block, byte-identical across `bsky-setup.sh`, `discord-setup.sh`, `x-setup.sh`,
`linkedin-setup.sh` (placed directly after `_wenv_validate`, so it is a second pinned block), e.g.
`_wenv_write <env_file> <remove-ERE> <KEY=VALUE>...`:

1. `umask 077` in a subshell/local scope so every file created is 0600 from birth (no widening window on a new `.env`).
2. Acquire the lock (CTO ruling, option b): `flock` on an fd opened on the target directory when `command -v flock` succeeds, otherwise an owner-pid `mkdir` lock (`.env.lock.d`, stale recovery by dead-pid check, shape copied from `plugins/soleur/hooks/version-banner.sh`), removed on every exit path. No persistent lock file; bash 3.2 safe (no `${v,,}`, `local -n`, `wait -n`).
3. Under the lock: `tmp=$(mktemp "${env_file}.tmp.XXXXXX")` (same directory, so `mv` is a same-filesystem atomic rename), `grep -a -v -E "$remove_ere" "$env_file" > "$tmp"` treating rc 1 as normal and rc 2 as a hard abort that leaves `.env` untouched (the current `|| true` turns an unreadable `.env` into a wiped one), append the new `KEY=VALUE` lines, `chmod 600`, `mv -f "$tmp" "$env_file"`, release. A `RETURN`/explicit cleanup removes the temp on every path (ADR-129 shape already used).
4. Each `cmd_write_env` keeps its own validation and prints exactly what it prints today (the community suite pins stdout/stderr text): only the removal-and-append body is replaced by one `_wenv_write` call with its script-specific ERE (`^(BSKY_HANDLE|BSKY_APP_PASSWORD)=`, the X four, the Discord five, `^LINKEDIN_`).

`community-argv.test.sh`: add the new block to the drift section (extract `_wenv_write` the way `wenv_block` extracts the validator;
byte-identity across four plus a widening mutation); the existing population/round-trip/hostile rows stay. New rows, RED first
(`cq-write-failing-tests-before`): (i) N parallel `write-env` runs yield each key exactly once (measured RED today: duplicates);
(ii) the same with `flock` absent from `PATH` (mkdir fallback); (iii) a `mv` shim records source dir equals target dir and the temp's mode at
rename time is 600 under `umask 000` (from birth, not chmod-after); (iv) a new `.env` under `umask 000` is 600 and no `.env.tmp.*`
or `.env.lock*` remains; (v) an unreadable `.env` aborts and is byte-identical; (vi) a killed run leaves `.env` intact and a stale
mkdir lock is recovered; (vii) must-PASS: a different, legitimate value set and an existing `.env` holding unrelated lines with
CRLF-free odd-but-legal content.

**A1b (#10091), lib.** `soleur_op_env_upsert` keeps its CR/LF refusal and adds a control-character refusal (`LC_ALL=C`,
`[[:cntrl:]]`, covering tab, DEL and the C0 set) with a value-free `SOLEUR_BOOTSTRAP_BAD_ARG key=<K> reason=value-contains-control-char`
(the existing CR/LF reason token is kept for CR/LF). `plugins/soleur/test/operator-script.test.sh`: refusal rows per class, a
must-PASS row proving `$ " ' space ! # ?` values still write, and a row that the marker never contains the value. The lib does NOT
get the community allow-list and the community block is NOT copied into it (two sinks, two checks; the byte-identity pins stay
about the setup scripts). `grep` the lib's `.env` consumers at implementation and record whether any `source`s the file (a
consumer-side hazard to document, not to widen this validator for).

**A2 (#10092).** Comment-only edit of the block above `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts`: list
the six community-skill emitters, name the `var=<NAME> phase=write-env` shape of the setup scripts' write-env refusals, and say the
registry-host emitters (`zot-disk-heartbeat`, `soleur-private-nic-guard`, `zot-log-boot`) never reach this extractor. `MARKER_RE`
itself is untouched. Gate: `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (vitest) and `tsc`. Folded into A because A's
plugin changes already fire `web-platform-release.yml`, so the comment costs no extra release (CTO ruling).

**A3 (#10093 markdown).** Convert each snippet to the CTO-ruled form, preceded by a one-line value-free shape check and one
sentence saying why argv is wrong (it shows in `/proc/<pid>/cmdline`):

```bash
case "$TOKEN" in ''|*[!A-Za-z0-9._~+/=-]*) echo "token refused" >&2; exit 1;; esac
curl --disable --noproxy '*' -fsS --config - "$URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN")
```

(`apikey:` header: `header = "apikey: %s"`; the Supabase example sends both headers, so two `header =` lines.) Files, by content
anchor: `postmerge/SKILL.md` (the Sentry monitors curl), `postmerge/references/sentry-error-count-delta.md` (the issue GET, keeping
`get_rc` capture), `reproduce-bug/SKILL.md` (the Sentry issues curl), `preflight/SKILL.md` (the service-role example),
`agents/engineering/infra/infra-security.md` (8 Cloudflare curls: one shared `case` above the block, one `--config -` per call, or a
tiny shell function defined once), `agents/engineering/review/deployment-verification-agent.md` (the table cell). `flag-delete` and
`flag-list` SKILL.md are converted only if the grep shows a real `curl ... -H` recipe, otherwise listed as prose residual.
`skill-creator/references/api-security.md` keeps its deliberate BAD example and is the S7 allowlist entry.
Do not reference `scripts/lib/bearer-curl.sh` from agent-run markdown (no checkout assumed in a consumer repo).
Skill-description word budget is untouched (no `description:` edit); the `skill-security-scan` fence carve-out applies to bash fences.

**A4. Battery stage S7** in `tests/scripts/test-argv-bearer-sweep.sh` (see Guard 3): derived census, residual allowlist, ceiling.
`EXPECTED_TESTS` is re-pinned from the measured total, never by arithmetic.

### PR B — registry template (#10119) and the registry heartbeat curls (#10093 part)

All in `apps/web-platform/infra/cloud-init-registry.yml`, one commit with its suites and battery rows, so declining the replace is one revert before merge:

1. `_htp_verify` (anchor: the function containing `htpasswd -vb /etc/zot/htpasswd "$1" "$2"`): `printf '%s' "$2" | htpasswd -vi /etc/zot/htpasswd "$1" >/dev/null 2>&1`, then the unchanged `case "$?"` (0 true, 3 false, else unknown). The probe script has no `pipefail`, so `$?` is `htpasswd`'s; a row pins that 127, 6 and 1 still map to `unknown` through the pipe.
2. Boot step (anchor: `htpasswd -Bbn '${zot_pull_user}' "$ZOT_PULL_TOKEN"`, inside `doppler run ... -- bash -s <<'ZOTEOF'` whose first line is `set -euo pipefail`): `install -m 600 /dev/null /etc/zot/htpasswd` replacing the post-hoc `chmod 600`, then two separate pipelines `printf '%s' "$ZOT_PULL_TOKEN" | htpasswd -Bin '${zot_pull_user}' > /etc/zot/htpasswd` and the push line with `>>`; empty-token guards stay above. Each `htpasswd` has its own pipe, so it cannot consume the `bash -s` script text.
3. Two heartbeat curls (CTO ruling, Fork 4), anchors `curl -fsS -m 10 "${disk_heartbeat_url}"` and `curl -fsS -m 10 -o /dev/null "${liveness_heartbeat_url}"`: `curl --disable --noproxy '*' -g -fsS -m 10 --config - < <(printf 'url = "%s"\n' '${disk_heartbeat_url}')` (liveness keeps `-o /dev/null`), the `|| PING_RC=$?` and `if ...; then PING=ok` shapes intact (process substitution preserves curl's status; both scripts are `#!/usr/bin/env bash`). No runtime shape guard (provider-generated Terraform literal; bytes are scarce). Do not add a comment line that contains `${...}` (a templatefile interpolates inside comments).
4. Reword comments that still name the argv form (line-18 trailing comment, the `htpasswd -vb` prose near the probe, `zot-image.provenance.md` "baked with `htpasswd -Bbn`"); the line-18 trailing comment is not stripped from `user_data`, so shortening it buys bytes.
5. Budget: run `bash apps/web-platform/infra/registry-userdata-budget.sh` before and after; ~100 B headroom; a shortfall is paid by stripping non-rationale bytes in the same file, never by raising `REGISTRY_GZIP_BUDGET`.

Tests: `registry-boot-guard.test.sh` stays green (probe-block pins hold: `printf '%s' "$2"` names the function argument; no `printf .*ZOT_*_TOKEN`) and gains the 127/6/1-through-the-pipe row; `htpasswd-stdin.test.sh` gains the rendered-boot-block row: extract the actual ZOTEOF block from the YAML, render `${zot_pull_user}`/`${zot_push_user}` and the `$${...}` escapes, run it through `bash -s` inside the digest-pinned `ubuntu:24.04` + `apache2-utils` image with stubs for `docker`/`doppler`-adjacent commands, failure arms included (a failing first `htpasswd` aborts under `set -e` before the `>>`; no half-written second entry; mode 600 from creation); battery S6 per Guard 2; `.claude/hooks/grep-q-pipe-guard.test.sh` `PRODUCER_JOIN`/`PJ_TRIPLES` re-measured by the derivation if new rows add a stub or producer.

**Hand-over note (the PR stops here).** PR body first line: "Merging this PR replaces the production registry host unattended (registry-host-replace-dispatch.yml push trigger); merge only when the replace can be watched." The note carries the exact steps: merge command (`gh pr merge <N> --squash` after explicit go-ahead; `Closes #10119` in the body, not the title), watch (`gh run list --workflow registry-host-replace-dispatch.yml --limit 3` then `gh run watch <id>`), post-merge read-only check with no SSH (`bash scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK`, expect `htpasswd_pull_matches=true htpasswd_push_matches=true`, a non-unknown `zot_image_digest`, the registry `/v2/` pull path answering 200/401 through the existing health gate), and the abort path (if the dispatcher's read-only preflight refuses, re-fire by hand per its runbook; revert PR re-fires another replace).

### PR C — inngest heartbeat (#10120) and the three probe scripts (#10093 last part)

1. `inngest-bootstrap.sh` (`HEARTBEATSCRIPTEOF`, POSIX `sh`/dash): re-implement from `b48247d559` against current `main`: `https://` tested on its own, then a NEGATED-class `case` over the rest, no trim, no host pin; `printf 'url = "%s"\n' "$INNGEST_HEARTBEAT_URL" | exec /usr/bin/curl --disable --noproxy '*' -gfsS --max-time 10 --config - >/dev/null` (pipe, not heredoc: Rule E refuses a heredoc feeding the config; no `[[ ]]`, no process substitution); a refusal makes zero requests, exits 2, and logs one value-free marker through the existing hourly `dark_arm_emit_due` limiter on its own stamp; the marker is assigned to a variable first so no `logger` line names the URL (the suite bans exactly that shape). `inngest.test.sh`: https canary URL, recording curl stub, twelve hostile or malformed values with zero requests, limiter re-emit row, static POSIX-shape row, and a dash row inside the digest-pinned ubuntu image (fail-closed in CI); floor re-measured (the commit moved 451 to 506; current literal is `INNGEST_MIN_ASSERTIONS=451`).
2. The three probe scripts (bash, `set -u`), same transport as the converted `web-git-data-probe.sh`: copy its `_hb_url_ok` and a per-attempt `_hb_curl` (`curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL")`, a fresh substitution per attempt because one is consumed once). `web-zot-consumer-probe.sh` and `inngest-consumer-probe.sh` `_ping()` (two attempts each), `web-private-nic-guard.sh` `beat()` (its comment "still rides curl's argv (tracked as #9639)" is rewritten). Refusal markers `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<WEB_ZOT_CONSUMER_URL|INNGEST_CONSUMER_URL|WEB_NIC_GUARD_URL>` to stderr (each unit's SyslogIdentifier ships it), folded into the existing fail-soft arm (a refusal is a WARN plus no ping, never an argv fallback). Test seams: the stub curl now records the stdin `url = "` line per attempt and fails on a missing line; enumerate every consumer first (`web-zot-consumer-probe.test.sh` T8 counts argv lines per repo and its stub already records stdin for the credential config; `web-private-nic-guard.test.sh` has a `transport_audit` over recorded argv and an X2 row; several negative rows go vacuous once the URL leaves argv and are repointed to the recorded line).
3. Battery S6-HB: delete all four `S6H_ALLOW` entries, `S6H_ALLOW_CEIL` 4 to 0, add the three scripts and `inngest-bootstrap.sh` to `S6H_CONVERTED`, mutation rows per Guard 1; `EXPECTED_TESTS` re-measured. `scripts/lint-shell-trace-credential-refusal.test.sh`, ADR-280 census rows and `.claude/hooks/grep-q-pipe-guard.test.sh` re-measured.

**Hand-over note (the PR stops here).** PR body states: `deploy-script-tests` GuardA reds by design (sanctioned window, #9081; precedent #10073), no pin bump rides this PR because a pre-merge tag is impossible (#8775, ADR-232 A5), no manual tag push (it starts nothing). On merge: the mint workflow mints the next `vinngest-v*` tag, builds and mirrors the image, and the build's bump job opens the pin-bump PR; GuardA returns green on that PR. Merge only after PR B has settled. Read-only verification: `gh run list --workflow mint-inngest-bootstrap-tag.yml --limit 3`, `gh pr list --search "inngest bootstrap pin"`, `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` on the bump PR, and the Better Stack heartbeats still arriving with no `SOLEUR_CREDENTIAL_REFUSED` row (the inngest script reaches its host only at a later image deploy or replace).

## Production-apply coupling

| File in PR | Workflow(s) fired on merge | Effect on a live system |
|---|---|---|
| any `plugins/soleur/**` non-test, non-docs file; `apps/web-platform/**` (PR A: community scripts, lib, markdown, the `.ts` comment) | `web-platform-release.yml` | version release and routine production app container deploy; `plugins/soleur/test/**` and `tests/scripts/**` alone do not fire it |
| `apps/web-platform/infra/cloud-init-registry.yml`, `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh`, `zot-image.provenance.md` (PR B) | push apply (no Terraform diff in its `-target` sets), `web-platform-release.yml`, and **`registry-host-replace-dispatch.yml`** (push trigger on the exact file; no reviewer gate, no confirm token) | renders `user_data` at both SHAs and, on a byte change, runs the registry host replace after a read-only preflight: **the sole image pull path is replaced unattended** and the converted boot block executes for the first time on the new host. Volume preserved. Whole-line comments are stripped at render and do not count; code and the line-18 trailing comment do. |
| `web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh`, `web-private-nic-guard.sh` and their suites (PR C) | push apply | `terraform_data` SSH re-delivery of each script to web-1 (`triggers_replace` hashes the file); also in the baked `host_script_files` hash that renders into web cloud-init (`hcloud_server.web` ignores `user_data`: no replace). Next 60 s tick runs the converted ping. |
| `apps/web-platform/infra/inngest-bootstrap.sh`, `inngest.test.sh` (PR C) | push apply (no Terraform diff), `mint-inngest-bootstrap-tag.yml` | tag mint, image build through `infra-privileged`, pin-bump PR; no host change until a later image deploy or replace |
| `tests/scripts/test-argv-bearer-sweep.sh`, ADR addendum, plan/spec files | none | docs/tests |

Net: PR A is a routine app release. PR B is one unattended registry replace. PR C is two web-1 re-deliveries and one tag mint. None is dispatched by hand
by the pipeline (`hr-menu-option-ack-not-prod-write-auth`); B and C end at a ready PR. Squash-merge means per-commit staging exists only before merge;
a post-merge revert is a new PR whose own merge re-fires everything it touches (for the registry file, another replace).

## Downtime & Cutover

No operation here takes a serving surface offline by itself except PR B's merge-triggered registry host replace, which is the existing, separately gated
mechanism (`registry-host-replace-dispatch.yml`: sole-copy LUKS volume protection set ADR-282, stock probe, read-only preflight that refuses when the fleet
is already serving off its last tier). The replace is the intended delivery of the template edit; its timing is the hand-over, which is why B is its own PR and
is never merged by the pipeline. PR C's re-delivery is a file copy plus an already-enabled timer (heartbeat grace covers a late beat); the tag mint publishes
an image with no host change. Rollback per PR: revert commit (A: no live state; B: a revert PR re-fires a replace, recovery is the replace itself; C: deliveries are idempotent, the revert re-delivers old bytes and mints another tag).

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file, provider, variable or secret changes. `triggers_replace` hashes of the web-1 probe installs change because script bytes change; that is the existing delivery mechanism.

### Apply path

Existing paths only: web-1 probe scripts via the push-apply `terraform_data` SSH provisioners; the registry template via cloud-init at the next registry host replace (`registry-host-replace-dispatch.yml`, option b of the replace paths); the inngest bootstrap via the mint/build pipeline. Expected downtime: none from A and C; B is the gated registry replace above.

### Host fan-out

No provisioner is added or edited; classifications in `web-host-provisioner-parity.test.sh` are unchanged (re-run it green in PR C).

### Distinctness / drift safeguards

No `dev != prd` surface. `registry-userdata-budget.sh` and `cloud-init-user-data-size.test.ts` gate the registry template; `REGISTRY_GZIP_BUDGET` stays 21,600.

### Vendor-tier reality check

Better Stack heartbeat behavior is unchanged (same URL, same GET). No paid-tier gate.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-280** (no new ordinal; status stays `adopting`) by appending, under its existing `## Addendum — 2026-10-12 (#9757 residue)`, a
`### 2026-10-13 follow-ups` sub-section with one short paragraph per PR (each PR appends only its own paragraph at the end of the file; a rebase
conflict keeps both): A records the lib control-character check as the sink-appropriate validator (deviation from "the same allow-list": different sink), the lock/atomic-write rule for `.env` writers and the inline markdown form (shape `case` + `--config -`, no library reference); B records `htpasswd -i` as the password transport (not curl, so not the library) and the registry heartbeat form with no runtime guard (provider-generated literal); C records the three probe scripts and the inngest body under the same inline-guard exception, the deleted allowlists, and the residual (same-uid `/proc/<pid>/environ` readers). The status flip `adopting` to `accepted` stays with #9905's follow-through. This is a task, not a follow-up issue.

### C4 views

No C4 impact, checked against all three files (`model.c4`, `views.c4`, `spec.c4`): external human actors (founder/Owner, inbound-mail correspondents, beta testers, PR contributors: none added or changed), external systems (Better Stack, Doppler, Discord, Hetzner, Sentry, the zot registry and the Inngest hosts: all modeled; no new vendor or edge, this changes how a credential reaches a child process), containers and stores (no new store; `inngest`, `inngestRedis`, the git-data store untouched), and actor-to-surface access relationships (unchanged). Derived cardinalities: `plugins/soleur/test/c4-count-parity.test.sh` run green on this branch now; re-run at the end of each PR.

### Sequencing

Each addendum paragraph ships in the PR whose behavior it describes.

## Guard Contract

### Guard 1 — Heartbeat URL never reaches curl argv (population: the infra scripts, now with an empty allowlist)

**Property.** In every `apps/web-platform/infra/*.sh` heartbeat script a heartbeat URL is never an argument of any process, is sent only after the shape judgement, and a malformed value makes zero requests and prints the value-free marker.

**Assembly.** The population is DERIVED by stage S6-HB (every tracked or untracked `apps/web-platform/infra/*.sh`, not `*.test.sh`, whose non-comment code mentions `heartbeat`), one violating-segment scan over every logical line, one converted set (`S6H_CONVERTED`, which gains the three probes and `inngest-bootstrap.sh`), and the residual allowlist `S6H_ALLOW`, deleted entry by entry to zero with `S6H_ALLOW_CEIL=0`. Chokepoint per script: the single guarded `--config -` line. Not covered, named: a URL carried in a variable that is none of the scanned names, `eval`, and the registry template (Guard 2).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Put the URL back on argv in one of the three probes (`curl ... "$URL"`) | RED (derived argv scan) |
| 2 | Add a second heartbeat curl after the compliant first in the same file | RED (argv and a second unguarded `url = "` config line) |
| 3 | Widen the guard class to admit `"` or a newline in one probe | RED (hostile-value rows: zero requests, one marker) |
| 4 | Leave a probe converted but keep its allowlist entry | RED (`stale-allowlist`) |
| 5 | Delete the S6-HB dispatch (population scan sees 0 scripts) | RED (`floor`) |
| 6 | Positive-pattern `case` in the POSIX script, or `[[ ]]` in it | RED (hostile-value row; dash row) |

**Harness rows.** A stub curl that ignores stdin and records nothing must make the per-attempt row RED (a missing recorded `url = "` line fails it); must-PASS: a well-formed URL with a different token than the canonical fixture, run once under bash and (inngest body) once under dash.

### Guard 2 — The registry template carries no heartbeat URL and no htpasswd password on argv

**Property.** In `cloud-init-registry.yml` no `curl` argument holds a `*_heartbeat_url` interpolation and no `htpasswd` invocation carries `b` in an option cluster.

**Assembly.** Two derived scans over the one file: the existing S6 htpasswd scan (`git grep` over `apps scripts .github`, the three registry sites move from the allowlist to the converted set by identity, one anchored row per site, floor stays 4 sites in 2 files) and a NEW registry-heartbeat row (every logical line of the YAML with a `curl` command word, whole-line comments dropped, whose text holds `heartbeat_url`, minus the `< <(printf 'url = ...)` feed, must be empty; the two converted sites asserted by identity). Allowlist `S6_ALLOW` deleted to zero with `S6_ALLOW_CEIL=0`. Not covered, named: an invocation through a variable or `eval`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce `htpasswd -Bbn u "$p"` at any of the three registry sites | RED |
| 2 | Put `"${disk_heartbeat_url}"` back on the curl argv | RED (new registry-heartbeat row) |
| 3 | Add a compliant fifth htpasswd site, then a non-compliant sixth in another file | RED (identity per site, not a count) |
| 4 | Rename the scanned binary or the variable in a scratch tree so the scan sees 0 | RED (floor) |
| 5 | Drop the `-i` or add `b` (`-Bbn`) in the rendered boot block executed in the container | RED (rendered-block row: the stub records the argv and the hash covers an empty password) |
| 6 | Make the boot block's first `htpasswd` fail and keep going | RED (failing first aborts before `>>`; no second entry) |

**Harness rows.** A suite edit that removes the rendered-block extraction (empty block) must RED (non-empty extraction row); must-PASS: option cluster in another order (`-iB`) and a `-vb` that appears only in a YAML comment.

### Guard 3 — No agent-run markdown teaches a bearer or apikey header on curl argv (stage S7)

**Property.** No tracked `*.md` under `plugins/` carries `curl ... -H/--header Authorization|apikey|X-Api-Key|Private-Token|Api-Key` outside the residual allowlist.

**Assembly.** One `git grep` over `plugins/**/*.md` (not `knowledge-base`, which holds history), pattern-anchored not line-anchored (`cq-cite-content-anchor-not-line-number`); residual allowlist by file and matched text (`api-security.md` BAD example, plus any prose site that stays), shrinking by deletion only, with a ceiling constant like `S6_ALLOW_CEIL`; a floor that the scan sees at least the allowlisted site (so a renamed pattern is RED). Rule E does not read markdown, so this is the only recurrence guard.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `curl -H "Authorization: Bearer $T"` to one converted file | RED |
| 2 | Add a compliant converted snippet, then a violating one in a different file | RED (the second, by identity) |
| 3 | Allowlist grows by one entry | RED (ceiling) |
| 4 | Rename the scanned header word in a scratch tree so the scan sees 0 | RED (floor) |

**Harness rows.** Must-PASS: a snippet using `header = "Authorization: Bearer %s"` on a `--config -` and one with `-H` only inside a prose sentence without `curl` on the line.

### Guard 4 — `write-env` is atomic, serialized, and mode 600 from birth

**Property.** After any number of concurrent `write-env` runs each managed key appears exactly once in `.env`, `.env` is never observable partial, never wider than 0600, and the temp is renamed within one filesystem.

**Assembly.** Every setup script's `cmd_write_env` flows through ONE helper `_wenv_write`, whose block is pinned byte-identical across the four scripts by the community suite (the chokepoint is the helper; the population is `WRITERS` derived by the suite's existing manifest row, floor 4). The lib's `soleur_op_env_upsert` is a separate sink with its own check.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the lock acquisition with a no-op in one copy | RED (parallel-run row shows duplicates; byte-identity RED) |
| 2 | Put `mktemp` back in the default temp dir | RED (same-directory shim row) |
| 3 | Create the temp without `umask 077` (chmod after) | RED (mode-at-rename shim row under `umask 000`) |
| 4 | Treat `grep` rc 2 as success (`|| true`) | RED (unreadable-`.env` row) |
| 5 | Leave `.env.lock*` behind | RED (artifact row) |
| 6 | Widen the helper in ONE copy | RED (byte-identity) |

**Harness rows.** A parallel-run harness that runs ONE process must RED (floor on the number of concurrent writers observed); must-PASS: a run with `flock` absent (mkdir path) and an existing `.env` with unrelated keys.

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeats for the converted scripts keep arriving after their delivery: registry disk and liveness beats (after the replace), web git-data probe, zot consumer, inngest consumer, private NIC guard (after the web-1 re-delivery); the inngest heartbeat after the later image deploy. The missed beat is the primary alarm, the refusal marker only names a cause"
  cadence: "60s for the probes and the inngest heartbeat, 5 min for the registry disk beat"
  alert_target: "operator email via the existing Better Stack heartbeat policies (git-data.tf, zot-registry.tf, inngest.tf, web-probe.tf)"
  configured_in: "apps/web-platform/infra/git-data.tf, apps/web-platform/infra/zot-registry.tf, apps/web-platform/infra/inngest.tf, apps/web-platform/infra/web-probe.tf"
error_reporting:
  destination: "layer 3, host journald to Vector Source 4 to Better Stack Logs (tags are allowlisted in vector.toml; the value-free SOLEUR_CREDENTIAL_REFUSED line is not touched by the PII scrub); the registry host posts SOLEUR_ZOT_DISK directly from cloud-init; layer 6 for the community scripts and suites (run logs); the community scripts' refusals mirror through the agent PostToolUse extractor (MARKER_RE) when printed inside an agent Bash call"
  fail_loud: "SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<NAME> from a converted heartbeat script (hourly limiter on the 60 s inngest unit), the existing WARN lines, SOLEUR_BOOTSTRAP_BAD_ARG for the lib validator, and the missed beat itself through the heartbeat policy"
failure_modes:
  - mode: "stored heartbeat URL fails the shape guard in a probe or the inngest script"
    detection: "layer 3: SOLEUR_CREDENTIAL_REFUSED row in Better Stack Logs (bash scripts/betterstack-query.sh --grep SOLEUR_CREDENTIAL_REFUSED), independent of the beat"
    alert_route: "the heartbeat policy pages on the missed beat; the marker row names the cause and rides the same journald path, so it can be absent exactly when that path is the fault"
  - mode: "htpasswd -vi or the converted boot block mis-behaves on the replaced registry host (htpasswd_*_matches wrong, or zot not launched)"
    detection: "layer 3 direct POST, not Vector: bash scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK reads htpasswd_pull_matches and htpasswd_push_matches; a boot failure shows as state_status=unknown and a missing host heartbeat; offline, the rendered-block row in htpasswd-stdin.test.sh before merge"
    alert_route: "no alert keys on htpasswd_*_matches today (query-only for a mismatch); the missing host heartbeat and the pull-path health gate cover the not-launched case"
  - mode: "registry user_data exceeds the gzip budget"
    detection: "layer 6: cloud-init-user-data-size.test.ts and registry-userdata-budget.sh on the PR run log"
    alert_route: "required CI check fails the PR"
  - mode: "concurrent write-env loses or duplicates a key, or leaves .env wider than 0600"
    detection: "layer 6: the community-argv suite parallel-run, mode and artifact rows on the PR run log"
    alert_route: "required CI check fails the PR"
  - mode: "a markdown snippet or an infra script regrows a bearer or heartbeat URL on curl argv"
    detection: "layer 6: battery stages S6, S6-HB and S7 on the PR run log"
    alert_route: "required CI check fails the PR"
  - mode: "the inngest tag mint, image build or auto pin-bump fails after PR C merges"
    detection: "layer 6: mint-inngest-bootstrap-tag.yml and build-inngest-bootstrap-image.yml run results, Slack post on a stage-named failure, GuardA staying red on main"
    alert_route: "Slack from the mint workflow and the red GuardA row on the next PR run"
logs:
  where: "Better Stack Logs (host scripts via Vector; registry host direct POST), GitHub Actions run logs (suites, mint and build workflows)"
  retention: "Better Stack Logs team retention; Actions logs 90 days"
discoverability_test:
  command: python3 -c "import re;fs=['apps/web-platform/infra/cloud-init-registry.yml','apps/web-platform/infra/inngest-bootstrap.sh','apps/web-platform/infra/web-zot-consumer-probe.sh','apps/web-platform/infra/inngest-consumer-probe.sh','apps/web-platform/infra/web-private-nic-guard.sh','plugins/soleur/skills/postmerge/SKILL.md','plugins/soleur/skills/reproduce-bug/SKILL.md'];p=re.compile(r'htpasswd +-[A-Za-z]*b|curl [^#]*(_url}|HEARTBEAT_URL|.[$]URL.)|curl [^#]*-H +.Authorization');n=sum(1 for f in fs for l in open(f) if not l.lstrip().startswith('#') and p.search(l));print('OK' if n==0 else 'FAIL')"
  expected_output: "OK"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** credential-transport and local-tooling hardening on existing surfaces; no new architecture, no Product, Marketing, Legal, Finance or Sales implication (no user-facing surface, no personal data, no new processor). The CTO agent ruled seven forks (grouping and merge order, flock portability, lib validator class, registry heartbeat form and guard row, #10120 re-implementation and the GuardA window, #10092 placement and emitter list, markdown scope and S7). All seven are in `decision-challenges.md` and folded above. GDPR gate: no regulated-data surface (no schema, migration, auth flow or API route) and none of the (a)-(d) expansion triggers; skipped. Encryption posture (2.11): the path pattern `cloud-init.*\.ya?ml$` matches `cloud-init-registry.yml`, but the plan introduces no persistent store and no new connection (it changes how a password and a URL reach a child process), so the gate skips; recorded here rather than as a vacuous section.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement the open argv-bearer sweep follow-ups: #10119, #10120, #10091, #10092 and #10093" | PR A, B, C | mapped |
| 2 | "#10119 ... its own PR ... stop at a green, ready PR and hand over the merge/apply step with an exact command or note" | PR B and its hand-over note | mapped |
| 3 | "#10120 ... its own PR, sequenced with the vinngest-v* tag mint and pin bump ... rebase onto current main, do not cherry-pick blindly ... hand that step to the operator rather than running it unattended" | PR C; re-implementation; hand-over note (the mint is automatic on merge, the bump is an auto PR) | mapped (premise corrected: no unattended step exists to run, see Reconciliation) |
| 4 | "#10093 ... batch the infra edits and keep the skill-markdown edits separable; shrink the explicit residual allowlist ... by deletion only. Coordinate the registry cloud-init heartbeat edits with #10119" | probes in C, registry heartbeats in B, markdown in A, allowlist to zero | mapped |
| 5 | "#10091 ... build file at mode 600 in target dir, mv -f under flock, extend soleur_op_env_upsert validation to the setup scripts' allow-list, update byte-identity rows ... in the same change" | PR A1, A1b | mapped; the lib extension is the CTO-ruled control-character check, not the exact allow-list (deviation recorded) |
| 6 | "#10092 ... fold it into the first PR here that touches that file for a functional reason, or ship it last/with the other web-platform changes; do not ship it alone" | A2 inside PR A | mapped |
| 7 | "Umbrella tracker #9757 must stay OPEN ... Ref #9757 ... Closes #N only for the five ... Tick the matching checklist items on #9757 as each lands" | PR bodies; Acceptance Criteria post-merge tick step | mapped |
| 8 | "state the grouping at plan time" | Overview table | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| New battery stage S7 (markdown census) | "keep the skill-markdown edits separable" | inferred — justification: Rule E does not read markdown, so without a derived row the class regrows silently; the S4 hmac-in-markdown census is the precedent; CTO-ruled |
| Converting `infra-security.md` and `deployment-verification-agent.md` (not named in #10093) | "four skill markdown snippets" | inferred — justification: same class, markdown only, zero apply surface, found by the S7 grep; CTO-ruled; flagged for operator override in `decision-challenges.md` |
| New registry-heartbeat guard row in PR B | "Coordinate the registry cloud-init heartbeat edits with #10119" | inferred — justification: the registry heartbeats are in no population today, and deleting the htpasswd allowlist would leave them the one untested site; CTO-ruled |
| Rendered-boot-block execution row | "(#10119 acceptance row 2)" | asked |
| Lib control-character check instead of the allow-list | "extend soleur_op_env_upsert validation to the setup scripts' allow-list" | asked, with a CTO-ruled narrowing (wrong sink) |
| ADR-280 follow-up paragraphs | none | inferred — justification: plan Phase 2.10, a decision a future engineer would find undocumented |

### Split Assessment

- Subsystems touched: 6 — `apps/web-platform`, `plugins/soleur`, `tests`, `scripts`-adjacent suites, `.claude/hooks` (re-measure only), `knowledge-base`
- Planned files: ~38 across three PRs (A ~16, B ~7, C ~15) | Estimated changed lines: ~1,000 across all three
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **split — already split.** The plan is three PRs precisely at the production-apply boundaries; each PR is below the thresholds on its own.

## Files to Edit

**PR A:**

- `plugins/soleur/skills/community/scripts/{bsky,discord,x,linkedin}-setup.sh` (`_wenv_write` block, `cmd_write_env` bodies)
- `plugins/soleur/skills/community/test/community-argv.test.sh` (new block drift rows, concurrency/mode/artifact rows)
- `plugins/soleur/scripts/lib/operator-script.sh`, `plugins/soleur/test/operator-script.test.sh`
- `apps/web-platform/server/git-lock-marker-telemetry.ts` (comment only)
- `plugins/soleur/skills/postmerge/SKILL.md`, `plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`, `plugins/soleur/skills/preflight/SKILL.md`, `plugins/soleur/agents/engineering/infra/infra-security.md`, `plugins/soleur/agents/engineering/review/deployment-verification-agent.md` (and `flag-delete`/`flag-list` SKILL.md only if a real recipe)
- `tests/scripts/test-argv-bearer-sweep.sh` (stage S7, `EXPECTED_TESTS`)
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (follow-up paragraph)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` only if a count moves

**PR B:**

- `apps/web-platform/infra/cloud-init-registry.yml`, `apps/web-platform/infra/registry-boot-guard.test.sh`, `apps/web-platform/infra/htpasswd-stdin.test.sh`, `apps/web-platform/infra/zot-image.provenance.md`
- `tests/scripts/test-argv-bearer-sweep.sh` (S6 allowlist deletion, converted-site rows, registry-heartbeat row, `EXPECTED_TESTS`)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (only if the derivation moves), ADR-280 paragraph

**PR C:**

- `apps/web-platform/infra/inngest-bootstrap.sh`, `apps/web-platform/infra/inngest.test.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.sh` + `.test.sh`, `apps/web-platform/infra/inngest-consumer-probe.sh` + `.test.sh`, `apps/web-platform/infra/web-private-nic-guard.sh` + `.test.sh`
- `tests/scripts/test-argv-bearer-sweep.sh` (S6-HB allowlist deletion, converted set, mutation rows, `EXPECTED_TESTS`)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (re-measure), ADR-280 paragraph

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10119-10120-10091-10092-10093-argv-bearer-followups/tasks.md` and `decision-challenges.md` (this plan's own artifacts).
- No new production file. PR B/C branch names are chosen at work time (suggested `fix-argv-registry-htpasswd-10119`, `fix-argv-inngest-probes-10120`), each cut from `main` after A merges or rebased onto it.

## Open Code-Review Overlap

None (open `code-review` issues queried by body-contains on every planned path; no match; 89 open issues scanned).

## Acceptance Criteria

### Pre-merge (per PR)

**PR A**

- [ ] The four setup scripts carry a byte-identical `_wenv_write` block; the parallel-run, no-`flock`, mode-at-rename, same-directory, unreadable-`.env`, killed-run and artifact rows in `community-argv.test.sh` are green and each RED row was observed RED against the unfixed scripts first.
- [ ] `soleur_op_env_upsert` refuses a control character with a value-free marker and still writes `$ " ' space ! # ?` values; `operator-script.test.sh` green; the lib's `.env` consumers were grepped and recorded.
- [ ] `git-lock-marker-telemetry.ts` diff is comment-only (`git diff -U0` shows no non-comment line), names the six emitters, `tsc` and `apps/web-platform/test/git-lock-marker-telemetry.test.ts` green.
- [ ] `git grep` for a bearer/apikey header on a curl argument list over `plugins/**/*.md` returns only the S7 allowlist; stage S7 rows and mutation rows green; `EXPECTED_TESTS` re-pinned to the measured total.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` green; ADR-280 follow-up paragraph present.
- [ ] PR body: `Closes #10091`, `Closes #10092`, `Ref #10093`, `Ref #9757` (never `Closes #9757`); first line states the merge fires one routine app release.

**PR B**

- [ ] No `htpasswd` option cluster with `b` and no heartbeat URL on curl argv in `cloud-init-registry.yml`; `S6_ALLOW` deleted, `S6_ALLOW_CEIL` 0, floor rows and converted-site rows replace the "residual site" rows, registry-heartbeat row and mutation rows green; `EXPECTED_TESTS` re-measured.
- [ ] The boot block rendered from the real YAML runs through `bash -s` in the digest-pinned `ubuntu:24.04` + `apache2-utils` image, failure arms included; `htpasswd-stdin.test.sh` fails closed in CI on a missing docker.
- [ ] `registry-boot-guard.test.sh` green (including the 127/6/1-through-the-pipe row); `cloud-init-user-data-size.test.ts` green with `REGISTRY_GZIP_BUDGET` unchanged; `registry-userdata-budget.sh` stored size recorded before and after in the PR body.
- [ ] PR body first line states the merge replaces the production registry host unattended; carries the hand-over note (merge command, watch command, read-only post-merge check, abort path); `Closes #10119`, `Ref #10093`, `Ref #9757`; **PR marked ready, not merged**.

**PR C**

- [ ] `bash apps/web-platform/infra/inngest.test.sh` green at the re-measured floor including the dash row; `web-zot-consumer-probe.test.sh`, `inngest-consumer-probe.test.sh`, `web-private-nic-guard.test.sh` green with the stub reading stdin per attempt; `S6H_ALLOW` deleted, `S6H_ALLOW_CEIL` 0; `lint-shell-trace-credential-refusal.test.sh`, ADR-280 census rows, `web-host-provisioner-parity.test.sh`, `infra-config-gate.test.sh`, `ci-deploy.test.sh` green.
- [ ] `cloud-init-inngest-bootstrap.test.sh`: GuardA red BY DESIGN and nothing else red (recorded: every other row of the file green).
- [ ] PR body first line states the merge fires the tag mint and the web-1 re-delivery; carries the GuardA window explanation, "B before C", the read-only verification commands; `Closes #10120`, `Closes #10093`, `Ref #9757`; **PR marked ready, not merged**.

**All PRs:** `npx markdownlint-cli2` clean on touched markdown; `python3 scripts/lint-shell-trace-credential-refusal.py --changed` green; review and QA complete; `Closes #N` in the body, not the title.

### Post-merge (operator-approved merges only; read-only checks)

- [ ] A: the merge-triggered `web-platform-release.yml` run succeeds.
- [ ] B: the `registry-host-replace-dispatch.yml` verdict is read (delivered, or a named preflight refusal); `SOLEUR_ZOT_DISK` reports `htpasswd_pull_matches=true htpasswd_push_matches=true`; the registry heartbeats arrive.
- [ ] C: the mint run, the build and the auto pin-bump PR succeed; GuardA green on the bump PR; no `SOLEUR_CREDENTIAL_REFUSED` row for the converted scripts.
- [ ] #9757 checklist ticked item by item with evidence as each PR lands; #9757 closed only after the last item is ticked and every tracked item is done.

## Test Scenarios

- Given N parallel `write-env` runs on one `.env`, then every managed key appears exactly once (integration, RED today).
- Given `flock` absent from `PATH`, then the mkdir lock serializes the same runs (integration).
- Given `umask 000`, then the new `.env` and the temp at rename time are 600 and no `.env.lock*` remains (unit with a `mv` shim).
- Given an unreadable `.env`, then `write-env` aborts and the file is byte-identical (unit).
- Given `soleur_op_env_upsert KEY $'a\tb'`, then it refuses with a value-free marker; given `KEY 'p@$$ w"rd!#'`, then it writes (unit).
- Given the rendered ZOTEOF block under `bash -s` with a failing first `htpasswd`, then the script aborts before `>>` and no second entry exists (integration, real image).
- Given a probe with a URL holding a quote or newline, then zero requests and one marker, per probe (integration).
- Given the inngest heartbeat body under dash with a well-formed URL, then one `--config -` curl and the URL appears only in the recorded stdin line (integration).
- Given a markdown snippet reverted to `-H "Authorization: Bearer $T"`, then S7 is RED (unit, mutation).
- Verification commands for `soleur:qa` (offline): `bash tests/scripts/test-argv-bearer-sweep.sh`, `bash plugins/soleur/skills/community/test/community-argv.test.sh`, `bash plugins/soleur/test/operator-script.test.sh`, `bash apps/web-platform/infra/registry-boot-guard.test.sh`, `bash apps/web-platform/infra/registry-userdata-budget.sh`, `bash apps/web-platform/infra/inngest.test.sh`, `bash apps/web-platform/infra/htpasswd-stdin.test.sh`, `python3 scripts/lint-shell-trace-credential-refusal.py`.

## Dependencies & Risks

- **R1: registry `user_data` budget (medium).** ~100 B headroom for the htpasswd rewrite plus two heartbeat conversions with no runtime guard; measure first; pay shortfalls inside the file; never raise the constant.
- **R2: merge-fires-apply (high, PR B and C).** Mitigated by separate PRs, ready-not-merged, hand-over notes, B-before-C.
- **R3: battery file shared by all three PRs.** `EXPECTED_TESTS` is the one guaranteed conflict; the later PR re-pins from the measured count at rebase. Allowlist constants differ (`S6_ALLOW_CEIL`, `S6H_ALLOW_CEIL`, the S7 ceiling) so they cannot conflict textually.
- **R4: ADR-280 appends from three PRs** at the same end-of-file location; distinct sub-headings, rebase keeps both.
- **R5: lock portability.** macOS lacks `flock(1)` and ships bash 3.2; the mkdir fallback and the bash-3.2-safe constructs are tested in the no-`flock` row; the opt-in `COMMUNITY_ARGV_DOCKER` bash:3.2 row is extended if cheap, not a gate.
- **R6: stub fidelity.** Suites that matched curl argv must now read stdin; a stub that records nothing must fail loudly (Guard 1 harness row).
- **R7: false refusal on a liveness path.** The shape class is a superset of the proven `_url_ok`; a refusal is a false page, not silent. Read-only live shape count of the three probe URLs (counts only, never the value) before PR C is marked ready; if any fails, stop and decide then.
- **R8: GuardA red-by-design** is a pre-existing sanctioned window, but CI shows red on PR C; the PR body names it so a reviewer does not read it as a defect.
- **R9: `.env` writers are user-tree writers** (`hr-write-boundary-sentinel-sweep-all-write-sites`): grep every writer of `.env` in `plugins/soleur/skills/community/scripts/` and the lib before declaring the sweep complete.
- **R10: line numbers drift.** Every cited location is paired with a content anchor; implementers re-anchor by content.

## Rollback

A: revert the PR (no live state; a revert re-fires one app release). B: a revert PR re-fires another registry replace, so treat it as a deliberate replace; the volume is preserved. C: deliveries are idempotent, a revert re-delivers the old bytes and mints another tag. Each PR is independently revertable because its battery rows ship in the same commit as the code they pin.

## Success Metrics

- `git grep` population rows: heartbeat curl with the URL on argv in `apps/web-platform/infra/*.sh` and `cloud-init-registry.yml` = 0; `htpasswd` with a password on argv = 0; bearer header on curl argv in `plugins/**/*.md` = the S7 allowlist only.
- Allowlists: `S6_ALLOW` 3 to 0, `S6H_ALLOW` 4 to 0.
- #9757: all items ticked or tracked; the issue closed by the last landing PR's hand-over, not by a `Closes` keyword.

## Sharp Edges

- Never write `Closes #9757` in any PR body or title; `Closes #N` goes in the body, never the title (`wg-use-closes-n-in-pr-body-not-title-to`).
- A heartbeat conversion must keep `-g` (`--config -` does not subsume it) and, in the registry, must not add a comment containing `${...}` (templatefile interpolates inside comments).
- Each `_ping` attempt needs its own `< <(printf ...)`: a process substitution is consumed once, so a `||` second attempt would read EOF.
- `$?` after `printf ... | htpasswd -vi ...` is the pipeline status (htpasswd's); do not add `pipefail` to the probe function.
- Do not use an `htpasswd` invocation without its own pipe inside a `bash -s <<'EOF'` block.
- The inngest heartbeat body is POSIX `sh`: no process substitution, no `[[ ]]`, no `logger`/`printf`/`echo` line naming the URL variable, no heredoc feeding the config (Rule E). A local `/bin/sh` that is bash proves nothing; the dash row names its image.
- `grep -v ... || true` hides rc 2 and wipes a file; treat rc 1 as normal and rc 2 as abort.
- A lock file left in a user's repo is an untracked artifact: lock a directory fd, remove the mkdir fallback on every exit path.
- Do not push a tag by hand for PR C: the build has no `push: tags` trigger and a hand-pushed tag starts nothing; the bump is its own PR.
- Never print a token, URL or hash value in a failure message; rows print counts and field names.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one states `aggregate pattern`.
- `knowledge-base/INDEX.md` may be created untracked by the learnings tool; never `git add` it (explicit paths only).

## References

- Tracker #9757 (open); issues #10119, #10120, #10091, #10092, #10093; parent plan `knowledge-base/project/plans/2026-10-12-fix-argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence-plan.md`; preserved commit `b48247d559` (local branch `keep/9757-inngest-heartbeat-argv`).
- ADR-280 (and its 2026-10-12 addendum), ADR-232 (mint/bump), ADR-282 (sole-copy LUKS volume set), #9081 (GuardA PR-context exemption), #8775 (tag must sit on `main`), #10073 and #10128 (inngest-bootstrap.sh since the preserved commit).
