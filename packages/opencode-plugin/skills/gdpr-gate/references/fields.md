<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# PII Field Patterns

Scan all field names, types, and surrounding context against these.
Flag on exact match OR semantic approximation.

---

## Critical Sensitivity — Always Flag, Always Fix

```
# Auth / Secrets
password, passwd, pwd, pass, passphrase
password_hash, hashed_password, encrypted_password
secret, client_secret, app_secret
api_key, api_secret, private_key, signing_key
token, auth_token, access_token, refresh_token, bearer_token
session_id, session_token
security_question, security_answer, hint

# Abbreviated / indirect — flag when on auth/user model
p, pw, cred, creds, credential, credentials
auth, auth_data, auth_info
key, k  (if on user/auth model)

# Payment Card — PCI-DSS
card_number, card_num, credit_card, debit_card, pan
cvv, cvv2, cvc, cvc2, card_code, security_code
account_number, routing_number, bank_account, iban, swift

# Government IDs
ssn, social_security, social_security_number
tax_id, taxpayer_id, itin, ein
passport, passport_number, passport_no
drivers_license, license_number, dl_number, dl_num
national_id, national_id_number, id_number

# Health / Medical — HIPAA
diagnosis, condition, medical_condition
medication, prescription, rx
health_record, medical_record, medical_history, ehr, phi
insurance, insurance_id, insurance_number, policy_number
icd_code, cpt_code, npi
mental_health, psychiatric, therapy_notes

# Biometric — BIPA
fingerprint, fingerprint_data, biometric
face_id, face_data, facial_recognition, face_scan
retina, retina_scan, iris, iris_scan
voice_print, voice_data, voice_recognition
dna, genetic_data
```

---

## High Sensitivity — Flag, Check Storage + Handling

```
# Identity
first_name, last_name, full_name, legal_name, maiden_name
middle_name, display_name
date_of_birth, dob, birth_date, birthdate, birthday
age (exact integer), gender, sex, race, ethnicity, nationality
photo, avatar, profile_picture, selfie

# Contact
email, email_address, email_addr
phone, phone_number, mobile, mobile_number, cell, telephone
address, street_address, street, addr
city, state, zip, zipcode, zip_code, postal_code
country, mailing_address, billing_address, shipping_address

# Financial (non-card)
salary, wage, income, compensation, pay_rate
balance, account_balance, net_worth
credit_score, fico, credit_rating
transaction_history, purchase_history, spending_data

# Location / Tracking
location, coordinates, lat, lng, latitude, longitude
gps, geo, geolocation
ip_address, ip_addr, ip, client_ip, remote_ip
```

---

## Lower Sensitivity — Flag in Context

```
# Behavioral
device_id, device_identifier, device_fingerprint
ad_id, idfa, gaid, advertising_id
browser_fingerprint, user_agent
search_history, browsing_history, click_history
session_data, activity_log

# Ambiguous — check what they actually store
notes, metadata, extra, data, info, details, misc, other
profile, profile_data, user_data, user_info, user_details
preferences, settings
```

---

## Indirect / Abbreviated Name Detection

Flag these based on context — they don't look like PII but frequently store it:

| Field | When to Flag | Risk |
|-------|-------------|------|
| `p`, `pw`, `k` | Any user/auth model | Almost always password or key |
| `creds`, `credential` | Anywhere | Auth credentials |
| `data`, `info`, `details` | User/customer models | PII blobs |
| `notes` | Patient/customer models | Unstructured PII |
| `metadata` | User models | Fingerprinting data |
| `token` | Anywhere | Raw auth tokens |
| `secret` | Anywhere | Should never be in DB |
| `code` | Auth/payment models | OTP, CVV, verification codes |
| `number` | User/payment models | Card, SSN, or phone |
| `value` | Sensitive models | Generic PII container |
| `raw`, `original` | Next to hashed fields | Plaintext alongside hash |

Rule: Ambiguous field name + user-facing/financial/health model = flag it.

---

## GDPR Article 9 — Special Categories of Personal Data

EU extension (not in upstream Sprinto). Article 9 prohibits processing of special-category data **without explicit consent or another lawful basis under Art. 9(2)**. Detection on column NAME alone is sufficient grounds for a `Critical` finding — the gate cannot verify whether Art. 9(2) basis is recorded, only that the column exists.

```
# Health data — Art. 9(1)
medical_history, medical_record, medical_condition, ehr, phi
diagnosis, condition, prescription, medication
mental_health, psychiatric, therapy_notes, therapy_session

# Genetic / biometric — Art. 9(1)
genetic_data, dna, genome, genetic_marker
biometric_id, fingerprint_data, retina_scan, iris_scan, face_data, voice_print

# Sex life / sexual orientation — Art. 9(1)
sexual_orientation, sex_life

# Trade-union — Art. 9(1)
union_member, union_membership, trade_union

# Religious / philosophical beliefs — Art. 9(1)
religion, religious_belief, religious_affiliation
philosophical_belief

# Political opinions — Art. 9(1)
political_opinion, political_affiliation, political_party

# Race / ethnic origin — Art. 9(1)
race, ethnic_origin, ethnicity, racial_data
```

**Rule:** Any column matching the above patterns triggers a `Critical` finding with `check_id: GDPR-Art-9`. The finding routes to the operator-acknowledgment flow (see SKILL.md "Critical-finding escalation"); it never auto-writes to `compliance-posture.md`.

**Why Art. 9 is the only `Critical` class:** Per the Kieran-review HIGH applied during plan review, lawful-basis / retention / DSAR / cross-border findings are demoted to `Important` — without that demotion, first-run noise on existing schemas would train operators to dismiss Critical, defeating the brand-survival rationale. Art. 9 column-name matches are the load-bearing Critical signal.
