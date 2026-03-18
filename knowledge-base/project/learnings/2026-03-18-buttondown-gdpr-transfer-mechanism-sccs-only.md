# Learning: Buttondown uses SCCs only (not DPF) for international transfers

## Problem
When adding Buttondown to GDPR Policy Section 6 (International Data Transfers), we needed to determine the correct transfer mechanism. GitHub uses EU-US Data Privacy Framework (DPF) as the primary mechanism with SCCs as supplementary. The question was whether Buttondown also uses DPF.

## Solution
Buttondown is NOT certified under the EU-US Data Privacy Framework. It relies solely on Standard Contractual Clauses (SCCs), Module 2 (Controller to Processor), per EU Implementing Decision (EU) 2021/914. This was verified via Buttondown's DPA at `https://buttondown.com/legal/data-processing-agreement`.

Key details:
- SCCs Module 2 with Option 2 for sub-processor authorization
- All 12 Buttondown subprocessors are US-based (AWS, Heroku, Mailgun, Postmark, Stripe, etc.)
- DPA also includes UK Addendum and Swiss FADP modifications (not needed for Soleur's EU-focused policy)
- DPA includes standard Article 28(3)(g) deletion/return clause upon termination

## Key Insight
Not all US-based SaaS processors use the same transfer mechanism. Always verify DPF certification status before assuming — GitHub (Microsoft) is DPF-certified, but smaller services like Buttondown rely solely on SCCs. Referencing DPF for a non-certified processor would be legally incorrect.

## Tags
category: legal
module: gdpr-policy
