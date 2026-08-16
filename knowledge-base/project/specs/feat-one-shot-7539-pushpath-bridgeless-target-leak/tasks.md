# Tasks — bridge-less push-path SSH-target leak (#7539)

Plan: `knowledge-base/project/plans/2026-08-16-fix-pushpath-bridgeless-ssh-target-leak-plan.md`
Branch: `feat-one-shot-7539-pushpath-bridgeless-target-leak` · PR #7568 · Closes #7539

Phase order is load-bearing: the guard (1) must be RED before the move (2) makes it green.

## 1. RED — the guard, as in-suite fixtures

- [x] 1.1 Refactor the new logic in `plugins/soleur/test/terraform-target-parity.test.ts` as **pure
      functions taking `(workflowText)`**, mirroring `extractTargets(text)` /
      `collectSshProvisioned(files)`. Without this the mutation rows cannot run in CI.
- [x] 1.2 Implement the bridge-less range extractor: from the `apply` job's first `terraform` step to
      the step whose `uses:` is `./.github/actions/cf-tunnel-ssh-bridge`. Anchor on the `uses:` path
      (content anchor), never a step title.
- [x] 1.3 Match targets over **comment-stripped** text via the existing `stripComments()`, and only
      on flag-shaped lines. Non-negotiable: the range holds two prose `-target=` mentions
      (`:365` comment, `:854` `::warning::` string) that would otherwise false-fire.
- [x] 1.4 Assert the property: zero `-target=terraform_data.*` in that range. Failure message must
      name the offending address, the step it was found in, and the step it belongs in.
- [x] 1.5 Raise `MIN_SSH_PROVISIONED` 10 → 17 (measured) with a deliberate-edit contract. Guard 1
      intersects `collectSshProvisioned()`, and 8 of the 17 are unpinned by the `:236` name list —
      including `inngest_consumer_probe_install` itself.
- [x] 1.6 Correct the stale header count at `:9` ("the 7 server.tf siblings").
- [x] 1.7 Place the new `describe` adjacent to the existing parity block (~`:226`), not at EOF.
- [x] 1.8 Mutation fixtures M1–M4, each asserting RED:
      M1 re-add the address before the bridge · M2 a *second* SSH address after a compliant first ·
      M3 a `-target` in the `:764` apply step (the range hole) · M4 break the bridge `uses:` anchor
      so an unresolvable range FAILS rather than passing on zero scanned targets.
- [x] 1.9 Harness fixtures H1–H2, each asserting PASS: H1 a commented-out target + a `::warning::`
      mentioning `-target=` · H2 SSH addresses only after the bridge, non-canonical names and file.
- [x] 1.10 Confirm the suite is RED against the tree as-is, naming `inngest_consumer_probe_install`.
- [x] 1.11 Commit the failing test first (`cq-write-failing-tests-before`).

## 2. GREEN — move the target, correct what the move falsifies

- [x] 2.1 Move `-target=terraform_data.inngest_consumer_probe_install` from its bridge-less position (cite by content, not line — the rebase shifted it) into the
      `:931-944` post-bridge list.
- [x] 2.2 `server.tf:743-748` — name the **stage**, state the resource is SSH-provisioned and belongs
      post-bridge, and frame the rule as **group by transport, not by feature** (`:576-578` batched
      all three inngest-consumer resources; the SSH one rode along).
- [x] 2.3 `:890` — operator-facing warning: "the **8** SSH-provisioned resources" → set language.
- [x] 2.4 `:911` — "none of the **7** resources has a `when = destroy` provisioner". Load-bearing:
      it is why stage 2 carries no destroy-guard, and this PR adds a member. Verified there is no
      `when = destroy` provisioner anywhere in the infra root, so re-assert for the set.
- [x] 2.5 `:918` — "internal plan against the **8** targets" → "its target set".
- [x] 2.6 `:815` — recovery lever `-F reason='bootstrap'` is a **no-op** (leaves `apply_target` at
      default, so the `apply` job never runs) → `-f apply_target=manual-rerun`.
- [x] 2.7 `:440-444` `ALLOW-LIST MAINTENANCE` — point at the guard as the enforcement; the
      instruction alone demonstrably did not hold (added `620f682c2` 2026-05-20; violated
      `0d6443960` 2026-08-12, 138 lines below it — inside the list that instruction governs).
- [x] 2.8 Confirm the suite is GREEN.

## 3. Close the green-skip dark path

- [x] 3.1 Add a `notify-ops-email` step to the `apply` job gated on
      `steps.ssh_token_gate.outputs.ssh_apply_skip == 'true'`. Inputs `subject`, `body`,
      `resend-api-key: ${{ secrets.RESEND_API_KEY }}`. Follow `infra-validation.yml:1636`.
- [x] 3.2 Body must name the undelivered work **and** the `manual-rerun` recovery command — a
      notification that says only "skipped" reproduces the `::warning::` problem in email form.
- [x] 3.3 Add the skip state to `Post-apply summary` (today prints only `job.status`).
- [x] 3.4 Assert the wiring in the parity suite (workflow-shape assertion), not by eyeballing YAML.

## 4. Harden the Vector reload

- [x] 4.1 Add real config validation of the rendered `/opt/soleur/vector.toml` **before** the
      `install` that overwrites the live file, injecting a dummy `BETTERSTACK_LOGS_TOKEN`.
- [x] 4.2 Rewrite the comment at `:1071-1074`, which currently claims validation is impossible —
      the dummy-value injection retires exactly its stated objection.
- [x] 4.3 Preserve a restorable copy of `/etc/vector/vector.toml` across the swap; restore it and
      reload on validation failure or post-reload liveness failure.
- [ ] 4.4 Prove it: a deliberately broken render must fail the apply **with the previous config
      still live**.

## 5. Verify — self-pulled, no SSH, no dashboard

- [ ] 5.1 Pre-merge AC1–AC10.
- [ ] 5.2 `actionlint` clean on the workflow.
- [ ] 5.3 Post-merge AC11: `inngest_consumer_probe_install` in `terraform state list` — the only
      criterion no concurrent session can produce.
- [ ] 5.4 Post-merge AC12/AC14: Better Stack rows for `SyslogIdentifier=inngest-consumer-probe`
      within ~4 min, via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`.
      Proves both hops and agent liveness in one query.
- [ ] 5.5 Post-merge AC13: the stage-2 step concluded `success`, never `skipped`.
- [ ] 5.6 Watch for the likeliest new red — the `:895` credential probe, unexercised since
      2026-08-12. Recovery table in the plan covers it.

## 6. Record

- [x] 6.1 Amend ADR-154 with the substantive rationale (runtime probe → build-time structural
      assertion; §3's step-position contract cannot reach a bridge-less stage) and carry the
      "open the bridge before stage 1" rejection into rejected-alternatives.
- [x] 6.2 Reciprocal pointers: ADR-154 Related gains the test file; the guard header gains
      `See ADR-154`.
- [ ] 6.3 File the follow-up: widen the SSH predicate beyond `terraform_data` blocks (deferred
      because it edits a shared fail-open parser under a P1).
- [ ] 6.4 File the follow-up: extract the HCL/workflow parsers to a shared module so future guards
      get a focused suite without duplicating a fail-open parser.
