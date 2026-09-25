---
title: "Tasks: rotate the web-probes-read prd Doppler token (#8705)"
plan: knowledge-base/project/plans/2026-09-24-security-rotate-web-probes-read-doppler-token-plan.md
issue: 8705
lane: cross-domain
---

# Tasks: rotate the web-probes-read prd Doppler token (#8705)

## 1. Setup

- 1.1 Bump `BASELINE_DECLARED_PROBES` from 24 to 25 in
  `plugins/soleur/test/preflight-discoverability-test.test.ts`, with a PLACEMENT/TRUTH/NO SUBSTITUTE
  comment. This plan's declaration already counts. Verify with
  `bun test plugins/soleur/test/preflight-discoverability-test.test.ts`.
- 1.2 Read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and confirm
  that Doppler, the Hetzner API, Better Stack, web-1/web-2 and their edges are already modeled.

## 2. Guards first (RED)

- 2.1 Change `scripts/lint-doppler-description-length.py` so its `HEREDOC` token carries the heredoc
  body in the value slot. Confirm `python3 scripts/lint-doppler-description-length.py` still exits 0.
- 2.2 Write `apps/web-platform/infra/web-probes-token-rotation.test.sh`:
  - 2.2.0 Shared rules, per the plan's Guard Contract:
    - the checker exits 0 for pass, 1 for a violation (printing the named-block message) and 2 for any
      exception or `ScanError`;
    - a row counts as RED only on exit 1 with the expected message;
    - every guard has a C0 row: an unmutated copy passes;
    - each mutation is confirmed applied to its temp copy and scoped to the block it names.
  - 2.2.1 Guard 1: a per-block consumer census.
    - Lex with `tokenize()`, loaded through `importlib`.
    - Match `ID . ID` sequences, tolerating `NL` inside brackets. Match templated `STR` tokens and
      `HEREDOC` bodies with word boundaries.
    - The `hcloud_server.web` exception matches the `web_probes_token` argument, not the whole block.
    - Floors: 4 / 1 / 1.
    - Rows 1–10 plus C0, H1 and H2. H2 runs against a copy of the suite, with an environment variable
      that stops it recursing.
  - 2.2.2 Guard 2: `create_before_destroy` scoped to the one `web_probes` block. Rows 1–6 plus C0 and
    H1.
  - 2.2.3 Guard 3:
    - verifier fixture rows 1–7;
    - rows 8–9 on the live path, with a stubbed `curl` on `PATH` and a sentinel token that must never
      be printed;
    - H1 uses millisecond timestamps;
    - the single-verdict-function assertion.
  - 2.2.4 The mutation battery runs by default. Counters are incremented at the call site. Each
    Python block floor is passed to bash as its own row. The ok()/no() self-test checks
    `pass+fail==cases`.
  - 2.2.5 The suite header notes that the installer floor encodes today's probe count.
  - 2.2.6 Add the suite to `PROMOTED_FILES` in `scripts/guard-vacuity-floor.test.sh`. This is
    required. Put the `MIN_ASSERTIONS` literal directly above its `if`.
- 2.3 Run the suite. Guard 2 is RED on the current tree (no `lifecycle` yet), and Guard 3 is RED (no
  verifier yet).

## 3. Core implementation (GREEN)

- 3.1 `apps/web-platform/infra/web-probe-read-token.tf`:
  - rename the token to `web-probes-read-2026-09-24`;
  - add `lifecycle { create_before_destroy = true }`;
  - replace the rotation comment with about 8 lines, without the literal `apply -replace=`.
- 3.2 `apps/web-platform/infra/server.tf`: reword the four "`-replace` rotation" comments. Comment
  only.
- 3.3 Create `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`:
  - resolve `DOPPLER_TOKEN_TF` from the environment, then `soleur-infra-privileged/prd`, then
    `soleur/prd_terraform`;
  - pass the header via `curl -K <(…)`, never in argv;
  - `set +x`; `unset` the token after use; `--max-time 10` on both calls;
  - a `page` key in the response means UNAVAILABLE;
  - fixture mode fetches no credential and prints a trailing `(fixture)` marker;
  - flags `--config`, `--retired-slug`, `--name-prefix` and `--not-before`, with defaults;
  - verdicts ROTATED/STALE/MISSING/UNAVAILABLE with exits 0/1/1/2;
  - the fixture seam `WEB_PROBES_TOKEN_LIST_JSON`;
  - no xtrace, and a header note on its removal (#8734).
- 3.4 Register the suite in `.github/workflows/infra-validation.yml`, next to `web-git-data-probe.test.sh`.
- 3.5 Add the 2026-09-24 paragraph to the ADR-119 addendum. It cites ADR-154 and ADR-148, and states
  that a same-name `-replace` is not preferred.
- 3.6 Add "re-seed a rotated baked credential" to the uses listed in
  `knowledge-base/engineering/operations/runbooks/web-host-replace.md`.

## 4. Testing

- 4.1 The new suite is green. Every mutation is RED and every must-PASS row is green.
- 4.2 The existing suites are green:
  - `web-zot-consumer-probe.test.sh`
  - `web-private-nic-guard.test.sh`
  - `web-git-data-probe.test.sh`
  - `inngest-consumer-probe.test.sh`
  - `fresh-boot-parity.test.sh`
  - `workspaces-luks-host-token-refresh.test.sh`
  - `terraform-target-parity.test.ts`
  - `guard-vacuity-floor.test.sh` (promote through `PROMOTED_FILES` if the suite enters its population)
  - `c4-count-parity.test.sh`
- 4.3 `terraform validate` passes in `apps/web-platform/infra`.
- 4.4 The verifier prints `STALE` against live Doppler before merge. This is the positive control.
- 4.5 `bash apps/web-platform/infra/run-registered-suites.sh` lists the new suite as registered.

## 5. Ship and post-merge (per plan Phases 3–4)

- 5.1 The PR body:
  - first line: "merging mutates production: yes";
  - `Ref #8705`, `Ref #8734` and `Ref #8737`, never `Closes`, with `closingIssuesReferences == []`;
  - the wording "forward read access closed; value exposure tracked in #8734".
- 5.2 Before merging:
  - the concurrency group is idle on both apply workflows;
  - the latest main push run's main stage deleted nothing;
  - that run's SSH stage read `0 added, 0 changed, 0 destroyed`;
  - the PR plan job differs from main's run only by the token replace and the four installer
    replaces.
- 5.3 Merge with `gh pr merge --squash --body-file`, with `[ack-destroy]` on its own line. Then check
  `git log -1 --format=%B origin/main`.
- 5.4 Monitor the push run by `head_sha`:
  - the main apply is `1 added, 0 changed, 1 destroyed` (the token only);
  - the SSH stage shows four `Creation complete` lines;
  - on failure, follow the Phase 3 step 4 recovery.
- 5.5 Post the resume checklist comment on #8705.
- 5.6 Run the verifier; it must print `ROTATED`. Then read the web-1 beats twice, at least 8 minutes
  apart: nic-guard, zot-consumer and inngest-consumer. The git-data beat is paused (#6548), so prove
  that probe through the plan's Logs query: host `soleur-web-platform`, at least one row, no
  FATAL/401 lines.
- 5.7 Send the operator the plain-language message, then wait for the go-ahead.
- 5.8 Run the `web-host-replace` `plan_only=true` rehearsal. It must show
  `hcloud_firewall_attachment.web` updated in place, with web-1 (`123931471`) still in
  `server_ids`. Then run the real replace.
- 5.9 After the replace:
  - monitor the run by id to `web_host_replace` `success`;
  - read the web-2 beats twice, at least 8 minutes apart;
  - run the Logs query for host `soleur-web-2`: at least one row per probe identifier, and no
    FATAL/401 lines;
  - sweep for cancelled push runs.
- 5.10 Close #8705 with the evidence comment. #8734 stays open.
