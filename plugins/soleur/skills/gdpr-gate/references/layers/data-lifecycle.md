<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# Layer: Data Lifecycle

## When This Layer Loads

Auto-trigger inline when Claude is about to generate:
- Any delete, destroy, or remove function on user/customer records
- Any anonymization or scrubbing function
- Any data export or portability endpoint
- Any cron job, scheduled task, or background worker
- Any backup script or database dump
- Any retention policy or cleanup job
- Any cascade delete or foreign key relationship setup

Also loads during full repo scan.

---

## DL-01: No Hard-Delete Path (Soft-Delete Only)

What to grep:
```
deleted_at
paranoid:        (Sequelize paranoid, Rails acts_as_paranoid)
acts_as_paranoid
SoftDelete
is_deleted
is_active: false (as substitute for deletion)
```

Flag when:
- Model has `deleted_at` but no corresponding hard-delete function
- ORM paranoid/soft-delete mode with no escape hatch
- `is_deleted` flag set but record stays in DB indefinitely
- No documented path to permanently purge a user's data

Why it matters: CCPA right to erasure requires actual deletion, not just hiding
records. Soft-delete alone is not sufficient — data is still in the database,
still in backups, and still exposed in a breach.

Fix pattern:
```javascript
// Wrong — soft delete only, no hard delete
async function deleteUser(userId) {
  await User.update({ deleted_at: new Date() }, { where: { id: userId } })
  // Record still in DB, still in backups, never truly gone
}

// Right — soft delete for grace period, then hard delete
async function deleteUser(userId) {
  // Mark for deletion with timestamp
  await User.update({
    deleted_at: new Date(),
    deletion_scheduled_at: new Date(Date.now() + 30 * 24 * 3600000) // 30 day grace
  }, { where: { id: userId } })
}

// Scheduled job — runs nightly
async function purgeDeletedUsers() {
  const users = await User.findAll({
    where: {
      deletion_scheduled_at: { [Op.lt]: new Date() }
    }
  })
  for (const user of users) {
    await cascadeDeleteUserData(user.id)  // see DL-02
    await user.destroy({ force: true })   // hard delete
  }
}
```

Regulation: CCPA (right to erasure), HIPAA

---

## DL-02: Deletion Doesn't Cascade to Related Tables

What to grep:
```
User.destroy(
User.delete(
user.delete()
DELETE FROM users
await user.remove()
```

Flag when:
- User deleted from `users` table but related records remain
- No cascade delete on foreign keys
- PII orphaned in: `orders`, `addresses`, `payment_methods`, `audit_logs`,
  `sessions`, `notifications`, `support_tickets`, `analytics_events`
- Related tables not listed in deletion function

Why it matters: Deleting the user row leaves PII scattered across the database.
A CCPA deletion request must remove data from ALL tables, not just `users`.

Fix pattern:
```javascript
// Wrong
async function deleteUser(userId) {
  await User.destroy({ where: { id: userId } })
  // Orders, addresses, payment methods, sessions still in DB
}

// Right — explicit cascade
async function cascadeDeleteUserData(userId) {
  await db.transaction(async (t) => {
    // Anonymize audit logs (keep for legal compliance, remove PII)
    await AuditLog.update(
      { user_id: null, ip_address: null, user_agent: null },
      { where: { user_id: userId }, transaction: t }
    )
    // Hard delete everything else
    await Session.destroy({ where: { user_id: userId }, transaction: t })
    await Address.destroy({ where: { user_id: userId }, transaction: t })
    await PaymentMethod.destroy({ where: { user_id: userId }, transaction: t })
    await Notification.destroy({ where: { user_id: userId }, transaction: t })
    await Order.update(  // anonymize orders (keep for accounting)
      { user_id: null, shipping_address: '[deleted]', billing_name: '[deleted]' },
      { where: { user_id: userId }, transaction: t }
    )
    await User.destroy({ where: { id: userId }, force: true, transaction: t })
  })
  // Also: trigger deletion from downstream vendors (email tool, CRM, analytics)
}
```

Regulation: CCPA, HIPAA

---

## DL-03: Anonymization That Doesn't Actually Anonymize

What to grep:
```
anonymize(
anonymise(
scrub_user(
redact(
null             (setting fields to null as "anonymization")
'[deleted]'      (replacing with literal string)
```

Flag when:
- "Anonymization" only nulls out name/email but keeps DOB + zip + gender (re-identifiable combo)
- Email replaced with `[deleted]` but user_id kept linked to other tables
- IP addresses kept after "anonymization"
- Unique identifiers (phone, SSN) replaced with placeholder that's still unique

Why it matters: A user with DOB + zip code + gender is re-identifiable in 87%
of cases (Latanya Sweeney). Nulling name and email while keeping these fields
is not anonymization — it's pseudonymization at best.

Fix pattern:
```javascript
// Wrong — leaves re-identifiable combination
async function anonymizeUser(userId) {
  await User.update({
    email: null,        // removed
    name: null,         // removed
    // dob, zip, gender, ip_address still present — re-identifiable
  }, { where: { id: userId } })
}

// Right — remove or generalize all quasi-identifiers
async function anonymizeUser(userId) {
  await User.update({
    email: `anon_${crypto.randomUUID()}@deleted.invalid`,  // unique but not real
    name: null,
    phone: null,
    ip_address: null,
    date_of_birth: null,          // or replace with birth_year only
    zip_code: zip.slice(0, 3) + '00',  // generalize to 3-digit prefix
    // Keep: aggregated/non-identifying analytics only
  }, { where: { id: userId } })
}
```

Regulation: CCPA, HIPAA, FTC Act

---

## DL-04: No Data Export / Portability Function (GDPR Art. 20 + CCPA)

EU rewrite (upstream framed CCPA-only). GDPR Art. 20 grants the data subject the right to receive personal data in a "structured, commonly used and machine-readable format" and to transmit it to another controller. CCPA grants a parallel right under §1798.110/.130. Both apply.

What to grep:
```
export_user_data
download_my_data
data_export
portability
/api/users/export
/account/download
```

Flag when:
- No data export endpoint or function exists in the codebase
- Export function exists but omits tables (check it covers all PII tables — see DL-02 cascade audit)
- Export format is not machine-readable (Art. 20 + CCPA both require structured format)
- Export omits data subject fields obtainable under Art. 15 right of access (which is broader than Art. 20 portability)

Why it matters: GDPR Art. 20 is enforceable independently of Art. 15 access requests. CCPA aligns. Without an automatable export endpoint, every DSAR becomes a manual SQL job — and the gate at FR4.3 (`GDPR-Art-17`) cannot verify deletability without evidence of complete enumeration first.

Fix pattern:
```javascript
// Minimum viable GDPR Art. 20 + CCPA data export
app.get('/api/account/export', auth, async (req, res) => {
  const userId = req.user.id

  const [user, orders, addresses, activityLog] = await Promise.all([
    User.findById(userId).select('-password_hash -ssn_encrypted'),
    Order.findAll({ where: { user_id: userId } }),
    Address.findAll({ where: { user_id: userId } }),
    ActivityLog.findAll({ where: { user_id: userId } })
  ])

  const export_data = {
    exported_at: new Date().toISOString(),
    profile: user,
    orders,
    addresses,
    activity: activityLog
  }

  res.setHeader('Content-Disposition', 'attachment; filename="my-data.json"')
  res.setHeader('Content-Type', 'application/json')
  res.json(export_data)

  // Log the export request for audit trail
  await AuditLog.create({ user_id: userId, action: 'data_export_requested' })
})
```

Regulation: GDPR Art. 20 (right to data portability), GDPR Art. 15 (right of access), CCPA §1798.110/.130, CPRA

---

## DL-05: No Retention Policy Enforcement in Code

What to grep:
```
created_at         (check if old records are ever purged)
expires_at         (check if expiry is actually enforced)
purge_at
scheduled_deletion
cron               (check if cleanup jobs exist)
sidekiq            (check for cleanup workers)
celery             (check for cleanup tasks)
```

Flag when:
- PII tables have no cleanup job or scheduled purge
- `expires_at` field exists but no code actually checks or enforces it
- Session table grows unboundedly (no cleanup of expired sessions)
- Audit logs accumulate forever with no retention limit

Fix pattern:
```javascript
// Retention enforcement job (run nightly via cron/Sidekiq/Celery)
async function enforceRetentionPolicies() {
  const now = new Date()

  // Expired sessions
  await Session.destroy({
    where: { expires_at: { [Op.lt]: now } }
  })

  // Audit logs older than 2 years
  const twoYearsAgo = new Date(now - 2 * 365 * 24 * 3600000)
  await AuditLog.destroy({
    where: { created_at: { [Op.lt]: twoYearsAgo } }
  })

  // Soft-deleted users past grace period
  await purgeDeletedUsers()

  // Unverified accounts older than 30 days (never activated)
  const thirtyDaysAgo = new Date(now - 30 * 24 * 3600000)
  await User.destroy({
    where: {
      email_verified_at: null,
      created_at: { [Op.lt]: thirtyDaysAgo }
    },
    force: true
  })
}
```

Regulation: CCPA, HIPAA, GLBA

---

## DL-06: PII in Database Backups Without Encryption

What to grep:
```
pg_dump
mysqldump
mongodump
backup
db:backup
rake db:dump
s3.upload          (near backup-related code)
```

Flag when:
- Backup scripts run without encryption flag
- Backup files uploaded to S3 without server-side encryption
- Backup destination is publicly accessible bucket
- No TTL/lifecycle policy on backup files (kept indefinitely)

Fix pattern:
```bash
# Wrong
pg_dump mydb > backup.sql
aws s3 cp backup.sql s3://my-backups/

# Right
pg_dump mydb | gzip | \
  openssl enc -aes-256-cbc -pass env:BACKUP_ENCRYPTION_KEY | \
  aws s3 cp - s3://my-backups/backup-$(date +%Y%m%d).sql.gz.enc \
  --sse AES256 \
  --storage-class STANDARD_IA

# S3 bucket policy: block public access
# S3 lifecycle rule: delete backups older than 90 days
```

```javascript
// In application backup code
await s3.putObject({
  Bucket: 'my-backups',
  Key: `backup-${Date.now()}.sql.gz`,
  Body: encryptedBackupStream,
  ServerSideEncryption: 'AES256',
  ACL: 'private',                    // never public
})
```

Regulation: HIPAA, PCI-DSS, CCPA, GLBA