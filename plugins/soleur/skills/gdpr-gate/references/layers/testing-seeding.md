<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# Layer: Testing & Seeding

## When This Layer Loads

Auto-trigger inline when Claude is about to generate:
- A seed file or database seeder
- A test factory or fixture file
- A test helper that creates user records
- Any test that instantiates a user, customer, or patient object
- Example or sample data in documentation or README

Also loads during full repo scan.

---

## TS-01: Real PII in Seed Files

What to grep:
```
seeds/
db/seeds/
seed.js, seed.ts, seed.rb, seed.py, seeds.sql
seeders/
prisma/seed.ts
faker          (check if it's actually used — or real data hardcoded)
```

Flag when:
- Real email addresses: anything that isn't `@example.com` or `@test.com`
- Real phone numbers: anything matching `\d{3}[-.\s]\d{3}[-.\s]\d{4}` that isn't `555-0100`–`555-0199`
- Real SSNs: anything matching `\d{3}-\d{2}-\d{4}` that isn't `000-00-0000`
- Real names that appear to be actual people (not clearly fake)
- Real addresses (not "123 Main St, Anytown")
- Real credit card numbers

Why it matters: Seed files are committed to git. Real PII in seeds means
real user data in your repo history — accessible to every developer,
contractor, and anyone who clones the repo.

Fix pattern:
```javascript
// Wrong
await User.create({
  email: 'john.smith@gmail.com',    // real email
  phone: '415-555-8923',            // real-looking phone
  ssn: '123-45-6789'               // real-format SSN
})

// Right — use faker or obviously fake data
import { faker } from '@faker-js/faker'

await User.create({
  email: faker.internet.email(),           // fake@example.com
  phone: faker.phone.number('555-01##'),   // 555-01xx range = fake
  ssn: '000-00-0000'                       // invalid SSN format = safe
})

// Or hardcode clearly fake data
await User.create({
  email: 'test.user@example.com',
  phone: '555-0100',
  ssn: '000-00-0000'
})
```

Regulation: CCPA (any real user data), HIPAA (health seed data)

---

## TS-02: Real PII in Test Fixtures / Factories

What to grep:
```
fixtures/
spec/fixtures/
test/fixtures/
factories/
spec/factories/
FactoryBot.define
factory(
Factory.create(
create(:user,
```

Flag when:
- Factory default values use real-format PII (real-looking SSNs, emails, phones)
- Fixture YAML files contain real email addresses
- `create(:user, email: 'real@gmail.com')` in test files

Fix pattern:
```ruby
# Wrong (FactoryBot)
FactoryBot.define do
  factory :user do
    email { 'john.smith@gmail.com' }
    phone { '415-555-8923' }
    ssn   { '123-45-6789' }
  end
end

# Right
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    phone { '555-0100' }
    ssn   { '000-00-0000' }
    name  { Faker::Name.name }
  end
end
```

```javascript
// Wrong (Jest + factory)
const userFactory = {
  email: 'john@gmail.com',
  ssn: '123-45-6789'
}

// Right
import { faker } from '@faker-js/faker'
const userFactory = () => ({
  email: faker.internet.email({ provider: 'example.com' }),
  ssn: '000-00-0000'
})
```

Regulation: CCPA, HIPAA

---

## TS-03: PII in Test Output / Snapshot Files

What to grep:
```
__snapshots__/
*.snap
.snap files
test/cassettes/    (VCR cassettes)
spec/cassettes/
fixtures/vcr/
```

Flag when:
- Snapshot files contain email, phone, name, SSN, or health data
- VCR/cassette recordings contain real API responses with PII
- Test output logs contain PII from real or realistic test data

Why it matters: Snapshot files are committed to git and updated automatically.
If tests run against realistic data, PII ends up in `.snap` files silently.

Fix pattern:
```javascript
// In snapshot — flag if you see:
// "email": "john@gmail.com"  ← real-looking email in snapshot

// Fix: ensure test data uses example.com domains
// Use serializers to mask PII in snapshots
expect(response.body).toMatchSnapshot({
  email: expect.stringMatching(/@example\.com$/),  // only match pattern
  id: expect.any(String)
})

// For VCR cassettes — scrub before committing
// Use cassette filtering to replace real values:
VCR.configure do |c|
  c.filter_sensitive_data('<EMAIL>') { real_user.email }
  c.filter_sensitive_data('<PHONE>') { real_user.phone }
end
```

Regulation: CCPA, HIPAA

---

## TS-04: Tests Running Against Production Data

What to grep:
```
DATABASE_URL=postgres://prod
process.env.DATABASE_URL    (check what it points to in test env)
RAILS_ENV=production        (in test files)
NODE_ENV=production         (in test config)
```

Flag when:
- Test configuration points to production database URL
- No separate test database configured
- Environment variable fallback could resolve to production in CI

Fix pattern:
```javascript
// Wrong — in test config or .env.test
DATABASE_URL=postgres://user:pass@prod-db.company.com/mydb

// Right
DATABASE_URL=postgres://localhost:5432/myapp_test
// Or in CI:
DATABASE_URL=postgres://postgres:postgres@localhost:5432/test_db

// Add guard in code:
if (process.env.DATABASE_URL?.includes('prod') && process.env.NODE_ENV === 'test') {
  throw new Error('Tests must not run against production database')
}
```

Regulation: CCPA, HIPAA (PHI exposure to dev/test environments)

---

## TS-05: PII Logged During Test Runs

What to grep:
```
console.log(         (in test files themselves)
puts                 (in Ruby test files)
print(               (in Python test files)
logger.             (if test env logging is verbose)
```

Flag when:
- Test files log user objects, API responses, or PII field values
- Test helpers print sensitive data for debugging
- CI log output captures PII (check if logs are stored/accessible)

Fix pattern:
```javascript
// Wrong
it('creates a user', async () => {
  const user = await User.create({ email: 'test@example.com', ssn: '000-00-0000' })
  console.log('Created user:', user)  // logs all fields including sensitive ones
})

// Right
it('creates a user', async () => {
  const user = await User.create({ email: 'test@example.com', ssn: '000-00-0000' })
  // No logging in tests — assertions are enough
  expect(user.id).toBeDefined()
  expect(user.email).toBe('test@example.com')
})
```

Regulation: CCPA, HIPAA

---

## EU extension — Art. 32 pseudonymization in non-prod

TS-01..TS-05 are Soleur-extended under GDPR Art. 32(1)(a) ("pseudonymisation
and encryption of personal data"). Test seeds, dev fixtures, and CI snapshots
are non-prod environments but they still process personal data the moment a
real-shape email, name, or identifier lands in `__synthesized__/`,
`__goldens__/`, or `test/fixtures/`. Pseudonymization is not optional in non-
prod — it is the Art. 32 floor for every environment that touches user-shape
data. Findings on this layer cross-reference TS-01 (the canonical
synthesized-data contract) and AGENTS.md `cq-test-fixtures-synthesized-only`.
