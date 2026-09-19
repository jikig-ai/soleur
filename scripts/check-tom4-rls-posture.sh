#!/usr/bin/env bash
# check-tom4-rls-posture.sh — mechanical gate over the RLS posture that
# `knowledge-base/legal/data-processing-agreement-template.md` warrants to
# counterparties (Schedule 4 TOM categories 4 and 7, and the §9 access-control
# bullet). Schedule 4 becomes Annex II to the Module 2/3 SCCs on execution, so
# every table name and predicate in it is a contractual representation.
#
# WHY THIS EXISTS. The instrument previously asserted `auth.uid() = user_id` RLS
# on `tc_acceptances`, a table that runs RLS-enabled with ZERO policies, and
# attributed `auth.uid() = founder_id` to `scope_grants` and `audit_byok_use`,
# a predicate both lost at migration `059_workspace_keyed_rls_sweep`. Both
# survived prose review. The CLO ruling at
# `knowledge-base/legal/audits/2026-09-15-clo-ruling-dpa-schedule-4-tom-4-rls-posture.md`
# requires this gate as the anti-recurrence measure: the enumeration of table
# names stays in the instrument, and a name may not enter it without a pinned
# invariant here.
#
# TWO MEASUREMENT RULES, each earned by a wrong reading during that ruling:
#
#   (1) NET OF DROPS, KEYED BY POLICY NAME — never a cumulative count. A
#       `DROP POLICY` + `CREATE POLICY` pair leaves the count identical and the
#       predicate inverted. That is exactly how the founder-keyed claim survived
#       a count-based check twice, by two independent readers.
#   (2) REPLAY IN STATEMENT ORDER, not file-at-a-time by statement kind. The
#       corpus idiom is `DROP POLICY IF EXISTS x ON t;` immediately followed by
#       `CREATE POLICY x ON t`. A two-pass scan applies the drop AFTER the
#       create and reports a live policy as absent.
#
# The instrument self-test at A0 refuses to run unless the parser finds policies
# on five tables that certainly have them. An enumeration of things that LACK a
# property fails by failing to FIND the property, which is byte-identical to
# absence — so this script may not report an absence it has not first proven it
# can detect a presence with.
#
# Usage:  bash scripts/check-tom4-rls-posture.sh [--verbose] [--root <dir>]
#         --root points the gate at a COPY of the tree. It exists so
#         check-tom4-rls-posture.test.sh can drive every assertion red against a
#         throwaway copy without ever mutating the real migration corpus. A guard
#         that has never been driven red is vacuous, and mutating live migrations
#         to prove it reddens is not an acceptable way to find out.
# Exit:   0 = PASS, 1 = one or more assertions FAILED, 2 = instrument self-test
#         failed (no verdict was obtained — this is NOT a pass).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { printf 'FATAL: cannot cd to repo root\n' >&2; exit 2; }

VERBOSE=0
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=1; shift ;;
    --root)    ROOT="${2:-}"; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [[ -n "$ROOT" ]]; then
  # Absolute only: the script has already cd'd to REPO_ROOT, so a relative
  # --root would silently resolve against the real tree instead of the copy.
  [[ "$ROOT" == /* ]] || { printf 'FATAL: --root must be an absolute path, got %s\n' "$ROOT" >&2; exit 2; }
  cd "$ROOT" || { printf 'FATAL: --root %s is not a directory\n' "$ROOT" >&2; exit 2; }
fi

python3 - "$VERBOSE" <<'PYEOF'
import collections, glob, os, re, sys

VERBOSE = sys.argv[1] == "1"
MIGDIR  = "apps/web-platform/supabase/migrations"
DPA     = "knowledge-base/legal/data-processing-agreement-template.md"
REGISTER= "knowledge-base/legal/article-30-register.md"
DPD     = "docs/legal/data-protection-disclosure.md"
DPD_MIR = "plugins/soleur/docs/pages/legal/data-protection-disclosure.md"

FAILURES = []
ASSERTED = 0

def check(aid, ok, what, fix):
    """Record one assertion. Never routes through a helper it backstops."""
    global ASSERTED
    ASSERTED += 1
    if ok:
        if VERBOSE:
            sys.stdout.write("  ok   %-4s %s\n" % (aid, what))
    else:
        FAILURES.append((aid, what, fix))
        sys.stderr.write("FAIL: %s %s -> %s\n" % (aid, what, fix))

# ---------------------------------------------------------------- corpus read
def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()

def strip_comments(text):
    """Remove `-- ...` line comments and /* ... */ blocks. A commented-out
    CREATE POLICY is not a policy, and migration 038's prose about
    FORCE ROW LEVEL SECURITY is not a FORCE clause."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return "\n".join(re.sub(r'--.*$', '', line) for line in text.splitlines())

MIGRATIONS = sorted(
    m for m in glob.glob(os.path.join(MIGDIR, "*.sql"))
    # Up-migrations only: a .down.sql undoes state that was never applied here.
    if not re.search(r'\.down\.sql$|rollback', os.path.basename(m), re.I)
)
if len(MIGRATIONS) < 100:
    sys.stderr.write("INSTRUMENT: only %d migrations found under %s — refusing "
                     "to report a verdict\n" % (len(MIGRATIONS), MIGDIR))
    raise SystemExit(2)

RAW     = {m: read(m) for m in MIGRATIONS}
BODY    = {m: strip_comments(RAW[m]) for m in MIGRATIONS}
ALL_RAW = "\n".join(RAW[m] for m in MIGRATIONS)
ALL     = "\n".join(BODY[m] for m in MIGRATIONS)

# A policy name is a bare identifier OR a double-quoted string that may contain
# spaces. Migration 001 has `create policy "Users can manage own API keys" on
# public.api_keys` — a bare-identifier class silently misses it and then reports
# api_keys as zero-policy, which is how an earlier enumeration named two
# correctly-policied tables. `re.I` is required: migration 001 is lower-case.
IDENT = r'(?:"[^"]+"|[A-Za-z0-9_]+)'
RX = [
    ("create_policy", re.compile(r'CREATE\s+POLICY\s+(' + IDENT + r')\s+ON\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?', re.I)),
    ("drop_policy",   re.compile(r'DROP\s+POLICY\s+(?:IF\s+EXISTS\s+)?(' + IDENT + r')\s+ON\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?', re.I)),
    # Anchored at statement start so `ALTER PUBLICATION ... DROP TABLE public.messages`
    # is not read as a table drop. Unanchored, that one line deletes `messages`
    # and every policy on it from the model — and the resulting count looks
    # plausible, which is why it went unnoticed in the ruling's own figures.
    ("create_table",  re.compile(r'(?:^|;)\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?', re.I | re.M)),
    ("drop_table",    re.compile(r'(?:^|;)\s*DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?', re.I | re.M)),
    ("enable_rls",    re.compile(r'ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY', re.I)),
]

live      = collections.defaultdict(dict)   # table -> {policy name: predicate text}
effective_drops = []                        # drops that actually removed a live policy
tables    = set()                           # net of DROP TABLE
rls       = set()                           # ENABLE ROW LEVEL SECURITY seen

def predicate_after(body, pos):
    """The USING / WITH CHECK text of the CREATE POLICY starting at `pos`,
    to the terminating semicolon. Assertion 20 requires the replay to carry the
    predicate, not merely the name: a rename with the same predicate and a
    re-predicate under the same name are different events."""
    end = body.find(";", pos)
    stmt = body[pos:end if end != -1 else len(body)]
    return " ".join(stmt.split())

for m in MIGRATIONS:
    body = BODY[m]
    events = []
    for kind, rx in RX:
        for mo in rx.finditer(body):
            events.append((mo.start(), kind, mo.groups()))
    # Statement order within the file, file order across the corpus.
    for pos, kind, g in sorted(events, key=lambda e: e[0]):
        if kind == "create_policy":
            live[g[1]][g[0].strip('"')] = predicate_after(body, pos)
        elif kind == "drop_policy":
            if live[g[1]].pop(g[0].strip('"'), None) is not None:
                effective_drops.append((os.path.basename(m), g[1], g[0].strip('"')))
        elif kind == "create_table":
            tables.add(g[0])
        elif kind == "drop_table":
            tables.discard(g[0]); live.pop(g[0], None); rls.discard(g[0])
        elif kind == "enable_rls":
            rls.add(g[0])

def policies(t):
    return set(live.get(t, {}).keys())

# ------------------------------------------------- A0. INSTRUMENT SELF-TEST
# Positive controls. Each of these tables certainly carries policies; if the
# parser reports zero for any of them it is broken, and every absence it would
# go on to report is unfalsifiable. Refuse to emit a verdict at all.
CONTROLS = ("conversations", "api_keys", "users", "scope_grants", "action_sends", "messages")
broken = [c for c in CONTROLS if not policies(c)]
if broken:
    sys.stderr.write("INSTRUMENT SELF-TEST FAILED: the policy parser found zero "
                     "policies on %s. An absence this parser reports is "
                     "indistinguishable from a parse failure. No verdict.\n"
                     % ", ".join(broken))
    raise SystemExit(2)
# The self-test must also prove the replay APPLIES drops; otherwise `live` is
# just `create` and the net-of-drops contract is vacuous. Test the MECHANISM
# (did any drop actually remove a live policy?), not a proxy for it. An earlier
# revision asserted that `scope_grants_owner_select` was absent — which a
# legitimate re-introduction of that policy falsifies, turning a real assertion-9
# finding into a spurious "the instrument is broken" with no actionable message.
if not effective_drops:
    sys.stderr.write("INSTRUMENT SELF-TEST FAILED: the replay applied %d policy "
                     "creations and not one effective DROP. Drops are not being "
                     "applied; net-of-drops is vacuous and every predicate below "
                     "may be a superseded one. No verdict.\n"
                     % sum(len(v) for v in live.values()))
    raise SystemExit(2)

# ------------------------------------------------------------- the pinned sets
SHAPE_IV = {  # TOM 4 shape (iv): RLS enabled, ZERO policies, Customer Data
    "tc_acceptances", "workspace_member_actions", "dsar_export_audit_pii",
    "tenant_deploy_audit", "denied_jti", "mint_rate_window", "runtime_mint_intent",
}
# Zero-policy tables that hold no Customer Data. Assertion 4 requires every
# zero-policy table to sit in exactly one of these two lists, so a NEW
# zero-policy table fails the build until someone classifies it.
NOT_CUSTOMER_DATA = {
    "_schema_migrations", "flag_flip_audit", "probe_tokens",
    "processed_github_events", "processed_resend_events", "processed_stripe_events",
    "statutory_repin_send", "tool_attempts",
}
WORKSPACE_KEYED = {
    "scope_grants":           "scope_grants_workspace_member_select",
    "audit_byok_use":         "audit_byok_use_workspace_member_select",
    "audit_github_token_use": "audit_github_token_use_workspace_member_select",
}
BUCKETS = {"chat-attachments", "dsar-exports", "workspace-logos"}

created_rls = tables & rls
zero_policy = {t for t in rls if not policies(t)}

# ============================================================== STRUCTURAL
check("1", not (tables - rls),
      "every corpus-created public table has ENABLE ROW LEVEL SECURITY (%d/%d)"
      % (len(created_rls), len(tables)),
      "tables missing it: %s — enable RLS, or the §9/TOM-4 universal is false"
      % sorted(tables - rls))

# Anchored on the DDL form, not the bare phrase: migration 038 discusses
# FORCE ROW LEVEL SECURITY inside a `COMMENT ON TABLE ... IS '...'` string
# literal, which the `--` comment stripper cannot reach. A phrase-anchored
# check fails on the very comment that documents why the clause is absent.
force = [mo.group(0) for mo in re.finditer(
    r'ALTER\s+TABLE\s+[^;]*?\bFORCE\s+ROW\s+LEVEL\s+SECURITY', ALL, re.I | re.S)]
check("2", not force,
      "no ALTER TABLE ... FORCE ROW LEVEL SECURITY anywhere (owner-bypass is load-bearing, migration 038)",
      "found in DDL: %s — TOM 4 shape (iv) states the owner reaches these tables" % force)

# ====================================================== SHAPE (iv) ENUMERATION
check("3", zero_policy == (SHAPE_IV | NOT_CUSTOMER_DATA),
      "net-zero-policy RLS-enabled set is exactly the %d pinned tables"
      % len(SHAPE_IV | NOT_CUSTOMER_DATA),
      "unexpected: %s / missing: %s"
      % (sorted(zero_policy - SHAPE_IV - NOT_CUSTOMER_DATA),
         sorted((SHAPE_IV | NOT_CUSTOMER_DATA) - zero_policy)))

unclassified = zero_policy - SHAPE_IV - NOT_CUSTOMER_DATA
check("4", not unclassified,
      "every zero-policy table is classified (shape (iv) list, or not-Customer-Data list)",
      "UNCLASSIFIED: %s — add each to TOM 4 shape (iv) in %s, or to "
      "NOT_CUSTOMER_DATA in this script with a reason. Without this the "
      "enumeration re-stales silently and every other assertion is decoration."
      % (sorted(unclassified), DPA))

bad5 = {t: sorted(policies(t)) for t in SHAPE_IV if policies(t)}
check("5", not bad5,
      "each of the %d shape-(iv) tables has exactly zero live policies" % len(SHAPE_IV),
      "these now carry policies: %s — TOM 4 calls them service-role-only" % bad5)

# ================================================================= PRINCIPALS
def grants_to(role, obj=None):
    pat = r'GRANT\s+[^;]*?\bON\s+(?:TABLE\s+)?(?:FUNCTION\s+)?[^;]*?\bTO\s+[^;]*?\b' + role + r'\b'
    return [mo.group(0) for mo in re.finditer(pat, ALL, re.I | re.S)]

auth_admin_tables = set()
for mo in re.finditer(r'GRANT\s+[^;]*?\bON\s+(?:TABLE\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+TO\s+[^;]*?\bsupabase_auth_admin\b',
                      ALL, re.I | re.S):
    auth_admin_tables.add(mo.group(1))
check("6", auth_admin_tables & SHAPE_IV == {"runtime_mint_intent"},
      "supabase_auth_admin reaches exactly one shape-(iv) table (runtime_mint_intent)",
      "shape-(iv) tables granted to supabase_auth_admin: %s — the corrigendum "
      "names runtime_mint_intent alone" % sorted(auth_admin_tables & SHAPE_IV))

check("7", re.search(r'GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+(?:public\.)?purge_workspace_member_actions\s*\(\s*\)\s+TO\s+postgres',
                     ALL, re.I) is not None,
      "purge_workspace_member_actions is granted to postgres (the owner-bypass retention path)",
      "not found — TOM 4 shape (iv) states postgres reaches these ledgers; if "
      "that grant is gone, the instrument now overstates the principal set")

client_roles = re.compile(r'\bTO\s+[^;]*?\b(anon|authenticated)\b', re.I)
bad8 = []
for mo in re.finditer(r'GRANT\s+[^;]*?\bON\s+(?:TABLE\s+)?(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s+TO\s+[^;]*?;',
                      ALL, re.I | re.S):
    if mo.group(1) in SHAPE_IV and client_roles.search(mo.group(0)):
        bad8.append(mo.group(0).strip())
check("8", not bad8,
      "no shape-(iv) TABLE is granted to anon or authenticated",
      "client-reachable grants found: %s — shape (iv) warrants that no "
      "client-held credential reaches these tables" % bad8)

# ================================================================= PREDICATES
ok9 = True
detail9 = []
for tab, expected in WORKSPACE_KEYED.items():
    got = policies(tab)
    if got != {expected}:
        ok9 = False
        detail9.append("%s = %s (want {%s})" % (tab, sorted(got), expected))
    pred = live.get(tab, {}).get(expected, "")
    if "is_workspace_member" not in pred:
        ok9 = False
        detail9.append("%s: %s does not key on is_workspace_member" % (tab, expected))
    # The dropped founder policy must not be live again under its old name.
    if tab + "_owner_select" in got:
        ok9 = False
        detail9.append("%s_owner_select is LIVE again — move the table back to "
                       "TOM 4 shape (ii) in the same commit" % tab)
restrictive_059 = len(re.findall(r'AS\s+RESTRICTIVE', BODY.get(os.path.join(MIGDIR, "059_workspace_keyed_rls_sweep.sql"), ""), re.I))
if restrictive_059:
    ok9 = False
    detail9.append("059 now has %d AS RESTRICTIVE clause(s); a restrictive "
                   "policy silently inverts the combination TOM 4 describes" % restrictive_059)
check("9", ok9,
      "scope_grants / audit_byok_use / audit_github_token_use each have exactly "
      "one live policy, workspace-keyed; the *_owner_select names are not live; "
      "zero AS RESTRICTIVE in 059",
      "; ".join(detail9))

check("10", policies("template_authorizations") == {"template_authorizations_owner_select"},
      "template_authorizations carries the founder-keyed policy alone (TOM 4 shape (ii))",
      "live set is %s — shape (ii) names this table and no other"
      % sorted(policies("template_authorizations")))

as_preds = live.get("action_sends", {})
check("11", as_preds and all(re.search(r'user_id\s*=\s*auth\.uid\(\)', p) for p in as_preds.values()),
      "every action_sends policy keys on user_id = auth.uid() (TOM 4 shape (iii))",
      "predicates: %s" % sorted(as_preds))

iwm = re.search(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.is_workspace_member\s*\([^)]*\)(.{0,400}?)AS\s+\$\$',
                ALL, re.I | re.S)
iwm_body = iwm.group(1) if iwm else ""
check("12",
      bool(iwm)
      and re.search(r'LANGUAGE\s+plpgsql', iwm_body, re.I)
      and re.search(r'SECURITY\s+DEFINER', iwm_body, re.I)
      and re.search(r'SET\s+search_path\s*=\s*public\s*,\s*pg_temp', iwm_body, re.I),
      "is_workspace_member is LANGUAGE plpgsql + SECURITY DEFINER + search_path = public, pg_temp",
      "declaration reads: %r — a switch to `sql STABLE` lets the planner inline "
      "it and dissolves the definer boundary while every other assertion still "
      "passes (migration 053 says so in terms)" % iwm_body.strip()[:200])

# =============================================================== GRANT MATRIX
def granted_roles(fn):
    """Net EXECUTE grantees of `fn`, replayed in migration order — GRANT and
    REVOKE both. Assertion 15 is order-sensitive: migration 068 granted
    is_jti_denied to `authenticated` and 069 revoked it, so a cumulative grep
    reports a live oracle that does not exist."""
    roles = set()
    for m in MIGRATIONS:
        for mo in re.finditer(r'(GRANT|REVOKE)\s+(?:ALL|EXECUTE)[^;]*?\bON\s+FUNCTION\s+(?:public\.)?'
                              + re.escape(fn) + r'\s*\([^)]*\)\s*(?:TO|FROM)\s+([^;]+);',
                              BODY[m], re.I | re.S):
        # FROM-list and TO-list are both comma-separated role lists.
            found = {r.strip().lower() for r in mo.group(2).split(",")}
            if mo.group(1).upper() == "GRANT":
                roles |= found
            else:
                roles -= found
    return roles

SERVICE_ONLY = ("accept_terms", "anonymise_tc_acceptances",
                "write_dsar_export_audit_pii", "write_tenant_deploy_audit")
bad13 = {}
for fn in SERVICE_ONLY:
    r = granted_roles(fn)
    if r - {"service_role"}:
        bad13[fn] = sorted(r)
check("13", not bad13,
      "the four shape-(iv) write RPCs are granted to service_role only",
      "these have other grantees: %s — TOM 4 warrants service-role-only writes" % bad13)

r14 = granted_roles("list_workspace_member_actions")
check("14", "authenticated" in r14,
      "list_workspace_member_actions is granted to authenticated (the one client-reachable shape-(iv) RPC)",
      "grantees are %s — TOM 4 names this RPC as the owner-checked read path" % sorted(r14))

r15 = granted_roles("is_jti_denied")
check("15", "authenticated" not in r15,
      "is_jti_denied is NOT granted to authenticated on a net replay (068 granted, 069 revoked)",
      "net grantees are %s — a live grant is an arbitrary-UUID deny-list oracle "
      "with no authorisation check" % sorted(r15))

# ======================================================== SHAPE (v) AND TOM 7
corpus_buckets = set(re.findall(r"bucket_id\s*=\s*'([a-z0-9-]+)'", ALL, re.I))
dpa_text = read(DPA)
check("16", corpus_buckets == BUCKETS and all(b in dpa_text for b in BUCKETS),
      "the storage buckets the corpus policies are exactly those TOM 4 shape (v) names",
      "corpus has %s, TOM 4 shape (v) pins %s, and each must appear in %s"
      % (sorted(corpus_buckets), sorted(BUCKETS), DPA))

worm_fns = set(re.findall(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z_]+_(?:no_mutate|no_update|no_delete))',
                          ALL, re.I))
worm_tables = {re.sub(r'_(no_mutate|no_update|no_delete)$', '', f) for f in worm_fns}
named_in_tom7 = set(re.findall(r'`([a-z_]+_(?:no_mutate|no_update|no_delete))`', dpa_text))
check("17", len(worm_fns) == 20 and len(worm_tables) == 19 and named_in_tom7 <= worm_fns,
      "WORM trigger functions number 20 across 19 ledgers, and every function TOM 7 names exists",
      "corpus has %d functions over %d ledgers; TOM 7 names these that do not "
      "exist: %s" % (len(worm_fns), len(worm_tables), sorted(named_in_tom7 - worm_fns)))

# ================================================================= CITATIONS
cited_migrations = set(re.findall(r'`(\d{3}_[a-z0-9_]+)`', dpa_text))
on_disk = {os.path.basename(m)[:-4] for m in MIGRATIONS}
missing18 = sorted(c for c in cited_migrations if c not in on_disk)
check("18", not missing18,
      "every migration filename cited in the DPA template exists on disk",
      "cited but absent: %s" % missing18)

# ============================== 19. THE CLASS CHECK, NOT THE INSTANCE CHECK
# No universal quantifier within five words of a table noun, across all four
# documents. Indexed by PROPOSITION, not by remembered phrasing: the three real
# sites read `every table`, `every database table` and `every multi-tenant
# table`, and a sweep anchored on the first found one of three.
UNIVERSAL = re.compile(
    r'\b(every|all|each)\b(?:\W+\w+){0,5}?\W+\b(tables?)\b', re.I)
# The quantifier must range over THE SCHEMA. Three readings are not that, and
# each was a false positive on this gate's first run:
#   - a determiner before the noun ("every read of THIS table") quantifies the
#     reads, not the tables;
#   - a numeral ("all THREE tables") is a bounded enumeration, not a universal;
#   - "every table named in TOM category 4" ranges over a list, not the schema.
# The corrected scoped form ("every table the migration corpus creates in the
# public schema") is the shape this gate exists to produce, so it is exempt;
# and a passage quoting the RETRACTED claim in order to withdraw it is prose
# about history, exempted on the same footing as assertion 21's dropped-policy
# citations.
EXEMPT = re.compile(
    r'(migration corpus creates|corpus creates in the `?public`?'
    r'|every (?:co-)?member'
    r'|\b(?:every|all|each)\b(?:\W+\w+){0,5}?\W+\b(?:this|that|the|these|those|'
    r'one|two|three|four|five|six|seven|eight|nine|ten|\d+)\W+tables?\b'
    r'|\btables?\s+named\b'
    r'|\b(?:asserted|previously|prior text|retracted|withdrawn|corrected|'
    r'superseded|the prior|earlier draft)\b)', re.I)
bad19 = []
for path in (DPA, REGISTER, DPD, DPD_MIR):
    if not os.path.exists(path):
        continue
    for n, line in enumerate(read(path).splitlines(), 1):
        if not re.search(r'\b(RLS|Row[- ]Level Security|Row Level Security)\b', line, re.I):
            continue
        for mo in UNIVERSAL.finditer(line):
            window = line[max(0, mo.start() - 120):mo.end() + 120]
            if EXEMPT.search(window):
                continue
            bad19.append("%s:%d: %s" % (path, n, mo.group(0)))
check("19", not bad19,
      "no unscoped RLS universal ('every/all/each ... table') in the four legal documents",
      "unscoped universals: %s — scope each to what the migration corpus "
      "creates, or state the shape" % bad19)

# =========== 20. THE REPLAY CARRIES PREDICATES, NOT JUST NAMES (structural)
carried = sum(1 for t in live for p in live[t] if live[t][p])
check("20", carried == sum(len(v) for v in live.values()) and carried > 0,
      "the net-of-drops replay retained a predicate for every live policy (%d)" % carried,
      "some live policies carry no predicate text — assertion 22 cannot run, and "
      "a re-predicate under an unchanged name would pass unnoticed")

# ======== 21. EVERY POLICY NAME CITED IN THE LEGAL CORPUS RESOLVES TO LIVE
LEGAL_GLOBS = ("knowledge-base/legal/**/*.md", "docs/legal/**/*.md",
               "plugins/soleur/docs/pages/legal/**/*.md")
POLICY_CITE = re.compile(r'`([a-z_]+_(?:owner_select|owner_insert|owner_update|owner_delete|'
                         r'workspace_member_select|workspace_member_insert|shared_select|'
                         r'no_mutate|no_update|no_delete))`')
all_live = {p for t in live for p in live[t]} | worm_fns
bad21 = []
for g in LEGAL_GLOBS:
    for path in glob.glob(g, recursive=True):
        for n, line in enumerate(read(path).splitlines(), 1):
            for mo in POLICY_CITE.finditer(line):
                name = mo.group(1)
                if name in all_live:
                    continue
                # A citation explicitly framed as dropped/superseded is correct
                # prose about history, not a stale claim.
                if re.search(r'\b(dropped|drop(?:ped|s)? |replaced|superseded|removed|'
                             r'no longer|prior text|previously|withdrawn)\b', line, re.I):
                    continue
                bad21.append("%s:%d: %s" % (path, n, name))
check("21", not bad21,
      "every policy name cited in the legal corpus is live, or is framed as dropped",
      "stale policy citations: %s — a legal document naming a policy the schema "
      "does not carry is the defect this gate exists to stop" % bad21)

# ====== 22. TOM 4's TABLE/PREDICATE ATTRIBUTIONS MATCH THE LIVE PREDICATE
SHAPES = {
    "is_workspace_member": list(WORKSPACE_KEYED),
    "founder_id":          ["template_authorizations"],
    "user_id":             ["action_sends"],
}
bad22 = []
for key, tabs in SHAPES.items():
    for t in tabs:
        preds = live.get(t, {})
        if not preds:
            bad22.append("%s: no live policy, but TOM 4 attributes %s" % (t, key))
            continue
        if not any(key in p for p in preds.values()):
            bad22.append("%s: live predicate does not mention %s (%s)"
                         % (t, key, sorted(preds)))
check("22", not bad22,
      "every table/predicate pair TOM 4 asserts matches the live predicate text",
      "mismatches: %s — a name may not stay in the instrument once its "
      "predicate has moved" % bad22)

# ------------------------------------------------------------------ verdict
# The floor and the verdict are emitted with sys.stdout.write + an explicit exit
# code, never through check() — a helper must not be the thing that reports
# whether the helper ran (ADR-193).
FLOOR = 22
if ASSERTED < FLOOR:
    sys.stderr.write("INSTRUMENT: only %d of %d assertions executed. A partial "
                     "run is not a pass.\n" % (ASSERTED, FLOOR))
    raise SystemExit(2)

if FAILURES:
    sys.stdout.write("check-tom4-rls-posture: %d assertion(s) FAILED of %d "
                     "(%d tables, %d RLS-enabled, %d zero-policy)\n"
                     % (len(FAILURES), ASSERTED, len(tables), len(rls), len(zero_policy)))
    raise SystemExit(1)

sys.stdout.write("check-tom4-rls-posture: %d/%d assertions PASS "
                 "(%d tables created, %d RLS-enabled, %d zero-policy, "
                 "%d WORM functions)\n"
                 % (ASSERTED, FLOOR, len(tables), len(rls), len(zero_policy), len(worm_fns)))
raise SystemExit(0)
PYEOF
