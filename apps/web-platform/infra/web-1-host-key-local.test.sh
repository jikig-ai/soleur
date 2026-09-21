#!/usr/bin/env bash
# Guard 3 (HCL site) for local.web_1_ssh_host_key in server.tf (#7226 / #8125, ADR-237).
#
# The local is the ONE place web-1's committed pin enters Terraform; every connection block's
# host_key reads it. This suite evaluates the REAL expression -- extracted verbatim from
# server.tf, never re-typed -- with `terraform console` in a scratch root that has no providers
# and no backend, against fixture pin files. Each mis-shaped fixture must ERROR (so every plan
# that reads the pin fails closed); a well-formed file must yield exactly its key line.
#
# It also runs the bash twin (.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh) on the
# same fixtures and requires the SAME verdict, so the HCL and bash sites cannot drift apart on
# what counts as a pin.
#
# CRLF: both sites drop CR bytes before selecting lines, so a CRLF-terminated valid file is
# ACCEPTED (a Windows checkout is not an attack). A CR used as a hidden separator inside one
# line (`<key>\r* ssh-rsa …`) is rejected, because dropping it leaves one malformed line.
#
# Every key here is generated at test time, except the committed pin file itself.
#
# H1: the committed pin's `# fingerprint:` header must equal `ssh-keygen -lf` of its key line, so
# the reviewed header (what the PR body records, AC9) cannot drift from the key Terraform trusts.
#
# (Not covered here: "the precheck step runs before the bridge in git-data-cutover.yml" --
# that workflow's structure is asserted by git-data-cutover-access.test.sh.)
set -uo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 2
INFRA="$ROOT/apps/web-platform/infra"
WRITER="$ROOT/.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

command -v terraform >/dev/null || { echo "FATAL: terraform is required" >&2; exit 2; }
command -v ssh-keygen >/dev/null || { echo "FATAL: ssh-keygen is required" >&2; exit 2; }
[[ -r "$WRITER" ]] || { echo "FATAL: $WRITER not readable" >&2; exit 2; }

pass=0; fail=0; cases=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

SANDBOX="$(mktemp -d -t web1hk.XXXXXXXX)" || exit 2
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

# ── Extract the locals block that defines web_1_ssh_host_key, verbatim ────────────────────
# A top-level `locals {` … `}` (closing brace at column 0) containing the definition.
python3 - "$INFRA/server.tf" "$SANDBOX/locals.tf" <<'PY' || { echo "FATAL: extraction failed" >&2; exit 2; }
import re, sys
src = open(sys.argv[1]).read()
blocks = re.findall(r'(?ms)^locals \{\n.*?^\}\n', src)
hits = [b for b in blocks if re.search(r'(?m)^\s*web_1_ssh_host_key\s*=', b)]
if len(hits) != 1:
    sys.exit(f"expected exactly one locals block defining web_1_ssh_host_key, found {len(hits)}")
if 'file("${path.module}/web-1-ssh-host-key.pub")' not in hits[0]:
    sys.exit("the local no longer reads ${path.module}/web-1-ssh-host-key.pub")
open(sys.argv[2], "w").write(hits[0])
PY
cases=$((cases + 1)); ok "extracted the web_1_ssh_host_key locals block verbatim from server.tf"

# hcl_eval <pin-file> -> prints the key on success; returns 1 on a Terraform error.
hcl_eval() { # <pin-file> [locals-file]
  local d="$SANDBOX/root.$RANDOM$RANDOM"
  mkdir -p "$d" && cp "${2:-$SANDBOX/locals.tf}" "$d/main.tf" && cp "$1" "$d/web-1-ssh-host-key.pub"
  local out err
  out="$(echo 'local.web_1_ssh_host_key' | terraform -chdir="$d" console 2>"$d/stderr")"
  err="$(<"$d/stderr")"
  rm -rf "$d"
  # `terraform console` exits 0 even when the expression errors; the verdict is the output.
  if [[ "$err" == *Error* || "$out" == *Error* ]]; then return 1; fi
  [[ "$out" =~ ^\"(.*)\"$ ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# writer_eval <pin-file> -> 0 when the bash twin accepts it.
writer_eval() {
  local out="$SANDBOX/kh.$RANDOM$RANDOM"
  bash "$WRITER" web-1 "$1" "$out" >/dev/null 2>&1
}

n=0
fixture() { n=$((n + 1)); printf '%s' "$1" > "$SANDBOX/fx.$n"; FX="$SANDBOX/fx.$n"; }

expect_key() { # <label> <file> <expected-key>
  local label="$1" f="$2" want="$3" got
  cases=$((cases + 1))
  if ! got="$(hcl_eval "$f")"; then no "$label: HCL errored on a valid pin"; return; fi
  if [[ "$got" != "$want" ]]; then no "$label: HCL returned [$got], want [$want]"; return; fi
  if ! writer_eval "$f"; then no "$label: HCL accepted but the bash twin REJECTED (sites disagree)"; return; fi
  ok "$label: HCL yields the key; bash twin agrees"
}

expect_error() { # <label> <file>
  local label="$1" f="$2" got
  cases=$((cases + 1))
  if got="$(hcl_eval "$f")"; then no "$label: HCL ACCEPTED it (returned [$got])"; return; fi
  if writer_eval "$f"; then no "$label: HCL errored but the bash twin ACCEPTED it (sites disagree)"; return; fi
  ok "$label: HCL errors; bash twin agrees"
}

# HCL-only: the bash twin is multi-algorithm by design (it also writes git-data's ED25519 pin),
# so it accepts an ED25519 line; for web-1 the bridge's HostKeyAlgorithms=ecdsa-sha2-nistp256
# is what refuses it. Terraform has no such option, so the HCL regex alone must reject it.
expect_error_hcl_only() { # <label> <file>
  local label="$1" f="$2" got
  cases=$((cases + 1))
  if got="$(hcl_eval "$f")"; then no "$label: HCL ACCEPTED it (returned [$got])"; return; fi
  ok "$label: HCL errors"
}

ssh-keygen -q -t ecdsa -b 256 -N '' -f "$SANDBOX/ec" >/dev/null
ssh-keygen -q -t ecdsa -b 256 -N '' -f "$SANDBOX/ec2" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$SANDBOX/ed" >/dev/null
ssh-keygen -q -t rsa -b 2048 -N '' -f "$SANDBOX/rsa" >/dev/null
EC="$(cut -d' ' -f1,2 "$SANDBOX/ec.pub")"
EC2="$(cut -d' ' -f1,2 "$SANDBOX/ec2.pub")"
ED="$(cut -d' ' -f1,2 "$SANDBOX/ed.pub")"
RSA="$(cut -d' ' -f1,2 "$SANDBOX/rsa.pub")"

# ── must yield the key ───────────────────────────────────────────────────────────────────
expect_key "V1: the committed pin file" "$INFRA/web-1-ssh-host-key.pub" \
  "$(awk '!/^[[:space:]]*#/ && NF' "$INFRA/web-1-ssh-host-key.pub")"
fixture $'# header\n# fingerprint: SHA256:x\n\n'"$EC"$'\n'; expect_key "V2: header + blank line + key" "$FX" "$EC"
fixture "$EC"; expect_key "V3: key with no trailing newline" "$FX" "$EC"
fixture $'# c\r\n'"$EC"$'\r\n'; expect_key "V4: CRLF-terminated file (CR dropped at both sites)" "$FX" "$EC"
fixture $'  # indented comment\n\t\n'"$EC"$'\n'; expect_key "V5: indented comment and whitespace-only line" "$FX" "$EC"

# ── must error ───────────────────────────────────────────────────────────────────────────
fixture $'# PLACEHOLDER\n# no key\n'; expect_error "E1: 0 key lines (comments only)" "$FX"
fixture ""; expect_error "E1b: empty file" "$FX"
fixture "$EC"$'\n'"$EC2"$'\n'; expect_error "E2: 2 key lines" "$FX"
fixture "$EC"$'\n'"* $RSA"$'\n'; expect_error "E2b: valid key plus an injected '* ssh-rsa' wildcard line" "$FX"
fixture "$EC"$'\r'"* $RSA"$'\r\n'; expect_error "E3: CR smuggled as a separator inside one line" "$FX"
fixture "$EC host@x"$'\n'; expect_error "E4: trailing comment" "$FX"
fixture "$EC "$'\n'; expect_error "E4b: trailing whitespace" "$FX"
fixture " $EC"$'\n'; expect_error "E5: leading space" "$FX"
fixture "${EC:0:$((${#EC} - 2))}="$'\n'; expect_error "E6: truncated key (139-char body)" "$FX"
fixture "$ED"$'\n'; expect_error_hcl_only "E7: an ED25519 key (Terraform negotiates ECDSA-P256)" "$FX"
fixture "$RSA"$'\n'; expect_error "E7b: an ssh-rsa key" "$FX"
fixture "* $EC"$'\n'; expect_error "E8: host-pattern prefix" "$FX"
fixture "@cert-authority * $EC"$'\n'; expect_error "E8b: @cert-authority marker" "$FX"
# Correct length (140-char body) with ONE character outside the base64 alphabet.
_ec_bad="${EC:0:80}!${EC:81}"
fixture "$_ec_bad"$'\n'; expect_error "E9: correct length, one invalid character ('!') in the body" "$FX"
fixture "${EC:0:80}-${EC:81}"$'\n'; expect_error "E9b: correct length, one invalid character ('-') in the body" "$FX"

# ── H1: the committed header fingerprint equals the key line's real fingerprint ───────────
cases=$((cases + 1))
_pin="$INFRA/web-1-ssh-host-key.pub"
_hdr_fp="$(sed -n 's/^# fingerprint: \(SHA256:[A-Za-z0-9+\/]*\)[[:space:]]*$/\1/p' "$_pin")"
_key_fp="$(awk '!/^[[:space:]]*#/ && NF' "$_pin" | ssh-keygen -lf - 2>/dev/null | awk '{ print $2 }')"
if [[ -n "$_hdr_fp" && "$_hdr_fp" == "$_key_fp" && "$(grep -c '^# fingerprint: ' "$_pin")" -eq 1 ]]; then
  ok "H1: the committed '# fingerprint:' header ($_hdr_fp) equals ssh-keygen -lf of the key line"
else
  no "H1: header fingerprint [$_hdr_fp] != key-line fingerprint [$_key_fp] (or the header is missing/duplicated)"
fi

# ── mutation: the harness can see a loosened expression ─────────────────────────────────
# Dropping the regex's `$` anchor must let the trailing-comment fixture through. If it does not,
# hcl_eval cannot tell an accepted pin from an errored one and every E-row above is vacuous.
cases=$((cases + 1))
sed 's/{86}=\$"/{86}="/' "$SANDBOX/locals.tf" > "$SANDBOX/locals-unanchored.tf"
fixture "$EC host@x"$'\n'
if cmp -s "$SANDBOX/locals.tf" "$SANDBOX/locals-unanchored.tf"; then
  no "M1: the anchor-drop mutation did not land (regex text changed?)"
elif got="$(hcl_eval "$FX" "$SANDBOX/locals-unanchored.tf")" && [[ "$got" == "$EC" ]]; then
  ok "M1: an unanchored regex accepts a trailing comment (the E-rows can detect loosening)"
else
  no "M1: the unanchored mutation still errored -- hcl_eval cannot observe acceptance"
fi

if (( pass + fail != cases )); then
  printf '[FATAL] accounting: pass+fail (%d) != cases (%d)\n' "$((pass + fail))" "$cases" >&2; exit 1
fi
FLOOR=23
if (( cases < FLOOR )); then
  printf '[FATAL] anti-vacuity floor: %d cases ran, expected >= %d\n' "$cases" "$FLOOR" >&2; exit 1
fi
echo "=== web-1-host-key-local: $pass passed, $fail failed ($cases cases) ==="
[[ "$fail" -eq 0 ]]
