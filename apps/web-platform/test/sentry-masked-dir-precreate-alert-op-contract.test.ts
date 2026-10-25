import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";
import { stripComments as stripTsComments } from "./helpers/strip-comments";

// Cross-artifact contract (Guard 1) between the pre-create failure emit in
// server/agent-runner-sandbox-config.ts and the Sentry rule `masked_dir_precreate_failed` that routes it.
// Before this rule a failed `mkdirSync` of a masked dir (cross-tenant read channel left unmasked) was a Sentry
// error event with nobody behind it. Chain proven here without firing a production event:
//   forced failure -> reportSilentFallback(null, { feature, op, tags.dir_kind }) -> live rule -> email action.
// The emit MUST use the message path (first argument the literal `null`): an Error first argument is mirrored by
// the pino logger as `feature=pino-mirror` and the tagged capture is deduplicated behind it (#8629 class), so a
// tag-filtered rule could never match. The real-path proof lives in agent-sandbox-precreate-sentry-path.test.ts.
// Emit sites and rule are both parsed from source (comments stripped), so a commented-out rule or emit cannot
// satisfy a check; the checks are pure functions over text so the harness self-tests below can feed fixtures.

const OP = "masked-dir-precreate";
const FEATURE = "agent-sandbox";
const KINDS = ["peer-socket", "session-tmp", "transcript"];
const RULE = "masked_dir_precreate_failed";

const here = dirname(fileURLToPath(import.meta.url));
const serverDir = join(here, "../server");
const sentryDir = join(here, "../infra/sentry");

/** HCL: block comments and whole-line `#` / `//` comments removed before any match. */
export const stripHcl = (s: string) =>
  s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/)/.test(l))
    .join("\n");

const SOURCE_RE = /\.(?:ts|tsx|mts)$/;
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
  if (open < 0) throw new Error(`fixture: an op "${OP}" is not inside an object literal`);
  depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return { text: src.slice(open, i + 1), start: open };
  }
  throw new Error(`fixture: unterminated object literal around an op "${OP}"`);
}

export interface EmitSite {
  file: string;
  feature: string;
  firstArgNull: boolean;
  dirKindExpr: string | null;
}

/** Every literal `op: "masked-dir-precreate"` emit in one (comment-stripped) source. */
export function emitSitesIn(file: string, src: string): EmitSite[] {
  const sites: EmitSite[] = [];
  for (const m of src.matchAll(new RegExp(`\\bop:\\s*(["'\`])${OP}\\1`, "g"))) {
    const obj = enclosingObject(src, m.index ?? 0);
    const feats = [...obj.text.matchAll(/\bfeature:\s*(["'`])([^"'`]+)\1/g)];
    if (feats.length !== 1) throw new Error(`fixture: ${file} needs exactly one literal feature in the emit object, found ${feats.length}`);
    const before = src.slice(0, obj.start);
    const dk = obj.text.match(/\btags:\s*\{[^}]*\bdir_kind:\s*([^,}\s]+)/);
    sites.push({
      file,
      feature: feats[0][2],
      firstArgNull: /\breportSilentFallback\(\s*null\s*,\s*$/.test(before),
      dirKindExpr: dk ? dk[1] : null,
    });
  }
  return sites;
}

/** The kind labels in the pre-create loop: the first string of EVERY `["<kind>", <list>]` pair between the loop head and `as const`. */
export function loopKinds(src: string): string[] {
  const head = src.indexOf("for (const [kind, dirs] of [");
  const tail = head < 0 ? -1 : src.indexOf("] as const", head);
  if (head < 0 || tail < 0) return [];
  const segment = src.slice(head, tail);
  return [...segment.matchAll(/\[\s*"([^"]*)"\s*,/g)].map((m) => m[1]).sort();
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

const tfFiles = readdirSync(sentryDir).filter((f) => f.endsWith(".tf"));
const allTf = tfFiles.map((f) => readFileSync(join(sentryDir, f), "utf8")).join("\n");
const issueAlertsTf = readFileSync(join(sentryDir, "issue-alerts.tf"), "utf8");
// Walked and comment-stripped ONCE per file (the strip is the slow part, and six cases read the result).
let serverSourcesCache: Array<{ file: string; src: string }> | undefined;
const serverSources = () => (serverSourcesCache ??= walk(serverDir).map((file) => ({ file, src: stripTsComments(readFileSync(file, "utf8"), file) })));
const emitSites = () => serverSources().flatMap(({ file, src }) => emitSitesIn(file, src));
const sandboxConfig = () => serverSources().find((s) => s.file.endsWith("agent-runner-sandbox-config.ts"))!;

const RULE_FIXTURE = `
resource "sentry_alert" "${RULE}" {
  organization      = var.sentry_org
  name              = "masked-dir-precreate-failed"
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

describe("masked-dir-precreate — emit site / rule contract", () => {
  it("finds the emit site by scanning server/ (floor: at least one)", () => {
    expect(emitSites().length).toBeGreaterThanOrEqual(1);
  });

  it("every occurrence of the op token is a literal emit site (no constant or indirection hides one)", () => {
    const literal = emitSites().length;
    const perFile: string[] = [];
    let tokens = 0;
    for (const { file, src } of serverSources()) {
      const n = [...src.matchAll(new RegExp(OP, "g"))].length;
      tokens += n;
      if (n > 0) perFile.push(`${file}=${n}`);
    }
    expect(tokens, `token counts per file: ${perFile.join(", ")}`).toBe(literal);
  });

  it("every emit site carries feature agent-sandbox, the literal null first argument, and dir_kind bound to the loop kind", () => {
    for (const s of emitSites()) {
      expect(s.feature, `${s.file} feature`).toBe(FEATURE);
      // An Error first argument is deduplicated behind the pino mirror capture (#8629 class).
      expect(s.firstArgNull, `${s.file} must call reportSilentFallback(null, ...)`).toBe(true);
      expect(s.dirKindExpr, `${s.file} tags.dir_kind`).toBe("kind");
    }
  });

  it("dir_kind is a closed three-value set: the loop labels are exactly peer-socket, session-tmp, transcript", () => {
    expect(loopKinds(sandboxConfig().src)).toEqual(KINDS);
  });

  it("the emit never interpolates the path into the message and passes code+syscall as extra", () => {
    const src = sandboxConfig().src;
    const at = src.indexOf(`op: "${OP}"`);
    const obj = enclosingObject(src, at).text;
    expect(obj).toMatch(/extra:\s*\{[^}]*\bdir\b[^}]*\bcode\b[^}]*\bsyscall\b/);
    expect(obj).not.toMatch(/message:[^\n]*\$\{\s*(?:dir|e\.|err)/);
  });

  it("the live rule routes it: feature eq + op eq, email to a person, rate trigger 0/1h, unique frequency", () => {
    expect(ruleProblems(issueAlertsTf, allTf)).toEqual([]);
    expect(tfFiles).toContain("issue-alerts.tf");
  });
});

describe("masked-dir-precreate — harness self-tests (mutation rows)", () => {
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

  it("dropping the op filter, the feature filter or the email action goes red", () => {
    const noOp = RULE_FIXTURE.replace(/\s*\{ tagged_event = \{ key = "op"[^\n]*\n/, "\n");
    expect(ruleProblems(noOp).length).toBeGreaterThan(0);
    const noFeature = RULE_FIXTURE.replace(/\s*\{ tagged_event = \{ key = "feature"[^\n]*\n/, "\n");
    expect(ruleProblems(noFeature).length).toBeGreaterThan(0);
    const noEmail = RULE_FIXTURE.replace(/\{ email = [^\n]*\n/, "");
    expect(ruleProblems(noEmail).length).toBeGreaterThan(0);
    const wrongOp = RULE_FIXTURE.replace(`value = "${OP}"`, `value = "${OP}-x"`);
    expect(ruleProblems(wrongOp).length).toBeGreaterThan(0);
  });

  it("a frequency_minutes shared with another rule goes red", () => {
    const other = `resource "sentry_alert" "other" {\n  frequency_minutes = 71\n}\n`;
    expect(ruleProblems(RULE_FIXTURE, RULE_FIXTURE + other)).toEqual(["frequency_minutes 71 not unique in the root"]);
  });

  const SITE = (first: string, feature = FEATURE, kind = "kind") =>
    `function f() { for (const [kind, dirs] of lists) { try {} catch (e) { reportSilentFallback(${first}, {\n feature: "${feature}",\n op: "${OP}",\n tags: { dir_kind: ${kind} },\n extra: { dir } }); } } }`;

  it("emit-site derivation: compliant passes; Error first arg, other feature, raw-path dir_kind, renamed op each go red", () => {
    const ok = emitSitesIn("a.ts", SITE("null"));
    expect(ok).toEqual([{ file: "a.ts", feature: FEATURE, firstArgNull: true, dirKindExpr: "kind" }]);
    expect(emitSitesIn("a.ts", SITE("err"))[0].firstArgNull).toBe(false);
    expect(emitSitesIn("a.ts", SITE("null", "other"))[0].feature).toBe("other");
    expect(emitSitesIn("a.ts", SITE("null", FEATURE, "dir"))[0].dirKindExpr).toBe("dir");
    expect(emitSitesIn("a.ts", SITE("null").replace(OP, `${OP}-x`))).toEqual([]);
  });

  it("loop-kind derivation: a fourth kind or a renamed kind goes red", () => {
    const three = `for (const [kind, dirs] of [["peer-socket", peerSocketDirs], ["transcript", transcriptDirs], ["session-tmp", [AGENT_SESSION_TMP_ROOT]]] as const) {`;
    expect(loopKinds(three)).toEqual(KINDS);
    expect(loopKinds(three.replace("]]] as", `]], ["bogus", []]] as`))).not.toEqual(KINDS);
    expect(loopKinds("no loop here")).toEqual([]);
    expect(loopKinds(three.replace("transcript", "transcripts"))).not.toEqual(KINDS);
  });

  it("the HCL comment strip is load-bearing: without it a commented rule would look live", () => {
    const commented = RULE_FIXTURE.split("\n").map((l) => `# ${l}`).join("\n");
    const noStrip = commented.replace(/^# /gm, "");
    // The unstripped text matches the block; the stripped text does not.
    expect(new RegExp(`resource\\s+"sentry_alert"\\s+"${RULE}"`).test(noStrip)).toBe(true);
    expect(new RegExp(`resource\\s+"sentry_alert"\\s+"${RULE}"`).test(stripHcl(commented))).toBe(false);
  });
});
