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
  interval(arm, k) = stamp[k+1] - stamp[k]            (stamp[TOTAL+1] is EOF); the head 0->1 and the tail never enter a site
  raw_cost = interval(owner, k) - median(interval of the two non-owning arms)      (unclamped)
  noise_s  = |difference of the two non-owner intervals|
Across reps the per-site value is the MEDIAN (a mean would follow one disturbed outlier). cost = max(0, raw_cost).
unconditional_s(arm) = arm wall - sum of its owned raw_cost, so the predicted wall of an arm closes by construction.
"""
import glob
import os
import re
import sys
import tempfile
from decimal import Decimal, getcontext
from statistics import median

getcontext().prec = 28
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
        s, e = read_text(base + ".wall").split()
        arms[arm] = {
            "times": parse_stamps(base + ".stamps.tsv", total),
            "range": parse_range(read_text(base + ".range")),
            "wall": Decimal(e) - Decimal(s),
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
    comp = [(r, compute_rep(rp, total, opts)) for r, rp in loaded]
    rowmap = {}
    sites_path = os.path.join(raw, "sites.tsv")
    if os.path.exists(sites_path):
        for line in read_text(sites_path).splitlines():
            o, _kind, row = line.split("\t")
            rowmap[int(o)] = row
    final = {}
    for k in range(1, total + 1):
        raws = [c["sites"][k]["raw"] for _, c in comp]
        noises = [c["sites"][k]["noise"] for _, c in comp]
        nonown = [c["sites"][k]["nonowner"] for _, c in comp]
        lives = [c["sites"][k]["live"] for _, c in comp]
        raw = agg(raws, opts.use_mean)
        final[k] = {
            "arm": comp[0][1]["sites"][k]["owner"],
            "row": rowmap.get(k, "?"),
            "raw": raw,
            "cost": max(Decimal(0), raw),
            "noise": agg(noises, opts.use_mean),
            "nonowner": agg(nonown, opts.use_mean),
            "live": int(median(lives) + Decimal("0.5")) if not opts.use_mean else int(agg(lives, True)),
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
    n = 0
    out = []
    for line in read_text(test_file).splitlines():
        m = re.match(r"(mutate|ow_mutate) ", line)
        if not m:
            continue
        n += 1
        last = line.split()[-1]
        out.append(f"{n}\t{m.group(1)}\t{last if re.fullmatch(r'row_[A-Za-z0-9_]+', last) else '?'}")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- selftest
def _write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def make_rep(raw, rep, costs, clean=True, extra_line=False, backwards=False):
    """Synthetic rep. Every site: owner interval = true cost + 0.025, non-owners 0.020 and 0.030 (median 0.025).
    Head 0->1 is 4.0 s in arm a and 1.0 s elsewhere; the tail (site TOTAL->EOF) is 0.5 s for the two non-owners of site TOTAL."""
    starts = {"a": Decimal("1000.0"), "b": Decimal("1000.2"), "c": Decimal("1000.4")}
    ranges = {"a": (1, 193), "b": (194, 386), "c": (387, 602)}
    walls = {"a": Decimal("1000.0"), "b": Decimal("500.0"), "c": Decimal("400.0")}
    for arm in ARMS:
        t = starts[arm]
        stamps = [("0", t)]
        t += Decimal("4.0") if arm == "a" else Decimal("1.0")
        for k in range(1, TOTAL + 1):
            stamps.append((str(k), t))
            own = ranges[arm][0] <= k <= ranges[arm][1]
            others = [x for x in ARMS if x != arm]
            if own:
                c = costs.get(k, Decimal(0))
                step = c + (Decimal("0.5") if k == TOTAL else Decimal("0.025"))
            else:
                owner = [x for x in ARMS if ranges[x][0] <= k <= ranges[x][1]][0]
                rank = [x for x in ARMS if x != owner].index(arm)
                step = Decimal("0.5") if k == TOTAL else (Decimal("0.020") if rank == 0 else Decimal("0.030"))
            t += step
        stamps.append(("EOF", t))
        text = "\n".join(f"{g}\t{v}" for g, v in stamps) + "\n"
        if extra_line:
            text += "603\t9999\n"
        if backwards:
            lines = text.splitlines()
            lines[10] = lines[10].split("\t")[0] + "\t1.0"
            text = "\n".join(lines) + "\n"
        base = os.path.join(raw, f"{rep}.{arm}")
        _write(base + ".stamps.tsv", text)
        _write(base + ".rc", "0\n")
        _write(base + ".wall", f"{starts[arm]}\t{starts[arm] + walls[arm]}\n")
        _write(base + ".passed", "ci-pr-affected-replay.test.sh: 10 passed, 0 failed, 10 assertions, 3 mutants\n")
        _write(base + ".range", f"{ranges[arm][0]}-{ranges[arm][1]}\n")
    _write(os.path.join(raw, f"{rep}.guard.txt"), f"rep={rep} tree=deadbeef\nloadavg_start=1 1 1\n{'CLEAN' if clean else 'DISTURBED'}\n")


def selftest():
    fails = []

    def check(name, cond):
        if not cond:
            fails.append(name)

    D = Decimal
    base_costs = {1: D(5), 100: D("-0.010"), 193: D(7), 194: D(3), 386: D(11), 387: D("2.5"), 602: D(9)}
    # make site 100's owner interval 0.015 (raw -0.010): cost -0.010 + 0.025 = 0.015 — handled by costs[100] = -0.010
    tmp = tempfile.mkdtemp(prefix="sct-", dir=os.environ.get("TMPDIR") or "/var/tmp")
    raw = os.path.join(tmp, "raw")
    os.makedirs(raw)
    for rep, c1 in (("r1", D(5)), ("r2", D(5)), ("r3", D(50))):
        make_rep(raw, rep, {**base_costs, 1: c1})
    _write(os.path.join(raw, "sites.tsv"), "".join(f"{k}\tmutate\trow_{k}\n" for k in range(1, TOTAL + 1)))

    def golden(t):
        """Literal expectations (hand-computed, not generator-derived). Returns a list of violated items."""
        bad = []
        want_cost = {1: "5.000", 100: "0.000", 193: "7.000", 194: "3.000", 386: "11.000", 387: "2.500", 602: "9.000", 2: "0.000", 300: "0.000"}
        for k, v in want_cost.items():
            if f3(t["final"][k]["cost"]) != v:
                bad.append(f"cost[{k}]={f3(t['final'][k]['cost'])} want {v}")
        if f3(t["final"][100]["raw"]) != "-0.010":
            bad.append(f"raw[100]={f3(t['final'][100]['raw'])} want -0.010")
        for a, v in (("a", "988.010"), ("b", "486.000"), ("c", "388.500")):
            if f3(t["uncond"][a]) != v:
                bad.append(f"unconditional[{a}]={f3(t['uncond'][a])} want {v}")
        if t["final"][1]["live"] != 2:
            bad.append(f"others_live[1]={t['final'][1]['live']} want 2")
        if t["final"][1]["row"] != "row_1" or t["final"][602]["arm"] != "c" or t["final"][193]["arm"] != "a" or t["final"][194]["arm"] != "b":
            bad.append("row/arm mapping")
        return bad

    good = build(raw)
    gb = golden(good)
    check("golden on the real estimator: " + "; ".join(gb), not gb)
    text = render(good)
    check("render has 602 data rows", len([l for l in text.splitlines() if re.match(r"\d+\t", l)]) == TOTAL)
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
    # refusals
    for label, kw in (("DISTURBED guard", {"clean": False}), ("extra stamp line", {"extra_line": True}), ("time goes backwards", {"backwards": True})):
        d = os.path.join(tmp, "bad-" + label.split()[0])
        os.makedirs(d)
        make_rep(d, "r1", base_costs, **kw)
        try:
            build(d)
            check(f"refusal expected: {label}", False)
        except Refusal:
            pass
    # exit status of a refusal through main()
    d = os.path.join(tmp, "bad-rc")
    os.makedirs(d)
    make_rep(d, "r1", base_costs, clean=False)
    check("main() exits 2 on a DISTURBED rep", main(["x", d, os.path.join(tmp, "o.tsv")]) == 2)
    if fails:
        print("SELFTEST FAIL:\n  " + "\n  ".join(fails))
        return 1
    print(f"site_cost_table.py selftest: golden ok, {len(mutants)} mutants red, 3 refusals, rc 2 on DISTURBED")
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
