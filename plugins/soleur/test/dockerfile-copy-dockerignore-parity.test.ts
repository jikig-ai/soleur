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
// for the multi-line host-scripts COPY block. This suite generalizes it to every builder
// `COPY --from=<stage>` src AND every builder-stage `RUN` shell-script invocation
// (`bash|sh|source|. <path>.sh` and direct-exec `./<path>.sh`, single-line and `\`-continued). It
// ships green against the current repo (already clean).
//
// Evaluator scope: a deliberate Set+prefix simplification, NOT a full Docker patternmatcher — but it
// is designed to fail in the SAFE (loud) direction, never the silent one:
//   - Literal directory-prefix EXCLUDES (`infra/`, `scripts/`) + exact `!<path>` RE-INCLUDES are
//     modeled precisely (these cover every real baked/consumed src today).
//   - GLOB EXCLUDES (`*.md`, `assets/*`, `_plugin-vendored/**`) are matched by an over-approximating
//     translation (`**`→`.*`, `*`→`[^/]*`, `?`→`[^/]`): a baked src they shadow is FLAGGED (loud),
//     never silently skipped — closing the fail-open a bare "skip all globs" would leave.
//   - GLOB RE-INCLUDES the model cannot represent surface as a SPURIOUS violation on the clean-repo
//     test (safe direction) — extend the model then.
// The one residual model boundary is pattern ORDER (Docker is last-match-wins; this model is not):
// a re-include placed BEFORE its dir exclude is treated as effective. No real `.dockerignore` authors
// that order; documented as a known limit rather than modeled. See the feat plan for the rationale.

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
 * (excluded); tolerates optional flags between `COPY` and `--from=`, both valued
 * (`--chown=`/`--chmod=`) and valueless (`--link`/`--parents`).
 */
export function parseBuilderCopySources(dockerfileText: string): SrcRef[] {
  const lines = dockerfileText.split("\n");
  // `(?:--\w+(?:=\S+)?\s+)*` tolerates BOTH `--flag=value` and bare `--flag` (BuildKit `--link`).
  const flags = "(?:--\\w+(?:=\\S+)?\\s+)*";
  const copyHead = new RegExp(`^\\s*COPY\\s+${flags}--from=\\S+`);
  const copyPrefix = new RegExp(`^\\s*COPY\\s+${flags}--from=\\S+\\s+`);
  const out: SrcRef[] = [];
  for (let i = 0; i < lines.length; i++) {
    // Only statements whose first keyword is COPY --from=<stage>. Join `\`-continuations.
    if (!copyHead.test(lines[i])) continue;
    const keywordLine = i + 1; // 1-indexed line of the COPY keyword
    let stmt = lines[i];
    while (/\\\s*$/.test(stmt) && i + 1 < lines.length) {
      stmt = stmt.replace(/\\\s*$/, " ") + lines[++i];
    }
    // Strip the leading `COPY (--flag… )* --from=<stage>` prefix, then tokenize the rest.
    const rest = stmt.replace(copyPrefix, "");
    const tokens = rest.split(/\s+/).filter(Boolean);
    tokens.pop(); // last token is the <dst>
    for (const tok of tokens) {
      if (tok.startsWith("/app/")) out.push({ src: tok.slice("/app/".length), line: keywordLine });
    }
  }
  return out;
}

/**
 * For `RUN` statements inside the `builder` stage (between `FROM … AS builder` and the next `FROM`),
 * the relative `.sh` script args the builder needs at build time (a `.dockerignore` strip → the RUN
 * `exit 127`s). Covers both interpreter-prefixed (`bash|sh|source|. <path>.sh`) and direct-exec
 * (`./<path>.sh`) invocations, single-line and `\`-continued multi-line, and normalizes a leading
 * `./` so the src matches the git-tracked (unprefixed) form.
 *
 * Scope note: the RUN scan is builder-stage-only (the release-break class is a builder consuming a
 * stripped context file). The COPY scan above is stage-agnostic (`--from=<stage>`) by design — a
 * runner `COPY --from=X` can extract from any earlier stage. Renaming the `builder` stage would
 * drop RUN coverage; keep the `AS builder` name or update this slice.
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
  // Two passes, both capturing the `.sh` path (group 1) WITHOUT any leading `./`:
  //  (1) interpreter-prefixed: `bash|sh|source|.` + ` [./]<path>.sh`
  //  (2) direct-exec: a `./<path>.sh` token at a command position (start / whitespace / `&&`)
  // The `.sh` suffix keeps this narrow — `RUN npm run build`, `RUN ./node_modules/.bin/esbuild
  // next.config.ts` (ends `.ts`/`.mjs`) do not match. Widen only with a fixture (see Sharp Edges).
  const interpreterRun = /(?:\bbash|\bsh|\bsource|(?:^|\s)\.)\s+(?:\.\/)?(\S+\.sh)\b/g;
  const directExecRun = /(?:^|\s|&&\s*)\.\/(\S+\.sh)\b/g;
  for (let i = start; i < end; i++) {
    if (!/^\s*RUN\b/.test(lines[i])) continue;
    const keywordLine = i + 1;
    // Join `\`-continuations into one logical statement (mirror the COPY parser).
    let stmt = lines[i];
    while (/\\\s*$/.test(stmt) && i + 1 < end) {
      stmt = stmt.replace(/\\\s*$/, " ") + lines[++i];
    }
    // A `bash ./x.sh` token matches BOTH passes; dedup per statement so each src is reported once.
    const stmtSrcs = new Set<string>();
    for (const m of stmt.matchAll(interpreterRun)) stmtSrcs.add(m[1]);
    for (const m of stmt.matchAll(directExecRun)) stmtSrcs.add(m[1]);
    for (const src of stmtSrcs) out.push({ src, line: keywordLine });
  }
  return out;
}

interface ExclusionModel {
  excludedDirPrefixes: string[]; // literal (non-`!`/non-`#`/non-glob) patterns, trailing `/` stripped
  globExcludeRes: RegExp[]; // over-approximating regexes for glob EXCLUDES (fail-loud, not skipped)
  reincludes: Set<string>; // exact `!<path>` lines (no globs)
}

/**
 * Over-approximating glob→regex for EXCLUDE patterns. Deliberately errs toward matching MORE
 * (the safe/loud direction: an over-match flags a src that then just needs a re-include; it never
 * silently passes a real strip). `**`→`.*`, `*`→`[^/]*`, `?`→`[^/]`; anchored with a trailing
 * `(?:/|$)` so a dir-glob also matches its children.
 */
function globExcludeToRegExp(pattern: string): RegExp {
  const esc = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  const body = esc
    .replace(/\*\*/g, " ") // placeholder so the single-`*` pass doesn't clobber `**`
    .replace(/\*/g, "[^/]*")
    .replace(/ /g, ".*")
    .replace(/\?/g, "[^/]");
  return new RegExp(`^${body}(?:/|$)`);
}

/** Excluded-dir-prefix set + glob-exclude regexes + exact-`!`-reinclude set. */
export function dockerignoreExclusionModel(dockerignoreText: string): ExclusionModel {
  const excludedDirPrefixes: string[] = [];
  const globExcludeRes: RegExp[] = [];
  const reincludes = new Set<string>();
  const hasGlob = (p: string) => /[*?[\]]/.test(p);
  for (const raw of dockerignoreText.split("\n")) {
    const pat = raw.trim();
    if (!pat || pat.startsWith("#")) continue;
    if (pat.startsWith("!")) {
      const body = pat.slice(1);
      // Glob re-includes are unmodeled: if one ever matters, a real strip surfaces as a SPURIOUS
      // clean-repo violation (safe/loud) — extend then. See header.
      if (!hasGlob(body)) reincludes.add(body.replace(/\/+$/, ""));
      continue;
    }
    if (hasGlob(pat)) {
      globExcludeRes.push(globExcludeToRegExp(pat.replace(/\/+$/, "")));
      continue;
    }
    excludedDirPrefixes.push(pat.replace(/\/+$/, ""));
  }
  return { excludedDirPrefixes, globExcludeRes, reincludes };
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
  const { excludedDirPrefixes, globExcludeRes, reincludes } =
    dockerignoreExclusionModel(dockerignoreText);
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
  // A src is stripped iff a literal dir-prefix OR an (over-approximating) glob exclude is its
  // ancestor, AND it has no exact `!`-re-include. Glob excludes are matched — NOT skipped — so a
  // baked path shadowed only by a glob (`*.md`, `assets/*`) fails LOUD, never silent.
  const isStripped = (src: string): boolean => {
    if (reincludes.has(src)) return false;
    const litHit = excludedDirPrefixes.some((p) => src === p || src.startsWith(p + "/"));
    const globHit = globExcludeRes.some((re) => re.test(src));
    return litHit || globHit;
  };

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
    // `-c core.quotePath=false` keeps non-ASCII paths literal (default octal-escapes + quotes them,
    // which would mangle the `apps/web-platform/` strip → a baked ref would fail isContextSourced).
    execFileSync("git", ["-c", "core.quotePath=false", "ls-files", "apps/web-platform"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
    })
      .split("\n")
      .filter(Boolean)
      .map((p) => p.replace(/^apps\/web-platform\//, "")),
  );

  // Render violations into an operator-actionable failure message (which file to edit + the exact
  // `!`-line + the Dockerfile line) — a bare `toEqual([])` diff prints only the raw objects.
  const explain = (vs: Violation[]): string =>
    "\n" +
    vs
      .map(
        (v) =>
          `  Dockerfile:${v.line} bakes/consumes context path "${v.src}" but .dockerignore strips ` +
          `it — add \`${v.reinclude}\` to apps/web-platform/.dockerignore (or the release build breaks).`,
      )
      .join("\n");

  test("real Dockerfile + .dockerignore + live tracked set → zero violations", () => {
    const violations = findReincludeViolations({
      dockerfileText: realDockerfile,
      dockerignoreText: realDockerignore,
      trackedContextPaths: realTracked,
    });
    // A non-empty list means a baked/consumed context path is missing its `!`-re-include — the
    // release WILL break. `explain` names each src + the exact `!<path>` line + Dockerfile line.
    expect(violations, violations.length ? explain(violations) : "clean").toEqual([]);
  });

  test("POSITIVE CONTROL: removing a real re-include from the model surfaces a violation", () => {
    // Proves the zero-violation test above is NOT vacuous: strip one known `!`-re-include from the
    // real .dockerignore and the guard must flag exactly that src. If a future refactor moved every
    // baked src out of an excluded dir, THIS test goes red first (the src no longer needs a
    // re-include), signalling that the clean-repo assertion has silently become vacuous.
    const withoutOneReinclude = realDockerignore.replace(
      /^!scripts\/assert-dev-signin-eliminated\.sh$/m,
      "",
    );
    const violations = findReincludeViolations({
      dockerfileText: realDockerfile,
      dockerignoreText: withoutOneReinclude,
      trackedContextPaths: realTracked,
    });
    expect(violations.map((v) => v.src)).toContain("scripts/assert-dev-signin-eliminated.sh");
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

  test("parseBuilderCopySources: bare valueless flag (--link) before --from is tolerated", () => {
    const srcs = parseBuilderCopySources(
      "FROM x AS runner\nCOPY --link --from=builder /app/infra/foo.sh ./infra/foo.sh",
    ).map((s) => s.src);
    expect(srcs).toEqual(["infra/foo.sh"]);
  });

  test("parseBuilderRunScriptSources: direct-exec RUN ./scripts/x.sh is captured (./ normalized)", () => {
    const df = ["FROM x AS builder", "RUN ./scripts/gen.sh --flag", "FROM y AS runner"].join("\n");
    expect(parseBuilderRunScriptSources(df).map((s) => s.src)).toEqual(["scripts/gen.sh"]);
  });

  test("parseBuilderRunScriptSources: bash ./scripts/x.sh normalizes the ./ prefix", () => {
    const df = ["FROM x AS builder", "RUN bash ./scripts/gen.sh", "FROM y AS runner"].join("\n");
    expect(parseBuilderRunScriptSources(df).map((s) => s.src)).toEqual(["scripts/gen.sh"]);
  });

  test("parseBuilderRunScriptSources: .sh on a \\-continuation line of a multi-line RUN is captured", () => {
    const df = [
      "FROM x AS builder",
      "RUN set -e \\",
      "  && bash scripts/gen.sh",
      "FROM y AS runner",
    ].join("\n");
    expect(parseBuilderRunScriptSources(df).map((s) => s.src)).toEqual(["scripts/gen.sh"]);
  });

  test("glob EXCLUDE fail-LOUD: a baked src shadowed only by a glob exclude is flagged (not skipped)", () => {
    // The earlier `if (hasGlob) continue` would have SILENTLY passed this — the fail-open the
    // review caught. A glob exclude (`assets/*`) with no re-include must now surface a violation.
    const violations = findReincludeViolations({
      dockerfileText: "FROM x AS runner\nCOPY --from=builder /app/assets/logo.svg ./assets/logo.svg",
      dockerignoreText: "assets/*",
      trackedContextPaths: new Set(["assets/logo.svg"]),
    });
    expect(violations.map((v) => v.src)).toEqual(["assets/logo.svg"]);
  });

  test("glob EXCLUDE + exact re-include → no violation", () => {
    const violations = findReincludeViolations({
      dockerfileText: "FROM x AS runner\nCOPY --from=builder /app/assets/logo.svg ./assets/logo.svg",
      dockerignoreText: "assets/*\n!assets/logo.svg",
      trackedContextPaths: new Set(["assets/logo.svg"]),
    });
    expect(violations).toEqual([]);
  });
});
