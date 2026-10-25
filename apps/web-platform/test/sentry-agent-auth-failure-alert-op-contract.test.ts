import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";
import { stripComments as stripTsComments } from "./helpers/strip-comments";
import { CLI_AUTH_FAILURE_REPLIES, SDK_API_KEY_SOURCES } from "../server/claude-error-signatures";

// Cross-artifact contract (Guard 1) between the auth-failure emit in server/agent-auth-failure.ts and the Sentry
// rule `agent_auth_failure` that routes it. Before this rule the Claude CLI's "Not logged in · Please run /login"
// reply reached the user with nothing in Sentry or Better Stack (#10455, #10548). Chain proven here without firing
// a production event:
//   auth-failure stream message -> reportSilentFallback(null, { feature, op, ... }) -> live rule -> email action.
// The emit MUST use the message path (first argument the literal `null`): an Error first argument is mirrored by the
// pino logger as `feature=pino-mirror` and the tagged capture is deduplicated behind it (#8629 class), so a
// tag-filtered rule could never match. The real-path proof lives in agent-auth-failure-sentry-path.test.ts; the
// payload allowlist and the secret canary (Guard 2) live there too.
// Emit sites and rule are both parsed from source (comments stripped), so a commented-out rule or emit cannot satisfy
// a check; the checks are pure functions over text so the harness self-tests below can feed fixtures.
// Integrity is anchored OUTSIDE this commit by scripts/sentry-alert-reference-gate.sh (the plan_pr job holds
// alert-reference.json equal to the Terraform PLAN) and by the daily live-fidelity probe; this test only proves the
// three committed artifacts agree with each other.

const OP = "cli-auth-failure";
const FEATURE = "agent-auth";
const RULE = "agent_auth_failure";
const REFERENCE_KEY = "agent-auth-failure";
const RULE_NAME = "agent-auth-failure";

const here = dirname(fileURLToPath(import.meta.url));
// Every root that can call the server-side reporter: `reportSilentFallback` is also called from app/ route handlers and lib/.
const sourceRoots = ["server", "lib", "app"].map((d) => join(here, "..", d));
const sentryDir = join(here, "../infra/sentry");

/** HCL: block comments and whole-line `#` / `//` comments removed before any match. */
export const stripHcl = (s: string) =>
  s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

const SOURCE_RE = /\.(?:ts|tsx|mts|js|jsx|mjs|cjs)$/;
const TEST_RE = /\.(?:test|spec)\.[a-z]+$/;
function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return name === "__tests__" ? [] : walk(p);
    return SOURCE_RE.test(p) && !TEST_RE.test(p) ? [p] : [];
  });
}

/** The `{ ... }` literal enclosing `index` (nearest unmatched `{` backwards, its match forwards). */
function enclosingObject(src: string, index: number): { text: string; start: number } {
  let depth = 0;
  let open = -1;
  for (let i = index - 1; i >= 0; i--) {
    if (src[i] === "}") depth++;
    else if (src[i] === "{") {
      if (depth === 0) {
        open = i;
        break;
      }
      depth--;
    }
  }
  if (open < 0) throw new Error("fixture: a literal op/feature is not inside an object literal");
  depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return { text: src.slice(open, i + 1), start: open };
  }
  throw new Error("fixture: unterminated object literal around a literal op/feature");
}

/** Occurrences of the feature value as a whole quoted string, in any position (value, constant, quoted key's value, array). */
export function featureTokenCount(src: string): number {
  return [...src.matchAll(new RegExp(`(["'\`])${FEATURE}\\1`, "g"))].length;
}

export interface EmitSite {
  file: string;
  feature: string;
  op: string;
  callee: string | null;
  firstArgNull: boolean;
  messageLiteral: boolean;
}

/** Every object literal (in one comment-stripped source) that carries a literal `feature: "agent-auth"`. */
export function featureSitesIn(file: string, src: string): EmitSite[] {
  const sites: EmitSite[] = [];
  const seen = new Set<number>();
  for (const m of src.matchAll(new RegExp(`\\bfeature:\\s*(["'\`])${FEATURE}\\1`, "g"))) {
    const obj = enclosingObject(src, m.index ?? 0);
    if (seen.has(obj.start)) continue;
    seen.add(obj.start);
    const ops = [...obj.text.matchAll(/\bop:\s*(["'`])([^"'`]+)\1/g)];
    if (ops.length !== 1) throw new Error(`fixture: ${file} needs exactly one literal op next to feature ${FEATURE}, found ${ops.length}`);
    const before = src.slice(0, obj.start);
    const call = before.match(/\b(\w+)\(\s*(null|[^,()]+)\s*,\s*$/);
    const msg = obj.text.match(/\bmessage:\s*(["'`])([^"'`]*)\1/);
    sites.push({
      file,
      feature: FEATURE,
      op: ops[0][2],
      callee: call ? call[1] : null,
      firstArgNull: !!call && call[2] === "null",
      // A constant message groups every event into ONE Sentry issue; an interpolated one splits the outage.
      messageLiteral: !!msg && !msg[2].includes("${") && !/\bmessage:\s*`[^`]*\$\{/.test(obj.text),
    });
  }
  return sites;
}

/** Problems with the rule in (comment-stripped) HCL; empty array = compliant. */
export function ruleProblems(hclRaw: string, allHclRaw = hclRaw): string[] {
  const hcl = stripHcl(hclRaw);
  const m = hcl.match(new RegExp(`resource\\s+"sentry_alert"\\s+"${RULE}"\\s*\\{[\\s\\S]*?\\n\\}`));
  if (!m) return [`no live sentry_alert "${RULE}" block`];
  const block = m[0];
  const bad: string[] = [];
  const tagged = [...block.matchAll(/tagged_event\s*=\s*\{([^}]*)\}/g)].map((x) => {
    const g = (k: string) => x[1].match(new RegExp(`\\b${k}\\s*=\\s*"([^"]+)"`))?.[1];
    return { key: g("key"), match: g("match"), value: g("value") };
  });
  const keys = tagged.map((t) => t.key).sort();
  if (JSON.stringify(keys) !== JSON.stringify(["feature", "op"])) bad.push(`tag conditions must be exactly feature+op, got ${keys.join(",")}`);
  const f = tagged.find((t) => t.key === "feature");
  const o = tagged.find((t) => t.key === "op");
  if (!f || f.match !== "eq" || f.value !== FEATURE) bad.push(`feature filter must be eq ${FEATURE}`);
  if (!o || o.match !== "eq" || o.value !== OP) bad.push(`op filter must be eq ${OP}`);
  if (!/^\s*logic_type\s*=\s*"all"/m.test(block)) bad.push('logic_type must be "all"');
  if (!/email\s*=\s*\{\s*target_type\s*=\s*"issue_owners"\s*,\s*fallthrough_type\s*=\s*"ActiveMembers"\s*\}/.test(block)) {
    bad.push("missing email action issue_owners + ActiveMembers");
  }
  if (/fallthrough_type\s*=\s*"NoOne"/.test(block)) bad.push("fallthrough NoOne");
  if (!/^\s*enabled\s*=\s*true/m.test(block)) bad.push("rule not enabled");
  const trig = block.match(/trigger_conditions\s*=\s*\[([\s\S]*?)\n\s*\]/);
  if (!trig || !/event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h"\s*,\s*value\s*=\s*0\s*\}/.test(trig[1])) {
    bad.push("trigger must be event_frequency_count 1h value 0");
  }
  const freq = block.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
  if (!freq) bad.push("no frequency_minutes");
  else {
    const all = [...stripHcl(allHclRaw).matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].map((x) => x[1]);
    if (all.filter((v) => v === freq[1]).length !== 1) bad.push(`frequency_minutes ${freq[1]} not unique in the root`);
  }
  if (!/^\s*monitor_ids\s*=\s*\[data\.sentry_project_issue_stream_monitor\.web_platform\.id\]/m.test(block)) bad.push("monitor_ids");
  if (!/ignore_changes\s*=\s*\[environment\]/.test(block)) bad.push("ignore_changes must be [environment]");
  return bad;
}

/** The rule's `frequency_minutes` as the reference must carry it (null when the block is absent). */
export function ruleFrequency(hclRaw: string): number | null {
  const m = stripHcl(hclRaw).match(new RegExp(`resource\\s+"sentry_alert"\\s+"${RULE}"\\s*\\{[\\s\\S]*?\\n\\}`));
  const f = m?.[0].match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
  return f ? Number(f[1]) : null;
}

/** What the committed alert-reference.json entry must equal, built from the rule's own constants. */
export function expectedReferenceEntry(frequency: number, detectorIds: string[]) {
  return {
    actionFilters: [
      {
        actions: [{ fallthroughType: "ActiveMembers", targetIdentifier: null, targetType: "issue_owners", type: "email" }],
        conditions: [
          { comparison: { key: "feature", match: "eq", value: FEATURE }, type: "tagged_event" },
          { comparison: { key: "op", match: "eq", value: OP }, type: "tagged_event" },
        ],
        logicType: "all",
      },
    ],
    detectorIds,
    enabled: true,
    frequency,
    name: RULE_NAME,
    triggerConditions: [{ comparison: { interval: "1h", value: 0 }, type: "event_frequency_count" }],
    triggerLogicType: "single",
  };
}

const tfFiles = readdirSync(sentryDir).filter((f) => f.endsWith(".tf"));
const allTf = tfFiles.map((f) => readFileSync(join(sentryDir, f), "utf8")).join("\n");
const issueAlertsTf = readFileSync(join(sentryDir, "issue-alerts.tf"), "utf8");
const reference = JSON.parse(readFileSync(join(sentryDir, "alert-reference.json"), "utf8")) as Record<string, unknown>;
// Walked and comment-stripped ONCE per file (the strip is the slow part, and several cases read the result).
let serverSourcesCache: Array<{ file: string; src: string }> | undefined;
// Comment-stripping parses every file (about 3 s for the roots); it only blanks characters, so it can never CREATE a token.
// A file whose raw text has neither token therefore counts 0 stripped or not, and is kept unparsed (the floors still count it).
const TOKEN_PREFILTER = new RegExp(`${FEATURE}|${OP}`);
const serverSources = () =>
  (serverSourcesCache ??= sourceRoots
    .flatMap((root) => walk(root))
    .map((file) => {
      const raw = readFileSync(file, "utf8");
      return { file, src: TOKEN_PREFILTER.test(raw) ? stripTsComments(raw, file) : raw };
    }));
const featureSites = () => serverSources().flatMap(({ file, src }) => featureSitesIn(file, src));

const RULE_FIXTURE = `
resource "sentry_alert" "${RULE}" {
  organization      = var.sentry_org
  name              = "${RULE_NAME}"
  enabled           = true
  frequency_minutes = 71
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]
  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]
  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "op", match = "eq", value = "${OP}" } },
        { tagged_event = { key = "feature", match = "eq", value = "${FEATURE}" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]
  lifecycle {
    ignore_changes = [environment]
  }
}
`;

describe("agent-auth-failure — emit site / rule contract", () => {
  it("the server walk is non-vacuous and the emit is found by scanning it (floors)", () => {
    // A walk that found nothing would make every later case pass over an empty set.
    expect(serverSources().length).toBeGreaterThanOrEqual(200);
    expect(serverSources().some(({ file }) => /[\\/]app[\\/]/.test(file)), "app/ is walked").toBe(true);
    expect(serverSources().some(({ file }) => /[\\/]lib[\\/]/.test(file)), "lib/ is walked").toBe(true);
    expect(featureSites().length).toBeGreaterThanOrEqual(1);
  });

  it("the SET of ops emitted under feature agent-auth is exactly {cli-auth-failure} (a second op or emit file goes red)", () => {
    const ops = [...new Set(featureSites().map((s) => s.op))].sort();
    expect(ops).toEqual([OP]);
    const files = [...new Set(featureSites().map((s) => s.file))];
    expect(files, `emit files: ${files.join(", ")}`).toHaveLength(1);
    expect(files[0]).toMatch(/server[\\/]agent-auth-failure\.ts$/);
  });

  it("every occurrence of the op token is a literal emit site (no constant or indirection hides one)", () => {
    const literal = featureSites().filter((s) => s.op === OP).length;
    const perFile: string[] = [];
    let tokens = 0;
    for (const { file, src } of serverSources()) {
      const n = [...src.matchAll(new RegExp(OP, "g"))].length;
      tokens += n;
      if (n > 0) perFile.push(`${file}=${n}`);
    }
    expect(tokens, `token counts per file: ${perFile.join(", ")}`).toBe(literal);
  });

  it("every quoted occurrence of the feature token is a literal emit site (no constant, quoted key or other file hides one)", () => {
    const literal = featureSites().length;
    const perFile: string[] = [];
    let tokens = 0;
    for (const { file, src } of serverSources()) {
      const n = featureTokenCount(src);
      tokens += n;
      if (n > 0) perFile.push(`${file}=${n}`);
    }
    expect(tokens, `quoted "${FEATURE}" counts per file: ${perFile.join(", ")}`).toBe(literal);
  });

  it("every emit site is reportSilentFallback(null, ...) (message path, level error) with a constant message", () => {
    for (const s of featureSites()) {
      // An Error first argument is deduplicated behind the pino mirror capture (#8629 class); warnSilentFallback is level warning.
      expect(s.callee, `${s.file} callee`).toBe("reportSilentFallback");
      expect(s.firstArgNull, `${s.file} must call reportSilentFallback(null, ...)`).toBe(true);
      expect(s.messageLiteral, `${s.file} message must be a constant literal (one issue per outage)`).toBe(true);
    }
  });

  it("the live rule routes it: feature eq + op eq, email to a person, rate trigger 0/1h, unique frequency", () => {
    expect(ruleProblems(issueAlertsTf, allTf)).toEqual([]);
    expect(tfFiles).toContain("issue-alerts.tf");
  });

  it("alert-reference.json carries the matching entry, field for field", () => {
    const masked = reference["masked-dir-precreate-failed"] as { detectorIds: string[] } | undefined;
    // The detector id is the web-platform issue-stream monitor; derive it from a sibling rule that uses the same monitor_ids.
    expect(masked?.detectorIds, "sibling reference entry to derive detectorIds from").toBeTruthy();
    const freq = ruleFrequency(issueAlertsTf);
    expect(freq, "rule frequency_minutes").not.toBeNull();
    expect(reference[REFERENCE_KEY]).toEqual(expectedReferenceEntry(freq!, masked!.detectorIds));
  });

  it("the README is the one decode copy: it names every payload key, cli_key_source value and match_kind, and the .tf points at it", () => {
    const readme = readFileSync(join(sentryDir, "README.md"), "utf8");
    const section = readme.slice(readme.indexOf("### Diagnostic rule: `agent-auth-failure`"), readme.indexOf("ADR: [ADR-031"));
    expect(section.length, "README diagnostic section").toBeGreaterThan(1000);
    const keys = ["runner", "credential_scheme", "auth_env_present", "auth_mode", "cli_key_source", "seccomp_artifact", "has_egress", "sandbox", "outer_wrap", "match_kind"];
    for (const k of keys) expect(section, `payload key ${k}`).toContain(`\`${k}`);
    for (const v of SDK_API_KEY_SOURCES) expect(section, `cli_key_source ${v}`).toContain(v === "none" ? "cli_key_source=none" : `\`${v}\``);
    for (const { kind } of CLI_AUTH_FAILURE_REPLIES) expect(section, `match_kind ${kind}`).toContain(`\`${kind}\``);
    expect(section).toContain("`structured`");
    // The responder contract: resolve (never archive) the shared issue, and the absolute fallback date.
    expect(section).toMatch(/never archive or ignore it/);
    expect(section).toContain("2026-11-30");
    // The table is not restated in the .tf (a second copy is how the two disagreed).
    expect(issueAlertsTf).not.toMatch(/DECODE KEY \(read the tags/);
    expect(issueAlertsTf).toMatch(/README\.md[^\n]*one copy of the tag decode table/);
  });

  it("the removal checklist lives where the README and the .tf say it does", () => {
    const owner = readFileSync(join(here, "../server/agent-auth-mode.ts"), "utf8");
    expect(owner).toContain("REMOVAL CHECKLIST");
    const readme = readFileSync(join(sentryDir, "README.md"), "utf8");
    expect(readme).toMatch(/removal checklist in the header of `server\/agent-auth-mode\.ts`/);
    expect(issueAlertsTf).toMatch(/removal checklist is in the header of server\/agent-auth-mode\.ts/);
    for (const text of [readme, issueAlertsTf]) expect(text).not.toMatch(/checklist (?:is )?in the header of (?:`)?server\/agent-auth-failure\.ts/);
    // Every file the checklist names exists (a rename leaves a dangling item).
    for (const f of ["server/agent-auth-failure.ts", "server/claude-code-message-translator.ts", "test/agent-sandbox-seccomp-selector.test.ts"]) {
      expect(owner, f).toContain(f.split("/").pop());
      expect(() => readFileSync(join(here, "..", f), "utf8"), f).not.toThrow();
    }
  });

  it("the reference file stays key-sorted (jq -S) so the plan-projection gate diff is a no-op", () => {
    const raw = readFileSync(join(sentryDir, "alert-reference.json"), "utf8");
    const keys = Object.keys(JSON.parse(raw));
    expect(keys).toEqual([...keys].sort());
  });
});

describe("agent-auth-failure — harness self-tests (mutation rows)", () => {
  it("the compliant fixture passes", () => {
    expect(ruleProblems(RULE_FIXTURE)).toEqual([]);
  });

  it("MUST-PASS non-canonical: the two tag conditions in the opposite order still pass", () => {
    const opLine = `        { tagged_event = { key = "op", match = "eq", value = "${OP}" } },\n`;
    const featureLine = `        { tagged_event = { key = "feature", match = "eq", value = "${FEATURE}" } },\n`;
    expect(RULE_FIXTURE).toContain(opLine + featureLine);
    const reordered = RULE_FIXTURE.replace(opLine + featureLine, featureLine + opLine);
    expect(reordered).not.toBe(RULE_FIXTURE);
    expect(reordered.indexOf('key = "feature"')).toBeLessThan(reordered.indexOf('key = "op"'));
    expect(ruleProblems(reordered)).toEqual([]);
  });

  it("MUST-PASS non-canonical: a different (unique) frequency still passes", () => {
    const other = RULE_FIXTURE.replace("frequency_minutes = 71", "frequency_minutes = 99");
    expect(other).not.toBe(RULE_FIXTURE);
    expect(ruleProblems(other)).toEqual([]);
  });

  it("a commented-out rule is not live", () => {
    const commented = RULE_FIXTURE.split("\n").map((l) => `# ${l}`).join("\n");
    expect(ruleProblems(commented)).toEqual([`no live sentry_alert "${RULE}" block`]);
    expect(ruleProblems(`/*${RULE_FIXTURE}*/`)).toEqual([`no live sentry_alert "${RULE}" block`]);
  });

  it("disabling the rule, dropping the op filter, the feature filter or the email action, or NoOne fallthrough goes red", () => {
    const disabled = RULE_FIXTURE.replace("enabled           = true", "enabled           = false");
    expect(disabled).not.toBe(RULE_FIXTURE);
    expect(ruleProblems(disabled)).toContain("rule not enabled");
    const noOp = RULE_FIXTURE.replace(/\s*\{ tagged_event = \{ key = "op"[^\n]*\n/, "\n");
    expect(ruleProblems(noOp).length).toBeGreaterThan(0);
    const noFeature = RULE_FIXTURE.replace(/\s*\{ tagged_event = \{ key = "feature"[^\n]*\n/, "\n");
    expect(ruleProblems(noFeature).length).toBeGreaterThan(0);
    const noEmail = RULE_FIXTURE.replace(/\{ email = [^\n]*\n/, "");
    expect(ruleProblems(noEmail).length).toBeGreaterThan(0);
    const noOne = RULE_FIXTURE.replace('fallthrough_type = "ActiveMembers"', 'fallthrough_type = "NoOne"');
    expect(ruleProblems(noOne).length).toBeGreaterThan(0);
    const wrongOp = RULE_FIXTURE.replace(`value = "${OP}"`, `value = "${OP}-x"`);
    expect(ruleProblems(wrongOp).length).toBeGreaterThan(0);
  });

  it("a third tag condition goes red (the extractor requires exactly feature and op)", () => {
    const extra = RULE_FIXTURE.replace(
      /(\{ tagged_event = \{ key = "feature"[^\n]*\n)/,
      `$1        { tagged_event = { key = "runner", match = "eq", value = "legacy" } },\n`,
    );
    expect(extra).not.toBe(RULE_FIXTURE);
    expect(ruleProblems(extra).join(" ")).toMatch(/exactly feature\+op/);
  });

  it("a frequency_minutes shared with another rule goes red", () => {
    const other = `resource "sentry_alert" "other" {\n  frequency_minutes = 71\n}\n`;
    expect(ruleProblems(RULE_FIXTURE, RULE_FIXTURE + other)).toEqual(["frequency_minutes 71 not unique in the root"]);
  });

  const SITE = (callee: string, first: string, extra = "", msg = `message: "agent-auth: constant"`, feature = FEATURE, op = OP) =>
    `function f(payload) { ${callee}(${first}, {\n feature: "${feature}",\n op: "${op}",\n ${msg},\n tags: payload,\n extra: { ...payload }${extra} }); }`;

  it("emit-site derivation: compliant passes; Error first arg, warn callee, interpolated message, renamed op each go red", () => {
    const ok = featureSitesIn("a.ts", SITE("reportSilentFallback", "null"));
    expect(ok).toEqual([{ file: "a.ts", feature: FEATURE, op: OP, callee: "reportSilentFallback", firstArgNull: true, messageLiteral: true }]);
    expect(featureSitesIn("a.ts", SITE("reportSilentFallback", "err"))[0].firstArgNull).toBe(false);
    expect(featureSitesIn("a.ts", SITE("reportSilentFallback", "new Error(x)"))[0].firstArgNull).toBe(false);
    expect(featureSitesIn("a.ts", SITE("warnSilentFallback", "null"))[0].callee).toBe("warnSilentFallback");
    expect(featureSitesIn("a.ts", SITE("reportSilentFallback", "null", "", "message: `agent-auth: ${kind}`"))[0].messageLiteral).toBe(false);
    expect(featureSitesIn("a.ts", SITE("reportSilentFallback", "null", "", `message: "m"`, FEATURE, `${OP}-x`))[0].op).toBe(`${OP}-x`);
  });

  it("MUST-PASS non-canonical: extra keys in another order still pass", () => {
    const reordered = `function f(payload) { reportSilentFallback(null, {\n extra: { ...payload },\n tags: payload,\n message: "agent-auth: constant",\n op: "${OP}",\n feature: "${FEATURE}" }); }`;
    expect(featureSitesIn("a.ts", reordered)).toEqual([
      { file: "a.ts", feature: FEATURE, op: OP, callee: "reportSilentFallback", firstArgNull: true, messageLiteral: true },
    ]);
  });

  it("the extractor sees EVERY site, not only the first (two sites in one source yield two)", () => {
    // Mutating the extractor to stop after the first site must fail THIS row: a second, non-compliant site hides behind a compliant first.
    const two = SITE("reportSilentFallback", "null") + "\n" + SITE("reportSilentFallback", "err", "", `message: "m"`, FEATURE, "other-op");
    const sites = featureSitesIn("a.ts", two);
    expect(sites).toHaveLength(2);
    expect(sites.map((s) => s.op)).toEqual([OP, "other-op"]);
    expect(sites[1].firstArgNull).toBe(false);
  });

  it("an emit hidden behind a constant has zero literal sites but a non-zero token count (the token-count case reds)", () => {
    const hidden = `const OPNAME = "${OP}"; function f() { reportSilentFallback(null, { feature: "${FEATURE}", op: OPNAME, message: "m" }); }`;
    expect(() => featureSitesIn("a.ts", hidden)).toThrow(/exactly one literal op/);
    expect([...hidden.matchAll(new RegExp(OP, "g"))].length).toBe(1);
  });

  it("the feature token is counted wherever it hides: a constant, a quoted key and a computed spread each exceed the literal sites", () => {
    const viaConst = `const F = "${FEATURE}"; function f() { reportSilentFallback(null, { feature: F, op: "${OP}", message: "m" }); }`;
    expect(featureSitesIn("a.ts", viaConst)).toHaveLength(0);
    expect(featureTokenCount(viaConst)).toBe(1);
    const quotedKey = `function f() { reportSilentFallback(null, { "feature": "${FEATURE}", op: "${OP}", message: "m" }); }`;
    expect(featureSitesIn("a.ts", quotedKey)).toHaveLength(0);
    expect(featureTokenCount(quotedKey)).toBe(1);
    const spread = `const base = { feature: "${FEATURE}", op: "${OP}", message: "m" }; function f() { reportSilentFallback(null, { ...base }); }`;
    expect(featureSitesIn("a.ts", spread)).toHaveLength(1);
    expect(featureTokenCount(spread)).toBe(1);
    expect(featureTokenCount(`import x from "./${FEATURE}-env-vars";`)).toBe(0);
  });

  it("the reference expectation is sensitive: a changed frequency, op value or enabled flag differs", () => {
    const good = expectedReferenceEntry(40, ["1"]);
    expect(expectedReferenceEntry(41, ["1"])).not.toEqual(good);
    const badOp = JSON.parse(JSON.stringify(good));
    badOp.actionFilters[0].conditions[1].comparison.value = "other";
    expect(badOp).not.toEqual(good);
    expect({ ...good, enabled: false }).not.toEqual(good);
  });

  it("ruleFrequency reads the rule's own frequency and ignores other rules", () => {
    expect(ruleFrequency(RULE_FIXTURE)).toBe(71);
    expect(ruleFrequency(`resource "sentry_alert" "other" {\n  frequency_minutes = 9\n}\n`)).toBeNull();
  });

  it("the HCL comment strip is load-bearing: without it a commented rule would look live", () => {
    const commented = RULE_FIXTURE.split("\n").map((l) => `# ${l}`).join("\n");
    const noStrip = commented.replace(/^# /gm, "");
    // The unstripped text matches the block; the stripped text does not.
    expect(new RegExp(`resource\\s+"sentry_alert"\\s+"${RULE}"`).test(noStrip)).toBe(true);
    expect(new RegExp(`resource\\s+"sentry_alert"\\s+"${RULE}"`).test(stripHcl(commented))).toBe(false);
  });
});
