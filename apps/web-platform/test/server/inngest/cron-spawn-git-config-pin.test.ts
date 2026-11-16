// #12757 Guard 3 — every cron child process that can run git carries CRON_GIT_CONFIG_PIN.
//
// HOW TO READ A RED RUN: every cron env literal (an object literal with a `HOME` key) under server/inngest must end with
// `...CRON_GIT_CONFIG_PIN`, imported from "@/server/host-git". When you add a cron, COPY THE ENV OF AN EXISTING CRON rather
// than writing one fresh, then add the new site to the stored maps below. The failure message names the file, the line and
// the fix; it never asks you to loosen the sweep.
//
// What this proves (the property, plan Guard 3): no git process a cron starts (by the agent through `claude`, by a bash
// script, or by the server itself) reads `$HOME/.gitconfig`, `$HOME/.config/git/config` or the system gitconfig, because
// `GIT_CONFIG_GLOBAL` names the image-owned identity file and `GIT_CONFIG_NOSYSTEM=1` (or the stricter `/dev/null` pins).
//
// The sweep is the TypeScript compiler API over every non-test `*.ts` file under server/inngest (open-world, recursive);
// the `.mjs` hooks are out of the sweep. Accepting identifiers must be BOUND (an import from the named module, or one named
// same-file declaration), never just spelled right: a local `const CRON_GIT_CONFIG_PIN = {}` is a violation.
//
// The stored maps (KNOWN_HOME_LITERALS, KNOWN_GIT_SPAWNS, DYNAMIC_COMMAND_SPAWNS, GIT_CAPABLE_LITERAL_EXCLUSIONS,
// GIT_CONFIG_WRITE_EXCEPTIONS) are identity maps, not counts: a rename, a removal or an addition goes red with a diff. A
// diff that edits both the guarded code and a map proves consistency, not integrity — any shrink of a map or any new
// exclusion is a review finding (plan Guard 3 "Anchor").
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import ts from "typescript";
import { afterAll, describe, expect, it, vi } from "vitest";

import { AGENT_GIT_GLOBAL_CONFIG, CRON_GIT_CONFIG_PIN } from "@/server/host-git";
import { gitCleanEnv } from "../../../../../plugins/soleur/test/lib/git-clean-env";
import { gitFixtureEnv } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

const APP = path.resolve(__dirname, "../../..");
const SWEEP_ROOT = path.join(APP, "server/inngest");
const SUBSTRATE = "functions/_cron-claude-eval-substrate.ts";
const SAFE_COMMIT = "functions/_cron-safe-commit.ts";
// The literal must never be retyped under server/inngest (row 4b). Built from parts so this file is not itself a hit
// for anyone grepping the tree for the path.
const RETYPED_PATH = ["", "usr", "local", "share", "soleur", "agent.gitconfig"].join("/");

// =============================================================================
// Stored identity maps (seeded from the first sweep on 2026-11-16)
// =============================================================================

/**
 * Row 2: every object literal with a HOME key, by file → enclosing function or step name (sorted, duplicates kept). A
 * template step name keeps its substitutions as `${}` (vendor-drift's per-bundle `detect-drift-${bundle.slug}`).
 */
const KNOWN_HOME_LITERALS: Record<string, string[]> = {
  "functions/cron-agent-native-audit.ts": ["buildSpawnEnv"],
  "functions/cron-architecture-diagram-sync.ts": ["buildSpawnEnv"],
  "functions/cron-bug-fixer.ts": ["buildSpawnEnv"],
  "functions/cron-campaign-calendar.ts": ["buildSpawnEnv"],
  "functions/cron-community-monitor.ts": ["buildSpawnEnv"],
  "functions/cron-competitive-analysis.ts": ["buildSpawnEnv"],
  "functions/cron-content-generator.ts": ["buildSpawnEnv"],
  "functions/cron-content-publisher.ts": ["buildPublisherEnv"],
  "functions/cron-content-vendor-drift.ts": ["detect-drift-${}", "discover-bundles"],
  "functions/cron-daily-triage.ts": ["buildSpawnEnv"],
  "functions/cron-follow-through-monitor.ts": ["buildSpawnEnv"],
  "functions/cron-github-cidr-refresh.ts": ["refreshCidr"],
  "functions/cron-growth-audit.ts": ["buildSpawnEnv"],
  "functions/cron-growth-execution.ts": ["buildSpawnEnv"],
  "functions/cron-legal-audit.ts": ["buildSpawnEnv"],
  "functions/cron-roadmap-review.ts": ["buildSpawnEnv"],
  "functions/cron-rule-prune.ts": ["run-rule-prune"],
  "functions/cron-seo-aeo-audit.ts": ["buildSpawnEnv"],
  "functions/cron-ux-audit.ts": ["buildSpawnEnv"],
  "functions/cron-weekly-analytics.ts": ["run-analytics"],
  "functions/event-ship-merge.ts": ["buildSpawnEnv", "checkout-pr", "checkout-pr"],
  "functions/oneshot-f2-defer-gate-review.ts": ["buildSpawnEnv"],
  "functions/oneshot-recheck-4217-calibration.ts": ["buildSpawnEnv"],
};

/** Row 4: every call whose first argument is a `git` command literal (any callee), by file → owner (sorted). */
const KNOWN_GIT_SPAWNS: Record<string, string[]> = {
  "functions/_cron-claude-eval-substrate.ts": ["setOriginToken", "setupEphemeralWorkspace"],
  "functions/_cron-safe-commit.ts": ["gitObjectBytes", "runGit"],
  "functions/cron-compound-promote.ts": ["spawnGit", "spawnGitCapture"],
  "functions/cron-content-publisher.ts": ["spawnGit"],
  "functions/cron-content-vendor-drift.ts": ["spawnGit", "spawnGitStdout"],
  "functions/cron-github-cidr-refresh.ts": ["refreshCidr", "setupEphemeralWorkspace"],
  "functions/cron-rule-prune.ts": ["spawnGit"],
  "functions/cron-strategy-review.ts": ["setupEphemeralWorkspace"],
  "functions/cron-weekly-analytics.ts": ["spawnGit"],
  "functions/event-ship-merge.ts": ["checkout-pr", "checkout-pr"],
};

/**
 * Row 4c: child_process calls whose command is NOT a literal (the sweep cannot read the word). Each is either "pinned"
 * (its env must pass the same acceptance as a git spawn) or excluded with a reason. A new dynamic spawn is a diff.
 */
const DYNAMIC_COMMAND_SPAWNS: Record<string, Record<string, string>> = {
  [SUBSTRATE]: {
    spawnSimple: "pinned",
    spawnClaudeEvalUnguarded: "pinned",
    exec: "excluded: framing-hook self-test probe; an execFileSync of nodeBin runs node, not git",
    run: "excluded: containment-hook self-test probe; an execFileSync of nodeBin runs node, not git",
  },
  "functions/cron-github-cidr-refresh.ts": {
    runProc: "excluded: generic runner; every caller passes a literal git/bash command, which rows 4 and 4c check at the call site",
  },
};

/**
 * Row 4c: literals whose basename or leading word is git/gh/bash/sh/env that are not the command of a pinned spawn.
 * `anchor` is a content anchor (a substring of the hit's source line), never a line number; each entry must match exactly
 * one live hit, so a stale entry fails.
 */
// Seeded from the first sweep (2026-11-16): zero hits needed an exclusion. The allowlist arrays and error-message strings
// that start with "git "/"gh "/"bash " are not in a spawn position (not a call's first argument, not an element of an
// array passed to a call), so the sweep does not count them; a BARE word ("git", "/usr/bin/git") counts anywhere.
const GIT_CAPABLE_LITERAL_EXCLUSIONS: { file: string; anchor: string; reason: string }[] = [];

/** Row 4d: post-construction writes to a GIT_CONFIG_* key, by file → "owner KEY" (exact match). */
const GIT_CONFIG_WRITE_EXCEPTIONS: Record<string, string[]> = {
  "functions/cron-compound-promote.ts": ["spawnGitCapture GIT_CONFIG_GLOBAL", "spawnGitCapture GIT_CONFIG_NOSYSTEM"],
};

// =============================================================================
// The analyser
// =============================================================================

const WORDS = new Set(["git", "gh", "bash", "sh", "env"]);
const CHILD_PROCESS_MODULES = new Set(["node:child_process", "child_process"]);

/** Accepting identifiers and where they must be bound. `localIn`: the one file whose own declaration counts. */
const BINDINGS: Record<string, { modules: string[]; localIn?: string; localAnywhere?: true }> = {
  CRON_GIT_CONFIG_PIN: { modules: ["@/server/host-git"] },
  withCronGitConfigPin: { modules: ["@/server/host-git"] },
  GIT_HARDENING_ENV: { modules: ["./_git-hardening", "@/server/inngest/functions/_git-hardening"] },
  spawnSimple: {
    modules: ["./_cron-claude-eval-substrate", "@/server/inngest/functions/_cron-claude-eval-substrate"],
    localIn: SUBSTRATE,
  },
  // A same-file declaration is accepted only if its own body pins /dev/null (checked in gitIsolatedEnvPins).
  gitIsolatedEnv: { modules: [], localAnywhere: true },
};

interface Site {
  file: string;
  line: number;
  owner: string;
  ok: boolean;
  why: string;
  text: string;
}
interface CapableSite extends Site {
  word: string;
}
interface Analysis {
  home: Site[];
  gitSpawns: Site[];
  capable: CapableSite[];
  dynamic: Site[];
  otherLiteral: Site[];
  configWrites: Site[];
  /** `import * as cp` / `import cp from` / `const cp = await import(…)` / `require(…)` of child_process (row 4e). */
  nsImports: Site[];
}

interface Ctx {
  file: string;
  src: string;
  sf: ts.SourceFile;
  /** local name → module, only for `import { X } from "m"` with no alias. */
  imports: Map<string, string>;
  /** every non-import declaration by name (variables, functions, parameters, classes, binding elements). */
  decls: Map<string, ts.Node[]>;
  /** names that call a child_process spawner. */
  spawners: Set<string>;
}

function skip(e: ts.Expression): ts.Expression {
  let cur = e;
  for (;;) {
    if (ts.isParenthesizedExpression(cur) || ts.isAsExpression(cur) || ts.isSatisfiesExpression(cur) || ts.isNonNullExpression(cur)) {
      cur = cur.expression;
    } else if (ts.isTypeAssertionExpression(cur)) {
      cur = cur.expression;
    } else return cur;
  }
}

function literalText(n: ts.Node): string | null {
  if (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) return n.text;
  if (ts.isTemplateExpression(n)) return n.head.text + n.templateSpans.map((s) => "${}" + s.literal.text).join("");
  return null;
}

/** The command word of a literal: its first whitespace-delimited token's basename, if it is one of WORDS. */
function commandWord(text: string): { word: string; bare: boolean } | null {
  const m = /^(\S+)(\s[\s\S]*)?$/.exec(text.trimStart());
  if (!m) return null;
  const base = m[1].split("/").pop() ?? "";
  if (!WORDS.has(base)) return null;
  return { word: base, bare: m[2] === undefined || m[2].trim() === "" };
}

function lineOf(sf: ts.SourceFile, n: ts.Node): number {
  return sf.getLineAndCharacterOfPosition(n.getStart(sf)).line + 1;
}

function lineText(ctx: Ctx, n: ts.Node): string {
  return ctx.src.split("\n")[lineOf(ctx.sf, n) - 1]?.trim() ?? "";
}

function isFunctionLike(n: ts.Node): n is ts.FunctionLikeDeclaration {
  return (
    ts.isFunctionDeclaration(n) ||
    ts.isFunctionExpression(n) ||
    ts.isArrowFunction(n) ||
    ts.isMethodDeclaration(n) ||
    ts.isConstructorDeclaration(n) ||
    ts.isGetAccessorDeclaration(n) ||
    ts.isSetAccessorDeclaration(n)
  );
}

/** The enclosing named function, or for an anonymous `step.run("<name>", fn)` callback the step name. */
function ownerOf(n: ts.Node): string {
  for (let cur: ts.Node = n; cur.parent; cur = cur.parent) {
    if (!isFunctionLike(cur)) continue;
    const p = cur.parent;
    if (
      ts.isCallExpression(p) &&
      ts.isPropertyAccessExpression(p.expression) &&
      p.expression.name.text === "run" &&
      p.arguments[0] &&
      literalText(p.arguments[0]) !== null &&
      p.arguments.includes(cur as ts.Expression)
    ) {
      return literalText(p.arguments[0]) as string;
    }
    if ((ts.isFunctionDeclaration(cur) || ts.isMethodDeclaration(cur)) && cur.name && ts.isIdentifier(cur.name)) return cur.name.text;
    if ((ts.isArrowFunction(cur) || ts.isFunctionExpression(cur)) && ts.isVariableDeclaration(p) && ts.isIdentifier(p.name)) return p.name.text;
    if ((ts.isArrowFunction(cur) || ts.isFunctionExpression(cur)) && ts.isPropertyAssignment(p) && ts.isIdentifier(p.name)) return p.name.text;
    if (ts.isFunctionExpression(cur) && cur.name) return cur.name.text;
  }
  return "<module>";
}

function buildCtx(file: string, src: string): Ctx {
  const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const imports = new Map<string, string>();
  const decls = new Map<string, ts.Node[]>();
  const spawners = new Set<string>();
  const addDecl = (name: string, node: ts.Node) => decls.set(name, [...(decls.get(name) ?? []), node]);
  const visitBinding = (b: ts.BindingName, node: ts.Node) => {
    if (ts.isIdentifier(b)) addDecl(b.text, node);
    else for (const el of b.elements) if (!ts.isOmittedExpression(el)) visitBinding(el.name, el);
  };
  const promisified: [string, string][] = [];
  const visit = (n: ts.Node) => {
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier)) {
      const mod = n.moduleSpecifier.text;
      const nb = n.importClause?.namedBindings;
      if (nb && ts.isNamedImports(nb)) {
        for (const el of nb.elements) {
          const imported = (el.propertyName ?? el.name).text;
          if (imported === el.name.text) imports.set(el.name.text, mod);
          else addDecl(el.name.text, el); // an aliased import never counts as the accepted name
          if (CHILD_PROCESS_MODULES.has(mod)) spawners.add(el.name.text);
        }
      }
      if (n.importClause?.name) addDecl(n.importClause.name.text, n);
      if (nb && ts.isNamespaceImport(nb)) addDecl(nb.name.text, nb);
      return;
    }
    if (ts.isVariableDeclaration(n)) {
      visitBinding(n.name, n);
      // `const { execFile } = await import("node:child_process")`
      const init = n.initializer ? skip(n.initializer) : undefined;
      const inner = init && ts.isAwaitExpression(init) ? skip(init.expression) : init;
      if (
        inner &&
        ts.isCallExpression(inner) &&
        inner.expression.kind === ts.SyntaxKind.ImportKeyword &&
        inner.arguments[0] &&
        CHILD_PROCESS_MODULES.has(literalText(inner.arguments[0]) ?? "") &&
        ts.isObjectBindingPattern(n.name)
      ) {
        for (const el of n.name.elements) if (ts.isIdentifier(el.name)) spawners.add(el.name.text);
      }
      // `const execFileP = promisify(execFile)`
      if (init && ts.isCallExpression(init) && ts.isIdentifier(init.expression) && init.expression.text === "promisify" && ts.isIdentifier(n.name)) {
        const a0 = init.arguments[0];
        if (a0 && ts.isIdentifier(a0)) promisified.push([n.name.text, a0.text]);
      }
    } else if ((ts.isFunctionDeclaration(n) || ts.isClassDeclaration(n)) && n.name) {
      addDecl(n.name.text, n);
    } else if (ts.isParameter(n)) {
      visitBinding(n.name, n);
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  for (const [name, of] of promisified) if (spawners.has(of)) spawners.add(name);
  return { file, src, sf, imports, decls, spawners };
}

function bound(ctx: Ctx, name: string): boolean {
  const rule = BINDINGS[name];
  if (!rule) return false;
  const local = ctx.decls.get(name) ?? [];
  if (ctx.imports.has(name)) return local.length === 0 && rule.modules.includes(ctx.imports.get(name) as string);
  if (rule.localIn === ctx.file || rule.localAnywhere) {
    return local.length === 1 && ts.isFunctionDeclaration(local[0]) && local[0].parent === ctx.sf;
  }
  return false;
}

/** Return-statement expressions of a function (not of functions nested in it). */
function returnsOf(fn: ts.FunctionLikeDeclaration): ts.Expression[] {
  if (!fn.body) return [];
  if (!ts.isBlock(fn.body)) return [fn.body];
  const out: ts.Expression[] = [];
  const visit = (n: ts.Node) => {
    if (isFunctionLike(n)) return;
    if (ts.isReturnStatement(n) && n.expression) out.push(n.expression);
    ts.forEachChild(n, visit);
  };
  ts.forEachChild(fn.body, visit);
  return out;
}

function propName(p: ts.ObjectLiteralElementLike): string | null {
  if (!p.name) return null;
  if (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name)) return p.name.text;
  return null;
}

/** `gitIsolatedEnv`'s own body: every return is a literal whose entries after the last spread pin /dev/null. */
function gitIsolatedEnvPins(ctx: Ctx): boolean {
  const decl = (ctx.decls.get("gitIsolatedEnv") ?? [])[0];
  if (!decl || !ts.isFunctionDeclaration(decl)) return false;
  const rets = returnsOf(decl);
  return (
    rets.length > 0 &&
    rets.every((r) => {
      const lit = skip(r);
      if (!ts.isObjectLiteralExpression(lit)) return false;
      const props = lit.properties;
      let lastSpread = -1;
      props.forEach((p, i) => {
        if (ts.isSpreadAssignment(p)) lastSpread = i;
      });
      const after = props.slice(lastSpread + 1);
      const val = (k: string) => {
        const p = after.find((q) => ts.isPropertyAssignment(q) && propName(q) === k) as ts.PropertyAssignment | undefined;
        return p ? literalText(skip(p.initializer)) : null;
      };
      return val("GIT_CONFIG_GLOBAL") === "/dev/null" && val("GIT_CONFIG_NOSYSTEM") === "1";
    })
  );
}

/** Lexical lookup of a name from a use site: the nearest enclosing block / file / parameter list that declares it. */
function resolveLocal(name: string, from: ts.Node): ts.Node | null {
  for (let cur: ts.Node | undefined = from.parent; cur; cur = cur.parent) {
    if (ts.isBlock(cur) || ts.isSourceFile(cur) || ts.isModuleBlock(cur) || ts.isCaseClause(cur)) {
      for (const st of cur.statements) {
        if (ts.isVariableStatement(st)) {
          for (const d of st.declarationList.declarations) if (ts.isIdentifier(d.name) && d.name.text === name) return d;
        } else if (ts.isFunctionDeclaration(st) && st.name?.text === name) return st;
      }
    }
    if (isFunctionLike(cur)) {
      for (const p of cur.parameters) if (ts.isIdentifier(p.name) && p.name.text === name) return p;
    }
  }
  return null;
}

type Verdict = { ok: boolean; why: string };
const OK = (why: string): Verdict => ({ ok: true, why });
const NO = (why: string): Verdict => ({ ok: false, why });

function isWriteTo(n: ts.Node, name: string): boolean {
  // Object.assign(name, ...), name.x = / name[x] = (including inside loops)
  if (ts.isCallExpression(n) && n.expression.getText() === "Object.assign" && n.arguments[0] && skip(n.arguments[0]).getText() === name) return true;
  if (ts.isBinaryExpression(n) && n.operatorToken.kind === ts.SyntaxKind.EqualsToken) {
    const l = n.left;
    if ((ts.isPropertyAccessExpression(l) || ts.isElementAccessExpression(l)) && l.expression.getText() === name) return true;
  }
  return false;
}

/** spawnGitCapture: `env.GIT_CONFIG_GLOBAL = "/dev/null"` and `env.GIT_CONFIG_NOSYSTEM = "1"` after every other write, before the use. */
function postAssignPinned(decl: ts.VariableDeclaration, name: string, use: ts.Node): boolean {
  const block = decl.parent?.parent?.parent;
  if (!block || !ts.isBlock(block)) return false;
  const pins = new Map<string, number>();
  let lastOther = -1;
  const visit = (n: ts.Node) => {
    if (isWriteTo(n, name)) {
      const b = ts.isBinaryExpression(n) ? n : null;
      const key = b && ts.isPropertyAccessExpression(b.left) ? b.left.name.text : null;
      const val = b ? literalText(skip(b.right)) : null;
      if (key === "GIT_CONFIG_GLOBAL" && val === "/dev/null") pins.set(key, n.getStart());
      else if (key === "GIT_CONFIG_NOSYSTEM" && val === "1") pins.set(key, n.getStart());
      else lastOther = Math.max(lastOther, n.getStart());
    }
    ts.forEachChild(n, visit);
  };
  visit(block);
  const g = pins.get("GIT_CONFIG_GLOBAL");
  const s = pins.get("GIT_CONFIG_NOSYSTEM");
  return g !== undefined && s !== undefined && g > lastOther && s > lastOther && use.getStart() > Math.max(g, s);
}

function envAccepted(ctx: Ctx, raw: ts.Expression, depth = 0): Verdict {
  const e = skip(raw);
  if (depth > 2) return NO("env resolution exceeded two hops");
  if (ts.isObjectLiteralExpression(e)) {
    const last = e.properties[e.properties.length - 1];
    if (last && ts.isSpreadAssignment(last)) {
      const s = skip(last.expression);
      if (ts.isIdentifier(s) && s.text === "CRON_GIT_CONFIG_PIN") {
        return bound(ctx, s.text) ? OK("ends with ...CRON_GIT_CONFIG_PIN") : NO("CRON_GIT_CONFIG_PIN is not bound to the @/server/host-git import");
      }
      if (ts.isIdentifier(s) && s.text === "GIT_HARDENING_ENV") {
        return bound(ctx, s.text) ? OK("ends with ...GIT_HARDENING_ENV") : NO("GIT_HARDENING_ENV is not bound to the _git-hardening import");
      }
      if (ts.isCallExpression(s) && ts.isIdentifier(s.expression) && s.expression.text === "gitIsolatedEnv") {
        return bound(ctx, "gitIsolatedEnv") && gitIsolatedEnvPins(ctx) ? OK("ends with ...gitIsolatedEnv()") : NO("gitIsolatedEnv is not a bound same-file /dev/null pin");
      }
    }
    return NO("env literal does not end with ...CRON_GIT_CONFIG_PIN");
  }
  if (ts.isCallExpression(e) && ts.isIdentifier(e.expression)) {
    const callee = e.expression.text;
    if (callee === "withCronGitConfigPin") return bound(ctx, callee) ? OK("withCronGitConfigPin(...)") : NO("withCronGitConfigPin is not bound to the @/server/host-git import");
    if (callee === "gitIsolatedEnv") return bound(ctx, callee) && gitIsolatedEnvPins(ctx) ? OK("gitIsolatedEnv()") : NO("gitIsolatedEnv is not a bound same-file /dev/null pin");
    const fn = resolveLocal(callee, e);
    let target: ts.FunctionLikeDeclaration | null = null;
    if (fn && ts.isFunctionDeclaration(fn)) target = fn;
    else if (fn && ts.isVariableDeclaration(fn) && fn.initializer && (ts.isArrowFunction(fn.initializer) || ts.isFunctionExpression(fn.initializer))) target = fn.initializer;
    if (target) {
      const rets = returnsOf(target);
      if (rets.length === 0) return NO(`${callee}() returns nothing the sweep can read`);
      for (const r of rets) {
        const v = envAccepted(ctx, r, depth + 1);
        if (!v.ok) return NO(`${callee}() → ${v.why}`);
      }
      return OK(`${callee}() (one hop) → pinned literal`);
    }
    return NO(`env is a call to ${callee}(), which is not a same-file function the sweep can resolve`);
  }
  if (ts.isIdentifier(e)) {
    const d = resolveLocal(e.text, e);
    if (d && ts.isVariableDeclaration(d) && d.initializer && (d.parent.flags & ts.NodeFlags.Const) !== 0) {
      const v = envAccepted(ctx, d.initializer, depth + 1);
      if (v.ok) return OK(`${e.text} (one hop) → ${v.why}`);
      if (postAssignPinned(d, e.text, e)) return OK(`${e.text} pinned to /dev/null by post-construction assignment`);
      return NO(`${e.text} → ${v.why}`);
    }
    return NO(`env identifier ${e.text} does not resolve to a same-file const`);
  }
  return NO(`env expression \`${e.getText().slice(0, 60)}\` is not a pinned form`);
}

/** The env of a spawn-ish call's options literal, with the order check (env must follow every spread). */
function envOfCall(call: ts.CallExpression): { env: ts.Expression | null; orderBad: boolean } {
  for (const a of call.arguments.slice(1)) {
    const o = skip(a);
    if (!ts.isObjectLiteralExpression(o)) continue;
    const idx = o.properties.findIndex((p) => (ts.isPropertyAssignment(p) || ts.isShorthandPropertyAssignment(p)) && propName(p) === "env");
    if (idx < 0) continue;
    const p = o.properties[idx];
    const orderBad = o.properties.slice(idx + 1).some((q) => ts.isSpreadAssignment(q));
    const env = ts.isPropertyAssignment(p) ? p.initializer : (p as ts.ShorthandPropertyAssignment).name;
    return { env, orderBad };
  }
  return { env: null, orderBad: false };
}

/** Any identifier or string literal (never a comment) naming a GIT_CONFIG_* key. */
function mentionsGitConfigKey(sf: ts.SourceFile): boolean {
  let hit = false;
  const visit = (n: ts.Node) => {
    if (hit) return;
    if ((ts.isIdentifier(n) || ts.isStringLiteralLike(n)) && n.text.startsWith("GIT_CONFIG_")) hit = true;
    else ts.forEachChild(n, visit);
  };
  visit(sf);
  return hit;
}

function safeCommitException(ctx: Ctx, call: ts.CallExpression, owner: string, env: ts.Expression): boolean {
  if (ctx.file !== SAFE_COMMIT || !["runGit", "gitObjectBytes"].includes(owner)) return false;
  if (mentionsGitConfigKey(ctx.sf)) return false; // exactModeEnv (the only extraEnv) must carry no GIT_CONFIG_* key
  const lit = skip(env);
  if (!ts.isObjectLiteralExpression(lit) || lit.properties.length !== 3) return false;
  const [a, b, c] = lit.properties;
  return (
    ts.isSpreadAssignment(a) &&
    a.expression.getText() === "process.env" &&
    ts.isSpreadAssignment(b) &&
    b.expression.getText() === "GIT_HARDENING_ENV" &&
    bound(ctx, "GIT_HARDENING_ENV") &&
    ts.isSpreadAssignment(c) &&
    c.expression.getText() === "extraEnv" &&
    call.arguments.length >= 2
  );
}

function callVerdict(ctx: Ctx, call: ts.CallExpression): Verdict {
  if (ts.isIdentifier(call.expression) && call.expression.text === "spawnSimple") {
    return bound(ctx, "spawnSimple") ? OK("spawnSimple chokepoint") : NO("spawnSimple is not bound to the substrate (a local look-alike?)");
  }
  const { env, orderBad } = envOfCall(call);
  if (!env) return NO("no env (inherits the server's process.env, so $HOME/.gitconfig is read)");
  if (orderBad) return NO("a spread comes after env in the options literal, so a caller's env can replace the pin");
  const owner = ownerOf(call);
  if (safeCommitException(ctx, call, owner, env)) return OK("named exception: _cron-safe-commit extraEnv after GIT_HARDENING_ENV");
  return envAccepted(ctx, env);
}

function analyze(file: string, src: string): Analysis {
  const ctx = buildCtx(file, src);
  const out: Analysis = { home: [], gitSpawns: [], capable: [], dynamic: [], otherLiteral: [], configWrites: [], nsImports: [] };
  const site = (n: ts.Node, v: Verdict): Site => ({ file, line: lineOf(ctx.sf, n), owner: ownerOf(n), ok: v.ok, why: v.why, text: lineText(ctx, n) });
  const configKey = (n: ts.Expression): string | null => {
    if (ts.isPropertyAccessExpression(n)) return n.name.text.startsWith("GIT_CONFIG") ? n.name.text : null;
    if (ts.isElementAccessExpression(n)) {
      const t = literalText(n.argumentExpression);
      return t && t.startsWith("GIT_CONFIG") ? t : null;
    }
    return null;
  };

  const visit = (n: ts.Node) => {
    // Row 4e: the walker tracks spawners by NAMED import only, so a namespace or default handle on child_process
    // (`cp.spawn(…)`) would be invisible to rows 4/4c. Any such handle is reported instead of silently passing.
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier) && CHILD_PROCESS_MODULES.has(n.moduleSpecifier.text)) {
      const nb = n.importClause?.namedBindings;
      if (n.importClause?.name || (nb && ts.isNamespaceImport(nb))) out.nsImports.push(site(n, NO("namespace/default import of child_process")));
    }
    if (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) return;
    // Any require()/import() of child_process, wherever it sits (a variable, or inline `require(cp).spawn(…)`),
    // except the destructured named form `const { spawn } = await import(cp)`, which buildCtx tracks as spawners.
    if (
      ts.isCallExpression(n) &&
      (n.expression.kind === ts.SyntaxKind.ImportKeyword || (ts.isIdentifier(n.expression) && n.expression.text === "require")) &&
      n.arguments[0] &&
      CHILD_PROCESS_MODULES.has(literalText(n.arguments[0]) ?? "")
    ) {
      let up: ts.Node = n.parent;
      while (ts.isAwaitExpression(up) || ts.isParenthesizedExpression(up) || ts.isAsExpression(up)) up = up.parent;
      const named = ts.isVariableDeclaration(up) && ts.isObjectBindingPattern(up.name);
      if (!named) out.nsImports.push(site(n, NO("whole-module handle on child_process")));
    }

    // Row 2: HOME-keyed object literals (keyed or shorthand).
    if (ts.isObjectLiteralExpression(n) && n.properties.some((p) => (ts.isPropertyAssignment(p) || ts.isShorthandPropertyAssignment(p)) && propName(p) === "HOME")) {
      const last = n.properties[n.properties.length - 1];
      let v: Verdict = NO("HOME: literal does not end with ...CRON_GIT_CONFIG_PIN");
      if (last && ts.isSpreadAssignment(last) && ts.isIdentifier(skip(last.expression)) && (skip(last.expression) as ts.Identifier).text === "CRON_GIT_CONFIG_PIN") {
        v = bound(ctx, "CRON_GIT_CONFIG_PIN") ? OK("pinned") : NO("HOME: literal ends with a CRON_GIT_CONFIG_PIN that is not bound to the @/server/host-git import");
      }
      out.home.push(site(n, v));
    }

    // Row 4d: post-construction writes to GIT_CONFIG_* and unexpected GIT_CONFIG_* values in literals.
    if (ts.isBinaryExpression(n) && n.operatorToken.kind >= ts.SyntaxKind.FirstAssignment && n.operatorToken.kind <= ts.SyntaxKind.LastAssignment) {
      const k = configKey(n.left);
      if (k) out.configWrites.push({ ...site(n, NO("write")), why: `${ownerOf(n)} ${k}` });
    }
    if (ts.isDeleteExpression(n)) {
      const k = configKey(skip(n.expression));
      if (k) out.configWrites.push({ ...site(n, NO("delete")), why: `${ownerOf(n)} delete ${k}` });
    }
    if (ts.isPropertyAssignment(n) && (propName(n) ?? "").startsWith("GIT_CONFIG")) {
      const k = propName(n) as string;
      const val = literalText(skip(n.initializer));
      const allowed =
        (k === "GIT_CONFIG_GLOBAL" && val === "/dev/null") || (k === "GIT_CONFIG_SYSTEM" && val === "/dev/null") || (k === "GIT_CONFIG_NOSYSTEM" && val === "1");
      const viaAssign =
        ts.isObjectLiteralExpression(n.parent) && ts.isCallExpression(n.parent.parent) && n.parent.parent.expression.getText() === "Object.assign";
      if (!allowed || viaAssign) out.configWrites.push({ ...site(n, NO("literal")), why: `${ownerOf(n)} literal ${k}` });
    }
    if (ts.isPropertyAssignment(n) && n.name && ts.isComputedPropertyName(n.name)) {
      const t = literalText(n.name.expression);
      if (t && t.startsWith("GIT_CONFIG")) out.configWrites.push({ ...site(n, NO("computed")), why: `${ownerOf(n)} computed ${t}` });
    }

    if (ts.isCallExpression(n)) {
      const a0 = n.arguments[0];
      const t0 = a0 ? literalText(a0) : null;
      const cw = t0 !== null ? commandWord(t0) : null;
      // Row 4: callee-agnostic, first argument is a bare `git` (or `/path/to/git`) literal.
      if (cw && cw.bare && cw.word === "git") out.gitSpawns.push(site(n, callVerdict(ctx, n)));
      // child_process calls: a non-literal command is a dynamic spawn; a literal outside WORDS is an unknown command.
      if (ts.isIdentifier(n.expression) && ctx.spawners.has(n.expression.text)) {
        if (t0 === null) out.dynamic.push(site(n, callVerdict(ctx, n)));
        else if (!cw) out.otherLiteral.push(site(n, NO(`child_process spawn of literal "${t0}"`)));
      }
    }

    // Row 4c: git-capable literals.
    const t = literalText(n);
    if (t !== null && !ts.isTemplateExpression(n.parent) && !ts.isTemplateSpan(n.parent)) {
      const cw = commandWord(t);
      if (cw) {
        const p = n.parent;
        let carrier: ts.CallExpression | null = null;
        if (ts.isCallExpression(p) && p.arguments[0] === n) carrier = p;
        else if (ts.isArrayLiteralExpression(p) && ts.isCallExpression(p.parent) && p.parent.arguments.includes(p)) carrier = p.parent;
        if (carrier) out.capable.push({ ...site(n, callVerdict(ctx, carrier)), word: cw.word });
        else if (cw.bare) out.capable.push({ ...site(n, NO(`bare "${cw.word}" literal is not the command of a spawn`)), word: cw.word });
      }
    }
    ts.forEachChild(n, visit);
  };
  visit(ctx.sf);
  return out;
}

// =============================================================================
// The sweep
// =============================================================================

function sweepFiles(root = SWEEP_ROOT): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const e of entries) {
      const abs = path.join(dir, e);
      if (statSync(abs).isDirectory()) walk(abs);
      else if (e.endsWith(".ts") && !e.endsWith(".test.ts") && !e.endsWith(".d.ts")) out.push(path.relative(root, abs).split(path.sep).join("/"));
    }
  };
  walk(root);
  return out.sort();
}

function sweep(root = SWEEP_ROOT): Analysis & { files: string[]; sources: Map<string, string> } {
  const files = sweepFiles(root);
  const sources = new Map<string, string>();
  const all: Analysis = { home: [], gitSpawns: [], capable: [], dynamic: [], otherLiteral: [], configWrites: [], nsImports: [] };
  for (const f of files) {
    const src = readFileSync(path.join(root, f), "utf8");
    sources.set(f, src);
    const a = analyze(f, src);
    for (const k of Object.keys(all) as (keyof Analysis)[]) (all[k] as Site[]).push(...(a[k] as Site[]));
  }
  return { ...all, files, sources };
}

function groupOwners(sites: Site[]): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const s of sites) (out[s.file] ??= []).push(s.owner);
  for (const k of Object.keys(out)) out[k].sort();
  return out;
}

function mapDiff(expected: Record<string, string[]>, actual: Record<string, string[]>): string[] {
  const diffs: string[] = [];
  for (const f of [...new Set([...Object.keys(expected), ...Object.keys(actual)])].sort()) {
    const e = [...(expected[f] ?? [])];
    const a = [...(actual[f] ?? [])];
    const plus: string[] = [];
    for (const x of a) {
      const i = e.indexOf(x);
      if (i >= 0) e.splice(i, 1);
      else plus.push(x);
    }
    if (plus.length || e.length) diffs.push(`${f}: ${[...plus.map((x) => `+${x}`), ...e.map((x) => `-${x}`)].join(" ")}`);
  }
  return diffs;
}

const S = sweep();
const at = (s: Site) => `server/inngest/${s.file}:${s.line}`;

// =============================================================================
// Rows
// =============================================================================

describe("Guard 3 — cron spawn env git-config pin census (#12757)", () => {
  it("row 0: CRON_GIT_CONFIG_PIN is exactly the identity file and NOSYSTEM (no extra key such as GIT_CONFIG_COUNT)", () => {
    expect(CRON_GIT_CONFIG_PIN).toStrictEqual({ GIT_CONFIG_GLOBAL: AGENT_GIT_GLOBAL_CONFIG, GIT_CONFIG_NOSYSTEM: "1" });
    expect(Object.isFrozen(CRON_GIT_CONFIG_PIN)).toBe(true);
  });

  it("sweep dispatch: the walk reaches server/inngest/functions (non-empty, recursive, excludes tests and .mjs)", () => {
    expect(S.files).toContain(SUBSTRATE);
    expect(S.files.some((f) => f.endsWith(".test.ts") || f.endsWith(".mjs"))).toBe(false);
  });

  it("row 2: every HOME: literal under server/inngest ends with ...CRON_GIT_CONFIG_PIN", () => {
    const bad = S.home
      .filter((s) => !s.ok)
      .map((s) => `${at(s)} (${s.owner}) ${s.why}. Add import { CRON_GIT_CONFIG_PIN } from "@/server/host-git" and make it the LAST entry.`);
    expect(bad, bad.join("\n")).toEqual([]);
  });

  it("row 2: the HOME: literal population matches KNOWN_HOME_LITERALS (identity, not a count)", () => {
    const diffs = mapDiff(KNOWN_HOME_LITERALS, groupOwners(S.home));
    const pin = S.home.every((s) => s.ok) ? "OK" : "FAILED";
    expect(diffs, `new/removed HOME: literal(s): ${diffs.join("; ")}. Pin check: ${pin}. If you added a cron, update KNOWN_HOME_LITERALS.`).toEqual([]);
  });

  it("row 4: every call whose first argument is a git literal carries a pinned env (any callee)", () => {
    const bad = S.gitSpawns
      .filter((s) => !s.ok)
      .map((s) => `${at(s)} (${s.owner}) git spawn: ${s.why}. Pass env: { ...process.env, ...CRON_GIT_CONFIG_PIN } after any ...opts, or route it through spawnSimple.`);
    expect(bad, bad.join("\n")).toEqual([]);
  });

  it("row 4: the git-spawn population matches KNOWN_GIT_SPAWNS", () => {
    const diffs = mapDiff(KNOWN_GIT_SPAWNS, groupOwners(S.gitSpawns));
    expect(diffs, `new/removed git spawn(s): ${diffs.join("; ")}. Pin the new site, then update KNOWN_GIT_SPAWNS.`).toEqual([]);
  });

  it("row 4c: every git/gh/bash/sh/env literal is the command of a pinned spawn, or a named exclusion", () => {
    const excluded = (s: CapableSite) => GIT_CAPABLE_LITERAL_EXCLUSIONS.some((x) => x.file === s.file && s.text.includes(x.anchor));
    const bad = S.capable
      .filter((s) => !s.ok && !excluded(s))
      .map(
        (s) =>
          `bare "${s.word}" literal at ${at(s)} is not the first arg of a pinned spawn (${s.why}). Route it through spawnSimple or a helper that spreads CRON_GIT_CONFIG_PIN, or add {file, anchor, reason} to GIT_CAPABLE_LITERAL_EXCLUSIONS.`,
      );
    expect(bad, bad.join("\n")).toEqual([]);
  });

  it("row 4c: each exclusion has a reason and matches exactly one live hit (a stale entry fails)", () => {
    for (const x of GIT_CAPABLE_LITERAL_EXCLUSIONS) {
      expect(x.reason.trim(), `${x.file} ${x.anchor}`).not.toBe("");
      const hits = S.capable.filter((s) => s.file === x.file && s.text.includes(x.anchor));
      expect(hits.length, `exclusion ${x.file} "${x.anchor}" matches ${hits.length} hits`).toBe(1);
    }
  });

  it("row 4c: every child_process spawn with a non-literal command is in DYNAMIC_COMMAND_SPAWNS; the pinned ones are pinned", () => {
    const diffs = mapDiff(
      Object.fromEntries(Object.entries(DYNAMIC_COMMAND_SPAWNS).map(([f, m]) => [f, Object.keys(m).sort()])),
      groupOwners(S.dynamic),
    );
    expect(diffs, `new/removed dynamic-command spawn(s): ${diffs.join("; ")}`).toEqual([]);
    const bad = S.dynamic
      .filter((s) => DYNAMIC_COMMAND_SPAWNS[s.file]?.[s.owner] === "pinned" && !s.ok)
      .map((s) => `${at(s)} (${s.owner}) chokepoint spawn: ${s.why}. Spread ...CRON_GIT_CONFIG_PIN LAST in its env.`);
    expect(bad, bad.join("\n")).toEqual([]);
    for (const [f, m] of Object.entries(DYNAMIC_COMMAND_SPAWNS)) for (const [o, r] of Object.entries(m)) expect(r.trim(), `${f} ${o}`).not.toBe("");
  });

  it("row 4c: no child_process spawn of a literal command outside git/gh/bash/sh/env", () => {
    const bad = S.otherLiteral.map((s) => `${at(s)} (${s.owner}) ${s.why}: extend WORDS (and pin it) or route it through a pinned helper`);
    expect(bad, bad.join("\n")).toEqual([]);
  });

  it("row 4d: no post-construction write to a GIT_CONFIG_* key outside GIT_CONFIG_WRITE_EXCEPTIONS (exact)", () => {
    const actual: Record<string, string[]> = {};
    for (const s of S.configWrites) (actual[s.file] ??= []).push(s.why);
    for (const k of Object.keys(actual)) actual[k].sort();
    const diffs = mapDiff(GIT_CONFIG_WRITE_EXCEPTIONS, actual);
    expect(diffs, `GIT_CONFIG_* write(s) changed: ${diffs.join("; ")}. Pin by spreading CRON_GIT_CONFIG_PIN last; never assign GIT_CONFIG_* after the literal.`).toEqual([]);
  });

  it("row 4e: no namespace, default or whole-module handle on child_process under server/inngest (rows 4/4c track named imports only)", () => {
    expect(
      S.nsImports.map((x) => `${at(x)} ${x.text}`),
      "import the spawner by name (`import { spawn } from \"node:child_process\"`) so rows 4/4c can see the call; do not extend this test to allow a handle",
    ).toEqual([]);
  });

  it("row 4b: no non-test file under server/inngest retypes the identity-file path (import it instead)", () => {
    const bad = [...S.sources].filter(([, src]) => src.includes(RETYPED_PATH)).map(([f]) => `server/inngest/${f}`);
    expect(bad, `retyped identity-file path in: ${bad.join(", ")}. import { CRON_GIT_CONFIG_PIN } from "@/server/host-git".`).toEqual([]);
  });
});

// =============================================================================
// Walk self-tests and binding-not-name controls (synthetic sources through the same analyser)
// =============================================================================

const HDR = `import { spawn, execSync } from "node:child_process";\nimport { CRON_GIT_CONFIG_PIN } from "@/server/host-git";\n`;

describe("Guard 3 — walk self-tests (positive controls on synthetic source)", () => {
  it("finds a pinned HOME literal, an unpinned one, a pin-first one, and the shorthand form", () => {
    const a = analyze(
      "functions/x.ts",
      HDR +
        `function pinned() { return { PATH: "p", HOME: process.env.HOME, ...CRON_GIT_CONFIG_PIN }; }\n` +
        `function bare() { return { HOME: process.env.HOME, GH_TOKEN: "t" }; }\n` +
        `function first() { return { ...CRON_GIT_CONFIG_PIN, HOME: process.env.HOME, GIT_CONFIG_GLOBAL: "/tmp/x" }; }\n` +
        `function short(HOME: string) { return { HOME }; }\n`,
    );
    expect(a.home.map((s) => [s.owner, s.ok])).toEqual([
      ["pinned", true],
      ["bare", false],
      ["first", false],
      ["short", false],
    ]);
  });

  it("finds a git first-argument call; a git inside a // comment is not a hit; a git template with substitutions is reported", () => {
    const a = analyze(
      "functions/x.ts",
      HDR +
        `function c() { spawn("git", ["status"], { env: { ...process.env, ...CRON_GIT_CONFIG_PIN } }); }\n` +
        `// spawn("git", ["status"]);\n` +
        // A double-quoted host string, so the inner template literal needs no escaped backticks. The
        // env is present but unpinned, so the sweep must still report it (ok=false).
        "function t(u: string) { execSync(`git clone ${u}`, { env: process.env }); }\n",
    );
    expect(a.gitSpawns.map((s) => [s.owner, s.ok])).toEqual([["c", true]]);
    expect(a.capable.map((s) => [s.owner, s.word, s.ok])).toEqual([
      ["c", "git", true],
      ["t", "git", false],
    ]);
  });

  it("row 4c's sweep reports gh/bash/sh literals, a sh -c git payload, a GIT const, and accepts the one-hop and helper forms", () => {
    const a = analyze(
      "functions/x.ts",
      `import { spawn } from "node:child_process";\nimport { withCronGitConfigPin, CRON_GIT_CONFIG_PIN } from "@/server/host-git";\n` +
        `function buildSpawnEnv(t: string) { return { HOME: process.env.HOME, GH_TOKEN: t, ...CRON_GIT_CONFIG_PIN }; }\n` +
        `function ok1(t: string) { const ghEnv = buildSpawnEnv(t); spawn("gh", ["pr", "list"], { env: ghEnv }); }\n` +
        `function ok2(opts: { env: NodeJS.ProcessEnv }) { spawn("bash", ["s.sh"], { env: withCronGitConfigPin(opts.env) }); }\n` +
        `function bad1() { spawn("gh", ["pr", "list"]); }\n` +
        `function bad2(opts: { env: NodeJS.ProcessEnv }) { spawn("bash", ["s.sh"], { env: opts.env }); }\n` +
        `function bad3() { spawn("sh", ["-c", "git status"], { stdio: "ignore" }); }\n` +
        `function bad4() { const GIT = "git"; spawn(GIT, ["status"]); }\n`,
    );
    expect(a.capable.map((s) => [s.owner, s.word, s.ok])).toEqual([
      ["ok1", "gh", true],
      ["ok2", "bash", true],
      ["bad1", "gh", false],
      ["bad2", "bash", false],
      ["bad3", "sh", false],
      ["bad3", "git", false],
      ["bad4", "git", false],
    ]);
    // the GIT const is also a dynamic spawn the stored map does not know
    expect(a.dynamic.map((s) => s.owner)).toEqual(["bad4"]);
  });

  it("row 4 order check: a ...opts spread after env is a violation", () => {
    const a = analyze(
      "functions/x.ts",
      HDR + `function spawnGit(args: string[], opts?: { cwd?: string }) { spawn("git", args, { env: { ...process.env, ...CRON_GIT_CONFIG_PIN }, ...opts }); }\n`,
    );
    expect(a.gitSpawns.map((s) => [s.owner, s.ok, s.why])).toEqual([["spawnGit", false, expect.stringMatching(/spread comes after env/)]]);
  });

  it("row 4d: an env.GIT_CONFIG_GLOBAL write after a pinned literal is reported", () => {
    const a = analyze(
      "functions/x.ts",
      HDR + `function f() { const env = { ...process.env, ...CRON_GIT_CONFIG_PIN }; env.GIT_CONFIG_GLOBAL = "/tmp/x"; delete env["GIT_CONFIG_NOSYSTEM"]; spawn("git", [], { env }); }\n`,
    );
    expect(a.configWrites.map((s) => s.why)).toEqual(["f GIT_CONFIG_GLOBAL", "f delete GIT_CONFIG_NOSYSTEM"]);
  });
});

describe("Guard 3 — binding, not name (CTO H5): each planted look-alike FAILS", () => {
  it("a local `const CRON_GIT_CONFIG_PIN = {}` spread into a HOME literal is a violation", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      `const CRON_GIT_CONFIG_PIN = {};\nfunction buildSpawnEnv() { return { HOME: process.env.HOME, ...CRON_GIT_CONFIG_PIN }; }\n`,
    );
    expect(a.home.map((s) => s.ok)).toEqual([false]);
  });

  it("an import of the right name shadowed by a local declaration is a violation", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      HDR + `function buildSpawnEnv() { const CRON_GIT_CONFIG_PIN = {}; return { HOME: process.env.HOME, ...CRON_GIT_CONFIG_PIN }; }\n`,
    );
    expect(a.home.map((s) => s.ok)).toEqual([false]);
  });

  it("a local `function spawnSimple` does not count as the chokepoint", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      `import { spawn } from "node:child_process";\nfunction spawnSimple(cmd: string, args: string[]) { return spawn(cmd, args); }\nasync function clone() { await spawnSimple("git", ["clone", "x"]); }\n`,
    );
    expect(a.gitSpawns.map((s) => [s.owner, s.ok])).toEqual([["clone", false]]);
  });

  it('a "/usr/bin/git" literal with no env is a violation in rows 4 and 4c', () => {
    const a = analyze("functions/cron-planted.ts", `import { spawn } from "node:child_process";\nfunction f() { spawn("/usr/bin/git", ["status"]); }\n`);
    expect(a.gitSpawns.map((s) => s.ok)).toEqual([false]);
    expect(a.capable.map((s) => [s.word, s.ok])).toEqual([["git", false]]);
  });

  it("row 4e: a namespace import, a default import, a dynamic whole-module import and a require are each reported", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      `import * as cp from "node:child_process";\nimport cp2 from "child_process";\n` +
        `async function f() { const m = await import("node:child_process"); const r = require("child_process"); }\n` +
        `async function g(cmd: string) { require("node:child_process").spawn(cmd, []); (await import("child_process")).spawn(cmd, []); }\n`,
    );
    expect(a.nsImports).toHaveLength(6);
    // control: the destructured named form is tracked as a spawner, not a handle
    expect(analyze("functions/x.ts", `async function d() { const { spawn } = await import("node:child_process"); }\n`).nsImports).toEqual([]);
    // control: a named import is not a handle
    expect(analyze("functions/x.ts", HDR).nsImports).toEqual([]);
  });

  it("an import of CRON_GIT_CONFIG_PIN from a look-alike module is a violation", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      `import { CRON_GIT_CONFIG_PIN } from "@/server/host-git-lookalike";\nfunction buildSpawnEnv() { return { HOME: process.env.HOME, ...CRON_GIT_CONFIG_PIN }; }\n`,
    );
    expect(a.home.map((s) => s.ok)).toEqual([false]);
  });

  it("promisify(execFile) and a destructured await import() are both tracked as spawners", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      `import { execFile } from "node:child_process";\nimport { promisify } from "node:util";\nconst run = promisify(execFile);\n` +
        `async function p(cmd: string) { await run(cmd, []); }\n` +
        `async function d(cmd: string) { const { spawn } = await import("node:child_process"); spawn(cmd, []); }\n`,
    );
    expect(a.dynamic.map((s) => [s.owner, s.ok])).toEqual([
      ["p", false],
      ["d", false],
    ]);
  });

  it("a post-construction GIT_CONFIG_GLOBAL write to a value other than /dev/null does not count as a pin", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      HDR + `function f() { const env = { ...process.env }; env.GIT_CONFIG_GLOBAL = "/tmp/x"; env.GIT_CONFIG_NOSYSTEM = "1"; spawn("git", [], { env }); }\n`,
    );
    expect(a.gitSpawns.map((s) => s.ok)).toEqual([false]);
  });

  it("a same-file gitIsolatedEnv that does not pin /dev/null is not accepted", () => {
    const a = analyze(
      "functions/cron-planted.ts",
      HDR + `function gitIsolatedEnv() { return { ...process.env, GIT_CONFIG_NOSYSTEM: "1" }; }\nfunction f() { spawn("git", [], { env: gitIsolatedEnv() }); }\n`,
    );
    expect(a.gitSpawns.map((s) => s.ok)).toEqual([false]);
  });

  it("controls: the real import and the substrate's own spawnSimple are accepted", () => {
    const a = analyze(
      SUBSTRATE,
      HDR + `export function spawnSimple(cmd: string, args: string[]) { return spawn(cmd, args, { env: { ...process.env, ...CRON_GIT_CONFIG_PIN } }); }\nasync function c() { await spawnSimple("git", ["clone"]); }\n`,
    );
    expect(a.gitSpawns.map((s) => s.ok)).toEqual([true]);
    expect(a.dynamic.map((s) => [s.owner, s.ok])).toEqual([["spawnSimple", true]]);
  });
});

// =============================================================================
// Rows 5 / 5b — real git, the property end to end
// =============================================================================

function gitVersion(): [number, number] | null {
  const r = spawnSync("git", ["--version"], { encoding: "utf8", env: gitCleanEnv() as NodeJS.ProcessEnv });
  const m = /git version (\d+)\.(\d+)/.exec(r.stdout ?? "");
  return m ? [Number(m[1]), Number(m[2])] : null;
}

describe("Guard 3 — real git (rows 5, 5b)", () => {
  const dirs: string[] = [];
  afterAll(() => {
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });

  /** A HOME with planted global configs (both ~/.gitconfig and the XDG file) and a planted system config. */
  function plantedHome(): string {
    const H = mkdtempSync(path.join(tmpdir(), "cron-pin-home-"));
    dirs.push(H);
    writeFileSync(path.join(H, ".gitconfig"), `[user]\n\tname = planted\n[alias]\n\tprobe = !touch ${H}/fired\n`);
    mkdirSync(path.join(H, ".config/git"), { recursive: true });
    writeFileSync(path.join(H, ".config/git/config"), `[user]\n\tname = planted\n[alias]\n\tprobexdg = !touch ${H}/fired-xdg\n`);
    writeFileSync(path.join(H, "sys.gitconfig"), `[alias]\n\tsysprobe = !touch ${H}/fired-sys\n`);
    return H;
  }

  /**
   * The shared fixture env (ceiling, synthesized identity, every inherited GIT_* dropped) with
   * exactly the keys this row is ABOUT removed: GIT_CONFIG_GLOBAL (the pin under test; the helper
   * pins /dev/null, which would make both arms identical) and XDG_CONFIG_HOME (so git reads
   * $HOME/.config). GIT_CONFIG_NOSYSTEM is dropped only for the system-config arm.
   */
  function baseEnv(H: string, nosystem = true): Record<string, string> {
    const env = { ...gitFixtureEnv(H), HOME: H, LC_ALL: "C" } as Record<string, string>;
    delete env.GIT_CONFIG_GLOBAL;
    delete env.XDG_CONFIG_HOME;
    if (!nosystem) delete env.GIT_CONFIG_NOSYSTEM;
    return env;
  }

  const git = (H: string, env: Record<string, string>, args: string[], cwd = H) =>
    spawnSync("git", args, { cwd, env: env as NodeJS.ProcessEnv, encoding: "utf8", timeout: 20_000 });

  it("precheck: git >= 2.32 (GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM semantics)", () => {
    const v = gitVersion();
    expect(v, "git is not on PATH").not.toBeNull();
    const [maj, min] = v as [number, number];
    expect(maj > 2 || (maj === 2 && min >= 32), `git ${maj}.${min} is older than 2.32: an old git, not a code bug`).toBe(true);
  });

  it("row 5 control: without the pin, the planted global config is read and its aliases run", () => {
    const H = plantedHome();
    const env = baseEnv(H);
    const name = git(H, env, ["config", "--global", "--show-origin", "--get", "user.name"]);
    expect(name.stdout).toMatch(/planted/);
    expect(git(H, env, ["probe"]).status).toBe(0);
    expect(existsSync(path.join(H, "fired"))).toBe(true);
    expect(git(H, env, ["probexdg"]).status).toBe(0);
    expect(existsSync(path.join(H, "fired-xdg"))).toBe(true);
  });

  it("row 5 pinned arm: with ...CRON_GIT_CONFIG_PIN neither ~/.gitconfig nor ~/.config/git/config is read", () => {
    const H = plantedHome();
    const env = { ...baseEnv(H), ...CRON_GIT_CONFIG_PIN };
    expect(env.GIT_CONFIG_GLOBAL, "the pin did not set GIT_CONFIG_GLOBAL").toBe(AGENT_GIT_GLOBAL_CONFIG);
    const name = git(H, env, ["config", "--global", "--show-origin", "--get", "user.name"]);
    expect(`${name.stdout}${name.stderr}`, "the planted identity was read (the level that answered is shown)").not.toMatch(/planted/);
    const probe = git(H, env, ["probe"]);
    expect(probe.status).not.toBe(0);
    expect(probe.stderr).toMatch(/not a git command/);
    expect(existsSync(path.join(H, "fired"))).toBe(false);
    const xdg = git(H, env, ["probexdg"]);
    expect(xdg.status).not.toBe(0);
    expect(existsSync(path.join(H, "fired-xdg"))).toBe(false);
  });

  it("row 5 third arm: GIT_CONFIG_SYSTEM's planted alias runs without the pin and is absent with it (NOSYSTEM, behaviourally)", () => {
    const H = plantedHome();
    const sys = path.join(H, "sys.gitconfig");
    const control = { ...baseEnv(H, false), GIT_CONFIG_SYSTEM: sys };
    expect(git(H, control, ["sysprobe"]).status, "control: the system alias did not run, so this arm proves nothing").toBe(0);
    expect(existsSync(path.join(H, "fired-sys"))).toBe(true);
    rmSync(path.join(H, "fired-sys"));
    const pinned = { ...baseEnv(H, false), GIT_CONFIG_SYSTEM: sys, ...CRON_GIT_CONFIG_PIN };
    const r = git(H, pinned, ["sysprobe"]);
    expect(r.status).not.toBe(0);
    expect(existsSync(path.join(H, "fired-sys"))).toBe(false);
  });

  it("row 5b (characterisation): with the pin, $HOME/.config/git/ignore is STILL read (XDG residual; Guard 1 is its barrier)", () => {
    const H = mkdtempSync(path.join(tmpdir(), "cron-pin-xdg-"));
    dirs.push(H);
    const repo = path.join(H, "repo");
    mkdirSync(repo);
    const env = { ...baseEnv(H), GIT_CEILING_DIRECTORIES: H, ...CRON_GIT_CONFIG_PIN };
    expect(git(H, env, ["init", "-q"], repo).status).toBe(0);
    writeFileSync(path.join(repo, "secret.txt"), "x");
    const before = git(H, env, ["status", "--porcelain", "--ignored"], repo);
    expect(before.stdout, "control: secret.txt must be untracked before the ignore file exists").toMatch(/^\?\? secret\.txt$/m);
    mkdirSync(path.join(H, ".config/git"), { recursive: true });
    writeFileSync(path.join(H, ".config/git/ignore"), "secret.txt\n");
    const after = git(H, env, ["status", "--porcelain", "--ignored"], repo);
    expect(after.stdout, "residual closed by git; update ADR-033").toMatch(/^!! secret\.txt$/m);
  });
});

// =============================================================================
// Row 6 — the probes (real implementation; setup-node.ts mocks them for every other suite)
// =============================================================================

describe("Guard 3 — row 6: host-git probes and withCronGitConfigPin (vi.importActual, temp paths only)", () => {
  const dirs: string[] = [];
  afterAll(() => {
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  const load = () => vi.importActual<typeof import("@/server/host-git")>("@/server/host-git");

  it("agentGitConfigReadable: true on a readable temp file, false on a missing path", async () => {
    const { agentGitConfigReadable } = await load();
    const d = mkdtempSync(path.join(tmpdir(), "cron-pin-probe-"));
    dirs.push(d);
    const f = path.join(d, "agent.gitconfig");
    writeFileSync(f, "[user]\n\tname = x\n");
    expect(agentGitConfigReadable(f)).toBe(true);
    expect(agentGitConfigReadable(path.join(d, "missing"))).toBe(false);
  });

  it("xdgGitResidualPresent: false on an empty home, false when .config/git is only a directory, true once ignore is a file", async () => {
    const { xdgGitResidualPresent } = await load();
    const h = mkdtempSync(path.join(tmpdir(), "cron-pin-xdghome-"));
    dirs.push(h);
    expect(xdgGitResidualPresent(h)).toBe(false);
    mkdirSync(path.join(h, ".config/git"), { recursive: true });
    expect(xdgGitResidualPresent(h)).toBe(false);
    writeFileSync(path.join(h, ".config/git/ignore"), "x\n");
    expect(xdgGitResidualPresent(h)).toBe(true);
    rmSync(path.join(h, ".config/git/ignore"));
    writeFileSync(path.join(h, ".config/git/attributes"), "x\n");
    expect(xdgGitResidualPresent(h)).toBe(true);
  });

  it("withCronGitConfigPin forces the pin on a pin-less env and over /tmp/evil, and keeps a caller's /dev/null", async () => {
    const { withCronGitConfigPin } = await load();
    expect(withCronGitConfigPin({ PATH: "/bin" } as unknown as NodeJS.ProcessEnv)).toStrictEqual({ PATH: "/bin", GIT_CONFIG_GLOBAL: AGENT_GIT_GLOBAL_CONFIG, GIT_CONFIG_NOSYSTEM: "1" });
    expect(withCronGitConfigPin({ PATH: "/bin", GIT_CONFIG_GLOBAL: "/tmp/evil", GIT_CONFIG_NOSYSTEM: "0" } as unknown as NodeJS.ProcessEnv)).toStrictEqual({
      PATH: "/bin",
      GIT_CONFIG_GLOBAL: AGENT_GIT_GLOBAL_CONFIG,
      GIT_CONFIG_NOSYSTEM: "1",
    });
    expect(withCronGitConfigPin({ PATH: "/bin", GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "0" } as unknown as NodeJS.ProcessEnv)).toStrictEqual({
      PATH: "/bin",
      GIT_CONFIG_GLOBAL: "/dev/null",
      GIT_CONFIG_NOSYSTEM: "1",
    });
  });
});
