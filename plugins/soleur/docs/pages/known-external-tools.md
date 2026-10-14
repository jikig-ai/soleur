---
title: "Known external tools — output filters and Soleur's evidence surface"
description: "Posture, diagnostics, and footguns for user-installed output-filtering tools (rtk, Headroom, proxy middleware) interacting with Soleur's guards and evidence literals."
layout: base.njk
permalink: known-external-tools/
---

<section class="page-hero">
  <div class="container">
    <h1>Known external tools</h1>
    <p>What happens when a user-installed output filter sits between your shell and the agent.</p>
  </div>
</section>

<section class="content">
<div class="container">

<p>Tools like <strong>rtk</strong> and <strong>Headroom</strong> reduce token usage by
rewriting command output before the model sees it. Soleur does not adopt, bundle, or
endorse them — but users install them independently, and when something then breaks the
question becomes "Soleur defect or filter ate the evidence?" This page is the answer key.</p>

<h2>The detection marker</h2>

<p>At every session boundary (<code>startup|resume|clear|compact</code>) the
<code>ext-filter-detect.sh</code> hook emits one <code>systemMessage</code> line per detected
tool — or <code>SOLEUR_EXT_FILTER tool=none</code> when nothing is found, so a dead hook is
distinguishable from no filter:</p>

<pre>SOLEUR_EXT_FILTER tool=&lt;t&gt; version=&lt;v&gt; posture=&lt;p&gt; via=&lt;evidence&gt; measured_at=&lt;date|-&gt; [path=&lt;settings&gt;] ref=soleur.ai/known-external-tools

abbreviated forms:  SOLEUR_EXT_FILTER tool=none ref=soleur.ai/known-external-tools
                    SOLEUR_EXT_FILTER tool=proxy posture=unknown via=proxy-env measured_at=- ref=soleur.ai/known-external-tools</pre>

<p>The marker is a <strong>stable contract</strong>: field names, ordering, and the posture
enum are frozen — bug reports and triage muscle memory parse it literally. When several
detectors fire, the markers are newline-joined inside <em>one</em>
<code>systemMessage</code> object — never N separate objects (the harness's parse must stay
single-document). <code>via=</code> is comma-joined evidence: <code>on-path</code> (PATH hit),
<code>settings-hook</code> (wired into a settings file), <code>proxy-env</code>
(non-default endpoint); a corroborated tool reads
<code>via=on-path,settings-hook</code>.
<code>systemMessage</code> is operator-facing and costs zero model tokens; severity
escalation lives in this page, never in marker adjectives. Any <code>path=</code> field is
tilde-collapsed (<code>~/.claude/settings.json</code>) — it never carries your absolute home
directory. The marker is <strong>Claude-Code-only</strong>: Devin, Grok, and other harnesses
run no SessionStart hooks, so their sessions have no marker — and that absence does
<strong>not</strong> mean "no filter" (use the manual check in rung 1 below).
Kill switch: <code>SOLEUR_DISABLE_EXT_FILTER_DETECT=1</code>.</p>

<h2>Posture tiers</h2>

<table>
<thead><tr><th>posture</th><th>meaning</th></tr></thead>
<tbody>
<tr><td><code>unmeasured</code></td><td>Soleur's gate-literal divergence harness has <em>not</em> run against this tool. Explicitly <strong>not</strong> an assurance of compatibility.</td></tr>
<tr><td><code>literal-clean</code></td><td>The divergence harness measured zero lost gate-literals on the committed corpus. Asserts literal survival only — not behavioral or instruction-following compatibility.</td></tr>
<tr><td><code>measured-incompatible</code></td><td>Gate-literal divergence measured (see Headroom below). Only emitted when the tool's identity is corroborated and its version is at or below the measured version.</td></tr>
<tr><td><code>tool=proxy posture=unknown</code></td><td><code>ANTHROPIC_BASE_URL</code> points at a non-default endpoint. A generic proxy (LiteLLM, Helicone, corporate egress) is never emitted under a vendor name — it is your infrastructure, and its filter posture is simply unknown to us.</td></tr>
<tr><td><code>tool=none</code></td><td>No filter detected by any arm. (Not "no filter exists" — four arms can still miss an unusual install.)</td></tr>
</tbody>
</table>

<h2>Per-tool posture</h2>

<table>
<thead><tr><th>tool</th><th>posture</th><th>basis</th></tr></thead>
<tbody>
<tr>
  <td><strong>rtk</strong></td>
  <td><code>unmeasured</code></td>
  <td>Divergence harness has not yet run against rtk on this host
  (<code>plugins/soleur/scripts/ext-filter-divergence.sh</code> reports
  <code>SKIPPED reason=rtk-absent</code> here). The posture is a point-in-time
  statement: when a measurement lands it is stamped
  <code>measured on rtk &lt;version&gt;, &lt;date&gt;</code>, and after any rtk upgrade
  re-run the harness — the claim does not follow the tool forward.</td>
</tr>
<tr>
  <td><strong>Headroom</strong></td>
  <td><code>measured-incompatible</code> (≤ v0.37.0)</td>
  <td>Archived eval, 2026-09-07, <code>headroom-ai==0.37.0</code>, library-mode
  <code>compress()</code> only: on a corpus of 2,252 <code>tool_result</code> payloads ≥2&nbsp;kB,
  244 of 581 modified payloads dropped at least one gate-relevant literal — including
  2,367 <code>file.ext:line</code> citations and 8 <code>SOLEUR_*</code> markers — because the
  compressor restructures <code>file:line</code> references into a header plus bare line
  numbers Soleur's greps cannot read. Claim scope: gate-literal integrity under that
  version and mode.</td>
</tr>
<tr>
  <td><strong>FCC aux optimizations</strong></td>
  <td>not applicable</td>
  <td><code>free-claude-code</code>'s five local optimizations (quota probes, titles,
  suggestions, filepaths, command prefixes) are <em>proxy-layer</em> intercepts: a plugin
  cannot observe provider API traffic, so there is no surface for Soleur to judge them on.
  They are unreachable from plugin hooks, not a finding about their quality.</td>
</tr>
</tbody>
</table>

<p><em>Methodology is symmetric:</em> the same gate-literal divergence harness is the
admission test for every tool — the current asymmetry between rtk and Headroom postures is
evidence (one measured, one not yet), not favoritism.</p>

<h2>rtk command grammar (canonical table)</h2>

<p>Soleur's destructive-command guard unwraps <code>rtk</code> on every invocation shape —
a filtered subcommand (<code>rtk git status</code> runs git), an exec subcommand, or the
fallback raw exec of an unrecognized word (<code>rtk rm -rf ~</code> runs rm). The
canonical set lives in <code>plugins/soleur/scripts/lib/ext-filter-grammar.tsv</code>
(version-pinned; verified 2026-10-13 against <code>src/lib.rs</code> on develop):</p>

<pre>exec subcommands:  run|err|test|proxy|bypass|summary
string payloads:   -c | --command | --shell  →  unparsed-wrapper ask, never silent allow
globals:           -v/-vv/-vvv/--verbose, --skip-env (either position — clap global=true)</pre>

<p><strong>Coverage caveat:</strong> rtk's rewrite hook only intercepts <em>Bash</em> tool
calls. <code>Read</code>, <code>Grep</code>, and <code>Glob</code> results are not filtered —
savings claims like "90%" are scoped to terminal-output tokens, not your bill.</p>

<p><strong>Boundary-anchor coverage:</strong> since
<a href="https://github.com/jikig-ai/soleur/issues/10248">#10248</a>, boundary-anchored
gates — the <code>gh pr merge</code> review-evidence gate, <code>git commit</code> guards,
<code>git stash</code>, <code>gh issue create</code>, prod-write defers — interpolate the
shared wrapper-prefix fragment (<code>plugins/soleur/scripts/lib/wrapper-boundary.sh</code>),
so <code>rtk gh pr merge</code>, <code>sudo rtk git commit</code>,
<code>X=1 rtk gh pr merge</code> and <code>… -- rtk gh pr merge</code> reach them judged.
Two residual classes remain BY DESIGN: unknown wrappers are not unwrapped (the fragment is
a closed grammar, not a heuristic), and opaque string payloads — <code>rtk run -c '…'</code>,
<code>rtk summary --shell '…'</code> — join the hooks' existing declared-lexical-limit class
(alongside <code>bash -c '…'</code>, subshells and eval): they are not matchable without
parsing a string as shell, which the gates deliberately never do.</p>

<h2>Three-rung diagnosis</h2>

<ol>
<li><strong>Check the marker.</strong> Scroll to the session-start system messages (or
   grep the session log) for <code>SOLEUR_EXT_FILTER</code>. Agents can re-derive it:
   <code>bash &lt;plugin&gt;/hooks/ext-filter-detect.sh --self-test</code> — the flag
   bypasses the harness-env gates.
   <code>tool=none</code> means no filter detected — not "no filter exists" (an org-policy
   settings hook, or a PATH the hook process does not inherit, can still hide one). Claude
   Code sessions only —
   a Devin or other-harness session has no marker by design; there, check
   <code>command -v rtk</code> and <code>~/.claude/settings.json</code> for hook entries
   manually.</li>
<li><strong>Reproduce with the filter off.</strong> RTK's disable is
   <code>mode = "disabled"</code> in <code>~/.config/rtk/config.toml</code> (or remove its
   hook entry from settings), and the per-command escape is the
   <code>rtk run</code>/<code>rtk bypass</code> passthrough — there is no
   <code>RTK_DISABLED</code> env var (it does not exist; verified against RTK's docs
   2026-10-13). Headroom's equivalent is removing its plugin/proxy wiring.</li>
<li><strong>Compare verbatim vs filtered.</strong> Run the command both ways and diff the
   evidence the gate needed. <code>plugins/soleur/scripts/ext-filter-divergence.sh</code>
   automates exactly this over the committed corpus — verdicts
   <code>LITERAL-CLEAN|UNMEASURED|DIVERGENT|INSTRUMENT-DEFECT</code> plus
   <code>SKIPPED reason=rtk-absent</code> when rtk isn't installed (exit codes:
   0 clean-or-skipped, 1 divergent, 3 usage/env, 4 instrument-defect).</li>
</ol>

<h2>Footguns</h2>

<ul>
<li><strong><code>rtk gain</code></strong> and <strong><code>rtk session</code></strong> show
  what rtk intercepted this session — the fastest way to prove a command was filtered.
  <code>rtk discover</code> lists commands it saw but did not filter.</li>
<li><strong>Telemetry defaults</strong> (verified against
  <a href="https://github.com/rtk-ai/rtk#readme">RTK's README</a>, 2026-10-13): rtk's
  telemetry is anonymous and <strong>off by default</strong> — opt-IN via
  <code>rtk telemetry enable</code>, not opt-out. Headroom's beacon is likewise off by
  default in current releases (their docs). Both are third-party claims about their own
  practices — re-check after upgrades.</li>
<li><strong>rtk's hook emits its own permission decisions</strong> on some integrations —
  Soleur's guard judges the original command text either way (the two hook chains
  compose, not replace).</li>
<li><strong>Proxy-layer filters see your API key and full prompt stream.</strong>
  Headroom's proxy mode — and any non-default <code>ANTHROPIC_BASE_URL</code>
  endpoint — sits on the credential path, not just the output path: your key and
  every prompt and tool result transit that infrastructure before reaching
  Anthropic. Read the vendor's privacy terms <em>before</em> installing a
  proxy-mode filter or pointing <code>ANTHROPIC_BASE_URL</code> at a third-party
  endpoint; a <code>tool=proxy posture=unknown</code> marker is Soleur telling
  you the transit exists, not judging it.</li>
<li><strong>Reporting bugs:</strong> when filing, paste the full marker line into the bug
  report's marker field and answer the filter dropdown — <em>triage</em> applies the
  <code>external-env</code> label when it isn't <code>none</code> (don't add it yourself).</li>
</ul>

</div>
</section>
