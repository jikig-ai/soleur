---
title: "fix: argv-bearer sweep S2, ops and runner scripts off the process command line"
date: 2026-10-08
slug: argv-bearer-sweep-s2-ops-runner-scripts
branch: feat-one-shot-argv-bearer-sweep-s2-ops-scripts
issue: 9597
closes: [8767]
type: fix
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-10-08
**Gates run (mechanically):** User-Brand Impact 4.6 (section present, threshold `single-user incident`), Observability 4.7 (five fields present, probe verb allowlisted, no shell-active characters, executed on the two already-clean files in 0.6 s), PAT sweep 4.8 (no hit), Guard Contract 4.11 (`lint-guard-contract.py` green, three entries), Scope Check 4.12 (one live section, `Recommendation:` present, no block marker), rule-id and PR/issue citation checks (every cited rule id active; #9597, #7797, #8767, #7898, #9294 open; #9674, #9736, #9594, #9632, #9654, #9733, #9747 merged). Not triggered: UI wireframe 4.9, Encryption Posture 4.10 (no store or connection), Downtime 4.55 (no serving surface goes offline; the one hosted-path risk is covered under MERGE EFFECTS), network-outage 4.5 (no trigger term).
**Reviewers (report-only, parallel):** plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, plus CTO and CPO consults), then security-sentinel, observability-coverage, test-design, user-impact.

### Key Improvements

1. A review seat proved the "no infra-suite edit" premise false for two sites (the suite's tool-census counts `python3` in the probe arms); D1 now converts 17 of 19 and holds back 2, with the one-line suite edit tracked and an explicit operator choice recorded.
2. Security seat verified the bash HMAC against bash 3.2 and a `6`x64 key, and found `set -a` exporting the function's locals; the function now turns allexport off, bans here-strings and heredocs on key-derived data, and the `.env` allow-list drops `~` (tilde expansion changes a stored value on source).
3. The curl config deny-list was validated against real curl 8.22: only `"`, `\` and newline change parsing, so the planned superset is complete; Phase 0 gains a byte-sweep oracle and a corrected value-free measurement (a password may contain `:`).
4. Test-design seat: the `hmac-cf` shim now recomputes the digest, delegated rows must record stdin, the population invariant becomes disjointness (so commits 3 to 8 stay green and bisectable), mutations run per copy and per script, held-back sites are pinned by arm anchor, and floors follow each suite's own shape (an exact `-ne` floor in `community-argv.test.sh`).
5. Observability and user-impact seats: failure modes cite observability layers, the hosted "mirrored or paged" implication is removed (the extractor is wired to the agent PostToolUse hook only), the hosted X run becomes a mandatory post-merge gate, and Phase 0 measures the Cloudflare Access, deploy-webhook and Anthropic credential shapes value-free.

### New Considerations Discovered

- `bs_read_classify` and two callers (`scheduled-inngest-health.yml`, `git-data-cutover.yml`) discard the reader's stderr, so the marker is invisible there; surfacing it belongs to S3 (both are S3 files) and is added to the follow-up list.
- `deploy-docs.yml` also fires on the plugin edits (docs site publish); `infra-validation.yml` runs the infra suites against the converted scripts in CI.
- An empty `WEBHOOK_SECRET` signs silently under `hmac.new(b"")`; the canonical snippet now exits non-zero on an empty key.
- `Closes #8767` is mandated by the brief but leaves the `op=backup` environment gap open; the PR body must say "partial" in words.

## Overview

Slice S2 of the argv-credential sweep (tracker #9597, parent #7797). S1 (`cc4fa34d9d`, #9674) widened Rule E
and converted the four community scripts. S2 moves the credentials that the ops and runner scripts under
`scripts/` and five community plugin scripts still put on a process command line onto stdin or the process
environment, and adds the `-u`/`--user` arm to Rule E in the same diff as the one script that needs it.

The PR carries `Ref #9597`, `Ref #7797` and `Closes #8767`. Only S5 closes #9597. S3 to S5 are out of scope.

**What the measurements changed (details in "Research Reconciliation").** The brief sizes
`scripts/cutover-inngest.sh` at 20 curl-header sites. That was true at S1 and is not true now: #9736
(merged 2026-10-08 00:13Z, after S1) already moved all of them onto the stdin config channel
(`_sig_curl`, `_bearer_curl`) and removed the file's baseline-E row. What remains in the file is the HMAC
key itself on `openssl dgst -hmac` argv at **19 sites** (invisible to Rule E; 17 are converted here and 2 are
held back for a measured reason, D1) plus the three #8767 halves that are still open. The brief's instruction to use python3 for the OAuth1 signing key would also break
hosted X posting: the web-platform runner image has no python3, and `x-community.sh` runs hosted from the
Inngest crons. Both findings reshape the plan; neither is carried over from the issue text.

### MERGE EFFECTS (read first)

| Trigger | Fires on merge? | Why | Plan response |
|---|---|---|---|
| `apps/web-platform/infra/**` (production push apply: `apply-web-platform-infra.yml`, paths also list itself and `tests/scripts/lib/destroy-guard-filter-web-platform.jq`) | **No edit planned** | **PROMINENT:** the 4,583-line owning suite of `cutover-inngest.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, lives under this path and splices named functions out of the script into render drivers. Editing it would fire the production apply (measured: #9736 edited it and the push apply ran, 2026-10-08 00:35Z, success). No S2 source file is itself under the path. | Design D1 keeps the HMAC conversions **inline** so the splice contract holds, and **holds back two sites** because the suite's tool-census regex would otherwise redden (review finding, verified: it counts `python3` in the read-only probe arms and requires exactly 2 tool calls). An acceptance row fails the PR if any path under the prefix, the apply workflow or the destroy-guard filter is in the diff. If implementation finds an edit there unavoidable, STOP and escalate: that edit belongs to S4/S5 with operator notice (see the decision record for the one-line suite edit that would convert the last two sites). |
| `plugins/soleur/**` except `docs/` and `test/` (and `apps/web-platform/**`): `web-platform-release.yml` | **Yes** | Edits to `plugins/soleur/skills/community/scripts/*.sh` and `plugins/soleur/skills/community/SKILL.md`. `x-community.sh` runs hosted (`cron-community-monitor`, `cron-content-publisher`), so a defect ships to production X metrics and posting. | PR body first line names the release trigger; a hosted-path smoke row (D3) and post-merge release check; CPO condition 5. |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | **No** (its push paths are host files, not `scripts/`) | It calls `bash scripts/check-deploy-script-parity.sh --status-only` (step in that workflow), so the **next** run of that workflow uses the converted script. | Refusal exits 2 (non-zero, red step), python3 present on the runner; the script's own suite plus a battery row. |
| `apply-web-platform-infra.yml` read steps | **No** | It calls `scripts/betterstack-query.sh` (two calls in its read steps). The converted reader is what the next apply uses. | Phase 0 measures the real credential shape value-free; the guard is a deny-list of the characters that can break a config line, not an allow-list; a read-only smoke dispatch on the branch before merge (Phase 9). |
| `deploy-docs.yml` (push on `plugins/soleur/skills/**`, and again after the release) | **Yes** | The same plugin edits rebuild and publish the docs site to Cloudflare Pages. | Named in the PR body; post-merge check that the run is green (no docs content changes). |
| `infra-validation.yml` (push and `pull_request` on `scripts/cutover-inngest.sh`, `scripts/betterstack-query.sh`, `scripts/lib/betterstack-read-classify.sh` and others) | CI only | It is the CI gate that runs the infra suites against the converted scripts; it deploys nothing. | Its result on the PR is part of the pre-merge proof. |
| `scheduled-followthrough-sweeper.yml` (daily 18:00Z) | No | Runs `scripts/sweep-followthroughs.sh` and the four converted probes on its next schedule. | Owning suite plus battery; first post-merge sweep is a named check. |

## Decisions

**D1. cutover-inngest.sh: convert 17 of the 19 HMAC-key sites inline, hold back 2, finish #8767, edit nothing under the infra path.**
Each `SIG=$(printf ... | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')` becomes the canonical
snippet with the key on the python3 child's environment only:
`SIG=$(printf ... | HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;sys.stdout.write(hmac.new(os.environb[b"HMAC_KEY"],sys.stdin.buffer.read(),hashlib.sha256).hexdigest())')`
(173 bytes as first verified, byte-equal to `openssl dgst -sha256 -hmac` on a synthetic key for the empty and a JSON body,
and non-zero with no key. Deepen adds an empty-key exit, because `hmac.new(b"")` signs silently: the final form reads the key into a name, then `k or sys.exit(1)`; Phase 0 re-measures the byte length and re-runs the oracle on the final text). Reasons it is a per-command prefix and `-I`: an exported key reaches every later
child, `-I` ignores `PYTHON*` and user-site injection, `os.environb` cannot raise on a non-UTF-8 byte. The render
drivers of the infra suite set `WEBHOOK_SECRET` as an **unexported** shell variable
(`printf 'BASE=...; WEBHOOK_SECRET="stub"; ...'`), which is a second reason the key must be passed by prefix rather
than read from the ambient environment. A sourced helper function is rejected for this file: the suite splices
only `_bearer_ok` and `_sig_curl` into its drivers, so a new function would be unbound there and the 1,069-assertion
exact floor would have to move, which means editing a file under the production-apply path. Cost accepted:
17 byte-identical copies, held together by a battery parity row (every converted copy equals the canonical string,
exactly the two held-back sites still carry `-hmac`) and an oracle row (canonical output equals `openssl dgst -hmac` over a
synthetic key).
**Held back, and why (verified by two review seats and re-read): the infra suite's tool census.** Lines in
`cutover-inngest-workflow.test.sh` (`#6617 probe arms make exactly 2 network/tool calls`, and the `check_rpg_tool_count`
mutation helper) count tokens matching `(curl|wget|nc|ncat|socat|python3?|perl|gh|aws|doppler|hcloud)` in the
`registry-probe)` through `rearm)` arms and require exactly 2. The HMAC sites at the `registry-probe` and `doublefire-probe`
arms sit in that range, so a `python3` token there takes the count from 2 to 4 and reddens the suite. Options, decided:
(A) hide the token (`"${_PY:-python3}"`, `node -e`): **rejected**, it games a guard whose stated purpose is "these arms cause no
side effects" and a reviewer would be right to call it evasion; (B) edit the two census regexes in the suite to allow the
canonical HMAC line: the correct fix, but it is an `apps/web-platform/infra/**` edit and fires the production apply on
merge, which belongs to the slice that carries operator notice (S4/S5); (C) **chosen:** convert the 17 sites outside the
census range now, leave the two read-only probe-arm sites on `openssl dgst -hmac` with a one-line comment naming this
decision, and track them with the suite edit in the follow-up issue list (Phase 10). Residual stated plainly: the same secret
is on `openssl`'s argv for those two sites, which run only on a manual dispatch of the read-only `registry-probe` and
`doublefire-probe` ops, for milliseconds; the conversion removes the other 17 windows (every automated op). Phase 0 proves the
partition by running the infra suite (read-only run) against a scratch copy with ALL 19 converted and recording which rows turn red; the
set of held-back sites is whatever that run says (expected: exactly those two). The operator may instead choose (B); that
choice is recorded in `decision-challenges.md` (headless).
`_sig_curl` gains one stderr line on its existing `_bearer_ok` refusal arms: the value-free marker
`SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape` (one edit covers every site, held back or not, and the two
Cloudflare Access values; the function stays one `^_sig_curl() {$` ... `^}$` range so the suite's awk splice still
extracts it). Refusal exit: unchanged, rc 2 to the caller, whose existing `|| echo "000"` and `::error::` arms turn it
into a red job.

**D2. #8767, the other three halves, and the tier row for `create_image`.**
(a) `backup)` arm: `::add-mask::` the Doppler-read `HCLOUD_TOKEN` immediately after the read, guarded on a non-empty
value (a bare directive on an empty read is the failure the existing `BS_API` arm already guards against), to stderr
as the G3 anchor does. (b) The non-201 branch prints the HTTP code and a fixed hint chosen by code class (401/403:
token rejected or read-only, see ADR-241 D4), never `$(cat /tmp/backup-body)`. (c) The action-error branch drops
`cat /tmp/backup-action` and prints the action id. (d) **Tier decision:** `create_image` is a Hetzner **write** and
the token it needs is the read/write `HCLOUD_TOKEN`, which ADR-241 D1 places in **Tier B**; `HCLOUD_TOKEN_READONLY`
returns `token_readonly` on it. The runbook row `cutover-inngest.yml::cutover` is therefore **split in two**: the
generation-anchor read stays Tier A (`HCLOUD_TOKEN_READONLY`), and `op=backup`'s `create_image` becomes a Tier B row.
Recorded as an ADR-241 amendment (the ADR's own mechanism for a tier classification change: "recorded here rather
than as a new ADR"). **Open gap, stated plainly:** the workflow's `environment:` expression lists arm, rollback,
resume, reflush, luks-cutover and luks-rollback but **not** `backup`, so today the write runs on a repo-secret-reachable
Doppler token with no reviewer-gated environment, and ADR-241 step O10 removes the token from `prd_terraform`
(which breaks `op=backup` outright). Closing it needs the workflow expression **and** the pinned infra suite
(which asserts the membership list) to change: both are infra-path edits, so it is a tracked follow-up issue
(created in Phase 10, with an owner and the O10 dependency), not part of S2. An in-script "interim guard" (for
example a ref check) is rejected: the dispatched ref supplies the script, so it is not a boundary. `Closes #8767`
is justified because the issue's four claims are resolved: argv (already done by #9594), body echo, mask, tier
decision; the residual re-plumb is its own issue.

**D3. HMAC primitive per surface (the "HMAC helper"): python3 on runners, bash plus `openssl dgst` over stdin in the plugin.**

- *Runner and sweeper surface* (cutover-inngest, check-deploy-script-parity, the four followthrough probes): the
  canonical snippet of D1. Precedent in tree: `kb-drift-walker.yml` (HMAC key from the environment via python3
  `hmac`). Where it can be sourced no helper is created now: the two followthrough suites relocate the probe into a
  sandbox by copying that one file, so a sourced library would be missing there, and S3 builds the workflow-side
  library (`scripts/lib/bearer-curl.sh`) where a checkout exists. The "helper" is therefore the **canonical snippet
  pinned by the battery** (oracle row, parity row, and a census row: no `-hmac` operand in any S2 file).
- *Plugin surface* (`x-community.sh`, `x-setup.sh`, OAuth1 HMAC-SHA1): **python3 is not available in the runner
  image** (measured: the `Dockerfile` installs `ca-certificates git bubblewrap socat qpdf jq openssh-client`, then
  `curl` and `gh`, on `node:22-slim`; `git grep -n python3 apps/web-platform/Dockerfile` is empty), and
  `x-community.sh` runs hosted. The signing key is therefore computed by RFC 2104 HMAC in bash with `openssl dgst
  -sha1 -binary` reading **stdin only**: the key lives in bash builtins and pipes (`printf`, `od`, `tr`), never in an
  exec argument. A 32-case prototype (key lengths 0, 1, 20, 63, 64, 65, 96, 200 against four messages) was byte-equal to
  `openssl dgst -sha1 -hmac ... -binary | base64`; the oracle suite adds a `6`x64 key (ipad XOR gives NUL bytes, so the
  pads are emitted as `printf '\xHH'` into the pipe and never held in a variable), a backslash/quote/space key, and an
  argv-recorder `openssl` shim asserting no `-hmac` or `-macopt` operand and no key bytes in any recorded argument across a
  full signing run. The function lives in one sourced file shared by both scripts
  (`plugins/soleur/skills/community/scripts/lib/hmac-sha1-b64.sh`) instead of two more copies of a crypto primitive.
  `node -e` with `crypto.createHmac` is the simpler alternative (the image has node) and is rejected because it adds a
  runtime dependency for installed plugin users who today need only `openssl`, `jq` and `curl`; the choice is
  reversible behind the one function. `openssl` presence in the image is already depended on by the hosted path
  (`require_openssl` runs before any X call), and Phase 0 re-measures it with `docker run` on the pinned base image.

**D4. Refusal contract per surface (marker, exit code, and the sink that hears it).** Marker everywhere:
`SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>`, value-free. `MARKER_RE` already has the
arm (registered by S1), so no new marker is added; the telemetry drift guard runs unchanged (Phase 9). Exit codes are
**not** uniformly 1, and the reason is the sink table below: where `1` means FAIL, or means "blame Doppler", a refusal
must not borrow it. Per the 2026-10-06 learning on refuse-before-send guards, each row names the old failure's sink and
the new refusal's sink:

| Surface | Old failure (bad credential) | New refusal exit | Sink that hears it | Verdict |
|---|---|---|---|---|
| `cutover-inngest.sh` webhook ops | HTTP 403 -> `::error::` + `exit 1` | rc 2 from `_sig_curl` -> `CODE=000` -> the arm's `::error::` + `exit 1` | red job, marker on the run log | same sink |
| `betterstack-query.sh` | 401 -> rc 22 -> `credentials-rejected` remedy | **exit 2** (not 1) | `bs_read_classify` maps 2 to `reader-refusal`; callers that keep stderr (the cutover remedy printer, `apply-web-platform-infra.yml`, `reusable-release.yml`) show the marker. **Two callers discard stderr** (`scheduled-inngest-health.yml` reads `2>/dev/null` so exit 2 becomes `__UNREADABLE__`; `git-data-cutover.yml` reads `2>/dev/null \|\| true` and fails generically after its retries): the marker is invisible there, which is no worse than the old 401. Exit 1 would map to `reader-exit-1`, whose remedy blames `DOPPLER_TOKEN`: the wrong action | better than the brief's 1; the marker is not claimed for those two |
| `check-deploy-script-parity.sh` | 403 -> `DRIFT(status)`, exit 1 | exit 2 (the script's existing usage-class refusal) | red step in `apply-deploy-pipeline-fix.yml` | same sink |
| the four followthrough probes | 403 -> `TRANSIENT` (rc 2) comment on the tracker | exit 2, marker line in the comment | tracker comment (the sweeper strips `^+` trace lines, not this line); a persistent refusal stays TRANSIENT exactly as a persistent 403 does today | same class; NOT exit 1, which is the FAIL verdict that closes or flags a tracker |
| `compound-promote.sh`, `learning-retrieval-bench.sh` | HTTP 401 -> empty content -> `exit 1` / `(API_ERROR)` | exit 1 | workflow step / bench summary | same sink; the bench must not turn a refusal into `(API_ERROR)` silently |
| setup scripts (`write-env`) | value written, later `source`d | exit 1 (exit 64 for the discord positional) | stderr to the invoking user | new refusal, user-visible |

**D5. Rule E `-u`/`--user` arm, seeded honestly.** Design in "Rule E arm" below. Measured effect on the census:
`betterstack-query.sh` is converted in the same diff and never enters baseline E; the arm **newly flags two
`apps/cla-evidence` R2 SigV4 sites** (`bootstrap.sh` and `scripts/r2-conditional-put.sh`, `--aws-sigv4 ... --user
"$ID:$SECRET"`). They are not converted here: the CLA-evidence upload scripts are the legal-evidence pipeline with
their own suites and owner, outside the brief's file list, and a defect there would be a legal-record regression
rather than an ops one. They enter baseline E and the ceiling table as two rows with a dated tracking issue
(Phase 10), and the arm's docstring says so. The ratchet therefore moves 32 files / 65 sites -> (-5 converted, +2 newly
visible) 29 files / 62 sites; the PR body states that the +2 is census widening, as S1's seed was.

**D6. `sweep-followthroughs.sh` env hop: convert, in-process.** `env -i PATH=... NAME=<secret> ... "$script"` puts every
forwarded secret on `env`'s argv until `env` calls `exec`. Replace it with a `python3 -I` launcher that builds the exact
`env -i` environment (PATH pinned to the FHS default, `HOME`, the validated secret names, `SOLEUR_FT_EARLIEST`) from the
sweeper's **own environment** by name and `os.execve`s the probe: names travel on argv, values never do. All existing
validation (`valid_secret_name`, set-but-empty, reserved names) runs first, unchanged. The sweeper runs on
`ubuntu-24.04`; the launcher is resolved with the sweeper's PATH, the probe still gets the pinned PATH. Proof: every
existing T8/G3 row (they assert the probe sees a forwarded name and not an unforwarded one) plus new rows: a recording
`env` shim is never invoked, a recording `python3` shim shows no secret value in its argv, and a name with a value
containing `=`, a newline and a 100 KB value round-trips intact. If the launcher cannot hold those rows the fallback is to
document the microsecond window and leave `env -i` (the S1 contract allows either); that fallback is a Phase 5 exit
criterion, not a mid-implementation choice.

**D7. `"$CURL_BIN"` sites: convert two, do not widen the lint.** Only two live sites exist (`git grep` below):
`compound-promote.sh` and `learning-retrieval-bench.sh` (`-H "x-api-key: $ANTHROPIC_API_KEY"`). Both move to
`--disable --noproxy '*' ... --config -` with the header on a process substitution behind the `_bearer_ok` shape
guard. Request bodies stay `-d "$REQUEST"` (non-secret corpus text, and the suites' mock curl captures the payload from
`-d`). Widening Rule E to recognise `"$CURL_BIN"` as a command word is deferred: after these two conversions no live
site remains (census row), so the widening would add a detector with zero members; the blind spot stays in the
docstring. Residual stated: `CURL_BIN` is an environment-declared binary that receives the key on its stdin, as before on
its argv; it is a test seam, not a boundary.

**D8. `write-env` hardening (three setup scripts) and the Discord positional webhook.** (Scope note: this is a `.env` source-injection class, not an argv leak; it is in because the brief names it explicitly for `bsky-setup.sh` and `discord-setup.sh`.) `.env` values are written
unquoted and later `source`d (`verify`, the community scripts), so a value holding `$(...)`, a backtick, a quote,
`;`, a space or a newline executes or splits on the next source. Validation is an **allow-list** per value, fail-closed:
`[A-Za-z0-9._:/@%+=,-]` and non-empty, implemented as an `LC_ALL=C case "$v" in ''|*[!set]*)` glob (not `grep`, which is line-oriented and lets a multi-line value through). `~` is deliberately absent: measured by the security seat, `A=~` sources as `$HOME` and `D=~+` as the working directory, which silently changes a stored credential (covers a Bluesky handle and app password, a Discord bot token, a webhook URL, X
keys, a LinkedIn person URN). A refused value prints the marker plus one human line naming only the VARIABLE and
the allowed class, writes nothing, exits 1, and leaves any existing `.env` untouched (validate every value before the
first write). `bsky-setup.sh` and `discord-setup.sh` are asked for; `x-setup.sh` is edited anyway for the signing key and
carries the identical `echo "KEY=${VAL}" >> .env` shape, so it is included and marked `inferred` in the provenance table (a
reviewer can cut it without touching the rest). `linkedin-setup.sh` has the same shape and is **not** touched here (review: one
inferred sibling is enough scope); it is named in the Phase 10 follow-up list so the class is tracked, not forgotten.
Allow-list limits are intentional: a value with a space, `#`, `?` or `&` is refused (the message says to edit `.env` by hand); `create-webhook` returns `https://discord.com/api/webhooks/<id>/<token>`, which has none of them, and thread-scoped URLs with `?thread_id=` are not supported by this script. The plugin release notes carry one changelog line for the changed CLI form.
`discord-setup.sh write-env <guild_id> <webhook_url>`: the webhook URL (a write-capable secret) moves to
`DISCORD_WEBHOOK_URL_INPUT`, the sibling of the two existing `*_WEBHOOK_URL_INPUT` variables. Argument handling happens
BEFORE the existing `webhook_url="${2:?Usage...}"` expansion (which would otherwise fire a bare usage error first) and has four
explicit branches, each with a row: (1) a second positional present: refuse, exit 64, one-line migration message that names the
variable and shows a copy-pasteable form, never echoing the argument (CPO conditions), and the copy-pasteable form does not leave the secret in shell history (`read -rs DISCORD_WEBHOOK_URL_INPUT; export DISCORD_WEBHOOK_URL_INPUT`), whether or not the env var is also set
(the secret is already on the argv); (2) no second positional and `DISCORD_WEBHOOK_URL_INPUT` set and non-empty: validate and
proceed; (3) neither: usage error naming the variable, exit 64; (4) env var set but empty: same as (3). Header, usage text and the
header's exit-code list (a new `64 - usage`) change in the same commit; `SKILL.md` needs no change (it never documented the positional).

**D9. Heartbeat-URL probes: document, do not convert in S2.** Measured with `git grep -nE 'curl[^|;]*"?\$\{?[A-Za-z_]*(HEARTBEAT|HB|PING|CHECKIN)[A-Za-z_]*\}?' -- . ':!knowledge-base' ':!*.md' ':!*.test.sh' ':!tests'`
(Phase 0 re-runs it; this is a pattern census, not a proof that no other spelling exists): the carriers found
(`inngest-bootstrap.sh` heredoc unit, `web-git-data-probe.sh`, `luks-monitor.sh`) are host files under
`apps/web-platform/infra/**`, so converting any of them fires the production apply. None was found in an S2 file. The
decision is recorded in the Rule E docstring (a URL path secret is not decidable from syntax and the carriers are
infra-path hosts, S4/S5 class), in the #9597 tracker comment, and in the follow-up issue list. Convertible later as
`url = "..."` on the stdin config behind a shape guard.

**D10. Baseline ordering.** Baseline E and the ceiling table change only after the merge commit exists (Phase 9
"ordering"), because a concurrent PR moves rows and a baseline generated on a stale tree is rejected by equality. The
rows that leave and enter are stated in "Baseline and ceiling rows".

**D11. Commits are separable by blast radius** (CPO condition 3): (1) lint arm and fixtures, (2) Hetzner/#8767, (3) deploy
webhook and Cloudflare Access (cutover HMAC, parity, probes), (4) Better Stack reader, (5) sweeper hop, (6) Anthropic key
sites, (7) plugin scripts, (8) docs and tracking, (9) baseline-only commit last.

## Research Reconciliation: brief and issue text vs. codebase

| Brief / issue claim | Reality (`667200edd5`, measured 2026-10-08) | Plan response |
|---|---|---|
| `cutover-inngest.sh` has 20 argv sites (HMAC + Cloudflare Access) | **0** curl credential headers on argv: #9736 moved all 20 to `_sig_curl`/`_bearer_curl`; `python3 scripts/lint-shell-trace-credential-refusal.py scripts/cutover-inngest.sh` = OK, and the file has no baseline-E row. Remaining: **19** `openssl dgst -sha256 -hmac "$WEBHOOK_SECRET"` sites (key on argv, invisible to Rule E) and the 3 #8767 halves. | Census below; D1 (17 converted, 2 held back), D2. No baseline row leaves for this file. |
| Baseline E is 33 files / 85 sites | **32 files / 65 sites**, baseline and ceiling identical (`grep -v '^#' ... \| awk`): #9736 dropped the cutover row (20 sites). | Rows leaving: 5 (D5), arithmetic corrected. |
| HMAC and OAuth1 keys go through python3 | python3 is absent from the runner image and `x-community.sh` runs hosted. | D3: python3 for runners, bash+openssl-stdin for the plugin. |
| Refusal exits 1 | exit 1 means FAIL in the followthrough contract and `reader-exit-1` ("blame DOPPLER_TOKEN") in the Better Stack classifier. | D4: per-surface exit table. |
| #8767: HCLOUD_TOKEN on argv | already stdin since #9594 (`_bearer_curl HCLOUD_TOKEN`); body echo, missing mask and the tier question remain. | D2. |
| Runbook row says `cutover-inngest.yml::cutover` is Tier A for the Hetzner read, `create_image` "tracked in #8767" | the same job's `backup` op is a write on a token the environment gate does not cover (the `environment:` expression omits `backup`). | D2: split row, ADR-241 amendment, follow-up issue. |
| Open item 1: web-2 carries the old monitors | web-2 was **replaced again** on 2026-10-07 (dispatch run 37678331159, 19:56Z, head `411f034290`, which contains the Tier 2 merge `f68395e2fc`; server created 20:05Z per #9733). It was built from a tree that has the converted monitors. | Resolved by evidence; no S2 work. The unverifiable part (on-host file content) cannot be read without SSH and is not claimed. |
| Open item 2: do the apply workflows fire on the next qualifying push? | **Yes.** `apply-web-platform-infra.yml` push runs: 2026-10-08 01:21Z, 00:35Z, 00:13Z, 2026-10-07 23:28Z, 22:35Z, all `success`; `apply-deploy-pipeline-fix.yml`: 23:28Z and 22:35Z `success`. | Resolved; no separate issue. It also confirms a test-only infra edit fires the apply (D1's reason to avoid one). |
| Open item 3: first scheduled content-publisher Bluesky run on the converted `bsky-community.sh` | No evidence yet: no status commit under `knowledge-base/marketing/distribution-content` and no content-publisher issue since the S1 merge (21:59Z). | Stays a post-merge check; this PR's merge also redeploys the image, so the check is re-armed (Acceptance, post-merge). |
| Open item 4: the main checkout's `.mcp.json` is modified | Not in this worktree (`git status` clean); belongs to the operator. | Untouched; an acceptance row asserts no `.mcp.json` in the diff. |
| `-u`/`--user` has one real site | Three curl sites: `betterstack-query.sh` and two R2 SigV4 `--user` sites in `apps/cla-evidence` (`ci-deploy.sh`'s `--user` is `docker run`, not curl). | D5. |
| Heartbeat-URL probes are an S2 item | none in S2 files; all carriers under the infra path. | D9. |

## Research Insights

**Premise Validation (Phase 0.6).** Cited by reference: #9597 (open, restated checklist read in full plus its latest
comment), #8767 (open; its argv half is already fixed), #7797 (open, parent), S1 = #9674 (merged `cc4fa34d9d`),
#9736 (merged, supersedes the brief's cutover count), #9632 (merged `a0359450dd`; its baseline row is gone). Cited
paths checked on `origin/main`: all S2 files exist; `scripts/cutover-inngest.sh` is 3,706 lines. Proposed mechanism vs
the ADR corpus: ADR-241 already provides the tier-reclassification mechanism (an amendment, not a new ADR) and D4's
`HCLOUD_TOKEN_READONLY`; nothing in the corpus rejects stdin config or per-command environment keys. What held: the
conversion pattern, the lint structure, the S1 learning. What was stale: the cutover site count, the baseline totals,
python3 as the universal primitive, exit 1 as the universal refusal code, open items 1 and 2.

**Property List (Phase 0.6b).**

1. After S2 no S2 file places a credential (header value, basic-auth pair, HMAC or signing key, API key) in any process's
   argument list.
2. A malformed credential produces zero outbound requests and one value-free marker line, with an exit code that cannot be
   misread as a success or as a different failure class.
3. A response body or token is never printed to a public run log by the Hetzner backup path, and the token is masked before
   first use.
4. Rule E sees basic-auth `-u`/`--user` on curl, and the ratchet records what it newly sees.
5. A value written to `.env` by a setup script cannot execute or split when the file is later sourced.
6. Hosted X posting/metrics, the follow-through sweeper, cutover ops and the Better Stack reader keep working with real
   credential shapes.

**Cut List (Phase 0.6b).** (i) A shared HMAC library for runner scripts (buys property 1, already bought by the pinned
canonical snippet; the library cannot be sourced by the one file with 19 sites or by the two relocating suites). (ii) A
Rule E detector for `"$CURL_BIN"` (zero members after D7). (iii) An in-script interim ref guard for `op=backup` (not a
boundary; D2). (iv) Converting the two R2 sites (own owner and suites; D5). (v) The `--oauth2-bearer`, `-U`/`--proxy-user`
and `Cookie` vocabulary additions (no measured site; stay documented gaps). (vi) A third marker or a new
`MARKER_RE` arm (the S1 arm covers every emitter).

**Learnings applied** (read, not recalled): `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe`
(process substitution, not a pipe: `pipefail` returns 141 on a never-reading consumer; the guard before every call);
`2026-10-06-a-refuse-before-send-guard-turned-a-paging-401-into-a-silent-skip` (D4's sink table);
`2026-10-07-a-guard-pr-added-an-unregistered-marker-and-resumed-fix-agents-stalled-on-a-status-line` (run the marker drift
guard; do not resume a stalled seat a third time, take it over with `git diff`);
`test-failures/2026-10-06-a-new-anti-vacuity-floor-joins-the-meta-guard-and-a-fix-pass-must-be-audited-in-every-run`
(floor shape for any suite that grows rows); `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards` (new
rows use here-strings or process substitution into `grep -q`, never `printf | grep -q`).

## Census (measured with grep and the lint, not carried over)

Line numbers are a snapshot at `667200edd5`; implementation locates every site by the content anchor in the third column.

| File | Sites (kind) | Anchor | Disposition |
|---|---|---|---|
| `scripts/cutover-inngest.sh` | 0 curl-header argv; **19** HMAC-key argv (`SIG`x12, `GSIG`x4, `GSIG2`, `RSIG`, `PF_SIG`; 13 with `printf ''`, 6 with `printf '%s' "$PAYLOAD"`; the two in the `registry-probe` and `doublefire-probe` arms are held back, D1); 1 direct curl already on stdin config (`DISC_CODE`); #8767: 1 unmasked Doppler read (`HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain)`), 1 body echo (`hcloud create_image returned HTTP $CODE: $(cat ...)`), 1 body `cat` (`cat /tmp/backup-action`) | `openssl dgst -sha256 -hmac "$WEBHOOK_SECRET"`; the `backup)` arm | convert 17 inline, hold back 2 (D1); D2 |
| `scripts/betterstack-query.sh` | 1 basic-auth pair (`run_sql`: `-u "${BETTERSTACK_QUERY_USERNAME}:${BETTERSTACK_QUERY_PASSWORD}"`) | `-u "${BETTERSTACK_QUERY_USERNAME}` | `--config -` + `user = "..."`, deny-list guard, exit 2 (D4) |
| `scripts/check-deploy-script-parity.sh` | 1 curl with 3 credential headers (`X-Signature-256`, `CF-Access-Client-Id`, `CF-Access-Client-Secret`) + 1 HMAC key argv (`HMAC="$(printf '' \| openssl dgst ...`); `CF_ID`/`CF_SEC` carry no shape guard today | `-H "X-Signature-256: sha256=${HMAC}"` | stdin config + `_bearer_ok` on all three values; baseline-E row leaves |
| `scripts/followthroughs/canary-promotion-5875.sh` | 1 curl, 3 headers; 1 HMAC argv; **no xtrace refusal** (A/B/C baseline) and Rule D findings (D baseline) | `SIGNATURE="$(printf '' \| openssl` | convert; add refusal preamble; A/B/C, D and E rows leave |
| `scripts/followthroughs/infra-config-activation-7220.sh` | 1 curl, 3 headers; 1 HMAC argv (`2>/dev/null \|\| _sig=""`); no xtrace refusal; D baseline | `_sig=$(printf '' \| openssl` | same |
| `scripts/followthroughs/infra-config-fatal-channel-7220.sh` | 1 curl, 3 headers; 1 HMAC argv; no xtrace refusal; D baseline | `_sig="$(printf '' \| openssl` | same |
| `scripts/followthroughs/inngest-soak-6178.sh` | 1 curl (inside the registry/slice fetch function), 3 headers; 1 HMAC argv; xtrace refusal already present | `SIG="$(printf '' \| openssl` | convert; E row leaves |
| `scripts/sweep-followthroughs.sh` | 1 hop: `env -i PATH=... HOME=... NAME=value ... "$script"` built at `env_args+=("$name=${!name}")` and run at `out=$("${env_args[@]}" "$script" 2>&1)` | `local -a env_args=("env" "-i"` | D6 |
| `scripts/compound-promote.sh` | 1 `x-api-key` on argv via `"$CURL_BIN"` (invisible to Rule E); A/B/C baseline row | `-H "x-api-key: $ANTHROPIC_API_KEY"` | D7; A/B/C row leaves if the explicit-path run is clean |
| `scripts/learning-retrieval-bench.sh` | 1 `x-api-key` on argv via `"$CURL_BIN"` in `anthropic_paraphrase` (4 Rule D wrapper-call findings); A/B/C and D baseline rows | same | D7; rows leave if clean |
| `plugins/soleur/skills/community/scripts/x-community.sh` | 1 OAuth1 signing key on argv (`openssl dgst -sha1 -hmac "$signing_key" -binary`); `require_openssl` runs before any call | `-hmac "$signing_key"` | D3 bash HMAC |
| `plugins/soleur/skills/community/scripts/x-setup.sh` | same 1 site; `write-env` writes 4 unvalidated values | same | D3; D8 |
| `plugins/soleur/skills/community/scripts/bsky-setup.sh` | `write-env` writes 2 unvalidated values (handle, app password) then `verify` sources `.env` | `cmd_write_env` | D8 |
| `plugins/soleur/skills/community/scripts/discord-setup.sh` | `write-env` writes 3 to 5 values; the webhook URL is `$2` (positional, on the script's argv); `verify` sources `.env` | `cmd_write_env` | D8 |
| `plugins/soleur/skills/community/scripts/linkedin-setup.sh` | `write-env` writes 4 unvalidated values | `cmd_write_env` | NOT changed in S2: listed as deferred in the Guard 3 population manifest and the Phase 10 follow-up list (D8) |
| heartbeat-URL curls | 0 in S2 files; carriers: `inngest-bootstrap.sh`, `web-git-data-probe.sh`, `luks-monitor.sh`, all under `apps/web-platform/infra/` | `curl .* "\$INNGEST_HEARTBEAT_URL"` | D9 |
| `-u`/`--user` on curl, repo-wide | 3: `betterstack-query.sh`; `apps/cla-evidence/infra/bootstrap.sh`; `apps/cla-evidence/scripts/r2-conditional-put.sh` | `git grep -nE '^\s+(-u\|--user) "'` | D5 |

Reproduce before implementing and record the output in the PR body (counts only, no values):
`grep -c 'openssl dgst -sha256 -hmac' scripts/cutover-inngest.sh` (19);
`git grep -nE 'x-api-key:' -- '*.sh' '*.yml' ':!*.test.sh' ':!tests' ':!scripts/fixtures'` (the two sites plus the S3 composite action);
`git grep -nE -- '-hmac' -- scripts plugins/soleur/skills/community/scripts .github/actions` (the S2 set plus the S3/S4 set, which stays);
`grep -v '^#' scripts/lint-shell-trace-credential-refusal-e.baseline.txt | awk -F'\t' '{n++; s+=$2} END{print n, s}'` (32 65).

## User-Brand Impact

**If this lands broken, the user experiences:** hosted X metrics or posting going quiet (a converted
`x-community.sh` refusing a valid key or mis-signing; the change ships to the hosted crons through the web-platform
release), the daily follow-through sweeper reporting TRANSIENT for the four converted probes or failing to forward a
secret to any of its ~76 probes, a cutover or backup dispatch refusing a valid signature, the production apply's Better
Stack read steps failing on the converted reader, or an installed user's setup script refusing a legitimate credential.
All of these are loud (red job, marker line, non-zero exit) and recoverable by revert.

**If this leaks, the user's data is exposed via:** the exact failure the sweep removes, plus the two ways this
change could add one: a `::add-mask::` placed after first use or a response body echoed into a PUBLIC GitHub run log
(the Hetzner read/write token is root on any host through rescue or rebuild; the deploy webhook HMAC key plus the
Cloudflare Access pair can rewrite the production web host and read its credential file, ADR-241 D1 amendment), and a
key written to a temp file or printed under tracing during a conversion. Any of these is a platform-wide compromise, not one
user's. Residual after S2: the key is on the child's environment (same-uid and root can read `/proc/<pid>/environ`,
as they can already read the parent shell's), a reduction from world-readable `cmdline`, not elimination.

- **Brand-survival threshold:** single-user incident

CPO assessment (domain review below) approved the threshold and attached five conditions, all carried into the
acceptance criteria: a negative canary test over stdout and stderr including error paths; mask before first use and no
body echo; separable commits; rotation tracking check; hosted smoke check on the first post-merge runs. The
`user-impact-reviewer` seat is mandatory at review.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-241** (Terraform credentials are tiered) with a dated entry in its amendment log: "2026-10-08 (#8767):
`op=backup`'s Hetzner `create_image` is a write, so its `HCLOUD_TOKEN` read is **Tier B**; the generation-anchor read
stays Tier A (`HCLOUD_TOKEN_READONLY`). The workflow's `environment:` expression does not yet include `backup`;
closing that and the O10 re-plumb is #<follow-up>." It is a tier classification change, which the ADR records as an
amendment rather than a new ADR (precedent in the same document: the 2026-09-30 and 2026-10-02 entries). Task in
Phase 8, not a deferral. The runbook row is split in the same commit
(`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`).

### C4 views

No C4 impact. Checked against all three model files: external systems touched are GitHub Actions runners, Hetzner API,
Better Stack query endpoint, Doppler, Cloudflare Access/deploy webhook, Anthropic API and Discord (counts of
Hetzner 42, Better Stack 28, Doppler 35, Anthropic 7, Discord 2, cutover 24 mentions in `model.c4`; the views include
the same systems), all already modeled; X and Bluesky are not modeled (a pre-existing gap this slice does not widen);
no actor, container, store or access relationship changes (transport inside existing edges only). The cardinality
gate `plugins/soleur/test/c4-count-parity.test.sh` was run during planning and passes (`Failed: 0`) and re-runs in Phase 9
because S2 adds no workflow or monitor.

### Sequencing

None: the amendment describes the current state.

## Implementation Phases

Order is guard-first, then conversions in blast-radius commits, then docs, then the baseline-only commit. Write each
phase's failing rows BEFORE its change (`cq-write-failing-tests-before`). Every command below prints counts or exit
codes only; no credential value is printed, echoed or compared in the clear (compare with `[[ "$a" == "$b" ]]` or `cmp`
and print only the verdict).

### Phase 0: Measure, then RED

1. Re-run the four census commands above; record counts. Confirm `git diff --name-only origin/main...HEAD` is empty of
   source files.
2. Runtime image toolset (value-free): `docker run --rm --entrypoint sh node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d -c 'for t in openssl python3 node od tr base64; do command -v $t >/dev/null && echo "$t=present" || echo "$t=absent"; done'`
   (pull is public). Expected: `openssl`, `od`, `tr`, `base64`, `node` present; `python3` absent. If `python3` is present the D3 plugin
   choice is re-opened (python3 becomes the single primitive); if `openssl` or `od` is absent D3 fails and the slice stops on the plugin
   rows only.
3. Better Stack credential shape, value-free, so the deny-list guard cannot refuse a real value: with the Doppler token available,
   `doppler secrets get BETTERSTACK_QUERY_USERNAME -p soleur -c prd_terraform --plain | LC_ALL=C grep -cvE '[:"\\[:cntrl:]]'` must print `1` (a count, not the value);
   for `..._PASSWORD` drop the colon from the class, because a password may contain `:` and only the username may not (the Phase 3 guard encodes exactly that split). Without Doppler access, record "unmeasured" and rely on the deny-list being
   the exact set of characters that can break a quoted config value (verified against real curl 8.22 during deepen: inside `user = "..."` only `"`, a backslash
   and a newline change parsing; `#`, `=`, `;`, `%`, tab, CR, DEL and UTF-8 are delivered verbatim).
   Measure the same way, count only, the credentials the new `_bearer_ok` guards judge: `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` against `^[A-Za-z0-9._~+/=-]+$`
   (the cutover script already applies this to the same values, so a pass is expected), and `ANTHROPIC_API_KEY` against the same class. The deploy-webhook key
   takes no shape guard (it is an HMAC key; only non-empty is required), so it needs no measurement. A refused real value would leave the four probes TRANSIENT with no alert,
   so a failed measurement stops that conversion until the class is widened with evidence.
4. Infra-suite partition (D1): copy `scripts/cutover-inngest.sh` to a scratch tree with ALL 19 HMAC sites converted and run
   `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` against it read-only (do not edit the suite; do not commit the scratch copy);
   record every red row. Expected: only the two census rows named in D1. Any other red row moves that site into the held-back set.
5. `git status --short` is clean in this worktree (verified at planning). The main checkout's modified `.mcp.json` and the staged
   follow-through script seen in the session snapshot belong to the main checkout (the script is already tracked on `main`); nothing
   there is touched or staged from here.
6. Draft RED rows: the lint suite rows for the `-u` arm (they fail against the current lint), the battery rows for each conversion (they fail
   against the current scripts), and the write-env rows. Record the RED counts.

### Phase 1: Rule E `-u`/`--user` arm (commit 1)

Design in "Rule E arm". Includes fixtures, suite rows, the docstring edits (below), and nothing else. One existing fixture needs a deliberate edit:
`scripts/fixtures/shell-trace-refusal/violation-ruled-bare-assignment-pin.sh` carries `-u "svc:${SENTRY_AUTH_TOKEN}"` and its Rule D mutation row (the row that
flips it from rc 1 to rc 0) would keep rc 1 once Rule E sees the `-u`. Swap the credential flag to `--oauth2-bearer "${SENTRY_AUTH_TOKEN}"` (Rule D still classifies it through its own
credential-flag list; Rule E stays blind to it by the documented gap) and re-run every row that names the fixture. The repo-wide run after the arm is expected to
fail on exactly the three `-u` sites until Phases 4 and 9; the suite's repo-wide rows use their sandbox repo so this is not a test failure.

### Phase 2: cutover-inngest.sh and #8767 (commit 2 = backup arm; commit 3 = HMAC sites)

1. `backup)` arm per D2. Order: shape check first (`_bearer_ok "$HCLOUD_TOKEN"`, so a value holding a newline can never inject a second `::` workflow command through the mask line), then the mask line `printf '::add-mask::%s\n' "$HCLOUD_TOKEN" >&2` (stderr; stdout inside `$(...)` would swallow it), directly after the read, before the first
   `_bearer_curl`. Replace the body echo with the code plus a class hint; drop `cat /tmp/backup-action`.
2. The inline HMAC conversions for the partition Phase 0 recorded (17 expected) + the `_sig_curl` marker line (D1); the held-back sites get a one-line comment naming D1 and the follow-up issue. Locate by anchor, never by line number. Do not touch
   `apps/web-platform/infra/cutover-inngest-workflow.test.sh`; run it read-only (`bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`)
   after each commit and require its exact floor (1069) to hold unchanged.
3. Battery rows (Stage S2-A, in `tests/scripts/test-argv-bearer-sweep.sh`): backup-arm extraction driver with shim `doppler` and recording `curl`:
   mask line is the first output event and appears exactly once, before any curl call; a canary token never appears in any recorded argv or in
   stdout/stderr on the 201, non-201 and action-error paths; a response body canary never appears in output; the arm exits 1 with the code only on non-201;
   canonical-snippet oracle against `openssl dgst -hmac` (empty body and a JSON body) and the parity row (every converted copy equals the canonical string; the `-hmac` operand appears only at the held-back sites; the unset-key case is non-zero).

### Phase 3: Better Stack reader (commit 4)

`run_sql` gets the guard (evaluated under `LC_ALL=C`, as `_bearer_ok` is; the script already exports it) and `--config -`: `user = "<u>:<p>"` on a process substitution. Guard (before any curl): username non-empty, no `:`, no `"`, no `\`, no control
character; password non-empty, no `"`, no `\`, no control character; reason `control_char` when a control character is present, else `token_shape`; one marker line plus
one stderr line naming only the variable; **exit 2**. `-d "$1"` (the SQL) stays an argument (not a secret). Rows (battery Stage S2-B, shim `curl` that models `--config -` and is calibrated for `user = "..."`: add a control that compares the shim's parse with `curl --libcurl` output (`CURLOPT_USERPWD` equals the fixture pair; a hostile value yields a second `CURLOPT_URL`), and sweep bytes 0x01 to 0x7f through the real curl so the deny-list is validated by an oracle, not by the characters the author chose; the empty-credential row is pinned to exit 3 (the script's existing `credentials absent` exit, before `run_sql`), and every refusal row keys on the marker, not the exit code alone):
no `-u`/`--user`/`--user=` token in any recorded argv, neither value in argv, exactly one `user = "..."` line on stdin; refusal rows for quote, backslash, CR, LF, tab,
colon-in-username, empty, and a hostile `x" \n url = "http://evil` value: zero curl calls, exit 2, marker once, value absent from output; the existing owning suites stay
green (`tests/scripts/test-betterstack-query-archive.sh`, `tests/scripts/test-betterstack-read-classify.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh`).

### Phase 4: check-deploy-script-parity.sh and the four probes (commit 3, continued)

Canonical snippet for the HMAC (assigned with `|| SIG=""` where the script has no `set -e`, then the output must match `^[0-9a-f]{64}$` or the script refuses before curl: with python3 missing or a bad key the substitution yields an empty string and an unsigned request would otherwise be sent), `_bearer_ok` (copy of the cutover function) on both Cloudflare Access values, `--disable --noproxy '*'` first,
`--config -` with the three `header = "..."` lines on a process substitution, refusal exit 2. The three probes without a refusal preamble gain the
standard `case "$-"` block; their A/B/C and D baseline rows are removed in the same commit; every converted file must pass the **explicit-path** run (all of Rules A to E,
no baseline). Owning suites: `scripts/check-deploy-script-parity.test.sh`, `scripts/followthroughs/infra-config-activation-7220.test.sh`
(its `openssl` stub becomes unused: remove it, and make the sandbox PATH resolve the real `python3`; the stubbed `curl` keeps ignoring stdin) and
`scripts/followthroughs/inngest-soak-6178.test.sh`. Battery Stage S2-C: a new manifest for the four probes (the population derivation will now list them because they contain
`--config -`): the two without owning suites (`canary-promotion-5875`, `infra-config-fatal-channel-7220`) run dynamically under a new `probe_rows_hmac` (the existing `probe_rows` hard-codes
`Authorization: Bearer`, its header-stripped-copy `sed` and `shape_check`/`xtrace_check` take one token variable) with a fourth manifest added to `CLASSIFIED`, under an auth profile `hmac-cf` added to the shim.
The profile is NOT shape-only: the shim recomputes the digest over the recorded request body with the fixture key (through the real `openssl`, the independent oracle) and compares it, and compares both
Cloudflare Access values exactly, so a hard-coded 64-zero digest or a wrong key returns 401 (`evaluate` takes a marker list that includes the digest). The two with owning suites are delegated, but
the delegation row is not "the suite names the probe": the two suites' `curl` stubs are extended to RECORD stdin and the suites assert the exact three header lines and a 64-hex signature, so a delegated probe cannot pass while sending no credential.
The row `population: the followthrough probes listed in baseline E equal the S2-owned list` is replaced by a **disjointness invariant** (no probe is both listed in baseline E and classified as converted),
which holds in both states, so commits 3 to 8 stay green and bisectable while baseline E still lists the probes and commit 9 empties it; it keeps a positive control that the extractor returns a
followthrough row from a synthetic baseline (an empty set cannot be a broken extractor). Mutation rows run one mutant PER COPY INDEX and PER SCRIPT (the suite's `mutated_copy` replaces the first match only, so "any one of the copies" would otherwise
mutate copy 1 every time), each asserting the line range it touched, and the held-back sites are pinned by arm anchor (`registry-probe)`, `doublefire-probe)`), not by a count of 2. The recording `python3`/`openssl` shims are
added per row through `RUN_EXTRA_PATH`, never by widening the battery's fail-closed `REALBIN` set; Stage S2-D (sweeper) lives in `scripts/sweep-followthroughs.test.sh` because the battery's `gh` stub exits 97.

### Phase 5: sweep-followthroughs.sh hop (commit 5)

D6. Rows in `scripts/sweep-followthroughs.test.sh` (existing T8/G3 stay) and battery Stage S2-D. Exit criterion: all existing rows green and the new rows green, else apply the documented fallback
and say so in the PR body.

### Phase 6: Anthropic key sites (commit 6)

D7 for `compound-promote.sh` and `learning-retrieval-bench.sh`. Guard: the key passes `_bearer_ok`-equivalent (`[A-Za-z0-9._~+/=-]`, non-empty) or the script exits 1 with the
marker; in the bench the refusal is raised before the first `anthropic_paraphrase` call and is never converted to `(API_ERROR)`. Rows: recording mock curl (the suites' own mock is
extended to record argv and stdin): key in stdin config, absent from argv, payload capture still works, hostile key refused with zero calls. Remove the A/B/C and D baseline rows if the
explicit-path run is clean.

### Phase 7: plugin scripts (commit 7)

1. `lib/hmac-sha1-b64.sh` (one function, no `exit`, returns non-zero on failure) sourced by `x-community.sh` and `x-setup.sh` in place of the `openssl dgst -hmac` line. Constraints from the security review: the function saves and turns off allexport on entry and restores it on return (under `set -a` its locals would otherwise be exported into the `openssl`, `od` and `tr` children's environment; `x-setup.sh` closes `set -a` before signing but variables sourced under `-a` stay exported), sets `LC_ALL=C` locally so `${#key}` counts bytes, carries its own xtrace refusal (it can be sourced without the caller's preamble), and never feeds key-derived data through a here-string or heredoc (bash older than 5.1, including macOS 3.2, writes those to a temp file); a grep row on the file bans both. The oracle also runs with `set -a` active and an env-recording `openssl` shim (no key-derived name in any child environment);
   `require_openssl` stays (still needed for `openssl rand` and the digest).
2. `write-env` validation and the Discord positional change (D8), `SKILL.md` and header/usage text. `plugins/soleur/skills/community/SKILL.md` is 17,447 bytes and has no entry in `plugins/soleur/test/skill-body-budget.json` (lifecycle skills only), and its description is not touched, so
   `SKILL_DESCRIPTION_WORD_BUDGET` is not in play; edit body lines only and re-run `bun test plugins/soleur/test/components.test.ts`.
3. Rows in `plugins/soleur/skills/community/test/community-argv.test.sh`: HMAC oracle (key lengths 0, 1, 20, 63, 64, 65, 96, 200 x four messages, plus `6`x64, backslash/quote/space keys, and a key
   containing `=` and `%`), recording `openssl` shim (no `-hmac`/`-macopt`, no key bytes in any argument across a full `fetch-metrics`, `post-tweet` and `validate-credentials` run), a full signed request still
   reaches the curl shim with the same `Authorization: OAuth ...` structure, write-env hostile-value rows per script (`$(touch SENTINEL)`, backtick, newline-plus-assignment, `"`, `;`, space): refused, no sentinel
   file, `.env` byte-identical before and after, marker once; round trip (a valid write then `source` yields the same values byte-for-byte; mode 600); discord second positional refused with exit 64, argument not echoed,
   env-var path works. The oracle adds RFC 2202 (HMAC-SHA1) vectors, and the cutover-snippet oracle adds RFC 4231 (HMAC-SHA256) vectors, as a non-openssl anchor, plus the empty-key behaviour stated (the runner snippet exits non-zero), trailing-newline bodies, and a base64-shaped key with `+/=`; the "oldest bash" run asserts the binary differs from the default or reports `not exercised`, and, when docker is available, the oracle is also executed inside the pinned `node:22-slim` image (its bash is the hosted one). Must-PASS rows use realistic shapes, not only the canonical (a Better Stack password with `$ # ; !` checked by `USERPWD` equality; an `.env` value with `+/=:%`).
   Floors: `community-argv.test.sh` ends in an EXACT `-ne 411` check (its comment records that `-lt` would grow the deferred ledger 47 to 48), so bump 411 in the same commit as the new rows and raise `EXPECTED_TESTS=187` in the same suite family; inner counters (32 oracle cases, 17 converted copies, the hostile-class count) guard the loops, because a row floor cannot see a loop that runs zero times.
4. Hosted-path canary: an invocation of `x-community.sh fetch-metrics` under `env -i PATH=<dir with only bash, openssl, jq, curl-shim, coreutils>` (no python3, no node) succeeds against the shim, proving
   the plugin path does not need an interpreter the image lacks.

### Phase 8: docs and tracking inputs (commit 8)

Create the follow-up issues FIRST (the ADR amendment cites the `op=backup` one by number), then the lint docstring (below), the runbook row split and the ADR-241 amendment, worded "classified Tier B; currently ungated and non-conformant: the tier census cannot see this script-level read, so nothing enforces the classification until #N lands". The marker-telemetry comment in `apps/web-platform/server/git-lock-marker-telemetry.ts` is NOT edited (review: it would add an `apps/web-platform/**` edit, tsc and vitest for a stale comment; the lint docstring records the wider emitter set instead). `bunx vitest run apps/web-platform/test/git-lock-marker-telemetry.test.ts` still runs in Phase 9 because `x-setup.sh` becomes a new emitter. Check rotation tracking (CPO condition 4): `git grep -n 'O13' knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
and issue #9294 already cover rotating the deploy HMAC, the Cloudflare Access pair and the Hetzner read/write token; file a new issue only if a credential in this slice is in neither.

### Phase 9: verification, then the baseline-only commit (commit 9)

Ordering (D10), each step a command with an exit code:

1. Commit 1 to 8 are on the branch; working tree clean.
2. `git fetch origin main && git merge origin/main` (resolve conflicts; if another PR touched baseline E take `origin/main`'s copy of both baseline files and regenerate). This is the "merge commit exists" step.
3. `python3 scripts/lint-shell-trace-credential-refusal.py --write-baseline-e`.
4. Edit `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv` in the same change: delete the five converted rows, add the two `apps/cla-evidence` rows (LC_ALL=C order); the file's header says the table must equal the baseline's own order.
5. Remove the A/B/C and D baseline lines of every converted file (see "Baseline and ceiling rows").
6. Run the full gate list (Acceptance, "Pre-merge") on the **committed** tree; commit step 3 to 5 as the baseline-only commit; `git status --short` shows nothing afterwards (S1 forgot to add the regenerated baseline).
7. Push once. If `origin/main` moves before merge, repeat steps 2 to 6 for the baseline hunk only.
8. Smoke on the branch before marking ready (the workflow files exist on the default branch, so `gh workflow run <file> --ref <branch>` is valid; a NEW workflow file would not be): (a) the sweeper with its real `dry_run` input (`gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`; measured: it has that input and maps it to `DRY_RUN`); (b) one workflow that calls `betterstack-query.sh`: measured candidates are `scheduled-zot-restart-loop.yml` (dispatchable, no inputs, but it files issues on a signal gap, so NOT read-only), `registry-zot-inventory.yml` (inputs `action`, `tracker`) and `inngest-config-drift.yml` (dispatchable); read the chosen one end to end first and use it only if its dispatch path performs no write. If none qualifies, the owning suites with the recording `curl` shim are the pre-merge proof and the first post-merge apply or scheduled read is the live proof, stated in the PR body. Never dispatch `cutover-inngest.yml` ops that write.

### Phase 10: PR and tracking

PR title `fix(security): argv-credential sweep S2 ...`; first body line names the plugin release trigger and states that no `apps/web-platform/infra/**` file is in the diff; `Ref #9597`, `Ref #7797`, `Closes #8767`;
no plan or spec file paths in the body and no `*-soak-*` script names (an earlier PR was falsely blocked from `gh pr ready` by the follow-through gate matching a script named like that); the +2/-5 baseline arithmetic;
the honest review-coverage statement. Issues to create (each with a milestone and `gh issue edit --add-blocked-by` where a blocker is known): (1) `op=backup` environment gate + O10 re-plumb (workflow expression and pinned infra suite; blocked by nothing, deadline before O10), (2) the two cla-evidence R2 `--user` sites (dated, owner: CLA-evidence), (3) heartbeat-URL path secrets in the three host files (S4/S5 class, ties to the infra apply notice), (4) the two held-back cutover probe-arm HMAC sites plus the one-line edit of the two tool-census regexes in the infra suite (carries operator notice; rides S4/S5), (5) `linkedin-setup.sh` `write-env` value validation (same class as D8), (6) record on the S3 tracker that `scheduled-inngest-health.yml` and `git-data-cutover.yml` discard the Better Stack reader's stderr (`2>/dev/null`), so a credential refusal (exit 2) reads as `__UNREADABLE__` / a generic retry failure there; S3 surfaces the stderr as `::warning::` when it converts those files. Issue (4) carries a due date and an owner. Comment on #9597: S2 done, corrected measurements (cutover 0 header sites / 19 HMAC of which 17 converted; baseline 29 files / 62 sites after S2), open items 1 and 2 resolved with evidence, item 3 re-armed, heartbeat decision; and on #7898 that the two `"$CURL_BIN"` sites are converted and the command-word blind spot remains.

## Rule E arm: `-u` / `--user`

**Property.** No curl command carries a basic-auth credential pair (`-u`, `--user`) in its own argument list, except in files listed in baseline E by exact path and count.

**Design.**

- Constants (named, one alternate per line so the suite can delete them): `E_USER_FLAG = ^(?:--user|-[A-Za-z]*u)$` (value is the NEXT word; covers `-u`, `-sSu`, `--user`), `E_USER_ATTACHED = ^(?:-u(?=.)|--user=)` (value glued: `-uname:pw`, `--user=name:pw`).
  Case-sensitive, so `-U`/`--proxy-user` (a different credential) and `--url` do not match.
- Reading sites mirror the header vocabulary's: `_e_scan` sets a new `f["user"]`; `check_rule_e` call-level and wrapper-site checks add a reason: "basic-auth credentials (`-u`/`--user USER:PASSWORD`) are an argument of this curl, readable by every local user in /proc/<pid>/cmdline and `ps`"; the second-credential rule treats `-u` as a credential, so `-u` plus an argv `apikey:` reports both. Array-held and wrapper-forwarded `-u` flow through the existing `_inline_arrays` / wrapper tables.
- The pinned finding grammar `credential header on curl argv` is **unchanged** (the suite's `E_MSG_RE` and its self-check key on it); the reason clause carries the `-u` wording. Only curl invocation segments are scanned, so `sort -u`, `docker run --user` and `git -u` are not read.
- Docstring edits in the same diff: remove "`-u`/`--user` detection is NOT here" and the `-u`/`--user` item of VOCABULARY GAPS; add a USER ARM paragraph; update EVASION SHAPES (the `$CURL_BIN` bullet now says the two live sites were converted in S2 and the spelling stays blind); add the heartbeat-URL decision (D9) and the R2 SigV4 census (D5) to the KNOWN BLIND SPOTS / baseline text.
- Expected census effect, to be confirmed by the first repo-wide run after the arm: exactly three new offenders (`betterstack-query.sh`, `bootstrap.sh`, `r2-conditional-put.sh`).

**Test rows** (`scripts/lint-shell-trace-credential-refusal.test.sh`, fixtures under `scripts/fixtures/shell-trace-refusal/`, each a separate file with a compliant first member, per the S1 lesson on combined fixtures):
violation: literal `-u "$U:$P"`; glued `-u"$U:$P"`; `--user "$U:$P"`; `--user="$U:$P"`; bundled `-sSu "$U:$P"`; `-u` inside a `local a=(...)` array declared plain, with a conditional `+=(`; `-u` forwarded through a file-local wrapper; `-u` plus an argv `apikey:` (second-credential); a SECOND curl in the same file after a compliant one;
a multi-line command with `--aws-sigv4 ... \` then `--user "$ID:$SECRET"` on a continuation line (the cla-evidence shape).
must-PASS (not the canonical): `--config -` with `user = "..."` on a process substitution; `-K -`; `--config <(...)`; `sort -u`, `docker run --user`, `curl --url`, `curl -U proxy` (proxy credential, a pinned gap: xfail row expects 0).
mutation rows: delete `E_USER_FLAG`, delete `E_USER_ATTACHED`, drop the `_e_scan` assignment, drop the wrapper-site read: each reddens a named fixture. The repo-wide sandbox row seeds a baseline-E count one lower than live for a `-u` file and expects the equality failure.

## Baseline and ceiling rows

| Artifact | Leaves in this change | Enters in this change | Totals |
|---|---|---|---|
| `lint-shell-trace-credential-refusal-e.baseline.txt` (regenerated, Phase 9) | `scripts/check-deploy-script-parity.sh` 1, `canary-promotion-5875.sh` 1, `infra-config-activation-7220.sh` 1, `infra-config-fatal-channel-7220.sh` 1, `inngest-soak-6178.sh` 1 | `apps/cla-evidence/infra/bootstrap.sh` 1, `apps/cla-evidence/scripts/r2-conditional-put.sh` 1 (census widening, tracked) | 32/65 -> 29/62 |
| `rule-e-census-ceiling.tsv` (hand-edited, same commit) | the same five rows | the same two rows | 32/65 -> 29/62; header comment updated |
| `lint-shell-trace-credential-refusal.baseline.txt` (A/B/C) | `canary-promotion-5875.sh`, `infra-config-activation-7220.sh`, `infra-config-fatal-channel-7220.sh`, and `compound-promote.sh` / `learning-retrieval-bench.sh` if their explicit-path run is clean | none | -3 to -5 |
| `lint-shell-trace-credential-refusal-d.baseline.txt` | `canary-promotion-5875.sh`, `infra-config-activation-7220.sh`, `infra-config-fatal-channel-7220.sh`, `learning-retrieval-bench.sh` if clean | none | -3 to -4 |
| `cutover-inngest.sh`, `betterstack-query.sh`, x/bsky/discord scripts | none: never in baseline E | none | n/a |

No row is added or raised for any converted file. The two entering rows are the only growth and are listed with their issue in the PR body; a reviewer gate, not a machine one, holds the ratchet shrink-only (baseline E is edited in the same diff as the code).

## Files to Edit

- `scripts/cutover-inngest.sh`, `scripts/betterstack-query.sh`, `scripts/check-deploy-script-parity.sh`
- `scripts/followthroughs/canary-promotion-5875.sh`, `scripts/followthroughs/infra-config-activation-7220.sh`, `scripts/followthroughs/infra-config-fatal-channel-7220.sh`, `scripts/followthroughs/inngest-soak-6178.sh`
- `scripts/sweep-followthroughs.sh`, `scripts/compound-promote.sh`, `scripts/learning-retrieval-bench.sh`
- `plugins/soleur/skills/community/scripts/x-community.sh`, `x-setup.sh`, `bsky-setup.sh`, `discord-setup.sh`; `plugins/soleur/skills/community/SKILL.md` (only if the usage text mentions the changed form; it does not today, so expect no edit)
- `scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-trace-credential-refusal.test.sh`, `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`, `scripts/lint-shell-trace-credential-refusal.baseline.txt`, `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`, `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`
- Tests: `tests/scripts/test-argv-bearer-sweep.sh`, `plugins/soleur/skills/community/test/community-argv.test.sh`, `scripts/check-deploy-script-parity.test.sh`, `scripts/followthroughs/infra-config-activation-7220.test.sh`, `scripts/followthroughs/inngest-soak-6178.test.sh`, `scripts/sweep-followthroughs.test.sh`, `scripts/compound-promote.test.sh`
- Docs: `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`

Path-glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above is a literal; verified with `git ls-files --error-unmatch` for each at implementation start. Prefixes that must be
ABSENT from the diff: `apps/web-platform/infra/`, `.github/workflows/apply-web-platform-infra.yml`, `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, `.mcp.json`.

## Files to Create

- `plugins/soleur/skills/community/scripts/lib/hmac-sha1-b64.sh` (D3; one function)
- Lint fixtures under `scripts/fixtures/shell-trace-refusal/`: `violation-argv-user-literal.sh`, `-attached.sh`, `-long.sh`, `-long-eq.sh`, `-bundle.sh`, `-array.sh`, `-wrapper.sh`, `-second-credential.sh`, `-multiline-sigv4.sh`, `compliant-stdin-user-config.sh`, `compliant-stdin-user-dash-k.sh`, `outofscope-nonyurl-user-flags.sh`, `outofscope-proxy-user.sh` (each synthesized, no real token; no YAML fixture)
- No new test suite: rows join existing registered suites, so no new `test-all.sh` registration, orphan-suite or vacuity-floor wiring is needed; every suite that gains rows keeps its floor in the lower-case "anti-vacuity floor" shape (`-lt N`).

## Open Code-Review Overlap

None. Checked 2026-10-08: `gh issue list --label code-review --state open` (200 limit) searched with `jq --arg path` for every file above and the runbook; no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`scripts/cutover-inngest.sh` (20 argv sites; finishes #8767: HTTP code only never the body, ::add-mask:: the Doppler-read token, decide the tier row for create_image)" [brief] | D1, D2, Phase 2 | mapped (corrected to 19 HMAC sites; header sites already done) |
| 2 | "`scripts/betterstack-query.sh` (-u basic auth, plus the -u/--user arm in Rule E in the SAME diff)" [brief] | D5, Phase 1, Phase 3, Rule E arm | mapped |
| 3 | "`scripts/check-deploy-script-parity.sh`, the four `scripts/followthroughs/*` baseline-E entries" [brief] | Phase 4, baseline table | mapped |
| 4 | "the HMAC helper" [brief] | D3 (canonical snippet + oracle, plugin function) | mapped (interpretation recorded: a pinned snippet, not a sourced library, on runners) |
| 5 | "OAuth1 `openssl -hmac` signing keys in x-community.sh / x-setup.sh" [brief] | D3, Phase 7 | mapped (bash, not python3, because the image lacks python3) |
| 6 | "the sweep-followthroughs.sh env hop" [brief] | D6, Phase 5 | mapped |
| 7 | "\"$CURL_BIN\" sites in compound-promote.sh and learning-retrieval-bench.sh" [brief] | D7, Phase 6 | mapped |
| 8 | "write-env value validation in bsky-setup.sh / discord-setup.sh" [brief] | D8, Phase 7 | mapped |
| 9 | "discord-setup.sh's write-env webhook-URL positional argument" [brief] | D8, Phase 7 | mapped |
| 10 | "heartbeat-URL probes (convert or document)" [brief] | D9 | mapped (document) |
| 11 | "a per-site census of every argv site in each S2 file (measured with grep, not carried over from the issue)" [brief] | Census section | mapped |
| 12 | "the tier-row decision for create_image in cutover-inngest.sh" [brief] | D2 | mapped |
| 13 | "the Rule E `-u/--user` arm design with test rows" [brief] | Rule E arm | mapped |
| 14 | "an explicit statement of which baseline-E / census-ceiling rows leave in this change" [brief] | Baseline and ceiling rows, Phase 9 | mapped |
| 15 | "Check whether any S2 file is under apps/web-platform/infra/** (merging those fires a production apply) and flag it prominently" [brief] | MERGE EFFECTS, D1 | mapped (no S2 file; its owning suite is, avoided by design) |
| 16 | "OPEN ITEMS TO CHECK, NOT ASSUME: (1) ... (4)" [brief] | Research Reconciliation rows | mapped |
| 17 | "S3-S5 are out of scope" [brief] | Cut List, Phase 10 follow-ups only | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `x-setup.sh` write-env validation | — | inferred — justification: the identical `echo "KEY=${VAL}" >> .env` shape followed by `source` leaves the exploit class open in a sibling that is edited anyway for ask 5; cut-able without affecting any other item (review trimmed `linkedin-setup.sh`, which stays a tracked follow-up) |
| `_sig_curl` marker line | "On a malformed credential print one value-free line" | asked |
| seeding the two cla-evidence rows | "plus the -u/--user arm in Rule E in the SAME diff" | asked (consequence of the arm: the arm newly sees them; conversion is out of the file list) |
| ADR-241 amendment and runbook split | "decide the tier row for create_image" | asked |
| `plugins/.../lib/hmac-sha1-b64.sh` | "Header-less secrets (HMAC keys, OAuth1 signing keys) go through python3 reading the key from the environment" | asked, with the primitive changed for the plugin (D3) |
| per-surface refusal exit codes | "exit 1" | asked, with a documented deviation (D4): 2 where 1 is a different failure class |
| `compound-promote.test.sh`, the two probe suites | "Pre-push gates to run (owning suites directly ...)" | asked |
| the follow-up issues (backup gate, cla-evidence, heartbeat) | "heartbeat-URL probes (convert or document)" and `wg-when-deferring-a-capability-create-a` | asked / required by the repo rule |

### Split Assessment

- Subsystems touched: 5 — `scripts`, `plugins/soleur`, `tests`, `knowledge-base`, `apps/web-platform` (one comment line)
- Planned files: 30 edited + 14 created | Estimated changed lines: ~1,700 (about 900 of them test rows and fixtures)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — **all three exceeded**
- Recommendation: **single PR, by the brief** ("Do ONE slice per PR ... this run is S2 only"), with the commit boundaries of D11 so a reviewer can read or revert per blast radius. If CI shows two red cycles from the plugin rows, the pre-agreed seam is to move commits 7 (plugin scripts) into an S2b PR, which does not change the other eight because the plugin files share no code with the runner scripts. The slice's size is driven by tests (conversion diffs are 1 to 6 lines each).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --name-only "$(git merge-base HEAD origin/main)"..HEAD` contains no path under `apps/web-platform/infra/`, neither `.github/workflows/apply-web-platform-infra.yml` nor `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, and no `.mcp.json`.
- [ ] Explicit-path `python3 scripts/lint-shell-trace-credential-refusal.py <every converted file>` exits 0 (all Rules A to E, no baseline), and the repo-wide run exits 0 with baseline E equal to the live set. Totals are DERIVED, not hard-coded: record `origin/main`'s baseline totals at the merge step (32 files / 65 sites at planning) and require post = pre - 5 files - 5 sites + 2 files + 2 sites (29 / 62 at planning). A mismatch means another PR moved rows or a new offender appeared: investigate before accepting the regenerated file. The five converted rows are absent and exactly the two cla-evidence rows are added; the ceiling table equals the regenerated baseline's own order (`diff` of the two path/count column sets is empty).
- [ ] `bash scripts/lint-shell-trace-credential-refusal.test.sh` exits 0 with every `-u` row above, the mutation rows red as designed, and the ceiling table equal to baseline E.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0 including: the converted-copy parity row (17 expected, the 2 held-back sites named), the HMAC oracle, the backup-arm rows (mask first and once, no body, no token in argv or output), the Better Stack rows, the four-probe manifest, the sweeper-hop rows, the two Anthropic rows; and a **canary sweep** row (CPO condition 1): a run of each converted script under a fake credential `CANARY-<random>` with every shim in failure modes (200, 401, 500, timeout, malformed JSON) never contains the canary in stdout or stderr; each such row first asserts a recorded shim call in the 200 mode (a script that exits at a precondition never touched the credential and proves nothing).
- [ ] `bash plugins/soleur/skills/community/test/community-argv.test.sh` exits 0 (HMAC oracle, recording `openssl` shim, write-env rows, discord positional refusal, no-interpreter hosted canary).
- [ ] The owning suites exit 0 unchanged where not listed as edited: `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` (floor 1069 untouched, **not edited**), `scripts/check-deploy-script-parity.test.sh`, `scripts/sweep-followthroughs.test.sh`, `scripts/compound-promote.test.sh`, the two probe suites, `tests/scripts/test-betterstack-query-archive.sh`, `tests/scripts/test-betterstack-read-classify.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh`.
- [ ] Drift and meta guards: the grep-q pipe guard test (`bash .claude/hooks/grep-q-pipe-guard.test.sh`), `scripts/lint-supabase-deprecated-endpoints.sh`, `scripts/lint-orphan-test-suites.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash plugins/soleur/test/fixture-env-adoption.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 lint-skill-body-budget.py` and `lint-rule-bodies.py --check` with `--base` the merge-base, `bunx vitest run apps/web-platform/test/git-lock-marker-telemetry.test.ts`, `tsc --noEmit` in `apps/web-platform`, gitleaks. Never `scripts/test-all.sh` locally.
- [ ] Zero `-hmac` operand remains in the S2 conversion targets (the 14 non-test source files under Files to Edit, except the two held-back cutover sites named in D1); zero `x-api-key` header on argv in `compound-promote.sh` and `learning-retrieval-bench.sh`; `git grep -nE -- '-hmac' -- scripts plugins/soleur/skills/community/scripts .github/actions ':!*.test.sh' ':!tests' ':!scripts/fixtures' ':!scripts/lint-shell-trace-credential-refusal.py'` lists only `.github/actions/dispatch-web-redeploy/track.sh` (2, S4). The scope excludes `knowledge-base/`, so this plan's own text does not satisfy or defeat the count (measured at planning: 19 in cutover + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 2 in track.sh; after S2 expect 2 in cutover and 2 in track.sh).
- [ ] `grep -c 'openssl dgst -sha256 -hmac' scripts/cutover-inngest.sh` prints 2 (exactly the two held-back probe-arm sites, each carrying the D1 comment) and the 17 snippet copies are byte-identical; the `::add-mask::` line precedes the first `_bearer_curl HCLOUD_TOKEN` in the `backup)` arm; no `$(cat /tmp/backup-` in any `::error::` line.
- [ ] The runbook row is split and ADR-241 carries the dated amendment naming the follow-up issue number; the five follow-up issues of Phase 10 exist (`gh issue view <N> --json state,title,milestone`).
- [ ] PR body: first line names the web-platform release trigger and the absence of infra-path edits; `Ref #9597`, `Ref #7797`, `Closes #8767`; the baseline arithmetic; no plan/spec paths; no `*-soak-*` script names; the word "partial" next to `Closes #8767` with the open `op=backup` environment gap stated (the brief mandates `Closes`; the gap is real and a closed issue must not hide it); the residual of the two held-back cutover sites (same secret on `openssl` argv for milliseconds on a manual read-only dispatch, tracked with a date and an owner); which sweeper form shipped (launcher or documented `env -i`); the read-only smoke run URLs; the commit-per-blast-radius table.
- [ ] Read-only smoke (Phase 9 step 8) succeeded: the Better Stack reader through one read-only workflow on the branch ref and a sweeper `DRY_RUN=1` dispatch.

### Post-merge (verified by outcome)

- [ ] The release run for the merge commit succeeds (`gh run list --workflow web-platform-release.yml --branch main --event push --limit 5 --json conclusion,headSha`), and `/health` reports the merge's build.
- [ ] No infra apply was triggered by the merge commit: `gh run list --workflow apply-web-platform-infra.yml --branch main --event push --limit 5 --json headSha --jq '.[].headSha[0:10]'` does not list the merge commit's first 10 characters (the `--event push` filter is required).
- [ ] The first post-merge scheduled run of each converted surface is healthy (CPO condition 5): the daily follow-through sweeper (the marker check is a count, not a visual read: `gh issue view <N> --json comments --jq '[.comments[-1].body] | map(select(contains("SOLEUR_CREDENTIAL_REFUSED"))) | length'` is 0 for each of the four probes' trackers, since a refusal is also TRANSIENT), the community-monitor X fetch (MANDATORY gate: force one via the `soleur:trigger-cron` skill if its event is allowlisted; if it is not, the postmerge step waits for the next scheduled run and the work is not reported done before it; a green Sentry monitor alone can mean the cron was not due), and the next apply or a read-only dispatch that reads Better Stack. Any `SOLEUR_CREDENTIAL_REFUSED` line from a hosted run is a defect.
- [ ] Re-armed open item 3: the first scheduled content-publisher run after this merge posts to Bluesky and X (or reports its normal no-post state); its fallback issue body carries no refusal marker.

## Observability

```yaml
liveness_signal:
  what: the repo-wide Rule E run stays green on main with baseline E equal to the live set (29 files / 62 sites after S2) and no S2 file ever re-enters it; the refusal marker is absent from hosted run output
  cadence: every CI run on push to main and on every PR (the lint suite and the sweep battery are required shards)
  alert_target: a red required test shard on the PR or on main. Hosted refusals are NOT claimed to be mirrored or paged: the marker extractor is wired only to the agent PostToolUse hook (MARKER_RE comment), so a hosted cron's captured stderr is visible only in its own run output and the content-publisher fallback issue body
  configured_in: scripts/test-all.sh (suites scripts/lint-shell-trace-credential-refusal, tests/scripts/argv-bearer-sweep, scripts/sweep-followthroughs) and .github/workflows/ci.yml
error_reporting:
  destination: stderr of the refusing script (one fixed value-free marker line plus one human line naming the variable), the CI log, and for followthrough probes the tracker comment
  fail_loud: every refusal exits non-zero with the code of D4 (never 0; 2 where 1 is a different failure class); the lint exits 1 on any unlisted offender or changed count and 2 when it cannot evaluate
failure_modes:
  - mode: a converted script refuses a valid credential (shape guard too strict, python3 or openssl missing where it runs)
    detection: battery must-PASS rows with real credential shapes, the no-interpreter hosted canary, the Phase 0 image toolset and credential-shape measurements, and the read-only smoke dispatches; in production the marker line on stderr of the failing step (observability layer 6, `workflow run log` with the `::error::` annotation for CI and cutover; the tracker comment for sweeper probes, which is the only reader of that surface; layer 7 `cli-stdout-artifact` for the setup scripts an installed user runs, where the refusal writes nothing and is re-runnable, so the durable artifact is the committed battery row, not a log)
    alert_route: red PR checks before merge; post-merge, the red job or step, the cron monitor, and the first-run checks in Acceptance
  - mode: a persistent refusal keeps a followthrough probe TRANSIENT forever (same as a persistent 403 today)
    detection: the tracker comment carries the marker on every sweep; unchanged class, stated in D4
    alert_route: the tracker comment stream; escalation is the sweeper's existing stale handling (not changed by S2)
  - mode: the Hetzner token or a response body reaches the public run log
    detection: backup-arm extraction rows (mask is the first event, canary token and body canary absent from all output on every path)
    alert_route: red battery before merge
  - mode: a new argv credential (including basic auth) appears in a script or workflow
    detection: repo-wide equality (offender not in baseline E, or a changed count) fails the lint shard
    alert_route: red required check on the PR
logs:
  where: CI logs of the test shards and of the workflows that call the converted scripts; the PR body records census counts
  retention: GitHub Actions default
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py scripts/betterstack-query.sh scripts/cutover-inngest.sh scripts/check-deploy-script-parity.sh
  expected_output: "OK:"
```

(An explicit-path run bypasses the baselines, so it prints `OK:` only when the files are clean on their own; it ran in 0.6 s on two files during planning, well inside the 15 s cap. The repo-wide run took 5.3 s on the unmodified tree; Phase 1 re-times it after the arm lands.)

## Guard Contract

### Guard 1 — Rule E `-u`/`--user` arm and the baseline ratchet

**Property.** No curl command in a tracked `*.sh`, workflow or composite-action YAML, or cloud-init YAML carries a basic-auth pair (`-u`, `--user`) in its own argument list, except in files listed in baseline E by exact path and count.

**Assembly.** Reading chokepoint: `_e_scan` (one place classifies the words after `curl` or after a wrapper name) feeding `check_rule_e`'s two sites (call-level and wrapper-site) and the second-credential rule; the flag spellings are the two constants `E_USER_FLAG` and `E_USER_ATTACHED`. Entry points: repo-wide run (baseline equality), explicit paths (baseline bypassed), YAML feeder, `--changed`. Members are not a list of today's three files: the arm quantifies over every curl segment the existing scanner already yields. Comparison chokepoint: baseline E equality plus the ceiling table.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `E_USER_FLAG` (or `E_USER_ATTACHED`) | RED: the literal/bundle fixtures (or the glued/`=` fixtures) report 0 and fail |
| 2 | Drop the `f["user"]` assignment in `_e_scan`, or stop dispatching the arm so the lint reports zero users on a corpus that contains three | RED: every `-u` fixture reports 0, and a sandbox repo-wide row whose baseline lists a `-u` file at its true count fails equality (live count 0) |
| 3 | Add a second `-u` curl after a compliant first in the same fixture (and, in the repo-wide sandbox, a second site in a baselined file) | RED: two findings expected; a check that stops at the first reports one |
| 4 | Make the arm read `docker run --user` / `sort -u` (loosen command-position scoping) | RED: the out-of-scope fixture expects 0 |
| 5 | Remove the wrapper-site read | RED: the wrapper-forwarded `-u` fixture reports 0 |
| 6 | Harness row: replace the lint under test with a stub that prints `OK` and exits 0 | RED: the suite's positive control and the rows that expect rc 1 fail; plus a must-PASS row that is NOT the canonical (`-K -`, `--config <(...)`) proving the arm does not reject everything |
| 7 | Seed baseline E with a count lower than live for a `-u` file, or add a `-u` site to a listed file | RED: equality names the file |

**Anchor.** Baseline E and the ceiling table live in the same diff as the code they gate, so the lint proves consistency, not integrity. What outside the commit must also move for a weakening to pass: the ceiling table (a second file whose edit a reviewer sees; the suite fails until both move), and the reviewer gate named in the lint docstring. A `>= N` floor is not used; set identity (path and count) is.

### Guard 2 — credential-off-argv battery rows (guard-before-curl, oracle, parity, canary)

**Property.** For every converted call site, a malformed credential produces zero outbound requests, one value-free marker and the exit code of D4; a well-formed one reaches the transport on stdin or the environment only; no canary secret appears in any recorded argv or in stdout/stderr on any path.

**Assembly.** The chokepoint is the recording shims (`curl`, `python3`, `openssl`, `doppler`, and `env` for the sweeper) that every row runs the real script under, with `env -i` and a fail-closed PATH. The `python3` and `openssl` shims record argv and then exec the REAL binary (a fake that returned a canned digest would agree with the consumer's own reading of the contract); the `curl` shim is the battery's existing one, calibrated by its real-curl oracle (control C3), extended with the `hmac-cf` auth profile; sites are derived by `git grep` (anchors in the Census), not by a hand list, and a population row fails when a derived S2 site has no row. Members that must each have a row: 19 cutover HMAC copies (parity), the `backup)` arm (three paths), the Better Stack reader, the parity script, four probes, the sweeper hop, two Anthropic sites, two plugin signing sites, four `write-env` writers, the Discord positional.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the shape guard after the curl call (or delete it) in any one converted script | RED: the hostile-value row sees a curl call or an INJECTED config line |
| 2 | Put the key back on an argument in one of the 17 converted cutover copies (a `-hmac` spelling outside the two held-back sites) | RED: parity row (copies differ, `-hmac` operand present at a non-held-back site) |
| 3 | Add one more inline copy that differs by one byte after the compliant ones | RED: the parity row is per-copy, not first-copy |
| 3c | Run the plugin HMAC function under `set -a` with an env-recording `openssl` shim; add a here-string or heredoc over key-derived data to the lib | RED: a key-derived name in a child environment; the grep row on `<<<`/`<<` |
| 3b | Run a script with `python3` absent from PATH (parity script and a probe, neither has `set -e`) | RED if an unsigned request is sent; expected: refusal marker, exit 2, zero curl calls |
| 4 | Move `::add-mask::` after the first curl call, or print the body on non-201 | RED: backup-arm rows (mask not first; body canary in output) |
| 5 | Make the recording `curl` shim stop recording stdin, or stop being auth-gated | RED: harness rows (`bearer-not-on-stdin`, stripped-copy reaches PASS) |
| 6 | A suite that dispatches zero rows (population derivation returns empty) | RED: the anti-vacuity floor (`-lt N`) and the derived-population row |
| 7 | Replace the oracle's synthetic key with the canonical-only case, or make the bash HMAC wrong for a 65-byte key only | RED: the oracle sweeps lengths 0, 1, 20, 63, 64, 65, 96, 200 and a `6`x64 key; one wrong length fails |
| 8 | Reorder (not delete) the sweeper's validation after the launcher | RED: a row where a reserved name in `secrets=` must be refused before any value is read |

**Anchor.** The synthetic keys are generated inside the suite; the committed oracle is the OTHER implementation (`openssl dgst -hmac`, which is only ever run with a synthetic key in a test), so a regression in the primitive cannot be masked by editing a stored expected value. Counts (19 copies, row floors) are paired with set identity (the parity row compares bytes of each copy).

### Guard 3 — `write-env` value validation

**Property.** No value written to `.env` by a setup script can execute or split when the file is later sourced, and a refused value leaves the existing file byte-identical.

**Assembly.** The `cmd_write_env` functions are the only writers (`git grep -n 'cmd_write_env'` under the community scripts directory finds four); every `echo "KEY=${VAL}" >> "$env_file"` in them is a write site. A population manifest classifies each writer as validated (`bsky-setup`, `discord-setup`, `x-setup`) or deferred with its issue (`linkedin-setup`); an unclassified writer reds the row. Chokepoint: the validate-all-before-first-write block in each function.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the validator call in one of the four functions | RED: that script's hostile-value row creates the sentinel or changes `.env` |
| 2 | Validate only the first value (a hostile second value passes) | RED: rows put the hostile value in position 2 and in the optional webhook variables |
| 3 | Move validation after the first write | RED: the byte-identical-before/after row |
| 4 | Widen the allow-list to include `$` or a space | RED: sentinel rows for `$(...)` and a spaced value |
| 5 | Harness: a stub `source` that never executes; a suite whose sentinel path is wrong | RED: a positive-control row proves the sentinel mechanism fires on a known-bad `.env` |
| 6 | Round-trip must-PASS with a real-shaped value that differs from the fixture canonical (long handle, URN with colons) | PASS expected (guards against a validator that rejects everything) |

**Anchor.** Set identity: the writer list is derived by `grep`, not counted; a fifth writer added later is unclassified and the population row fails; moving `linkedin-setup` out of the deferred bucket requires its validator row.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO sign-off; threshold single-user incident). Legal/GDPR: no regulated-data surface and no new processing activity (credential transport only), so the gate is not invoked; marketing/sales/finance/support: none.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Inline python3 x19 accepted with three guards (output format parity: the old `sed` extraction is gone and the digest is bare hex; payload bytes via `sys.stdin.buffer`; a grep sentinel against a returning `-hmac`), all in D1. The bash HMAC for the plugin was called the weakest part and `node -e` suggested; kept with the reasons in D3 (no new runtime dependency for installed users, 35+ oracle cases, hosted no-interpreter canary), reversible behind one function. Mask placement before first use and code-only error output accepted; the CTO suggested printing the Hetzner `error.code`/`message`, declined: the brief and #8767 say code only. Exit 2 can coincide with curl's own rc 2 (init failure): noted, the marker line on stderr discriminates, same as the existing destination-pin refusal. A persistent TRANSIENT never alerts: unchanged class, stated in D4. An interim guard for the ungated `op=backup` write was suggested: rejected because the dispatched ref supplies the script (not a boundary); recorded as a dated follow-up with the O10 dependency. `.env` escaping versus a validator: the validator here is an allow-list, fail-closed, validate-all-before-write, not a reject-list. Recommendations adopted: a canary test on the hosted `x-community.sh` path; a dated tracking issue for the two cla-evidence rows. No blocker; Phase 0 re-measures openssl/node/python3 in the image with `docker run`.

### Product (CPO)

**Status:** reviewed
**Assessment:** Threshold `single-user incident` confirmed (a leaked deploy HMAC with the Cloudflare Access pair, or the Hetzner token, is a platform-wide compromise; the run log is public). The Discord change is acceptable as a hard refusal with a migration message that names the variable, shows a copy-pasteable example, exits with a distinct non-zero code, never echoes the argument, and updates `SKILL.md`, the header and the usage text in the same PR (D8). Verdict: approved, subject to five conditions, each mapped: (1) negative canary test over stdout and stderr including error paths (Guard 2, Acceptance); (2) mask before first use and no body echo (D2, Phase 2); (3) separable commits isolating the Hetzner, deploy and Cloudflare Access items (D11); (4) rotation tracking check (Phase 8); (5) first post-merge smoke of hosted X posting and the sweeper (Acceptance, post-merge). The Discord plugin release note is deferred to the release flow.

## Test Scenarios

1. `backup` arm, 201: mask is the first output event, one curl call with the token on stdin, rc 0 after the poll; non-201: exit 1, the HTTP code in `::error::`, a canary response body absent from every stream; action error: no body, the action id present.
2. Cutover HMAC copy: output equals `openssl dgst -hmac` for an empty body and a `$PAYLOAD` JSON; unset key -> non-zero and `_sig_curl` refusal marker; the Cloudflare Access value with a quote or newline -> rc 2, zero requests.
3. Better Stack reader: well-formed pair -> one request with `user = "..."` on stdin and no `-u` in argv; each hostile shape -> exit 2, zero requests, marker once; existing archive/classify suites unchanged.
4. Parity script and four probes: 200 only with the three headers on stdin; no `openssl` on PATH needed; refusal exit 2; the sweeper comment shows the marker and no value.
5. Sweeper hop: a forwarded secret reaches the probe, an unforwarded one does not, a value with `=`, newline and 100 KB survives, `env` is never exec'd, no value in the `python3` argv.
6. Anthropic sites: key on stdin, payload capture intact, hostile key refused with zero calls and exit 1 (never `(API_ERROR)`).
7. Plugin: HMAC oracle matrix, recording `openssl` shim, full signed request shape, no-interpreter PATH run, three write-env hostile-value cases (bsky, discord, x) and a round trip, Discord second positional refused with exit 64. The refusal's most natural repair (what a stuck agent types next: export `DISCORD_WEBHOOK_URL_INPUT` and re-run, or hand-edit `.env`) must itself be handled: the env-var path passes the allow-list and writes mode 600; re-passing the positional is refused again; a value that fails the allow-list is refused on the env path too.
8. Lint: each `-u` fixture, the out-of-scope fixtures, the mutation rows, the repo-wide sandbox rows (count-lower and added-site), and the real-corpus census (three new offenders before Phases 3 and 9, none after).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this one carries `single-user incident` and `requires_cpo_signoff: true`.
- The infra suite sets `WEBHOOK_SECRET` as an unexported shell variable in its render drivers; a conversion that reads the key from the ambient environment instead of a per-command prefix passes in production and fails there (D1).
- `HMAC_KEY="$WEBHOOK_SECRET" python3 ...` under `set -x` would print the key: every edited script keeps its xtrace refusal; the three probes that lack one gain it in the same commit (Rule A is an explicit-path failure otherwise).
- The follow-through contract reads exit 1 as FAIL. A refusal that exits 1 in a probe would close or flag a tracker on a credential typo.
- `bs_read_classify` maps exit 1 to "blame DOPPLER_TOKEN"; the Better Stack reader refuses with 2.
- `curl --config -` consumes stdin: a body must be `-d "$x"` (non-secret only) or `@file`; never `--data-binary @-` in the same call. The Anthropic request body stays on `-d`.
- Use a process substitution, never `printf | curl --config -`: under `pipefail` a consumer that never reads stdin returns 141 (S1 measurement).
- New suites that create a git fixture must use `git_fixture_env "$dir"` from `plugins/soleur/test/lib/git-fixture-env.sh`; none is planned, but a sandbox repo for the repo-wide lint rows is exactly that shape.
- Never commit a pathological YAML fixture; generate it into the test's temp copy (CodeQL's extractor overflows).
- Baseline regeneration happens only after the merge commit exists; a baseline generated earlier is rejected by equality as soon as another PR moves a row. Do not hand-edit baseline E; edit only the ceiling table by hand.
- No new `SOLEUR_*` marker is added, but `x-setup.sh` becomes a NEW emitter of the existing `SOLEUR_CREDENTIAL_REFUSED` (its `write-env` validator prints it), and the telemetry drift guard walks `skills/*/scripts/*.sh`: run `git-lock-marker-telemetry.test.ts` (Phase 9). The emitter list in `MARKER_RE`'s comment is left stale on purpose (a comment-only edit would add `tsc`, vitest and an `apps/web-platform/**` change); the Rule E docstring records the wider emitter set. The sourced HMAC function must not print the marker (it returns non-zero; the caller decides the exit code and prints).
- If an agent returns the same status line twice, run that seat's checks yourself with `git diff`; do not resume a third time.
- Portability of the plugin function (it ships to installed users' hosts): external binaries are `openssl`, `od`, `tr`, `base64`; shell features are `printf -v`, `${var:i:2}`, arithmetic XOR and `printf '\xHH'`. All exist on macOS's bash 3.2 and BSD `od`/`base64` (digest output is 28 characters, so GNU line wrapping never applies); there is no `timeout`, `xxd`, `sed -i` or `readlink -f` in it. The oracle suite runs it under the oldest `bash` on the runner as well as the default.
- New battery rows must not use `! grep -q ...` or `printf | grep -q ...` for a negative or early-exit check: a negation folds grep's rc 2 (pattern did not compile) into "no match", and the pipe form flakes under `pipefail`. Use a count compared with `==`, or a here-string, and pin the pattern with a compile pre-check.
- The discoverability probe (three files) prints `OK:` only after the conversions: on the unchanged tree `check-deploy-script-parity.sh` still reports its violation, so the probe was executed during planning on the two files that are already clean (it printed `OK: 2 scanned file(s)` in 0.6 s) and is re-run on the final tree in Phase 9.
