# Tasks: Add Finance Domain

## 1. Token Budget Trimming

### 1.1 Audit longest agent descriptions
- Count current word budget: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`
- Identify descriptions over 55 words
- Trim to ~35-45 words while preserving disambiguation sentences
- Target: reduce budget by ~200 words to create headroom

## 2. Agent Files

### 2.1 Create `plugins/soleur/agents/finance/cfo.md`
- Follow `cro.md` template (3-phase domain leader contract)
- Assess: check `knowledge-base/finance/` artifacts, read ops expenses for cost context
- Delegate: budget-analyst, revenue-analyst, financial-reporter
- Sharp Edges: no financial advice, defer expenses to COO, defer revenue pipeline to CRO

### 2.2 Create `plugins/soleur/agents/finance/budget-analyst.md`
- Scope: budget planning, allocation, burn rate
- Disambiguation: reference revenue-analyst, financial-reporter, ops-advisor

### 2.3 Create `plugins/soleur/agents/finance/revenue-analyst.md`
- Scope: revenue tracking, forecasting, P&L projections
- Disambiguation: reference pipeline-analyst (Sales), budget-analyst, financial-reporter

### 2.4 Create `plugins/soleur/agents/finance/financial-reporter.md`
- Scope: financial summaries, cash flow statements, reporting
- Disambiguation: reference budget-analyst, revenue-analyst

### 2.5 Update `ops-advisor.md` disambiguation
- Add sentence: "Use cfo for financial analysis and budgeting; use this agent for expense tracking and vendor management"

## 3. Documentation Infrastructure

### 3.1 Update `docs/_data/agents.js`
- DOMAIN_LABELS: add finance
- DOMAIN_CSS_VARS: add finance with --cat-finance
- domainOrder: add finance after engineering

### 3.2 Update `docs/css/style.css`
- Add `--cat-finance: #26A69A;` to @layer tokens

## 4. Brainstorm Routing

### 4.1 Update `commands/soleur/brainstorm.md` Phase 0.5
- Add assessment question #8
- Add routing block for CFO
- Add participation block for CFO

## 5. Project Documentation + Version

### 5.1 Update AGENTS.md
### 5.2 Update README.md (plugin) -- add Finance section, update counts
### 5.3 Update README.md (root) -- update domain list, table, counts
### 5.4 Update plugin.json -- description, version
### 5.5 Update CHANGELOG.md
### 5.6 Update index.njk -- stats "7 Departments", inline text
### 5.7 Update bug_report.yml -- version placeholder
