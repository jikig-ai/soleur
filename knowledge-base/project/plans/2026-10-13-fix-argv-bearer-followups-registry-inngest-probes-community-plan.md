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

## Enhancement Summary

**Deepened on:** 2026-10-13 (after a learnings sweep, seven CTO-agent rulings plus one re-ruling, a sharp-edges verification pass, then security-sentinel, architecture-strategist, observability-coverage-reviewer and test-design-reviewer; gates 4.6-4.12 and 4.55 run: user-brand present, observability probe passes the verb gate and prints a RED reading on main, PAT sweep clean, no UI surface, encryption posture skipped with reason, guard-contract lint green with 4 entries, scope check compliant, downtime section present).

### Key improvements

1. **One lock mechanism, not two** (security review plus CTO re-ruling): a mkdir lock with atomic-rename stale recovery, bounded fail-closed wait, symlink resolution; flock dropped. The parallel-run row is now a forced-interleave row across different writers (a whole-file atomic replace cannot duplicate keys, so the first draft's row could not go RED).
2. **Follow-through probes are pure verdict emitters** attached to the work issues themselves (the convention and dry-run forbid a probe that closes other issues); the registry probe keys on a changed `boot_id` and `deliver=true` (the old host emits the same row every five minutes); the inngest monitors are paused, so the refusal marker is their sole detector.
3. **Operator Holds section** so ship cannot arm auto-merge on the registry replace or the tag mint; B and C stay held (no auto-merge) and branch only after A (and B) merge.
4. **Markdown census measured**, not assumed: 22 hits, ten curls to convert across nine files (adds `ship/SKILL.md`, the Sentry PUT, two agent files), one documentation allowlist, logical-line join, extra mutation rows.
5. **Coupling table corrected**: PR A fires four workflows, not one; PR B's replace delivers everything since the dispatcher watermark and coincides with a release whose mirror path uses the registry; `inngest-consumer-probe.sh` also fires the mint.
6. **Lib validator decision rule**: if any consumer sources a file the lib writes, the lib writes a sourceable-safe form (not a note).

### New considerations discovered

- `soleur_op_env_upsert` consumers may `source` the file: code execution through an unvalidated `$(...)` value (decision rule above).
- Registry heartbeat URLs are documented as non-secret and stay a literal in `user_data`: the conversion buys only the `/proc` half.
- The three probes' refusal markers would ship 1,440 rows/day each without a limiter.
- A `Closes` keyword would close #10119/#10120 at merge, before the replace or mint is verified.

## Overview

Five open follow-ups of the argv-bearer sweep (umbrella #9757, which stays OPEN until all five land; every PR body says
`Ref #9757`, never `Closes #9757`, and carries `Closes #N` only for the issues that PR completes) are planned together and
grouped into three pull requests, the fewest that respect the production-apply boundary each file carries:

| PR | Issues touched | Content | What its merge fires | Ends at |
|---|---|---|---|---|
| **A** (this branch) | Closes #10091, #10092; Ref #10093 (skill-markdown part) | community `write-env` lock + temp-in-target-dir + `mv -f`; `soleur_op_env_upsert` control-character check; `MARKER_RE` comment; six markdown snippets off argv; new battery stage S7 | `web-platform-release.yml` (a routine app release), `version-bump-and-release.yml` (`plugins/soleur/**`, any file), `deploy-docs.yml` (`plugins/soleur/skills/**` and `agents/**`: a docs-site deploy) and `skill-security-scan-postmerge.yml` (every push). No infra apply, no mint, no replace. | normal pipeline (review, QA, ship) |
| **B** | Ref #10119 (closed after the verified replace, see below); Ref #10093 (registry-heartbeat part) | `cloud-init-registry.yml`: htpasswd off argv (3 sites), `install -m 600`, two heartbeat curls on `--config -`; battery S6 allowlist deleted, new registry-heartbeat row; rendered-boot-block execution row | **an unattended production registry host replace** (`registry-host-replace-dispatch.yml` push trigger), plus the push apply and the app release | **a held PR (no auto-merge armed; see the holds section) with a hand-over note; never merged by the pipeline** |
| **C** | Ref #10120 and Ref #10093 (both closed after the verified mint and bump, see below) | `inngest-bootstrap.sh` heartbeat (re-implemented from `b48247d559`), the three probe scripts, battery S6-HB allowlist deleted | push apply (web-1 SSH re-delivery of three scripts), `mint-inngest-bootstrap-tag.yml` (auto tag, image build, auto pin-bump PR), the app release | **a held PR (B merged and #10119 PASS first; see the holds section), GuardA red by design; never merged by the pipeline** |

Merge order (ruled by the CTO agent, see Decision Classes): A at any time; **B fully settled (replace finished, registry healthy,
heartbeat green) before C is merged**, because C's merge triggers an image build that mirrors to the registry. Each PR body states
"B before C, wait for B healthy". Close semantics (sharp edge for post-merge production writes): PR A uses `Closes #10091`/`Closes #10092` in its body (no production write to verify beyond a routine release). PR B and PR C use `Ref #N` only, because their merges fire a registry replace and a tag mint whose success is not known at merge; each gets a follow-through tracker (Phase 2.9.1 below) whose verification script closes the work issue (#10119 for B; #10120 and then #10093 for C, since C lands #10093's last part) once the read-only verdict passes. This is why the operator brief's "Closes #N in the body" is applied to A only and `Ref` elsewhere: a `Closes` keyword would mark #10119/#10120 done at merge, before the replace or mint is verified.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issues | Reality on `origin/main` (2026-10-13) | Plan response |
|---|---|---|
| #10091: `linkedin-setup.sh` is a deferred, unvalidated writer | `linkedin-setup.sh` already carries the byte-identical `_wenv_*` block and calls `_wenv_validate` (done by #10086). All four setup scripts validate. | #10091 reduces to the write path (lock, temp in target dir, `mv -f`) and the lib validator. |
| #10091: extend `soleur_op_env_upsert` to "the same allow-list the setup scripts use" | `soleur_op_env_upsert` already builds a sibling temp (`mktemp "${env_file}.tmp.XXXXXX"`) and `mv`s it (atomic); it is the sink for arbitrary operator-entered credentials (`template.sh`), which legitimately contain `$ " ' space ! # ?`. The setup-script allow-list protects a different sink (curl's stdin config). | **Deviation, CTO-ruled:** the lib check becomes CR/LF plus `[[:cntrl:]]` under `LC_ALL=C` (value-free marker), not the exact allow-list. Recorded as a Decision Class row (user-challenge flavoured: it narrows the issue's wording). |
| #10092: comment lists four emitters, `x-setup.sh` is the fifth | Emitters by grep over `plugins/`: `discord-community.sh`, `discord-setup.sh`, `bsky-community.sh`, `bsky-setup.sh`, `x-setup.sh`, `linkedin-setup.sh` (six). | Comment names all six; comment-only; `MARKER_RE` text unchanged (`SOLEUR_CREDENTIAL_REFUSED\b.*` already matches). |
| #10120: rebase `b48247d559` onto main | `inngest-bootstrap.sh` changed after that commit (`git log b48247d559..HEAD -- apps/web-platform/infra/inngest-bootstrap.sh` lists only #10128, `f663c4af0e`; #10073 is an ancestor). `git apply --check` of the format-patch against current `HEAD` succeeds (measured), but a clean apply on a baked carrier proves nothing about the heartbeat block's neighbours. | Re-implement guided by the commit (CTO ruling), then re-run the whole battery; the commit is the recipe, not a cherry-pick. |
| #10120 AC5: on the inngest host, check `/proc/<pid>/cmdline` during a tick | That needs host access, and `hr-no-ssh-fallback-in-runbooks` forbids an SSH step. The new script also reaches the host only at a later image deploy or replace. | Replace AC5 with: static argv-free proof (stub rows + dash row), mint run success, pin-bump PR opened, Better Stack heartbeat still arriving once the image deploys, no `SOLEUR_CREDENTIAL_REFUSED` row. Deviation recorded. |
| #10120: "the tag mint is a production apply, hand it to the operator" | `mint-inngest-bootstrap-tag.yml` fires automatically on a push to `main` touching `apps/web-platform/infra/inngest*`; the build has no `push: tags` trigger (ADR-232 A5) and its `bump-cloud-init-pin` job holds `infra-privileged` (refuses a tag-ref run); a tag must sit on a `main` commit (#8775). A pre-merge tag and a pre-merge pin bump are impossible. | PR C cannot carry the bump. Hand-over = merge it (after B settles), then watch the auto mint and the auto pin-bump PR. No manual tag push. |
| #10093: "shrink the allowlist in the sweep's guard row" | `S6H_ALLOW` has 4 entries (three probe scripts and `inngest-bootstrap.sh`), `S6H_ALLOW_CEIL=4`; the registry heartbeat curls are in no population (stage comment: NOT COVERED). | C deletes all four entries (ceiling 4 to 0). B adds a derived registry-heartbeat row (CTO ruling), because the registry is the highest-value untested site. |
| #10093 names four markdown snippets | A logical-line census (backslash continuations joined; 22 hits, measured 2026-10-13) over `plugins/**/*.md` finds more. Convert (10 curls in 9 files incl. the four named): `postmerge/SKILL.md`, `postmerge/references/sentry-error-count-delta.md` (the issue GET AND the `SENTRY_RW_TOKEN` PUT), `reproduce-bug/SKILL.md`, `preflight/SKILL.md`, `ship/SKILL.md` (service-role `apikey` + `Authorization` continuation line), `agents/engineering/infra/infra-security.md` (8 Cloudflare curls), `agents/engineering/review/deployment-verification-agent.md` (1 table cell). Allowlist (documentation of the chat-visibility threat model, not the `/proc` one): `skills/skill-creator/references/api-security.md`, 5 sites. Prose, reworded by hand so they leave the census: `flag-delete`/`flag-list` SKILL.md. Safe (argv-safe form, must-PASS): `cf-token-scope/references/widen-playbook.md` (`-H @<(printf ...)`); `trigger-cron` SKILL.md prose. | CTO ruling (convert named plus agent files in PR A, S7 with a shrink-only allowlist), extended by this census: `ship/SKILL.md` and the sentry PUT join the convert list. Files beyond the issue text: Scope Check, `inferred`. |
| #10119: `htpasswd-stdin.test.sh` already measured the contract | Exists on main (263 lines, merged by #10086) with ubuntu and httpd digests; `registry-userdata-budget.sh` measured now: stored 21,500 B vs `REGISTRY_GZIP_BUDGET` 21,600 (headroom ~100 B), cap 32,768. | Reuse its rows; add the rendered-boot-block row there. Budget measured before and after; shortfall paid inside the same file, never by raising the constant. |
| `deploy-script-tests` GuardA is green | Measured green on main now (250/250, pin `vinngest-v1.1.52`). | Baseline recorded; PR C reds it by design (precedent: #10073, #9944). Not a required check (#9081 open). |

## Research Insights

**Premise Validation (Phase 0.6).** `gh issue view` on #10119, #10120, #10091, #10092, #10093 and #9757: all OPEN, none closed by a PR.
Cited paths all exist on `origin/main` (21 checked, including both suites, the battery, the lib and the four community scripts).
Stale: #10091's "linkedin deferred" premise (done) and the "four emitters" count (six). No ADR rejects `htpasswd -i`, stdin config for
heartbeats or a lib control-character check (ADR-280 `adopting` carries the mechanism; its 2026-10-12 addendum already records the
heartbeat-guard deviations). Local branch `keep/9757-inngest-heartbeat-argv` exists with `b48247d559` (446-line patch, 3 files).

**Property List (Phase 0.6b).**

1. No heartbeat URL (registry two, inngest one, three probe scripts) and no zot htpasswd password is an argument of any process. (Residual, named: the two registry URLs remain a literal in `user_data`.)
2. A malformed stored heartbeat URL makes zero requests and logs one value-free `SOLEUR_CREDENTIAL_REFUSED` line (rate-limited on the 60 s inngest unit).
3. Concurrent `write-env` runs of the four community setup scripts lose no key and duplicate none; `.env` is never observable half-written, never wider than mode 600, and never replaced across a filesystem.
4. `soleur_op_env_upsert` refuses a value holding a control character without refusing any legitimate credential.
5. No agent-run markdown teaches a bearer or apikey header on curl's argument list; a recurrence is a RED battery row.
6. The registry host replace and the inngest tag mint are never fired by a pipeline merge; each is a named hand-over.

**Cut List (Phase 0.6b).**

- *A shared heartbeat library* → cut: checkout-less hosts cannot source one (prior plan Cut List); inline `_hb_url_ok` copies exist.
- *Runtime shape guard on the two registry heartbeat curls* → cut (CTO): the URL is a provider-generated Terraform attribute, not operator input; the guard spends scarce gzip bytes.
- *Porting the setup-script allow-list into the lib* → cut (CTO): wrong sink; would refuse real vendor credentials.
- *A persistent `.env.lock` file* → cut (planner, within the CTO's option b): a lock file persists as an untracked artifact in a consumer's repo; lock an fd opened on the target directory instead, mkdir fallback removed on every exit path.
- *A lock in `soleur_op_env_upsert`/`env_reset`* → out of #10091's text (the lib already writes atomically via a sibling temp and `mv`, which closes the delete-then-append window; two concurrent upserts of different keys can still lose one update, because an atomic rename is not a serialized read-modify-write). Deferred WITH a tracker: at work time file one `deferred-scope-out` issue (what: serialize the lib's upsert/reset read-modify-write with the same lock helper; why: not the setup-script window #10091 names, and the template runs single-process per founder; re-evaluate when a generated script can run concurrently; milestone `Post-MVP / Later`), per `wg-when-deferring-a-capability-create-a`.
- *A pre-merge tag mint or pin bump for #10120* → impossible (#8775, ADR-232 A5); see Reconciliation.
- *A lexer-grade markdown scanner* → cut: one `git grep` pattern with an allowlist, the S4 hmac census is the precedent.

**Relevant learnings** (institutional search, 25 hits; applied below): the 2026-10-06 sweep ratchet learning (process substitution, shape guard, ratchet); 2026-10-11 inline-copy parity learning (pin the contract, not only the copies); `2026-03-13-shell-script-defensive-patterns` (pair `mktemp` with a trap; `grep` rc 1 vs 2); `2026-05-12-cross-session-lock-lease-bash-primitives` (flock / pidfile owner identity); `2026-07-03-cloud-init-32kb-cap` and `2026-07-07-arc-closes-premature-and-subcap-guard-headroom-consumed` (budget headroom is consumed silently; `${var}` in a comment of a templatefile still interpolates); `2026-10-11-env-u-cant-scrub-a-function-three-shell-traps` (`grep -q` SIGPIPE under pipefail, `VAR=x func`); `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern` (no `|| true` that hides a heartbeat failure). Gaps (no precedent): lib `.env` concurrency, `MARKER_RE` emitter comments.

## Problem Statement / Motivation

Same exposure class as the swept sites: a secret is readable by every local user in `/proc/<pid>/cmdline` for the life of a child
process, and, for the two registry heartbeat URLs, the conversion buys only the `/proc` half: `zot-registry.tf` calls those URLs "not a secret (a bare ping URL)" and they stay a literal in `user_data` (readable through the Hetzner metadata API) after the edit. They are converted because the issue names them and they share the file with #10119; the residual is recorded in the ADR paragraph and Property 1.
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
2. Acquire the lock. ONE mutual-exclusion mechanism on every platform (security review: "flock when present, else mkdir" lets a flock run and a mkdir run exclude nothing against each other, `flock` without `-w` blocks forever, and `exec {fd}<dir` needs bash 4.1 while macOS ships 3.2): an owner-pid `mkdir` lock directory (`.env.lock.d`, beside the RESOLVED `.env`), `flock` dropped. Stale recovery is by atomic rename, never `rmdir`-then-`mkdir` (that is a two-waiter race: both judge the lock stale, A recovers and holds a fresh lock, B's `rmdir` deletes A's live lock): a waiter that judges the lock stale (owner pid dead, re-read after the claim) `mv`s the lock directory to a unique `.env.lock.d.stale.$$` name (only one waiter wins the rename), then loops back to `mkdir`. Bounded wait (about 10 s) that FAILS CLOSED: no write, a value-free marker, exit 1, `.env` untouched. The lock is released on `EXIT INT TERM HUP` (trap scoped to the helper and restored after), and the helper sweeps its own stale `.env.tmp.*` leftovers owned by the user at start. `.env` is resolved through `readlink -f` first; a dangling link or a non-regular target is refused with a value-free marker (otherwise `mv -f` would replace a symlink with a regular file and leave the real target stale), and the lock and temp live beside the resolved target so the rename stays same-filesystem. Bash 3.2 safe: no `${v,,}`, `local -n`, `wait -n`, `exec {fd}<`. (Amends the CTO's Fork 2 option b on the strength of the security review; re-ruled below.)
3. Under the lock: `tmp=$(mktemp "${env_file}.tmp.XXXXXX")` (same directory, so `mv` is a same-filesystem atomic rename), `grep -a -v -E "$remove_ere" "$env_file" > "$tmp"` treating rc 1 as normal and rc 2 as a hard abort that leaves `.env` untouched (the current `|| true` turns an unreadable `.env` into a wiped one), append the new `KEY=VALUE` lines, `chmod 600`, `mv -f "$tmp" "$env_file"`, release. A `RETURN`/explicit cleanup removes the temp on every path (ADR-129 shape already used).
4. Each `cmd_write_env` keeps its own validation and prints exactly what it prints today (the community suite pins stdout/stderr text): only the removal-and-append body is replaced by one `_wenv_write` call with its script-specific ERE (`^(BSKY_HANDLE|BSKY_APP_PASSWORD)=`, the X four, the Discord five, `^LINKEDIN_`).

Portability, enumerated per binary against BSD/macOS userland: `mkdir` (atomic everywhere; the only lock primitive), `mktemp "${f}.tmp.XXXXXX"` (a suffix template works on both), `kill -0` (portable), file mode read in the shim via `stat -c %a` (GNU) with a `stat -f %Lp` (BSD) fallback. The rows run on this repo's Linux userland and the opt-in `COMMUNITY_ARGV_DOCKER` row gains a `bash:3.2` run of the lock path (opt-in, not a gate); macOS userland itself is named as untested, not claimed.

`community-argv.test.sh`: add the new block to the drift section (extract `_wenv_write` the way `wenv_block` extracts the validator;
byte-identity across four plus a widening mutation); the existing population/round-trip/hostile rows stay. New rows, RED first
(`cq-write-failing-tests-before`): (i) N parallel `write-env` runs yield each key exactly once (measured RED today: duplicates);
(ii) a two-waiter stale-recovery race (a dead owner pid, two waiters released together: exactly one proceeds, none deletes a live lock) and a bounded-wait row (a live holder: the second run fails closed and `.env` is byte-identical); (iii) a `mv` shim records source dir equals target dir and the temp's mode at
rename time is 600 under `umask 000` (from birth, not chmod-after); (iv) a new `.env` under `umask 000` is 600 (a creating-command shim, e.g. a `grep`/`cat` stand-in that records `stat -L /proc/self/fd/1` of its stdout redirect, observes the mode at birth; `mktemp` itself always yields 0600 so a `mv`-time mode read cannot distinguish `umask 077` from chmod-after) and no `.env.tmp.*` or `.env.lock.d*` remains, including after SIGTERM; (v) an unreadable `.env` aborts and is byte-identical; (vi) a killed run (SIGKILL and SIGTERM) leaves `.env` intact and a stale lock is recovered; (vi-b) symlinked `.env` (the real target is rewritten, the link survives), dangling link and directory `.env` refused; (vii) must-PASS: a different, legitimate value set and an existing `.env` holding unrelated lines with
CRLF-free odd-but-legal content.

**A1b (#10091), lib.** `soleur_op_env_upsert` keeps its CR/LF refusal and adds a control-character refusal (`LC_ALL=C`,
`[[:cntrl:]]`, covering tab, DEL and the C0 set) with a value-free `SOLEUR_BOOTSTRAP_BAD_ARG key=<K> reason=value-contains-control-char`
(the existing CR/LF reason token is kept for CR/LF). `plugins/soleur/test/operator-script.test.sh`: refusal rows per class, a
must-PASS row proving `$ " ' space ! # ?` values still write, and a row that the marker never contains the value. The lib does NOT
get the community allow-list and the community block is NOT copied into it (two sinks, two checks; the byte-identity pins stay
about the setup scripts). At implementation `grep` the lib's `.env` consumers (the community scripts `source` the repo-root `.env` under `set -a`, so check whether the file the lib writes is the same one). **Decision rule, not a note:** if any consumer `source`s a file `soleur_op_env_upsert` writes, the lib writes the value in a sourceable-safe form (single-quote escaping or `%q`) AND a must-PASS round-trip row proves `source` reads the original value back for `$ " ' space ! # ? ;` and a command substitution without executing it; if every consumer parses the file as raw `KEY=VALUE`, the raw form stays and the grep result is recorded. The control-character check also names U+0085, U+2028 and U+2029 (or states why the sink makes them harmless) and uses `local LC_ALL=C` (a bare assignment would leak into the sourcing caller).

**A2 (#10092).** Comment-only edit of the block above `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts`: list
the six community-skill emitters, name the `var=<NAME> phase=write-env` shape of the setup scripts' write-env refusals, and say the
registry-host emitters (`zot-disk-heartbeat`, `soleur-private-nic-guard`, `zot-log-boot`) never reach this extractor. `MARKER_RE`
itself is untouched. Word the comment by RULE, not by an enumeration that goes stale: the community-skill emitters (derived with `git grep -l SOLEUR_CREDENTIAL_REFUSED -- plugins/soleur/skills/community/scripts`: six today, listed by name) reach this extractor; every host-side emitter outside that directory (registry host scripts, `luks-monitor`, `web-git-data-probe`, the probes and the inngest bootstrap that PR C converts, `infra-config-verify`) never does. Gate: `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (vitest) and `tsc`. Folded into A because A's
plugin changes already fire `web-platform-release.yml`, so the comment costs no extra release (CTO ruling).

**A3 (#10093 markdown).** Convert each snippet to the CTO-ruled form, preceded by a one-line value-free shape check and one
sentence saying why argv is wrong (it shows in `/proc/<pid>/cmdline`):

```bash
(LC_ALL=C; case "$TOKEN" in ''|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo "token refused" >&2; exit 1; }
curl --disable --proto '=https' -m 30 -fsS --config - "$URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN")
```

Deviations from the CTO's Fork 7 form, from the security review: `LC_ALL=C` so the class is not collation-dependent, `--proto '=https' -m 30` so a mistyped `http://` base never sends the bearer in cleartext and a call cannot hang, and NO `--noproxy '*'` (these are third-party API calls; a host behind a mandatory egress proxy would silently break). The class refuses tokens holding `: @ % !` (deliberate; the real Sentry, Supabase, Cloudflare and Doppler tokens use `A-Za-z0-9._-` and base64 `+/=`). Each converted snippet carries a one-line note "bash only, never under `bash -x`" and none may also read stdin (`-d @-`, `-T -`, a heredoc or pipe into curl): S7 gets a row for `-d @-` beside `--config -`.

(`apikey:` header: `header = "apikey: %s"`; the Supabase example sends both headers, so two `header =` lines.) Files, by content
anchor: `postmerge/SKILL.md` (the Sentry monitors curl), `postmerge/references/sentry-error-count-delta.md` (the issue GET keeping
`get_rc` capture, and the `-X PUT` resolve call with `SENTRY_RW_TOKEN`), `reproduce-bug/SKILL.md` (the Sentry issues curl), `preflight/SKILL.md` (the service-role example), `ship/SKILL.md` (the Supabase column-verify curl carrying `apikey` and `Authorization`; it is a lifecycle skill with a byte ceiling in `skill-body-budget.json` and ~713 B of headroom, so record `ceiling - wc -c` before and after and trim non-rationale bytes in the same file if the snippet does not fit),
`agents/engineering/infra/infra-security.md` (8 Cloudflare curls: one shared `case` above the block, one `--config -` per call, or a
tiny shell function defined once), `agents/engineering/review/deployment-verification-agent.md` (the table cell). `flag-delete` and
`flag-list` SKILL.md hold prose ("passed only to `curl -H Authorization`"), reworded to "passed only on curl's stdin config" so they leave the census.
`skill-creator/references/api-security.md` (5 sites, a doc about chat visibility) is the one S7 allowlist entry (file + measured count 5).
Do not reference `scripts/lib/bearer-curl.sh` from agent-run markdown (no checkout assumed in a consumer repo).
Skill-description word budget is untouched (no `description:` edit); the `skill-security-scan` fence carve-out applies to bash fences.

**A4. Battery stage S7** in `tests/scripts/test-argv-bearer-sweep.sh` (see Guard 3): derived census, residual allowlist, ceiling.
`EXPECTED_TESTS` is re-pinned from the measured total, never by arithmetic, and never downward without a named reason (B and C delete rows).

### PR B — registry template (#10119) and the registry heartbeat curls (#10093 part)

All in `apps/web-platform/infra/cloud-init-registry.yml`, one commit with its suites and battery rows, so declining the replace is one revert before merge:

1. `_htp_verify` (anchor: the function containing `htpasswd -vb /etc/zot/htpasswd "$1" "$2"`): `printf '%s' "$2" | htpasswd -vi /etc/zot/htpasswd "$1" >/dev/null 2>&1`, then the unchanged `case "$?"` (0 true, 3 false, else unknown). The probe script has no `pipefail`, so `$?` is `htpasswd`'s; a row pins that 127, 6 and 1 still map to `unknown` through the pipe, and a static row pins that the probe script has no `set -e` and no `pipefail` before `_htp_verify` (either would turn rc 3 into `unknown` or abort the script); an `htpasswd -vi` row for a password over 72 bytes and over 255 bytes records the bcrypt-truncation and stdin-limit behavior.
2. Boot step (anchor: `htpasswd -Bbn '${zot_pull_user}' "$ZOT_PULL_TOKEN"`, inside `doppler run ... -- bash -s <<'ZOTEOF'` whose first line is `set -euo pipefail`): `install -m 600 /dev/null /etc/zot/htpasswd` replacing the post-hoc `chmod 600`, `/etc/zot` is created with `install -d -m 755`; then two separate pipelines `printf '%s' "$ZOT_PULL_TOKEN" | htpasswd -Bin '${zot_pull_user}' > /etc/zot/htpasswd` and the push line with `>>`; empty-token guards stay above. Each `htpasswd` has its own pipe, so it cannot consume the `bash -s` script text.
3. Two heartbeat curls (CTO ruling, Fork 4), anchors `curl -fsS -m 10 "${disk_heartbeat_url}"` and `curl -fsS -m 10 -o /dev/null "${liveness_heartbeat_url}"`: `curl --disable --noproxy '*' -g -fsS -m 10 --config - < <(printf 'url = "%s"\n' '${disk_heartbeat_url}')` (liveness keeps `-o /dev/null`), the `|| PING_RC=$?` and `if ...; then PING=ok` shapes intact (process substitution preserves curl's status; both scripts are `#!/usr/bin/env bash`). No runtime shape guard (provider-generated Terraform literal; bytes are scarce), but a RENDER-TIME check that costs no runtime bytes: the offline render must show both URLs matching `^https://[A-Za-z0-9._~:/?&=%+-]+$` (a Terraform `validation` block on the source attribute or a row over the budget script's render), because a `'`, `\\`, `"` or newline in the single-quoted literal would break the quoting or inject a config directive. Do not add a comment line that contains `${...}` (a templatefile interpolates inside comments).
4. Reword comments that still name the argv form (line-18 trailing comment, the `htpasswd -vb` prose near the probe, `zot-image.provenance.md` "baked with `htpasswd -Bbn`"); the line-18 trailing comment is not stripped from `user_data`, so shortening it buys bytes.
5. Budget: run `bash apps/web-platform/infra/registry-userdata-budget.sh` before and after; ~100 B headroom; a shortfall is paid by stripping non-rationale bytes in the same file, never by raising `REGISTRY_GZIP_BUDGET`. **Fallback order if stripping cannot cover it:** (1) drop the two heartbeat conversions from PR B (they buy only the `/proc` half, see Problem Statement) and ship them with PR C's probe scripts as a separate registry-template change that waits for the next intended replace, (2) never drop the `install -m 600` line or an htpasswd conversion (they are #10119's whole ask).

Tests: `registry-boot-guard.test.sh` stays green (probe-block pins hold: `printf '%s' "$2"` names the function argument; no `printf .*ZOT_*_TOKEN`) and gains the 127/6/1-through-the-pipe row; `htpasswd-stdin.test.sh` gains the rendered-boot-block row: extract the actual ZOTEOF block from the YAML, render `${zot_pull_user}`/`${zot_push_user}` and the `$${...}` escapes, run it through `bash -s` inside the digest-pinned `ubuntu:24.04` + `apache2-utils` image with stubs for `docker`/`doppler`-adjacent commands (take the rendered text from the same offline `templatefile` render `registry-userdata-budget.sh` already produces, read at work time, rather than a hand-written substitution; assert the `doppler run ... -- bash -s <<'ZOTEOF'` wrapper line statically), failure arms included (a failing first `htpasswd` aborts under `set -e` before the `>>`; no half-written second entry; mode 600 from creation); battery S6 per Guard 2; `.claude/hooks/grep-q-pipe-guard.test.sh` `PRODUCER_JOIN`/`PJ_TRIPLES` re-measured by the derivation if new rows add a stub or producer.

**Pre-merge read-only preview (before the PR is held for the go-ahead):** run `bash scripts/registry-delivery-change.sh` and the render comparison against the dispatcher's last successful run and record in the PR body that this PR is the ONLY render delta (otherwise name the other deltas it will deliver), and record the current `boot_id` from the latest `SOLEUR_ZOT_DISK` row for the follow-through probe.

**Hand-over note (the PR stops here).** PR body first line: "Merging this PR replaces the production registry host unattended (registry-host-replace-dispatch.yml push trigger); merge only when the replace can be watched." The note carries the exact steps: merge command (`gh pr merge <N> --squash` after explicit go-ahead; `Closes #10119` in the body, not the title), watch (`gh run list --workflow registry-host-replace-dispatch.yml --limit 3` then `gh run watch <id>`), post-merge read-only check with no SSH (`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK`; the probe pairs the absence arms with the positive control that a fresh `SOLEUR_ZOT_DISK` row IS present, expect `htpasswd_pull_matches=true htpasswd_push_matches=true`, a non-unknown `zot_image_digest`, the registry `/v2/` pull path answering 200/401 through the existing health gate), and the abort path (expect `user_data` drift on `hcloud_server.registry` until the replace lands; if the dispatcher's read-only preflight refuses, re-fire by hand per its runbook; revert PR re-fires another replace). The post-merge verification is NOT left to prose: it is the follow-through probe below.

### PR C — inngest heartbeat (#10120) and the three probe scripts (#10093 last part)

1. `inngest-bootstrap.sh` (`HEARTBEATSCRIPTEOF`, POSIX `sh`/dash): re-implement from `b48247d559` against current `main`: `https://` tested on its own, then a NEGATED-class `case` over the rest, no trim, no host pin; `printf 'url = "%s"\n' "$INNGEST_HEARTBEAT_URL" | exec /usr/bin/curl --disable --noproxy '*' -gfsS --max-time 10 --config - >/dev/null` (pipe, not heredoc: Rule E refuses a heredoc feeding the config; no `[[ ]]`, no process substitution); a refusal makes zero requests, exits 2, and logs one value-free marker through the existing hourly `dark_arm_emit_due` limiter on its own stamp; the marker is assigned to a variable first so no `logger` line names the URL (the suite bans exactly that shape). `inngest.test.sh`: https canary URL, recording curl stub, twelve hostile or malformed values with zero requests, limiter re-emit row, static POSIX-shape row, and a dash row (prefer a local `dash` when `command -v dash` succeeds, which CI runners satisfy; the digest-pinned ubuntu container is the fallback; fail-closed in CI, a loud counted skip locally so the assertion floor `INNGEST_MIN_ASSERTIONS` is not failed by a docker-less run); floor re-measured (the commit moved 451 to 506; current literal is `INNGEST_MIN_ASSERTIONS=451`).
2. The three probe scripts (bash, `set -u`), same transport as the converted `web-git-data-probe.sh`: copy its `_hb_url_ok` and a per-attempt `_hb_curl` (`curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL")`, a fresh substitution per attempt because one is consumed once). `web-zot-consumer-probe.sh` and `inngest-consumer-probe.sh` `_ping()` (two attempts each), `web-private-nic-guard.sh` `beat()` (its comment "still rides curl's argv (tracked as #9639)" is rewritten). The marker is rate-limited so a persistent malformed URL does not ship 1,440 rows a day per script (`inngest-consumer-probe.sh` routes it through its existing `_fault` limiter, whose ~48 rows/day ceiling is enforced; the zot consumer and the NIC guard use an hourly stamp under `/run`). Refusal markers `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<WEB_ZOT_CONSUMER_URL|INNGEST_CONSUMER_URL|WEB_NIC_GUARD_URL>` to stderr (each unit's SyslogIdentifier ships it), folded into the existing fail-soft arm (a refusal is a WARN plus no ping, never an argv fallback). Test seams: the stub curl now records the stdin `url = "` line per attempt and fails on a missing line; enumerate every consumer first (`web-zot-consumer-probe.test.sh` T8 counts argv lines per repo and its stub already records stdin for the credential config; `web-private-nic-guard.test.sh` has a `transport_audit` over recorded argv and an X2 row; several negative rows go vacuous once the URL leaves argv and are repointed to the recorded line).
3. Battery S6-HB: delete all four `S6H_ALLOW` entries, `S6H_ALLOW_CEIL` 4 to 0, add the three scripts and `inngest-bootstrap.sh` to `S6H_CONVERTED`, mutation rows per Guard 1; `EXPECTED_TESTS` re-measured. `scripts/lint-shell-trace-credential-refusal.test.sh`, ADR-280 census rows and `.claude/hooks/grep-q-pipe-guard.test.sh` re-measured.

**Hand-over note (the PR stops here).** PR body states: `deploy-script-tests` GuardA reds by design (sanctioned window, #9081; precedent #10073), no pin bump rides this PR because a pre-merge tag is impossible (#8775, ADR-232 A5), no manual tag push (it starts nothing). On merge: the mint workflow mints the next `vinngest-v*` tag, builds and mirrors the image, and the build's bump job opens the pin-bump PR; GuardA returns green on that PR. Merge only after PR B has settled. Read-only verification is the follow-through probe below (mint run concluded success, the pin-bump PR merged, `cloud-init-inngest-bootstrap.test.sh` GuardA green on `main`). A "no `SOLEUR_CREDENTIAL_REFUSED` row for the inngest script" check is deliberately NOT claimed: the script reaches its host only at a later image deploy or replace, so absence would be vacuous until then; the three probe scripts' absence check is paired with a positive control (their heartbeats arriving, `arm-heartbeats.sh --status`).

## Follow-Through Enrollment

PRs B and C end at a hand-over whose merge the pipeline never performs; the post-merge reading must not rot as operator-action prose
(`hr-ship-message-no-operator-checklist`, `wg-block-pr-ready-on-undeferred-operator-steps`). The convention
(`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`) is binding: a probe is a PURE verdict emitter (exit 0 PASS, 1 FAIL,
2 NOT YET, 3 CANNOT ESTABLISH), the sweeper closes only the tracker that carries the directive, and the probe must be safe under the sweeper's
`dry_run=true` and its closed-set re-runs (so it never writes: no `gh issue close`, no comments). The trackers are therefore the work issues themselves;
at work time a `<!-- soleur:followthrough script=<path> earliest=<filing time, literal ISO> secrets=<names> -->` directive and the `follow-through` label are
added to each (`gh issue edit`, so the directive is not on a new issue that merely points at them). `earliest=` is the filing time because the merge time is
unknown pre-merge; each probe exits 2 until its PR is merged. Before filing, copy each probe to the main checkout (the `gh issue create`/`edit` hook resolves
`script=` there, not in the worktree) and dry-run it. Four probes, each with its own `.test.sh` stubbing `gh` and Better Stack (unit layer, no network):

- `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` (tracker #10119; `secrets=GH_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD`, confirm each name against `.github/workflows/scheduled-followthrough-sweeper.yml`'s env at work time and wire any missing one there). It resolves the merge SHA itself (`gh pr list --head <branch> --state merged`), exits 2 until merged, and PASSes only when (i) a `registry-host-replace-dispatch.yml` run whose head is at or after the merge SHA reports `deliver=true` AND `apply_conclusion=success` (a `success` run with `deliver=false` is a no-op, and the dispatcher's concurrency group may coalesce the merge SHA's own run into a successor whose range subsumes it, so the probe does not require a run for the exact SHA), AND (ii) a `SOLEUR_ZOT_DISK` row newer than that apply with a `boot_id` different from the pre-merge `boot_id` (the pipeline records the pre-merge value in the PR body before marking ready) shows `htpasswd_pull_matches=true htpasswd_push_matches=true` and a non-unknown `zot_image_digest`. The old host emits the same `true true` row every 5 minutes today, so a fresh-row check alone would close the tracker on pre-replace data. The not-launched detector it cites is the unpaused `soleur-registry-disk-prd` heartbeat (period 900, grace 600), not `state_status=unknown` (a boot block that aborts before the reporter cron is installed emits no row at all). Exit 3 when the read path is unproven.
- `scripts/followthroughs/inngest-heartbeat-stdin-10120.sh` (tracker #10120; `secrets=GH_TOKEN`): PASS when the mint run for a commit at or after the merge SHA concluded success, the pin-bump PR is merged, and `cloud-init-inngest-bootstrap.test.sh` GuardA is green on `main` (read via the merged bump PR's required-check state or a read-only rerun, never a claim from memory). It does NOT claim "no `SOLEUR_CREDENTIAL_REFUSED` for the inngest script": that script reaches its host only at a later image deploy, so absence would be vacuous. The `inngest_prd` monitor is `paused = true` in source ("paused until the operator confirms inngest-server is running"), so for this script the refusal marker (tag `inngest-heartbeat`) is the SOLE detector; a false refusal pages nobody. State that in the PR body.
- `scripts/followthroughs/argv-probes-heartbeat-10093.sh` (tracker #10093; `secrets=GH_TOKEN BETTERSTACK_API_TOKEN`): PASS when PR A is merged (its S7 stage exists on `main`), the #10119 and #10120 trackers are CLOSED, the push-apply run for PR C's merge SHA concluded success, and then, at least period+grace after that run (240 s for the zot probe, 480 s for the NIC guard), the armed web monitors read `up` (`arm-heartbeats.sh --status <name>` for each `web_hosts` key's `soleur-web-zot-consumer-<host>` and `soleur-web-nic-guard-<host>`; a `paused` monitor is exit 3 CANNOT ESTABLISH, not a pass, because a paused monitor exposes no ping time). A monitor that read `up` stays up for period+grace after the last real beat, so the delay is what makes the control mean something.
- `scripts/followthroughs/argv-sweep-umbrella-9757.sh` (tracker #9757; `secrets=GH_TOKEN`): PASS when #10119, #10120, #10091, #10092 and #10093 are all CLOSED and #9757's body has no unchecked box. This gives the umbrella an owner; the checklist ticks themselves are made by the PR authors as each lands.

The PR bodies reference the trackers as `Tracks #N` (and `Ref #N`), which is what lets ship's operator-step gate see a deferred, automated owner.

## Operator Holds

(Consumed by ship Phase 6 at the draft exit; a hold that cannot be evaluated STANDS.)

- **PR B hold:** do not arm auto-merge and do not merge until the operator gives an explicit go-ahead for the production registry host replace (an authorization no agent can discharge). PR B stays a draft, or ready with no auto-merge armed, and the pipeline's "run the merge" step does not apply to it.
- **PR C hold:** do not arm auto-merge and do not merge until PR B is MERGED (`git merge-base --is-ancestor <B sha> origin/main`) AND tracker #10119's probe verdict is PASS (its issue is CLOSED) AND the operator has given an explicit go-ahead for the tag mint and web-1 re-delivery.
- **PR A:** no hold, but merge it only when no registry replace is running and, while B is open, not during B's replace window (A's own release path mirrors through the registry).

## Production-apply coupling

| File in PR | Workflow(s) fired on merge | Effect on a live system |
|---|---|---|
| any `plugins/soleur/**` file (PR A: community scripts, lib, markdown, the `.ts` comment under `apps/web-platform/server`) | `web-platform-release.yml` (non-test, non-docs only; `plugins/soleur/test/**` and `tests/scripts/**` alone do not fire it), `version-bump-and-release.yml` (`plugins/soleur/**`, no excludes: EVERY A file under `plugins/soleur/`, tests included), `deploy-docs.yml` (`plugins/soleur/skills/**`, `agents/**`), `skill-security-scan-postmerge.yml` (every push) | a version release, the routine production app container deploy, a docs-site deploy, a post-merge scan. No infra apply, no mint, no registry replace. |
| `apps/web-platform/infra/cloud-init-registry.yml`, `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh`, `zot-image.provenance.md` (PR B) | push apply (no Terraform diff in its `-target` sets), `web-platform-release.yml`, and **`registry-host-replace-dispatch.yml`** (push trigger on the exact file; no reviewer gate, no confirm token) | renders `user_data` at both SHAs and, on a byte change, runs the registry host replace after a read-only preflight: **the sole image pull path is replaced unattended** and the converted boot block executes for the first time on the new host. Volume preserved. Whole-line comments are stripped at render and do not count; code and the line-18 trailing comment do. |
| `web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh`, `web-private-nic-guard.sh` and their suites (PR C) | push apply | `terraform_data` SSH re-delivery of each script to web-1 (`triggers_replace` hashes the file); also in the baked `host_script_files` hash that renders into web cloud-init (`hcloud_server.web` ignores `user_data`: no replace). Next 60 s tick runs the converted ping. |
| `apps/web-platform/infra/inngest-bootstrap.sh`, `inngest.test.sh` and also `inngest-consumer-probe.sh` + `.test.sh` (the `inngest*` glob matches them, so they fire the mint too) (PR C) | push apply (no Terraform diff), `mint-inngest-bootstrap-tag.yml`; `apps/web-platform/infra/*.sh` also fires `validate-vector-config.yml` (validation only) | tag mint, image build through `infra-privileged`, pin-bump PR; no host change until a later image deploy or replace |
| `tests/scripts/test-argv-bearer-sweep.sh`, ADR addendum, plan/spec files | none | docs/tests |

Net: PR A is a routine release set (app release, version release, docs deploy). PR B is one unattended registry replace, delivering EVERYTHING since the dispatcher's last-success watermark (an earlier `variables.tf`/`zot-registry.tf` delta whose delivery was refused or coalesced ships in the same replace), at the same moment as a concurrent `web-platform-release.yml` whose mirror path pulls through the registry being replaced; until the replace lands `hcloud_server.registry` shows `user_data` drift (the drift alerter may open an issue; the abort path says so). PR C is three web-1 re-deliveries, one tag mint and, later, the auto-merged pin-bump PR (another release and push apply, intended by ADR-232). None is dispatched by hand
by the pipeline (`hr-menu-option-ack-not-prod-write-auth`); B and C end at a green, ready PR whose hold stands (the operator brief asks for ready; the Operator Holds section keeps ship from merging it). Squash-merge means per-commit staging exists only before merge;
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
conflict keeps both): A also edits the 2026-10-12 addendum's stale sentences ("(c) #10091 and (e) #10092 are deferred", the heartbeat and probe-scripts-"tracked in #10093" statements) to point at the new sub-section, and records the lib control-character check as the sink-appropriate validator (deviation from "the same allow-list": different sink), the lock/atomic-write rule for `.env` writers and the inline markdown form (shape `case` + `--config -`, no library reference); B records `htpasswd -i` as the password transport (not curl, so not the library) and the registry heartbeat form with no runtime guard (provider-generated literal, render-time check instead), stating explicitly that these two curls are OUTSIDE the registry section's `_bs_ok` inline-judge parity audit (verify at work time that the audit does not count `curl` sites, so adding a guard-less curl cannot red it); C records the three probe scripts and the inngest body under the same inline-guard exception, the deleted allowlists, and the residual (same-uid `/proc/<pid>/environ` readers). The status flip `adopting` to `accepted` stays with #9905's follow-through. This is a task, not a follow-up issue.

### C4 views

No new element or relationship, checked against all three files (`model.c4`, `views.c4`, `spec.c4`): external human actors (founder/Owner, inbound-mail correspondents, beta testers, PR contributors: none added or changed), external systems (Better Stack, Doppler, Discord, Hetzner, Sentry, the zot registry and the Inngest hosts: all modeled; no new vendor or edge, this changes how a credential reaches a child process), containers and stores (no new store; `inngest`, `inngestRedis`, the git-data store untouched), and actor-to-surface access relationships (unchanged). The follow-through probes use the already-modeled sweeper, Better Stack and GitHub. `plugins/soleur/test/c4-count-parity.test.sh` (green now, re-run at the end of each PR) is a regression check on derived cardinalities only; it says nothing about edges, which the enumeration above covers.

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
| 4 | Inject a synthetic allowlist entry for an already-converted script into the harness's array (the real array is empty after C, so the stale-allowlist row cannot rely on a populated one) | RED (`stale-allowlist`, and nothing else) |
| 5 | Rename the word `heartbeat` everywhere in a scratch tree so the scan sees 0 scripts | RED (`floor`) |
| 5b | Keep `_hb_url_ok` defined but delete its call in one probe | RED in that probe's own suite (zero requests plus one marker expected) and in the inngest suite for its body; the static class-before-config row cannot see this |
| 6 | Positive-pattern `case` in the POSIX script, or `[[ ]]` in it | RED (hostile-value row; dash row) |

**Harness rows.** The ceiling rows become `0 == 0` plus a grow-by-one mutant; re-anchor the M-stale and M1 edits on text that still exists after C. A stub curl that ignores stdin and records nothing must make the per-attempt row RED (a missing recorded `url = "` line fails it); must-PASS: a well-formed URL with a different token than the canonical fixture, run once under bash and (inngest body) once under dash.

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
| 5 | Put `htpasswd -Bbn u "$ZOT_PULL_TOKEN"` back while keeping the pipe | RED (an argv-recording wrapper ahead of the real `htpasswd` on `PATH` logs argv then `exec`s the real binary; the row asserts no argument holds the token and no option cluster holds `b`; a correct hash would not catch this, and an argv-form control run must go RED) |
| 6 | Make the boot block's first `htpasswd` fail and keep going | RED (failing first aborts before `>>`; no second entry; the docker launch is not reached; the file is not left half-built for a later start) |
| 7 | Leave a `$${` unrendered or hand-edit the extracted block | RED (the extraction comes ONLY from the budget script's offline `templatefile` render; non-empty and `bash -n` rows; fails closed in CI on a missing `terraform` as well as a missing docker) |

**Harness rows.** A suite edit that removes the rendered-block extraction (empty block) must RED (non-empty extraction row); the `htpasswd-stdin.test.sh` rendered-block arm joins `DECLARED_ROWS` and the `_arm_skip` counts so a local docker-less run reports the skipped rows, and states why it needs a network call (`apt-get install apache2-utils`); must-PASS: option cluster in another order (`-iB`) and a `-vb` that appears only in a YAML comment.

### Guard 3 — No agent-run markdown teaches a bearer or apikey header on curl argv (stage S7)

**Property.** No tracked `*.md` under `plugins/` carries `curl ... -H/--header Authorization|apikey|X-Api-Key|Private-Token|Api-Key` outside the residual allowlist.

**Assembly.** One scan over `git ls-files` `plugins/**/*.md` (not `knowledge-base`, which holds history; the plugin docs site excluded), run over LOGICAL lines (backslash continuations joined, as the S6-HB scanner does: 6 of the 22 measured hits carry `-H` on a continuation line, so a per-line pattern is green over them), pattern-anchored not line-anchored (`cq-cite-content-anchor-not-line-number`): a `curl` command word and a `-H`/`--header` whose header name is Authorization, apikey, X-Api-Key, Private-Token or Api-Key. Residual allowlist by file with its measured count (`api-security.md`, 5), shrinking by deletion only, with a ceiling constant like `S6_ALLOW_CEIL` taken from the measured count; a floor that the scan sees at least the allowlisted file (so a renamed pattern is RED). Rule E does not read markdown, so this is the only recurrence guard.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `curl -H "Authorization: Bearer $T"` to one converted file | RED |
| 2 | Add a compliant converted snippet, then a violating one in a different file | RED (the second, by identity) |
| 3 | Allowlist grows by one entry | RED (ceiling) |
| 4 | Rename the scanned header word in a scratch tree so the scan sees 0 | RED (floor) |
| 5 | Put the `-H "Authorization: ..."` on a `\`-continuation line of an otherwise converted snippet | RED (logical-line join) |
| 6 | `--header=Authorization:`, a lowercase `authorization:`, `-H"Authorization` with no space, and a curl inside a table cell | RED each (the header-name match is case-insensitive and shape-tolerant; a table row is one physical line and is not split on pipe, semicolon or double-ampersand the way the S6-HB scanner splits shell) |
| 7 | A continuation that ends a line just before the closing code fence | no false positive and no hidden curl (the join stops at a fence boundary) |
| 8 | `-d @-` beside `--config -` in a converted snippet | RED (both consume stdin) |

**Harness rows.** Must-PASS: a snippet using `header = "Authorization: Bearer %s"` on a `--config -`, the argv-safe `-H @<(printf ...)` form (as in `cf-token-scope/references/widen-playbook.md`), and a prose sentence with `-H` and no `curl` command word.

### Guard 4 — `write-env` is atomic, serialized, and mode 600 from birth

**Property.** After any number of concurrent `write-env` runs each managed key appears exactly once in `.env`, `.env` is never observable partial, never wider than 0600, and the temp is renamed within one filesystem.

**Assembly.** Every setup script's `cmd_write_env` flows through ONE helper `_wenv_write`, whose block is pinned byte-identical across the four scripts by the community suite (the chokepoint is the helper; the population is `WRITERS` derived by the suite's existing manifest row, floor 4). The lib's `soleur_op_env_upsert` is a separate sink with its own check.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the lock acquisition with a no-op in one copy | RED under a FORCED interleave: different writers (bsky, discord, x, linkedin) run concurrently with a `grep`/`mktemp` shim that sleeps inside the critical section and records start/end intervals, and every writer's key set must survive (a whole-file atomic replace makes same-script duplicates impossible, so only lost updates between different writers can show the missing lock) |
| 2 | Put `mktemp` back in the default temp dir | RED (same-directory shim row) |
| 3 | Create a fresh `.env` with default umask then chmod (instead of under `umask 077`) | RED (creating-command shim reads the mode at birth under `umask 000`) |
| 4 | Treat `grep` rc 2 as success (`\|\| true`) | RED (unreadable-`.env` row) |
| 5 | Leave `.env.lock.d*` or `.env.tmp.*` behind (also after SIGTERM) | RED (artifact rows) |
| 6 | Widen the helper in ONE copy | RED (byte-identity, with an extraction-sanity row: non-empty, minimum length, anchor strings, so an empty extraction cannot make the four-way compare trivially green) |
| 7 | Stale recovery by `rmdir` then `mkdir` | RED (two-waiter race row) |
| 8 | Replace `readlink -f` resolution with the raw path | RED (symlinked-`.env` row: the link would be replaced by a regular file) |

**Harness rows.** The parallel harness must RED when only one writer ran (recorded overlapping start/end intervals are asserted, not a writer count); must-PASS: an existing `.env` with unrelated keys and a different legitimate value set. `community-argv.test.sh` pins an exact count (`-ne 1436`): re-pin it from the measured total when the new rows land.

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeats for the converted scripts keep arriving after their delivery. Armed (a missed beat pages): the registry disk beat soleur-registry-disk-prd (period 900, grace 600) after the replace, and the web git-data, zot consumer and NIC guard monitors after the web-1 re-delivery. NOT armed: the inngest monitors (inngest_prd and the inngest consumer are paused = true in source until the operator confirms the inngest host), so for the inngest scripts the SOLEUR_CREDENTIAL_REFUSED marker (tags inngest-heartbeat, inngest-consumer-probe) is the sole detector and the inngest bootstrap only reaches its host at a later image deploy"
  cadence: "60s for the probes and the inngest heartbeat, 5 min for the registry disk report (the heartbeat period is 900s)"
  alert_target: "operator email via the existing Better Stack heartbeat policies (git-data.tf, zot-registry.tf, inngest.tf, web-probe.tf)"
  configured_in: "apps/web-platform/infra/git-data.tf, apps/web-platform/infra/zot-registry.tf, apps/web-platform/infra/inngest.tf, apps/web-platform/infra/web-probe.tf"
error_reporting:
  destination: "layer 3, host journald to Vector Source 4 to Better Stack Logs (tags are allowlisted in vector.toml; the value-free SOLEUR_CREDENTIAL_REFUSED line is not touched by the PII scrub); the registry host posts SOLEUR_ZOT_DISK directly from cloud-init; layer 6 for the community scripts and suites (run logs); the community scripts' refusals mirror through the agent PostToolUse extractor (MARKER_RE) when printed inside an agent Bash call"
  fail_loud: "SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<NAME> from a converted heartbeat script (hourly limiter on the 60 s inngest unit), the existing WARN lines, SOLEUR_BOOTSTRAP_BAD_ARG for the lib validator, and the missed beat itself through the heartbeat policy"
failure_modes:
  - mode: "stored heartbeat URL fails the shape guard in a probe or the inngest script"
    detection: "layer 3: SOLEUR_CREDENTIAL_REFUSED row in Better Stack Logs (doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_CREDENTIAL_REFUSED; inside the follow-through sweeper the BETTERSTACK_QUERY_* env is used directly), independent of the beat. Each probe's marker is rate-limited (the existing _fault limiter in inngest-consumer-probe.sh, an hourly /run stamp in the zot consumer and NIC guard) so a persistent malformed URL costs about 24 rows a day per script, not 1,440; Vector tags web-zot-consumer-probe, inngest-consumer-probe and web-nic-guard (the NIC unit's SyslogIdentifier, not web-private-nic-guard) are already allowlisted"
    alert_route: "the heartbeat policy pages on the missed beat; the marker row names the cause and rides the same journald path, so it can be absent exactly when that path is the fault"
  - mode: "htpasswd -vi or the converted boot block mis-behaves on the replaced registry host (htpasswd_*_matches wrong, or zot not launched)"
    detection: "layer 3 direct POST, not Vector: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK reads htpasswd_pull_matches and htpasswd_push_matches (the follow-through probe keys on a changed boot_id); a boot block that aborts before the reporter cron is installed emits NO row, which the unpaused soleur-registry-disk-prd heartbeat catches after about 25 minutes of silence; offline, the rendered-block row in htpasswd-stdin.test.sh before merge"
    alert_route: "no alert keys on htpasswd_*_matches today (query-only for a mismatch); soleur-registry-disk-prd pages on the not-launched case, and the pull-path health gate covers a registry that answers wrongly"
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
  command: grep -c -e 'curl -s -H' plugins/soleur/skills/reproduce-bug/SKILL.md
  expected_output: "0"
```

The probe above is PR A's (it prints `1` on `main` and `0` once A3 lands: a RED to GREEN reading). PR B and PR C each carry their own probe in their Acceptance Criteria, derived the same way and checked before they are marked ready: PR B `grep -c -e 'htpasswd -Bbn' -e 'htpasswd -vb' apps/web-platform/infra/cloud-init-registry.yml` expecting `0` (the comments naming the argv form are reworded, so the whole-file count is the right reading); PR C `grep -c -e 'max-time 10 "[$]INNGEST' apps/web-platform/infra/inngest-bootstrap.sh` (one match on `main`) expecting `0`.

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
- `plugins/soleur/skills/postmerge/SKILL.md`, `plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`, `plugins/soleur/skills/preflight/SKILL.md`, `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/agents/engineering/infra/infra-security.md`, `plugins/soleur/agents/engineering/review/deployment-verification-agent.md`, and the prose rewording in `plugins/soleur/skills/flag-delete/SKILL.md` and `plugins/soleur/skills/flag-list/SKILL.md`
- `tests/scripts/test-argv-bearer-sweep.sh` (stage S7, `EXPECTED_TESTS`)
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (follow-up paragraph)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` only if a count moves

**PR B:**

- `apps/web-platform/infra/cloud-init-registry.yml`, `apps/web-platform/infra/registry-boot-guard.test.sh`, `apps/web-platform/infra/htpasswd-stdin.test.sh`, `apps/web-platform/infra/zot-image.provenance.md`
- `tests/scripts/test-argv-bearer-sweep.sh` (S6 allowlist deletion, converted-site rows, registry-heartbeat row, `EXPECTED_TESTS`)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (only if the derivation moves), ADR-280 paragraph
- Create: `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` and its `.test.sh`; the follow-through tracker issue

**PR C:**

- `apps/web-platform/infra/inngest-bootstrap.sh`, `apps/web-platform/infra/inngest.test.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.sh` + `.test.sh`, `apps/web-platform/infra/inngest-consumer-probe.sh` + `.test.sh`, `apps/web-platform/infra/web-private-nic-guard.sh` + `.test.sh`
- `tests/scripts/test-argv-bearer-sweep.sh` (S6-HB allowlist deletion, converted set, mutation rows, `EXPECTED_TESTS`)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (re-measure), ADR-280 paragraph
- Create: `scripts/followthroughs/inngest-heartbeat-stdin-10120.sh` and its `.test.sh`; the follow-through tracker issue

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10119-10120-10091-10092-10093-argv-bearer-followups/tasks.md` and `decision-challenges.md` (this plan's own artifacts).
- No new production file. PR B/C branch names are chosen at work time (suggested `fix-argv-registry-htpasswd-10119`, `fix-argv-inngest-probes-10120`), each cut from `main` after A merges or rebased onto it.

## Open Code-Review Overlap

None (open `code-review` issues queried by body-contains on every planned path; no match; 89 open issues scanned).

## Acceptance Criteria

### Pre-merge (per PR)

**PR A**

- [ ] Diff scope: `git diff --name-only origin/main...HEAD` touches nothing under `apps/web-platform/infra/` (so no infra apply or mint is fired) and only `apps/web-platform/server/git-lock-marker-telemetry.ts` under `apps/web-platform/`; allowed besides the Files-to-Edit list: pipeline-written `knowledge-base/` artifacts.
- [ ] The four setup scripts carry a byte-identical `_wenv_write` block; the parallel-run, no-`flock`, mode-at-rename, same-directory, unreadable-`.env`, killed-run and artifact rows in `community-argv.test.sh` are green and each RED row was observed RED against the unfixed scripts first.
- [ ] `soleur_op_env_upsert` refuses a control character with a value-free marker and still writes `$ " ' space ! # ?` values; `operator-script.test.sh` green; the lib's `.env` consumers were grepped and recorded.
- [ ] `git diff -U0 origin/main...HEAD -- apps/web-platform/server/git-lock-marker-telemetry.ts | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*//'` prints nothing (comment-only; the `MARKER_RE` literal is unchanged); every file `git grep -l SOLEUR_CREDENTIAL_REFUSED -- plugins/soleur/skills/community/scripts` lists is named in the comment; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and `./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts` green.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` reports every S7 row green (the derived census over logical lines finds only the `api-security.md` allowlist entry, count 5) and the S7 mutation rows RED against their mutants; `EXPECTED_TESTS` re-pinned to the measured total; for each edited lifecycle skill the budget headroom (`ceiling - wc -c` from `skill-body-budget.json`) is recorded and non-negative (`ship` started at ~713 B).
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` green; ADR-280 follow-up paragraph present.
- [ ] PR body: `Closes #10091`, `Closes #10092`, `Ref #10093`, `Ref #9757` (never `Closes #9757`); first line states the merge fires a routine release set (app release, version release, docs-site deploy, post-merge scan) and no infra apply, mint or replace.

**PR B**

- [ ] Diff scope: `git diff --name-only origin/main...HEAD` is a subset of {`apps/web-platform/infra/cloud-init-registry.yml`, `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh`, `zot-image.provenance.md`, `tests/scripts/test-argv-bearer-sweep.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, the ADR-280 file, `scripts/followthroughs/*` for its tracker, and this plan's pipeline-written artifacts under `knowledge-base/`}; in particular no `inngest*` file (it would fire the mint) and no `zot-registry.tf`/`variables.tf` (they are also dispatcher inputs).
- [ ] No `htpasswd` option cluster with `b` and no heartbeat URL on curl argv in `cloud-init-registry.yml`; `S6_ALLOW` deleted, `S6_ALLOW_CEIL` 0, floor rows and converted-site rows replace the "residual site" rows, registry-heartbeat row and mutation rows green; `EXPECTED_TESTS` re-measured.
- [ ] The boot block rendered from the real YAML runs through `bash -s` in the digest-pinned `ubuntu:24.04` + `apache2-utils` image, failure arms included; `htpasswd-stdin.test.sh` fails closed in CI on a missing docker.
- [ ] `registry-boot-guard.test.sh` green (including the 127/6/1-through-the-pipe row); `cloud-init-user-data-size.test.ts` green with `REGISTRY_GZIP_BUDGET` unchanged; `registry-userdata-budget.sh` stored size recorded before and after in the PR body.
- [ ] PR body first line states the merge replaces the production registry host unattended; carries the hand-over note (merge command, watch command, read-only post-merge check, abort path); `Ref #10119`, `Ref #10093`, `Ref #9757`, `Tracks #10119`; the PR is marked ready (green) per the operator brief, auto-merge is never armed, and the standing hold in `## Operator Holds` keeps ship from merging it; the discoverability probe `grep -c -e 'htpasswd -Bbn' -e 'htpasswd -vb' apps/web-platform/infra/cloud-init-registry.yml` prints `0` (expected_output `0`; it prints `5` on `main`).

**PR C**

- [ ] Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the Files-to-Edit list for PR C plus `scripts/followthroughs/*` and pipeline-written `knowledge-base/` artifacts; no `cloud-init-registry.yml`.
- [ ] `bash apps/web-platform/infra/inngest.test.sh` green at the re-measured floor including the dash row; `web-zot-consumer-probe.test.sh`, `inngest-consumer-probe.test.sh`, `web-private-nic-guard.test.sh` green with the stub reading stdin per attempt; `S6H_ALLOW` deleted, `S6H_ALLOW_CEIL` 0; `lint-shell-trace-credential-refusal.test.sh`, ADR-280 census rows, `web-host-provisioner-parity.test.sh`, `infra-config-gate.test.sh`, `ci-deploy.test.sh` green.
- [ ] `cloud-init-inngest-bootstrap.test.sh`: GuardA red BY DESIGN and nothing else red (recorded: every other row of the file green).
- [ ] PR body first line states the merge fires the tag mint and the web-1 re-delivery; carries the GuardA window explanation, "B before C", the read-only verification commands; `Ref #10120`, `Ref #10093`, `Ref #9757`, `Tracks #10120`, `Tracks #10093`; the PR is marked ready (green; GuardA red by design is the one exception), auto-merge never armed, held until B is merged and #10119 PASSes; the discoverability probe `grep -c -e 'max-time 10 "[$]INNGEST' apps/web-platform/infra/inngest-bootstrap.sh` prints `0` (it prints `1` on `main`).

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
- **R3: battery file shared by all three PRs.** `EXPECTED_TESTS` is a lower bound and the one guaranteed conflict: every PR re-measures the whole battery after its last rebase (a pre-ready step, not an afterthought) and the pin never decreases without a named reason (B and C delete rows, so a pin taken from a measured total can silently lower the floor: state pre- and post-values in the PR body). S7 (a new stage near the end, A) and the S6-HB ceiling/converted rows (C, around the stage's own block just before the `EXPECTED_TESTS` literal) are adjacent hunks and can conflict textually; resolve by keeping both. **Rule: PR B and PR C branch from `main` only after PR A has merged** (not "or rebased"), and C only after B.
- **R4: ADR-280 appends from three PRs** at the same end-of-file location; each PR's heading is self-describing (`### 2026-10-13 follow-ups — PR A (#10091, #10092, #10093 markdown)`, `... — PR B (#10119)`, `... — PR C (#10120, #10093)`) so a rebase that keeps both never yields duplicate headings; because B and C branch after A merges, each simply appends below the previous.
- **R5: lock portability.** macOS lacks `flock(1)` and ships bash 3.2; the mkdir fallback and the bash-3.2-safe constructs are tested in the no-`flock` row; the opt-in `COMMUNITY_ARGV_DOCKER` bash:3.2 row is extended if cheap, not a gate.
- **R6: stub fidelity.** Suites that matched curl argv must now read stdin; a stub that records nothing must fail loudly (Guard 1 harness row).
- **R7: false refusal on a liveness path.** The shape class is a superset of the proven `_url_ok`; a refusal is a false page, not silent. Before PR C is marked ready, a read-only shape count of the three probe URLs: source = the Doppler `prd` values behind `WEB_ZOT_CONSUMER_URL`, `INNGEST_CONSUMER_URL` (via its `INNGEST_CONSUMER_URL_KEY` indirection, `inngest.tf`) and `WEB_NIC_GUARD_URL` (via `WEB_NIC_GUARD_URL_KEY`), read with a read-scoped token under `doppler run`, printing only `ok`/`refused` counts per key, never a value. If the read path is unavailable the PR body says the count is unproven (no claim of green); if any value fails the guard, stop and decide then.
- **R8: GuardA red-by-design.** The window runs from PR C's merge to the merge of the auto pin-bump PR. In it `infra-validation.yml` (push to `main`) and the six-hourly `main-health-monitor.yml` run the full infra suites and may file a P1 `ci/main-broken` issue naming the GuardA carrier-drift assertions of `cloud-init-inngest-bootstrap.test.sh` (precedent #10073/#9944 rode the same window). The PR body names the exact red assertions (the `GuardA: every baked carrier is byte-identical at <tag>` row; every other row green) and says the bump PR's merge closes the window; the follow-through probe above closes the loop and the P1 issue, if one is filed, is closed with it.
- **R9: `.env` writers are user-tree writers** (`hr-write-boundary-sentinel-sweep-all-write-sites`): grep every writer of `.env` in `plugins/soleur/skills/community/scripts/` and the lib before declaring the sweep complete.
- **R10: line numbers drift.** Every cited location is paired with a content anchor; implementers re-anchor by content.

## Rollback

A: revert the PR (no live state; a revert re-fires one app release). B: a revert PR re-fires another registry replace, so treat it as a deliberate replace; the volume is preserved. C: deliveries are idempotent, a revert re-delivers the old bytes and mints another tag. Each PR is independently revertable because its battery rows ship in the same commit as the code they pin.

## Success Metrics

- Population rows, each read from its battery stage (S6, S6-HB, S7 in `tests/scripts/test-argv-bearer-sweep.sh`): heartbeat curl with the URL on argv = 0, `htpasswd` with a password on argv = 0, bearer header on curl argv in `plugins/**/*.md` = the S7 allowlist only.
- Allowlists: `S6_ALLOW` 3 to 0, `S6H_ALLOW` 4 to 0, S7 residual = `api-security.md` x5 (measured by the stage's own scan, `bash tests/scripts/test-argv-bearer-sweep.sh`).
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
- ADR-280 (and its 2026-10-12 addendum), ADR-232 (mint/bump), ADR-282 (sole-copy LUKS volume set), #9081 (GuardA PR-context exemption), #8775 (tag must sit on `main`), #10128 (inngest-bootstrap.sh since the preserved commit; #10073 precedent for the GuardA window).
