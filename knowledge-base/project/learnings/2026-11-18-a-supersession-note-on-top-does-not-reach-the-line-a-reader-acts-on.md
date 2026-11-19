---
title: A supersession note on top does not reach the line a reader acts on
date: 2026-11-18
category: workflow-patterns
module: knowledge-base
tags: [supersession, adr, archive-kb, review]
pr: 9832
issues: [9842, 12901]
---

# Learning: a supersession note on top does not reach the line a reader acts on

## Problem

PR #9832 landed two 2026-10 design docs (tenant executor brainstorm + spec) as a
historical record, with a 4-line "Superseded in part by ADR-325" note under each
title. The six-seat review found that the note, while accurate, left these gaps:

- **It sat far from the lines it overrode.** The bodies still said "Managed
  vendors: no", rejected Cloudflare Sandbox and kept EU-only. FR4, T7 and
  Decision 16 described an Anthropic-only injector. Someone reading the
  build-vs-adopt table or FR4 directly got no signal from those lines. The
  credential path (FR4) was the one with user impact: someone implementing S3
  could put a GitHub token inside the sandbox.
- **Its decision numbers collided.** "(Decision 1)" in the brainstorm reads as
  the brainstorm's own Key Decision 1, not ADR-325's.
- **It dropped a condition.** "EU-only is negotiable for a clear gain" left out
  ADR-325 Decision 3's definition (a flip fact, a passed Cloudflare trial, the
  CLO gates). That reads as a looser residency commitment than the ADR makes.
- **Its link would break on archive.** The relative ADR link was correct in place
  but broke after `archive-kb.sh` moved the files one level deeper. Three
  archived docs on main already carry broken links this way (#12901).

## Solution

- Cite the superseding ADR by repo-root path in backticks, which survives the
  archive move, and prefix every number with the ADR's name ("ADR-325 Decision 3").
- State the conditions on any loosened commitment in the note itself.
- Say "the body is left as written on <date>" and put a short inline
  `*[ADR-325: ...]*` marker on each line the note overrides, with priority on
  any line about credentials or a tenant boundary.
- Update spec frontmatter `status:` and `updated:` so a frontmatter search does
  not list the spec as a live draft.

## Key Insight

A partial-supersession note is a pointer, but the reader acts on a line in the
body. Every overridden line that a reader could build from needs its own
marker, and a link inside a file that will move must not be relative.

## Session Errors

1. **The first draft said S3 was "widened from GitHub-only"; the body never says
   that.** Recovery: removed the phrase and re-cited it. **Prevention:** for each
   claim a note adds, grep the body for the phrase it says it replaces before
   writing it.
2. **A pre-existing MD004 failure (44 errors) came from a wrapped spec line that
   began with "+".** Recovery: rejoined the line. **Prevention:** markdownlint
   catches it, so run `markdownlint-cli2` on landed docs before the first push.
3. **The relative ADR link would break after archival.** Recovery: switched to a
   repo-root path in backticks; filed #12901 for the script. **Prevention:**
   #12901, which makes `archive-kb.sh` rewrite or refuse the relative links it breaks.
4. **Bare "Decision N" citations collided with the doc's own numbering.**
   Recovery: prefixed them with "ADR-325". **Prevention:** when citing another
   document's numbered items, always name the document.
5. **Template substitution produced "are is now".** Recovery: fixed with sed and
   checked by grep. **Prevention:** read the rendered diff, not the template.
6. **The git-history seat raised a P1 that the Art. 30 register still asserts
   file-cap bwrap. It was already handled:** main has a 2026-11-03 supersession
   marker (#9851) on that entry. Recovery: dismissed with evidence.
   **Prevention:** before raising a stale-claim finding, read the lines just
   below the claim for a supersession marker.
7. **An `ls` check exited 2 on an alternate-path probe.** Recovery: confirmed
   both links resolved. **Prevention:** one-off.
8. **The issue filing was refused twice by hooks:** the body file was written in
   the same call, and the filing lacked a user-impact or machinery label.
   Recovery: wrote the file first, then added `meta/machinery`. **Prevention:**
   write the body file in its own step; label machinery findings `meta/machinery`.

## Tags

category: workflow-patterns
module: knowledge-base
