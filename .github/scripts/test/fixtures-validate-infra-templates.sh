#!/usr/bin/env bash
# Fixture tests for validate-infra-templates.sh (#6454).
#
# Drives the REAL executor against SYNTHETIC templates built in a mktemp -d
# (cq-test-fixtures-synthesized-only) — never the repo's real infra corpus (except
# F23, below), so the suite stays deterministic as apps/*/infra/ grows.
#
# Each fixture asserts a DISTINCT exit code. A fixture asserting merely
# "non-zero" passes when the script crashes for an unrelated reason, which is
# how a gate rots into a no-op. Exit contract (mirrors the SUT's header):
#   0 pass · 1 validation failed · 2 render failed · 3 stub var leaked
#   4 template<->.tf drift · 5 counter mismatch · 6 tooling absent
#
# When the SUT's contract changes, update this fixture in the same PR.
#
# One deliberate carve-out from "synthetic only": F23 copies the REAL registry
# pair (cloud-init-registry.yml + zot-registry.tf) into a mktemp root and mutates
# the COPY (#6509). The property under test — "this template renders under its own
# call site" — cannot be synthesized. The mutation targets are DERIVED from the real
# template at run time, so growth of apps/*/infra/ cannot rot the arms.

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
# `timeout` is load-bearing, not hygiene: a mutation that makes the SUT read
# STDIN (an empty filename handed to awk) HANGS instead of failing, and an
# un-timed harness hangs with it — so a mutation test reports "still running"
# rather than a verdict, and a wedged gate would burn the CI runner's whole
# budget. 120s is ~7x the full suite's real runtime (~18s).
run_check() { OUT=$(timeout 120 bash "$EXEC" "$1" 2>&1); RC=$?; }

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
# Assert the POSITIVE: that the raw path is what ran. A negative-space
# `assert_not_out "exit 4"` here is unfalsifiable — the SUT never prints the
# string "exit 4" on any path, so it passes against empty output and certifies
# nothing.
assert_out "F4-took-raw-path" "raw — no template syntax"

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
# 6b: a template referenced by TWO call sites whose key sets DIFFER → exit 4 (never silently pick one)
# 6c: TWO call sites with ONE key set and different values → PASS (the render stubs
#     values, so both sites render identical bytes; #8609 keyless + token-bearing render)
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
# `assert_rc 4` ALONE cannot tell the no-call-site branch from the empty-var-map
# branch — both exit 4. Verified: with both attribution checks deleted, this
# fixture still exits 4 via the empty-map branch, so the rc assert alone
# certifies a neighbour of what it names. Pin the message.
assert_out "F6a-names-the-right-branch" "NO templatefile() call site"

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
    farewell = var.other
  })
}
EOF
run_check "$D"
assert_rc "F6b-ambiguous-call-site-reds" 4
assert_out "F6b-names-the-right-branch" "ambiguous var map"

D=$(newdir f6c)
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
    greeting = ""
  })
}
EOF
run_check "$D"
assert_rc "F6c-same-key-set-call-sites-pass" 0
# rc 0 alone would also pass if the multi-site check were deleted outright and a
# site picked blindly; pin the branch that decided it.
assert_out "F6c-names-the-shared-key-set-branch" "share one key set"

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
# Case-insensitive, and asserted against the FULL output: a case-sensitive
# `assert_not_out "SKIP"` was unfalsifiable here (the SUT's message says
# "not skipping", lowercase, so the needle could never match either way).
if grep -Fqi "skip" <<<"$OUT" && ! grep -Fqi "not skipping" <<<"$OUT"; then
  bad "F8-no-self-skip" "output mentions skipping without the fail-closed disclaimer"
else
  ok "F8-no-self-skip"
fi
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

# ---------------------------------------------------------------------------
# F11-F14 — FALSE-RED guards. Each input below is a CORRECT template that an
# earlier revision of the gate rejected. A gate that reds a correct file is the
# #6454 dynamic itself (operators learn the red light means nothing), so these
# matter as much as the anti-no-op fixtures: F2/F3 prove the gate can fail,
# F11-F14 prove it doesn't fail on good input.
# ---------------------------------------------------------------------------

# F11 — a ONE-LINE templatefile map. Ordinary Terraform style. A line-based
# scan starting AFTER the call-site line never sees these keys → empty map → 4.
D=$(newdir f11)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", { greeting = var.greeting })
}
EOF
run_check "$D"
assert_rc "F11-one-line-map-passes" 0

# F11b — one-line map with MULTIPLE keys, comma-separated. A line-anchored key
# regex finds only the first and the render dies on the missing one.
D=$(newdir f11b)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting} ${farewell}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", { greeting = var.a, farewell = var.b })
}
EOF
run_check "$D"
assert_rc "F11b-one-line-multi-key-passes" 0

# F12 — a nested map value whose closing `})` lands at column 0. A scan that
# stops at the first `^\s*\})` truncates the map, dropping a real key.
D=$(newdir f12)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    cfg = jsonencode({
      a = 1
})
    greeting = var.greeting
  })
}
EOF
run_check "$D"
assert_rc "F12-nested-brace-value-passes" 0

# F13 — a NEGATED bool directive. Matching only `%{ if <key>` types this key as
# a string, and `!"x"` is a Terraform type error → exit 2 on a correct file.
D=$(newdir f13)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
package_update: false
%{ if !skip_extra ~}
runcmd:
  - echo included
%{ endif ~}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    skip_extra = var.skip_extra
  })
}
EOF
run_check "$D"
assert_rc "F13-negated-bool-passes" 0

# F14 — a COMPOUND bool directive. Only the first identifier follows `if`, so
# the second types as a string → `true && "x"` → exit 2 on a correct file.
D=$(newdir f14)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
package_update: false
%{ if enable_a && enable_b ~}
runcmd:
  - echo included
%{ endif ~}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    enable_a = var.a
    enable_b = var.b
  })
}
EOF
run_check "$D"
assert_rc "F14-compound-bool-passes" 0

# F14b — a key COMPARED to a string in a directive is a STRING, not a bool.
# Typing it bool would make `true == "prod"` a type error. Guards the
# comparison carve-out in the bool heuristic.
D=$(newdir f14b)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
package_update: false
%{ if tier == "prod" ~}
runcmd:
  - echo prod
%{ endif ~}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    tier = var.tier
  })
}
EOF
run_check "$D"
assert_rc "F14b-compared-key-stays-string" 0

# F15 — a TF-escaped `$${greeting}` colliding with a map key name renders to a
# literal `${greeting}` BY DESIGN (it is a shell seam). The leak check must not
# read that as an unsubstituted stub → exit 0, not exit 3.
D=$(newdir f15)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo "$${greeting}"
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    greeting = var.greeting
  })
}
EOF
run_check "$D"
assert_rc "F15-escaped-collision-not-a-leak" 0

# F16 — exit 3 for real. The leak check is the backstop for a decode that hands
# back the RAW template: we would then be schema-checking un-rendered text while
# believing it rendered, which is #6454 itself. Terraform always substitutes a
# key that is in the map, so the only honest way to reach this is to inject a
# renderer that returns the template un-substituted. Stub `terraform` on PATH to
# emit the double-JSON-encoded RAW body the real console would emit for a
# rendered doc.
D=$(newdir f16)
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
STUBBIN="$TMP/stubbin-f16"
mkdir -p "$STUBBIN"
for b in bash sh grep egrep awk sed jq mktemp rm cat printf echo wc sort head tail tr dirname basename chmod find cp mv test env cloud-init python3; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$STUBBIN/$b" 2>/dev/null
done
# Double-encode: the SUT decodes with `jq -r . | jq -r .`, mirroring the real
# console's re-quoting of the jsonencode result.
jq -Rs . < "$D/cloud-init.yml" | jq -Rs . > "$TMP/f16-payload"
cat > "$STUBBIN/terraform" <<EOF
#!/usr/bin/env bash
cat "$TMP/f16-payload"
EOF
chmod +x "$STUBBIN/terraform"
OUT=$(PATH="$STUBBIN" bash "$EXEC" "$D" 2>&1); RC=$?
assert_rc "F16-unsubstituted-render-reds" 3
assert_out "F16-names-the-leaked-var" 'greeting'

# ---------------------------------------------------------------------------
# F17 — the WRAPPED `templatefile(` call style. `terraform fmt` accepts it, so a
# line-based discovery grep finds ZERO referents, the template silently leaves the
# corpus, and the N/N counter stays self-consistent while covering less. Reproduced
# against the real corpus: hooks.json.tmpl vanished and the gate reported a happy
# `4/4`. The single most dangerous shape in this suite — it is a SILENT false-green,
# where every other failure here is loud.
# ---------------------------------------------------------------------------
D=$(newdir f17)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile(
    "${path.module}/cloud-init.yml",
    { greeting = var.greeting }
  )
}
EOF
run_check "$D"
assert_rc "F17-wrapped-call-style-discovered" 0
assert_out "F17-counted-the-template" "1/1"

# F18 — a call site discovery CANNOT parse (non-${path.module} referent) must red,
# not shrink the corpus silently. This is the independent completeness floor: the
# N/N counter cannot catch under-discovery because both sides come from the same
# pass, so the floor is the second opinion.
D=$(newdir f18)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  tpl = "${path.module}/cloud-init.yml"
  ud  = templatefile(local.tpl, { greeting = var.greeting })
}
EOF
run_check "$D"
assert_rc "F18-unparseable-call-site-reds" 5
assert_out "F18-names-the-shortfall" "discovery parsed only"

# F18b — the floor must NOT fire on a corpus whose .tf merely MENTIONS
# templatefile() in prose. ci-ssh-key.tf's real comment does exactly this, and so
# does server.tf's own #6454 note; a bare `grep -c 'templatefile('` counts them and
# reds a correct corpus. (The same comment-matching trap the anchored attribution
# pattern exists to dodge — easy to reintroduce in a new guard.)
D=$(newdir f18b)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting}
EOF
cat > "$D/main.tf" <<'EOF'
# server.tf reads this output into the `templatefile()` interpolation map so
# `cloud-init.yml`'s `${ci_ssh_public_key_openssh}` resolves at plan time.
# Another mention: templatefile() is used below.
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    greeting = var.greeting
  })
}
EOF
run_check "$D"
assert_rc "F18b-prose-mentions-do-not-red" 0

# F19 — a referent escaping the infra root. `[^"]+` happily captures a traversal;
# without a containment guard the gate reads an out-of-root file, classifies it
# "raw", and COUNTS IT AS VALIDATED — manufacturing a green N/N out of a file that
# is not a template at all.
#
# (#7025) The RULE changed but the REFUSAL did not. Containment used to be "the referent must
# be a plain basename"; module call sites two levels down must write `../../<name>`, so it is
# now "the referent, resolved against the .tf that writes it, must land inside ROOT". The
# assertion below is re-pinned onto the refusal sentence rather than onto the old rule's
# phrasing — the sentence is the contract; "plain basename" was an implementation detail that
# is no longer true of a correct corpus.
D=$(newdir f19)
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/../../../../../../../etc/passwd", { x = var.x })
}
EOF
run_check "$D"
assert_rc "F19-traversal-referent-reds" 4
assert_out "F19-names-containment" "Refusing to read outside the infra root"

# F19b — the same escape attempted from a MODULE subdir, which is the position that made the
# rule change necessary. A module referent legitimately BEGINS with `../../`, so the guard can
# no longer refuse on spelling; this pins that it still refuses on the RESOLVED path.
D=$(newdir f19b)
mkdir -p "$D/modules/evil"
cat > "$D/modules/evil/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/../../../../../../../etc/passwd", { x = var.x })
}
EOF
run_check "$D"
assert_rc "F19b-module-traversal-reds" 4
assert_out "F19b-names-containment" "Refusing to read outside the infra root"

# F19c — the LEGITIMATE module shape must be accepted and ATTRIBUTED, not merely tolerated.
# Without this, F19/F19b are satisfied by a guard that refuses every module referent, which
# would red the real corpus. This is the arm that distinguishes "contained" from "forbidden".
D=$(newdir f19c)
mkdir -p "$D/modules/ud"
printf '#cloud-config
write_files:
  - path: /tmp/x
    content: ${greeting}
' > "$D/cloud-init.yml"
cat > "$D/modules/ud/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/../../cloud-init.yml", { greeting = "hi" })
}
EOF
run_check "$D"
assert_rc "F19c-module-referent-accepted" 0
assert_out "F19c-counted-the-template" "rendered+validated 1/1"

# F20 — a brace inside a STRING VALUE is not structural. Counting it truncates the
# map early and silently drops a real key -> exit 2 on a correct .tf.
D=$(newdir f20)
cat > "$D/cloud-init.yml" <<'EOF'
#cloud-config
runcmd:
  - echo ${greeting} ${farewell}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  ud = templatefile("${path.module}/cloud-init.yml", {
    greeting = "hi}there"
    farewell = var.farewell
  })
}
EOF
run_check "$D"
assert_rc "F20-brace-in-string-value-passes" 0

# F21 — the LEFT-strip directive form `%{~ if x ~}` is legal Terraform. A bool regex
# anchored on `%{ if` misses it, the key types as a string, and a bare `"x"`
# condition is a type error -> exit 2 on a correct template.
# Uses a JSON template deliberately: `%{~` strips the PRECEDING whitespace,
# including the newline, so in YAML it glues the previous line to the next and the
# document is legitimately invalid — which would fail the fixture for a reason that
# has nothing to do with the typing under test. JSON has no such sensitivity, so
# the only thing that can red this is the bool typing.
D=$(newdir f21)
cat > "$D/conf.json" <<'EOF'
{
  "mode": "%{~ if enable_x ~}on%{~ else ~}off%{~ endif ~}"
}
EOF
cat > "$D/main.tf" <<'EOF'
locals {
  cfg = templatefile("${path.module}/conf.json", {
    enable_x = var.enable_x
  })
}
EOF
run_check "$D"
assert_rc "F21-left-strip-directive-passes" 0

# F22 — a root with no templates still emits the summary line. AC10 greps for
# `rendered+validated N/N`; a root that prints only prose is indistinguishable from
# a gate that never ran, which is the exact ambiguity the line exists to remove.
D=$(newdir f22)
cat > "$D/main.tf" <<'EOF'
locals {
  nothing = "here"
}
EOF
run_check "$D"
assert_rc "F22-empty-root-passes" 0
assert_out "F22-emits-summary-line" "rendered+validated 0/0"

# ---------------------------------------------------------------------------
# F23 — the REAL registry template stays inside what the gate renders (#6509).
# Real corpus copy, mutated copy. Populations are derived from the template:
# distinct `${var}` references and distinct `$${TOKEN` escapes. The suite samples
# the FIRST and LAST member of each; the full 16-var / 28-token sweeps were run
# once at authoring (see the spec's evidence.md), not on every CI pass.
# ---------------------------------------------------------------------------
REPO_ROOT=$(cd "$DIR/../../.." && pwd)
REG_SRC="$REPO_ROOT/apps/web-platform/infra"

# `read -d ''` returns 1 at EOF by design; harmless here (no `set -e`), `|| true` keeps it so.
read -r -d '' REG_MUT_PY <<'PY' || true
import re, sys
mode, path = sys.argv[1], sys.argv[2]
arg = sys.argv[3] if len(sys.argv) > 3 else ""
s = open(path).read()
# Assumes the call and the map's opening `{` share one line (as terraform fmt leaves them);
# a reformat makes F23b/F23e report "mutation was a no-op" rather than a verdict.
CALL = 'templatefile("${path.module}/cloud-init-registry.yml"'
if mode == "vars":
    seen = []
    for m in re.finditer(r"(?<!\$)\$\{([a-z_][a-z0-9_]*)\}", s):
        if m.group(1) not in seen:
            seen.append(m.group(1))
    print("\n".join(seen))
elif mode == "tokens":
    seen = []
    for m in re.finditer(r"\$\$\{([A-Za-z_][A-Za-z0-9_]*)", s):
        if m.group(1) not in seen:
            seen.append(m.group(1))
    print("\n".join(seen))
elif mode == "dropkey":
    i = s.index(CALL)
    m = re.compile(r"^[ \t]*" + re.escape(arg) + r"[ \t]*=.*\n", re.M).search(s, i)
    if m:
        s = s[: m.start()] + s[m.end():]
    open(path, "w").write(s)
elif mode == "undouble":
    s2 = re.sub(r"\$\$\{" + re.escape(arg) + r"(?![A-Za-z0-9_])", "${" + arg, s, count=1)
    open(path, "w").write(s2)
elif mode == "undouble-pct":
    open(path, "w").write(s.replace("%%{http_code}", "%{http_code}", 1))
elif mode == "addvar":
    open(path, "w").write(s + "\n# ${undeclared_var}\n")
elif mode == "extrakey":
    i = s.index(CALL)
    j = s.index("\n", i) + 1
    # Land the key INSIDE the map: the call line must open the map, else leave the copy
    # untouched so the no-op guard reports it (an out-of-map key would pass F23e vacuously).
    if s[i:j].rstrip().endswith("{"):
        open(path, "w").write(s[:j] + '    zz_unused_key = "x"\n' + s[j:])
PY

reg_mut() { python3 -I -c "$REG_MUT_PY" "$@"; }

# reg_root <name>: isolated root holding exactly the real registry pair. The copy goes
# through python, not cp, and the root is bound under $TMP: both keep the P1b
# relative-operand ratchet row for this file unchanged (see fixture-relative-assert).
reg_root() {
  local d="$TMP/$1"
  mkdir -p "$d"
  python3 -I -c 'import shutil, sys; [shutil.copy(f, sys.argv[1]) for f in sys.argv[2:]]' \
    "$d" "$REG_SRC/cloud-init-registry.yml" "$REG_SRC/zot-registry.tf"
  echo "$d"
}

# reg_noop_guard <arm> <file> <src>: a mutation that left the copy byte-identical to
# its source is a named failure, never a pass.
reg_noop_guard() { # arm file src -> 0 if the mutation landed
  if cmp -s "$2" "$3"; then
    RC=0
    OUT=""
    bad "$1" "mutation was a no-op (copy identical to source)"
    return 1
  fi
  return 0
}

# F23a — baseline: the real pair renders, by NAME, as the only member of its root.
D=$(reg_root f23a)
run_check "$D"
assert_rc "F23a-registry-baseline-renders" 0
assert_out "F23a-registry-named-ok" "ok  cloud-init-registry.yml"
assert_out "F23a-registry-counted" "rendered+validated 1/1 file"
# The real call site wraps templatefile() in replace(...): pin that the strip is applied.
assert_out "F23a-render-strip-applied" "applied the call site's render strip"

mapfile -t REG_VARS < <(reg_mut vars "$REG_SRC/cloud-init-registry.yml")
mapfile -t REG_TOKS < <(reg_mut tokens "$REG_SRC/cloud-init-registry.yml")
if [[ "${#REG_VARS[@]}" -lt 2 || "${#REG_TOKS[@]}" -lt 2 ]]; then
  RC=0
  OUT=""
  bad "F23-populations-derived" "derived ${#REG_VARS[@]} vars / ${#REG_TOKS[@]} tokens from the real template (need >= 2 each)"
else
  ok "F23-populations-derived"
fi

# F23b — a dropped map key reds. FIRST and LAST derived var.
for v in "${REG_VARS[0]:-}" "${REG_VARS[@]: -1}"; do
  [[ -n "$v" ]] || continue
  D=$(reg_root "f23b-$v")
  reg_mut dropkey "$D/zot-registry.tf" "$v"
  reg_noop_guard "F23b-drop-$v" "$D/zot-registry.tf" "$REG_SRC/zot-registry.tf" || continue
  run_check "$D"
  assert_rc "F23b-drop-$v-reds" 2
  assert_out "F23b-drop-$v-render-message" "terraform failed to render"
  assert_out "F23b-drop-$v-names-key" "\"$v\""
done

# F23c — an un-doubled escape reds. FIRST and LAST derived token, plus %%{.
for t in "${REG_TOKS[0]:-}" "${REG_TOKS[@]: -1}" "%%{http_code}"; do
  [[ -n "$t" ]] || continue
  D=$(reg_root "f23c-${t//[^A-Za-z0-9_]/_}")
  if [[ "$t" == "%%{http_code}" ]]; then
    reg_mut undouble-pct "$D/cloud-init-registry.yml"
  else
    reg_mut undouble "$D/cloud-init-registry.yml" "$t"
  fi
  reg_noop_guard "F23c-undouble-$t" "$D/cloud-init-registry.yml" "$REG_SRC/cloud-init-registry.yml" || continue
  run_check "$D"
  assert_rc "F23c-undouble-$t-reds" 2
  assert_out "F23c-undouble-$t-render-message" "terraform failed to render"
done

# F23d — an undeclared var in the template reds and is named.
D=$(reg_root f23d)
reg_mut addvar "$D/cloud-init-registry.yml"
reg_noop_guard "F23d-undeclared-var" "$D/cloud-init-registry.yml" "$REG_SRC/cloud-init-registry.yml" && {
  run_check "$D"
  assert_rc "F23d-undeclared-var-reds" 2
  assert_out "F23d-render-message" "terraform failed to render"
  assert_out "F23d-names-var" "\"undeclared_var\""
}

# F23e — must-PASS, non-canonical: an UNUSED extra map key is tolerated. A gate or
# harness that rejects everything fails here, so the reds above carry information.
D=$(reg_root f23e)
reg_mut extrakey "$D/zot-registry.tf"
reg_noop_guard "F23e-extra-key" "$D/zot-registry.tf" "$REG_SRC/zot-registry.tf" && {
  run_check "$D"
  assert_rc "F23e-unused-extra-key-passes" 0
}

# Anti-vacuity floor: deleting arms (or the whole F23 block) must not read as green.
# Reported by printf + exit, never through bad(). Ratchet MIN_ASSERTIONS in the same
# commit as any added or removed assertion; slack in a floor is attack budget.
ASSERTED=$((PASS + FAIL))
MIN_ASSERTIONS=68
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %d assertions ran, expected >= %d - the suite was stranded, not clean.\n' \
    "$ASSERTED" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
