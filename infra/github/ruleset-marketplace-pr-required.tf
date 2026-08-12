# Branch protection + Terraform-owned contents for `jikig-ai/soleur-marketplace`,
# the plugin's SOLE distribution channel (ADR-182, #7493).
#
# WHAT THIS CLOSES. Before this file, that repo had ZERO rulesets and no branch
# protection (verified live 2026-08-12: `gh api repos/jikig-ai/soleur-marketplace/rulesets`
# returned `[]`). THREE GitHub Apps hold org-wide `contents: write` on it —
#
#   soleur-ai (App 3261325)  contents:write  pull_requests:write  administration:write
#   claude                   contents:write  pull_requests:write  —
#   entire                   contents:write  pull_requests:write  administration:read
#
# — so any of them could push the manifest that decides which code lands on every
# installed user's machine, routing around this monorepo's entire CI/CLA/review
# apparatus. The daily drift guard sees that up to 24 h later; for a supply-chain
# repoint, 24 h of detection is a post-mortem, not a control.
#
# ────────────────────────────────────────────────────────────────────────────────
# WHY `required_approving_review_count = 1`, AND WHY THE HUMAN BYPASSES ARE
# `always` RATHER THAN `pull_request` LIKE THEIR SIBLINGS.
#
# Both answers were MEASURED on a disposable repo (jikig-ai/test-new-project, zero
# code references) on 2026-08-12, with the ruleset and every artifact removed
# afterward. They are recorded here because both are counter-intuitive and one
# contradicts the sibling convention in this same directory.
#
#   config                                  | founder merge | founder push | claude/entire
#   ----------------------------------------|---------------|--------------|---------------
#   count = 0                               | yes           | no           | YES — self-merge
#   count = 1, human bypass `pull_request`  | NO            | no           | no
#   count = 1, human bypass `always`        | yes           | yes          | no
#
# Row 1 is the trap. `required_approving_review_count` is Optional with NO schema
# default at integrations/github 6.12.1, so omitting it yields 0 — and a
# PR-with-zero-approvals requirement is not a control against an actor holding
# `pull_requests: write`. `claude` and `entire` would branch, open a PR, and merge
# it themselves. A first draft of this file shipped exactly that and claimed it
# closed their write paths.
#
# Row 2 is why the siblings' `bypass_mode = "pull_request"` is wrong HERE.
# Measured: the sole maintainer's own merge was REFUSED — `reviewDecision:
# REVIEW_REQUIRED`, "the base branch policy prohibits the merge" — and required an
# explicit `--admin` override. On a one-collaborator repo that makes every routine
# change an administrator override, and it degrades the emergency path this repo
# most needs: `soleur-marketplace` is what a broken install is fixed THROUGH.
#
# Row 3 is what is declared below. `always` restores direct push for the two human
# actors, so spec G5 (the maintainer keeps a direct emergency path) actually holds,
# while `claude` and `entire` stay blocked — neither carries `administration: write`,
# so neither can reach the `--admin` override that made row 2 survivable.
#
# HONEST STRENGTH CLAIM. This raises the bar from ONE App acting alone to TWO Apps
# colluding: `claude` could open a PR and `entire` approve it (both hold
# `pull_requests: write`, and GitHub blocks self-approval). Closing that residual
# needs the App installations narrowed to selected repositories, which is tracked
# separately — it removes the threat rather than gating it. What IS unconditional
# here is `deletion` and `non_fast_forward`: no PR flow routes around either.
# ────────────────────────────────────────────────────────────────────────────────
resource "github_repository_ruleset" "marketplace_pr_required" {
  name = "Marketplace PR Required"

  # A REFERENCE, not the literal "soleur-marketplace". Same string, but it
  # supplies the dependency edge (repo before ruleset) and survives a rename
  # instead of silently splitting. `var.gh_repo` is deliberately NOT used — it
  # defaults to "soleur" and this is a different repository, not a configurable
  # one, so a second variable would advertise a knob that does not exist.
  repository = github_repository.soleur_marketplace.name

  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # `actor_id = 0` is the provider's HCL spelling for OrganizationAdmin; the live
  # API reads it back as `null` (provider issue #2536). Any canonical comparison
  # against live state must normalise 0 -> null before comparing — see
  # scripts/marketplace-ruleset-canonical-bypass-actors.json and the SE-1 note in
  # ruleset-cla-required.tf, which documents the same asymmetry for the sibling.
  bypass_actors {
    actor_id    = 0
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always" # NOT `pull_request` — see the measured table above.
  }

  bypass_actors {
    actor_id    = 5 # built-in Admin repository role
    actor_type  = "RepositoryRole"
    bypass_mode = "always" # NOT `pull_request` — see the measured table above.
  }

  # The soleur-ai App, so `github_repository_file.marketplace_manifest` below can
  # write through this ruleset in the unattended apply. This is NOT a hole: the
  # App's write is the REVIEWED path, because its content originates in this
  # monorepo behind CI, required checks and CODEOWNERS. Today that same App can
  # push this repo with no review at all, so the ruleset is strictly a narrowing.
  #
  # 3261325 is the APP id. The INSTALLATION id is 122213433 and appears twice in
  # apply-github-infra.yml; passing it here silently matches no actor, and the
  # symptom is a confusing 404-shaped failure rather than a permission error.
  bypass_actors {
    actor_id    = 3261325
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  # Exactly one `rules` block is permitted (min_items = 1, max_items = 1 at
  # 6.12.1); multiple rule TYPES live inside it.
  rules {
    # Every sub-field is set explicitly. None carries a schema default, so an
    # omission is a silent 0/false — which is precisely how the first draft of
    # this file shipped a ruleset that did not close what it claimed to.
    pull_request {
      required_approving_review_count   = 1
      require_code_owner_review         = false # no CODEOWNERS in that repo
      require_last_push_approval        = false
      dismiss_stale_reviews_on_push     = false
      required_review_thread_resolution = false
      allowed_merge_methods             = ["squash", "merge", "rebase"]
    }

    # Unconditional for every non-bypassing actor, and the part of this ruleset
    # that no PR flow can route around. `archive_on_destroy` on the repository
    # protects the REPO; nothing else protected the branch.
    deletion         = true
    non_fast_forward = true
  }
}

# Terraform owns the manifest's CONTENTS, not merely the repo's settings.
#
# The content source is a file in THIS monorepo under `/infra/github/`, which is
# already CODEOWNERS-pinned — so the published manifest inherits this repo's CI,
# required checks and second-reviewer review without adding any CI to the
# marketplace repo itself. `marketplace-manifest-guard` (ci.yml) validates that
# source on every PR; see scripts/marketplace-manifest-validate.sh for why a
# published-artifact check cannot substitute for it.
#
# ⚠ DESTROY SEMANTICS — read before adding this address to any destroy plan.
# `github_repository_file` has NO `keep_on_destroy` and no lifecycle escape at
# 6.12.1: destroying it DELETES the published manifest, which breaks
# `claude plugin marketplace add` for every new install until the next apply.
# `archive_on_destroy = true` on github_repository.soleur_marketplace does NOT
# cover this — it protects the repository, not a file inside it. So the
# `[ack-destroy]` line in a merge commit now also means "unpublish the plugin";
# the destroy guard catches the plan, and that acknowledgement is the only thing
# between it and the apply.
resource "github_repository_file" "marketplace_manifest" {
  repository = github_repository.soleur_marketplace.name
  branch     = "main"
  file       = ".claude-plugin/marketplace.json"
  content    = file("${path.module}/soleur-marketplace-manifest.json")

  # The file already exists in that repo, so a plain create would 422. Verified
  # against the pinned provider's source rather than assumed: at v6.12.1
  # resourceGithubRepositoryFileCreate GETs the path first and, when this is
  # true, sets `opts.SHA` from the existing file before writing — i.e. an
  # existing byte-identical file takes an update-shaped path, not a conflict.
  # This is why no `terraform import` step is needed; adding a third import-id
  # shape to apply-github-infra.yml was the alternative and is the riskier one
  # (that file already documents two shapes whose difference is load-bearing).
  overwrite_on_create = true

  commit_message = "chore(terraform): reconcile marketplace manifest from jikig-ai/soleur"
  commit_author  = "soleur-ai[bot]"
  commit_email   = "soleur-ai[bot]@users.noreply.github.com"
}
