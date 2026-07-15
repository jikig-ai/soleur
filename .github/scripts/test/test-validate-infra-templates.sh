#!/usr/bin/env bash
# Fixture tests for validate-infra-templates.sh (#6454).
#
# Drives the REAL executor against SYNTHETIC templates built in a mktemp -d
# (cq-test-fixtures-synthesized-only) — never the repo's real infra corpus, so
# the suite stays deterministic as apps/*/infra/ grows.
#
# Each fixture asserts a DISTINCT exit code. A fixture asserting merely
# "non-zero" passes when the script crashes for an unrelated reason, which is
# how a gate rots into a no-op. Exit contract (mirrors the SUT's header):
#   0 pass · 1 validation failed · 2 render failed · 3 stub var leaked
#   4 template<->.tf drift · 5 counter mismatch · 6 tooling absent
#
# When the SUT's contract changes, update this fixture in the same PR.

set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
EXEC="$DIR/../validate-infra-templates.sh"

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Harness ---
RC=0
OUT=""
run_check() { OUT=$(bash "$EXEC" "$1" 2>&1); RC=$?; }

ok() { echo "PASS [$1]"; PASS=$((PASS + 1)); }
bad() { echo "FAIL [$1]: $2"; echo "  rc=$RC out=$OUT"; FAIL=$((FAIL + 1)); }

assert_rc() { # name expected
  if [[ "$RC" -eq "$2" ]]; then ok "$1"; else bad "$1" "expected rc=$2 got rc=$RC"; fi
}
assert_out() { # name substring
  if grep -Fq "$2" <<<"$OUT"; then ok "$1"; else bad "$1" "expected output to contain '$2'"; fi
}
assert_not_out() { # name substring
  if grep -Fq "$2" <<<"$OUT"; then bad "$1" "expected output NOT to contain '$2'"; else ok "$1"; fi
}

# Each fixture lives in its own infra-root dir with a stub *.tf supplying the
# templatefile() call site, so discovery is exercised exactly as in production.
newdir() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }

# ---------------------------------------------------------------------------
# F1 — the #6454 regression itself.
# `%{ if ... ~}` at COLUMN 1 makes YAML read a leading '%' as a directive
# indicator, so raw `cloud-init schema` hard-fails before schema-checking.
# The script must RENDER first and PASS. This is the exact before/after.
# ---------------------------------------------------------------------------
D=$(newdir f1)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
%{ if enable_extra ~}
write_files:
  - path: /etc/extra.conf
    content: enabled
%{ endif ~}
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    enable_extra = var.enable_extra
    greeting     = var.greeting
  })
}
EOF
# Precondition: prove the RAW file really is red today (the filed bug).
if cloud-init schema -c "$D/cloud-init.yml" >/dev/null 2>&1; then
  bad "F1-precondition-raw-is-red" "raw cloud-init schema unexpectedly PASSED; fixture no longer reproduces #6454"
else
  ok "F1-precondition-raw-is-red"
fi
run_check "$D"
assert_rc "F1-script-passes-rendered" 0

# ---------------------------------------------------------------------------
# F2 — anti-no-op, load-bearing. The single most valuable fixture in the suite:
# a gate that cannot fail is not a gate. Renders to `runcmd: "a-string"`, which
# cloud-init's schema rejects (runcmd must be an array). Proves the render is
# followed by REAL semantic validation — the coverage dead since #6344.
# ---------------------------------------------------------------------------
D=$(newdir f2)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd: "${cmd}"
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    cmd = var.cmd
  })
}
EOF
run_check "$D"
assert_rc "F2-semantic-violation-reds" 1

# ---------------------------------------------------------------------------
# F3 — anti-no-op. Renders to malformed YAML → exit 1.
# ---------------------------------------------------------------------------
D=$(newdir f3)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
write_files:
  - path: /etc/a.conf
   content: "${v}"
     bad_indent: [unclosed
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    v = var.v
  })
}
EOF
run_check "$D"
assert_rc "F3-malformed-yaml-reds" 1

# ---------------------------------------------------------------------------
# F4 — escape fidelity. The negative lookbehind is the subtlest character
# sequence in the fix, and the live `%%{http_code}` curl strings in
# cloud-init-inngest.yml depend on it.
#
# This file carries ONLY TF-escaped `$${SHELL_VAR}` / `%%{http_code}` and NO
# real template syntax, and has NO .tf call site. A naive `grep -qE '%\{|\$\{'`
# detector misreads the escapes as template syntax, tries to attribute it,
# finds no call site, and reds with exit 4 — a false-red on a correct file,
# i.e. #6454 reproduced by the fix itself. Correct detection takes the raw
# path and exits 0.
# ---------------------------------------------------------------------------
D=$(newdir f4)
cat > "$D/cloud-init-esc.yml" <<'EOF'
#cloud-config
runcmd:
  - curl -s -o /dev/null -w '%%{http_code}' https://example.invalid
  - echo "$${SHELL_VAR}"
EOF
run_check "$D"
assert_rc "F4-escapes-take-raw-path" 0
assert_not_out "F4-no-false-drift" "exit 4"

# ---------------------------------------------------------------------------
# F5 — silent-skip guard (the #6454 class recurring). Two discovered members,
# one unreadable. The script must never report success having validated fewer
# members than it discovered → exit 5, never a partial pass.
# ---------------------------------------------------------------------------
D=$(newdir f5)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/cloud-init-locked.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  a = templatefile("${path.module}/cloud-init.yml", {
    greeting = var.greeting
  })
  b = templatefile("${path.module}/cloud-init-locked.yml", {
    greeting = var.greeting
  })
}
EOF
chmod 000 "$D/cloud-init-locked.yml"
run_check "$D"
assert_rc "F5-counter-mismatch-reds" 5
chmod 644 "$D/cloud-init-locked.yml"  # so the EXIT trap can clean up

# ---------------------------------------------------------------------------
# F6 — attribution. Guards the `ci-ssh-key.tf` comment-match trap found while
# planning: a loose `grep -l "templatefile(.*cloud-init.yml"` matches that
# file's PROSE COMMENT, yields an empty key map, and fails the render.
#
# 6a: a template with real syntax but NO .tf call site  → exit 4 (nobody renders it)
# 6b: a template referenced by TWO call sites           → exit 4 (ambiguous; never silently pick one)
#
# 6a's stub .tf mirrors ci-ssh-key.tf's REAL prose shape — `templatefile()` and
# the filename mentioned in the same comment but never adjacent as call syntax.
# That is what the anchored pattern must ignore. (A comment carrying VERBATIM
# call syntax is indistinguishable from a call site by any regex; that case
# still fails loud at exit 2 via terraform, never silently.)
# ---------------------------------------------------------------------------
D=$(newdir f6a)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${orphan}
EOF
cat > "$D/main.tf" <<'EOF'
# Cloud-init's `ssh_authorized_keys:` block on a fresh host needs the same
# public key. server.tf:29-43 reads this output into the
# `templatefile()` interpolation map so `cloud-init.yml`'s
# `${ci_ssh_public_key_openssh}` resolves at plan time.
locals {
  unrelated = "noop"
}
EOF
run_check "$D"
assert_rc "F6a-no-call-site-reds" 4

D=$(newdir f6b)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  first = templatefile("${path.module}/cloud-init.yml", {
    greeting = var.greeting
  })
}
EOF
cat > "$D/other.tf" <<'EOF'
locals {
  second = templatefile("${path.module}/cloud-init.yml", {
    greeting = var.other
  })
}
EOF
run_check "$D"
assert_rc "F6b-ambiguous-call-site-reds" 4

# ---------------------------------------------------------------------------
# F7 — arm selection. THE property justifying the render over a directive-strip
# (Design Decision 0). Arm B alone is schema-invalid; a strip keeps both arms'
# bodies unconditionally and produces a document matching NEITHER arm, so it
# would pass this vacuously. Rendering both arms catches it → exit 1.
# ---------------------------------------------------------------------------
D=$(newdir f7)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
%{ if enable_extra ~}
runcmd:
  - echo valid-arm
%{ else ~}
runcmd: "invalid-arm-not-a-list"
%{ endif ~}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    enable_extra = var.enable_extra
  })
}
EOF
run_check "$D"
assert_rc "F7-false-arm-caught" 1

# ---------------------------------------------------------------------------
# F8 — fail-closed tooling. An advisory test may self-SKIP; a GATE may not.
# terraform absent → exit 6 and the word SKIP must not appear.
# ---------------------------------------------------------------------------
D=$(newdir f8)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    greeting = var.greeting
  })
}
EOF
# Build a PATH that carries everything the script needs EXCEPT terraform, so
# this isolates the terraform-absent branch rather than the cloud-init one.
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
for b in bash sh grep egrep awk sed jq mktemp rm cat printf echo wc sort head tail tr dirname basename chmod find cp mv test env cloud-init python3; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$FAKEBIN/$b" 2>/dev/null
done
OUT=$(PATH="$FAKEBIN" bash "$EXEC" "$D" 2>&1); RC=$?
assert_rc "F8-tooling-absent-fails-closed" 6
assert_not_out "F8-no-self-skip" "SKIP"
assert_out "F8-names-terraform" "terraform"

# ---------------------------------------------------------------------------
# F9 — the JSON leg AND the #6448 forward-compatibility proof, load-bearing.
#
# A .tf declares templatefile("${path.module}/some-config.json", {...}) — the
# exact shape #6448 will introduce when docker-daemon.json stops being file()
# and starts deriving insecure-registries from local.registry_private_ip.
#
# The file is NOT a cloud-init, is NOT named in any allowlist, and is
# discovered from the CALL SITE ALONE. It renders to malformed JSON → exit 1.
# This is what keeps #6448 from re-opening #6454.
# ---------------------------------------------------------------------------
D=$(newdir f9)
cat > "$D/some-config.json" <<'EOF'
{
  "insecure-registries": ["${registry_private_ip}:5000"],,,BROKEN
}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  dj = templatefile("${path.module}/some-config.json", {
    registry_private_ip = local.registry_private_ip
  })
}
EOF
run_check "$D"
assert_rc "F9-malformed-json-reds" 1
assert_out "F9-discovered-from-call-site" "some-config.json"

# F9b — the same JSON template, WELL-FORMED, must pass. Without this, F9 could
# pass because the file was never discovered at all rather than because the
# JSON leg works.
D=$(newdir f9b)
cat > "$D/some-config.json" <<'EOF'
{
  "insecure-registries": ["${registry_private_ip}:5000"]
}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  dj = templatefile("${path.module}/some-config.json", {
    registry_private_ip = local.registry_private_ip
  })
}
EOF
run_check "$D"
assert_rc "F9b-valid-json-passes" 0
assert_out "F9b-validated-counter" "1/1"

# ---------------------------------------------------------------------------
# F10 — a dir with no templates at all (the real infra/github/ case) exits 0
# with an explicit message, never a silent success.
# ---------------------------------------------------------------------------
D=$(newdir f10)
cat > "$D/main.tf" <<'EOF'
locals {
  nothing = "here"
}
EOF
run_check "$D"
assert_rc "F10-empty-dir-passes" 0
assert_out "F10-explicit-message" "no infra templates"

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
