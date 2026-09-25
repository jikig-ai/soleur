import { describe, test, expect, vi } from "vitest";
import { readdirSync, statSync } from "fs";
import { join, relative, resolve, sep } from "path";

// Guard 1 — middleware matcher coverage of authenticated surfaces
// (perf-dashboard-section-load-latency plan §Guard Contract, Guard 1).
//
// Property: every request path that can reach a route handler — including
// every `/api/*` handler that may consume `x-soleur-auth-user-id` — traverses
// `middleware.ts`, so the inbound-strip + verified-set sequence can never be
// bypassed. If a future matcher narrowing excluded an API route, a CLIENT-
// FORGED `x-soleur-auth-user-id` header would reach that handler unstripped
// — a single-user-incident-class auth bypass.
//
// Assembly under guard: `export const config.matcher` evaluated against the
// set of route-handler paths produced by walking `app/api/**/route.ts` — the
// STRUCTURE (walk + evaluate every member), not today's file list, which
// drifts with every new route.
//
// Mutation-matrix coverage notes:
//   row 1 (narrow matcher to exclude an /api route) → the per-route loop
//     below fails on that path.
//   row 3 (a NEW route outside the matcher) → the walk discovers it and the
//     same assertion fails — every member is evaluated, never just one.
//   row 4 (evaluator corrupted to always-true) → the negative controls at the
//     bottom (static/excluded paths must NOT match) go RED, so a harness that
//     can never fail is itself detected.
//   row 5 (delete-before-PUBLIC_PATHS ordering) → pinned separately in
//     test/middleware.test.ts (source-order + behavioral strip assertions).

// The config export shares a module with the middleware function; importing it
// pulls @supabase/ssr + the edge-observability shim, so mock both exactly as
// the existing middleware suites do. We never invoke middleware() here — only
// the matcher list is read.
vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: vi.fn(), getSession: vi.fn() },
    rpc: vi.fn(),
    from: vi.fn(),
  })),
}));
vi.mock("@/lib/observability-edge", () => ({
  reportEdgeSilentFallback: vi.fn(),
}));

import { config } from "@/middleware";

const API_ROOT = resolve(__dirname, "../../app/api");

// Recursively collect request paths for every route handler file under
// app/api (any depth) — i.e. each `route.ts`/`route.tsx`.
// NOTE: this must stay a // line comment — the glob spelling `app/api/**/x`
// embeds `*/`, which would terminate a /* */ block comment early.
function collectApiRoutePaths(dir: string): string[] {
  const paths: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      paths.push(...collectApiRoutePaths(full));
    } else if (entry === "route.ts" || entry === "route.tsx") {
      // app/api/foo/bar/route.ts → /api/foo/bar
      const rel = relative(API_ROOT, dir).split(sep).join("/");
      paths.push(rel ? `/api/${rel}` : "/api");
    }
  }
  return paths;
}

/**
 * Evaluate one Next.js `config.matcher` entry against a request pathname.
 *
 * The shipped matcher is a raw-regex entry
 * (`"/((?!_next/static|_next/image|...$).*)"`), so `new RegExp` reproduces
 * Next's own path-to-regexp-compiled behavior for it. This evaluator is
 * deliberately literal — if a future matcher adds `:param`-style syntax that
 * does not compile to equivalent regex semantics, affected route paths will
 * FAIL here and force the evaluator to be extended. That is the guard working
 * as designed (fail toward RED, never vacuously green).
 */
function pathnameMatches(matcherPattern: string, pathname: string): boolean {
  return new RegExp(`^${matcherPattern}$`).test(pathname);
}

const rawMatcher = config.matcher as string | string[];
const matchers: string[] = Array.isArray(rawMatcher)
  ? [...rawMatcher]
  : [rawMatcher];

function matchesMiddleware(pathname: string): boolean {
  return matchers.some((m) => pathnameMatches(m, pathname));
}

describe("Guard 1 — middleware matcher covers every /api/* route", () => {
  const routePaths = collectApiRoutePaths(API_ROOT);

  test("anti-vacuity: the walk found a non-trivial number of route handlers", () => {
    // ~105 route.ts files exist today. A floor well below that still proves
    // the walk ran; an empty glob must never pass this guard.
    expect(routePaths.length).toBeGreaterThanOrEqual(25);
    // And the matcher list itself is non-empty — a vacuous `matcher: []`
    // would trivially "cover" nothing while the loop below asserts nothing.
    expect(matchers.length).toBeGreaterThan(0);
  });

  test.each(routePaths)(
    "route %s traverses middleware (matches config.matcher)",
    (pathname) => {
      expect(
        matchesMiddleware(pathname),
        `${pathname} is NOT matched by config.matcher — a request to it ` +
          `bypasses the x-soleur-auth-user-id strip/verify sequence`,
      ).toBe(true);
    },
  );

  test("positive control: a known dynamic API route matches", () => {
    // /api/accept-terms is TC-EXEMPT but must still traverse middleware (the
    // auth check itself applies — exempt means "skip T&C", not "no middleware").
    expect(matchesMiddleware("/api/accept-terms")).toBe(true);
    expect(matchesMiddleware("/api/workspace/active-repo")).toBe(true);
  });

  test("negative controls: static/excluded paths do NOT match (evaluator can fail)", () => {
    // These are exactly what the shipped matcher excludes. If the evaluator
    // were corrupted to always-true (Guard 1 row 4), these go RED.
    expect(matchesMiddleware("/_next/static/chunks/main.js")).toBe(false);
    expect(matchesMiddleware("/_next/image/logo.png")).toBe(false);
    expect(matchesMiddleware("/favicon.ico")).toBe(false);
    expect(matchesMiddleware("/sw.js")).toBe(false);
    expect(matchesMiddleware("/icons/logo.svg")).toBe(false);
  });
});
