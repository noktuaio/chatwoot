# Email Campaign — ONDA 2 Build Manifest (AUTHORITATIVE)

> Fork Chatwoot v4.14.1 EE (Hub2you / Autonomia) at
> `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`. Rails 7.1 + Vue 3.
> Single source of truth for parallel impl agents. All paths ABSOLUTE-relative to the
> repo root above. **Build ONLY Onda 2** (recipient import + campaign engine + send/schedule
> + compose/list FE). Do NOT build Onda 3 (tracking pixel / click rewrite / SNS event
> webhook / RD report page in CRM) nor Onda 4 (public unsubscribe endpoint /
> auto-suppression-on-bounce / per-tenant guardrail monitor / caps).
>
> Scope source: `docs/email_campaign_v1_prd.md` §9 (Onda 2) + task brief.
> Build **ON TOP OF** the shipped Onda 1 (`docs/email_campaign_onda1_manifest.md`):
> `EmailSenderIdentity`, the gem-free `EmailCampaigns::Ses::{Client,Sender,IdentityProvisioner,
> ConfigurationSetEnsurer}`, `EmailCampaigns::Config`, policy `EmailSenderIdentityPolicy`,
> the `email_campaigns` route namespace, the FE `emailSenderIdentities` store/api/page, and the
> `CAMPAIGN.EMAIL_SENDER` i18n block. **Do NOT modify any Onda 1 file** except the shared
> integration files explicitly listed under Package J.

---

## 0. Hard rules (apply to every package)

- **Additive + zero regression.** Do NOT touch in a breaking way: native `Campaign`,
  `Channel::Email`, `WhatsappApiCampaign*`, the **phone/Contacts path** of `campaign_imports/*`.
  New backend lives under top-level models `EmailCampaign`/`EmailCampaignRecipient`/
  `EmailSuppression` + the `EmailCampaigns::*` service/job namespace.
- **Import extension is purely additive.** `campaign_imports/HeaderMapper` and `Validator`
  gain email support gated behind an explicit **mode** flag; default mode = `phone` =
  byte-for-byte current behavior. The email recipient list is written by a NEW service
  (`EmailCampaigns::RecipientImporter`) — it **reuses** `CampaignImports::Parser` +
  `HeaderMapper` but does **NOT** go through `CampaignImports::Importer` (no Contacts created).
- **Inert unless enabled.** Every entrypoint (controller, job, cron, FE route) checks
  `EmailCampaigns::Config.enabled?` (Ruby) / `globalConfig.emailCampaignEnabled === true &&
  globalConfig.crmKanbanEnabled === true` (FE). `EmailCampaigns::Config.enabled?` already
  ANDs `Crm::Config.enabled?` with `EMAIL_CAMPAIGN_ENABLED` (Onda 1, do not change).
- **Send only via Onda 1 SES layer.** `EmailCampaigns::Ses::Sender#deliver` (needs a VERIFIED
  `EmailSenderIdentity`). NO new gem, NO Dockerfile change, NO `aws-sdk-ses`/`sesv2`.
  A campaign may send only if `sender_identity.usable?` (i.e. `verified?`).
- **SES SANDBOX.** Engine must work in sandbox (sends only to verified addresses, 200/day).
  Do NOT assume production access. Throttle to SES MaxSendRate.
- **Compliance now:** every send sets a `List-Unsubscribe` + `List-Unsubscribe-Post` header
  (RFC 8058) pointing at a PLACEHOLDER unsubscribe URL carrying a per-recipient token; the
  real endpoint is Onda 4. Check `EmailSuppression` at send time → skip suppressed.
- **Ruby:** RuboCop, ≤150 cols, compact `module/class`. `ruby -c` every `.rb` touched.
- **Vue 3 `<script setup>` + Composition API**, Tailwind `n-*` tokens ONLY (no scoped /
  custom / inline CSS), `components-next`, `i-lucide-*`, NO bare strings (i18n everywhere).
- **i18n parity:** every key added to `en/campaign.json` MUST be added to
  `pt_BR/campaign.json` with identical key tree.

### Verified environment facts (do NOT re-investigate)
- Latest migration timestamp on disk: `20260612090000_create_email_sender_identities.rb`
  (Onda 1). Onda 2 migrations start at `20260612093000` and increase. Use
  `ActiveRecord::Migration[7.1]`.
- `EmailCampaigns::Ses::Sender.new(identity).deliver(to:, subject:, html_body:, text_body: nil,
  from_email: nil, reply_to: nil)` → returns SES `MessageId` (String). Raises
  `EmailCampaigns::Ses::Error` if `!identity.usable?`. `Client#send_email` already wires
  `ConfigurationSetName` + `ReplyToAddresses`. **The Onda 1 `Client#send_email` has NO
  `headers:` param** — see §C2 for the headers gap and the exact additive edit required.
- `WhatsappApiCampaign` status pattern: `enum status` integer-backed; `refresh_counters!`
  does `recipients.group(:status).count` then `update_columns(...counts..., updated_at:)`;
  `cancel!`/`pause!`/`resume!` use `with_lock`. Scheduler picks `scheduled.where('scheduled_at
  <= ?', Time.current)` and transitions inside `with_lock`. Delivery is a chained self-
  re-enqueue (`DeliveryJob` processes one recipient then re-enqueues). **Onda 2 email
  DeliveryJob uses a simpler batch loop** (SES has its own rate limit; no per-inbox ordering).
- `EmailSenderIdentity` (Onda 1): `belongs_to :account`; `enum status {pending:0,verifying:1,
  verified:2,failed:3}`; `usable?` == `verified?`; scope `verified_identities`; columns include
  `from_email`, `reply_to_inbox_id`, `ses_configuration_set`. Account does NOT declare the
  inverse association (scope via `where(account: ...)`).
- `campaign_imports` pipeline: `CampaignImports::Parser.new(file, filename:).perform` →
  `ParsedFile` with `.format` (`'csv'`/`'xlsx'`), `.headers` (Array), `.rows` (each `.values`
  Array + `.row_number`). `HeaderMapper.new(headers).perform` → `Result(mapping:, errors:)`
  where `mapping` is `{ logical_name => column_index }`. `HeaderMapper.normalize(h)` /
  `.transliterate`. `CsvSanitizer.formula_like?(value)` flags CSV-injection.
  `CampaignImports::Config.{supported_formats,max_csv_rows,max_xlsx_rows,max_file_size_bytes}`.
- Routes: `namespace :email_campaigns` already exists in `config/routes.rb` (~line 213),
  currently holding only `resources :sender_identities`. Onda 2 ADDS sibling resources INSIDE
  that same namespace block.
- jbuilder convention: response wrapped in `json.payload do ... end`; collection via
  `json.array! @collection, partial: '<name>', as: :<name>`; partial `_<name>.json.jbuilder`.
- globalConfig flow: `dashboard_controller.rb#global_config` emits `EMAIL_CAMPAIGN_ENABLED`
  (line ~84, already present) → `globalConfig.js` maps to `emailCampaignEnabled`
  (already present). No new globalConfig flag needed for Onda 2.
- FE campaigns routes: `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js`
  — has `email_sender` child route. Onda 2 ADDS an `email_campaigns` child route after it.
- Vuex store: import list ~line 16 of `store/index.js`, modules object ~line 83;
  mutation types in `store/mutation-types.js`. `emailSenderIdentities` module already wired.
- i18n campaign file `campaign.json` (root key `CAMPAIGN`); `EMAIL_SENDER` block present.
  Onda 2 adds a SIBLING `CAMPAIGN.EMAIL_CAMPAIGN` block.
- Policy lesson (Onda 1): a top-level model gets a top-level policy named after the class
  (`EmailSenderIdentityPolicy`, NOT namespaced) — a namespaced policy breaks Pundit lookup.
  So Onda 2 policy is **`EmailCampaignPolicy`** at `app/policies/email_campaign_policy.rb`.

---

## File ownership table (DISJOINT — no file in two packages)

| Pkg | Owns (create unless noted EDIT) |
|-----|----------------------------|
| **A** models+migrations | `db/migrate/20260612093000_create_email_campaigns.rb`; `db/migrate/20260612093100_create_email_campaign_recipients.rb`; `db/migrate/20260612093200_create_email_suppressions.rb`; `app/models/email_campaign.rb`; `app/models/email_campaign_recipient.rb`; `app/models/email_suppression.rb` |
| **B** import extension | EDIT `app/services/campaign_imports/header_mapper.rb`; EDIT `app/services/campaign_imports/validator.rb`; `app/services/email_campaigns/recipient_importer.rb`; `app/services/email_campaigns/email_normalizer.rb` |
| **C** engine (jobs+liquid+cron) | EDIT `app/services/email_campaigns/ses/client.rb` (add `headers:` passthrough — see §C2); `app/jobs/email_campaigns/delivery_job.rb`; `app/jobs/email_campaigns/schedule_due_campaigns_job.rb`; `app/services/email_campaigns/delivery_engine.rb`; `app/services/email_campaigns/template_renderer.rb`; `app/services/email_campaigns/scheduler.rb` |
| **D** API | `app/controllers/api/v1/accounts/email_campaigns/campaigns_controller.rb`; `app/controllers/api/v1/accounts/email_campaigns/recipients_controller.rb`; `app/policies/email_campaign_policy.rb`; `app/views/api/v1/accounts/email_campaigns/campaigns/_campaign.json.jbuilder`; `.../campaigns/index.json.jbuilder`; `.../campaigns/show.json.jbuilder`; `app/views/api/v1/accounts/email_campaigns/recipients/_recipient.json.jbuilder`; `.../recipients/index.json.jbuilder` |
| **E** FE | `app/javascript/dashboard/api/emailCampaigns.js`; `app/javascript/dashboard/store/modules/emailCampaigns.js`; `app/javascript/dashboard/routes/dashboard/campaigns/pages/EmailCampaignsPage.vue`; `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue`; `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDetailsDialog.vue` |
| **F** i18n | new `CAMPAIGN.EMAIL_CAMPAIGN` block authored as a standalone fragment; reconciled into both `campaign.json` by J |
| **J** integration | EDIT `config/routes.rb`; EDIT `config/schedule.yml`; EDIT `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js`; EDIT `app/javascript/dashboard/store/index.js`; EDIT `app/javascript/dashboard/store/mutation-types.js`; merge F's block into `en/campaign.json` + `pt_BR/campaign.json` |

> No EE overlay required (admin-only feature; matches Onda 1 decision). `EmailCampaignPolicy`
> is OSS-only, no `prepend_mod_with`.

---

## Package A — Models + Migrations

### A1. Migration `db/migrate/20260612093000_create_email_campaigns.rb`

```ruby
class CreateEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :email_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :sender_identity, null: false,
                   foreign_key: { to_table: :email_sender_identities }
      t.string :name, null: false
      t.string :subject, null: false
      t.string :from_name
      t.text :body_html
      t.string :reply_to
      # status: draft(0) scheduled(1) sending(2) sent(3) paused(4) canceled(5) failed(6)
      t.integer :status, null: false, default: 0
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.integer :recipients_count, null: false, default: 0
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :suppressed_count, null: false, default: 0
      t.string :ses_configuration_set
      t.text :last_error

      t.timestamps
    end

    add_index :email_campaigns, [:account_id, :status, :scheduled_at],
              name: 'idx_email_campaigns_account_status_scheduled'
  end
end
```

### A2. Migration `db/migrate/20260612093100_create_email_campaign_recipients.rb`

```ruby
class CreateEmailCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    create_table :email_campaign_recipients do |t|
      t.references :email_campaign, null: false, foreign_key: true
      t.string :name
      t.string :email, null: false
      # status: pending(0) sent(1) failed(2) suppressed(3)
      t.integer :status, null: false, default: 0
      t.string :ses_message_id
      t.datetime :sent_at
      t.text :last_error

      t.timestamps
    end

    add_index :email_campaign_recipients,
              'email_campaign_id, lower(email)',
              unique: true,
              name: 'idx_email_campaign_recipients_campaign_email'
    add_index :email_campaign_recipients, [:email_campaign_id, :status],
              name: 'idx_email_campaign_recipients_campaign_status'
  end
end
```

### A3. Migration `db/migrate/20260612093200_create_email_suppressions.rb`

```ruby
class CreateEmailSuppressions < ActiveRecord::Migration[7.1]
  def change
    create_table :email_suppressions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :email, null: false
      t.string :reason   # hard_bounce / complaint / unsubscribe / manual
      t.string :source   # ses / api / import / manual
      t.datetime :created_at, null: false
    end

    add_index :email_suppressions,
              'account_id, lower(email)',
              unique: true,
              name: 'idx_email_suppressions_account_email'
  end
end
```

> Note: `email_suppressions` has only `created_at` (no `updated_at`) — it is an append /
> upsert log. Use a bare `create_table` column `t.datetime :created_at, null: false` (NOT
> `t.timestamps`). The table is WRITTEN by Onda 2 only via import/API manual add (source
> `import`/`manual`/`api`); the bounce/complaint auto-suppression and public-unsubscribe
> writers come in Onda 4. The DeliveryJob only READS it.

### A4. Model `app/models/email_campaign.rb`

```ruby
class EmailCampaign < ApplicationRecord
  belongs_to :account
  belongs_to :sender_identity, class_name: 'EmailSenderIdentity'

  has_many :email_campaign_recipients, dependent: :destroy

  enum status: {
    draft: 0, scheduled: 1, sending: 2, sent: 3, paused: 4, canceled: 5, failed: 6
  }

  validates :name, presence: true, length: { maximum: 120 }
  validates :subject, presence: true, length: { maximum: 250 }
  validates :body_html, presence: true
  validate  :sender_identity_must_belong_to_account
  validate  :reply_to_format, if: -> { reply_to.present? }

  scope :due, -> { scheduled.where('scheduled_at <= ?', Time.current) }

  EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP

  def sendable?
    (draft? || scheduled?) && sender_identity&.usable? && email_campaign_recipients.exists?
  end

  def terminal?
    sent? || canceled? || failed?
  end

  def mark_sending!
    update!(status: :sending)
  end

  def pause!
    return unless sending? || scheduled?

    update!(status: :paused)
  end

  def cancel!
    return if terminal?

    with_lock do
      update!(status: :canceled)
      email_campaign_recipients.where(status: :pending)
                               .update_all(status: EmailCampaignRecipient.statuses[:suppressed],
                                           updated_at: Time.current)
      refresh_counters!
    end
  end

  def finalize!
    refresh_counters!
    update!(status: :sent, sent_at: Time.current)
  end

  def refresh_counters!
    counts = email_campaign_recipients.group(:status).count
    update_columns(
      recipients_count: counts.values.sum,
      sent_count: count_for(counts, 'sent'),
      failed_count: count_for(counts, 'failed'),
      suppressed_count: count_for(counts, 'suppressed'),
      updated_at: Time.current
    )
  end

  private

  def count_for(counts, name)
    counts.fetch(name, counts.fetch(EmailCampaignRecipient.statuses[name], 0))
  end

  def sender_identity_must_belong_to_account
    return if sender_identity.nil?
    return if sender_identity.account_id == account_id

    errors.add(:sender_identity_id, 'must belong to the same account')
  end

  def reply_to_format
    errors.add(:reply_to, 'is invalid') unless reply_to.match?(EMAIL_REGEX)
  end
end
```

Notes: `ApplicationRecord` enforces a global 255-char string cap (MEMORY) — `subject`
validated ≤250 for headroom. The same global `validates_column_content_length` callback
also caps any `:text` column WITHOUT an explicit `:length` validator at 20,000 chars, so
`body_html` carries an explicit `length: { maximum: 500_000 }` (BODY_HTML_MAX) to suppress
that default and allow real marketing HTML. Counters refreshed via `update_columns`
(skip validation/callbacks), exactly the WhatsApp pattern.

### A5. Model `app/models/email_campaign_recipient.rb`

```ruby
class EmailCampaignRecipient < ApplicationRecord
  belongs_to :email_campaign

  enum status: { pending: 0, sent: 1, failed: 2, suppressed: 3 }

  before_validation :normalize_email

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :email_campaign_id, case_sensitive: false }

  def mark_sent!(ses_message_id)
    update!(status: :sent, ses_message_id: ses_message_id, sent_at: Time.current, last_error: nil)
  end

  def mark_failed!(message)
    update!(status: :failed, last_error: message.to_s.truncate(500))
  end

  def mark_suppressed!
    update!(status: :suppressed)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
```

### A6. Model `app/models/email_suppression.rb`

```ruby
class EmailSuppression < ApplicationRecord
  belongs_to :account

  REASONS = %w[hard_bounce complaint unsubscribe manual].freeze
  SOURCES = %w[ses api import manual].freeze

  before_validation :normalize_email
  before_create :set_created_at

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :account_id, case_sensitive: false }

  # Returns a downcased Set of suppressed emails for an account (DeliveryJob preload).
  def self.suppressed_set_for(account)
    where(account_id: account.id).pluck(:email).map(&:downcase).to_set
  end

  def self.suppressed?(account, email)
    where(account_id: account.id).where('lower(email) = ?', email.to_s.downcase).exists?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def set_created_at
    self.created_at ||= Time.current
  end
end
```

Notes: model has no `updated_at` column, so `ApplicationRecord` timestamp behavior must not
require it — defining `before_create :set_created_at` and a manual `created_at` keeps Rails
happy (Rails skips `updated_at` if the column is absent). Do NOT add `Account has_many`
inverse (scope via `where(account_id:)`), mirroring Onda 1.

---

## Package B — Import extension (email recipient list)

> **Design contract (locked).** The phone→Contacts import path through
> `CampaignImports::Importer` is **untouched**. Email recipients are imported by a NEW service
> `EmailCampaigns::RecipientImporter` that reuses ONLY `CampaignImports::Parser` (file parse)
> and `CampaignImports::HeaderMapper` (header detection, extended with an email alias + a
> `mode:` param). It writes `EmailCampaignRecipient` rows directly. No `campaign_imports`
> records, no Contacts, no labels, no `Importer`/`Validator` job pipeline.

### B1. EDIT `app/services/campaign_imports/header_mapper.rb`

Make `HeaderMapper` mode-aware so the phone path is byte-identical by default.

- Add `email` to `ALIASES`:
  ```ruby
  ALIASES = {
    name: ['nome', 'name', 'cliente', 'contato', 'nome completo', 'paciente'],
    phone_number: ['telefone', 'phone', 'phone_number', 'whatsapp', 'celular', 'numero', 'número'],
    email: ['email', 'e-mail', 'e mail', 'correio', 'correio eletronico', 'correio eletrônico']
  }.freeze
  ```
  (Adding a key to `ALIASES` does NOT change phone behavior — `logical_name_for` already
  iterates all aliases and the new `:email` logical name is simply never required unless mode
  asks for it.)
- Add an optional `mode:` keyword (default `:phone`) controlling which REQUIRED-header errors
  are emitted:
  ```ruby
  def initialize(headers, mode: :phone)
    @headers = Array(headers)
    @mode = mode
  end
  ```
  In `perform`, replace the hardcoded required-header errors with:
  ```ruby
  errors = []
  errors << 'missing_name_header' unless mapping.key?(:name)
  if @mode == :email
    errors << 'missing_email_header' unless mapping.key?(:email)
  else
    errors << 'missing_phone_number_header' unless mapping.key?(:phone_number)
  end
  errors += duplicated.uniq.map { |column| "duplicated_#{column}_header" }
  ```
  Default `mode: :phone` → identical output to today. Existing callers pass no `mode`.

### B2. `app/services/email_campaigns/email_normalizer.rb` (NEW)

```ruby
module EmailCampaigns
  class EmailNormalizer
    Error = Class.new(StandardError)
    Result = Struct.new(:email, :masked, keyword_init: true)

    def self.normalize!(raw)
      email = raw.to_s.strip.downcase
      raise Error, 'blank_email' if email.blank?
      raise Error, 'invalid_email' unless email.match?(EmailCampaign::EMAIL_REGEX)

      Result.new(email: email, masked: mask(email))
    end

    def self.mask(email)
      local, _at, domain = email.partition('@')
      head = local[0]
      "#{head}#{'*' * [local.length - 1, 1].max}@#{domain}"
    end
  end
end
```

### B3. EDIT `app/services/campaign_imports/validator.rb` — NO functional edit required

The `Validator` is bound to the phone job pipeline; the email path does NOT use it. **Do NOT
add email branches to `Validator`** (that would risk the phone path). Email row validation
lives entirely inside `RecipientImporter` (B4) via `EmailNormalizer`. (This package OWNS the
file only to guarantee no other package edits it; leave it unchanged unless a later wave needs
it. If RuboCop or a reviewer requires it, the file may stay byte-identical.)

> Rationale recorded for the architecture reviewer: threading an email mode through
> `Validator`/`Importer` (which assume `phone_hash`, label planning, Contacts) is higher-risk
> than a dedicated importer. The reused, low-risk pieces are `Parser` (pure file→rows) and
> `HeaderMapper` (pure header→index). That is the minimal, zero-regression surface.

### B4. `app/services/email_campaigns/recipient_importer.rb` (NEW)

```ruby
module EmailCampaigns
  class RecipientImporter
    Error = Class.new(StandardError)
    Result = Struct.new(:imported, :duplicates, :invalid, :suppressed, :total, keyword_init: true)

    MAX_ROWS = 50_000

    def initialize(campaign, file, filename:)
      @campaign = campaign
      @file = file
      @filename = filename
      @account = campaign.account
    end

    def perform
      parsed = CampaignImports::Parser.new(@file, filename: @filename).perform
      raise Error, 'unsupported_file_format' unless CampaignImports::Config.supported_formats.include?(parsed.format)

      mapping = header_mapping(parsed.headers)
      rows = data_rows(parsed)
      raise Error, 'empty_file' if rows.blank?
      raise Error, 'row_limit_exceeded' if rows.size > MAX_ROWS

      import_rows(rows, mapping)
    end

    private

    def header_mapping(headers)
      result = CampaignImports::HeaderMapper.new(headers, mode: :email).perform
      raise Error, result.errors.join(',') if result.errors.present?

      result.mapping
    end

    def data_rows(parsed)
      parsed.rows.reject { |row| row.values.all? { |v| v.to_s.strip.empty? } }
    end

    def import_rows(rows, mapping)
      suppressed = EmailSuppression.suppressed_set_for(@account)
      seen = Set.new
      stats = { imported: 0, duplicates: 0, invalid: 0, suppressed: 0 }

      ActiveRecord::Base.transaction do
        rows.each { |row| process_row(row, mapping, suppressed, seen, stats) }
        @campaign.refresh_counters!
      end

      Result.new(total: rows.size, **stats)
    end

    def process_row(row, mapping, suppressed, seen, stats)
      name = value_at(row, mapping[:name])
      raw_email = value_at(row, mapping[:email])
      normalized = EmailCampaigns::EmailNormalizer.normalize!(raw_email)
      email = normalized.email

      return (stats[:duplicates] += 1) if seen.include?(email) || existing?(email)

      seen << email
      status = suppressed.include?(email) ? :suppressed : :pending
      stats[suppressed.include?(email) ? :suppressed : :imported] += 1
      @campaign.email_campaign_recipients.create!(name: name.presence, email: email, status: status)
    rescue EmailCampaigns::EmailNormalizer::Error
      stats[:invalid] += 1
    end

    def existing?(email)
      @campaign.email_campaign_recipients.where('lower(email) = ?', email).exists?
    end

    def value_at(row, index)
      return '' if index.nil?

      row.values[index].to_s.strip
    end
  end
end
```

Contract: dedup by `lower(email)` within the campaign (both in-file via `seen` and against
already-persisted rows via `existing?`); suppressed emails are still inserted but with status
`suppressed` (so the per-campaign count is honest and DeliveryJob skips them); invalid rows are
counted and dropped (not fatal). Returns a `Result` the controller renders. Wrapped in one
transaction. NO Contacts, NO labels, NO `campaign_imports` row.

---

## Package C — Engine (jobs + liquid + cron)

### C1. `app/services/email_campaigns/template_renderer.rb` (NEW)

Thin Liquid wrapper. Mirrors the spirit of `Liquid::CampaignTemplateService` but takes a
recipient (name + email), supporting `{{ contact.name }}`, `{{ contact.email }}`, and the
pt_BR convenience aliases `{{ nome }}` / `{{ email }}`.

```ruby
module EmailCampaigns
  class TemplateRenderer
    def initialize(recipient)
      @recipient = recipient
    end

    def render(template)
      return '' if template.blank?

      Liquid::Template.parse(template).render(drops)
    rescue Liquid::Error
      template
    end

    private

    def drops
      name = @recipient.name.to_s
      email = @recipient.email.to_s
      {
        'contact' => { 'name' => name, 'email' => email },
        'nome' => name,
        'email' => email
      }
    end
  end
end
```

Notes: `Liquid::Template#render` accepts a plain Hash of String→value drops. `{{ contact.name }}`
resolves via the nested hash. Renders BOTH `subject` and `body_html` (call `.render` twice).

### C2. EDIT `app/services/email_campaigns/ses/client.rb` — add `headers:` passthrough

The Onda 1 `send_email` cannot set custom headers (List-Unsubscribe). Add an optional
`headers:` keyword that maps to SESv2 `Content.Simple.Headers` (array of `{Name:, Value:}`).
**Additive, default `nil` → byte-identical to today.**

```ruby
def send_email(from:, to:, subject:, html_body:, text_body: nil,
               configuration_set: nil, reply_to: nil, headers: nil)
  body = {
    FromEmailAddress: from,
    Destination: { ToAddresses: [to] },
    ReplyToAddresses: [reply_to].compact.presence,
    ConfigurationSetName: configuration_set,
    Content: { Simple: {
      Subject: { Data: subject },
      Body: email_body(html_body, text_body),
      Headers: ses_headers(headers)
    }.compact }
  }.compact
  post("#{API_VERSION_PATH}/outbound-emails", body)
end
```
Add private helper:
```ruby
def ses_headers(headers)
  return nil if headers.blank?

  headers.map { |name, value| { Name: name, Value: value } }
end
```
> SESv2 `Content.Simple.Headers` is the supported way to set `List-Unsubscribe` /
> `List-Unsubscribe-Post` on a Simple message. `.compact` on the inner Simple hash drops
> `Headers` when nil → no change to Onda 1 sends. This is the ONLY Onda 1 file Package C edits.

### C3. EDIT `app/services/email_campaigns/ses/sender.rb` — accept `headers:`

Add `headers: nil` to `deliver(...)` and pass it through to `@client.send_email(... headers: headers)`.
Additive (default nil). (Owned by C even though it is an Onda 1 file — listed in §C ownership.)

```ruby
def deliver(to:, subject:, html_body:, text_body: nil, from_email: nil, reply_to: nil, headers: nil)
  raise Error, "identity #{@identity.domain} is not verified" unless @identity.usable?

  response = @client.send_email(
    from: resolve_from(from_email), to: to, subject: subject,
    html_body: html_body, text_body: text_body, reply_to: reply_to,
    configuration_set: @identity.ses_configuration_set, headers: headers
  )
  response['MessageId']
end
```

> NOTE for J/ownership: `sender.rb` and `ses/client.rb` are Onda 1 files but their Onda 2
> edits are owned exclusively by Package C and are listed in the ownership table. No other
> package may touch them.

### C4. `app/services/email_campaigns/delivery_engine.rb` (NEW)

Batch delivery respecting SES max send rate. Idempotent: only sends to `pending` recipients;
skips suppressed; marks per-recipient status + `ses_message_id`.

```ruby
module EmailCampaigns
  class DeliveryEngine
    BATCH_SIZE = 100
    # SES sandbox MaxSendRate is ~1/s; sleep between sends to stay under the rate.
    SEND_INTERVAL = (1.0 / EmailCampaigns::Config.max_send_rate).seconds

    def initialize(campaign)
      @campaign = campaign
      @account = campaign.account
    end

    def perform
      return unless EmailCampaigns::Config.enabled?
      return unless eligible?

      @campaign.mark_sending! unless @campaign.sending?
      sender = EmailCampaigns::Ses::Sender.new(@campaign.sender_identity)
      suppressed = EmailSuppression.suppressed_set_for(@account)

      @campaign.email_campaign_recipients.pending.find_each(batch_size: BATCH_SIZE) do |recipient|
        break unless @campaign.reload.sending?

        deliver_one(recipient, sender, suppressed)
        sleep(SEND_INTERVAL) if SEND_INTERVAL.positive?
      end

      @campaign.finalize! if @campaign.reload.sending? && no_pending?
    end

    private

    def eligible?
      @campaign.reload
      return false unless @campaign.sending? || @campaign.scheduled?
      return false unless @campaign.sender_identity&.usable?

      true
    end

    def deliver_one(recipient, sender, suppressed)
      return recipient.mark_suppressed! if suppressed.include?(recipient.email.downcase)

      rendered = render(recipient)
      message_id = sender.deliver(
        to: recipient.email,
        subject: rendered[:subject],
        html_body: rendered[:body_html],
        reply_to: @campaign.reply_to.presence || default_reply_to,
        from_email: from_email,
        headers: unsubscribe_headers(recipient)
      )
      recipient.mark_sent!(message_id)
    rescue StandardError => e
      recipient.mark_failed!(e.message)
    ensure
      @campaign.refresh_counters!
    end

    def render(recipient)
      renderer = EmailCampaigns::TemplateRenderer.new(recipient)
      { subject: renderer.render(@campaign.subject), body_html: renderer.render(@campaign.body_html) }
    end

    def from_email
      [@campaign.from_name.presence, @campaign.sender_identity.from_email.presence]
        .then { |name, addr| addr.present? && name.present? ? "#{name} <#{addr}>" : addr }
    end

    def default_reply_to
      @campaign.sender_identity.from_email.presence
    end

    # RFC 8058 one-click unsubscribe. Placeholder URL — the real public endpoint is Onda 4.
    def unsubscribe_headers(recipient)
      token = EmailCampaigns::Config.unsubscribe_token(recipient)
      url = EmailCampaigns::Config.unsubscribe_url(token)
      {
        'List-Unsubscribe' => "<#{url}>",
        'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click'
      }
    end

    def no_pending?
      !@campaign.email_campaign_recipients.pending.exists?
    end
  end
end
```

> `from_email` helper: `from_name` is optional display name. If `sender_identity.from_email`
> is blank, `Ses::Sender#resolve_from` falls back to `no-reply@<domain>` (Onda 1 behavior) —
> so passing `from_email: nil` is safe; the helper above returns nil when addr blank.
> Simplify to: `def from_email; @campaign.from_name.present? && @campaign.sender_identity.from_email.present? ? "#{@campaign.from_name} <#{@campaign.sender_identity.from_email}>" : @campaign.sender_identity.from_email.presence; end`.

### C5. Config additions — EDIT decision

The unsubscribe token/url + `max_send_rate` constants belong in `EmailCampaigns::Config`
(an Onda 1 file owned by Onda 1 Package A). **To avoid editing an Onda 1 file from Package C**,
add these as constants/methods INSIDE `EmailCampaigns::DeliveryEngine` is NOT clean. DECISION:
Package C adds a tiny NEW file `app/services/email_campaigns/delivery_config.rb`:

```ruby
module EmailCampaigns
  module DeliveryConfig
    module_function

    def max_send_rate
      ENV.fetch('EMAIL_CAMPAIGN_SES_MAX_SEND_RATE', 1).to_f
    end

    # Placeholder unsubscribe link; real public endpoint ships in Onda 4. Token is a signed
    # global id so Onda 4 can resolve it without schema change.
    def unsubscribe_token(recipient)
      verifier.generate(recipient.id, purpose: :email_unsubscribe)
    end

    def unsubscribe_url(token)
      base = ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com')
      "#{base}/email_campaigns/unsubscribe/#{token}"
    end

    def verifier
      Rails.application.message_verifier(:email_campaign_unsubscribe)
    end
  end
end
```

Then in C4 replace `EmailCampaigns::Config.max_send_rate` → `EmailCampaigns::DeliveryConfig.max_send_rate`,
`EmailCampaigns::Config.unsubscribe_token` → `EmailCampaigns::DeliveryConfig.unsubscribe_token`,
`EmailCampaigns::Config.unsubscribe_url` → `EmailCampaigns::DeliveryConfig.unsubscribe_url`.
This keeps all Onda-2 config additive in a NEW file (no edit to `email_campaigns/config.rb`).

### C6. `app/jobs/email_campaigns/delivery_job.rb` (NEW)

```ruby
class EmailCampaigns::DeliveryJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    return unless EmailCampaigns::Config.enabled?

    campaign = EmailCampaign.find_by(id: campaign_id)
    return if campaign.blank?

    EmailCampaigns::DeliveryEngine.new(campaign).perform
  end
end
```

### C7. `app/services/email_campaigns/scheduler.rb` (NEW)

```ruby
module EmailCampaigns
  class Scheduler
    def perform
      return unless Config.enabled?

      EmailCampaign.due.find_each(batch_size: 50) { |campaign| start(campaign) }
    end

    private

    def start(campaign)
      enqueue = false
      campaign.with_lock do
        campaign.reload
        next unless campaign.scheduled? && campaign.scheduled_at <= Time.current
        next unless campaign.sender_identity&.usable?

        campaign.mark_sending!
        enqueue = true
      end
      EmailCampaigns::DeliveryJob.perform_later(campaign.id) if enqueue && Config.enabled?
    rescue StandardError => e
      campaign&.update(status: :failed, last_error: e.message.to_s.truncate(500))
    end
  end
end
```

### C8. `app/jobs/email_campaigns/schedule_due_campaigns_job.rb` (NEW)

```ruby
class EmailCampaigns::ScheduleDueCampaignsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailCampaigns::Scheduler.new.perform
  end
end
```

### C9. cron entry (J edits `config/schedule.yml`, append after the Onda 1 poll entry ~line 112)

```yaml
# executed every 5 minutes; enqueues delivery for due scheduled email campaigns.
# feature flag checked inside the job.
email_campaign_schedule_due_campaigns_job:
  cron: '*/5 * * * *'
  class: 'EmailCampaigns::ScheduleDueCampaignsJob'
  queue: scheduled_jobs
```

---

## Package D — API (controllers / routes / policy / jbuilder)

> Inherits the Onda 1 base controller
> `Api::V1::Accounts::EmailCampaigns::BaseController` (already exists; enforces
> `EmailCampaigns::Config.enabled?` → 404 when disabled). Do NOT re-create it.

### D1. `app/controllers/api/v1/accounts/email_campaigns/campaigns_controller.rb`

```ruby
class Api::V1::Accounts::EmailCampaigns::CampaignsController <
  Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_campaign, only: [:show, :update, :destroy, :send_now, :schedule, :pause, :cancel]

  def index
    authorize EmailCampaign
    @campaigns = campaign_scope.includes(:sender_identity).order(created_at: :desc)
  end

  def show; end

  def create
    @campaign = campaign_scope.new(campaign_params)
    authorize @campaign
    @campaign.ses_configuration_set = @campaign.sender_identity&.ses_configuration_set
    @campaign.save!
    render :show, status: :created
  end

  def update
    @campaign.assign_attributes(campaign_params)
    @campaign.save!
    render :show
  end

  def destroy
    @campaign.destroy!
    head :no_content
  end

  def send_now
    return render_unprocessable('email_campaign.not_sendable') unless @campaign.sendable?

    @campaign.mark_sending!
    EmailCampaigns::DeliveryJob.perform_later(@campaign.id)
    render :show
  end

  def schedule
    return render_unprocessable('email_campaign.scheduled_at_required') if params[:scheduled_at].blank?

    @campaign.update!(status: :scheduled, scheduled_at: params[:scheduled_at])
    render :show
  end

  def pause
    @campaign.pause!
    render :show
  end

  def cancel
    @campaign.cancel!
    render :show
  end

  private

  def campaign_scope
    EmailCampaign.where(account: Current.account)
  end

  def fetch_campaign
    @campaign = campaign_scope.find(params[:id])
    authorize @campaign
  end

  def campaign_params
    params.require(:email_campaign)
          .permit(:name, :subject, :from_name, :body_html, :reply_to, :sender_identity_id)
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
```

### D2. `app/controllers/api/v1/accounts/email_campaigns/recipients_controller.rb`

Nested under a campaign. `index` lists recipients (paginated + counts); `create` triggers an
import (multipart upload) via `RecipientImporter`.

```ruby
class Api::V1::Accounts::EmailCampaigns::RecipientsController <
  Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_campaign
  before_action :set_current_page, only: [:index]

  RESULTS_PER_PAGE = 50

  def index
    @recipients = @campaign.email_campaign_recipients
                           .order(:id)
                           .page(@current_page).per(RESULTS_PER_PAGE)
    @recipients_count = @campaign.email_campaign_recipients.count
  end

  def create
    return render_unprocessable('email_campaign.import_file_required') if params[:import_file].blank?
    return render_unprocessable('email_campaign.file_too_large') if too_large?
    return render_unprocessable('email_campaign.not_editable') unless @campaign.draft?

    @result = EmailCampaigns::RecipientImporter.new(
      @campaign, params[:import_file], filename: params[:import_file].original_filename
    ).perform
    @campaign.reload
    render :index
  rescue EmailCampaigns::RecipientImporter::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_campaign
    @campaign = EmailCampaign.where(account: Current.account).find(params[:campaign_id])
    authorize @campaign, :show?
  end

  def too_large?
    params[:import_file].size > CampaignImports::Config.max_file_size_bytes
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
```

> `authorize @campaign, :show?` reuses `EmailCampaignPolicy#show?` for recipient access
> (admin-only, account-scoped). `index` renders the recipients `index.json.jbuilder`; `create`
> renders the SAME view (recipient list refreshed) — the FE re-reads counts off the campaign.

### D3. Routes (J edits `config/routes.rb`, INSIDE the existing `namespace :email_campaigns`
block ~line 213, as a sibling to `resources :sender_identities`)

```ruby
namespace :email_campaigns do
  resources :sender_identities, only: [:index, :create, :show] do
    member do
      post :verify
    end
  end
  resources :campaigns, only: [:index, :create, :show, :update, :destroy] do
    member do
      post :send_now
      post :schedule
      post :pause
      post :cancel
    end
    resources :recipients, only: [:index, :create]
  end
end
```

Resulting base paths under `/api/v1/accounts/:account_id/email_campaigns/campaigns`.
Member helper prefix: `send_now_api_v1_account_email_campaigns_campaign` etc. Nested:
`api_v1_account_email_campaigns_campaign_recipients`.

### D4. Policy `app/policies/email_campaign_policy.rb` (TOP-LEVEL — named after record class)

```ruby
class EmailCampaignPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def create?
    administrator?
  end

  def update?
    show?
  end

  def destroy?
    show?
  end

  def send_now?
    show?
  end

  def schedule?
    show?
  end

  def pause?
    show?
  end

  def cancel?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
```

> CRITICAL (Onda 1 lesson): the policy is `EmailCampaignPolicy` at
> `app/policies/email_campaign_policy.rb` (NOT `EmailCampaigns::CampaignPolicy`). Pundit infers
> the policy from the record class `EmailCampaign`; a namespaced policy breaks the lookup.

### D5. jbuilder views

Dir `app/views/api/v1/accounts/email_campaigns/campaigns/`.

`_campaign.json.jbuilder`:
```ruby
json.id campaign.id
json.account_id campaign.account_id
json.sender_identity_id campaign.sender_identity_id
json.sender_domain campaign.sender_identity&.domain
json.name campaign.name
json.subject campaign.subject
json.from_name campaign.from_name
json.body_html campaign.body_html
json.reply_to campaign.reply_to
json.status campaign.status
json.scheduled_at campaign.scheduled_at
json.sent_at campaign.sent_at
json.recipients_count campaign.recipients_count
json.sent_count campaign.sent_count
json.failed_count campaign.failed_count
json.suppressed_count campaign.suppressed_count
json.ses_configuration_set campaign.ses_configuration_set
json.last_error campaign.last_error
json.created_at campaign.created_at
json.updated_at campaign.updated_at
```

`index.json.jbuilder`:
```ruby
json.payload do
  json.campaigns do
    json.array! @campaigns, partial: 'campaign', as: :campaign
  end
end
```

`show.json.jbuilder`:
```ruby
json.payload do
  json.partial! 'campaign', campaign: @campaign
end
```

Dir `app/views/api/v1/accounts/email_campaigns/recipients/`.

`_recipient.json.jbuilder`:
```ruby
json.id recipient.id
json.email_campaign_id recipient.email_campaign_id
json.name recipient.name
json.email recipient.email
json.status recipient.status
json.ses_message_id recipient.ses_message_id
json.sent_at recipient.sent_at
json.last_error recipient.last_error
json.created_at recipient.created_at
```

`index.json.jbuilder`:
```ruby
json.payload do
  json.campaign do
    json.partial! 'api/v1/accounts/email_campaigns/campaigns/campaign', campaign: @campaign
  end
  json.recipients do
    json.array! @recipients, partial: 'api/v1/accounts/email_campaigns/recipients/recipient', as: :recipient
  end
  json.meta do
    json.count @recipients_count
    json.current_page @current_page.to_i
  end
  if @result
    json.import_result do
      json.imported @result.imported
      json.duplicates @result.duplicates
      json.invalid @result.invalid
      json.suppressed @result.suppressed
      json.total @result.total
    end
  end
end
```

---

## Package E — Frontend (Campanhas area: Email Campaigns sub-page)

### E1. API module `app/javascript/dashboard/api/emailCampaigns.js`

```js
/* global axios */
import ApiClient from './ApiClient';

class EmailCampaignsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/campaigns', { accountScoped: true });
  }

  sendNow(id) {
    return axios.post(`${this.url}/${id}/send_now`);
  }

  schedule(id, scheduledAt) {
    return axios.post(`${this.url}/${id}/schedule`, { scheduled_at: scheduledAt });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  getRecipients(id, page = 1) {
    return axios.get(`${this.url}/${id}/recipients?page=${page}`);
  }

  importRecipients(id, file) {
    const formData = new FormData();
    formData.append('import_file', file);
    return axios.post(`${this.url}/${id}/recipients`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new EmailCampaignsAPI();
```

Notes: `create({ email_campaign: {...} })`, `update(id, { email_campaign: {...} })`,
`get()`, `show(id)`, `delete(id)` come from `ApiClient`. The store wraps payloads under
`email_campaign`.

### E2. Store module `app/javascript/dashboard/store/modules/emailCampaigns.js`

Mirror `emailSenderIdentities.js`. State `{ records, recipients: [], importResult: null,
uiFlags: { isFetching, isCreating, isUpdating, isDeleting, isImporting } }`. Getters
`getCampaigns`, `getRecipients`, `getImportResult`, `getUIFlags`. Actions:
- `get({ commit })` → `EmailCampaignsAPI.get()`, commit `SET_EMAIL_CAMPAIGNS` with
  `response.data.payload.campaigns`.
- `create({ commit }, payload)` → `EmailCampaignsAPI.create({ email_campaign: payload })`,
  commit `ADD_EMAIL_CAMPAIGN` with `response.data.payload`; return payload.
- `update({ commit }, { id, ...payload })` → `EmailCampaignsAPI.update(id, { email_campaign: payload })`,
  commit `EDIT_EMAIL_CAMPAIGN`.
- `delete({ commit }, id)` → `EmailCampaignsAPI.delete(id)`, commit `DELETE_EMAIL_CAMPAIGN`.
- `sendNow({ commit }, id)` / `schedule({ commit }, { id, scheduledAt })` /
  `pause` / `cancel` → call API, commit `EDIT_EMAIL_CAMPAIGN` with `response.data.payload`.
- `getRecipients({ commit }, { id, page })` → commit `SET_EMAIL_CAMPAIGN_RECIPIENTS` with
  `response.data.payload.recipients`; also commit `EDIT_EMAIL_CAMPAIGN` with
  `response.data.payload.campaign`.
- `importRecipients({ commit }, { id, file })` → `EmailCampaignsAPI.importRecipients(id, file)`,
  commit `SET_EMAIL_CAMPAIGN_RECIPIENTS` + `SET_EMAIL_CAMPAIGN_IMPORT_RESULT` with
  `response.data.payload.import_result`, and `EDIT_EMAIL_CAMPAIGN` with `payload.campaign`.

Use `MutationHelpers.set/create/update` like the WhatsApp/sender modules; `DELETE_EMAIL_CAMPAIGN`
removes by id from `records`.

### E3. Mutation types (J edits `app/javascript/dashboard/store/mutation-types.js`)
```
SET_EMAIL_CAMPAIGN_UI_FLAG: 'SET_EMAIL_CAMPAIGN_UI_FLAG',
SET_EMAIL_CAMPAIGNS: 'SET_EMAIL_CAMPAIGNS',
ADD_EMAIL_CAMPAIGN: 'ADD_EMAIL_CAMPAIGN',
EDIT_EMAIL_CAMPAIGN: 'EDIT_EMAIL_CAMPAIGN',
DELETE_EMAIL_CAMPAIGN: 'DELETE_EMAIL_CAMPAIGN',
SET_EMAIL_CAMPAIGN_RECIPIENTS: 'SET_EMAIL_CAMPAIGN_RECIPIENTS',
SET_EMAIL_CAMPAIGN_IMPORT_RESULT: 'SET_EMAIL_CAMPAIGN_IMPORT_RESULT',
```

### E4. Store registration (J edits `app/javascript/dashboard/store/index.js`)
Add `import emailCampaigns from './modules/emailCampaigns';` and `emailCampaigns,` to modules.

### E5. Page `.../campaigns/pages/EmailCampaignsPage.vue`

`<script setup>` + Composition API. Mirror `EmailSenderPage.vue` shell (`CampaignLayout`,
`globalConfig` gate, `useMapGetter`, `onMounted` fetch). Behavior:
- `enabled = computed(() => globalConfig.value?.emailCampaignEnabled === true &&
  globalConfig.value?.crmKanbanEnabled === true)`.
- `campaigns = useMapGetter('emailCampaigns/getCampaigns')`; `uiFlags`.
- `onMounted` → if enabled `store.dispatch('emailCampaigns/get')` AND
  `store.dispatch('emailSenderIdentities/get')` (compose dialog needs verified domains).
- `<CampaignLayout :header-title="t('CAMPAIGN.EMAIL_CAMPAIGN.HEADER_TITLE')"
  :button-label="t('CAMPAIGN.EMAIL_CAMPAIGN.NEW')" @click="openCompose()">`.
- `#action` slot → `<EmailCampaignDialog v-if="showDialog" :campaign="editing"
  @saved="..." @close="...">`.
- List: each campaign card shows name, subject, a status badge
  (`CAMPAIGN.EMAIL_CAMPAIGN.STATUS.*`; map draft→slate, scheduled→blue, sending→amber,
  sent→teal, paused→amber, canceled→slate, failed→ruby — reuse the EmailSenderPage
  `text-n-*-11 bg-n-*-3` token helper), recipient counts
  (`recipients_count` / `sent_count` / `failed_count` / `suppressed_count`), and action
  buttons: "Manage recipients" (opens `EmailCampaignDetailsDialog`), "Send now"
  (`i-lucide-send`, only when `status==='draft'` and `recipients_count>0`), "Schedule"
  (`i-lucide-calendar-clock`), "Pause" (`status==='sending'`), "Cancel"
  (`status` in draft/scheduled/sending/paused). Use `Button` from components-next.
- Empty state `CAMPAIGN.EMAIL_CAMPAIGN.EMPTY_STATE.*`.
- Send-now/cancel/pause dispatch the matching store action + `useAlert` success/error i18n.

### E6. Dialog `.../components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue`

`<script setup>` + components-next `Dialog`/`Input`/`Button` (+ a `<select>` styled with
`n-*` tokens for the sender domain & status-less compose). Props: `campaign` (optional, for
edit). Fields:
- `name` (text, required).
- `subject` (text, required, supports `{{ nome }}`).
- `senderIdentityId` (select of VERIFIED identities only:
  `useMapGetter('emailSenderIdentities/getIdentities')` filtered `status==='verified'`;
  if none, show `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NO_VERIFIED_DOMAIN` with a link hint to the
  Email sending domains page).
- `fromName` (text, optional).
- `replyTo` (text, optional — email; helper text "responses become a conversation in the
  connected inbox" via i18n; no inbox-select wiring in Onda 2, a free email field is
  acceptable — Reply-To inbox association is refined later).
- `bodyHtml` (a `<textarea>` with `n-*` tokens, monospace, rows=12; label
  `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BODY_LABEL`, helper notes Liquid `{{ nome }}` /
  `{{ contact.name }}` support + that a one-click unsubscribe link is added automatically).
- On submit → `emailCampaigns/create` (or `update` when editing) with
  `{ name, subject, senderIdentityId→sender_identity_id, fromName→from_name, replyTo→reply_to,
  bodyHtml→body_html }` (store maps camelCase→snake_case in the action payload), emit `saved`,
  `useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SUCCESS'))`. Validate name/subject/body/
  senderIdentityId non-empty (i18n errors under `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.*_ERROR`).

### E7. Recipients dialog `.../EmailCampaign/EmailCampaignDetailsDialog.vue`

`<script setup>` + components-next `Dialog`. Props: `campaign`. On open dispatch
`emailCampaigns/getRecipients`. Shows:
- Upload area reusing the campaign-import UX pattern (`<input type="file"
  accept=".csv,.xlsx">` styled with `n-*`; "select file" button) → on file pick dispatch
  `emailCampaigns/importRecipients({ id, file })`; show `import_result` summary
  (imported / duplicates / invalid / suppressed / total) via
  `CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.IMPORT_RESULT.*`. Disabled unless `campaign.status ===
  'draft'`.
- Counts row from `campaign` (recipients/sent/failed/suppressed).
- Paginated recipient table (email · name · status badge · sent_at · last_error) from
  `getRecipients`.
- i18n under `CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.*`.

### E8. FE route (J edits `campaigns.routes.js`)

Add import `import EmailCampaignsPage from './pages/EmailCampaignsPage.vue';` and a child route
AFTER the `email_sender` route:
```js
{
  path: 'email_campaigns',
  name: 'campaigns_email_index',
  meta,
  beforeEnter: (to, _from, next) => {
    if (
      window.globalConfig?.EMAIL_CAMPAIGN_ENABLED === 'true' &&
      window.globalConfig?.CRM_KANBAN_ENABLED === 'true'
    ) {
      next();
      return;
    }
    next({ name: 'campaigns_sms_index', params: to.params });
  },
  component: EmailCampaignsPage,
},
```
(`meta` already carries `featureFlag: FEATURE_FLAGS.CAMPAIGNS` + `permissions: ['administrator']`.)

---

## Package F — i18n (block authored once, J merges into both files, parity 1:1)

Insert a SIBLING block `CAMPAIGN.EMAIL_CAMPAIGN` under root `CAMPAIGN` in
`en/campaign.json` AND `pt_BR/campaign.json`, after the `EMAIL_SENDER` block.

### English (`en/campaign.json`)
```json
"EMAIL_CAMPAIGN": {
  "HEADER_TITLE": "Email campaigns",
  "NEW": "New email campaign",
  "DESCRIPTION": "Compose an email, pick a verified sending domain, upload your recipient list and send now or schedule it.",
  "EMPTY_STATE": {
    "TITLE": "No email campaigns yet",
    "SUBTITLE": "Create your first campaign to compose and send an email to an imported list."
  },
  "STATUS": {
    "DRAFT": "Draft",
    "SCHEDULED": "Scheduled",
    "SENDING": "Sending",
    "SENT": "Sent",
    "PAUSED": "Paused",
    "CANCELED": "Canceled",
    "FAILED": "Failed"
  },
  "COUNTS": {
    "RECIPIENTS": "Recipients",
    "SENT": "Sent",
    "FAILED": "Failed",
    "SUPPRESSED": "Suppressed"
  },
  "ACTIONS": {
    "MANAGE_RECIPIENTS": "Recipients",
    "EDIT": "Edit",
    "DELETE": "Delete",
    "SEND_NOW": "Send now",
    "SCHEDULE": "Schedule",
    "PAUSE": "Pause",
    "CANCEL": "Cancel",
    "SEND_SUCCESS": "Campaign queued for sending.",
    "SCHEDULE_SUCCESS": "Campaign scheduled.",
    "PAUSE_SUCCESS": "Campaign paused.",
    "CANCEL_SUCCESS": "Campaign canceled.",
    "DELETE_SUCCESS": "Campaign deleted.",
    "ERROR": "Something went wrong. Please try again."
  },
  "DIALOG": {
    "CREATE_TITLE": "New email campaign",
    "EDIT_TITLE": "Edit email campaign",
    "NAME_LABEL": "Campaign name",
    "NAME_PLACEHOLDER": "e.g. June newsletter",
    "NAME_ERROR": "Enter a campaign name",
    "SUBJECT_LABEL": "Subject",
    "SUBJECT_PLACEHOLDER": "e.g. Hi {{ nome }}, news from us",
    "SUBJECT_ERROR": "Enter a subject",
    "SENDER_LABEL": "Sending domain",
    "SENDER_PLACEHOLDER": "Select a verified domain",
    "SENDER_ERROR": "Select a verified sending domain",
    "NO_VERIFIED_DOMAIN": "No verified sending domain yet. Add and verify one under Email sending domains first.",
    "FROM_NAME_LABEL": "From name (optional)",
    "FROM_NAME_PLACEHOLDER": "e.g. Acme Marketing",
    "REPLY_TO_LABEL": "Reply-to (optional)",
    "REPLY_TO_PLACEHOLDER": "e.g. support@yourcompany.com",
    "REPLY_TO_HINT": "Replies go to this address; connect it as an inbox to turn replies into conversations.",
    "BODY_LABEL": "Email body (HTML)",
    "BODY_PLACEHOLDER": "<p>Hi {{ nome }}, ...</p>",
    "BODY_HINT": "Use {{ nome }} or {{ contact.name }} to personalize. A one-click unsubscribe link is added automatically.",
    "BODY_ERROR": "Enter the email body",
    "SUBMIT": "Save campaign",
    "CANCEL": "Cancel",
    "SUCCESS": "Campaign saved.",
    "ERROR": "Could not save the campaign. Please try again."
  },
  "SCHEDULE_DIALOG": {
    "TITLE": "Schedule campaign",
    "DATETIME_LABEL": "Send at",
    "DATETIME_ERROR": "Pick a date and time",
    "SUBMIT": "Schedule",
    "CANCEL": "Cancel"
  },
  "RECIPIENTS": {
    "TITLE": "Recipients",
    "SUBTITLE": "Upload a CSV or XLSX with name and email columns. Recipients are used only for this campaign and are not added to your contacts.",
    "UPLOAD": "Upload list",
    "UPLOAD_HINT": "CSV or XLSX with name + email columns.",
    "TABLE": {
      "EMAIL": "Email",
      "NAME": "Name",
      "STATUS": "Status",
      "SENT_AT": "Sent at",
      "ERROR": "Error"
    },
    "STATUS": {
      "PENDING": "Pending",
      "SENT": "Sent",
      "FAILED": "Failed",
      "SUPPRESSED": "Suppressed"
    },
    "IMPORT_RESULT": {
      "TITLE": "Import finished",
      "IMPORTED": "Imported",
      "DUPLICATES": "Duplicates skipped",
      "INVALID": "Invalid skipped",
      "SUPPRESSED": "Suppressed",
      "TOTAL": "Total rows"
    },
    "EMPTY": "No recipients yet. Upload a list to get started.",
    "IMPORT_SUCCESS": "Recipient list imported.",
    "IMPORT_ERROR": "Could not import the list. Check the file format and columns."
  }
}
```

### Portuguese (`pt_BR/campaign.json`) — same key tree
```json
"EMAIL_CAMPAIGN": {
  "HEADER_TITLE": "Campanhas de e-mail",
  "NEW": "Nova campanha de e-mail",
  "DESCRIPTION": "Componha um e-mail, escolha um domínio de envio verificado, suba sua lista de destinatários e envie agora ou agende.",
  "EMPTY_STATE": {
    "TITLE": "Nenhuma campanha de e-mail ainda",
    "SUBTITLE": "Crie sua primeira campanha para compor e enviar um e-mail para uma lista importada."
  },
  "STATUS": {
    "DRAFT": "Rascunho",
    "SCHEDULED": "Agendada",
    "SENDING": "Enviando",
    "SENT": "Enviada",
    "PAUSED": "Pausada",
    "CANCELED": "Cancelada",
    "FAILED": "Falhou"
  },
  "COUNTS": {
    "RECIPIENTS": "Destinatários",
    "SENT": "Enviados",
    "FAILED": "Falharam",
    "SUPPRESSED": "Suprimidos"
  },
  "ACTIONS": {
    "MANAGE_RECIPIENTS": "Destinatários",
    "EDIT": "Editar",
    "DELETE": "Excluir",
    "SEND_NOW": "Enviar agora",
    "SCHEDULE": "Agendar",
    "PAUSE": "Pausar",
    "CANCEL": "Cancelar",
    "SEND_SUCCESS": "Campanha enfileirada para envio.",
    "SCHEDULE_SUCCESS": "Campanha agendada.",
    "PAUSE_SUCCESS": "Campanha pausada.",
    "CANCEL_SUCCESS": "Campanha cancelada.",
    "DELETE_SUCCESS": "Campanha excluída.",
    "ERROR": "Algo deu errado. Tente novamente."
  },
  "DIALOG": {
    "CREATE_TITLE": "Nova campanha de e-mail",
    "EDIT_TITLE": "Editar campanha de e-mail",
    "NAME_LABEL": "Nome da campanha",
    "NAME_PLACEHOLDER": "ex.: Newsletter de junho",
    "NAME_ERROR": "Informe um nome para a campanha",
    "SUBJECT_LABEL": "Assunto",
    "SUBJECT_PLACEHOLDER": "ex.: Olá {{ nome }}, novidades para você",
    "SUBJECT_ERROR": "Informe um assunto",
    "SENDER_LABEL": "Domínio de envio",
    "SENDER_PLACEHOLDER": "Selecione um domínio verificado",
    "SENDER_ERROR": "Selecione um domínio de envio verificado",
    "NO_VERIFIED_DOMAIN": "Nenhum domínio de envio verificado ainda. Adicione e verifique um em Domínios de envio de e-mail primeiro.",
    "FROM_NAME_LABEL": "Nome do remetente (opcional)",
    "FROM_NAME_PLACEHOLDER": "ex.: Marketing Acme",
    "REPLY_TO_LABEL": "Responder para (opcional)",
    "REPLY_TO_PLACEHOLDER": "ex.: suporte@suaempresa.com",
    "REPLY_TO_HINT": "As respostas vão para este endereço; conecte-o como uma caixa de entrada para transformar respostas em conversas.",
    "BODY_LABEL": "Corpo do e-mail (HTML)",
    "BODY_PLACEHOLDER": "<p>Olá {{ nome }}, ...</p>",
    "BODY_HINT": "Use {{ nome }} ou {{ contact.name }} para personalizar. Um link de descadastro de 1 clique é adicionado automaticamente.",
    "BODY_ERROR": "Informe o corpo do e-mail",
    "SUBMIT": "Salvar campanha",
    "CANCEL": "Cancelar",
    "SUCCESS": "Campanha salva.",
    "ERROR": "Não foi possível salvar a campanha. Tente novamente."
  },
  "SCHEDULE_DIALOG": {
    "TITLE": "Agendar campanha",
    "DATETIME_LABEL": "Enviar em",
    "DATETIME_ERROR": "Escolha uma data e hora",
    "SUBMIT": "Agendar",
    "CANCEL": "Cancelar"
  },
  "RECIPIENTS": {
    "TITLE": "Destinatários",
    "SUBTITLE": "Suba um CSV ou XLSX com colunas de nome e e-mail. Os destinatários são usados apenas nesta campanha e não são adicionados aos seus contatos.",
    "UPLOAD": "Subir lista",
    "UPLOAD_HINT": "CSV ou XLSX com colunas de nome + e-mail.",
    "TABLE": {
      "EMAIL": "E-mail",
      "NAME": "Nome",
      "STATUS": "Status",
      "SENT_AT": "Enviado em",
      "ERROR": "Erro"
    },
    "STATUS": {
      "PENDING": "Pendente",
      "SENT": "Enviado",
      "FAILED": "Falhou",
      "SUPPRESSED": "Suprimido"
    },
    "IMPORT_RESULT": {
      "TITLE": "Importação concluída",
      "IMPORTED": "Importados",
      "DUPLICATES": "Duplicados ignorados",
      "INVALID": "Inválidos ignorados",
      "SUPPRESSED": "Suprimidos",
      "TOTAL": "Total de linhas"
    },
    "EMPTY": "Nenhum destinatário ainda. Suba uma lista para começar.",
    "IMPORT_SUCCESS": "Lista de destinatários importada.",
    "IMPORT_ERROR": "Não foi possível importar a lista. Verifique o formato do arquivo e as colunas."
  }
}
```

---

## Package J — Integration (edits to shared files)

1. `config/routes.rb`: ADD `resources :campaigns ... do member ... resources :recipients ... end`
   INSIDE the existing `namespace :email_campaigns` block (§D3). Do NOT remove
   `resources :sender_identities`.
2. `config/schedule.yml`: append the `email_campaign_schedule_due_campaigns_job` cron (§C9)
   after the Onda 1 `email_campaign_poll_pending_identities_job` entry.
3. `campaigns.routes.js`: import `EmailCampaignsPage` + add `email_campaigns` child route
   after `email_sender` (§E8).
4. `store/index.js`: import + register the `emailCampaigns` module (§E4).
5. `store/mutation-types.js`: add the 7 mutation types (§E3).
6. Merge F's `EMAIL_CAMPAIGN` block into BOTH `en/campaign.json` and `pt_BR/campaign.json`
   (after `EMAIL_SENDER`); run i18n parity check.

> No `dashboard_controller.rb` / `globalConfig.js` edit needed — `EMAIL_CAMPAIGN_ENABLED` /
> `emailCampaignEnabled` already exist from Onda 1.

---

## Gates (run after build)
- `ruby -c` on every new/edited `.rb`.
- `pnpm eslint` on touched JS/Vue.
- i18n parity: `en/campaign.json` vs `pt_BR/campaign.json` key trees identical.
- `vite build` clean.
- `eager_load` on a temp Swarm service (catches policy/class-name mismatches — verify
  `EmailCampaignPolicy` resolves for `EmailCampaign`).
- Regression: confirm a phone CSV still imports through `campaign_imports` unchanged
  (HeaderMapper default `mode: :phone`).
- Real SES send smoke (human, later): create an `EmailCampaign` on the verified `hub2you.ai`
  identity, import a one-row list of a sandbox-verified address, `send_now`, confirm
  `ses_message_id` stored + status `sent` + the email arrives with a `List-Unsubscribe`
  header; import a list containing a suppressed address → recipient lands `suppressed`,
  DeliveryJob skips it.

## Out of scope (later waves — do NOT build in Onda 2)
- Onda 3: tracking pixel, click rewrite, SNS event webhook + configuration-set event
  destinations, `EmailEvent` model, RD-style report page in CRM "Gestão campanhas".
- Onda 4: public one-click unsubscribe ENDPOINT (Onda 2 only emits the header + token),
  auto-suppression on bounce/complaint, per-tenant guardrail monitor + daily caps.
- Reply-To → inbox association wiring (Onda 2 uses a free Reply-To email field).
- "Save recipients as contacts."
```