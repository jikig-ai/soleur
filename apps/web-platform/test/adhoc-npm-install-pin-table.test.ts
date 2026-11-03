import { describe, it, expect } from "vitest";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Pin-table guard (#11855): every npm tree resolved OUTSIDE a lockfile —
// `npm install -g`, `npm i -g`, `npm install --no-save`, and `npx pkg@ver`
// invocations — must carry an exact version declared here, reconciled BOTH
// ways: every scanned site needs a row, and every row needs a live site.
// Extends the single-site parity pattern (dockerfile-vitest-version-pin) into
// a table so an added or unpinned site reddens instead of floating silently.
//
// SITE SHAPES, three kinds:
//   literal  — `npm install -g vitest@4.1.12`, `npx playwright@1.61.0-alpha-…`
//   env      — `npm i -g "@openai/codex@${CODEX_PIN}"`; the same file must bind
//              the variable to an exact semver literal (`CODEX_PIN: "0.156.1"`,
//              `VAR="x.y.z"`), or to a version PIN FILE (`< .bun-version`,
//              `.nvmrc`, `.tool-versions`) whose content is exact semver.
//   bare-npx — `npx playwright test`: resolves LOCAL node_modules only when the
//              package is bound by a tracked lockfile or a declared install row
//              in the same file; on a miss npx fetches `latest` — the float this
//              guard exists to kill. `npx --no-install` is never a site (it
//              cannot fetch).
//
// MANIFEST COVERAGE: a tracked `package.json` whose declared deps bind no
// lockfile (not a workspace member, no same-dir package-lock.json) must sit in
// MANIFEST_CARVEOUTS with its dep specs recorded — the row reddens on drift so
// a dep added to an unbound manifest is a deliberate edit, not a silent float.
//
// EXTRACTION is command-position, not raw-string: `npm install`/`npx` counts as
// an invocation only when it is the command word of a segment — leading
// `RUN`/`run:`/YAML-bullet/`env`/`sudo`/`exec`-class prefixes are consumed,
// segments split on `&&`/`;`/`|`/`&` and on a standalone `--` (proxy-wrapper
// inner command, e.g. `proxy.py -- npx pkg@ver`). What this skips, by design:
//   * `npx` inside a `for`-list word, inside `die "…"`/`echo "…"` arguments,
//     inside `::error::` help text — none sits at command position;
//   * `npm ci` (subcommand isn't install|i) — lockfile-bound, drain guard owns;
//   * `apt-get install`, `pip install`, `bun install`, `bunx` — other package
//     managers; lint-workflow-install-sites.sh owns the bun side.
// BOUNDARY — surfaces enumerated and NOT scanned here:
//   * `*.test.{sh,ts,tsx}` and `**/test/**` — mutation fixtures necessarily
//     carry violating text (same exclusion as lint-workflow-install-sites.sh);
//   * `*.md`/SKILL.md prose — scaffolded examples; kept honest by review;
//   * nested-shell strings (`bash -c "…"`, `$(…)`) inside .sh/.yml — no such
//     invocation exists today; .mcp.json IS handled (its args arrays split
//     `npx` from its spec across JSON lines, so invocations are re-synthesized
//     per server before scanning);
//   * `.ts`/`.mjs` spawn sites — none carry `npm install`/`npx` today (checked:
//     only prose strings and a token-echo); the class is named, not silent;
//   * `*.tf` heredoc `user_data`, `lefthook.yml`, `.github/actions/**`,
//     `cloud-init-*.yml` — all in the scan assembly (listed so the enumeration
//     is stated, not discovered later); none carries an install today;
//   * line-continuation (`\`-joined) install commands — none today.
// Anti-vacuity floors sit in the first test: a broken extractor that finds
// zero sites must report red, not green.

const REPO_ROOT = path.resolve(__dirname, "../../..");

function readRel(rel: string): string {
  return readFileSync(path.join(REPO_ROOT, rel), "utf8");
}
function existsRel(rel: string): boolean {
  return existsSync(path.join(REPO_ROOT, rel));
}

// ---------------------------------------------------------------------------
// THE TABLE. One row per (file, pkg); `expect` is asserted against EVERY
// scanned occurrence of that pkg in that file — two differing pins of one pkg
// in one file cannot both be declared, by construction.
// ---------------------------------------------------------------------------

type PinRow =
  | { kind: "literal"; file: string; pkg: string; expect: string }
  | { kind: "env"; file: string; pkg: string; envVar: string }
  | { kind: "bare-npx"; file: string; pkg: string };

const PIN_TABLE: PinRow[] = [
  // ---- apps/web-platform/Dockerfile (cli-tools stage globals) ----
  { kind: "literal", file: "apps/web-platform/Dockerfile", pkg: "@anthropic-ai/claude-code", expect: "2.1.293" },
  { kind: "literal", file: "apps/web-platform/Dockerfile", pkg: "likec4", expect: "1.60.0" },
  { kind: "literal", file: "apps/web-platform/Dockerfile", pkg: "vitest", expect: "4.1.12" },
  { kind: "literal", file: "apps/web-platform/Dockerfile", pkg: "playwright", expect: "1.61.0-alpha-1778188671000" },
  // ---- .github/workflows/ci.yml ----
  { kind: "literal", file: ".github/workflows/ci.yml", pkg: "npm", expect: "11.21.1" },
  { kind: "literal", file: ".github/workflows/ci.yml", pkg: "likec4", expect: "1.60.0" },
  { kind: "literal", file: ".github/workflows/ci.yml", pkg: "playwright", expect: "1.60.0" },
  { kind: "literal", file: ".github/workflows/ci.yml", pkg: "http-server", expect: "14.1.1" },
  { kind: "env", file: ".github/workflows/ci.yml", pkg: "@openai/codex", envVar: "CODEX_PIN" },
  { kind: "env", file: ".github/workflows/ci.yml", pkg: "@opencode/cli", envVar: "OPENCODE_PIN" },
  { kind: "bare-npx", file: ".github/workflows/ci.yml", pkg: "playwright" },
  { kind: "bare-npx", file: ".github/workflows/ci.yml", pkg: "@11ty/eleventy" },
  { kind: "bare-npx", file: ".github/workflows/ci.yml", pkg: "http-server" },
  // ---- .github/workflows/deploy-docs.yml ----
  { kind: "literal", file: ".github/workflows/deploy-docs.yml", pkg: "playwright", expect: "1.60.0" },
  { kind: "literal", file: ".github/workflows/deploy-docs.yml", pkg: "http-server", expect: "14.1.1" },
  { kind: "literal", file: ".github/workflows/deploy-docs.yml", pkg: "wrangler", expect: "4.124.0" },
  { kind: "bare-npx", file: ".github/workflows/deploy-docs.yml", pkg: "@11ty/eleventy" },
  { kind: "bare-npx", file: ".github/workflows/deploy-docs.yml", pkg: "http-server" },
  // ---- .github/workflows/gdpr-gate-self-test.yml ----
  { kind: "literal", file: ".github/workflows/gdpr-gate-self-test.yml", pkg: "lefthook", expect: "2.2.2" },
  // ---- .github/workflows/main-health-monitor.yml ----
  { kind: "literal", file: ".github/workflows/main-health-monitor.yml", pkg: "likec4", expect: "1.60.0" },
  // ---- .github/workflows/npm-publish.yml ----
  { kind: "literal", file: ".github/workflows/npm-publish.yml", pkg: "npm", expect: "11.21.1" },
  // ---- .github/workflows/scheduled-marketplace-drift.yml ----
  { kind: "env", file: ".github/workflows/scheduled-marketplace-drift.yml", pkg: "@anthropic-ai/claude-code", envVar: "CLI_VERSION" },
  // ---- .github/workflows/web-platform-release.yml ----
  { kind: "bare-npx", file: ".github/workflows/web-platform-release.yml", pkg: "playwright" },
  // ---- .mcp.json (both surfaces pin @playwright/mcp@0.0.78; the lockfile's
  // nested copy is 0.0.75 — the 0.0.78 pin is the attested direction per
  // knowledge-base/legal/compliance-posture.md, recorded not re-litigated) ----
  { kind: "literal", file: ".mcp.json", pkg: "@playwright/mcp", expect: "0.0.78" },
  { kind: "literal", file: "plugins/soleur/.mcp.json", pkg: "@playwright/mcp", expect: "0.0.78" },
  // ---- plugins/soleur/scripts/render-c4-model.sh ----
  { kind: "env", file: "plugins/soleur/scripts/render-c4-model.sh", pkg: "likec4", envVar: "LIKEC4_VERSION" },
  // ---- apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh ----
  { kind: "env", file: "apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh", pkg: "bun", envVar: "BUN_VERSION" },
  // ---- package.json script surfaces ----
  { kind: "bare-npx", file: "package.json", pkg: "@11ty/eleventy" },
  { kind: "bare-npx", file: "apps/web-platform/package.json", pkg: "playwright" },
  { kind: "bare-npx", file: "plugins/soleur/docs/package.json", pkg: "@11ty/eleventy" },
  // ---- scripts/validate-blog-links.sh builds the docs site via npx when no
  // _site dir is passed — resolves the root lockfile's @11ty/eleventy ----
  { kind: "bare-npx", file: "scripts/validate-blog-links.sh", pkg: "@11ty/eleventy" },
];

// Manifests whose declared deps bind no lockfile. `deps` records the live
// spec per package (asserted — a bump that edits the manifest but not this
// row is red); `{}` rows assert the manifest stays dep-free.
const MANIFEST_CARVEOUTS: { manifest: string; deps: Record<string, string>; why: string }[] = [
  {
    manifest: "packages/opencode-plugin/package.json",
    deps: { yaml: "^2.8.3" },
    why: "published to npm via npm-publish.yml; consumers resolve its ranges, no lockfile binds them",
  },
  {
    manifest: "plugins/soleur/docs/package.json",
    deps: {},
    why: "scripts-only manifest; its `cd ../../../` npx scripts resolve through the root lockfile",
  },
  {
    manifest: "plugins/soleur/skills/code-to-prd/test/fixture/package.json",
    deps: {},
    why: "synthetic walker fixture, private, never installed",
  },
];

// ---------------------------------------------------------------------------
// Assembly — recursive walk (no git dependency), mirroring
// lint-workflow-install-sites.sh's lesson that a root-only glob misses nested
// .github/workflows/ trees.
// ---------------------------------------------------------------------------

const SKIP_DIRS = new Set([
  ".git",
  "node_modules",
  ".worktrees",
  "worktrees", // .claude/worktrees holds nested checkouts
  ".next",
  "dist",
  "coverage",
  "_site",
  ".turbo",
  ".cache",
  "out",
]);

function walk(dir: string, rel: string, acc: string[]): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) {
      if (!SKIP_DIRS.has(e.name)) walk(path.join(REPO_ROOT, r), r, acc);
      continue;
    }
    acc.push(r);
  }
  return acc;
}

const TEST_SURFACE = /(^|\/)(test|tests|fixtures?|__fixtures__)(\/|$)|\.test\.(sh|ts|tsx|mjs|py)$/;

function inScanSet(rel: string): boolean {
  const base = path.basename(rel);
  if (TEST_SURFACE.test(rel)) return false;
  if (/\.(ya?ml)$/.test(rel) && /(^|\/)\.github\/(workflows|actions)\//.test(rel)) return true;
  if (/^cloud-init.*\.(ya?ml)$/.test(base)) return true;
  if (/^lefthook.*\.(ya?ml)$/.test(base)) return true;
  if (rel.endsWith(".sh")) return true;
  if (rel.endsWith(".template")) return true;
  if (base === ".mcp.json") return true;
  if (base === "package.json") return true;
  if (base === "Dockerfile" || base.startsWith("Dockerfile.")) return true;
  return false;
}

// ---------------------------------------------------------------------------
// Extraction — command-position parser
// ---------------------------------------------------------------------------

type Site = {
  file: string;
  pkg: string;
  /** null = unpinned (bare spec) */
  spec: string | null;
  via: "npm-install" | "npx" | "npm-install-unpinned";
  line: number;
};

// Words consumed while looking for the command word: YAML step keys, Dockerfile
// instructions, shell command prefixes and env-assignment prefixes.
const PREFIX_WORDS = new Set([
  "run:",
  "RUN",
  "-",
  "env",
  "exec",
  "sudo",
  "command",
  "nice",
  "time",
  "nohup",
  "xargs",
  "if",
  "then",
  "elif",
  "do",
  "!",
  "{",
  "(",
]);
// Prefix flags that consume one argument of their own (env -u NAME, env -C DIR).
const PREFIX_ARG_FLAGS = new Set(["-u", "-C", "-v", "-S", "-g", "-n"]);

/** Index of the command word, or -1 when the segment has none. */
function commandIndex(toks: string[]): number {
  let i = 0;
  while (i < toks.length) {
    const t = toks[i];
    if (PREFIX_WORDS.has(t)) {
      i++;
      continue;
    }
    if (PREFIX_ARG_FLAGS.has(t)) {
      i += 2;
      continue;
    }
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) {
      i++;
      continue;
    }
    if (t.startsWith("-") && t !== "--") {
      i++;
      continue;
    }
    break;
  }
  return i < toks.length ? i : -1;
}

function parseSpecToken(tok: string): { pkg: string; spec: string | null } | null {
  const t = tok.replace(/^["'`]+|["'`),.;]+$/g, "");
  const m = t.match(/^(@[\w.-]+\/)?([\w][\w.-]*?)(?:@(.+))?$/);
  if (!m) return null;
  const pkg = (m[1] ?? "") + m[2];
  if (!pkg || pkg.includes("=")) return null;
  return { pkg, spec: m[3] ?? null };
}

/** Split a line into command segments on `&&`, `||`, `;`, `|`, `&` — only
 *  OUTSIDE quotes. A quoted `&&` (`echo "… && npm install …"`) is not a
 *  boundary: splitting there would promote a message-string into a command. */
function segmentsOf(line: string): string[] {
  const segs: string[] = [];
  let cur = "";
  let sq = false;
  let dq = false;
  const flush = () => {
    const t = cur.trim();
    if (t) segs.push(t);
    cur = "";
  };
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (sq) {
      cur += c;
      if (c === "'") sq = false;
      continue;
    }
    if (dq) {
      cur += c;
      if (c === '"') dq = false;
      continue;
    }
    if (c === "'") {
      sq = true;
      cur += c;
      continue;
    }
    if (c === '"') {
      dq = true;
      cur += c;
      continue;
    }
    if (c === "&" && line[i + 1] === "&") {
      flush();
      i++;
      continue;
    }
    if (c === "|" && line[i + 1] === "|") {
      flush();
      i++;
      continue;
    }
    if (c === ";" || c === "|" || c === "&") {
      flush();
      continue;
    }
    cur += c;
  }
  flush();
  return segs;
}

function processTokens(file: string, lineNo: number, toks: string[], out: Site[]): void {
  const ci = commandIndex(toks);
  if (ci === -1) return;
  const cmd = toks[ci];

  if (cmd === "npm") {
    const sub = toks[ci + 1];
    if (sub !== "install" && sub !== "i") return;
    for (const tok of toks.slice(ci + 2)) {
      if (tok === "--") break;
      if (tok.startsWith("-")) continue;
      if (/^[A-Z_][A-Z0-9_]*=/.test(tok)) continue;
      const parsed = parseSpecToken(tok);
      if (!parsed) continue;
      out.push({
        file,
        pkg: parsed.pkg,
        spec: parsed.spec,
        via: parsed.spec === null ? "npm-install-unpinned" : "npm-install",
        line: lineNo,
      });
    }
  } else if (cmd === "npx") {
    const rest = toks.slice(ci + 1);
    if (rest.some((t) => t === "--no-install" || t === "--offline")) return;
    for (const tok of rest) {
      if (tok === "--") break;
      if (tok.startsWith("-")) continue;
      const parsed = parseSpecToken(tok);
      if (parsed) out.push({ file, pkg: parsed.pkg, spec: parsed.spec, via: "npx", line: lineNo });
      break;
    }
  } else {
    // A standalone `--` opens a nested command (proxy-wrapper inner command,
    // e.g. `proxy.py -- npx pkg@ver`).
    const dashIdx = toks.indexOf("--", ci + 1);
    if (dashIdx !== -1) processTokens(file, lineNo, toks.slice(dashIdx + 1), out);
  }
  // Any other command word: segment carries no npm/npx invocation at command
  // position — a later `npx` token is prose (for-list, message, positional).
}

function extractFromLine(file: string, lineNo: number, rawLine: string, out: Site[]): void {
  const trimmed = rawLine.trimStart();
  if (trimmed.startsWith("#")) return;
  // A trailing comment is stripped before tokenizing — `# see TOOLCHAIN PINS`
  // must not read as positional package specs.
  const commentAt = rawLine.search(/\s+#/);
  const line = commentAt === -1 ? rawLine : rawLine.slice(0, commentAt);

  for (const seg of segmentsOf(line)) {
    processTokens(file, lineNo, seg.split(/\s+/).filter(Boolean), out);
  }
}

/** .mcp.json: args arrays split `npx` from its spec across lines — parse the
 *  JSON and re-synthesize each server's invocation as one line. */
function mcpInvocationLines(rel: string): string[] {
  const doc = JSON.parse(readRel(rel)) as {
    mcpServers?: Record<string, { command?: string; args?: unknown }>;
  };
  const lines: string[] = [];
  for (const srv of Object.values(doc.mcpServers ?? {})) {
    const args = Array.isArray(srv.args) ? (srv.args as unknown[]).join(" ") : String(srv.args ?? "");
    lines.push(`${srv.command ?? ""} ${args}`);
  }
  return lines;
}

/** package.json: only the `scripts` map holds invocations. */
function manifestScriptLines(rel: string): string[] {
  const doc = JSON.parse(readRel(rel)) as { scripts?: Record<string, string> };
  return Object.values(doc.scripts ?? {});
}

const LOCKFILES = [
  "package-lock.json",
  "apps/web-platform/package-lock.json",
  "plugins/soleur/skills/pencil-setup/scripts/package-lock.json",
  "plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json",
  "spike/package-lock.json",
];

function loadSites(): { sites: Site[]; files: string[] } {
  const all = walk(REPO_ROOT, "", []);
  const files = all.filter(inScanSet).sort();
  const sites: Site[] = [];
  for (const rel of files) {
    const base = path.basename(rel);
    let lines: string[];
    if (base === ".mcp.json") lines = mcpInvocationLines(rel);
    else if (base === "package.json") lines = manifestScriptLines(rel);
    else lines = readRel(rel).split("\n");
    lines.forEach((l, i) => extractFromLine(rel, i + 1, l, sites));
  }
  return { sites, files };
}

const EXACT_RE = /^\d+\.\d+\.\d+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$/;
const PIN_FILE_RE = /([\w./-]*\.(?:bun-version|nvmrc|node-version|tool-versions|python-version|ruby-version|go-version))/;

/** A site is satisfied by a row iff the row's shape matches the site's. */
function rowSatisfies(row: PinRow, s: Site): boolean {
  if (row.file !== s.file || row.pkg !== s.pkg) return false;
  if (row.kind === "literal") return s.spec === row.expect;
  if (row.kind === "env") return s.spec === `\${${row.envVar}}`;
  return s.spec === null;
}
/** A row is live iff a site exists only it can explain (its own shape). */
function rowIsLive(row: PinRow, sites: Site[]): boolean {
  return sites.some((s) => rowSatisfies(row, s));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const { sites, files } = loadSites();

describe("adhoc npm install pin-table (#11855)", () => {
  it("scan assembly is non-vacuous (floors)", () => {
    // ~30 scan files and ~30 site occurrences today; a broken extractor or a
    // truncated walk must report red, never a quiet green.
    expect(files.length).toBeGreaterThanOrEqual(25);
    expect(sites.length).toBeGreaterThanOrEqual(20);
    expect(PIN_TABLE.length).toBeGreaterThanOrEqual(18);
    expect(MANIFEST_CARVEOUTS.length).toBeGreaterThanOrEqual(3);
  });

  it("every scanned site is satisfied by a declared row", () => {
    const violations: string[] = [];
    for (const s of sites) {
      const rows = PIN_TABLE.filter((r) => r.file === s.file && r.pkg === s.pkg);
      if (rows.length === 0) {
        violations.push(`UNDECLARED site ${s.file}:${s.line} ${s.pkg}@${s.spec ?? "<bare>"} — add a pin or a table row`);
        continue;
      }
      if (!rows.some((r) => rowSatisfies(r, s))) {
        const declared = rows
          .map((r) => (r.kind === "literal" ? `${r.pkg}@${r.expect}` : r.kind === "env" ? `${r.pkg}@\${${r.envVar}}` : `bare ${r.pkg}`))
          .join(", ");
        violations.push(`${s.file}:${s.line} ${s.pkg}@${s.spec ?? "<bare>"} matches no declared row (${declared})`);
      }
    }
    expect(violations).toEqual([]);
  });

  it("every declared spec is an exact version", () => {
    for (const r of PIN_TABLE) {
      if (r.kind === "literal") {
        expect(r.expect, `${r.file} ${r.pkg}: floating spec ${r.expect}`).toMatch(EXACT_RE);
      }
    }
  });

  it("every row has a live site (no dead declarations)", () => {
    const dead = PIN_TABLE.filter((r) => !rowIsLive(r, sites)).map(
      (r) =>
        `${r.pkg}${r.kind === "literal" ? `@${r.expect}` : r.kind === "env" ? ` via \${${r.envVar}}` : " (bare)"} in ${r.file}`,
    );
    expect(dead).toEqual([]);
  });

  it("env-pin variables bind an exact semver — literal in-file or via pin file", () => {
    const violations: string[] = [];
    for (const r of PIN_TABLE) {
      if (r.kind !== "env") continue;
      const text = readRel(r.file);
      const assign = text.match(new RegExp(`${r.envVar}\\s*[:=]\\s*(.+)`));
      if (!assign) {
        violations.push(`${r.file}: ${r.envVar} is never assigned`);
        continue;
      }
      const rhs = assign[1].trim();
      if (EXACT_RE.test(rhs.replace(/^["']|["'\s]*$/g, ""))) continue;
      const pinFile = rhs.match(PIN_FILE_RE)?.[1];
      if (pinFile && existsRel(pinFile) && EXACT_RE.test(readRel(pinFile).trim())) continue;
      violations.push(
        `${r.file}: ${r.envVar} binds ${JSON.stringify(rhs.slice(0, 60))} — not an exact semver literal and not a version pin file`,
      );
    }
    expect(violations).toEqual([]);
  });

  it("bare-npx packages resolve through a bound tree (lockfile or same-file install)", () => {
    const locks = LOCKFILES.map((lf) => JSON.parse(readRel(lf)) as { packages: Record<string, unknown> });
    const locked = new Set<string>();
    for (const l of locks) {
      for (const k of Object.keys(l.packages)) {
        const m = k.match(/(?:^|\/)node_modules\/(.+)$/);
        if (m) locked.add(m[1]);
      }
    }
    const installedHere = new Set(
      PIN_TABLE.filter((r) => r.kind !== "bare-npx").map((r) => `${r.file}${r.pkg}`),
    );
    const violations: string[] = [];
    for (const r of PIN_TABLE) {
      if (r.kind !== "bare-npx") continue;
      if (!locked.has(r.pkg) && !installedHere.has(`${r.file}${r.pkg}`)) {
        violations.push(
          `${r.file}: bare \`npx ${r.pkg}\` resolves nothing bound — it fetches latest. Pin it or install it in-file`,
        );
      }
    }
    expect(violations).toEqual([]);
  });

  it("unpinned npm-install specs are violations by construction", () => {
    const bad = sites.filter((s) => s.via === "npm-install-unpinned");
    expect(
      bad.map((s) => `${s.file}:${s.line} ${s.pkg}`),
      "a package token after `npm install` with no @version floats",
    ).toEqual([]);
  });

  it("every tracked package.json binds a lockfile or sits in MANIFEST_CARVEOUTS", () => {
    const all = walk(REPO_ROOT, "", []);
    const manifests = all.filter((r) => path.basename(r) === "package.json");
    const carved = new Map(MANIFEST_CARVEOUTS.map((c) => [c.manifest, c]));

    // Workspace membership: any lockfile registering this manifest dir as a key.
    const workspaceDirs = new Set<string>();
    for (const lf of LOCKFILES) {
      const l = JSON.parse(readRel(lf)) as { packages: Record<string, unknown> };
      for (const k of Object.keys(l.packages)) {
        if (k && !k.includes("node_modules")) workspaceDirs.add(k);
      }
    }

    const violations: string[] = [];
    for (const m of manifests) {
      const dir = path.dirname(m);
      if (existsRel(`${dir}/package-lock.json`)) continue;
      if (workspaceDirs.has(dir)) continue;
      const row = carved.get(m);
      if (!row) {
        violations.push(`${m}: no lockfile binds its declared deps and no MANIFEST_CARVEOUTS row names it`);
        continue;
      }
      const doc = JSON.parse(readRel(m)) as {
        dependencies?: Record<string, string>;
        devDependencies?: Record<string, string>;
        peerDependencies?: Record<string, string>;
      };
      const liveDeps = { ...doc.dependencies, ...doc.devDependencies, ...doc.peerDependencies };
      for (const [name, spec] of Object.entries(liveDeps)) {
        if (row.deps[name] !== spec) {
          violations.push(`${m}: dep ${name}@${spec} not recorded in its carve-out row (${row.deps[name] ?? "absent"})`);
        }
      }
      for (const name of Object.keys(row.deps)) {
        if (!(name in liveDeps)) violations.push(`${m}: carve-out records ${name} but the manifest no longer declares it`);
      }
    }
    expect(violations).toEqual([]);
  });
});
