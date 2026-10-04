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
#   * the job's `if:` must be absent, exactly always() or true (the string or the YAML
#     boolean), or name merge_group POSITIVELY: a merge_group inside `!=`, `!(...)` or
#     `!contains/startsWith/endsWith(...)`, or combined with `&& false` / `&& 0`, excludes the
#     event and fails closed,
#   * a context of the CLA Required ruleset has no real merge_group producer by design (its
#     real jobs run on pull_request_target/issue_comment). The synthetic names are DERIVED from
#     the CLA canonical JSON (no hand-typed list); each is satisfied ONLY by the synthetic
#     workflow, whose step that posts conclusion=success must be unconditional: no step-level
#     `if:`, no `continue-on-error` anywhere in the job, no job `needs:`. The set of names that
#     step posts must equal the CLA canonical names (an extra or a missing name is a failure).
#
# Rollback guard: when infra/github/ruleset-ci-required.tf has NO `merge_queue {` block there is
# no queue and no merge_group producer is required (a rollback PR may re-add CodeQL). The probe
# then prints `merge-group-coverage=SKIPPED (no merge_queue rule: producers not required)` and
# exits 0; that line is deliberately NOT an OK line.
#
# Output (stdout): `merge-group-coverage=OK contexts=<n> producers=<m>` and exit 0, or one
# `::error::merge-group-coverage: <context>: <reason>` line per failure, a FAIL summary and
# exit 1. Exit 2 is a usage/environment error (missing file, no PyYAML, unparseable YAML).
#
# Usage: scripts/probe-merge-group-coverage.sh [repo-root]
# Test seams (used by plugins/soleur/test/required-checks-merge-group-coverage.test.sh):
#   MGC_WORKFLOWS_DIR, MGC_CI_JSON, MGC_CLA_JSON, MGC_TF, MGC_MIN_CONTEXTS.
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

# The synthetic workflow; the contexts it (and only it) covers on merge_group are the CLA
# canonical's, derived below.
SYNTHETIC_WORKFLOW = "merge-queue-cla-synthetics.yml"
# Floor on the number of contexts examined: an empty or relocated canonical must not read
# as "all covered".
MIN_CONTEXTS_DEFAULT = 20

root = sys.argv[1]
wf_dir = os.environ.get("MGC_WORKFLOWS_DIR") or os.path.join(root, ".github", "workflows")
ci_json = os.environ.get("MGC_CI_JSON") or os.path.join(
    root, "scripts", "ci-required-ruleset-canonical-required-status-checks.json")
cla_json = os.environ.get("MGC_CLA_JSON") or os.path.join(
    root, "scripts", "ci-cla-required-ruleset-canonical-required-status-checks.json")
tf_path = os.environ.get("MGC_TF") or os.path.join(root, "infra", "github", "ruleset-ci-required.tf")
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


def _strip_negations(s):
    """Delete every negated sub-expression: `!(...)`, `!fn(...)` (balanced parentheses) and
    `!token`. `!=` is not a negation operator and is handled separately."""
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "!" and not (i + 1 < n and s[i + 1] == "="):
            j = i + 1
            while j < n and s[j].isspace():
                j += 1
            k = j
            while k < n and (s[k].isalnum() or s[k] in "_.-"):
                k += 1
            while k < n and s[k].isspace():
                k += 1
            if k < n and s[k] == "(":
                depth = 0
                while k < n:
                    if s[k] == "(":
                        depth += 1
                    elif s[k] == ")":
                        depth -= 1
                        if depth == 0:
                            k += 1
                            break
                    k += 1
                i = k
            else:
                i = max(j, k if k > j else j)
                while i < n and (s[i].isalnum() or s[i] in "_.-'\""):
                    i += 1
            out.append(" ")
            continue
        out.append(c)
        i += 1
    return "".join(out)


def if_ok(expr, ctx):
    # YAML `if: true` loads as the boolean True, `if: false` as False.
    if expr is None:
        return True
    if isinstance(expr, bool):
        return expr
    s = re.sub(r"\$\{\{|\}\}", "", str(expr)).strip()
    if s in ("", "always()", "true"):
        return True
    # The literal must appear OUTSIDE a negation: `github.event_name != 'merge_group'` (either
    # operand order), `!(...)` and `!contains/startsWith/endsWith(...)` exclude the event.
    s = re.sub(r"!=\s*['\"]merge_group['\"]|['\"]merge_group['\"]\s*!=", "", s)
    s = _strip_negations(s)
    if "merge_group" not in s:
        return False
    # `merge_group && false` / `&& 0` (either side) can never be true.
    if re.search(r"&&\s*(?:false|0)(?![\w.])", s) or re.search(r"(?<![\w.])(?:false|0)\s*&&", s):
        return False
    return True


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


def success_posting_steps(job):
    """Steps that post a check-run with conclusion=success: (step, names). A step that only posts
    failure (the failure-report step) produces no green context and is not a producer."""
    out = []
    steps = job.get("steps")
    if not isinstance(steps, list):
        return out
    for step in steps:
        run = step.get("run") if isinstance(step, dict) else None
        if not isinstance(run, str) or "check-runs" not in run or not re.search(r"conclusion=success\b", run):
            continue
        names = set()
        for m in re.finditer(r"\bfor\s+\w+\s+in\s+([^;\n]+?)\s*;\s*do\b", run):
            names.update(m.group(1).split())
        for m in re.finditer(r"\bname=\"?([A-Za-z0-9_.-]+)\"?", run):
            names.add(m.group(1))
        out.append((step, names))
    return out


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
        for step, names in success_posting_steps(job):
            if ctx not in names:
                continue
            if not if_ok(job.get("if"), ctx):
                return "synthetic job %s has an if that excludes merge_group" % jid
            if "needs" in job:
                return "synthetic job %s has needs: (a skipped dependency skips the job)" % jid
            if "continue-on-error" in job or any(
                    isinstance(st, dict) and "continue-on-error" in st for st in job.get("steps", [])):
                return "synthetic job %s has continue-on-error (a failed step would not fail the job)" % jid
            if "if" in step:
                return "the step posting %s in synthetic job %s has a step-level if" % (ctx, jid)
            return None
    return "synthetic workflow %s does not post %s with conclusion=success" % (SYNTHETIC_WORKFLOW, ctx)


def synthetic_posted_names():
    d = workflows.get(SYNTHETIC_WORKFLOW)
    names = set()
    if isinstance(d, dict) and isinstance(d.get("jobs"), dict):
        for job in d["jobs"].values():
            if isinstance(job, dict):
                for _step, step_names in success_posting_steps(job):
                    names |= step_names
    return names


def merge_queue_present(path):
    """True when the HCL has a `merge_queue {` block outside comments (#, //, /* */)."""
    if not os.path.isfile(path):
        die("ruleset terraform file not found: %s" % path)
    with open(path) as fh:
        text = fh.read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = "\n".join(re.sub(r"(?:#|//).*$", "", ln) for ln in text.splitlines())
    return re.search(r"^\s*merge_queue\s*\{", text, re.M) is not None


cla_contexts = read_contexts(cla_json)
SYNTHETIC_CONTEXTS = tuple(cla_contexts)
contexts = []
for ctx in read_contexts(ci_json) + cla_contexts:
    if ctx not in contexts:
        contexts.append(ctx)

if not merge_queue_present(tf_path):
    print("merge-group-coverage=SKIPPED (no merge_queue rule: producers not required)")
    sys.exit(0)

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

# The synthetic must post exactly the CLA ruleset's names: a name it posts that the ruleset does
# not require (or the reverse, reported above per context) is drift between the two.
for extra in sorted(synthetic_posted_names() - set(SYNTHETIC_CONTEXTS)):
    fail(extra, "posted by %s with conclusion=success but not required by the CLA ruleset canonical" % SYNTHETIC_WORKFLOW)

if failures:
    print("merge-group-coverage=FAIL contexts=%d failures=%d" % (len(contexts), len(failures)))
    sys.exit(1)

print("merge-group-coverage=OK contexts=%d producers=%d" % (len(contexts), len(producer_jobs)))
PY
