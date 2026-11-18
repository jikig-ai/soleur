import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

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
//   - every app reader and writer of `repo_last_synced_at` (W5: only `syncPull` stamps it on the sync path).
//
// Multi-line aware: the scan reads whole files, and `.select(` arguments are matched across line breaks.

const APP = path.join(__dirname, "..");
const ROOTS = ["app", "server", "lib", "components", "hooks", "scripts", "infra"];
// Root-level app files that run server code (a reader there would be missed by the directory walk).
const ROOT_FILES = ["middleware.ts", "instrumentation.ts"];
const HELD_TOKEN = /\b(kb_sync_held_files|kb_sync_held_checked_at|get_workspace_kb_sync_held)\b/;

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
const sources = new Map(files.map((f) => [path.relative(APP, f).split(path.sep).join("/"), code(readFileSync(f, "utf8"))]));

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
  });

  it("disconnect and setup null the held columns through the separate best-effort clearKbSyncHeldCols (D33(2))", () => {
    for (const f of ["app/api/repo/disconnect/route.ts", "app/api/repo/setup/route.ts"]) {
      expect(sources.get(f) ?? "", f).toMatch(/\bclearKbSyncHeldCols\(\s*serviceClient,\s*activeWorkspaceId\s*\)/);
      // Never folded into the existing repo-column write (D33(2)).
      expect(HELD_TOKEN.test(sources.get(f) ?? ""), f).toBe(false);
    }
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
    // neither sets the pull-blocked column (the self-heal's alone, D42).
    const heldCalls = [...src.matchAll(/\bwriteHeldFromIsolated\(\{([^}]*)\}\)/g)].map((m) => m[1]);
    expect(heldCalls).toHaveLength(2);
    expect(heldCalls[0]).toMatch(/T: merged\.remote\.tip,[\s\S]*checkedAt: merged\.remote\.readAt,\s*service,/);
    expect(heldCalls[1]).toMatch(/T, headSha, checkedAt: readAt, service\s*$/);
    for (const args of heldCalls) expect(args).not.toMatch(/pullBlocked/);
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
        if (/kb_sync_held_(files|checked_at)/.test(m[2]) && f !== "app/(dashboard)/dashboard/settings/page.tsx") offenders.push(f);
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

  it("the select strings name only columns migration 187 created", () => {
    const mig = readFileSync(path.join(APP, "supabase/migrations/187_workspace_kb_sync_held_files.sql"), "utf8");
    for (const col of ["kb_sync_held_files", "kb_sync_held_checked_at"]) expect(mig).toContain(`ADD COLUMN IF NOT EXISTS ${col}`);
    for (const [, src] of sources) {
      for (const m of src.matchAll(/\bkb_sync_held_[a-z_]+\b/g)) {
        expect(["kb_sync_held_files", "kb_sync_held_checked_at"]).toContain(m[0]);
      }
    }
  });

  it("server/agent-runner.ts reads the count through syncPull's return, else the one stored reader (task 11.3b, D41(e))", () => {
    const src = sources.get("server/agent-runner.ts") ?? "";
    expect(src).toMatch(/const pull: SyncPullResult \| undefined = await syncPull\(userId, workspacePath, supabase\(\), activeWorkspaceId\)/);
    expect(src).toMatch(/buildKbSyncHeldAgentLine\(\{\s*heldFiles: pull\?\.heldFiles \?\? null,\s*checkedAt: pull\?\.checkedAt \?\? null,/);
    expect(src).toMatch(/buildKbSyncMergeBlockedAgentLine\(pull\?\.pullReason \?\? null, knownDefaultBranch\)/);
    // The fallback is keyed on the same active workspace and only when the fresh count is null.
    expect(src).toMatch(/pull !== undefined && pull\.heldFiles == null \? await readLegacyStoredKbSyncHeld\(userId, activeWorkspaceId\)/);
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

  it("the DB-side writer set_repo_status stamps it only on ready (migration 113)", () => {
    const m113 = readFileSync(path.join(APP, "supabase/migrations/113_set_repo_status_writes_workspace_repo_error.sql"), "utf8");
    expect(m113).toMatch(/repo_last_synced_at\s*=\s*CASE WHEN p_status = 'ready' THEN now\(\)/);
  });

  it("the DB-side reader is the clone lock (migration 108)", () => {
    const m108 = readFileSync(path.join(APP, "supabase/migrations/108_repo_clone_self_heal_rpc.sql"), "utf8");
    expect(m108).toMatch(/claim_repo_clone_lock/);
    expect(m108).toMatch(/repo_last_synced_at/);
  });
});
