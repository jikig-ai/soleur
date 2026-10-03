#!/usr/bin/env bash
# Guard 1 engine (#9454): every context required by ANY ruleset on main must be produced on
# a `merge_group` event. A required context with no merge_group producer leaves the queue
# entry pending forever (the 2026-06-30 deadlock, see the merge-queue PIR).
#
# OFFLINE and read-only: no gh, no network, no credentials. Reads
#   - scripts/ci-required-ruleset-canonical-required-status-checks.json   (CI Required)
#   - scripts/ci-cla-required-ruleset-canonical-required-status-checks.json (CLA Required)
#   - .github/workflows/*.yml
# so a context added to either ruleset is audited without editing this script. The
# canonical JSONs are held equal to the live rulesets by the daily ruleset audit.
#
# Per context (EXACTLY ONE producing job; zero is a missing producer, two is ambiguity):
#   * the workflow's `on:` must contain merge_group (map, list and string forms; PyYAML
#     parses the bare key `on` as boolean True),
#   * the job's `if:` must be absent, exactly always(), or name merge_group literally
#     (anything else fails closed),
#   * a context in SYNTHETIC_CONTEXTS has no real merge_group producer by design (its real
#     jobs run on pull_request_target/issue_comment). It is satisfied ONLY by the synthetic
#     workflow, and that workflow must really post the name (cross-checked here, so adding
#     a name to the allowlist alone changes nothing).
#
# Output (stdout): `merge-group-coverage=OK contexts=<n> producers=<m>` and exit 0, or one
# `::error::merge-group-coverage: <context>: <reason>` line per failure, a FAIL summary and
# exit 1. Exit 2 is a usage/environment error (missing file, no PyYAML, unparseable YAML).
#
# Usage: scripts/probe-merge-group-coverage.sh [repo-root]
# Test seams (used by plugins/soleur/test/required-checks-merge-group-coverage.test.sh):
#   MGC_WORKFLOWS_DIR, MGC_CI_JSON, MGC_CLA_JSON, MGC_MIN_CONTEXTS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

command -v python3 >/dev/null 2>&1 || { echo "::error::merge-group-coverage: python3 not found" >&2; exit 2; }

exec python3 - "$ROOT" <<'PY'
import glob
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    print("::error::merge-group-coverage: python3 has no PyYAML module")
    sys.exit(2)

# The synthetic workflow and the contexts it (and only it) covers on merge_group.
SYNTHETIC_WORKFLOW = "merge-queue-cla-synthetics.yml"
SYNTHETIC_CONTEXTS = ("cla-check", "cla-evidence")
# Floor on the number of contexts examined: an empty or relocated canonical must not read
# as "all covered".
MIN_CONTEXTS_DEFAULT = 20
# Contexts whose job `if:` is allowed to exclude merge_group, with a justification. Empty:
# every required job must run on merge_group.
IF_ALLOWLIST = {}

root = sys.argv[1]
wf_dir = os.environ.get("MGC_WORKFLOWS_DIR") or os.path.join(root, ".github", "workflows")
ci_json = os.environ.get("MGC_CI_JSON") or os.path.join(
    root, "scripts", "ci-required-ruleset-canonical-required-status-checks.json")
cla_json = os.environ.get("MGC_CLA_JSON") or os.path.join(
    root, "scripts", "ci-cla-required-ruleset-canonical-required-status-checks.json")
min_contexts = int(os.environ.get("MGC_MIN_CONTEXTS") or MIN_CONTEXTS_DEFAULT)

failures = []


def fail(ctx, reason):
    failures.append((ctx, reason))
    print("::error::merge-group-coverage: %s: %s" % (ctx, reason))


def die(msg):
    print("::error::merge-group-coverage: %s" % msg)
    sys.exit(2)


def read_contexts(path):
    if not os.path.isfile(path):
        die("canonical file not found: %s" % path)
    try:
        with open(path) as fh:
            data = json.load(fh)
    except ValueError as exc:
        die("canonical file is not valid JSON: %s (%s)" % (path, exc))
    if not isinstance(data, list):
        die("canonical file is not a JSON array: %s" % path)
    out = []
    for item in data:
        if not isinstance(item, dict) or not isinstance(item.get("context"), str) or not item["context"]:
            die("canonical entry without a string context in %s" % path)
        out.append(item["context"])
    return out


def on_of(d):
    # PyYAML (YAML 1.1) parses the bare key `on` as the boolean True.
    for k in ("on", True):
        if k in d:
            return d[k]
    return None


def triggers(d):
    on = on_of(d)
    if isinstance(on, dict):
        return set(str(k) for k in on)
    if isinstance(on, list):
        return set(str(k) for k in on)
    if isinstance(on, str):
        return {on}
    return set()


def if_ok(expr, ctx):
    if expr is None:
        return True
    s = re.sub(r"\$\{\{|\}\}", "", str(expr)).strip()
    if s in ("", "always()", "true"):
        return True
    if "merge_group" in s:
        return True
    return ctx in IF_ALLOWLIST


try:
    Loader = yaml.CSafeLoader
except AttributeError:
    Loader = yaml.SafeLoader

if not os.path.isdir(wf_dir):
    die("workflows directory not found: %s" % wf_dir)

# producers_by_name: resolved job name (else job id) -> [(file, job id, triggers, if)]
workflows = {}
producers_by_name = {}
for path in sorted(glob.glob(os.path.join(wf_dir, "*.yml")) + glob.glob(os.path.join(wf_dir, "*.yaml"))):
    try:
        with open(path) as fh:
            d = yaml.load(fh, Loader=Loader)
    except yaml.YAMLError as exc:
        die("cannot parse %s: %s" % (path, str(exc).splitlines()[0]))
    if not isinstance(d, dict):
        continue
    base = os.path.basename(path)
    workflows[base] = d
    trig = triggers(d)
    jobs = d.get("jobs")
    if not isinstance(jobs, dict):
        continue
    for jid, job in jobs.items():
        if not isinstance(job, dict):
            continue
        name = job.get("name", jid)
        if not isinstance(name, str) or "${{" in name:
            continue
        producers_by_name.setdefault(name, []).append((base, str(jid), trig, job.get("if")))


def posted_names(job):
    """Names a job posts as check-runs: tokens of `for x in a b c; do` loops and literal
    name=<token> arguments, in steps whose script calls the check-runs API."""
    names = set()
    steps = job.get("steps")
    if not isinstance(steps, list):
        return names
    for step in steps:
        run = step.get("run") if isinstance(step, dict) else None
        if not isinstance(run, str) or "check-runs" not in run:
            continue
        for m in re.finditer(r"\bfor\s+\w+\s+in\s+([^;\n]+?)\s*;\s*do\b", run):
            names.update(m.group(1).split())
        for m in re.finditer(r"\bname=\"?([A-Za-z0-9_.-]+)\"?", run):
            names.add(m.group(1))
    return names


def synthetic_status(ctx):
    """None when the synthetic covers ctx on merge_group, else a reason string."""
    d = workflows.get(SYNTHETIC_WORKFLOW)
    if d is None:
        return "synthetic workflow %s is missing" % SYNTHETIC_WORKFLOW
    if "merge_group" not in triggers(d):
        return "synthetic workflow %s does not trigger on merge_group" % SYNTHETIC_WORKFLOW
    jobs = d.get("jobs") if isinstance(d.get("jobs"), dict) else {}
    for jid, job in jobs.items():
        if not isinstance(job, dict):
            continue
        if ctx in posted_names(job):
            if not if_ok(job.get("if"), ctx):
                return "synthetic job %s has an if that excludes merge_group" % jid
            return None
    return "synthetic workflow %s does not post %s" % (SYNTHETIC_WORKFLOW, ctx)


contexts = []
for ctx in read_contexts(ci_json) + read_contexts(cla_json):
    if ctx not in contexts:
        contexts.append(ctx)

if len(contexts) < min_contexts:
    fail("(floor)", "%d contexts examined (floor %d): the canonical required-check lists are empty or truncated"
         % (len(contexts), min_contexts))

producer_jobs = set()
for ctx in contexts:
    if ctx in SYNTHETIC_CONTEXTS:
        reason = synthetic_status(ctx)
        if reason is None:
            producer_jobs.add((SYNTHETIC_WORKFLOW, "synthetic"))
        else:
            fail(ctx, "no merge_group producer (%s)" % reason)
        continue
    prods = producers_by_name.get(ctx, [])
    if not prods:
        fail(ctx, "no merge_group producer (no job in .github/workflows is named or id'd %s)" % ctx)
        continue
    if len(prods) > 1:
        fail(ctx, "ambiguous producer (%d jobs: %s)"
             % (len(prods), ", ".join("%s:%s" % (p[0], p[1]) for p in prods)))
        continue
    f, jid, trig, cond = prods[0]
    if "merge_group" not in trig:
        fail(ctx, "no merge_group producer (%s job %s does not trigger on merge_group)" % (f, jid))
        continue
    if not if_ok(cond, ctx):
        fail(ctx, "no merge_group producer (%s job %s has an if that excludes merge_group: %s)"
             % (f, jid, str(cond).strip()))
        continue
    producer_jobs.add((f, jid))

if failures:
    print("merge-group-coverage=FAIL contexts=%d failures=%d" % (len(contexts), len(failures)))
    sys.exit(1)

print("merge-group-coverage=OK contexts=%d producers=%d" % (len(contexts), len(producer_jobs)))
PY
