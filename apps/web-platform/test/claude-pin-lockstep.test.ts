import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

// Lockstep guard (#12102): the claude runtime is pinned in several places that
// have to move together when a Bun/CLI advisory forces a bump, and nothing but
// a dated follow-through probe looked at them.
//
//   - every `anthropics/claude-code-action@<sha> # vX.Y.Z` pin in
//     .github/workflows and in the customer-facing constraint-scaffold template
//     is ONE (sha, tag) pair — the action bundles its own CLI and Bun, so a
//     straggler keeps a vulnerable runtime in a job that holds secrets;
//   - `CLI_VERSION` in scheduled-marketplace-drift.yml, the Dockerfile
//     `npm install -g @anthropic-ai/claude-code@…` and this app's package.json
//     name the same claude-code version (adhoc-npm-install-pin-table only
//     checks the first is an exact semver, deliberately not which one);
//   - the pen-cli engine override for `@anthropic-ai/claude-agent-sdk` equals
//     this app's SDK pin, and its committed lock resolves that version.
//
// ALSO SCANNED: plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml.
// It is provisioned into another repository, so a copy already installed there
// keeps its old pin until re-provisioned; this guard covers the asset in this
// repo. On v1.0.101 that asset's unquoted `Bash(...)` allowlist was silently
// widened to bare `Bash` by the action's argument parsing (CTO F7), which is
// why it cannot be left on an older release.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const read = (rel: string): string => readFileSync(path.join(REPO_ROOT, rel), "utf8");

const TEMPLATE =
  "plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template";
const DIGEST_ASSET =
  "plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml";
const DRIFT_WORKFLOW = ".github/workflows/scheduled-marketplace-drift.yml";
const DOCKERFILE = "apps/web-platform/Dockerfile";
const PEN_CLI_DIR = "plugins/soleur/skills/pencil-setup/scripts/pen-cli";

// The 40-hex SHA is required, so a tag-only (`@v1`) or short-SHA pin is not a
// match — and is caught by the per-file `@` census below rather than skipped.
const PIN_RE = /anthropics\/claude-code-action@([0-9a-f]{40})[ \t]+#[ \t]*(v\d+\.\d+\.\d+)\b/g;
const USE_RE = /anthropics\/claude-code-action@/g;

function workflowFiles(): string[] {
  return readdirSync(path.join(REPO_ROOT, ".github/workflows"))
    .filter((f) => f.endsWith(".yml") || f.endsWith(".yaml"))
    .sort()
    .map((f) => `.github/workflows/${f}`);
}

interface Site {
  file: string;
  sha: string;
  tag: string;
}

function collect(): { sites: Site[]; uses: Record<string, number> } {
  const sites: Site[] = [];
  const uses: Record<string, number> = {};
  for (const file of [...workflowFiles(), TEMPLATE, DIGEST_ASSET]) {
    const text = read(file);
    const n = (text.match(USE_RE) ?? []).length;
    if (n > 0) uses[file] = n;
    for (const m of text.matchAll(PIN_RE)) sites.push({ file, sha: m[1], tag: m[2] });
  }
  return { sites, uses };
}

function exactlyOne(text: string, re: RegExp, what: string): string {
  const all = [...text.matchAll(re)];
  expect(all.length, `expected exactly one ${what}`).toBe(1);
  return all[0][1];
}

describe("claude pin lockstep (#12102)", () => {
  it("positive control: the pin regex matches a full pin and refuses tag-only and short-SHA forms", () => {
    const sha = "3b7e1a45ca6f231c62605aabcf79e6a41b08c7da";
    expect([...`uses: anthropics/claude-code-action@${sha} # v1.0.263`.matchAll(PIN_RE)]).toHaveLength(1);
    expect([...`uses: anthropics/claude-code-action@v1 # v1.0.263`.matchAll(PIN_RE)]).toHaveLength(0);
    expect([...`uses: anthropics/claude-code-action@3b7e1a4 # v1.0.263`.matchAll(PIN_RE)]).toHaveLength(0);
  });

  it("every claude-code-action use is a full-SHA pin with a version comment", () => {
    const { sites, uses } = collect();
    // Non-vacuity: the census must see the sites it exists to compare.
    expect(Object.keys(uses).length, "files carrying a claude-code-action use").toBeGreaterThanOrEqual(6);
    expect(Object.keys(uses), "the operator-digest asset must be in the census").toContain(DIGEST_ASSET);
    for (const [file, n] of Object.entries(uses)) {
      const matched = sites.filter((s) => s.file === file).length;
      expect(matched, `${file}: ${n} use(s) but ${matched} full-SHA pin(s)`).toBe(n);
    }
  });

  it("all claude-code-action pins are one (sha, tag) pair", () => {
    const { sites } = collect();
    const pairs = new Map<string, string[]>();
    for (const s of sites) pairs.set(`${s.sha} # ${s.tag}`, [...(pairs.get(`${s.sha} # ${s.tag}`) ?? []), s.file]);
    const detail = [...pairs.entries()].map(([k, files]) => `${k}: ${files.join(", ")}`).join("\n");
    expect(pairs.size, `pins diverge:\n${detail}`).toBe(1);
  });

  it("CLI_VERSION, the Dockerfile and package.json name the same claude-code version", () => {
    const pkg = JSON.parse(read("apps/web-platform/package.json"));
    const pinned: string = pkg.dependencies["@anthropic-ai/claude-code"];
    expect(pinned).toMatch(/^\d+\.\d+\.\d+$/);
    const cli = exactlyOne(read(DRIFT_WORKFLOW), /^\s*CLI_VERSION:\s*"(\d+\.\d+\.\d+)"/gm, "CLI_VERSION assignment");
    const docker = exactlyOne(
      read(DOCKERFILE),
      /^RUN npm install -g @anthropic-ai\/claude-code@(\d+\.\d+\.\d+)\b/gm,
      "Dockerfile claude-code install",
    );
    expect({ CLI_VERSION: cli, Dockerfile: docker }).toEqual({ CLI_VERSION: pinned, Dockerfile: pinned });
  });

  it("the pen-cli SDK override equals this app's SDK pin and its lock resolves it", () => {
    const pkg = JSON.parse(read("apps/web-platform/package.json"));
    const sdk: string = pkg.dependencies["@anthropic-ai/claude-agent-sdk"];
    expect(sdk).toMatch(/^\d+\.\d+\.\d+$/);
    const pen = JSON.parse(read(`${PEN_CLI_DIR}/package.json`));
    expect(pen.overrides?.["@anthropic-ai/claude-agent-sdk"], "pen-cli overrides entry").toBe(sdk);
    const lock = JSON.parse(read(`${PEN_CLI_DIR}/package-lock.json`));
    const resolved = lock.packages["node_modules/@anthropic-ai/claude-agent-sdk"]?.version;
    expect(resolved, "pen-cli lock SDK version").toBe(sdk);
  });
});
