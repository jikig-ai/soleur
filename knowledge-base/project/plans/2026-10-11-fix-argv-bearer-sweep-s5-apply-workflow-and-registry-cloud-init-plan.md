---
title: "fix(security): argv-bearer sweep S5, the apply workflow and the registry cloud-init off the process command line"
date: 2026-10-11
slug: argv-bearer-sweep-s5-apply-workflow-and-registry-cloud-init
branch: feat-one-shot-9597-argv-bearer-sweep-s5
issue: 9597
closes: 9597
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-11
**Sections enhanced:** Hypotheses (network-outage deep-dive), Encryption Posture (new), Downtime & Cutover (new), Research Insights (verification pass)
**Agents used:** six-seat plan review at plan time (DHH, Kieran, code-simplicity, architecture, spec-flow, CTO at the devex lens) and a CPO sign-off advisory; deepen-plan gates 4.5, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.12 run mechanically; verify-the-negative and cited-number sweeps run inline (the research fan-out was spent at plan time and the plan's risk is delivery, not an unfamiliar technology).

### Key improvements

1. The deepen gates added two required sections the first draft did not carry: `## Downtime & Cutover` (the merge replaces `hcloud_server.registry`; a zero-downtime path was evaluated and is not available for a single-instance registry on one LUKS volume, so the residual is bounded and approved) and `## Encryption Posture` (the file match fires the gate; no new store or connection, the ledger rows already exist).
2. Verify-the-negative sweep, all confirmed on the tree: `hcloud_server.registry` is `-target`ed only in the three dispatch-only jobs (lines 2164, 2406, 3093), so no push-triggered job can create it; the disk-heartbeat and NIC-guard cron lines (1036, 2351) have no stderr redirect; no argv `--token` call exists (comments only); no `--insecure` or `-k` on any converted curl.
3. Cited numbers re-verified live: #9597, #9756, #9757, #9905 open; #9893, #9877, #9954, #9942, #9529, #7071 merged; #8714 and #6400 closed; #9373 open (fixed by #9942); #7904 is a closed drift issue that the drift workflow's own comment cites for its perpetually non-zero plan. ADR-084, 096, 169, 184, 185, 190, 241 and 280 exist.

### New considerations discovered

- The user_data stand-in measurement is +340 B stored for four inline copies against 588 B of slack; the single-helper default should be smaller, so no budget raise is expected.
- The ledger (`scripts/encryption-posture-ledger.json`) already carries `betterstack.logs`, `hcloud_volume.registry` and the host-to-Better Stack connection rows; S5 adds none and should not need to edit it (Phase 0 runs `lint-encryption-posture.py` to confirm).

## Overview

Slice S5, the last, of the argv-credential sweep (tracker #9597, parent #7797). S1 (#9674) widened Rule E, S2 (#9753) converted the ops and runner scripts, S3 (#9811) added the
shared library `scripts/lib/bearer-curl.sh` (ADR-280) and converted the workflows that cannot fire production, S4 (#9893, merge `3eb0238125`) converted the push-triggered production-class files.
S5 converts what Rule E still baselines on `origin/main` (`31ada28352`, measured today with the lint, not carried over): **4 files, 11 sites**.

| Baseline-E row | Sites | Disposition in S5 |
|---|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | 5 | **Converted** (library form; all four jobs carry a checkout) |
| `apps/web-platform/infra/cloud-init-registry.yml` | 4 | **Converted** (inline form; the host has no checkout, and a user_data budget) and **delivered by an automatic registry host replace on merge**; see MERGE EFFECTS |
| `apps/cla-evidence/infra/bootstrap.sh` | 1 | **Stays**: owned by #9756 (open; R2 SigV4 `--user` pair, legal-evidence upload path with its own suites) |
| `apps/cla-evidence/scripts/r2-conditional-put.sh` | 1 | **Stays**: owned by #9756 |

After S5 the baseline holds two rows (2 sites), each carrying an owner comment naming #9756, which is the tracker's own close condition ("baseline E holds only entries owned by other tracked work"). The PR carries
`Closes #9597` and `Ref #7797`; it is the only slice that does. The verification of the S4 conversions stays with #9905; S5's own first runs are read in Phase 5 and recorded on #9905 and #9597 (D8), with no new probe.

**What the measurements changed (details in "Research Reconciliation"):**

1. **Merging the registry file fires a production host replace with no human gate.** `registry-host-replace-dispatch.yml` triggers on every push to `main` that changes the rendered registry user_data and dispatches `apply_target=registry-host-replace` (`-replace=hcloud_server.registry`) after a read-only preflight. The tracker's "the plan must show no host replacement" cannot be satisfied: editing a code line of `cloud-init-registry.yml` replaces the host, and the merge is the dispatch. The registry is the fleet's sole pull path (an outage window per replace, #7071). This is the single largest effect of the slice and it is surfaced at the pre-ship stop, with a pre-built carve-out (D4).
2. **The tracker's byte-budget prose is stale.** `apply-web-platform-infra.yml` is **455,606 bytes** today (gate 490,000): #9877 retired the wipe apparatus and shrank it. No relocation of comment prose is needed; S5 adds roughly 1 KB.
3. **There are no `doppler secrets ... --token` argv calls left.** The three occurrences in the file are comments; every Doppler call uses `DOPPLER_TOKEN` in the environment. Nothing to convert.
4. **The apply workflow has 5 argv sites, not 6** (the ceiling table still says 6, and its header claims it equals the baseline; both rows leave in this PR).
5. **The registry user_data has about 588 bytes of slack** under the test's policy constant (`REGISTRY_GZIP_BUDGET = 21_600`, measured 21,012 stored; the Hetzner cap is 32,768). The library (5,670 B gzipped) cannot be baked into the host. A stand-in measurement of four inline wrapper copies (whole-template gzip delta, plan time) is **+340 B stored**, so the default (one small host helper, D5) is expected to fit without raising the constant; the rendered, comment-stripped stream from `registry-userdata-budget.sh` is the authority and Phase 0 re-measures.
6. **Only one of the five workflow sites is exercised by a merge.** Four jobs are dispatch-only, and the push-triggered `apply` job (which none of the five sites live in) is still red on main from the tainted egress resources, so its post-apply steps never run. The registry dispatch the merge itself fires does run `registry_host_replace` (site `2272`) and boots a new host that posts through the converted scripts: that is the S5 live proof, and it is read in Phase 5.
7. **The registry host cannot show a refusal marker to anyone.** The disk-heartbeat and NIC-guard cron lines have no stderr redirect (cron has no MTA), the boot block's output goes to `cloud-init-output.log`, and the log shipper ships only `CONTAINER_NAME=zot` journal rows. A refused ingest token therefore shows only as absent rows. The detector is the existing absence monitors, and Phase 0.8 reads the live token's shape (a boolean, never the value) before merge so a first-boot refusal is excluded in advance.

### MERGE EFFECTS (read first)

Evaluated by reading every workflow's `on.push.paths` against the planned file set, not from memory.

| Trigger | Fires on merge? | Why | Plan response |
|---|---|---|---|
| `registry-host-replace-dispatch.yml` (push `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`) | **Yes, and it replaces the registry host** | The rendered user_data differs (code lines change). The gate renders at the delivery watermark and at head, then runs `scripts/registry-replace-preflight.sh` (read-only; refuses when the fleet is already on its last pull tier; fails closed) and dispatches the replace. No `environment:` reviewer gate, no `confirm=` token. Recent precedent: every run of the last two weeks succeeded (latest `db6631ddb7`, run `38106711093`, the zot log shipper change, about 12 minutes, alongside a red push apply). Three ways a delivery does not complete: the preflight refuses (its P3 waits up to 35 minutes for the release the same merge fires, and about 18% of releases exceed that, so a refusal is a planned-for outcome); the dispatched run queues behind the push apply in the shared group `terraform-apply-web-platform-host` (the dispatcher's 1500 s poll then reports `unverified`); a later infra push evicts the pending dispatched run (one pending run per group). | **Explicit approval at the Phase 4 stop, before the merge**, because the merge is the dispatch (D4). Auto-merge is armed only after the approval. The approval covers the merge-triggered dispatch only; each re-fire is a separate production dispatch and needs its own approval. Phase 5 has a branch for each of the three non-completions. |
| `apply-web-platform-infra.yml` (push `apps/web-platform/infra/**` and its own file) | **Yes** | The workflow file and `cloud-init-registry.yml` match. The `apply` job runs a large `-target` list whose SSH-provisioned set does not reach `hcloud_server.registry`, so the dispatcher is the only delivery path for the host. It is **already red on main** at the "Terraform apply (SSH-provisioned resources, over the bridge)" step (runs `38128304531`, `38106710993`, `38105510474`: the tainted `cron_egress_firewall`, `egress_gateway`, `egress_gateway_web2`; the web-2 timeout), so a red run is not S5's. | Re-check before attributing (Phase 0, Phase 5). A red `apply` is S5's only if it fails in a step S5 edited. The tunnel-ingress verify stays unproven and is tracked by #9905. |
| `web-platform-release.yml` (push `apps/web-platform/**`) | Yes | Any `apps/web-platform/infra/**` edit matches. Its deploy for the same merge pulls from the registry that is being replaced. | Phase 5 expects the arm to resolve; an `image_pull_failed` inside the replace window is read as that window, not as an S5 regression, unless it persists after the replace is verified. |
| `infra-validation.yml`, `validate-vector-config.yml`, unfiltered push gates | Yes | CI gates. | `infra-validation` is **red on main** (`deploy-script-tests (4/4)`: the inngest-bootstrap pin v1.1.49 against tag v1.1.50, GuardA carrier drift, and the provisioner-parity mutation control). Not S5's and not a required check (read from the repo rulesets). Phase 0 records the failing suite names on main; Phase 4 and Phase 5 compare names, so a new failure among the suites S5 edits is not hidden by the old red. |
| `version-bump-and-release.yml` (`plugins/soleur/**`) | **No** | S5 plans no `plugins/` edit except the budget test constant `plugins/soleur/test/cloud-init-user-data-size.test.ts` (a test file, only if D6 raises it); Phase 0 re-checks the path filter against the final file set. | AC: the merge-base diff carries no `plugins/soleur/skills\|agents\|commands\|hooks` path. |
| Other apply jobs that render the same user_data (`registry_region_migrate`, `registry_luks_recut`) | At their next approved dispatch | They create the registry host from the same template, so a later dispatch boots the converted scripts. | Nothing for S5 beyond keeping their converted heartbeat steps (lines 2506, 3293) green. |
| `scheduled-terraform-drift.yml` | Daily | Full-root plan with `-detailed-exitcode`. It is already perpetually non-zero (the workflow's own comment cites #7904, a closed drift issue), so registry replace drift is **not a new signal and not a detector**. | The detector for an undelivered edit is the dispatcher's verdict comment on the PR and the owned `action-required` issue it files when nothing is derivable. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked on `origin/main`: #9597 open; #9756 open (owns the two cla-evidence rows); #9757 open (library gaps and URL-path secrets, not re-reported); #9905 open (S4 first-run probe); #9893 merged; #9877 merged (it retired the wipe apparatus; the S4 plan's collision note is closed); #9954 merged (pin bump to v1.1.49; main has moved on to v1.1.50 since). Cited files and symbols exist (`scripts/lib/bearer-curl.sh`, both baseline files, the sweep battery, the five apply sites, the four registry sites). Stale: the 485,630-byte relocation, the `--token` calls, the site count of 6, and the "no host replacement" expectation (see Research Reconciliation). Mechanism against the ADR corpus: ADR-280 decides stdin config through one library and allows the inline wrapper where a pinned property rules out sourcing a repo file; ADR-096 and ADR-190 decide that registry user_data delivery is an immutable replace through the dispatcher. No rejected alternative is re-proposed.

**Property List.**

- P1. After S5, no curl in `apply-web-platform-infra.yml` or `cloud-init-registry.yml` carries a credential header on its own argument list.
- P2. A refused credential lands in the same verdict class as the failure it replaces, and never in a class that asserts an unmeasured cause (in particular, the gating Hetzner existence probe stays fail-closed).
- P3. A registry user_data change reaches the host only through a delivery an operator approved with the merge effects in view.
- P4. Baseline E holds only rows owned by tracked work, and the ratchet cannot be loosened by one diff alone.
- P5. The first real run of each converted site is tracked to a verdict, with no SSH.
- P6. The registry user_data stays inside Hetzner's cap and the policy headroom, and any budget raise is deliberate and recorded.

**Cut List (mechanism, property, what already covers it).**

- Relocating comment prose out of the workflow: buys the byte gate; the file is 455,606 B against 490,000, so there is no gate to buy. Cut.
- Converting the three `doppler ... --token` calls: buys P1 for Doppler; none exist on argv (comments only). Cut.
- Baking `scripts/lib/bearer-curl.sh` into the registry user_data: buys library parity on the host; 5,670 B gzipped against 588 B of slack, and a boot-time dependency on a baked file for a non-gating log post. Cut for the small host helper (D5).
- An owner column in the baseline format (parser change): buys P4's "owned by tracked work"; a comment line above each row already carries it and the reviewer gate is the anchor. Cut.
- Converting the two cla-evidence files: owned by #9756, a legal-evidence path with its own suites. Cut (recorded as a User-Challenge in `decision-challenges.md`).
- Library gaps and URL-path secrets (`--proto`, `--expand-*`, `--head`, the rc-64 marker, the `--url` prefix parse, the Slack webhook URL, psql URIs, the seed password): #9757. Cut; not re-reported.
- A new follow-through script, suite and tracker for S5's own first runs: the evidence that is certain to occur is read in Phase 5 and the dispatch-only jobs ride #9905 (D8). Cut.
- Four byte-equal inline wrapper copies plus a parity audit on the registry host: one helper is the single chokepoint (D5); the copies stay only as a measured fallback.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):

- `test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`: `hcloud_server.registry` has no `ignore_changes` on `user_data` (`zot-registry.tf` says so twice), so a "mechanical" edit is a host replace; census by what a file CARRIES, and run the sibling suites that pin text by name.
- `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md` and `best-practices/2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render.md`: measure the cap on the gzipped render (`registry-userdata-budget.sh`), prose counts.
- `best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md`: shell `${VAR}` is `$${VAR}` in the template; the existing sites already use it.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: process substitution, never a pipe; the shape guard before any curl; the ratchet is per file.
- `2026-10-06-a-refuse-before-send-guard-turned-a-paging-401-into-a-silent-skip.md`: a conversion can move a failure into a class that never pages; ask which verdict each refusal reaches.
- `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`: pair the count with set identity (the derived census in Guard 1).
- `2026-07-28-the-fix-for-a-too-noisy-alarm-shipped-five-new-ways-for-it-to-go-silent.md`: for the registry ship path ask what input makes the signal go quiet (a refused token silences the log rows; see Guard 2).
- Not covered by any learning (fresh planning): the Better Stack send-failed drift guard and its mutation pin, the `workflow_run` deploy invariants, and self-listing push paths.

## Research Reconciliation: brief and tracker text vs. codebase

| Brief / tracker claim | Reality (`origin/main` `31ada28352`, measured 2026-10-11) | Plan response |
|---|---|---|
| "`apply-web-platform-infra.yml` (6 sites; ... relocate comment prose first so the file ends smaller than 485,630 bytes, gate 490,000)" | The lint reports **5** sites (lines 2272, 2506, 2641, 2648, 3293). The file is **455,606 bytes**; headroom to the gate is 34,394 B. | No relocation. S5 adds about 1 KB; AC pins the size below 490,000 with the gate test. Ceiling table row 6 leaves with the file. |
| "plus the three `doppler secrets ... --token` calls" | `grep -n -- --token` returns three **comments** (lines 1228, 1289, 3458); the calls pass `DOPPLER_TOKEN` in the environment (#7661 G11). No argv `--token` anywhere in `.github`, `scripts`, `apps`. | Nothing to convert. Recorded so a later sweep does not re-open it. |
| "`cloud-init-registry.yml` (4 sites, inline form; the plan must show no host replacement)" | 4 sites confirmed (1017, 1332, 2319, 2669). The file renders `hcloud_server.registry` user_data (`zot-registry.tf:553`, no `ignore_changes`); an edit of a code line **replaces the host**, and the merge dispatches that replace automatically. | The plan does not claim "no replacement". It states the replacement, gates the merge on explicit operator approval (D4), and keeps a one-commit carve-out. |
| Baseline after S5 "holds only entries owned by other tracked work" | The two cla-evidence rows are owned by #9756 (open, names exactly those files). No other row. | Owner comment lines added to the baseline (D1); no format change. |
| "S5 must take the remaining 4 files / 11 sites to the final target" | The final target is the two #9756 rows (2 sites). Two files, 9 sites convert. | Stated in Overview; the brief's "4 files / 11 sites" is the starting state. |
| "`infra-validation` was red on main from cloud-init pin drift (the pin bump merged since)" | Still red: `deploy-script-tests (4/4)` fails on the inngest-bootstrap pin (v1.1.49 vs tag v1.1.50, run `38106711039`), GuardA carrier drift, and the provisioner-parity mutation control. A run on `31ada28352` was in progress at plan time. | Not S5's. Re-check in Phase 0 and Phase 4; no fix bundled. |
| "`apply-web-platform-infra` fails on the tainted egress resources ... check whether it is still failing" | Still failing on the latest three main pushes (the SSH-provisioned apply step). | Same. Attribution rule in Phase 5: a red apply is S5's only if it fails in a step S5 touches. |
| S4 plan: "S5 (`apply-web-platform-infra.yml`, `cloud-init-registry.yml`) is not planned here" | Consistent. | Carried. |
| ceiling table header: "currently IDENTICAL to the baseline" | Ceiling lists the apply workflow at 6, the baseline at 5. | Both rows leave in this change; the header sentence is corrected to describe the final state. |

## Hypotheses

The brief names a web-2 SSH timeout (tainted egress resources) as a pre-existing failure. S5 neither diagnoses nor fixes it, and none of S5's sites run in the failing `apply` job. Per the L3 to L7 order of the network-outage checklist, the firewall allow-list and DNS or routing layers are **not verified here** (they need a Hetzner credential this planning run does not read), the TLS layer does not apply to an SSH provisioner, and no service-layer hypothesis is offered. The failure is identical across three consecutive pushes (`38105510474`, `38106710993`, `38128304531`) and starts at #9529's merge; it is carried by #9905. A red `apply` job is attributed to S5 only if it fails in a step S5 edited.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

| Layer | Status | Artifact or reason |
|---|---|---|
| L3 firewall allow-list | not verified here | needs `hcloud firewall describe` with a Hetzner credential; this planning run reads none; the failing step is a `remote-exec` over the bridge to the web hosts, not an S5 site |
| L3 DNS and routing | not verified here | same; no S5 site depends on a host name that this change resolves differently |
| L7 TLS or proxy | not applicable | SSH provisioner; S5's own HTTPS calls keep default certificate verification and gain `--disable --noproxy '*'` |
| L7 application | out of scope | tracked by #9905 and the open-web-egress work; attributed to S5 only if a step S5 edited fails |

## Decisions

**D1. Scope: two files, nine sites; the two cla-evidence rows stay under #9756.** The tracker's own S5 definition lists the apply workflow and the registry file. The cla-evidence scripts are the legal-evidence upload path with their own suites (a defect there is a legal-record regression), carry a basic-auth `--user` pair rather than a bearer, and have an open owner. The baseline gets one comment line above each remaining row (`# owned by #9756`), the ceiling table the same, and `--write-baseline-e` regenerates the rest. **Challengeable (User-Challenge, persisted to `decision-challenges.md`):** folding the two files into S5 would make the baseline empty at the cost of a legal-evidence change in a last-and-alone production slice.

**D2. The five workflow sites use the library (`bc_curl`), sourced from the job's own checkout.** All four jobs (`registry_host_replace`, `registry_region_migrate`, `registry_pull_path_gate`, `registry_luks_recut`) start with `actions/checkout`; Phase 0 confirms with `scripts/lint-workflow-local-action-checkout.py` that none uses `path:`, a foreign `repository:` or a sparse cone that drops `scripts/lib`. The credentials are read in-step (`doppler secrets get BETTERSTACK_API_TOKEN --plain`, and `HCLOUD_TOKEN` exported by the `infra-credentials` composite) inside `$(...)`, which strips trailing newlines before the shape guard. The converted calls drop `2>/dev/null` so a refusal marker is visible (ADR-280, the 2026-10-10 addendum: curl's stderr is intentionally not silenced on converted calls).

**D3. Refusal verdicts (the review anchor for Guard 2).**

| Site | Old failure class | Refusal lands in | Mechanism |
|---|---|---|---|
| `2272`, `2506`, `3293` (Better Stack heartbeat status, non-gating, `set +e`) | `STATUS="unavailable (lookup failed or not yet ingested)"` | The same string; the step stays green | No pre-guard: a library rc 2 makes `BODY` empty, which is the existing "unavailable" arm. Marker visible. |
| `2641` (`registry_pull_path_gate`, gating: volume existence by id) | `PROBE_STATUS="000"` via `\|\| PROBE_STATUS="000"` | The same existing class: the step turns `000` into `unknown-000`, and only a 404 with a name count other than 0 aborts, so a refusal can never read as "absent" (the absent verdict needs a 404) | No pre-guard is expected. Phase 0.4 reads the step and **names the downstream consumer of `unknown-*`** (what it does on unknown); if any consumer treats `unknown-*` as a license to proceed, an explicit pre-guard (`bc_ok_var HCLOUD_TOKEN`, then `bc_refuse`) writes the abort the unreadable-credential branch already writes. |
| `2648` (same step: volume count by name) | `NAME_COUNT="unknown"` | The same | `[[ "$NAME_COUNT" =~ ^[0-9]+$ ]] \|\| NAME_COUNT="unknown"` already folds any non-numeric into unknown. |

**D4. The registry file converts, and its delivery is an operator-approved merge effect (default; User-Challenge).** The tracker mandates the registry rows in S5, the exposure is real (the Better Stack Logs ingest token is on argv of four scripts that run every five minutes on a host that serves the fleet's pull path), and the registry is replaced whenever its user_data changes, which has happened three times this week. The plan therefore converts it **in its own commit** (commit 6), states the replacement as a merge effect, and the Phase 4 stop asks the operator for explicit approval of "this merge dispatches `registry-host-replace`". **Approval semantics.** The stop shows the Phase 0.2 preflight reading or "could not read"; auto-merge is armed only after the approval (a dispatcher with no reviewer gate plus an armed auto-merge would make the approval easy to bypass by accident, and auto-merge can fire hours later); the approval covers the merge-triggered dispatch only, each re-fire is a separate production dispatch with its own approval, and a BEHIND PR is brought up with `git merge origin/main` and re-approved, never synced silently. **Carve-out (pre-built and structural):** everything registry-specific (the template, the helper, the suites, the battery's registry rows, the registry baseline and ceiling rows, the budget constant, the ADR registry paragraph) sits in the LAST commit (C3), so the carve-out is dropping a trailing commit, not reverting from the middle. The new tracker issue that owns the four rows (maintenance-window delivery) is filed before the drop, the baseline then keeps the registry row (6 sites in total), and the PR still carries `Closes #9597` because every remaining row is owned by tracked work. Phase 4 dry-runs the drop (`git revert --no-commit` of C3 in a scratch worktree, then the baseline and battery gates) so the recipe has been executed before it is needed. Either branch satisfies the close condition; the default converts because the exposure is live and the delivery path is routine and verified.

**D5. The four registry sites post through one host helper written by cloud-init and sourced by the four scripts (default); four inline copies are the fallback.** The host has no checkout (0 `git clone` references; cloud-init-only per ADR-096) and the library does not fit the budget, so the host-side form is a pinned-property exception in the sense of the ADR-280 inline-wrapper clause (no repo on the host rather than a checkout-free job). Plan review (CTO, simplicity, architecture) preferred one chokepoint to four byte-equal copies plus a parity audit: a `write_files` helper (path final in Phase 0, for example `/usr/local/lib/soleur/bs-post.sh`) holds the `betterstack_ingest_url` once, reads `BETTERSTACK_LOGS_TOKEN` by name, judges it (non-empty, `[A-Za-z0-9._~+/=-]`) before any request, and posts with `curl --disable --noproxy '*' -fsS -m 10 -H 'Content-Type: application/json' --config - "$URL" --data-raw "$PAYLOAD" < <(printf 'header = "Authorization: Bearer %s"\n' ...)`. The **per-command stdin redirect is load-bearing**: the boot block runs under `doppler run ... -- bash -s <<'ZLSBOOTEOF'` (and `ZOTEOF` for the earlier block), where stdin IS the script, so a bare `--config -` would swallow the rest of the heredoc. `-m 10` stays (`zot-http-deadlines-required.test.sh` parses it). A refusal prints `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=token_shape` to stderr and takes the **existing not-shipped branch** (the one the token-unset case takes), never the egress-FAILED retry branch, and never changes the caller's exit status (cron jobs must not wedge). The shipper judges the credential **once per run**, before its batch loop, so a refusal is one line per five-minute run. A missing or unreadable helper takes the same not-shipped branch (`[ -r ... ] || not-shipped`), never an argv fallback. **Fallback (decided in Phase 0.5):** if the suites that execute these scripts (`zot-log-shipper.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `private-nic-guard.test.sh`) can provide the helper only through a test-only seam in production code, use four inline copies of one canonical text pinned byte-equal by a parity audit in the battery (the same device `hm_audit` is for the HMAC snippet; measured cost +340 B stored). The registry marker is not observable from Better Stack (Overview item 7), so it is not read by any probe.

**D6. The user_data budget is measured, then raised only by the measured delta.** Phase 0.5 renders the candidate (helper, and the four-copy fallback for comparison) with `registry-userdata-budget.sh` (gzipped, base64, the authority). The plan-time stand-in is +340 B for four copies against 588 B of slack, so no raise is expected. If the measured stored bytes exceed `REGISTRY_GZIP_BUDGET` (21_600), the constant is raised by at most the measured overshoot plus a small margin (no round-number padding: three raises in three weeks, 20,000 to 21,000 to 21,600, with 3,167 B of runway left to the 24,767 B ceiling), with the precedent comment block and an ADR-185 amendment that also reconciles #9373's raise, which has no ADR record. Anything that would cross 24,767 B is a policy change and stops the slice.

**D7. The Better Stack drift guard and its mutation pin: measure, edit only if false.** `SOLEUR_CREDENTIAL_REFUSED` is already in `NON_PAGING_MARKERS` of `betterstack-send-failed-alert.test.sh` (measured today: `67 passed, 0 failed (9 cases)`), and the guard scans `cloud-init*.yml`, so the converted registry file is in its population. Phase 0.5 runs the guard and its mutation suite on the converted file. The rationale string is edited only if the measurement shows it false (it says the marker never enters web-1 journald, which stays true), and the pin 67 moves only if the measured pass count moves, deliberately and with the reason beside the constant. The marker stays NON_PAGING; no `logger` priority call is added (a crit `logger` would page).

**D8. No new follow-through script, suite or tracker (plan review: DHH, the CTO and the simplicity seat converged; cut).** The only soak-shaped criterion would be "the dispatch-only jobs run once", which may not happen in 30 days and would end in operator-triggered noise, and #9597 closes with the PR (there is no soak-gated close, so Phase 2.9.1 enrollment does not apply). The evidence that is certain to occur is read in Phase 5: the merge's own dispatched `registry_host_replace` run (the heartbeat-status step concluded `success` AND no refusal line in that job's log, because the step is non-gating and a refusal also ends green), the new host's first rows (`SOLEUR_ZOT_LOG_BOOT` for the new `boot_id`, then `SOLEUR_ZOT_DISK`), the release arm, and the push apply attributed by step. The three dispatch-only jobs are recorded as a comment on #9905, whose probe already scans apply-workflow run logs for the marker (Phase 0.9 confirms by reading the script's scan scope; if it does not cover dispatch runs of `apply-web-platform-infra`, the comment says so and no probe edit is made in S5).

**D9. Rule A to D do not reach the two YAML files, and the plan does not pretend they do.** The lint's `--changed` mode is shell-only and its own source states YAML is excluded from Rules A to D (around line 1184), so a clean `--changed` run proves little about these files. The checks that bind are the explicit-path Rule E run, the derived census (Guard 1) and the executed-body rows (Guard 2). The gate's own `--changed --base origin/main` invocation is still run, because that is what CI runs.

**D10. Not in S5 (each with its owner).** #9757 (library gaps, URL-path secrets, held-back arms; not re-reported), #9756 (the two cla-evidence rows), #9905 (S4 first-run probe, including the unproven tunnel-ingress verify), #9294 (rotation of the deploy secrets; S5 reduces argv exposure and rotates nothing), the tainted egress resources and the web-2 timeout (open-web-egress work), the inngest-bootstrap pin drift and the provisioner-parity suite (main-health, not S5), and the Markdown that agents execute (Rule E blind spot, recorded in the lint docstring).

**D11. `Closes #9597` closes the tracker at merge, and the plan says what that does not close.** The tracker's own instruction closes it with S5 once baseline E holds only owned rows. The registry host keeps the argv form until the replace is delivered, and the apply workflow's dispatch-only jobs run only on an approved dispatch. Phase 5 comments the delivery verdict on #9597; if delivery is not confirmed by the end of Phase 5 (refused, queued out, evicted, still unverified), an `action-required` issue owns the delivery, so the open exposure always has a named owner.

## Census and per-site contract

**Workflow sites** (`.github/workflows/apply-web-platform-infra.yml`; checkout at lines 2081, 2323, 2585, 2982):

| Line | Job (dispatch-only) | Step | Credential and source | Form | Verdict (D3) |
|---|---|---|---|---|---|
| 2272 | `registry_host_replace` (runs on the merge's own dispatch) | Best-effort heartbeat status (non-gating) | `BETTERSTACK_API_TOKEN`, `doppler secrets get` into `TOKEN` | library | unavailable |
| 2506 | `registry_region_migrate` | same step name | same | library | unavailable |
| 2641 | `registry_pull_path_gate` | Resolve recovery posture (D4 live existence probe) | `HCLOUD_TOKEN`, loader-exported | library | fail-closed abort |
| 2648 | `registry_pull_path_gate` | same step | same | library | unknown |
| 3293 | `registry_luks_recut` | Best-effort registry disk heartbeat status (non-gating) | `BETTERSTACK_API_TOKEN` | library | unavailable |

**Registry host sites** (`apps/web-platform/infra/cloud-init-registry.yml`; credential `BETTERSTACK_LOGS_TOKEN`, injected by `doppler run` from the isolated soleur-registry/prd config; URL is the templated `betterstack_ingest_url`):

| Line | Script (write_files or runcmd) | Posts | Cadence | Refusal marker `script=` |
|---|---|---|---|---|
| 1017 | `/usr/local/bin/zot-disk-heartbeat.sh` (`post() { ...; }`, retry once) | `SOLEUR_ZOT_DISK` | cron every 5 min, and once at boot | `zot-disk-heartbeat` |
| 1332 | `/usr/local/bin/zot-log-shipper.sh` (`post_body()`, once per batch) | journal rows | cron `3-59/5` | `zot-log-shipper` |
| 2319 | `/usr/local/bin/soleur-private-nic-guard.sh` (`post()`) | `SOLEUR_PRIVATE_NIC` | cron | `soleur-private-nic-guard` |
| 2669 | runcmd boot block | `SOLEUR_ZOT_LOG_BOOT` | once per boot | `zot-log-boot` |

Whole-repo transport grep (the stub holders). Phase 0 runs the suites that EXECUTE or pin the converted bodies, and CI runs the rest; none is edited unless it is measured red, and none is weakened. Executed or pinning the bodies: `zot-log-shipper.test.sh`, `zot-disk-heartbeat-redaction.test.sh` (asserts on the captured POST body), `private-nic-guard.test.sh`, `registry-boot-guard.test.sh`, `plugins/soleur/test/zot-http-deadlines-required.test.sh` (parses the `-m 10` deadline), `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`, `plugins/soleur/test/heartbeat-live-reconcile.test.ts` and `terraform-target-parity.test.ts` (both read the workflow step names, which must not change), and `apps/web-platform/test/infra/betterstack-send-failed-alert*.test.sh`. The registry template is rendered through `templatefile()` (`$${VAR}` and `%%{http_code}` unescape only on render), so every body-executing row runs against the **rendered** output of `registry-userdata-budget.sh --json <out>`, not the raw template.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) the registry host replace fires on merge and the registry, the fleet's sole pull path, is unavailable for the replace window, so a production deploy in that window cannot pull its image (running web hosts keep serving); (b) a converted gating step refuses a valid credential and the recovery-posture probe aborts, blocking a registry recut; (c) a converted registry script stops shipping its rows, so the disk, private-NIC and log-channel alarms read absence as health or page falsely.
- **If this leaks, the user's workflow is exposed via:** the Hetzner API token (`HCLOUD_TOKEN`, full infrastructure authority) and the Better Stack API and Logs-ingest tokens on a process command line, readable by every local user through `/proc/<pid>/cmdline` and `ps` on the runner and, for the ingest token, on the registry host. The conversion removes that channel; a mistake that instead prints a value (a verbose flag, a trace, an echoed refusal) would put the token in a run log.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the Hetzner token is infrastructure-wide authority and the registry replace is a production-impacting operation fired by a merge, so one leaked value or one unplanned replace window reaches every user; `aggregate pattern` would understate the registry effect, and `none` does not hold for a production host replace. Same tier as S4. CPO sign-off at plan time is required (`requires_cpo_signoff: true`); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-280** (status stays `adopting`) with an S5 addendum, authored in this PR as a task of Phases 2 and 3, not a follow-up: the final state of baseline E; the registry-host form (a cloud-init-written helper) and its pinned property (no repo on the host, and the user_data budget: the library measured 5,670 B gzipped against 588 B slack), bounded by a new byte-equal parity audit over the four copies; the refusal-verdict table (D3); the statement that merging a registry user_data change delivers by an automatic replace (cross-referenced to ADR-169/ADR-190 and the runbook, which already decide it); the two cla-evidence rows and their owner. If the user_data constant is raised, an **ADR-185** addendum records the new constant and its headroom, per the existing precedents in the test file. No new ADR: S5 follows decisions already recorded. No ADR-241 change (S5 names no new `secrets.*` and moves no tier classification).

### C4 views

Read in full in Phase 0: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Enumerated against them for this change: (a) external human actors: none added or changed; (b) external systems: Better Stack (Logs ingest and the uptime API), the Hetzner Cloud API, the self-hosted zot registry (`zotRegistry`), GitHub Actions runners, Doppler: all already modeled, and S5 adds no edge (the credential channel changes, the edges do not); (c) containers and data stores touched: the registry host and its volume, already modeled; (d) actor-to-surface access relationships: unchanged. Expected conclusion: **no C4 change**, backed by `bash plugins/soleur/test/c4-count-parity.test.sh` (green at plan time: `Failed: 0`) re-run in Phase 0 and Phase 4. If the read finds a description the change falsifies, the `.c4` edit lands in this PR and `c4-code-syntax` and `c4-render` run.

### Sequencing

The ADR describes the target state; the registry portion becomes true only after the delivered replace (Phase 5 verifies it). The status stays `adopting` until the delivery verdict is recorded (Phase 5).

## Infrastructure (IaC)

No new resource, vendor or secret. The change edits existing IaC inputs and one workflow.

### Terraform changes

None to `.tf` files. `cloud-init-registry.yml` is a template input of `hcloud_server.registry.user_data` (`zot-registry.tf:553`); no provider, pin or `TF_VAR_*` changes.

### Apply path

(a) cloud-init-only for the registry host, delivered by the existing dispatcher's `-replace='hcloud_server.registry'` (ADR-096, ADR-190; the volume is preserved, `store_destroyed==0`), not by an edit on the running host. Expected blast radius: one pull-path outage window; the preflight refuses when the fleet is already on its last tier and fails closed. The workflow edit needs no apply of its own beyond the merge-fired push run, which is red on main for unrelated reasons.

### Distinctness / drift safeguards

`dev != prd` is untouched (no Doppler config changes). The drift workflow shows the registry user_data difference until the delivery lands (MERGE EFFECTS); the carve-out leaves that drift in place deliberately only if the new tracker owns its delivery.

### Vendor-tier reality check

Better Stack: the heartbeat status read and the Logs ingest are unchanged calls; no tier-gated resource is created.

## Downtime & Cutover

**The offline-inducing operation.** Merging a code-line change of `cloud-init-registry.yml` makes `registry-host-replace-dispatch.yml` dispatch `-replace='hcloud_server.registry'`: the registry host is destroyed and recreated (the data volume and its LUKS key are preserved, `store_destroyed==0`). The surface it affects is the fleet's only container pull path, for the length of the replace.

**Zero-downtime paths evaluated.**

| Path | Verdict |
|---|---|
| Blue-green (a second registry host, cut over, old retired) | Not available: zot runs as a single instance at a fixed private address (`10.0.1.30:5000`, hard-wired in the web hosts' pull configuration) on one LUKS volume that attaches to one server at a time; a second host would need a second store and a pull-path cut-over, which is its own project (ADR-096 and ADR-190 decided the replace shape and retracted the host-to-GHCR fallback, #7071). |
| Edit the running host in place | Rejected by the repo's rules (immutable redeploy for production host configuration) and by the host being cloud-init-only with no edit path. |
| State-only re-address | Does not apply: the bytes of the rendered user_data change. |
| Deliver later, in a window already scheduled for another registry change | **The carve-out (D4).** Because the dispatcher batches every render input since its watermark into one replace, deferring the four rows costs nothing structural. |
| Comment-only edit | Does not deliver (the gate renders and compares bytes), but also converts nothing. |

**Residual downtime, accepted with a bound.** One replace window, measured at about 12 minutes on the most recent comparable run (`38106711093`), during which a production deploy cannot pull its image and running web hosts keep serving. Bounds: the read-only preflight refuses when the fleet is already on its last pull tier and fails closed; the operator approves the merge at the Phase 4 stop with the merge time chosen away from an active release; each stage has a verification (the dispatcher's gate summary and `store_destroyed==0`, the dispatched run's conclusion, then the new host's `SOLEUR_ZOT_LOG_BOOT` and `SOLEUR_ZOT_DISK` rows for the new `boot_id`); and the rollback is the existing runbook `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` plus dropping C3 and re-delivering. The CPO sign-off conditions apply.

## Encryption Posture

No new persistent store and no new cross-component connection: S5 changes how a credential reaches `curl`, not where data goes or what is stored. The file match (`cloud-init-registry.yml`) fires the gate, so the existing postures are cited rather than restated; `scripts/encryption-posture-ledger.json` already carries every row below and Phase 0 runs `scripts/lint-encryption-posture.py` against the converted template to confirm S5 moves none of them.

```yaml
at_rest:
  - store: hcloud_volume.registry
    mechanism: luks
    evidence: apps/web-platform/infra/cloud-init-registry.yml (luksFormat/luksOpen with the escrowed key) and the ledger row for hcloud_volume.registry
    defends_against: a seized or RMA'd disk, a raw volume snapshot
    does_not_defend: a leaked credential, an app-layer read on the unlocked live host, exfiltration through a compromised zot process, and the reboot window with the volume unlocked
    disclosed_as: the ledger's disclosed_as field for this store
    live_verification: available (the registry host's LUKS rows, followthroughs/registry-luks-live-8386.sh)
  - store: betterstack.logs
    mechanism: provider-managed:betterstack-encrypted-at-rest
    evidence: ledger row betterstack.logs (attestation URL and retrieval date recorded there)
    defends_against: provider-side disk loss
    does_not_defend: a leaked ingest token, a compromised Better Stack account, anything after the log row is delivered
    disclosed_as: the ledger's disclosed_as field for this store
    live_verification: unavailable:the provider exposes no per-source at-rest probe
  - store: the helper file written by cloud-init (root disk)
    mechanism: plaintext-exception
    evidence: the helper holds code and a public URL only; the token is read from the process environment that `doppler run` provides and is never written to disk by this change
    defends_against: not applicable, there is no secret in the file
    does_not_defend: a local root reader reading the helper text (which carries no secret)
    disclosed_as: not-publicly-claimed
    live_verification: available (Phase 0.8 and the rendered-output rows confirm the helper text carries no token literal)
in_transit:
  - connection: registry host -> Better Stack Logs ingest (s2457081.eu-fsn-3.betterstackdata.com)
    enforced_at: apps/web-platform/infra/zot-registry.tf:127 (local.betterstack_logs_ingest_url, https) and the helper's single curl
    tls: https; the minimum version is curl's default on the host and is not pinned by this change
    cert_verification: on (no `--insecure` or `-k` anywhere in the converted file, checked by grep)
    does_not_defend: a leaked ingest token, a compromised provider account, metadata of the request
    disclosed_as: ledger row `hosts -> Better Stack (heartbeats + Logs API)`
  - connection: GitHub Actions runner -> Better Stack uptime API and Hetzner Cloud API
    enforced_at: .github/workflows/apply-web-platform-infra.yml lines 2272, 2506, 2641, 2648, 3293 via scripts/lib/bearer-curl.sh (`--disable --noproxy '*'` first)
    tls: https; minimum version is the runner curl's default
    cert_verification: on (the library unsets the environment variables that redirect TLS trust)
    does_not_defend: a leaked API token and a compromised provider account
    disclosed_as: ledger row `hosts -> Better Stack (heartbeats + Logs API)`
exception:
  justification: the helper file carries no secret, so plaintext on the root disk exposes nothing
  tracking_issue: "#9597"
  reevaluate_when: the helper ever gains a credential literal or a token cache
  expires_on: 2027-01-09
```

## Observability

```yaml
liveness_signal:
  what: Better Stack Logs rows from the registry host (SOLEUR_ZOT_DISK every five minutes, SOLEUR_PRIVATE_NIC, shipper rows, and one SOLEUR_ZOT_LOG_BOOT per boot, read per new boot_id) and the workflow jobs concluding success with no SOLEUR_CREDENTIAL_REFUSED line in their logs
  cadence: every 5 minutes (host rows), per dispatch (workflow jobs)
  alert_target: the existing Better Stack absence monitors and the zot disk and private-NIC alarms (unchanged); the dispatcher's verdict comment and owned issue for the delivery
  configured_in: apps/web-platform/infra/cloud-init-registry.yml, apps/web-platform/infra/uptime-alerts.tf, .github/workflows/registry-host-replace-dispatch.yml
error_reporting:
  destination: GitHub Actions run log (layer 6) for the workflow sites, where the value-free marker and the ::error:: annotation are visible; for the registry host the marker goes to stderr only and is NOT observable from Better Stack (no cron redirect, no MTA, boot output in cloud-init-output.log, shipper selects only CONTAINER_NAME=zot), so the registry-host signal is the ABSENCE of rows (layer 3)
  fail_loud: workflow sites end in a red step, a visible annotation or the existing honest soft class (D3 table); registry-host refusals are loud only through the absence monitors, which is why Phase 0.8 reads the live token shape before merge; a refusal is never paged (stated, matching ADR-280)
failure_modes:
  - mode: a stored credential falls outside the shape alphabet or carries a control byte (workflow sites)
    detection: the marker line in the run log, read in Phase 5 for the merge's own dispatch and by the #9905 probe's marker scan for later runs
    alert_route: red step or visible annotation per site
  - mode: the registry host stops shipping rows after the replace (a refused, empty or missing ingest token, or a missing helper)
    detection: absence of SOLEUR_ZOT_LOG_BOOT and SOLEUR_ZOT_DISK rows for the new boot_id, read with scripts/betterstack-query.sh; the existing absence monitors
    alert_route: the existing zot disk and log-channel alarms; Phase 5 treats absent rows as a failed delivery and files the owning issue
  - mode: the merge's registry replace is refused, queued out, evicted or fails mid-run
    detection: the dispatcher's verdict comment on the PR, its refusal artifact, the apply run conclusion (queued behind the push apply, cancelled by a later infra push, or unverified after the 1500 s poll)
    alert_route: PR comment and the owned action-required issue; re-fire only with a fresh approval
  - mode: a refusal reads as "volume absent" in the recovery-posture probe
    detection: Guard 2 row 1 executing the real step with a refused token
    alert_route: pre-merge CI red
  - mode: a new argv credential header appears in either converted file
    detection: Rule E baseline equality plus the derived census in the sweep battery
    alert_route: pre-merge CI red
logs:
  where: GitHub Actions run logs for workflow sites; Better Stack (registry source) for host rows
  retention: GitHub run logs 90 days by default; Better Stack per the source's retention (read the connection's setting before relying on it past 30 days)
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py .github/workflows/apply-web-platform-infra.yml apps/web-platform/infra/cloud-init-registry.yml
  expected_output: "OK:"
```

(Measured at plan time: the command runs in 0.3 s and prints `9 violation(s) in 2 scanned file(s)` before the work; it must print `OK:` after. Affected-surface note: the registry host is a blind surface; its in-surface signals are the rows it posts. They discriminate a missing token (the existing WARN line, which is also lost to cron's void), a refused token and an egress failure only by absence, which is stated rather than claimed otherwise.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Do ONE slice per PR: S5 only, and stop there." [brief] | Overview; D1; D10 | mapped |
| 2 | "S5 must take the remaining 4 files / 11 sites to the final target. Read the baseline and its list from the lint before planning." [brief] | Overview table; Census; Phases 1 to 3 | mapped |
| 3 | "`apply-web-platform-infra.yml` (6 sites; ...) plus the three `doppler secrets ... --token` calls, and `cloud-init-registry.yml` (4 sites, inline form; the plan must show no host replacement)." [issue #9597] | D2, D3, D4, D5; Research Reconciliation rows 1 to 3 | mapped (the "no host replacement" expectation is falsified and answered by D4) |
| 4 | "`Closes #9597` here once baseline E holds only entries owned by other tracked work." [issue #9597] | D1; Phases 2 and 3; AC | mapped |
| 5 | "Do not re-report them, and do not bundle them into S5 unless the plan says so." [brief] | D10; Cut List | mapped |
| 6 | "Known pre-existing failures on main (not S5's, do not fix in this PR)" and "Check whether it is still failing before treating a red apply as yours." [brief] | Hypotheses; MERGE EFFECTS; Research Reconciliation; Phase 0; Phase 5 | mapped |
| 7 | "Do not print or echo any token value, and compare secrets without printing them." [brief] | D2, D5; Guard 2 harness rows (negative canary); AC | mapped |
| 8 | "Poll with Monitor, never Bash run_in_background." and "Merge with gh pr merge --squash --auto. Never sync a BEHIND armed PR." [brief] | Phase 4, Phase 5 | mapped |
| 9 | "Before ship, stop and get explicit operator notice. A production-apply dispatch needs explicit operator approval each time." [brief] | D4; Phase 4 stop | mapped |
| 10 | "After merge, run deploy-arm.sh find --wait <FULL merge sha>, then served from a detached origin/main worktree, before any post-deploy action." [brief] | Phase 5 | mapped |
| 11 | "Known CI guards that bit S4: infra no-human-steps lint, the Better Stack send-failed drift guard and its mutation baseline pin, the workflow_run deploy invariants (G8), and the rename-guard (5% copy detection ...)" [brief] | D7, D8; Phase 0; Phase 4; AC | mapped |
| 12 | "Measure what you can without SSH, and report plainly what you could not." [brief] | Observability; Phase 5; "What could not be measured" in Risks | mapped |
| 13 | "The refusal marker is SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape\|control_char>. It is NON_PAGING in the Better Stack drift guard, and the mutation baseline is pinned at 67." [brief] | D5, D7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/apply-web-platform-infra.yml` edit | "`apply-web-platform-infra.yml` (6 sites; ...)" (ask 3) | asked |
| `apps/web-platform/infra/cloud-init-registry.yml` edit | "`cloud-init-registry.yml` (4 sites, inline form ...)" (ask 3) | asked |
| baseline and ceiling rows (`scripts/lint-shell-trace-credential-refusal-e.baseline.txt`, `rule-e-census-ceiling.tsv`) | "S5 must take the remaining 4 files / 11 sites to the final target" (ask 2) | asked |
| owner comment lines in the baseline and ceiling | "once baseline E holds only entries owned by other tracked work" (ask 4) | asked |
| S5 stage in `tests/scripts/test-argv-bearer-sweep.sh` | "Do ONE slice per PR" (the slice's own ratchet) | inferred: S3 and S4 each added a stage, and the lint "cannot decide ordering statically", so the guard-before-curl rows live in the battery |
| budget constant edit in `plugins/soleur/test/cloud-init-user-data-size.test.ts` (conditional) | "inline form" (ask 3) | inferred: the existing size test fails closed above 21_600 B stored and the measured slack is 588 B |
| `betterstack-send-failed-alert*.test.sh` rationale and pin | "NON_PAGING in the Better Stack drift guard, and the mutation baseline is pinned at 67" (ask 13) | asked |
| sibling suite edits (`zot-*.test.sh`, `private-nic-guard.test.sh`, `registry-boot-guard.test.sh`), only where measured red | "Known CI guards that bit S4" (ask 11) | inferred: they execute or pin the bodies being converted and go red if left untouched; edited only where measured red |
| ADR-280 addendum of about ten lines (and an ADR-185 amendment only if the constant moves) | "Closes #9597" (ask 4) | inferred: plan Phase 2.10 makes the ADR a deliverable of the plan that changes the recorded decision |
| `scripts/lint-shell-trace-credential-refusal.py` docstring (once) and the baseline and ceiling header comments | "Closes #9597" (ask 4) | inferred: the docstring and the ceiling header describe states that stop being true, and the header comment carries the #9756 owner so no row is edited adjacent to a carve-out hunk |
| `knowledge-base/project/specs/feat-one-shot-9597-argv-bearer-sweep-s5/{tasks.md,decision-challenges.md}` | "Do ONE slice per PR" | inferred: the pipeline's own artifacts (tasks derive from the plan; the User-Challenge channel is ADR-084) |

### Split Assessment

- Subsystems touched: 6, roots `.github`, `apps/web-platform`, `scripts`, `tests`, `plugins`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: about 600 (the battery stage is most of it)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — proposed boundary: S5a (workflow, battery rows, baseline rows for the apply file, ADR addendum) and S5b (registry file, its suites, the budget constant, the host-side rows). **Not taken** (DHH argued for the split as the default; recorded as DC-3 in `decision-challenges.md`), with the reason: the operator's brief is "Do ONE slice per PR: S5 only" and the tracker defines S5 as one last-and-alone PR and the only closing one, and two PRs would leave a baseline with a registry row and no owner between them. The seam is kept as a **commit boundary** (C3 holds everything registry-specific and is the last commit) so it can be split or dropped without rework (D4 carve-out).

## Guard Contract

### Guard 1 — No tracked file outside the #9756 rows puts a credential header on a curl argument list, and the converted sites keep it that way (population derived from the tree)

**Property.** After S5, Rule E reports exactly two sites repo-wide (the two cla-evidence rows), the baseline and the ceiling table each hold exactly those two rows, and no `curl` in the two converted files carries a credential header, `-u` or `--user` operand of its own.
**Assembly.** (a) Rule E over the whole tree (YAML arm for workflow `run:` bodies, raw lines for cloud-init), compared to the baseline by EQUALITY on path and count; (b) the ceiling table, checked in both directions; (c) a battery census derived from the tree, not a count: every non-comment `curl` word in the registry template's Better Stack posting scripts sits inside the helper (set identity by script), and every `bc_curl` in the five apply steps has the library `source` line earlier in the same step, which also catches credential shapes Rule E's vocabulary does not know (its recorded blind spots); (d) the structural rule from ADR-280 decision 4 (`lint-workflow-local-action-checkout.py`: usable checkout, no sparse cone dropping `scripts/lib`). The chokepoints are two: the library `_bc_send` (workflow) and the host helper (registry).
**Mutation matrix.** (each in a scratch copy; assert the mutation landed with `diff -q`; an unmutated control first)

| # | Mutation | Must go RED |
|---|---|---|
| 1 | restore `-H "Authorization: Bearer $TOKEN"` in the helper (or one script) | Rule E on the explicit path and the census |
| 2 | add a **second** credentialed curl to a registry script after a compliant first (the shipper's loop) | the census compares sets by script, not "at least one clean" |
| 3 | **reorder:** move the `source scripts/lib/bearer-curl.sh` line below the first `bc_curl` in one step; and move the registry guard call below the first post | the ordering rows (they judge position inside the step and the script, which a delete-only matrix cannot) |
| 4 | **dispatch:** empty the derived population (rename the anchor the census greps for) | the anti-vacuity floor on the census (a literal floor, `-lt`) |

**Harness rows.** (a) a recording curl stub that ignores `--config -` makes "credential reaches stdin, not argv" go red (a suite edit, not a guard edit); (b) must-PASS inputs that are not the canonical: a 64-character alphanumeric Hetzner-shaped token and a Better Stack token containing `_` and `-`; the library trims a trailing blank, the host helper refuses it (the stated, asserted divergence; the library also refuses a leading blank, which the S4 inline workflow sites trim, and the host helper refuses); (c) the census runs against a synthesized tree whose only registry curl is compliant (must-PASS) and against one with an extra member (must-FAIL); (d) a negative canary: a distinctive fake credential planted and searched for in every captured stream on every refusal and error path.
**Anchor.** The merge-base diff plus the reviewer gate on baseline shrink-only is the independent control; the ceiling table is a second file a loosening must edit in the same diff; CODEOWNERS already covers the library, the workflow and `apps/web-platform/infra/` (`@deruelle`). Stated: the guard proves the set and its shape, not that the set is the right set (the blind spots recorded in the lint docstring remain).

### Guard 2 — A refusal reaches the same verdict class as the old failure, on every converted site

**Property.** For each site, a refused credential produces the verdict class of the failure it replaces (D3 table) and never a class that asserts an unmeasured cause; the gating volume-existence probe stays fail-closed, and a registry script keeps its exit status, its not-shipped branch and the rest of its heredoc.
**Assembly.** The real step bodies (extracted from the committed workflow, and for the registry the RENDERED user_data, not the raw template) executed against a recording curl: the three heartbeat-status steps, both curls of the posture step, the four registry scripts (the shipper's batch loop and the boot block's heredoc context included). The chokepoint is the D3 sink table; a fifth site added later is caught by the derived census in Guard 1.
**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| 1 | map a refusal (rc 2) of the existence probe to a 404 or to an arm that proceeds | the fail-closed row (a refused token must reach `unknown-*` and the consumer's abort or hold) |
| 2 | registry: let a refusal fall into the egress-FAILED retry branch (`post \|\| post \|\| echo`) | the not-shipped-branch row (marker count and branch taken) |
| 3 | shipper: move the guard inside the batch loop | the once-per-run row (exactly one marker per run for N batches) |
| 4 | a refusal changes a registry script's exit status | the cron-must-not-wedge row |
| 5 | drop the guard (curl called with an unusable token) | the shape row (zero requests on a refused value; the recording curl sees none) |
| 6 | silence a converted workflow call with `2>/dev/null` | the marker-visible row |
| 7 | drop the per-command stdin redirect in the boot block (`--config -` reads the heredoc) | the heredoc row (the line after the post still runs) |

**Harness rows.** the unmutated control first; must-PASS realistic tokens (as Guard 1); a negative canary; the rendered output passes `bash -n` for every script and runcmd block, so an escape error in the template (`$${VAR}`, `%%{http_code}`) cannot pass on raw text.
**Anchor.** The D3 sink table is the review anchor; a weakening has to edit the table and the step in one diff.

## Implementation Phases

Three commits, ordered so the carve-out is dropping the LAST one (D4). Each commit passes its own gates; the RED rows are written first (Phase 0.7) and land in the commit whose behaviour turns them green.

### Phase 0: Gates, measure, replay, then RED

0.1 Re-measure on `origin/main`: baseline and census lint output (expect 4 files / 11 sites), file sizes, the latest `apply-web-platform-infra` and `infra-validation` runs with the **failing suite names recorded** for the later comparison, and the dispatcher's last successful watermark.
0.2 Registry readiness (no SSH): read the header of `scripts/registry-replace-preflight.sh` for its modes and credentials (documented usage `[--manual] | --print-asset | --check-asset`); run only a mode that is read-only and whose credentials are reachable without a write scope, and read the fleet's pull-tier state from the data the preflight reads (`scripts/betterstack-query.sh`); otherwise record that it could not be measured. The result goes into the Phase 4 stop.
0.3 Read the three `.c4` files; run `bash plugins/soleur/test/c4-count-parity.test.sh`.
0.4 Replay the **real** argument lists of the five workflow curls through `_bc_tail_ok` (a refusal turns that site into a plan amendment, not a library edit); read the posture step and **name the consumer of `unknown-*`** (D3); confirm each job's checkout with `lint-workflow-local-action-checkout.py`.
0.5 Registry measurement: draft the helper and the four-copy fallback, render each with `registry-userdata-budget.sh` and record stored bytes against 21,600 (D6); decide helper vs fallback by whether the three executing suites can provide the helper without a test-only seam in production code (D5); run the Better Stack drift guard and its mutation suite on the candidate (D7); confirm the rendered scripts and runcmd blocks pass `bash -n`.
0.6 Run the suites in the transport-grep list on the unchanged tree to record baseline pass counts.
0.7 Write the RED rows first (Guard 1 and Guard 2 matrices, the S5 battery stage, the baseline and ceiling expectations parametrized on whether the registry commit is present) and run them against the unconverted tree: they must fail for the right reasons.
0.8 Live credential shape (booleans only, never printed, compared in-process without echo): read `BETTERSTACK_LOGS_TOKEN` (soleur-registry, prd), `BETTERSTACK_API_TOKEN` and `HCLOUD_TOKEN` (prd_terraform) read-only from Doppler and check each against the guard alphabet and the no-control-byte rule. A mismatch on the registry token is a stop (the new host would boot blind); a mismatch on a workflow credential is a plan amendment. If Doppler is unreachable, record "could not measure" in the Phase 4 stop.
0.9 Read `scripts/followthroughs/bearer-curl-s4-first-runs-9905.sh` for the run-log scan scope (D8).

### Phase 1 (commit C1): the five workflow sites and the workflow's baseline rows

Lines 2272, 2506, 3293 (library form, marker visible, the `STATUS` arm unchanged); lines 2641 and 2648 per D3; the battery rows for the workflow sites (Guard 1 rows 1, 3, 4 and Guard 2 rows 1, 5, 6 as they apply); `--write-baseline-e` and the ceiling row removed by hand for the apply file; `wc -c` below 490,000 and the size, target-parity and heartbeat-reconcile suites green.

### Phase 2 (commit C2): final-state documentation that does not depend on the registry commit

The #9756 owner comment as a HEADER comment of the baseline and of the ceiling table (not adjacent to any row, so dropping C3 does not conflict), the one-time lint docstring and ceiling-header correction, and the ADR-280 S5 addendum (about ten lines: the final baseline, the owners, the replace-on-merge statement, the pinned-property wording for the host form; the registry paragraph sits in C3's hunk).

### Phase 3 (commit C3, LAST; the carve-out unit): the registry file

The template change (helper written by `write_files`, four call sites converted, the once-per-run shipper guard, the per-command stdin redirect in the boot block), sibling suites edited only where measured red, the battery's registry rows (Guard 1 rows 1, 2 and the census; Guard 2 rows 2, 3, 4, 7 and the rendered-output rows), the budget constant and its comment block only if D6 measures over (with the ADR-185 amendment), the registry baseline and ceiling rows removed, and the registry paragraph of the ADR-280 addendum.

### Phase 4: pre-push verification and the operator stop

Run the gates by their OWN invocations (see Acceptance Criteria), `git merge origin/main` if behind (never a rebase of an armed PR), the three-tier review, and the **dry-run of the carve-out** (`git revert --no-commit` of C3 in a scratch detached worktree, then the baseline, lint and battery gates; the result is recorded). **Stop and give the operator explicit notice.** The notice leads with: "Merging dispatches `registry-host-replace` on production, with no reviewer gate." It then names the replace-window impact (production deploys cannot pull images while running web hosts keep serving) and a deliberately chosen merge time (not during an active release; a preflight refusal, which happens in about 18% of cases, is expected and harmless), and: the merge dispatches `registry-host-replace` (D4), the Phase 0.2 reading or "could not read", the queueing, refusal and eviction outcomes and that each re-fire needs its own approval, the push apply being already red, which conversions are unproven until a dispatch, the budget decision, the Phase 0.8 result, and the carve-out option. No merge and no armed auto-merge until the operator approves. Merge with `gh pr merge --squash --auto` after approval; poll with Monitor, never a background Bash.

### Phase 5: post-merge verification (no SSH)

`bash plugins/soleur/scripts/deploy-arm.sh find --wait <FULL 40-hex merge sha>` (one verdict line; a short sha matches nothing); then `deploy-arm.sh served <sha>` from a detached `origin/main` worktree, before any other post-deploy read. Then read, in order: the dispatcher's verdict comment and the dispatched `registry-host-replace` run (its gate summary and `store_destroyed==0`; whether it queued behind the push apply, was evicted by a later infra push, or ended `unverified`; a refused preflight is re-fired only with a fresh approval); the new host's rows with `scripts/betterstack-query.sh` (`SOLEUR_ZOT_LOG_BOOT` for the new `boot_id`, then `SOLEUR_ZOT_DISK`; absent rows are a failed delivery and file the owning issue, and the fix is a Doppler value change, not code); the `registry_host_replace` job's heartbeat-status step concluded `success` AND its log carries no refusal line; the push `apply` run attributed by step (D8 and MERGE EFFECTS); the failing-suite names of `infra-validation` against the Phase 0.1 record; the release arm, reading an `image_pull_failed` inside the replace window as that window unless it persists after the replace is verified. Comment the delivery verdict on #9597 and the dispatch-only jobs on #9905 (D8, D11).

## Baseline and ceiling rows

| File | Before | After |
|---|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | baseline 5, ceiling 6 | row removed from both |
| `apps/web-platform/infra/cloud-init-registry.yml` | 4 / 4 | row removed from both (kept, with a new owner, only on the carve-out) |
| `apps/cla-evidence/infra/bootstrap.sh` | 1 / 1 | stays; owner comment `#9756` |
| `apps/cla-evidence/scripts/r2-conditional-put.sh` | 1 / 1 | stays; owner comment `#9756` |
| Total | 4 files / 11 sites | 2 files / 2 sites |

## Test Scenarios

1. The five workflow steps executed with a valid synthesized credential: each curl sees `--disable --noproxy '*'` first, the credential only on stdin, and no argv carrying it.
2. The same steps with a credential outside the alphabet and with a control byte: zero requests, one value-free marker line, the D3 verdict.
3. The volume-existence probe with a refused token reaches the ABORT arm (not "absent").
4. The four registry scripts extracted from the committed cloud-init and run against stubbed `curl`, `doppler`, `docker`: valid token posts through the wrapper; an unusable token prints one marker per run and takes the not-shipped branch; exit status unchanged.
5. The four wrapper copies are byte-equal; one changed byte is caught.
6. The rendered registry user_data stays under the size test's constant and under `HETZNER_CAP`.
7. The Better Stack drift guard and its mutation suite are green at the measured count; the marker stays NON_PAGING.
8. Rule E repo-wide: `OK` with 2 baselined sites; explicit paths on both converted files: `OK:`.
9. `--changed --base origin/main` over the final file set: `OK`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Rule E repo-wide reports `OK` with **2 baselined sites**; the baseline and the ceiling table each hold exactly the two cla-evidence rows, with the `#9756` owner in their header comment; `python3 scripts/lint-shell-trace-credential-refusal.py .github/workflows/apply-web-platform-infra.yml apps/web-platform/infra/cloud-init-registry.yml` prints `OK:` (it printed `9 violation(s)` before). On the carve-out, the registry row stays with a new owner and the count is 6 sites.
- [ ] `wc -c .github/workflows/apply-web-platform-infra.yml` is below 490,000 and `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
- [ ] The S5 battery stage passes in full (the Guard 1 and Guard 2 rows, mutation rows judged red by name, harness rows, negative canary) locally, with the registry rows present and, in the dry-run, with C3 dropped; no row was weakened to pass.
- [ ] The rendered registry user_data (`registry-userdata-budget.sh --json <out>`) has stored bytes at or below `REGISTRY_GZIP_BUDGET` and below the Hetzner cap, every rendered script and runcmd block passes `bash -n`, and the repo's template validation (`.github/scripts/test/fixtures-validate-infra-templates.sh`, and `cloud-init schema` when the tool is installed) passes. If the constant moved, it moved by the measured overshoot plus a small margin, its comment block and the ADR-185 amendment are in the diff, and no value above 24,767 B.
- [ ] `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` and its mutation suite are green; the pin is 67 unless the measured count moved, with the reason beside the constant.
- [ ] Every suite in the transport-grep list passes at its Phase 0 count or higher; `heartbeat-live-reconcile.test.ts` and `terraform-target-parity.test.ts` pass with the workflow step names unchanged.
- [ ] The failing-suite names of `infra-validation` on the PR equal the Phase 0.1 record from main (no new name), and the lists are in the PR body.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` is green; the C4 conclusion cites the actors, systems and relationships enumerated above.
- [ ] The gates run with their OWN invocation, not a hand-listed path set: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` are clean (the plan, the spec directory and the ADR addendum are in the changed set; the second is shell-only and is run because CI runs it); a local run of the rename-guard over the PR range reports no rename or copy into an allowlisted path (no new `*.test.sh` under `apps/web-platform/infra/`).
- [ ] `git diff --name-only origin/main...HEAD` (merge-base form) carries no `plugins/soleur/skills|agents|commands|hooks` path (no plugin release run) and no `*.tf` path; the only `plugins/` path allowed is the budget test constant, and only if D6 raised it.
- [ ] `bun test apps/web-platform/test/git-lock-marker-telemetry.test.ts` (with the package's own runner; read `package.json` `scripts.test` first) passes: `SOLEUR_CREDENTIAL_REFUSED` is already a registered marker and S5 adds only new `script=` values.
- [ ] The Phase 0.8 result (booleans) is in the PR body; no token value appears in the PR body, commit messages, test output or logs.
- [ ] The carve-out dry-run is recorded in the PR body, and the PR body carries `Closes #9597`, `Ref #7797`, the MERGE EFFECTS table, the carve-out option, the pre-existing failures with their re-check results, and the residual stated plainly: the registry host keeps the argv form until the replace is delivered, so "Closes" is not "fully remediated".

### Post-merge (verification, no SSH)

- [ ] `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full merge sha>` prints `ARM=<id> ... MATCH=exact|descendant DEPLOY=success`, and `served` reports the merged build; `/health` reports it with `supabase: connected` (or the replace-window reading in Phase 5 is recorded).
- [ ] The dispatcher recorded a verdict on the PR and the `registry-host-replace` run it dispatched succeeded with `store_destroyed==0`; or the non-completion was handled per Phase 5 (a re-fire only with a fresh approval, an owning issue filed).
- [ ] Better Stack (read with `scripts/betterstack-query.sh`) shows `SOLEUR_ZOT_LOG_BOOT` for the new `boot_id` and `SOLEUR_ZOT_DISK` rows after it (the positive proof; the marker is not observable on this host).
- [ ] The `registry_host_replace` job's heartbeat-status step concluded `success` and its log carries no `SOLEUR_CREDENTIAL_REFUSED` line; the same read on any other new `apply-web-platform-infra` run.
- [ ] The push `apply` run on the merge sha is attributed by step (red in the tainted-resource step is not S5's); the tunnel-ingress verify stays with #9905.
- [ ] #9597 closes with the PR; the delivery verdict is commented on it; the dispatch-only jobs are commented on #9905.

## Domain Review

**Domains relevant:** Engineering, Operations, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** (CTO seat, devex lens, run at plan review) the conversion is mechanical and ADR-280 already decides its shape; the risks are delivery and long-term maintainability. Prefer one cloud-init-written helper to four byte-equal copies (adopted, D5, with a measured fallback); keep the registry rows with a pre-merge approval stop and arm auto-merge only after it (adopted, D4); cut the new follow-through script and fold the dispatch-only jobs into #9905 (adopted, D8); raise the budget only by the measured delta, never past 24,767 B (adopted, D6). Complexity: medium; the 14-file test surface the first draft carried dominated, now trimmed.

### Product (CPO)

**Status:** reviewed (plan-time sign-off for `requires_cpo_signoff: true`: approve with conditions)
**Assessment:** the `single-user incident` tier is right and keeping the registry rows in this PR is justified because the exposure is live; C3-last is the right carve-out design. Conditions adopted: the Phase 4 notice leads with the no-reviewer-gate sentence and names the replace-window impact, the Phase 0.2 reading, the three non-completions and the dry-run; no armed auto-merge before explicit approval and a BEHIND PR is re-approved, never silently synced; the merge time is chosen deliberately; if approval is declined or does not arrive, C3 is dropped after tracked work owns the rows; the Phase 0.8 token-shape read happens before merge; the no-echo, no-trace criteria stay. Closing #9597 at merge is acceptable only with the residual stated plainly in the PR body ("Closes" is not "fully remediated": the registry host keeps the argv form until the replace is delivered) and the delivery verdict commented on #9597 before the work is called done; an unconfirmed delivery at the end of Phase 5 makes the `action-required` issue mandatory.

### Operations (COO)

**Status:** reviewed
**Assessment:** the merge dispatches a production host replace with only a read-only preflight as a gate, so the pre-ship notice must say so, including the queueing, refusal and eviction outcomes and that every re-fire needs its own approval. The dispatcher's verdict comment, refusal artifact and runbook (`registry-host-replace-dispatch.md`) are the existing operating surface, so no new operational step is created, and nothing here is a manual step: the replace and its verification are automated and read without SSH.

## Open Code-Review Overlap

None (queried the open `code-review` issues against the eight primary files: the two converted files, the baseline, the lint, the budget test, the drift guard test, the battery, the library).

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml`
- `apps/web-platform/infra/cloud-init-registry.yml`
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`
- `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`
- `scripts/lint-shell-trace-credential-refusal.py` (docstring, once)
- `tests/scripts/test-argv-bearer-sweep.sh` (S5 stage)
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (budget constant, only if Phase 0.5 measures over 21_600)
- `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` and `betterstack-send-failed-alert-mutation.test.sh` (only if the measurement shows the rationale false or the count moved)
- `apps/web-platform/infra/zot-log-shipper.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `private-nic-guard.test.sh`, `registry-boot-guard.test.sh` (only where measured red; never weakened)
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (S5 addendum)
- `knowledge-base/engineering/architecture/decisions/ADR-185-*.md` (amendment, only if the constant moves)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9597-argv-bearer-sweep-s5/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9597-argv-bearer-sweep-s5/decision-challenges.md`

## Risks and Sharp Edges

- **The merge replaces the registry host.** The preflight can refuse, the dispatched run can queue behind the push apply or be evicted by a later infra push, and a refused delivery leaves the host on the argv form. The carve-out exists for a declined approval; for a non-completion after merge, Phase 5 files the owning issue and every re-fire needs a fresh approval. Nothing in S5 fires a dispatch itself.
- **A refused ingest token silences the registry host's rows, and no marker can be read there.** The helper takes the not-shipped branch (the same as an unset token); the absence monitors are the detector, and Phase 0.8 reads the live token shape before merge so a first-boot refusal is excluded in advance.
- **The template is rendered.** `$${VAR}` and `%%{http_code}` unescape only through `templatefile()`, so tests that execute scripts run the rendered output; an escape error produces a host that boots wrong with no SSH, and a re-dispatch re-renders the same bytes.
- **The budget raise is policy-adjacent.** Above 24,767 B stored the slice stops; below it the raise equals the measured overshoot plus a small margin and is recorded.
- **A plan section that is empty, or contains only placeholder text, or omits the threshold, fails `deepen-plan` Phase 4.6.** `## User-Brand Impact` above is filled; keep it so.
- **Guard-before-curl is not statically decidable by the lint.** The battery's ordering rows carry it (Guard 1 row 3); a refactor that moves a guard must move its row.
- **Do not sync a BEHIND armed PR.** Use `git merge origin/main` before arming, never a rebase of an armed PR; and arm auto-merge only after the operator approval.
- **Rename-guard.** New suites are rows in existing files because a new `*.test.sh` under `apps/web-platform/infra/` that resembles an existing one trips 5% copy detection and the override label needs operator approval.
- **What could not be measured at plan time, stated plainly:** the live preflight verdict and the fleet's current pull tier (needs the preflight's credentials), the live credential shapes (Phase 0.8 reads them), the Hetzner firewall and DNS state behind the web-2 timeout, the exact stored-byte delta of the final template (the plan-time figure is a stand-in), and whether the three dispatch-only jobs run within any window (they run only on an approved dispatch). The `apply` job's post-apply steps cannot be exercised while the tainted egress resources keep it red.

## Plan Review Revisions

Six seats reviewed the first draft (DHH, Kieran, code-simplicity, architecture, spec-flow, CTO at the devex lens). Mechanical findings were applied; Taste and User-Challenge findings are in `decision-challenges.md`.

| # | Finding (seat) | Class | Disposition |
|---|---|---|---|
| R1 | The carve-out was not a one-commit revert; registry text sat in commits 1, 7, 8, 9 (Kieran, architecture, spec-flow) | mechanical | Fixed: three commits, everything registry-specific in the LAST (C3), owner comments in header comments, dry-run of the drop in Phase 4 |
| R2 | The marker is invisible on three of four registry scripts, so the "marker or absence" claim and the zero-marker AC were false or vacuous (Kieran, architecture, spec-flow) | mechanical | Fixed: absence is the detector, stated; the AC is positive (new `boot_id` rows); Phase 0.8 reads the live token shape |
| R3 | A bare `--config -` in the boot block reads the heredoc (Kieran) | mechanical | Fixed: per-command stdin redirect, Guard 2 row 7 |
| R4 | Guard 2 may execute raw template bytes (architecture) | mechanical | Fixed: rendered output, `bash -n`, template validation AC |
| R5 | The push apply is targeted, not untargeted; drift is perpetually non-zero and not a detector; queueing, poll and eviction semantics (architecture, spec-flow) | mechanical | Fixed in MERGE EFFECTS and Phase 5 |
| R6 | A refusal at line 2641 lands in `unknown-000`, so a pre-guard is likely unnecessary (Kieran) | mechanical | D3 row rewritten; Phase 0.4 names the consumer |
| R7 | Approval does not cover refusal or re-fire; auto-merge could fire hours later (spec-flow, CTO) | mechanical | D4 approval semantics; auto-merge armed after approval |
| R8 | The heartbeat-step `success` AC proves nothing (a refusal also ends green) (spec-flow) | mechanical | AC adds the no-refusal-line reading |
| R9 | Rules A to D are shell-only, so D9 was vacuous for the two YAML files (Kieran) | mechanical | D9 rewritten |
| R10 | Guard 1 mutation rows 3, 5, 7 and the container row were redundant with Rule E and the ceiling (DHH, simplicity) | mechanical | Cut rows 3 and 7 and the container row; row 5 kept as the guard's own dispatch row, which the contract requires |
| R11 | Phase 4 empty commit, nine commits, repeated docstring edit, speculative D7 string edit, long suite list (DHH, simplicity) | mechanical | Cut or folded (three commits) |
| R12 | `infra-validation` red hides S5 regressions (spec-flow) | mechanical | Failing-suite names recorded and compared |
| R13 | Four copies vs one helper (CTO, simplicity, architecture, DHH) | taste | Default one helper, measured fallback (D5) |
| R14 | New follow-through script, suite and tracker (DHH, CTO, simplicity) | taste | Cut (D8); recorded as DC-4 |
| R15 | Split the registry into its own PR as the default (DHH) | user-challenge | Not taken (operator brief: one slice per PR); DC-3 |
| R16 | `Closes #9597` before verification (DHH, spec-flow) | user-challenge | Kept per the tracker; D11 names the residual and its owner |

## Review corrections (2026-10-11, after the 10-seat panel on #9986)

Appended, not edited in place: the decisions above are dated and the record of what planning believed stays.

- **D5 outcome.** Phase 0.5 chose the FALLBACK: four inline copies of the judge (`_bs_ok`) and the stdin-config post, not a cloud-init-written helper. Reasons: the three suites that execute these scripts extract them standalone (a helper at an absolute path needs a path rewrite in each), a missing helper is a silent not-shipped on a host whose only signal is absent rows, and the measured cost fits (21,012 to 21,472 B stored against the policy constant 21,600). The ADR-280 S5 addendum records this; the "single helper is the default" wording in D5, Phase 3, tasks.md and session-state.md is superseded.
- **D8 limit.** `scripts/followthroughs/bearer-curl-s4-first-runs-9905.sh` scans the newest completed runs of the push-triggered apply job only; its REQUIRED list does not name the dispatch-only jobs, so "the dispatch-only jobs ride #9905" holds only incidentally (a dispatch run inside the scanned window is marker-scanned; nothing requires one). Phase 5 therefore reads the dispatched `registry-host-replace` run directly, as D8 already says, and the #9905 comment states this limit. No probe edit is made in S5.
- **Detector for a refused registry token.** The registry host runs no Vector (cloud-init-registry.yml), so the Observability block's "layer 3" label is wrong for it. The detectors are: the hourly `scheduled-zot-restart-loop.yml` (PRODUCER_SILENT after 3 h without `SOLEUR_ZOT_DISK` rows, filing a `[ci/zot-telemetry-silent]` issue, which does not page, and which decays to TRANSIENT after 24 h of silence), plus the positive-match Better Stack alerts that use `on_missing_data = "treat_as_zero"` and so read silence as healthy. `registry_disk_prd` (a token-free ping) stays green. Phase 5's direct read of the new boot_id rows is the check that holds.
- **Inline judge vs library.** The library trims trailing whitespace before judging; the first S5 draft of the inline judge did not, so a stored value with a trailing blank worked on the old argv form and would have silenced the replaced host. The inline copies now trim the same way (battery rows pin it).
- **Not measured.** The privileged-tier `HCLOUD_TOKEN` shape (only `HCLOUD_TOKEN_READONLY` was readable), the live preflight verdict, `cloud-init schema` (not installed locally; CI runs it).
- **Out of this slice, recorded.** `htpasswd -vb/-Bbn` puts the zot pull/push passwords on argv in the registry template (pre-existing, not a curl bearer, not covered by Rule E); it is noted on #9757.
