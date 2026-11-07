#!/usr/bin/env python3
"""site_cost_table.py — per-site cost table from the stamp files of site_cost_run.sh readings (Ref #12013).

Usage (run with `python3 -I`):
  site_cost_table.py <rawdir> <out.tsv>        build <out.tsv> and <out>.by_rep.tsv from the raw files of every rep
  site_cost_table.py --sites <test-file>       print the sites map (ordinal, kind, row) of a replay test file
  site_cost_table.py --selftest                hand-computed golden + mutants + refusals

Raw files per rep R and arm A (copied by the operator from the reading's output dir):
  R.A.stamps.tsv  "<tag>\\t<EPOCHREALTIME>" lines: 0, 1..TOTAL, EOF (TOTAL+2 lines)
  R.A.rc          the arm's exit status           R.A.wall   "<start>\\t<end>" EPOCHREALTIME
  R.A.passed      the arm's final "N passed" line R.A.range  "<lo>-<hi>"
  R.guard.txt     site_cost_run.sh guard file (last line CLEAN or DISTURBED; "rep=.. tree=.." first line)
  sites.tsv       "<ordinal>\\t<kind>\\t<row>" (from --sites), one line per gated site

Per rep and site k (owner = the arm whose range holds k):
  interval(arm, k) = stamp[k+1] - stamp[k]            (stamp[TOTAL+1] is EOF); the head 0->1 never enters a site. The tail (site TOTAL to EOF)
  is part of site TOTAL's interval in EVERY arm and cancels in raw_cost only up to the arms' tail differences (a few seconds in the real readings).
  Equal consecutive stamps are accepted (microsecond clock, skipped sites); only a decrease is refused.
  raw_cost = interval(owner, k) - median(interval of the two non-owning arms)      (unclamped)
  noise_s  = |difference of the two non-owner intervals|
Across reps the per-site value is the MEDIAN (a mean would follow one disturbed outlier; with the two reps shipped the median of two IS their mean,
so the outlier protection exists from three reps on). others_live is the median of per-rep counts, rounded half up. cost = max(0, raw_cost).
noise_s is the spread of the two non-owner skip intervals (milliseconds); it is NOT a between-rep noise measure, which site_cost_whatif.py's rep-disagreement test carries.
unconditional_s(arm) = arm wall - sum of its owned raw_cost, so the predicted wall of an arm closes by construction.
"""
import glob
import contextlib
import io
import os
import re
import shutil
import sys
import tempfile
from decimal import Decimal, InvalidOperation
from statistics import median

TOTAL = 602  # DECLARED_TOTAL of plugins/soleur/test/ci-pr-affected-replay.test.sh on the tree under test
ARMS = ("a", "b", "c")
FLAG_NONOWNER_S = Decimal("5")


class Refusal(Exception):
    """A reading or input that must not be turned into a table (exit 2)."""


class Opts:
    """Selftest-only perturbations of the estimator; every one must turn the golden RED."""

    def __init__(self, shift_owner=0, off_by_one_stamp=False, fold_head=False, clamp_raw=False, use_mean=False, no_subtraction=False):
        self.shift_owner = shift_owner
        self.off_by_one_stamp = off_by_one_stamp
        self.fold_head = fold_head
        self.clamp_raw = clamp_raw
        self.use_mean = use_mean
        self.no_subtraction = no_subtraction


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        raise Refusal(f"cannot read {path}: {e}")


def parse_stamps(path, total):
    lines = read_text(path).splitlines()
    if len(lines) != total + 2:
        raise Refusal(f"{path}: {len(lines)} stamp lines, expected {total + 2} (0..{total} then EOF)")
    tags = [str(i) for i in range(total + 1)] + ["EOF"]
    times = []
    for want, line in zip(tags, lines):
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] != want:
            raise Refusal(f"{path}: expected tag {want!r}, got {line[:40]!r}")
        try:
            times.append(Decimal(parts[1]))
        except Exception:
            raise Refusal(f"{path}: bad time in {line[:40]!r}")
    for i in range(1, len(times)):
        if times[i] < times[i - 1]:
            raise Refusal(f"{path}: time goes backwards at tag {tags[i]}")
    return times  # index 0..total, then EOF at total+1


def parse_range(text):
    m = re.fullmatch(r"(\d+)-(\d+)", text.strip())
    if not m:
        raise Refusal(f"bad range {text!r}")
    return int(m.group(1)), int(m.group(2))


def load_rep(raw, rep, total):
    guard = read_text(os.path.join(raw, f"{rep}.guard.txt")).splitlines()
    if not guard or guard[-1].strip() != "CLEAN":
        raise Refusal(f"rep {rep}: guard file does not end in CLEAN (DISTURBED or incomplete) — a disturbed reading is not a result")
    m = re.search(r"tree=(\S+)", guard[0])
    tree = m.group(1) if m else "unknown"
    arms = {}
    for arm in ARMS:
        base = os.path.join(raw, f"{rep}.{arm}")
        if read_text(base + ".rc").strip() != "0":
            raise Refusal(f"rep {rep} arm {arm}: arm exit status is not 0")
        passed = read_text(base + ".passed").strip()
        if not re.search(r", 0 failed,", passed) or " passed" not in passed:
            raise Refusal(f"rep {rep} arm {arm}: final line is not a clean pass: {passed[:80]!r}")
        try:
            s, e = read_text(base + ".wall").split()
            wall_s, wall_e = Decimal(s), Decimal(e)
        except (ValueError, InvalidOperation):
            raise Refusal(f"rep {rep} arm {arm}: malformed .wall file")
        if not (wall_s.is_finite() and wall_e.is_finite() and wall_e > wall_s):
            raise Refusal(f"rep {rep} arm {arm}: malformed .wall file (not finite, or the end is not after the start)")
        arms[arm] = {
            "times": parse_stamps(base + ".stamps.tsv", total),
            "range": parse_range(read_text(base + ".range")),
            "wall": wall_e - wall_s,
            "span": (wall_s, wall_e),
            "passed": passed,
        }
    # the three ranges must tile 1..total
    spans = sorted(a["range"] for a in arms.values())
    nxt = 1
    for lo, hi in spans:
        if lo != nxt or hi < lo:
            raise Refusal(f"rep {rep}: ranges do not tile 1..{total}: {spans}")
        nxt = hi + 1
    if nxt != total + 1:
        raise Refusal(f"rep {rep}: ranges end at {nxt - 1}, expected {total}")
    return {"tree": tree, "arms": arms}


def owner_of(k, ranges, shift):
    kk = k - shift
    for arm, (lo, hi) in ranges.items():
        if lo <= kk <= hi:
            return arm
    return None


def compute_rep(rep, total, opts):
    arms = rep["arms"]
    ranges = {arm: arms[arm]["range"] for arm in ARMS}
    eof = {arm: arms[arm]["times"][total + 1] for arm in ARMS}

    def interval(arm, k):
        t = arms[arm]["times"]
        if opts.off_by_one_stamp:
            return t[k] - t[k - 1]
        if opts.fold_head and k == 1:
            return t[2] - t[0]
        return t[k + 1] - t[k]

    sites = {}
    owned_sum = {arm: Decimal(0) for arm in ARMS}
    for k in range(1, total + 1):
        owner = owner_of(k, ranges, opts.shift_owner)
        if owner is None:
            raise Refusal(f"site {k} has no owner under the ranges {ranges}")
        others = [a for a in ARMS if a != owner]
        oi = interval(owner, k)
        n1, n2 = interval(others[0], k), interval(others[1], k)
        med = (n1 + n2) / 2
        raw = oi if opts.no_subtraction else oi - med
        if opts.clamp_raw and raw < 0:
            raw = Decimal(0)
        tk = arms[owner]["times"][k]
        live = sum(1 for a in others if eof[a] > tk)
        sites[k] = {"owner": owner, "raw": raw, "noise": abs(n1 - n2), "nonowner": med, "live": live}
        owned_sum[owner] += raw
    uncond = {arm: arms[arm]["wall"] - owned_sum[arm] for arm in ARMS}
    return {"sites": sites, "uncond": uncond, "wall": {arm: arms[arm]["wall"] for arm in ARMS}}


def agg(values, use_mean):
    if use_mean:
        return sum(values) / len(values)
    return median(values)


def build(raw, total=TOTAL, opts=None):
    opts = opts or Opts()
    reps = sorted({os.path.basename(p)[: -len(".guard.txt")] for p in glob.glob(os.path.join(raw, "*.guard.txt"))})
    if not reps:
        raise Refusal(f"no *.guard.txt in {raw}")
    loaded = [(r, load_rep(raw, r, total)) for r in reps]
    trees = {rp["tree"] for _, rp in loaded}
    if len(trees) != 1:
        raise Refusal(f"reps were taken on different trees: {sorted(trees)}")
    ranges0 = {a: loaded[0][1]["arms"][a]["range"] for a in ARMS}
    for r, rp in loaded:
        if {a: rp["arms"][a]["range"] for a in ARMS} != ranges0:
            raise Refusal(f"rep {r} used different arm ranges")
    # Two readings whose time spans intersect disturbed each other, whatever their guard files say (reps r2 and r3 of the first attempt did).
    spans = sorted((min(a["span"][0] for a in rp["arms"].values()), max(a["span"][1] for a in rp["arms"].values()), r) for r, rp in loaded)
    for (s0, e0, r0), (s1, e1, r1) in zip(spans, spans[1:]):
        if s1 < e0:
            raise Refusal(f"reps {r0} and {r1} overlap in time: they disturbed each other whatever their guard files say")
    comp = [(r, compute_rep(rp, total, opts)) for r, rp in loaded]
    rowmap = {}
    sites_path = os.path.join(raw, "sites.tsv")
    if not os.path.exists(sites_path):
        raise Refusal("raw/sites.tsv is missing: without it every row would be labelled '?' (generate it with --sites from the test file of the tree that was measured)")
    for line in read_text(sites_path).splitlines():
        parts = line.split("\t")
        if len(parts) != 3 or not parts[0].isdigit():
            raise Refusal(f"sites.tsv has a malformed line: {line[:60]!r}")
        rowmap[int(parts[0])] = parts[2]
    if sorted(rowmap) != list(range(1, total + 1)):
        raise Refusal(f"sites.tsv maps {len(rowmap)} sites, expected exactly the ordinals 1..{total} (regenerate it from the test file of the tree that was measured)")
    final = {}
    for k in range(1, total + 1):
        raws = [c["sites"][k]["raw"] for _, c in comp]
        noises = [c["sites"][k]["noise"] for _, c in comp]
        nonown = [c["sites"][k]["nonowner"] for _, c in comp]
        lives = [c["sites"][k]["live"] for _, c in comp]
        raw = agg(raws, opts.use_mean)
        final[k] = {
            "arm": comp[0][1]["sites"][k]["owner"],
            "row": rowmap[k],
            "raw": raw,
            "cost": max(Decimal(0), raw),
            "noise": agg(noises, opts.use_mean),
            "nonowner": agg(nonown, opts.use_mean),
            "live": round_half_up_median(lives) if not opts.use_mean else int(agg(lives, True)),
            "by_rep": raws,
        }
        final[k]["flag"] = "flag" if (final[k]["cost"] < final[k]["noise"] or final[k]["nonowner"] > FLAG_NONOWNER_S) else "-"
    uncond = {a: agg([c["uncond"][a] for _, c in comp], opts.use_mean) for a in ARMS}
    walls = {a: agg([c["wall"][a] for _, c in comp], opts.use_mean) for a in ARMS}
    return {"final": final, "uncond": uncond, "walls": walls, "reps": [r for r, _ in comp], "ranges": ranges0,
            "tree": next(iter(trees)), "total": total, "passed": {a: loaded[0][1]["arms"][a]["passed"] for a in ARMS}}


def f3(x):
    return format(x.quantize(Decimal("0.001")), "f")


def render(t):
    out = [f"# tree={t['tree']}", f"# DECLARED_TOTAL={t['total']}", "# reps=" + ",".join(t["reps"]),
           "# ranges " + " ".join(f"{a}={t['ranges'][a][0]}-{t['ranges'][a][1]}" for a in ARMS),
           "# unconditional_s " + " ".join(f"{a}={f3(t['uncond'][a])}" for a in ARMS),
           "# wall_s " + " ".join(f"{a}={f3(t['walls'][a])}" for a in ARMS),
           "# scope: the tree named above only. After the observation-window retirement (129 sites, ordinals 1-129 here), ordinal k of the 473-site test file is ordinal k+129 here.",
           "# estimator: raw_cost = owner interval - median(two non-owner intervals), unclamped; reps aggregated by median; cost = max(0, raw_cost)",
           "site\tarm\trow\tcost_s\traw_cost_s\tnoise_s\tflag\tothers_live"]
    for k in range(1, t["total"] + 1):
        s = t["final"][k]
        out.append(f"{k}\t{s['arm']}\t{s['row']}\t{f3(s['cost'])}\t{f3(s['raw'])}\t{f3(s['noise'])}\t{s['flag']}\t{s['live']}")
    return "\n".join(out) + "\n"


def render_by_rep(t):
    out = ["# raw_cost_s per rep: " + ",".join(t["reps"]), "site\tarm\t" + "\t".join(t["reps"])]
    for k in range(1, t["total"] + 1):
        s = t["final"][k]
        out.append(f"{k}\t{s['arm']}\t" + "\t".join(f3(v) for v in s["by_rep"]))
    return "\n".join(out) + "\n"


def sites_of(test_file):
    """(ordinal, kind, row) per gated call. A call whose quoted arguments span several lines closes on a later line, so the row label is the
    last token of the first line at or after the call that ends in a bare row_* token (the statement is continuous, so no other call can
    start before it closes)."""
    out = []
    lines = read_text(test_file).splitlines()
    n = 0
    for i, line in enumerate(lines):
        m = re.match(r"(mutate|ow_mutate) ", line)
        if not m:
            continue
        n += 1
        row = "?"
        for j in range(i, min(i + 60, len(lines))):
            if j > i and re.match(r"(mutate|ow_mutate) ", lines[j]):
                break  # the next call starts: this one had no row label
            mm = re.search(r"\s(row_[A-Za-z0-9_]+)\s*(?:#.*)?$", lines[j])
            if mm:
                row = mm.group(1)
                break
        out.append(f"{n}\t{m.group(1)}\t{row}")
    return "\n".join(out) + "\n"


def _write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def round_half_up_median(values):
    """Median of integer counts, rounded half up (two reps give half-integers)."""
    return int(Decimal(str(median(values))) + Decimal("0.5"))


def make_rep(raw, rep, costs, clean=True, extra_line=False, backwards=False, base=0, tree="deadbeef", rc="0",
             passed="ci-pr-affected-replay.test.sh: 10 passed, 0 failed, 10 assertions, 3 mutants", range_a="1-193", wall_text=None, chunks=None, wall_a=1000):
    """Synthetic rep. Every site: owner interval = true cost + 0.025, non-owners 0.020 and 0.030 (median 0.025).
    Head 0->1 is 4.0 s in arm a and 1.0 s elsewhere. Site TOTAL carries the tail: owner c 0.5 s + cost, non-owners a 0.4 s and b 0.6 s
    (median 0.5, so raw_cost is the cost and noise_s is 0.2). `chunks` adds an unconditional chunk (seconds) to site k in every arm."""
    chunks = chunks or {}
    b0 = Decimal(base)
    starts = {"a": Decimal("1000.0") + b0, "b": Decimal("1030.2") + b0, "c": Decimal("1100.4") + b0}  # staggered so others_live varies per site
    ranges = {"a": (1, 193), "b": (194, 386), "c": (387, 602)}
    walls = {"a": Decimal(wall_a), "b": Decimal("500.0"), "c": Decimal("400.0")}
    for arm in ARMS:
        t = starts[arm]
        stamps = [("0", t)]
        t += Decimal("4.0") if arm == "a" else Decimal("1.0")
        for k in range(1, TOTAL + 1):
            stamps.append((str(k), t))
            owner = [x for x in ARMS if ranges[x][0] <= k <= ranges[x][1]][0]
            if arm == owner:
                step = costs.get(k, Decimal(0)) + (Decimal("0.5") if k == TOTAL else Decimal("0.025"))
            elif k == TOTAL:
                step = Decimal("0.4") if arm == "a" else Decimal("0.6")
            else:
                rank = [x for x in ARMS if x != owner].index(arm)
                step = Decimal("0.020") if rank == 0 else Decimal("0.030")
            t += step + Decimal(str(chunks.get(k, 0)))
        stamps.append(("EOF", t))
        text = "\n".join(f"{g}\t{v}" for g, v in stamps) + "\n"
        if extra_line:
            text += "603\t9999\n"
        if backwards:
            lines = text.splitlines()
            lines[10] = lines[10].split("\t")[0] + "\t1.0"
            text = "\n".join(lines) + "\n"
        file_base = os.path.join(raw, f"{rep}.{arm}")
        _write(file_base + ".stamps.tsv", text)
        _write(file_base + ".rc", rc + "\n")
        _write(file_base + ".wall", wall_text if (wall_text is not None and arm == "a") else f"{starts[arm]}\t{starts[arm] + walls[arm]}\n")
        _write(file_base + ".passed", passed + "\n")
        _write(file_base + ".range", (range_a if arm == "a" else f"{ranges[arm][0]}-{ranges[arm][1]}") + "\n")
    _write(os.path.join(raw, f"{rep}.guard.txt"), f"rep={rep} tree={tree}\nloadavg_start=1 1 1\n{'CLEAN' if clean else 'DISTURBED'}\n")


MIN_CHECKS = 47  # absolute floor on the assertions the selftest runs; raise it with the suite, never derive it


def selftest():
    fails = []
    ran = [0]

    def check(name, cond):
        ran[0] += 1
        if not cond:
            fails.append(name)

    # positive control: the recorder must record a false condition (reported without routing through it)
    check("control (deliberately false, removed below)", False)
    if not fails:
        print("SELFTEST FAIL: the check recorder does not record a failure")
        return 1
    fails.clear()

    D = Decimal
    base_costs = {1: D(5), 100: D("-0.010"), 150: D(1), 193: D(7), 194: D(3), 386: D(11), 387: D("2.5"), 602: D(9)}
    chunks = {150: 6}
    tmp = tempfile.mkdtemp(prefix="sct-", dir=os.environ.get("TMPDIR") or "/var/tmp")
    try:
        return _selftest_body(tmp, check, fails, ran, D, base_costs, chunks)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _selftest_body(tmp, check, fails, ran, D, base_costs, chunks):
    raw = os.path.join(tmp, "raw")
    os.makedirs(raw)
    # the three reps differ in site 1's cost, in the unconditional chunk at site 150 and in arm a's wall, so a median, a mean and a first-rep read differ
    for idx, (rep, c1, ch, wa) in enumerate((("r1", D(5), 6, 1010), ("r2", D(5), 6, 1000), ("r3", D(50), 20, 1000))):
        make_rep(raw, rep, {**base_costs, 1: c1}, base=idx * 10000, chunks={150: ch}, wall_a=wa)
    _write(os.path.join(raw, "sites.tsv"), "".join(f"{k}\tmutate\trow_{k}\n" for k in range(1, TOTAL + 1)))

    def golden(t):
        """Literal expectations (hand-computed, not generator-derived). Returns a list of violated items."""
        bad = []
        want_cost = {1: "5.000", 100: "0.000", 150: "1.000", 193: "7.000", 194: "3.000", 386: "11.000", 387: "2.500", 602: "9.000", 2: "0.000", 300: "0.000"}
        for k, v in want_cost.items():
            if f3(t["final"][k]["cost"]) != v:
                bad.append(f"cost[{k}]={f3(t['final'][k]['cost'])} want {v}")
        if f3(t["final"][100]["raw"]) != "-0.010":
            bad.append(f"raw[100]={f3(t['final'][100]['raw'])} want -0.010")
        for a, v in (("a", "987.010"), ("b", "486.000"), ("c", "388.500")):
            if f3(t["uncond"][a]) != v:
                bad.append(f"unconditional[{a}]={f3(t['uncond'][a])} want {v}")
        for k, v in ((1, 2), (386, 1), (602, 0)):
            if t["final"][k]["live"] != v:
                bad.append(f"others_live[{k}]={t['final'][k]['live']} want {v}")
        if t["final"][1]["row"] != "row_1" or t["final"][602]["arm"] != "c" or t["final"][193]["arm"] != "a" or t["final"][194]["arm"] != "b":
            bad.append("row/arm mapping")
        for k, v in ((602, "0.200"), (2, "0.010"), (1, "0.010")):
            if f3(t["final"][k]["noise"]) != v:
                bad.append(f"noise[{k}]={f3(t['final'][k]['noise'])} want {v}")
        if f3(t["final"][150]["nonowner"]) != "6.025":
            bad.append(f"nonowner[150]={f3(t['final'][150]['nonowner'])} want 6.025")
        for k, v in ((1, "-"), (100, "flag"), (150, "flag"), (602, "-")):
            if t["final"][k]["flag"] != v:
                bad.append(f"flag[{k}]={t['final'][k]['flag']} want {v}")
        return bad

    good = build(raw)
    gb = golden(good)
    check("golden on the real estimator: " + "; ".join(gb), not gb)
    text = render(good)
    lines = text.splitlines()
    check("render has 602 data rows", len([l for l in lines if re.match(r"\d+\t", l)]) == TOTAL)
    check("render header carries the unconditional shares", "# unconditional_s a=987.010 b=486.000 c=388.500" in lines)
    for hline in ("# tree=deadbeef", f"# DECLARED_TOTAL={TOTAL}", "# reps=r1,r2,r3", "# ranges a=1-193 b=194-386 c=387-602", "# wall_s a=1000.000 b=500.000 c=400.000"):
        check(f"render header line {hline!r}", hline in lines)
    check("render header carries the scope line", any(l.startswith("# scope:") for l in lines))
    # producer-consumer contract: what the builder renders is what the what-if reads and accepts
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import site_cost_whatif as wf
    contract = os.path.join(tmp, "contract.tsv")
    _write(contract, text)
    check("render -> site_cost_whatif.read_table -> check() reports no problem", wf.check(wf.read_table(contract)) == [])
    check("render row of site 1", "1\ta\trow_1\t5.000\t5.000\t0.010\t-\t2" in lines)
    check("render row of site 100 (negative raw kept, cost clamped)", "100\ta\trow_100\t0.000\t-0.010\t0.010\tflag\t2" in lines)
    by = render_by_rep(good).splitlines()
    check("by-rep row of site 1 shows each rep, outlier included", "1\ta\t5.000\t5.000\t50.000" in by)
    mutants = {
        "owner range shifted by 1": Opts(shift_owner=1),
        "stamp mapping k to k-1": Opts(off_by_one_stamp=True),
        "head folded into site 1": Opts(fold_head=True),
        "clamped raw_cost": Opts(clamp_raw=True),
        "mean instead of median": Opts(use_mean=True),
        "no subtraction of the non-owner median": Opts(no_subtraction=True),
    }
    for name, o in mutants.items():
        try:
            bad = golden(build(raw, opts=o))
        except Refusal as e:
            bad = [str(e)]
        check(f"mutant must go RED: {name}", bool(bad))
    # rounding of half-integer medians (two reps are the shipped case)
    for vals, want in (([1, 2], 2), ([0, 1], 1), ([2, 2], 2), ([0, 1, 1], 1), ([0, 0], 0)):
        check(f"round_half_up_median({vals}) == {want}", round_half_up_median(vals) == want)
    two = os.path.join(tmp, "two")
    os.makedirs(two)
    _write(os.path.join(two, "sites.tsv"), "".join(f"{k}\tmutate\trow_{k}\n" for k in range(1, TOTAL + 1)))
    for idx, rep in enumerate(("r1", "r2")):
        make_rep(two, rep, base_costs, base=idx * 10000, chunks=chunks)
    t2 = build(two)
    check("two-rep build: cost of site 193 is 7 and others_live of site 1 is 2", t2["final"][193]["cost"] == D(7) and t2["final"][1]["live"] == 2)
    # refusals: each must refuse FOR ITS REASON (the message is matched)
    cases = (
        ("DISTURBED guard", {"clean": False}, "does not end in CLEAN"),
        ("extra stamp line", {"extra_line": True}, "stamp lines"),
        ("time goes backwards", {"backwards": True}, "goes backwards"),
        ("arm exit status", {"rc": "1"}, "exit status is not 0"),
        ("unclean passed line", {"passed": "x: 9 passed, 1 failed, 10 assertions"}, "not a clean pass"),
        ("ranges that do not tile", {"range_a": "1-190"}, "do not tile"),
        ("malformed wall file", {"wall_text": "garbage\n"}, "malformed .wall"),
        ("non-finite wall file", {"wall_text": "nan nan\n"}, "malformed .wall"),
        ("wall file whose end is before its start", {"wall_text": "9 5\n"}, "malformed .wall"),
    )
    for label, kw, want in cases:
        d = os.path.join(tmp, "bad-" + label.replace(" ", "-"))
        os.makedirs(d)
        make_rep(d, "r1", base_costs, **kw)
        _write(os.path.join(d, "sites.tsv"), "")
        try:
            build(d)
            check(f"refusal expected: {label}", False)
        except Refusal as e:
            check(f"refusal for {label} names its reason ({want!r}): {e}", want in str(e))
    d = os.path.join(tmp, "bad-tree")
    os.makedirs(d)
    make_rep(d, "r1", base_costs, base=0)
    make_rep(d, "r2", base_costs, base=10000, tree="other")
    try:
        build(d)
        check("refusal expected: reps on different trees", False)
    except Refusal as e:
        check(f"refusal for different trees: {e}", "different trees" in str(e))
    for label, base2 in (("reps overlapping in time (all arms)", 100), ("reps overlapping only the longest arm of the first", 600)):
        d = os.path.join(tmp, "bad-overlap-" + str(base2))
        os.makedirs(d)
        make_rep(d, "r1", base_costs, base=0)
        make_rep(d, "r2", base_costs, base=base2)
        try:
            build(d)
            check(f"refusal expected: {label}", False)
        except Refusal as e:
            check(f"refusal for {label}: {e}", "overlap in time" in str(e))
    d = os.path.join(tmp, "abutting")  # the second rep starts exactly when the first one's longest arm ends: accepted
    os.makedirs(d)
    _write(os.path.join(d, "sites.tsv"), "".join(f"{k}\tmutate\trow_{k}\n" for k in range(1, TOTAL + 1)))
    make_rep(d, "r1", base_costs, base=0)
    make_rep(d, "r2", base_costs, base=1000)
    check("abutting reps are accepted", build(d)["reps"] == ["r1", "r2"])
    d = os.path.join(tmp, "equal-stamps")  # a skipped site whose consecutive stamps tie (microsecond clock) is accepted; only a decrease is refused
    os.makedirs(d)
    _write(os.path.join(d, "sites.tsv"), "".join(f"{k}\tmutate\trow_{k}\n" for k in range(1, TOTAL + 1)))
    make_rep(d, "r1", {**base_costs, 5: D("-0.025")}, base=0)
    check("equal consecutive stamps are accepted", build(d)["reps"] == ["r1"])
    d = os.path.join(tmp, "no-sites")
    os.makedirs(d)
    make_rep(d, "r1", base_costs)
    try:
        build(d)
        check("refusal expected: sites.tsv missing", False)
    except Refusal as e:
        check(f"refusal for a missing sites.tsv: {e}", "sites.tsv is missing" in str(e))
    d = os.path.join(tmp, "bad-sites-line")
    os.makedirs(d)
    make_rep(d, "r1", base_costs)
    _write(os.path.join(d, "sites.tsv"), "1\tmutate\n")
    try:
        build(d)
        check("refusal expected: malformed sites.tsv line", False)
    except Refusal as e:
        check(f"refusal for a malformed sites.tsv line: {e}", "malformed line" in str(e))
    d = os.path.join(tmp, "bad-empty")
    os.makedirs(d)
    try:
        build(d)
        check("refusal expected: no reps", False)
    except Refusal as e:
        check(f"refusal for no reps: {e}", "no *.guard.txt" in str(e))
    d = os.path.join(tmp, "bad-sites")
    os.makedirs(d)
    make_rep(d, "r1", base_costs)
    _write(os.path.join(d, "sites.tsv"), "1\tmutate\trow_1\n2\tmutate\trow_2\n3\tmutate\trow_3\n")
    try:
        build(d)
        check("refusal expected: sites map of the wrong size", False)
    except Refusal as e:
        check(f"refusal for a sites map of the wrong size: {e}", "maps 3 sites" in str(e))
    # the sites extractor: single-line call, multi-line call (row on the closing line), call without a row
    tf = os.path.join(tmp, "t.sh")
    _write(tf, "mutate m1 'old' 'new' row_alpha\now_mutate m2 $'a\nb' $'c\nd' row_beta\nmutate m3 'x' 'y'\nchk something\nmutate m4 'p' 'q' row_gamma\n"
              "mutate m5 'p' $'q\nr' row_delta   # a note after the row token\nmutate m6 'p' 'q' row_eps # trailing comment\n")
    check("sites_of reads single-line, multi-line, unlabelled and trailing-comment calls", sites_of(tf) ==
          "1\tmutate\trow_alpha\n2\tow_mutate\trow_beta\n3\tmutate\t?\n4\tmutate\trow_gamma\n5\tmutate\trow_delta\n6\tmutate\trow_eps\n")
    # exit status of a refusal through main()
    d = os.path.join(tmp, "bad-rc")
    os.makedirs(d)
    make_rep(d, "r1", base_costs, clean=False)
    quiet = io.StringIO()
    with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
        rc_bad = main(["x", d, os.path.join(tmp, "o.tsv")])
        rc_good = main(["x", raw, os.path.join(tmp, "o.tsv")])
    check("main() exits 2 on a DISTURBED rep", rc_bad == 2)
    check("main() exits 0 and writes both files on a good build", rc_good == 0
          and os.path.exists(os.path.join(tmp, "o.tsv")) and os.path.exists(os.path.join(tmp, "o.by_rep.tsv")))
    if fails:
        print("SELFTEST FAIL:\n  " + "\n  ".join(fails))
        return 1
    # floor: a check recorder that stops running is not a pass
    if ran[0] < MIN_CHECKS:
        print(f"SELFTEST FAIL: only {ran[0]} checks ran, floor is {MIN_CHECKS}")
        return 1
    print(f"site_cost_table.py selftest: {ran[0]} checks, golden ok, {len(mutants)} mutants red, {len(cases) + 7} refusals matched by reason, rc 2 on DISTURBED")
    return 0


def main(argv):
    try:
        if len(argv) == 2 and argv[1] == "--selftest":
            return selftest()
        if len(argv) == 3 and argv[1] == "--sites":
            sys.stdout.write(sites_of(argv[2]))
            return 0
        if len(argv) == 3:
            t = build(argv[1])
            _write(argv[2], render(t))
            root, ext = os.path.splitext(argv[2])
            _write(root + ".by_rep" + ext, render_by_rep(t))
            print(f"site_cost_table.py: wrote {argv[2]} ({t['total']} sites, reps {','.join(t['reps'])}, tree {t['tree']})")
            return 0
        print(__doc__)
        return 2
    except Refusal as e:
        print(f"site_cost_table.py: REFUSED: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
