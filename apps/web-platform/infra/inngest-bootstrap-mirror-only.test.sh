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
# WHY THE MIRROR IS NOT GATED ON THE BRIDGE. An earlier revision of this file gated the
# mirror on `steps.zot_bridge.outcome == 'success'` and asserted that gate as REQUIRED.
# That is the #6416 defect: a `continue-on-error: true` bridge SOFT-FAILS into a SKIPPED
# mirror, and a skipped step never reaches its own degrade path — so `mirror_status` stays
# unset and every signal this workflow owns (::warning::, step summary, Slack) is
# unreachable in the one case worth reporting. The bridge is also the step the measured
# fault class actually kills (#7242).
#
# So the invariant is the INVERSE of what this header used to prescribe: `zot_bridge` keeps
# `continue-on-error: true` UNCONDITIONALLY, `zot_mirror` carries NO `if:`, and the bridge
# result reaches the script as the BRIDGE_OUTCOME env var to be branched on internally.
# The belt-off under mirror_only lives on the MIRROR step alone, and what makes a bridge
# failure red a mirror_only run is `degraded bridge_down` exiting 1 — not the scheduler.
#
# Structural assertions parse the file as YAML rather than grepping the raw text, and every
# assertion over a step's `run:` BODY runs against `code_of(body)` — comments stripped.
# Both matter: this file's own header names `continue-on-error`, `mirror_only` and
# `crane copy` at length, and the workflow's does the same, so a bare grep matches the prose
# DESCRIBING the property and passes vacuously (cq-assert-anchor-not-bare-token). That is
# not hypothetical — it is measured: before comment-stripping, reverting the entire change
# passed all 25 assertions. Note that `code_of` strips comments but NOT string literals, so
# an assertion can still be satisfied by a `degraded()` message naming the construct;
# anchor those at call position (see the crane-validate and ERR-trap checks).
#
# The cross-workflow crane-pin leg at the end greps three files directly rather than parsing
# them — it compares a pinned literal, not a property of this workflow's structure. It anchors
# on the ASSIGNMENT (`^\s*CRANE_SHA256="<sha>"`), because a bare whole-file match is satisfied
# by a comment recording the OLD pin above a drifted one.
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

jobs = wf.get("jobs") or {}
steps = ((jobs.get("build")) or {}).get("steps") or []
by_id = {s.get("id"): s for s in steps if s.get("id")}

# --- JOB-LEVEL SURFACE. Every step-level belt below is defeatable one indent level up, and
# that surface was completely unparsed: a job-level `if: !inputs.mirror_only` skips the WHOLE
# job under mirror_only (workflow reports SUCCESS, nothing mirrored, no mirror_status, no
# Slack), and a job-level `continue-on-error: true` reports the workflow green while the
# mirror step fails. Both are one-line edits and both passed the previous revision 42/0.
check("the workflow has exactly the `build` job (a second job is an unparsed surface)",
      sorted(jobs) == ["build"], repr(sorted(jobs)))
_bj = jobs.get("build") or {}
check("jobs.build carries no job-level if: (it would skip the whole mirror)",
      "if" not in _bj, repr(_bj.get("if")))
check("jobs.build carries no job-level continue-on-error: (it would mask a red mirror)",
      "continue-on-error" not in _bj, repr(_bj.get("continue-on-error")))
check("jobs.build carries no matrix strategy (it would race duplicate mirrors of one tag)",
      "strategy" not in _bj, repr(_bj.get("strategy")))


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

    Quote-aware, and it has to be. The naive `re.sub(r'(?<!\S)#.*$', '')` over-strips at a
    `#` inside a string -- and such a string EXISTS in this body today (the step-summary line
    ending `See the #7203 review findings.`). That is not a cosmetic truncation:

      * three assertions below are NEGATIVE (`no docker push`, `no docker tag`, the
        dark-launch non-blocking check). Over-stripping DELETES the text they search for, so
        they pass vacuously -- the failure direction is NOT safe, contrary to what this
        docstring used to claim.
      * measured: reverting to `docker tag`/`docker push` while ending the line with a
        `(see #7203)` comment-shaped suffix passed the whole suite; the identical edit
        spelled `(see issue 7203)` was killed. The `#` was doing all of the evasion.

    So track quote state and only treat an UNQUOTED `#` at a word boundary as a comment.
    Backslash escapes are honoured. Heredocs are not modelled -- this body has none, and a
    future one would over-strip (loud FAIL on positives) rather than under-strip.
    """
    out = []
    for line in body.splitlines():
        res, quote, i, esc = [], None, 0, False
        while i < len(line):
            ch = line[i]
            if esc:
                res.append(ch); esc = False; i += 1; continue
            if ch == "\\" and quote != "'":
                res.append(ch); esc = True; i += 1; continue
            if quote:
                if ch == quote:
                    quote = None
                res.append(ch); i += 1; continue
            if ch in ("'", '"'):
                quote = ch; res.append(ch); i += 1; continue
            if ch == "#" and (i == 0 or line[i - 1].isspace()):
                break
            res.append(ch); i += 1
        out.append("".join(res))
    return "\n".join(out)


# EXACT-STRING equality throughout. The risk on every one of these is OPERAND INVERSION
# (`inputs.mirror_only` where `!inputs.mirror_only` belongs), and an inversion is invisible
# to a substring check while flipping the meaning completely.
GUARD = "${{ !inputs.mirror_only }}"


def _branch_calls(code, cond_line, call):
    """True iff `call` appears in cond_line's branch body at exactly one extra indent level.

    Bounding the nesting is the point. An unbounded `(?:.*\\n)*?` between the condition and
    the call matches at ANY depth, so wrapping the call in a second `if` — which is how a
    degrade gets silently restricted to one path — satisfies it. Requiring the call at
    cond_indent + 2 means it runs whenever the branch is taken.
    """
    lines = code.splitlines()
    try:
        start = lines.index(cond_line)
    except ValueError:
        return False
    indent = len(cond_line) - len(cond_line.lstrip())
    want = " " * (indent + 2) + call
    for line in lines[start + 1:]:
        if line.strip() == "fi" and (len(line) - len(line.lstrip())) == indent:
            return False
        if line.startswith(want):
            return True
    return False

# Matched by WHAT THE STEP DOES, not by what it is called. A name-prefix filter
# (`startswith("Build + verify + push")`) is scoped to a label an author controls: a step
# named "Rebuild + push (retry shim)" running the identical `docker build`/`docker push` was
# invisible to it, so the assertion literally named "EVERY build+push step" was quantifying
# over one name, not over the set of steps that can move the tag's GHCR digest.
def _rebuilds_tag(s):
    # UNION of content and name, deliberately. Content alone misses nothing dangerous, but
    # name alone caught a case content does not: a step CALLED "Build + verify + push ..."
    # whose body does not (yet) build. That one is benign today and one edit from not being,
    # so keep both arms — a step claiming to be the build step must carry the guard whether
    # or not it currently earns the name.
    body = str(s.get("run") or "")
    uses = str(s.get("uses") or "")
    return bool(
        re.search(r'^\s*docker\s+(build|buildx\s+build)\b', body, re.M)
        or re.search(r'^\s*docker\s+push\b', body, re.M)
        or re.search(r'docker/build-push-action', uses)
        or str(s.get("name", "")).startswith("Build + verify + push")
    )


builds = [s for s in steps if _rebuilds_tag(s)]
check("at least one build/push step exists (else the filter is broken, not the workflow)",
      len(builds) >= 1, f"found {len(builds)}")
# `all([])` is vacuously True, which is why the non-empty check above is load-bearing.
check("EVERY step that can rebuild/push the tag is skipped under mirror_only",
      all(s.get("if") == GUARD for s in builds),
      repr([(s.get("name"), s.get("if")) for s in builds]))

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
    # CALL POSITION, not membership. `"crane copy" in code` is satisfied by degraded()'s own
    # advisory message string ("...backfill via ... crane, digest-preserving..."), which
    # code_of does NOT strip -- strings are not comments. Measured: a full revert kept the
    # token alive from that string and passed.
    check("mirror invokes `crane copy` at call position",
          re.search(r'^\s*retry\s+crane\s+copy\s+"\$IMAGE:\$TAG"\s+"\$ZOT:\$TAG"', code, re.M) is not None,
          "expected `retry crane copy \"$IMAGE:$TAG\" \"$ZOT:$TAG\"` at line start")
    # Brace-form-tolerant AND command-position-anchored: `docker push "${ZOT}:${TAG}"` walked
    # past the old dollar-only patterns, which is how a full revert of this change passed.
    check("no `docker push` to the zot ref survives",
          not re.search(r'(^|;|&&|\|\|)\s*docker\s+push\s+"?\$\{?ZOT', code, re.M))
    check("no `docker tag` onto the zot ref survives",
          not re.search(r'(^|;|&&|\|\|)\s*docker\s+tag\s+[^\n]*\$\{?ZOT', code, re.M))

    # ORDERED, not merely present. The name says "before extraction"; substring membership
    # cannot support that verb, and swapping the two lines so an unverified tarball is
    # extracted as root passed the old check.
    if "sha256sum -c -" in code and "tar -xzf" in code:
        check("crane tarball is SHA-verified BEFORE extraction (ordered)",
              code.index("sha256sum -c -") < code.index("tar -xzf"))
    else:
        check("crane tarball is SHA-verified BEFORE extraction (ordered)", False,
              "one of sha256sum/tar is missing entirely")

    # POLARITY + NESTING, not token adjacency. The previous form
    # (`BRIDGE_OUTCOME.*\n(?:.*\n)?\s*degraded bridge_down`) proved only that the two tokens
    # were near each other: inverting the operator to `= "success"` — a complete inversion of
    # the #6416/#7242 guard — passed, and so did `= "failure"`, which fails OPEN on
    # `skipped`/`cancelled`. Pin the exact condition, then require the call in its body.
    BRIDGE_COND = 'if [ "${BRIDGE_OUTCOME:-}" != "success" ]; then'
    check("the bridge branch tests the exact NOT-success condition (polarity pinned)",
          BRIDGE_COND in code,
          "expected the literal `if [ \"${BRIDGE_OUTCOME:-}\" != \"success\" ]; then`")
    check("the bridge branch body calls degraded bridge_down",
          _branch_calls(code, BRIDGE_COND, "degraded bridge_down"),
          "expected `degraded bridge_down` inside that branch, at its own indent")

    # CONSEQUENCE, not presence, and BOUNDED. Deleting `degraded 1` from the mismatch branch
    # left an earlier revision 25/25 green while execution fell through to `mirror_status=ok`.
    # The unbounded `(?:.*\n)*?` that replaced it was no better: it matched the call at ANY
    # nesting depth, so wrapping it in `if [ "$MIRROR_ONLY" = true ]` — which restores the
    # false-green on the BUILD path, the one that runs on every release — still passed.
    UNMEAS_COND = 'if [ -z "$SRC_DIGEST" ] || [ -z "$DST_DIGEST" ]; then'
    MISMATCH_COND = 'if [ "$SRC_DIGEST" != "$DST_DIGEST" ]; then'
    check("the unmeasurable-parity branch tests the exact condition",
          UNMEAS_COND in code, "expected the literal -z SRC/-z DST condition")
    check("the unmeasurable-parity branch calls degraded parity_unmeasured UNCONDITIONALLY",
          _branch_calls(code, UNMEAS_COND, "degraded parity_unmeasured"))
    check("the parity-mismatch branch tests the exact condition",
          MISMATCH_COND in code, "expected the literal SRC != DST condition")
    check("the parity-mismatch branch calls degraded parity_mismatch UNCONDITIONALLY",
          _branch_calls(code, MISMATCH_COND, "degraded parity_mismatch"))
    # A matching manifest digest does not prove the blobs are still present: zot runs gc +
    # dedupe and `crane copy` skips blobs the destination already HEADs as present.
    #
    # Anchored at CALL POSITION, not as a bare substring. Comment-stripping is not enough
    # here: degraded()'s own message string names this construct ("manifest digest matches
    # but crane validate --remote failed"), and a message is not a comment, so `code` still
    # contains the token after the call is deleted. Measured — the bare-substring form
    # survived a mutation that replaced the invocation with `true`. cq-assert-anchor-not-bare-token
    # applies to STRING LITERALS too, not just comments.
    # `timeout \d+` between retry and crane is REQUIRED, not merely tolerated: "non-blocking"
    # holds for exit codes but not wall clock, and the job declares no timeout-minutes, so an
    # unbounded stall against the tunnelled listener would burn the 360-minute default and RED
    # a release from a check documented as unable to affect the outcome.
    check("blob presence is validated at call position, under a wall-clock bound",
          re.search(r'^\s*retry\s+timeout\s+\d+\s+crane\s+validate\s+--remote\s+"\$ZOT', code, re.M) is not None,
          "expected `retry timeout <n> crane validate --remote \"$ZOT...` at line start")
    # DARK-LAUNCH POSTURE (wg-dark-launch-deploy-gates). The blob check is runtime-unvalidated
    # against this registry, so it must NOT gate until observed passing on a real run. Pinned
    # in both directions: it must record a verdict (so the promotion criterion is measurable)
    # and it must NOT route to degraded() (so a heuristic mismatch cannot red every release).
    check("blob validation records a verdict for the promotion criterion",
          re.search(r'^\s*echo "blob_validate=ok" >> "\$GITHUB_OUTPUT"', code, re.M) is not None)
    # MULTI-LINE AWARE. `[^\n]*` cannot cross a line continuation, so promoting the gate
    # exactly as this workflow's own PROMOTION CRITERION spells it — `retry ... \` newline
    # `  || degraded blobs_missing ...` — slipped straight past. That is the single most
    # likely edit anyone will ever make to this file, so it is the one the check must catch.
    # Join continuations before searching.
    _joined = re.sub(r'\\\n\s*', ' ', code)
    check("blob validation is NON-BLOCKING while dark-launched (does not reach degraded)",
          re.search(r'crane\s+validate\s+--remote.*?\|\|\s*degraded', _joined) is None,
          "a dark-launched gate must not route to degraded() until promoted (line continuations joined)")

    # Ordering: a `mirror_status=ok` written before the comparison certifies regardless of
    # the verdict. Unconditional now -- the old `if ... in body` form silently emitted NO
    # verdict when either token vanished, so deleting the token dropped an assertion instead
    # of failing one.
    # `.index()` returns the FIRST occurrence, so a decoy `if [ -z "$SRC_DIGEST" ]` inserted
    # earlier relocates the index and the ordering assertion certifies the INVERTED order.
    # Require the tokens to be unique, then compare — uniqueness is the property that makes
    # the comparison mean anything.
    n_guard = code.count(UNMEAS_COND)
    n_ok = code.count('echo "mirror_status=ok"')
    check("the parity guard and the ok-write each occur exactly once (no decoys)",
          n_guard == 1 and n_ok == 1, f"guard={n_guard} ok={n_ok}")
    check("mirror_status=ok is written AFTER the parity check, not before",
          n_guard == 1 and n_ok == 1
          and code.index(UNMEAS_COND) < code.index('echo "mirror_status=ok"'))

    # (4) degraded() must exit 1 under mirror_only. Asserted structurally here and
    # EXECUTED in the behavioral leg below. EXACTLY ONE definition: bash binds the LAST
    # definition executed before the call sites, while the behavioral leg's extractor takes
    # the FIRST — so a second degraded() ending `exit 0` makes the behavioural leg test a
    # function the workflow never calls, defeating all eight of its assertions at once.
    check("degraded() is defined exactly once (a second definition shadows the tested one)",
          len(re.findall(r'^\s*degraded\(\)\s*\{', code, re.M)) == 1,
          f"found {len(re.findall(r'^[ ]*degraded\(\)', code, re.M))} definitions")
    check("degraded() has a mirror_only arm", 'MIRROR_ONLY:-false' in code)
    # The ERR trap is the backstop for the deliberate absence of `set -e`: without it a
    # future fallible command with no `|| degraded` route falls through to mirror_status=ok.
    # Anchored on `trap` at COMMAND position (line start), for the same reason as the
    # validate check above: a bare `trap ... ERR` substring is satisfied by any line that
    # merely mentions the construct.
    check("an ERR trap routes unrouted failures to degraded()",
          re.search(r"^\s*trap\s+'degraded\s+unrouted.*'\s+ERR\s*$", code, re.M) is not None,
          "expected a `trap 'degraded unrouted ...' ERR` at command position")
    # ARMED ONCE IS NOT ARMED THROUGHOUT. `trap - ERR` anywhere after it disarms the backstop
    # for the whole remaining body — including the parity and blob regions — and the
    # arming check alone cannot see that.
    check("the ERR trap is never disarmed later in the body",
          re.search(r'^\s*trap\s+-\s+ERR', code, re.M) is None,
          "found a `trap - ERR` that disarms the unrouted-failure backstop")

# The Slack degrade step must carry a STATUS FUNCTION. Without one GitHub prepends an
# implicit success(), so the step is skipped on exactly the mirror_only degrades it exists
# to report -- the mode that authorises a root-exec digest pin had no push signal at all.
slack = next((s for s in steps if "slack" in str(s.get("name", "")).lower()), None)
check("the Slack degrade step exists", slack is not None)
if slack:
    slack_if = str(slack.get("if") or "")
    # EXACT, not an allowlist. `failure()` was accepted by the old membership test and is NOT
    # equivalent: it is true only once the job has already failed, i.e. only under
    # mirror_only — which silently deletes the BUILD-path degrade ⚠️ that is the entire
    # reason (#6278) this step exists. `always()` would also fire on cancellation.
    check("the Slack gate is exactly `!cancelled() &&` guarded (not failure()/always())",
          slack_if == "${{ !cancelled() && steps.zot_mirror.outputs.mirror_status == 'degraded' }}",
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
  # Anchored on the ASSIGNMENT, not a whole-file grep. A bare `grep -qF` over raw text is
  # satisfied by a comment recording the OLD pin (`# previous pin: c1434008...`) sitting
  # above a drifted assignment — the same cq-assert-anchor-not-bare-token failure this suite
  # was rewritten to fix, in the one leg that reads raw file text instead of `code`.
  if [[ ! -f "$wf" ]]; then
    no "crane pin parity: $wf not found"
  elif grep -qE "^[[:space:]]*CRANE_SHA256=\"${CRANE_SHA_EXPECTED}\"" "$wf"; then
    ok "crane SHA256 pin matches across workflows — $(basename "$wf")"
  else
    no "crane SHA256 pin DRIFTED in $wf (expected an assignment of $CRANE_SHA_EXPECTED)"
  fi
done

echo ""
echo "passed: $pass  failed: $fail"

# ANTI-VACUITY FLOOR. Without it the ONLY merge gate is `fail == 0`, and a suite that ran
# ZERO assertions satisfies that trivially: neutering the verdict emitter printed
# `passed: 0  failed: 0` and exited 0, i.e. CI green over a suite asserting nothing. A green
# run must carry evidence that the assertions actually executed.
#
# A FLOOR (-lt), never equality: a few assertions are legitimately conditional, so the count
# has real variance and pinning it exactly would flake on every addition. Derived from a green
# run, not from the number expected. The sibling this file is modelled on
# (workspaces-luks-cutover-workflow.test.sh) carries the same shape.
#
# Set CLOSE to actual (50 vs 52), not comfortably below it. A floor 12 under actual measures
# nothing in between: deleting the whole behavioural leg, two parity-loop files and the two
# most load-bearing structural checks landed exactly on a floor of 30 and still certified the
# run. A floor catches total neutering; only a tight one catches attrition. Re-derive it when
# adding assertions — that is the intended maintenance cost.
MIN_ASSERTIONS=50
if (( pass + fail < MIN_ASSERTIONS )); then
  echo "FAIL - only $((pass + fail)) assertions ran (floor $MIN_ASSERTIONS) — a green run here would be vacuous"
  exit 1
fi

(( fail == 0 )) || exit 1
