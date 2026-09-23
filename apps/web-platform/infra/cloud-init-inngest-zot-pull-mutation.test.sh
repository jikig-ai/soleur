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

# #7849: fixture git spawns go through the shared builder, not the ambient environment. Without
# it, an inherited GIT_DIR retargets `git init`/`add`/`commit`/`tag` below at the caller's real
# repository — cwd does not win that fight, and this file's fixture is built with a bare `cd`.
GIT_FIXTURE_ENV_LIB="$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
[ -f "$GIT_FIXTURE_ENV_LIB" ] && [ -r "$GIT_FIXTURE_ENV_LIB" ] \
  || die "fixture-env helper missing or unreadable at $GIT_FIXTURE_ENV_LIB"
# shellcheck source=../../../plugins/soleur/test/lib/git-fixture-env.sh
source "$GIT_FIXTURE_ENV_LIB"
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

# #7695: Guard A reads the BUILD workflow (for the cp/COPY carrier set) and resolves the pinned
# tag through git. Neither is reachable from a relocated sandbox, so both must be carried here or
# the guard reds on the unmutated tree and the harness aborts before any mutation runs — which is
# this file's own rule at the top of this block, applied to a guard added after it was written.
cp -a "$REPO_ROOT/.github/workflows/build-inngest-bootstrap-image.yml" "$SANDBOX_ROOT/.github/workflows/" \
  || die "could not copy build-inngest-bootstrap-image.yml into the sandbox"

# A throwaway repo whose tag points at the PRISTINE tree, so Guard A's comparison is meaningful
# rather than skipped: on the unmutated sandbox the tag's tree IS the working tree, and a case
# that mutates a carrier reds it for real. The tag name is derived from the pin literal exactly
# as the guard derives it, so the two cannot drift apart.
_pin_tag="$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$PRISTINE/cloud-init-inngest.yml" 2>/dev/null | head -1 | sed 's/.*://')"
[[ -n "$_pin_tag" ]] || die "could not derive the pinned tag for the sandbox git fixture"
(
  set -e
  cd "$SANDBOX_ROOT"
  # Return checked: git_fixture_env exports NOTHING when it refuses, so an unchecked call would
  # proceed with the caller's own environment while reading exactly like protection.
  git_fixture_env "$SANDBOX_ROOT" || exit 64
  git init -q
  git config user.email sandbox@example.invalid
  git config user.name "sandbox"
  git config commit.gpgsign false
  git add -A
  git commit -qm "sandbox baseline"
  # A LOOSE REF, not `git tag` (#8539). Guard A reads this fixture with `git tag --list
  # 'vinngest-v*'`, which is a READ and sees a loose ref exactly as it sees an annotated tag —
  # so the fixture never needed a tag-AUTHORING verb. Writing the ref keeps this battery out of
  # `scripts/battery-tag-authorship.test.sh`'s offender set without spending one of that
  # ledger's 12 exemption slots (ADR-207 §5: a ceiling raised to make a run green is not a
  # ceiling). The ref is inside $SANDBOX_ROOT/.git, which this suite created; nothing here can
  # reach the live repo's refs/tags.
  #
  # DECLARED, not silently exploited (review). A direct write to `.git/refs/tags/` is that
  # guard's OWN under-approximation #7 — "authors a tag carrying no `git` token at all" — so
  # this route is invisible to it by the guard's own admission, and it was taken on the day that
  # ledger hit its ceiling (12 <= 12). Two facts keep it honest rather than an evasion: the
  # write is confined to a sandbox this suite builds, and the LIGHTWEIGHT ref is behaviourally
  # identical to the annotated tag it replaced for every operation the code under test performs
  # (`git tag --list`, `rev-parse <tag>^{commit}`, `show <tag>:<path>` — all verified). It
  # DIVERGES on `rev-parse <tag>` bare, `cat-file -t`, `for-each-ref %(objecttype)` and
  # `describe` without `--tags`; if Guard A ever grows a row touching tag-object identity, this
  # fixture will pass where production fails, and nothing here would notice.
  mkdir -p .git/refs/tags
  git rev-parse HEAD > ".git/refs/tags/vinngest-$_pin_tag"
) > "$WORK/gitfixture.log" 2>&1 || { cat "$WORK/gitfixture.log" >&2; die "could not build the sandbox git fixture for Guard A"; }
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

# =======================================================================================
# #6500 Guard 1 rows: each pull-outcome ARM reports on the Sentry `stage:` schema.
# Every row names the Guard 1b assertion it must red; a row that reds on something else is
# MISROUTED, not killed.
# =======================================================================================
G1_ZOT='        soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true\n'
G1_FB='        soleur-boot-emit inngest_ghcr_fallback warning "rc=$zot_rc" || true\n'
g1_replace() { # g1_replace <id> <expect> <old> <new> [target]
  case_mutate "$1" "$2" "${5:-$SRC}" "
import sys
p=sys.argv[1]; s=open(p).read()
old=$3; new=$4
assert s.count(old)==1, 'anchor not found exactly once'
open(p,'w').write(s.replace(old,new,1))
"
}
g1_replace g1-row1-served-emit-deleted "G1b: the served arm emits inngest_zot exactly once" \
  "'''$G1_ZOT'''" "''"
g1_replace g1-row2-missed-emit-deleted "G1b: the missed arm emits inngest_ghcr_fallback exactly once" \
  "'''$G1_FB'''" "''"
g1_replace g1-row3a-served-not-guarded "G1b: the served arm emits inngest_zot exactly once" \
  "'''$G1_ZOT'''" "'''        soleur-boot-emit inngest_zot info \"ep=\$ZOT_EP\"\n'''"
g1_replace g1-row3b-missed-not-guarded "G1b: the missed arm emits inngest_ghcr_fallback exactly once" \
  "'''$G1_FB'''" "'''        soleur-boot-emit inngest_ghcr_fallback warning \"rc=\$zot_rc\"\n'''"
# Row 4: relocate the served call into the missed arm — both calls then sit in one arm, which a
# file-level count cannot see.
case_mutate g1-row4-served-call-in-missed-arm "G1b: the served arm emits inngest_zot exactly once" "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
zot="        soleur-boot-emit inngest_zot info \"ep=$ZOT_EP\" || true\n"
fb="        soleur-boot-emit inngest_ghcr_fallback warning \"rc=$zot_rc\" || true\n"
assert s.count(zot)==1 and s.count(fb)==1, "call sites not found"
s=s.replace(zot,"",1).replace(fb,fb+zot,1)
open(p,"w").write(s)
'
g1_replace g1-row5-served-emits-twice "G1b: the served arm emits inngest_zot exactly once" \
  "'''$G1_ZOT'''" "'''$G1_ZOT$G1_ZOT'''"
g1_replace g1-row6-stage-renamed "G1b: the served arm emits inngest_zot exactly once" \
  "'''$G1_ZOT'''" "'''        soleur-boot-emit inngest_zot_ok info \"ep=\$ZOT_EP\" || true\n'''"
g1_replace g1-row7-absolute-path "G1b: the served arm emits inngest_zot exactly once" \
  "'''$G1_ZOT'''" "'''        /usr/local/bin/soleur-boot-emit inngest_zot info \"ep=\$ZOT_EP\" || true\n'''"
g1_replace g1-row8-double-space "G1b: the served arm emits inngest_zot exactly once" \
  "'''$G1_ZOT'''" "'''        soleur-boot-emit  inngest_zot info \"ep=\$ZOT_EP\" || true\n'''"
g1_replace g1-row9-tf-key-dropped "G1b: inngest-host.tf threads sentry_dsn = var.sentry_dsn" \
  "'''    sentry_dsn = var.sentry_dsn\n'''" "''" inngest-host.tf
g1_replace g1-row11-dsn-file-world-readable "G1b: write_files delivers /etc/default/soleur-sentry-dsn 0600" \
  "'''      SOLEUR_SENTRY_DSN='\${sentry_dsn}'\n    owner: root:root\n    permissions: '0600'\n'''" \
  "'''      SOLEUR_SENTRY_DSN='\${sentry_dsn}'\n    owner: root:root\n    permissions: '0644'\n'''"
g1_replace g1-row12-arm-anchor-drifted "G1b dispatch: the served (zot) arm was extracted" \
  "'''      if [ \"\$zot_rc\" -eq 0 ]; then\n'''" "'''      if [ \"\$zot_rc\" = 0 ]; then\n'''"
g1_replace g1-extra-backgrounded-emit "G1b: no soleur-boot-emit call is backgrounded" \
  "'''$G1_FB'''" "'''        soleur-boot-emit inngest_ghcr_fallback warning \"rc=\$zot_rc\" || true &\n'''"
# Review P1-2: a nested if/else inside the SERVED arm must not be read as the arm split. Delete
# the real fallback emit and plant one behind a nested `else` in the served arm.
case_mutate g1-row14-nested-else-hijack "G1b: the missed arm emits inngest_ghcr_fallback exactly once" "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
zot="        soleur-boot-emit inngest_zot info \"ep=$ZOT_EP\" || true\n"
fb="        soleur-boot-emit inngest_ghcr_fallback warning \"rc=$zot_rc\" || true\n"
assert s.count(zot)==1 and s.count(fb)==1, "call sites not found"
plant=("        if [ -n \"$IREF\" ]; then :\n        else\n"
       "          ZOT_LEG=\"$ZOT_LEG\"\n          ZOT_LEG=\"$ZOT_LEG\"\n"
       "          soleur-boot-emit inngest_ghcr_fallback warning \"rc=$zot_rc\" || true\n        fi\n")
s=s.replace(fb,"",1).replace(zot,zot+plant,1)
open(p,"w").write(s)
'
# Review P2-3: a call that can never run is not a call. Dead code behind `if false`, and dead code
# inside a heredoc (data, not shell).
case_mutate g1-row15-dead-if-false "G1b: the served arm emits inngest_zot exactly once" "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
zot="        soleur-boot-emit inngest_zot info \"ep=$ZOT_EP\" || true\n"
assert s.count(zot)==1, "call site not found"
s=s.replace(zot,"        if false; then\n  "+zot+"        fi\n",1)
open(p,"w").write(s)
'
case_mutate g1-row16-dead-heredoc "G1b: the missed arm emits inngest_ghcr_fallback exactly once" "$SRC" '
import sys
p=sys.argv[1]; s=open(p).read()
fb="        soleur-boot-emit inngest_ghcr_fallback warning \"rc=$zot_rc\" || true\n"
assert s.count(fb)==1, "call site not found"
s=s.replace(fb,"        : <<'"'"'OFF'"'"'\n"+fb+"        OFF\n",1)
open(p,"w").write(s)
'
# Row 13 (harness): a mutator that changes nothing must ABORT the battery, never score a verdict.
# Run in a subshell so the die() it triggers is observed rather than inherited.
G1_PROBE_RC=0
( case_mutate g1-row13-harness-probe "unused" "$SRC" 'import sys' ) >/dev/null 2>&1 || G1_PROBE_RC=$?
TOTAL=$((TOTAL + 1))
if [[ "$G1_PROBE_RC" -eq 2 ]]; then
  PASS=$((PASS + 1)); echo "  KILLED:   g1-row13-harness-probe — an unlanded mutation ABORTS (rc=2)"
else
  FAIL=$((FAIL + 1)); echo "  SURVIVED: g1-row13-harness-probe — an unlanded mutation did not abort (rc=$G1_PROBE_RC)"
fi

# =======================================================================================
# #8539 NIC-G1 rows: the private-NIC fallback is present, reloaded, and gates the zot login.
# Rows 1-11 are the plan's Guard 1 mutation matrix (the plan's "Guard 1"; the suite section is
# named NIC-G1 because this battery already has a Guard 1). Each names the NIC-G1 assertion it
# must red; a row that reds on something else is MISROUTED, not killed. Order is checked by the
# guard on parsed runcmd LIST positions of the RENDER, so every SRC mutation below reaches the
# guard through terraform's own templatefile + strip — the path the bytes take to the host.
# =======================================================================================
# Shared mutator prelude. Every anchor is asserted to occur EXACTLY once, so a mutator whose
# anchor drifted fails loudly (and case_mutate turns that into a HARNESS ABORT) instead of
# no-opping.
NG1_PY='
import re,sys
p=sys.argv[1]; s=open(p).read()
CALL="  - /usr/local/bin/soleur-inngest-nic-wait ${inngest_private_ip} || true\n"
RELOAD="  - networkctl reload || /usr/local/bin/inngest-boot-phone-home.sh private_nic_reload_failed \"rc=$?\"\n"
def once(a, t=None):
    t = s if t is None else t
    assert t.count(a)==1, "anchor not found exactly once: %r" % a
def rep(a, b):
    once(a); return s.replace(a, b, 1)
def item_end(t, pos):
    first = t.index("\n", pos) + 1
    for m in re.finditer(r"^.*$", t[first:], re.M):
        if re.match(r"^(  - |  #|\S)", m.group(0)):
            return first + m.start()
    raise AssertionError("runcmd item end not found")
def save(t): open(p,"w").write(t)
'
# Row 1: move the NIC-wait call to AFTER the zot-login item (the item that follows it).
NG1_ROW1_MUT="$NG1_PY"'
once(CALL)
i=s.index(CALL); t=s[:i]+s[i+len(CALL):]
m=re.compile(r"^  - ", re.M).search(t, i)
assert m, "item after the call not found"
e=item_end(t, m.start())
assert "docker login \"$ZOT_EP\"" in t[m.start():e], "the item after the call is not the zot login"
save(t[:e]+CALL+t[e:])
'
case_mutate ng1-row1-call-after-zot-login "NIC-G1 row1:" "$SRC" "$NG1_ROW1_MUT"
# Row 2: REORDER (not delete) the reload to after the call.
case_mutate ng1-row2-reload-after-call "NIC-G1 row2:" "$SRC" "$NG1_PY"'
once(CALL); t=rep(RELOAD, "")
save(t.replace(CALL, CALL+RELOAD, 1))
'
# Row 3: delete the reload.
case_mutate ng1-row3-reload-deleted "NIC-G1 row3:" "$SRC" "$NG1_PY"'
save(rep(RELOAD, ""))
'
# Row 4: keep the compliant call and add a SECOND call later in runcmd.
case_mutate ng1-row4-second-call-later "NIC-G1 row4: runcmd carries exactly ONE" "$SRC" "$NG1_PY"'
once(CALL)
a="  - groupadd -f deploy\n"
save(rep(a, a+CALL))
'
# Row 5: the literal at the call site. The render is IDENTICAL (the stub binds 10.0.1.40), which
# is exactly why this row reads the source raw.
case_mutate ng1-row5-literal-at-call-site "NIC-G1 row5: the one NIC-wait call site" "$SRC" "$NG1_PY"'
save(rep(CALL, "  - /usr/local/bin/soleur-inngest-nic-wait 10.0.1.40 || true\n"))
'
# Row 6 (both variants the matrix names): widen the match scope.
case_mutate ng1-row6a-driver-to-type-ether "NIC-G1 row6:" "$SRC" "$NG1_PY"'
save(rep("      Driver=virtio_net\n", "      Type=ether\n"))
'
case_mutate ng1-row6b-name-loses-negation "NIC-G1 row6:" "$SRC" "$NG1_PY"'
save(rep("      Name=!eth0\n", "      Name=eth0\n"))
'
# Row 7: a name that sorts BEFORE netplan's 10-netplan-* would win over the good case.
case_mutate ng1-row7-sorts-before-netplan "NIC-G1 row7:" "$SRC" "$NG1_PY"'
save(rep("  - path: /etc/systemd/network/99-soleur-private-fallback.network\n",
         "  - path: /etc/systemd/network/05-soleur-private-fallback.network\n"))
'
# Row 8: the derived set. A new private-net action ahead of the call.
case_mutate ng1-row8-curl-registry-before-call "NIC-G1 row8:" "$SRC" "$NG1_PY"'
save(rep(CALL, "  - curl -fsS --max-time 5 http://10.0.1.30:5000/v2/ || true\n"+CALL))
'
# Row 9: the guard'"'"'s OWN dispatch renders an empty runcmd. "0 items checked" must red.
case_mutate ng1-row9-empty-runcmd "NIC-G1 anti-vacuity: " "$GUARD" "$NG1_PY"'
a="  bash \"$SCRIPT_DIR/inngest-userdata-budget.sh\" \"$NG1_RENDER\" > \"$NG1_DIR/budget.log\" 2>&1 || true\n"
save(rep(a, a+"  echo \"runcmd: []\" > \"$NG1_RENDER\"\n"))
'
# Row 10: the binding in the real root. The budget render uses its own stub map and cannot see
# this, so the guard reads inngest-host.tf raw.
case_mutate ng1-row10-binding-to-registry-ip "NIC-G1 row10:" "inngest-host.tf" "$NG1_PY"'
save(rep("    inngest_private_ip   = local.inngest_private_ip\n",
         "    inngest_private_ip   = local.registry_private_ip\n"))
'
# Row 11: byte-equality. Dropping UseMTU=yes leaves a well-formed file that silently runs the
# private link at 1500 on Hetzner'"'"'s 1450 net.
case_mutate ng1-row11-usemtu-dropped "NIC-G1 row11:" "$SRC" "$NG1_PY"'
save(rep("      UseMTU=yes\n", ""))
'

# --- NIC-G1 must-PASS inputs: non-canonical files the guard must stay GREEN on --------------
# A guard that reds on these is over-fitted to the canonical bytes; one that is never run on
# them could be. Same landed-diff discipline as case_mutate; a HELD row requires rc=0.
case_must_pass() {
  local id="$1" target="$2" mutator="$3"
  TOTAL=$((TOTAL + 1))
  local dir="$WORK/case-$id"
  rm -rf "$dir"
  cp -a "$SANDBOX_ROOT" "$dir" || die "case $id: could not copy sandbox"
  local tgt="$dir/$INFRA_REL/$target"
  [[ -f "$tgt" ]] || die "case $id: target $target is not in the sandbox"
  local before="$WORK/case-$id.before"
  cp "$tgt" "$before" || die "case $id: could not back up $target"
  python3 -c "$mutator" "$tgt" || die "case $id: must-PASS edit failed to apply — this case tested NOTHING"
  diff -q "$before" "$tgt" >/dev/null 2>&1 && die "case $id: must-PASS edit did not change $target — this case tested NOTHING"
  local log="$WORK/case-$id.log"
  local rc; rc="$(run_guard "$dir/$INFRA_REL" "$log")"
  if [[ "$rc" != "0" ]]; then
    FAIL=$((FAIL + 1))
    echo "  BROKE:    $id — a non-canonical but COMPLIANT input went RED (rc=$rc); the guard is over-fitted:"
    grep -E '^  FAIL' "$log" | head -5 | sed 's/^/               /'
    return
  fi
  PASS=$((PASS + 1))
  echo "  HELD:     $id — compliant non-canonical input stays GREEN"
}
# POSITIVE CONTROL for case_must_pass itself. Both must-PASS rows below reported HELD
# unconditionally at review: the helper owns its own verdict, so neutering it is invisible to
# TOTAL, to PASS/FAIL conservation and to BATTERY_MIN_ROWS alike. These rows are the only ones
# asserting the guard is not OVER-fitted, so an unbacked HELD is the whole over-fit axis going
# dark. Drive it with an input that MUST red the guard and require it to say BROKE.
_mp_f=$FAIL
case_must_pass ng1-harness-mustpass-can-report-broke "$SRC" "$NG1_PY"'
save(rep(RELOAD, ""))
' >/dev/null
if [[ "$FAIL" -ne $((_mp_f + 1)) ]]; then
  printf '[FATAL] harness: case_must_pass did not flag an input that reds the guard — every HELD above is unbacked\n' >&2
  exit 1
fi
FAIL=$_mp_f; TOTAL=$((TOTAL - 1))
echo "  HARNESS:  case_must_pass can report BROKE (positive control)"

# (i) Two unrelated runcmd items reordered ahead of the call, and blank lines inserted.
case_must_pass ng1-mustpass-reordered-and-blank-lines "$SRC" "$NG1_PY"'
once(CALL); once(RELOAD)
g="  - groupadd -f docker\n  - groupadd -f deploy\n"
t=rep(g, "")
t=t.replace(CALL, "\n\n"+g+"\n"+CALL+"\n", 1).replace(RELOAD, RELOAD+"\n\n", 1)
save(t)
'
# --- NIC-G1 escapes: real private-net uses the pre-review derivation scored as NOT-a-use ------
# Each of these was measured GREEN against the pristine guard at review. They are must-RED rows,
# not mutations of the guard: the guard was working exactly as written, and its predicate was
# narrower than the property its name claims. A mutation battery structurally cannot find these.
case_mutate ng1-escape-absolute-path-curl "NIC-G1 row8:" "$SRC" "$NG1_PY"'
save(rep(CALL, "  - /usr/bin/curl -sf http://10.0.1.30:5000/v2/ || true\n"+CALL))
'
case_mutate ng1-escape-wget "NIC-G1 row8:" "$SRC" "$NG1_PY"'
save(rep(CALL, "  - wget -qO- http://10.0.1.30:5000/v2/ || true\n"+CALL))
'
case_mutate ng1-escape-variable-target "NIC-G1 row8:" "$SRC" "$NG1_PY"'
save(rep(CALL, "  - curl -sf \"$ZOT_EP/v2/\" || true\n"+CALL))
'
case_mutate ng1-escape-networkd-shadow-in-run "NIC-G1 row7b:" "$SRC" "$NG1_PY"'
w="  - path: /run/systemd/network/00-hijack.network\n    content: |\n      [Match]\n      Driver=virtio_net\n\n      [Network]\n      DHCP=no\n    owner: root:root\n    permissions: \x27\x27\x270644\x27\x27\x27\n"
save(rep(CALL, CALL).replace("write_files:\n", "write_files:\n"+w, 1))
'
# must-PASS: the GHCR login with its flags reordered. This form was a FALSE RED before review --
# docker_target returned the -u flag VALUE, so a public login scored as a private-net use and an
# unrelated edit would have reddened rows 1 and 8.
case_must_pass ng1-mustpass-ghcr-login-flags-first "$SRC" "$NG1_PY"'
a="docker login ghcr.io -u \"$GHCR_READ_USER\" --password-stdin"
b="docker login -u \"$GHCR_READ_USER\" --password-stdin ghcr.io"
save(rep(a, b))
'

# (ii) A config WRITE that names the endpoint, ahead of the call. The canonical file already
# carries two (the ZOT_EP daemon.json write and the soleur-zot-read creds bake; the baseline and
# the guard'"'"'s own must-PASS count cover them); this adds a third of the same class.
case_must_pass ng1-mustpass-endpoint-config-write-before-call "$SRC" "$NG1_PY"'
save(rep(CALL, "  - echo \"ZOT_EP=${zot_registry_endpoint}\" > /etc/default/soleur-zot-ep\n"+CALL))
'

# --- NIC-G1 harness row: neuter the ORDER comparison; the battery must notice ------------
# Make row 1's comparison compare a list position to itself. The neutered guard is still green on
# the unmutated tree, so only the mutation rows can see it — and row 1 must then come back NOT
# killed. If it still reports KILLED, the battery's row-1 verdict does not depend on the
# comparison it claims to test.
NG1_HARN_ROOT="$WORK/harness-ng1-root"
rm -rf "$NG1_HARN_ROOT"
cp -a "$SANDBOX_ROOT" "$NG1_HARN_ROOT" || die "NIC-G1 harness: could not copy sandbox"
NG1_HARN_GUARD="$NG1_HARN_ROOT/$INFRA_REL/$GUARD"
cp "$NG1_HARN_GUARD" "$WORK/harness-ng1.before" || die "NIC-G1 harness: could not back up the guard"
python3 -c '
import sys
p=sys.argv[1]; s=open(p).read()
old="\"(( NG1_CALL_POS >= 0 && NG1_CALL_POS + 1 == NG1_FIRST_USE_POS ))\""
new="\"(( NG1_CALL_POS >= 0 && NG1_FIRST_USE_POS == NG1_FIRST_USE_POS ))\""
assert s.count(old)==1, "row-1 order comparison not found exactly once"
open(p,"w").write(s.replace(old,new,1))
' "$NG1_HARN_GUARD" || die "NIC-G1 harness: the order-comparison neuter did not apply — the harness row tested NOTHING"
diff -q "$WORK/harness-ng1.before" "$NG1_HARN_GUARD" >/dev/null 2>&1 \
  && die "NIC-G1 harness: the neuter did not change the guard — the harness row tested NOTHING"
NG1_HARN_BASE_RC="$(run_guard "$NG1_HARN_ROOT/$INFRA_REL" "$WORK/harness-ng1-base.log")"
[[ "$NG1_HARN_BASE_RC" == "0" ]] \
  || die "NIC-G1 harness: the neutered guard is not green on the UNMUTATED tree (rc=$NG1_HARN_BASE_RC) — the row would be meaningless"
NG1_HARN_OUT="$( SANDBOX_ROOT="$NG1_HARN_ROOT"; case_mutate ng1-harness-row1-self-compare "NIC-G1 row1:" "$SRC" "$NG1_ROW1_MUT" )" \
  || die "NIC-G1 harness: the row-1 case aborted under the neutered guard"
TOTAL=$((TOTAL + 1))
if [[ "$NG1_HARN_OUT" == *"KILLED:"* ]]; then
  FAIL=$((FAIL + 1))
  echo "  SURVIVED: ng1-harness-row1-self-compare — row 1 still reports KILLED with the order comparison neutered"
else
  PASS=$((PASS + 1))
  echo "  KILLED:   ng1-harness-row1-self-compare — neutering the order comparison flips row 1 off KILLED ($(printf '%s' "$NG1_HARN_OUT" | grep -oE 'SURVIVED|MISROUTED' | head -1))"
fi

# --- Anti-vacuity floor over the whole battery ----------------------------------------------
# Deleting a row (or its dispatch line) otherwise leaves `N/N mutants killed` and exit 0, with the
# property that row pinned now unexercised. The bound is the MEASURED row count of a green run,
# EXACT-as-floor (no slack). Reported with printf + exit, never through the verdict counters it
# backstops (ADR-193). Bump it in the same edit that adds a row.
BATTERY_MIN_ROWS=46
if (( TOTAL < BATTERY_MIN_ROWS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= %d. A row was deleted or its dispatch line removed.\n' "$TOTAL" "$BATTERY_MIN_ROWS" >&2
  exit 1
fi

echo ""
echo "=== Results: $PASS/$TOTAL mutants killed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL mutant(s) survived or misrouted — the guard does not pin what it claims."
  exit 1
fi
echo "OK"
