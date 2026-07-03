// Generic pre-merge guard: Dockerfile `COPY --from=builder` / builder-`RUN .sh` of a
// `.dockerignore`-stripped build-context path.
//
// apps/web-platform/Dockerfile is a 3-stage build. The `builder` stage runs `COPY . .` (filtered
// by apps/web-platform/.dockerignore). The `runner` stage then bakes specific build artifacts into
// the final image via `COPY --from=builder /app/<path> ...`, and the builder stage runs shell
// scripts via `RUN bash scripts/<x>.sh`. When a referenced `<path>` is a CONTEXT-SOURCED file
// (committed in the repo, copied into the builder by `COPY . .`) that lives under a `.dockerignore`
// exclusion (e.g. `infra/`, `scripts/`) with NO matching `!`-re-include, the builder never has the
// file → the runner COPY fails `"/app/infra/<file>": not found` (or the builder RUN exits 127) →
// the `release` job goes red → `deploy` is skipped → prod stays frozen on the prior image. Because
// the break lands on `main`, EVERY web-platform release fails until it is hotfixed.
//
// This has bitten the release repeatedly: the sandbox-canary re-includes (ADR-079) and the 25 baked
// host-bootstrap scripts (ADR-080), each fixed reactively AFTER the release broke. CI does NOT run
// the Docker build, so a source-level `bun test` assertion is the only pre-merge catch.
//
// The existing guard in cloud-init-user-data-size.test.ts is PARTIAL — it only asserts re-inclusion
// for the multi-line host-scripts COPY block. This suite generalizes it to EVERY builder
// `COPY --from=<stage>` src AND every builder-stage `RUN` shell-script arg, closing the class
// wholesale. It ships green against the current repo (already clean).
//
// Evaluator scope: a deliberate Set+prefix simplification, NOT a full Docker patternmatcher. Every
// in-scope `.dockerignore` exclude a real baked/consumed src hits is a literal directory prefix and
// every re-include is an exact `!<path>`. The model is fail-loud-safe: a future glob re-include it
// cannot represent surfaces as a SPURIOUS violation on the clean-repo test (safe direction) — extend
// the model then; it never silently passes a real strip. See the feat plan for the full rationale.

import { test, expect, describe } from "bun:test";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const WEB = join(REPO_ROOT, "apps", "web-platform");
const DOCKERFILE = join(WEB, "Dockerfile");
const DOCKERIGNORE = join(WEB, ".dockerignore");

// ---------------------------------------------------------------------------
// Pure functions (inline, per the cloud-init-user-data-size.test.ts convention — no lib/ module).
// ---------------------------------------------------------------------------

interface SrcRef {
  src: string; // build-context-relative path (with the `/app/` prefix stripped)
  line: number; // 1-indexed Dockerfile line of the COPY/RUN keyword
}

/**
 * Every `/app/`-prefixed `<src>` from all `COPY --from=<stage> <src...> <dst>` statements
 * (single-line and `\`-continued multi-line). The last token of a statement is the `<dst>`
 * (excluded); tolerates optional `--chown=`/`--chmod=` flags between `COPY` and `--from=`.
 */
export function parseBuilderCopySources(dockerfileText: string): SrcRef[] {
  const lines = dockerfileText.split("\n");
  const out: SrcRef[] = [];
  for (let i = 0; i < lines.length; i++) {
    // Only statements whose first keyword is COPY --from=<stage>. Join `\`-continuations.
    if (!/^\s*COPY\s+(?:--\w+=\S+\s+)*--from=\S+/.test(lines[i])) continue;
    const keywordLine = i + 1; // 1-indexed line of the COPY keyword
    let stmt = lines[i];
    while (/\\\s*$/.test(stmt) && i + 1 < lines.length) {
      stmt = stmt.replace(/\\\s*$/, " ") + lines[++i];
    }
    // Strip the leading `COPY (--flag=… )* --from=<stage>` prefix, then tokenize the rest.
    const rest = stmt.replace(/^\s*COPY\s+(?:--\w+=\S+\s+)*--from=\S+\s+/, "");
    const tokens = rest.split(/\s+/).filter(Boolean);
    tokens.pop(); // last token is the <dst>
    for (const tok of tokens) {
      if (tok.startsWith("/app/")) out.push({ src: tok.slice("/app/".length), line: keywordLine });
    }
  }
  return out;
}

/**
 * For `RUN` lines inside the `builder` stage (between `FROM … AS builder` and the next `FROM`),
 * the relative `.sh` path args matching `(?:bash|sh|source|\.)\s+(\S+\.sh)\b`. These are context
 * srcs the builder needs at build time (a `.dockerignore` strip → `exit 127`).
 */
export function parseBuilderRunScriptSources(dockerfileText: string): SrcRef[] {
  const lines = dockerfileText.split("\n");
  // Slice the builder stage: from `FROM … AS builder` to the next `FROM`.
  let start = -1;
  let end = lines.length;
  for (let i = 0; i < lines.length; i++) {
    if (start === -1) {
      if (/^\s*FROM\s+.*\bAS\s+builder\b/i.test(lines[i])) start = i + 1;
    } else if (/^\s*FROM\s+/i.test(lines[i])) {
      end = i;
      break;
    }
  }
  if (start === -1) return [];
  const out: SrcRef[] = [];
  const runScript = /(?:\bbash|\bsh|\bsource|(?:^|\s)\.)\s+(\S+\.sh)\b/g;
  for (let i = start; i < end; i++) {
    if (!/^\s*RUN\b/.test(lines[i])) continue;
    for (const m of lines[i].matchAll(runScript)) out.push({ src: m[1], line: i + 1 });
  }
  return out;
}

interface ExclusionModel {
  excludedDirPrefixes: string[]; // literal (non-`!`/non-`#`/non-glob) patterns, trailing `/` stripped
  reincludes: Set<string>; // exact `!<path>` lines (no globs)
}

/** Excluded-dir-prefix set + exact-`!`-reinclude set. Simplified evaluator — no glob engine. */
export function dockerignoreExclusionModel(dockerignoreText: string): ExclusionModel {
  const excludedDirPrefixes: string[] = [];
  const reincludes = new Set<string>();
  const hasGlob = (p: string) => /[*?[\]]/.test(p);
  for (const raw of dockerignoreText.split("\n")) {
    const pat = raw.trim();
    if (!pat || pat.startsWith("#")) continue;
    if (pat.startsWith("!")) {
      const body = pat.slice(1);
      if (!hasGlob(body)) reincludes.add(body.replace(/\/+$/, ""));
      continue;
    }
    if (hasGlob(pat)) continue; // simplified evaluator: only literal prefixes (fail-loud on globs)
    excludedDirPrefixes.push(pat.replace(/\/+$/, ""));
  }
  return { excludedDirPrefixes, reincludes };
}

interface GuardInput {
  dockerfileText: string;
  dockerignoreText: string;
  trackedContextPaths: Set<string>; // build-context-relative git-tracked file paths
}

interface Violation extends SrcRef {
  reinclude: string; // the exact `!<path>` line to add to apps/web-platform/.dockerignore
}

/**
 * The composed guard over `parseBuilderCopySources ∪ parseBuilderRunScriptSources`: skip srcs that
 * are NOT context-sourced (not in, and not an ancestor-dir of any path in, `trackedContextPaths`);
 * flag a context-sourced src iff some excluded prefix is its ancestor AND it is not re-included.
 */
export function findReincludeViolations(input: GuardInput): Violation[] {
  const { dockerfileText, dockerignoreText, trackedContextPaths } = input;
  const { excludedDirPrefixes, reincludes } = dockerignoreExclusionModel(dockerignoreText);
  const refs = [
    ...parseBuilderCopySources(dockerfileText),
    ...parseBuilderRunScriptSources(dockerfileText),
  ];

  // context-sourced = the path itself is git-tracked, OR it is an ancestor dir of a tracked path
  // (e.g. `public` → `public/index.html`). A src that is neither is build-generated → skip.
  const isContextSourced = (src: string): boolean => {
    if (trackedContextPaths.has(src)) return true;
    const prefix = src + "/";
    for (const p of trackedContextPaths) if (p.startsWith(prefix)) return true;
    return false;
  };
  const isStripped = (src: string): boolean =>
    excludedDirPrefixes.some((p) => src === p || src.startsWith(p + "/")) && !reincludes.has(src);

  const seen = new Set<string>();
  const violations: Violation[] = [];
  for (const { src, line } of refs) {
    if (seen.has(src)) continue;
    seen.add(src);
    if (!isContextSourced(src)) continue; // build-generated (e.g. .next, dist/server) — safe to skip
    if (isStripped(src)) violations.push({ src, line, reinclude: `!${src}` });
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("Dockerfile COPY --from=builder / RUN .sh <-> .dockerignore re-include parity", () => {
  // --- Gap-demonstration fixtures (synthesized; cq-test-fixtures-synthesized-only) ---

  test("(a) COPY form: an infra/-baked COPY --from=builder with no re-include is flagged", () => {
    const dockerfileText = [
      "FROM node:22-slim AS builder",
      "COPY . .",
      "FROM node:22-slim AS runner",
      "COPY --from=builder /app/infra/new-baked.sh ./infra/new-baked.sh",
    ].join("\n");
    const dockerignoreText = ["infra/", "!infra/other.sh"].join("\n");
    const violations = findReincludeViolations({
      dockerfileText,
      dockerignoreText,
      trackedContextPaths: new Set(["infra/new-baked.sh"]),
    });
    expect(violations.map((v) => v.src)).toContain("infra/new-baked.sh");
  });

  test("(b) RUN form: a builder RUN bash scripts/<x>.sh with no re-include is flagged", () => {
    const dockerfileText = [
      "FROM node:22-slim AS builder",
      "COPY . .",
      "RUN bash scripts/new-run.sh",
      "FROM node:22-slim AS runner",
    ].join("\n");
    const dockerignoreText = ["scripts/"].join("\n");
    const violations = findReincludeViolations({
      dockerfileText,
      dockerignoreText,
      trackedContextPaths: new Set(["scripts/new-run.sh"]),
    });
    expect(violations.map((v) => v.src)).toContain("scripts/new-run.sh");
  });

  // --- Real-repo regression: the current tree must be clean (0 violations) ---

  const realDockerfile = readFileSync(DOCKERFILE, "utf8");
  const realDockerignore = readFileSync(DOCKERIGNORE, "utf8");
  const realTracked = new Set(
    execFileSync("git", ["ls-files", "apps/web-platform"], { cwd: REPO_ROOT, encoding: "utf8" })
      .split("\n")
      .filter(Boolean)
      .map((p) => p.replace(/^apps\/web-platform\//, "")),
  );

  test("real Dockerfile + .dockerignore + live tracked set → zero violations", () => {
    const violations = findReincludeViolations({
      dockerfileText: realDockerfile,
      dockerignoreText: realDockerignore,
      trackedContextPaths: realTracked,
    });
    // A non-empty list here means a baked/consumed context path is missing its `!`-re-include —
    // the release WILL break. The message names each src + the exact `!<path>` line to add.
    expect(violations).toEqual([]);
  });

  // --- Non-vacuity: the parsers actually see the real srcs ---

  test("parseBuilderCopySources(real) returns ≥1 /app/infra src and /app/public (non-vacuity)", () => {
    const srcs = parseBuilderCopySources(realDockerfile).map((s) => s.src);
    expect(srcs).toContain("public");
    expect(srcs.some((s) => s.startsWith("infra/"))).toBe(true);
    // The multi-line host-scripts COPY (Dockerfile:177) must be parsed, not just single-line ones.
    expect(srcs).toContain("infra/soleur-host-bootstrap.sh");
    // The `<dst>` token must be excluded, never returned as a src.
    expect(srcs.some((s) => s.startsWith("opt/") || s.includes("host-scripts/"))).toBe(false);
  });

  test("parseBuilderRunScriptSources(real) returns the builder-stage assert script", () => {
    const srcs = parseBuilderRunScriptSources(realDockerfile).map((s) => s.src);
    expect(srcs).toContain("scripts/assert-dev-signin-eliminated.sh");
  });

  // --- The one genuine false-positive case: .next is build-generated (untracked), under `.next/` ---

  test(".next (untracked, under the .next/ exclusion) is skipped, never flagged", () => {
    // Sanity: `.next` really is baked (Dockerfile:143) and really is excluded (.dockerignore:78).
    expect(parseBuilderCopySources(realDockerfile).map((s) => s.src)).toContain(".next");
    const model = dockerignoreExclusionModel(realDockerignore);
    expect(model.excludedDirPrefixes).toContain(".next");
    // …yet the guard never flags it, because it is not git-tracked (build-generated).
    const violations = findReincludeViolations({
      dockerfileText: realDockerfile,
      dockerignoreText: realDockerignore,
      trackedContextPaths: realTracked,
    });
    expect(violations.map((v) => v.src)).not.toContain(".next");
  });

  // --- Minimal evaluator unit tests ---

  test("evaluator: excluded dir prefix with no re-include → violation", () => {
    const violations = findReincludeViolations({
      dockerfileText: "FROM x AS runner\nCOPY --from=builder /app/infra/drop.txt ./drop.txt",
      dockerignoreText: "infra/",
      trackedContextPaths: new Set(["infra/drop.txt"]),
    });
    expect(violations.map((v) => v.src)).toEqual(["infra/drop.txt"]);
  });

  test("evaluator: exact !<path> re-include → no violation", () => {
    const violations = findReincludeViolations({
      dockerfileText: "FROM x AS runner\nCOPY --from=builder /app/infra/keep.txt ./keep.txt",
      dockerignoreText: "infra/\n!infra/keep.txt",
      trackedContextPaths: new Set(["infra/keep.txt"]),
    });
    expect(violations).toEqual([]);
  });

  test("evaluator: un-excluded top-level src (public) → no violation", () => {
    const violations = findReincludeViolations({
      dockerfileText: "FROM x AS runner\nCOPY --from=builder /app/public ./public",
      dockerignoreText: "infra/\nscripts/",
      trackedContextPaths: new Set(["public/index.html"]),
    });
    expect(violations).toEqual([]);
  });

  // --- Parser edge cases ---

  test("parser: --chown flag between COPY and --from is tolerated; dest excluded", () => {
    const srcs = parseBuilderCopySources(
      "FROM x AS runner\nCOPY --from=builder --chown=1001:1001 /app/foo ./foo",
    ).map((s) => s.src);
    expect(srcs).toEqual(["foo"]);
  });

  test("parseBuilderRunScriptSources: RUN npm run build / esbuild are NOT matched (no .sh)", () => {
    const df = [
      "FROM x AS builder",
      "RUN npm run build",
      "RUN ./node_modules/.bin/esbuild next.config.ts",
      "FROM y AS runner",
    ].join("\n");
    expect(parseBuilderRunScriptSources(df)).toEqual([]);
  });

  test("parseBuilderRunScriptSources ignores RUN .sh OUTSIDE the builder stage", () => {
    const df = [
      "FROM x AS builder",
      "RUN echo hi",
      "FROM y AS runner",
      "RUN bash scripts/postrun.sh",
    ].join("\n");
    expect(parseBuilderRunScriptSources(df)).toEqual([]);
  });
});
