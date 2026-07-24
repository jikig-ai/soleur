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
# Job-name contract: the 20 `context` strings below are public ABI for the
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
# action's ALLOWED_PATHS excludes AGENTS.{core,docs,rest}.md; #6038 must reproduce
# it in the action's Phase-4 ceiling before extending ALLOWED_PATHS. See the
# CODEOWNERS-gated note in scripts/required-checks.txt + ADR-092.
#
# #6882 adds `credential-path-guard` (20th, ADR-139) — the always-run ci.yml
# full-scan job that blocks a tracked doc from reintroducing a resolvable
# credential-file path. First apply (this PR's merge via apply-github-infra.yml)
# makes it LIVE-required. Content-scoped, but its bot-PR synthetic is EARNED (the
# composite action reproduces the scan over its staged paths) rather than sound-
# by-unreachability like rule-body-lint above — because this scanner's SCAN_DIRS
# DOES intersect the action's ALLOWED_PATHS at weakness-digest.md. The
# ALLOWED_PATHS ∩ SCAN_DIRS test must be re-derived per gate, never inherited.
#
# #5780 briefly added a second rule sibling — a `merge_queue` block adopting a
# GitHub merge queue for `main` to fix the strict-up-to-date BEHIND starvation.
# It was REVERTED (2026-06-30) and is NOT present: CodeQL reports no status
# context on `merge_group` in ANY setup mode, so a queue and a blocking required
# `CodeQL` check are mutually exclusive (see the `codeql-action#1537` note in
# codeql-1537-revisit-watch.yml, and the kill-switch record on the
# `Merge queue REVERTED` comment below). `rules` therefore holds
# exactly ONE rule type today. Any code/probe that reads the
# required-status-checks rule MUST still select by type
# (`select(.type=="required_status_checks")`), never a positional `.rules[0]` —
# the guard is kept so a future re-adoption cannot silently break the readers.
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

      # --- Baseline 5 (verified against ruleset-live-pre-import.json at adoption) ---
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
        context        = "CodeQL"
        integration_id = var.codeql_integration_id
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
      # .github/workflows/legal-doc-cross-document-gate.yml:36, NOT the
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
      # line in AGENTS.{core,docs,rest}.md. Runs under GitHub Actions
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

      # #6882 (ADR-139) adds `credential-path-guard` (20th) — the ci.yml
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
    }

    # Merge queue REVERTED (#5780 kill-switch, 2026-06-30). The queue was
    # enabled by PR #5800 but DEADLOCKED main: GitHub CodeQL *default setup*
    # does not run / post the required `CodeQL` context on a `merge_group`
    # temp ref (it fires only on `push`/`pull_request`), so every queue entry
    # stalled AWAITING_CHECKS until the 15-min timeout, then re-jammed (3 real
    # PRs — #5808/#5794/#5798 — were stuck). All 15 OTHER required contexts DID
    # report on the temp ref, so PR-1's `merge_group` wiring is correct; the
    # gap is CodeQL-on-`merge_group` only. Reverting to direct-merge restores
    # CodeQL coverage (it runs on `pull_request`).
    #
    # DO NOT re-adopt the queue by "converting CodeQL to advanced setup". This
    # comment said exactly that until #6446's review; it is FALSE and following
    # it re-creates the deadlock this kill-switch exists for. The PIR is the
    # authority: "CodeQL does not report a status on `merge_group` in ANY setup
    # mode, so advanced setup does not fix it. The queue and a blocking required
    # CodeQL check are mutually exclusive; decision is to keep CodeQL required
    # and not adopt the queue." (codeql-action#1537, open since 2023 — the
    # `codeql-1537-revisit-watch` workflow polls it.) Re-adoption is unblocked
    # only if upstream ships `merge_group` status reporting. Tracked in #5780;
    # see the PIR + ADR-032 amendment.
  }
}
