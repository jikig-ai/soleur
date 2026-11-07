#!/usr/bin/env python3
"""site_cost_whatif.py — validation, paper check and #12263 pricing on the measured site-cost table (Ref #12013).

Usage (run with `python3 -I`):
  site_cost_whatif.py --check <site_costs.tsv>
  site_cost_whatif.py <site_costs.tsv> <launch_order.t1.tsv> <launch_order.control2.tsv> [--derived t1=216,control2=234]
  site_cost_whatif.py --selftest

Model (a direction check, never a result): list schedule, width 4, lane tokens ignored, the suites that ran ALONE at the end
(the `*` drain-barrier suites) removed, jobs launched in start-time order of the committed reading. The three replay arms are
re-priced from the table; every other suite keeps its measured wall. Pooled arm wall = s * (U + sum of raw cost of sites that had
another arm live) + sum of raw cost of sites with no other arm live, where s is fitted on arms b and c of the archived
readings (their runs overlapped the other arms throughout) and the part with no other arm live is taken at ratio 1.0.

The archived readings ran 599 gated sites with arms 1-193 / 194-386 / 387-599; the table is on the current 602 ordinals, so the
archived arms are rebuilt in current ordinals: old ordinal o is current ordinal o if o < 127 else o + 3 (sites 127-129 were added).
"""
import bisect
import heapq
import itertools
import os
import re
import sys
from statistics import median

NAME = "site_cost_whatif.py"
WIDTH = 4
GATE_NOMINAL_S = 60.0
FLOOR_CONSIDER_S = 30.0
ARM_LABELS = ["plugins/soleur/test/ci-pr-affected-replay-a", "plugins/soleur/test/ci-pr-affected-replay-b", "plugins/soleur/test/ci-pr-affected-replay-c"]
APPROVAL = "apps/web-platform/test/approval-guard1-mutation"
LONG3 = [APPROVAL, "apps/web-platform/test/argv-bearer-sweep", "apps/web-platform/test/destroy-ask-mutation"]
APPROVAL_WALLS = (666.0, 880.0, 1080.0)
ARM_PERT = (-0.15, 0.0, 0.15)
ADDED = (127, 128, 129)
OLD_RANGES = {"a": (1, 193), "b": (194, 386), "c": (387, 599)}
ARMS = ("a", "b", "c")


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
    t.walls = {}
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
        elif line.startswith("# wall_s "):
            t.walls = {k: float(v) for k, v in (kv.split("=") for kv in line.split()[2:])}
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
    if t.total != 602:
        bad.append(f"header DECLARED_TOTAL={t.total}, expected 602")
    if sorted(t.uncond) != list(ARMS):
        bad.append("header lacks unconditional_s for every arm")
    if len(t.rows) != 602:
        bad.append(f"{len(t.rows)} data rows, expected 602")
    if [r["site"] for r in t.rows] != list(range(1, len(t.rows) + 1)):
        bad.append("site ordinals are not 1..N in order")
    spans = sorted(t.ranges.values())
    nxt = 1
    for lo, hi in spans:
        if lo != nxt:
            bad.append(f"ranges do not tile 1..602: {spans}")
            break
        nxt = hi + 1
    else:
        if nxt != 603:
            bad.append(f"ranges end at {nxt - 1}, expected 602")
    for r in t.rows:
        if r["cost"] < 0:
            bad.append(f"site {r['site']} has a negative cost")
            break
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
    return jobs, engaged


def drain_suites(jobs):
    """Suites whose interval overlaps no other suite's interval: they ran alone (the `*` drain-barrier suites)."""
    alone = set()
    for i, a in enumerate(jobs):
        if all(not (a["start"] < b["done"] and b["start"] < a["done"]) for j, b in enumerate(jobs) if j != i):
            alone.add(a["label"])
    return alone


def schedule(walls_in_order):
    """Return (pool_end, starts) of a width-4 list schedule over [(label, wall)] in launch order."""
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


# ------------------------------------------------------------------ arm walls from the table
class Model:
    """Per-site pooled cost under a contention scale, with prefix sums for O(1) arm walls."""

    def __init__(self, t, scale, perturb=None, pristine=False, prist_row=None):
        self.t = t
        n = len(t.rows)
        self.n = n
        pert = perturb or {a: 0.0 for a in ARMS}
        self.U = {a: t.uncond[a] * (1 + pert[a]) for a in ARMS}
        self.pooled = [0.0] * (n + 1)
        self.noprist = [0.0] * (n + 1)
        first_of = {}
        for r in t.rows:
            first_of.setdefault((r["arm"], r["row"]), r["site"])
        for r in t.rows:
            k = r["site"]
            raw = r["raw"] * (1 + pert[r["arm"]])
            if pristine and first_of[(r["arm"], r["row"])] == k:
                raw -= prist_row.get(r["row"], 0.0) * (1 + pert[r["arm"]])
            mult = scale if r["live"] > 0 else 1.0
            self.pooled[k] = raw * mult
            self.noprist[k] = raw * mult
        self.prefix = list(itertools.accumulate(self.pooled))
        self.scale = scale
        self.pristine = pristine
        self.prist_row = prist_row or {}
        self.row_ords = {}
        for r in t.rows:
            self.row_ords.setdefault(r["row"], []).append(r["site"])
        if pristine:
            self._charge = self._build_charge(pert)

    def _build_charge(self, pert):
        """charge[(lo, hi)] = pristine cost of the rows present in [lo, hi] (rows start dispatched at their first site there)."""
        n = self.n
        weight = {}
        for r in self.t.rows:
            weight.setdefault(r["row"], (1 + pert[r["arm"]]))
        by_row_first = {}
        site_row = {r["site"]: r["row"] for r in self.t.rows}
        charge = {}
        for lo in range(1, n + 1):
            seen = set()
            acc = 0.0
            for hi in range(lo, n + 1):
                row = site_row[hi]
                if row not in seen:
                    seen.add(row)
                    acc += self.prist_row.get(row, 0.0) * weight[row] * (self.scale if self._row_live(row) else 1.0)
                charge[(lo, hi)] = acc
        return charge

    def _row_live(self, row):
        return any(r["live"] > 0 for r in self.t.rows if r["row"] == row)

    def wall(self, arm, lo, hi):
        w = self.U[arm] * self.scale + (self.prefix[hi] - self.prefix[lo - 1])
        if self.pristine:
            w += self._charge[(lo, hi)]
        return w


def estimate_pristine(t):
    """Per-row pristine cost: first site of a row in an arm minus the median of its other sites there (>= 0); a row with no arm
    holding two of its sites takes the largest estimate observed."""
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
    n = model.n
    return [model.wall("a", 1, x), model.wall("b", x + 1, y), model.wall("c", y + 1, n)]


def pool_end_for(walls, rest, approval_first=False, long3=None, approval_wall=None):
    jobs = list(zip(ARM_LABELS, walls))
    rest = [(l, (approval_wall if (approval_wall is not None and l == APPROVAL) else w)) for l, w in rest]
    if approval_first and long3:
        head = [j for j in rest if j[0] in long3]
        tail = [j for j in rest if j[0] not in long3]
        order = jobs + head + tail
    else:
        order = jobs + rest
    return schedule(order)


def best_split(model, rest, approval_first=False, long3=None, approval_wall=None, base_split=None):
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
        end, _, _ = pool_end_for(w, rest, approval_first, long3, approval_wall)
        if best is None or end < best[0] or (end == best[0] and lb < best[4]):
            best = (end, x, y, w, lb)
    return best


# ------------------------------------------------------------------ verdict
def decide(valid, model_ok, nominal_off, nominal_on, robust_off, robust_on, nominal_sf_on=None, sf_ok=False):
    """GATE line text from the measured facts. nominal_* are gains in seconds in the ordering on main today."""
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


def robust_min(table, scale, rest, split, base_split, prist, pristine, approval_first=False, long3=None, with_approval=True):
    """Minimum over the perturbation combinations of (baseline pool end - candidate pool end), paired."""
    worst = None
    walls = APPROVAL_WALLS if with_approval else (None,)
    for pa, pb, pc in itertools.product(ARM_PERT, repeat=3):
        m = Model(table, scale, {"a": pa, "b": pb, "c": pc}, pristine, prist)
        for aw in walls:
            e0, _, _ = pool_end_for(arm_walls_for(m, base_split), rest, approval_first, long3, aw)
            e1, _, _ = pool_end_for(arm_walls_for(m, split), rest, approval_first, long3, aw)
            g = e0 - e1
            if worst is None or g < worst:
                worst = g
    return worst


def base_split_of(t):
    return (t.ranges["a"][1], t.ranges["b"][1])


# ------------------------------------------------------------------ validation of the table (plan 4.2)
def t1_arm_sites(t):
    """Current ordinals of the sites each archived arm ran (599-site era)."""
    def cur(o):
        return o if o < 127 else o + 3
    return {a: [cur(o) for o in range(lo, hi + 1)] for a, (lo, hi) in OLD_RANGES.items()}


def fit_scale(t, jobs_by_label, label_tag):
    sites = t1_arm_sites(t)
    rows = {r["site"]: r for r in t.rows}
    out = {}
    for a, lab in zip(ARMS, ARM_LABELS):
        pred = t.uncond[a] + sum(rows[k]["raw"] for k in sites[a])
        out[a] = (jobs_by_label[lab]["wall"], pred)
    rb = out["b"][0] / out["b"][1]
    rc = out["c"][0] / out["c"][1]
    return out, rb, rc


def validation(t, by_rep, readings):
    """Returns (ok, lines, scale). readings: {name: jobs_by_label}."""
    ok = True
    lines = []
    rows = {r["site"]: r for r in t.rows}
    scale = None
    for name, jb in readings.items():
        out, rb, rc = fit_scale(t, jb, name)
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
    # flagged sites (cost < noise)
    for a in ARMS:
        owned = [r for r in t.rows if r["arm"] == a]
        tot = sum(max(0.0, r["raw"]) for r in owned)
        fl = sum(max(0.0, r["raw"]) for r in owned if r["flag"] == "flag")
        share = fl / tot if tot else 0.0
        lines.append(f"validation flagged sites arm {a}: {sum(1 for r in owned if r['flag'] == 'flag')} of {len(owned)}, holding {share * 100:.1f}% of raw site-seconds (limit 20%)")
        if share > 0.20:
            ok = False
    # split-half stability
    if by_rep is not None:
        reps, brows = by_rep
        if len(reps) >= 2:
            for a in ARMS:
                ords = [k for k in sorted(brows) if brows[k][0] == a]
                size = max(1, len(ords) // 10)
                blocks = [ords[i:i + size] for i in range(0, len(ords), size)]
                if len(blocks) > 10:
                    blocks[-2] += blocks[-1]
                    blocks.pop()
                armtot = sum(max(0.0, brows[k][1][0]) for k in ords) or 1.0
                bad = []
                sums = [[sum(brows[k][1][i] for k in blk) for blk in blocks] for i in range(len(reps))]
                material = [j for j in range(len(blocks)) if sums[0][j] >= 0.05 * armtot]
                for j in material:
                    vals = [sums[i][j] for i in range(len(reps))]
                    if (max(vals) - min(vals)) / max(abs(max(vals)), 1e-9) > 0.20:
                        bad.append(j)
                order = [sorted(material, key=lambda j, i=i: sums[i][j]) for i in range(len(reps))]
                rank_ok = all(o == order[0] for o in order)
                lines.append(f"validation split-half arm {a}: {len(material)} material blocks, unstable blocks={bad}, rank order {'equal' if rank_ok else 'DIFFERS'}")
                if bad or not rank_ok:
                    ok = False
            unstable = [k for k, (a, v) in brows.items() if (max(v) - min(v)) > max(2.0, 0.25 * max(abs(x) for x in v))]
            for a in ARMS:
                owned = [k for k, (aa, v) in brows.items() if aa == a]
                tot = sum(max(0.0, rows[k]["raw"]) for k in owned) or 1.0
                u = sum(max(0.0, rows[k]["raw"]) for k in owned if k in unstable)
                lines.append(f"validation rep-disagreement arm {a}: sites with r1/r2 cost differing by more than max(2 s, 25%) hold {u / tot * 100:.1f}% of raw site-seconds (limit 20%)")
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
    p(f"check ok: 602 rows, ranges {t.ranges}, tree {t.tree}")
    by_path = table_path.rsplit(".", 1)[0] + ".by_rep.tsv"
    by_rep = read_by_rep(by_path) if os.path.exists(by_path) else None
    j1, eng1 = read_launch(t1_path)
    j2, eng2 = read_launch(c2_path)
    jb1 = {j["label"]: j for j in j1}
    jb2 = {j["label"]: j for j in j2}
    readings = {"t1": jb1, "control2": jb2}
    # packing floor from the committed rows
    for name, jl in (("t1", j1), ("control2", j2)):
        floor = sum(j["wall"] for j in jl) / WIDTH
        cd = derived.get(name)
        extra = f"; with cold derive {cd:.0f} s: {floor + cd:.0f} s" if cd else ""
        p(f"packing floor {name}: sum of walls {sum(j['wall'] for j in jl):.0f} s / {WIDTH} = {floor:.0f} s{extra} (bar 600 s)")
    # model reproduction on the archived readings with measured walls
    model_ok = True
    for name, jl, want_end, want_ap_start in (("t1", j1, 1845.0, 765.0), ("control2", j2, None, None)):
        alone = drain_suites(jl)
        body = [(j["label"], j["wall"]) for j in jl if j["label"] not in alone]
        end, starts, last = schedule(body)
        meas_end = max(j["done"] for j in jl if j["label"] not in alone)
        p(f"model {name}: removed drain suites {sorted(alone)}; modelled pool end {end:.0f} s, archived {meas_end:.0f} s; "
          f"{APPROVAL.split('/')[-1]} start modelled {starts.get(APPROVAL, float('nan')):.0f} s archived {jb1_start(jl):.0f} s; run ends on {last}")
        # control2 ran the old star barrier, whose post-barrier drain is not modelled: only t1's pool end is compared
        if want_end is not None and abs(end - meas_end) > 15:
            model_ok = False
        if want_ap_start is not None and abs(starts[APPROVAL] - want_ap_start) > 15:
            model_ok = False
    # control2's approval end from t1's order with control2's walls
    alone1 = drain_suites(j1)
    order_t1 = [j["label"] for j in j1 if j["label"] not in alone1]
    body = [(l, jb2[l]["wall"]) for l in order_t1 if l in jb2]
    _, starts_x, _ = schedule(body)
    ap_end = starts_x[APPROVAL] + jb2[APPROVAL]["wall"]
    ap_want = jb2[APPROVAL]["done"]
    p(f"model: t1 order with control2 walls puts {APPROVAL.split('/')[-1]} ending at {ap_end:.0f} s, archived control2 {ap_want:.0f} s")
    if abs(ap_end - ap_want) > 15:
        model_ok = False
    p(f"model reproduction {'ok' if model_ok else 'FAILED'} (limit 15 s)")
    ok, vlines, scale = validation(t, by_rep, readings)
    for l in vlines:
        p(l)
    p(f"validation {'passed' if ok else 'FAILED: the table does not support a rebalance'}")
    scale = scale or 1.0
    # gate search on the t1 order
    alone = drain_suites(j1)
    rest = [(j["label"], j["wall"]) for j in j1 if j["label"] not in alone and j["label"] not in ARM_LABELS]
    prist = estimate_pristine(t)
    base = base_split_of(t)
    results = {}
    for ordering in ("main", "start-first"):
        sf = ordering == "start-first"
        for pristine in (False, True):
            m = Model(t, scale, None, pristine, prist)
            e0, _, last0 = pool_end_for(arm_walls_for(m, base), rest, sf, LONG3 if sf else None)
            best = best_split(m, rest, sf, LONG3 if sf else None)
            end, x, y, w, _ = best
            rob = robust_min(t, scale, rest, (x, y), base, prist, pristine, sf, LONG3 if sf else None)
            results[(ordering, pristine)] = (e0, end, (x, y), w, rob, last0)
            p(f"{ordering} pristine_charge={'on' if pristine else 'off'}: baseline pool end {e0:.0f} s (ends on {last0.split('/')[-1]}); best split "
              f"1-{x} / {x + 1}-{y} / {y + 1}-602 arm walls {w[0]:.0f}/{w[1]:.0f}/{w[2]:.0f}; pool end {end:.0f} s; nominal gain {e0 - end:.0f} s; "
              f"min paired gain over 81 combinations {rob:.0f} s")
    g_off, g_on = results[("main", False)][0] - results[("main", False)][1], results[("main", True)][0] - results[("main", True)][1]
    r_off, r_on = results[("main", False)][4], results[("main", True)][4]
    sf_on = results[("start-first", True)][0] - results[("start-first", True)][1]
    sf_ok = results[("start-first", True)][4] >= 0 and results[("start-first", False)][4] >= 0
    # the split that would land (charged model) must also clear the bar under the uncharged model
    land = results[("main", True)][2]
    m_off = Model(t, scale, None, False, prist)
    e0_off, _, _ = pool_end_for(arm_walls_for(m_off, base), rest)
    e_land_off, _, _ = pool_end_for(arm_walls_for(m_off, land), rest)
    cross = e0_off - e_land_off
    p(f"cross-check: the charged-model split 1-{land[0]} / {land[0] + 1}-{land[1]} / {land[1] + 1}-602 gains {cross:.0f} s under the uncharged model")
    g_off = min(g_off, cross) if cross < g_off else g_off
    # #12263 pricing (paper only)
    for name, jl in (("t1", j1),):
        alone = drain_suites(jl)
        body = [(j["label"], j["wall"]) for j in jl if j["label"] not in alone]
        floor = sum(w for _, w in body) / WIDTH
        e_main, _, last_main = schedule(body)
        ap_first = [x for x in body if x[0] == APPROVAL] + [x for x in body if x[0] != APPROVAL]
        e_ap, _, last_ap = schedule(ap_first)
        l3 = [x for x in body if x[0] in LONG3] + [x for x in body if x[0] not in LONG3]
        e_l3, _, last_l3 = schedule(l3)
        p(f"#12263 pricing {name} (measured walls, drain suites removed): packing floor {floor:.0f} s; order as run {e_main:.0f} s (ends on {last_main.split('/')[-1]}); "
          f"{APPROVAL.split('/')[-1]} first {e_ap:.0f} s (gap to floor {e_ap - floor:.0f} s, ends on {last_ap.split('/')[-1]}); "
          f"three long suites first {e_l3:.0f} s (gap to floor {e_l3 - floor:.0f} s, ends on {last_l3.split('/')[-1]})")
    line = decide(ok, model_ok, g_off, g_on, r_off, r_on, sf_on, sf_ok)
    if line == "GATE: PROCEED" and (g_on < GATE_NOMINAL_S):
        line = "GATE: NO-REBALANCE"
    print(line)
    return 0


def jb1_start(jl):
    for j in jl:
        if j["label"] == APPROVAL:
            return j["start"]
    return float("nan")


# ------------------------------------------------------------------ selftest
def _toy_table(costs_a=(10, 10, 10), costs_b=(5, 5), costs_c=(5,), live=0):
    t = Table()
    t.tree = "toy"
    t.total = 6
    sites = list(costs_a) + list(costs_b) + list(costs_c)
    arms = ["a"] * len(costs_a) + ["b"] * len(costs_b) + ["c"] * len(costs_c)
    t.ranges = {"a": (1, len(costs_a)), "b": (len(costs_a) + 1, len(costs_a) + len(costs_b)), "c": (len(sites), len(sites))}
    t.uncond = {a: 0.0 for a in ARMS}
    t.rows = [{"site": i + 1, "arm": arms[i], "row": f"row{i}", "cost": float(c), "raw": float(c), "noise": 0.0, "flag": "-", "live": live}
              for i, c in enumerate(sites)]
    return t


def selftest():
    fails = []

    def ck(name, cond):
        if not cond:
            fails.append(name)

    # 3-arm toy, hand-checked: costs a=[10,10,10] b=[5,5] c=[5]; walls 30/10/5; best split 1-2 / 3-4 / 5-6 gives 20/15/10
    t = _toy_table()
    m = Model(t, 1.0)
    base = (3, 5)
    ck("toy baseline walls 30/10/5", [round(x) for x in arm_walls_for(m, base)] == [30, 10, 5])
    ck("toy 1-2/3-4/5-6 walls 20/15/10", [round(x) for x in arm_walls_for(m, (2, 4))] == [20, 15, 10])
    best = best_split(m, [])
    ck("toy best pool end 20", round(best[0]) == 20)
    worst = robust_min(t, 1.0, [], (2, 4), base, {}, False, with_approval=False)
    ck(f"toy minimum paired gain over the 27 combinations is 8.5 (got {worst})", abs(worst - 8.5) < 1e-9)
    # decide(): clear split / flat / start-first only / pristine flip / invalid / void model
    ck("clear split prints PROCEED", decide(True, True, 120, 110, 5, 3) == "GATE: PROCEED")
    ck("flat table prints NO-REBALANCE", decide(True, True, 10, 8, 1, 0) == "GATE: NO-REBALANCE")
    ck("start-first-only gain prints (start-first only)", decide(True, True, 10, 8, 1, 0, 90, True) == "GATE: NO-REBALANCE (start-first only)")
    ck("pristine-charge flip prints NO-REBALANCE", decide(True, True, 120, 20, 5, 3) == "GATE: NO-REBALANCE")
    ck("robustness failure prints NO-REBALANCE", decide(True, True, 120, 110, -1, 3) == "GATE: NO-REBALANCE")
    ck("invalid table prints NO-REBALANCE", decide(False, True, 500, 500, 5, 5).startswith("GATE: NO-REBALANCE"))
    ck("void model prints NO-REBALANCE", decide(True, False, 500, 500, 5, 5).startswith("GATE: NO-REBALANCE"))
    # a clear-split synthetic through the real search: arm a is a long pole, the rest of the pool is empty
    big = _toy_table(costs_a=(100,) * 8, costs_b=(10, 10), costs_c=(10, 10))
    mb = Model(big, 1.0)
    e0, _, _ = pool_end_for(arm_walls_for(mb, (8, 10)), [])
    bb = best_split(mb, [])
    ck(f"clear-split toy gains >= 60 s through the real search (gain {e0 - bb[0]:.0f})", e0 - bb[0] >= GATE_NOMINAL_S)
    flat = _toy_table(costs_a=(10, 10, 10), costs_b=(10, 10, 10), costs_c=(10, 10, 10))
    mf = Model(flat, 1.0)
    ef, _, _ = pool_end_for(arm_walls_for(mf, (3, 6)), [])
    bf = best_split(mf, [])
    ck("flat toy gains < 60 s", ef - bf[0] < GATE_NOMINAL_S)
    # drain-suite detection and the scheduler
    jobs = [{"label": "x", "start": 0, "done": 10, "wall": 10}, {"label": "y", "start": 0, "done": 5, "wall": 5},
            {"label": "z", "start": 11, "done": 20, "wall": 9}]
    ck("drain detection", drain_suites(jobs) == {"z"})
    e, s, last = schedule([("p", 10), ("q", 3), ("r", 3), ("s", 3), ("t", 4)])
    ck("scheduler: 5th job starts at the earliest free slot (3) and ends at 7; pool end is 10", s["t"] == 3 and e == 10 and last == "p")
    # pristine charge: a row split across the boundary pays once more
    tp = _toy_table()
    for r in tp.rows:
        r["row"] = "R" if r["site"] in (1, 2, 4) else r["row"]
    pr = {"R": 3.0}
    mp = Model(tp, 1.0, None, True, pr)
    ck(f"pristine: arm a over 1-2 keeps its own first-site charge (20), got {mp.wall('a', 1, 2):.3f}", abs(mp.wall("a", 1, 2) - 20.0) < 1e-9)
    ck(f"pristine: arm b over 3-4 (row first seen at site 4) is 15, got {mp.wall('b', 3, 4):.3f}", abs(mp.wall("b", 3, 4) - 15.0) < 1e-9)
    ck(f"pristine: a candidate arm 2-3 whose range lacks the row's first site pays it again (23), got {mp.wall('a', 2, 3):.3f}", abs(mp.wall("a", 2, 3) - 23.0) < 1e-9)
    ck("pristine: a range without the row pays nothing (10 for sites 5-6)", abs(mp.wall("c", 5, 6) - 10.0) < 1e-9)
    if fails:
        print("SELFTEST FAIL:\n  " + "\n  ".join(fails))
        return 1
    print(f"{NAME} selftest: toy 3-arm minimum paired gain 8.5 hand-checked, verdict logic (PROCEED / flat / start-first only / pristine flip), search and scheduler ok")
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
        return report(argv[1], argv[2], argv[3], derived)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
