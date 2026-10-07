---
title: "fix: argv-bearer sweep Tier 3, guard-first slice (YAML + non-Bearer lint arms, plugin scripts) and review SKILL.md body extraction"
date: 2026-10-07
slug: argv-bearer-sweep-tier3-guard-first-slice-and-review-skill-extraction
branch: feat-one-shot-argv-bearer-sweep-tier3
issue: 9597
closes: []
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-10-07
**Gates run:** User-Brand Impact (4.6), Observability (4.7, discoverability probe executed read-only and shape-checked against the verb gate), PAT-shape (4.8), Guard Contract (4.11, `lint-guard-contract.py` green, adequacy read done), Scope Check (4.12). Not triggered: UI wireframe (4.9), Encryption Posture (4.10, no store or connection), Downtime (4.55, S1 touches no serving surface; S5 contract requires a no-replace plan), network-outage (4.5, no trigger term).
**Reviewers (report-only, parallel):** architecture-strategist, security-sentinel, code-simplicity-reviewer, spec-flow-analyzer, observability-coverage-reviewer, test-design-reviewer, and a verify-the-negative pass. Findings applied below; the full plan-review panel was not run as a separate step.

### Key Improvements

1. S1's production claim was wrong: any `plugins/soleur/**` edit fires `web-platform-release.yml`, and `bsky-community.sh` runs hosted from `scripts/content-publisher.sh`. The PR-body line, User-Brand Impact, P4 and the acceptance rows now say so, with a positive post-merge release check.
2. The review extraction shrank from the whole 250 KB Defect Classes section to three conditional migration/RLS bullets (4.4 KB, about 3 KB of headroom), after the simplicity review showed the whole-section read would add about 60k tokens to every review.
3. The YAML arm reads `run:` bodies through PyYAML (a raw-line feeder misses folded and inline `run:` steps), with raw lines kept only for cloud-init; PyYAML is imported lazily, an unparseable file exits 2, and the vocabulary is a superset (`Authorization:` of any scheme) with `-u` deferred to S2.
4. The bsky body recipe no longer leaks the password on `jq`'s argv (jq reads it from its environment, per the `configure-auth.sh` precedent); a `jq` shim row is added.
5. `discord-setup.sh` cannot pass an explicit-path run until it gains the xtrace refusal and loses its A/B/C baseline line; its array miss is an `_array_body` declaration-regex bug shared with Rule D, not a vocabulary gap.
6. The guard contract was rebuilt around what the suites can actually drive (`sbx_repo` for repo-wide rows, one fixture per read site and per alternate, pinned message grammar and `E_MSG_RE`, counter-hung floors).

### New Considerations Discovered

- `gh run list ... --branch main` without `--event push` misleads; with it, the last push apply on main is 2026-10-06 17:13Z and none followed three later infra-touching merges (the parent's open item 1).
- PR #9632 is no longer a draft and may merge during S1's CI cycle; baseline hunks are adjacent, so the plan prescribes a final baseline-only commit and regenerate-on-rebase.
- Other argv credentials outside Rule E: `x-access-token:` git remote URLs (`bump-inngest-bootstrap-pin.sh`), `doppler --token`, `openssl -hmac` signing keys (about 30 sites, including the OAuth1 keys in `x-community.sh` and `x-setup.sh`), `jq --arg`.
- Exposure model table (runner, host, user machine) added; helper sourcing creates no new injection class (no `pull_request_target` in S3/S4), and gets a CODEOWNERS row.

## Overview

Tier 2 and the residual non-Bearer credentials merged on 2026-10-06 (`f68395e2fc`, PR #9654). What is
left on #9597 is far larger than one safe PR, and it is the part where the blast radius changes:
workflow YAML runs on GitHub-hosted runners, a CI-only verification surface, and several of the files
fire a PRODUCTION push apply or release when merged. This plan therefore does three things.

1. **Decides first** how the Rule E lint grows (Decision D1), because every later conversion PR is
   measured by it.
2. **Plans the first PR (Slice S1) as a bounded, guard-first slice** and specifies the later slices
   (S2 to S5) at contract level, each with its own tracking issue, so #9597 stays the tracker and
   nothing is silently dropped. S1 carries `Ref #9597` and `Ref #7797`; no slice before the last one
   carries a `Closes`.
3. **Makes room in `plugins/soleur/skills/review/SKILL.md`** (476,997 bytes against a 477,000 ceiling,
   3 bytes of headroom) by extracting one block to `references/`, then adds the Sharp Edge about review
   seats that stall on a tool call (item 4 of the brief).

Out of scope here and recorded only as ops follow-ups owned by the parent session: (1) why the
push-triggered infra apply did not fire after the Tier 2 merge, and the operator-gated production
apply; (2) web-2 tracking. Coordinator note (measured 2026-10-07): web-2 was replaced 2026-10-06
19:28Z from main at `2efc8025ff`, which is BEFORE the Tier 2 merge, so web-2 still carries the old
copy of the monitors and bootstrap and the item-2 re-check stands for its next replacement.

## Decisions (recorded first, as the brief requires)

**D1. The lint grows by two arms, not three.** Rule E (`scripts/lint-shell-trace-credential-refusal.py`)
gets (a) a YAML arm and (b) a non-Bearer credential vocabulary. It does NOT get a "guard runs before
curl" static check.

- *YAML arm: yes, by extracting `run:` bodies, not by feeding raw YAML lines.* First prototype: raw
  YAML lines through `check_rule_e` reproduced the hand classification (35 argv sites in 16 files, zero
  false positives over the 9 comment/echo and 11 already-stdin hits that a plain `git grep` counts), but
  a second prototype with synthetic YAML shapes showed raw lines are blind to a folded scalar (`run: >-`)
  and to an inline `run: curl ...` (single-line, double-quoted-escaped) step: 0 of 4 flagged, against 3 of
  3 for literal blocks, list-item continuations and `${{ }}` interpolation. A guard over a structured
  language must lex that language's layer first (`plan-sharp-edges` entry on line scanners). So the arm
  loads each workflow and composite action with PyYAML (`yaml.safe_load`, already the approach of
  `scripts/lint-workflow-run-body-syntax.py`, which also skips steps whose `shell:` is not bash) and runs
  Rule E over every `run` string value at any depth. Cloud-init files are different: their scripts are
  `write_files[].content` literal blocks and `runcmd` entries, `cloud-init.yml` is Terraform-templated and
  does not parse as YAML, and a third prototype (extract `write_files` content and `runcmd`) found 3 of the
  4 `cloud-init-registry.yml` sites while raw lines found 4 of 4; so `cloud-init-*.yml` uses raw lines
  (their embedded shell is literal-block by construction). A `.github/**` file PyYAML cannot parse is
  exit 2, the lint's existing "cannot evaluate" contract (ADR-157), never a skip and never a silent
  fallback: an unparseable workflow is already broken. `import yaml` happens lazily, only when a
  `.github` YAML file is about to be scanned, because the lint is stdlib-only today and its `--changed`
  step (advisory, `ci.yml`) never scans YAML; PyYAML is already imported by the lints that `scripts/test-all.sh`
  runs on the ubuntu runner (`lint-workflow-run-body-syntax.py`), so the repo-wide suite has it. Measured parity for the two-path design: 31 Bearer argv sites
  in the `.github/**` files by extraction plus 4 in cloud-init by raw lines = 35; widened vocabulary
  49 + 4 = 53 YAML sites. Scope of the arm: Rule E only; Rules A, B, C and D key on a shebang/preamble and
  stay `*.sh`.
- *Non-Bearer vocabulary: yes, and as a superset.* One named constant replacing `E_BEARER` at its five read
  sites (held-name capture, array capture, header scan, call-level check, wrapper-site check): any
  `Authorization:` header (every scheme: `Bearer`, `Bot`, `Basic`, `Token`, `Api-Key`), `CF-Access-Client-(Id|Secret)`,
  `X-Signature-256` and `X-API-Key`. A superset beats an enumerated scheme list: the repo has zero real
  sites for `Basic`, `Token`, `Private-Token` or non-stdin `Api-Key`, so enumerating them is speculative,
  and `Authorization:` alone covers `Bot`. Prototype census with the enumerated schemes over every tracked
  `*.sh` and YAML: 86 sites in 34 files (33 sites in 12 `.sh` files, 53 sites in 22 YAML files); Phase 0
  re-measures with the final constant. `-u`/`--user` detection is NOT in S1: its only real site is
  `scripts/betterstack-query.sh:352`, which S2 converts, so S2 adds the arm and the conversion in one diff.
  Bodies and URLs carrying a secret (bsky password JSON, heartbeat-URL path secrets, `x-access-token:`
  git remote URLs) stay census-only: whether a `-d` operand or a URL is a secret is not decidable from
  syntax.
- *"Guard runs before curl": no.* The lint's own docstring records why Rule A is a prologue rule and not
  a before-the-first-bind rule: ordering relative to a bind is undecidable statically (function hoisting,
  `source`, quoted heredocs). The property is pinned instead by behaviour: per-site refusal rows and a
  "guard moved after curl" mutation row in `tests/scripts/test-argv-bearer-sweep.sh`. For YAML the guard
  duplication problem disappears by construction (D3: one shared helper, one `_bearer_ok`).
- *`--changed` stays `*.sh`-only.* If YAML were in `--changed`, any unrelated edit to a baselined
  workflow (including `apply-web-platform-infra.yml`, 4.4 KB under its byte gate) would be forced to
  fully remediate in that PR. Growth in YAML is still blocked: the repo-wide run (a required `test`
  shard through `scripts/test-all.sh`) compares baseline E by equality on path AND count, and explicit
  paths bypass the baseline, so a conversion PR proves its files clean by naming them.

**D2. Split: five slices, S1 first.** One PR cannot finish Tier 3 safely. S1 is the bounded slice.
Slices S2 to S5 are specified in "Slice Contracts" and filed as issues in Phase 6 of S1.

**D3. Workflow YAML sites call a tested shared helper, host-baked files stay inline.** For steps on a
checked-out runner the conversion is `. scripts/lib/bearer-curl.sh` plus a one-line call, not an inline
`--config -` expansion at each site. Reasons, all measured: byte budget (`apply-web-platform-infra.yml`
485,630 bytes vs the 490,000 gate; an inline conversion adds bytes per site, a helper call is
byte-neutral), one `_bearer_ok` definition instead of up to 55 copies, and one place a battery can test
the transport. The earlier Cut List entry "no shared library" is not contradicted: it was scoped to
host scripts, which cannot source repo files at runtime. Cloud-init embedded scripts and host scripts
keep the inline form. The helper is created in S3 (its first user), not in S1. One edit to it rewrites the
transport of 12 to 17 workflows at once, so S3 adds a `/scripts/lib/bearer-curl.sh @deruelle` line to
`.github/CODEOWNERS` (peer `scripts/lib/*.sh` files are pinned the same way) and states the source-trust
rule: the helper is only ever sourced from the job's own checkout of the trusted ref, never from an
artifact download path or an untrusted `head_sha`. Measured: none of the S3/S4 workflows uses
`pull_request_target`; the only `workflow_run` is `web-platform-release.yml` (`branches: [main]`, with a
runtime re-check), and fork pull requests get no secrets, so sourcing the helper opens no new injection
class.

**D4. HMAC key off argv uses python3 reading the key from the environment.** `openssl dgst -hmac
"$KEY"` has no stdin or env form. Verified equal byte-for-byte on a fake key (python `hmac` and openssl
produce the same digest, including the empty-body case the deploy-status calls sign). The key then
travels in `execve` envp (readable only by the owner and root through `/proc/<pid>/environ`) instead of
the world-readable `cmdline`. Runner-side scripts use it in S2/S4; the on-host `ci-deploy.sh` waits for
a measured python3-on-host row (the cloud-init package list names only `curl fail2ban jq nftables`;
`cloud-init` itself is Python, but that is a claim to verify, not assume). Review evidence closes the
host question: `soleur-host-bootstrap.sh` already runs `python3` at boot ("a cloud-init dependency, always
present") and the image is Ubuntu 24.04, so a `command -v python3` guard in the converted script is the
remaining proof. Four rules for the conversion: (1) the signature is validated against `^[0-9a-f]{64}$` and a
miss is a refusal before curl, because every existing site ends in a pipeline with `sed` that would
otherwise yield an empty signature and send an unsigned request; (2) the key is set with a per-command
prefix (`KEY="$secret" python3 -c ...`), never `export`, since an exported key reaches every later child
(`curl`, `jq`, `doppler`), and `set -x` is banned around the call because xtrace prints inline
assignments; (3) the key is read with `os.environb` so a non-UTF-8 byte cannot raise; (4) the residual is
stated honestly: `/proc/<pid>/environ` is readable by the same uid and root, which is why this is a
reduction from world-readable `cmdline`, not elimination.

**D5. Review SKILL.md extraction takes the conditional migration/RLS cluster of the Defect Classes list,
not the whole section.** The new bullet needs about 1.1 KB, so the extraction only has to free about 1.5
KB. Three non-contiguous bullets of `### Defect Classes This Review Reliably Catches` (SKILL.md lines
1216, 1222, 1224: "Legal-disclosure prose hallucinated against the actual migration body", "Stale plan-time
RLS-policy enumeration drift", "RLS-policy-expression edit breaks exact-string verify/ sentinels ...") are
about migrations and RLS policies, total 4,402 bytes plus separators, and are only relevant when a diff
touches `supabase/migrations/` or RLS policies. They move verbatim to
`references/defect-classes-migrations.md`, linked from the list the way `references/wfs.md` already is
(`- [migration and RLS classes](./references/defect-classes-migrations.md)`, with the load condition in the
reference's own header line). Expected headroom afterwards: about 3 KB (3 + 4,405 - about 250 link line -
about 1,100 bullet). Alternatives, measured: (A) the whole 250,787-byte section behind an unconditional read
(rejected: it adds a roughly 60k-token read to every review at the synthesis step to fix a 1 KB problem
and changes every review's behaviour; the first draft of this plan chose it and a simplicity pass reversed
it; that draft had also dismissed the small cluster by comparing its size with the whole section instead
of with the 1.1 KB need); (C) `### 2. Rate Limit Fallback` (rejected: it carries Gate 2a,
"can agents be spawned at all", evaluated before EVERY spawn, so it is not conditional); (D) `### Sharp
Edges: Review Agent Limitations` (rejected: the stall guidance must stay in the lead's working set while
the panel runs). Precedent: `references/wfs.md`, and the reachability test in `components.test.ts`.

**D6. `Closes` policy.** Each slice PR closes its OWN slice issue (S2 to S5) and never the tracker; S2 also
closes #8767; only S5 carries `Closes #9597`. Blocked-by edges: S3 and S4 blocked by S2 (the HMAC helper is
built in S2, and S3 converts `canary-status` and `scheduled-inngest-health`, which carry HMAC sites), S4 by
the S3 helper, S5 by S3 and S4. The original #9597 body is copied into a comment before it is restated. `#8767` is
partly stale (its argv half is already fixed: `scripts/cutover-inngest.sh` `backup)` calls `_bearer_curl`,
a stdin form); its remaining halves (response body echoed, no `::add-mask::`) plus the tier question are
finished in S2, which carries `Closes #8767`. `#7898` (Rule D backlog, 67 files, plus the YAML and
`CURL_BIN` scope gaps) is NOT finished by any slice: S1 closes only the Rule E part of its section 3, so
S1 comments on it and leaves it open. `#7797` stays `Ref` everywhere; closing it is a decision after S5
(label `security/leak-suspected`).

## Research Reconciliation: brief and issue text vs. codebase

| Brief / issue claim | Reality (origin/main `e4cd9bd48c`, measured 2026-10-07) | Plan response |
|---|---|---|
| Tier 3 is "21 workflow YAML files / 55 sites; apply-web-platform-infra.yml has 12" | `git grep -nE 'Authorization: Bearer' -- '.github/**/*.yml' 'apps/**/cloud-init*.yml'` = 21 files / 55 hits, but only **35 are argv sites in 16 files**: 11 hits are already the stdin form (`printf ... \| curl -H @-` / `header = ...`) and 9 are comments or `echo` runbook text. `apply-web-platform-infra.yml` has **6** argv sites, not 12. | Plan sizes work from the 35; record both numbers on #9597. |
| Rule E "sees only `Authorization: Bearer`", Tier 3 is Bearer | The non-Bearer argv surface in YAML is a separate 18 sites: webhook HMAC plus Cloudflare Access pair (`apply-deploy-pipeline-fix.yml` 6, `restart-inngest-server.yml` 4, `web-platform-release.yml` 3, `deploy-inngest-image.yml` 2, `scheduled-inngest-health.yml` 1, `canary-status.yml` 1) and `x-api-key` (`anthropic-preflight/action.yml`). | Included in the YAML arm census and in S4/S3 contracts. |
| `scripts/cutover-inngest.sh` appears once on #9597 ("HMAC and Access pair") | It has **20** `X-Signature-256` plus CF-Access curl sites on argv, in a 3,200-line script. | Its own slice (S2); not folded into S1. |
| #8767: op=backup puts HCLOUD_TOKEN on curl argv | Already stdin: `backup)` calls `_bearer_curl HCLOUD_TOKEN ...` (lines ~1791, ~1805). Still true: the non-201 branch echoes `$(cat /tmp/backup-body)`; no `::add-mask::` after the `doppler secrets get`; the tier row question stands (create_image is a write). | S2 finishes the remaining halves; `Closes #8767` there. |
| #9597: `discord-setup.sh` carries `Authorization: Bot` | Yes, but inside a `local curl_args=(...)` array; a prototype run of the widened vocabulary did NOT flag it. | RED row in Phase 1: the widened arm must flag array-held non-Bearer headers (the five `E_BEARER` read sites include the array-capture one). |
| #9597: "heartbeat-URL probes (secret in the URL path)" | Not detectable from header/flag syntax. | Census-only, decided in S2 (no lint arm). |
| `ci-deploy.sh` is a webhook-HMAC argv site | `openssl dgst -hmac "$secret"` at line ~359 and `-H "X-Signature-256..."` at ~370; it runs ON the host through the deploy webhook, so the python3-on-host row (D4) gates it. | S4 contract. |
| Env hop in `scripts/sweep-followthroughs.sh` is a credential on argv | `env -i NAME=<secret>` puts the value on `env`'s argv until `env` calls `exec` (microseconds) and in its own xtrace line. Tested: `exec -c` cannot carry the variable; a subshell that unsets everything outside an allowlist and then `exec`s the probe keeps the secret in envp only. | S2 contract, with a decision row (convert if the sweeper's test battery stays green, otherwise document). |
| Merging a plugin-only PR mutates nothing in production | `web-platform-release.yml` triggers on push to main for `plugins/soleur/**` except `docs/` and `test/`, and `scripts/content-publisher.sh` runs `bsky-community.sh` HOSTED (line ~763), so S1's plugin script edits ship to the content-publisher host on merge. | Declared in the PR body's first line and in User-Brand Impact; Phase 2 keeps bsky refusals non-zero and the post-merge check reads the release run. |
| Any merge touching `apps/web-platform/infra/**` is harmless | `apply-web-platform-infra.yml` triggers on push to main for `apps/web-platform/infra/**`, for itself, and for `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Merging any PR that edits those fires a PRODUCTION apply. | S1 edits none of those paths (acceptance row). S4/S5 declare the apply-on-merge effect and gate it. Measured caveat: `gh run list --workflow apply-web-platform-infra.yml --branch main --event push --limit 5` shows the newest push runs at 2026-10-06 13:51Z to 17:13Z (the default listing without `--event push` is dominated by older rows and misleads), and no push run follows the three later infra-touching merges (`f68395e2fc` 20:18Z, `2ef72cd651` 20:45Z, `88acf996aa` 21:07Z), so the Tier 2 merge did NOT fire it; that is the parent session's open item 1. S4/S5 plan as if the trigger fires and treat a non-fire as unexplained, not as safety. |
| `lint-skill-body-budget` ceiling can be raised | The ceiling is read from the merge base and ratchets down only; raising it is a separate reviewed PR. | Extract first (D5); the new bullet is the only addition to SKILL.md. |

## Research Insights

**Premise Validation.** #9597, #7797, #8767 and #7898 are OPEN with no linked closing PR. The Tier 2 PR
(#9654) is merged. PR #9632 (`feat-one-shot-a3-credential-hardening-egress-probe-nic-guard`, no longer a
draft as of 2026-10-07T07:45Z, merge state BLOCKED, so it may merge during S1's CI cycle) edits `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`, the A/B/C
and D baselines, `scripts/guard-vacuity-floor.test.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh`: a
textual-conflict hotspot for S1, not an overlap in scope. Draft PR #9674 is this branch. No ADR rejects
the stdin-config mechanism (the prior sweep's learning records it as the established form; ADR-202 is
the carried self-refusal ADR this lint family descends from).

**Measurements (commands).**

- Bearer census: `git grep -nE 'Authorization: Bearer' -- '.github/**/*.yml' 'apps/**/cloud-init*.yml'`: 55
  hits / 21 files. Classified by a scratch script into 35 argv (16 files), 11 already-stdin (8 files), 9
  doc (3 files). Re-run `check_rule_e` over the raw YAML lines: 35 sites / 16 files, identical.
- Widened vocabulary prototype (`E_BEARER` rebound in a scratch copy): 86 sites / 34 files; per-file
  table recorded in Phase 0 and again on #9597.
- Trigger class per YAML file (from each file's `on:` block): push-to-main with production effect:
  `apply-web-platform-infra`, `apply-deploy-pipeline-fix`, `apply-inngest-rls` (also schedule),
  `apply-github-infra`, `restart-inngest-server`, `deploy-inngest-image`, `web-platform-release`
  (also `workflow_run`); self-listed in their own push paths: `apply-web-platform-infra`,
  `apply-inngest-rls`, `restart-inngest-server`, `deploy-inngest-image`. Dispatch/schedule/pull_request
  only: `git-data-rung2-rehearsal`, `workspaces-luks-cutover`, `scheduled-terraform-drift`, `rule-audit`,
  `git-data-cutover`, `scheduled-inngest-health`, `scheduled-prod-version-drift`, `canary-status`,
  `board-status-sync` (pull_request), `sentry-audit-gate` (pull_request).
- Byte budget: `wc -c .github/workflows/apply-web-platform-infra.yml` = 485,630;
  `plugins/soleur/test/workflow-file-size.test.ts` gates 490,000; GitHub refuses above 512,000 (ADR-231).
  `apply-deploy-pipeline-fix.yml` 177,302; `web-platform-release.yml` 170,734; `cloud-init-registry.yml`
  184,967. Precedent for relocation: the file header already points rationale prose at
  `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`.
- `wc -c plugins/soleur/skills/review/SKILL.md` = 476,997; ceiling 477,000 in
  `plugins/soleur/test/skill-body-budget.json` (row `review`).
- HMAC: python3 `hmac.new(key_from_env, body, sha256)` equals `openssl dgst -sha256 -hmac` (fake key,
  non-empty and empty body). Host python3 availability: NOT yet verified.

**Exposure model (security review, measured).** No self-hosted runners exist (`runs-on:.*self-hosted`
returns nothing) and there is no `hidepid` on the hosts.

| Surface | Who can read argv | Window | Ranking and why S1 goes first |
|---|---|---|---|
| GitHub-hosted runner | the job's own steps and any third-party action in the job; log and xtrace leakage (Doppler-read values are not auto-masked) | the curl lifetime on a single-tenant, ephemeral VM | lowest: attacker must already run code in the job |
| Web host | any local account (no `hidepid`); not containers (separate PID namespace) | the curl or `openssl` lifetime, repeated on every deploy poll | highest value: the webhook HMAC key and the CF-Access pair authorize deploy commands on prod (`ci-deploy.sh` `fan_out_to_peers` is the single highest-value site) |
| Installed user's machine (plugin scripts) | anyone on a possibly shared machine, an unknown audience | the curl lifetime | the only surface where the attacker is a stranger and the only one that needs no infra gate, hence S1 |

The ordering is therefore "stranger-reachable and ungated first", not "highest value first"; the host
HMAC sites are S4 because they need the production gate.

**Institutional learnings applied** (from `knowledge-base/project/learnings/`):

- `2026-10-06-a-refuse-before-send-guard-turned-a-paging-401-into-a-silent-skip.md`: a shape guard
  changes WHICH failure fires; per converted site, read the alert predicate of the marker the refusal
  emits (a `SEND_SKIPPED` never pages). Anti-vacuity floors must be written `-lt N` with the lower-case
  text `anti-vacuity floor`; run lints on a committed tree; a panel seat whose last block is a tool call
  has not delivered (the origin of item 4).
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`
  (conversion pattern: process substitution, `--disable --noproxy '*'` first, guard before the call).
- `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`: no heredocs in `run: |`;
  Doppler-fetched secrets are NOT auto-masked by Actions (explicit `::add-mask::`).
- `2026-03-19-github-actions-env-indirection-for-context-values.md`: `${{ }}` through `env:`, never
  interpolated into `run:` (the 35 argv sites already use `$VAR` forms; keep it so).
- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so`
  (byte ceiling, comment prose alone crossed it).

**Property List.**

- P1. No credential-bearing header, `-u` operand, or secret body appears on the argv of a curl in a
  converted script or workflow step.
- P2. A malformed credential never reaches curl, and the refusal reports through a sink that pages
  where the old failure paged.
- P3. The set of offenders can only shrink: any new argv credential in a `*.sh` or workflow/cloud-init
  YAML file turns the repo-wide lint red.
- P4. A conversion that fires a production apply or release on merge is declared and gated before it
  merges. S1 cannot fire an infra apply; it DOES fire the plugin release deploy (any
  `plugins/soleur/**` edit outside `docs/` and `test/` triggers `web-platform-release.yml`), and says so.
- P5. `review/SKILL.md` stays under its ceiling with the stall Sharp Edge present in the lead's working
  set, and every moved byte is still reachable and unchanged.

**Cut List** (mechanism, property, what already covers it).

- "Guard runs before curl" static lint check: P2 is covered by per-site refusal rows plus a
  guard-moved-after-curl mutation row; the static check is undecidable (Rule A's docstring).
- A byte-identity parity lint for the ~55 inlined `_bearer_ok` copies: P2 for host scripts; for YAML the
  shared helper removes the duplication; for host scripts a parity test is filed with S4 (follow-up
  issue), not built here.
- A hand-written YAML or cloud-init parser: PyYAML `run:` extraction (the `lint-workflow-run-body-syntax.py` precedent) plus raw lines for the templated cloud-init files covers the corpus; measured both ways in D1.
- A `--changed` YAML mode: forces unrelated PRs to remediate and endangers the apply workflow's byte
  budget; the repo-wide equality run already blocks growth.
- Raising the review SKILL.md ceiling: ceilings only ratchet down (ADR-229).

## User-Brand Impact

**If this lands broken, the user experiences:** (S1) a Discord or Bluesky community script exiting
non-zero or silently skipping a post for an installed user, or the repo-wide lint going red on every PR
until the baseline is fixed; (later slices) a release, deploy or infra apply failing or a monitor going
quiet. S1 changes no file under `apps/web-platform/infra/**`, so it cannot fire an infra apply; it does edit
`plugins/soleur/**`, so merging it triggers the web-platform release, which ships the changed
`bsky-community.sh` to the content-publisher host (`scripts/content-publisher.sh` runs it hosted), so a
bad bsky conversion would also stop the scheduled Bluesky post.

**If this leaks, the user's workflow is exposed via:** the argv of a short-lived curl on a runner or an
installed user's machine (a local process listing shows a Discord bot token, a Bluesky app password, a
webhook HMAC key or a Cloudflare Access pair). S1 removes the vector for the four community scripts and
makes every remaining instance a counted, shrink-only baseline entry; the residual in S2 to S5 is
visible in the baseline until converted.

- **Brand-survival threshold:** aggregate pattern

## Architecture Decision (ADR/C4)

No architectural decision: a lint scope extension and call-site conversions behind an existing,
ADR-backed mechanism. Test applied: would an engineer reading the ADRs and C4 be misled after this ships?
No; no actor, system, store or access relationship changes (checked against `model.c4`, `views.c4`,
`spec.c4` for the external systems named here: GitHub Actions runners, Cloudflare Access, Better Stack,
Hetzner API, Discord and Bluesky APIs are already modeled or are plugin-side clients outside the
product boundary; the cardinality gate `plugins/soleur/test/c4-count-parity.test.sh` is run in Phase 6
because S1 adds no workflow or monitor). The D3 shared helper and D5 extraction are recorded in this plan
and in the S3 PR description, not in an ADR; the architecture review suggests a short ADR-202 amendment
when the S3 helper lands (the lint's YAML scope and `--changed` decision extend that mechanism), and S3
should take that as an in-scope task rather than a follow-up.

## Implementation Phases (S1, this PR)

Write the failing rows first (cq-write-failing-tests-before). One push at the end: a CI cycle is about 35
minutes and a push resets it. Do not run `scripts/test-all.sh` locally (it queues behind sibling
worktrees); run the owning suites directly.

### Phase 0: Census and RED rows

- Re-run the lint's own census: `python3 scripts/lint-shell-trace-credential-refusal.py --census` (baseline
  state) and the scratch widened-vocabulary census; write the per-file table (path, group, site count)
  once, in the PR body and the #9597 restatement (not as a third copy in the spec dir). Re-measure; do not
  copy this plan's numbers.
- Add RED rows first to `scripts/lint-shell-trace-credential-refusal.test.sh` (see Guard Contract) and
  to `plugins/soleur/skills/community/test/community-argv.test.sh` (one row per converted call site).
  That hermetic PATH-shim suite already exists as the sibling precedent for `linkedin-setup.sh`,
  `x-community.sh` and `x-setup.sh` (it drives the scripts end to end and records curl argv and stdin
  config); extend it for the four scripts, and add to `tests/scripts/test-argv-bearer-sweep.sh` only the
  rows that need a shim feature the community suite lacks. Confirm the suite is registered (run
  `bash scripts/lint-orphan-test-suites.sh` once files are tracked).
- Owning-test census for the four scripts (strict sense: a suite that names them): none today. Three
  suites touch them indirectly and must stay green: `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`,
  `apps/web-platform/test/server/inngest/cron-community-monitor-allowlist.test.ts` and
  `test/content-publisher.test.ts` (which mocks `bsky-community.sh`).
- Diff the Rule D census before and after the array-declaration fix below (Phase 1), so no new
  Rule D finding appears outside baseline D. Measured by the test-design review: the declaration fix alone
  moves Rule D from 14 to 15 files, adding exactly `discord-setup.sh`, which therefore must be fully
  Rule D-clean in the same diff (baseline D has no entry for it).
- Shim and suite extensions, each its own commit with its own rows (so a shim that accepts too much
  cannot make later rows vacuous): (a) `tests/scripts/test-argv-bearer-sweep.sh` is hard-wired to
  Bearer (`evaluate` greps `header = "Authorization: Bearer <tok>"`, the shim's `have_auth` matches the same):
  parameterise both by scheme and add a row asserting the exact line `header = "Authorization: Bot <tok>"`
  plus a mutation that swaps `Bot` for `Bearer` and must go RED (Discord rejects `Bearer`); (b) the shim's
  `-d|--data|--data-binary` arm ignores its value and has no code that reads `--data-binary @file`: make it
  record the body file's content and `stat` mode at curl time, add a `fail7` transport-failure mode, and
  calibrate against real curl with `--libcurl` (control C3) so `--data-binary @file` keeping CR/LF where
  `-d @file` strips them is pinned; (c) a `jq` shim recording `jq`'s argv; (d) the population row at
  `tests/scripts/test-argv-bearer-sweep.sh` (about lines 737 to 741) asserts that no `scripts/followthroughs/*`
  path is in baseline E; the widened vocabulary lists four of them (`canary-promotion-5875`,
  `infra-config-activation-7220`, `infra-config-fatal-channel-7220`, `inngest-soak-6178`, the S2 set), so
  relax it to "the listed followthrough set equals the S2-owned list", with a floor row for it. The community
  rows themselves go in `plugins/soleur/skills/community/test/community-argv.test.sh`, whose own shim must
  gain the same body-file reading if it lacks it (verify first).
- Lint-suite mechanics (`scripts/lint-shell-trace-credential-refusal.test.sh`): `mutate_row` copies the
  lint to `$WORK/mut.py`, so repo-wide rows (second site, discovery reverted, baseline hidden count)
  cannot run there; drive them through the `sbx_repo` mini-repo, extended with a
  `.github/workflows/offender.yml` and a baseline entry. YAML fixtures live in
  `scripts/fixtures/shell-trace-refusal/` and the dispatch keys on suffix and content, never on a
  repo-relative `.github/` prefix (out-of-repo fixture paths are absolute, so a prefix test scans nothing
  and every row passes vacuously); `fx_mut_row` gains a suffix parameter (it hard-codes `.sh`). Pin the
  finding grammar (`path:LINE:` plus a fixed phrase), update `E_MSG_RE` in the same commit (it hard-codes
  "bearer token on curl argv", so every `want=0` row would otherwise count zero matches of a dead regex
  and pass), and add one self-check row asserting `E_MSG_RE` matches a known violating fixture's output.
  Floors hang on call-site counters in this suite: raise `MIN_ASSERTIONS` to the measured count, make
  `E_ROWS` exact, add a `Y_ROWS` counter; the battery's `EXPECTED_TESTS` stays exact.

### Phase 1: Lint arms and seeded baseline (guard first)

- `scripts/lint-shell-trace-credential-refusal.py`:
  1. Replace `E_BEARER` by a named credential-header constant at its five read sites; keep `E_APIKEY`
     semantics ("second credential beside the first"). Update the finding text from "bearer token" to
     "credential" and its remedy line to the config-stdin form for each scheme.
  2. (Deferred to S2: `-u`/`--user` detection, with the `betterstack-query.sh` conversion.)
  3. Discovery: a `rule_e_files()` that returns tracked `*.sh` plus `.github/**/*.yml|*.yaml` and
     `apps/**/cloud-init*.yml`; Rules A to D keep `all_shell_files()`. `--changed` stays `*.sh`-only
     (D1). Explicit paths may now be YAML and run Rule E only. Two feeders (D1): a PyYAML extractor that
     yields every `run` string value of workflows and composite actions (skipping non-bash `shell:`, as
     `scripts/lint-workflow-run-body-syntax.py` does), reporting `file: step <name>` plus a best-effort
     line found by locating the body's first line in the file; and a raw-line feeder for
     `cloud-init-*.yml` only. A `.github/**` file PyYAML cannot parse exits 2 (cannot evaluate). Import PyYAML
     lazily at the first `.github` YAML scan so the stdlib-only `--changed` path is unaffected; a missing
     PyYAML (`ImportError`) exits 2, and only `yaml.YAMLError` is caught for the unparseable-file path (a
     blanket `except Exception` would turn a missing dependency into silently different per-file counts).
     Prefer `CSafeLoader` with a fallback (the YAML load adds about 5 s over 103 files locally, and the
     repo-wide run measured 7 to 18 s depending on machine load). Checkable evidence that `import yaml`
     works where the repo-wide suite runs: cite a green CI log in which
     `scripts/lint-workflow-run-body-syntax` passed. `cloud-init.yml` (Terraform-templated, does not parse)
     is part of the raw-line set: the discovery pathspec is `apps/**/cloud-init*.yml`.
  4. Make the discovery list a measured set: `git ls-files` pathspecs verified to match at least one real
     file each (`hr-when-a-plan-specifies-relative-paths-e-g`).
- Fix the known miss: `discord-setup.sh` array-held `Authorization: Bot` header must be flagged (RED row
  first). The cause is NOT the vocabulary: `_array_body`'s declaration regex accepts only `local -a`,
  `declare -a` or `readonly -a`, and `discord-setup.sh:71` is `local curl_args=(`, so the declaration is
  skipped and only the later `+=(-d "$data")` is inlined (verified: `_e_bearer_arrays` finds `curl_args`
  but `check_rule_e` returns 0). `_array_body` is shared with Rule D and the wrapper analysis, so the fix
  site is that regex and the Phase 0 Rule D census diff is the guard against collateral findings.
- Seed `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` with the measured counts for every
  file the widened arm flags, MINUS files S1 converts (the four community scripts). Use
  `--write-baseline-e` only AFTER Phase 2 conversions and only on a tree rebased onto current
  `origin/main` (see Sharp Edges on #9632). `web-private-nic-guard.sh`'s line is whatever the lint
  reports; do not hand-edit it.
- Update the lint docstring's Rule E block (members, the YAML scope, the vocabulary, the `--changed`
  decision and its reason, the known blind spots: bodies, URL userinfo (`x-access-token:` remotes), `doppler --token`, `jq --arg`,
  `openssl dgst -hmac "$KEY"` (about 30 sites; census-only in S1, S2 decides an arm), `env:`-held header
  values (`-H "$H"`), `env -i`, `wget`, `gh api -H`, `-K` files with default umask).

### Phase 2: Community scripts (user-run, but shipped by the plugin release on merge)

- `plugins/soleur/skills/community/scripts/discord-community.sh` (line ~220) and `discord-setup.sh` (the
  `curl_args` array, line ~74): Bot token through `--config -` with a process substitution, `--disable
  --noproxy '*'` first. `discord-community.sh` already validates the token's base64.base64.base64 shape in
  `validate_env` before any curl, so reuse that check as the guard rather than adding a second one;
  `discord-setup.sh` needs the same shape check on `DISCORD_BOT_TOKEN_INPUT` before its call. A refusal
  prints one fixed value-free line, `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=token_shape`, and exits
  1; it must NOT reuse `report_transport_failure`, whose text blames `~/.curlrc` and proxies and would
  misdirect the user. `discord-setup.sh` has neither `--disable` nor `--noproxy` today; adding
  `--noproxy '*'` is a behaviour change for users behind a corporate proxy, so the PR carries a changelog
  line and the transport-failure message names the proxy case.
- `discord-setup.sh` also carries no xtrace refusal (the lint prints `binds a live credential but carries no
  xtrace refusal`), and it is baselined in `scripts/lint-shell-trace-credential-refusal.baseline.txt`
  (A/B/C). An explicit-path run bypasses baselines, so the file must be fully clean on its own: add the
  xtrace-refusal preamble (copy the neighbour form from `discord-community.sh`) and delete its line from
  that baseline in the same diff (deletion only). The discoverability probe below depends on this.
- `bsky-setup.sh` (line ~268) and `bsky-community.sh` (line ~237): the createSession body carries the app
  password and a user-supplied handle. Use the `configure-auth.sh` precedent end to end: the body is written
  to a 0600 temp file (create it with `mktemp "${TMPDIR:-/tmp}/bsky-body.XXXXXXXX"`, not `mktemp -t`, which
  treats its argument as a prefix on macOS) and sent with `--data-binary @file` (not `-d @file`, which strips
  CR/LF); the password and handle reach `jq` through its ENVIRONMENT as an inline assignment prefix on
  the `jq -n` call that reads `$ENV.BSKY_ID` and `$ENV.BSKY_PW` and writes the body file directly,
  never `jq --arg`, because jq's own argv is world-readable too (`configure-auth.sh` says so at its
  body-file comment); never `export` them. One owning EXIT trap removes the file on every exit path
  (`lint-trap-tempfile-ownership.py`), and the writer must not run inside a `$(...)` that would swallow the
  `exit`. The battery adds a `jq` shim row asserting no credential value appears on `jq`'s argv (the curl
  shim alone cannot see a `--arg` regression). Explicit JSON `Content-Type`. Double-escaping an arbitrary
  handle into a config string is the fragile alternative and is not used. Both bsky refusals exit non-zero
  (never 0 or 3): `bsky-community.sh post` also runs HOSTED, from `scripts/content-publisher.sh` (line ~763,
  `BSKY_SCRIPT`), where a non-zero exit feeds the fallback-issue path, so the battery asserts the exit
  code and that the refusal marker reaches stderr.
- `plugins/soleur/skills/flag-bootstrap/SETUP.md`: the five `curl ... -H "Authorization: Api-Key $TOKEN"`
  examples become the stdin-config form (docs only; Rule E does not scan Markdown, so the row is a
  `git grep` row in the battery).
- Every curl keeps its own `< <(printf ...)`; never one config across calls; no pipe form in bash
  scripts (SIGPIPE).

### Phase 3: review SKILL.md extraction and Sharp Edge (item 4)

1. Re-measure and pin: `wc -c plugins/soleur/skills/review/SKILL.md` (476,997 at planning), the three
   migration/RLS bullets by their bold leads (not by line number), and the pinned anchors that must stay in
   SKILL.md: the `lifecycle-handoff-protocol` marker, `run only the suites targeting the files they were
   given`, `TEST_GROUP=affected bash scripts/test-all.sh`, `SOLEUR_SUBAGENT` (read by
   `fanout-suite-scope.test.sh` arms 4 and 8d and `workflow-fidelity.test.ts`). None sits in a moved
   bullet (checked: the three leads appear nowhere outside SKILL.md and the anchors are on lines 14 and
   197 to 213).
2. Create `plugins/soleur/skills/review/references/defect-classes-migrations.md` with a header line in the
   `wfs.md` style ("Loaded from the Defect Classes list in SKILL.md when the diff adds or edits a
   `supabase/migrations/*.sql` file or an RLS policy") and the three bullets moved verbatim (byte identity:
   the three bullets' bytes equal the removed bytes, checked with `wc -c` and a diff).
3. In SKILL.md, in place of the three bullets, add one bullet under the existing
   `- [workflow suites](./references/wfs.md)` line: `- [migration and RLS classes](./references/defect-classes-migrations.md)`
   as a markdown link, never a backtick path (`plugins/soleur/AGENTS.md` compliance checklist and the
   components test `describe("No backtick file references in skills")`). The components reachability test
   requires the file name to appear in SKILL.md.
4. Add the Sharp Edge, one bullet, in `### Sharp Edges: Review Agent Limitations` next to the existing
   "Parallel review batches can stall silently" bullet: a seat whose last transcript block is a
   `tool_use` has not delivered; read its last assistant text with `jq` (never `Read` or `tail` the
   JSONL, which floods context), then `SendMessage` "make no further tool calls, reply now with the
   report"; the "completed" notification fires per pause, not at the end. Evidence: PR #9654, about 9 of
   12 seats. Name the learning file as the source.
5. Byte budget as a delta (recorded before writing the prose): ceiling 477,000, current 476,997; the move
   frees about 4,405 bytes; the link bullet adds about 250 and the new bullet about 1,100, so the expected
   result is about 3,050 bytes of headroom. Assert the measured result, not this estimate.
6. Do not touch frontmatter `description:` (no description-budget movement); do not raise
   `skill-body-budget.json`.
7. Verify: `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`,
   `bun test plugins/soleur/test/components.test.ts` (reachability of `references/*.md`, no backtick
   references, description word budget unchanged), `bash plugins/soleur/test/fanout-suite-scope.test.sh`,
   `bun test plugins/soleur/test/workflow-fidelity.test.ts`.
8. Independence: Phase 3 is its own commit group and may become its own PR if the CI cycle is reset by
   the #9632 sequencing (the files do not overlap).

### Phase 4: Verification (committed-tree form, before the single push)

`git add` and commit first, then run (a lint that enumerates with `git grep` run on untracked files
passed locally and failed in CI last time). All must exit 0:

00. Before anything: `git status --short` must list only this branch's intended files (a foreign
   untracked `*.sh`, for example a probe file another session left under `scripts/`, makes
   `--changed` fail on a file that is not ours): never `git add -A` and never delete a file that belongs to
   another session.
0. The gates' OWN invocations, not reconstructions of their input sets:
   `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` (CI runs exactly
   this at `.github/workflows/ci.yml`, the `--changed` step) and
   `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` over the changed docs
   (this plan and `tasks.md` are in the changed set).
1. `python3 scripts/lint-shell-trace-credential-refusal.py <each changed .sh path, explicit>` (explicit
   paths bypass the baselines: every converted file must be clean on its own).
2. `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide, equality against baseline E).
3. `bash scripts/lint-shell-trace-credential-refusal.test.sh`
4. `bash tests/scripts/test-argv-bearer-sweep.sh`
5. `bash .claude/hooks/grep-q-pipe-guard.test.sh` (the grep-q pipe guard)
6. `bash scripts/lint-supabase-deprecated-endpoints.sh`
7. `bash scripts/lint-orphan-test-suites.sh`
8. `bash scripts/guard-vacuity-floor.test.sh` (new floors written `-lt N` with the lower-case message
   `anti-vacuity floor`; ratchet must not grow)
9. `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"` and
   `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base HEAD origin/main)"`
10. `python3 scripts/lint-trap-tempfile-ownership.py` and `--check-highwater` (the bsky tempfiles),
    `bash plugins/soleur/test/fixture-relative-assert.test.sh`,
    `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`
11. `tsc --noEmit` in `apps/web-platform` only if a `.ts` test was changed (none planned; record "not
    applicable" otherwise)
12. `gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges origin/main..HEAD"`
13. `python3 scripts/lint-guard-contract.py` over this plan; `bash plugins/soleur/test/c4-count-parity.test.sh`;
    `bash scripts/markdown-lint.sh` over the changed `*.md` under `plugins/` (`SETUP.md` and the new
    reference; the repo's pinned `markdownlint-cli`). `.markdownlintignore` excludes
    `knowledge-base/project/`, so the plan and `tasks.md` are not linted by the repo gate; planning ran
    `npx markdownlint-cli2` over them anyway (a hard tab inside a quoted command or a list glued to the line
    above its heading would otherwise surface in a later phase)
Never print, echo or grep for a credential value in any of these; compare secrets by outcome only. No
`git stash`; no pattern-matching process kill.

### Phase 5: PR

Edit the existing draft PR #9674 for this branch (retitle it, replace the `WIP:` body) rather than creating
a second PR. Immediately before enabling auto-merge re-check #9632
(`gh pr view 9632 --json state,mergedAt`): if it merged, rebase, take main's side of any baseline
conflict, finish the rebase, and regenerate with `--write-baseline-e`; put every baseline file in one
final commit so that step is mechanical. A merge-queue run combining both trees fails on "listed but no
longer carries", so do not enable auto-merge while #9632 is merging.

- PR body, first line (the answer to "does merging this alone mutate production?", derived from the diff
  and the workflows' `paths:` triggers): "Merging this PR fires the web-platform release (it edits
  `plugins/soleur/**`) and no infra apply (no path under `apps/web-platform/infra/`, no apply workflow,
  no `.tf`)." Then: `Ref #9597`, `Ref #7797` (no `Closes`), the slice table, the honest review-coverage
  line, the census numbers, and the #9632 sequencing note.

### Phase 6: Tracking (same session, as deferral-tracking requires)

- File one issue per later slice (S2, S3, S4, S5), each with what, why, re-evaluation criteria, blocked-by
  edges (`gh issue edit <N> --add-blocked-by <M>`: S3 and S4 blocked by S2; S4 by the S3 helper; S5 by S3
  and S4) and a milestone from `knowledge-base/product/roadmap.md`. Verify the labels exist first
  (`gh label list --limit 200`); #9597's own labels (`priority/p3-low`, `domain/engineering`,
  `type/security`) are the safe set. Record the four issue numbers in `session-state.md`.
- Copy the original #9597 body into a comment before restating it.
- Restate the #9597 body with the slice table and the corrected measurements (35 argv / 55 hits;
  apply workflow 6 not 12; cutover-inngest.sh 20 sites; the 18 non-Bearer YAML sites). Comment on #7797
  and #7898 (what S1 closed of its section 3); leave both open. Comment on #8767 pointing at S2 and the
  stale argv half.

## Slice Contracts (later PRs; each filed as an issue in Phase 6)

**S2: ops and runner scripts under `scripts/` and `plugins/` (no infra apply and no `apps/web-platform/**` or `plugins/soleur/**` edit, except the community signing-key row below).** `scripts/cutover-inngest.sh` (20
HMAC + CF-Access sites; also finishes #8767: report the HTTP code only, never the body; `::add-mask::`
the Doppler-read `HCLOUD_TOKEN`; decide the tier row `cutover-inngest.yml::cutover` in
`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, because `create_image` is
a write; carries `Closes #8767`), `scripts/betterstack-query.sh` (`-u`; about 12 suites drive it through a
stub host, so the shim must keep them green), `scripts/check-deploy-script-parity.sh`,
`scripts/followthroughs/{canary-promotion-5875,infra-config-activation-7220,infra-config-fatal-channel-7220,inngest-soak-6178}.sh`,
the HMAC helper (D4), the `openssl dgst -sha1 -hmac "$signing_key"` OAuth1 signing-key sites in
`plugins/soleur/skills/community/scripts/x-community.sh` (line ~296) and `x-setup.sh` (line ~297) (the key
is on argv today; they are plugin-path edits, so they fire the plugin release like S1), and the
`scripts/sweep-followthroughs.sh` env hop (decision row, D-table above). Heartbeat-URL probes: decide
convert-or-document (not lintable). Also adds the `-u`/`--user` arm to Rule E in the same diff as the
`betterstack-query.sh:352` conversion (its only real site). The `sweep-followthroughs.sh` env hop: a
subshell that unsets everything outside a keep-list is weaker than `env -i` (it cannot unset non-identifier
names, bash re-exports `_`, `PWD`, `SHLVL`, `OLDPWD`, and exported functions need separate handling), so
if S2 converts it at all it builds the clean environment in-process (`python3 -I -c` with `os.execve` and an
allowlisted dict, exact `env -i` semantics), otherwise it documents the microsecond `env` argv window and
moves on. Proof: shim battery plus each script's owning suite. For every converted call site in S2 to S5,
record the old failure's sink and the new refusal's sink, read the alert predicate (the learning on
refuse-before-send guards), and add a battery row asserting the refusal reaches a paging or red surface;
for a watchdog or cron, the refusal exits non-zero and fails the job, so a refusal never reads as healthy.

**S3: workflow YAML that cannot fire production on merge (dispatch, schedule, pull_request only) and the
composite actions `notify-ops-email` (used by 13 workflows, so not low-risk: the helper battery and its
selftest gate it) and `anthropic-preflight`.** Creates `scripts/lib/bearer-curl.sh` (D3) with its own battery rows;
converts `git-data-rung2-rehearsal` (4), `workspaces-luks-cutover` (1), `scheduled-terraform-drift` (1),
`rule-audit` (2), `git-data-cutover` (1), `scheduled-inngest-health` (3), `scheduled-prod-version-drift`
(2), `canary-status` (1), `board-status-sync` (1), `sentry-audit-gate` (1), `.github/actions/notify-ops-email`
(1), `.github/actions/anthropic-preflight` (1): 19 sites in 12 files (re-measure). Per-job precondition:
the job checks the repo out before the step (census row; otherwise inline form). Load the helper with
the names it defines `unset` before `source` and prove what loaded with its own selftest, never
`source lib; [[ -n "$VAR" ]]`, which an inherited environment value satisfies. Syntax checks: `actionlint`
for workflows and `bash -c` over the extracted `run:` text; do not run `actionlint` on composite action
files (it emits spurious schema errors against the action format). Pre-merge proof: helper
battery plus a run-block extraction test (python YAML load, run text under the PATH shim with fake env);
a `gh workflow run <file> --ref <branch>` smoke only for the read-only probes (`canary-status`, the
`scheduled-*` workflows, `rule-audit`); `git-data-cutover` (modes include `flip`),
`workspaces-luks-cutover` (sole-copy user data behind a reviewer-gated environment) and
`git-data-rung2-rehearsal` ("build it, do not fire it") are NEVER dispatched for a smoke and are proven by
the run-block extraction test under the PATH shim only. pull_request workflows prove themselves in CI.
`anthropic-preflight` ends its call in `|| echo "000"`, which routes to `ok=false`; a guard refusal there
would silently skip every Claude step (the failure shape of the 2026-10-06 learning), so its refusal
exits 1. Helper source form: `source "${GITHUB_WORKSPACE}/scripts/lib/bearer-curl.sh"` (the apply workflow
sources repo libraries this way at 36 sites; a relative path breaks under `working-directory:`). `scripts/lib/`
is excluded from Rule E, so the helper is covered by its own battery and selftest, not by the lint.

**S4: push-triggered, non-apply production-class files.** `restart-inngest-server` (4),
`deploy-inngest-image` (2), `apply-inngest-rls` (4), `apply-github-infra` (1), `web-platform-release` (5),
`apply-deploy-pipeline-fix` (6), `.github/actions/mint-infra-app-token` (2; used by `apply-github-infra`,
`build-inngest-bootstrap-image` and `mint-inngest-bootstrap-tag`, so a failure blocks those three), `.github/actions/dispatch-web-redeploy/track.sh` (2),
`apps/web-platform/scripts/github-app-key-status.sh` (matches the release trigger `apps/web-platform/**`),
`apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh` (its second call signs with
`openssl dgst -hmac "$WEBHOOK_SECRET"` at line ~143, also under `apps/web-platform/infra/**`),
`apps/web-platform/infra/{push-infra-config,infra-config-verify,ci-deploy}.sh` (these live under
`apps/web-platform/infra/**`, so merging them FIRES the production apply). Before editing any
`apps/web-platform/infra/*` file, enumerate every push-triggered workflow whose `paths:` include it
(`apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` both list infra files) and state
whether its `-target` graph reaches the change and whether its guard counts the change class. Merge is a
declared production effect: operator awareness before merge, outcome-verified after (the markers or runs named in
the slice issue), plus the python3-on-host row for `ci-deploy.sh`. `web-platform-release.yml` does not list itself in its push paths, so a broken conversion there would
surface on the next unrelated main completion (its `workflow_run` arm): require a `workflow_dispatch` run
with `skip_deploy=true` on the branch copy before merge. Two more checks for the host scripts: a refusal in a
webhook-run script must reach stderr or stdout and the calling workflow must print the body on non-2xx;
any `logger -t` marker on a host oneshot must use a tag already in the Vector allowlist. Add
`.github/scripts/bump-inngest-bootstrap-pin.sh` (line ~214 builds `https://x-access-token:${GH_TOKEN}@github.com/...`
and passes it to `git ls-remote` and `git push` on argv: a write-capable installation token) with a
`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0=http.extraheader` or credential-helper fix that keeps its
`BUMP_PUSH_URL` fixture override, and a census row `git grep -nE 'x-access-token:'`.

**S5: the apply workflow and its sibling, last and separate.** `apply-web-platform-infra.yml` (6 argv
sites; the file lists itself in its own push paths, so the merge fires a PRODUCTION push apply on main:
operator awareness, no batching with anything else) and `apps/web-platform/infra/cloud-init-registry.yml`
(4 sites, inline form because it is baked into the registry host). BEFORE the conversion, relocate
comment prose from the apply workflow to `apply-web-platform-infra-job-rationale.md` (keeping the
`# Rationale:` pointer lines) so the file ends smaller than 485,630 bytes; acceptance records the byte
delta explicitly (`wc -c` before and after, gate 490,000). Add the three `doppler secrets ... --token "$DOPPLER_TOKEN_INNGEST_ARM"` calls in the same
workflow (lines ~2261 to 2270; Doppler honours the `DOPPLER_TOKEN` environment variable, so the token moves
to a per-command environment prefix) to the same PR. The cloud-init change must show no host
replacement in the plan (the destroy-guard filter is a push trigger too). Carries `Closes #9597` once
baseline E holds only entries owned by other tracked work (the nic-guard line while #9632 is open).

## Files to Edit (S1)

- `scripts/lint-shell-trace-credential-refusal.py`
- `scripts/lint-shell-trace-credential-refusal.test.sh`
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` (delete the `discord-setup.sh` line only)
- `tests/scripts/test-argv-bearer-sweep.sh`
- `plugins/soleur/skills/community/test/community-argv.test.sh`
- `plugins/soleur/skills/community/scripts/discord-community.sh`
- `plugins/soleur/skills/community/scripts/discord-setup.sh`
- `plugins/soleur/skills/community/scripts/bsky-setup.sh`
- `plugins/soleur/skills/community/scripts/bsky-community.sh`
- `plugins/soleur/skills/flag-bootstrap/SETUP.md`
- `plugins/soleur/skills/review/SKILL.md`

## Files to Create (S1)

- `plugins/soleur/skills/review/references/defect-classes-migrations.md`
- `knowledge-base/project/specs/feat-one-shot-argv-bearer-sweep-tier3/{tasks.md,session-state.md,decision-challenges.md}` (the census table is recorded once, in the PR body and the #9597 restatement, not as a third copy)

## Open Code-Review Overlap

Two partial hits among the 87 open `code-review` issues (matched by basename, because the first
full-path search found none). #8881 names `review/SKILL.md` once, incidentally (a rebalance review):
acknowledge, different concern. #7098 ("audit the 56 `run:` bodies whose `set` omits -e against GitHub's
inherited `bash -e`") names `apply-web-platform-infra.yml` seven times: acknowledge for S1 (no workflow
edit), and for S5 note that converting its six sites touches `run:` bodies #7098 audits, so S5 must not
change any body's `set` line and re-runs the #7098 lint if one lands first.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Tier 3 (measured 21 workflow YAML files / 55 sites, apply-web-platform-infra.yml has 12; cloud-init-*.yml; the env -i hop in scripts/sweep-followthroughs.sh)" [brief] | D2, Slice Contracts S2 to S5 (re-measured: 35 argv / 55 hits, 6 in the apply file) | mapped |
| 2 | "plus the further argv credentials listed on #9597 (ci-deploy.sh HMAC, infra-config-verify.sh, push-infra-config.sh, Discord Bot headers, bsky password bodies, betterstack-query.sh -u, cutover-inngest.sh, check-deploy-script-parity.sh, track.sh, openssl -hmac in verify-tunnel-ingress-origin.sh, flag-bootstrap/SETUP.md)" [brief] | Phase 2 (Discord, bsky, SETUP.md), S2 (betterstack-query, cutover-inngest, check-deploy-script-parity), S4 (ci-deploy, infra-config-*, track.sh); `openssl -hmac` in verify-tunnel-ingress-origin.sh: S2 HMAC helper (D4) | mapped |
| 3 | "DECIDE FIRST (and record as a decision in the plan) whether the lint ... gets a YAML arm and a non-Bearer arm plus a \"guard runs before curl\" check" [brief] | D1 | mapped |
| 4 | "Re-measure the Tier 3 site counts yourself before claiming them." [brief] | Research Reconciliation, Phase 0 | mapped |
| 5 | "Evaluate splitting: ... plan the first PR as a bounded slice with `Ref #9597` / `Ref #7797` and file or update follow-up issues for the remainder; `Closes #9597` only if the plan truly finishes everything." [brief] | D2, D6, Phase 5, Phase 6 | mapped |
| 6 | "Also check open issues #8767 ... and #7898 ... for overlap" [brief] | D6, S2 (`Closes #8767`), Phase 6 comments | mapped |
| 7 | "extract a block to plugins/soleur/skills/review/references/ first (linked as a proper markdown link per the skill compliance checklist, with the content anchors any tests/lints pin kept intact), then add the Sharp Edge." [brief] | D5, Phase 3 | mapped |
| 8 | "Check lint-skill-body-budget.py and the skill description budget." [brief] | Phase 3 steps 5 to 7 | mapped |
| 9 | "Before pushing any conversion PR, these must pass in committed-tree form" [brief] | Phase 4 | mapped |
| 10 | "Do NOT plan those as code work; just reference them as out-of-scope operator/ops follow-ups." [brief, items 1 and 2] | Overview | mapped |
| 11 | "Do not print or echo any token value, and compare secrets without printing them. Never use git stash or a pattern-matching process kill." [brief] | Phase 4 closing line, Sharp Edges | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Lint YAML arm and non-Bearer vocabulary (Phase 1) | asks 3, 1 ("a YAML arm and a non-Bearer arm") | asked |
| `-u` detection in the lint (moved to S2) | ask 2 ("betterstack-query.sh -u") | asked (its only real site is the S2 script) |
| Seeded baseline for YAML and non-Bearer files | ask 1 ("Rule E sees only `Authorization: Bearer`") | inferred, justification: a widened arm with no seeded baseline reds every PR, and the shrink-only equality is the enforcement contract that keeps the remainder visible |
| `--changed` stays `*.sh`-only | ask 5 ("workflow YAML runs on GitHub-hosted runners, so the blast radius and the CI-cycle cost differ") | inferred, justification: including YAML would force unrelated PRs, and the apply workflow with 4.4 KB headroom, to fully remediate |
| Phase 2 Discord, bsky, SETUP.md | ask 2 | asked |
| Fix for the `discord-setup.sh` array miss | ask 2 ("Discord Bot headers") | inferred, justification: without it the widened arm silently misses the exact file the ask names |
| Phase 3 extraction and Sharp Edge | asks 7, 8 | asked |
| Migration/RLS cluster extraction choice | ask 7 ("extract a block") | asked (block chosen by D5 with alternatives measured) |
| Slice Contracts S2 to S5 and Phase 6 issues | ask 5 | asked |
| Shared helper `scripts/lib/bearer-curl.sh` (S3) | ask 1 ("apply-web-platform-infra.yml has 12") | inferred, justification: the apply workflow's byte gate and the up-to-55 duplicated guards make per-site inline conversion fail the gate or rot |
| HMAC via python3 (S2/S4) | ask 2 ("openssl -hmac in verify-tunnel-ingress-origin.sh") | asked |
| `Closes #8767` in S2 | ask 6 | asked |
| Guard Contract section | ask 9 | inferred, justification: plan Phase 2.12 requires it for any plan whose deliverable includes a guard (lint arms, ratchet) |
| decision-challenges.md | ask 4 | inferred, justification: plan-review taste findings persist there for `ship` (ADR-084) |
| Delete the `discord-setup.sh` line from the A/B/C baseline and add its xtrace refusal | ask 9 ("python3 scripts/lint-shell-trace-credential-refusal.py on the explicit changed paths (explicit paths bypass the baselines)") | inferred, justification: explicit paths bypass baselines, so the file cannot pass the required explicit-path run while it lacks the refusal |

### Split Assessment

- Subsystems touched: 4 (`scripts`, `tests`, `plugins/soleur`, `knowledge-base`)
- Planned files: 13 edited + 4 created for S1 (plus the YAML fixture set under `scripts/fixtures/shell-trace-refusal/`) | Estimated changed lines: about 700 (lint 250, lint tests 150, battery 150, four scripts 100, baseline 35, SETUP.md 20); the review extraction moves about 4.4 KB (three bullets) and is counted as a move, not new code
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split. The four-roots threshold is exceeded by a margin that is mostly knowledge-base artifacts; the real boundary is already drawn: S1 (this PR) is the guard plus the four community scripts plus the independent review extraction, and S2 to S5 are the split, each with its own issue. Within S1, Phase 3 (review SKILL.md) is an independent commit group and can be cherry-picked into its own PR if review asks for it.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 4 items 1 to 13 all exit 0 on the committed tree (list recorded in the PR body with exit codes; no credential value printed anywhere).
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide) exits 0; baseline E equals the live offender set by path and count and contains no entry for the four converted community scripts.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0 with one row per converted call site, including: token absent from argv, exact stdin config, refusal row (token containing CR/LF, quote, space: curl never invoked), must-PASS row with the real token shape, and the `--data-binary @file` body rows for both bsky scripts.
- [ ] `git grep -nE -- '(-H|--header)[ =]+"?Authorization: (Bot|Bearer|Api-Key)' -- <four community scripts> plugins/soleur/skills/flag-bootstrap/SETUP.md` returns no hit.
- [ ] `git diff --name-only "$(git merge-base HEAD origin/main)"..HEAD` contains no path under `apps/web-platform/infra/` and neither `.github/workflows/apply-web-platform-infra.yml` nor `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (a merge cannot fire the production push apply); the PR body's first line names the plugin-release trigger that the `plugins/soleur/**` edits DO fire.
- [ ] `wc -c plugins/soleur/skills/review/SKILL.md` is below 477,000 with the new Sharp Edge present; `plugins/soleur/test/skill-body-budget.json` unchanged; `references/defect-classes-migrations.md` bytes plus SKILL.md bytes account for the original 476,997 plus the link bullet plus the new Sharp Edge (the move is verbatim).
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (reachability names `defect-classes-migrations.md`, no backtick path references, description budget untouched).
- [ ] PR body: `Ref #9597`, `Ref #7797` (no `Closes`), slice table, honest review-coverage statement, #9632 sequencing note.
- [ ] For each of the four issue numbers recorded in `session-state.md`, `gh issue view <N> --json blockedBy,milestone,title` shows the S2 to S5 title, a milestone and the blocked-by edges of D6; the #9597 body names all four numbers and carries the corrected measurements (`35` argv sites, `6` in the apply workflow, `20` in `cutover-inngest.sh`). (A body-search form such as `--search '9597 in:body'` returned nothing during planning and is not used.)

### Post-merge (verified by outcome)

- [ ] The next `main` CI run is green on `scripts/lint-shell-trace-credential-refusal-repo` and on the `rule-body-lint` and skill-budget jobs.
- [ ] The web-platform release run for the merge commit succeeds: `gh run list --workflow web-platform-release.yml --branch main --event push --limit 5 --json conclusion,headSha` shows the merge commit's first 10 characters with `success`, and the next scheduled content-publisher run (Sentry monitor, read through the repo's `scripts/` probes, no SSH) reports healthy.
- [ ] No infra apply run was triggered by the merge commit: `gh run list --workflow apply-web-platform-infra.yml --branch main --event push --limit 5 --json createdAt,headSha --jq '.[].headSha[0:10]'` does not print the merge commit's first 10 characters (the form was executed during planning and prints five SHAs; the `--event push` filter is required).

## Observability

```yaml
liveness_signal:
  what: the repo-wide Rule E run (scripts/lint-shell-trace-credential-refusal-repo suite) stays green on main and its baseline E entry count only decreases
  cadence: every CI run on push to main and on every PR
  alert_target: a red required test shard on the PR or on main
  configured_in: scripts/test-all.sh (suite scripts/lint-shell-trace-credential-refusal-repo) and .github/workflows/ci.yml
error_reporting:
  destination: lint stderr with file:line and the credential scheme found; CI log
  fail_loud: exit 1 on any unlisted offender or any listed file whose count changed; exit 2 when the lint cannot evaluate (unreadable file, git error)
failure_modes:
  - mode: a new argv credential appears in a workflow or script
    detection: repo-wide equality (offender not in baseline E) fails the test shard
    alert_route: red required check on the PR
  - mode: a widened-vocabulary false positive reds unrelated PRs
    detection: the census rows in the lint test suite (measured zero false positives on the 9 comment/echo and 11 stdin hits); surface is the CI shard run log (lint stderr, file:line), a build-time gate
    alert_route: red lint test suite before merge
  - mode: a converted community script refuses a valid credential and goes quiet (observability layer 7 for an installed user's CLI, plus the hosted path for bsky-community.sh)
    detection: layer 7 is cli-stdout-artifact. The refusal prints one fixed value-free stderr line (`SOLEUR_CREDENTIAL_REFUSED script=<name> reason=token_shape`, never the token or handle) and exits 1; the committed battery rows (must-PASS with the real token shape, refusal row asserting the marker and that curl was not invoked) are the durable artifact, and the probe reads that committed artifact, not the network. Hosted path: the bsky refusal exits non-zero (never 0 or 3), `scripts/content-publisher.sh` captures its stderr into the fallback-issue path, and the Inngest cron monitor still pages
    alert_route: red battery before merge; on the hosted path the existing fallback issue plus the cron monitor
logs:
  where: CI logs of the test shard; PR body records the census table
  retention: GitHub Actions default
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py plugins/soleur/skills/community/scripts/discord-community.sh plugins/soleur/skills/community/scripts/discord-setup.sh plugins/soleur/skills/community/scripts/bsky-community.sh plugins/soleur/skills/community/scripts/bsky-setup.sh
  expected_output: OK:
```

(An explicit-path run bypasses the baselines, so it prints `OK:` only when the converted files are
clean on their own, and it finishes in well under Check 10's 15-second cap; the repo-wide run took about
7 seconds before the YAML arm and is therefore not used as the probe. Phase 1 re-times the repo-wide run
after the arm lands and records it, because a CI shard that approaches a time cap is its own failure
mode.)

## Guard Contract

### Guard 1: Rule E widened (YAML discovery plus credential vocabulary) and the baseline E ratchet

**Property.** No curl in a tracked `*.sh`, workflow or composite-action YAML, or cloud-init YAML carries a
credential-bearing header (any `Authorization:` scheme, `CF-Access-Client-*`, `X-Signature-256`, `X-API-Key`)
on its own argument list, except in files listed in baseline E by exact path and count. (`-u` operands join
in S2.)

**Assembly.** Discovery chokepoint: `rule_e_files()` (new) feeding `check_rule_e` through two feeders: the
PyYAML `run:`-body extractor for `.github/**` and the raw-line feeder for `cloud-init-*.yml`; the parallel
path `check_file` (A to D, `*.sh` only) must NOT receive YAML. Vocabulary chokepoint: the single credential
constant read at five sites (held-name capture, array capture, `_e_scan` header branch, call-level
`bearer_in_call`, wrapper-site `bearer_ctx`), enumerated by `grep -n` over the lint file, not by line
numbers in this plan. Argument-shape forms the vocabulary must cover: `-H "X"`, `-H"X"`, `--header X`,
array elements, wrapper functions. Entry points: repo-wide run (baseline equality),
explicit paths (baseline bypassed), `--changed` (`*.sh` only, by D1).

**Mutation matrix.** Repo-wide rows (1 to 3) run through the `sbx_repo` mini-repo; the others through
`mutate_row` and `fx_mut_row` on fixtures.

| # | Edit (must drive RED) | Reddens |
|---|---|---|
| 1 | Add a second argv credential site (a `CF-Access-Client-Id` header) in a baselined workflow YAML after a compliant first site, OR hide one site by seeding a baseline count lower than live | repo-wide equality (count mismatch) naming the file |
| 2 | Revert discovery so YAML is not scanned, or drop the dispatch of the new arm (the lint reports `0 checked` and exits 0) | in the sandbox: a listed YAML file with live count 0 fails equality; against the real corpus: one grow-only anti-vacuity floor on the YAML population (the measured file count at implementation time, 103 today, not a round number with 3% slack) |
| 3 | Narrow the vocabulary back to `Bearer`, OR re-narrow exactly ONE of the five read sites (held-name capture, array capture, header scan, call-level check, wrapper-site check) to the legacy constant, OR delete one regex alternate | one fixture per read site that is non-Bearer (variable-held `CF-Access-Client-Id`, array-held `Bot` declared as plain `local x=(...)` with a conditional `+=(` append, wrapper-called `X-Signature-256`, a second-credential case) and one fixture holding a site per alternate, driven by a loop of N `mutate_row` calls over the alternates derived from the constant's own source (each expects rc 1 and exactly N-1 findings) |
| 4 | Revert the array-declaration regex in `_array_body` (accept only `local -a` again) | the `local x=(` array fixture (this is the `discord-setup.sh` miss) and the Rule D census row |
| 5 | Add the same credential header in a folded scalar (`run: >-`), in an inline QUOTED `run: "curl ..."` step (an unquoted inline `run: curl -H "Authorization: ..."` is invalid YAML because of the colon-space, so it is not a fixture) and in a double-quoted-escaped inline step, each as its OWN fixture with a compliant literal block first | a raw-line feeder moves rc 1 to 0 per fixture; a combined fixture would only change the count while rc stays 1 |
| 6 | Make the extractor skip a composite-action step (`runs.steps[*]`) or a workflow step with no `shell:` key | two fixtures (a composite action with `shell:`, a workflow step without it), each with its own mutation |
| 7 | Make an unparseable `.github` YAML file skip or fall back silently instead of exiting 2; make a missing PyYAML fall through; broaden the `except` to `Exception` | a fixture that is unparseable AND holds a raw-detectable site (otherwise "skipped" and "fallback found nothing" give the same rc), expecting exit 2 and a pinned stderr note; a row that hides `yaml` and expects exit 2 |

**Harness rows.** (a) A positive control asserting that the fixture copy contains at least N `.yml`
files, so a guard that scans no YAML at all cannot pass the must-PASS set (the suite has no "YAML loader"; its
instruments are the positive control, the `mutate_row` self-test and the `cp -r` of the fixture directory).
(b) Make the fixture runner ignore the exit status: the RED rows (which expect exit 1) must fail the suite.
(c) A violating twin for each must-PASS via `fx_mut_row` (the `shell: python` twin changes `python` to
`bash`). Must-PASS inputs that are not the canonical, and that the contract explicitly permits, built from
the measured 9 doc and 11 stdin hits and synthesised per `cq-test-fixtures-synthesized-only`: a `run:` step
whose `shell:` is `python` (skipped by the precedent lint) containing the header text, an echo of a
runbook line containing `-H "Authorization: Bearer $X"` inside a YAML `run:` string, a `printf ... | curl
-H @-` stdin form, a comment line, and a `curl ... --config -` form with a process substitution; none
may be flagged. (d) A row comparing the seeded baseline's per-file counts with the hand-classified census
table, because `--write-baseline-e` seeds the baseline from the tool under test and would otherwise certify
its own false positives and negatives. Pinned blind spots with xfail rows (not evasions to pretend away):
`x-gitlab-token`-style custom headers, `-b "session=$T"` and `-H "Cookie: s=$T"`. Any `Authorization:`
value, including `${SCHEME}` and `Digest`, IS flagged because the constant matches the header name.

**Anchor.** Baseline E is shrink-only by equality with the live set; `--check-highwater` style growth is
caught by the repo-wide run; weakening needs a visible non-deletion diff in the baseline file, which a
reviewer sees and which #9632's concurrent edits make conspicuous. Nothing outside the commit moves
automatically: a reviewer, not the lint, judges a deliberate vocabulary narrowing, which is why
mutation row 3 exists.

### Guard 2: the community-script conversions (battery rows)

**Property.** None of the four community scripts puts a credential on a curl argv or in an argv body,
and a malformed credential never reaches curl.

**Assembly.** Every curl call in the four files, including those reached through the `curl_args` array
and through helper functions, enumerated by running the lint's census over each whole file.
Chokepoints: the battery's PATH shim (observes argv, stdin config, the `--data-binary @file` body at
curl time) and Rule E in explicit-path mode.

**Mutation matrix.**

| # | Edit (must drive RED) | Reddens |
|---|---|---|
| 1 | Restore `-H "Authorization: Bot ${TOKEN}"` at one site, including a second site added after a compliant first | token-in-argv row and Rule E |
| 2 | Make the token guard accept a newline | refusal row (injection recorded) |
| 3 | Move the guard after the curl call | refusal row (curl invoked on a malformed token) |
| 4 | Hand the bsky password to curl as `-d "$body"`, OR to `jq` as `--arg pw "$BSKY_APP_PASSWORD"` | body-not-on-argv row (curl shim) and jq-argv row (jq shim) |
| 4b | Export the password (`export BSKY_PW=...`) so every later child inherits it | row asserting `curl` and `jq` children of the unrelated steps do not see it in their environment |
| 5 | Drop one script from the battery's dispatch list | row-count and vacuity floor |

**Harness rows.** (a) Make the shim record stdin to the wrong path: every stdin row reddens. (b) Make
the shim stop reading the `--data-binary @file` body: the bsky rows redden. Must-PASS non-canonical
inputs: a Discord-shaped token with dots and dashes; a bsky handle containing dots and a password with
dashes, plus a handle containing a double quote that must be refused or escaped correctly (never reach
curl unescaped).

**Anchor.** Battery rows only. The two bsky scripts are not in baseline E (a body is not a header), so lint
equality says nothing about them: a regression to `-d "{...\"password\":\"$X\"}"` stays lint-green, and the
battery is the one chokepoint. A static `git grep` row over both bsky scripts for a password variable inside a
`-d`/`--data*` operand backs it. For the two Discord scripts Rule E equality applies too (their baseline
lines, where present, are deleted in the same diff).

## Infrastructure (IaC)

### Terraform changes

None. S1 touches no `.tf` file and no path under `apps/web-platform/infra/`.

### Apply path

Not applicable to S1. S4 and S5 are production-effect merges (declared in their contracts): any edit
under `apps/web-platform/infra/**`, to `apply-web-platform-infra.yml`, or to
`tests/scripts/lib/destroy-guard-filter-web-platform.jq` triggers the push apply on main. The apply
itself stays operator-gated; why the push apply did not fire after the Tier 2 merge is the parent
session's item 1, not code work here.

### Distinctness / drift safeguards

No change to dev/prd distinctness, state or secrets.

### Vendor-tier reality check

No new vendor resource.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed (inline assessment; no leader subagent spawned in this planning run)
**Assessment:** Security-hardening and tooling change inside the established ADR-backed pattern. The
architectural risks are (a) the production-apply-on-merge coupling in S4/S5, handled by sequencing and
declaration, (b) the apply workflow byte gate, handled by relocation-before-conversion, and (c)
behavioural change to the review skill (the Defect Classes list moves from ambient to on-demand load),
which the plan review should challenge explicitly. No product, legal, marketing or finance surface:
plugin scripts run on installed users' machines but gain no new data processing or disclosure.

## Test Scenarios

1. Widened arm over the YAML corpus (extraction for `.github/**`, raw lines for cloud-init): 35 Bearer argv
   sites in 16 files flagged; the 9 doc and 11 stdin hits not flagged; about 53 sites in 21 to 22 files once
   the vocabulary is widened (the prototype's per-file table is the oracle, re-measured in Phase 0). These
   shrink-only figures live in the PR body, not in assertions: S3's first conversion would turn an exact
   assertion red; only grow-only floors are asserted.
1b. Synthetic YAML shapes: literal block, folded scalar, inline `run:`, inline double-quoted-escaped,
   list-item continuation and `${{ }}` interpolation each flagged; echo-only and `printf | curl -H @-`
   not flagged.
2. `discord-setup.sh` array-held `Authorization: Bot` header flagged before conversion, clean after.
3. A fixture YAML with `-H "Authorization: Bearer ${T}"` inside `run: |` fails; the same step in the
   `--config -` form passes; a `run:` that only `echo`es the old form passes.
4. Each community script: valid token reaches curl on stdin only; token with newline, quote, space is
   refused with curl never invoked.
5. bsky createSession: password present in the 0600 body file at curl time, absent from argv; file
   removed on exit and on error; handle with a double quote is not injectable.
6. Baseline E equality: converting a listed site without deleting its line fails; deleting a line
   without converting fails.
7. review SKILL.md: Sharp Edge present; `defect-classes-migrations.md` linked and reachable; moved bytes identical;
   pinned anchors still found; body below the ceiling.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `--changed` and explicit paths bypass the baselines, so any file named explicitly must be fully remediated; do not leave a half-converted file.
- Merging anything under `apps/web-platform/infra/**`, or `apply-web-platform-infra.yml` itself, fires a PRODUCTION push apply. S1 must not touch those paths; the acceptance row diffs the path list.
- PR #9632 edits baseline E, the A/B/C and D baselines, `scripts/guard-vacuity-floor.test.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh`. If it merges during the ~35 minute cycle, baseline E equality fails for a reason unrelated to the code: rebase, regenerate with `--write-baseline-e` on the rebased tree, re-run the lint. Never hand-edit the nic-guard line and never touch #9632's worktree.
- Do not Read or `tail` a subagent's JSONL transcript; use `jq` on its last assistant text, and send "make no further tool calls, reply now" to a seat that ended on a tool call.
- Never `printf ... | curl` in bash scripts (SIGPIPE when the consumer does not read stdin); each curl gets its own `< <(printf ...)` and never shares a config across calls.
- `_bearer_ok` covers token shapes only. Anything with spaces, `"`, `:` or `\` (user:password, an OAuth1-style header) needs `_cfg_ok`/`_cfg_q`; a too-narrow charset silently refuses a valid credential and the script goes quiet.
- Before choosing the marker a refusal emits, read the alert predicate of that marker family: a `*_SKIPPED` row never pages (the learning behind this plan).
- Anti-vacuity floors: `-lt N` on the `if` plus the lower-case text `anti-vacuity floor`; an upper-case spelling or a `-ne N` form is invisible to `scripts/guard-vacuity-floor.test.sh`.
- The YAML arm must not regress to raw-line feeding for workflows: raw lines miss folded scalars and inline `run:` steps (measured 0 of 4); mutation matrix row 5 exists for this. Cloud-init files are the one place raw lines are right.
- Run every lint on a committed tree: `git grep`-based lints do not see untracked new files.
- No heredocs inside workflow `run: |` blocks; pass `${{ }}` values through `env:`; Doppler-fetched secrets are not auto-masked.
- Every secret comparison and log check avoids printing values (no `echo`, no `grep` of a value, no `set -x`).
- The review extraction is verbatim: do not "tidy" moved bullets; the byte-identity check is the proof, and the pinned anchors must be re-grepped on the tree being committed.
- The `description:` frontmatter of the review skill is not edited; the cumulative word budget is a different gate from the body byte ceiling.
