#!/usr/bin/env node
// Dormant metadata-only collector. Preview is the default; --execute requires
// separate approval of its exact source/CA/output-bound command. No write SQL.
import { execFile } from "node:child_process";
import { createHash, X509Certificate } from "node:crypto";
import { constants, promises as fs } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const executeFile = promisify(execFile);
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const SOURCE_FILES = [
  "apps/web-platform/scripts/capture-codex-dev-catalog.mjs",
  "apps/web-platform/lib/supabase/resolve-ref.ts",
  "apps/web-platform/package-lock.json",
];
const BYTE_LIMIT = 4 * 1024 * 1024;
const SHA = /^[a-f0-9]{40}$/;
const DIGEST = /^[a-f0-9]{64}$/;
const UID = process.getuid?.();
const hash = (value) => createHash("sha256").update(value).digest("hex");
class Refusal extends Error { constructor(code) { super(`catalog_capture:${code}`); this.code = code; } }
function requireValue(condition, code) { if (!condition) throw new Refusal(code); }

// The SQL is fixed source, never accepted from arguments or a ledger field.
// Each cap requests one additional row so overflows refuse rather than truncate.
export const SECTIONS = Object.freeze([
  { name: "identity", maximum: 1, sql: "SELECT clock_timestamp()::text AS observed_at, current_database() AS database, current_user AS role, version() AS version, pg_backend_pid() AS backend_pid LIMIT 2" },
  { name: "ledger", maximum: 1024, sql: "SELECT filename, content_sha, to_char(applied_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') AS applied_at FROM public._schema_migrations ORDER BY filename LIMIT 1025" },
  { name: "relations", maximum: 1024, sql: "SELECT c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, c.relacl::text AS acl FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m') ORDER BY c.relname LIMIT 1025" },
  { name: "columns", maximum: 4096, sql: "SELECT c.relname, a.attname, a.attnum, format_type(a.atttypid,a.atttypmod) AS type, a.attnotnull, a.attidentity, a.attgenerated, pg_get_expr(d.adbin,d.adrelid) AS default_expression FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE n.nspname='public' AND c.relkind IN ('r','p') AND a.attnum>0 AND NOT a.attisdropped ORDER BY c.relname,a.attnum LIMIT 4097" },
  { name: "constraints", maximum: 4096, sql: "SELECT c.relname, k.conname, k.contype, k.convalidated, pg_get_constraintdef(k.oid,true) AS definition FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY c.relname,k.conname LIMIT 4097" },
  { name: "indexes", maximum: 4096, sql: "SELECT c.relname, i.indexrelid::regclass::text AS index_name, i.indisvalid, i.indisready, pg_get_indexdef(i.indexrelid) AS definition FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY c.relname,index_name LIMIT 4097" },
  { name: "triggers", maximum: 4096, sql: "SELECT c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid,true) AS definition FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY c.relname,t.tgname LIMIT 4097" },
  { name: "policies", maximum: 4096, sql: "SELECT tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname='public' ORDER BY tablename,policyname LIMIT 4097" },
  { name: "functions", maximum: 128, sql: "SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,p.prosecdef,p.proconfig,p.proacl::text AS acl,pg_get_functiondef(p.oid) AS definition,has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND p.proname IN ('bind_agent_engine_run','start_agent_engine_attempt','transition_agent_engine_attempt','assert_agent_engine_attempt_generation','append_agent_engine_lifecycle_event','save_agent_engine_recovery_checkpoint','get_agent_engine_recovery_checkpoint','anonymise_agent_engine_data','set_workspace_default_engine','count_codex_conversation_rebinds','record_codex_history_transfer_acknowledgment','codex_history_transfer_acknowledged','purge_stale_codex_history_transfer_acknowledgments','purge_codex_history_transfer_acknowledgments_on_member_change','issue_codex_history_transfer_notice','mark_codex_history_transfer_notice_delivered','delete_codex_history_transfer_notice_issuance','purge_stale_codex_history_transfer_notice_issuances','purge_replaced_codex_history_notice_membership') ORDER BY p.proname,arguments LIMIT 129" },
  { name: "sessions", maximum: 256, sql: "SELECT clock_timestamp()::text AS observed_at,pid,backend_start::text,application_name,state,xact_start::text,wait_event_type,wait_event FROM pg_stat_activity WHERE datname=current_database() ORDER BY pid LIMIT 257" },
  { name: "locks", maximum: 256, sql: "SELECT clock_timestamp()::text AS observed_at,l.pid,l.locktype,l.mode,l.granted,l.relation::regclass::text AS relation,l.classid,l.objid,l.objsubid,(l.locktype='advisory' AND l.objsubid=1 AND l.classid=((hashtextextended('tenant_integration_dev_suite',0)>>32)&4294967295) AND l.objid=(hashtextextended('tenant_integration_dev_suite',0)&4294967295)) AS dev_suite_mutex FROM pg_locks l WHERE l.database=(SELECT oid FROM pg_database WHERE datname=current_database()) AND l.locktype IN ('advisory','relation') ORDER BY l.pid,l.locktype,l.mode LIMIT 257" },
].map((section) => Object.freeze(section)));

export function parseArguments(argv) {
  const options = { execute: false };
  const keys = { "--source-sha": "sourceSha", "--ca-file": "caFile", "--ca-sha256": "caSha256", "--output-directory": "outputDirectory" };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    requireValue(!seen.has(argument), "arguments");
    seen.add(argument);
    if (argument === "--execute") { options.execute = true; continue; }
    requireValue(Object.hasOwn(keys, argument) && typeof argv[index + 1] === "string" && !argv[index + 1].startsWith("--"), "arguments");
    options[keys[argument]] = argv[++index];
  }
  requireValue(SHA.test(options.sourceSha ?? "") && DIGEST.test(options.caSha256 ?? "") && options.caFile && options.outputDirectory, "arguments");
  return options;
}

async function fixedCommand(binary, args, code, env = process.env) {
  try { return (await executeFile(binary, args, { env, timeout: 15_000, maxBuffer: 256 * 1024, encoding: "utf8" })).stdout; }
  catch { throw new Refusal(code); }
}

async function bounded(promise, milliseconds, code) {
  let timer;
  try {
    requireValue(milliseconds > 0, "deadline");
    return await Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Refusal(code)), milliseconds); })]);
  } finally { clearTimeout(timer); }
}

async function verifySource(sourceSha, repoRoot = REPO_ROOT) {
  const env = { PATH: "/usr/bin:/bin", HOME: "/nonexistent", GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0" };
  const git = (args) => fixedCommand("git", ["-C", repoRoot, ...args], "source_binding", env);
  requireValue((await git(["rev-parse", "HEAD"])).trim() === sourceSha, "source_binding");
  requireValue(!(await git(["status", "--porcelain=v1", "--untracked-files=all", "--", "apps/web-platform", "scripts/codex-qualification"])).trim(), "source_binding");
  const files = {};
  for (const path of SOURCE_FILES) {
    const bytes = await fs.readFile(join(repoRoot, path));
    const committedBlob = (await git(["rev-parse", `${sourceSha}:${path}`])).trim();
    const currentBlob = (await git(["hash-object", "--no-filters", "--", path])).trim();
    requireValue(SHA.test(committedBlob) && committedBlob === currentBlob, "source_binding");
    files[path] = hash(bytes);
  }
  for (const path of ["apps/web-platform/node_modules/postgres/src/index.js", "apps/web-platform/node_modules/postgres/src/connection.js"]) files[path] = hash(await fs.readFile(join(repoRoot, path)));
  return { source_sha: sourceSha, files };
}

async function localBindings(options, repoRoot) {
  requireValue(SHA.test(options.sourceSha ?? "") && DIGEST.test(options.caSha256 ?? ""), "arguments");
  const output = resolve(options.outputDirectory);
  requireValue(isAbsolute(options.outputDirectory) && relative(join(repoRoot, ".soleur"), output) !== "" && !relative(join(repoRoot, ".soleur"), output).startsWith(".."), "output_path");
  const parent = dirname(output);
  requireValue(await fs.realpath(parent) === parent, "output_path");
  const parentStat = await fs.stat(parent);
  requireValue(parentStat.isDirectory() && parentStat.uid === UID && !(parentStat.mode & 0o022), "output_path");
  try { await fs.lstat(output); throw new Refusal("output_exists"); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const handle = await fs.open(options.caFile, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    requireValue(stat.isFile() && stat.nlink === 1 && stat.uid === UID && !(stat.mode & 0o077) && stat.size <= 64 * 1024, "ca_binding");
    const ca = await handle.readFile();
    requireValue(hash(ca) === options.caSha256, "ca_binding");
    const certificate = new X509Certificate(ca);
    requireValue(certificate.ca && Date.now() >= Date.parse(certificate.validFrom) && Date.now() < Date.parse(certificate.validTo), "ca_binding");
    return { ca, output };
  } finally { await handle.close(); }
}

function connectionOptions(dsn, ca, expectedRef) {
  const url = new URL(dsn);
  requireValue(["postgres:", "postgresql:"].includes(url.protocol) && !url.search && !url.hash && /^aws-[a-z0-9-]+\.pooler\.supabase\.com$/.test(url.hostname) && ["5432", "6543"].includes(url.port) && url.pathname === "/postgres" && decodeURIComponent(url.username) === `postgres.${expectedRef}` && url.password.length > 0, "identity");
  return {
    host: url.hostname, port: Number(url.port), database: "postgres", username: decodeURIComponent(url.username), password: decodeURIComponent(url.password),
    ssl: { ca, rejectUnauthorized: true, servername: url.hostname }, max: 1, prepare: false, fetch_types: false, connect_timeout: 10, idle_timeout: 5,
    onnotice: () => {},
    connection: { application_name: "pr9051-catalog-readonly", default_transaction_read_only: "on", statement_timeout: "10000", lock_timeout: "1000", idle_in_transaction_session_timeout: "15000" },
  };
}

async function dependencies() {
  // Lazy imports: importing this module or previewing never resolves DNS,
  // invokes Doppler, constructs a database connection or imports application code.
  const [{ default: postgres }, { resolveSupabaseRef }] = await Promise.all([import("postgres"), import("../lib/supabase/resolve-ref.ts")]);
  return { resolveRef: resolveSupabaseRef, connect: async (options) => postgres(options), doppler: (args) => fixedCommand("doppler", args, "credential_read") };
}

async function publish(output, data, receipt) {
  // Linux descriptor-relative publication prevents a replaced parent pathname
  // redirecting writes. Unknown/existing leaves are preserved, never removed.
  const parent = await fs.open(dirname(output), constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  let directory;
  try {
    const stat = await parent.stat();
    requireValue(stat.uid === UID && !(stat.mode & 0o022), "output_path");
    const leaf = join(`/proc/self/fd/${parent.fd}`, basename(output));
    await fs.mkdir(leaf, { mode: 0o700 });
    directory = await fs.open(leaf, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    const created = await directory.stat();
    requireValue(created.uid === UID && !(created.mode & 0o077), "output_path");
    for (const [name, value] of [["catalog.json", data], ["receipt.json", JSON.stringify(receipt) + "\n"]]) {
      const handle = await fs.open(join(`/proc/self/fd/${directory.fd}`, name), constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      try { await handle.chmod(0o600); await handle.writeFile(value); await handle.sync(); }
      finally { await handle.close(); }
    }
    await directory.sync();
    await parent.sync();
  } finally { if (directory) await directory.close(); await parent.close(); }
}

export async function runCapture(options, injected = {}) {
  let database;
  try {
    const verify = injected.verifySource ?? ((sha) => verifySource(sha, injected.repoRoot ?? REPO_ROOT));
    let source;
    try { source = await verify(options.sourceSha); } catch { throw new Refusal("source_binding"); }
    const local = await localBindings(options, injected.repoRoot ?? REPO_ROOT);
    const preview = { status: "preview-no-external-actions", source, ca_sha256: options.caSha256, output_directory: local.output, sections: SECTIONS.map(({ name, maximum }) => ({ name, maximum })), work_seconds: 60, byte_limit: BYTE_LIMIT, application_rows: 0, mutations: 0, writer_clearance: false };
    if (options.execute !== true) return preview;
    const deadline = Date.now() + 60_000;
    const step = (operation, code) => {
      const remaining = deadline - Date.now();
      requireValue(remaining > 0, "deadline");
      return bounded(operation(), Math.min(15_000, remaining), code);
    };
    const adapters = { ...(await (injected.doppler && injected.connect && injected.resolveRef ? Promise.resolve({}) : dependencies())), ...injected };
    const read = async (args) => {
      try { return (await step(() => adapters.doppler(args), "credential_read")).trim(); } catch { throw new Refusal("credential_read"); }
    };
    const config = JSON.parse(await read(["configs", "get", "dev_scheduled", "-p", "soleur", "--json"]));
    requireValue(config.environment === "dev", "identity");
    const get = (key, configName) => read(["secrets", "get", key, "--plain", "-p", "soleur", "-c", configName]);
    const devUrl = await get("NEXT_PUBLIC_SUPABASE_URL", "dev_scheduled");
    const prodUrl = await get("NEXT_PUBLIC_SUPABASE_URL", "prd");
    const devRef = await step(() => adapters.resolveRef(devUrl), "identity");
    const prodRef = await step(() => adapters.resolveRef(prodUrl), "identity");
    requireValue(/^[a-z0-9]{20}$/.test(devRef ?? "") && /^[a-z0-9]{20}$/.test(prodRef ?? "") && devRef !== prodRef, "identity");
    const dsn = await get("DATABASE_URL_POOLER", "dev_scheduled");
    const connection = connectionOptions(dsn, local.ca, devRef);
    try { database = await step(() => adapters.connect(connection), "database"); } catch { throw new Refusal("database"); }
    const sections = {};
    requireValue(Date.now() < deadline, "deadline");
    await bounded(database.begin("isolation level repeatable read read only", async (tx) => {
      const query = (sql) => step(() => tx.unsafe(sql), "database");
      await query("SET LOCAL statement_timeout = '10s'; SET LOCAL lock_timeout = '1s'; SET LOCAL idle_in_transaction_session_timeout = '15s'; SET LOCAL application_name = 'pr9051-catalog-readonly'");
      const state = await query("SELECT current_setting('transaction_read_only') AS read_only,current_setting('transaction_isolation') AS isolation");
      requireValue(state.length === 1 && state[0].read_only === "on" && state[0].isolation === "repeatable read", "transaction_read_only");
      for (const section of SECTIONS) {
        const rows = await query(section.sql);
        requireValue(Array.isArray(rows) && rows.length <= section.maximum, "row_limit");
        sections[section.name] = rows;
        requireValue(Buffer.byteLength(JSON.stringify(sections)) <= BYTE_LIMIT, "byte_limit");
      }
    }), deadline - Date.now(), "deadline");
    await database.end({ timeout: 5 });
    database = undefined;
    try { requireValue(JSON.stringify(await verify(options.sourceSha)) === JSON.stringify(source), "source_binding"); } catch { throw new Refusal("source_binding"); }
    requireValue(Date.now() < deadline, "deadline");
    const data = JSON.stringify({ source, captured_at: new Date().toISOString(), sections, application_rows: 0, mutations: 0, writer_clearance: false, session_observations_are_not_exclusion: true }) + "\n";
    requireValue(Buffer.byteLength(data) <= BYTE_LIMIT, "byte_limit");
    const result = { status: "captured-read-only-metadata", source_sha: options.sourceSha, ca_sha256: options.caSha256, catalog_sha256: hash(data), counts: Object.fromEntries(Object.entries(sections).map(([name, rows]) => [name, rows.length])), application_rows: 0, mutations: 0, writer_clearance: false };
    await publish(local.output, data, result);
    return result;
  } catch (error) {
    throw new Refusal(error instanceof Refusal ? error.code : "refused");
  } finally {
    if (database) { try { await database.end({ timeout: 5 }); } catch { /* No success receipt exists on a collection failure. */ } }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { console.log(JSON.stringify(await runCapture(parseArguments(process.argv.slice(2))))); }
  catch (error) { console.error(error instanceof Refusal ? error.message : "catalog_capture:refused"); process.exitCode = 1; }
}
