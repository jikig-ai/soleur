#!/usr/bin/env bash
# Tests for scripts/lint-infra-no-human-steps.py.
#
# Sentinel model = human-actor + infra-imperative CO-OCCURRENCE. Enforcement
# teeth for hr-no-ssh-fallback-in-runbooks. Assert on EXIT CODES (not summary
# literals). Each case writes a throwaway .md via `mktemp` and runs the linter
# with an explicit positional path (bypasses scan-dir discovery + git), except
# the --changed fail-closed case which drives a scratch git repo.
#
# Exit contract: 0 clean, 1 violation(s)/structural error, 2 arg/git error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-infra-no-human-steps.py"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# write_case <name> writes stdin to a fresh file and echoes its path.
CASE_N=0
mkcase() {
  CASE_N=$((CASE_N + 1))
  local f="$TMPDIR_TEST/case_${CASE_N}.md"
  cat > "$f"
  printf '%s' "$f"
}

# run_case <name> <expected_exit> <file>
run_case() {
  local name="$1" expected="$2" file="$3"
  local actual=0
  python3 "$SUT" "$file" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit=$expected actual=$actual"
  fi
}

# ---------------------------------------------------------------------------
# Baseline model cases.
# ---------------------------------------------------------------------------

# T1 — a human-step line FAILS.
f="$(mkcase <<'EOF'
# Cutover runbook

The operator SSHs into web-1 and runs terraform apply during the window.
EOF
)"
run_case "human-step line FAILS" 1 "$f"

# T2 — an orchestrator-defers line PASSES (no human actor).
f="$(mkcase <<'EOF'
# Cutover runbook

The dispatch workflow runs terraform apply through the R2 concurrency serializer.
EOF
)"
run_case "orchestrator-defers line PASSES" 0 "$f"

# T3 — a paired ignore-region line PASSES.
f="$(mkcase <<'EOF'
# Cutover runbook

<!-- lint-infra-ignore start -->
The operator reboots the drained host by hand, then runs terraform apply.
<!-- lint-infra-ignore end -->
EOF
)"
run_case "paired ignore-region line PASSES" 0 "$f"

# T4 — a fenced block hides an actor+imperative; an inline command w/o actor PASSES.
f="$(mkcase <<'EOF'
# Cutover runbook

The dispatch internally invokes `terraform apply` after the R2 lock.

```bash
# operator-facing example only — the operator reboots web-1 by hand
terraform apply -target=hcloud_volume.workspaces
```
EOF
)"
run_case "fenced actor+imperative + inline command w/o actor PASSES" 0 "$f"

# T5 — a `tofu apply` by operator paraphrase FAILS.
f="$(mkcase <<'EOF'
# Cutover runbook

Then the operator applies the change by hand with tofu apply on the box.
EOF
)"
run_case "tofu-apply-by-operator paraphrase FAILS" 1 "$f"

# T6 — a bare imperative with NO actor PASSES (proves it is not a denylist).
f="$(mkcase <<'EOF'
# Notes

The placement-group reboot is deferred to the orchestrator; terraform apply is
serialized through R2.
EOF
)"
run_case "bare imperative without actor PASSES" 0 "$f"

# T7 — a human step under an exact `## Resolved` section PASSES (section carve).
f="$(mkcase <<'EOF'
# Incident

## Resolved

Historically the operator had to reboot web-1 by hand; superseded by dispatch.
EOF
)"
run_case "exact Resolved-section human step PASSES" 0 "$f"

# T8 — adjacent actor/imperative split (same block) FAILS.
f="$(mkcase <<'EOF'
# Cutover runbook

The operator, once the window opens, must then
reboot the sole live origin and restore weight.
EOF
)"
run_case "adjacent actor/imperative split FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 1 — verb inflection (trailing \b matched only the bare lemma).
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

The operator reboots web-1 by hand.
EOF
)"
run_case "D1 inflected imperative 'reboots' FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

The operator is rebooting web-1 during the window.
EOF
)"
run_case "D1 inflected imperative 'is rebooting' FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 2 — inline backticks must NOT erase the imperative (RAW-line detect).
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

You must run `terraform apply` by hand on the host.
EOF
)"
run_case "D2 backticked imperative + actor FAILS" 1 "$f"

# Defect 3-b — the backtick strip must not erase an ACTOR word either.
f="$(mkcase <<'EOF'
# Runbook

The `operator` must reboot web-1.
EOF
)"
run_case "D3b backticked actor + imperative FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 3 — adjacency gap: actor / BLANK / imperative (both orderings).
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

The operator must:

reboot the origin and restore weight.
EOF
)"
run_case "D3 actor / blank / imperative FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

reboot the origin and restore weight,

which the operator does during the window.
EOF
)"
run_case "D3 imperative / blank / actor (reverse) FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 4 — widened actor lexicon (ssh to / onto / -i, yourself, <role> runs).
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

SSH to web-1 and reboot the origin.
EOF
)"
run_case "D4 'ssh to' actor FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

ssh -i key.pem web-2 and reboot it.
EOF
)"
run_case "D4 'ssh -i' actor FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

Reboot the box yourself once the window opens.
EOF
)"
run_case "D4 'yourself' actor FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

The founder runs terraform apply during the maintenance window.
EOF
)"
run_case "D4 'founder runs' actor FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 5 — widened imperative surface.
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

The operator runs terraform destroy on the stale host.
EOF
)"
run_case "D5 'terraform destroy' FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

The operator will power off web-1 by hand.
EOF
)"
run_case "D5 'power off' FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

The operator runs systemctl restart on the session-proxy unit.
EOF
)"
run_case "D5 'systemctl restart' FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

The operator runs cryptsetup to open the LUKS volume by hand.
EOF
)"
run_case "D5 'cryptsetup' FAILS" 1 "$f"

f="$(mkcase <<'EOF'
# Runbook

The operator runs docker restart on the web container.
EOF
)"
run_case "D5 'docker restart' FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 6 — lint-infra-ignore bypass hardening.
# ---------------------------------------------------------------------------

# 6a/6b — a bare (non-HTML-comment) token in PROSE must NOT open a region.
f="$(mkcase <<'EOF'
# Runbook

See lint-infra-ignore for the carve-out convention.

The operator reboots web-1 by hand.
EOF
)"
run_case "D6a bare prose token does NOT suppress → FAILS" 1 "$f"

# 6b — a marker inside a fenced block must NOT open a region.
f="$(mkcase <<'EOF'
# Runbook

```md
<!-- lint-infra-ignore start -->
```

The operator reboots web-1 by hand.
EOF
)"
run_case "D6b marker inside fence does NOT suppress → FAILS" 1 "$f"

# 6c — a `start` with no matching `end` is fail-closed (must NOT grandfather).
f="$(mkcase <<'EOF'
# Runbook

<!-- lint-infra-ignore start -->
The operator reboots web-1 by hand.
EOF
)"
run_case "D6c unterminated ignore region → fail-closed exit 1" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 7 — `## Resolved questions` must NOT carve (loose-substring bug).
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Incident

## Resolved questions

The operator reboots web-1 by hand during the window.
EOF
)"
run_case "D7 'Resolved questions' does NOT carve → FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 8 — an unbalanced/odd fence must NOT silence the file tail.
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

```bash
echo hi

The operator reboots web-1 by hand.
EOF
)"
run_case "D8 unterminated fence → fail-closed exit 1" 1 "$f"

# ---------------------------------------------------------------------------
# Defect 9 — `--changed` fail-closed when the merge base can't resolve → exit 2.
# ---------------------------------------------------------------------------
d9_status=0
(
  set -e
  REPO="$TMPDIR_TEST/nogit"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b feature-only .
  git config user.email t@t && git config user.name t
  mkdir -p knowledge-base/project/plans
  echo "# clean" > knowledge-base/project/plans/p.md
  git add -A && git commit -q -m init
  # No origin/main, no main, and a bogus base → _resolve_base returns None → 2.
  rc=0
  python3 "$SUT" --changed --base does-not-exist-ref >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]]
) || d9_status=$?
if [[ "$d9_status" == "0" ]]; then
  pass "D9 --changed unresolvable base → exit 2"
else
  fail "D9 --changed unresolvable base → exit 2" "sub-shell status=$d9_status"
fi

# ---------------------------------------------------------------------------
# Regression — the paired multi-line comment shape the PR docs already use.
# ---------------------------------------------------------------------------
f="$(mkcase <<'EOF'
# Runbook

<!-- lint-infra-ignore start
     multi-line rationale describing the deferred orchestrator, not a human. -->
The orchestrator reboots the drained host, then the operator confirms via CI.
<!-- lint-infra-ignore end -->

The dispatch applies the plan.
EOF
)"
run_case "multi-line start comment region PASSES" 0 "$f"

# ---------------------------------------------------------------------------
# Defect 10 (#6771) — a CI workflow FILENAME must not satisfy the imperative.
#
# `apply-web-platform-infra.yml` matched `-target\b.*?\bappl(y|ies|ied)\b`
# because the `-` after `apply` is a word boundary; `reboot-*.yml` matches the
# bare `\breboot\b` imperative the same way. A filename NAMES automation — it
# never instructs — so filenames are neutralized before the actor/imperative
# scan. See the module docstring in the SUT.
# ---------------------------------------------------------------------------

# F1 — the live #6749 repro, verbatim. Actor `operator's` on the first line,
# `-target=` + `apply-...yml` on the second: adjacency, not a human step.
f="$(mkcase <<'EOF'
# Plan

`lifecycle { ignore_changes = [value] }` (so TF adopts the operator's value), **and the matching
`-target=` line in `apply-web-platform-infra.yml`** — without that line the resource is declared
EOF
)"
run_case "F1 workflow filename beside 'operator' PASSES (#6749 repro)" 0 "$f"

# F2 — POSITIVE CONTROL. The fix must not blunt the sentinel: a human
# personally running terraform apply still FAILS.
f="$(mkcase <<'EOF'
# Runbook

The operator runs `terraform apply` from their laptop during the window.
EOF
)"
run_case "F2 human runs terraform apply STILL FAILS" 1 "$f"

# F3 — filename-class breadth: `reboot-*.yml` names a workflow, and `reboot`
# is a bare imperative, so the neutralization (not the `-target` anchor) is
# what clears this one.
f="$(mkcase <<'EOF'
# Plan

The operator is paged by `reboot-web-hosts.yml` when the drain stalls.
EOF
)"
run_case "F3 reboot-*.yml filename beside 'operator' PASSES" 0 "$f"

# F4 — glob form. `*` is in the filename char class so a globbed workflow
# name is neutralized too. Uses `reboot-*.yml` rather than the `destroy-*.yml`
# of plan task 1.5: bare `destroy` is NOT an imperative (it requires a
# terraform/tofu prefix), so a `destroy-*` fixture cannot distinguish a char
# class with `*` from one without it — it would pass either way (vacuous).
f="$(mkcase <<'EOF'
# Plan

The operator reviews the `reboot-*.yml` workflows before the freeze.
EOF
)"
run_case "F4 globbed workflow filename PASSES" 0 "$f"

# F5 — REGRESSION GUARD for the tool-anchored `-target` imperative: a human
# hand-running a targeted apply must still FAIL.
f="$(mkcase <<'EOF'
# Runbook

The operator runs `terraform -target=doppler_secret.foo apply` by hand.
EOF
)"
run_case "F5 hand-run terraform -target apply STILL FAILS" 1 "$f"

# F6 — ADJACENCY HAZARD. This is the ONLY mechanical detector of an
# empty-string substitution: deleting the filename span would splice
# `terraform` against `applies` and CREATE a match that is not in the source.
# Substituting `_` keeps the tokens apart. Do not drop this case.
f="$(mkcase <<'EOF'
# Plan

The operator runs terraform pipeline.yml applies cleanly.
EOF
)"
run_case "F6 filename removal must not splice a new match" 0 "$f"

# F7 — actor-side neutralization: the ACTOR half is scanned on the
# neutralized text too, so a workflow named `operator-*.yml` does not supply
# a human actor.
f="$(mkcase <<'EOF'
# Plan

The `operator-digest.yml` workflow runs terraform apply on merge.
EOF
)"
run_case "F7 workflow filename does not supply a human actor" 0 "$f"

# F8 — `.yaml` long form. LOAD-BEARING: an implementation whose fast path
# tests only the literal ".yml" passes every other case here and is still
# broken for ".yaml".
f="$(mkcase <<'EOF'
# Plan

The operator is paged by `reboot-web-hosts.yaml` when the drain stalls.
EOF
)"
run_case "F8 .yaml long-form filename PASSES" 0 "$f"

# F9 — POSITIVE CONTROL WITHOUT THE TOKEN `terraform`. Lifted verbatim from
# knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md.
#
# This is the case whose ABSENCE let a bad fix through: anchoring the `-target`
# imperative on terraform/tofu/opentofu adjacency was measured to silence 41
# corpus lines, ~40% of them genuine human steps like this one — and every
# other positive control here contains the literal word "terraform", so the
# suite stayed green while the sentinel lost its teeth. A human-run apply is
# routinely phrased WITHOUT naming the tool. Do not drop this case, and do not
# add a tool anchor without making it RED first.
f="$(mkcase <<'EOF'
# Cutover runbook

This maintenance-window apply is a **FULL operator apply** (not the per-PR CI
`-target` path), so it ALSO lands the resources the dark-launch merge-apply
deliberately excludes.
EOF
)"
run_case "F9 tool-token-free 'FULL operator apply' STILL FAILS" 1 "$f"

# ---------------------------------------------------------------------------
# Minimum-cardinality guard (an empty/short run must not GREEN).
# ---------------------------------------------------------------------------
MIN_CASES=39
echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]]
