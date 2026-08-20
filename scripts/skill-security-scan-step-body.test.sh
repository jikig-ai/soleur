#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guards 1–3 for #7629 — the skill-security-scan PR gate's fail-open paths.
#
# WHAT THIS EXISTS TO CATCH. The gate is a set of `run:` bodies in two workflow
# files. Nothing executed those bodies, so every assertion about them was a
# claim about YAML text rather than about behaviour — and six paths through
# them reported success while producing zero scan coverage. A grep over the
# workflow source cannot distinguish "the gate blocks this input" from "the
# gate never looked", because both render as the same bytes on disk.
#
# So this harness EXTRACTS each in-scope body and EXECUTES it, under the shell
# GitHub Actions actually uses. That shell matters and is easy to get wrong: a
# `run:` block with no `shell:` key runs under
#     bash --noprofile --norc -eo pipefail {0}
# so `-e` and `pipefail` are ON before the body's own `set -euo pipefail` runs.
# A harness that executes an extracted block under a bare `bash` cannot observe
# any `set -e` abort, which is precisely the class that ships here.
#
# RED BY DESIGN AT THE COMMIT THAT INTRODUCES IT. Fixtures 1a–1e assert the
# gate FAILS CLOSED on inputs it currently passes, so they fail against the
# unmodified workflows. That is the point: the closer is the NEXT commit, which
# touches `.github/workflows/skill-security-scan-*`. The separation is
# re-derivable from history forever —
#   git log --diff-filter=A --format=%H -- scripts/skill-security-scan-step-body.test.sh
# yields a SHA whose `git show --name-only` contains no workflow path.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation of this suite inherits the bare /tmp, a machine-global
# 4 GiB tmpfs shared by every parallel worktree; the registered runners default
# to /var/tmp. Without this, verdicts become a function of another session's
# disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WF_PR="$REPO_ROOT/.github/workflows/skill-security-scan-pr-trailer.yml"
WF_PM="$REPO_ROOT/.github/workflows/skill-security-scan-postmerge.yml"

SANDBOX=$(mktemp -d -t sss-step-body.XXXXXXXX) || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
# A harness that fails to SET UP must abort, never continue — a half-built
# sandbox produces a CONFIDENT WRONG verdict about the SUT, not a missing one.
trap 'rm -rf "$SANDBOX"' EXIT

python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to extract the step bodies (python3 -c "import yaml" failed)\n' >&2
  exit 2; }

# ── Guard 1 — extraction / dispatch ──────────────────────────────────────────
#
# THE IN-SCOPE SET, WRITTEN DOWN. A harness that discovers its own work-list
# from the same file it audits cannot tell "this body is clean" from "this body
# was never extracted" — the count shrinks on both sides and the check holds.
# So the four bodies are named here, and their number is asserted against a
# literal below.
IN_SCOPE_PR=(
  "Identify added SKILL/agent files in PR diff"
  "Validate override artifacts (if any)"
  "Run scanner against each added SKILL/agent"
)
IN_SCOPE_PM=(
  "Detect merged HIGH-RISK skills without override"
)
# THE EXCLUSION SET, WITH ITS REASON. Both workflows carry a one-line
# `Assert jq present …` step. It is excluded because it asserts a runner-image
# dependency and has no branch that can report success without doing its work —
# it is `command -v jq` and nothing else. Excluding it is a decision recorded
# here, not an accident of a glob that happened not to match it.
EXCLUDED=(
  "Assert jq present (runner-image dependency — no install, no network)"
)

extract_body() {  # $1=workflow $2=step name $3=destination file
  python3 - "$1" "$2" "$3" <<'PY'
import sys, yaml
wf, want, dest = sys.argv[1], sys.argv[2], sys.argv[3]
d = yaml.safe_load(open(wf))
hits = [s for j in d["jobs"].values() for s in j.get("steps", []) if s.get("name", "") == want]
if len(hits) != 1:
    sys.stderr.write(f"expected exactly 1 step named {want!r} in {wf}, found {len(hits)}\n")
    sys.exit(1)
if "run" not in hits[0]:
    sys.stderr.write(f"step {want!r} in {wf} has no run: body\n")
    sys.exit(1)
open(dest, "w").write(hits[0]["run"])
PY
}

# G1.1 — every in-scope name resolves to exactly one extractable body.
_extracted=0
for _n in "${IN_SCOPE_PR[@]}"; do
  if extract_body "$WF_PR" "$_n" "$SANDBOX/body.$_extracted" 2>"$SANDBOX/x.err"; then
    pass; _extracted=$((_extracted + 1))
  else
    fail "G1.1 pr-trailer: could not extract step $_n: $(cat "$SANDBOX/x.err")"
  fi
done
for _n in "${IN_SCOPE_PM[@]}"; do
  if extract_body "$WF_PM" "$_n" "$SANDBOX/body.$_extracted" 2>"$SANDBOX/x.err"; then
    pass; _extracted=$((_extracted + 1))
  else
    fail "G1.2 postmerge: could not extract step $_n: $(cat "$SANDBOX/x.err")"
  fi
done

# G1.3 — SHAPE PREDICATE. Every `run:` body in both workflows is either in the
# in-scope set or in the written-down exclusion set. This is what catches a
# NEW un-audited step being added: a body that is in neither set reds here,
# rather than silently escaping the harness.
# Names are passed through the ENVIRONMENT, newline-delimited, and split in
# Python. They are NOT interpolated into the heredoc: `${arr[@]@Q}` renders as
# a run of adjacent quoted literals, and Python CONCATENATES adjacent string
# literals into one — so an interpolated list silently collapses to a single
# member and every real name reads as unclassified. That produced a confident
# false RED the first time this guard ran.
_unclassified=$(
  SSS_IN_SCOPE="$(printf '%s\n' "${IN_SCOPE_PR[@]}" "${IN_SCOPE_PM[@]}")" \
  SSS_EXCLUDED="$(printf '%s\n' "${EXCLUDED[@]}")" \
  python3 - "$WF_PR" "$WF_PM" <<'PY'
import os, sys, yaml
in_scope = {n for n in os.environ["SSS_IN_SCOPE"].split("\n") if n}
excluded = {n for n in os.environ["SSS_EXCLUDED"].split("\n") if n}
out = []
for wf in sys.argv[1:]:
    d = yaml.safe_load(open(wf))
    for j in d["jobs"].values():
        for s in j.get("steps", []):
            if "run" not in s:
                continue
            n = s.get("name", "")
            if n not in in_scope and n not in excluded:
                out.append(f"{wf}:{n}")
print("\n".join(out))
PY
)
if [ -z "$_unclassified" ]; then
  pass
else
  fail "G1.3 un-audited run: body present in neither the in-scope nor the exclusion set: $_unclassified"
fi

# ── Fixture plumbing ─────────────────────────────────────────────────────────
#
# EVERY FIXTURE CWD MUST CARRY STUBS FOR *BOTH* SCRIPTS THE BODIES INVOKE.
# The scan body's very first assignment calls parse-override.sh; the audit
# body's does too. Under `set -euo pipefail` a missing script makes bash exit
# 127 and pipefail propagates it, so a fixture lacking the parse-override.sh
# stub would make a RED fixture "fail" for the wrong reason and fabricate the
# RED evidence this harness exists to produce honestly.
SCAN_REL="plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh"
OVER_REL="plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh"

mkfixture() {  # $1=name; echoes the fixture root
  local root="$SANDBOX/fx-$1"
  mkdir -p "$root/$(dirname "$SCAN_REL")"
  # Default stubs: a well-behaved scanner and a well-behaved override parser.
  # Individual fixtures overwrite whichever one they are exercising.
  cat > "$root/$SCAN_REL" <<'STUB'
#!/usr/bin/env bash
echo "LOW-RISK"
STUB
  cat > "$root/$OVER_REL" <<'STUB'
#!/usr/bin/env bash
echo '{"matched":[],"invalid_schema":[],"stale_findings":[]}'
STUB
  chmod +x "$root/$SCAN_REL" "$root/$OVER_REL"
  printf '%s' "$root"
}

# Executes an extracted body under the shell GitHub Actions actually uses.
# `--noprofile --norc -eo pipefail` is the documented default for a `run:`
# block with no `shell:` key; running it under a bare `bash` would make the
# entire `set -e` abort class structurally invisible.
run_body() {  # $1=body file $2=cwd; env passed by caller; stdout+stderr -> $OUT, status -> $RC
  OUT="$SANDBOX/out.$$.$RANDOM"
  ( cd "$2" && GITHUB_OUTPUT="$2/gh_output" bash --noprofile --norc -eo pipefail "$1" ) \
    >"$OUT" 2>&1
  RC=$?
}

BODY_IDENT="$SANDBOX/body.0"   # Identify added SKILL/agent files in PR diff
BODY_OVER="$SANDBOX/body.1"    # Validate override artifacts (if any)
BODY_SCAN="$SANDBOX/body.2"    # Run scanner against each added SKILL/agent
BODY_AUDIT="$SANDBOX/body.3"   # Detect merged HIGH-RISK skills without override

# ── 1a — a base SHA git cannot resolve must FAIL CLOSED ──────────────────────
#
# MOTIVATING INPUT (#7629): BASE_SHA=0000000000000000000000000000000000000000.
# `git diff … | grep … || true` puts the `|| true` on the WHOLE pipeline, so a
# git failure and a legitimately-empty diff are the same observable: `added`
# empty, `no_new_skills=true`, gate green having scanned nothing.
# Asserted on that concrete SHA, not on a token.
_fx=$(mkfixture 1a)
( cd "$_fx" && git init -q -b main . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m one \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m two ) >/dev/null 2>&1 || {
  printf 'FAIL: 1a fixture repo could not be built\n' >&2; exit 2; }
BASE_SHA=0000000000000000000000000000000000000000 \
HEAD_SHA=$(git -C "$_fx" rev-parse HEAD) \
  run_body "$BODY_IDENT" "$_fx"
if [ "$RC" -ne 0 ]; then
  pass
else
  fail "1a UNRESOLVABLE BASE: body exited 0 on BASE_SHA=0000000000000000000000000000000000000000 (git cannot resolve it); the gate reports no_new_skills and scans nothing. Output: $(head -c 300 "$OUT")"
fi
if grep -q '::error::' "$OUT" 2>/dev/null; then
  pass
else
  fail "1a UNRESOLVABLE BASE: no ::error:: annotation naming the unresolvable base/head pair"
fi

# ── 1b — a scanner that crashes must FAIL CLOSED ─────────────────────────────
#
# MOTIVATING INPUT: run-scan.sh writes a Python traceback to stderr and exits 1.
# Today `2>/dev/null` discards the traceback and `|| echo 'UNKNOWN'` converts a
# crash into a non-HIGH-RISK verdict, so `fail` stays 0.
_fx=$(mkfixture 1b)
mkdir -p "$_fx/plugins/soleur/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$_fx/plugins/soleur/skills/demo/SKILL.md"
cat > "$_fx/$SCAN_REL" <<'STUB'
#!/usr/bin/env bash
echo "Traceback (most recent call last):" >&2
echo "  File \"run-scan.py\", line 1, in <module>" >&2
echo "RuntimeError: rule pack failed to load" >&2
exit 1
STUB
chmod +x "$_fx/$SCAN_REL"
ADDED="plugins/soleur/skills/demo/SKILL.md" BASE_SHA=x HEAD_SHA=y \
  run_body "$BODY_SCAN" "$_fx"
if [ "$RC" -ne 0 ]; then
  pass
else
  fail "1b SCANNER CRASH: body exited 0 though run-scan.sh exited 1 with a traceback; a crashed scanner is scored as a clean skill. Output: $(head -c 300 "$OUT")"
fi
if grep -q 'RuntimeError: rule pack failed to load' "$OUT" 2>/dev/null; then
  pass
else
  fail "1b SCANNER CRASH: the scanner's stderr was discarded (2>/dev/null); the traceback that explains the failure never reaches the log"
fi

# ── 1c — a usage banner on stdout must FAIL CLOSED ───────────────────────────
#
# MOTIVATING INPUT: first stdout line is `usage: run-scan.sh [file]`, exit 0.
# No verdict token is present, `grep -oE` finds nothing, `|| echo UNKNOWN`
# supplies a verdict the gate then treats as acceptable.
# Asserting the output NAMES the rejected verdict token is what stops this
# passing on an unrelated abort.
_fx=$(mkfixture 1c)
mkdir -p "$_fx/plugins/soleur/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$_fx/plugins/soleur/skills/demo/SKILL.md"
cat > "$_fx/$SCAN_REL" <<'STUB'
#!/usr/bin/env bash
echo "usage: run-scan.sh [file]"
exit 0
STUB
chmod +x "$_fx/$SCAN_REL"
ADDED="plugins/soleur/skills/demo/SKILL.md" BASE_SHA=x HEAD_SHA=y \
  run_body "$BODY_SCAN" "$_fx"
if [ "$RC" -ne 0 ]; then
  pass
else
  fail "1c USAGE BANNER: body exited 0 though the scanner emitted no verdict token; 'usage: run-scan.sh [file]' is scored as a pass. Output: $(head -c 300 "$OUT")"
fi
if grep -qE 'UNKNOWN' "$OUT" 2>/dev/null; then
  pass
else
  fail "1c USAGE BANNER: output does not name the rejected verdict token (UNKNOWN), so the non-zero exit cannot be attributed to the unparseable verdict rather than to an unrelated abort"
fi

# ── 1d — zero verdicts produced must FAIL CLOSED (P2b) ───────────────────────
#
# MOTIVATING INPUT: no_new_skills=false — the gate believes it has work — yet
# every listed path is unreadable, so the loop's `[ ! -f "$path" ] && continue`
# arms skip all of them, `fail` stays 0 and the step exits 0 having produced
# ZERO verdicts. This is the fail-open one step BELOW where the issue cuts:
# the gate is not merely lenient about a bad verdict, it is silent about
# having formed none at all.
_fx=$(mkfixture 1d)
ADDED=$'plugins/soleur/skills/ghost-one/SKILL.md\nplugins/soleur/skills/ghost-two/SKILL.md' \
BASE_SHA=x HEAD_SHA=y \
  run_body "$BODY_SCAN" "$_fx"
if [ "$RC" -ne 0 ]; then
  pass
else
  fail "1d ZERO VERDICTS: body exited 0 with no_new_skills=false and 2 unreadable paths — it scanned nothing and reported success. Output: $(head -c 300 "$OUT")"
fi

# ── 1e — an unresolvable postmerge base must FAIL CLOSED ─────────────────────
#
# MOTIVATING INPUT: a root commit, where `git rev-parse HEAD^1` cannot resolve.
# Today the `|| git rev-parse HEAD` fallback makes base==head, so the audit
# diffs a commit against itself, finds nothing added, and prints
# "nothing to audit" — a bypass audit that structurally cannot detect a bypass.
_fx=$(mkfixture 1e)
( cd "$_fx" && git init -q -b main . \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root ) >/dev/null 2>&1 || {
  printf 'FAIL: 1e fixture repo could not be built\n' >&2; exit 2; }
MERGE_SHA=$(git -C "$_fx" rev-parse HEAD) run_body "$BODY_AUDIT" "$_fx"
if [ "$RC" -ne 0 ]; then
  pass
else
  fail "1e UNRESOLVABLE POSTMERGE BASE: audit exited 0 on a root commit where HEAD^1 does not resolve; it degraded to diffing HEAD against itself and reported 'nothing to audit'. Output: $(head -c 300 "$OUT")"
fi

# ── 1f — the merge_group base/head shape must PASS ───────────────────────────
#
# A HARNESS THAT ONLY EVER ASSERTS "MUST FAIL" CANNOT SEE A GATE THAT BECOMES
# TOO AGGRESSIVE. Every fixture above is a must-FAIL; these are the far side of
# the transform. Without them, a fix that makes the gate reject everything
# would score a perfect run.
_fx=$(mkfixture 1f)
( cd "$_fx" && git init -q -b main . \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m head ) >/dev/null 2>&1 || {
  printf 'FAIL: 1f fixture repo could not be built\n' >&2; exit 2; }
BASE_SHA=$(git -C "$_fx" rev-parse HEAD~1) \
HEAD_SHA=$(git -C "$_fx" rev-parse HEAD) \
  run_body "$BODY_IDENT" "$_fx"
if [ "$RC" -eq 0 ]; then
  pass
else
  fail "1f MERGE_GROUP SHAPE: body exited $RC on a well-formed base/head pair with no added skills — the gate now fails closed on a legitimately empty diff. Output: $(head -c 300 "$OUT")"
fi
if grep -q 'no_new_skills=true' "$_fx/gh_output" 2>/dev/null; then
  pass
else
  fail "1f MERGE_GROUP SHAPE: no_new_skills=true was not written to GITHUB_OUTPUT on an empty diff"
fi

# ── 1g — the must-PASS rows from Guards 1–3 ──────────────────────────────────

# 1g.i — a clean override parse must PASS.
_fx=$(mkfixture 1g-i)
BASE_SHA=x HEAD_SHA=y run_body "$BODY_OVER" "$_fx"
if [ "$RC" -eq 0 ]; then
  pass
else
  fail "1g.i CLEAN OVERRIDE: body exited $RC on a well-formed empty override payload. Output: $(head -c 300 "$OUT")"
fi

# 1g.ii — a genuine LOW-RISK skill must PASS.
_fx=$(mkfixture 1g-ii)
mkdir -p "$_fx/plugins/soleur/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$_fx/plugins/soleur/skills/demo/SKILL.md"
ADDED="plugins/soleur/skills/demo/SKILL.md" BASE_SHA=x HEAD_SHA=y \
  run_body "$BODY_SCAN" "$_fx"
if [ "$RC" -eq 0 ]; then
  pass
else
  fail "1g.ii LOW-RISK SKILL: scan body exited $RC on a readable skill the scanner scored LOW-RISK. Output: $(head -c 300 "$OUT")"
fi

# 1g.iii — a HIGH-RISK skill WITH a matching override must PASS. This is the
# arm that proves the per-skill binding still accepts a legitimate override,
# rather than the gate having been hardened into rejecting every HIGH-RISK.
_fx=$(mkfixture 1g-iii)
mkdir -p "$_fx/plugins/soleur/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$_fx/plugins/soleur/skills/demo/SKILL.md"
cat > "$_fx/$SCAN_REL" <<'STUB'
#!/usr/bin/env bash
echo "HIGH-RISK"
STUB
cat > "$_fx/$OVER_REL" <<'STUB'
#!/usr/bin/env bash
echo '{"matched":[{"skill":"demo"}],"invalid_schema":[],"stale_findings":[]}'
STUB
chmod +x "$_fx/$SCAN_REL" "$_fx/$OVER_REL"
ADDED="plugins/soleur/skills/demo/SKILL.md" BASE_SHA=x HEAD_SHA=y \
  run_body "$BODY_SCAN" "$_fx"
if [ "$RC" -eq 0 ]; then
  pass
else
  fail "1g.iii HIGH-RISK + MATCHING OVERRIDE: scan body exited $RC though slug 'demo' appears in matched[]; a legitimate override is being rejected. Output: $(head -c 300 "$OUT")"
fi

# 1g.iv — a HIGH-RISK skill WITHOUT an override must still FAIL. This is the
# gate's original purpose; if it ever stops holding, every other assertion here
# is measuring a gate that does not gate.
_fx=$(mkfixture 1g-iv)
mkdir -p "$_fx/plugins/soleur/skills/demo"
printf -- '---\nname: demo\n---\nbody\n' > "$_fx/plugins/soleur/skills/demo/SKILL.md"
cat > "$_fx/$SCAN_REL" <<'STUB'
#!/usr/bin/env bash
echo "HIGH-RISK"
STUB
chmod +x "$_fx/$SCAN_REL"
ADDED="plugins/soleur/skills/demo/SKILL.md" BASE_SHA=x HEAD_SHA=y \
  run_body "$BODY_SCAN" "$_fx"
if [ "$RC" -ne 0 ]; then
  pass
else
  fail "1g.iv HIGH-RISK WITHOUT OVERRIDE: scan body exited 0 — the gate's primary purpose no longer holds"
fi

# ── Assertion floor ──────────────────────────────────────────────────────────
#
# DELIBERATELY NOT ROUTED THROUGH fail(). A floor that increments the same
# counter it guards shares a lifetime with the thing it is checking: gut the
# suite and the floor disappears alongside the assertions, so the run still
# reports a clean total. This one compares against a literal and exits
# directly, so deleting assertions above reddens the run rather than shrinking
# both sides of an equality.
_total=$((passes + fails))
_FLOOR=17
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'skill-security-scan-step-body: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'skill-security-scan-step-body: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
[ "$fails" -eq 0 ] || exit 1
exit 0
