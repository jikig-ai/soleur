---
last_updated: 2026-04-07
owner: CMO
status: draft
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/product/design/onboarding/onboarding-walkthrough.pen
---

# Start Fresh Onboarding -- Copy Deck

Copy for the first-run experience on the Soleur web platform dashboard.
Three states: First Run (no context), Foundations (idea captured), and
Transition (foundations complete).

---

## 1. First-Run State

The founder has just created a "Start Fresh" project. No business context
exists yet. The goal: get them to describe their startup idea in one message.

### Section Label

> COMMAND CENTER

Rationale: Keeps the label consistent with the existing dashboard header and
nav item. The founder will see this label throughout their lifecycle -- using
it from day zero builds familiarity, not confusion.

Alternative: YOUR ORGANIZATION

### Hero Heading

**Option A (recommended):**

> Tell your organization what you're building.

Rationale: Declarative, activating. Positions the founder as the one with the
vision and the system as the team that needs the briefing. Natural next action
is obvious -- type into the input.

**Option B:**

> Brief your team.

Rationale: Shortest possible. Military/executive register. May feel too terse
without surrounding visual context to carry it.

**Option C:**

> Define the mission.

Rationale: Frames the first message as a foundational act, not a casual chat.
Slightly more abstract than Option A.

### Subheading

**Option A (recommended):**

> Describe your startup idea and your AI organization will get to work.

**Option B:**

> One message turns into a vision document, brand identity, market analysis,
> and legal foundations.

**Option C:**

> Your first message sets the direction for every department.

### Chat Input Placeholder

**Option A (recommended):**

> What are you building?

Rationale: Direct, low-friction. Mirrors how a cofounder would ask. Does not
prescribe format or length.

**Option B:**

> Describe your startup in a few sentences...

**Option C:**

> My company does X for Y by doing Z...

Rationale: Gives a lightweight structural hint. Risk: some founders may try to
fill the template literally rather than thinking freely.

---

## 2. Foundations State

The founder has submitted their first message. The Vision document has been
auto-generated. The dashboard now shows 4 foundation cards -- one already
complete, three actionable.

### Section Label

> FOUNDATIONS

Rationale: A distinct label signals progress. The founder has moved from the
blank slate to a structured phase. "Foundations" communicates that these are
prerequisites, not optional tasks -- the bedrock before the real work begins.

Alternative: ORGANIZATION SETUP

### Heading

**Option A (recommended):**

> Build the foundations.

**Option B:**

> Your organization needs context.

**Option C:**

> Four briefings to full operational readiness.

### Subheading

**Option A (recommended):**

> Each card briefs a department leader. Complete them in any order.

**Option B:**

> Your AI team needs these four inputs to operate at full capacity.

**Option C:**

> Vision is set. Three briefings remain before your organization is fully
> operational.

---

### Foundation Cards

#### Card 1: Vision

| Property | Value |
|----------|-------|
| Title | Vision |
| Leader | CPO |
| Status | Complete (auto-generated from first message) |
| Done label | see below |

This card is always in the "done" state when foundations are shown. It serves
as proof that the system already acted on the founder's first message.

#### Card 2: Brand Identity

| Property | Value |
|----------|-------|
| Title | Brand Identity |
| Leader | CMO |
| Status | Not started |

**Prompt text (pre-filled into chat on click):**

> Define the brand identity for my company -- positioning, voice, and visual
> direction.

Alternative prompt:

> Build a brand guide. Cover positioning, tone of voice, and visual identity.

#### Card 3: Business Validation

| Property | Value |
|----------|-------|
| Title | Business Validation |
| Leader | CPO |
| Status | Not started |

**Prompt text (pre-filled into chat on click):**

> Run a business validation -- market research, competitive landscape, and
> business model.

Alternative prompt:

> Validate my business idea. Research the market, identify competitors, and
> define the business model.

#### Card 4: Legal Foundations

| Property | Value |
|----------|-------|
| Title | Legal Foundations |
| Leader | CLO |
| Status | Not started |

**Prompt text (pre-filled into chat on click):**

> Set up legal foundations -- privacy policy, terms of service, and
> recommended legal structure.

Alternative prompt:

> Draft the foundational legal documents. Start with privacy policy, terms,
> and entity structure recommendation.

---

### Done Label

**Recommended:** Checkmark icon only (no text).

Rationale: "Complete" and "Done" are task-management language. A checkmark
communicates the same state without the gamification connotation. The visual
distinction between a gold checkmark and the un-started card state is
sufficient.

If a text label is needed for accessibility, use **Complete** as the
aria-label / screen-reader text, but do not display it visually.

Alternative (if text is required): **Complete** -- not "Done" (too casual for
the executive briefing frame).

---

## 3. Transition State

All 4 foundation cards are complete. The dashboard transitions from the
foundations view to the full Command Center (conversation inbox with filters
and suggested prompts).

### Transition Heading

**Option A (recommended):**

> Foundations set. Your organization is operational.

Rationale: Two declarative sentences. First acknowledges completion. Second
frames the system as now fully capable. No celebration language -- just a
status change.

**Option B:**

> Every department is briefed. The Command Center is yours.

**Option C:**

> Full operational readiness.

### Transition Subheading

**Option A (recommended):**

> Start any conversation. Your team has the context to execute.

**Option B:**

> Your AI organization now has the context it needs. Direct any department
> from here.

### Display Behavior

The transition message should appear briefly (3-5 seconds or until the
founder interacts) before resolving into the standard Command Center empty
state. It is a moment of acknowledgment, not a gate. The founder should never
feel blocked.

If the transition feels disruptive, it is acceptable to skip it entirely and
show the Command Center empty state directly. The foundation cards themselves
provide closure -- a separate transition screen is optional.

---

## Copy Principles Applied

For reference, these are the brand guide constraints enforced throughout:

- **Declarative voice:** Every heading is a statement, not a question or
  invitation. No "Welcome," "Let's get started," or "Ready to begin?"
- **Founder as principal:** "Tell your organization," "Brief your team" --
  the founder directs, the system executes.
- **No gamification:** No progress bars, point systems, streak counters, or
  "X of Y complete" framing. The checkmark is a status indicator, not a
  reward.
- **No exclamation marks:** Confident tone does not need emphasis punctuation.
- **No emojis in copy:** Cards may use a single monochrome icon per the task
  brief.
- **Concise:** Headings are under 8 words. Subheadings are single sentences.
  Prompt texts are one sentence each.
- **Executive briefing register:** "Operational readiness," "briefings,"
  "foundations" -- not "setup wizard," "getting started," or "onboarding
  checklist."
