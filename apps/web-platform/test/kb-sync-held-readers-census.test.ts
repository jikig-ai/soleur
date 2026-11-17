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
//   - `server/agent-runner.ts` names no held column (it uses `syncPull`'s fresh `{ heldFiles }` return);
//   - `server/current-repo-url.ts` names no held column;
//   - every app reader and writer of `repo_last_synced_at` (W5: only `syncPull` stamps it on the sync path).
//
// Multi-line aware: the scan reads whole files, and `.select(` arguments are matched across line breaks.

const APP = path.join(__dirname, "..");
const ROOTS = ["app", "server", "lib", "components", "hooks"];
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
const sources = new Map(files.map((f) => [path.relative(APP, f).split(path.sep).join("/"), code(readFileSync(f, "utf8"))]));

type Role = { role: string; required: boolean };

// Every app file whose code names a held column or the RPC. `required: false` rows are owned by sibling Phase 11
// tasks (the writer in session-sync and the cc agent line); they are allowed now and must flip to `true` when they land.
const HELD_MENTIONS: Record<string, Role> = {
  "app/(dashboard)/dashboard/settings/page.tsx": { role: "reader: Settings, service client, active workspace id", required: true },
  "server/workspace-repo-mirror.ts": { role: "type: WorkspaceRepoCols", required: true },
  "app/api/repo/disconnect/route.ts": { role: "writer: nulls both columns on disconnect", required: true },
  "app/api/repo/setup/route.ts": { role: "writer: nulls both columns on (re)connect", required: true },
  "server/session-sync.ts": { role: "writer: separate service-client UPDATE after each sync", required: false },
  "server/cc-dispatcher.ts": { role: "reader: get_workspace_kb_sync_held RPC (cc agent line)", required: false },
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

  it("server/agent-runner.ts and server/current-repo-url.ts name no held column", () => {
    for (const f of ["server/agent-runner.ts", "server/current-repo-url.ts"]) {
      expect(sources.has(f), f).toBe(true);
      expect(HELD_TOKEN.test(sources.get(f)!), f).toBe(false);
    }
  });
});

// Every app file whose code names `repo_last_synced_at`, with its role. W5: on the sync path only `syncPull` stamps
// it, so "Updated from GitHub" stays true. DB-side reader (not app code): claim_repo_clone_lock (migration 108) uses it
// as the clone lock's staleness clock, which is why setup stamps it on the cloning flip.
const LAST_SYNCED_MENTIONS: Record<string, string> = {
  "app/(dashboard)/dashboard/settings/page.tsx": "reader: Owner 'Updated from GitHub' date line",
  "app/api/repo/status/route.ts": "reader: lastSyncedAt in the repo status payload",
  "app/api/repo/setup/route.ts": "writer: cloning flip (clone-lock clock), ready stamp, cleared on a reaped clone",
  "app/api/repo/disconnect/route.ts": "writer: cleared on disconnect",
  "server/session-sync.ts": "writer: updateLastSynced, syncPull only (W5)",
  "server/workspace-repo-mirror.ts": "type: WorkspaceRepoCols",
};

describe("repo_last_synced_at: readers census (#12714, D29(9))", () => {
  it("every file whose code names repo_last_synced_at is listed", () => {
    const mentioning = [...sources].filter(([, src]) => /\brepo_last_synced_at\b/.test(src)).map(([f]) => f).sort();
    expect(mentioning).toEqual(Object.keys(LAST_SYNCED_MENTIONS).sort());
  });

  it("the DB-side reader is the clone lock (migration 108)", () => {
    const m108 = readFileSync(path.join(APP, "supabase/migrations/108_repo_clone_self_heal_rpc.sql"), "utf8");
    expect(m108).toMatch(/claim_repo_clone_lock/);
    expect(m108).toMatch(/repo_last_synced_at/);
  });
});
