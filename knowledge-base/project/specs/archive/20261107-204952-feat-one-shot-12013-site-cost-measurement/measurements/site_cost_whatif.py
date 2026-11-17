#!/usr/bin/env python3
"""site_cost_whatif.py — validation, paper check and #12263 pricing on the measured site-cost table (Ref #12013).

Usage (run with `python3 -I`):
  site_cost_whatif.py --check <site_costs.tsv>
  site_cost_whatif.py <site_costs.tsv> <launch_order.t1.tsv> <launch_order.control2.tsv> [--derived t1=216,control2=234]
  site_cost_whatif.py --selftest

Model (a direction check, never a result): list schedule, width 4, lane tokens ignored, the suites that ran ALONE at the end
(the `*` drain-barrier suites) removed, jobs launched in start-time order of the archived t1 reading. The three replay arms are
re-priced from the table; every other suite keeps its measured wall. Pooled arm wall = s * (U + sum of raw cost of sites that had
another arm live) + sum of raw cost of sites with no other arm live, where s is fitted on arms b and c of the FIRST archived reading
(t1; its control2 value is printed, not used) and the part with no other arm live is taken at ratio 1.0.

What the table and the model describe: the 602-site tree the readings were taken on and the archived t1 launch order. They are NOT a
model of main after the observation-window retirement (473 sites).

The archived readings ran 599 gated sites with arms 1-193 / 194-386 / 387-599; the table is on the current 602 ordinals, so the
archived arms are rebuilt in current ordinals: old ordinal o is current ordinal o if o < FIRST_ADDED else o + len(ADDED) (sites 127-129
were added after the readings).
"""
import heapq
import itertools
import os
import re
import sys
from statistics import median

NAME = "site_cost_whatif.py"
TOTAL = 602  # DECLARED_TOTAL of the tree the table was measured on
WIDTH = 4
GATE_NOMINAL_S = 60.0
ARM_LABELS = ["plugins/soleur/test/ci-pr-affected-replay-a", "plugins/soleur/test/ci-pr-affected-replay-b", "plugins/soleur/test/ci-pr-affected-replay-c"]
APPROVAL = "apps/web-platform/test/approval-guard1-mutation"
LONG3 = [APPROVAL, "apps/web-platform/test/argv-bearer-sweep", "apps/web-platform/test/destroy-ask-mutation"]
APPROVAL_WALLS = (666.0, 880.0, 1080.0)  # the three archived approval-guard1-mutation walls (#12263 body, control2, t1); ruling R4
ARM_PERT = (-0.15, 0.0, 0.15)
ADDED = (127, 128, 129)
FIRST_ADDED = ADDED[0]
OLD_RANGES = {"a": (1, 193), "b": (194, 386), "c": (387, 599)}
ARMS = ("a", "b", "c")
MIN_CHECKS = 74  # absolute floor on the assertions the selftest runs; raise it with the suite, never derive it


def p(msg):
    print(f"{NAME}: {msg}")


# ------------------------------------------------------------------ table
class Table:
    pass


def read_table(path):
    t = Table()
    t.tree = None
    t.total = None
    t.uncond = {}
    t.ranges = {}
    t.rows = []
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    for line in lines:
        if line.startswith("# tree="):
            t.tree = line.split("=", 1)[1].strip()
        elif line.startswith("# DECLARED_TOTAL="):
            t.total = int(line.split("=", 1)[1])
        elif line.startswith("# unconditional_s "):
            t.uncond = {k: float(v) for k, v in (kv.split("=") for kv in line.split()[2:])}
        elif line.startswith("# ranges "):
            t.ranges = {k: tuple(int(x) for x in v.split("-")) for k, v in (kv.split("=") for kv in line.split()[2:])}
        elif line.startswith("#") or line.startswith("site\t"):
            continue
        elif line.strip():
            c = line.split("\t")
            t.rows.append({"site": int(c[0]), "arm": c[1], "row": c[2], "cost": float(c[3]), "raw": float(c[4]), "noise": float(c[5]),
                           "flag": c[6], "live": int(c[7])})
    return t


def check(t):
    """Validity assertions; returns a list of problems (empty = valid)."""
    bad = []
    if not t.tree:
        bad.append("header lacks '# tree='")
    if t.total != TOTAL:
        bad.append(f"header DECLARED_TOTAL={t.total}, expected {TOTAL}")
    if sorted(t.uncond) != list(ARMS):
        bad.append("header lacks unconditional_s for every arm")
    if len(t.rows) != TOTAL:
        bad.append(f"{len(t.rows)} data rows, expected {TOTAL}")
    if [r["site"] for r in t.rows] != list(range(1, len(t.rows) + 1)):
        bad.append("site ordinals are not 1..N in order")
    spans = sorted(t.ranges.values())
    nxt = 1
    for lo, hi in spans:
        if lo != nxt:
            bad.append(f"ranges do not tile 1..{TOTAL}: {spans}")
            break
        nxt = hi + 1
    else:
        if nxt != TOTAL + 1:
            bad.append(f"ranges end at {nxt - 1}, expected {TOTAL}")
    for r in t.rows:
        if r["cost"] < 0:
            bad.append(f"site {r['site']} has a negative cost")
            break
    unlabelled = [r["site"] for r in t.rows if r["row"] == "?"]
    if unlabelled:
        bad.append(f"{len(unlabelled)} unlabelled rows (first: site {unlabelled[0]}): the pristine-row model would pool them into one pseudo-row")
    for r in t.rows:
        lo, hi = t.ranges.get(r["arm"], (0, -1))
        if not lo <= r["site"] <= hi:
            bad.append(f"site {r['site']} is labelled arm {r['arm']} outside its range")
            break
    return bad


def read_by_rep(path):
    rows = {}
    reps = []
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if line.startswith("# raw_cost_s per rep:"):
                reps = line.split(":", 1)[1].strip().split(",")
            elif line.startswith("#") or line.startswith("site\t"):
                continue
            elif line.strip():
                c = line.split("\t")
                rows[int(c[0])] = (c[1], [float(x) for x in c[2:]])
    return reps, rows


# ------------------------------------------------------------------ launch orders
def read_launch(path):
    jobs = []
    engaged = None
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if line.startswith("#"):
                m = re.search(r"engaged_at_s=([0-9.]+)", line)
                if m:
                    engaged = float(m.group(1))
                continue
            c = line.split("\t")
            jobs.append({"label": c[0], "start": float(c[1]) - engaged, "done": float(c[2]) - engaged, "wall": float(c[3]) / 1000.0})
    jobs.sort(key=lambda j: (j["start"], j["label"]))
    return jobs


def drain_suites(jobs):
    """Suites whose interval overlaps no other suite's interval: they ran alone (the `*` drain-barrier suites)."""
    alone = set()
    for i, a in enumerate(jobs):
        if all(not (a["start"] < b["done"] and b["start"] < a["done"]) for j, b in enumerate(jobs) if j != i):
            alone.add(a["label"])
    return alone


def schedule(walls_in_order):
    """Return (pool_end, starts, last_label) of a width-4 list schedule over [(label, wall)] in launch order."""
    free = [0.0] * WIDTH
    heapq.heapify(free)
    starts = {}
    end = 0.0
    last = None
    for label, w in walls_in_order:
        t = heapq.heappop(free)
        starts[label] = t
        e = t + w
        if e > end:
            end, last = e, label
        heapq.heappush(free, e)
    return end, starts, last


def start_of(jobs, label):
    for j in jobs:
        if j["label"] == label:
            return j["start"]
    return float("nan")


# ------------------------------------------------------------------ arm walls from the table
class Model:
    """Per-site pooled cost under a contention scale, with prefix sums for O(1) arm walls.

    With the pristine charge, the first site of each (baseline arm, row) has its pristine cost taken out, and a candidate arm pays the
    row's pristine cost once for every row it holds (attached to the first such site's baseline arm and live flag). For the baseline
    split the two cancel exactly, so both variants give the baseline the same walls."""

    def __init__(self, t, scale, perturb=None, pristine=False, prist_row=None):
        self.t = t
        n = len(t.rows)
        self.n = n
        pert = perturb or {a: 0.0 for a in ARMS}
        self.U = {a: t.uncond[a] * (1 + pert[a]) for a in ARMS}
        self.pooled = [0.0] * (n + 1)
        first_of = {}
        for r in t.rows:
            first_of.setdefault((r["arm"], r["row"]), r["site"])
        for r in t.rows:
            k = r["site"]
            raw = r["raw"] * (1 + pert[r["arm"]])
            if pristine and first_of[(r["arm"], r["row"])] == k:
                raw -= prist_row.get(r["row"], 0.0) * (1 + pert[r["arm"]])
            self.pooled[k] = raw * (scale if r["live"] > 0 else 1.0)
        self.prefix = list(itertools.accumulate(self.pooled))
        self.scale = scale
        self.pristine = pristine
        self.prist_row = prist_row or {}
        if pristine:
            self._charge = self._build_charge(pert)

    def _build_charge(self, pert):
        """charge[(lo, hi)] = pristine cost of the rows present in [lo, hi], each paid once."""
        site_row = [None] + [r["row"] for r in self.t.rows]
        site_w = [None] + [(1 + pert[r["arm"]]) * (self.scale if r["live"] > 0 else 1.0) for r in self.t.rows]
        charge = {}
        for lo in range(1, self.n + 1):
            seen = set()
            acc = 0.0
            for hi in range(lo, self.n + 1):
                row = site_row[hi]
                if row not in seen:
                    seen.add(row)
                    acc += self.prist_row.get(row, 0.0) * site_w[hi]
                charge[(lo, hi)] = acc
        return charge

    def wall(self, arm, lo, hi):
        w = self.U[arm] * self.scale + (self.prefix[hi] - self.prefix[lo - 1])
        if self.pristine:
            w += self._charge[(lo, hi)]
        return w


def estimate_pristine(t):
    """Per-row pristine cost: first site of a row in an arm minus the median of its other sites there (>= 0); a row with no arm
    holding two of its sites takes the largest estimate observed (an arbitrary but conservative fallback: for a row that sits in one
    arm the subtraction and the charge cancel exactly in the baseline, so it only matters for a candidate split that cuts such a row)."""
    est = {}
    by = {}
    for r in t.rows:
        by.setdefault((r["arm"], r["row"]), []).append(r["raw"])
    for (arm, row), vals in by.items():
        if len(vals) >= 2:
            est.setdefault(row, []).append(max(0.0, vals[0] - median(vals[1:])))
    out = {row: median(v) for row, v in est.items()}
    mx = max(out.values()) if out else 0.0
    for r in t.rows:
        out.setdefault(r["row"], mx)
    return out


def arm_walls_for(model, split):
    x, y = split
    return [model.wall("a", 1, x), model.wall("b", x + 1, y), model.wall("c", y + 1, model.n)]


def pool_end_for(walls, rest, long_first=None, approval_wall=None):
    """Pool end of the three arms (first in the launch order) plus `rest`; `long_first` hoists those suites right after the arms."""
    jobs = list(zip(ARM_LABELS, walls))
    rest = [(l, (approval_wall if (approval_wall is not None and l == APPROVAL) else w)) for l, w in rest]
    if long_first:
        order = jobs + [j for j in rest if j[0] in long_first] + [j for j in rest if j[0] not in long_first]
    else:
        order = jobs + rest
    return schedule(order)


def best_split(model, rest, long_first=None, approval_wall=None):
    """Best contiguous split by pool end. The prune is exact: the pool end is at least the longest arm wall."""
    n = model.n
    cands = []
    for x in range(1, n - 1):
        for y in range(x + 1, n):
            w = arm_walls_for(model, (x, y))
            cands.append((max(w), x, y, w))
    cands.sort()
    best = None
    for lb, x, y, w in cands:
        if best is not None and lb >= best[0]:
            break
        end, _, _ = pool_end_for(w, rest, long_first, approval_wall)
        if best is None or end < best[0] or (end == best[0] and lb < best[4]):
            best = (end, x, y, w, lb)
    return best


# ------------------------------------------------------------------ verdict
def decide(valid, model_ok, nominal_off, nominal_on, robust_off, robust_on, nominal_sf_on=None, sf_ok=False):
    """GATE line text from the measured facts. nominal_* are gains in seconds in the ordering of the archived t1 reading."""
    if not valid:
        return "GATE: NO-REBALANCE (table does not support a rebalance)"
    if not model_ok:
        return "GATE: NO-REBALANCE (model does not reproduce the archived readings; check void)"
    gating_ok = (nominal_off >= GATE_NOMINAL_S and nominal_on >= GATE_NOMINAL_S and robust_off >= 0 and robust_on >= 0)
    if gating_ok:
        return "GATE: PROCEED"
    if sf_ok and nominal_sf_on is not None and nominal_sf_on >= GATE_NOMINAL_S:
        return "GATE: NO-REBALANCE (start-first only)"
    return "GATE: NO-REBALANCE"


def robust_min(table, scale, rest, splits, base_split, prist, pristine, long_first=None, with_approval=True):
    """Minimum over the perturbation combinations (and splits) of (baseline pool end - candidate pool end), paired.
    Scale factors attach to the BASELINE arm that owns each site, identically for baseline and candidate."""
    worst = None
    walls = APPROVAL_WALLS if with_approval else (None,)
    for pa, pb, pc in itertools.product(ARM_PERT, repeat=3):
        m = Model(table, scale, {"a": pa, "b": pb, "c": pc}, pristine, prist)
        for aw in walls:
            e0, _, _ = pool_end_for(arm_walls_for(m, base_split), rest, long_first, aw)
            for split in splits:
                e1, _, _ = pool_end_for(arm_walls_for(m, split), rest, long_first, aw)
                g = e0 - e1
                if worst is None or g < worst:
                    worst = g
    return worst


def candidates_of(results):
    """The splits that would land: the best split of the uncharged model and the best split of the charged one (t1 order)."""
    return sorted({results[("t1-order", False)][2], results[("t1-order", True)][2]})


def gate_for(t, scale, rest, prist, base, cands, pristine):
    """(minimum nominal gain, minimum paired gain over the perturbation combinations) over ALL candidate splits under one pristine model."""
    m = Model(t, scale, None, pristine, prist)
    e0, _, _ = pool_end_for(arm_walls_for(m, base), rest)
    gains = [e0 - pool_end_for(arm_walls_for(m, s), rest)[0] for s in cands]
    return min(gains), robust_min(t, scale, rest, cands, base, prist, pristine)


def base_split_of(t):
    return (t.ranges["a"][1], t.ranges["b"][1])


# ------------------------------------------------------------------ validation of the table (plan 4.2)
def t1_arm_sites(_t=None):
    """Current ordinals of the sites each archived arm ran (599-site era): old ordinal o is o below FIRST_ADDED, else o + len(ADDED)."""
    def cur(o):
        return o if o < FIRST_ADDED else o + len(ADDED)
    return {a: [cur(o) for o in range(lo, hi + 1)] for a, (lo, hi) in OLD_RANGES.items()}


def fit_scale(t, jobs_by_label):
    sites = t1_arm_sites(t)
    rows = {r["site"]: r for r in t.rows}
    out = {}
    for a, lab in zip(ARMS, ARM_LABELS):
        pred = t.uncond[a] + sum(rows[k]["raw"] for k in sites[a])
        out[a] = (jobs_by_label[lab]["wall"], pred)
    return out, out["b"][0] / out["b"][1], out["c"][0] / out["c"][1]


def validation(t, by_rep, readings):
    """Returns (ok, lines, scale). readings: {name: jobs_by_label}; the scale of the first reading is the one used."""
    ok = True
    lines = []
    rows = {r["site"]: r for r in t.rows}
    scale = None
    for name, jb in readings.items():
        out, rb, rc = fit_scale(t, jb)
        spread = abs(rb - rc) / max(rb, rc)
        s = (rb + rc) / 2
        lines.append(f"validation {name}: pooled/predicted b={rb:.3f} c={rc:.3f} spread={spread * 100:.1f}% (limit 10%) scale={s:.3f}")
        if spread > 0.10:
            ok = False
        sites = t1_arm_sites(t)
        ov = sum(rows[k]["raw"] for k in sites["a"] if rows[k]["live"] > 0)
        al = sum(rows[k]["raw"] for k in sites["a"] if rows[k]["live"] == 0)
        pred_a = s * (t.uncond["a"] + ov) + al
        meas_a = out["a"][0]
        err = abs(pred_a - meas_a) / meas_a
        lines.append(f"validation {name}: arm a alone_s={al:.1f} overlapped_s={ov:.1f} predicted_pooled_s={pred_a:.1f} archived_s={meas_a:.1f} error={err * 100:.1f}% (limit 15%)")
        if err > 0.15:
            ok = False
        if scale is None:
            scale = s
            lines.append(f"validation: the scale of reading {name} ({s:.3f}) is the one the model uses")
    flagged = [r["site"] for r in t.rows if r["flag"] == "flag"]
    lines.append(f"validation flagged sites ({len(flagged)}): {flagged}")
    for a in ARMS:
        owned = [r for r in t.rows if r["arm"] == a]
        tot = sum(max(0.0, r["raw"]) for r in owned)
        fl = sum(max(0.0, r["raw"]) for r in owned if r["flag"] == "flag")
        share = fl / tot if tot else 0.0
        lines.append(f"validation flagged sites arm {a}: {sum(1 for r in owned if r['flag'] == 'flag')} of {len(owned)}, holding {share * 100:.1f}% of raw site-seconds (limit 20%)")
        if share > 0.20:
            ok = False
    # split-half stability: fails closed when the per-rep file is missing or holds fewer than two reps
    reps, brows = by_rep if by_rep is not None else ([], {})
    if len(reps) < 2:
        lines.append("validation split-half and rep-disagreement: FAILED (fail closed): the per-rep file is missing or holds fewer than two reps")
        return False, lines, scale
    tarm = {r["site"]: r["arm"] for r in t.rows}
    if set(brows) != set(tarm) or any(brows[k][0] != tarm[k] or len(brows[k][1]) != len(reps) for k in brows):
        lines.append("validation split-half and rep-disagreement: FAILED (fail closed): the per-rep file does not cover exactly the table's sites, arms and reps")
        return False, lines, scale
    label = "/".join(reps[:2]) if len(reps) == 2 else ",".join(reps)
    for a in ARMS:
        ords = [k for k in sorted(brows) if brows[k][0] == a]
        n = len(ords)
        if n == 0:
            lines.append(f"validation split-half arm {a}: FAILED (fail closed): the per-rep file holds no site of this arm")
            ok = False
            continue
        blocks = [[] for _ in range(10)]
        for i, k in enumerate(ords):
            blocks[i * 10 // n].append(k)
        armtots = [sum(max(0.0, brows[k][1][i]) for k in ords) or 1.0 for i in range(len(reps))]
        bad = []
        sums = [[sum(brows[k][1][i] for k in blk) for blk in blocks] for i in range(len(reps))]
        # a block is material when it holds at least 5% of the arm's raw seconds in ANY rep
        material = [j for j in range(len(blocks)) if any(sums[i][j] >= 0.05 * armtots[i] for i in range(len(reps)))]
        for j in material:
            vals = [sums[i][j] for i in range(len(reps))]
            if (max(vals) - min(vals)) / max(abs(max(vals)), 1e-9) > 0.20:
                bad.append(j)
        order = [sorted(material, key=lambda j, i=i: sums[i][j]) for i in range(len(reps))]
        rank_ok = all(o == order[0] for o in order)
        lines.append(f"validation split-half arm {a}: {len(material)} material blocks, unstable blocks={bad}, rank order {'equal' if rank_ok else 'DIFFERS'}")
        if bad or not rank_ok:
            ok = False
    unstable = {k for k, (a, v) in brows.items() if (max(v) - min(v)) > max(2.0, 0.25 * max(abs(x) for x in v))}
    for a in ARMS:
        owned = [k for k, (aa, v) in brows.items() if aa == a]
        tot = sum(max(0.0, rows[k]["raw"]) for k in owned) or 1.0
        u = sum(max(0.0, rows[k]["raw"]) for k in owned if k in unstable)
        lines.append(f"validation rep-disagreement arm {a}: sites with {label} cost differing by more than max(2 s, 25%) hold {u / tot * 100:.1f}% of raw site-seconds (limit 20%)")
        if u / tot > 0.20:
            ok = False
    return ok, lines, scale


# ------------------------------------------------------------------ report
def report(table_path, t1_path, c2_path, derived):
    t = read_table(table_path)
    bad = check(t)
    if bad:
        for b in bad:
            p("CHECK FAIL: " + b)
        print("GATE: NO-REBALANCE (table does not support a rebalance)")
        return 2
    p(f"check ok: {TOTAL} rows, ranges {t.ranges}, tree {t.tree}")
    p(f"scope: the table is the {TOTAL}-site tree above and the launch order is the archived t1 reading; this is not a model of main after the observation-window retirement")
    by_path = table_path.rsplit(".", 1)[0] + ".by_rep.tsv"
    by_rep = read_by_rep(by_path) if os.path.exists(by_path) else None
    j1 = read_launch(t1_path)
    j2 = read_launch(c2_path)
    readings = {"t1": {j["label"]: j for j in j1}, "control2": {j["label"]: j for j in j2}}
    alone = {"t1": drain_suites(j1), "control2": drain_suites(j2)}
    for name, jl in (("t1", j1), ("control2", j2)):
        floor = sum(j["wall"] for j in jl) / WIDTH
        cd = derived.get(name)
        extra = f"; with cold derive {cd:.0f} s: {floor + cd:.0f} s" if cd else ""
        p(f"packing floor {name}: sum of walls {sum(j['wall'] for j in jl):.0f} s / {WIDTH} = {floor:.0f} s{extra} (bar 600 s)")
    # model reproduction on the archived readings with measured walls
    model_ok = True
    for name, jl in (("t1", j1), ("control2", j2)):
        body = [(j["label"], j["wall"]) for j in jl if j["label"] not in alone[name]]
        end, starts, last = schedule(body)
        meas_end = max(j["done"] for j in jl if j["label"] not in alone[name])
        p(f"model {name}: removed drain suites {sorted(alone[name])}; modelled pool end {end:.0f} s, archived {meas_end:.0f} s; "
          f"{APPROVAL.split('/')[-1]} start modelled {starts.get(APPROVAL, float('nan')):.0f} s archived {start_of(jl, APPROVAL):.0f} s; run ends on {last}")
        if name == "t1":  # control2 ran the old star barrier, whose post-barrier drain is not modelled: only its approval end is compared below
            if abs(end - meas_end) > 15 or abs(starts[APPROVAL] - start_of(jl, APPROVAL)) > 15:
                model_ok = False
    body1 = [(j["label"], j["wall"]) for j in j1 if j["label"] not in alone["t1"]]
    c2_walls = readings["control2"]
    _, starts_x, _ = schedule([(l, c2_walls[l]["wall"]) for l, _ in body1 if l in c2_walls])
    ap_end = starts_x[APPROVAL] + c2_walls[APPROVAL]["wall"]
    ap_want = c2_walls[APPROVAL]["done"]
    p(f"model: t1 order with control2 walls puts {APPROVAL.split('/')[-1]} ending at {ap_end:.0f} s, archived control2 {ap_want:.0f} s")
    if abs(ap_end - ap_want) > 15:
        model_ok = False
    p(f"model reproduction {'ok' if model_ok else 'FAILED'} (limit 15 s; control2's own pool end is not compared: it ran the old star barrier)")
    ok, vlines, scale = validation(t, by_rep, readings)
    for l in vlines:
        p(l)
    p(f"validation {'passed' if ok else 'FAILED: the table does not support a rebalance'}")
    scale = scale or 1.0
    # gate search on the t1 order
    rest = [(l, w) for l, w in body1 if l not in ARM_LABELS]
    prist = estimate_pristine(t)
    base = base_split_of(t)
    n_combo = len(ARM_PERT) ** 3 * len(APPROVAL_WALLS)
    p(f"robustness: arm perturbations {ARM_PERT} each x approval-guard1-mutation walls {APPROVAL_WALLS} s = {n_combo} paired combinations "
      f"(666 s: the #12263 issue body; 880 s: archived control2; 1080 s: archived t1)")
    results = {}
    for ordering, long_first in (("t1-order", None), ("start-first", LONG3)):
        for pristine in (False, True):
            m = Model(t, scale, None, pristine, prist)
            e0, _, last0 = pool_end_for(arm_walls_for(m, base), rest, long_first)
            end, x, y, w, _ = best_split(m, rest, long_first)
            rob = robust_min(t, scale, rest, [(x, y)], base, prist, pristine, long_first)
            results[(ordering, pristine)] = (e0, end, (x, y), rob)
            p(f"{ordering} pristine_charge={'on' if pristine else 'off'}: baseline pool end {e0:.0f} s (ends on {last0.split('/')[-1]}); best split "
              f"1-{x} / {x + 1}-{y} / {y + 1}-{TOTAL} arm walls {w[0]:.0f}/{w[1]:.0f}/{w[2]:.0f}; pool end {end:.0f} s; nominal gain {e0 - end:.0f} s; "
              f"min paired gain over {n_combo} combinations {rob:.0f} s")
    # the split that would land must clear the bar under BOTH pristine models: cross-evaluate both candidate splits under both models
    cands = candidates_of(results)
    gate = {}
    for pristine in (False, True):
        gate[pristine] = gate_for(t, scale, rest, prist, base, cands, pristine)
        p(f"gate pristine_charge={'on' if pristine else 'off'}: candidate splits {cands}; minimum nominal gain {gate[pristine][0]:.0f} s; minimum paired gain {gate[pristine][1]:.0f} s")
    sf_on = results[("start-first", True)][0] - results[("start-first", True)][1]
    sf_ok = results[("start-first", True)][3] >= 0 and results[("start-first", False)][3] >= 0
    # #12263 pricing (paper only)
    floor = sum(w for _, w in body1) / WIDTH
    e_main, _, last_main = schedule(body1)
    e_ap, _, last_ap = schedule([x for x in body1 if x[0] == APPROVAL] + [x for x in body1 if x[0] != APPROVAL])
    e_l3, _, last_l3 = schedule([x for x in body1 if x[0] in LONG3] + [x for x in body1 if x[0] not in LONG3])
    p(f"#12263 pricing t1 (measured walls, drain suites removed): packing floor {floor:.0f} s; order as run {e_main:.0f} s (ends on {last_main.split('/')[-1]}); "
      f"{APPROVAL.split('/')[-1]} first {e_ap:.0f} s (gap to floor {e_ap - floor:.0f} s, ends on {last_ap.split('/')[-1]}); "
      f"three long suites first {e_l3:.0f} s (gap to floor {e_l3 - floor:.0f} s, ends on {last_l3.split('/')[-1]})")
    print(decide(ok, model_ok, gate[False][0], gate[True][0], gate[False][1], gate[True][1], sf_on, sf_ok))
    return 0


# ------------------------------------------------------------------ selftest
def _toy_table(costs_a=(10, 10, 10), costs_b=(5, 5), costs_c=(5,), live=0, uncond=0.0):
    t = Table()
    t.tree = "toy"
    t.total = 6
    sites = list(costs_a) + list(costs_b) + list(costs_c)
    arms = ["a"] * len(costs_a) + ["b"] * len(costs_b) + ["c"] * len(costs_c)
    t.ranges = {"a": (1, len(costs_a)), "b": (len(costs_a) + 1, len(costs_a) + len(costs_b)), "c": (len(sites), len(sites))}
    t.uncond = {a: uncond for a in ARMS}
    t.rows = [{"site": i + 1, "arm": arms[i], "row": f"row{i}", "cost": float(c), "raw": float(c), "noise": 0.0, "flag": "-", "live": live}
              for i, c in enumerate(sites)]
    return t


def _synthetic_validation_inputs(raw=1.0, u=100.0, scale=1.2, a_factor=1.0, c_factor=1.0, reps=("x", "y"), rep_values=(1.0, 1.0),
                                 rep_fn=None, live_alone=0, scale2=None):
    """A 602-row table and archived walls consistent with `scale` on arms b and c; arm a's archived wall is a_factor times its prediction.
    rep_fn(k, arm, i_in_arm) -> per-rep values replaces rep_values; live_alone makes the first N sites of arm a run with no other arm live;
    scale2 adds a second reading ('other') built with that scale."""
    t = Table()
    t.tree, t.total = "synthetic", TOTAL
    t.ranges = {"a": (1, 193), "b": (194, 386), "c": (387, TOTAL)}
    t.uncond = {a: u for a in ARMS}
    t.rows = [{"site": k, "arm": a, "row": f"r{k}", "cost": raw, "raw": raw, "noise": 0.0, "flag": "-", "live": 1}
              for a, (lo, hi) in t.ranges.items() for k in range(lo, hi + 1)]
    t.rows.sort(key=lambda r: r["site"])
    sites = t1_arm_sites()
    pred = {a: u + raw * len(sites[a]) for a in ARMS}
    walls = {"a": scale * pred["a"] * a_factor, "b": scale * pred["b"], "c": scale * pred["c"] * c_factor}
    jobs = {lab: {"wall": walls[a]} for a, lab in zip(ARMS, ARM_LABELS)}
    for r in t.rows[:live_alone]:
        r["live"] = 0
    idx = {a: 0 for a in ARMS}
    by_rep_rows = {}
    for r in t.rows:
        by_rep_rows[r["site"]] = (r["arm"], list(rep_fn(r["site"], r["arm"], idx[r["arm"]])) if rep_fn else list(rep_values))
        idx[r["arm"]] += 1
    by_rep = (list(reps), by_rep_rows) if reps else None
    readings = {"t1": jobs}
    if scale2 is not None:
        readings["other"] = {lab: {"wall": scale2 * pred[a] * (a_factor if a == "a" else 1.0)} for a, lab in zip(ARMS, ARM_LABELS)}
    return t, by_rep, readings


def _write_table(path, t):
    """Render a Table in the format site_cost_table.py writes (the consumer's input)."""
    out = [f"# tree={t.tree}", f"# DECLARED_TOTAL={t.total}", "# reps=x,y",
           "# ranges " + " ".join(f"{a}={t.ranges[a][0]}-{t.ranges[a][1]}" for a in ARMS),
           "# unconditional_s " + " ".join(f"{a}={t.uncond[a]:.3f}" for a in ARMS), "site\tarm\trow\tcost_s\traw_cost_s\tnoise_s\tflag\tothers_live"]
    out += [f"{r['site']}\t{r['arm']}\t{r['row']}\t{r['cost']:.3f}\t{r['raw']:.3f}\t{r['noise']:.3f}\t{r['flag']}\t{r['live']}" for r in t.rows]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def _write_by_rep(path, by_rep):
    reps, rows = by_rep
    out = ["# raw_cost_s per rep: " + ",".join(reps), "site\tarm\t" + "\t".join(reps)]
    out += [f"{k}\t{a}\t" + "\t".join(f"{v:.3f}" for v in vals) for k, (a, vals) in sorted(rows.items())]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def _write_launch(path, arm_walls):
    """A launch-order file produced by the model's own scheduler: three arms, the approval suite, two more long suites, ten fillers, then a lone drain suite."""
    jobs = list(zip(ARM_LABELS, arm_walls)) + [(APPROVAL, 300.0), (LONG3[1], 200.0), (LONG3[2], 150.0)] + [(f"filler/{i}", 40.0) for i in range(10)]
    end, starts, _ = schedule(jobs)
    rows = [(lab, starts[lab], starts[lab] + w, w) for lab, w in jobs] + [("drain/alone", end + 5.0, end + 8.0, 3.0)]
    with open(path, "w", encoding="utf-8") as f:
        f.write("# reading=synthetic engaged_at_s=0\n")
        f.write("".join(f"{lab}\t{s0:.3f}\t{d:.3f}\t{int(w * 1000)}\t0\n" for lab, s0, d, w in rows))


def selftest():
    fails = []
    ran = [0]

    def ck(name, cond):
        ran[0] += 1
        if not cond:
            fails.append(name)

    # positive control: the recorder must record a false condition (reported without routing through it)
    ck("control (deliberately false, removed below)", False)
    if not fails:
        print("SELFTEST FAIL: the check recorder does not record a failure")
        return 1
    fails.clear()

    # 3-arm toy, hand-checked: costs a=[10,10,10] b=[5,5] c=[5]; walls 30/10/5; best split 1-2 / 3-4 / 5-6 gives 20/15/10
    t = _toy_table()
    m = Model(t, 1.0)
    base = (3, 5)
    ck("toy baseline walls 30/10/5", [round(x) for x in arm_walls_for(m, base)] == [30, 10, 5])
    ck("toy 1-2/3-4/5-6 walls 20/15/10", [round(x) for x in arm_walls_for(m, (2, 4))] == [20, 15, 10])
    best = best_split(m, [])
    ck("toy best pool end 20", round(best[0]) == 20)
    worst = robust_min(t, 1.0, [], [(2, 4)], base, {}, False, with_approval=False)
    ck(f"toy minimum paired gain over the 27 combinations is 8.5 (got {worst})", abs(worst - 8.5) < 1e-9)
    # contention scale, unconditional share and perturbation, hand-computed: a=[10,10,10] live [1,1,0], U=20, scale 1.5
    tl = _toy_table(uncond=20.0)
    for r, lv in zip(tl.rows, (1, 1, 0, 0, 0, 0)):
        r["live"] = lv
    ml = Model(tl, 1.5)
    ck(f"live toy wall(a,1-3) = 20*1.5 + 1.5*(10+10) + 10 = 70 (got {ml.wall('a', 1, 3)})", abs(ml.wall("a", 1, 3) - 70.0) < 1e-9)
    ck(f"live toy wall(b,4-5) = 20*1.5 + 10 = 40 (got {ml.wall('b', 4, 5)})", abs(ml.wall("b", 4, 5) - 40.0) < 1e-9)
    mp = Model(tl, 1.5, {"a": 0.15, "b": 0.0, "c": 0.0})
    ck(f"live toy under +15% on arm a = 20*1.15*1.5 + 1.5*(11.5+11.5) + 11.5 = 80.5 (got {mp.wall('a', 1, 3)})", abs(mp.wall("a", 1, 3) - 80.5) < 1e-9)
    # the approval dimension: with a short approval job, the override makes the approval wall the pool end for both splits
    ra = [(APPROVAL, 10.0)]
    ck("toy with a short approval job: best pool end still 20", round(best_split(m, ra)[0]) == 20)
    g_free = robust_min(t, 1.0, ra, [(2, 4)], base, {}, False, with_approval=False)
    g_ovr = robust_min(t, 1.0, ra, [(2, 4)], base, {}, False, with_approval=True)
    ck(f"approval override: free gain 8.5, overridden gain 0 (got {g_free}, {g_ovr})", abs(g_free - 8.5) < 1e-9 and abs(g_ovr) < 1e-9)
    ck("pool_end_for applies approval_wall to the approval job only", pool_end_for([10, 10, 10], ra, approval_wall=100.0)[0] == 100.0)
    ck("long_first hoists the named suites right after the arms",
       pool_end_for([10, 10, 10], [("x", 5.0), (APPROVAL, 50.0)], long_first=[APPROVAL])[1][APPROVAL] == 0.0)
    # decide(): clear split / flat / boundaries / asymmetric pairs / start-first only / robustness / invalid / void model
    ck("clear split prints PROCEED", decide(True, True, 120, 110, 5, 3) == "GATE: PROCEED")
    ck("both gains exactly at the bar and both robust minima exactly 0 print PROCEED", decide(True, True, 60.0, 60.0, 0, 0) == "GATE: PROCEED")
    ck("a gain just under the bar prints NO-REBALANCE (off)", decide(True, True, 59.9, 120, 5, 5) == "GATE: NO-REBALANCE")
    ck("a gain just under the bar prints NO-REBALANCE (on)", decide(True, True, 120, 59.9, 5, 5) == "GATE: NO-REBALANCE")
    ck("pristine-charge flip (off high, on low) prints NO-REBALANCE", decide(True, True, 120, 20, 5, 3) == "GATE: NO-REBALANCE")
    ck("pristine-charge flip (off low, on high) prints NO-REBALANCE", decide(True, True, 20, 120, 5, 3) == "GATE: NO-REBALANCE")
    ck("a negative robust minimum (off) prints NO-REBALANCE", decide(True, True, 120, 110, -0.001, 3) == "GATE: NO-REBALANCE")
    ck("a negative robust minimum (on) prints NO-REBALANCE", decide(True, True, 120, 110, 3, -0.001) == "GATE: NO-REBALANCE")
    ck("flat table prints NO-REBALANCE", decide(True, True, 10, 8, 1, 0) == "GATE: NO-REBALANCE")
    ck("start-first-only gain prints (start-first only)", decide(True, True, 10, 8, 1, 0, 90, True) == "GATE: NO-REBALANCE (start-first only)")
    ck("a start-first gain without start-first robustness is plain NO-REBALANCE", decide(True, True, 10, 8, 1, 0, 90, False) == "GATE: NO-REBALANCE")
    ck("a small start-first gain is plain NO-REBALANCE", decide(True, True, 10, 8, 1, 0, 59.9, True) == "GATE: NO-REBALANCE")
    ck("invalid table prints NO-REBALANCE", decide(False, True, 500, 500, 5, 5).startswith("GATE: NO-REBALANCE (table"))
    ck("void model prints NO-REBALANCE", decide(True, False, 500, 500, 5, 5).startswith("GATE: NO-REBALANCE (model"))
    # a clear-split synthetic through the real search: arm a is a long pole, the rest of the pool is empty
    big = _toy_table(costs_a=(100,) * 8, costs_b=(10, 10), costs_c=(10, 10))
    mb = Model(big, 1.0)
    e0, _, _ = pool_end_for(arm_walls_for(mb, (8, 10)), [])
    bb = best_split(mb, [])
    ck(f"clear-split toy gains >= 60 s through the real search (gain {e0 - bb[0]:.0f})", e0 - bb[0] >= GATE_NOMINAL_S)
    flat = _toy_table(costs_a=(10, 10, 10), costs_b=(10, 10, 10), costs_c=(10, 10, 10))
    mf = Model(flat, 1.0)
    ef, _, _ = pool_end_for(arm_walls_for(mf, (3, 6)), [])
    ck("flat toy gains < 60 s", ef - best_split(mf, [])[0] < GATE_NOMINAL_S)
    # drain-suite detection, scheduler
    jobs = [{"label": "x", "start": 0, "done": 10, "wall": 10}, {"label": "y", "start": 0, "done": 5, "wall": 5},
            {"label": "z", "start": 11, "done": 20, "wall": 9}]
    ck("drain detection", drain_suites(jobs) == {"z"})
    ck("drain detection: intervals that merely touch do not overlap, so both count as alone",
       drain_suites([{"label": "x", "start": 0, "done": 10, "wall": 10}, {"label": "w", "start": 10, "done": 12, "wall": 2}]) == {"x", "w"})
    e, s, last = schedule([("p", 10), ("q", 3), ("r", 3), ("s", 3), ("t", 4)])
    ck("scheduler: 5th job starts at the earliest free slot (3) and ends at 7; pool end is 10", s["t"] == 3 and e == 10 and last == "p")
    # pristine charge: a row present in two arms is charged to both; the baseline split is the same with and without the charge
    tp = _toy_table()
    for r in tp.rows:
        r["row"] = "R" if r["site"] in (1, 2, 4) else r["row"]
    pr = {"R": 3.0}
    mpr = Model(tp, 1.0, None, True, pr)
    ck(f"pristine: arm a over 1-2 keeps its own first-site charge (20), got {mpr.wall('a', 1, 2):.3f}", abs(mpr.wall("a", 1, 2) - 20.0) < 1e-9)
    ck(f"pristine: arm b over 3-4 (row first seen at site 4) is 15, got {mpr.wall('b', 3, 4):.3f}", abs(mpr.wall("b", 3, 4) - 15.0) < 1e-9)
    ck(f"pristine: a candidate arm 2-3 whose range lacks the row's first site pays it again (23), got {mpr.wall('a', 2, 3):.3f}", abs(mpr.wall("a", 2, 3) - 23.0) < 1e-9)
    ck("pristine: a range without the row pays nothing (10 for sites 5-6)", abs(mpr.wall("c", 5, 6) - 10.0) < 1e-9)
    moff = Model(tp, 1.0)
    ck("pristine: the baseline split has the same arm walls with and without the charge",
       all(abs(x - y) < 1e-9 for x, y in zip(arm_walls_for(moff, (3, 5)), arm_walls_for(mpr, (3, 5)))))
    # the t1 ordinal map: the three archived arms partition every current ordinal except the added ones, with no repeats
    sites = t1_arm_sites()
    union = sorted(k for a in ARMS for k in sites[a])
    ck("t1 ordinal map covers 1..TOTAL minus the added sites exactly once", union == sorted(set(range(1, TOTAL + 1)) - set(ADDED)))
    ck("t1 ordinal map: arm sizes are the archived 193/193/213", [len(sites[a]) for a in ARMS] == [193, 193, 213])
    ck("t1 ordinal map: old 126 stays 126, old 127 becomes 130", 126 in sites["a"] and 127 not in sites["a"] and 130 in sites["a"])
    # validation(): pass, and each failure branch
    tv, byv, rdv = _synthetic_validation_inputs()
    okv, linesv, sv = validation(tv, byv, rdv)
    ck(f"validation passes on a consistent synthetic table (scale {sv})", okv and abs(sv - 1.2) < 1e-9)
    tv, byv, rdv = _synthetic_validation_inputs(c_factor=1.4 / 1.2)
    ck("validation fails when arms b and c disagree on the scale (spread above 10%)", not validation(tv, byv, rdv)[0])
    tv, byv, rdv = _synthetic_validation_inputs(a_factor=1.3)
    ck("validation fails when arm a is predicted more than 15% off", not validation(tv, byv, rdv)[0])
    tv, byv, rdv = _synthetic_validation_inputs(reps=None)
    okn, linen, _ = validation(tv, byv, rdv)
    ck("validation fails closed when the per-rep file is missing", not okn and any("fail closed" in l for l in linen))
    tv, byv, rdv = _synthetic_validation_inputs(reps=("x",), rep_values=(1.0,))
    ck("validation fails closed with a single rep", not validation(tv, byv, rdv)[0])
    tv, byv, rdv = _synthetic_validation_inputs(rep_values=(1.0, 2.0))
    ck("validation fails when the reps disagree by 100% on material blocks", not validation(tv, byv, rdv)[0])
    tv, byv, rdv = _synthetic_validation_inputs()
    for r in tv.rows:
        r["flag"] = "flag"
    ck("validation fails when flagged sites hold more than 20% of an arm's raw seconds", not validation(tv, byv, rdv)[0])
    # validation(): each branch pinned by a fixture that reaches ONLY that branch (the logs name the branch that fired)
    def block_of(i, n):
        return i * 10 // n
    n_of = {"a": 193, "b": 193, "c": 216}
    tv, byv, rdv = _synthetic_validation_inputs(rep_fn=lambda k, a, i: (1.0 + 0.01 * block_of(i, n_of[a]), 1.0 + 0.01 * (9 - block_of(i, n_of[a]))))
    okr, lr, _ = validation(tv, byv, rdv)
    ck("validation: only the rank order differs -> fails with 'unstable blocks=[], rank order DIFFERS'", not okr and any("unstable blocks=[], rank order DIFFERS" in l for l in lr))
    tv, byv, rdv = _synthetic_validation_inputs(rep_fn=lambda k, a, i: (3.0 + 0.5 * block_of(i, n_of[a]) + (1.5 if i % 2 == 0 else -1.5),
                                                                       3.0 + 0.5 * block_of(i, n_of[a]) - (1.5 if i % 2 == 0 else -1.5)))
    okd, ld, _ = validation(tv, byv, rdv)
    ck("validation: only the per-site rep disagreement fires (ranks equal, blocks stable, 100% of raw seconds)",
       not okd and any("rank order equal" in l for l in ld) and any("hold 100.0%" in l for l in ld) and not any("unstable blocks=[0" in l for l in ld))
    tv, byv, rdv = _synthetic_validation_inputs(rep_fn=lambda k, a, i: ((0.02, 0.06) if (a == "a" and block_of(i, 193) == 3) else (1.0, 1.0)))
    oks, ls, _ = validation(tv, byv, rdv)
    ck("validation: a sub-5% block that is 3x apart between reps is not material and passes", oks)
    tv, byv, rdv = _synthetic_validation_inputs(rep_fn=lambda k, a, i: ((1.0, 3.0) if (a == "a" and i < 19) else (1.0, 1.0)))
    oksp, lsp, _ = validation(tv, byv, rdv)
    ck("validation: a spike on the first tenth of arm a shows up as 'unstable blocks=[0]'", not oksp and any("arm a" in l and "unstable blocks=[0]" in l for l in lsp))
    tv, byv, rdv = _synthetic_validation_inputs(rep_fn=lambda k, a, i: ((0.02, 1.0) if (a == "a" and block_of(i, 193) == 3) else (1.0, 1.0)))
    okm, lm, _ = validation(tv, byv, rdv)
    ck("validation: a block material in only the SECOND rep is counted (union over reps) and shows as unstable", not okm and any("arm a" in l and "unstable blocks=[3]" in l for l in lm))
    tv, byv, rdv = _synthetic_validation_inputs()
    short = (byv[0], {k: v for k, v in byv[1].items() if k % 2})
    okc, lc, _ = validation(tv, short, rdv)
    ck("validation: a per-rep file that omits sites fails closed", not okc and any("does not cover exactly" in l for l in lc))
    tv, byv, rdv = _synthetic_validation_inputs(live_alone=50)
    oka, la, _ = validation(tv, byv, rdv)
    ck("validation: the alone/overlapped split of arm a is 50.0 / 143.0 s", oka and any("alone_s=50.0 overlapped_s=143.0" in l for l in la))
    tv, byv, rdv = _synthetic_validation_inputs(scale2=2.0)
    okt, lt, st = validation(tv, byv, rdv)
    ck(f"validation: the model scale is the FIRST reading's (1.2), got {st}", abs(st - 1.2) < 1e-9 and any("validation other:" in l for l in lt))
    tv, byv, rdv = _synthetic_validation_inputs(a_factor=1.17)
    ck("validation: arm a's error is taken against the archived wall (14.5% passes; against the prediction it would be 17%)", validation(tv, byv, rdv)[0])
    tv, byv, rdv = _synthetic_validation_inputs(c_factor=1.105)
    ck("validation: the b/c spread is taken against the larger ratio (9.5% passes; against the smaller it would be 10.5%)", validation(tv, byv, rdv)[0])
    tv, byv, rdv = _synthetic_validation_inputs()
    del byv[1][1]  # arm a loses its site 1 in the per-rep file: still fine; remove every arm-b row instead
    for k in [k for k, (a, _v) in byv[1].items() if a == "b"]:
        del byv[1][k]
    ck("validation: an arm with no row in the per-rep file fails closed", not validation(tv, byv, rdv)[0])
    # check(): a table with an unlabelled row is refused
    tv, byv, rdv = _synthetic_validation_inputs()
    ck("check() accepts the consistent synthetic table", check(tv) == [])
    tv.rows[10]["row"] = "?"
    ck("check() refuses a table with an unlabelled row", any("unlabelled" in b for b in check(tv)))
    # pristine charge under live, scale and perturbation, hand-computed: R at sites 1,2 (arm a) and 4 (arm b), live everywhere, scale 1.5, +15% on arm a, R=3
    tq = _toy_table()
    for r in tq.rows:
        r["live"] = 1
        r["row"] = "R" if r["site"] in (1, 2, 4) else r["row"]
    mq = Model(tq, 1.5, {"a": 0.15, "b": 0.0, "c": 0.0}, True, {"R": 3.0})
    ck(f"pristine under pert+scale: wall(a,1-2) = 34.5 (= the uncharged baseline), got {mq.wall('a', 1, 2):.4f}", abs(mq.wall("a", 1, 2) - 34.5) < 1e-9)
    ck(f"pristine under pert+scale: wall(a,2-3) = 34.5 + 3*1.15*1.5 = 39.675, got {mq.wall('a', 2, 3):.4f}", abs(mq.wall("a", 2, 3) - 39.675) < 1e-9)
    ck(f"pristine under pert+scale: wall(b,3-4) = 17.25 + 7.5 (site 4 charged back) = 24.75, got {mq.wall('b', 3, 4):.4f}", abs(mq.wall("b", 3, 4) - 24.75) < 1e-9)
    # robust_min over several splits is the minimum over them: adding the baseline split itself (gain 0) pulls the minimum to 0
    ck("robust_min over [(2,4)] is 8.5 and over [(2,4), (3,5)] is 0 (the baseline split gains nothing)",
       abs(robust_min(t, 1.0, [], [(2, 4)], base, {}, False, with_approval=False) - 8.5) < 1e-9
       and abs(robust_min(t, 1.0, [], [(2, 4), (3, 5)], base, {}, False, with_approval=False)) < 1e-9)
    ck("gate_for(): the minimum over candidates, not the best (the baseline split gains 0)",
       gate_for(t, 1.0, [], {}, base, [(2, 4), (3, 5)], False) == (0.0, 0.0))
    ck("gate_for(): a single candidate keeps its own nominal gain (10) and robust minimum (8.5)",
       gate_for(t, 1.0, [], {}, base, [(2, 4)], False) == (10.0, 8.5))
    ck("candidates_of(): both models' best splits, sorted, deduplicated",
       candidates_of({("t1-order", False): (0, 0, (5, 9), 0), ("t1-order", True): (0, 0, (1, 2), 0)}) == [(1, 2), (5, 9)]
       and candidates_of({("t1-order", False): (0, 0, (1, 2), 0), ("t1-order", True): (0, 0, (1, 2), 0)}) == [(1, 2)])
    ck("decide(): an invalid table wins over a void model", decide(False, False, 500, 500, 5, 5).startswith("GATE: NO-REBALANCE (table"))
    ck("decide(): a start-first gain exactly at the bar prints (start-first only)", decide(True, True, 10, 8, 1, 0, 60.0, True) == "GATE: NO-REBALANCE (start-first only)")
    # report(): the wiring from files to the GATE line, on a consistent synthetic table (uniform costs: validation passes, no split gains 60 s)
    import contextlib
    import io
    import tempfile
    rep_dir = tempfile.mkdtemp(prefix="swf-", dir=os.environ.get("TMPDIR") or "/var/tmp")
    try:
        tv, byv, rdv = _synthetic_validation_inputs()
        tpath = os.path.join(rep_dir, "t.tsv")
        _write_table(tpath, tv)
        _write_by_rep(os.path.join(rep_dir, "t.by_rep.tsv"), byv)
        lpath = os.path.join(rep_dir, "launch.tsv")
        _write_launch(lpath, [rdv["t1"][lab]["wall"] for lab in ARM_LABELS])
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc_rep = report(tpath, lpath, lpath, {"t1": 216.0})
        out = buf.getvalue()
        ck("report(): rc 0 and a plain NO-REBALANCE on a consistent uniform table", rc_rep == 0 and out.rstrip().endswith("GATE: NO-REBALANCE"))
        ck("report(): validation passed, model reproduction ok, both gate lines and the robustness provenance are printed",
           "validation passed" in out and "model reproduction ok" in out and out.count("gate pristine_charge=") == 2 and "666 s: the #12263 issue body" in out)
        ck("report(): the cold derive is added to the packing floor", "with cold derive 216 s" in out)
        short = tv
        short.rows = short.rows[:-1]
        _write_table(tpath, short)
        buf2 = io.StringIO()
        with contextlib.redirect_stdout(buf2):
            rc_bad = report(tpath, lpath, lpath, {})
        ck("report(): a table that fails check() returns 2 with the table-level GATE line", rc_bad == 2 and "GATE: NO-REBALANCE (table does not support a rebalance)" in buf2.getvalue())
        tv2, byv2, rdv2 = _synthetic_validation_inputs(rep_values=(1.0, 2.0))
        _write_table(tpath, tv2)
        _write_by_rep(os.path.join(rep_dir, "t.by_rep.tsv"), byv2)
        buf3 = io.StringIO()
        with contextlib.redirect_stdout(buf3):
            rc_v = report(tpath, lpath, lpath, {})
        ck("report(): failing validation is carried into the GATE line", rc_v == 0 and "validation FAILED" in buf3.getvalue()
           and buf3.getvalue().rstrip().endswith("GATE: NO-REBALANCE (table does not support a rebalance)"))
    finally:
        import shutil
        shutil.rmtree(rep_dir, ignore_errors=True)
    # estimate_pristine: first site minus the median of the others in the same arm, clamped at 0; a single-site row takes the maximum
    te = _toy_table(costs_a=(9, 3, 3), costs_b=(5, 5), costs_c=(5,))
    for r, row in zip(te.rows, ("R", "R", "R", "S", "S", "T")):
        r["row"] = row
    pe = estimate_pristine(te)
    ck(f"estimate_pristine: row R = 9 - median(3,3) = 6, row S = max(0, 5-5) = 0, single-site row T takes the max 6 (got {pe})",
       pe["R"] == 6.0 and pe["S"] == 0.0 and pe["T"] == 6.0)
    if fails:
        print("SELFTEST FAIL:\n  " + "\n  ".join(fails))
        return 1
    if ran[0] < MIN_CHECKS:
        print(f"SELFTEST FAIL: only {ran[0]} checks ran, floor is {MIN_CHECKS}")
        return 1
    print(f"{NAME} selftest: {ran[0]} checks; toy 3-arm minimum paired gain 8.5 hand-checked, contention/approval/pristine models, verdict boundaries, "
          f"validation branches, ordinal map")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) == 3 and argv[1] == "--check":
        bad = check(read_table(argv[2]))
        for b in bad:
            p("CHECK FAIL: " + b)
        if not bad:
            p("check ok")
        return 1 if bad else 0
    if len(argv) >= 4:
        derived = {}
        if len(argv) >= 6 and argv[4] == "--derived":
            derived = {k: float(v) for k, v in (kv.split("=") for kv in argv[5].split(","))}
        elif len(argv) > 4:
            print(f"{NAME}: unknown option {argv[4]!r} (only --derived name=secs,name=secs)")
            return 2
        return report(argv[1], argv[2], argv[3], derived)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
