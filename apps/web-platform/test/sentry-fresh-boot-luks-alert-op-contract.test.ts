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
const PAGE_STAGES = [
  ...PROVISIONER_FATAL_ARMS.map((a) => `${PROV}${a}`),
  "workspaces_luks_not_mounted",
  ...READINESS_REASONS.map((r) => `fresh_boot_not_ready_${r}`),
];
// Non-fatal stages: the off-host header copy, the probe-timer warn, the arm-file write, the readiness row's
// direct channel. Severity is separated by STAGE NAME (no rule in issue-alerts.tf filters on Sentry level), so
// a warning never shares a stage name with a fatal arm: the timer warning is `wire_warn`, not `wire`.
const QUIET_STAGES = [`${PROV}escrow`, `${PROV}wire_warn`, `${PROV}result`, "fresh_boot_ready_bs_egress"];

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
    expect(PAGE_STAGES.length).toBe(13);
  });

  it("web_luks_boot_warning routes EXACTLY the non-paging stages (both directions)", () => {
    const got = routedStages(tf, "web_luks_boot_warning");
    expect(sorted(got)).toEqual(sorted(QUIET_STAGES));
    expect(QUIET_STAGES.length).toBe(4);
  });

  it("no stage is on both rules and the green twin `fresh_boot_ready` is on neither", () => {
    const fatal = routedStages(tf, "web_luks_boot_fatal");
    const quiet = routedStages(tf, "web_luks_boot_warning");
    expect(fatal.filter((s) => quiet.includes(s))).toEqual([]);
    expect([...fatal, ...quiet]).not.toContain("fresh_boot_ready");
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
    // `warn wire ...` would page: `wire` is a fatal arm and the paging rule matches on stage, not level.
    expect([...warn].filter((a) => fatal.has(a) || !quietArms.includes(a))).toEqual([]);
    // A literal emit of a quiet stage (the escrow event) must carry level warning, so Sentry's severity
    // agrees with the routing.
    for (const a of quietArms) {
      if (literalLevels.has(a)) expect(literalLevels.get(a), `${PROV}${a} is routed quiet but emitted at that level`).toBe("warning");
    }
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

  it("a quiet stage emitted at level fatal is seen", () => {
    const { literalLevels } = provisionerArms(provisioner.replace(/(soleur-boot-emit workspaces_luks_provision_escrow )warning/, "$1fatal"));
    // Only meaningful when the escrow event is a literal emit; the real file is asserted green above.
    if (provisionerArms(provisioner).literalLevels.has("escrow")) expect(literalLevels.get("escrow")).toBe("fatal");
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
