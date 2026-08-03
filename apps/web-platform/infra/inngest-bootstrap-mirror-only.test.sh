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
python3 - "$WF" "$SCRATCH" > "$SCRATCH/verdicts.tsv" <<'PY'
import sys, yaml

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
named = {str(s.get("name", "")): s for s in steps}

# EXACT-STRING equality throughout. The risk on every one of these is OPERAND INVERSION
# (`inputs.mirror_only` where `!inputs.mirror_only` belongs), and an inversion is invisible
# to a substring check while flipping the meaning completely.
GUARD = "${{ !inputs.mirror_only }}"

build = next((s for s in steps if str(s.get("name", "")).startswith("Build + verify + push")), None)
check("build step exists", build is not None)
if build:
    # (2) The rebuild must not run under mirror_only: `docker build` + push of the SAME tag
    # MOVES the tag's GHCR digest, which is the one thing a digest backfill must not do.
    check("build step is skipped under mirror_only (exact !inputs.mirror_only)",
          build.get("if") == GUARD, repr(build.get("if")))

bridge = by_id.get("zot_bridge")
check("zot_bridge step exists", bridge is not None)
if bridge:
    # (3) THE COUPLING. See the header. A hardcoded `true` here re-opens the false-green.
    check("zot_bridge drops continue-on-error under mirror_only (exact !inputs.mirror_only)",
          bridge.get("continue-on-error") == GUARD, repr(bridge.get("continue-on-error")))

mirror = by_id.get("zot_mirror")
check("zot_mirror step exists", mirror is not None)
if mirror:
    check("zot_mirror drops continue-on-error under mirror_only (exact !inputs.mirror_only)",
          mirror.get("continue-on-error") == GUARD, repr(mirror.get("continue-on-error")))
    # Asserted so the coupling that makes (3) load-bearing cannot be silently removed:
    # if this gate ever goes away, the bridge belt stops mattering and this suite would
    # otherwise keep passing while guarding a property that no longer exists.
    check("zot_mirror is gated on zot_bridge succeeding (the coupling behind the belt-off)",
          mirror.get("if") == "steps.zot_bridge.outcome == 'success'", repr(mirror.get("if")))

    env = mirror.get("env") or {}
    check("MIRROR_ONLY reaches the script via env:, not interpolation",
          env.get("MIRROR_ONLY") == "${{ inputs.mirror_only }}", repr(env.get("MIRROR_ONLY")))

    body = mirror.get("run") or ""
    open(f"{scratch}/mirror-body.sh", "w").write(body)

    # (1) crane copy replaces docker tag+push. Registry->registry preserves the manifest
    # bytes, so ONE @sha256 resolves on both registries; `docker tag`+`push` re-creates the
    # manifest and was the original defect.
    check("mirror uses `crane copy` for the GHCR->zot hop", "crane copy" in body)
    check("no `docker push` to the zot ref survives", 'docker push "$ZOT' not in body)
    check("no `docker tag` to the zot ref survives", 'docker tag "$IMAGE:$TAG" "$ZOT' not in body)
    check("crane tarball is SHA-pinned before extraction", "sha256sum -c -" in body)

    # (2 of the parity assertion) An EMPTY source digest must count as failure. `|| true` on
    # the capture means an auth/network fault yields "", and "" == "" would otherwise read
    # as a match and certify nothing.
    check("parity check treats an EMPTY source digest as failure",
          '-z "$SRC_DIGEST"' in body, "expected a -z guard on SRC_DIGEST")
    check("parity check compares the two digests",
          '"$SRC_DIGEST" != "$DST_DIGEST"' in body)
    # Ordering matters: a `mirror_status=ok` written before the comparison would certify
    # the run regardless of the verdict.
    if "mirror_status=ok" in body and '-z "$SRC_DIGEST"' in body:
        check("mirror_status=ok is written AFTER the parity check, not before",
              body.index('-z "$SRC_DIGEST"') < body.index("mirror_status=ok"))

    # (4) degraded() must exit 1 under mirror_only. Asserted structurally here and
    # EXECUTED in the behavioral leg below.
    check("degraded() has a mirror_only arm", 'MIRROR_ONLY:-false' in body)

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
    # Subshell so `exit` inside degraded() ends only this invocation. GITHUB_* point at
    # scratch files because the real function appends to both.
    (
      set -uo pipefail
      GITHUB_OUTPUT="$SCRATCH/out.$1"; GITHUB_STEP_SUMMARY="$SCRATCH/sum.$1"
      export GITHUB_OUTPUT GITHUB_STEP_SUMMARY
      : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"
      MIRROR_ONLY="$1" TAG="vinngest-v0.0.0-test" ZOT="127.0.0.1:5000/test/image"
      export MIRROR_ONLY TAG ZOT
      # shellcheck source=/dev/null
      source "$SCRATCH/degraded.sh"
      degraded 7
    ) >"$SCRATCH/log.$1" 2>&1
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
fi

echo ""
echo "passed: $pass  failed: $fail"
(( fail == 0 )) || exit 1
