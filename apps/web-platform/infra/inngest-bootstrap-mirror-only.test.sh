#!/usr/bin/env bash
#
# Structural + behavioral gate for the `mirror_only` backfill path of
# .github/workflows/build-inngest-bootstrap-image.yml (#7144 finding 2).
#
# WHY A DEDICATED SUITE. This workflow publishes the image cloud-init.yml's web-host arm
# execs AS ROOT, and `mirror_only` exists so a caller can backfill an already-published tag
# onto zot and then PIN it by @sha256. That makes exactly one property load-bearing:
#
#   a GREEN mirror_only run must mean "zot serves the GHCR digest for this tag".
#
# Every assertion below defends that biconditional from the *false-green* side, because a
# run that reports success while mirroring nothing is what causes a pin to a digest zot
# cannot serve — which sends every fresh boot down the GHCR-fallback branch and fires
# `inngest_ghcr_fallback` permanently. Precedent for the failure class:
# knowledge-base/engineering/operations/post-mortems/2026-07-29-v0244-1-published-green-with-an-unpullable-image-postmortem.md
#
# THE COUPLING THAT MOTIVATES (3). The mirror step is gated on
# `steps.zot_bridge.outcome == 'success'`. A `continue-on-error: true` bridge therefore
# SOFT-FAILS into a SKIPPED mirror and a GREEN job — the belt-off on the mirror step alone
# does not close it, because a skipped step never reaches its own degrade path. Both steps
# must drop the belt under mirror_only, or the guarantee above is false.
#
# EVERY structural assertion parses the file as YAML, never greps it. This file's own
# header names `continue-on-error`, `mirror_only` and `crane copy` at length, and the
# workflow's does the same — a bare grep matches the prose describing the property and
# passes vacuously (cq-assert-anchor-not-bare-token).
#
# The behavioral leg EXECUTES the workflow's own extracted `degraded()` — the real function
# body, not a model of it — under both MIRROR_ONLY values.
set -euo pipefail

WF=".github/workflows/build-inngest-bootstrap-image.yml"
[[ -f "$WF" ]] || { echo "FAIL - $WF not found (run from the repo root)"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

SCRATCH="$(mktemp -d -t ib-mirror.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# --- structural assertions, parsed as YAML ------------------------------------------------
# The python leg writes one TSV verdict per line; bash reports them. Same split as the
# sibling workflow suites (workspaces-luks-cutover-workflow.test.sh).
# No `> "$SCRATCH/verdicts.tsv"` redirect here: the python block opens that same path itself.
# Two writers to one path works only while nothing prints to stdout — any future print()
# lands at offset 0 and corrupts verdict line 1.
python3 - "$WF" "$SCRATCH" <<'PY'
import re, sys, yaml

wf = yaml.safe_load(open(sys.argv[1]))
scratch = sys.argv[2]
verdicts = []

def check(name, cond, detail=""):
    # Strip tabs/newlines: the bash reader splits on tabs, so an embedded one in a YAML
    # value would desync the loop and manufacture a phantom verdict.
    d = str(detail)[:200].replace("\t", " ").replace("\n", " ").replace("\r", " ")
    verdicts.append(("ok" if cond else "FAIL", name.replace("\t", " "), d))

# PyYAML parses the bare `on:` key as the boolean True (YAML 1.1). Accept either.
on = wf.get("on", wf.get(True)) or {}
inputs = ((on.get("workflow_dispatch") or {}).get("inputs")) or {}

mo = inputs.get("mirror_only")
check("workflow_dispatch declares a mirror_only input", isinstance(mo, dict), sorted(inputs))
if isinstance(mo, dict):
    # Typed boolean, not string: a string input makes every falsy caller value ("false",
    # "") a TRUTHY GHA expression, which would silently skip the build on the release path.
    check("mirror_only is type boolean", mo.get("type") == "boolean", mo.get("type"))
    check("mirror_only defaults to false", mo.get("default") is False, repr(mo.get("default")))
    check("mirror_only is not required (release path omits it)",
          mo.get("required") in (False, None), repr(mo.get("required")))

steps = ((wf.get("jobs") or {}).get("build") or {}).get("steps") or []
by_id = {s.get("id"): s for s in steps if s.get("id")}


def code_of(body):
    """Shell body with whole-line and trailing comments removed.

    LOAD-BEARING, not tidiness. Every `X in body` assertion below is a substring grep over
    text that carries its OWN rationale comments, and this workflow's comments name every
    construct being asserted at length. Measured on the #7203 tree: reverting the entire
    change -- `crane copy` back to `docker tag` + `docker push` in brace form -- passed all
    25 assertions, because `check("mirror uses crane copy", "crane copy" in body)` was
    satisfied by the comment the same commit added inside the step. Stripping the comment
    and re-running the identical mutant turned it RED, proving the comment was the sole
    anchor. cq-assert-anchor-not-bare-token; the file header used to claim immunity from
    this while having it.

    Not a full lexer: `#` inside a double-quoted string would be over-stripped. No such
    string exists in this body, and the failure direction is safe -- over-stripping can only
    make an assertion FAIL, never pass vacuously.
    """
    out = []
    for line in body.splitlines():
        stripped = re.sub(r'(?<!\S)#.*$', '', line)
        out.append(stripped)
    return "\n".join(out)


# EXACT-STRING equality throughout. The risk on every one of these is OPERAND INVERSION
# (`inputs.mirror_only` where `!inputs.mirror_only` belongs), and an inversion is invisible
# to a substring check while flipping the meaning completely.
GUARD = "${{ !inputs.mirror_only }}"

# ALL matches, not `next(...)`. A first-match lookup asserts about a representative rather
# than about the set: adding a SECOND, unguarded "Build + verify + push (retry shim)" step
# left the old suite fully green while a rebuild under mirror_only moved the tag's GHCR
# digest -- the one thing a digest backfill must not do.
builds = [s for s in steps if str(s.get("name", "")).startswith("Build + verify + push")]
check("at least one build step exists", len(builds) >= 1, f"found {len(builds)}")
check("EVERY build+push step is skipped under mirror_only (exact !inputs.mirror_only)",
      all(s.get("if") == GUARD for s in builds),
      repr([s.get("if") for s in builds]))

# The `pin` step feeds ONLY the build step's env, and its greps have no `|| true` under
# `set -euo pipefail` -- ungated it can red a backfill of an old tag whose infra/ layout
# differs, a fault with no relationship to the mirror.
pin = by_id.get("pin")
check("the pin-reading step is gated to match the build step it feeds",
      pin is not None and pin.get("if") == GUARD,
      repr(pin.get("if")) if pin else "no step with id: pin")

# NEGATIVE assertion, and the reason it exists: `mirror_only` skips the build, which makes
# the GHCR login look vestigial to a future reader -- while it is in fact crane's SOLE
# source of GHCR READ credential. #7203 established the precedent of gating build-path
# steps on !inputs.mirror_only; applying that one step up silently breaks `crane copy`.
login = next((s for s in steps if "login" in str(s.get("name", "")).lower()
              and "ghcr" in str(s.get("name", "")).lower()), None)
check("the GHCR login step exists", login is not None)
if login:
    check("GHCR login is NOT gated off under mirror_only (crane's source credential)",
          login.get("if") is None, repr(login.get("if")))

bridge = by_id.get("zot_bridge")
check("zot_bridge step exists", bridge is not None)
if bridge:
    # The belt is UNCONDITIONAL now. What makes a bridge failure red a mirror_only run is
    # the internal BRIDGE_OUTCOME branch below, not this marker -- so that a bridge failure
    # reaches the emitter on BOTH paths instead of skipping the step (#6416).
    check("zot_bridge keeps continue-on-error: true unconditionally",
          bridge.get("continue-on-error") is True, repr(bridge.get("continue-on-error")))

mirror = by_id.get("zot_mirror")
check("zot_mirror step exists", mirror is not None)
if mirror:
    check("zot_mirror drops continue-on-error under mirror_only (exact !inputs.mirror_only)",
          mirror.get("continue-on-error") == GUARD, repr(mirror.get("continue-on-error")))
    # THE #6416 INVARIANT, stated as a NEGATIVE. A gate on the bridge's outcome SKIPS this
    # step, and a skipped step emits no `mirror_status` -- so every degrade signal the
    # workflow owns becomes unreachable in the one case worth reporting. The previous
    # revision asserted the OPPOSITE (that the gate was present), which would have turned
    # this suite red the moment anyone ported the known-good sibling fix.
    check("zot_mirror is NOT gated on the bridge outcome (a skipped step cannot emit)",
          mirror.get("if") is None, repr(mirror.get("if")))

    env = mirror.get("env") or {}
    check("MIRROR_ONLY reaches the script via env:, not interpolation",
          env.get("MIRROR_ONLY") == "${{ inputs.mirror_only }}", repr(env.get("MIRROR_ONLY")))
    # OUTCOME, never CONCLUSION: continue-on-error forces conclusion to 'success' while
    # outcome keeps the true result. Reading conclusion masks every bridge failure.
    check("the bridge result reaches the script as OUTCOME, not conclusion",
          env.get("BRIDGE_OUTCOME") == "${{ steps.zot_bridge.outcome }}",
          repr(env.get("BRIDGE_OUTCOME")))

    body = mirror.get("run") or ""
    code = code_of(body)
    open(f"{scratch}/mirror-body.sh", "w").write(body)

    # (1) crane copy replaces docker tag+push. Registry->registry preserves the manifest
    # bytes, so ONE @sha256 resolves on both registries; `docker tag`+`push` re-creates the
    # manifest and was the original defect. Asserted against `code`, so the step's own
    # rationale comments cannot satisfy it.
    check("mirror uses `crane copy` for the GHCR->zot hop", "crane copy" in code)
    # Brace-form-tolerant: `docker push "${ZOT}:${TAG}"` walked past the old dollar-only
    # patterns, which is how a full revert of this change passed the suite.
    check("no `docker push` to the zot ref survives",
          not re.search(r'docker\s+push\s+"?\$\{?ZOT', code))
    check("no `docker tag` onto the zot ref survives",
          not re.search(r'docker\s+tag\s+.*\$\{?ZOT', code))

    # ORDERED, not merely present. The name says "before extraction"; substring membership
    # cannot support that verb, and swapping the two lines so an unverified tarball is
    # extracted as root passed the old check.
    if "sha256sum -c -" in code and "tar -xzf" in code:
        check("crane tarball is SHA-verified BEFORE extraction (ordered)",
              code.index("sha256sum -c -") < code.index("tar -xzf"))
    else:
        check("crane tarball is SHA-verified BEFORE extraction (ordered)", False,
              "one of sha256sum/tar is missing entirely")

    # The bridge branch must exist AND must route to degraded(), not merely mention the var.
    check("a bridge-down branch routes to degraded()",
          re.search(r'BRIDGE_OUTCOME.*\n(?:.*\n)?\s*degraded\s+bridge_down', code) is not None,
          "expected a BRIDGE_OUTCOME test whose body calls `degraded bridge_down`")

    # CONSEQUENCE, not presence. Deleting `degraded 1` from the mismatch branch left the old
    # suite 25/25 green while execution fell through to `mirror_status=ok` -- parity became
    # advisory, which is the exact false-green this file exists to prevent.
    check("an unmeasurable parity read routes to degraded()",
          re.search(r'-z "\$SRC_DIGEST".*\n(?:.*\n)*?\s*degraded\s+parity_unmeasured', code) is not None)
    check("a parity MISMATCH routes to degraded()",
          re.search(r'"\$SRC_DIGEST" != "\$DST_DIGEST".*\n(?:.*\n)*?\s*degraded\s+parity_mismatch', code) is not None)
    # A matching manifest digest does not prove the blobs are still present: zot runs gc +
    # dedupe and `crane copy` skips blobs the destination already HEADs as present.
    #
    # Anchored at CALL POSITION, not as a bare substring. Comment-stripping is not enough
    # here: degraded()'s own message string names this construct ("manifest digest matches
    # but crane validate --remote failed"), and a message is not a comment, so `code` still
    # contains the token after the call is deleted. Measured — the bare-substring form
    # survived a mutation that replaced the invocation with `true`. cq-assert-anchor-not-bare-token
    # applies to STRING LITERALS too, not just comments.
    check("blob presence is validated at call position, not inferred from the digest",
          re.search(r'^\s*retry\s+crane\s+validate\s+--remote\s+"\$ZOT', code, re.M) is not None,
          "expected a `retry crane validate --remote \"$ZOT...` invocation at line start")

    # Ordering: a `mirror_status=ok` written before the comparison certifies regardless of
    # the verdict. Unconditional now -- the old `if ... in body` form silently emitted NO
    # verdict when either token vanished, so deleting the token dropped an assertion instead
    # of failing one.
    have_ok = "mirror_status=ok" in code
    have_guard = '-z "$SRC_DIGEST"' in code
    check("mirror_status=ok is written AFTER the parity check, not before",
          have_ok and have_guard and code.index('-z "$SRC_DIGEST"') < code.index("mirror_status=ok"),
          f"ok={have_ok} guard={have_guard}")

    # (4) degraded() must exit 1 under mirror_only. Asserted structurally here and
    # EXECUTED in the behavioral leg below.
    check("degraded() has a mirror_only arm", 'MIRROR_ONLY:-false' in code)
    # The ERR trap is the backstop for the deliberate absence of `set -e`: without it a
    # future fallible command with no `|| degraded` route falls through to mirror_status=ok.
    # Anchored on `trap` at COMMAND position (line start), for the same reason as the
    # validate check above: a bare `trap ... ERR` substring is satisfied by any line that
    # merely mentions the construct.
    check("an ERR trap routes unrouted failures to degraded()",
          re.search(r"^\s*trap\s+'degraded\s+unrouted.*'\s+ERR\s*$", code, re.M) is not None,
          "expected a `trap 'degraded unrouted ...' ERR` at command position")

# The Slack degrade step must carry a STATUS FUNCTION. Without one GitHub prepends an
# implicit success(), so the step is skipped on exactly the mirror_only degrades it exists
# to report -- the mode that authorises a root-exec digest pin had no push signal at all.
slack = next((s for s in steps if "slack" in str(s.get("name", "")).lower()), None)
check("the Slack degrade step exists", slack is not None)
if slack:
    slack_if = str(slack.get("if") or "")
    check("the Slack gate carries a status function (else implicit success() skips it)",
          any(fn in slack_if for fn in ("!cancelled()", "always()", "failure()")),
          repr(slack_if))

with open(f"{scratch}/verdicts.tsv", "w") as fh:
    for status, name, detail in verdicts:
        fh.write(f"{status}\t{name}\t{detail}\n")
PY

while IFS=$'\t' read -r status name detail; do
  [[ -n "${status:-}" ]] || continue
  if [[ "$status" == "ok" ]]; then ok "$name"; else no "$name${detail:+ — got $detail}"; fi
done < "$SCRATCH/verdicts.tsv"

# --- behavioral leg: run the workflow's OWN degraded(), both modes -------------------------
# Structural assertion (4) proves the arm is present; only execution proves it EXITS. The
# whole point of the arm is the exit code, and a `return 1` or a misplaced `fi` would keep
# every structural check green while handing back a green run.
BODY="$SCRATCH/mirror-body.sh"
if [[ ! -s "$BODY" ]]; then
  no "mirror step run body could not be extracted (behavioral leg skipped)"
else
  bash -n "$BODY" && ok "extracted mirror body parses as bash" || no "extracted mirror body is not valid bash"

  # Extract just the degraded() definition, by brace matching on the closing line at the
  # function's own indentation. Running the full body would need a live registry.
  python3 - "$BODY" "$SCRATCH/degraded.sh" <<'PY'
import sys, re
lines = open(sys.argv[1]).read().splitlines()
start = next(i for i, l in enumerate(lines) if re.match(r"^(\s*)degraded\(\)\s*\{", l))
indent = re.match(r"^(\s*)", lines[start]).group(1)
end = next(i for i in range(start + 1, len(lines)) if lines[i] == f"{indent}}}")
open(sys.argv[2], "w").write("\n".join(lines[start:end + 1]) + "\n")
PY

  run_degraded() {
    # $1 = the MIRROR_ONLY value under test. Slot name, not the value, so the empty-string
    # case gets its own files.
    local slot="${2:-$1}"
    # Subshell so `exit` inside degraded() ends only this invocation. GITHUB_* point at
    # scratch files because the real function appends to both.
    (
      set -uo pipefail
      GITHUB_OUTPUT="$SCRATCH/out.$slot"; GITHUB_STEP_SUMMARY="$SCRATCH/sum.$slot"
      export GITHUB_OUTPUT GITHUB_STEP_SUMMARY
      : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"
      MIRROR_ONLY="$1" TAG="vinngest-v0.0.0-test" ZOT="127.0.0.1:5000/test/image"
      IMAGE="ghcr.io/jikig-ai/soleur-inngest-bootstrap"
      export MIRROR_ONLY TAG ZOT IMAGE
      # shellcheck source=/dev/null
      source "$SCRATCH/degraded.sh"
      degraded test_reason 7
      # SENTINEL. Reached only if degraded() RETURNED instead of EXITING. Without this the
      # two are indistinguishable here — `degraded` is the subshell's last command, so
      # `return 1` and `exit 1` both make the subshell exit 1. In the real step body
      # degraded() is called at top level with no `set -e`, so a `return` lets execution
      # fall through to `mirror_status=ok`: a green run with no mirror. The file header
      # claims this leg catches exactly that mutant; before the sentinel it did not.
      echo "SENTINEL_REACHED_degraded_returned_instead_of_exiting"
    ) >"$SCRATCH/log.$slot" 2>&1
  }

  # BUILD path: the mirror is secondary to the GHCR release, so a degrade must NOT red it.
  if run_degraded false; then
    ok "degraded() exits 0 on the build path (mirror is secondary; release stands)"
  else
    no "degraded() exited non-zero with MIRROR_ONLY=false — this would red every release on a transient mirror fault"
  fi
  grep -q "mirror_status=degraded" "$SCRATCH/out.false" \
    && ok "degraded() records mirror_status=degraded on the build path" \
    || no "degraded() did not write mirror_status=degraded (the Slack degrade step keys on it)"

  # mirror_only: the mirror IS the run. A zero exit here is the false-green this file exists
  # to prevent — it would certify a backfill that did not happen and license a bad pin.
  if run_degraded true; then
    no "degraded() exited 0 with MIRROR_ONLY=true — a failed backfill would report SUCCESS and license a pin to a digest zot cannot serve"
  else
    ok "degraded() exits non-zero under mirror_only (a failed backfill reds the run)"
  fi
  grep -q "::error::" "$SCRATCH/log.true" \
    && ok "degraded() emits an ::error:: annotation under mirror_only" \
    || no "degraded() emitted no ::error:: under mirror_only"

  # PUSH path. On `push: tags` the inputs context is empty, so `${{ inputs.mirror_only }}`
  # renders the EMPTY STRING — not "false". "false" is only ever produced by an explicit
  # dispatch with the box unchecked, so both prior fixtures tested a value the release path
  # never sees. This pins the `:-` colon form: rewriting it to `${MIRROR_ONLY-false}` (bare,
  # substitutes on unset only) would make the empty string fall through to the mirror_only
  # arm and RED every tag-push release on a transient mirror fault.
  if run_degraded "" empty; then
    ok "degraded() exits 0 when MIRROR_ONLY is the empty string (the real push-path value)"
  else
    no "degraded() exited non-zero with MIRROR_ONLY='' — this reds every tag-push release on a transient mirror fault"
  fi

  # The sentinel must never print on ANY path — see run_degraded().
  if grep -rqs "SENTINEL_REACHED" "$SCRATCH"/log.*; then
    no "degraded() RETURNED instead of exiting — execution would fall through to mirror_status=ok (green run, no mirror)"
  else
    ok "degraded() exits rather than returns on every path (no fall-through to mirror_status=ok)"
  fi

  # Named cause, not just a status. A single 'degraded' bucket cannot tell a supply-chain
  # checksum mismatch from a transient TCP reset, and mirror_reason is what the Slack
  # message and any future consumer read.
  grep -q "mirror_reason=test_reason" "$SCRATCH/out.false" \
    && ok "degraded() records the named reason as mirror_reason" \
    || no "degraded() did not write mirror_reason (the Slack message and step summary key on it)"
fi

# --- cross-workflow crane pin parity -------------------------------------------------------
# The mirror step's own comment says "keep the three in step". That was unenforced prose; a
# drifted pin in one workflow is exactly the sort of thing a comment cannot catch.
CRANE_SHA_EXPECTED="c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b"
for wf in .github/workflows/build-inngest-bootstrap-image.yml \
          .github/workflows/build-inngest-config-bundle.yml \
          .github/workflows/reusable-release.yml; do
  if [[ ! -f "$wf" ]]; then
    no "crane pin parity: $wf not found"
  elif grep -qF "$CRANE_SHA_EXPECTED" "$wf"; then
    ok "crane SHA256 pin matches across workflows — $(basename "$wf")"
  else
    no "crane SHA256 pin DRIFTED in $wf (expected $CRANE_SHA_EXPECTED)"
  fi
done

echo ""
echo "passed: $pass  failed: $fail"

# ANTI-VACUITY FLOOR. Without it the ONLY merge gate is `fail == 0`, and a suite that ran
# ZERO assertions satisfies that trivially: neutering the verdict emitter printed
# `passed: 0  failed: 0` and exited 0, i.e. CI green over a suite asserting nothing. A green
# run must carry evidence that the assertions actually executed.
#
# A FLOOR (-lt), never equality: one assertion is legitimately conditional, so the count has
# real variance and pinning it exactly would flake on every addition. Derived from a green
# run, not from the number expected. The sibling this file is modelled on
# (workspaces-luks-cutover-workflow.test.sh) carries the same shape.
MIN_ASSERTIONS=30
if (( pass + fail < MIN_ASSERTIONS )); then
  echo "FAIL - only $((pass + fail)) assertions ran (floor $MIN_ASSERTIONS) — a green run here would be vacuous"
  exit 1
fi

(( fail == 0 )) || exit 1
