import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import ts from "typescript";
import { parseSource } from "./approval/source-scan";
import { collapseSql, stripSqlComments } from "./helpers/sql-lex";

// Readers census for the #12714 held columns and for `repo_last_synced_at` (rulings W2, W5, D29(3), D29(9); AC20).
//
// The held columns are display-only: no gate, approval or push decision reads them. This census pins every app source
// file whose CODE (comments stripped) names `kb_sync_held_files` / `kb_sync_held_checked_at` / the RPC, with its role,
// and fails on any unlisted file, so a new reader has to be classified here first. It also pins:
//   - no tenant `.select(` string names a held column (the `authenticated` column grant excludes them, migration 187);
//     the Settings page reads them with the SERVICE client, the cc agent line through the member-checked RPC;
//   - `server/agent-runner.ts` names no held column (it uses `syncPull`'s fresh `{ heldFiles }` return, and, when that is
//     null, the stored columns only through `readStoredKbSyncHeld`, #12704 D41(e));
//   - `server/current-repo-url.ts` names no held column;
//   - every app reader and writer of `repo_last_synced_at` (W5: only `syncPull` stamps it on the sync path);
//   - #12704 D45(e): every `.from("workspaces")` chain that selects ALL columns (`.select("*")`, `.select()`), which
//     names no held column yet reads them, is listed in ALL_COLUMN_READERS with its role, and an unlisted one fails;
//   - the SQL rows read comment-stripped SQL with statement-anchored patterns (pattern P3-14), so a header comment that
//     names a token cannot stand in for the statement.
//
// Multi-line aware: the scan reads whole files, and `.select(` arguments are matched across line breaks.

const APP = path.join(__dirname, "..");
const ROOTS = ["app", "server", "lib", "components", "hooks", "scripts", "infra"];
// Root-level app files that run server code (a reader there would be missed by the directory walk).
const ROOT_FILES = ["middleware.ts", "instrumentation.ts"];
// #12704 D42: `kb_sync_pull_blocked` is a held column too (display-only, excluded from the tenant grant, read by the RPC).
const HELD_TOKEN = /\b(kb_sync_held_files|kb_sync_held_checked_at|kb_sync_pull_blocked|get_workspace_kb_sync_held)\b/;
const HELD_COLUMNS = ["kb_sync_held_files", "kb_sync_held_checked_at", "kb_sync_pull_blocked"];

function walk(dir: string, out: string[]): void {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const e of entries) {
    if (e === "node_modules" || e.startsWith(".")) continue;
    const p = path.join(dir, e);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(e) && !/\.(test|spec)\.(ts|tsx)$/.test(e) && !e.endsWith(".d.ts")) out.push(p);
  }
}

/** Source with block and line comments removed (a `//` right after `:` is kept, so URLs in strings survive). */
function code(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/(^|[^:])\/\/[^\n]*/g, "$1");
}

const files: string[] = [];
for (const r of ROOTS) walk(path.join(APP, r), files);
for (const f of ROOT_FILES) {
  try {
    if (statSync(path.join(APP, f)).isFile()) files.push(path.join(APP, f));
  } catch {
    // absent: nothing to scan
  }
}
const raw = new Map(files.map((f) => [path.relative(APP, f).split(path.sep).join("/"), readFileSync(f, "utf8")]));
const sources = new Map([...raw].map(([f, src]) => [f, code(src)]));

/** A migration file, comments stripped and whitespace collapsed (test/helpers/sql-lex.ts), for statement-anchored rows. */
const sql = (name: string): string => collapseSql(stripSqlComments(readFileSync(path.join(APP, "supabase/migrations", name), "utf8")));

const stringArg = (n: ts.Node | undefined): string | null =>
  n && (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) ? n.text : null;

/**
 * D45(e): the `.from("workspaces")` chains in one file that read EVERY column: a `.select()` with no argument, or one whose
 * column list has a bare `*`, anywhere after the `.from(...)` in the same chain (an `.update(...).select()` returns whole
 * rows too). Returns one entry per site. A non-literal column list is reported as `<computed>` (it may be `*`).
 */
function allColumnWorkspaceSelects(src: string, file: string): string[] {
  if (!/["'`]workspaces["'`]/.test(src)) return [];
  const sf = parseSource(src, file);
  const hits: string[] = [];
  const fromWorkspaces = (e: ts.Expression): boolean => {
    let x: ts.Expression = e;
    for (;;) {
      if (ts.isParenthesizedExpression(x) || ts.isNonNullExpression(x) || ts.isAsExpression(x)) x = x.expression;
      else if (ts.isCallExpression(x)) {
        const c = x.expression;
        if (ts.isPropertyAccessExpression(c) && c.name.text === "from" && stringArg(x.arguments[0]) === "workspaces") return true;
        x = c;
      } else if (ts.isPropertyAccessExpression(x)) x = x.expression;
      else return false;
    }
  };
  const visit = (n: ts.Node): void => {
    if (ts.isCallExpression(n) && ts.isPropertyAccessExpression(n.expression) && n.expression.name.text === "select" && fromWorkspaces(n.expression.expression)) {
      const arg = n.arguments[0];
      const cols = arg === undefined ? "*" : stringArg(arg);
      if (cols === null) hits.push(`${file} <computed>`);
      else if (cols.split(",").some((c) => c.trim() === "*")) hits.push(`${file} *`);
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return hits;
}

/**
 * D45(e): every app chain that selects all `workspaces` columns, so it carries the held columns without naming them. Each
 * is display-only, or it must not be one of these.
 */
const ALL_COLUMN_READERS: Record<string, string> = {
  "server/dsar-export.ts *":
    "reader: the Art. 15 DSAR export of the user's own workspaces (every column, service client); a copy of the user's data, read by no gate",
};

type Role = { role: string; required: boolean };

// Every app file whose code names a held column or the RPC, each required to name it (task 11.2 landed the session-sync
// writer; the review's Phase 0 moved it to server/kb-sync-held-refresh.ts, whose patch is the frozen `{ heldFiles,
// checkedAt }`, so only server/workspace-repo-mirror.ts maps it to the column names).
const HELD_MENTIONS: Record<string, Role> = {
  "app/(dashboard)/dashboard/settings/page.tsx": { role: "reader: Settings, service client, active workspace id", required: true },
  "server/workspace-repo-mirror.ts": {
    role: "type: KbSyncHeldRow (never WorkspaceRepoCols); writers: clearKbSyncHeldCols (disconnect and setup, D33(2)), writeKbSyncHeldCols (the held-count path, D29(1), D39)",
    required: true,
  },
  // #12704 (D41(e), D42): the ONE reader of the stored columns moved out of the dispatcher, shared by both runners.
  "server/kb-sync-held-agent-line.ts": {
    role: "reader: readStoredKbSyncHeld, get_workspace_kb_sync_held RPC on the caller's tenant client (cc line; legacy fallback)",
    required: true,
  },
};

describe("kb-sync held columns: readers census (#12714, AC20)", () => {
  it("scans the app (non-vacuity floor)", () => {
    expect(sources.size).toBeGreaterThan(200);
  });

  it("every file whose code names a held column or the RPC is classified, and the landed rows are present", () => {
    const mentioning = [...sources].filter(([, src]) => HELD_TOKEN.test(src)).map(([f]) => f).sort();
    const unlisted = mentioning.filter((f) => !(f in HELD_MENTIONS));
    expect(unlisted, `classify these held-column readers/writers in HELD_MENTIONS: ${unlisted.join(", ")}`).toEqual([]);
    for (const [f, { required }] of Object.entries(HELD_MENTIONS)) {
      if (required) expect(mentioning, f).toContain(f);
    }
    // D42: a file that names only the pull-blocked column is a held reader too (the RPC's third column).
    for (const col of HELD_COLUMNS) expect(HELD_TOKEN.test(`row.${col}`), col).toBe(true);
    expect(mentioning.filter((f) => /\bkb_sync_pull_blocked\b/.test(sources.get(f) ?? ""))).toEqual([
      "server/kb-sync-held-agent-line.ts",
      "server/workspace-repo-mirror.ts",
    ]);
  });

  it("disconnect and setup null the held columns through the separate best-effort clearKbSyncHeldCols (D33(2))", () => {
    // One clear per arm, counted (tests F8): disconnect has one; setup has two, the cloning flip and the reaped clone.
    const CLEARS: Record<string, number> = { "app/api/repo/disconnect/route.ts": 1, "app/api/repo/setup/route.ts": 2 };
    for (const [f, n] of Object.entries(CLEARS)) {
      const src = sources.get(f) ?? "";
      expect([...src.matchAll(/\bclearKbSyncHeldCols\(\s*serviceClient,\s*activeWorkspaceId\s*\)/g)], f).toHaveLength(n);
      // Never folded into the existing repo-column write (D33(2)).
      expect(HELD_TOKEN.test(src), f).toBe(false);
    }
    // The reaped-clone arm clears right after its not_connected write, before it returns (tests F8).
    expect(sources.get("app/api/repo/setup/route.ts") ?? "").toMatch(
      /err instanceof WorkspaceReapInProgressError\) \{[\s\S]*?repo_status: "not_connected",[\s\S]*?\}\);\s*await clearKbSyncHeldCols\(serviceClient, activeWorkspaceId\);\s*return;\s*\}/,
    );
  });

  it("session-sync writes the held columns only through writeKbSyncHeldCols, never folded into the stamp (D29(1))", () => {
    // The write lives in kb-sync-held-refresh.ts (Phase 0 move, WP3 body): ONE writeKbSyncHeldCols call, in `persist`,
    // which every entry (writeHeldFromIsolated, and refreshHeldCount through it) goes through with the frozen patch shape:
    // the caller's injected service client when given (session-sync's), else the process's.
    const refresh = sources.get("server/kb-sync-held-refresh.ts") ?? "";
    expect([...refresh.matchAll(/\bwriteKbSyncHeldCols\(/g)]).toHaveLength(1);
    expect(refresh).toMatch(/writeKbSyncHeldCols\(\s*service\(\),\s*workspaceId,\s*patch\s*\)/);
    expect([...refresh.matchAll(/\bpersist\(/g)]).toHaveLength(2); // its definition and its one call
    expect(refresh).toMatch(
      /persist\(service \? \(\) => service : getServiceClient,\s*a\.workspaceId,\s*\{\s*heldFiles: held === null \? null : held\.total,\s*checkedAt: a\.checkedAt,/,
    );
    // The pre-review entries are gone: one count-and-write entry (D39(a)).
    expect(refresh).not.toMatch(/\b(heldCountOn|writeHeldCount)\b/);
    expect(refresh).not.toMatch(/writeRepoColsToWorkspace/);
    // workspace-repo-mirror.ts maps the patch to the migration-187 columns (the pull-blocked one only when given, D42),
    // in the one shared held UPDATE body (simplicity F7).
    const mirror = sources.get("server/workspace-repo-mirror.ts") ?? "";
    expect(mirror).toMatch(
      /const row: KbSyncHeldRow = \{\s*kb_sync_held_files: patch\.heldFiles,\s*kb_sync_held_checked_at: checkedAt\s*\};/,
    );
    expect(mirror).toMatch(/if \(patch\.pullBlocked !== undefined\) row\.kb_sync_pull_blocked = patch\.pullBlocked;/);
    expect([...mirror.matchAll(/\.update\(row\)/g)]).toHaveLength(1);
    const src = sources.get("server/session-sync.ts") ?? "";
    // session-sync reaches the held write only through the moved helper, never writeKbSyncHeldCols directly.
    expect(src).not.toMatch(/\bwriteKbSyncHeldCols\b/);
    expect(src).toMatch(/import \{ writeHeldFromIsolated \} from "\.\/kb-sync-held-refresh"/);
    // syncPull and syncPush (D39(a)(b)): each with its injected service client and checked_at = its own ls-remote instant;
    // neither ever SETS a pull-blocked value (the self-heal's alone, D42). R2-B (verify-coverage #6): syncPull's
    // merged/up_to_date CLEARS it (null) and nothing else; syncPush leaves it alone.
    const heldCalls = [...src.matchAll(/\bwriteHeldFromIsolated\(\{((?:[^{}]|\{[^{}]*\})*)\}\)/g)].map((m) => m[1]);
    expect(heldCalls).toHaveLength(2);
    expect(heldCalls[0]).toMatch(/T: merged\.remote\.tip,[\s\S]*checkedAt: merged\.remote\.readAt,\s*service,/);
    expect(heldCalls[0]).toMatch(/\.\.\.\(clears \? \{ pullBlocked: null \} : \{\}\),\s*$/);
    expect([...heldCalls[0].matchAll(/pullBlocked/g)]).toHaveLength(1);
    expect(src).toMatch(/const clears = merged\.reason === "merged" \|\| merged\.reason === "up_to_date";/);
    expect(heldCalls[1]).toMatch(/T, headSha, checkedAt: readAt, service\s*$/);
    expect(heldCalls[1]).not.toMatch(/pullBlocked/);
    // The only `writeRepoColsToWorkspace(` call is the stamp, and it names no held column.
    const repoWrites = [...src.matchAll(/writeRepoColsToWorkspace\(([^)]*)\)/g)].map((m) => m[1]);
    expect(repoWrites.length).toBeGreaterThan(0);
    for (const args of repoWrites) expect(args).not.toMatch(/kb_sync_held/);
    expect(src).toMatch(/async function updateLastSynced\([^)]*\)[^{]*\{\s*await writeRepoColsToWorkspace\(service, workspaceId, \{\s*repo_last_synced_at: new Date\(\)\.toISOString\(\),\s*\}\);\s*\}/);
  });

  it("no gate, approval or push module reads the held columns (display-only)", () => {
    for (const [f, src] of sources) {
      if (!/^(server\/approval\/|server\/push-branch\.ts|server\/kb-sync-publish\.ts|server\/cc-github-push\.ts)/.test(f)) continue;
      expect(HELD_TOKEN.test(src), f).toBe(false);
    }
  });

  it("no .select( string outside the Settings page names a held column (no tenant select carries them)", () => {
    const offenders: string[] = [];
    for (const [f, src] of sources) {
      for (const m of src.matchAll(/\.select\(\s*(["'`])([\s\S]*?)\1/g)) {
        if (/kb_sync_(held_(files|checked_at)|pull_blocked)/.test(m[2]) && f !== "app/(dashboard)/dashboard/settings/page.tsx") offenders.push(f);
      }
    }
    expect(offenders).toEqual([]);
  });

  it("the Settings page selects the held count through the service client on the workspaces table", () => {
    const page = sources.get("app/(dashboard)/dashboard/settings/page.tsx") ?? "";
    expect(page).toMatch(/service\s*\.from\("workspaces"\)\s*\.select\(\s*"[^"]*\bkb_sync_held_files\b[^"]*"\s*,?\s*\)\s*\.eq\("id",\s*active\.workspaceId\)/);
    // The checked-at time is the agent line's "as of", not a Settings value.
    expect(page).not.toMatch(/kb_sync_held_checked_at/);
  });

  it("the select strings name only columns migration 187 created (comment-stripped, statement-anchored)", () => {
    const mig = sql("187_workspace_kb_sync_held_files.sql");
    const TYPES: Record<string, string> = { kb_sync_held_files: "integer", kb_sync_held_checked_at: "timestamptz", kb_sync_pull_blocked: "text" };
    for (const col of HELD_COLUMNS) {
      expect(mig, col).toMatch(new RegExp(`ALTER TABLE public\\.workspaces ADD COLUMN IF NOT EXISTS ${col} ${TYPES[col]}\\b`));
    }
    for (const [, src] of sources) {
      for (const m of src.matchAll(/\bkb_sync_(held_[a-z_]+|pull_blocked)\b/g)) expect(HELD_COLUMNS).toContain(m[0]);
    }
  });

  it("D45(e): every .from(\"workspaces\") chain that selects all columns is listed (they carry the held columns unnamed)", () => {
    const hits = [...raw].flatMap(([f, src]) => allColumnWorkspaceSelects(src, f)).sort();
    expect(hits, `classify these all-column workspaces readers in ALL_COLUMN_READERS: ${hits.join(", ")}`).toEqual(Object.keys(ALL_COLUMN_READERS).sort());
    // none of them is a gate, approval or push module (display-only, as the named readers above)
    for (const h of hits) expect(h).not.toMatch(/^(server\/approval\/|server\/push-branch\.ts|server\/kb-sync-publish\.ts|server\/cc-github-push\.ts)/);
  });

  it("known-positive (D45(e)): an unlisted all-column select fails, in each spelling; a named column list does not", () => {
    const f = "server/planted.ts";
    const plant = (body: string) => allColumnWorkspaceSelects(`export async function p(service: any) {\n${body}\n}\n`, f);
    expect(plant(`  return service\n    .from("workspaces")\n    .select("*")\n    .eq("id", "w");`)).toEqual([`${f} *`]);
    expect(plant(`  return service.from('workspaces').select();`)).toEqual([`${f} *`]);
    expect(plant("  return service.from(`workspaces`).eq(\"id\", 1).select(` *, members(*)`);")).toEqual([`${f} *`]);
    expect(plant(`  return service.from("workspaces").update({ a: 1 }).eq("id", "w").select();`)).toEqual([`${f} *`]);
    expect(plant(`  const cols = "*";\n  return service.from("workspaces").select(cols);`)).toEqual([`${f} <computed>`]);
    expect(plant(`  return service.from("workspaces").select("repo_url, repo_status");`)).toEqual([]);
    expect(plant(`  return service.from("users").select("*");`)).toEqual([]);
  });

  it("server/agent-runner.ts reads the count through syncPull's return, else the one stored reader (task 11.3b, D41(e))", () => {
    const src = sources.get("server/agent-runner.ts") ?? "";
    // simplicity F14 / quality P3-10: syncPull always resolves a SyncPullResult, so the result is not widened with `undefined`.
    expect(src).toMatch(/const pull: SyncPullResult = await syncPull\(userId, workspacePath, supabase\(\), activeWorkspaceId\)/);
    expect(src).not.toMatch(/SyncPullResult \| undefined|\bpull\?\./);
    expect(src).toMatch(/buildKbSyncHeldAgentLine\(\{\s*heldFiles: pull\.heldFiles,\s*checkedAt: pull\.checkedAt,/);
    expect(src).toMatch(/buildKbSyncMergeBlockedAgentLine\(pull\.pullReason, knownDefaultBranch\)/);
    // The fallback is keyed on the same active workspace and only when the fresh count is null.
    expect(src).toMatch(/=\s*pull\.heldFiles == null \? await readLegacyStoredKbSyncHeld\(userId, activeWorkspaceId\)/);
    expect(src).toMatch(/readStoredKbSyncHeld\(tenant, \{ userId, workspaceId, runner: "legacy" \}\)/);
  });

  it("server/agent-runner.ts and server/current-repo-url.ts name no held column", () => {
    for (const f of ["server/agent-runner.ts", "server/current-repo-url.ts"]) {
      expect(sources.has(f), f).toBe(true);
      expect(HELD_TOKEN.test(sources.get(f)!), f).toBe(false);
    }
  });
});

// Every app file whose code names `repo_last_synced_at`, with its role. W5: on the sync path only `syncPull` stamps
// it, so "Updated from GitHub" stays true. DB-side reader (not app code): claim_repo_clone_lock (migration 108) uses it
// as the clone lock's staleness clock, which is why setup stamps it on the cloning flip. DB-side writers (not app code):
// that RPC (the cloning flip) and set_repo_status (migration 113) on `ready`; both are repo setup, not the sync path.
const LAST_SYNCED_MENTIONS: Record<string, string> = {
  "app/(dashboard)/dashboard/settings/page.tsx": "reader: Owner 'Updated from GitHub' date line",
  "app/api/repo/status/route.ts": "reader: lastSyncedAt in the repo status payload",
  "app/api/repo/setup/route.ts": "writer: cloning flip (clone-lock clock), ready stamp, cleared on a reaped clone",
  "app/api/repo/disconnect/route.ts": "writer: cleared on disconnect",
  "server/session-sync.ts": "writer: updateLastSynced, syncPull only (W5; syncPush never stamps, AC17)",
  "server/workspace-repo-mirror.ts": "type: WorkspaceRepoCols",
};

describe("repo_last_synced_at: readers census (#12714, D29(9))", () => {
  it("every file whose code names repo_last_synced_at is listed", () => {
    const mentioning = [...sources].filter(([, src]) => /\brepo_last_synced_at\b/.test(src)).map(([f]) => f).sort();
    expect(mentioning).toEqual(Object.keys(LAST_SYNCED_MENTIONS).sort());
  });

  it("AC17: syncPush never stamps it; syncPull is the only updateLastSynced caller", () => {
    const src = sources.get("server/session-sync.ts") ?? "";
    const pushAt = src.indexOf("export async function syncPush(");
    const pullAt = src.indexOf("export async function syncPull(");
    expect(pushAt).toBeGreaterThan(-1);
    expect(pullAt).toBeGreaterThan(-1);
    const push = src.slice(pushAt);
    const pull = src.slice(pullAt, pushAt > pullAt ? pushAt : undefined);
    expect(push).not.toMatch(/\bupdateLastSynced\(|\brepo_last_synced_at\b/);
    expect(pull).toMatch(/\bupdateLastSynced\(service, workspaceId\)/);
    // The definition plus exactly one call site.
    expect([...src.matchAll(/\bupdateLastSynced\(/g)]).toHaveLength(2);
  });

  // pattern P3-14: comment-stripped, collapsed SQL (sql-lex drops the spaces around parentheses), anchored on the UPDATE
  // inside the function's own body (the match cannot run past its closing `$$;`), so a header comment matches nothing.
  const SET_REPO_STATUS_STAMP =
    /FUNCTION public\.set_repo_status\([^)]*\)(?:(?!\$\$;)[\s\S])*?UPDATE public\.workspaces SET [^;]*repo_last_synced_at = CASE WHEN p_status = 'ready' THEN now\(\)ELSE repo_last_synced_at END WHERE id = p_workspace_id;/;
  const CLONE_LOCK_CLOCK =
    /FUNCTION public\.claim_repo_clone_lock\(p_workspace_id uuid\)(?:(?!\$\$;)[\s\S])*?UPDATE public\.workspaces SET [^;]*WHERE id = p_workspace_id AND[^;]*repo_last_synced_at IS NULL OR repo_last_synced_at < now\(\)- interval '5 minutes'/;

  it("the DB-side writer set_repo_status stamps it only on ready (migration 113)", () => {
    expect(sql("113_set_repo_status_writes_workspace_repo_error.sql")).toMatch(SET_REPO_STATUS_STAMP);
  });

  it("the DB-side reader is the clone lock (migration 108): its staleness clock in the claim's WHERE", () => {
    expect(sql("108_repo_clone_self_heal_rpc.sql")).toMatch(CLONE_LOCK_CLOCK);
  });

  it("known-positive (pattern P3-14): the SQL rows do not match tokens that only a comment carries", () => {
    const commentOnly = collapseSql(
      stripSqlComments(
        "-- claim_repo_clone_lock(p_workspace_id uuid) uses repo_last_synced_at IS NULL OR repo_last_synced_at < now() - interval '5 minutes'\n" +
          "/* FUNCTION public.set_repo_status(p uuid) UPDATE public.workspaces SET repo_last_synced_at = CASE WHEN p_status = 'ready' THEN now() ELSE repo_last_synced_at END WHERE id = p_workspace_id; */\n" +
          "CREATE OR REPLACE FUNCTION public.claim_repo_clone_lock(p_workspace_id uuid) RETURNS boolean AS $$ BEGIN RETURN true; END; $$;",
      ),
    );
    expect(commentOnly).not.toMatch(CLONE_LOCK_CLOCK);
    expect(commentOnly).not.toMatch(SET_REPO_STATUS_STAMP);
  });
});
