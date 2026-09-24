#!/usr/bin/env python3
"""Regenerate scripts/suite-shard-legs{,-heavy}.tsv from CI suite-timings artifacts (#8006, ADR-240).

WHY THIS EXISTS
---------------
The `test-scripts` matrix legs are balanced by label, not by position: the committed
manifest maps each light-group suite label to the leg a sticky-LPT pass over
CI-measured durations produced. The runner only looks the label up; this script is
the ONLY place assignment is computed — `_shard_selects` sees one registration at a
time and can never balance a set it is still discovering. `--group heavy` applies the
same mechanics to the `test-scripts-heavy` matrix and writes a SECOND file —
per-group manifests, not a shared one, so a heavy regen never rewrites the light
table's insertion-stable surface (ADR-240 amendment).

STICKY-LPT, not plain LPT: longest-processing-time first, but a label keeps its
incumbent leg whenever that leg's running load is within epsilon of the least-loaded
leg. Regeneration therefore changes only what rebalancing requires, and the
committed file diffs small — the property ADR-235's conflict learnings demand of a
generated artifact that lands on every sibling PR.

INPUT
-----
`suite-timings-scripts-N` artifacts from one CI run for --group light
(`suite-timings.tsv` rows: `label<TAB>ms[<TAB>verdict|tmp_delta]`), or
`suite-timings-scripts-heavy-N` for --group heavy. Boundary rows, skipped rows, and
FAIL/KILLED/TRIPWIRE verdicts are excluded — a suite that did not finish carries a
partial timing that would skew the balance. Each group's artifact pattern is
exclusive: light legs never read heavy artifacts and vice versa, because the
registered-label sets are disjoint (want_scripts vs want_scripts_heavy) and a
wrong-group row would fail the ⊆ lint while consuming leg weight for nothing.

USAGE
-----
    python3 scripts/regenerate-shard-manifest.py --run 35840517639 --write
    python3 scripts/regenerate-shard-manifest.py                 # latest green main run, dry-run
    python3 scripts/regenerate-shard-manifest.py --timings-dir /tmp/timings --write
    python3 scripts/regenerate-shard-manifest.py --group heavy --run 35840517639 --write

Without --write: prints the predicted per-leg totals and the diff vs the incumbent
manifest. With --write: rewrites the group's manifest deterministically (header +
label-sorted rows).
"""

import argparse
import glob
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

REPO = "jikig-ai/soleur"
CI_YML = os.path.join(os.path.dirname(__file__), "..", ".github", "workflows", "ci.yml")
INFRA_YML = os.path.join(os.path.dirname(__file__), "..", ".github", "workflows", "infra-validation.yml")
MANIFEST = os.path.join(os.path.dirname(__file__), "suite-shard-legs.tsv")
MANIFEST_HEAVY = os.path.join(os.path.dirname(__file__), "suite-shard-legs-heavy.tsv")
MANIFEST_INFRA = os.path.join(os.path.dirname(__file__), "..", "apps", "web-platform", "infra", "suite-shard-legs.tsv")
GENERATOR_VERSION = "2"
EPSILON_FRACTION = 0.05  # of mean leg load

# Artifact name patterns, one per group and mutually exclusive: the heavy job's
# artifacts carry a `-heavy-` infix the light pattern cannot match, and vice versa.
LIGHT_ARTIFACT = re.compile(r"^suite-timings-scripts-\d+$")
HEAVY_ARTIFACT = re.compile(r"^suite-timings-scripts-heavy-\d+$")
INFRA_ARTIFACT = re.compile(r"^suite-timings-infra-\d+$")


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def gh(args, **kw):
    """Run gh; return stdout text. Dies with the command on failure."""
    p = subprocess.run(["gh"] + args, capture_output=True, text=True, **kw)
    if p.returncode != 0:
        die(f"gh {' '.join(args)} failed: {p.stderr.strip()}")
    return p.stdout


def latest_green_main_run(workflow="ci.yml"):
    out = gh([
        "api", f"repos/{REPO}/actions/workflows/{workflow}/runs",
        "-f", "branch=main", "-f", "status=success", "-f", "per_page=1",
        "--jq", ".workflow_runs[0].id",
    ]).strip()
    if not out or out == "null":
        die(f"no successful {workflow} run on main found; pass --run explicitly")
    return int(out)


def fetch_timings_from_run(run_id, artifact_re):
    """Return {label: ms} merged across the group's timing artifacts of RUN_ID."""
    arts = json.loads(gh([
        "api", f"repos/{REPO}/actions/runs/{run_id}/artifacts",
        "--jq", "{artifacts: [.artifacts[] | {id: .id, name: .name}]}",
    ]))["artifacts"]
    names = [a for a in arts if artifact_re.match(a["name"])]
    if not names:
        die(f"run {run_id} has no {artifact_re.pattern} artifacts")
    merged = {}
    with tempfile.TemporaryDirectory() as td:
        for a in names:
            # Binary payload — capture_output bytes, not the text-mode gh() helper.
            p = subprocess.run(
                ["gh", "api", f"repos/{REPO}/actions/artifacts/{a['id']}/zip"],
                capture_output=True)
            if p.returncode != 0:
                die(f"artifact {a['id']} download failed")
            zpath = os.path.join(td, f"{a['id']}.zip")
            with open(zpath, "wb") as f:
                f.write(p.stdout)
            with zipfile.ZipFile(zpath) as z:
                with z.open("suite-timings.tsv") as tf:
                    merge_tsv(io.TextIOWrapper(tf, encoding="utf-8"), merged,
                              source=a["name"])
    return merged


def fetch_timings_from_dir(d, artifact_re=None):
    """Return {label: ms} merged across suite-timings.tsv files under D. When
    ARTIFACT_RE is given, a nested dir must match it — a mixed download dir
    (light + heavy legs side by side) merges only the requested group's files."""
    merged = {}
    nested_all = glob.glob(os.path.join(d, "*", "suite-timings.tsv"))
    matching = ([p for p in nested_all
                 if artifact_re.match(os.path.basename(os.path.dirname(p)))]
                if artifact_re is not None else [])
    # The filter engages only when CI-artifact-named dirs are actually present —
    # a local dir of arbitrary names (leg1/, leg2/) is not an artifact layout
    # and must merge whole rather than die on an empty filtered set.
    nested = matching if matching else nested_all
    paths = sorted(nested + glob.glob(os.path.join(d, "*.tsv")))
    if not paths:
        die(f"no suite-timings.tsv files found under {d}")
    for p in paths:
        with open(p, encoding="utf-8") as f:
            merge_tsv(f, merged, source=p)
    return merged


def merge_tsv(fh, merged, source):
    """Fold one suite-timings.tsv into {label: max_ms}. Warns on cross-leg dups."""
    for lineno, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        if not line:
            continue
        fields = line.split("\t")
        label, ms_s = fields[0], fields[1] if len(fields) > 1 else ""
        verdict = fields[2] if len(fields) > 2 else ""
        if label.startswith("__run_boundary"):
            continue
        if verdict.startswith("skip=") or verdict in ("FAIL", "KILLED", "TRIPWIRE"):
            continue
        if not re.fullmatch(r"\d+", ms_s or ""):
            die(f"{source}:{lineno}: bad ms field in {line!r}")
        ms = int(ms_s)
        if label in merged:
            print(f"WARN: {label!r} timed on multiple legs "
                  f"({merged[label]}ms vs {ms}ms in {source}) — keeping max",
                  file=sys.stderr)
        merged[label] = max(merged.get(label, 0), ms)


def read_ci_leg_count(job, workflow=None, key="shard"):
    """N of JOB's matrix — `test-scripts`/`test-scripts-heavy` in ci.yml (key
    `shard:`), or `deploy-script-tests` in infra-validation.yml (key `leg:`) —
    scoped to the named job block so leg counts can never be confused."""
    txt = open(workflow or CI_YML, encoding="utf-8").read()
    # The continuation is bounded to lines indented >= 4 (or blank): a `shard:`/
    # `leg:` line absent from THIS job cannot silently match the NEXT job's — the
    # next `^  job:` key at indent 2 terminates the scan and the match fails.
    m = re.search(r"^  %s:\n(?: {4}.*\n| *\n)*? {8}%s: \[\"1/(\d+)\"" % (re.escape(job), key),
                  txt, re.M)
    if not m:
        die(f"could not find {job} matrix {key} declaration in {os.path.basename(workflow or CI_YML)}")
    return int(m.group(1))


def registered_labels(group):
    """The group's registered label set via the runner's own enumerate — the
    same set the ⊆ lint derives. Timing rows for labels that are not registered
    (fixture leaks like `slowfixture`, renamed-away suites, or the OTHER group's
    labels) must not be tabled: they would red the lint and consume leg weight
    for nothing."""
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # Scrub the shard carriers: an exported shard variable would silently shard
    # the enumerate, and the generated manifest would table one leg's subset.
    env = {k: v for k, v in os.environ.items()
           if k not in ("SCRIPTS_SHARD", "TEST_GROUP",
                        "SOLEUR_SHARD_MANIFEST", "SOLEUR_SHARD_MANIFEST_HEAVY",
                        "SOLEUR_INFRA_SHARD", "SOLEUR_INFRA_MANIFEST")}
    if group == "infra":
        p = subprocess.run(
            ["bash", "apps/web-platform/infra/run-registered-suites.sh", "--enumerate"],
            cwd=repo_root, capture_output=True, text=True, env=env)
    else:
        p = subprocess.run(
            ["bash", "scripts/test-all.sh", "--enumerate", group],
            cwd=repo_root, capture_output=True, text=True, env=env)
    if p.returncode != 0:
        die(f"enumerate failed (rc={p.returncode}): {p.stderr.strip()[:400]}")
    return {ln.split("\t", 1)[1] for ln in p.stdout.splitlines()
            if ln.startswith("SUITE_REGISTRATION\t")}


def read_incumbent(path):
    """{label: leg} from an existing manifest; {} if absent."""
    out = {}
    if not os.path.exists(path):
        return out
    for raw in open(path, encoding="utf-8"):
        if raw.startswith("#") or not raw.strip():
            continue
        parts = raw.rstrip("\n").split("\t")
        if len(parts) == 2 and parts[1].isdigit():
            out[parts[0]] = int(parts[1])
    return out


def assign(timings, n, incumbent):
    """Sticky-LPT: desc-ms order; least-loaded leg wins unless the incumbent leg is
    within epsilon of it. Deterministic: ties break on label sort."""
    total = sum(timings.values())
    eps = EPSILON_FRACTION * (total / n) if n else 0
    loads = [0] * n
    legs = {}
    for label in sorted(timings, key=lambda l: (-timings[l], l)):
        ms = timings[label]
        least = min(range(n), key=lambda i: loads[i])
        inc = incumbent.get(label)  # 1-based leg, as written in the manifest
        leg = inc - 1 if (inc is not None and 1 <= inc <= n
                          and loads[inc - 1] <= loads[least] + eps) else least
        legs[label] = leg + 1
        loads[leg] += ms
    return legs, loads


def render(legs, n, run_id, group):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    fname = {"light": "suite-shard-legs.tsv", "heavy": "suite-shard-legs-heavy.tsv",
             "infra": "suite-shard-legs.tsv"}[group]
    regen = {"light": "", "heavy": "--group heavy ", "infra": "--group infra "}[group]
    runner = ("apps/web-platform/infra/run-registered-suites.sh `_shard_selects` equivalent"
              if group == "infra" else
              "scripts/test-all.sh `_shard_selects`")
    lines = [
        f"# {fname} — duration-aware shard assignment (ADR-240)",
        f"# n={n}",
        f"# generated-from-run={run_id}",
        f"# generated-at={ts}",
        f"# generator=regenerate-shard-manifest.py v{GENERATOR_VERSION}",
        f"# regen: python3 scripts/regenerate-shard-manifest.py {regen}--run <id> --write",
        f"# runner: {runner} (untabled labels hash-fallback)",
    ]
    lines += [f"{label}\t{legs[label]}" for label in sorted(legs)]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--group", choices=["light", "heavy", "infra"], default="light",
                    help="which matrix's manifest to build: test-scripts (light), "
                         "test-scripts-heavy, or deploy-script-tests (infra)")
    ap.add_argument("--run", type=int, default=None,
                    help="CI run id to read timings from (default: latest green main ci.yml run)")
    ap.add_argument("--timings-dir", default=None,
                    help="read suite-timings.tsv files from a local dir instead of gh")
    ap.add_argument("--write", action="store_true",
                    help="rewrite the manifest; default is a dry-run report")
    ap.add_argument("--manifest", default=None,
                    help="manifest path (default: the group's committed manifest)")
    ap.add_argument("--registered-file", default=None,
                    help="file of registered labels (default: derive via --enumerate)")
    args = ap.parse_args()

    if args.group == "heavy":
        job, group, artifact_re = "test-scripts-heavy", "scripts-heavy", HEAVY_ARTIFACT
        default_manifest = MANIFEST_HEAVY
        workflow, key = CI_YML, "shard"
    elif args.group == "infra":
        job, group, artifact_re = "deploy-script-tests", "infra", INFRA_ARTIFACT
        default_manifest = MANIFEST_INFRA
        workflow, key = INFRA_YML, "leg"
    else:
        job, group, artifact_re = "test-scripts", "scripts", LIGHT_ARTIFACT
        default_manifest = MANIFEST
        workflow, key = CI_YML, "shard"
    manifest_path = args.manifest if args.manifest else default_manifest

    n = read_ci_leg_count(job, workflow, key)
    run_id = args.run
    if args.timings_dir:
        timings = fetch_timings_from_dir(args.timings_dir, artifact_re)
        src = f"dir:{args.timings_dir}"
    else:
        if run_id is None:
            run_id = latest_green_main_run(os.path.basename(workflow))
        timings = fetch_timings_from_run(run_id, artifact_re)
        src = f"run:{run_id}"
    if not timings:
        die(f"no usable suite timings from {src}")

    if args.registered_file:
        with open(args.registered_file, encoding="utf-8") as f:
            registered = {ln.strip() for ln in f if ln.strip()}
    else:
        registered = registered_labels(group)
    dropped = sorted(set(timings) - registered)
    for label in dropped:
        print(f"WARN: dropping timed-but-unregistered label {label!r}",
              file=sys.stderr)
        del timings[label]
    if not timings:
        die(f"no timed label is a registered scripts suite (source: {src})")

    incumbent = read_incumbent(manifest_path)
    legs, loads = assign(timings, n, incumbent)

    print(f"source: {src}")
    print(f"suites timed: {len(timings)}  total: {sum(timings.values())}ms")
    for i, ms in enumerate(loads, 1):
        print(f"  leg {i}/{n}: {ms}ms ({ms / 1000:.1f}s)")
    spread = max(loads) - min(loads)
    print(f"spread: {spread}ms ({spread / 1000:.1f}s)")

    if incumbent:
        moved = sum(1 for l, leg in legs.items() if incumbent.get(l) != leg)
        new = sum(1 for l in legs if l not in incumbent)
        gone = sum(1 for l in incumbent if l not in legs)
        print(f"vs incumbent: {moved} moved, {new} new, {gone} no longer timed")

    if args.write:
        prov = (str(run_id) if run_id else
                f"local:{os.path.basename(os.path.abspath(args.timings_dir))}")
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(render(legs, n, prov, args.group))
        print(f"wrote {manifest_path} ({len(legs)} rows)")
    else:
        print("dry-run — pass --write to update the manifest")


if __name__ == "__main__":
    main()
