#!/usr/bin/env bash
# shellcheck disable=SC2016  # node -e bodies are single-quoted JS; `${…}` is JS template syntax, not shell.
# Deterministic battery for the B5 rule-phrasing A/B (#8290, plan §Guard 2). ZERO live API.
#   VERDICT   — scripts/rule-phrasing-verdict.cjs on the synthetic E0-E9 (+EV1) fixtures in
#               test/fixtures/rule-phrasing/ (compact specs expanded to promptfoo -o JSON by
#               expand.cjs); each must yield its pre-registered token (mutation matrix).
#   OBSERVE   — scripts/measure-rule-compliance.cjs on the hand-written sample table
#               (observable-samples.jsonl), incl. the H-E2 refusal-sentence must-PASS rows and
#               the recorded known false negative.
#   HASH-LOCK — prompts/rule-phrasing.cjs throws on a mutated fixture body / a drifted live
#               body (on TEMP copies — the committed fixture is never touched), and the intact
#               arms differ exactly as AC-E2 requires.
#   CLI       — one-line JSON, exit 2 on bad args, exit 1 fail-closed.
# Every case increments `cases` at the CALL SITE and records exactly one ok/bad verdict, so
# passes + fails == cases. The anti-vacuity floor reports via printf + exit 1, never bad()
# (ADR-193), so a neutered verdict helper cannot disarm it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
FIX="$HERE/fixtures/rule-phrasing"
VERDICT="$SKILL_DIR/scripts/rule-phrasing-verdict.cjs"
export SKILL_DIR FIX

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rule-phrasing-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT INT TERM

passes=0; fails=0; cases=0
ok()  { printf 'ok   [%s]\n' "$1"; passes=$((passes + 1)); }
bad() { printf 'FAIL [%s]: %s\n' "$1" "$2"; fails=$((fails + 1)); }

# --- VERDICT: the mutation matrix ------------------------------------------------------
# check_fixture <spec.json> -> "OK <detail>" or "MISMATCH <detail>" on stdout.
check_fixture() {
  node -e '
    const path = require("node:path");
    const { expand } = require(path.join(process.env.FIX, "expand.cjs"));
    const { verdict } = require(path.join(process.env.SKILL_DIR, "scripts", "rule-phrasing-verdict.cjs"));
    const { spec, json } = expand(process.argv[1]);
    const v = verdict(json);
    const why = [];
    if (spec.expect && v.token !== spec.expect) why.push(`token ${v.token} != ${spec.expect}`);
    if (spec.expect_not && v.token === spec.expect_not) why.push(`token must not be ${spec.expect_not}`);
    if (spec.expect_delta_negative && !(v.delta < 0)) why.push(`delta ${v.delta} not negative`);
    if (spec.expect_v1_rules !== undefined && v.v1_rules.length !== spec.expect_v1_rules) why.push(`v1_rules ${v.v1_rules.length} != ${spec.expect_v1_rules}`);
    // E4/E5 isolate ONE failing EXTEND condition: the pooled effect must otherwise qualify.
    if (spec.id === "E4" && !(v.delta >= v.mwe && v.lower > 0 && v.models_no_regression === false)) why.push("E4 is not isolated to the per-model check");
    if (spec.id === "E5" && !(v.delta >= v.mwe && v.lower > 0 && v.rules_positive === 1)) why.push("E5 is not isolated to the >=3-of-4 rule check");
    process.stdout.write((why.length ? "MISMATCH " + why.join("; ") : "OK token=" + v.token) + "\n");
  ' "$1" 2>&1 || true
}

for f in "$FIX"/E*.json; do
  cases=$((cases + 1))
  res="$(check_fixture "$f")"
  if [[ "$res" == OK* ]]; then ok "verdict $(basename "$f" .json): ${res#OK }"; else bad "verdict $(basename "$f" .json)" "$res"; fi
done

# --- OBSERVE: the hand-written sample table --------------------------------------------
while IFS=$'\t' read -r status label detail; do
  cases=$((cases + 1))
  if [[ "$status" == "OK" ]]; then ok "observable: $label"; else bad "observable: $label" "$detail"; fi
done < <(node -e '
  const fs = require("node:fs");
  const path = require("node:path");
  const measure = require(path.join(process.env.SKILL_DIR, "scripts", "measure-rule-compliance.cjs"));
  for (const line of fs.readFileSync(path.join(process.env.FIX, "observable-samples.jsonl"), "utf8").split("\n")) {
    if (line.trim() === "") continue;
    const s = JSON.parse(line);
    const r = measure(s.output, { vars: { rule: s.rule } });
    const got = r.score === 1 ? "compliant" : "noncompliant";
    const good = r.pass === true && got === s.expect && r.reason.startsWith("rule-" + got);
    process.stdout.write([good ? "OK" : "MISMATCH", s.label, `got ${got} (pass=${r.pass}) want ${s.expect}: ${r.reason}`].join("\t") + "\n");
  }
')

# --- HASH-LOCK + AC-E2 arm shape --------------------------------------------------------
# arm_check <mode> -> "OK <detail>" | "MISMATCH <detail>". Modes build TEMP copies only.
arm_check() {
  node -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const crypto = require("node:crypto");
    const gen = require(path.join(process.env.SKILL_DIR, "prompts", "rule-phrasing.cjs"));
    const mode = process.argv[1];
    const tmp = process.argv[2];
    const root = gen.findRepoRoot(process.env.SKILL_DIR);
    const fixture = JSON.parse(fs.readFileSync(path.join(process.env.SKILL_DIR, "prompts", "rule-phrasing-bodies.json"), "utf8"));
    const id = Object.keys(fixture)[0];
    const sha = (s) => crypto.createHash("sha256").update(s, "utf8").digest("hex");
    const tags = (s) => s.match(/\[[a-z-]+:[^\]]*\]/g) || [];
    const expectThrow = (fn, re) => {
      try { fn(); return "MISMATCH did not throw"; }
      catch (e) { return re.test(e.message) ? "OK threw: " + e.message.slice(0, 90) : "MISMATCH wrong error: " + e.message; }
    };
    const tmpRoot = () => {
      for (const f of ["AGENTS.md", "AGENTS.rules.md"]) fs.copyFileSync(path.join(root, f), path.join(tmp, f));
      return tmp;
    };
    let out;
    if (mode === "intact") {
      const arms = Object.fromEntries(gen.ARMS.map((a) => [a, gen.buildCorpus(a).split("\n")]));
      const p = arms.prohibition, q = arms.positive, n = arms.none;
      const changed = p.filter((l, i) => l !== q[i]).length;
      const pSet = new Map(); p.forEach((l) => pSet.set(l, (pSet.get(l) || 0) + 1));
      const nSet = new Map(); n.forEach((l) => nSet.set(l, (nSet.get(l) || 0) + 1));
      let removed = 0; for (const [l, c] of pSet) removed += c - (nSet.get(l) || 0);
      const why = [];
      if (p.length !== q.length || changed !== 4) why.push(`positive changes ${changed} lines (want 4)`);
      if (p.length - n.length !== 8 || removed !== 8) why.push(`none removes ${p.length - n.length}/${removed} lines (want 8)`);
      const removedLines = p.filter((l) => !nSet.has(l));
      if (JSON.stringify(tags(p.join("\n"))) !== JSON.stringify(tags(q.join("\n")))) why.push("positive [tag] tokens differ from prohibition");
      const pTagsKept = tags(p.filter((l) => !removedLines.includes(l)).join("\n"));
      if (JSON.stringify(pTagsKept) !== JSON.stringify(tags(n.join("\n")))) why.push("none [tag] tokens differ on surviving lines");
      out = why.length ? "MISMATCH " + why.join("; ") : `OK positive=4 changed, none=8 removed, tags identical (${tags(p.join("\n")).length} tokens)`;
    } else if (mode === "fixture-body-mutated") {
      const f = JSON.parse(JSON.stringify(fixture));
      f[id].prohibition = f[id].prohibition.replace("Never", "Do not");
      fs.writeFileSync(path.join(tmp, "bodies.json"), JSON.stringify(f));
      out = expectThrow(() => gen.buildCorpus("prohibition", { fixture: path.join(tmp, "bodies.json") }), /hash-lock/);
    } else if (mode === "fixture-rehashed") {
      const f = JSON.parse(JSON.stringify(fixture));
      f[id].prohibition = f[id].prohibition.replace("Never", "Do not");
      f[id].prohibition_sha256 = sha(f[id].prohibition);
      fs.writeFileSync(path.join(tmp, "bodies.json"), JSON.stringify(f));
      out = expectThrow(() => gen.buildCorpus("positive", { fixture: path.join(tmp, "bodies.json") }), /hash-lock: live body/);
    } else if (mode === "live-body-drifted") {
      const r = tmpRoot();
      const p = path.join(r, "AGENTS.rules.md");
      fs.writeFileSync(p, fs.readFileSync(p, "utf8").replace(fixture[id].prohibition, fixture[id].prohibition + " Extra."));
      out = expectThrow(() => gen.buildCorpus("none", { root: r }), /hash-lock: live body/);
    } else if (mode === "pointer-duplicated") {
      const r = tmpRoot();
      const p = path.join(r, "AGENTS.md");
      fs.appendFileSync(p, `\n- [id: ${id}]\n`);
      out = expectThrow(() => gen.buildCorpus("none", { root: r }), /exactly 1/);
    } else if (mode === "positive-tag-moved") {
      const f = JSON.parse(JSON.stringify(fixture));
      f[id].positive = f[id].positive.replace(/ \[id: [^\]]*\]/, "");
      fs.writeFileSync(path.join(tmp, "bodies.json"), JSON.stringify(f));
      out = expectThrow(() => gen.buildCorpus("positive", { fixture: path.join(tmp, "bodies.json") }), /tag/);
    } else if (mode === "promptfoo-shape") {
      const r = gen.positive({ vars: { input: "hello" }, provider: { id: "x" }, config: {} });
      out = Array.isArray(r) && r.length === 2 && r[0].role === "system" && r[1].role === "user" && r[1].content === "hello"
        ? "OK [system corpus, user input]" : "MISMATCH " + JSON.stringify(r).slice(0, 120);
    } else {
      out = "MISMATCH unknown mode " + mode;
    }
    process.stdout.write(out + "\n");
  ' "$1" "$2" 2>&1 || true
}

for mode in intact fixture-body-mutated fixture-rehashed live-body-drifted pointer-duplicated positive-tag-moved promptfoo-shape; do
  cases=$((cases + 1))
  d="$TMP/$mode"; mkdir -p "$d"
  res="$(arm_check "$mode" "$d")"
  if [[ "$res" == OK* ]]; then ok "arms $mode: ${res#OK }"; else bad "arms $mode" "$res"; fi
done
# The committed fixture must be byte-identical after the mutations above (they used temp copies).
cases=$((cases + 1))
if node -e '
  const fs = require("node:fs"); const crypto = require("node:crypto"); const path = require("node:path");
  const f = JSON.parse(fs.readFileSync(path.join(process.env.SKILL_DIR, "prompts", "rule-phrasing-bodies.json"), "utf8"));
  for (const id of Object.keys(f)) if (crypto.createHash("sha256").update(f[id].prohibition, "utf8").digest("hex") !== f[id].prohibition_sha256) process.exit(1);
'; then ok "committed fixture intact (every prohibition hashes to its prohibition_sha256)"; else bad "committed fixture intact" "a prohibition body no longer matches its sha256"; fi

# --- CLI shape ----------------------------------------------------------------------------
node -e '
  const path = require("node:path");
  const { expand } = require(path.join(process.env.FIX, "expand.cjs"));
  require("node:fs").writeFileSync(process.argv[1], JSON.stringify(expand(path.join(process.env.FIX, "E0-clear-win.json")).json));
' "$TMP/e0.json"

cases=$((cases + 1))
rc=0; out="$(node "$VERDICT" "$TMP/e0.json" 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 0 && "$(printf '%s\n' "$out" | wc -l)" -eq 1 && "$out" == *'"token":"EXTEND"'* ]]; then ok "cli: one-line JSON, exit 0, token EXTEND"; else bad "cli: valid run" "rc=$rc out=${out:0:160}"; fi

cases=$((cases + 1))
rc=0; node "$VERDICT" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "cli: no args exits 2"; else bad "cli: no args" "rc=$rc (want 2)"; fi

cases=$((cases + 1))
rc=0; node "$VERDICT" "$TMP/e0.json" --repeat zero >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "cli: bad --repeat exits 2"; else bad "cli: bad --repeat" "rc=$rc (want 2)"; fi

cases=$((cases + 1))
rc=0; out="$(node "$VERDICT" "$TMP/does-not-exist.json" 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 1 && "$out" == *'"token":null'* ]]; then ok "cli: unreadable input fails closed (exit 1, token null)"; else bad "cli: fail-closed" "rc=$rc out=${out:0:160}"; fi

cases=$((cases + 1))
rc=0; out="$(node "$VERDICT" "$TMP/e0.json" --repeat 2 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 0 && "$out" == *'"token":"ABORTED"'* ]]; then ok "cli: declared repeat 2 vs 3-result cells -> ABORTED"; else bad "cli: declared repeat mismatch" "rc=$rc out=${out:0:160}"; fi

cases=$((cases + 1))
rc=0; out="$(node "$VERDICT" "$TMP/e0.json" --expected-models 4 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 0 && "$out" == *'"token":"ABORTED"'* && "$out" == *'model count 3 != expected 4'* ]]; then ok "cli: a missing model's column -> ABORTED"; else bad "cli: expected-models mismatch" "rc=$rc out=${out:0:160}"; fi

cases=$((cases + 1))
if node -e '
  const path = require("node:path");
  const m = require(path.join(process.env.SKILL_DIR, "scripts", "measure-rule-compliance.cjs"));
  try { m("x", { vars: { rule: "no-such-rule" } }); process.exit(1); } catch (e) { process.exit(/unknown vars.rule/.test(e.message) ? 0 : 1); }
'; then ok "measure: unknown vars.rule throws"; else bad "measure: unknown vars.rule" "did not throw"; fi

# --- accounting + anti-vacuity floor ----------------------------------------------------
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\nFATAL: accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
# Measured on this tree: 12 verdict fixtures + 31 samples + 8 arm cases + 7 CLI/measure = 58.
EXPECTED_ASSERTIONS=58
# ONE simple assignment directly above the floor `if` (guard-vacuity-floor.test.sh slices it).
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
if [[ "$cases" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: only %s assertion(s) executed, floor is %s. The battery ran but did not assert.\n' \
    "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi

if [[ "$fails" -ne 0 ]]; then
  echo "rule-phrasing: $fails of $cases assertion(s) failed"
  exit 1
fi
echo "rule-phrasing: all $cases assertions passed"
