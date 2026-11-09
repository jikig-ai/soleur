#!/usr/bin/env bash
# #12089 review — umbrella-aggregate parity lint.
#
# Each umbrella job folds several former jobs into MEMBER steps whose verdicts
# are surfaced by one `aggregate` step's `member(...)` calls. Three invariants
# keep the fold honest:
#
#   (a) COVERAGE: every `- id:` step except `aggregate` appears in EXACTLY one
#       `member(...)` call's id list in the aggregate run: block — a member
#       step absent from every call is a verdict the job never reads (a red
#       member cannot fail the umbrella), and a step listed twice double-counts.
#   (b) ISOLATION: every member step's `if:` contains `!cancelled()` — the
#       always-run clause that keeps one red member from hiding the rest.
#   (c) EXISTENCE: an `aggregate` step exists in the job.
#   (d) VERDICT-FLOW: coverage alone certifies wiring, not failure — the
#       aggregate must also consume its member verdicts: `failed=0` init,
#       `|| failed=1` on every member() call, and the `[ "$failed" -ne 0 ]`
#       → `exit 1` tail. The member() body's discriminating lines
#       (`skipped) ;;`, `*) any_fail=1`, the owed-verdict `return 1`, the
#       pass `return 0`) are pinned as tokens — a one-character edit that
#       flips skipped→success or drops the fail edge is a silent green.
#   (e) CENSUS: UMBRELLAS below must equal the set of jobs containing an
#       `- id: aggregate` step across .github/workflows/*.yml — a new
#       umbrella added outside the census fails until registered.
#   (f) CANONICAL-SOURCE: member() exists ONCE, in
#       scripts/lib/umbrella-member.sh (#12276 — the five inline copies were
#       one shared arbiter's worth of drift waiting to happen). Each
#       aggregate run block must source it exactly once via the
#       `${GITHUB_WORKSPACE:?}` form and must NOT carry an inline
#       `member() {` redefinition — a shadow body after the source line
#       silently re-opens the five-way drift the dedup closed. The semantics
#       tokens of (d) are pinned against the lib file, once, not per block.
#
#   (g) PARSED STEP/JOB KEYS (every umbrella): the workflow is loaded with a real YAML parser (PyYAML,
#       fail-closed when absent: exit 2) and every job and every step is checked against an ALLOW-LIST
#       of keys, so no spelling of a neutraliser gets past a text match: `continue-on-error` (bare,
#       "quoted", 'quoted', first key after `- `, flow style, job level), `shell:` (a custom shell
#       template never runs the command), `defaults:`, a job-level `if:` (a skipped required job reads
#       as passing) and a local `uses: ./...` composite action (its inner steps are not scanned) are all
#       outside the allow-list. `member()` reads `conclusion`, and `continue-on-error: true` turns a
#       failed step's conclusion into `success`. Measured against the tree: only `guards-advisory`
#       legitimately uses `continue-on-error` (8 of its steps; its verdicts are non-blocking by design
#       and it is not a required context), and only `quality-advisory` carries a job-level `if`/`needs`
#       (it is not a required context either); `quality-advisory` has NO continue-on-error, so it is not
#       exempt from that rule. See POLICY below.
#   (h) STEP `if:` GRAMMAR (every umbrella step with an `id`): the parsed value is
#       `${{ !cancelled() }}` or `${{ !cancelled() && <expr> }}`, where <expr> is built ONLY from the
#       allow-listed comparison atoms below joined by `&&`, `||` and parentheses, with no `||` at depth
#       0. A `&& false`, a trailing YAML comment naming `!cancelled()`, `success()` and a literal are
#       rejected. The aggregate step's `if:` must be exactly `${{ !cancelled() }}`.
#   (i) MEMBER LINES: every line of the aggregate that starts with `member ` must match ONE strict
#       shape, and its 4th and 5th arguments must be exactly the `conclusion` / `outcome` expressions
#       of the ids named in the 3rd, in order. A constant, another step's verdict, `|| true ||`
#       between the links, a trailing comment or `&& false` do not match.
#   (j) AGGREGATE SHAPE: the aggregate run block is a fixed statement sequence (set, failed=0, source,
#       member lines, the `if [ "$failed" -ne 0 ]` tail, at most one closing echo); the tail is the
#       last statement (an `exit`, `return`, `set +e` or any other statement anywhere else is rejected).
#
# RESIDUALS this lint does not close (ADR-032): a member group is an OR over its arms (a dead arm
# next to a live sibling stays green); the `run:` bodies of member steps are not inspected here
# (the parked-hold steps' bodies are executed by scripts/ci-parked-hold.test.sh section E); a
# never-true event comparison in an `if:` atom is not detectable; a second producer of the context
# name `secret-guards` is not checked.
#
# Parsing: PyYAML (the same dependency the required quality-guards member `workflow-duplicate-keys`
# has, assumed preinstalled on ubuntu-24.04: its summary line prints `pyyaml=<version>` as the
# evidence). A missing PyYAML fails this lint (exit 2) rather than skipping it.
# The member(...) call's THIRD argument is the single-quoted CSV of step ids.
#
# Umbrella census (three files, five jobs):
#   ci.yml                 guards-ruleset, guards-advisory
#   pr-quality-guards.yml  quality-guards, quality-advisory
#   secret-scan.yml        secret-guards
#
# Registered in scripts/test-all.sh (live lint, no .test.sh wrapper).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

python3 -I - <<'PYEOF'
import glob
import os
import re
import sys

try:
    import yaml
except ImportError:
    print("::error::lint-umbrella-aggregate: PyYAML is required to parse the workflows (python3 -c 'import yaml' failed); failing closed", file=sys.stderr)
    sys.exit(2)

# CSafeLoader when PyYAML was built with libyaml (about 10x faster), the pure-python SafeLoader otherwise.
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)


def load_yaml(path):
    with open(path, encoding="utf-8") as fh:
        return yaml.load(fh, Loader=LOADER)


UMBRELLAS = {
    ".github/workflows/ci.yml": ["guards-ruleset", "guards-advisory"],
    ".github/workflows/pr-quality-guards.yml": ["quality-guards", "quality-advisory"],
    ".github/workflows/secret-scan.yml": ["secret-guards"],
}

# Allow-listed keys (rule (g)). A key outside the list is a finding, whatever its spelling or value.
STEP_KEYS = {"id", "if", "name", "env", "run", "uses", "with", "working-directory"}
JOB_KEYS = {"name", "runs-on", "timeout-minutes", "permissions", "env", "steps"}
POLICY = {
    # job -> (allowed job keys, allowed step keys). Required contexts take the defaults.
    "guards-advisory": (JOB_KEYS, STEP_KEYS | {"continue-on-error"}),  # 8 steps use it today
    "quality-advisory": (JOB_KEYS | {"if", "needs"}, STEP_KEYS),  # job-level if/needs today, no continue-on-error
}

failures = []


def fail(msg):
    failures.append(msg)
    print(f"::error::lint-umbrella-aggregate: {msg}", file=sys.stderr)


# ---- rule (h): step `if:` grammar ---------------------------------------------------------------
IF_ATOMS = [
    r"github\.event_name (?:==|!=) '[a-z_]+'",
    r"github\.event\.pull_request\.head\.repo\.full_name == github\.repository",
    r"steps\.[A-Za-z0-9_-]+\.outputs\.[A-Za-z0-9_]+ (?:==|!=) '[^']*'",
    r"needs\.[A-Za-z0-9_-]+\.result (?:==|!=) '[a-z]+'",
    r"needs\.[A-Za-z0-9_-]+\.outputs\.[A-Za-z0-9_]+ (?:==|!=) '[^']*'",
]
ATOM_RE = re.compile("|".join(f"(?:{a})" for a in IF_ATOMS))
IF_HEAD = "${{ !cancelled()"


def if_problem(value, is_aggregate):
    """None when the parsed `if:` value satisfies rule (h), else the reason."""
    if not isinstance(value, str):
        return f"`if:` is not a string expression ({value!r})"
    v = value.strip()
    if is_aggregate:
        return None if v == "${{ !cancelled() }}" else "aggregate `if:` must be exactly ${{ !cancelled() }}"
    if v == "${{ !cancelled() }}":
        return None
    m = re.fullmatch(r"\$\{\{ !cancelled\(\) && (.+) \}\}", v)
    if not m:
        return "`if:` does not start with ${{ !cancelled() && ...}} (a comment, success(), a literal or a different head)"
    rest = m.group(1)
    skeleton = ATOM_RE.sub("A", rest)
    if not re.fullmatch(r"[A()&| ]+", skeleton) or "A" not in skeleton:
        return f"`if:` has a term outside the allow-listed comparison atoms ({rest})"
    depth = 0
    toks = re.findall(r"\(|\)|\|\||&&|A", skeleton)
    for t in toks:
        if t == "(":
            depth += 1
        elif t == ")":
            depth -= 1
        elif t == "||" and depth == 0:
            return "`if:` has a top-level `||`: it would run the step when !cancelled() is false"
    if depth != 0:
        return "`if:` has unbalanced parentheses"
    return None


# ---- rules (i)/(j): the aggregate run block --------------------------------------------------------
MEMBER_RE = re.compile(
    r"member (?P<name>[A-Za-z0-9._-]+) '(?P<scope>\*|-|[a-z_]+(?:,[a-z_]+)*)' "
    r"'(?P<ids>[A-Za-z0-9_-]+(?:,[A-Za-z0-9_-]+)*)' '(?P<conc>[^']*)' '(?P<out>[^']*)' \|\| failed=1"
)
SOURCE_PREFIX = 'source "${GITHUB_WORKSPACE:?}/scripts/lib/umbrella-member.sh" || { echo "::error::'
SOURCE_SUFFIX = '"; exit 1; }'


def stmt_lines(run):
    out = []
    for raw in run.split("\n"):
        t = raw.strip()
        if t == "" or t.startswith("#"):
            continue
        out.append(t)
    return out


def check_aggregate(where, run):
    """Rules (i), (j). Returns the list of member id lists in the block."""
    stmts = stmt_lines(run)
    member_ids = []
    state = "set"
    for t in stmts:
        if state == "set":
            if t != "set -uo pipefail":
                fail(f"{where} aggregate: first statement must be `set -uo pipefail` ({t})")
                return member_ids
            state = "failed0"
        elif state == "failed0":
            if t != "failed=0":
                fail(f"{where} aggregate: second statement must be `failed=0` ({t})")
                return member_ids
            state = "source"
        elif state == "source":
            if not (t.startswith(SOURCE_PREFIX) and t.endswith(SOURCE_SUFFIX) and '"' not in t[len(SOURCE_PREFIX):-len(SOURCE_SUFFIX)]):
                fail(f"{where} aggregate: third statement must be the canonical source line ({t[:80]})")
                return member_ids
            state = "members"
        elif state == "members":
            if t.startswith("member "):
                m = MEMBER_RE.fullmatch(t)
                if not m:
                    fail(f"{where} aggregate: malformed member call (must match the strict shape, ending ` || failed=1` exactly): {t[:120]}")
                    member_ids.append([])
                    continue
                ids = m.group("ids").split(",")
                want_c = ",".join("${{ steps.%s.conclusion }}" % i for i in ids)
                want_o = ",".join("${{ steps.%s.outcome }}" % i for i in ids)
                if m.group("conc") != want_c:
                    fail(f"{where} aggregate: member `{m.group('name')}` 4th argument is not exactly the conclusion expressions of its ids ({','.join(ids)})")
                if m.group("out") != want_o:
                    fail(f"{where} aggregate: member `{m.group('name')}` 5th argument is not exactly the outcome expressions of its ids ({','.join(ids)})")
                member_ids.append(ids)
            elif t == 'if [ "$failed" -ne 0 ]; then':
                if not member_ids:
                    fail(f"{where} aggregate: no member call before the tail")
                state = "tail-echo"
            else:
                fail(f"{where} aggregate: statement outside the allowed sequence before the tail ({t[:100]})")
                return member_ids
        elif state == "tail-echo":
            if re.fullmatch(r'echo "[^"]*"', t):
                continue
            if t == "exit 1":
                state = "tail-fi"
            else:
                fail(f"{where} aggregate: tail must be echo lines then `exit 1` ({t[:100]})")
                return member_ids
        elif state == "tail-fi":
            if t != "fi":
                fail(f"{where} aggregate: tail must close with `fi` right after `exit 1` ({t[:100]})")
                return member_ids
            state = "closing"
        elif state == "closing":
            if re.fullmatch(r'echo "[^"]*"', t):
                state = "done"
            else:
                fail(f"{where} aggregate: the `if [ \"$failed\" -ne 0 ]` tail must be the last statement (only one closing echo may follow): {t[:100]}")
                return member_ids
        elif state == "done":
            fail(f"{where} aggregate: statement after the closing echo ({t[:100]})")
            return member_ids
    if state not in ("closing", "done"):
        fail(f"{where} aggregate: the block ends before the complete `if [ \"$failed\" -ne 0 ]` tail (state {state})")
    return member_ids


for path, jobs in UMBRELLAS.items():
    try:
        doc = load_yaml(path)
    except Exception as e:  # unreadable or unparseable: fail closed
        fail(f"{path}: cannot be parsed as YAML ({type(e).__name__})")
        continue
    all_jobs = doc.get("jobs", {}) if isinstance(doc, dict) else {}
    for job in jobs:
        jb = all_jobs.get(job)
        where = f"{path} `{job}`"
        if not isinstance(jb, dict):
            fail(f"{path}: umbrella job `{job}` not found")
            continue
        job_keys, step_keys = POLICY.get(job, (JOB_KEYS, STEP_KEYS))
        for k in jb:
            if k not in job_keys:
                fail(f"{where}: job key `{k}` is outside the allow-list ({', '.join(sorted(job_keys))}); a `continue-on-error`, `if`, `defaults` or similar job key can turn a red member into a pass")
        steps = jb.get("steps")
        if not isinstance(steps, list):
            fail(f"{where}: no steps list")
            continue

        ided = []
        for n, s in enumerate(steps):
            if not isinstance(s, dict):
                fail(f"{where}: step #{n} is not a mapping")
                continue
            label = s.get("id") or s.get("name") or f"#{n}"
            for k in s:
                if k not in step_keys:
                    fail(f"{where} step `{label}`: disallowed step key `{k}` (allow-list: {', '.join(sorted(step_keys))})")
            u = s.get("uses")
            if u is not None and not (isinstance(u, str) and re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}", u)):
                fail(f"{where} step `{label}`: `uses` must be an owner/repo@<40-hex sha> action (a local or docker action's inner steps are not scanned): {u}")
            if "id" in s:
                ided.append(s)

        # (c) aggregate exists
        agg = [s for s in ided if s["id"] == "aggregate"]
        members = [s["id"] for s in ided if s["id"] != "aggregate"]
        if not agg:
            fail(f"{where}: no `aggregate` step")
            continue
        if len(agg) > 1:
            fail(f"{where}: {len(agg)} `aggregate` steps (want 1)")

        # (b)/(h) every id'd step's if: is in the grammar
        for s in ided:
            if "if" not in s:
                fail(f"{where} step `{s['id']}`: no `if:`")
                continue
            why = if_problem(s["if"], s["id"] == "aggregate")
            if why:
                fail(f"{where} step `{s['id']}`: {why}")

        agg_run = agg[0].get("run")
        if not isinstance(agg_run, str):
            fail(f"{where} aggregate: no `run:` string")
            continue

        # (a) coverage — every non-aggregate step id in exactly one member() call; (i)/(j) shape
        counted = {}
        for ids in check_aggregate(where, agg_run):
            for sid in ids:
                counted[sid] = counted.get(sid, 0) + 1
        for sid in members:
            n = counted.get(sid, 0)
            if n == 0:
                fail(f"{where} step `{sid}`: absent from every member() call")
            elif n > 1:
                fail(f"{where} step `{sid}`: in {n} member() calls (want 1)")
        for sid, n in counted.items():
            if sid not in members:
                fail(f"{where}: member() call names step id `{sid}` that has no `- id:` step")
        if not members:
            fail(f"{where}: no member steps found (anti-vacuity floor)")

        # (d) verdict-flow tokens, (f) canonical-source pin
        rb = agg_run
        for tok in ("failed=0", 'if [ "$failed" -ne 0 ]', "exit 1"):
            if tok not in rb:
                fail(f"{where} aggregate: verdict-flow token `{tok}` missing")
        src_n = rb.count('source "${GITHUB_WORKSPACE:?}/scripts/lib/umbrella-member.sh"')
        if src_n != 1:
            fail(f"{where} aggregate: canonical member() source line present {src_n}x (want 1)")
        if "member() {" in rb:
            fail(f"{where} aggregate: inline member() redefinition shadows the canonical lib")

# (d-continued) member() semantics, pinned ONCE against the canonical lib —
# they used to be checked per run block when each umbrella carried its own
# copy. A missing lib means every umbrella's source line fails at CI time;
# report it here first with the file it cannot source.
lib_path = "scripts/lib/umbrella-member.sh"
if os.path.isfile(lib_path):
    lib = open(lib_path, encoding="utf-8").read()
    if "member() {" not in lib:
        fail(f"{lib_path}: no member() definition")
    for tok in ("skipped) ;;", "*) any_fail=1", "owed a verdict", "return 1", "return 0"):
        if tok not in lib:
            fail(f"{lib_path}: member() semantics token `{tok}` missing")
else:
    fail(f"{lib_path}: canonical member() library absent — umbrellas cannot source it")

# (e) census — every job with an `id: aggregate` step in the tree must be a registered umbrella
discovered = set()
for path in sorted(glob.glob(".github/workflows/*.yml")):
    if "aggregate" not in open(path, encoding="utf-8").read():
        continue  # no step can be named `aggregate` in a file that never says the word: skip the parse
    try:
        doc = load_yaml(path)
    except Exception as e:
        fail(f"{path}: cannot be parsed as YAML ({type(e).__name__}); the census cannot read it")
        continue
    for jname, jb in (doc.get("jobs") or {}).items() if isinstance(doc, dict) else []:
        for s in (jb.get("steps") or []) if isinstance(jb, dict) else []:
            # an umbrella aggregate is the one that sources the canonical member() lib or calls member
            # (scheduled-integration-suites.yml has an unrelated step that is also named `aggregate`)
            if isinstance(s, dict) and s.get("id") == "aggregate" and isinstance(s.get("run"), str) and (
                "umbrella-member.sh" in s["run"] or re.search(r"^\s*member ", s["run"], re.M)
            ):
                discovered.add((path, jname))
census = {(p, j) for p, jobs in UMBRELLAS.items() for j in jobs}
for path, job in sorted(discovered - census):
    fail(f"{path}: `- id: aggregate` in unregistered umbrella `{job}` — add to UMBRELLAS")
for path, job in sorted(census - discovered):
    fail(f"{path}: registered umbrella `{job}` has no `- id: aggregate` step")

if failures:
    print(f"lint-umbrella-aggregate: FAIL ({len(failures)} finding(s))")
    sys.exit(1)
print(f"lint-umbrella-aggregate: OK ({sum(len(v) for v in UMBRELLAS.values())} umbrella jobs verified)")
PYEOF
