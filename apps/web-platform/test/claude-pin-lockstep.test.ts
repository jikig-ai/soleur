import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Lockstep guard (#12102): the claude runtime is pinned in several places that
// have to move together when a Bun/CLI advisory forces a bump, and nothing but
// a dated follow-through probe looked at them.
//
//   - every `anthropics/claude-code-action@<sha> # vX.Y.Z` pin the repository
//     carries is ONE (sha, tag) pair at or above MIN_ACTION_TAG — the action
//     bundles its own CLI and Bun, so a straggler keeps a vulnerable runtime in
//     a job that holds secrets;
//   - `CLI_VERSION` in scheduled-marketplace-drift.yml (and the install line
//     that reads it), the Dockerfile `npm install -g @anthropic-ai/claude-code@…`
//     and this app's package.json name the same claude-code version
//     (adhoc-npm-install-pin-table only checks the first is an exact semver,
//     deliberately not which one);
//   - every `@anthropic-ai/claude-agent-sdk*` entry in the pen-cli lock equals
//     this app's SDK pin, and the pen-cli override names it.
//
// POPULATION: the carriers are DISCOVERED (every .yml/.yaml/.template under
// .github and plugins/soleur/skills that names the action) and compared with
// EXPECTED_CARRIERS, so a new carrier is a deliberate one-line add rather than
// a file the guard never saw. The operator-digest asset is in the set on
// purpose: it is provisioned into another repository, so a copy already
// installed there keeps its old pin until re-provisioned (tracked in the
// follow-up issue), but this repository's copy must not lag. That makes the
// guard a COUPLING: bumping the action anywhere in this repository means
// bumping it in all six places, and a deliberate lag needs a named, ticketed
// exception added here, not a silent skip. On v1.0.101 the asset's unquoted
// `Bash(...)` allowlist was reduced to bare `Bash` by the action's argument
// parsing (source-read by the CTO, F7); operator-digest-workflow.test.sh now
// pins the quoting that survives every release.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const read = (rel: string): string => readFileSync(path.join(REPO_ROOT, rel), "utf8");

const TEMPLATE =
  "plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template";
const DIGEST_ASSET =
  "plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml";
const DRIFT_WORKFLOW = ".github/workflows/scheduled-marketplace-drift.yml";
const DOCKERFILE = "apps/web-platform/Dockerfile";
const PEN_CLI_DIR = "plugins/soleur/skills/pencil-setup/scripts/pen-cli";

const EXPECTED_CARRIERS: readonly string[] = [
  ".github/workflows/claude-code-review.yml",
  ".github/workflows/fix-constraints-stage-a.yml",
  ".github/workflows/scheduled-machinery-drain.yml",
  ".github/workflows/test-pretooluse-hooks.yml",
  DIGEST_ASSET,
  TEMPLATE,
];

// Each SHA the repository may pin, with the tag it was verified to be (a tag
// object resolved with `gh api repos/anthropics/claude-code-action/git/ref/tags/<tag>`).
// A pin comment is otherwise just text: this ties it to the SHA offline, and a new
// bump has to add its verified entry here deliberately.
const KNOWN_ACTION_PINS: Readonly<Record<string, string>> = {
  "3b7e1a45ca6f231c62605aabcf79e6a41b08c7da": "v1.0.263",
};

// First release with Bun 1.4.4 and the 2.1.311 CLI (#12102). A coherent revert
// of every carrier to an older pair would otherwise pass the one-pair check.
const MIN_ACTION_TAG: readonly [number, number, number] = [1, 0, 263];

// Case-insensitive (GitHub resolves owner/repo case-insensitively) and allows a
// subpath (`anthropics/claude-code-action/base-action@…`). The 40-hex SHA is
// required, so a tag-only (`@v1`) or short-SHA pin is not a PIN match and is
// caught by the per-file use census instead of being skipped.
const USE_SRC = String.raw`anthropics\/claude-code-action(?:\/[\w.-]+)*@`;
const USE_RE = new RegExp(USE_SRC, "gi");
const PIN_RE = new RegExp(USE_SRC + String.raw`([0-9a-f]{40})[ \t]+#[ \t]*(v\d+\.\d+\.\d+)\b`, "gi");

const SCAN_ROOTS = [".github", "plugins/soleur/skills"];
const SCAN_EXT = /\.(ya?ml|template)$/;
const SKIP_SEGMENT = /(^|\/)(node_modules|test|tests|fixtures)(\/|$)/;

function discover(): string[] {
  const found: string[] = [];
  for (const root of SCAN_ROOTS) {
    for (const rel of readdirSync(path.join(REPO_ROOT, root), { recursive: true }) as string[]) {
      const file = `${root}/${String(rel).split(path.sep).join("/")}`;
      if (!SCAN_EXT.test(file) || SKIP_SEGMENT.test(file)) continue;
      if (new RegExp(USE_SRC, "i").test(read(file))) found.push(file);
    }
  }
  return found.sort();
}

interface Site {
  file: string;
  sha: string;
  tag: string;
}

function collect(files: readonly string[]): { sites: Site[]; uses: Record<string, number> } {
  const sites: Site[] = [];
  const uses: Record<string, number> = {};
  for (const file of files) {
    const text = read(file);
    uses[file] = (text.match(USE_RE) ?? []).length;
    for (const m of text.matchAll(PIN_RE)) sites.push({ file, sha: m[1].toLowerCase(), tag: m[2] });
  }
  return { sites, uses };
}

function exactlyOne(text: string, re: RegExp, what: string): string {
  const all = [...text.matchAll(re)];
  expect(all.length, `expected exactly one ${what}`).toBe(1);
  return all[0][1];
}

const tagTuple = (tag: string): number[] => tag.slice(1).split(".").map(Number);
const atLeast = (have: number[], floor: readonly number[]): boolean => {
  for (let i = 0; i < floor.length; i++) {
    if (have[i] !== floor[i]) return have[i] > floor[i];
  }
  return true;
};

// CLI <-> SDK pairing (#12514, ruling F2): the two pins move together because
// @anthropic-ai/claude-agent-sdk 0.3.N ships the 2.1.N CLI as its own binary
// (its package.json `claudeCodeVersion`; measured 0.3.321 -> 2.1.321, and the
// two linux-x64 binaries are byte-identical), and hosted consults run that
// bundled binary. The patch numbers have NOT always matched in this
// package.json's history (2.1.219 and 2.1.280 sat on SDK 0.3.197, 2.1.293 on
// 0.3.284), but every such state was a CLI-only bump, which F2 forbids. So the
// rule is patch equality on the declared release lines; a new major/minor line
// on either side is a deliberate edit to these two constants after re-measuring
// the SDK's claudeCodeVersion.
const CLI_LINE = "2.1";
const SDK_LINE = "0.3";

function pairViolation(cli: string, sdk: string): string | null {
  const c = /^(\d+\.\d+)\.(\d+)$/.exec(cli);
  const s = /^(\d+\.\d+)\.(\d+)$/.exec(sdk);
  if (!c || !s) return `not exact semver pins: claude-code ${cli}, claude-agent-sdk ${sdk}`;
  if (c[1] !== CLI_LINE || s[1] !== SDK_LINE) {
    return `release line moved (claude-code ${c[1]}.x, claude-agent-sdk ${s[1]}.x; declared ${CLI_LINE}.x <-> ${SDK_LINE}.x): re-measure the SDK's claudeCodeVersion, then update CLI_LINE/SDK_LINE`;
  }
  if (c[2] !== s[2]) {
    return `claude-code ${cli} is not paired with claude-agent-sdk ${sdk} (expected ${SDK_LINE}.${c[2]}): bump both together (ruling F2)`;
  }
  return null;
}

describe("claude pin lockstep (#12102)", () => {
  it("positive control: the pin regex matches full pins in any case or subpath and refuses tag-only and short-SHA forms", () => {
    const sha = "3b7e1a45ca6f231c62605aabcf79e6a41b08c7da";
    const m = (s: string): number => [...s.matchAll(PIN_RE)].length;
    expect(m(`uses: anthropics/claude-code-action@${sha} # v1.0.263`)).toBe(1);
    expect(m(`uses: Anthropics/Claude-Code-Action@${sha} # v1.0.263`)).toBe(1);
    expect(m(`uses: anthropics/claude-code-action/base-action@${sha} # v1.0.263`)).toBe(1);
    expect(m(`uses: anthropics/claude-code-action@v1 # v1.0.263`)).toBe(0);
    expect(m(`uses: anthropics/claude-code-action@3b7e1a4 # v1.0.263`)).toBe(0);
    expect("uses: anthropics/claude-code-action@v1".match(USE_RE)).toHaveLength(1);
  });

  it("positive control: the tag floor orders versions numerically", () => {
    expect(atLeast([1, 0, 263], MIN_ACTION_TAG)).toBe(true);
    expect(atLeast([1, 0, 268], MIN_ACTION_TAG)).toBe(true);
    expect(atLeast([1, 1, 0], MIN_ACTION_TAG)).toBe(true);
    expect(atLeast([1, 0, 236], MIN_ACTION_TAG)).toBe(false);
    expect(atLeast([1, 0, 101], MIN_ACTION_TAG)).toBe(false);
  });

  it("the discovered carriers are exactly the expected set", () => {
    const found = discover();
    expect(
      found,
      "a file naming claude-code-action appeared or disappeared: add it to EXPECTED_CARRIERS (or remove it) deliberately",
    ).toEqual([...EXPECTED_CARRIERS].sort());
  });

  it("every claude-code-action use in every carrier is a full-SHA pin with a version comment", () => {
    const { sites, uses } = collect(EXPECTED_CARRIERS);
    for (const file of EXPECTED_CARRIERS) {
      const matched = sites.filter((s) => s.file === file).length;
      expect(uses[file], `${file}: no claude-code-action use found`).toBeGreaterThan(0);
      expect(matched, `${file}: ${uses[file]} use(s) but ${matched} full-SHA pin(s)`).toBe(uses[file]);
    }
    expect(sites.map((s) => s.file), "the template is in the census").toContain(TEMPLATE);
    expect(sites.map((s) => s.file), "the operator-digest asset is in the census").toContain(DIGEST_ASSET);
  });

  it("all claude-code-action pins are one (sha, tag) pair", () => {
    const { sites } = collect(EXPECTED_CARRIERS);
    const pairs = new Map<string, string[]>();
    for (const s of sites) pairs.set(`${s.sha} # ${s.tag}`, [...(pairs.get(`${s.sha} # ${s.tag}`) ?? []), s.file]);
    const detail = [...pairs.entries()].map(([k, files]) => `${k}: ${files.join(", ")}`).join("\n");
    expect(pairs.size, `pins diverge:\n${detail}`).toBe(1);
  });

  it("every pinned SHA is a known, verified tag object and its comment names that tag", () => {
    const { sites } = collect(EXPECTED_CARRIERS);
    expect(sites.length).toBeGreaterThan(0);
    for (const s of sites) {
      expect(KNOWN_ACTION_PINS[s.sha], `${s.file} pins ${s.sha}, which is not in KNOWN_ACTION_PINS (verify the tag object, then add it)`).toBeDefined();
      expect(s.tag, `${s.file}: the comment names ${s.tag} but ${s.sha} is ${KNOWN_ACTION_PINS[s.sha]}`).toBe(KNOWN_ACTION_PINS[s.sha]);
    }
  });

  it(`the pinned action tag is at or above v${MIN_ACTION_TAG.join(".")} (the Bun 1.4.4 release)`, () => {
    const { sites } = collect(EXPECTED_CARRIERS);
    expect(sites.length).toBeGreaterThan(0);
    for (const s of sites) {
      expect(atLeast(tagTuple(s.tag), MIN_ACTION_TAG), `${s.file} pins ${s.tag}, below the Bun 1.4.4 release`).toBe(true);
    }
  });

  it("CLI_VERSION, the install line that reads it, the Dockerfile and package.json name the same claude-code version", () => {
    const pkg = JSON.parse(read("apps/web-platform/package.json"));
    const pinned: string = pkg.dependencies["@anthropic-ai/claude-code"];
    expect(pinned).toMatch(/^\d+\.\d+\.\d+$/);
    const drift = read(DRIFT_WORKFLOW);
    const cli = exactlyOne(drift, /^\s*CLI_VERSION:\s*"(\d+\.\d+\.\d+)"/gm, "CLI_VERSION assignment");
    exactlyOne(
      drift,
      /^[^#\n]*(npm install -g "@anthropic-ai\/claude-code@\$\{CLI_VERSION\}")/gm,
      "install line that reads CLI_VERSION",
    );
    const docker = exactlyOne(
      read(DOCKERFILE),
      /^[^#\n]*@anthropic-ai\/claude-code@(\d+\.\d+\.\d+)(?=[\s\\]|$)/gm,
      "Dockerfile claude-code install",
    );
    expect({ CLI_VERSION: cli, Dockerfile: docker }).toEqual({ CLI_VERSION: pinned, Dockerfile: pinned });
  });

  it("positive control: the CLI/SDK pairing rule refuses an unpaired, re-lined or ranged pin", () => {
    expect(pairViolation("2.1.321", "0.3.321")).toBeNull();
    // a CLI-only bump (the state F2 forbids)
    expect(pairViolation("2.1.321", "0.3.311")).toMatch(/not paired/);
    // the real pre-F2 drift in this package.json's history
    expect(pairViolation("2.1.293", "0.3.284")).toMatch(/not paired/);
    // an SDK-only bump
    expect(pairViolation("2.1.311", "0.3.321")).toMatch(/not paired/);
    // a new release line on either side needs a deliberate re-declaration
    expect(pairViolation("2.2.321", "0.3.321")).toMatch(/release line moved/);
    expect(pairViolation("2.1.321", "0.4.321")).toMatch(/release line moved/);
    // a range is not a pin
    expect(pairViolation("2.1.321", "^0.3.321")).toMatch(/not exact semver/);
  });

  it("the claude-code pin and the claude-agent-sdk pin are one paired release (2.1.N <-> 0.3.N)", () => {
    const pkg = JSON.parse(read("apps/web-platform/package.json"));
    const cli: string = pkg.dependencies["@anthropic-ai/claude-code"];
    const sdk: string = pkg.dependencies["@anthropic-ai/claude-agent-sdk"];
    expect(pairViolation(cli, sdk), "apps/web-platform/package.json CLI/SDK pins").toBeNull();
  });

  it("the pen-cli SDK override names this app's SDK pin", () => {
    const pkg = JSON.parse(read("apps/web-platform/package.json"));
    const sdk: string = pkg.dependencies["@anthropic-ai/claude-agent-sdk"];
    expect(sdk).toMatch(/^\d+\.\d+\.\d+$/);
    const pen = JSON.parse(read(`${PEN_CLI_DIR}/package.json`));
    expect(pen.overrides?.["@anthropic-ai/claude-agent-sdk"], "pen-cli overrides entry").toBe(sdk);
  });

  it("every claude-agent-sdk entry in the pen-cli lock resolves this app's SDK pin", () => {
    const pkg = JSON.parse(read("apps/web-platform/package.json"));
    const sdk: string = pkg.dependencies["@anthropic-ai/claude-agent-sdk"];
    const lock = JSON.parse(read(`${PEN_CLI_DIR}/package-lock.json`));
    const keys = Object.keys(lock.packages).filter((k) =>
      /(^|\/)@anthropic-ai\/claude-agent-sdk(-[a-z0-9-]+)?$/.test(k),
    );
    expect(keys, "the top-level SDK entry").toContain("node_modules/@anthropic-ai/claude-agent-sdk");
    const wrong = keys.filter((k) => lock.packages[k].version !== sdk).map((k) => `${k}@${lock.packages[k].version}`);
    expect(wrong, `lock entries not at ${sdk}`).toEqual([]);
  });
});
