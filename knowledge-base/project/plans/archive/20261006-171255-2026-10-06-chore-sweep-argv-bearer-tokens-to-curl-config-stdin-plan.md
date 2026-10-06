---
title: "Sweep argv bearer tokens in tracked shell scripts to curl --config - (stdin)"
date: 2026-10-06
slug: sweep-argv-bearer-tokens-to-curl-config-stdin
branch: feat-one-shot-7843-argv-bearer-to-config-stdin
issue: 7843
closes: 7843
type: chore
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-10-06
**Agents used:** security-sentinel, architecture-strategist, spec-flow-analyzer, test-design-reviewer (plus the earlier CTO, DHH, Kieran and code-simplicity plan review)

### Key Improvements

1. The canonical process-substitution form FAILS Rule D when the call is outside `$(...)` (measured twice); the lint is fixed first, with a bare-form must-PASS fixture.
2. Wrapper awareness for Rules D/E is specified as a design (file-wide name collection, transitive closure, command-position match, argument splicing), not a one-liner.
3. A token-shape guard (allowlist, rejects empty) precedes every converted call: a newline in any token injects a config directive and an unset token yields a headerless request.
4. Tier 2 widened to 11 files (three run live in the push-triggered infra apply with no pre-merge exercise); the `cutover-verify.sh` exemplar edit is dropped.
5. The battery is keyed to baseline E so every commit is green, has instrument controls and a real-curl `--libcurl` oracle, models real curl, is auth-gated, and carries a pipe-form mutant row that discriminates at 100 KB.

### New Considerations Discovered

- Merge of `apps/web-platform/**` and `plugins/soleur/**` triggers a production release; the plugin scripts are vendored onto the host runtime.
- `scripts/sweep-followthroughs.sh` puts every forwarded secret on `env -i NAME=<secret>` argv in the sweeper-to-probe hop (named residual).
- `-v`/`--trace*` print the header even from a stdin config; `command printf` is still the builtin.
- `--changed` is advisory; baseline E equality lives in the lint itself so the required repo-wide run enforces it.

## Overview

Tracked shell scripts still hand curl a bearer credential as an argument (the header flag
with an `Authorization: Bearer <token>` value). Whatever is on a command line is readable from the
process table and from `/proc/<pid>/cmdline`, and it is printed by `bash -x` when a traced parent
invokes the script. This plan moves the header onto curl's stdin config channel for every in-scope
script, keeps each script's existing xtrace self-refusal green, and shrinks the commit-time lint
baselines as scripts are converted. It is the prevention follow-through for the open incident
issue #7797, which stays open as the incident record.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-10-06 on this worktree) | Plan response |
|---|---|---|
| "61 scripts / 108 sites" (#7843, measured 2026-09-06) | Live count by logical-command census (backslash continuations joined, array/variable-held headers included): **64 files / 136 curl call sites** in tracked non-test `.sh`. The same grep the brief used (`Authorization: Bearer` string, any context) returns 79 non-test files; the `-H "Authorization: Bearer` same-line form alone returns 59. The inventory drifted by +3 files / +28 sites, mostly three seed scripts that hold the header in a variable (`header_auth`) and pass it 31 times. | Re-derived inventory is the work-list (see Research Insights). The issue's numbers are not used. |
| "87 tracked non-test .sh files still carry `-H "Authorization: Bearer`" (brief) | 87 does not reproduce for non-test files: 59 same-line, 79 any-context. 92 files appear only when the grep also matches already-converted stdin forms (`header = "Authorization: Bearer`, `--header @<(printf ...)`, `printf 'Authorization: Bearer %s' \|` ) and comment/emitter prose. Nine files already use a stdin form and are NOT work. | Census excludes already-safe forms; they are listed so nobody re-converts them. |
| "shrink its baseline as sites are converted" (brief) | The two existing baselines (`lint-shell-trace-credential-refusal.baseline.txt` = Rules A/B/C, `...-d.baseline.txt` = Rule D) list files lacking the xtrace refusal / transport confinement. **Neither lists argv-bearer sites**, so converting a site shrinks neither by itself. They shrink only because CI runs `--changed` (ci.yml:231), which bypasses baselines: every touched script must be fully A/B/C/D-clean. 19 of the 57 touched files are currently in a baseline, but only 13 of the 57 FAIL the lint when scanned by explicit path (`gdpr-override`, `arm-heartbeats`, `dsar-export-oversize`, `configure-auth`, `check-cloudflare-token-drift`, `autovacuum-thrash-6168`, `concurrency-slot-wal-backoff`, `provision-plausible-goals`, `weekly-analytics`, `l3-probe-armed-6438`, `web2-standby-soak-6459`, `preapply-entrypoint-gate`, `cutover-verify`); six baselined Tier 1 files already pass and only need their entries deleted (`audit-sentry-extra-text-references`, `configure-sentry-alerts`, `verify-tunnel-ingress-origin`, `seed-dev-users`, `seed-live-verify-user`, `seed-qa-user`). 24 baseline entries repo-wide are already stale (17 of 67 in A/B/C, 7 of 31 in D: the repo-wide run reports 50 and 24 live offenders). | Phase 1 adds Rule E (argv-bearer) with its own enumerated baseline, so "baseline shrinks as sites convert" is literally true for the sweep; Phase 7 regenerates A/B/C and D baselines (they shrink by the touched files plus the stale entries). |
| "pattern in apps/web-platform/infra/inngest-boot-emitter.sh" (brief) | No such `.sh` exists on `origin/main`; only `inngest-boot-emitter.test.sh`. The proven in-repo shapes are `curl_auth()` in `cutover-verify.sh`, `-K -` in `rung2-rehearsal/seed-dirty-journal.sh`, `--config -` in `workspaces-luks-provision.sh` / `web2-rebirth.sh`, `--header @-` in `supabase-logs-query.sh`. | Canonical form is derived from those (Proposed Solution), not from the missing file. |
| "any PR that edits one of the listed callers must convert it" (#7843 trigger) | Not enforced by anything today; Rule D accepts argv bearer (measured: a compliant-D fixture with `-H "Authorization: Bearer ${TOK}"` exits 0). The `--changed` step at ci.yml:231 sits in the `lint-bot-statuses` job, which is NOT in `scripts/required-checks.txt` (advisory). The repo-wide run `scripts/lint-shell-trace-credential-refusal-repo` inside the required `test` context (test-all.sh:4213) IS blocking. | Rule E makes the trigger mechanical: new offenders are blocked by the required repo-wide run (baseline-gated); the touched-file drawdown (`--changed`) is advisory, and baseline E's equality rule makes a stale or grown list a blocking failure. |
| `cutover-verify.sh` is "already proven" | It converts the header but its `curl_auth()` omits `--disable`/`--noproxy '*'`, so Rule D fails it today (it is in the D baseline); it sits under `apps/web-platform/infra/**`, so editing it fires the push-triggered infra apply for no consumer. | Left alone (stays in baseline D); `scripts/supabase-logs-query.sh`, which Rule D's own docstring names as the repo's complete instance, is the exemplar to cite. |
| Host scripts are ordinary edit targets | 8 of the argv-bearer scripts under `apps/web-platform/infra/` are hashed into `terraform_data.*.triggers_replace` in `server.tf` and/or baked into the image (`host_script_files`, Dockerfile COPY); open tracker #7898 records that editing them re-runs prod-host provisioners on merge and belongs to a deployment window. Three more (`fresh-host-boot-trail.sh`, `verify-tunnel-ingress-origin.sh`, `zot-image-oci-archive.sh`) are not host-hashed but run LIVE inside the push-triggered `apply-web-platform-infra.yml` (or a path-triggered mirror workflow) on merge, with no pre-merge exercise of the changed transport. | All 11 deferred (Tier 2) to the residue tracker #9597; the Rule E baseline carries them. See Scope Check. |
| Rule D accepts the canonical process-substitution form | FALSE for the bare form: a call outside `$(...)` such as `curl --disable --noproxy '*' ... --config - URL < <(printf ... "$TOK")` fails Rule D with "credentialed curl sends to $TOK, which is env-settable and never compared against a literal" (measured twice; the plan's first measurement ran inside a command substitution, which `_mask_cmdsubs` hides). Cause: `_destination_vars` reads the token inside `<(...)` as a curl operand. | Phase 1 fixes `_destination_vars` first (skip tokens after a redirection operator, mask `<(...)`/`>(...)` spans) with a must-PASS fixture, before any conversion. |

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view`: #7843 OPEN (no closing PR), #7797 OPEN,
#7842 OPEN (PreToolUse hook + CI `run:` form lint: not this scope), #7898 OPEN (Rule D drawdown:
host-script boundary, not this scope). The cited files exist on `origin/main` except
`inngest-boot-emitter.sh` (stale, see reconciliation). ADR corpus: ADR-202 (xtrace self-refusal)
records the argv correction ("argv hygiene is the only defense" for a traced parent) and does not
reject `--config -`; ADR-263 records the charset-before-config-stream discipline; ADR-198 records
stdin-header precedent. No ADR rejects the mechanism.

**Property List (Phase 0.6b).**

1. P1 — No bearer token appears in the argument list of any curl in a tracked, non-test shell script, so `ps`, `/proc/<pid>/cmdline` and a traced parent's `+ curl ...` line cannot render it.
2. P2 — Conversion never weakens an existing guard: each script keeps its xtrace self-refusal and each credentialed curl keeps `--disable` first and `--noproxy '*'` (Rules A/B/C/D stay green on every touched file).
3. P3 — Behaviour is unchanged for every defined input: same HTTP request, same exit/status/`-w` output under `set -e` / `set -o pipefail`. (An undefined token is the one difference: expansion now fails inside the process-substitution subshell, so each script keeps its existing non-empty guard BEFORE the call, and a battery row pins that an unset token never reaches PASS.)
4. P4 — The baselines shrink and regrowth is mechanically visible (a new argv bearer outside the enumerated baseline fails the required repo-wide lint run; touching a baselined script is flagged by the advisory `--changed` step).
5. P5 — A broken conversion cannot hide: a script that stops sending its credential must fail a test, because follow-through soak probes auto-close trackers on a healthy-looking result.

**Cut List (Phase 0.6b).**

- Shared sourced helper lib (`scripts/lib/curl-bearer.sh`) → buys one place for the charset guard. Cut: host-deployed and plugin-shipped scripts cannot source a repo-relative lib, so it would coexist with an inline form anyway; the guard is needed at 4 response-derived-token sites only. Inline per-site/per-file wrapper is the repo precedent (9 existing sites).
- `-H @-` as the canonical (vs `--config -`) → cut: the issue prescribes `--config -`, it works on every curl the fleet runs (stdin config has always existed; `-H @file` needs curl 7.55+), and 9 sites already use it. `--header @-` sites already in tree are left alone.
- Converting GitHub workflow YAML (14 files, ~32 sites) in this PR → cut: the lint cannot see YAML, `run:` blocks execute on runners where the process table is not an exposure surface the incident touched, and #7898 §3 records the YAML boundary. Tracked in the residue issue.
- Non-Bearer argv credentials (`-u`, `X-API-Key`, OAuth1 `Authorization:` in `x-community.sh`/`x-setup.sh`) → cut from the Bearer sweep except where a second credential header travels in the same curl call (`apikey:` with the same service-role key) and must move with it. Tracked in the residue issue.
- Host-deployed and live-in-apply scripts (11 files) → cut (deployment window and no pre-merge exercise, see reconciliation).

**Mechanism measurements (this worktree, curl 8.22.0 / bash 5.3.15).**

- `printf 'header = "Authorization: Bearer %s"\n' "$t" | curl --disable --noproxy '*' -sS --config - URL` delivers the header; `/proc/<pid>/cmdline` of the curl shows `... --config - URL` with no token.
- **Config injection is real.** A token containing `"` + newline + `url = "..."` made curl issue a *second request* to the injected URL (two responses printed). Any token that comes from an API response (bsky `accessJwt`, LinkedIn `access_token`, OAuth exchanges) must be charset-guarded before it enters the config stream; env/Doppler tokens are fixed-format.
- **pipefail + SIGPIPE.** `printf ... | true` under `set -o pipefail` returned 141 on the first iteration of a 5-iteration loop and 141 for a 200 KB payload. Real curl reads the config first, so this bites a consumer that never reads stdin, which in practice means test stubs and shims (the plan rewrites those anyway); it is not asserted to be a production hazard. The process-substitution form (`curl ... --config - < <(printf ...)`) keeps curl as the only command whose status is observed and returned 0 in the same experiment. It is bash-only; the one `#!/bin/sh` script (`soleur-host-bootstrap.sh`) is in Tier 2.
- Rule D accepts the process-substitution form ONLY when the call sits inside `$(...)`; the bare form fails its destination-pin limb (see Reconciliation) and needs the Phase 1 lint fix. Rule D also accepts the unconverted argv form: it is orthogonal to this sweep, which is why Rule E exists.
- **Token-shape hazards (measured).** A token holding a newline plus `url = "..."` injects a second request even with no quote in it (env-sourced tokens included, so the guard is not limited to response-derived sites); a trailing CR is dropped by curl; `\n` inside a token truncates the header; `-v`/`--trace-ascii` print the header even from a stdin config; a process-substitution `printf` expands the token into a traced parent's `++ printf` line (the xtrace preamble stays the defense); `command printf` is still the builtin, only `env printf`, `/usr/bin/printf` and `exec printf` exec; no `/proc/*/cmdline` contained the token while a process-substitution `printf` was live; an unset token under `set -u` inside `< <(printf ...)` is swallowed by the subshell and curl runs headerless (the argv form aborted).
- Repo-wide lint run takes 5.4 s; `c4-count-parity` passes (2.7 s) before the change.

**Existing in-repo shapes / learnings applied.**
`scripts/lint-shell-trace-credential-refusal.py` (Rules A–D, `--changed` baseline bypass, `--census`, `--write-baseline*`); ADR-202; post-mortem `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`; ADR-263 (charset sanitisation before a curl config stream); ADR-198 (`-K -` stdin header for ingest tokens); `tests/scripts/test-sentry-alert-live-fidelity.sh` (PATH-shim curl recording argv NUL-delimited plus stdin: the model for the battery); `knowledge-base/project/learnings/bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md` (enumerate sweep work-lists by grep, never by intuition); `plugins/soleur/test/fixture-relative-assert.baseline.txt` (row-by-row equality baseline that must be regenerated when a script edit moves its counts); followthrough lints (`scripts/lint-followthrough-varq-ban.sh`, `scripts/followthrough-exec-bit.test.sh`) constrain what a probe edit may contain.

**Open Code-Review Overlap check (Phase 1.7.5).** 87 open `code-review` issues queried; none names any file in `## Files to Edit` / `## Files to Create`. Recorded as `None` below.

## Problem Statement

A command line is world-readable on Linux (`/proc/<pid>/cmdline` is mode 0444, and `ps` shows it) for
the life of the process, and `bash -x` prints it after expansion. #7797 printed two live API tokens
into an agent transcript that way. ADR-202 added a self-refusal preamble to every credential-binding
script, but xtrace does not cross `exec` or a child invocation: a traced **parent** calling
`./child.sh "$TOK"` prints the token while the child's own preamble sees a clean `$-`. For that shape
argv hygiene is the only defense, so the sweep closes a real residual of the #7797 vector and not
only procfs hygiene. #7797's original statement that the sweep "buys zero trace-vector protection"
was wrong; ADR-202 §Named residual holes records the correction.

Limit of the claim: the sweep removes the token from curl's argument list and from the `+ curl ...`
trace line. A sourced library (`_cf-admin-token.sh` and the `tests/scripts/lib/*-gate.sh` files)
runs in its caller's shell with no preamble of its own, so under a traced parent the builtin
`printf` that feeds curl still expands the token into a `+` line. For those five files the
conversion buys procfs hygiene and a smaller trace surface, not trace immunity; the caller's
preamble remains the trace defense. The `printf` must stay the shell builtin (never `command
printf`, `env printf` or `/usr/bin/printf`), because an exec'd printf would put the token back on
argv.

## Proposed Solution

Move every bearer header off curl's argument list onto curl's stdin config channel, in the same shape
the tree already uses at nine sites, with two refinements measured above (process substitution, charset guard).

**Canonical form A — one call site (bash).** The token reaches curl as bytes on stdin; the only argv
text is `--config -`. The token-shape guard (below) runs first in the same function or script:

```bash
# before
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" "$url")"
# after
code="$(curl --disable --noproxy '*' -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  --config - "$url" \
  < <(printf 'header = "Authorization: Bearer %s"\n' "${SENTRY_ACTIONS_RO_TOKEN}"))"
```

Rules for the form: the format string is always a literal with `%s`; `--disable` is the literal
first argument and `--noproxy '*'` is present (Rule D); the credential flag is removed from the
argument list, not merely supplemented; curl keeps its position as the only observed command (no
`printf | curl` pipeline, see the SIGPIPE measurement); `printf` is the shell builtin (never `env
printf`, `/usr/bin/printf` or `exec printf`); never a here-string or heredoc for the header (bash
before 5.1 writes those to a temp file); no `-v`, `--verbose`, `--trace*` or `-D -` on that call; no
body through stdin (`-d @-`, `--data-binary @-`, `-T -`, `--json @-`): use `--data-binary @file`.

**Canonical form B — a script with several calls.** One local wrapper owns the transport flags, the
token-shape guard and the header, so the property lives in one place per file and each call site
loses its `-H` line. The wrapper refuses before curl runs, so an unusable token never produces a
headerless request:

```bash
sentry_curl() {
  _bearer_ok "${SENTRY_AUTH_TOKEN:-}" || { echo "sentry_curl: token unusable" >&2; return 2; }
  curl --disable --noproxy '*' "$@" --config - \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN")
}
```

A header that travels with a second credential header in the same call (`apikey: <service-role key>`
beside `Authorization: Bearer <same key>`) moves into the same config stream as a second `header =`
line; leaving the `apikey:` header on argv would leave the identical secret on `ps`.

**Token-shape guard (every form, every site).** Measured: a newline in ANY token, env-sourced
included, injects a curl config directive, and an unset token under `set -u` inside the process
substitution yields a headerless request instead of an abort. So every converted call is preceded by
an allowlist check that also rejects empty, fail closed, never echoing the value:

```bash
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
```

`local LC_ALL=C` pins the ranges (locale-dependent ranges on older bash). Followthrough probes
(`lint-followthrough-varq-ban.sh` bans `: "${VAR:?}"`) replace their existing `-z` guard with the
sanctioned shape: `if ! _bearer_ok "$TOK"; then echo "TRANSIENT: token unusable" >&2; exit 2; fi`.
Response-derived tokens (`bsky-community.sh`, `bsky-setup.sh`, `linkedin-setup.sh`, and
`linkedin-community.sh` if applicable; provenance resolved in Phase 0) use the same guard; they are
the highest-risk members, not the only ones. Phase 0 records each wrapper's token source and its
actual character class so the allowlist is checked against real formats, never remembered ones.

**Canonical form D — text a script prints for a human to run.** `provision-cloudflare.sh`,
`provision-doppler.sh`, `trigger.sh`, `durable-reminder-prefer-inngest.sh` and
`registry-luks-recut-gate.sh` print or generate `curl -H "Authorization: Bearer ..."` command text.
That text is converted to the stdin form so a copy-paste does not reintroduce the argv exposure.
It is hand-converted and checked by an acceptance grep; Rule E scopes to executed curl commands and
does not parse printed text.

**Not converted (already safe).** `--header @-` / `-H @<(printf ...)` / `--config <(...)` / `-K -`
sites: `supabase-logs-query.sh`, `supabase-advisor-scan.sh`, `sentry-alert-live-fidelity.sh`,
`assert-byok-rules-exist.sh`, `postgrest-reload-schema.sh`, `audit-ruleset-bypass.sh`,
`cf-token-scope.sh`, `bin/snapshot-github-app.sh`, `rotate-supabase-db-credential.sh` (0600 config
file), `web2-rebirth.sh`, `resend-inbound-bootstrap.sh`, `web-probes-token-rotation-verify.sh`,
`rung2-rehearsal/seed-dirty-journal.sh`, the two bootstrap scripts under `knowledge-base/project/specs/`.
The conversion batteries do not touch them.

## Inventory (live, two derivations)

Derivation 1 (string grep): `git grep -l 'Authorization: Bearer' -- '*.sh'` minus `*.test.sh`,
`tests/`, `fixtures/` returns 79 files; the `-H "Authorization: Bearer` same-line subset is 59.
Derivation 2 (logical-command census, the one used): the executable procedure
`knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py`
joins backslash continuations, keeps commands whose argv carries a bearer header (`-H`/`--header`
not followed by `@`, not a curl-config `header` line), adds variable-held (`-H "$header_auth"`) and
array-held (`curl_args+=(-H ...)`, `_auth=(-H ...)`) headers, and includes the sourced production
gate libs `tests/scripts/lib/*-gate.sh`. Run once at plan time: `TOTAL sites=136 files=64`, of which
**53 files / 123 sites are in scope (Tier 1)** and 11 files / 13 sites are deferred (Tier 2). Every
count in this plan comes from that run (or the lint's own `--census`), not from a hand tally. The
Phase 0 task re-runs it at work time and diffs it against this list; a mismatch is resolved before
any conversion. It is a one-time measurement (the lint's own `--census` is the standing detector); no test depends on it.

**Tier 1 — converted in this PR (file, site count).**

scripts/followthroughs (20 files / 22 sites): `ac10-workspace-reconcile-sentry-4246.sh` (1), `ac8-founder-ambiguous-soak-5673.sh` (1), `accounted-beacon-live-6462.sh` (1), `anthropic-admin-key-6297.sh` (1), `autovacuum-thrash-6168.sh` (1), `betterstack-roundtrip-latency-7855.sh` (1), `community-monitor-checkin-soak-5728.sh` (1), `concurrency-slot-wal-backoff.sh` (1), `cron-machinery-soak-9272.sh` (2), `cwv-field-rum-9178.sh` (1), `dashboard-cold-tiers-8978.sh` (1), `l3-probe-armed-6438.sh` (1), `phase3-ga-soak-5274.sh` (1), `reconcile-ff-only-sentry-4977.sh` (1), `send-failed-alert-probe-8097.sh` (1), `sentry-checkins-3859.sh` (1), `sync-health-residual-5689.sh` (2), `web2-standby-soak-6459.sh` (1), `workspaces-luks-soak-6604.sh` (1), `zot-soak-6122.sh` (1).

scripts (8 files / 15 sites): `arm-checkpoint.sh` (1), `betterstack-ingest-probe.sh` (1), `check-cloudflare-token-drift.sh` (1), `cutover-inngest.sh` (5), `provision-plausible-goals.sh` (2, array-held), `registry-heartbeat-poll.sh` (1), `sentry-issue.sh` (2), `weekly-analytics.sh` (2).

apps/web-platform/scripts + supabase/scripts (8 files / 53 sites): `audit-sentry-extra-text-references.sh` (4), `configure-sentry-alerts.sh` (5), `dsar-export-oversize.sh` (5, plus 5 co-travelling `apikey:`), `seed-dev-users.sh` (6, variable-held), `seed-live-verify-user.sh` (14, variable-held), `seed-qa-user.sh` (11, variable-held), `sentry-monitors-audit.sh` (6), `../supabase/scripts/configure-auth.sh` (2).

apps/cla-evidence/scripts (2 / 7): `_cf-admin-token.sh` (2, sourced), `gdpr-override.sh` (5).

apps/web-platform/infra, not host-deployed (1 / 2): `arm-heartbeats.sh` (2, run by `apply-web-platform-infra.yml`; it has a 13-assertion owning test, so the changed transport is exercised before merge).

tests/scripts/lib production gates (4 / 5; the sourced libs run in the infra apply workflow's steps, so their owning tests are the pre-merge exercise): `git-data-birth-readiness-gate.sh` (2, array-held with a stub seam), `preapply-entrypoint-gate.sh` (1), `stock-preflight-gate.sh` (1), `registry-luks-recut-gate.sh` (1, printed command text, form D).

plugins and hooks (10 / 19): `plugins/soleur/scripts/audit-flag-flip.sh` (1 + `apikey:`), `skills/community/scripts/{bsky-community,bsky-setup,linkedin-community,linkedin-setup}.sh` (6), `skills/provision-cloudflare/scripts/provision-cloudflare.sh` (2, text + live), `skills/provision-doppler/scripts/provision-doppler.sh` (6, text + live), `skills/trigger-cron/scripts/trigger.sh` (2), `skills/user-set-role/scripts/set-role.sh` (1 + `apikey:`), `.claude/hooks/durable-reminder-prefer-inngest.sh` (1, generated command text).

**Tier 2 — deferred to the residue tracker #9597 (11 files / 13 sites).** Host-deployed (edit re-runs prod provisioners on merge, per #7898):
`apps/web-platform/infra/{container-restart-monitor,cron-egress-alarm,disk-monitor,resource-monitor,inngest-rearm-reminders,inngest-wiped-volume-verify,web-private-nic-guard}.sh` and `soleur-host-bootstrap.sh` (`#!/bin/sh`, so process substitution is unavailable: the form there is the pipe). Run live in the push-triggered infra apply or a path-triggered mirror workflow with no pre-merge exercise: `scripts/fresh-host-boot-trail.sh` (2), `scripts/verify-tunnel-ingress-origin.sh` (1), `zot-image-oci-archive.sh` (2). All are listed in Rule E's baseline with per-file site counts and the residue issue number.

**Tier 3 — also in the residue tracker:** `.github/workflows/*.yml` and composite actions (14 files, ~32 sites: `apply-web-platform-infra.yml` 8, `git-data-rung2-rehearsal.yml` 4, `scheduled-terraform-drift.yml` 3, others 1-2, `mint-infra-app-token/action.yml` 2), `cloud-init-*.yml`, and non-Bearer argv credentials (`-u user:token` in `web-zot-consumer-probe.sh` / `zot-entry-gate.sh`, OAuth1 `Authorization:` in `x-community.sh` / `x-setup.sh`, standalone `apikey:` in `seed-qa-user.sh:175` which carries only the anon key).

Measured conflicts to check at work time (all zero at plan time): a Tier 1 site that also uses curl's stdin for a body (`-d @-`, `--data-binary @-`, `-T -`, `--json @-`): 0 of 136; a site that already passes `-K`/`--config`: 0; `-u` sites among Tier 1: 0.

## Implementation Phases

Ordering (CTO, plan-review, deepen-plan): the detector lands BEFORE the conversions with a baseline
listing every current offender, so every intermediate commit is green and each conversion flips
exactly one row and deletes exactly one baseline line. Within a batch, commit (a) compliance
prerequisites (xtrace refusal, Rule D flags, destination pin), then (b) the conversion. Pilot files
(Phase 1.5) are converted there and struck from their group's phase list.

### Phase 0 — Freeze and measure (no code)

- 0.1 Re-run `census-argv-bearer.py` (a throwaway planning measurement; it prints `TOTAL` on stderr, so never `tail -n +2` its stdout) and the acceptance grep; expect `TOTAL sites=136 files=64`, Tier 1 = 53 files / 123 sites, Tier 2 = 11 files / 13 sites.
- 0.2 Lint the 19 baselined Tier 1 files by explicit path (baseline-bypassing) and record, per file, which of A/B/C/D fire, whether the prerequisite is behaviour-changing (a destination pin or a new refusal exit path), and whether the script already has a pre-call token guard. Plan-time result: 13 fail, 6 only need their baseline line deleted.
- 0.3 Record, per Tier 1 script, token provenance (env / Doppler / response-derived), the token's actual character class, and whether `--disable` / `--noproxy '*'` are already present (plugin scripts run on users' machines: a forced `--noproxy '*'` ignores a user's `HTTPS_PROXY`; either keep the requirement and state the behaviour change in the PR body and ADR addendum, or exempt plugin-shipped scripts from `--noproxy` and keep `--disable`; the work phase picks and records one, Rule D already scopes plugin scripts in).
- 0.4 Grep every Tier 1 curl for `-v`, `--verbose`, `--trace`, `--trace-ascii`, `--trace-config`, `-D -`, `--dump-header`, and for stdin bodies; expected zero for bodies (measured), record any verbosity hit.
- 0.5 Settle the Tier split before baseline E exists: confirm by grep that no Tier 1 file is in `file(`/`filesha256(`/`triggers_replace`/`host_script_files`/Dockerfile COPY, and that none is run live by the apply workflow without its own pre-merge test.

### Phase 1 — Lint first: Rule D fix, Rule E, wrapper awareness, battery, pilot

- 1.1 Rule D destination-pin fix: `_destination_vars` skips tokens that follow a redirection operator (`<`, `<<<`, `>`, `>>`, `2>`) and masks `<(...)` / `>(...)` spans like `$(...)`. Fixture first: `compliant-stdin-bearer-procsub-bare.sh` (bare curl outside `$(...)`, env-read token) must exit 0 under Rule D; it exits 1 today.
- 1.2 Wrapper awareness for Rules D and E, as a design not a one-liner: collect wrapper names file-wide first (a function whose body invokes curl, plus the transitive closure to a fixpoint, so a wrapper defined after its use or `sb_get() { sb_curl ...; }` counts); match the name in command position (line start, after `|`, `;`, `&&`, `||`, `(`, `$(`, backtick, `!`); build the logical command for a call site by splicing the wrapper's curl line with `"$@"` replaced by the call's arguments (reusing the `_inline_arrays` positional approach); Rule D flag/credential checks run on the spliced command, the pin check and Rule E's argv check run on the call-site arguments. Documented blind spots (named in Rule E's header comment): wrappers defined in a sourced lib, and a header passed positionally (`-H "$2"`). Before committing, run `--census` before and after this change and fix or baseline every NEW Rule D offender in the same commit; "Phase 1 state" for later deletion-only checks means the baselines as regenerated at the end of Phase 1.
- 1.3 Write the Guard 1 fixtures and test rows first (matrix below), then `check_rule_e()` called from `check_file()`, plus the `main()` plumbing: the `"e"` entry in `baselines_by_rule`, `load_baseline_e`, `--write-baseline-e`, an `offenders_e` census line and a `--- rule E ---` list, `OK:` output naming Rule E. Rule E has its own scope function (`excluded_for_rule_d` without its exec-bit carve-out, so all four production gate libs are in scope), runs on each logical command's invocation segment (not the whole assembly, which would flag the safe `printf 'Authorization: ...' | curl -H @-`), and resolves variable-held headers file-wide (`name=...Bearer...` then `-H "$name"`). Baseline E is `path<TAB>site count`; the repo-wide run fails when a baselined file's live count differs (equality, not suppression by file) and when a listed file no longer offends. The standalone 5.4 s run, `--census` and the suite therefore agree.
- 1.4 Generate baseline E from the unconverted tree, then diff Rule E's offender set against the census (minus the printed-text emitters) and resolve every difference before committing. Header cites #9597 and the shrink-only contract.
- 1.5 Write `tests/scripts/test-argv-bearer-sweep.sh` (Files to Create, Guard 2) and register it: explicit `run_suite` line in `scripts/test-all.sh`, `python3 scripts/regenerate-shard-manifest.py --incremental --write`, a classification in `scripts/lib/test-affected-paths.sh`, an `EXPECTED_TESTS` floor and a `_report` self-test, one `TMPD` root with one EXIT trap before `source test-helpers.sh`. The orphan linter keys on `*.test.sh` and does not see `tests/scripts/test-*.sh`, so registration is proven by `grep -c 'tests/scripts/test-argv-bearer-sweep.sh' scripts/test-all.sh` equal to 1 plus the label appearing in a `test-all.sh` run log. Expectations are keyed off baseline E: a script still listed there asserts "argv bearer present (known, unconverted)"; once removed it asserts the full contract. Every commit is therefore green, and the one-time RED-versus-GREEN evidence for the PR body is the same rows flipping.
- 1.6 Pilot, proving every form end to end: `scripts/arm-checkpoint.sh` (form A), `apps/web-platform/scripts/configure-sentry-alerts.sh` (form B), `scripts/provision-plausible-goals.sh` (array-held, A/B/C- and D-baselined). Prove: battery rows flipped, owning test green, lint green, baseline E regenerated with deletions only.

### Phase 2 — scripts/followthroughs (20 files)

- 2.1 Prerequisites for the four baselined probes (`autovacuum-thrash-6168`, `concurrency-slot-wal-backoff`, `l3-probe-armed-6438`, `web2-standby-soak-6459`); each prerequisite commit re-runs the battery's 401 row.
- 2.2 Convert each probe to form A with the token-shape guard replacing the existing `-z` guard (curl invocation and guard only; keep `2>/dev/null` and the `-w` status capture where they are; `lint-followthrough-varq-ban.sh` compliant).
- 2.3 Gates: battery rows, `bash -n`, `lint-followthrough-varq-ban.sh`, `followthrough-exec-bit.test.sh`, `sweep-followthroughs.test.sh`, probe-owned tests (`anthropic-admin-key-6297`, `cwv-field-rum-9178`, `send-failed-alert-probe-8097`, `betterstack-roundtrip-latency-7855` via `tests/scripts/test-betterstack-roundtrip-latency.sh`); regenerate baseline E.

### Phase 3 — scripts/*.sh (6 files after the pilots)

- 3.1 Prerequisites: `check-cloudflare-token-drift.sh`, `weekly-analytics.sh`.
- 3.2 Convert `betterstack-ingest-probe.sh` (update its stub in `tests/scripts/test-betterstack-ingest-probe.sh`, which asserts the Bearer text in argv), `check-cloudflare-token-drift.sh` (called from the `cf-tunnel-ssh-bridge` composite action and `reusable-release.yml`: extend `scripts/check-cloudflare-token-drift.test.sh` to assert the token on stdin and absent from argv), `registry-heartbeat-poll.sh`, `sentry-issue.sh`, `weekly-analytics.sh`; `cutover-inngest.sh` (5 sites, 3000+ lines, form B wrapper) in its own commit with `apps/web-platform/infra/cutover-inngest-workflow.test.sh` and `inngest-cutover-flip.test.sh`.

### Phase 4 — apps/web-platform/scripts and supabase/scripts (7 files after the pilot)

- 4.1 Prerequisites: `dsar-export-oversize.sh`, `configure-auth.sh`, and baseline-line deletion for the six files that already pass.
- 4.2 Convert with form B wrappers. The three `seed-*` scripts replace the `header_auth`/`header_api`/`header_json` plumbing with one `sb_curl` wrapper emitting both `Authorization: Bearer` and `apikey:` lines (the standalone anon-key `apikey:` call at `seed-qa-user.sh:175` stays on argv: it is not a secret bearer and Rule E must not flag it); `seed-live-verify-user.test.sh` is the pre-existing oracle. `dsar-export-oversize.sh` moves its five `apikey:` headers with the bearer. `sentry-monitors-audit.sh` runs in the release path and is exercised by `sentry-audit-gate.yml` on the PR itself.
- Merge of `apps/web-platform/**` triggers a production release (`web-platform-release.yml`); the PR body says so.

### Phase 5 — cla-evidence, non-host infra, production gate libs

- 5.1 Prerequisites: `gdpr-override.sh`, `arm-heartbeats.sh`, `preapply-entrypoint-gate.sh`.
- 5.2 Convert `_cf-admin-token.sh` (sourced by `bootstrap.sh` and `gdpr-override.sh`; its test stub never asserts the header today, so extend `_cf-admin-token.test.sh` to), `gdpr-override.sh`, `arm-heartbeats.sh` (13-assertion `arm-heartbeats.test.sh`; its fake curl returns 401 unless `Authorization: Bearer` is in argv, so rewrite it to read stdin), and the four gate libs with `tests/scripts/test-preapply-entrypoint-gate.sh`, `tests/scripts/test-stock-preflight-gate.sh` (T27 asserts a literal curl command in the lib's header text; text and assertion move together), `tests/scripts/test-git-data-birth-readiness-gate.sh` (the `SOLEUR_RUNG2_STUB_BEARER` seam keeps its meaning; only the header source changes).

### Phase 6 — plugins and hooks (10 files)

- 6.1 Convert. Token-shape guard everywhere; form D for printed command text; bash-only constructs already used by each file (plugin users may run bash 3.2: no here-strings for the header, `local LC_ALL=C` in the guard). Owning tests: `plugins/soleur/test/audit-flag-flip.test.sh`, `operator-ack-guard.test.sh`, `cf-token-scope.test.sh`, `.claude/hooks/durable-reminder-prefer-inngest.test.sh`, `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`, `trigger-cron-allowlist-parity.test.ts`.
- Merge of `plugins/soleur/**` triggers a production release and these scripts are vendored into the image and run on the host runtime (ADR-080); the PR body says so.

### Phase 7 — Final baselines, ADR addendum, rebase, verification

- 7.1 Regenerate `lint-shell-trace-credential-refusal.baseline.txt` and `...-d.baseline.txt` with `--write-baseline` / `--write-baseline-d` (full tree, never scoped); diff is deletions only versus their end-of-Phase-1 state; baseline E ends as the Tier 2 set.
- 7.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate its baseline in the same commit only if counts moved.
- 7.3 ADR-202 dated addendum (short, see Architecture Decision); raise `MIN_ASSERTIONS` in `lint-shell-trace-credential-refusal.test.sh` to the measured count.
- 7.4 Rebase on a freshly fetched `origin/main` immediately before ship; re-run the census and Rule E, convert or Tier-2-list any argv bearer a concurrent PR added, and regenerate baseline E mechanically (`--write-baseline-e`, never a hand merge).
- 7.5 Full gate: repo-wide lint, `--changed`, battery, every owning test, `c4-count-parity`, markdownlint on the plan/ADR.
- 7.6 PR body: first line states that merge triggers a production release (`apps/web-platform/**`, `plugins/soleur/**`) and a push-triggered infra apply (zero Terraform resource delta; `arm-heartbeats.sh` runs live in it); `Ref #7797`; `Closes #7843` with the remaining scope stated as moved to #9597; Tier 2/3 list. No criterion depends on a post-merge sweeper run.

## Files to Edit

Tier 1 conversions: every path in the Tier 1 list above (53 files).
Registration: `scripts/test-all.sh` (explicit `run_suite` line for the new battery; the repo-wide lint suite `scripts/lint-shell-trace-credential-refusal-repo` already exists at line 4213 and needs no change), `scripts/suite-shard-legs.tsv` (via `regenerate-shard-manifest.py --incremental --write`), `scripts/lib/test-affected-paths.sh` (classification of the new suite).
Lint and baselines: `scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-trace-credential-refusal.test.sh`, `scripts/lint-shell-trace-credential-refusal.baseline.txt`, `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`.
Owning tests to update where a stub inspects argv for the header (the set is what the Phase 1.5 battery run shows red, and at least): `tests/scripts/test-betterstack-ingest-probe.sh`, `tests/scripts/test-betterstack-roundtrip-latency.sh`, `tests/scripts/test-stock-preflight-gate.sh`, `apps/web-platform/infra/arm-heartbeats.test.sh`, `apps/cla-evidence/scripts/gdpr-override.test.sh`, `plugins/soleur/test/audit-flag-flip.test.sh`, `plugins/soleur/test/cf-token-scope.test.sh`, `.claude/hooks/durable-reminder-prefer-inngest.test.sh`, `apps/web-platform/scripts/seed-live-verify-user.test.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `apps/web-platform/infra/inngest-cutover-flip.test.sh`, `apps/cla-evidence/scripts/_cf-admin-token.test.sh` (its stub never asserts the header today), `scripts/check-cloudflare-token-drift.test.sh`, `tests/scripts/test-preapply-entrypoint-gate.sh`, `tests/scripts/test-git-data-birth-readiness-gate.sh`, `plugins/soleur/test/operator-ack-guard.test.sh`, `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`, `plugins/soleur/test/trigger-cron-allowlist-parity.test.ts`.
Generated-baseline file that may move: `plugins/soleur/test/fixture-relative-assert.baseline.txt`.
ADR: `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md`.

## Files to Create

- `tests/scripts/test-argv-bearer-sweep.sh` (manifest-driven shim battery; Guard 2)
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` (Rule E baseline: the 11 Tier 2 files with per-file site counts)
- `scripts/fixtures/shell-trace-refusal/violation-argv-bearer-literal.sh`, `violation-argv-bearer-second-member.sh`, `violation-argv-bearer-variable-held.sh`, `violation-argv-bearer-array-held.sh`, `violation-argv-bearer-long-form.sh`, `violation-argv-bearer-wrapper.sh`, `violation-argv-bearer-config-hazards.sh`, `violation-ruled-wrapper-env-url.sh` (Rule D wrapper case), `compliant-stdin-bearer-procsub.sh`, `compliant-stdin-bearer-procsub-bare.sh`, `compliant-stdin-bearer-wrapper.sh`, `compliant-stdin-bearer-header-at-stdin.sh`, `compliant-all-safe-forms.sh` (Rule E fixtures; synthesized tokens only, per `cq-test-fixtures-synthesized-only`)
- `knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py` (the executable inventory procedure; already written at plan time) and `decision-challenges.md` (the single-PR vs split User-Challenge)
- `knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/tasks.md` (Save Tasks step)

## Open Code-Review Overlap

None. 87 open `code-review` issues were queried (`gh issue list --label code-review --state open --json number,title,body`) and matched with `jq --arg path` against every file in the Tier 1 list plus the lint, its test and `cutover-verify.sh`: zero matches.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-202 with a short dated addendum (about 10 lines; no new ordinal, so no collision exposure) in this PR: (1) the argv correction recorded in §Named residual holes is now implemented for Tier 1 and ratcheted by Rule E, (2) sourced libraries get procfs hygiene but not trace immunity, (3) Tier 2/3 are deferred to #9597, (4) named residual: `scripts/sweep-followthroughs.sh` builds `env -i NAME=<secret> <probe>` for every probe, so each forwarded secret is on `env`'s argv in the sweeper-to-probe hop (the sweeper has its own unconditional xtrace refusal, so this is a procfs-window residual, not a trace one) and converting the probes does not remove it, (5) the plugin-script proxy/`~/.curlrc` behaviour change if kept. Canonical forms A-D, the SIGPIPE measurement and the config-injection finding live in Rule E's header comment in the lint, not in the ADR. Reason it is a deliverable of this plan: plan Phase 2.10 (an extension of an accepted ADR's enforcement belongs to the plan that creates it).

### C4 views

No C4 impact. Checked against `model.c4`, `views.c4` and `spec.c4` by enumerating: external human actors (none added; the operators and CI that run these scripts are already modeled), external systems touched by the converted calls (Sentry 24 mentions, Better Stack 21, Supabase 20, Hetzner 42, Cloudflare 22, Resend 12, Doppler 35, Plausible 3: all modeled; LinkedIn, Bluesky and X are community-plugin integrations on users' machines and are not modeled before or after), data stores (none touched), actor-to-surface access relationships (unchanged: this changes how a header is transported on existing edges, and `model.c4` already documents "Bearer-on-stdin transport per supabase-logs-query.sh" on the `github -> supabase` edge). `plugins/soleur/test/c4-count-parity.test.sh` passes before the change (re-run in Phase 7).

### Sequencing

Single PR; the ADR addendum describes the shipped state.

## User-Brand Impact

- **If this lands broken, the user experiences:** a converted operational script silently sends no credential (or the wrong one) and its soak probe or gate reports a healthy result: a follow-through tracker is auto-closed while the underlying signal is unverified, or a DSAR/GDPR tooling run fails closed with an auth error instead of completing. No end-user-facing page changes.
- **If this leaks, the user's data is exposed via:** the argv/process-table vector this sweep removes (`/proc/<pid>/cmdline`, a traced parent's `+ curl` line) carrying Supabase service-role keys, Sentry/Better Stack/Hetzner/Cloudflare/Doppler tokens; the conversion introduces no new file or log sink for the token (stdin only) and one new injection surface (token content into curl config) closed by the charset guard.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the sweep reduces an existing exposure and no single script's failure leaks user data, but a repeated silent-auth-break pattern across the probe fleet would erode trust in the soak/gate machinery, so it is not `none`; it is not `single-user incident` because every failure mode is fail-closed or detected by the battery before merge.

Artifact/vector pairs for review: (1) probe false-green after a broken header, via a swallowed 401 -> battery negative-path rows; (2) token visible in argv after a partial conversion -> Rule E + battery row (ii); (3) config injection from a response-derived token -> form C guard + battery fixture with a newline/quote token.

## Observability

```yaml
liveness_signal:
  what: "the required-context suite 'scripts/lint-shell-trace-credential-refusal-repo' (Rule E, repo-wide) and 'tests/scripts/argv-bearer-sweep' (the battery), both run by scripts/test-all.sh; the advisory --changed step at ci.yml:231 flags touched baselined scripts"
  cadence: "every pull request and every merge-queue run"
  alert_target: "PR check status: the test context is required, the --changed step (lint-bot-statuses job) is advisory"
  configured_in: "scripts/test-all.sh, .github/workflows/ci.yml, scripts/lint-shell-trace-credential-refusal.py (Rule E), tests/scripts/test-argv-bearer-sweep.sh"
error_reporting:
  destination: "GitHub Actions job log (stderr of the lint and the battery) and check annotations"
  fail_loud: "lint exits 1 with '<file>:<line>: bearer token on curl argv'; the battery prints the failing manifest row and exits non-zero"
failure_modes:
  - mode: "a converted script stops sending its credential and a probe reads the 401 as healthy"
    detection: "battery rows (ii)(iii) for every probe and form C site, three negative rows (401 must not reach PASS), unset-token row"
    alert_route: "required test context red on the PR"
  - mode: "an argv bearer is reintroduced in a tracked script outside baseline E"
    detection: "Rule E in the repo-wide run (blocking); baseline E must equal the live offender set exactly"
    alert_route: "required test context red; merge queue ejects"
  - mode: "a response-derived token with a newline or quote injects a curl config directive"
    detection: "battery fixture token containing a quote and newline must be refused by the form C allowlist guard (non-zero exit, zero curl calls recorded)"
    alert_route: "required test context red"
logs:
  where: "GitHub Actions run logs for ci.yml"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py
  expected_output: "OK:"
```

## Guard Contract

### Guard 1 — Rule E: argv-bearer ratchet

**Property.** No executed curl command in a tracked, non-test shell script carries a bearer token in its own argument list, and baseline E equals the live offender set (path and site count) exactly.

**Assembly.** The chokepoint is `_curl_commands()` in `scripts/lint-shell-trace-credential-refusal.py` feeding a new `check_rule_e()` called from `check_file()` and registered in `main()`'s rule-to-baseline map; Rule E runs on EVERY logical command's invocation segment (never only the first, never the whole pipeline assembly). Members the property quantifies over: the short `-H` and long `--header` flags, with or without a space (`-H"..."`), double- or single-quoted, any case of `Authorization:`/`Bearer`; a header held in a variable (`h="Authorization: Bearer $T"`, `-H "$h"`, resolved file-wide); a header held in an array (`curl_args+=(-H ...)`, `_auth=(-H ...)`); a header placed after the URL; a file-local wrapper (the wrapper's own curl line AND its call sites, with the transitive and defined-after cases); a second credential header (`apikey:` carrying the same key) in the same call; and the config-stdin call's own hazards: `-v`/`--verbose`/`--trace*`/`-D -` on a bearer-bearing call, a stdin body (`@-`, `-T -`, `--json @-`) in a `--config -` call, and a here-string or heredoc feeding the header. Safe forms (`-H @-`, `--header @<(...)`, `--config -`, `-K -`, `--config <(...)`, a standalone anon-key `apikey:`) are not flagged, and a bearer inside a trailing comment is not scored. Scope: Rule E's own scope function (`excluded_for_rule_d` minus the exec-bit carve-out, so the four production gate libs are in scope); printed command text and YAML are out of scope (acceptance grep covers the former, #9597 the latter). Baseline E is bypassed by `--changed` and by explicit paths.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `compliant-stdin-bearer-procsub.sh` with the `--config -` call replaced by `-H "Authorization: Bearer ${TOK}"` | RED with exactly one Rule E message (the suite counts Rule E messages per fixture, never rc alone) |
| 2 | Delete the `check_rule_e` assignment in `check_file()` (anchored on its own line, scoped to that function) or remove the Rule E fixture loop | RED: a floor on executed Rule E fixtures plus `--census` `offenders_e` equal to baseline E's length make a dead dispatch read RED, never "0 checked" |
| 3 | `violation-argv-bearer-second-member.sh`: a compliant stdin call then a second call with a literal bearer | RED, one message |
| 4 | `violation-argv-bearer-variable-held.sh`; `violation-argv-bearer-array-held.sh`; `violation-argv-bearer-long-form.sh` (`--header 'authorization: bearer ...'`, no space `-H"..."`, header after the URL) | RED each, one message each |
| 5 | `violation-argv-bearer-wrapper.sh`: wrapper defined AFTER its call site, a transitive wrapper, and a call after `||` and inside `$(...)` | RED each |
| 6 | `violation-argv-bearer-config-hazards.sh`: `-v` on a `--config -` call; `-d @-` on a `--config -` call; header fed by `<<<` | RED each |
| 7 | Rule D: `violation-ruled-wrapper-env-url.sh`: a wrapper called with an env-settable `"$URL"` never pinned (starts from `compliant-ruled-pinned-destination.sh`, so only Rule D can fire) | RED from Rule D |
| 8 | Sandbox repo (`sbx_repo_run`: a mini repo with a perl-mutated copy of the lint, its baselines, `git init && git add`): drop the `"e"` entry from `baselines_by_rule` | RED: an E-only offender listed in baseline E reports instead of falling back to the A/B/C list |
| 9 | Sandbox repo: list a clean file in baseline E; remove a still-violating file from it; change a listed file's site count | RED each (equality on path and count); and an explicit path to a baselined file reports (bypass) while the repo-wide run does not |
| 10 | Harness: any mutant run whose stderr contains `Traceback` or `SyntaxError` is an instrument error (a Python syntax error exits 1 and would otherwise read as RED); `mutate_row` gains a Rule-E-message-count assertion and an anchored, function-scoped perl expression | the instrument self-test fails if a no-op mutation reads RED |
| 11 | Harness must-PASS (not the canonical): `compliant-stdin-bearer-header-at-stdin.sh`, `compliant-stdin-bearer-wrapper.sh`, `compliant-all-safe-forms.sh` (`--header @<(...)`, `-K -`, `--config <(...)`), a bearer in a trailing comment, the standalone anon-key `apikey:` call, and `compliant-stdin-bearer-procsub-bare.sh` (also asserts Rule D rc 0) | GREEN (rc 0, zero Rule E messages) |

**Anchor.** The stored value is baseline E (path and count). The lint itself, in full-tree mode, fails when a listed file no longer offends or its count differs, and reports any offender not listed, so a weakening needs the file edited in the same diff as the code it excuses; its header ties every entry to #9597; the required `test` context runs both the standalone repo-wide run and the suite.

### Guard 2 — Conversion battery (`tests/scripts/test-argv-bearer-sweep.sh`)

**Property.** For every followthrough probe that holds a credentialed curl and every form-A/B/C site the suite lists, a run that reaches the call records the bearer on curl's stdin and never in curl's argument list, an unusable credential produces zero calls and never the script's PASS outcome, and a stripped or rejected credential produces the script's TRANSIENT/FAIL status, never PASS.

**Assembly.** The chokepoint is the PATH-shim `curl` that every row runs the script under (`env -i PATH=<shim>:<symlink dir> HOME TMPDIR`, with fail-closed `gh`/`doppler`/`ssh` stubs and zero unexpected calls asserted). It records each call to its own `calls/<n>.argv` and `calls/<n>.stdin`, models real curl (reads stdin only for `--config -`/`-K -`; arity table for flags with values; honours `-o`, `-D`, `-w` including real-newline and `\n` forms, `-s/-S`; exit 22 on >= 400 with `-f`/`--fail`/`--fail-with-body`; exit 99 `UNMODELLED FLAG` for anything outside the table), parses stdin against `^header = "[^"\\]*"$` and records INJECTED otherwise, and is auth-gated (200 and a canned body only when `Authorization: Bearer <fixture>` is seen on stdin or argv, otherwise 401). Assertions quantify over every call to the manifest's `hosts` with a `min_calls` floor, not over calls that "carry a credential". Population: the followthrough probes that contain a credentialed curl, derived at test time (not a hard-coded 20) and reduced to those hermetically reachable (about 13 of 17 simple probes; `anthropic-admin-key`, `cwv-field-rum`, `send-failed-alert` and `betterstack-roundtrip` are covered through their owning tests, extended in place; the two probes that write fixed `/tmp` paths and `phase3-ga-soak-5274`, which exits before any curl on a placeholder, are `static-only` with a justification and a row that goes RED when the placeholder is pinned); plus the form C sites. Three instrument controls run first and abort the suite with FATAL otherwise: a canonical-compliant synthetic probe must be GREEN, an argv-bearer synthetic probe must be RED on check (ii), and the real-curl oracle (`curl --libcurl` against `http://127.0.0.1:9/`, no server needed) must show exactly one `Authorization` header append for forms A, B and C and a second `CURLOPT_URL` for the hostile token. Coverage of the rest of Tier 1 is delegated, by decision, to Rule E (static) and each script's owning test (extended in place), not re-modelled here.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert one converted probe to `-H "Authorization: Bearer ${TOK}"` | RED on check (ii) specifically (token in recorded argv), not on "no calls" |
| 2 | Make a covered script exit before its curl (the guard's own dispatch) | RED: below `min_calls` fails the row; the recorded failing check is the call-count check |
| 3 | A script with two curls, the first converted and the second left on argv; run in a 200 `{"data":[]}` mode so the second call is reached | RED (assertion covers every call to the hosts) |
| 4 | Harness: shim stops recording stdin; shim stops being auth-gated | RED for every row |
| 5 | Harness must-PASS (not the canonical): a script using `-H @-` fed by `printf`; one using a wrapper; a realistic JWT-shaped token in the allowed charset that must reach the next call with the Bearer on stdin | GREEN |
| 6 | Negative paths: header stripped by a mutated probe copy, and shim 401, for a Sentry, a Better Stack and a Supabase probe | exact per-probe TRANSIENT/FAIL rc (2 or 3 per its contract) AND a `TRANSIENT` marker on stderr (reusing `BASH_ERR_RE`/`_guard_out`), never PASS |
| 7 | Token-shape: a quote+newline token, a newline-only env-sourced token, an empty token, an unset token (run for ALL covered probes), a non-ASCII byte (`é`), and a malformed config line | zero calls (form C sites: exactly the login call and none after it), no INJECTED, the token absent from stderr, TRANSIENT rc |
| 8 | Pipe-form mutant: a copy of one converted probe rewritten to `printf \| curl`, with a 100,000-byte token and a shim that never reads stdin, under `set -o pipefail` | the converted probe rc 0; the mutant rc 141 (a 100 KB token is the smallest size at which the pipe form fails reliably; small tokens never discriminate) |
| 9 | xtrace: `SHELLOPTS=xtrace` and `bash -x` with the token only in env | the probe refuses (rc 78) with zero calls and no token on stderr |

**Anchor.** Nothing stored can be weakened silently: the population is derived from the followthrough directory at test time, and each manifest entry must exist and each probe containing a `--config -` call must be in the manifest or in a recorded `static-only` exclusion with a reason.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "sweep the remaining argv bearer tokens (`-H "Authorization: Bearer ..."` on curl argv) in tracked shell scripts to `curl --config -` with the header on stdin" [brief] | Phases 1-6, Canonical forms A-D, Files to Edit | mapped (Tier 1); Tier 2/3 descoped — justification: host-deployed edits re-run prod provisioners on merge (#7898), YAML is outside the lint's reach; both tracked in the residue issue |
| 2 | "so `bash -x` / `ps` / /proc/<pid>/cmdline cannot render them" [brief] | Property P1, battery rows (ii)(iii), Rule E | mapped |
| 3 | "Read `gh issue view 7843` for the scoped inventory (61 scripts / 108 sites)" [brief] | Research Reconciliation, Inventory, Phase 0.1 | mapped (inventory re-derived; 64 files / 136 sites) |
| 4 | "existing in-repo patterns (e.g. apps/web-platform/infra/cutover-verify.sh, apps/web-platform/infra/inngest-boot-emitter.sh, scripts/fixtures/shell-trace-refusal/)" [brief] | Canonical forms (derived from the in-repo shapes), Rule E fixtures | mapped (`inngest-boot-emitter.sh` does not exist; recorded in reconciliation) |
| 5 | "use `Ref #7797`, not Closes — it stays open as the incident record" [brief] | Phase 7.6 | mapped |
| 6 | "Do not touch or print any token values" [brief] | Test Scenarios (synthesized fixtures only; no step runs a probe with a real credential) | mapped |
| 7 | "keep each script's xtrace self-refusal and the commit-time lint (scripts/lint-shell-trace-credential-refusal.py) green" [brief] | Phases 2-6 step (a), Property P2 | mapped |
| 8 | "shrink its baseline as sites are converted" [brief] | Phase 1.3-1.4 (baseline E), per-phase regeneration, Phase 7.1 | mapped |
| 9 | "re-derive the live inventory yourself (git grep, two ways)" [brief] | Inventory, Phase 0.1 | mapped |
| 10 | "any PR that edits one of the 61 listed callers must convert that caller" [issue #7843] | Rule E (`--changed` bypass) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Canonical forms A, B | "sweep ... to `curl --config -` with the header on stdin" | asked |
| Canonical form D (printed command text) | — | inferred — justification: a copied printed command reintroduces the argv exposure for whoever runs it; hand-converted, outside Rule E |
| Token-shape guard at every site | — | inferred — justification: measured config injection (a newline plus `url =` made curl issue a second request, env-sourced tokens included) and measured headerless fail-open for an unset token; without it the new stdin channel adds failure modes the argv form did not have |
| Process substitution instead of `printf \| curl` | — | inferred — justification: measured SIGPIPE 141 under `set -o pipefail` with a non-reading consumer would turn the sweep into intermittent failures in every scripted stub |
| Tier 2/3 deferral (11 files) | — | inferred — justification: #7898 records that editing the host-hashed scripts re-runs prod provisioners on merge, and three more run live in the push-triggered infra apply with no pre-merge exercise; a sweep PR must not take a deployment window it did not plan for |
| Phase 0 battery (Guard 2), scoped to the 20 probes and form C sites | "Do not touch or print any token values" | inferred — justification: follow-through probes auto-close trackers on a healthy-looking result, so a silently broken header is a false-green; the shim proves delivery without a real token; scoped narrowly because Rule E and the owning tests cover the rest |
| Rule E + baseline E, Rule D wrapper/redirect fixes | "shrink its baseline as sites are converted" | asked (Rule E); the Rule D fixes are inferred — justification: the converted forms fail or evade Rule D without them (measured) |
| ADR-202 addendum | — | inferred — justification: plan Phase 2.10; the plan extends an accepted ADR's enforcement and ADR-202 records the argv residual this sweep closes |
| Residue tracker #9597 | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; Tier 2/3 deferrals without an issue are invisible (filed at plan time) |

### Split Assessment

- Subsystems touched: 7 — `apps/cla-evidence`, `apps/web-platform`, `plugins/soleur`, `.claude`, `scripts`, `tests`, `knowledge-base`
- Planned files: ~95 (53 scripts, ~17 owning tests, lint + 4 baselines + ~14 fixtures + new suite, ADR, plan/tasks) | Estimated changed lines: ~2,000
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split. Three plan reviewers and the CTO recommended splitting; the thresholds are all exceeded. Proposed boundary: (a) Phases 0-3 (battery, Rule E + baseline, `scripts/**`, followthroughs) and (b) Phases 4-6 (`apps/**`, `plugins/**`, hooks, gate libs) + Phase 7. **Decision: single PR with the phase-ordered commits above, split boundary (a)/(b) kept as the pre-agreed fallback** — justification: the pipeline produces one PR per invocation; the edits are uniform and mechanical; and, with Rule E and baseline E landing first (Phase 1), each phase shrinks the baseline, so "one PR rewrites the baseline twice" no longer applies and a later split costs nothing structural. Recorded as a User-Challenge in `knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/decision-challenges.md` for the operator.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py` was re-run at work time before Phase 1 and matched `TOTAL sites=136 files=64`; after Phase 6 the same command lists exactly the Tier 2 set (11 files, 13 sites). After Phase 1 the lint's `--census` is the standing detector and takes precedence over the grep below.
- [ ] `git grep -nE -- '(-H|--header)[[:space:]]+\\?["'"'"']?Authorization:[[:space:]]*Bearer' -- '*.sh' ':!*.test.sh' ':!tests/**' ':!**/fixtures/**' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u` returned 58 files at plan time (all in Tier 1 or Tier 2; comment lines excluded, which is why it reads 58 against the 59 of the unfiltered grep) and returns only Tier 2 files after Phase 6. It cannot see variable-held or array-held headers; the census can.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` exits 0 and prints `OK:`; `--changed --base origin/main` exits 0 with every touched file un-baselined.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py --census` shows `offenders_e` equal to baseline E's line count (the Tier 2 set), with per-file site counts equal; `offenders` and `offenders_d` are strictly smaller than their end-of-Phase-1 values (50/24 at plan time before the Rule D fix and wrapper awareness re-measure them).
- [ ] The A/B/C, D and E baseline diffs contain deletions only versus their end-of-Phase-1 state (`git diff -U0 <phase-1-commit> -- scripts/lint-shell-trace-credential-refusal*.baseline.txt | grep '^+[^+]'` prints nothing); no Tier 1 file remains in any baseline.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0; the three instrument controls pass; every dynamic row flipped from its known-unconverted expectation to the full contract as its script converted (evidence recorded in the PR body); `grep -c 'tests/scripts/test-argv-bearer-sweep.sh' scripts/test-all.sh` is 1 and the label appears in a `test-all.sh` run log; the shard manifest and affected-paths classification are updated.
- [ ] `bash scripts/lint-shell-trace-credential-refusal.test.sh` exits 0 including the new Rule E and Rule D rows (each Guard 1 mutation row 1-9 observed to fail the suite when applied, rows 10-11 observed as specified).
- [ ] Every Tier 1 curl call has the token-shape guard before it (battery rows 7 prove the refusal paths for covered probes; the owning tests or Rule E fixtures cover the rest).
- [ ] The Tier 1 infra file (`arm-heartbeats.sh`) and the four gate libs carry no reference in `file(`, `filesha256(`, `triggers_replace`, `host_script_files` or the Dockerfile (grep output in the PR body); the PR body states that merge triggers a production release (`apps/web-platform/**`, `plugins/soleur/**`) and a push-triggered infra apply with zero Terraform resource delta.
- [ ] Every owning test listed in Files to Edit passes; `scripts/lint-followthrough-varq-ban.sh`, `scripts/followthrough-exec-bit.test.sh`, `scripts/sweep-followthroughs.test.sh`, `plugins/soleur/test/fixture-relative-assert.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] No fixture, test or log in the PR contains a real token; fixtures use synthesized values (`cq-test-fixtures-synthesized-only`).
- [ ] ADR-202 carries the dated addendum; #9597 is referenced from baseline E's header comment and the PR body; PR body has `Ref #7797` and `Closes #7843` with the moved scope stated.
- [ ] `bash -n` passes on every touched script; every converted curl keeps `--disable` as its first argument and carries `--noproxy '*'` (or the recorded plugin exemption); `printf` feeding curl is the shell builtin.

## Test Scenarios

- Given a converted followthrough probe and a shim that records argv and stdin, when the probe runs with fixture token `fixture-token-<name>`, then no recorded argv entry contains the token and stdin carries `header = "Authorization: Bearer fixture-token-<name>"`.
- Given the same probe and a shim answering HTTP 401, then the probe exits with its TRANSIENT/FAIL status, never PASS.
- Given a wrapper-based script (`seed-qa-user.sh`) whose calls pipe curl output into `python3`, when run against the shim, then every call carries both `Authorization` and `apikey` on stdin and none on argv.
- Given a response-derived token `a"\nurl = "http://x/y`, when `bsky-community.sh` builds its header, then the form C guard refuses and the shim records zero calls.
- Given an unset, empty, newline-bearing, quote-bearing or non-ASCII token, then the token-shape guard refuses, no curl call is recorded (form C sites: only the login call) and the exit status is the script's TRANSIENT/FAIL status, never PASS.
- Given `SHELLOPTS=xtrace` with the token in env, a converted probe refuses with rc 78, zero calls, and no token on stderr.
- Given a 100,000-byte token, a never-reading shim and `set -o pipefail`, the converted probe returns rc 0 and the pipe-form mutant returns 141.
- Given `set -o pipefail` and a shim that never reads stdin, when a converted script runs, then its exit status is unaffected by the unread config (process-substitution form).
- Given `compliant-stdin-bearer-header-at-stdin.sh` and `compliant-stdin-bearer-wrapper.sh`, Rule E reports nothing; given each `violation-argv-bearer-*.sh`, Rule E reports exactly one finding per offending call site.
- Given a touched file that is in baseline E, `--changed` reports it (baseline bypass) until it is converted.

## Domain Review

**Domains relevant:** Engineering (security hardening of operator, CI and plugin tooling). No product, marketing, finance, legal, sales, operations-vendor or support surface changes.

### Engineering

**Status:** reviewed
**Assessment:** CTO assessment (spawned at plan time): direction sound; boundary at host-deployed scripts is right (server.tf hashes them into `triggers_replace`); main risk is silent auth break turning follow-through probes false-green, mitigated by the battery's negative-path rows and the post-merge sweeper comparison; recommended strictly ordered commits (compliance, conversion, Rule E), shrink-only baselines with issue links, an explicit stdin-conflict/`-K`/`-u` census, and a split into three PRs (single-PR decision and fallback boundary recorded in Scope Check). Applied: negative-path rows, commit ordering, baseline equality row, census results, post-merge comparison. Plan-review (DHH, Kieran, code-simplicity) applied: detector-first ordering with per-phase baseline shrink, wrapper-aware Rule D/E, `main()` plumbing row, allowlist charset guard, battery scoped to probes and form C sites, ADR addendum trimmed, post-merge comparison dropped, residue tracker filed early, sourced-library trace limit stated. Deepen-plan (security, architecture, flow, test-design passes) applied: bare-form Rule D fix first, wrapper-awareness design, Rule E own scope and per-file baseline counts, token-shape guard at every site, Tier 2 widened to 11, cutover-verify exemplar edit dropped, battery keyed to baseline E with instrument controls and a real-curl oracle, pipe-form mutant row, merge side-effect statements. Not applied: live dry-run of converted probes against real APIs (requires reading real tokens; the brief forbids touching token values). GDPR gate: not invoked; the change moves a transport channel for existing credentials and introduces no new processing, store, schema or lawful-basis question (`dsar-export-oversize.sh` and `gdpr-override.sh` change only how their existing auth header is carried).

## Dependencies & Risks

- **Silent auth break (highest).** A conversion that drops the header turns a 200 into a 401; probes that read "no data" as healthy would false-green. Mitigation: battery rows (v), per-site review that status capture (`-w`) and `2>/dev/null` placement are untouched, post-merge sweeper comparison.
- **`--config -` consumes stdin.** Measured zero Tier 1 conflicts; any site added later that needs stdin for a body must use `--data-binary @file`. Rule E does not police this, the battery row (iii) would catch it as a missing header.
- **Test stubs asserting argv.** Stubs that assert `Authorization: Bearer` in argv (e.g. `test-betterstack-ingest-probe.sh:64`) will go red by design; they are updated to read stdin and to assert absence from argv, in the same commit as the script.
- **Baseline interaction.** `--changed` makes the 13 failing baselined files fully A/B/C/D-clean in this PR (the other 6 only lose a baseline line); the prerequisite commits are separate. Some prerequisites change behaviour (a Rule D destination pin, a new refusal exit); Phase 0.2 sizes them per file and the battery's 401 row re-runs after each probe prerequisite.
- **Merge side effects.** `apps/web-platform/**` and `plugins/soleur/**` edits trigger a production release and the plugin scripts are vendored onto the host runtime; `apply-web-platform-infra.yml` is push-triggered on `apps/web-platform/infra/**` and runs `arm-heartbeats.sh` and the gate libs live. The mitigation is the owning-test updates and the PR-body statement, not a gate.
- **Plugin users' environments.** Forced `--noproxy '*'` and `--disable` ignore a user's proxy and `~/.curlrc`; Phase 0.3 records per script and the PR body/ADR addendum state the behaviour change (or the exemption).
- **Lint blast radius.** The Rule D destination-pin fix and wrapper awareness change a lint that gates the whole tree; Phase 1.2 measures `--census` before and after and resolves every new offender in the same commit.
- **Mid-PR drift.** A concurrent PR can add an argv bearer after baseline E is generated; Phase 7.4 rebases and regenerates mechanically.
- **Plugin-shipped scripts** run on users' machines: bash-only constructs already present in each file, no new dependency.
- **Tier 2 re-introduction window.** Until #9597 lands, the 11 Tier 2 scripts keep argv bearers; baseline E names them with site counts so growth elsewhere cannot hide.
- **`--changed` is advisory.** ci.yml:231 runs in the non-required `lint-bot-statuses` job; the blocking enforcement is the repo-wide run inside the required `test` context. The touched-file drawdown trigger therefore surfaces in review, and growth is blocked.
- **Large PR.** Split fallback at the Scope Check boundary.

## References & Research

#7843, #7797, #7842, #7898; ADR-202, ADR-263, ADR-198; `scripts/lint-shell-trace-credential-refusal.py`; `tests/scripts/test-sentry-alert-live-fidelity.sh`; `apps/web-platform/infra/cutover-verify.sh`; `scripts/supabase-logs-query.sh`; post-mortem `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`.

Spec lacks valid `lane:` (no `spec.md` exists for this branch): defaulted to `cross-domain` (fail-closed).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `--changed` (what CI runs) bypasses every baseline, so touching ANY script in a baseline makes it fully Rule A/B/C/D-clean in the same PR. That is why Phases 2-6 carry a prerequisite commit per group and why 19 files cost more than their conversion alone.
- The new battery must be registered in `scripts/test-all.sh` by hand and verified with `lint-orphan-test-suites.sh`; an unregistered suite reads as coverage and never runs.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` is a row-by-row equality baseline with per-file counts for several Tier 1 scripts (`dsar-export-oversize.sh`, `weekly-analytics.sh`, `sentry-monitors-audit.sh`, ...). A script edit that moves a count turns that suite red; regenerate in the same commit, never loosen it.
- Followthrough probes are constrained by `lint-followthrough-varq-ban.sh` (no `: "${VAR:?}"`), `trusted-verdict.sh` routing and the exec bit; a conversion edits only the curl invocation.
- `#!/bin/sh` and process substitution do not mix: the only such script (`soleur-host-bootstrap.sh`) is Tier 2 and will take the pipe form there, where pipefail does not exist in dash.
- Tests that stub curl and assert the bearer text in argv (`test-betterstack-ingest-probe.sh:64`) go red BY DESIGN when the script converts; update the stub to read stdin and assert the token is absent from argv, never loosen it to accept either.
- Co-travelling credential headers (`apikey:`) must move with the bearer in the same config stream; converting only the `Authorization` line leaves the identical key on `ps`.
- A response-derived token needs the form C guard BEFORE it is formatted into the config stream; the format string stays a literal `%s` template.
- Rule E's baseline equals the live offender set exactly (growth and shrink both need a regeneration commit); do not hand-edit it to excuse a script.
- No step runs a converted probe with a real credential (the brief forbids touching token values); the next scheduled sweeper run is the live signal and no criterion depends on it.
- Rule D's destination-pin limb misreads a token inside `< <(printf ...)` as a curl operand when the call is OUTSIDE `$(...)` (measured twice); a fixture inside `$(...)` hid it. Fix the lint before any conversion, and give every fixture the bare shape.
- A Rule E fixture must start from a Rule-A/B/C/D-clean fixture (`compliant-ruled-pinned-destination.sh`), and the suite counts Rule E messages; an rc-only row passes for the wrong rule.
- `lint-orphan-test-suites.sh` keys on `*.test.sh` and does not see `tests/scripts/test-*.sh`; "reports no orphan" is vacuous for the new battery, so registration is proven by counting its `run_suite` line and seeing its label in a run log.
- The probe population is derived at test time and reduced to hermetically reachable probes; `phase3-ga-soak-5274` exits on a placeholder before any curl, and two probes write fixed `/tmp` paths: none belong in verdict rows.
- A traced parent sees `++ printf 'header = ...' <token>` from the process substitution; the xtrace preamble is the defense, so a converted script without one gains procfs hygiene only.
- A 4xx shim answer proves nothing about the header: the shim is auth-gated (200 only with the fixture bearer) so a dropped header changes the outcome.
