# Decision challenges (plan-review, headless)

Taste items surfaced by the plan-review panel. Each was decided in the plan; the operator can reverse any of them.

## 2026-10-04 - keep the deny-by-default child environment (allowlist unset loop)

- Panel split: DHH and Kieran-class review argued it guards the wrong threat (the real attacker is a main-merged edit that adds a step, and the child is reviewed repo code); CTO and code-simplicity kept it (the loader exports the whole Tier-B set, so the checker, the Doppler CLI and curl would otherwise inherit read/write Hetzner and R2 credentials the token ask does not need).
- Decision in the plan: keep it, as one subshell loop with no argv exposure; the shape test pins a canary row. Cost: about 5 lines and one behavioural row. Reversal: delete the loop and call the preflight directly; Guard 1 row 8 goes with it.

## 2026-10-04 - no model.c4 clause for the new infra-privileged consumer

- CTO suggested one sentence on the `github -> doppler` edge; code-simplicity and the structural reviewer cut it (no element, relationship or count changes; the dispatched forget and teardown consumers were never added to that edge either).
- Decision in the plan: no C4 edit; the ADR-241 dated note and runbook step 0 record the fact. Reversal: add the clause, run `bash scripts/regenerate-c4-model.sh` and the C4 suites.

## 2026-10-04 - residual: no enforced review on the token-holding job

- Architecture review (verified against the repository rulesets): no ruleset requires a pull-request review or code-owner approval, so CODEOWNERS rows would not be a control. The CPO condition ("edits to this file should need CODEOWNERS review") cannot be met by this change; it needs a ruleset change (an admin action, outside this PR).
- Decision in the plan: state the residual in the ADR note and Known Limits instead of adding decorative rows. Reversal or follow-up: an admin enables a pull-request-review rule with code-owner review on `main`; not filed as an issue here because the CODEOWNERS header already records it as an admin follow-up.

## 2026-10-04 - shape test location: plugins/soleur/test (required) instead of apps/web-platform/infra (advisory)

- Deepen-plan measurement: `infra-validation.yml`'s `deploy-script-tests` is not in `scripts/required-checks.txt` or the CI Required ruleset, so a shape suite in `apps/web-platform/infra/` (where the neighbouring `workspaces-plaintext-forget-workflow.test.sh` lives) is advisory. A guard over a token-holding job should be required, so the plan places it in `plugins/soleur/test/` (scripts-group glob, `test-scripts` shard, required `test`).
- Consequence: no shard-manifest rows and no `infra-validation.yml` path edit. Reversal: move the file and add those; the guard becomes advisory.

## 2026-10-04 - USER-CHALLENGE: read only DOPPLER_TOKEN_TF directly instead of loading the whole Tier-B project

- The security reviewer recommends passing `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` into one step, running `doppler secrets get DOPPLER_TOKEN_TF -p soleur-infra-privileged -c prd --plain`, masking it, and dropping the loader and the allowlist. Benefit: nothing but one token enters the job environment, so an accidental inheritance by a benign child process is avoided. It is not a bound on a leak: `DOPPLER_TOKEN_TF` reads and writes every project including the Tier-B carrier (ADR-241 D11), so whoever holds it can read the whole Tier-B set by API anyway, and the in-step allowlist already covers accidental inheritance. Cost, as measured by the architecture review (a sandbox step reading the token directly left the census result unchanged; its G1g forbids only `-c prd_terraform` reads outside the loader): no census edit is needed. The real cost is the Doppler CLI: the loader pins 3.75.3 by sha256, and a loader-less route takes an unpinned CLI (22 workflows already use `cli-action@`) or duplicates the pinned install. It also departs from the stated direction, and acquires the token by a different path than the birth and replace jobs use, so a green here would predict less about theirs.
- The operator's stated direction is "loads credentials through the existing tiered loader (.github/actions/infra-credentials) on `infra-privileged`", so the plan keeps the loader and records the alternative here, with the allowlist described honestly as hygiene (the parent step shell keeps the full environment readable at /proc/$PPID/environ). Default: the operator's direction. Revisit with #9461.

## Work-phase forks (appended at work time; the plan did not settle these)

- **No deferral issue is filed for the scheduled escrow check (plan task 5.2 not taken).** The plan read `wg-when-deferring-a-capability-create-a` as "file an issue for a declined capability". The rule's text is the opposite default: document the deferral in place and file an issue only when the `wg-defer-only-after-inline-triage` triple test passes. The deferral and its re-evaluation trigger are written in the ADR-241 amendment-log entry of 2026-10-04 and in the plan's Deferred table; the narrower-credential direction is already tracked by #9461. Reversal: file the issue with `meta/machinery` if a reviewer wants it tracked.
- **The step prints a `Verdict:` line to the run log, not only to the job summary.** The job summary page is not readable through the GitHub command line, so an agent could see PASS/FAIL but not the verdict text. The log line carries the same fixed sentence (no new data), and the runbooks tell the reader to read it with `gh run view --log`.
- **The step redacts any 40+ character run of key-like characters in addition to `dp.<kind>.<body>` token shapes.** The checker embeds up to 300 characters of Doppler CLI stderr in an `unreadable` line, and only `dp.*` shapes were redacted there; a JWT-like or base64-like string would have reached the run log. The behavioural suite pins it (the stderr row). Cost: a legitimate 40+ character token in checker output reads `REDACTED` (none today; the longest name the checker prints is 38).
- **Analyzer bans whole words, not just verbs.** The shape test refuses the standalone words `terraform`, `doppler`, `gh`, `curl`, `git`, `tee` and a few others anywhere in a run body (whole-line comments excluded). It is stricter than the plan's write-verb denylist; a future step that needs one of them has to change the suite in the same PR, which is the point.
