<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# PII Leakage Vectors

Loaded during repo scan only. These are the places PII most commonly
leaks in production — outside of models and schemas.

---

## V-01: Logging (Highest Frequency)

What to grep:
```
console.log(       console.error(     console.info(
logger.info(       logger.debug(      logger.warn(      logger.error(

# JavaScript / Node
winston.           bunyan.            Timber.log(

# Python
print(             logging.info(      logging.debug(     logging.warning(
logger.info(       logger.debug(      log.info(

# Ruby / Rails
Rails.logger.      logger.info        logger.debug       puts

# Go
log.Printf(        log.Println(       fmt.Println(       fmt.Printf(
zap.               logrus.

# Java / Kotlin
System.out.print(  log.info(          logger.info(       Logger.getLogger(
Timber.log(
```

Flag when:
- Full objects logged: `console.log(user)`, `logger.info(req.body)`
- PII field names near log call: `logger.debug("email:", user.email)`
- Request/response bodies logged in middleware

Fix pattern:
```javascript
// Wrong
console.log('User updated:', user)
logger.info(req.body)

// Right
console.log('User updated:', user.id)          // log ID only
logger.info({ action: 'user_updated', userId: user.id })
```

---

## V-02: Error Handling (Second Most Common)

What to grep:
```
catch (          except:          rescue
.catch(          on_error         rescue =>
error.message    err.toString()   JSON.stringify(error)
res.status(500).json(    render json: e    raise
```

Flag when:
- Raw error objects returned to client: `res.json({ error: err })`
- Stack traces exposed: `res.send(err.stack)`
- Request body in error response: `res.json({ error: e, input: req.body })`

Fix pattern:
```javascript
// Wrong
app.use((err, req, res, next) => {
  res.status(500).json({ error: err.message, stack: err.stack })
})

// Right
app.use((err, req, res, next) => {
  logger.error({ errorId: uuid(), message: err.message }) // log server-side only
  res.status(500).json({ error: 'Something went wrong', errorId })
})
```

---

## V-03: Analytics / Tracking

What to grep:
```
mixpanel.track(    amplitude.track(    analytics.track(
segment.identify(  heap.identify(      posthog.capture(
gtag(              fbq(                _hsq.push(
rudderstack.       braze.              klaviyo.
```

Flag when:
- PII passed as event properties: `track('Signup', { email, phone })`
- Full user object in identify: `identify(userId, { ...user })`
- Health or financial data in any analytics call

Fix pattern:
```javascript
// Wrong
mixpanel.track('Purchase', { email: user.email, card_last4, amount })

// Right
mixpanel.track('Purchase', { userId: user.id, amount })  // no PII in events
```

---

## V-04: Caching

What to grep:
```
redis.set(         redis.setex(       cache.set(
Rails.cache.write( memcache.set(      client.set(
Cache.put(         CacheManager.
```

Flag when:
- PII cached without TTL: `redis.set('user:123', JSON.stringify(user))`
- Full user object cached: includes email, phone, sensitive fields
- No encryption on cached PII

Fix pattern:
```javascript
// Wrong
redis.set(`user:${id}`, JSON.stringify(user))

// Right
redis.setex(`user:${id}`, 3600, JSON.stringify({
  id: user.id,
  name: user.name   // only cache what's needed, set TTL
}))
```

---

## V-05: External API Calls

What to grep:
```
fetch(             axios.post(        axios.get(
requests.post(     http.Post(         HTTParty.post(
RestClient.post(   urllib.request(    curl
```

Flag when:
- PII fields in request body to third-party URLs
- Full user object forwarded to external service
- Sensitive data in query parameters (visible in logs)

Fix pattern:
```javascript
// Wrong
await axios.post('https://api.vendor.com/users', {
  email: user.email, ssn: user.ssn, dob: user.dob
})

// Right — send only what vendor actually needs
await axios.post('https://api.vendor.com/users', {
  externalId: user.id,
  verified: true
})
```

---

## V-06: API Responses / Serializers

What to grep:
```
res.json(user      render json: @user    jsonify(user)
to_json            as_json               serialize
JSON.stringify(user  toJSON(            transform(user
```

Flag when:
- Full model returned: `res.json(user)` — includes all fields
- `password_hash` included in response
- SSN, health fields, or financial data in response body
- `SELECT *` used in query feeding into response

Fix pattern:
```javascript
// Wrong
res.json(user)

// Right
res.json({
  id: user.id,
  name: user.name,
  email: user.email
  // password_hash, ssn, dob excluded explicitly
})
```

---

## V-07: File / Object Storage

What to grep:
```
s3.upload(         s3.putObject(      bucket.file(
fs.writeFile(      fs.appendFile(     open(filename, 'w')
Storage.upload(    blob.upload(       writeStream(
```

Flag when:
- PII written to unencrypted local files
- S3 bucket ACL not set to private
- No server-side encryption on S3 uploads
- Export files (CSV, JSON) containing PII stored without encryption

Fix pattern:
```javascript
// Wrong
s3.putObject({ Bucket: 'exports', Key: 'users.csv', Body: csvData })

// Right
s3.putObject({
  Bucket: 'exports',
  Key: 'users.csv',
  Body: csvData,
  ServerSideEncryption: 'AES256',
  ACL: 'private'
})
```

---

## V-08: Config / Environment Files

What to grep:
```
.env               .env.example       config/database.yml
seed.rb            seeds.js           fixtures/
hardcoded @        hardcoded phone    hardcoded SSN
```

Flag when:
- Real email addresses, phone numbers, SSNs in seed/fixture files
- PII in `.env.example` (often committed to git)
- Real credentials or PII in any committed config file

Fix:
- Replace with obviously fake data: `user@example.com`, `555-0100`, `000-00-0000`
- Add `.env` to `.gitignore` if not already present
- Audit git history for accidentally committed PII (use `git-secrets` or `truffleHog`)