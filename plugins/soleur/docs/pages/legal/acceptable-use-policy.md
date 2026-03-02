---
title: "Acceptable Use Policy"
description: "Permitted and prohibited uses of the Soleur platform."
layout: base.njk
permalink: pages/legal/acceptable-use-policy.html
---

<section class="page-hero">
  <div class="container">
    <h1>Acceptable Use Policy</h1>
    <p>Effective February 20, 2026</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Soleur -- Company-as-a-Service Platform**

**Effective Date:** February 20, 2026

**Last Updated:** February 20, 2026

---

## 1. Introduction

This Acceptable Use Policy ("AUP" or "Policy") governs your use of the Soleur platform ("Soleur," "the Platform," "the Plugin"), a Claude Code plugin providing agents for software development workflows, including code generation, review, planning, deployment, and browser automation. Soleur is developed and maintained by Jikigai ("we," "us," "our") and is available at [soleur.ai](https://soleur.ai) and through the GitHub repository [jikig-ai/soleur](https://github.com/jikig-ai/soleur).

By installing, configuring, or using Soleur, you ("User," "you," "your") agree to comply with this Policy. If you do not agree, you must discontinue use of the Platform immediately.

This Policy applies to all users globally, with specific provisions addressing compliance with the laws of the European Union (including the General Data Protection Regulation) and the United States.

---

## 2. Scope

This Policy applies to all use of the Soleur platform, including but not limited to:

- Interaction with Soleur's {{ stats.agents }} AI agents and {{ stats.skills }} skills;
- Execution of shell commands, code generation, and file manipulation through agents;
- Browser automation via the agent-browser subsystem;
- API interactions initiated by or through Soleur agents;
- Use of the compounding knowledge base; and
- Any output, artifact, or action produced by or through the Platform.

Soleur operates locally on your machine. You retain full control over agent actions and bear responsibility for all activities performed through the Platform under your account or on your systems.

---

## 3. Permitted Use

You may use Soleur for lawful purposes consistent with its intended function as a software development productivity tool. Permitted uses include, but are not limited to:

- Generating, reviewing, and refactoring source code;
- Automating software development workflows (build, test, deploy);
- Planning and managing software projects;
- Generating documentation and technical specifications;
- Conducting code review and security analysis;
- Automating repetitive development tasks; and
- Researching and prototyping software solutions.

---

## 4. Prohibited Conduct

You must not use Soleur, directly or indirectly, to engage in any of the following activities. This list is illustrative, not exhaustive.

### 4.1 Malicious Automation

You must not use Soleur's agents, skills, or browser automation capabilities to:

- (a) Generate, distribute, or facilitate spam, unsolicited bulk messages, or automated mass outreach;
- (b) Conduct phishing attacks, social engineering, or credential harvesting;
- (c) Develop, test, or deploy malware, ransomware, viruses, trojans, worms, or other malicious software;
- (d) Perform or facilitate denial-of-service (DoS/DDoS) attacks;
- (e) Conduct unauthorized port scanning, vulnerability scanning, or network reconnaissance against systems you do not own or have explicit authorization to test;
- (f) Exploit, probe, or attempt to compromise the security of any system, network, or service;
- (g) Automate actions that violate rate limits, access controls, or terms of service of any third-party platform; or
- (h) Create botnets, automated sock-puppet accounts, or deceptive automated personas.

### 4.2 Harmful or Illegal Content

You must not use Soleur to generate, process, store, or distribute:

- (a) Content that is unlawful under applicable law in any relevant jurisdiction;
- (b) Content that promotes, incites, or facilitates violence, terrorism, or extremism;
- (c) Child sexual abuse material (CSAM) or any content that sexualizes minors;
- (d) Content that constitutes or facilitates harassment, stalking, doxxing, or intimidation;
- (e) Content that infringes upon the intellectual property rights of others, including unauthorized reproduction of copyrighted works;
- (f) Defamatory, fraudulent, or deliberately misleading content intended to deceive; or
- (g) Content that violates export control laws, sanctions regulations, or trade restrictions.

### 4.3 Circumvention of Security Controls

You must not:

- (a) Attempt to bypass, disable, or circumvent any security mechanism, access control, or usage limitation of the Soleur platform;
- (b) Reverse-engineer Soleur for the purpose of developing competing products or extracting proprietary logic (subject to applicable license terms);
- (c) Modify Soleur in a manner designed to remove safety guardrails, audit logging, or confirmation prompts that protect against destructive operations;
- (d) Use Soleur to circumvent security controls, authentication mechanisms, or access restrictions on third-party systems; or
- (e) Attempt to manipulate or override the agent instruction framework to cause agents to perform actions outside their defined scope or safety boundaries.

### 4.4 Violation of Third-Party Terms

You must comply with the terms of service, acceptable use policies, and usage guidelines of all third-party services accessed through or in conjunction with Soleur, including but not limited to:

- **Anthropic / Claude:** You must comply with [Anthropic's Acceptable Use Policy](https://www.anthropic.com/policies/aup) and Usage Policy when using Soleur, which operates as a Claude Code plugin and relies on Anthropic's API;
- **GitHub:** You must comply with [GitHub's Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) and Acceptable Use Policies when Soleur interacts with GitHub repositories, issues, pull requests, or APIs;
- **Other APIs and Services:** You must ensure that any API keys, tokens, or credentials used by Soleur agents are obtained and used in compliance with the applicable service provider's terms; and
- **Rate Limits and Quotas:** You must not configure or direct Soleur agents to exceed the rate limits, quotas, or fair-use thresholds of any third-party service.

### 4.5 Misrepresentation

You must not:

- (a) Represent output generated by Soleur's AI agents as being produced by a human when disclosure of AI involvement is required by law, regulation, or applicable professional standards;
- (b) Use Soleur-generated content to impersonate individuals, organizations, or government entities; or
- (c) Misrepresent the capabilities, limitations, or origin of Soleur or its outputs.

---

## 5. User Responsibilities

### 5.1 Local Execution Model

Soleur operates locally on your machine. You are solely responsible for:

- Reviewing and approving agent actions before execution, particularly destructive operations (file deletion, force-push, deployment);
- Securing API keys, credentials, and secrets used by or accessible to Soleur agents;
- Ensuring that generated code, configurations, and artifacts are reviewed before deployment to production systems;
- Maintaining appropriate backups of your data and code; and
- Configuring appropriate access controls on your local environment.

### 5.2 Output Review

AI-generated outputs, including code, documentation, and automated actions, may contain errors, vulnerabilities, or unintended consequences. You must:

- Review all generated code for security vulnerabilities before use;
- Validate generated configurations and deployment scripts before execution;
- Not rely on Soleur-generated legal, medical, financial, or other professional content without independent professional review; and
- Accept that Soleur's outputs are assistive, not authoritative.

### 5.3 Data Protection

When using Soleur in a manner that involves personal data:

- You must comply with all applicable data protection laws, including the EU General Data Protection Regulation (GDPR) and applicable US state privacy laws;
- You must have a lawful basis for processing any personal data that Soleur agents may access or generate;
- You must not direct Soleur agents to collect, scrape, or process personal data in violation of applicable law; and
- You are the data controller for any personal data processed through your use of the Platform.

---

## 6. Enforcement

### 6.1 Monitoring

While Soleur operates locally and we do not monitor your usage in real time, we reserve the right to investigate reported violations of this Policy.

### 6.2 Consequences of Violation

Violation of this Policy may result in:

- Warnings or requests to cease the violating activity;
- Temporary or permanent suspension of access to Soleur updates, support, or community resources;
- Removal from community channels (GitHub Discussions, issue trackers); and
- Referral to law enforcement authorities where we believe a violation involves criminal conduct.

### 6.3 Reporting Violations

If you become aware of any use of Soleur that violates this Policy, please report it through:

- **GitHub:** Open an issue or security advisory at [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [soleur.ai](https://soleur.ai)

---

## 7. Jurisdiction-Specific Provisions

### 7.1 European Union / European Economic Area

For users subject to EU/EEA law:

- This Policy is intended to be consistent with the GDPR, the EU AI Act, and other applicable Union and Member State law;
- Nothing in this Policy limits your rights under the GDPR, including your rights of access, rectification, erasure, and data portability;
- Where Soleur generates output that constitutes a decision with legal or similarly significant effects on individuals, you must ensure human oversight as required by applicable law; and
- The provisions of this Policy shall be interpreted in conformity with applicable EU law, and any provision found to be inconsistent shall be modified to the minimum extent necessary to achieve compliance.

### 7.2 United States

For users subject to US law:

- This Policy is intended to be consistent with applicable federal and state law, including the Computer Fraud and Abuse Act (CFAA), CAN-SPAM Act, and applicable state privacy laws (e.g., CCPA/CPRA);
- You must not use Soleur in any manner that would constitute a violation of the CFAA, including unauthorized access to computer systems; and
- You are responsible for compliance with any industry-specific regulations applicable to your use (e.g., HIPAA, FERPA, GLBA) if you direct Soleur agents to interact with regulated data.

---

## 8. Modifications

We reserve the right to modify this Policy at any time. Material changes will be communicated through the GitHub repository (release notes, changelog, or repository notification). Your continued use of Soleur after such changes constitutes acceptance of the modified Policy.

---

## 9. Severability

If any provision of this Policy is found to be unenforceable or invalid under applicable law, that provision shall be limited or eliminated to the minimum extent necessary, and the remaining provisions shall remain in full force and effect.

---

## 10. Governing Law and Dispute Resolution

### 10.1 Governing Law

This Policy shall be governed by and construed in accordance with the laws of France, without regard to its conflict of laws provisions.

### 10.2 Jurisdiction

Any disputes arising under or in connection with this Policy shall be subject to the exclusive jurisdiction of the courts of Paris, France.

### 10.3 EU/EEA Consumers

If you are a consumer in the EU/EEA, nothing in this Policy affects your rights under mandatory EU or member state consumer protection laws, including your right to bring proceedings in the courts of your country of habitual residence.

---

## 11. Legal Entity and Contact

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

For questions about this Policy, please contact us through:

- **Email:** legal@jikigai.com
- **GitHub:** [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [soleur.ai](https://soleur.ai)

---

> **Related documents:** This Acceptable Use Policy references data protection practices and obligations. Consider generating companion **Privacy Policy**, **GDPR Policy**, and **Terms and Conditions** documents to ensure consistency. If Soleur processes personal data on behalf of users in a controller-processor relationship, a **Data Processing Agreement** may also be appropriate.

---

    </div>
  </div>
</section>
