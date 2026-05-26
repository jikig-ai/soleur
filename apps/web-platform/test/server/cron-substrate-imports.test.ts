import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const FUNCTIONS_DIR = join(
  __dirname,
  "../../server/inngest/functions",
);

const SHARED_IMPORT_RE =
  /from\s+["']\.\/_cron-shared["']/;
const EVAL_SUBSTRATE_IMPORT_RE =
  /from\s+["']\.\/_cron-claude-eval-substrate["']/;

const FORBIDDEN_LOCAL_DEFS = [
  /\bfunction\s+redactToken\b/,
  /\bfunction\s+buildAuthenticatedCloneUrl\b/,
  /\bfunction\s+mintInstallationToken\b/,
  /\bfunction\s+postSentryHeartbeat\b/,
  /\bconst\s+SENTRY_DOMAIN_RE\s*=/,
  /\bconst\s+SENTRY_PROJECT_RE\s*=/,
  /\bconst\s+SENTRY_PUBLIC_KEY_RE\s*=/,
  /\bconst\s+REPO_OWNER\s*=\s*"jikig-ai"/,
  /\bconst\s+REPO_NAME\s*=\s*"soleur"/,
];

const FORBIDDEN_EVAL_LOCAL_DEFS = [
  /\bfunction\s+resolveClaudeBin\b/,
  /\bfunction\s+spawnSimple\b/,
  /\bfunction\s+spawnClaudeEval\b/,
];

function getCronFiles(): string[] {
  return readdirSync(FUNCTIONS_DIR)
    .filter((f) => /^cron-.*\.ts$/.test(f) && !f.startsWith("_"))
    .sort();
}

function stripComments(src: string): string {
  return src
    .replace(/\/\/.*$/gm, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
}

describe("cron-substrate-imports guard", () => {
  const cronFiles = getCronFiles();

  it("discovers at least 14 cron-*.ts files", () => {
    expect(cronFiles.length).toBeGreaterThanOrEqual(14);
  });

  for (const file of cronFiles) {
    describe(file, () => {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      const stripped = stripComments(src);

      it("imports from _cron-shared or _cron-claude-eval-substrate", () => {
        const hasShared = SHARED_IMPORT_RE.test(src);
        const hasEval = EVAL_SUBSTRATE_IMPORT_RE.test(src);
        expect(
          hasShared || hasEval,
          `${file} must import from at least one substrate module`,
        ).toBe(true);
      });

      it("does not locally redefine extracted _cron-shared symbols", () => {
        for (const re of FORBIDDEN_LOCAL_DEFS) {
          expect(
            re.test(stripped),
            `${file} locally redefines a symbol that should be imported from _cron-shared: ${re.source}`,
          ).toBe(false);
        }
      });

      if (EVAL_SUBSTRATE_IMPORT_RE.test(src)) {
        it("does not locally redefine extracted _cron-claude-eval-substrate symbols", () => {
          for (const re of FORBIDDEN_EVAL_LOCAL_DEFS) {
            expect(
              re.test(stripped),
              `${file} locally redefines a symbol that should be imported from _cron-claude-eval-substrate: ${re.source}`,
            ).toBe(false);
          }
        });
      }
    });
  }
});

describe("substrate module guards", () => {
  it("shared modules do not export buildSpawnEnv", () => {
    for (const mod of ["_cron-shared.ts", "_cron-claude-eval-substrate.ts"]) {
      const src = readFileSync(join(FUNCTIONS_DIR, mod), "utf-8");
      expect(
        /\bexport\b.*\bbuildSpawnEnv\b/.test(src),
        `${mod} must NOT export buildSpawnEnv (per-handler security boundary)`,
      ).toBe(false);
    }
  });
});

describe("fixture proofs", () => {
  it("positive: a compliant handler source passes", () => {
    const src = `
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";
const SENTRY_MONITOR_SLUG = "test";
export async function handler() {}
`;
    expect(SHARED_IMPORT_RE.test(src)).toBe(true);
    const stripped = stripComments(src);
    for (const re of FORBIDDEN_LOCAL_DEFS) {
      expect(re.test(stripped)).toBe(false);
    }
  });

  it("negative: a handler with local redactToken is caught", () => {
    const src = `
import { type HandlerArgs } from "./_cron-shared";
function redactToken(s: string, token: string): string { return s; }
`;
    const stripped = stripComments(src);
    expect(FORBIDDEN_LOCAL_DEFS[0].test(stripped)).toBe(true);
  });

  it("negative: a handler with local SENTRY_DOMAIN_RE is caught", () => {
    const src = `
import { type HandlerArgs } from "./_cron-shared";
const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\\.sentry\\.io$/i;
`;
    const stripped = stripComments(src);
    expect(FORBIDDEN_LOCAL_DEFS[4].test(stripped)).toBe(true);
  });

  it("negative: a handler with local REPO_OWNER is caught", () => {
    const src = `
import { type HandlerArgs } from "./_cron-shared";
const REPO_OWNER = "jikig-ai";
`;
    const stripped = stripComments(src);
    expect(FORBIDDEN_LOCAL_DEFS[7].test(stripped)).toBe(true);
  });

  it("negative: a handler with local resolveClaudeBin importing from eval substrate is caught", () => {
    const src = `
import { type SpawnResult } from "./_cron-claude-eval-substrate";
function resolveClaudeBin(): string { return ""; }
`;
    const stripped = stripComments(src);
    expect(FORBIDDEN_EVAL_LOCAL_DEFS[0].test(stripped)).toBe(true);
  });

  it("commented-out definitions are not flagged", () => {
    const src = `
import { redactToken } from "./_cron-shared";
// function redactToken(s: string, token: string): string { return s; }
`;
    const stripped = stripComments(src);
    expect(FORBIDDEN_LOCAL_DEFS[0].test(stripped)).toBe(false);
  });
});
