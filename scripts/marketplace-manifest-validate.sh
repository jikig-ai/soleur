#!/usr/bin/env bash
# Guard 4 — validate the marketplace manifest SOURCE before it can merge.
#
# Usage: marketplace-manifest-validate.sh <path-to-manifest.json>
# Exit:  0 = every assertion holds; 1 = at least one finding, or the file could not be read.
#
# WHY THIS EXISTS, AND WHY IT IS NOT REDUNDANT WITH THE DRIFT WORKFLOW.
# `.github/workflows/scheduled-marketplace-drift.yml` asserts the same delivery contract against
# the PUBLISHED artifact at raw.githubusercontent.com. That gate answers "is what we published
# still correct?" — necessarily AFTER publication. This one answers "is what we are ABOUT to
# publish correct?", which is a different question with a different blast radius:
#
#   Once infra/github/ owns the manifest's contents (github_repository_file) AND the drift
#   workflow dispatches a reconcile apply, a bad manifest that MERGES gets published, detected,
#   and then REPUBLISHED by the reconcile — every day, indefinitely — while a published-vs-source
#   byte-diff reports in-sync the whole time, because published genuinely does match source.
#   Automation defending a wrong state is strictly worse than no automation. The only place that
#   loop can be broken is before the merge, which is here.
#
# So: this gate protects the SOURCE, the drift gate protects the PUBLICATION. Neither subsumes
# the other, and the byte-diff verifier subsumes neither — byte-equality with a wrong source is
# a wrong manifest, faithfully delivered.
#
# FAIL CLOSED. An unreadable file, an unparseable body, a non-object top level, or a `.plugins`
# that is not a one-element array are ALL findings, never "nothing to check". The failure this
# refuses is the one where the validator cannot see the artifact and reports clean.
#
# BOT-PR SYNTHETIC-CHECK NOTE (ADR-139 ALLOWED_PATHS ∩ SCAN_DIRS test, re-derived per #7493 —
# the intersection argument is per-gate and must never be inherited):
#   SCAN_DIRS for this gate = the single file infra/github/soleur-marketplace-manifest.json.
#   ALLOWED_PATHS in .github/actions/bot-pr-with-synthetic-checks/action.yml =
#     { knowledge-base/project/weakness-digest.md, knowledge-base/project/rule-metrics.json }.
#   Intersection is EMPTY, so no bot PR can modify this gate's guarded surface and its synthetic
#   green is sound-by-unreachability (the `rule-body-lint` argument, not the
#   `credential-path-guard` earned-green one). If ALLOWED_PATHS ever gains an infra/github path,
#   this gate must be reproduced in the action's Phase-4 ceiling before that lands.
set -uo pipefail

MANIFEST="${1-}"

findings=()

finding() { findings+=("$1"); }

# Every value below is interpolated from ATTACKER-CONTROLLED JSON — a PR author writes this
# file. `jq -r` renders a JSON "\n" as a real newline, so an unsanitised value printed to
# stderr can forge `::error::`/`::add-mask::`/`::stop-commands::` workflow commands. The drift
# workflow already treats this exact data class as requiring sanitisation and documents it as
# load-bearing; this gate reads the same class in CI and had no equivalent. U+2028/U+2029 are
# stripped too — they are not bash line breaks, but the repo's own 2026-04-17 learning records
# them as separators that leak through byte-oriented filters.
sanitize() { printf '%s' "$1" | tr -d '\000-\037\177' | sed 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/##\[/#[/g'; }

if [[ -z "$MANIFEST" ]]; then
  finding "no_argument: expected a path to the manifest JSON as \$1"
elif [[ ! -f "$MANIFEST" ]]; then
  finding "file_missing: no readable file at '${MANIFEST}'"
elif [[ ! -s "$MANIFEST" ]]; then
  finding "file_empty: '${MANIFEST}' is zero bytes"
else
  body="$(cat -- "$MANIFEST")"

  # Gate on `type` BEFORE trusting any value. `jq -e` exits 0 for a `0` or an empty string, and
  # `null | length` is 0, so a value-shaped test on a garbage body can return success. A
  # boolean-valued expression is the only form whose exit code means what it appears to mean.
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body"; then
    finding "unparseable: '${MANIFEST}' did not parse as a JSON object"
  else
    # --- marketplace identity ------------------------------------------------------------------
    # Asserted OUTSIDE the .plugins shape gate: these two are properties of the marketplace
    # document itself and stay evaluable even when .plugins is malformed.
    #
    # `.name` is not cosmetic — it is the `@`-half of the install and update commands
    # (`claude plugin install soleur@soleur-marketplace`, `claude plugin update
    # soleur@soleur-marketplace`), which are printed on three published site pages. Renaming it
    # breaks the documented install AND update path for every existing user, and nothing else in
    # this repo or the drift workflow reads it.
    mp_name="$(jq -r 'if (.name | type) == "string" then .name else "" end' <<<"$body" 2>/dev/null)"
    if [[ "$mp_name" != "soleur-marketplace" ]]; then
      finding "marketplace_name: .name is '$(sanitize "$mp_name")', expected 'soleur-marketplace' — this is the @-half of the published install/update command"
    fi

    # `.owner` is the identity the marketplace presents. An attacker substituting it is a
    # phishing surface that no byte-diff and no drift assertion would report, because the
    # published bytes would faithfully match a compromised source.
    owner_name="$(jq -r 'if (.owner.name | type) == "string" then .owner.name else "" end' <<<"$body" 2>/dev/null)"
    owner_email="$(jq -r 'if (.owner.email | type) == "string" then .owner.email else "" end' <<<"$body" 2>/dev/null)"
    if [[ "$owner_name" != "Jean Deruelle" || "$owner_email" != "jean.deruelle@jikigai.com" ]]; then
      finding "marketplace_owner: .owner is '$(sanitize "$owner_name") <$(sanitize "$owner_email")>', expected the declared Soleur owner identity"
    fi

    entry_shape="$(jq -r 'if (.plugins | type) == "array" and (.plugins[0] | type) == "object" then "ok" else "bad" end' <<<"$body" 2>/dev/null)"
    if [[ "$entry_shape" != "ok" ]]; then
      plugins_type="$(jq -r '.plugins | type' <<<"$body" 2>/dev/null)"
      finding "shape: .plugins[0] is not an object (.plugins has type '${plugins_type:-<unreadable>}'); no assertion below is evaluable"
    else
      # --- entry count -------------------------------------------------------------------------
      # Checked FIRST and independently of the per-field assertions below, all of which read
      # `.plugins[0]`. An APPENDED entry leaves entry 0 perfectly valid, so a positional check
      # set cannot see it — measured on the published guard before #7493.
      entry_count="$(jq -r '.plugins | length | tostring' <<<"$body" 2>/dev/null)"
      if [[ "$entry_count" != "1" ]]; then
        finding "entry_count: .plugins has '${entry_count}' entries, expected exactly 1. Every assertion below reads .plugins[0], so an appended entry would otherwise be unguarded"
      fi

      # --- no version key ----------------------------------------------------------------------
      # Compared against the literal "false" rather than negated, so an empty value from a failed
      # jq invocation reports as a finding instead of as a pass.
      has_version="$(jq -r '.plugins[0] | has("version") | tostring' <<<"$body" 2>/dev/null)"
      if [[ "$has_version" != "false" ]]; then
        finding "version_key_present: .plugins[0] carries a 'version' key (probe returned '${has_version}', expected 'false'). claude plugin update compares version STRINGS, so a constant one always compares equal: the update short-circuits, reports success, and delivers nothing (#7471). This is the failure with no visible symptom"
      fi

      # --- entry name --------------------------------------------------------------------------
      entry_name="$(jq -r 'if (.plugins[0].name | type) == "string" then .plugins[0].name else "" end' <<<"$body" 2>/dev/null)"
      if [[ "$entry_name" != "soleur" ]]; then
        finding "entry_name: .plugins[0].name is '$(sanitize "$entry_name")', expected 'soleur' (empty means absent, null, or not a string)"
      fi

      # --- source type -------------------------------------------------------------------------
      src_type="$(jq -r 'if (.plugins[0].source.source | type) == "string" then .plugins[0].source.source else "" end' <<<"$body" 2>/dev/null)"
      if [[ "$src_type" != "git-subdir" ]]; then
        finding "source_type: .plugins[0].source.source is '$(sanitize "$src_type")', expected 'git-subdir'. Any other source type restores the whole-repo clone (~181 MiB against the CLI's 120 s default) that #7471 exists to remove"
      fi

      # --- source path -------------------------------------------------------------------------
      src_path="$(jq -r 'if (.plugins[0].source.path | type) == "string" then .plugins[0].source.path else "" end' <<<"$body" 2>/dev/null)"
      if [[ "$src_path" != "plugins/soleur" ]]; then
        finding "source_path: .plugins[0].source.path is '$(sanitize "$src_path")', expected 'plugins/soleur'"
      fi

      # --- source url --------------------------------------------------------------------------
      # Accepts the https and ssh spellings, with or without the `.git` suffix or a trailing
      # slash — those are the same repository. Anything else (a fork, a rename, another org) is
      # a repoint.
      src_url="$(jq -r 'if (.plugins[0].source.url | type) == "string" then .plugins[0].source.url else "" end' <<<"$body" 2>/dev/null)"
      if [[ ! "$src_url" =~ ^(https://github\.com/|git@github\.com:)jikig-ai/soleur(\.git)?/?$ ]]; then
        finding "source_url: .plugins[0].source.url is '$(sanitize "$src_url")', expected to point at jikig-ai/soleur"
      fi

      # --- no pin ------------------------------------------------------------------------------
      # ALLOWLIST, not a denylist. The first draft enumerated five pin spellings
      # (ref/sha/commit/branch/tag); `revision` — and any future spelling the CLI grows —
      # sailed through. The set of keys this source legitimately carries is closed and tiny,
      # so assert THAT and let everything else be a finding by construction.
      extra_keys="$(jq -r 'if (.plugins[0].source | type) == "object" then ([.plugins[0].source | keys_unsorted[] | select(. != "source" and . != "url" and . != "path")] | join(",")) else "<unreadable>" end' <<<"$body" 2>/dev/null)"
      if [[ -n "$extra_keys" ]]; then
        finding "source_extra_keys: .plugins[0].source carries unexpected key(s) '$(sanitize "$extra_keys")'; only source/url/path are allowed. The entry is deliberately unpinned — any pin (ref, sha, commit, branch, tag, revision, …) freezes every new install at a stale tree, which is #7471's defect 1 by another route"
      fi
    fi
  fi
fi

count="${#findings[@]}"
if [[ "$count" -eq 0 ]]; then
  echo "marketplace-manifest-validate: OK — every delivery-contract assertion holds for '${MANIFEST}'"
  exit 0
fi

echo "marketplace-manifest-validate: ${count} failing assertion(s) for '${MANIFEST}'" >&2
printf 'marketplace-manifest| %s\n' "${findings[@]}" >&2
exit 1
