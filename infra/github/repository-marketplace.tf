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
# OWNERSHIP BOUNDARY -- read before editing:
#   Terraform owns:     visibility, description, topics, archival/destroy.
#   Terraform does NOT own the repo CONTENTS. `.claude-plugin/marketplace.json`
#   is hand-maintained in that repo and has no CI, no review, and no CODEOWNERS
#   there. The ONLY control on the artifact is the daily drift guard
#   `.github/workflows/scheduled-marketplace-drift.yml` in THIS repo, which
#   re-reads the published manifest over raw.githubusercontent.com and opens an
#   issue on mismatch. Deleting that workflow leaves the manifest ungoverned.
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
