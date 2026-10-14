<overview>
This reference documents common patterns for skill authoring, including templates, examples, terminology consistency, and anti-patterns. Skill bodies are structured with markdown headings; the XML tags shown inside examples are optional wrappers around one block within a section.
</overview>

<template_pattern>
<description>
Provide templates for output format. Match the level of strictness to your needs.
</description>

<strict_requirements>
Use when output format must be exact and consistent:

```markdown
## Report Structure

ALWAYS use this exact template structure:

```markdown
# [Analysis Title]

## Executive summary
[One-paragraph overview of key findings]

## Key findings
- Finding 1 with supporting data
- Finding 2 with supporting data
- Finding 3 with supporting data

## Recommendations
1. Specific actionable recommendation
2. Specific actionable recommendation
```

```

**When to use**: Compliance reports, standardized formats, automated processing
</strict_requirements>

<flexible_guidance>
Use when Claude should adapt the format based on context:

```markdown
## Report Structure

Here is a sensible default format, but use your best judgment:

```markdown
# [Analysis Title]

## Executive summary
[Overview]

## Key findings
[Adapt sections based on what you discover]

## Recommendations
[Tailor to the specific context]
```

Adjust sections as needed for the specific analysis type.

```

**When to use**: Exploratory analysis, context-dependent formatting, creative tasks
</flexible_guidance>
</template_pattern>

<examples_pattern>
<description>
For skills where output quality depends on seeing examples, provide input/output pairs.
</description>

<commit_messages_example>
```markdown
## Objective

Generate commit messages following conventional commit format.

## Commit Message Format

Generate commit messages following these examples:

<example number="1">
<input>Added user authentication with JWT tokens</input>

### Output

```

feat(auth): implement JWT-based authentication

Add login endpoint and token validation middleware

```
</output>
</example>

<example number="2">
<input>Fixed bug where dates displayed incorrectly in reports</input>
<output>
```

fix(reports): correct date formatting in timezone conversion

Use UTC timestamps consistently across report generation

```
</output>
</example>

Follow this style: type(scope): brief description, then detailed explanation.
</commit_message_format>
```

</commit_messages_example>

<when_to_use>

- Output format has nuances that text explanations can't capture
- Pattern recognition is easier than rule following
- Examples demonstrate edge cases
- Multi-shot learning improves quality
</when_to_use>
</examples_pattern>

<consistent_terminology>
<principle>
Choose one term and use it throughout the skill. Inconsistent terminology confuses Claude and reduces execution quality.
</principle>

<good_example>
Consistent usage:

- Always "API endpoint" (not mixing with "URL", "API route", "path")
- Always "field" (not mixing with "box", "element", "control")
- Always "extract" (not mixing with "pull", "get", "retrieve")

```markdown
## Objective

Extract data from API endpoints using field mappings.

## Quick Start

1. Identify the API endpoint
2. Map response fields to your schema
3. Extract field values

```

</good_example>

<bad_example>
Inconsistent usage creates confusion:

```markdown
## Objective

Pull data from API routes using element mappings.

## Quick Start

1. Identify the URL
2. Map response boxes to your schema
3. Retrieve control values

```

Claude must now interpret: Are "API routes" and "URLs" the same? Are "fields", "boxes", "elements", and "controls" the same?
</bad_example>

<implementation>
1. Choose terminology early in skill development
2. Document key terms in the skill's opening section
3. Use find/replace to enforce consistency
4. Review reference files for consistent usage
</implementation>
</consistent_terminology>

<provide_default_with_escape_hatch>
<principle>
Provide a default approach with an escape hatch for special cases, not a list of alternatives. Too many options paralyze decision-making.
</principle>

<good_example>
Clear default with escape hatch:

```markdown
## Quick Start

Use pdfplumber for text extraction:

```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

For scanned PDFs requiring OCR, use pdf2image with pytesseract instead.

```
</good_example>

<bad_example>
Too many options creates decision paralysis:

```markdown
## Quick Start

You can use any of these libraries:

- **pypdf**: Good for basic extraction
- **pdfplumber**: Better for tables
- **PyMuPDF**: Faster but more complex
- **pdf2image**: For scanned documents
- **pdfminer**: Low-level control
- **tabula-py**: Table-focused

Choose based on your needs.

```

Claude must now research and compare all options before starting. This wastes tokens and time.
</bad_example>

<implementation>
1. Recommend ONE default approach
2. Explain when to use the default (implied: most of the time)
3. Add ONE escape hatch for edge cases
4. Link to advanced reference if multiple alternatives truly needed
</implementation>
</provide_default_with_escape_hatch>

<anti_patterns>
<description>
Common mistakes to avoid when authoring skills.
</description>

<pitfall name="tag_only_body">
❌ **BAD**: A tag-only body with no headings, where top-level tags stand in for sections:

```markdown
## Objective

PDF processing with text extraction, form filling, and merging capabilities.

## Quick Start

Extract text with pdfplumber...

## Advanced Features

Form filling requires additional setup...

```

✅ **GOOD**: Markdown headings structure the body:

```markdown
# PDF Processing

PDF processing with text extraction, form filling, and merging capabilities.

## Quick start
Extract text with pdfplumber...

## Advanced features
Form filling requires additional setup...
```

**Why it matters**: Markdown headings structure a skill body; XML tags are optional semantic wrappers inside a section and never replace headings. Every shipped Soleur `SKILL.md` (102/102 measured) uses `#` headings, so a tag-only body is the odd one out for both readers and tooling.
</pitfall>

<pitfall name="vague_descriptions">
❌ **BAD**:
```yaml
description: Helps with documents
```

✅ **GOOD**:

```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

**Why it matters**: Vague descriptions prevent Claude from discovering and using the skill appropriately.
</pitfall>

<pitfall name="inconsistent_pov">
❌ **BAD**:
```yaml
description: I can help you process Excel files and generate reports
```

✅ **GOOD**:

```yaml
description: Processes Excel files and generates reports. Use when analyzing spreadsheets or .xlsx files.
```

**Why it matters**: Skills must use third person. First/second person breaks the skill metadata pattern.
</pitfall>

<pitfall name="wrong_naming_convention">
❌ **BAD**: Directory name doesn't match skill name or verb-noun convention:
- Directory: `facebook-ads`, Name: `facebook-ads-manager`
- Directory: `stripe-integration`, Name: `stripe`
- Directory: `helper-scripts`, Name: `helper`

✅ **GOOD**: Consistent verb-noun convention:

- Directory: `manage-facebook-ads`, Name: `manage-facebook-ads`
- Directory: `setup-stripe-payments`, Name: `setup-stripe-payments`
- Directory: `process-pdfs`, Name: `process-pdfs`

**Why it matters**: Consistency in naming makes skills discoverable and predictable.
</pitfall>

<pitfall name="too_many_options">
❌ **BAD**:
```markdown
## Quick Start

You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or pdfminer, or tabula-py...

```

✅ **GOOD**:

```markdown
## Quick Start

Use pdfplumber for text extraction:

```python
import pdfplumber
```

For scanned PDFs requiring OCR, use pdf2image with pytesseract instead.

```

**Why it matters**: Decision paralysis. Provide one default approach with escape hatch for special cases.
</pitfall>

<pitfall name="deeply_nested_references">
❌ **BAD**: References nested multiple levels:
```

SKILL.md → advanced.md → details.md → examples.md

```

✅ **GOOD**: References one level deep from SKILL.md:
```

SKILL.md → advanced.md
SKILL.md → details.md
SKILL.md → examples.md

```

**Why it matters**: Claude may only partially read deeply nested files. Keep references one level deep from SKILL.md.
</pitfall>

<pitfall name="windows_paths">
❌ **BAD**:
```markdown
## Reference Guides

See scripts\validate.py for validation

```

✅ **GOOD**:

```markdown
## Reference Guides

See scripts/validate.py for validation

```

**Why it matters**: Always use forward slashes for cross-platform compatibility.
</pitfall>

<pitfall name="dynamic_context_and_file_reference_execution">
**Problem**: When showing examples of dynamic context syntax (exclamation mark + backticks) or file references (@ prefix), the skill loader executes these during skill loading.

❌ **BAD** - These execute during skill load:

```markdown
## Examples

Load current status with: !`git status`
Review dependencies in: @package.json

```

✅ **GOOD** - Add space to prevent execution:

```markdown
## Examples

Load current status with: ! `git status` (remove space before backtick in actual usage)
Review dependencies in: @ package.json (remove space after @ in actual usage)

```

**When this applies**:

- Skills that teach users about dynamic context (slash commands, prompts)
- Any documentation showing the exclamation mark prefix syntax or @ file references
- Skills with example commands or file paths that shouldn't execute during loading

**Why it matters**: Without the space, these execute during skill load, causing errors or unwanted file reads.
</pitfall>

<pitfall name="missing_required_sections">
❌ **BAD**: Missing required sections:
```markdown
## Quick start
Use this tool for processing...
```

✅ **GOOD**: All required sections present:

```markdown
# Data Processing

Process data files with validation and transformation.

## Quick start
Use this tool for processing...

## Success criteria
- Input file successfully processed
- Output file validates without errors
- Transformation applied correctly
```

**Why it matters**: Every skill needs a `#` title with its purpose, a `## Quick start` (or first phase), and a completion criterion.
</pitfall>

<pitfall name="tags_replacing_some_headings">
❌ **BAD**: A top-level tag standing in for one section while the rest use headings:
```markdown
<objective>
PDF processing capabilities
</objective>

## Quick start

Extract text with pdfplumber...

```

✅ **GOOD**: Every section is a heading; a tag, if used, wraps one block inside a section:
```markdown
# PDF Processing

PDF processing capabilities.

## Quick start

Extract text with pdfplumber...

<example>
pdfplumber.open("file.pdf").pages[0].extract_text()
</example>
```

**Why it matters**: Headings carry the structure. A wrapper bounds a block the model must treat as one unit; it is never a section of its own.
</pitfall>

<pitfall name="unclosed_xml_tags">
❌ **BAD**: Forgetting to close XML tags:
```markdown
## Objective

Process PDF files

### Quick Start

Use pdfplumber...

```

✅ **GOOD**: Properly closed tags:
```markdown
## Objective

Process PDF files

## Quick Start

Use pdfplumber...

```

**Why it matters**: Unclosed tags break XML parsing and create ambiguous boundaries.
</pitfall>
</anti_patterns>

<progressive_disclosure_pattern>
<description>
Keep SKILL.md concise by linking to detailed reference files. Claude loads reference files only when needed.
</description>

<implementation>
```markdown
## Objective

Manage Facebook Ads campaigns, ad sets, and ads via the Marketing API.

## Quick Start

### Basic Operations

See [basic-operations.md](basic-operations.md) for campaign creation and management.

## Advanced Features

**Custom audiences**: See [audiences.md](audiences.md)
**Conversion tracking**: See [conversions.md](conversions.md)
**Budget optimization**: See [budgets.md](budgets.md)
**API reference**: See [api-reference.md](api-reference.md)

```

**Benefits**:
- SKILL.md stays under 500 lines
- Claude only reads relevant reference files
- Token usage scales with task complexity
- Easier to maintain and update
</implementation>
</progressive_disclosure_pattern>

<validation_pattern>
<description>
For skills with validation steps, make validation scripts verbose and specific.
</description>

<implementation>
```markdown
## Validation

After making changes, validate immediately:

```bash
python scripts/validate.py output_dir/
```

If validation fails, fix errors before continuing. Validation errors include:

- **Field not found**: "Field 'signature_date' not found. Available fields: customer_name, order_total, signature_date_signed"
- **Type mismatch**: "Field 'order_total' expects number, got string"
- **Missing required field**: "Required field 'customer_name' is missing"

Only proceed when validation passes with zero errors.

```

**Why verbose errors help**:
- Claude can fix issues without guessing
- Specific error messages reduce iteration cycles
- Available options shown in error messages
</implementation>
</validation_pattern>

<checklist_pattern>
<description>
For complex multi-step workflows, provide a checklist Claude can copy and track progress.
</description>

<implementation>
```markdown
## Workflow

Copy this checklist and check off items as you complete them:

```

Task Progress:

- [ ] Step 1: Analyze the form (run analyze_form.py)
- [ ] Step 2: Create field mapping (edit fields.json)
- [ ] Step 3: Validate mapping (run validate_fields.py)
- [ ] Step 4: Fill the form (run fill_form.py)
- [ ] Step 5: Verify output (run verify_output.py)

```

<step_1>
**Analyze the form**

Run: `python scripts/analyze_form.py input.pdf`

This extracts form fields and their locations, saving to `fields.json`.
</step_1>

<step_2>
**Create field mapping**

Edit `fields.json` to add values for each field.
</step_2>

<step_3>
**Validate mapping**

Run: `python scripts/validate_fields.py fields.json`

Fix any validation errors before continuing.
</step_3>

<step_4>
**Fill the form**

Run: `python scripts/fill_form.py input.pdf fields.json output.pdf`
</step_4>

<step_5>
**Verify output**

Run: `python scripts/verify_output.py output.pdf`

If verification fails, return to Step 2.
</step_5>
</workflow>
```

**Benefits**:

- Clear progress tracking
- Prevents skipping steps
- Easy to resume after interruption
</implementation>

</checklist_pattern>
