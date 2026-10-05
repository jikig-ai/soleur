# CI Required ruleset (id 14145388) -- adopted via `terraform import` per the
# README.md Phase 2 runbook. WIDENED from 5 to 14 required status checks to
# close the secret-scan-failure-merged gap surfaced by PR #3886
# (`lint fixture content` failed and merged because it was not required).
# #4385 then added `enforce` (15th; the "14" wording above is the #3886
# import figure and was left stale). #5585 adds `tenant-integration-required`
# (16th) — the first PATH-FILTERED required check: an always-run aggregator
# gate job (see .github/workflows/tenant-integration.yml) that fails closed, so
# the path-filtered tenant-isolation suite gates merges without leaving
# unrelated PRs "Expected — Waiting". See ADR-032.
#
# Bypass actors preserved from the live ruleset:
#   - OrganizationAdmin (actor_id = 0 per provider issue #2536)  -- pull_request mode
#   - RepositoryRole id = 5 (built-in Admin)                     -- pull_request mode
#
# Strict policy preserved (strict_required_status_checks_policy = true).
#
# Job-name contract: the 23 `context` strings below are public ABI for the
# branch-protection gate. A workflow job rename (`lint fixture content` ->
# `lint-fixture-content`) silently un-requires the check until this resource
# is updated in the same PR. See ADR-032 Sharp Edges.
#
# #6049 adds `adr-ordinals` (17th) — a ci.yml always-run gate job that the live
# ruleset already required but this IaC root + the canonical JSON omitted (an
# IaC-revert latent bug: the next apply would have computed it unmanaged and
# REMOVED it from live). Reconciled here as a no-op apply (live already has it).
#
# #6103 adds `rule-body-lint` (18th, ADR-092) — the always-run ci.yml job that
# blocks un-acked hr-*/wg-* rule-body weakening. First apply (this PR's merge via
# apply-github-infra.yml) makes it LIVE-required. It is a content-scoped gate: on
# bot PRs the synthetic is FABRICATED (not earned) — sound ONLY while the bot
# action's ALLOWED_PATHS excludes AGENTS.rules.md; #6038 must reproduce
# it in the action's Phase-4 ceiling before extending ALLOWED_PATHS. See the
# CODEOWNERS-gated note in scripts/required-checks.txt + ADR-092.
#
# #6882 adds `credential-path-guard` (21st, ADR-139) — the always-run ci.yml
# full-scan job that blocks a tracked doc from reintroducing a resolvable
# credential-file path. First apply (this PR's merge via apply-github-infra.yml)
# makes it LIVE-required. Content-scoped, but its bot-PR synthetic is EARNED (the
# composite action reproduces the scan over its staged paths) rather than sound-
# by-unreachability like rule-body-lint above — because this scanner's SCAN_DIRS
# DOES intersect the action's ALLOWED_PATHS at weakness-digest.md. The
# ALLOWED_PATHS ∩ SCAN_DIRS test must be re-derived per gate, never inherited.
#
# #9454 re-adopts the GitHub merge queue for `main` (#5780 adopted it first, #5800;
# it was reverted 2026-06-30 as the deadlock kill-switch, see the `merge_queue`
# block comment below). `rules` therefore holds TWO rule types:
# `required_status_checks` and `merge_queue`. The `CodeQL` required check was
# REMOVED in the same apply: CodeQL cannot report a status on `merge_group` in ANY
# setup mode (github/codeql-action#1537, open), so a queue and a blocking required
# `CodeQL` check are mutually exclusive. CodeQL stays ADVISORY — the
# `pull_request` scan still runs, and codeql-main-alert-gate.yml turns the pushed
# commit's result into a deduplicated issue within minutes. Because `rules` now
# holds two rule types, any code/probe that reads the required-status-checks rule
# MUST select by type (`select(.type=="required_status_checks")`), never a
# positional `.rules[0]` — apply-github-infra.yml's verify step and the audit
# script already do. The guard is kept so readers cannot silently break.
resource "github_repository_ruleset" "ci_required" {
  name        = "CI Required"
  repository  = var.gh_repo
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # actor_id = 0 sentinel for OrganizationAdmin per provider issue #2536
  # (live API returns null; provider's HCL form for null is 0 on v6.10+).
  # If Phase 2.3 plan-diff probe surfaces bypass_actors churn, add
  # `lifecycle { ignore_changes = [bypass_actors] }` per Risk R6.
  bypass_actors {
    actor_id    = 0
    actor_type  = "OrganizationAdmin"
    bypass_mode = "pull_request"
  }

  bypass_actors {
    actor_id    = 5 # built-in Admin repository role
    actor_type  = "RepositoryRole"
    bypass_mode = "pull_request"
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = true
      do_not_enforce_on_create             = false

      # --- Baseline (verified against ruleset-live-pre-import.json at adoption; the 5th,
      # `CodeQL`, was REMOVED by #9454 — see the merge_queue block comment below) ---
      required_check {
        context        = "test"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "dependency-review"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "e2e"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "skill-security-scan PR gate"
        integration_id = var.actions_integration_id
      }

      # --- Tier 1: secret-scan + guard-script-fixture jobs ---
      # All 6 jobs run under GitHub Actions (integration_id 15368) on every
      # PR (no path filters). 5 from .github/workflows/secret-scan.yml,
      # 1 ("Bash fixture tests for guard scripts") from
      # .github/workflows/pr-quality-guards.yml.
      required_check {
        context        = "gitleaks scan"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "lint fixture content"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "allowlist-diff (.gitleaks.toml paths surface)"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "rename-guard (allowlist destinations)"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "waiver discipline (issue:#NNN trailer)"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "Bash fixture tests for guard scripts"
        integration_id = var.actions_integration_id
      }
      # markdownlint over the whole tracked corpus (#7927). Whole-corpus, not
      # changed-files: none of the errors that first blocked a local `git merge`
      # were in the PR that tripped over them, so a changed-files gate would
      # reproduce the blind spot it exists to close.
      required_check {
        context        = "markdown-lint"
        integration_id = var.actions_integration_id
      }

      # --- Tier 2: non-secret-scan correctness gates from .github/workflows/ci.yml ---
      required_check {
        context        = "lockfile-sync"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "service-role-allowlist-gate"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "tc-document-sha-guard"
        integration_id = var.actions_integration_id
      }
      # adr-ordinals (#6049): always-run ADR-ordinal-collision gate job in
      # .github/workflows/ci.yml. GitHub Actions context (integration_id 15368,
      # NOT GHAS 57789 — using the CodeQL id would silently un-match the gate).
      # Reconciled from live, which already required it; see the count-contract
      # comment at the top of this file.
      required_check {
        context        = "adr-ordinals"
        integration_id = var.actions_integration_id
      }

      # --- Tier 3: legal-doc cross-document lockstep gate (#4384, closes the
      # advisory-bypass-via-auto-merge gap that produced #4333). Context
      # string is the JOB name (`enforce`) at
      # .github/workflows/pr-quality-guards.yml (jobs.enforce — folded from legal-doc-cross-document-gate.yml, #8902), NOT the
      # workflow display name — per ADR-032 job-name contract. Workflow
      # `paths:` filter removed in the same PR (#4384) so the job posts on
      # every PR; the existing `surface_hit=false` short-circuit (lines
      # 82-85) keeps non-DSAR PRs at O(seconds). See learning
      # 2026-03-20-github-required-checks-skip-ci-synthetic-status.md.
      required_check {
        context        = "enforce"
        integration_id = var.actions_integration_id
      }

      # --- Tier 4: tenant-isolation suite required-check shim (#5585). Context
      # is the JOB name `tenant-integration-required` at
      # .github/workflows/tenant-integration.yml — an always-run (if: always())
      # aggregator that fails closed when the dev-Supabase tenant-isolation
      # suite is red. Runs under GitHub Actions (integration_id 15368), so bot
      # PRs satisfy it via the synthetic check-run posted by
      # bot-pr-with-synthetic-checks (CHECK_NAMES) — same as the other 15368
      # checks. Unlike them, the heavy suite is path-gated (detect-changes), so
      # this is the first conditionally-skipped-but-required check. See ADR-032.
      required_check {
        context        = "tenant-integration-required"
        integration_id = var.actions_integration_id
      }

      # --- Tier 5: hard-rule body-weakening gate (#6103, ADR-092). Context is
      # the JOB name `rule-body-lint` at .github/workflows/ci.yml — an always-run
      # gate that BLOCKS any un-acked change/deletion of an hr-*/wg-* rule BODY
      # line in AGENTS.rules.md. Runs under GitHub Actions
      # (integration_id 15368). Content-scoped: the bot synthetic is fabricated,
      # not earned — sound only while the bot action's ALLOWED_PATHS excludes
      # AGENTS bodies (see scripts/required-checks.txt note + ADR-092 residual).
      required_check {
        context        = "rule-body-lint"
        integration_id = var.actions_integration_id
      }

      # --- Tier 6: Grok fidelity gate (#6325 Phase F). Context is the JOB name
      # `grok-fidelity` at .github/workflows/ci.yml — grok inspect contract +
      # /go golden-path eval under Grok harness fixture.
      required_check {
        context        = "grok-fidelity"
        integration_id = var.actions_integration_id
      }

      # #6589 — apply-sentry-infra.yml's always-run aggregator. The heavy
      # full-root terraform plan is path-gated behind it; this context is what
      # makes an unacknowledged Sentry destroy unmergeable rather than merely
      # visible. Advisory would not do: a red-but-mergeable check still permits
      # merge -> post-merge apply failure -> the orphan survives, which is the
      # exact #6074 end state the gate exists to prevent.
      required_check {
        context        = "sentry-destroy-required"
        integration_id = var.actions_integration_id
      }

      # #6882 (ADR-139) adds `credential-path-guard` (21st) — the ci.yml
      # always-run FULL-SCAN job that fails any tracked doc reintroducing a
      # home-relative resolvable path to a real credential file (the vector that
      # read a live Doppler token into model context via preflight/SKILL.md).
      # Promoted advisory -> blocking after #6880 drained the grandfathered
      # backlog to zero. Advisory would not do: the guard already ran and a red
      # -but-mergeable check restores the leak vector on the next ignored merge.
      #
      # Content-scoped, and UNLIKE rule-body-lint / sentry-destroy-required its
      # bot-PR green is EARNED, not fabricated-but-unreachable: the scanner's
      # SCAN_DIRS intersects the composite action's ALLOWED_PATHS at
      # weakness-digest.md, so the action reproduces the scan in its Phase-4
      # ceiling before posting any synthetic. See ADR-139 + required-checks.txt.
      required_check {
        context        = "credential-path-guard"
        integration_id = var.actions_integration_id
      }

      # #7493 adds `marketplace-manifest-guard` (22nd) — the ci.yml always-run
      # job validating `infra/github/soleur-marketplace-manifest.json`, the
      # SOURCE that `github_repository_file.marketplace_manifest` publishes to
      # jikig-ai/soleur-marketplace. First apply (this PR's merge via
      # apply-github-infra.yml) makes it LIVE-required.
      #
      # BORN BLOCKING, deliberately. Advisory would not do here and the reason
      # is mechanical rather than stylistic: once Terraform owns the manifest's
      # contents AND scheduled-marketplace-drift.yml dispatches a reconcile
      # apply, a bad manifest that MERGES is published, detected, and then
      # REPUBLISHED every day — while a published-vs-source byte-diff reports
      # in-sync the whole time, because published genuinely does match source.
      # The merge boundary is the only place that loop can be broken, so a
      # red-but-mergeable check would hand automation a wrong state to defend.
      #
      # Content-scoped. Its bot-PR green is SOUND-BY-UNREACHABILITY (the
      # rule-body-lint argument), NOT earned like credential-path-guard above:
      # SCAN_DIRS here is the single file soleur-marketplace-manifest.json and
      # the composite action's ALLOWED_PATHS is {weakness-digest.md,
      # rule-metrics.json} — intersection EMPTY, re-derived per ADR-139 rather
      # than inherited. If ALLOWED_PATHS ever gains an infra/github path, the
      # gate must be reproduced in the action's Phase-4 ceiling BEFORE it lands.
      required_check {
        context        = "marketplace-manifest-guard"
        integration_id = var.actions_integration_id
      }

      # #8203 adds `vendor-pin-required` (24th) — vendor-pin-verify.yml's
      # always-run aggregator and the THIRD instance of the #5585
      # always-run-aggregator pattern (ADR-032; sentry-destroy-required was
      # the second, #6589). The upstream-blob
      # verification (verify-upstream-blobs, the #8181 path+commit+blob
      # binding) is path-gated behind detect-changes; this context is what
      # makes a red binding result unmergeable rather than merely visible —
      # before this, the verify job's context was never registered, so a red
      # could merge (#8203's title bug).
      #
      # Bot-PR disposition: the composite action DOES post a synthetic green —
      # CHECK_NAMES derives from scripts/required-checks.txt — fabricated but
      # sound-by-UNREACHABILITY like rule-body-lint / sentry-destroy-required,
      # because the action's ALLOWED_PATHS does not intersect
      # plugins/soleur/skills/** (no bot PR can reach the vendored surface).
      # The Inngest re-vendor
      # path (content-vendor-drift) pushes with an App token that triggers
      # real CI (#8166), so its vendor-pin-required is EARNED — and
      # SYNTHETIC_CHECK_NAMES in _cron-safe-commit.ts must never gain this
      # name, or the binding result would be fabricated on exactly the diffs
      # it gates. See scripts/required-checks.txt + ADR-032.
      required_check {
        context        = "vendor-pin-required"
        integration_id = var.actions_integration_id
      }
    }

    # Merge queue (#9454). Re-adopted to remove the merge-train tax: with
    # `strict_required_status_checks_policy = true` every main advance forced a
    # `gh pr update-branch` plus a full CI cycle per PR (#5780's BEHIND starvation).
    # The queue builds each candidate against the projected post-merge state, so
    # "up-to-date" is satisfied BY CONSTRUCTION.
    #
    # RE-ADOPTION RECORD. #5800 enabled the queue and DEADLOCKED main within ~14
    # minutes (kill-switch ran in ~4): CodeQL default setup posts no `CodeQL`
    # context on a `merge_group` temp ref (it fires only on `push`/`pull_request`),
    # so every entry stalled AWAITING_CHECKS. Converting CodeQL to advanced setup
    # does NOT fix that — the PIR is the authority ("CodeQL does not report a status
    # on `merge_group` in ANY setup mode"; codeql-action#1537, still open;
    # codeql-1537-revisit-watch.yml polls it). The resolution here is the operator's
    # decision to make CodeQL ADVISORY (ADR-032 re-adoption trigger (b)): the
    # `CodeQL` required_check above is gone, and CodeQL is not a required context
    # anywhere (canonical JSON, DR skeleton, required-checks.txt).
    #
    # HARD PRECONDITION: every context required by ANY ruleset on `main` must be
    # produced on `merge_group` (a missing producer leaves the entry pending
    # FOREVER). The 23 CI Required contexts have a `merge_group` producer; the two
    # CLA Required contexts are covered by merge-queue-cla-synthetics.yml, which
    # verifies the PR head's real results first. Re-tighten recipe if upstream ever
    # ships `merge_group` status reporting: re-add the `CodeQL` required_check with
    # `integration_id = var.codeql_integration_id` (57789) alongside the queue.
    #
    # Kill switch / rollback: ONE Terraform diff — remove this block, restore the
    # `CodeQL` required_check, revert the canonical JSON + DR skeleton lines. If the
    # queue is stalled, merge that rollback with `gh pr merge --admin`; the DR script
    # scripts/create-ci-required-ruleset.sh is the emergency path (re-run it with the
    # queue rule omitted).
    #
    # Parameters (all seven set explicitly; provider defaults are 60/5/5/1/5 and the
    # REST API 422s a partial payload). `min_entries_to_merge_wait_minutes = 0`
    # because the 5-minute default would add that wait to every merge. A parity gate
    # (tests/scripts/test-audit-ruleset-bypass.sh, T-mq-1) holds this block equal to
    # the DR skeleton in scripts/create-ci-required-ruleset.sh and the README table.
    # `max_entries_to_build = 2` bounds hosted-runner contention (each candidate
    # runs all 25 contexts); raise only after the canary measures it.
    # `check_response_timeout_minutes = 60` must exceed the slowest required check on
    # `merge_group` INCLUDING runner start spread (PR CI max 32.8 min; ADR-032
    # 2026-09-14 measured a 28-minute max start spread), else a green PR is dequeued.
    merge_queue {
      merge_method                      = "SQUASH"
      grouping_strategy                 = "ALLGREEN"
      max_entries_to_merge              = 1
      min_entries_to_merge              = 1
      min_entries_to_merge_wait_minutes = 0
      max_entries_to_build              = 2
      check_response_timeout_minutes    = 60
    }
  }
}
