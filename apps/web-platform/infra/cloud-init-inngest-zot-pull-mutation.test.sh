#!/usr/bin/env bash
# Mutation battery for Guard 1 (#7462) — the zot-primary bootstrap pull arm.
#
# WHY THIS FILE EXISTS. `cloud-init-inngest-bootstrap.test.sh` asserts that the arm is shaped
# correctly. It cannot tell you whether those assertions can FAIL. Reading a guard is not
# evidence it works — a guard whose predicate is unmatchable reports clean forever, and the
# repo has shipped exactly that several times (a `[^\n]` bracket expression that excludes the
# letter `n`, a bare-token grep satisfied by the comment explaining the token, a `>= N` floor
# that counts assertion CALLS rather than bodies). The plan's Guard Contract states a mutation
# matrix; this executes it, so AC5 stays true after this session rather than being a one-time
# observation. Registered alongside the sibling *-mutation.test.sh suites.
#
# CONTRACT. For each case: apply ONE mutation to a pristine sandbox copy, confirm the mutation
# actually LANDED (diff against the backup — a sed that matched nothing is a case that tested
# nothing and would report "the guard did not detect this"), run the guard, require a non-zero
# exit, and require the named assertion to be among the failures. A surviving mutant is
# reported with its two readings spelled out: either the fixtures do not exercise the property,
# or the mutant is equivalent. It is never left unlabelled.
#
# HARNESS FAILURES ABORT (exit 2), never degrade. A battery that cannot copy its own tree does
# not produce a missing result, it produces a CONFIDENT WRONG one: the next case runs against
# the previous case's mutation and reports a verdict about the SUT that the harness's own
# breakage produced.

set -uo pipefail

# /tmp is a machine-global RAM-backed tmpfs shared by every parallel worktree on this box, and
# this battery writes ~10 copies of a 6 MB tree. test-all.sh and run-registered-suites.sh both
# default TMPDIR=/var/tmp; a DIRECT invocation (the inner loop while editing the guard) does
# not, so without this line the verdicts become a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="cloud-init-inngest-bootstrap.test.sh"
SRC="cloud-init-inngest.yml"

PASS=0
FAIL=0
TOTAL=0

die() { echo "HARNESS ABORT: $*" >&2; exit 2; }

WORK="$(mktemp -d -t inngest-zot-mut-XXXXXX)" || die "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT

# THE SANDBOX MUST CARRY EVERYTHING THE GUARD RESOLVES, INCLUDING WHAT IT REACHES OUTSIDE ITS
# OWN DIRECTORY. Relocating a script silently breaks every `$SCRIPT_DIR/../..`-relative read,
# and the resulting failure is indistinguishable from a real one. The guard reaches two files
# up at `.github/workflows/infra-validation.yml` and `.github/scripts/validate-infra-templates.sh`,
# so the sandbox reproduces the three intervening directory levels rather than just the infra
# dir. Derived from the guard, not remembered: grep it for `\.\./` before trusting this list.
#   $ grep -nE '\.\./' cloud-init-inngest-bootstrap.test.sh
# The baseline check below is what turns a missed entry into a HARNESS ABORT instead of ten
# confident-wrong verdicts — it already caught exactly this omission once.
SANDBOX_ROOT="$WORK/repo"
INFRA_REL="apps/web-platform/infra"
PRISTINE="$SANDBOX_ROOT/$INFRA_REL"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || die "could not resolve repo root"
mkdir -p "$PRISTINE" "$SANDBOX_ROOT/.github/workflows" "$SANDBOX_ROOT/.github/scripts" \
  || die "could not create sandbox tree"
# EXCLUDE `.terraform` (162 MB of provider plugins) rather than copying it and deleting it
# after. This runner's own header records that suites copying that tree are the heaviest bulk
# writers in the repo and can exhaust the shared tmpfs — producing a RED that looks like a real
# regression and is really a full disk. Nothing here needs it: the guard's render legs call
# `terraform console` in a fresh scratch dir, and `templatefile()` is a builtin that loads no
# provider. tar rather than rsync because tar is always present; `set -o pipefail` above makes
# a failure in EITHER half of the pipe reach the `||`.
(cd "$SCRIPT_DIR" && tar -cf - --exclude=./.terraform --exclude=./.terraform.lock.hcl .) \
  | (cd "$PRISTINE" && tar -xf -) \
  || die "could not copy $SCRIPT_DIR to $PRISTINE"
cp -a "$REPO_ROOT/.github/workflows/infra-validation.yml" "$SANDBOX_ROOT/.github/workflows/" \
  || die "could not copy infra-validation.yml into the sandbox"
cp -a "$REPO_ROOT/.github/scripts/validate-infra-templates.sh" "$SANDBOX_ROOT/.github/scripts/" \
  || die "could not copy validate-infra-templates.sh into the sandbox"
# Assert the exclusion actually held. A tar --exclude whose pattern stops matching (a leading
# `./` dropped, say) silently reinstates 162 MB per case, and the only symptom is a battery
# that gets mysteriously slower and starts failing on capacity somewhere else.
[[ -d "$PRISTINE/.terraform" ]] && die "the .terraform exclusion did not hold — the sandbox copy would be ~162 MB per case"
[[ -f "$PRISTINE/$GUARD" ]] || die "sandbox is missing $GUARD"
[[ -f "$PRISTINE/$SRC" ]]   || die "sandbox is missing $SRC"

# The guard's AC6 leg FAILS LOUDLY rather than SKIPPING when it sees a CI marker with no
# reachable git tags — correct there, noise here (the sandbox is not a git repo). Unset both so
# every run in this battery takes the same branch, in CI and locally alike. Without this the
# battery's own verdicts differ between a laptop and the runner.
unset CI GITHUB_ACTIONS

# Runs the guard in a sandbox. Echoes the exit code; writes the log to $2.
run_guard() {
  local dir="$1" log="$2"
  ( cd "$dir" && bash "./$GUARD" ) > "$log" 2>&1
  echo $?
}

# --- Baseline: the guard must be GREEN on an unmutated tree ------------------------------
# Without this, every case below could be passing for a reason unrelated to its mutation.
BASE_LOG="$WORK/baseline.log"
BASE_RC="$(run_guard "$PRISTINE" "$BASE_LOG")"
if [[ "$BASE_RC" != "0" ]]; then
  echo "HARNESS ABORT: the guard is not green on an UNMUTATED sandbox (rc=$BASE_RC)." >&2
  echo "Every mutation case below would report RED for a reason that is not its mutation." >&2
  grep -E '^  FAIL|^=== Results' "$BASE_LOG" >&2 | head -20
  exit 2
fi
echo "=== Guard 1 (#7462) mutation battery ==="
echo "baseline: guard GREEN on unmutated sandbox ($(grep -oE '[0-9]+/[0-9]+ passed' "$BASE_LOG" | head -1))"
echo ""

# case <id> <expected-failing-assertion-substring> <file-to-mutate> <python-mutator>
#
# The mutator is python rather than sed because three of the six rows are RELOCATIONS or
# multi-line edits, and because python's str.replace lets the case ASSERT its anchor was found
# instead of silently no-opping (a sed `s///` that matches nothing exits 0 and prints success).
case_mutate() {
  local id="$1" expect="$2" target="$3" mutator="$4"
  TOTAL=$((TOTAL + 1))

  local dir="$WORK/case-$id"
  rm -rf "$dir"
  cp -a "$SANDBOX_ROOT" "$dir" || die "case $id: could not copy sandbox"
  local tgt="$dir/$INFRA_REL/$target"
  [[ -f "$tgt" ]] || die "case $id: mutation target $target is not in the sandbox"
  local before="$WORK/case-$id.before"
  cp "$tgt" "$before" || die "case $id: could not back up $target"

  if ! python3 -c "$mutator" "$tgt"; then
    die "case $id: mutator failed to apply (its anchor was not found) — this case tested NOTHING"
  fi
  if diff -q "$before" "$tgt" >/dev/null 2>&1; then
    die "case $id: mutation did not change $target — this case tested NOTHING"
  fi

  local log="$WORK/case-$id.log"
  local rc; rc="$(run_guard "$dir/$INFRA_REL" "$log")"

  if [[ "$rc" == "0" ]]; then
    FAIL=$((FAIL + 1))
    echo "  SURVIVED: $id — the guard stayed GREEN under this mutation."
    echo "            Two readings, and one of them must be recorded before this ships:"
    echo "            (a) the guard's fixtures do not exercise the property — fix the FIXTURES;"
    echo "            (b) the mutant is EQUIVALENT — prove no verdict changes, and say so here."
    return
  fi
  # Scope to FAILURE lines. `assert()` echoes the description on PASS as well as FAIL, so an
  # unscoped grep matched the PASS line of the very assertion the row claims went RED — 7 of 9
  # rows passed with their named assertion neutered to `true`, and one was misrouting on the
  # unmutated tree. The row's contract is "THIS assertion failed", not "the guard exited 1".
  if ! grep -E '^  FAIL' "$log" | grep -qF "$expect"; then
    FAIL=$((FAIL + 1))
    echo "  MISROUTED: $id — the guard went RED, but NOT on the assertion this row targets."
    echo "             expected a failure naming: $expect"
    echo "             actual failures:"
    grep -E '^  FAIL' "$log" | head -5 | sed 's/^/               /'
    return
  fi
  PASS=$((PASS + 1))
  echo "  KILLED:   $id — RED on \"$expect\""
}

# ---------------------------------------------------------------------------------------
# Matrix row 1 — reorder so the GHCR ref is attempted first.
# Relocates the pre-oci-pull emit ABOVE the resolution region, so the effective (GHCR-seeded)
# pull no longer follows a completed resolution.
# ---------------------------------------------------------------------------------------
case_mutate row1-ghcr-attempted-first \
  "Row1: the zot leg is attempted BEFORE pre-oci-pull" \
  "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
import re as _re
m=_re.search(r"^    /usr/local/bin/inngest-boot-phone-home\.sh pre-oci-pull .*\n", s, _re.M)
assert m, "pre-oci-pull emit not found"
emit=m.group(0)
anchor="    ZOT_LEG=unconfigured\n"
assert anchor in s, "ZOT_LEG anchor not found"
s=s[:m.start()]+s[m.end():]
s=s.replace(anchor,emit+anchor,1)
open(p,"w").write(s)
'

# ---------------------------------------------------------------------------------------
# Matrix row 2 — drop the @sha256: digest from the zot ref (mutable-tag form).
# ---------------------------------------------------------------------------------------
case_mutate row2-zot-ref-loses-digest \
  "Row2: the zot leg carries a full sha256 digest pin" \
  "$SRC" '
import re,sys
p=sys.argv[1]; s=open(p).read()
m=re.search(r"^(\s*ZIREF=\"[^\"]*?)@sha256:[0-9a-f]{64}(\")$",s,re.M)
assert m, "ZIREF digest-pinned assignment not found"
s=s[:m.start()]+m.group(1)+m.group(2)+s[m.end():]
open(p,"w").write(s)
'

# ---------------------------------------------------------------------------------------
# Matrix row 3 — silence the inngest_ghcr_fallback emit on the flip.
# This is the mutation that matters most operationally: it leaves a WORKING boot (GHCR still
# serves) whose zot miss is invisible, which is the "silently degraded to break-glass" state
# ADR-096 Phase 5 must not retire GHCR on top of.
# ---------------------------------------------------------------------------------------
case_mutate row3-fallback-emit-silenced \
  "Row3: the zot->GHCR flip emits inngest_ghcr_fallback" \
  "$SRC" '
import re,sys
p=sys.argv[1]; s=open(p).read()
out=[l for l in s.split("\n") if "inngest-boot-phone-home.sh inngest_ghcr_fallback" not in l]
assert len(out)<len(s.split("\n")), "fallback emit line not found"
open(p,"w").write("\n".join(out))
'

# ---------------------------------------------------------------------------------------
# Matrix row 4 — point ONE downstream consumer at the GHCR literal while the pull uses zot.
# The row the plan calls out as "precisely how a zot-primary change ships while still pulling
# from GHCR". Adds a second member AFTER a compliant first, so the count guard and the
# per-consumer set guard are both exercised.
# ---------------------------------------------------------------------------------------
case_mutate row4-extract-consumer-rederives-ghcr \
  "Row4: consumer 2/4 — the extract container reads" \
  "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
old="docker create --name soleur-inngest-bootstrap-extract \"$IREF\""
new="docker create --name soleur-inngest-bootstrap-extract ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24@sha256:6cdaa63d1496642e681898a831234b712f75d3b09bd0844bcabec3de74b0a0f8"
assert old in s, "extract consumer not found"
open(p,"w").write(s.replace(old,new,1))
'

# ---------------------------------------------------------------------------------------
# Matrix row 5 — remove the both-legs-failed marker.
# ---------------------------------------------------------------------------------------
case_mutate row5-all-legs-marker-removed \
  "Row5: a distinct all-legs-failed stage exists" \
  "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
lines=s.split("\n")
out=[l for l in lines if "inngest-boot-phone-home.sh oci-pull-ALL-LEGS-FAILED" not in l]
assert len(out)<len(lines), "all-legs-failed emit line not found"
open(p,"w").write("\n".join(out))
'

# ---------------------------------------------------------------------------------------
# Matrix row 6 — make the guard VACUOUS: point it at a file with no content.
# Targets the guard'"'"'s own dispatch rather than the SUT. Without the Row6 accounting the
# whole Guard 1 section would report clean against an empty input, because a `grep -q` over
# nothing is simply false and every NEGATIVE assertion passes.
# ---------------------------------------------------------------------------------------
case_mutate row6-guard-checks-zero-content \
  "Row6 anti-vacuity" \
  "$GUARD" '
import sys
p=sys.argv[1]; s=open(p).read()
old="INNGEST_CI_YML=\"$SCRIPT_DIR/cloud-init-inngest.yml\""
new="INNGEST_CI_YML=\"$SCRIPT_DIR/cloud-init-inngest.EMPTY.yml\"; : > \"$INNGEST_CI_YML\""
assert old in s, "INNGEST_CI_YML assignment not found"
open(p,"w").write(s.replace(old,new,1))
'

# ---------------------------------------------------------------------------------------
# Beyond the matrix. Three properties the arm depends on that the matrix does not name, each
# of which fails SILENTLY in production: the boot still completes, it is just permanently on
# the break-glass leg or leaking a credential.
# ---------------------------------------------------------------------------------------

# Without the restart, daemon.json sits on disk unread for the whole boot (the docker.io
# package started the daemon during `packages:`), docker refuses the plain-HTTP registry, and
# the "zot-primary" arm falls back on EVERY boot — inert by accident, and green everywhere.
case_mutate extra-docker-not-restarted \
  "Phase4: docker is RESTARTED after the daemon config is written" \
  "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
lines=s.split("\n")
out=[l for l in lines if "systemctl restart docker" not in l or l.strip().startswith("#")]
assert len(out)<len(lines), "systemctl restart docker line not found"
open(p,"w").write("\n".join(out))
'

# The login must precede the pull it authorizes. Relocating it after the resolution region
# reproduces the exact defect the placement exists to avoid (the bootstrap image ships its own
# zot_login, which runs too late to authorize the pull that fetches that very image).
case_mutate extra-zot-login-after-pull \
  "Phase5: the zot login precedes the zot pull" \
  "$SRC" '
import re,sys
p=sys.argv[1]; s=open(p).read()
m=re.search(r"^ *if printf .*docker login \"\$ZOT_EP\" -u \"\$ZOT_PULL_USER\".*$",s,re.M)
assert m, "zot login line not found"
line=m.group(0).strip()
s=s[:m.start()]+"        if true; then"+s[m.end():]
# Anchor on the PULL itself, not on the pre-zot-pull emit. The emit precedes the pull, so
# inserting there relocates the login to a DIFFERENT place that is still before the pull --
# a mutation that does not reproduce the defect it names, and its survival would read as a
# gap in the guard rather than a bug in this case. It did, on the first run.
pm=re.search(r"^ *(timeout [0-9]+ )?docker pull \"\$ZIREF\" > /var/log/inngest-zot-pull\.log 2>&1\n",s,re.M)
assert pm, "zot pull anchor not found"
s=s[:pm.end()] + "      " + line + " :; fi\n" + s[pm.end():]
open(p,"w").write(s)
'

# A credential absent from inngest-redact.sh ships in clear on exactly the path that carries
# it: the zot leg auth failure is what produces a log tail worth shipping in the first place.
case_mutate extra-zot-token-not-redacted \
  "the zot pull token is in inngest-redact.sh" \
  "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
old="      . /etc/default/soleur-zot-read 2>/dev/null; vals+=(\"$ZOT_PULL_TOKEN\")\n"
assert old in s, "redact value-list line not found"
open(p,"w").write(s.replace(old,"",1))
'

echo ""
echo "=== Results: $PASS/$TOTAL mutants killed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL mutant(s) survived or misrouted — the guard does not pin what it claims."
  exit 1
fi
echo "OK"
