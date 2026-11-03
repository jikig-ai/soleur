import { describe, it, expect } from "vitest";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Pin-table guard (#11855): every npm tree resolved OUTSIDE a lockfile —
// `npm install -g`, `npm i -g`, `npm install --no-save`, `npm exec`, and
// `npx pkg@ver` invocations — must carry an exact version declared here,
// reconciled BOTH ways: every scanned site needs a row, every row needs a
// live site. Extends the single-site parity pattern
// (dockerfile-vitest-version-pin) into a table so an added or unpinned site
// reddens instead of floating silently.
//
// SITE SHAPES, three kinds:
//   literal  — `npm install -g vitest@4.1.12`, `npx playwright@1.61.0-alpha-…`
//   env      — `npm i -g "@openai/codex@${CODEX_PIN}"`; the same file must bind
//              the variable to an exact semver literal (`CODEX_PIN: "0.156.1"`,
//              `VAR="x.y.z"`), or to a version PIN FILE (`< .bun-version`,
//              `.nvmrc`, `.tool-versions`) whose content is exact semver.
//   bare-npx — `npx playwright test`: resolves LOCAL node_modules only when the
//              row names the binding (a tracked lockfile, or a pinned install
//              in the same file); on a miss npx fetches `latest` — the float
//              this guard exists to kill. `npx --no-install` is never a site.
//              (Same-JOB limitation: a same-file pin in job A does not license
//              bare npx in job B's fresh runner — `resolves` rows name the
//              binding that actually exists today; a cross-job reuse is a
//              deliberate new row, not an accidental pass.)
//
// MANIFEST COVERAGE: a tracked `package.json` whose declared deps bind no
// lockfile (not a workspace member, no same-dir package-lock.json) must sit in
// MANIFEST_CARVEOUTS with its dep specs recorded — the row reddens on drift so
// a dep added to an unbound manifest is a deliberate edit, not a silent float.
//
// EXTRACTION is command-position, not raw-string: `npm`/`npx` counts as an
// invocation only when it is the command word of a segment — leading
// `RUN`/`run:`/YAML-bullet/`env`/`sudo`/`exec`/`time`-class prefixes are
// consumed, segments split on `&&`/`;`/`|`/`&` OUTSIDE quotes and recurse on a
// standalone `--` token (proxy-wrapper inner command, `sudo -- npm …`, and
// `npx npm@x install …` nested installs). What this skips, by design:
//   * `npx` inside a `for`-list word, inside `die "…"`/`echo "…"` arguments,
//     inside `::error::` help text — none sits at command position;
//   * `npm ci` (subcommand isn't install|i|exec|x) — lockfile-bound;
//   * `apt-get install`, `pip install`, `bun install`, `bunx` — other package
//     managers; lint-workflow-install-sites.sh owns the bun side.
// BOUNDARY — surfaces enumerated and NOT scanned here:
//   * `*.test.{sh,ts,tsx}` and `**/test/**` — mutation fixtures necessarily
//     carry violating text (same exclusion as lint-workflow-install-sites.sh);
//   * `*.md`/SKILL.md prose — scaffolded examples; kept honest by review;
//   * `.ts`/`.mjs`/`.py` spawn sites — none carry `npm install`/`npx` today
//     (checked: only prose strings and a token-echo); named, not silent;
//   * nested-shell strings (`bash -c "…"`, `$(…)`) inside .sh/.yml — no such
//     invocation exists today; .mcp.json IS handled (its args arrays split
//     `npx` from its spec across JSON lines, so invocations are re-synthesized
//     per server before scanning);
//   * prefix words beyond PREFIX_WORDS (`doas`, `pkexec`, `nix run`) — none
//     today; extend the list when one lands;
//   * line-continuation (`\`-joined) install commands — none today.
// Anti-vacuity: floors near measured reality AND sentinel member assertions —
// a walk that silently drops a whole surface class must report red.

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
// in one file cannot both be declared, by construction (see the conflict note
// in the site-satisfaction test's message).
// ---------------------------------------------------------------------------

type PinRow =
  | { kind: "literal"; file: string; pkg: string; expect: string }
  | { kind: "env"; file: string; pkg: string; envVar: string }
  | { kind: "bare-npx"; file: string; pkg: string; resolves: BareNpxBinding[] };

/** What binds a bare-npx package: a lockfile path, or "same-file-install"
 *  (a declared literal/env install row for the same pkg in the same file). */
type BareNpxBinding = string | "same-file-install";

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
  { kind: "bare-npx", file: ".github/workflows/ci.yml", pkg: "playwright", resolves: ["apps/web-platform/package-lock.json"] },
  { kind: "bare-npx", file: ".github/workflows/ci.yml", pkg: "@11ty/eleventy", resolves: ["package-lock.json"] },
  { kind: "bare-npx", file: ".github/workflows/ci.yml", pkg: "http-server", resolves: ["same-file-install"] },
  // ---- .github/workflows/deploy-docs.yml ----
  { kind: "literal", file: ".github/workflows/deploy-docs.yml", pkg: "playwright", expect: "1.60.0" },
  { kind: "literal", file: ".github/workflows/deploy-docs.yml", pkg: "http-server", expect: "14.1.1" },
  { kind: "literal", file: ".github/workflows/deploy-docs.yml", pkg: "wrangler", expect: "4.124.0" },
  { kind: "bare-npx", file: ".github/workflows/deploy-docs.yml", pkg: "@11ty/eleventy", resolves: ["package-lock.json"] },
  { kind: "bare-npx", file: ".github/workflows/deploy-docs.yml", pkg: "http-server", resolves: ["same-file-install"] },
  // ---- .github/workflows/gdpr-gate-self-test.yml ----
  { kind: "literal", file: ".github/workflows/gdpr-gate-self-test.yml", pkg: "lefthook", expect: "2.2.2" },
  // ---- .github/workflows/main-health-monitor.yml ----
  { kind: "literal", file: ".github/workflows/main-health-monitor.yml", pkg: "likec4", expect: "1.60.0" },
  // ---- .github/workflows/npm-publish.yml ----
  { kind: "literal", file: ".github/workflows/npm-publish.yml", pkg: "npm", expect: "11.21.1" },
  // ---- .github/workflows/scheduled-marketplace-drift.yml ----
  { kind: "env", file: ".github/workflows/scheduled-marketplace-drift.yml", pkg: "@anthropic-ai/claude-code", envVar: "CLI_VERSION" },
  // ---- .github/workflows/web-platform-release.yml ----
  { kind: "bare-npx", file: ".github/workflows/web-platform-release.yml", pkg: "playwright", resolves: ["apps/web-platform/package-lock.json"] },
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
  { kind: "bare-npx", file: "package.json", pkg: "@11ty/eleventy", resolves: ["package-lock.json"] },
  { kind: "bare-npx", file: "apps/web-platform/package.json", pkg: "playwright", resolves: ["apps/web-platform/package-lock.json"] },
  { kind: "bare-npx", file: "plugins/soleur/docs/package.json", pkg: "@11ty/eleventy", resolves: ["package-lock.json"] },
  // ---- scripts/validate-blog-links.sh builds the docs site via npx when no
  // _site dir is passed — resolves the root lockfile's @11ty/eleventy ----
  { kind: "bare-npx", file: "scripts/validate-blog-links.sh", pkg: "@11ty/eleventy", resolves: ["package-lock.json"] },
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
  if (rel.endsWith(".tf")) return true;
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
  /** File line number, or a synthesized key (`scripts.x`, `mcpServers.x`). */
  loc: string;
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
// Prefix flags that consume one argument of their own (env -u NAME, env -C DIR,
// env -S STRING). Deliberately excludes -v/-n/-g: those are arg-taking for env
// but bare flags for `time`/`command -v`, and eating the next token there loses
// a real command.
const PREFIX_ARG_FLAGS = new Set(["-u", "-C", "-S"]);
// npm flags that take a separate (non `=`-joined) value; each consumes the next
// token so it never parses as a package spec.
const NPM_ARG_FLAGS = new Set([
  "--prefix",
  "--cache",
  "--userconfig",
  "--globalconfig",
  "--before",
  "--tag",
  "--registry",
  "--loglevel",
  "--scope",
  "--otp",
  "--access",
  "--workspace",
  "-w",
]);

/** Index of the command word, or -1 when the segment has none. */
function commandIndex(toks: string[]): number {
  let i = 0;
  while (i < toks.length) {
    const t = toks[i];
    if (t === "--") return i; // boundary at command position — caller recurses
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
    if (t.startsWith("-")) {
      i++;
      continue;
    }
    break;
  }
  return i < toks.length ? i : -1;
}

function unquote(t: string): string {
  return t.replace(/^["'`]+|["'`]+$/g, "");
}

function parseSpecToken(tok: string): { pkg: string; spec: string | null } | null {
  const t = unquote(tok).replace(/[),.;]+$/, "");
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

/** Whitespace-split a segment, keeping quoted spans as single tokens so a
 *  `--` inside `"do not run -- npx foo"` never reads as a boundary. */
function tokenize(seg: string): string[] {
  const toks: string[] = [];
  let cur = "";
  let sq = false;
  let dq = false;
  const flush = () => {
    if (cur) toks.push(cur);
    cur = "";
  };
  for (const c of seg) {
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
    if (/\s/.test(c)) {
      flush();
      continue;
    }
    cur += c;
  }
  flush();
  return toks;
}

/** Index of the first non-flag token at/after `from`; npm's own value-taking
 *  flags consume their argument (handles `npm --prefix /opt install …`). */
function npmSubcommandIndex(toks: string[], from: number): number {
  for (let i = from; i < toks.length; i++) {
    const t = toks[i];
    if (t === "--") return -1; // options closed without a subcommand
    if (NPM_ARG_FLAGS.has(t)) {
      i++;
      continue;
    }
    if (t.startsWith("-")) continue;
    return i;
  }
  return -1;
}

function processTokens(file: string, loc: string, toks: string[], out: Site[]): void {
  const ci = commandIndex(toks);
  if (ci === -1) return;
  const cmd = unquote(toks[ci]);

  if (cmd === "--") {
    // A standalone `--` at command position opens a nested command
    // (`sudo -- npm install …`, `proxy.py -- npx pkg@ver`).
    processTokens(file, loc, toks.slice(ci + 1), out);
    return;
  }

  if (cmd === "npm") {
    const si = npmSubcommandIndex(toks, ci + 1);
    if (si === -1) return;
    const sub = unquote(toks[si]);
    if (sub === "install" || sub === "i") {
      for (let i = si + 1; i < toks.length; i++) {
        const tok = toks[i];
        if (tok === "--") continue; // end-of-OPTIONS for npm, not end of args
        if (NPM_ARG_FLAGS.has(tok)) {
          i++;
          continue;
        }
        if (tok.startsWith("-")) continue;
        if (/^[A-Z_][A-Z0-9_]*=/.test(tok)) continue;
        const parsed = parseSpecToken(tok);
        if (!parsed) continue;
        out.push({
          file,
          pkg: parsed.pkg,
          spec: parsed.spec,
          via: parsed.spec === null ? "npm-install-unpinned" : "npm-install",
          loc,
        });
      }
    } else if (sub === "exec" || sub === "x") {
      // `npm exec [--yes] pkg@ver -- cmd…`: the spec is the first non-flag
      // token before `--`; args after `--` are the invoked command's, not pkgs.
      for (let i = si + 1; i < toks.length; i++) {
        const tok = toks[i];
        if (tok === "--") break;
        if (NPM_ARG_FLAGS.has(tok)) {
          i++;
          continue;
        }
        if (tok.startsWith("-")) continue;
        const parsed = parseSpecToken(tok);
        if (!parsed) continue;
        emitNpxSite(file, loc, parsed, toks.slice(i + 1), out);
        break;
      }
    }
  } else if (cmd === "npx") {
    const rest = toks.slice(ci + 1);
    if (rest.some((t) => t === "--no-install" || t === "--offline")) return;
    for (let i = 0; i < rest.length; i++) {
      const tok = rest[i];
      if (tok === "--") break;
      if (tok.startsWith("-")) continue;
      const parsed = parseSpecToken(tok);
      if (!parsed) continue;
      emitNpxSite(file, loc, parsed, rest.slice(i + 1), out);
      break;
    }
  }
  else {
    // A standalone `--` inside the segment opens a nested command
    // (proxy-wrapper inner command, `python3 proxy.py -- npx pkg@ver`).
    const dashIdx = toks.indexOf("--", ci + 1);
    if (dashIdx !== -1) processTokens(file, loc, toks.slice(dashIdx + 1), out);
  }
  // Any other command word: segment carries no npm/npx invocation at command
  // position — a later `npx` token is prose (for-list, message, positional).
}

function emitNpxSite(
  file: string,
  loc: string,
  parsed: { pkg: string; spec: string | null },
  rest: string[],
  out: Site[],
): void {
  out.push({ file, pkg: parsed.pkg, spec: parsed.spec, via: "npx", loc });
  // `npx npm@x install …` runs a nested npm invocation — the spec names the
  // runner AND the inner install resolves its own tree: both need declaring.
  if (parsed.pkg === "npm") {
    processTokens(file, loc, ["npm", ...rest], out);
  }
}

function extractFromLine(file: string, loc: string, rawLine: string, out: Site[]): void {
  const trimmed = rawLine.trimStart();
  if (trimmed.startsWith("#")) return;
  // A trailing comment is stripped before tokenizing — `# see TOOLCHAIN PINS`
  // must not read as positional package specs.
  const commentAt = rawLine.search(/\s+#/);
  const line = commentAt === -1 ? rawLine : rawLine.slice(0, commentAt);

  for (const seg of segmentsOf(line)) {
    processTokens(file, loc, tokenize(seg), out);
  }
}

/** .mcp.json: args arrays split `npx` from its spec across lines — parse the
 *  JSON and re-synthesize each server's invocation as one line. */
function mcpInvocationLines(rel: string): [loc: string, line: string][] {
  const doc = JSON.parse(readRel(rel)) as {
    mcpServers?: Record<string, { command?: string; args?: unknown }>;
  };
  const lines: [string, string][] = [];
  for (const [name, srv] of Object.entries(doc.mcpServers ?? {})) {
    const args = Array.isArray(srv.args) ? (srv.args as unknown[]).join(" ") : String(srv.args ?? "");
    lines.push([`mcpServers.${name}`, `${srv.command ?? ""} ${args}`]);
  }
  return lines;
}

/** package.json: only the `scripts` map holds invocations. */
function manifestScriptLines(rel: string): [loc: string, line: string][] {
  const doc = JSON.parse(readRel(rel)) as { scripts?: Record<string, string> };
  return Object.entries(doc.scripts ?? {}).map(([k, v]) => [`scripts.${k}`, v]);
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
    let entries: [loc: string, line: string][];
    if (base === ".mcp.json") entries = mcpInvocationLines(rel);
    else if (base === "package.json") entries = manifestScriptLines(rel);
    else entries = readRel(rel).split("\n").map((l, i): [string, string] => [`${i + 1}`, l]);
    for (const [loc, l] of entries) extractFromLine(rel, loc, l, sites);
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
/** A row is live iff a site exists it can explain (its own shape). */
function rowIsLive(row: PinRow, sites: Site[]): boolean {
  return sites.some((s) => rowSatisfies(row, s));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const { sites, files } = loadSites();

describe("adhoc npm install pin-table (#11855)", () => {
  it("scan assembly is non-vacuous (floors near measured reality + sentinels)", () => {
    // Measured: 933 scan files, 35 sites, 31 rows. A walk that silently drops a
    // whole surface class (e.g. only .github/workflows/ survives = ~103 files /
    // ~21 sites) must report red, not green.
    expect(files.length).toBeGreaterThanOrEqual(800);
    expect(sites.length).toBeGreaterThanOrEqual(30);
    expect(PIN_TABLE.length).toBeGreaterThanOrEqual(28);
    expect(MANIFEST_CARVEOUTS.length).toBeGreaterThanOrEqual(3);
    for (const sentinel of [
      "apps/web-platform/Dockerfile",
      ".mcp.json",
      "package.json",
      ".github/workflows/ci.yml",
      "apps/web-platform/.github/workflows/constraint-gates.yml",
      "lefthook.yml",
      "plugins/soleur/scripts/render-c4-model.sh",
    ]) {
      expect(files, `scan set must contain ${sentinel}`).toContain(sentinel);
    }
  });

  it("every scanned site is satisfied by a declared row", () => {
    const violations: string[] = [];
    for (const s of sites) {
      const rows = PIN_TABLE.filter((r) => r.file === s.file && r.pkg === s.pkg);
      if (rows.length === 0) {
        violations.push(`UNDECLARED site ${s.file}:${s.loc} ${s.pkg}@${s.spec ?? "<bare>"} — add a pin or a table row`);
        continue;
      }
      if (!rows.some((r) => rowSatisfies(r, s))) {
        const declared = rows
          .map((r) =>
            r.kind === "literal" ? `${r.pkg}@${r.expect}` : r.kind === "env" ? `${r.pkg}@\${${r.envVar}}` : `bare ${r.pkg}`,
          )
          .join(", ");
        violations.push(
          `${s.file}:${s.loc} ${s.pkg}@${s.spec ?? "<bare>"} matches no declared row (${declared}) ` +
            `[one file may declare only one pin per pkg — a second differing pin cannot be declared, it must be unified]`,
        );
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

  it("env-pin variables bind an exact semver — every uncommented assignment", () => {
    const violations: string[] = [];
    for (const r of PIN_TABLE) {
      if (r.kind !== "env") continue;
      // Every line that binds the var (anchor: no `#` between line start and
      // the name — a commented-out `# CODEX_PIN: "x"` is not a binding, and a
      // `JUNK_CODEX_PIN:` name cannot shadow the match).
      const re = new RegExp(`^\\s*[^#\\n]*?\\b${r.envVar}\\s*[:=]\\s*(.+)$`, "gm");
      let found = false;
      for (const m of readRel(r.file).matchAll(re)) {
        found = true;
        const rhs = m[1].replace(/\s+#.*$/, "").trim(); // strip trailing comment BEFORE pin-file read
        if (EXACT_RE.test(rhs.replace(/^["']|["']$/g, ""))) continue;
        const pinFile = rhs.match(PIN_FILE_RE)?.[1];
        if (pinFile && existsRel(pinFile) && EXACT_RE.test(readRel(pinFile).trim())) continue;
        violations.push(
          `${r.file}: ${r.envVar} binds ${JSON.stringify(rhs.slice(0, 60))} — not an exact semver literal and not a version pin file`,
        );
      }
      if (!found) violations.push(`${r.file}: ${r.envVar} is never assigned`);
    }
    expect(violations).toEqual([]);
  });

  it("bare-npx packages resolve through the binding the row names", () => {
    const lockCache = new Map<string, Set<string>>();
    const lockedIn = (lf: string): Set<string> => {
      if (!lockCache.has(lf)) {
        const l = JSON.parse(readRel(lf)) as { packages: Record<string, unknown> };
        const names = new Set<string>();
        for (const k of Object.keys(l.packages)) {
          const m = k.match(/(?:^|\/)node_modules\/(.+)$/);
          if (m) names.add(m[1]);
        }
        lockCache.set(lf, names);
      }
      return lockCache.get(lf)!;
    };
    const installedHere = new Set(
      PIN_TABLE.filter((r) => r.kind !== "bare-npx").map((r) => `${r.file} ${r.pkg}`),
    );
    const violations: string[] = [];
    for (const r of PIN_TABLE) {
      if (r.kind !== "bare-npx") continue;
      if (!Array.isArray(r.resolves) || r.resolves.length === 0) {
        violations.push(`${r.file}: bare-npx row for ${r.pkg} names no binding (resolves is empty)`);
        continue;
      }
      for (const b of r.resolves) {
        if (b === "same-file-install") {
          if (!installedHere.has(`${r.file} ${r.pkg}`)) {
            violations.push(`${r.file}: ${r.pkg} claims same-file-install but no declared install row exists`);
          }
        } else {
          if (!existsRel(b)) {
            violations.push(`${r.file}: ${r.pkg} resolves via ${b} — lockfile does not exist`);
          } else if (!lockedIn(b).has(r.pkg)) {
            violations.push(`${r.file}: bare \`npx ${r.pkg}\` names ${b} but it has no node_modules/${r.pkg} — it fetches latest`);
          }
        }
      }
    }
    expect(violations).toEqual([]);
  });

  it("unpinned npm-install specs are violations by construction", () => {
    const bad = sites.filter((s) => s.via === "npm-install-unpinned");
    expect(
      bad.map((s) => `${s.file}:${s.loc} ${s.pkg}`),
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
