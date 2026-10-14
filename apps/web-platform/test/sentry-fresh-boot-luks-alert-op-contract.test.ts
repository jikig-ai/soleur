import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the fresh-boot LUKS path's Sentry routing (#6931, ADR-263).
//
// THE CLASS THIS CLOSES. soleur-boot-emit sends ONE shared message ("soleur-cloud-init boot stage")
// for every stage, so a stage that matches no tagged_event filter lands in the always-open group and
// pages nobody (issue-alerts.tf records the same failure at web_terminal_boot_fatal and
// web_private_nic_boot_gate). The provisioner's fatal arms, the cloud-init hard gate (which
// `poweroff -f`s) and the readiness gate are exactly the events a console-less web-2 has no other
// signal for. Three artifacts must agree on the stage vocabulary: the EMITTERS (workspaces-luks-
// provision.sh, soleur-host-bootstrap.sh's readiness helper, cloud-init.yml), the ROUTER
// (issue-alerts.tf) and the committed alert-reference.json the daily drift probe reads.
//
// Two rules, split by severity (the web_host_github_app_key_boot precedent): web_luks_boot_fatal pages
// (ActiveMembers), web_luks_boot_warning does not (NoOne). Asserting both here, in both directions,
// means a stage cannot cross the severity boundary or a new arm ship unrouted without a red CI.
//
// ONE STAGE PAGES AT LEVEL WARNING ON PURPOSE (#9377, ADR-263 D8): `workspaces_luks_provision_escrow`
// (the off-host header copy failed, escrow=missing). The boot continues, so the provisioner emits it at
// level warning, but a web-class host with no off-host header copy is a single-point loss, so a person is
// paged. It is routed on the paging rule by STAGE NAME (no rule filters on level). PAGE_AT_WARNING below is
// the explicit, closed list of such stages; every other warning must stay on the quiet rule.
//
// MUTATION ROWS are in-file: every extractor is a pure function of the corpus text, and the last
// describe block feeds each one a broken copy and requires the verdict to flip.

const here = dirname(fileURLToPath(import.meta.url));
const infra = join(here, "../infra");
const read = (p: string): string => readFileSync(join(infra, p), "utf8");
const tf = read("sentry/issue-alerts.tf");
const reference = JSON.parse(read("sentry/alert-reference.json")) as Record<string, any>;
const provisioner = read("workspaces-luks-provision.sh");
const bootstrap = read("soleur-host-bootstrap.sh");
const cloudInit = read("cloud-init.yml");

const codeLines = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");

const PROV = "workspaces_luks_provision_";
// Fatal arms of the provisioner (exit 10-17) + the cloud-init gate + one stage per readiness reason.
const PROVISIONER_FATAL_ARMS = ["config", "device", "discriminate", "key", "format", "open", "wire", "mount"] as const;
const READINESS_REASONS = ["token", "vector", "volume", "luks"] as const;
// Stages that page although the provisioner emits them at level WARNING (the boot continues): the off-host
// header copy failed (escrow=missing). A closed list; adding to it is a deliberate paging decision.
const PAGE_AT_WARNING = [`${PROV}escrow`];
const PAGE_STAGES = [
  ...PROVISIONER_FATAL_ARMS.map((a) => `${PROV}${a}`),
  "workspaces_luks_not_mounted",
  ...READINESS_REASONS.map((r) => `fresh_boot_not_ready_${r}`),
  ...PAGE_AT_WARNING,
];
// Non-fatal, non-paging stages: the probe-timer warn, the arm-file write, the readiness row's direct channel.
// Severity is separated by STAGE NAME (no rule in issue-alerts.tf filters on Sentry level), so a warning never
// shares a stage name with a fatal arm: the timer warning is `wire_warn`, not `wire`.
const QUIET_STAGES = [`${PROV}wire_warn`, `${PROV}result`, "fresh_boot_ready_bs_egress"];

// ---- ROUTER side -----------------------------------------------------------------------------

function rawRule(src: string, name: string): string {
  const start = src.indexOf(`resource "sentry_alert" "${name}"`);
  if (start === -1) throw new Error(`${name} resource not found in issue-alerts.tf`);
  const rest = src.slice(start);
  const end = rest.search(/\n\}\n/);
  if (end === -1) throw new Error(`${name} resource block is not closed`);
  return rest.slice(0, end);
}
const ruleBody = (src: string, name: string): string => codeLines(rawRule(src, name));

// The stage set of a rule: exactly one `tagged_event` on key `stage`, match `in`.
function routedStages(src: string, name: string): string[] {
  const body = ruleBody(src, name);
  const af = body.indexOf("action_filters = [");
  if (af === -1) throw new Error(`action_filters not found on ${name}`);
  const conds = [...body.slice(af).matchAll(/tagged_event\s*=\s*\{([^}]*)\}/g)].map((m) => m[1]);
  if (conds.length !== 1) throw new Error(`${name}: expected exactly one tagged_event, found ${conds.length}`);
  const key = /key\s*=\s*"([^"]+)"/.exec(conds[0])?.[1];
  const match = /match\s*=\s*"([^"]+)"/.exec(conds[0])?.[1];
  const value = /value\s*=\s*"([^"]+)"/.exec(conds[0])?.[1];
  if (key !== "stage" || match !== "in" || !value) throw new Error(`${name}: the condition is not stage/in/<list>`);
  return value.split(",");
}

const fallthrough = (src: string, name: string): string | undefined =>
  /fallthrough_type\s*=\s*"([^"]+)"/.exec(ruleBody(src, name))?.[1];

// ---- EMITTER side ----------------------------------------------------------------------------

// Every arm the provisioner can emit under workspaces_luks_provision_<arm>: the fatal()/warn() call
// sites plus any literal `soleur-boot-emit workspaces_luks_provision_<arm>`.
function provisionerArms(src: string): { all: Set<string>; fatal: Set<string>; warn: Set<string>; literalLevels: Map<string, string> } {
  const code = codeLines(src);
  const fatal = new Set([...code.matchAll(/(?<![A-Za-z0-9_])fatal ([a-z_]+) [0-9]+/g)].map((m) => m[1]));
  const warn = new Set([...code.matchAll(/(?<![A-Za-z0-9_])warn ([a-z_]+) [a-z_]+/g)].map((m) => m[1]));
  const lit = [...code.matchAll(/soleur-boot-emit workspaces_luks_provision_([a-z_]+) ([a-z]+)/g)];
  const literalLevels = new Map(lit.map((m) => [m[1], m[2]] as [string, string]));
  return { all: new Set([...fatal, ...warn, ...literalLevels.keys()]), fatal, warn, literalLevels };
}

// Everything the provisioner does AFTER its (single) escrow emit. A boot-continues event may be followed by
// the result row and `exit 0` and nothing that ends the boot: no other `exit`, no fatal() arm call.
function afterEscrowEmit(src: string): string {
  const code = codeLines(src);
  const i = code.search(/soleur-boot-emit workspaces_luks_provision_escrow /);
  if (i === -1) throw new Error("the escrow emit was not found in the provisioner");
  return code.slice(i);
}
const exitsAfterEscrowEmit = (src: string): string[] =>
  [...afterEscrowEmit(src).matchAll(/(?<![A-Za-z0-9_$.-])exit(?:[ \t]+([0-9]+))?(?![A-Za-z0-9_-])/g)].map((m) => m[1] ?? "");
const fatalCallsAfterEscrowEmit = (src: string): string[] =>
  [...afterEscrowEmit(src).matchAll(/(?<![A-Za-z0-9_])fatal [a-z_]+ [0-9]+/g)].map((m) => m[0]);

function readinessHelper(src: string): string {
  const m = /cat > \/usr\/local\/bin\/soleur-fresh-boot-ready <<'FRESHREADYEOF'\n([\s\S]*?)\nFRESHREADYEOF/.exec(src);
  if (!m) throw new Error("the soleur-fresh-boot-ready heredoc was not found");
  return codeLines(m[1]);
}

const readinessReasons = (src: string): string[] =>
  [...readinessHelper(src).matchAll(/REASON=([a-z]+)/g)].map((m) => m[1]).filter((r) => r !== "none");

const sorted = (xs: Iterable<string>): string[] => [...new Set(xs)].sort();

describe("fresh-boot LUKS Sentry routing: the routers", () => {
  it("web_luks_boot_fatal routes EXACTLY the paging stages (both directions)", () => {
    const got = routedStages(tf, "web_luks_boot_fatal");
    expect(got.length).toBeGreaterThan(0);
    expect(new Set(got).size).toBe(got.length);
    expect(sorted(got)).toEqual(sorted(PAGE_STAGES));
    expect(PAGE_STAGES.length).toBe(14);
  });

  it("web_luks_boot_warning routes EXACTLY the non-paging stages (both directions)", () => {
    const got = routedStages(tf, "web_luks_boot_warning");
    expect(sorted(got)).toEqual(sorted(QUIET_STAGES));
    expect(QUIET_STAGES.length).toBe(3);
  });

  it("no stage is on both rules and the green twin `fresh_boot_ready` is on neither", () => {
    const fatal = routedStages(tf, "web_luks_boot_fatal");
    const quiet = routedStages(tf, "web_luks_boot_warning");
    expect(fatal.filter((s) => quiet.includes(s))).toEqual([]);
    expect([...fatal, ...quiet]).not.toContain("fresh_boot_ready");
  });

  it("escrow=missing pages: the escrow stage is on the paging rule and on exactly one rule (#9377)", () => {
    const fatal = routedStages(tf, "web_luks_boot_fatal");
    const quiet = routedStages(tf, "web_luks_boot_warning");
    for (const s of PAGE_AT_WARNING) {
      expect(fatal, `${s} must be on the paging rule`).toContain(s);
      expect(quiet, `${s} must not be on the quiet rule`).not.toContain(s);
      expect(fatal.filter((x) => x === s).length + quiet.filter((x) => x === s).length).toBe(1);
    }
    // The carve-out is closed: only stages routed on the paging rule may be listed in it.
    for (const s of PAGE_AT_WARNING) expect(PAGE_STAGES).toContain(s);
  });

  it("the stages that stay quiet (wire_warn, result, fresh_boot_ready_bs_egress) are still off the paging rule", () => {
    const fatal = routedStages(tf, "web_luks_boot_fatal");
    for (const s of QUIET_STAGES) expect(fatal, `${s} must not page`).not.toContain(s);
  });

  it("the fatal rule pages (ActiveMembers) and the warning rule does not (NoOne), both value = 0", () => {
    expect(fallthrough(tf, "web_luks_boot_fatal")).toBe("ActiveMembers");
    expect(fallthrough(tf, "web_luks_boot_warning")).toBe("NoOne");
    for (const r of ["web_luks_boot_fatal", "web_luks_boot_warning"]) {
      const body = ruleBody(tf, r);
      expect(body).toMatch(/event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h",\s*value\s*=\s*0\s*\}/);
      expect(body).toMatch(/enabled\s*=\s*true/);
      expect(body).toMatch(/issue_owners/);
    }
  });

  it("each rule uses a frequency_minutes no other rule in the root uses (Sentry dedups identical rules at POST)", () => {
    const all = [...codeLines(tf).matchAll(/^\s*frequency_minutes\s*=\s*(\d+)/gm)].map((m) => m[1]);
    for (const r of ["web_luks_boot_fatal", "web_luks_boot_warning"]) {
      const own = /^\s*frequency_minutes\s*=\s*(\d+)/m.exec(ruleBody(tf, r))?.[1];
      expect(own, `${r} has no frequency_minutes`).toBeTruthy();
      expect(all.filter((v) => v === own)).toHaveLength(1);
    }
  });

  it("alert-reference.json carries both rules, equal to the .tf (the daily drift probe's reference)", () => {
    for (const [res, name, ft] of [
      ["web_luks_boot_fatal", "web-host-luks-boot-fatal", "ActiveMembers"],
      ["web_luks_boot_warning", "web-host-luks-boot-warning", "NoOne"],
    ] as const) {
      const ref = reference[name];
      expect(ref, `${name} missing from alert-reference.json`).toBeTruthy();
      const cond = ref.actionFilters[0].conditions;
      expect(cond).toHaveLength(1);
      expect(cond[0].comparison.key).toBe("stage");
      expect(cond[0].comparison.match).toBe("in");
      expect(cond[0].comparison.value.split(",")).toEqual(routedStages(tf, res));
      expect(ref.actionFilters[0].actions[0].fallthroughType).toBe(ft);
      expect(String(ref.frequency)).toBe(/^\s*frequency_minutes\s*=\s*(\d+)/m.exec(ruleBody(tf, res))?.[1]);
    }
  });
});

describe("fresh-boot LUKS Sentry routing: the emitters", () => {
  it("every provisioner arm is routed, and every routed provisioner stage is still emitted", () => {
    const { all } = provisionerArms(provisioner);
    expect(all.size, "extracted no provisioner arm").toBeGreaterThanOrEqual(9);
    const routed = [...PAGE_STAGES, ...QUIET_STAGES].filter((s) => s.startsWith(PROV)).map((s) => s.slice(PROV.length));
    expect(sorted(all)).toEqual(sorted(routed));
  });

  it("every arm with a fatal() call site is on the PAGING rule (a shared stage name pages by design)", () => {
    const { fatal } = provisionerArms(provisioner);
    expect(sorted(fatal)).toEqual(sorted(PROVISIONER_FATAL_ARMS));
    const paging = routedStages(tf, "web_luks_boot_fatal");
    for (const a of fatal) expect(paging).toContain(`${PROV}${a}`);
  });

  it("a warning never reuses a paging arm's stage name, and a quiet stage is never emitted at level fatal", () => {
    const { fatal, warn, literalLevels } = provisionerArms(provisioner);
    const quietArms = QUIET_STAGES.filter((s) => s.startsWith(PROV)).map((s) => s.slice(PROV.length));
    const pageAtWarningArms = PAGE_AT_WARNING.map((s) => s.slice(PROV.length));
    // `warn wire ...` would page: `wire` is a fatal arm and the paging rule matches on stage, not level.
    // The one deliberate exception is the PAGE_AT_WARNING carve-out (escrow), which is emitted by a literal
    // soleur-boot-emit and never through warn().
    expect([...warn].filter((a) => (fatal.has(a) && !pageAtWarningArms.includes(a)) || !(quietArms.includes(a) || pageAtWarningArms.includes(a)))).toEqual([]);
    // A literal emit of a quiet stage must carry level warning, so Sentry's severity agrees with the routing.
    for (const a of quietArms) {
      if (literalLevels.has(a)) expect(literalLevels.get(a), `${PROV}${a} is routed quiet but emitted at that level`).toBe("warning");
    }
  });

  it("every PAGE_AT_WARNING stage is emitted by the provisioner at level warning (the boot continues) and is not a fatal arm (#9377)", () => {
    const { fatal, literalLevels } = provisionerArms(provisioner);
    for (const s of PAGE_AT_WARNING) {
      const arm = s.slice(PROV.length);
      expect(literalLevels.has(arm), `${s} is not emitted by a literal soleur-boot-emit`).toBe(true);
      expect(literalLevels.get(arm), `${s} pages by stage name but must be emitted at level warning (boot continues)`).toBe("warning");
      expect(fatal.has(arm), `${s} must not also be a fatal() arm`).toBe(false);
    }
    // The escrow stage is a boot-continues event: after the emit the provisioner reaches `exit 0` and NOTHING ELSE ends
    // the boot (a trailing `exit 0` alone is satisfied by an `exit 17` placed right after the emit).
    const code = codeLines(provisioner);
    expect(code.trimEnd().endsWith("exit 0")).toBe(true);
    expect(exitsAfterEscrowEmit(provisioner), "the only exit after the escrow emit is the final `exit 0`").toEqual(["0"]);
    expect(fatalCallsAfterEscrowEmit(provisioner), "no fatal() arm call after the escrow emit").toEqual([]);
  });

  it("the provisioner emits through the workspaces_luks_provision_<arm> stage form at fatal and warning", () => {
    const code = codeLines(provisioner);
    expect(code).toContain('soleur-boot-emit "workspaces_luks_provision_$1" fatal');
    expect(code).toContain('soleur-boot-emit "workspaces_luks_provision_$1" warning');
  });

  it("the readiness helper emits one fatal stage per reason, and the reasons are exactly the routed ones", () => {
    expect(sorted(readinessReasons(bootstrap))).toEqual(sorted(READINESS_REASONS));
    const helper = readinessHelper(bootstrap);
    expect(helper).toContain('soleur-boot-emit "fresh_boot_not_ready_$REASON" fatal');
    expect(helper).toContain("soleur-boot-emit fresh_boot_ready info");
    expect(helper).toContain("soleur-boot-emit fresh_boot_ready_bs_egress warning");
  });

  it("the cloud-init hard gate emits workspaces_luks_not_mounted at fatal and powers the host off", () => {
    const gate = codeLines(cloudInit)
      .split("\n")
      .filter((l) => l.includes("workspaces_luks_not_mounted"));
    expect(gate).toHaveLength(1);
    expect(gate[0]).toContain("soleur-boot-emit workspaces_luks_not_mounted fatal; poweroff -f");
  });
});

describe("fresh-boot LUKS Sentry routing: MUTATION rows (each extractor must flip on a broken copy)", () => {
  const PAGE_RULE = "web_luks_boot_fatal";
  // Mutate the PAGING rule's own text only: its prose names the same stages above the list.
  const inRule = (from: string, to: string): string => {
    const raw = rawRule(tf, PAGE_RULE);
    const mutated = raw.replace(from, to);
    if (mutated === raw) throw new Error(`mutation did not land: ${from}`);
    return tf.replace(raw, mutated);
  };
  const sameAsPage = (src: string): boolean =>
    JSON.stringify(sorted(routedStages(src, PAGE_RULE))) === JSON.stringify(sorted(PAGE_STAGES));

  it("control: the real .tf satisfies the extractors the mutants are judged by", () => {
    expect(sameAsPage(tf)).toBe(true);
  });

  it("a stage dropped from the paging list is seen", () => {
    expect(sameAsPage(inRule(`${PROV}wire,`, ""))).toBe(false);
  });

  it("a stage renamed in the paging list is seen", () => {
    expect(sameAsPage(inRule("workspaces_luks_not_mounted,", "workspaces_luks_not_mounted2,"))).toBe(false);
  });

  it("a success beacon added to the paging list is seen", () => {
    expect(sameAsPage(inRule(`${PROV}wire,`, `${PROV}wire,fresh_boot_ready,`))).toBe(false);
  });

  it("the paging rule flipped to NoOne is seen", () => {
    const raw = rawRule(tf, PAGE_RULE);
    expect(fallthrough(tf.replace(raw, raw.replace('fallthrough_type = "ActiveMembers"', 'fallthrough_type = "NoOne"')), PAGE_RULE)).toBe("NoOne");
  });

  it("a renamed provisioner arm is seen (the arm set no longer equals the routed set)", () => {
    const routed = [...PAGE_STAGES, ...QUIET_STAGES].filter((s) => s.startsWith(PROV)).map((s) => s.slice(PROV.length));
    const mutated = provisioner.replace(/fatal key 13/g, "fatal keyx 13");
    expect(provisionerArms(provisioner).all.has("key")).toBe(true);
    expect(JSON.stringify(sorted(provisionerArms(mutated).all))).not.toEqual(JSON.stringify(sorted(routed)));
  });

  it("a warning emitted under a paging arm's stage name is seen", () => {
    const sameName = provisioner.replace(/warn wire_warn /g, "warn wire ");
    const mutated = sameName === provisioner ? provisioner.replace(/warn result /g, "warn wire ") : sameName;
    expect(mutated).not.toBe(provisioner);
    const { fatal, warn } = provisionerArms(mutated);
    expect([...warn].some((a) => fatal.has(a))).toBe(true);
  });

  it("a PAGE_AT_WARNING stage emitted at level fatal is seen (escrow is a boot-continues event)", () => {
    const mutated = provisioner.replace(/(soleur-boot-emit workspaces_luks_provision_escrow )warning/, "$1fatal");
    expect(mutated).not.toBe(provisioner);
    expect(provisionerArms(provisioner).literalLevels.get("escrow")).toBe("warning");
    expect(provisionerArms(mutated).literalLevels.get("escrow")).toBe("fatal");
  });

  it("an exit placed right after the escrow emit is seen (the trailing exit 0 alone would not see it)", () => {
    const mutated = provisioner.replace(/(soleur-boot-emit workspaces_luks_provision_escrow warning[^\n]*\n)/, "$1  exit 17\n");
    expect(mutated).not.toBe(provisioner);
    expect(codeLines(mutated).trimEnd().endsWith("exit 0")).toBe(true); // the old check is blind to it
    expect(exitsAfterEscrowEmit(provisioner)).toEqual(["0"]);
    expect(exitsAfterEscrowEmit(mutated)).toEqual(["17", "0"]);
  });

  it("a fatal() arm call or a bare exit after the escrow emit is seen", () => {
    const withFatal = provisioner.replace(/(soleur-boot-emit workspaces_luks_provision_escrow warning[^\n]*\n)/, "$1  fatal wire 16 \"x\"\n");
    expect(withFatal).not.toBe(provisioner);
    expect(fatalCallsAfterEscrowEmit(provisioner)).toEqual([]);
    expect(fatalCallsAfterEscrowEmit(withFatal)).toEqual(['fatal wire 16']);
    const bare = provisioner.replace(/(soleur-boot-emit workspaces_luks_provision_escrow warning[^\n]*\n)/, "$1  exit\n");
    expect(exitsAfterEscrowEmit(bare)).toEqual(["", "0"]);
  });

  it("a quiet stage emitted at level fatal is seen", () => {
    // `result` is a quiet stage; give it a literal fatal emit and the level check must see it.
    const mutated = provisioner + "\nsoleur-boot-emit workspaces_luks_provision_result fatal\n";
    expect(provisionerArms(mutated).literalLevels.get("result")).toBe("fatal");
    expect(provisionerArms(provisioner).literalLevels.has("result")).toBe(false);
  });

  // Router-side mutants for escrow=missing (Guard 4). Each mutates the rule's own text and is judged by the
  // same extractors the real-tree rows use.
  const inNamedRule = (name: string, from: string, to: string): string => {
    const raw = rawRule(tf, name);
    const mutated = raw.replace(from, to);
    if (mutated === raw) throw new Error(`mutation did not land in ${name}: ${from}`);
    return tf.replace(raw, mutated);
  };
  const ESC = `${PROV}escrow`;
  const escrowRuleCount = (src: string): number =>
    [routedStages(src, "web_luks_boot_fatal"), routedStages(src, "web_luks_boot_warning")].filter((l) => l.includes(ESC)).length;
  const escrowPages = (src: string): boolean => routedStages(src, "web_luks_boot_fatal").includes(ESC);

  it("control: the real .tf lists escrow on exactly one rule, the paging one", () => {
    expect(escrowRuleCount(tf)).toBe(1);
    expect(escrowPages(tf)).toBe(true);
  });

  it("escrow moved back to the warning list is seen", () => {
    const m = inNamedRule("web_luks_boot_fatal", `,${ESC}"`, `"`);
    const m2 = m.replace(
      /(resource "sentry_alert" "web_luks_boot_warning"[\s\S]*?value = ")/,
      `$1${ESC},`,
    );
    expect(m2).not.toBe(m);
    expect(escrowPages(m2)).toBe(false);
    expect(sameAsPage(m2)).toBe(false);
  });

  it("escrow removed from both lists is seen", () => {
    const m = inNamedRule("web_luks_boot_fatal", `,${ESC}"`, `"`);
    expect(escrowRuleCount(m)).toBe(0);
  });

  it("escrow listed on both rules is seen", () => {
    const m = inNamedRule("web_luks_boot_warning", `value = "${PROV}wire_warn`, `value = "${ESC},${PROV}wire_warn`);
    expect(escrowRuleCount(m)).toBe(2);
  });

  it("the quiet rule flipped to ActiveMembers is seen (it would page the quiet stages)", () => {
    const m = inNamedRule("web_luks_boot_warning", 'fallthrough_type = "NoOne"', 'fallthrough_type = "ActiveMembers"');
    expect(fallthrough(m, "web_luks_boot_warning")).not.toBe("NoOne");
  });

  it("the paging rule's recipients changed away from ActiveMembers is seen (it would silence the page)", () => {
    const m = inNamedRule(PAGE_RULE, 'fallthrough_type = "ActiveMembers"', 'fallthrough_type = "NoOne"');
    expect(fallthrough(m, PAGE_RULE)).not.toBe("ActiveMembers");
  });

  it("harness: a paging list emptied is refused by the extractor, never read as a pass", () => {
    const raw = rawRule(tf, PAGE_RULE);
    const emptied = tf.replace(raw, raw.replace(/value = "workspaces_luks_provision_config[^"]*"/, 'value = ""'));
    expect(emptied).not.toBe(tf);
    expect(() => routedStages(emptied, PAGE_RULE)).toThrow(/not stage\/in\/<list>/);
  });

  it("a new unrouted readiness reason is seen", () => {
    const mutated = bootstrap.replace("else REASON=luks", "elif [ \"$X\" != 1 ]; then REASON=newreason\nelse REASON=luks");
    expect(mutated).not.toBe(bootstrap);
    expect(sorted(readinessReasons(mutated))).not.toEqual(sorted(READINESS_REASONS));
  });

  it("a second tagged_event on the paging rule is refused by the extractor", () => {
    const raw = rawRule(tf, PAGE_RULE);
    const mutated = tf.replace(
      raw,
      raw.replace(
        /(\{ tagged_event = \{[^}]*\} \},)/,
        '$1\n        { tagged_event = { key = "stage", match = "eq", value = "fresh_boot_ready" } },',
      ),
    );
    expect(mutated).not.toBe(tf);
    expect(() => routedStages(mutated, PAGE_RULE)).toThrow(/exactly one tagged_event/);
  });
});
