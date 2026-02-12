# Core Principles for Skill Authoring

Core principles guide skill authoring decisions. These principles ensure skills are efficient, effective, and maintainable across different models and use cases.

## Standard Markdown Format

Skills use YAML frontmatter and standard markdown headings. Use `#`, `##`, `###` for structure. Keep markdown formatting for content (bold, italic, lists, code blocks, links).

Every skill should have:
- A clear heading describing what the skill does
- A quick start section with immediate, actionable guidance
- Success criteria defining how to know it worked

## Conciseness

The context window is shared. A skill shares it with the system prompt, conversation history, other skills' metadata, and the actual request.

Only add context Claude doesn't already have. Challenge each piece of information:
- "Does Claude really need this explanation?"
- "Can I assume Claude knows this?"
- "Does this paragraph justify its token cost?"

Assume Claude is smart. Don't explain obvious concepts.

### Concise vs Verbose Example

**Concise** (~50 tokens):
```markdown
## Quick Start
Extract PDF text with pdfplumber:

```python
import pdfplumber

with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```
```

**Verbose** (~150 tokens):
```markdown
## Quick Start
PDF files are a common file format used for documents. To extract text from them, we'll use a Python library called pdfplumber. First, you'll need to import the library, then open the PDF file using the open method, and finally extract the text from each page. Here's how to do it:

```python
import pdfplumber

with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

This code opens the PDF and extracts text from the first page.
```

The concise version assumes Claude knows what PDFs are, understands Python imports, and can read code. All those assumptions are correct.

### When to Elaborate

Add explanation when:
- Concept is domain-specific (not general programming knowledge)
- Pattern is non-obvious or counterintuitive
- Context affects behavior in subtle ways
- Trade-offs require judgment

Don't add explanation for:
- Common programming concepts (loops, functions, imports)
- Standard library usage (reading files, making HTTP requests)
- Well-known tools (git, npm, pip)
- Obvious next steps

## Degrees of Freedom

Match the level of specificity to the task's fragility and variability. Give Claude more freedom for creative tasks, less freedom for fragile operations.

### High Freedom

**When to use:** Multiple approaches are valid, decisions depend on context, heuristics guide the approach, creative solutions welcome.

Example: A code review skill gives principles and criteria but lets Claude adapt the review based on what the code needs.

### Medium Freedom

**When to use:** A preferred pattern exists, some variation is acceptable, configuration affects behavior, templates can be adapted.

Example: A report generation skill provides a template and lets Claude customize based on requirements.

### Low Freedom

**When to use:** Operations are fragile and error-prone, consistency is critical, a specific sequence must be followed, deviation causes failures.

Example: A database migration skill specifies an exact command with no variation allowed.

### Matching Specificity

The key is matching specificity to fragility:

- **Fragile operations** (database migrations, payment processing, security): Low freedom, exact instructions
- **Standard operations** (API calls, file processing, data transformation): Medium freedom, preferred pattern with flexibility
- **Creative operations** (code review, content generation, analysis): High freedom, heuristics and principles

Mismatched specificity causes problems:
- Too much freedom on fragile tasks -> errors and failures
- Too little freedom on creative tasks -> rigid, suboptimal outputs

## Model Testing

Skills act as additions to models, so effectiveness depends on the underlying model. What works for Opus might need more detail for Haiku.

### Testing Across Models

Test skills with all models planned for use:

**Claude Haiku** (fast, economical) benefits from:
- More explicit instructions
- Complete examples (no partial code)
- Clear success criteria
- Step-by-step workflows

**Claude Sonnet** (balanced) benefits from:
- Balanced detail level
- Clear structure for navigation
- Progressive disclosure
- Concise but complete guidance

**Claude Opus** (powerful reasoning) benefits from:
- Concise instructions
- Principles over procedures
- High degrees of freedom
- Trust in reasoning capabilities

### Balancing Across Models

Aim for instructions that work well across all target models. A good balance provides a complete working example (for Haiku), clear defaults with escape hatches (for Sonnet), and enough context without over-explanation (for Opus).

### Iterative Improvement

1. Start with medium detail level
2. Test with target models
3. Observe where models struggle or succeed
4. Adjust based on actual performance
5. Re-test and iterate

Don't optimize for one model. Find the balance that works across target models.

## Progressive Disclosure

SKILL.md serves as an overview. Reference files contain details. Claude loads reference files only when needed.

Progressive disclosure keeps token usage proportional to task complexity:

- Simple task: Load SKILL.md only (~500 tokens)
- Medium task: Load SKILL.md + one reference (~1000 tokens)
- Complex task: Load SKILL.md + multiple references (~2000 tokens)

Without progressive disclosure, every task loads all content regardless of need.

### Implementation

- Keep SKILL.md under 500 lines
- Split detailed content into reference files
- Keep references one level deep from SKILL.md
- Link to references from relevant sections
- Use descriptive reference file names

See [skill-structure.md](./skill-structure.md) for progressive disclosure patterns.

## Validation

Validation scripts are force multipliers. They catch errors that Claude might miss and provide actionable feedback.

Good validation scripts:
- Provide verbose, specific error messages
- Show available valid options when something is invalid
- Pinpoint exact location of problems
- Suggest actionable fixes
- Are deterministic and reliable

See [workflows-and-validation.md](./workflows-and-validation.md) for validation patterns.

## Summary

- **Standard Markdown**: Use markdown headings for structure, not XML tags
- **Conciseness**: Only add context Claude doesn't have. Assume Claude is smart
- **Degrees of Freedom**: Match specificity to fragility
- **Model Testing**: Test with all target models. Balance detail level
- **Progressive Disclosure**: Keep SKILL.md concise. Split details into reference files
- **Validation**: Make validation scripts verbose and specific
