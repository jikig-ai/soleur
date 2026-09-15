# shellcheck shell=bash
# Shared create-gate arm: a git-data host create carries exactly the root key, by
# fingerprint (#8189, ADR-220, Guard 4).
#
# SOURCED BY BOTH HOST-CREATING GATES, and only by them:
#   tests/scripts/lib/git-data-host-replace-gate.sh  (apply_target=git-data-host-replace)
#   tests/scripts/lib/git-data-host-birth-gate.sh    (apply_target=git-data-host-create)
# tests/scripts/test-git-data-root-key-arm.sh holds the call-site census (exactly those two).
#
# WHY. The root key is minted in its own Terraform root (apps/web-platform/infra/
# git-data-root-key/) and reaches git-data.tf only as a Hetzner id, looked up by label
# (`data "hcloud_ssh_keys" "git_data_root"`). Anyone holding HCLOUD_TOKEN can upload a key
# carrying that label. The one value outside that reach is the SHA256 fingerprint committed
# by a reviewed PR in apps/web-platform/infra/git-data-root-key.fingerprint, so a create is
# refused unless the key the plan resolved hashes to exactly that value.
#
# WHAT IT READS (terraform show -json, Terraform 1.10.5, measured):
#   - A data source fully known at plan time appears ONLY in
#     .prior_state.values.root_module.resources[] (mode == "data"), never in
#     resource_changes[]. Present in resource_changes[] means a DEFERRED read, whose result
#     no plan-time check can see — refused.
#   - hcloud_ssh_keys.ssh_keys[] carries id (NUMBER), name, fingerprint, labels, public_key.
#     Hetzner's `fingerprint` is MD5 colon-hex, not SHA256, so it is NOT compared: the SHA256
#     is derived from `public_key` with ssh-keygen.
#   - hcloud_server.ssh_keys is list(string); compared as a SET of strings.
#   - The default key's id comes from hcloud_ssh_key.default in prior_state. It is known on
#     every real plan (the key pre-exists and carries ignore_changes=[public_key]). If it is
#     absent, not a decimal id, or planned to change (its new id unknown), the arm refuses:
#     an unknown id is not evidence of the right key set.
#
# THE PLAN JSON IS ADVERSARIAL. Every shape is type-checked: a null or non-array where an
# array belongs is an error, never a zero-length pass. A jq failure refuses.
#
# REFUSAL. One verdict line, then one detail line, then the remedy:
#   verdict=git_data_root_key_not_in_create reason=<word>
# with <word> one of (D-2's set, unchanged):
#   fingerprint_file_missing  the anchor file is absent, unreadable, or not exactly one
#                             `SHA256:<43 base64 chars>` line (a malformed anchor is no anchor;
#                             the detail line says which)
#   data_source_absent        data.hcloud_ssh_keys.git_data_root is not resolved in prior_state
#                             (absent, duplicated, deferred to apply, or the plan is unreadable)
#   key_count                 the data source did not resolve to exactly one key
#   name                      the one key is not named soleur-git-data-root
#   fingerprint               its public_key does not hash to the committed fingerprint
#   server_keys               some created hcloud_server.git_data does not carry exactly
#                             {default key id, root key id}, or none is created, or the default
#                             key id is not known
#
# Usage:  source tests/scripts/lib/git-data-root-key-arm.sh
#         git_data_root_key_arm <plan.json> <fingerprint-file>   # 0=PASS, 1=REFUSE

_git_data_root_key_refuse() {
  local reason="$1" detail="$2"
  echo "verdict=git_data_root_key_not_in_create reason=${reason}"
  echo "git_data_root_key_arm: detail: ${detail}"
  echo "git_data_root_key_arm: remedy: dispatch apply-git-data-root-key.yml; commit its printed fingerprint; re-dispatch. After a rotation, the previous key stops authenticating at this create."
  return 1
}

git_data_root_key_arm() {
  local plan_json="${1:-}" fp_file="${2:-}"
  local want facts reason detail root_id default_id public_key tmpd got lines

  # ── The anchor ────────────────────────────────────────────────────────────────
  if [[ -z "$fp_file" || ! -f "$fp_file" || ! -r "$fp_file" ]]; then
    _git_data_root_key_refuse fingerprint_file_missing "no readable fingerprint file at '${fp_file}'"
    return 1
  fi
  # Bounded read: a one-line anchor is 51 bytes. Anything over 256 is not one.
  if [[ "$(wc -c < "$fp_file")" -gt 256 ]]; then
    _git_data_root_key_refuse fingerprint_file_missing "fingerprint file '${fp_file}' is malformed (over 256 bytes)"
    return 1
  fi
  # $(<file) strips trailing newlines only; an embedded newline survives and fails the
  # anchored ERE (bash =~ anchors ^/$ to the whole string).
  want="$(<"$fp_file")"
  if [[ ! "$want" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]; then
    _git_data_root_key_refuse fingerprint_file_missing "fingerprint file '${fp_file}' is malformed (want one line matching ^SHA256:[A-Za-z0-9+/]{43}\$)"
    return 1
  fi

  if [[ -z "$plan_json" || ! -f "$plan_json" ]]; then
    _git_data_root_key_refuse data_source_absent "plan JSON '${plan_json}' not found"
    return 1
  fi

  # ── The plan facts, one jq program, every shape type-checked ──────────────────
  # Emits {"reason":"ok", root_id, default_id, public_key} or {"reason":<word>,"detail":…}.
  # Raises (rc≠0) on any shape it cannot classify; that refuses below.
  if ! facts=$(jq -c '
      def arr($what): if type == "array" then . else error("\($what) is not an array") end;
      def obj($what): if type == "object" then . else error("\($what) is not an object") end;
      def has_unknown: if type == "boolean" then . elif type == "array" or type == "object" then any(.[]; has_unknown) else false end;
      def decimal_id: (if type == "number" or type == "string" then tostring else error("id is neither number nor string") end)
        | if test("^[0-9]+$") then . else error("id \(.) is not a decimal id") end;
      def refuse($r; $d): {reason: $r, detail: $d};

      obj("plan") as $p
      | ($p.resource_changes | arr("resource_changes")) as $rc
      | [ $rc[] | obj("resource_changes entry") ] as $entries
      | if ($p.prior_state | type) != "object"
           or ($p.prior_state.values | type) != "object"
           or ($p.prior_state.values.root_module | type) != "object"
           or ($p.prior_state.values.root_module.resources | type) != "array"
        then refuse("data_source_absent"; "plan has no prior_state.values.root_module.resources array")
        else
          ($p.prior_state.values.root_module.resources | map(obj("prior_state resource"))) as $res
          | [ $entries[] | select(.address == "data.hcloud_ssh_keys.git_data_root") ] as $deferred
          | [ $res[] | select(.address == "data.hcloud_ssh_keys.git_data_root" and .mode == "data") ] as $ds
          | if ($deferred | length) > 0 then
              refuse("data_source_absent"; "data.hcloud_ssh_keys.git_data_root is in resource_changes (a deferred read, resolved only at apply)")
            elif ($ds | length) != 1 then
              refuse("data_source_absent"; "data.hcloud_ssh_keys.git_data_root resolved \($ds | length) times in prior_state (want exactly 1)")
            elif (($ds[0].values | type) != "object") or (($ds[0].values.ssh_keys | type) != "array") then
              refuse("key_count"; "data.hcloud_ssh_keys.git_data_root has no ssh_keys array")
            elif ($ds[0].values.ssh_keys | length) != 1 then
              refuse("key_count"; "data.hcloud_ssh_keys.git_data_root resolved \($ds[0].values.ssh_keys | length) keys (want exactly 1)")
            else
              ($ds[0].values.ssh_keys[0] | obj("resolved key")) as $key
              | if $key.name != "soleur-git-data-root" then
                  refuse("name"; "the resolved key is named \($key.name | tojson) (want \"soleur-git-data-root\")")
                elif ($key.public_key | type) != "string" or ($key.public_key | test("^[^\n\r]+$") | not) then
                  refuse("fingerprint"; "the resolved key has no single-line public_key to hash")
                else
                  ($key.id | decimal_id) as $root_id
                  | [ $res[] | select(.address == "hcloud_ssh_key.default" and .mode == "managed") ] as $def
                  | [ $entries[] | select(.address == "hcloud_ssh_key.default")
                      | select(.change | obj("hcloud_ssh_key.default change") | .actions | arr("hcloud_ssh_key.default actions") | any(. != "no-op" and . != "read")) ] as $def_moving
                  | [ $entries[] | select(.address == "hcloud_server.git_data")
                      | select(.change | obj("hcloud_server.git_data change") | .actions | arr("hcloud_server.git_data actions") | index("create")) ] as $created
                  | if ($def | length) != 1 or (($def[0].values | type) != "object") or ($def[0].values.id == null) then
                      refuse("server_keys"; "hcloud_ssh_key.default is not resolved exactly once in prior_state, so the default key id is unknown")
                    elif ($def_moving | length) > 0 then
                      refuse("server_keys"; "hcloud_ssh_key.default is planned to change, so the id a created server would carry is unknown")
                    elif ($created | length) == 0 then
                      refuse("server_keys"; "no hcloud_server.git_data is created in this plan")
                    else
                      ($def[0].values.id | decimal_id) as $default_id
                      | ([$default_id, $root_id] | unique) as $want
                      | if ($want | length) != 2 then
                          refuse("server_keys"; "the default key and the root key share id \($root_id)")
                        else
                          [ $created[]
                            | .change as $c
                            | select(
                                (($c.after | type) != "object")
                                or (($c.after.ssh_keys | type) != "array")
                                or ($c.after_unknown == true)
                                or ((($c.after_unknown | type) == "object") and (($c.after_unknown.ssh_keys // false) | has_unknown))
                                or (($c.after.ssh_keys | map(if type == "number" or type == "string" then tostring else "<\(type)>" end) | unique) != $want)
                              ) ] as $bad
                          | if ($bad | length) > 0 then
                              refuse("server_keys"; "\($bad | length) created hcloud_server.git_data carry ssh_keys \($bad | map(.change.after.ssh_keys? // null) | tojson), want the set \($want | tojson) (default, root)")
                            else
                              {reason: "ok", root_id: $root_id, default_id: $default_id, public_key: $key.public_key}
                            end
                        end
                    end
                end
            end
        end
    ' < "$plan_json" 2>/dev/null); then
    _git_data_root_key_refuse data_source_absent "plan JSON '${plan_json}' could not be read or classified (jq failed: an unparseable document or a shape it refuses)"
    return 1
  fi

  reason=$(jq -r '.reason | if type == "string" then . else error("no reason") end' <<<"$facts" 2>/dev/null) || reason=""
  if [[ "$reason" != "ok" ]]; then
    detail=$(jq -r '.detail // "unclassified"' <<<"$facts" 2>/dev/null) || detail="unclassified"
    case "$reason" in
      data_source_absent|key_count|name|fingerprint|server_keys) ;;
      *) reason="data_source_absent"; detail="the arm's classifier returned no reason word" ;;
    esac
    _git_data_root_key_refuse "$reason" "$detail"
    return 1
  fi

  root_id=$(jq -r '.root_id' <<<"$facts")
  default_id=$(jq -r '.default_id' <<<"$facts")
  public_key=$(jq -r '.public_key' <<<"$facts")

  # ── The fingerprint, derived (Hetzner's own field is MD5) ─────────────────────
  tmpd="$(mktemp -d "${TMPDIR:-/var/tmp}/gd-root-key-arm.XXXXXX")" || {
    _git_data_root_key_refuse fingerprint "could not create a temp dir to hash the resolved public_key"
    return 1
  }
  printf '%s\n' "$public_key" > "${tmpd}/key.pub"
  got=""
  if lines=$(ssh-keygen -l -E sha256 -f "${tmpd}/key.pub" 2>/dev/null); then
    # Exactly one key in the file, exactly one SHA256 token on its line.
    if [[ "$(printf '%s\n' "$lines" | wc -l)" -eq 1 ]]; then
      got=$(printf '%s\n' "$lines" | awk '{print $2}')
    fi
  fi
  rm -rf "$tmpd"
  if [[ ! "$got" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]; then
    _git_data_root_key_refuse fingerprint "ssh-keygen could not derive a SHA256 fingerprint from the resolved key's public_key"
    return 1
  fi
  if [[ "$got" != "$want" ]]; then
    _git_data_root_key_refuse fingerprint "the resolved key (id ${root_id}) hashes to ${got}; the committed anchor is ${want}"
    return 1
  fi

  echo "git_data_root_key_arm: PASS — data.hcloud_ssh_keys.git_data_root resolved to exactly soleur-git-data-root (id ${root_id}, ${got}, matching the committed anchor); every created hcloud_server.git_data carries exactly {${default_id}, ${root_id}}"
  return 0
}
