# `jikig-ai/soleur-marketplace` -- the plugin's SOLE distribution channel.
#
# Every `claude plugin marketplace add jikig-ai/soleur-marketplace` resolves
# against this repo; if it disappears or goes private, every NEW install breaks
# (existing installs keep their cached checkout, so the failure is invisible to
# current users and total for new ones). End-to-end install timings and payload
# size measured from the published repo are recorded in
# `knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md`
# §2B -- "The published marketplace, measured against the real repo".
#
# Adopted via `terraform import` on the first apply-github-infra.yml run after
# this file merges (see the `import_repository` helper in that workflow and
# infra/github/README.md), exactly like the two sibling rulesets.
#
# OWNERSHIP BOUNDARY -- read before editing (REWRITTEN by #7493; the previous
# text is now false in both of its clauses and is quoted below so the change is
# legible rather than silent):
#   Terraform owns:     visibility, description, topics, archival/destroy, AND
#                       the repo's default-branch ruleset + the CONTENTS of
#                       `.claude-plugin/marketplace.json`.
#
#   Superseded 2026-08-12 (#7493): "Terraform does NOT own the repo CONTENTS ...
#   The ONLY control on the artifact is the daily drift guard". Both clauses were
#   retired together. The manifest's content is now declared by
#   `github_repository_file.marketplace_manifest` in
#   ruleset-marketplace-pr-required.tf, sourced from
#   `infra/github/soleur-marketplace-manifest.json` in THIS repo — so it carries
#   this repo's CI (the always-run `marketplace-manifest-guard` context), its
#   required checks, and the CODEOWNERS pin on `/infra/github/`. The daily drift
#   guard remains, with its role changed from sole control to publication
#   verifier, and it now dispatches a reconcile apply on a content-drift verdict.
#
#   ⚠ A DESTROY NOW UNPUBLISHES THE PLUGIN. `github_repository_file` has no
#   `keep_on_destroy` at provider 6.12.1, so destroying that resource DELETES the
#   published manifest and breaks `marketplace add` for every new install.
#   `archive_on_destroy` below does NOT cover it — that protects the repository,
#   not a file inside it. The `[ack-destroy]` line in a merge commit therefore
#   carries more weight than it did when it could only remove a ruleset.
#
# Attribute-by-attribute provenance (all read from the live API with
# `gh api repos/jikig-ai/soleur-marketplace` before this file was written, so
# the first plan after import is a no-op):
#   - `name`/`visibility`/`description`: live values, verbatim.
#   - `has_issues`/`has_wiki`/`has_projects`: these are Optional with NO schema
#     default in integrations/github v6.12.1, so omitting them means `false`.
#     They were live-true at adoption time and were turned off to match this
#     declaration -- a manifest-only repo takes its issues in `jikig-ai/soleur`.
#   - Everything omitted is either Optional+Computed (`vulnerability_alerts`,
#     `allow_forking`, `web_commit_signoff_required`) or already equals the
#     provider default at HEAD (`allow_merge_commit`/`allow_squash_merge`/
#     `allow_rebase_merge` = true; `allow_auto_merge`/`delete_branch_on_merge`/
#     `allow_update_branch`/`is_template`/`has_discussions` = false; the four
#     `*_commit_title`/`*_commit_message` settings). Verified against the
#     schema of the pinned provider (`.terraform.lock.hcl` -> 6.12.1) rather
#     than assumed, because an Optional-no-default bool silently plans a
#     revert to `false` on the first apply.
resource "github_repository" "soleur_marketplace" {
  name        = "soleur-marketplace"
  description = "Marketplace manifest for the Soleur plugin — serves plugins/soleur from jikig-ai/soleur via git-subdir"
  visibility  = "public"

  # A manifest-only repo: no issue tracker, no wiki, no project boards.
  has_issues   = false
  has_wiki     = false
  has_projects = false

  # Declared empty so a topic added through the GitHub UI is visible as intent
  # drift on the next plan. Caveat: `topics` is Optional+Computed in the SDKv2
  # provider, so an EMPTY set reads as "unset" and will not actively remove a
  # UI-added topic -- to strip one, list the desired end state here explicitly.
  topics = []

  # Deletion protection. This repo is the product's only distribution channel
  # and its recreation is not equivalent to its survival: a destroy/recreate
  # breaks `marketplace add` for the window it is gone. `archive_on_destroy`
  # turns a `terraform destroy` (or a resource-block deletion) into an archive
  # instead of a delete, which is recoverable. It is defence in depth on top of
  # the apply workflow's `[ack-destroy]` gate, which catches the plan; this
  # catches the apply.
  archive_on_destroy = true
}

# THE RULESET'S QUANTIFIER, PINNED (#7493 review).
#
# `ruleset-marketplace-pr-required.tf` conditions on `~DEFAULT_BRANCH` rather than a literal
# branch name — which is correct, because it survives a rename. But nothing declared WHICH branch
# the default is, and that is the assumption the whole control rests on.
#
# The gap: any actor with `administration: write` on this repo — which includes the `soleur-ai`
# App that Terraform itself authenticates as — can `PATCH /repos/jikig-ai/soleur-marketplace
# {"default_branch": "..."}`. The ruleset then follows the NEW default, leaving `refs/heads/main`
# unprotected, while `github_repository_file.marketplace_manifest` still writes to `main` and
# raw.githubusercontent.com still serves `main`. Every assertion in Guard 1 stays green
# throughout, because `conditions.ref_name.include == ["~DEFAULT_BRANCH"]` is exactly what it
# checks — the pivot is invisible to a probe that reads the ruleset alone.
#
# `github_branch_default` rather than `github_repository.default_branch`: the latter is deprecated
# in the 6.x provider. Create is a PATCH of the repository, so it is idempotent against the
# already-correct live state and needs no import. Declaring it makes a pivot show as drift on the
# next plan and reverts it on the next apply.
resource "github_branch_default" "soleur_marketplace" {
  repository = github_repository.soleur_marketplace.name
  branch     = "main"
}
