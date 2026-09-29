#!/usr/bin/env python3
"""Regenerate scripts/suite-shard-legs{,-heavy}.tsv from CI suite-timings artifacts (#8006, #9232; ADR-240).

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

AGGREGATION + FLOOR (#9232)
---------------------------
Weights aggregate across the last N green main runs by MEDIAN per label — a
sustained drift moves a weight; a one-run spike does not. A registered label
absent from every timing input is still tabled, at the floor weight
(median of the group's measured labels, else DEFAULT_SUITE_MS), marked
`src=floor` in the durations table so a later aggregation never re-reads the
estimate as a measurement. Zero usable timings degrades to an all-floor,
count-balanced manifest with a WARN — strictly better than a die.

The same `--write` also emits `suite-durations*.tsv` beside each group's
manifest (`label<TAB>ms<TAB>src`, label-sorted): the single duration source
the #8231 local parallel scheduler re-packs at an arbitrary worker count via
`--durations <table> --legs W --manifest <path> --write` — no gh calls.

INPUT
-----
`suite-timings-scripts-N` artifacts from one CI run for --group light
(`suite-timings.tsv` rows: `label<TAB>ms[<TAB>verdict|tmp_delta]`),
`suite-timings-scripts-heavy-N` for --group heavy, or `suite-timings-infra-N`
for --group infra (the deploy-script-tests legs). Boundary rows, skipped rows,
and FAIL/KILLED/TRIPWIRE verdicts are excluded — a suite that did not finish
carries a partial timing that would skew the balance. Each group's artifact
pattern is exclusive: light legs never read heavy artifacts and vice versa,
because the registered-label sets are disjoint (want_scripts vs
want_scripts_heavy) and a wrong-group row would fail the ⊆ lint while
consuming leg weight for nothing. Source precedence: `--durations` >
`--timings-dir` (repeatable — one run per dir) > gh (`--run`/`--runs`).

USAGE
-----
    python3 scripts/regenerate-shard-manifest.py --runs 5 --write   # median over last 5 green runs
    python3 scripts/regenerate-shard-manifest.py --run 35840517639 --write   # single-run override
    python3 scripts/regenerate-shard-manifest.py --timings-dir /tmp/timings --write
    python3 scripts/regenerate-shard-manifest.py --group heavy --runs 5 --write
    python3 scripts/regenerate-shard-manifest.py --group infra --run 36060795570 --write
    python3 scripts/regenerate-shard-manifest.py --durations scripts/suite-durations.tsv \\
        --legs 4 --manifest /tmp/local-legs.tsv --write            # #8231 local packing

Without --write: prints the predicted per-leg totals and the diff vs the incumbent
manifest. With --write: rewrites the group's manifest AND durations table
deterministically (header + label-sorted rows). `--legs K` may emit at any K to
an explicit `--manifest` path or in dry-run; writing K != the workflow's
declared leg count to the committed manifest is refused — a committed
n-mismatch silently degrades every leg to positional.
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
DURATIONS = os.path.join(os.path.dirname(__file__), "suite-durations.tsv")
DURATIONS_HEAVY = os.path.join(os.path.dirname(__file__), "suite-durations-heavy.tsv")
DURATIONS_INFRA = os.path.join(os.path.dirname(__file__), "..", "apps", "web-platform", "infra", "suite-durations.tsv")
GENERATOR_VERSION = "3"
EPSILON_FRACTION = 0.05  # of mean leg load
# Weight for a registered suite no run measured: median-of-measured normally;
# this constant when nothing measured at all (the all-floor degrade).
DEFAULT_SUITE_MS = 60000

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


def green_main_runs(workflow="ci.yml", n=5):
    """The N most recent successful main runs of WORKFLOW, newest first.
    Uses `gh run list` rather than the REST runs-list endpoint — the latter
    answers 404 for some credential shapes while run-list and the per-run
    artifacts endpoint both work."""
    p = subprocess.run(
        ["gh", "run", "list", "--workflow", workflow, "--branch", "main",
         "--status", "success", "-L", str(n), "--json", "databaseId",
         "--jq", ".[].databaseId"],
        capture_output=True, text=True)
    if p.returncode != 0:
        die(f"gh run list --workflow {workflow} failed: {p.stderr.strip()}")
    runs = [int(x) for x in p.stdout.split() if x and x != "null"]
    if not runs:
        die(f"no successful {workflow} runs on main found; pass --run or "
            f"--timings-dir/--durations explicitly")
    return runs


def median(xs):
    """Median of a sorted-or-unsorted int list: the middle value, or the mean
    of the two middles for an even sample count (deterministic)."""
    xs = sorted(xs)
    m = len(xs)
    return xs[m // 2] if m % 2 else (xs[m // 2 - 1] + xs[m // 2]) // 2


def fetch_timings_from_run(run_id, artifact_re, expected_legs=None, allow_empty=False):
    """Return {label: ms} merged across the group's timing artifacts of RUN_ID.
    In multi-run aggregation (allow_empty) a run that uploaded no artifacts for
    the group warns and contributes nothing instead of dying — one shape-dead
    run must not void the other N-1."""
    arts = json.loads(gh([
        "api", f"repos/{REPO}/actions/runs/{run_id}/artifacts?per_page=100",
        "--jq", "{artifacts: [.artifacts[] | {id: .id, name: .name}]}",
    ]))["artifacts"]
    names = [a for a in arts if artifact_re.match(a["name"])]
    if not names:
        if allow_empty:
            print(f"WARN: run {run_id} has no {artifact_re.pattern} artifacts — "
                  f"it contributes nothing to the aggregation", file=sys.stderr)
            return {}
        die(f"run {run_id} has no {artifact_re.pattern} artifacts")
    if expected_legs is not None and len(names) != expected_legs:
        print(f"WARN: run {run_id} produced {len(names)} {artifact_re.pattern} "
              f"artifact(s), expected {expected_legs} — a leg died before its "
              f"feed write; suites it would have timed carry the floor weight "
              f"in the regenerated manifest.", file=sys.stderr)
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
                try:
                    tf = z.open("suite-timings.tsv")
                except KeyError:
                    die(f"artifact {a['name']} (id {a['id']}) contains no "
                        f"suite-timings.tsv — a leg uploaded a different shape")
                with tf:
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
    # Flat files must be *timings*.tsv, not *.tsv — a stray notes.tsv in the
    # dir would merge garbage labels or die on a bad ms field.
    paths = sorted(nested + glob.glob(os.path.join(d, "*timings*.tsv")))
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
                        "SOLEUR_INFRA_SHARD", "SOLEUR_INFRA_MANIFEST",
                        "SOLEUR_INFRA_DIR", "SOLEUR_INFRA_TIMINGS",
                        "INFRA_ORPHAN_LIST")}
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


def aggregate_runs(per_run):
    """{label: median_ms} across a list of per-run {label: ms} merges.
    Median, not max or mean: a sustained drift must move the weight, a one-run
    contention spike must not entrench itself (ADR-240 amd., #8163's 2.4x
    contended-vs-isolated measurement)."""
    samples = {}
    for timings in per_run:
        for label, ms in timings.items():
            samples.setdefault(label, []).append(ms)
    return {label: median(xs) for label, xs in samples.items()}


def read_durations(path):
    """Read a committed durations table (`label<TAB>ms<TAB>src`).

    Returns (weights, floor_labels): src=measured rows supply weights; src=floor
    rows supply NO weight — they re-derive at floor_ms on this invocation, so an
    estimate can never launder into a measurement across regenerations."""
    weights, floors = {}, set()
    if not os.path.exists(path):
        die(f"--durations file not found: {path}")
    for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3 or not parts[1].isdigit() \
                or parts[2] not in ("measured", "floor"):
            die(f"{path}:{lineno}: malformed durations row {line!r} — "
                f"expected 'label<TAB>ms<TAB>src' with src in (measured|floor)")
        if parts[2] == "measured":
            weights[parts[0]] = int(parts[1])
        else:
            floors.add(parts[0])
    return weights, floors


def render_durations(weights, src_map, group, prov, floor_ms):
    """The committed `label<TAB>ms<TAB>src` table — the single duration source
    both the CI regen and the #8231 local scheduler consume."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    fname = {"light": "suite-durations.tsv", "heavy": "suite-durations-heavy.tsv",
             "infra": "suite-durations.tsv"}[group]
    lines = [
        f"# {fname} — aggregated per-suite durations (ADR-240 amd.)",
        f"# group={group}",
        f"# generated-from-runs={prov}",
        f"# default-weight-ms={floor_ms}",
        f"# generated-at={ts}",
        f"# generator=regenerate-shard-manifest.py v{GENERATOR_VERSION}",
    ]
    lines += [f"{label}\t{weights[label]}\t{src_map[label]}"
              for label in sorted(weights)]
    return "\n".join(lines) + "\n"


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


def render(legs, n, prov, group, runs_csv=None, floor_ms=None):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    fname = {"light": "suite-shard-legs.tsv", "heavy": "suite-shard-legs-heavy.tsv",
             "infra": "suite-shard-legs.tsv"}[group]
    regen = {"light": "", "heavy": "--group heavy ", "infra": "--group infra "}[group]
    runner = ("apps/web-platform/infra/run-registered-suites.sh manifest/hashing assignment"
              if group == "infra" else
              "scripts/test-all.sh `_shard_selects`")
    lines = [
        f"# {fname} — duration-aware shard assignment (ADR-240)",
        f"# n={n}",
        # Both keys are written on purpose: the manifest lint anchors on
        # `^# generated-from-run=` (singular), which `runs=` does not satisfy.
        f"# generated-from-run={prov}",
        f"# generated-from-runs={runs_csv or prov}",
        f"# default-weight-ms={floor_ms}",
        f"# generated-at={ts}",
        f"# generator=regenerate-shard-manifest.py v{GENERATOR_VERSION}",
        f"# regen: python3 scripts/regenerate-shard-manifest.py {regen}--runs 5 --write",
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
                    help="CI run id to read timings from (explicit single-run "
                         "override; equivalent to --runs 1 over that run)")
    ap.add_argument("--runs", type=int, default=5,
                    help="aggregate timings over the N most recent green main "
                         "runs of the group's workflow by per-label median "
                         "(default: 5)")
    ap.add_argument("--timings-dir", action="append", default=None,
                    help="read suite-timings.tsv files from a local dir instead "
                         "of gh; repeatable — each dir is one run's artifact set")
    ap.add_argument("--durations", default=None,
                    help="read a committed suite-durations table instead of "
                         "fetching timings (src=floor rows re-derive at the "
                         "floor, never as measured)")
    ap.add_argument("--durations-out", default=None,
                    help="write the aggregated durations table to this path "
                         "(default: the group's committed suite-durations.tsv)")
    ap.add_argument("--legs", type=int, default=None,
                    help="emit the packing at K legs instead of the workflow's "
                         "declared count — arbitrary-K emission for #8231's "
                         "local scheduler; --write to the committed manifest "
                         "with K != the workflow N is refused")
    ap.add_argument("--write", action="store_true",
                    help="rewrite the manifest + durations table; default is a "
                         "dry-run report")
    ap.add_argument("--manifest", default=None,
                    help="manifest path (default: the group's committed manifest)")
    ap.add_argument("--registered-file", default=None,
                    help="file of registered labels (default: derive via --enumerate)")
    args = ap.parse_args()

    if args.legs is not None and args.legs < 1:
        die("--legs must be >= 1")

    if args.group == "heavy":
        job, group, artifact_re = "test-scripts-heavy", "scripts-heavy", HEAVY_ARTIFACT
        default_manifest = MANIFEST_HEAVY
        default_durations = DURATIONS_HEAVY
        workflow, key = CI_YML, "shard"
    elif args.group == "infra":
        job, group, artifact_re = "deploy-script-tests", "infra", INFRA_ARTIFACT
        default_manifest = MANIFEST_INFRA
        default_durations = DURATIONS_INFRA
        workflow, key = INFRA_YML, "leg"
    else:
        job, group, artifact_re = "test-scripts", "scripts", LIGHT_ARTIFACT
        default_manifest = MANIFEST
        default_durations = DURATIONS
        workflow, key = CI_YML, "shard"
    manifest_path = args.manifest if args.manifest else default_manifest
    durations_path = args.durations_out if args.durations_out else default_durations

    # n_wf is ALWAYS the workflow's declared leg count — the artifact-completeness
    # WARN and the committed-manifest n-pin bind to it. --legs reshapes only the
    # emitted packing.
    n_wf = read_ci_leg_count(job, workflow, key)
    n = args.legs if args.legs is not None else n_wf

    # A committed manifest whose n disagrees with the workflow matrix silently
    # degrades every leg to positional while reading as applied — refuse the
    # write BEFORE computing anything; dry-run and explicit --manifest are the
    # sanctioned K-simulation paths.
    if args.write and args.legs is not None and args.legs != n_wf \
            and os.path.abspath(manifest_path) == os.path.abspath(default_manifest):
        die(f"--legs {args.legs} mismatches the {job} matrix's declared {n_wf} "
            f"legs — refusing to commit an n-mismatched {os.path.basename(default_manifest)}. "
            f"Pass --manifest <path> to emit at K={args.legs} elsewhere.")

    # Input-source precedence mirrors the file's pairing rule: whichever source
    # actually fed stamps the provenance. --durations > --timings-dir > gh.
    floor_inputs = set()
    run_ids = []
    per_run = []
    if args.durations:
        weights, floor_inputs = read_durations(args.durations)
        src = f"durations:{args.durations}"
        if args.timings_dir or args.run or args.runs != 5:
            print(f"WARN: --durations wins over "
                  f"--timings-dir/--run/--runs (source precedence)",
                  file=sys.stderr)
    elif args.timings_dir:
        for d in args.timings_dir:
            per_run.append((f"dir:{d}", fetch_timings_from_dir(d, artifact_re)))
        src = "dir:" + ",".join(
            os.path.basename(os.path.abspath(d)) for d in args.timings_dir)
    else:
        if args.run:
            run_ids = [args.run]
        else:
            run_ids = green_main_runs(os.path.basename(workflow), args.runs)
        for r in run_ids:
            per_run.append((f"run:{r}",
                            fetch_timings_from_run(
                                r, artifact_re, expected_legs=n_wf,
                                allow_empty=len(run_ids) > 1)))
        src = "run:" + ",".join(str(r) for r in run_ids)
        weights = None

    if args.durations:
        measured = weights
    else:
        measured = aggregate_runs([t for _, t in per_run])

    if args.registered_file:
        with open(args.registered_file, encoding="utf-8") as f:
            registered = {ln.strip() for ln in f if ln.strip()}
    else:
        registered = registered_labels(group)
    dropped = sorted(set(measured) - registered)
    for label in dropped:
        print(f"WARN: dropping timed-but-unregistered label {label!r}",
              file=sys.stderr)
        del measured[label]
    dropped_floor = sorted(floor_inputs - registered)
    for label in dropped_floor:
        print(f"WARN: dropping floor-row label {label!r} — not a registered "
              f"{group} suite", file=sys.stderr)

    # Floor tabling (#9232): a registered label absent from every timing input
    # still carries weight — floor_ms is the median of the measured set, else
    # DEFAULT_SUITE_MS. Floor rows are marked src=floor so a later aggregation
    # never entrenches its own estimate as "measured". A timings-empty
    # invocation produces an all-floor count-balanced manifest with a WARN —
    # strictly better than the die this replaces.
    floor_ms = median(measured.values()) if measured else DEFAULT_SUITE_MS
    timings = dict(measured)
    src_map = {label: "measured" for label in measured}
    floored = 0
    for label in sorted(registered):
        if label not in timings:
            timings[label] = floor_ms
            src_map[label] = "floor"
            floored += 1
    if floored:
        print(f"WARN: {floored} registered label(s) have no measured timing — "
              f"tabled at floor {floor_ms}ms (src=floor)", file=sys.stderr)
    if not measured:
        print(f"WARN: no usable suite timings from {src} — producing an "
              f"all-floor count-balanced manifest (floor={floor_ms}ms)",
              file=sys.stderr)

    incumbent = read_incumbent(manifest_path)
    legs, loads = assign(timings, n, incumbent)

    print(f"source: {src}")
    for label_src, t in per_run:
        print(f"  {label_src}: {len(t)} timed label(s)")
    print(f"suites: {len(timings)} tabled ({len(measured)} measured, "
          f"{floored} at floor {floor_ms}ms)  total: {sum(timings.values())}ms")
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
        # Provenance follows the SOURCE the timings actually came from — a
        # `--run` flag paired with `--timings-dir`/`--durations` must not stamp
        # a run id on data that run never produced.
        if args.durations:
            prov = f"durations:{os.path.basename(os.path.abspath(args.durations))}"
            runs_csv = prov
        elif args.timings_dir:
            prov = "local:" + ",".join(
                os.path.basename(os.path.abspath(d)) for d in args.timings_dir)
            runs_csv = prov
        else:
            prov = str(run_ids[0])
            runs_csv = ",".join(str(r) for r in run_ids)
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(render(legs, n, prov, args.group,
                           runs_csv=runs_csv, floor_ms=floor_ms))
        print(f"wrote {manifest_path} ({len(legs)} rows)")
        with open(durations_path, "w", encoding="utf-8") as f:
            f.write(render_durations(timings, src_map, args.group,
                                     runs_csv, floor_ms))
        print(f"wrote {durations_path} ({len(timings)} rows)")
    else:
        print("dry-run — pass --write to update the manifest")


if __name__ == "__main__":
    main()
