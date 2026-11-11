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
# Job-name contract: the 10 `context` strings below are public ABI for the
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

      # --- Umbrella required contexts (#12089, ADR-032 amendment 2026-11-06) ---
      # The 16 small-guard contexts that used to occupy Tiers 1/2/3/5/6 (plus
      # the #6882 and #7493 singletons) were folded into THREE umbrella
      # contexts in THIS commit — the rename and the workflow producers landed
      # together, so at no commit does a required name lack a merge_group
      # producer (the pend-forever class; see the merge_queue precondition
      # note below). Each folded guard now runs as a `!cancelled()`-gated
      # MEMBER STEP inside its umbrella job, and the umbrella's `aggregate`
      # step fails the job iff any member failed. Member inventory +
      # per-member bot-PR synthetic justifications: scripts/required-checks.txt.
      #
      #   guards-ruleset  (.github/workflows/ci.yml job `guards-ruleset`):
      #     adr-ordinals, rule-body-lint, tc-document-sha-guard,
      #     marketplace-manifest-guard, service-role-allowlist-gate,
      #     credential-path-guard, cve-safe-status (#12348), lockfile-sync,
      #     grok-fidelity
      #   quality-guards  (.github/workflows/pr-quality-guards.yml job
      #     `quality-guards`): enforce, markdown-lint,
      #     guard-script-fixture-tests (context was "Bash fixture tests for
      #     guard scripts")
      #   secret-guards   (.github/workflows/secret-scan.yml job
      #     `secret-guards`): scan ("gitleaks scan"), lint-fixture-content
      #     ("lint fixture content"), waiver-discipline, rename-guard,
      #     allowlist-diff
      required_check {
        context        = "guards-ruleset"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "quality-guards"
        integration_id = var.actions_integration_id
      }
      required_check {
        context        = "secret-guards"
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

      # --- PR3b (#10859, ADR-276 ruling (a) of 2026-11-06): the oracle-review sentinel lands REQUIRED, in the same  ---
      # --- commit as its ci.yml producer (ADR-032). The S4 ratchet member retired 2026-11-09 (#9729 ruling: the      ---
      # --- stage never activated; the full battery already runs on every PR and merge_group entry).                ---
      # oracle-review-required: the sentinel's own pull_request arm classifies on the BASE commit's resolved oracle
      #   list (scripts/ci-oracle-surface.txt); ALLOWED_PATHS ∩ oracle surface = ∅ (pinned by
      #   plugins/soleur/test/bot-synthetic-unreachability.test.sh), so every bot PR is verdict not-oracle and the
      #   synthetic green asserts exactly that.
      required_check {
        context        = "oracle-review-required"
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
    # FOREVER). The 10 CI Required contexts have a `merge_group` producer; the two
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
    # `max_entries_to_build = 1` (lowered from 2 on #12269, lever E of epic
    # #11556 — the measured experiment): the 28-day decision window counted 27
    # cancelled `merge_group` ci.yml runs (threshold >= 2; clustered on the
    # 2026-11-06/07 congestion burst), so queue-side speculative demand was
    # real and the flip signal fired. Soak verdict lives on #12269 via
    # scripts/followthroughs/mq-lever-e-verdict-12269.sh; revert is a
    # value-only diff back to 2 on all four surfaces (this file, the DR
    # skeleton, the README table, merge-queue-stall-check.yml).
    # `check_response_timeout_minutes` (120) must exceed the slowest required check on
    # `merge_group` INCLUDING runner start spread, else a green PR is dequeued. Raised
    # from 60 on 2026-10-11 (#9454 canary item 5): 240 `merge_group` CI runs measured
    # p95 44.1 min, longest success 60.5 min (above the old 60) and one
    # `checks_timed_out` ejection. The stall probe (45 min) stays below it. Raised again
    # 75 -> 120 on 2026-11-03 (#12030): under hosted-runner saturation (60 jobs running, 222
    # queued) one `merge_group` CI run took 79 min, its shards waiting 10-28 min for a
    # runner, and the entry was ejected with `checks_timed_out`. The cost is that a hung
    # entry can hold the queue 45 min longer than at 75; the demand side is #12030.
    # `max_entries_to_merge = 3` (raised from 1 on #11678 under the ADR-270 raise
    # checklist): groups batch merge LANDINGS, not `merge_group` builds — each
    # position still pays its own cumulative candidate build. Preconditions landed
    # in the same PR: merge-queue-cla-verify.sh enumerates every member PR
    # (head_ref names only the deepest), and the Guard-2 safety pin sanctions
    # {1,3} so a value-only 1->3 or 3->1 PR needs no guard edit.
    merge_queue {
      merge_method                      = "SQUASH"
      grouping_strategy                 = "ALLGREEN"
      max_entries_to_merge              = 3
      min_entries_to_merge              = 1
      min_entries_to_merge_wait_minutes = 0
      max_entries_to_build              = 1
      check_response_timeout_minutes    = 120
    }
  }
}

# #12089 apply ack — the required_status_checks swap from the 16 folded guard
# contexts to the 3 umbrella contexts is an intentional nested-block rewrite;
# the apply-side destroy-guard ack rides the merge commit message ([ack-destroy]).
