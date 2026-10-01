import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test for the web-host terminal serving-block boot-FATAL alarm
// (#6396, ADR-082 Item 5 — "the SOLE page for a dead web-2 warm standby").
//
// The cloud-init terminal `docker run` block emits `soleur-boot-emit <stage> fatal` on a
// no-SSH boot abort (tags.stage names the failing region). web-2 is a warm standby that takes
// no app.soleur.ai traffic, so `betteruptime_monitor.app` stays GREEN on a dead standby, and
// the #5933 per-host origin uptime probe was RETIRED — this Sentry issue-alert is the ONLY page.
//
// Each terminal stage string is pinned in BOTH its cloud-init emit site AND issue-alerts.tf so
// a rename in either — which would silently DARK the alert (the operator-only-finds-out-after-a-
// dead-standby failure this alarm exists to prevent) — breaks CI instead.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const cloudInit = readFileSync(join(here, "../infra/cloud-init.yml"), "utf8");

const STAGES = [
  "terminal_preamble",
  "hostscripts_incomplete",
  "doppler_download",
  "docker_run",
  // #8651: the seed block's on_err fatal (`soleur-hostscript-seed failed`, stage=pull). Since
  // #8036 1d there is no GHCR arm behind the zot pull, so this is a web boot zot could not serve.
  "pull",
] as const;

const infraDir = join(here, "../infra");

// Comment lines stripped (first non-blank character `#`): rationale prose names every stage, and
// prose must satisfy neither the condition extraction nor the emitter scan below.
const codeLines = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");

// The rule's watched stage set, read from the `web_terminal_boot_fatal` resource BODY only (header
// to its own column-0 `}`), comments stripped, then from its `action_filters` `conditions = [`
// block. A whole-file toContain() is satisfied by ANY rule carrying the value — moving `pull` into
// web_private_nic_boot_gate left the old pin green while this rule stopped paging it.
function watchedStages(): string[] {
  const start = tf.indexOf('resource "sentry_alert" "web_terminal_boot_fatal"');
  if (start === -1) throw new Error("web_terminal_boot_fatal resource not found in issue-alerts.tf");
  const rest = tf.slice(start);
  const end = rest.search(/\n\}\n/);
  if (end === -1) throw new Error("web_terminal_boot_fatal resource block is not closed");
  const body = codeLines(rest.slice(0, end));
  // Anchor through action_filters FIRST: a bare "conditions = [" matches trigger_conditions.
  const af = body.indexOf("action_filters = [");
  if (af === -1) throw new Error("action_filters block not found on web_terminal_boot_fatal");
  const cStart = body.indexOf("conditions = [", af);
  if (cStart === -1) throw new Error("action_filters[].conditions not found on web_terminal_boot_fatal");
  const cRest = body.slice(cStart);
  const cEnd = cRest.search(/\n[ \t]*\]/);
  if (cEnd === -1) throw new Error("action_filters[].conditions block is not closed");
  const out: string[] = [];
  const re = /tagged_event\s*=\s*\{[^}]*?key\s*=\s*"([^"]+)"[^}]*?value\s*=\s*"([^"]+)"[^}]*?\}/g;
  for (const m of cRest.slice(0, cEnd).matchAll(re)) {
    if (m[1] !== "stage") throw new Error(`web_terminal_boot_fatal filters on a non-stage key: ${m[1]}`);
    out.push(m[2]);
  }
  return out;
}

// Every boot-template emitter file: apps/web-platform/infra/**/*.{yml,sh}. `*.test.sh` is
// excluded — those are harnesses whose fixtures emit on purpose, never a host's emitter.
function infraEmitterFiles(): string[] {
  return (readdirSync(infraDir, { recursive: true }) as string[])
    .filter((f) => /\.(ya?ml|sh)$/.test(f) && !/\.test\.sh$/.test(f) && !f.includes("node_modules"))
    .map((f) => join(infraDir, f));
}

type Emit = { file: string; stage: string; level: string; form: string };

// Every emit of a WATCHED stage in one file's code lines, in the four shapes a boot emits by:
//   soleur-boot-emit <stage> <level>        host-local / bootstrap-defined emitter
//   _emit "<msg>" <stage> <level>           cloud-init.yml's seed-block transport (on_err)
//   emit <stage> <level>                    a script-local two-channel wrapper (nic-wait)
//   soleur-wait-ready <kind> <name> <stage> emits <stage> at INFO on success — a watched stage
//                                           passed to it is a healthy-boot page by construction
// A stage passed as a VARIABLE is attributed to every watched literal that same file assigns to
// that variable (`stage=docker_run`, `STAGE=pull`): that is how the terminal trap and on_err
// carry four of the five. Positional `$1`/`$2` are skipped — their callers are scanned directly.
function watchedEmits(file: string, text: string, watched: readonly string[]): Emit[] {
  const code = codeLines(text);
  const out: Emit[] = [];
  const bound = (v: string): string[] =>
    watched.filter((st) => new RegExp(`(^|[^A-Za-z0-9_])${v}=["']?${st}["']?([^A-Za-z0-9_]|$)`, "m").test(code));
  const push = (raw: string, level: string, form: string) => {
    const lvl = level.replace(/"/g, "");
    if (raw.startsWith("$")) {
      const v = raw.slice(1).replace(/^\{|\}$/g, "");
      if (/^[0-9]$/.test(v)) return;
      for (const st of bound(v)) out.push({ file, stage: st, level: lvl, form });
    } else if (watched.includes(raw)) {
      out.push({ file, stage: raw, level: lvl, form });
    }
  };
  for (const m of code.matchAll(/soleur-boot-emit\s+"?(\$?\{?[A-Za-z0-9_]+\}?)"?\s+("?[A-Za-z$][A-Za-z0-9_"]*)/g))
    push(m[1], m[2], "soleur-boot-emit");
  for (const m of code.matchAll(/(?<![A-Za-z0-9_-])_emit\s+"[^"]*"\s+"?(\$?\{?[A-Za-z0-9_]+\}?)"?\s+("?[A-Za-z$][A-Za-z0-9_"]*)/g))
    push(m[1], m[2], "_emit");
  for (const m of code.matchAll(/(?<![A-Za-z0-9_-])emit\s+"?(\$?\{?[A-Za-z0-9_]+\}?)"?\s+("?[A-Za-z$][A-Za-z0-9_"]*)/g))
    push(m[1], m[2], "emit");
  for (const m of code.matchAll(/soleur-wait-ready\s+[A-Za-z]+\s+\S+\s+"?([A-Za-z][A-Za-z0-9_]*)/g))
    push(m[1], "info", "soleur-wait-ready");
  return out;
}

describe("web-host-terminal-boot-fatal alert op contract", () => {
  it("cloud-init.yml arms the composite EXIT trap that emits soleur-boot-emit <stage> fatal", () => {
    // The mutable-stage EXIT trap fires on exit 1 / set -e aborts (doppler_download, docker_run).
    expect(cloudInit).toContain(
      `[ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal`,
    );
    // The poweroff path bypasses the EXIT trap (signal death) — an explicit emit precedes it.
    expect(cloudInit).toContain("soleur-boot-emit hostscripts_incomplete fatal");
  });

  it("cloud-init.yml advances the mutable stage through every fatal-tagged region", () => {
    // Pin the stage ASSIGNMENTS (not bare tag literals) so a rename breaks CI. terminal_preamble
    // is the armed value; doppler_download + docker_run advance the trap's coverage.
    expect(cloudInit).toContain("stage=terminal_preamble");
    expect(cloudInit).toContain("stage=doppler_download");
    expect(cloudInit).toContain("stage=docker_run");
  });

  it("web_terminal_boot_fatal watches EXACTLY the five stages (extracted from its own conditions)", () => {
    // Non-vacuity on both sides: an emptied STAGES or a blind extractor must red, never compare ∅ = ∅.
    expect(STAGES.length).toBe(5);
    const watched = watchedStages();
    expect(watched.length, "extracted no stage condition from web_terminal_boot_fatal").toBeGreaterThan(0);
    // No duplicate condition, and set-equal to STAGES: an added `value = "app_zot"` (a success
    // beacon — it would page every healthy boot at value = 0) or a removed `pull` both red here.
    expect(new Set(watched).size).toBe(watched.length);
    expect([...watched].sort()).toEqual([...STAGES].sort());
  });

  // value = 0 is safe ONLY because every watched stage is a failure-only emit (the resource
  // comment says so). This is that claim, read from the emitters rather than trusted: any emit of
  // a watched stage at a level other than fatal — or through soleur-wait-ready, which emits its
  // stage at info on success — would page a healthy boot.
  it("every emitter of a watched stage in infra/**/*.{yml,sh} emits it at level fatal", () => {
    expect(STAGES.length).toBe(5);
    const files = infraEmitterFiles();
    // Non-vacuity: the scan must see the tree, including the template that carries all five.
    expect(files.length).toBeGreaterThan(20);
    expect(files.some((f) => f.endsWith("/cloud-init.yml"))).toBe(true);
    const emits = files.flatMap((f) => watchedEmits(f, readFileSync(f, "utf8"), STAGES));
    const bad = emits
      .filter((e) => e.level !== "fatal")
      .map((e) => `${relative(infraDir, e.file)}: ${e.form} ${e.stage} ${e.level}`);
    expect(bad, "a watched stage is emitted at a non-fatal level").toEqual([]);
    // Every watched stage has at least one fatal emitter the scan attributed: a stage the scan
    // cannot find is a stage whose failure-only claim is unverified, not verified.
    for (const st of STAGES) {
      expect(emits.some((e) => e.stage === st && e.level === "fatal"), `no fatal emitter found for ${st}`).toBe(true);
    }
  });

  it("the emitter scan is not blind (synthetic plants, one per shape, are each caught)", () => {
    const plants: Array<[string, string]> = [
      ["soleur-boot-emit pull info", "soleur-boot-emit"],
      ['_emit "soleur-hostscript-seed failed" docker_run warning', "_emit"],
      ['emit terminal_preamble warning "x"', "emit"],
      ["soleur-wait-ready port 9000 doppler_download || exit 1", "soleur-wait-ready"],
      ['stage=hostscripts_incomplete\ntrap \'[ "$rc" = 0 ] || soleur-boot-emit "$stage" info\' EXIT', "soleur-boot-emit"],
    ];
    for (const [text, form] of plants) {
      const got = watchedEmits("plant", text, STAGES).filter((e) => e.level !== "fatal");
      expect(got.map((e) => e.form), `plant not caught: ${text}`).toEqual([form]);
    }
    // And a comment line is prose, not an emit.
    expect(watchedEmits("plant", "# soleur-boot-emit pull info", STAGES)).toEqual([]);
  });

  // apply-sentry-infra.yml plans the sentry root FULL (no `-target=` allowlist), so
  // the plan universe is `state UNION config`: declaring the resource IS what applies
  // it, and deleting this block is what destroys the live rule. Declaration is
  // therefore the whole apply contract — there is no separate "wired into the apply
  // list" condition left to assert.
  it("issue-alerts.tf declares web_terminal_boot_fatal as a first-occurrence page with a notify target", () => {
    expect(tf).toContain(
      'resource "sentry_alert" "web_terminal_boot_fatal"',
    );
    const start = tf.indexOf(
      'resource "sentry_alert" "web_terminal_boot_fatal"',
    );
    const rest = tf.slice(start + 1);
    const nextResource = rest.indexOf("\nresource ");
    const scoped =
      nextResource === -1 ? tf.slice(start) : tf.slice(start, start + 1 + nextResource);
    // Page on the FIRST fatal — a dead serving host is high-severity, not a rate. value MUST be 0
    // (#8036 1d): the comparison is a strict `>` per issue group, and the `pull` stage's fatal
    // ("soleur-hostscript-seed failed") lands in a group of its own, so `value = 1` could not
    // page a single event there (measured: WEB-PLATFORM-4T, the only one in 30 days, never paged).
    // Safe at 0 only because every stage condition is a failure-only emit.
    // `any-short` is the provider's spelling for OR on
    // `action_filters[].logic_type` (short-circuiting). Semantics are
    // identical to the old `filter_match = "any"`; only the spelling moved.
    expect(scoped).toMatch(/logic_type\s*=\s*"any-short"/);
    expect(scoped).toContain("event_frequency");
// The count-vs-percent discriminator moved from a `comparison_type` FIELD to
    // the attribute NAME: `{ event_frequency_count = { interval, value } }`.
    // Same semantics, and still unsatisfiable by prose.
    expect(scoped).toMatch(/event_frequency_count\s*=/);
    const trigger = scoped.match(/event_frequency_count\s*=\s*\{[^}]*\}/);
    expect(trigger, "no event_frequency_count trigger on web_terminal_boot_fatal").not.toBeNull();
    expect(trigger![0]).toMatch(/value\s*=\s*0\b/);
    expect(trigger![0]).not.toMatch(/value\s*=\s*[1-9]/);
    expect(scoped).toMatch(/interval\s*=\s*"1h"/);
    // Every filter selects on key = "stage" (the shared soleur-boot-emit events tag the region).
    // Whitespace-tolerant so a `terraform fmt` re-alignment doesn't break a behavior-unchanged test.
    expect(scoped).not.toMatch(/key\s*=\s*"(?!stage")/);
    expect(scoped).toMatch(/key\s*=\s*"stage"/);
    // No-SSH page target: a silent removal would make the alarm fire-but-page-nobody.
    // Lowercase `issue_owners` on `sentry_alert`; the CamelCase spelling belongs to
    // the retired `sentry_issue_alert` shape.
    expect(scoped).toMatch(/email\s*=\s*\{[^}]*target_type\s*=\s*"issue_owners"/);
    expect(scoped).toContain("ActiveMembers");
  });
});
