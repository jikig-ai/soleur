---
page: connect-repo-onboarding
status: draft
created: 2026-03-29
revised: 2026-03-29
owner: CMO
context: Signup flow page between "Setup API Key" and "Dashboard"
---

<!-- Revision 2026-03-29 v3
Changes:
- Aligned with updated brand guide dual-register voice system
- Replaced "8 departments" with "your AI team" throughout (general register)
- Replaced "AI organization" / "organization" with "AI team"
- New heading aligned with value prop framings: "Give Your AI Team the Full Picture"
- Replaced C-suite acronyms in loading state with business function names
- Added trust scaffolding to States 1, 5, and 6
- Fixed "code folder" to "project folder" for consistency in State 4
- Updated implementation notes for general-register terminology

Previous revision: v2
Changes:
- Rewrote all states for non-technical founder accessibility
- Introduced "repository" concept with plain-language context on first use
- Swapped card order: "Create New Project" is now the primary card (Option A)
- "Connect Existing Repository" is now the secondary card (Option B)
- Replaced jargon throughout: "cloning" -> "copying your project files",
  "scaffolding" -> "set up", "GitHub App" -> plain-language explanation
- Added plain-language GitHub context to the redirect interstitial
- Reframed repo selection as project selection with repository context
- Simplified error states: removed "clone" language, added GitHub context
- Preserved all technical accuracy and implementation notes
- Maintained brand voice: peer-to-peer, direct, no fluff

Previous revision history:
- Heading: resolved to Variant A with stronger verb "Equip" per CMO feedback
- Scope: removed "public only" language; both public and private repos supported
- Added: "Create new repo" flow copy (Option B)
- Added: GitHub redirect interstitial microcopy
- Added: 5-step loading checklist (replacing 3 rotating messages) per wireframe
- Added: "What happens next" block per wireframe
- Added: success state stats card labels per wireframe
- Added: dynamic confirm button pattern (Connect [owner/repo-name])
- Fixed: "8 departments" used consistently throughout
- Fixed: CTA button color implementation note (gold gradient, not green/teal)
- Verified: interrupted install state copy (already covered, no changes needed)
- Verified: empty repo list state copy (already covered, clarified actionability)
-->

# Connect Repo -- Onboarding Page Copy

All copy for the "Connect Repository" step in the Soleur signup flow.
Organized by page state. Character counts provided for layout planning.

---

## State 1: Initial (Three Options)

### Page Heading

> Give Your AI Team the Full Picture

**Character count:** 34

### Subheading

> Your AI team works best when it understands your actual business --
> your decisions, your patterns, what you have built so far. Connect
> a project so your team starts with real context, not a blank slate.

**Character count:** 206

### Trust Scaffolding

> You stay in control -- your AI team proposes changes, you decide what ships.

**Character count:** 76

### Option A: Create New Project

**Button label:** Create New Project

**Description:** Starting from scratch? We create a project workspace
on GitHub (owned by Microsoft) under your own account -- you keep full
ownership of your code and data. Your AI team gets a home base
from day one.

**Character count (description):** 195

### Option B: Connect Existing Project

**Button label:** Connect Existing Project

**Description:** Already have code on GitHub? Connect it and your
AI team starts with full context -- your architecture, your patterns,
your decisions.

**Character count (description):** 146

### Option C: Skip for Now

**Link text:** Skip this step -- you can connect a project later from Settings.

**Character count:** 61

---

## State 1a: Create New Project Flow

### Heading

> Create a New Project

**Character count:** 20

### Project Name Input

**Label:** Project name

**Placeholder:** my-company

**Helper text:** This becomes a repository (a project folder) on GitHub,
where your code and files are stored.

**Character count (helper):** 90

### Visibility Selector

**Label:** Visibility

**Options:**

- **Private** -- Only you and people you invite can see this project.
  Recommended for most companies.
- **Public** -- Anyone on the internet can see this project. Choose this
  if you plan to share your work openly.

**Default selection:** Private

### What Gets Set Up

**Label (collapsed by default):** What do we set up for you?

**Body:** We create your project on GitHub and add a `knowledge-base/`
folder -- your company's institutional memory. Everything your AI team
learns about your business stays here and compounds over time. You can
reorganize it anytime.

**Character count (body):** 199

### Confirm Button

**Button label:** Create and Connect

**Character count:** 18

---

## State 2: GitHub Redirect

### Interstitial Microcopy

Displayed near the "Connect Existing Project" button, before redirect.

> **What is GitHub?** GitHub is a trusted platform, owned by Microsoft,
> where millions of developers and companies store their project files
> securely. We need to connect to it so your AI team can read and work
> on your project.

**Character count:** 210

> **Why your own GitHub account?** Your project is created under your
> GitHub account, not ours. You own your code and data completely.
> This also keeps your files separate from every other Soleur user --
> no shared storage, no co-mingled data.

**Character count:** 214

> You will be redirected to GitHub to approve access for Soleur.
> This lets your AI team read your code and open pull requests
> (proposed code changes). You will return here automatically.

**Character count:** 192

---

## State 3: Permission Explainer (Microcopy)

**Label:** What access are you granting?

**Body:**

- **Project files** -- read and write access, so your AI team can
  read your code and propose changes
- **Project info** -- read-only, for project names and branch info

Nothing else. No access to your GitHub profile, other projects, or billing.

### Security Reassurance

> Soleur uses short-lived access tokens that expire after one hour.
> We never store long-lived credentials. Every session gets a fresh
> token scoped to the projects you selected.

**Character count:** 187

---

## State 4: Repo Selection (Post GitHub Approval)

### Heading

> Select a Project

**Character count:** 16

### Subheading

> Choose which project your AI team will work on. Each project below
> is a repository (a project folder) from your GitHub account.

**Character count:** 133

### Search Placeholder

> Search your projects...

**Character count:** 22

### Empty State

**Heading:** No projects found

**Body:** Soleur can only see projects you gave it access to in the
previous step. You can update which projects Soleur can access, or
connect a different GitHub account.

**Character count (body):** 165

**Primary action:** Update Project Access

**Secondary action:** Connect a Different Account

### Confirm Selection Button

**Button label:** Connect [owner/repo-name]

**Implementation note:** Dynamic -- inserts the selected owner and repo name.
Example: "Connect foundername/saas-product". Falls back to "Connect
Project" if selection data is unavailable.

**Character count (example):** 33

---

## State 5: Loading / Setting Up

This state may last 30+ seconds. Copy should reinforce the value of
what is happening, not fill dead air.

### Primary Message

> Setting up your AI team...

**Character count:** 27

### Progress Checklist

Display as a 5-step checklist. Each step shows a spinner while active,
a checkmark when complete. Steps advance sequentially -- step 1 is
the actual slow operation; steps 2-5 complete quickly.

| Step | Label | Chars |
|------|-------|-------|
| 1 | Copying [repo-name] into your workspace | 39+ |
| 2 | Scanning project structure | 26 |
| 3 | Detecting knowledge base | 24 |
| 4 | Analyzing conventions and patterns | 34 |
| 5 | Preparing your AI team to work on your project | 47 |

**Implementation note:** Step 1 label is dynamic -- insert the repo name.
Example: "Copying saas-product into your workspace".
Steps 2-5 use fixed labels.

### What Happens Next

Displayed below the checklist while loading completes.

> Your AI team -- marketing, engineering, legal, finance, and more --
> will have full context on your project from the first conversation.

**Character count:** 115

### Trust Signal

> Your code stays in your GitHub account. Your AI team reads it --
> you decide what changes get made.

**Character count:** 96

---

## State 6: Success

### Completion Message

**Heading:** Your AI team is ready.

**Character count:** 23

### Stats Card

Displayed as a compact card summarizing the connected project.

| Label | Value (dynamic) | Example |
|-------|-----------------|---------|
| Project | [owner/repo-name] | foundername/saas-product |
| Language | [detected primary language] | TypeScript |
| Visibility | Public or Private | Private |
| Knowledge base | Detected or Not found | Detected |
| Departments ready | 8 | 8 |

**Implementation note:** "Departments ready" is always 8. "Knowledge base"
shows "Detected" if a `knowledge-base/` directory exists in the repo,
"Not found" otherwise. Language is the primary language detected during
the project scan.

### Body

> Your AI team. Your project. Full context from the first conversation.

**Character count:** 55

### Trust Signal

> You are always the decision-maker. Your AI team proposes -- you approve.

**Character count:** 72

### CTA Button

**Button label:** Open Dashboard

**Character count:** 14

---

## State 7: Error -- Setup Failed

**Heading:** We could not set up your project

**Body:** Something went wrong while copying your project files. This
usually means an access issue or a temporary problem on GitHub's end.

**Actions:**

- **Primary button:** Retry Connection
- **Secondary link:** Check GitHub's status page
- **Tertiary link:** Connect a different project

---

## State 8: Error -- GitHub Approval Interrupted

**Heading:** GitHub approval did not complete

**Body:** The approval process was interrupted before finishing.
Nothing was changed on your GitHub account and no access was granted.

**Action:** Try Again

---

## Implementation Notes

- All headings use Cormorant Garamond per brand guide.
- Body text and descriptions use Inter.
- CTA buttons use the gold gradient (D4B36A to B8923E). Do not use
  green, teal, or any other color for primary CTAs.
- Skip link uses Text Tertiary (#6A6A6A), not gold.
- Loading checklist steps should animate: spinner while active, checkmark
  on complete. Use subtle fade transitions, not hard-cuts.
- No emojis anywhere on this page.
- The word "plugin" must not appear anywhere in this flow.
- This page uses the **general register** per the brand guide's
  dual-register voice system. Use "your AI team" not "8 departments"
  or "63 agents" in user-facing copy. The stats card label
  "Departments ready: 8" is the one exception (data display context).
- The word "repository" is introduced with a parenthetical definition
  on first meaningful use, then used naturally afterward. In headings
  and buttons facing the user, prefer "project" over "repository"
  except where technical precision is required (e.g., the stats card).
