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
  (their embedded shell is literal-block by construction) and an unparseable file falls back to raw lines
  with a stderr note, never to a silent skip. Measured parity for the two-path design: 31 Bearer argv sites
  in the `.github/**` files by extraction plus 4 in cloud-init by raw lines = 35; widened vocabulary
  49 + 4 = 53 YAML sites. Scope of the arm: Rule E only; Rules A, B, C and D key on a shebang/preamble and
  stay `*.sh`.
- *Non-Bearer vocabulary: yes.* One named constant replacing `E_BEARER` at its five read sites
  (held-name capture, array capture, header scan, call-level check, wrapper-site check): `Authorization:
  (Bearer|Bot|Basic|Token|Api-Key)`, `CF-Access-Client-(Id|Secret)`, `X-Signature-256`, `X-API-Key`,
  `Private-Token`, plus `-u`/`--user` with a variable operand. Prototype census over every tracked
  `*.sh` and YAML: 86 sites in 34 files (33 sites in 12 `.sh` files, 53 sites in 22 YAML files).
  Bodies and URLs carrying a secret (bsky password JSON, heartbeat-URL path secrets) stay census-only:
  whether a `-d` operand is a secret is not decidable from syntax.
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
keep the inline form. The helper is created in S3 (its first user), not in S1.

**D4. HMAC key off argv uses python3 reading the key from the environment.** `openssl dgst -hmac
"$KEY"` has no stdin or env form. Verified equal byte-for-byte on a fake key (python `hmac` and openssl
produce the same digest, including the empty-body case the deploy-status calls sign). The key then
travels in `execve` envp (readable only by the owner and root through `/proc/<pid>/environ`) instead of
the world-readable `cmdline`. Runner-side scripts use it in S2/S4; the on-host `ci-deploy.sh` waits for
a measured python3-on-host row (the cloud-init package list names only `curl fail2ban jq nftables`;
`cloud-init` itself is Python, but that is a claim to verify, not assume).

**D5. Review SKILL.md extraction takes the whole `### Defect Classes This Review Reliably Catches`
section** (250,787 bytes, lines 1183 to 1441, 150 bullets) into `references/defect-classes.md`, verbatim.
Alternatives, each measured: (B) a partial cluster: bold-lead clustering found only 4,405 bytes of
SQL/RLS and 1,821 bytes of React leads, and keyword clustering (21 bullets, 38,183 bytes) is mostly
bullets that merely mention Terraform as an example; (C) `### 2. Rate Limit Fallback`: it carries Gate 2a,
"can agents be spawned at all", which must be evaluated before EVERY spawn, so it is not conditional
content; (D) `### Sharp Edges: Review Agent Limitations`: the new stall guidance must stay in the lead's
working set while the panel runs. Precedents: `references/wfs.md` (the section already delegates one
class to a reference via a link) and `plan/references/plan-sharp-edges.md` (151 KB, paged read, pinned
by the reachability test).

**D6. `Closes` policy.** No slice before S5 carries `Closes`. S5 carries `Closes #9597`. `#8767` is
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
| Any merge touching `apps/web-platform/infra/**` is harmless | `apply-web-platform-infra.yml` triggers on push to main for `apps/web-platform/infra/**`, for itself, and for `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Merging any PR that edits those fires a PRODUCTION apply. | S1 edits none of those paths (acceptance row). S4/S5 declare the apply-on-merge effect and gate it. Measured caveat: `gh run list --workflow apply-web-platform-infra.yml --branch main --limit 3` shows the newest push run on main at 2026-09-27, so the 2026-10-06 Tier 2 merge (which edited `apps/web-platform/infra/*.sh`) did NOT fire it, which is the parent session's open item 1; S4/S5 plan as if the trigger fires and treat a non-fire as unexplained, not as safety. |
| `lint-skill-body-budget` ceiling can be raised | The ceiling is read from the merge base and ratchets down only; raising it is a separate reviewed PR. | Extract first (D5); the new bullet is the only addition to SKILL.md. |

## Research Insights

**Premise Validation.** #9597, #7797, #8767 and #7898 are OPEN with no linked closing PR. The Tier 2 PR
(#9654) is merged. Draft PR #9632 (`feat-one-shot-a3-credential-hardening-egress-probe-nic-guard`, WIP,
updated 2026-10-07T07:20Z) edits `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`, the A/B/C
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
  merges; nothing in S1 can fire one.
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
quiet. S1 changes no file under `apps/web-platform/infra/**`, so it cannot fire a production apply.

**If this leaks, the user's workflow is exposed via:** the argv of a short-lived curl on a runner or an
installed user's machine (a local process listing shows a Discord bot token, a Bluesky app password, a
webhook HMAC key or a Cloudflare Access pair). S1 removes the vector for the four community scripts and
makes every remaining instance a counted, shrink-only baseline entry; the residual in S2 to S5 is
visible in the baseline until converted.

**Brand-survival threshold:** aggregate pattern

## Architecture Decision (ADR/C4)

No architectural decision: a lint scope extension and call-site conversions behind an existing,
ADR-backed mechanism. Test applied: would an engineer reading the ADRs and C4 be misled after this ships?
No; no actor, system, store or access relationship changes (checked against `model.c4`, `views.c4`,
`spec.c4` for the external systems named here: GitHub Actions runners, Cloudflare Access, Better Stack,
Hetzner API, Discord and Bluesky APIs are already modeled or are plugin-side clients outside the
product boundary; the cardinality gate `plugins/soleur/test/c4-count-parity.test.sh` is run in Phase 6
because S1 adds no workflow or monitor). The D3 shared helper and D5 extraction are recorded in this plan
and in the S3 PR description, not in an ADR.

## Implementation Phases (S1, this PR)

Write the failing rows first (cq-write-failing-tests-before). One push at the end: a CI cycle is about 35
minutes and a push resets it. Do not run `scripts/test-all.sh` locally (it queues behind sibling
worktrees); run the owning suites directly.

### Phase 0: Census and RED rows

- Re-run the lint's own census: `python3 scripts/lint-shell-trace-credential-refusal.py --census` (baseline
  state) and the scratch widened-vocabulary census; write the per-file table (path, group, site count)
  into the S1 spec dir `census-tier3.md` (a point-in-time record). Re-measure; do not copy this plan's
  numbers.
- Add RED rows first to `scripts/lint-shell-trace-credential-refusal.test.sh` (see Guard Contract) and
  to `tests/scripts/test-argv-bearer-sweep.sh` (one row per converted community script, per call site).
- Check `plugins/soleur/skills/community/` for owning tests of the four scripts; there are none today
  (`git grep` over `*.test.*` for the script names finds only an incident redaction test and an inngest
  allowlist test), so the battery hosts the rows.

### Phase 1: Lint arms and seeded baseline (guard first)

- `scripts/lint-shell-trace-credential-refusal.py`:
  1. Replace `E_BEARER` by a named credential-header constant at its five read sites; keep `E_APIKEY`
     semantics ("second credential beside the first"). Update the finding text from "bearer token" to
     "credential" and its remedy line to the config-stdin form for each scheme.
  2. Add `-u`/`--user` with a variable operand (`-u "$U:$P"`, `--user "${U}:${P}"`) to `_e_scan`.
  3. Discovery: a `rule_e_files()` that returns tracked `*.sh` plus `.github/**/*.yml|*.yaml` and
     `apps/**/cloud-init*.yml`; Rules A to D keep `all_shell_files()`. `--changed` stays `*.sh`-only
     (D1). Explicit paths may now be YAML and run Rule E only. Two feeders (D1): a PyYAML extractor that
     yields every `run` string value of workflows and composite actions (skipping non-bash `shell:`, as
     `scripts/lint-workflow-run-body-syntax.py` does), reporting `file: step <name>` plus a best-effort
     line found by locating the body's first line in the file; and a raw-line feeder for
     `cloud-init-*.yml`, also used as the fallback for any file PyYAML cannot parse (stderr note, never a
     silent skip). PyYAML must be importable in the CI job that runs the lint (the precedent lint already
     imports it; confirm in the shard that runs `scripts/lint-shell-trace-credential-refusal-repo`).
  4. Make the discovery list a measured set: `git ls-files` pathspecs verified to match at least one real
     file each (`hr-when-a-plan-specifies-relative-paths-e-g`).
- Investigate and fix the known miss: `discord-setup.sh` array-held `Authorization: Bot` header must be
  flagged (RED row first).
- Seed `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` with the measured counts for every
  file the widened arm flags, MINUS files S1 converts (the four community scripts). Use
  `--write-baseline-e` only AFTER Phase 2 conversions and only on a tree rebased onto current
  `origin/main` (see Sharp Edges on #9632). `web-private-nic-guard.sh`'s line is whatever the lint
  reports; do not hand-edit it.
- Update the lint docstring's Rule E block (members, the YAML scope, the vocabulary, the `--changed`
  decision and its reason, the known blind spots: bodies, URLs, `env -i`, `wget`, `gh api -H`, `-K` files
  with default umask).

### Phase 2: Community scripts (user-run, no production trigger)

- `plugins/soleur/skills/community/scripts/discord-community.sh` (line ~220) and `discord-setup.sh` (the
  `curl_args` array, line ~74): Bot token through `--config -` with a process substitution, `--disable
  --noproxy '*'` first, token-shape guard before the call (`_bearer_ok`; Discord tokens are base64url
  with dots), refusal reports through the script's existing error path (read its alert/exit semantics,
  do not reuse a sibling's marker). `discord-setup.sh` currently has neither `--disable` nor
  `--noproxy`; add both (Rule D debt, same call).
- `bsky-setup.sh` (line ~268) and `bsky-community.sh` (line ~237): the createSession body carries the app
  password and a user-supplied handle. Use the `configure-auth.sh` precedent: body written by
  `jq -n --arg` directly to a 0600 `mktemp -t` file and sent with `--data-binary @file` (not `-d @file`,
  which strips CR/LF); trap cleanup per `lint-trap-tempfile-ownership.py`; explicit JSON
  `Content-Type`. Double-escaping an arbitrary handle into a config string is the fragile alternative and
  is not used.
- `plugins/soleur/skills/flag-bootstrap/SETUP.md`: the five `curl ... -H "Authorization: Api-Key $TOKEN"`
  examples become the stdin-config form (docs only; Rule E does not scan Markdown, so the row is a
  `git grep` row in the battery).
- Every curl keeps its own `< <(printf ...)`; never one config across calls; no pipe form in bash
  scripts (SIGPIPE).

### Phase 3: review SKILL.md extraction and Sharp Edge (item 4)

1. Pre-check the pinned anchors stay in SKILL.md (all measured outside lines 1183 to 1441): the
   `lifecycle-handoff-protocol` marker (line 14), `run only the suites targeting the files they were given`
   (197), `TEST_GROUP=affected bash scripts/test-all.sh` (198), `SOLEUR_SUBAGENT` (200, 213),
   `plugins/soleur/lib/workflow-fidelity.ts` sentinel test (`workflow-fidelity.test.ts` reads the
   SKILL), and `fanout-suite-scope.test.sh` arms 4 and 8d. Re-grep before moving; none may land in the
   moved range.
2. Create `plugins/soleur/skills/review/references/defect-classes.md` with the 150 bullets and the
   lead-in paragraph moved verbatim (byte identity: moved bytes equal removed bytes, checked with
   `wc -c` and a diff of the concatenation). Header line in the `wfs.md` style: loaded from SKILL.md when
   synthesizing findings.
3. In SKILL.md keep the `### Defect Classes This Review Reliably Catches` heading, and replace the body
   with a `**Read [defect-classes.md](./references/defect-classes.md) now**` directive (markdown link,
   not a backtick path: `plugins/soleur/AGENTS.md` compliance checklist and the components test at
   `describe("No backtick file references in skills")`), placed under the Findings Synthesis step so it
   loads where findings are classified and, per ADR-229's ledger, off every earlier turn. State the three
   Read pages (the catalogue is far above one Read page) as `plan/SKILL.md` does for
   `plan-sharp-edges.md`. Keep the existing `[workflow suites](./references/wfs.md)` bullet in SKILL.md.
4. Add the Sharp Edge, one bullet, in `### Sharp Edges: Review Agent Limitations` next to the existing
   "Parallel review batches can stall silently" bullet: a seat whose last transcript block is a
   `tool_use` has not delivered; read its last assistant text with `jq` (never `Read` or `tail` the
   JSONL, which floods context), then `SendMessage` "make no further tool calls, reply now with the
   report"; the "completed" notification fires per pause, not at the end. Evidence: PR #9654, about 9 of
   12 seats. Name the learning file as the source.
5. Byte budget as a delta (recorded before writing the prose): ceiling 477,000, current 476,997; the move
   removes 250,787 bytes of body; the directive adds about 700 bytes and the new bullet about 1,100, so
   the expected result is about 227,000 bytes. Assert the measured result, not this estimate.
6. Do not touch frontmatter `description:` (no description-budget movement); do not raise
   `skill-body-budget.json`.
7. Verify: `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`,
   `bun test plugins/soleur/test/components.test.ts` (reachability of `references/*.md`, no backtick
   references, description word budget unchanged), `bash plugins/soleur/test/fanout-suite-scope.test.sh`,
   `bun test plugins/soleur/test/workflow-fidelity.test.ts`.

### Phase 4: Verification (committed-tree form, before the single push)

`git add` and commit first, then run (a lint that enumerates with `git grep` run on untracked files
passed locally and failed in CI last time). All must exit 0:

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
    `npx markdownlint-cli2` over the plan and `tasks.md` (a hard tab inside a quoted command or a list
    glued to the line above its heading blocks the work phase's first commit)
Never print, echo or grep for a credential value in any of these; compare secrets by outcome only. No
`git stash`; no pattern-matching process kill.

### Phase 5: PR

- PR body, first line: "Merging this PR does not mutate production: no path under
  `apps/web-platform/infra/`, no apply workflow, no `.tf`" (the answer to whether the merge alone mutates
  production, from the diff and the workflows' `paths:` triggers). Then: `Ref #9597`, `Ref #7797` (no
  `Closes`), the slice table, the honest review-coverage line, the
  census numbers, the note that S1 touches no `apps/web-platform/infra/**` path (so no production apply
  fires), and the #9632 sequencing note.

### Phase 6: Tracking (same session, as deferral-tracking requires)

- File one issue per later slice (S2, S3, S4, S5), each with what, why, re-evaluation criteria, blocked-by
  edges (`gh issue edit <N> --add-blocked-by <M>`: S5 blocked by S3 and S4; S4 by the S3 helper) and a
  milestone from `knowledge-base/product/roadmap.md`.
- Restate the #9597 body with the slice table and the corrected measurements (35 argv / 55 hits;
  apply workflow 6 not 12; cutover-inngest.sh 20 sites; the 18 non-Bearer YAML sites). Comment on #7797
  and #7898 (what S1 closed of its section 3); leave both open. Comment on #8767 pointing at S2 and the
  stale argv half.

## Slice Contracts (later PRs; each filed as an issue in Phase 6)

**S2: ops and runner scripts (no push-to-main production effect).** `scripts/cutover-inngest.sh` (20
HMAC + CF-Access sites; also finishes #8767: report the HTTP code only, never the body; `::add-mask::`
the Doppler-read `HCLOUD_TOKEN`; decide the tier row `cutover-inngest.yml::cutover` in
`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, because `create_image` is
a write; carries `Closes #8767`), `scripts/betterstack-query.sh` (`-u`; about 12 suites drive it through a
stub host, so the shim must keep them green), `scripts/check-deploy-script-parity.sh`,
`scripts/followthroughs/{canary-promotion-5875,infra-config-activation-7220,infra-config-fatal-channel-7220,inngest-soak-6178}.sh`,
`apps/web-platform/scripts/github-app-key-status.sh`, the HMAC helper (D4), and the
`scripts/sweep-followthroughs.sh` env hop (decision row, D-table above). Heartbeat-URL probes: decide
convert-or-document (not lintable). Proof: shim battery plus each script's owning suite.

**S3: workflow YAML that cannot fire production on merge (dispatch, schedule, pull_request only) and
low-risk composite actions.** Creates `scripts/lib/bearer-curl.sh` (D3) with its own battery rows;
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
for dispatch workflows a `gh workflow run <file> --ref <branch>` smoke on the branch copy; pull_request
workflows prove themselves in CI.

**S4: push-triggered, non-apply production-class files.** `restart-inngest-server` (4),
`deploy-inngest-image` (2), `apply-inngest-rls` (4), `apply-github-infra` (1), `web-platform-release` (5),
`apply-deploy-pipeline-fix` (6), `.github/actions/mint-infra-app-token` (2; a failure here blocks every
apply), `.github/actions/dispatch-web-redeploy/track.sh` (2),
`apps/web-platform/infra/{push-infra-config,infra-config-verify,ci-deploy}.sh` (these live under
`apps/web-platform/infra/**`, so merging them FIRES the production apply). Before editing any
`apps/web-platform/infra/*` file, enumerate every push-triggered workflow whose `paths:` include it
(`apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` both list infra files) and state
whether its `-target` graph reaches the change and whether its guard counts the change class. Merge is a
declared production effect: operator awareness before merge, outcome-verified after (the markers or runs named in
the slice issue), plus the python3-on-host row for `ci-deploy.sh`.

**S5: the apply workflow and its sibling, last and separate.** `apply-web-platform-infra.yml` (6 argv
sites; the file lists itself in its own push paths, so the merge fires a PRODUCTION push apply on main:
operator awareness, no batching with anything else) and `apps/web-platform/infra/cloud-init-registry.yml`
(4 sites, inline form because it is baked into the registry host). BEFORE the conversion, relocate
comment prose from the apply workflow to `apply-web-platform-infra-job-rationale.md` (keeping the
`# Rationale:` pointer lines) so the file ends smaller than 485,630 bytes; acceptance records the byte
delta explicitly (`wc -c` before and after, gate 490,000). The cloud-init change must show no host
replacement in the plan (the destroy-guard filter is a push trigger too). Carries `Closes #9597` once
baseline E holds only entries owned by other tracked work (the nic-guard line while #9632 is open).

## Files to Edit (S1)

- `scripts/lint-shell-trace-credential-refusal.py`
- `scripts/lint-shell-trace-credential-refusal.test.sh`
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`
- `tests/scripts/test-argv-bearer-sweep.sh`
- `plugins/soleur/skills/community/scripts/discord-community.sh`
- `plugins/soleur/skills/community/scripts/discord-setup.sh`
- `plugins/soleur/skills/community/scripts/bsky-setup.sh`
- `plugins/soleur/skills/community/scripts/bsky-community.sh`
- `plugins/soleur/skills/flag-bootstrap/SETUP.md`
- `plugins/soleur/skills/review/SKILL.md`
- `scripts/guard-vacuity-floor.test.sh` only if a new floor must be registered (it is also a #9632 file;
  rebase rather than resolve by hand)

## Files to Create (S1)

- `plugins/soleur/skills/review/references/defect-classes.md`
- `knowledge-base/project/specs/feat-one-shot-argv-bearer-sweep-tier3/{tasks.md,session-state.md,decision-challenges.md,census-tier3.md}`

## Open Code-Review Overlap

None. The 87 open `code-review` issues were searched for every S1 path and for
`scripts/cutover-inngest.sh`, `scripts/betterstack-query.sh` and `apply-web-platform-infra.yml`; no body
names any of them.

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
| 8 | "Check lint-skill-body-budget.py and the skill description budget." [brief] | Phase 3 steps 5 and 6 | mapped |
| 9 | "Before pushing any conversion PR, these must pass in committed-tree form" [brief] | Phase 4 | mapped |
| 10 | "Do NOT plan those as code work; just reference them as out-of-scope operator/ops follow-ups." [brief, items 1 and 2] | Overview | mapped |
| 11 | "Do not print or echo any token value, and compare secrets without printing them. Never use git stash or a pattern-matching process kill." [brief] | Phase 4 closing line, Sharp Edges | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Lint YAML arm and non-Bearer vocabulary (Phase 1) | asks 3, 1 ("a YAML arm and a non-Bearer arm") | asked |
| `-u` detection in the lint | ask 2 ("betterstack-query.sh -u") | asked |
| Seeded baseline for YAML and non-Bearer files | ask 1 ("Rule E sees only `Authorization: Bearer`") | inferred, justification: a widened arm with no seeded baseline reds every PR, and the shrink-only equality is the enforcement contract that keeps the remainder visible |
| `--changed` stays `*.sh`-only | ask 5 ("workflow YAML runs on GitHub-hosted runners, so the blast radius and the CI-cycle cost differ") | inferred, justification: including YAML would force unrelated PRs, and the apply workflow with 4.4 KB headroom, to fully remediate |
| Phase 2 Discord, bsky, SETUP.md | ask 2 | asked |
| Fix for the `discord-setup.sh` array miss | ask 2 ("Discord Bot headers") | inferred, justification: without it the widened arm silently misses the exact file the ask names |
| Phase 3 extraction and Sharp Edge | asks 7, 8 | asked |
| Whole-section extraction choice | ask 7 ("extract a block") | asked (block chosen by D5 with alternatives measured) |
| Slice Contracts S2 to S5 and Phase 6 issues | ask 5 | asked |
| Shared helper `scripts/lib/bearer-curl.sh` (S3) | ask 1 ("apply-web-platform-infra.yml has 12") | inferred, justification: the apply workflow's byte gate and the up-to-55 duplicated guards make per-site inline conversion fail the gate or rot |
| HMAC via python3 (S2/S4) | ask 2 ("openssl -hmac in verify-tunnel-ingress-origin.sh") | asked |
| `Closes #8767` in S2 | ask 6 | asked |
| Guard Contract section | ask 9 | inferred, justification: plan Phase 2.12 requires it for any plan whose deliverable includes a guard (lint arms, ratchet) |
| decision-challenges.md and census-tier3.md | ask 4 | inferred, justification: plan-review taste findings persist there for `ship` (ADR-084); the census file is the re-measurement evidence the ask demands |

### Split Assessment

- Subsystems touched: 4 (`scripts`, `tests`, `plugins/soleur`, `knowledge-base`)
- Planned files: 12 edited + 5 created for S1 | Estimated changed lines: about 700 (lint 250, lint tests 150, battery 150, four scripts 100, baseline 35, SETUP.md 20); the review extraction moves about 250 KB in a few hundred long lines and is counted as a move, not new code
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split. The four-roots threshold is exceeded by a margin that is mostly knowledge-base artifacts; the real boundary is already drawn: S1 (this PR) is the guard plus the four user-run scripts plus the independent review extraction, and S2 to S5 are the split, each with its own issue. Within S1, Phase 3 (review SKILL.md) is an independent commit group and can be cherry-picked into its own PR if review asks for it.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 4 items 1 to 13 all exit 0 on the committed tree (list recorded in the PR body with exit codes; no credential value printed anywhere).
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide) exits 0; baseline E equals the live offender set by path and count and contains no entry for the four converted community scripts.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0 with one row per converted call site, including: token absent from argv, exact stdin config, refusal row (token containing CR/LF, quote, space: curl never invoked), must-PASS row with the real token shape, and the `--data-binary @file` body rows for both bsky scripts.
- [ ] `git grep -nE -- '(-H|--header)[ =]+"?Authorization: (Bot|Bearer|Api-Key)' -- <four community scripts> plugins/soleur/skills/flag-bootstrap/SETUP.md` returns no hit.
- [ ] `git diff --name-only "$(git merge-base HEAD origin/main)"..HEAD` contains no path under `apps/web-platform/infra/` and neither `.github/workflows/apply-web-platform-infra.yml` nor `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (a merge cannot fire the production push apply).
- [ ] `wc -c plugins/soleur/skills/review/SKILL.md` is below 477,000 with the new Sharp Edge present; `plugins/soleur/test/skill-body-budget.json` unchanged; `references/defect-classes.md` bytes plus SKILL.md bytes account for the original 476,997 plus the link directive plus the new bullet (move is verbatim).
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (reachability names `defect-classes.md`, no backtick path references, description budget untouched).
- [ ] PR body: `Ref #9597`, `Ref #7797` (no `Closes`), slice table, honest review-coverage statement, #9632 sequencing note.
- [ ] `gh issue list --state open --search '9597 in:body' --json number,title` lists four issues titled for S2, S3, S4 and S5, each with a milestone; the #9597 body names all four numbers and carries the corrected measurements (`35` argv sites, `6` in the apply workflow, `20` in `cutover-inngest.sh`).

### Post-merge (verified by outcome)

- [ ] The next `main` CI run is green on `scripts/lint-shell-trace-credential-refusal-repo` and on the `rule-body-lint` and skill-budget jobs.
- [ ] No infra apply run was triggered by the merge commit: `gh run list --workflow apply-web-platform-infra.yml --branch main --limit 3 --json createdAt,headSha --jq '.[].headSha[0:10]'` does not print the merge commit's first 10 characters (the form was executed during planning and prints three SHAs).

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
    detection: the census rows in the lint test suite (measured zero false positives on the 9 comment/echo and 11 stdin hits)
    alert_route: red lint test suite before merge
  - mode: a converted community script refuses a valid credential and goes quiet
    detection: battery must-PASS row with the real token shape
    alert_route: red battery before merge (the plugin runs on an installed user's CLI, so there is no server-side sink; the refusal prints to stderr and exits non-zero)
logs:
  where: CI logs of the test shard; PR body records the census table
  retention: GitHub Actions default
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py plugins/soleur/skills/community/scripts/discord-community.sh plugins/soleur/skills/community/scripts/discord-setup.sh
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
credential-bearing header or a `-u` operand with a variable on its own argument list, except in files
listed in baseline E by exact path and count.

**Assembly.** Discovery chokepoint: `rule_e_files()` (new) feeding `check_rule_e` through two feeders: the
PyYAML `run:`-body extractor for `.github/**` and the raw-line feeder for `cloud-init-*.yml`; the parallel
path `check_file` (A to D, `*.sh` only) must NOT receive YAML. Vocabulary chokepoint: the single credential
constant read at five sites (held-name capture, array capture, `_e_scan` header branch, call-level
`bearer_in_call`, wrapper-site `bearer_ctx`), enumerated by `grep -n` over the lint file, not by line
numbers in this plan. Argument-shape forms the vocabulary must cover: `-H "X"`, `-H"X"`, `--header X`,
array elements, wrapper functions, `-u`/`--user`. Entry points: repo-wide run (baseline equality),
explicit paths (baseline bypassed), `--changed` (`*.sh` only, by D1).

**Mutation matrix.**

| # | Edit (must drive RED) | Reddens |
|---|---|---|
| 1 | Add a second argv credential site (a `CF-Access-Client-Id` header) in a baselined workflow YAML after a compliant first site | repo-wide equality (count mismatch) |
| 2 | Revert discovery so YAML files are not scanned (`rule_e_files()` returns only `*.sh`) | census row asserting the YAML population reached `>= 100` files and the 35 Bearer sites |
| 3 | Narrow the vocabulary back to `Bearer` only | rows for `Bot` (array form in `discord-setup.sh`), `CF-Access-Client-Id`, `X-Signature-256`, `-u "$U:$P"` |
| 4 | Drop the dispatch of the new arm (the lint reports `0 checked` and exits 0) | non-vacuity floor on files scanned and sites found (`-lt N` anti-vacuity floor) |
| 5 | Add a third non-Bearer header in a new `*.sh` after a compliant stdin one | rule E finding for that file |
| 6 | Seed a baseline line with a count lower than live (hide one site) | equality failure naming the file |
| 7 | Add the same credential header in a YAML folded scalar (`run: >-`), in an inline `run: curl ...` step and in a double-quoted-escaped inline step, each after a compliant literal-block step | one finding per shape; a raw-line feeder scores 0 of 3, so this row reddens a regression to it |
| 8 | Make the extractor skip a step whose `shell:` key is absent or a composite-action step (`runs.steps[*]`) | row asserting a composite-action fixture and a no-`shell:` fixture are both scanned |
| 9 | Make an unparseable YAML file skip silently | row asserting the raw-line fallback fires and the stderr note appears |

**Harness rows.** (a) Make the test suite's fixture YAML loader return an empty list: the per-fixture rows
must red, not pass over nothing. (b) Make the fixture runner ignore the exit status: the RED rows
(which expect exit 1) must fail the suite. Must-PASS inputs that are not the canonical, and that the
contract explicitly permits: a `run:` step whose `shell:` is `python` (not bash, skipped by the precedent
lint) containing the header text, an echo of a
runbook line containing `-H "Authorization: Bearer $X"` inside a YAML `run:` string, a `printf ... | curl
-H @-` stdin form, a comment line, and a `curl ... --config -` form with a process substitution; none
may be flagged (the measured 9 doc and 11 stdin hits are the real-world corpus for these).

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
| 4 | Make `jq` write the bsky body with the password on argv (`-d "$body"`) | body-not-on-argv row |
| 5 | Drop one script from the battery's dispatch list | row-count and vacuity floor |

**Harness rows.** (a) Make the shim record stdin to the wrong path: every stdin row reddens. (b) Make
the shim stop reading the `--data-binary @file` body: the bsky rows redden. Must-PASS non-canonical
inputs: a Discord-shaped token with dots and dashes; a bsky handle containing dots and a password with
dashes, plus a handle containing a double quote that must be refused or escaped correctly (never reach
curl unescaped).

**Anchor.** Rule E equality on the converted files (their baseline lines are deleted in the same diff)
plus the battery row count recorded in the PR body.

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
   sites in 16 files flagged; the 9 doc and 11 stdin hits not flagged; 53 sites in 22 files once the
   vocabulary is widened (the prototype's per-file table is the oracle, re-measured in Phase 0).
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
7. review SKILL.md: Sharp Edge present; `defect-classes.md` linked and reachable; moved bytes identical;
   pinned anchors still found; body below the ceiling.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `--changed` and explicit paths bypass the baselines, so any file named explicitly must be fully remediated; do not leave a half-converted file.
- Merging anything under `apps/web-platform/infra/**`, or `apply-web-platform-infra.yml` itself, fires a PRODUCTION push apply. S1 must not touch those paths; the acceptance row diffs the path list.
- PR #9632 edits baseline E, the A/B/C and D baselines, `scripts/guard-vacuity-floor.test.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh`. If it merges during the ~35 minute cycle, baseline E equality fails for a reason unrelated to the code: rebase, regenerate with `--write-baseline-e` on the rebased tree, re-run the lint. Never hand-edit the nic-guard line and never touch #9632's worktree.
- Do not Read or `tail` a subagent's JSONL transcript; use `jq` on its last assistant text, and send "make no further tool calls, reply now" to a seat that ended on a tool call.
- Never `printf ... | curl` in bash scripts (SIGPIPE when the consumer does not read stdin); each curl gets its own `< <(printf ...)` and never shares a config across calls.
- `_bearer_ok` covers token shapes only. Anything with spaces, `"`, `:` or `\` (user:password, an OAuth1-style header) needs `_cfg_ok`/`_cfg_q`; a too-narrow charset silently refuses a valid credential and the script goes quiet. Keep `_bearer_ok` verbatim so the lint equality holds.
- Before choosing the marker a refusal emits, read the alert predicate of that marker family: a `*_SKIPPED` row never pages (the learning behind this plan).
- Anti-vacuity floors: `-lt N` on the `if` plus the lower-case text `anti-vacuity floor`; an upper-case spelling or a `-ne N` form is invisible to `scripts/guard-vacuity-floor.test.sh`.
- The YAML arm must not regress to raw-line feeding for workflows: raw lines miss folded scalars and inline `run:` steps (measured 0 of 4); the mutation matrix row 7 exists for this. Cloud-init files are the one place raw lines are right.
- Run every lint on a committed tree: `git grep`-based lints do not see untracked new files.
- No heredocs inside workflow `run: |` blocks; pass `${{ }}` values through `env:`; Doppler-fetched secrets are not auto-masked.
- Every secret comparison and log check avoids printing values (no `echo`, no `grep` of a value, no `set -x`).
- The review extraction is verbatim: do not "tidy" moved bullets; the byte-identity check is the proof, and the pinned anchors must be re-grepped on the tree being committed.
- The `description:` frontmatter of the review skill is not edited; the cumulative word budget is a different gate from the body byte ceiling.
