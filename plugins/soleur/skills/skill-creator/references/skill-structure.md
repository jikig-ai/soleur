<overview>
Skills have three structural components: YAML frontmatter (metadata), a markdown-heading body (content organization), and progressive disclosure (file organization). This reference defines requirements and best practices for each component.
</overview>

<body_structure_requirements>
<critical_rule>
**Markdown headings structure a skill body; XML tags are optional semantic wrappers inside a section and never replace headings.** Use `#` for the skill title, `##` for each major section, and `###` below that. Keep markdown formatting within content (bold, italic, lists, code blocks, links).

Measured basis: 102/102 shipped Soleur `SKILL.md` bodies use `#` headings, and 4 of them also use XML wrappers inside a section. A body built only from top-level tags, with no headings, is the anti-pattern.
</critical_rule>

<required_sections>
Every skill body carries these, as headings:

- **`# <Skill Name>`** followed by what the skill does and why it matters (1-3 paragraphs)
- **`## Quick start`** (or the first numbered phase) - immediate, actionable guidance
- **A completion criterion** - a `## Success criteria` section, or an explicit exit condition closing each phase
</required_sections>

<conditional_sections>
Add based on skill complexity and domain requirements:

- **`## Context`** - Background/situational information
- **`## Workflow`** or **`## Phase N: ...`** - Step-by-step procedures
- **`## Advanced features`** - Deep-dive topics (progressive disclosure)
- **`## Validation`** - How to verify outputs
- **`## Examples`** - Multi-shot learning
- **`## Anti-patterns`** or **`## Sharp Edges`** - Common mistakes to avoid
- **`## Security checklist`** - Non-negotiable security patterns
- **`## Testing`** - Testing workflows
- **`## References`** - Links to reference files

See [authoring-levers.md](authoring-levers.md) for co-location: everything about one concept (what it is, how it applies, where it breaks) lives in one section.
</conditional_sections>

<section_selection>
**Simple skills** (single domain, straightforward):

- Required sections only
- Example: Text extraction, file format conversion

**Medium skills** (multiple patterns, some complexity):

- Required sections + workflow/examples as needed
- Example: Document processing with steps, API integration

**Complex skills** (multiple domains, security, APIs):

- Required sections + conditional sections as appropriate
- Example: Payment processing, authentication systems, multi-step workflows
</section_selection>

<optional_xml_wrappers>
Inside a section, an XML tag can mark a discrete block the model must treat as one unit: an input/output example pair, a template to copy verbatim, a checklist. The heading still names the section; the tag only bounds the block:

```markdown
## Examples

<example number="1">
<input>User input</input>
<output>Expected output</output>
</example>
```

When you use a wrapper, close it, and nest it inside a heading rather than in place of one.
</optional_xml_wrappers>

<section_naming_conventions>
Use descriptive heading names:

- `## Workflow` not `## Steps stuff`
- `## Success criteria` not `## Done`
- `## Anti-patterns` not `## Don't do`

Be consistent within your skill. If you use `## Workflow`, don't also use `## Process` for the same purpose (unless they serve different roles).
</section_naming_conventions>
</body_structure_requirements>

<yaml_requirements>
<required_fields>

```yaml
---
name: skill-name-here
description: What it does and when to use it (third person, specific triggers)
---
```

</required_fields>

<name_field>
**Validation rules**:

- Maximum 64 characters
- Lowercase letters, numbers, hyphens only
- No XML tags
- No reserved words: "anthropic", "claude"
- Must match directory name exactly

**Examples**:

- ✅ `process-pdfs`
- ✅ `manage-facebook-ads`
- ✅ `setup-stripe-payments`
- ❌ `PDF_Processor` (uppercase)
- ❌ `helper` (vague)
- ❌ `claude-helper` (reserved word)
</name_field>

<description_field>
**Validation rules**:

- Non-empty, maximum 1024 characters
- No XML tags
- Third person (never first or second person)
- Include what it does AND when to use it

**Critical rule**: Always write in third person.

- ✅ "Processes Excel files and generates reports"
- ❌ "I can help you process Excel files"
- ❌ "You can use this to process Excel files"

**Structure**: Include both capabilities and triggers.

**Effective examples**:

```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

```yaml
description: Analyze Excel spreadsheets, create pivot tables, generate charts. Use when analyzing Excel files, spreadsheets, tabular data, or .xlsx files.
```

```yaml
description: Generate descriptive commit messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes.
```

**Avoid**:

```yaml
description: Helps with documents
```

```yaml
description: Processes data
```

</description_field>
</yaml_requirements>

<naming_conventions>
Use **`<noun|domain>-<verb>` prefix-grouping** for skill names: the shared grouping token comes
first, the action second. Shipped evidence -- `flag-create`, `flag-delete`, `flag-list`,
`flag-set-role`; `cron-list`, `cron-delete`; `legal-audit`, `legal-generate`; `operator-digest`,
`operator-rephrase`; `release-announce`, `release-docs`. **No shipped Soleur skill uses the
verb-first `create-*` / `setup-*` / `manage-*` / `generate-*` form.** Why the prefix leads: a sorted
skill list then reads as families rather than as a flat wall, so every `flag-*` skill is found in
one place -- which is how `plugins/soleur/commands/help.md` renders the listing.

The patterns below are retained as upstream illustrations of the **pattern** shape (one pattern per
capability class), not as Soleur name templates. Read them for the grouping idea, not for the word
order.

<pattern name="create">
Building/authoring tools

Examples: `create-agent-skills`, `create-hooks`, `create-landing-pages`
</pattern>

<pattern name="manage">
Managing external services or resources

Examples: `manage-facebook-ads`, `manage-zoom`, `manage-stripe`, `manage-supabase`
</pattern>

<pattern name="setup">
Configuration/integration tasks

Examples: `setup-stripe-payments`, `setup-meta-tracking`
</pattern>

<pattern name="generate">
Generation tasks

Examples: `generate-ai-images`
</pattern>

<avoid_patterns>

- Vague: `helper`, `utils`, `tools`
- Generic: `documents`, `data`, `files`
- Reserved words: `anthropic-helper`, `claude-tools`
- Inconsistent: Directory `facebook-ads` but name `facebook-ads-manager`
</avoid_patterns>
</naming_conventions>

<progressive_disclosure>
<principle>
SKILL.md serves as an overview that points to detailed materials as needed. This keeps context window usage efficient.
</principle>

<practical_guidance>

- Keep SKILL.md body under 500 lines
- Split content into separate files when approaching this limit
- Keep references one level deep from SKILL.md
- Add table of contents to reference files over 100 lines
</practical_guidance>

<pattern name="high_level_guide">
Quick start in SKILL.md, details in reference files:

````markdown
---
name: pdf-processing
description: Extracts text and tables from PDF files, fills forms, and merges documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
---

# PDF Processing

Extract text and tables from PDF files, fill forms, and merge documents using Python libraries.

## Quick start

Extract text with pdfplumber:

```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

## Advanced features

**Form filling**: See [forms.md](forms.md)
**API reference**: See [reference.md](reference.md)
````

Claude loads forms.md or reference.md only when needed.
</pattern>

<pattern name="domain_organization">
For skills with multiple domains, organize by domain to avoid loading irrelevant context:

```

bigquery-skill/
├── SKILL.md (overview and navigation)
└── reference/
    ├── finance.md (revenue, billing metrics)
    ├── sales.md (opportunities, pipeline)
    ├── product.md (API usage, features)
    └── marketing.md (campaigns, attribution)

```

When user asks about revenue, Claude reads only finance.md. Other files stay on filesystem consuming zero tokens.
</pattern>

<pattern name="conditional_details">
Show basic content in SKILL.md, link to advanced in reference files:

```markdown
# DOCX Processing

Process DOCX files with creation and editing capabilities.

## Quick start

### Creating documents

Use docx-js for new documents. See [docx-js.md](docx-js.md).

### Editing documents

For simple edits, modify the document XML directly.

**For tracked changes**: See [redlining.md](redlining.md)
**For OOXML details**: See [ooxml.md](ooxml.md)
```

Claude reads redlining.md or ooxml.md only when the user needs those features.
</pattern>

<critical_rules>
**Keep references one level deep**: All reference files should link directly from SKILL.md. Avoid nested references (SKILL.md → advanced.md → details.md) as Claude may only partially read deeply nested files.

**Add table of contents to long files**: For reference files over 100 lines, include a table of contents at the top.

**Structure reference files with headings too**: Reference files follow the same rule as `SKILL.md`: markdown headings for structure, XML wrappers optional inside a section. (Some older skill-creator references, this one included, still carry top-level tags as content labels; do not copy that shape into new files.)
</critical_rules>
</progressive_disclosure>

<file_organization>
<filesystem_navigation>
Claude navigates your skill directory using bash commands:

- Use forward slashes: `reference/guide.md` (not `reference\guide.md`)
- Name files descriptively: `form_validation_rules.md` (not `doc2.md`)
- Organize by domain: `reference/finance.md`, `reference/sales.md`
</filesystem_navigation>

<directory_structure>
Typical skill structure:

```
skill-name/
├── SKILL.md (main entry point, markdown headings)
├── references/ (optional, for progressive disclosure)
│   ├── guide-1.md (markdown headings)
│   ├── guide-2.md (markdown headings)
│   └── examples.md (markdown headings)
└── scripts/ (optional, for utility scripts)
    ├── validate.py
    └── process.py
```

</directory_structure>
</file_organization>

<anti_patterns>
<pitfall name="tag_only_body">
✅ Structure the body with markdown headings; wrap a discrete block in a tag only inside a section:

```markdown
# PDF Processing

PDF processing with text extraction, form filling, and merging.

## Quick start
Extract text...

## Advanced features
Form filling...
```

❌ Anti-pattern: a tag-only body with no headings, where top-level tags stand in for sections:

```xml
<objective>
PDF processing with text extraction, form filling, and merging.
</objective>

<quick_start>
Extract text...
</quick_start>
```

</pitfall>

<pitfall name="vague_descriptions">
- ❌ "Helps with documents"
- ✅ "Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction."
</pitfall>

<pitfall name="inconsistent_pov">
- ❌ "I can help you process Excel files"
- ✅ "Processes Excel files and generates reports"
</pitfall>

<pitfall name="wrong_naming_convention">
- ❌ Directory: `facebook-ads`, Name: `facebook-ads-manager`
- ✅ Directory: `manage-facebook-ads`, Name: `manage-facebook-ads`
- ❌ Directory: `stripe-integration`, Name: `stripe`
- ✅ Directory: `setup-stripe-payments`, Name: `setup-stripe-payments`
</pitfall>

<pitfall name="deeply_nested_references">
Keep references one level deep from SKILL.md. Claude may only partially read nested files (SKILL.md → advanced.md → details.md).
</pitfall>

<pitfall name="windows_paths">
Always use forward slashes: `scripts/helper.py` (not `scripts\helper.py`)
</pitfall>

<pitfall name="missing_required_sections">
Every skill needs a `#` title with its purpose, a `## Quick start` (or first phase), and a completion criterion (`## Success criteria` or a per-phase exit condition).
</pitfall>
</anti_patterns>

<validation_checklist>
Before finalizing a skill, verify:

- ✅ YAML frontmatter valid (name matches directory, description in third person)
- ✅ Body structured with markdown headings (XML tags, if any, only wrap blocks inside a section)
- ✅ Required sections present: title + purpose, quick start, completion criterion
- ✅ Conditional sections appropriate for complexity level
- ✅ Any XML wrappers closed and nested inside a heading
- ✅ Progressive disclosure applied (SKILL.md < 500 lines)
- ✅ Reference files structured with markdown headings
- ✅ File paths use forward slashes
- ✅ Descriptive file names
</validation_checklist>
