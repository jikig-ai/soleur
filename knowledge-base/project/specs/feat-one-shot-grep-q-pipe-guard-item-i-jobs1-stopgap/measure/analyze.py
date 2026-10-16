#!/usr/bin/env python3
"""Item I analysis over the raw pulls under /var/tmp/item-i (re-run with: python3 -I analyze.py).

Inputs written by the pull-*.sh scripts and by the two `gh run list` commands in the plan:
  runs.json         monitor runs (gh run list --workflow main-health-monitor.yml)
  iv-push.json      infra-validation push-to-main runs
  outcomes.tsv      per monitor run: tests=/infra= verdict from the SOLEUR_MAIN_HEALTH annotation
  timeouts.tsv      per monitor run: GitHub's "has timed out after N minutes" annotation per step
  monitor-facts.tsv per monitor run: facts extracted from the job log (extract-monitor-facts.sh)
  legs.tsv, red-headers.tsv  deploy-script-tests leg conclusions and RED suites (-P 4)
Every figure printed here is a count of a parsed field; the CONTROLS block fails loudly if an
instrument cannot tell a known-positive from a known-negative.
"""
import collections, json, sys

import os
D = os.environ.get('OUT', '/var/tmp/item-i').rstrip('/') + '/'

def rows(path):
    return [l.rstrip('\n').split('\t') for l in open(D + path)]

# ---- monitor verdicts -------------------------------------------------------------------------
out = {r[0]: r for r in rows('outcomes.tsv')}          # rid created concl jid start end tests infra te ie
to = {r[0]: r for r in rows('timeouts.tsv')}           # rid tests_timeout infra_timeout
facts = {r[0]: r for r in rows('monitor-facts.tsv')}   # rid tN tP tk iN iP ib nreds reds

def verdict(rid):
    o, t, f = out[rid], to[rid], facts.get(rid, [])
    tests, infra = o[6], o[7]
    return dict(created=o[1], concl=o[2], tests=tests, infra=infra,
                tto=t[1] == '1', ito=t[2] == '1', P=f[5] if len(f) > 5 else '-',
                N=f[4] if len(f) > 4 else '-', reds=[x for x in (f[8].split(',') if len(f) > 8 else []) if x])

V = {rid: verdict(rid) for rid in out}

# ---- CONTROLS (fail loudly) -------------------------------------------------------------------
POS = '38897624648'   # 2026-10-16 12:01Z: tests and infra both killed at their ceilings
assert POS in V, 'positive control run %s is outside the pulled window (retention or --limit): pick another run with tests=failure infra=failure and both timeout annotations' % POS
assert V[POS]['tests'] == 'failure' and V[POS]['infra'] == 'failure' and V[POS]['tto'] and V[POS]['ito'], 'positive control lost'
neg = [r for r, v in V.items() if v['tests'] == 'success' and v['infra'] == 'success']
assert neg and all(not V[r]['tto'] and not V[r]['ito'] for r in neg), 'negative control: success rows must carry no timeout annotation'
absent = [r for r, v in V.items() if v['concl'] == 'cancelled']
assert absent and all(V[r]['infra'] in ('ABSENT', 'skipped') for r in absent), 'cancelled runs must read ABSENT'
print('CONTROLS OK: positive', POS, '| negatives', len(neg), '| cancelled->ABSENT', len(absent))

# ---- M1 monitor outcome table ------------------------------------------------------------------
c = collections.Counter()
bym = collections.defaultdict(collections.Counter)
for rid, v in V.items():
    if v['infra'] in ('ABSENT', 'skipped'):
        k = 'no-verdict'
    elif v['infra'] == 'success':
        k = 'ok'
    elif v['ito']:
        k = 'timeout'
    else:
        k = 'red'
    c[k] += 1
    bym[v['created'][:7]][k] += 1
print('M1 infra step:', dict(c))
for m in sorted(bym):
    print('   ', m, dict(bym[m]))
print('M1 tests step ceiling kills:', sum(v['tto'] for v in V.values()), 'of', len(V))
print('M1 infra -P values:', dict(collections.Counter(v['P'] for v in V.values())))

# ---- M2/M3 leg data (-P 4) -----------------------------------------------------------------------
iv = {str(r['databaseId']): r for r in json.load(open(D + 'iv-push.json'))}
legs = rows('legs.tsv')
lc = collections.Counter(l[3] for l in legs)
print('M2 legs (push-to-main, since 2026-09-25):', len(legs), dict(lc), 'runs:', len({l[0] for l in legs}))

# a run with a cancelled leg has an incomplete RED set: leave it out of adjacency and of the paired set
cancelled_runs = {l[0] for l in legs if l[3] == 'cancelled'}
order = sorted({l[0] for l in legs} - cancelled_runs, key=lambda r: iv[r]['createdAt'])
idx = {r: i for i, r in enumerate(order)}
red = collections.defaultdict(set)
for l in open(D + 'red-headers.tsv'):
    d, rid, suite, rc, el = l.split()
    if rid in idx:
        red[suite].add(idx[rid])
iso = chain = 0
for s_, ix in red.items():
    for i in ix:
        if (i - 1 in ix) or (i + 1 in ix):
            chain += 1
        else:
            iso += 1
print('M3 suite-REDs: isolated', iso, 'chained', chain, '| isolated suite-events per push run (a run with 2 isolated suites counts twice; upper bound, includes one-commit regressions)', round(iso / len(order), 3), 'over', len(order), 'runs (', len(cancelled_runs), 'runs with a cancelled leg left out )')

# leg controls: a known-RED leg log yields a RED header, a known-green leg yields none
KNOWN_RED_JOB = '108669589945'   # cutover-inngest-workflow.test.sh, rc=1 (2026-09-27)
red_jobs = {l.rstrip('\n').split('\t')[1] for l in open(D + 'failed-legs.tsv')}
if KNOWN_RED_JOB in red_jobs:
    assert any(l.split()[1] for l in open(D + 'red-headers.tsv')), 'leg RED headers empty although failed legs exist'
else:
    print('NOTE: known-RED leg job', KNOWN_RED_JOB, 'is outside the pulled window; leg-control skipped')
assert any(l[3] == 'success' for l in legs), 'no green leg to serve as the negative control'

# ---- M4 paired same-sha ----------------------------------------------------------------------------
sha_legs = collections.defaultdict(set)
for l in open(D + 'red-headers.tsv'):
    d, rid, suite, rc, el = l.split()
    sha_legs[iv[rid]['headSha']].add(suite)
legsha = {iv[l[0]]['headSha'] for l in legs if l[0] not in cancelled_runs}
mon = {str(r['databaseId']): r for r in json.load(open(D + 'runs.json'))}
paired = par_only = mon_only = with_red = 0
for rid, m in mon.items():
    # a ceiling-killed monitor step has a right-censored RED set: leave it out of the paired set
    if m['headSha'] in legsha and V[rid]['infra'] not in ('ABSENT', 'skipped') and V[rid]['P'] == '1' and not V[rid]['ito']:
        paired += 1
        a_, b_ = set(V[rid]['reds']), sha_legs.get(m['headSha'], set())
        par_only += len(b_ - a_)
        mon_only += len(a_ - b_)
        with_red += 1 if (a_ or b_) else 0
print('M4 paired shas', paired, '| of which with at least one RED in either arm:', with_red, '| suites RED at -P4 but not at -P1:', par_only, '| RED at -P1 but not at -P4:', mon_only)
