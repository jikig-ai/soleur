import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { rootCertificates } from "node:tls";
import { afterEach, describe, expect, it, vi } from "vitest";
import { dopplerEnvironment, parseArguments, preparePinnedDriver, runCapture, SECTIONS } from "../../scripts/capture-codex-dev-catalog.mjs";

const SHA = "a".repeat(40);
const DEV = "a".repeat(20);
const PRD = "b".repeat(20);
const CANARY = "SYNTHETIC_PRIVATE_VALUE_DO_NOT_LOG";
const roots: string[] = [];
afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "codex-catalog-"));
  roots.push(root);
  mkdirSync(join(root, ".soleur"), { mode: 0o700 });
  const caFile = join(root, "root.pem");
  writeFileSync(caFile, rootCertificates[0], { mode: 0o600 });
  const packageRoot = join(root, "package");
  mkdirSync(join(packageRoot, "src"), { recursive: true, mode: 0o700 });
  writeFileSync(join(packageRoot, "package.json"), JSON.stringify({ name: "postgres", version: "3.4.9", type: "module", exports: { import: "./src/index.js" } }));
  writeFileSync(join(packageRoot, "src", "index.js"), "export default function postgres() {}\n");
  const driverArchive = join(root, "postgres-3.4.9.tgz");
  execFileSync("tar", ["-czf", driverArchive, "-C", root, "package"]);
  chmodSync(driverArchive, 0o600);
  const driverIntegrity = `sha512-${createHash("sha512").update(readFileSync(driverArchive)).digest("base64")}`;
  mkdirSync(join(root, "apps", "web-platform"), { recursive: true });
  writeFileSync(join(root, "apps", "web-platform", "package-lock.json"), JSON.stringify({ packages: { "node_modules/postgres": { version: "3.4.9", resolved: "https://registry.npmjs.org/postgres/-/postgres-3.4.9.tgz", integrity: driverIntegrity } } }));
  const options = { sourceSha: SHA, caFile, caSha256: createHash("sha256").update(rootCertificates[0]).digest("hex"), driverArchive, driverIntegrity, outputDirectory: join(root, ".soleur", "capture"), execute: true };
  const query = vi.fn(async (sql: string): Promise<Record<string, unknown>[]> => sql.startsWith("SELECT current_setting")
    ? [{ read_only: "on", isolation: "repeatable read" }]
    : sql.includes("FROM public._schema_migrations")
      ? [{ filename: "001_synthetic.sql", content_sha: null, applied_at: "2026-10-26T12:00:00.123456Z" }]
      : []);
  const transaction = vi.fn(async (mode: string, callback: (tx: { unsafe: typeof query }) => Promise<unknown>) => callback({ unsafe: query }));
  const end = vi.fn(async () => {});
  const connect = vi.fn(async (_options: Record<string, unknown>) => ({ begin: transaction, end }));
  const doppler = vi.fn(async (args: string[]) => {
    if (args[0] === "configs") return JSON.stringify({ environment: "dev" });
    if (args[2] === "DATABASE_URL_POOLER") return `postgres://postgres.${DEV}:${CANARY}@aws-0-eu-central-1.pooler.supabase.com:6543/postgres`;
    return `https://${args.includes("prd") ? PRD : DEV}.supabase.co`;
  });
  const verifySource = vi.fn(async () => ({ source_sha: SHA, files: {} }));
  const resolveRef = vi.fn(async (url: string) => new URL(url).hostname.split(".")[0]);
  const preparePinnedDriver = vi.fn(async () => ({ entry: join(packageRoot, "src", "index.js"), version: "3.4.9", cleanup: vi.fn(async () => {}) }));
  const dependencies = { repoRoot: root, verifySource, preparePinnedDriver, doppler, resolveRef, connect };
  return { root, options, dependencies, query, transaction, connect, end, doppler, verifySource };
}

describe("dormant shared-dev catalog capture", () => {
  it("defaults to preview and refuses unknown, duplicate or incomplete arguments", () => {
    const f = fixture();
    const args = ["--source-sha", SHA, "--ca-file", f.options.caFile, "--ca-sha256", f.options.caSha256, "--driver-archive", f.options.driverArchive, "--output-directory", f.options.outputDirectory];
    expect(parseArguments(args).execute).toBe(false);
    expect(parseArguments([...args, "--execute"]).execute).toBe(true);
    expect(() => parseArguments([...args, "--execute", "--execute"])).toThrow();
    expect(() => parseArguments([...args, "--database-url", CANARY])).toThrow();
    const archiveIndex = args.indexOf("--driver-archive");
    const withoutArchive = args.filter((_, index) => index !== archiveIndex && index !== archiveIndex + 1);
    expect(() => parseArguments(withoutArchive)).toThrow();
  });

  it("captures relation and function owners needed to compare effective privilege boundaries", () => {
    expect(SECTIONS.find((section: { name: string }) => section.name === "relations")?.sql).toContain("pg_get_userbyid(c.relowner)");
    expect(SECTIONS.find((section: { name: string }) => section.name === "functions")?.sql).toContain("pg_get_userbyid(p.proowner)");
  });

  it("passes only approved Doppler auth context and drops executable/host overrides", () => {
    expect(dopplerEnvironment({
      NODE_ENV: "test",
      HOME: "/home/synthetic",
      PATH: "/tmp/attacker:/usr/bin",
      DOPPLER_TOKEN: "SYNTHETIC_DOPPLER_TOKEN",
      DOPPLER_API_HOST: "https://attacker.invalid",
      NODE_OPTIONS: "--require /tmp/attacker.js",
      LD_PRELOAD: "/tmp/attacker.so",
    })).toEqual({
      PATH: "/usr/bin:/bin",
      HOME: "/home/synthetic",
      DOPPLER_TOKEN: "SYNTHETIC_DOPPLER_TOKEN",
    });
  });

  it("loads only a tarball whose bytes match the lockfile integrity and exact postgres version", async () => {
    const f = fixture();
    const prepared = await preparePinnedDriver(f.options.driverArchive, f.options.driverIntegrity);
    try {
      expect(prepared.version).toBe("3.4.9");
      expect(prepared.entry).toContain("/src/index.js");
      const loaded = await import(pathToFileURL(prepared.entry).href);
      expect(typeof loaded.default).toBe("function");
    } finally {
      await prepared.cleanup();
    }

    const altered = join(f.root, "altered.tgz");
    writeFileSync(altered, readFileSync(f.options.driverArchive));
    writeFileSync(altered, Buffer.concat([readFileSync(altered), Buffer.from("changed")]));
    chmodSync(altered, 0o600);
    await expect(preparePinnedDriver(altered, f.options.driverIntegrity)).rejects.toThrow("driver_integrity");
    await expect(preparePinnedDriver(f.options.driverArchive, "sha512-AAAA")).rejects.toThrow("driver_integrity");
  });

  it("preview verifies local bindings but makes zero external calls and writes nothing", async () => {
    const f = fixture();
    const result = await runCapture({ ...f.options, execute: false }, f.dependencies);
    expect(result.status).toBe("preview-no-external-actions");
    expect(result).toMatchObject({ source: { runtime_dependencies: { postgres: { version: "3.4.9", integrity: f.options.driverIntegrity } } } });
    expect(f.verifySource).toHaveBeenCalledWith(SHA);
    expect(f.doppler).not.toHaveBeenCalled();
    expect(f.dependencies.resolveRef).not.toHaveBeenCalled();
    expect(f.connect).not.toHaveBeenCalled();
    expect(existsSync(f.options.outputDirectory)).toBe(false);
  });

  it("real source binding accepts committed bytes and rejects another SHA or dirty source before external calls", async () => {
    const f = fixture();
    const paths = ["apps/web-platform/scripts/capture-codex-dev-catalog.mjs", "apps/web-platform/lib/supabase/resolve-ref.ts", "apps/web-platform/package-lock.json"];
    for (const file of paths) {
      mkdirSync(join(f.root, file, ".."), { recursive: true });
      writeFileSync(join(f.root, file), file.endsWith(".json") ? JSON.stringify({ packages: { "node_modules/postgres": { version: "3.4.9", resolved: "https://registry.npmjs.org/postgres/-/postgres-3.4.9.tgz", integrity: f.options.driverIntegrity } } }) : "// synthesized source\n");
    }
    const git = (args: string[]) => execFileSync("git", ["-C", f.root, "-c", "core.hooksPath=/dev/null", ...args], { env: { NODE_ENV: "test", PATH: "/usr/bin:/bin", HOME: "/nonexistent", GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" }, encoding: "utf8" }).trim();
    git(["init", "-q"]);
    git(["add", "--", ...paths]);
    git(["-c", "user.name=Synthetic", "-c", "user.email=fixture@example.com", "commit", "-qm", "synthetic source"]);
    const sourceSha = git(["rev-parse", "HEAD"]);
    const { verifySource: _unused, ...adapters } = f.dependencies;
    expect((await runCapture({ ...f.options, sourceSha, execute: false }, adapters)).status).toBe("preview-no-external-actions");
    await expect(runCapture({ ...f.options, sourceSha: SHA }, adapters)).rejects.toThrow("source_binding");
    for (const file of paths.slice(0, 3)) {
      const original = readFileSync(join(f.root, file));
      writeFileSync(join(f.root, file), "changed source\n");
      await expect(runCapture({ ...f.options, sourceSha }, adapters)).rejects.toThrow("source_binding");
      writeFileSync(join(f.root, file), original);
    }
    expect(f.doppler).not.toHaveBeenCalled();
    expect(f.connect).not.toHaveBeenCalled();
  });

  it.each(["wrong-environment", "same-project", "wrong-database-ref"])("rejects %s before database contact", async (mutation) => {
    const f = fixture();
    const original = f.doppler.getMockImplementation()!;
    f.doppler.mockImplementation(async (args) => mutation === "wrong-environment" && args[0] === "configs"
      ? JSON.stringify({ environment: "prd" })
      : mutation === "same-project" && args.includes("prd") ? `https://${DEV}.supabase.co`
        : mutation === "wrong-database-ref" && args[2] === "DATABASE_URL_POOLER"
          ? `postgres://postgres.${PRD}:${CANARY}@aws-0-eu-central-1.pooler.supabase.com:6543/postgres` : original(args));
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow("identity");
    expect(f.connect).not.toHaveBeenCalled();
    expect(existsSync(f.options.outputDirectory)).toBe(false);
  });

  it.each(["?sslmode=disable", "?sslmode=require", "?host=synthetic.invalid", "?options=-c%20default_transaction_read_only=off", "?application_name=override"])("rejects DSN option injection %s", async (suffix) => {
    const f = fixture();
    const original = f.doppler.getMockImplementation()!;
    f.doppler.mockImplementation(async (args) => (await original(args)) + (args[2] === "DATABASE_URL_POOLER" ? suffix : ""));
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow("identity");
    expect(f.connect).not.toHaveBeenCalled();
  });

  it("collects fixed metadata under verified TLS and explicit read-only repeatable-read; preserves microseconds privately", async () => {
    const f = fixture();
    const result = await runCapture(f.options, f.dependencies);
    expect(result.status).toBe("captured-read-only-metadata");
    const connection = f.connect.mock.calls[0][0] as Record<string, unknown>;
    expect(connection.ssl).toMatchObject({ rejectUnauthorized: true, servername: "aws-0-eu-central-1.pooler.supabase.com" });
    expect(connection).toMatchObject({ max: 1, prepare: false, fetch_types: false, connect_timeout: 10, connection: { default_transaction_read_only: "on" } });
    expect(f.transaction).toHaveBeenCalledWith("isolation level repeatable read read only", expect.any(Function));
    expect(f.query.mock.calls[0][0]).toMatch(/^SET LOCAL statement_timeout/);
    expect(f.end).toHaveBeenCalledOnce();
    expect(statSync(f.options.outputDirectory).mode & 0o777).toBe(0o700);
    const captureFile = join(f.options.outputDirectory, "catalog.json");
    const receiptFile = join(f.options.outputDirectory, "receipt.json");
    expect(statSync(captureFile).mode & 0o777).toBe(0o600);
    expect(statSync(receiptFile).mode & 0o777).toBe(0o600);
    const bytes = readFileSync(captureFile, "utf8");
    expect(bytes).toContain("2026-10-26T12:00:00.123456Z");
    expect(bytes + JSON.stringify(result)).not.toContain(CANARY);
    expect(f.doppler.mock.calls.filter(([a]) => a.includes("prd"))).toEqual([[["secrets", "get", "NEXT_PUBLIC_SUPABASE_URL", "--plain", "-p", "soleur", "-c", "prd"]]]);
  });

  it("a failed read-only precondition prevents every metadata query and publication", async () => {
    const f = fixture();
    f.query.mockImplementation(async (sql) => sql.startsWith("SELECT current_setting") ? [{ read_only: "off", isolation: "repeatable read" }] : []);
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow("transaction_read_only");
    expect(f.query.mock.calls.some(([sql]) => sql.includes("FROM public._schema_migrations"))).toBe(false);
    expect(f.end).toHaveBeenCalledOnce();
    expect(existsSync(join(f.options.outputDirectory, "receipt.json"))).toBe(false);
  });

  it("row overflow refuses without truncation or a success receipt", async () => {
    const f = fixture();
    const original = f.query.getMockImplementation()!;
    const ledger = SECTIONS.find((s: { name: string }) => s.name === "ledger")!;
    f.query.mockImplementation(async (sql) => sql.includes("FROM public._schema_migrations") ? Array.from({ length: ledger.maximum + 1 }, () => ({ filename: "001_synthetic.sql" })) : original(sql));
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow("row_limit");
    expect(existsSync(join(f.options.outputDirectory, "receipt.json"))).toBe(false);
  });

  it("oversized catalog bytes refuse without publication", async () => {
    const f = fixture();
    const original = f.query.getMockImplementation()!;
    f.query.mockImplementation(async (sql) => sql.includes("FROM public._schema_migrations") ? [{ filename: "x".repeat(4 * 1024 * 1024 + 1) }] : original(sql));
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow("byte_limit");
    expect(existsSync(join(f.options.outputDirectory, "receipt.json"))).toBe(false);
  });

  it("the work deadline refuses further queries and publication while still closing the connection", async () => {
    const f = fixture();
    let now = Date.now();
    vi.spyOn(Date, "now").mockImplementation(() => now);
    const original = f.query.getMockImplementation()!;
    f.query.mockImplementation(async (sql) => { if (sql.includes("FROM public._schema_migrations")) now += 61_000; return original(sql); });
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow("deadline");
    expect(f.end).toHaveBeenCalledOnce();
    expect(existsSync(join(f.options.outputDirectory, "receipt.json"))).toBe(false);
  });

  it("an output created during collection is preserved and never overwritten", async () => {
    const f = fixture();
    const original = f.query.getMockImplementation()!;
    f.query.mockImplementation(async (sql) => {
      if (sql.includes("FROM public._schema_migrations")) {
        mkdirSync(f.options.outputDirectory, { mode: 0o700 });
        writeFileSync(join(f.options.outputDirectory, "catalog.json"), "synthetic foreign artifact");
      }
      return original(sql);
    });
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow();
    expect(readFileSync(join(f.options.outputDirectory, "catalog.json"), "utf8")).toBe("synthetic foreign artifact");
    expect(existsSync(join(f.options.outputDirectory, "receipt.json"))).toBe(false);
  });

  it.each(["credential", "database"])("%s failures never expose underlying secret-bearing errors", async (where) => {
    const f = fixture();
    if (where === "credential") f.doppler.mockRejectedValueOnce(new Error(CANARY));
    else f.connect.mockRejectedValueOnce(new Error(CANARY));
    let error: unknown;
    try { await runCapture(f.options, f.dependencies); } catch (caught) { error = caught; }
    expect(error).toBeInstanceOf(Error);
    expect(String(error)).not.toContain(CANARY);
    expect((error as Error & { cause?: unknown }).cause).toBeUndefined();
    expect(existsSync(join(f.options.outputDirectory, "receipt.json"))).toBe(false);
  });

  it.each(["existing-output", "symlink-output", "public-ca", "ca-digest"])("%s refuses before external calls", async (mutation) => {
    const f = fixture();
    if (mutation === "existing-output") mkdirSync(f.options.outputDirectory);
    if (mutation === "symlink-output") symlinkSync(f.root, f.options.outputDirectory);
    if (mutation === "public-ca") chmodSync(f.options.caFile, 0o644);
    if (mutation === "ca-digest") f.options.caSha256 = "0".repeat(64);
    await expect(runCapture(f.options, f.dependencies)).rejects.toThrow();
    expect(f.doppler).not.toHaveBeenCalled();
  });
});
