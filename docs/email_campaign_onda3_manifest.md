# Email Campaign — ONDA 3 Build Manifest (AUTHORITATIVE)

> Fork Chatwoot v4.14.1 EE (Hub2you / Autonomia) at
> `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`. Rails 7.1 + Vue 3.
> Single source of truth for parallel impl agents. All paths ABSOLUTE-relative to the repo
> root above. **Build ONLY Onda 3**: (1) `EmailEvent` model + event-derived counters; (2) OWN
> tracking (open pixel + click redirect, signed-token, public, listmonk/Postal style) + a
> `TrackingInjector` wired into the DeliveryEngine at send time; (3) SES SNS ingestion
> (public webhook: SubscriptionConfirmation + Notification → Delivery/Bounce/Complaint →
> EmailEvent + recipient status + counters + auto-suppression on hard bounce/complaint) + a
> configuration-set event-destination ensurer; (4) RD-style report page in CRM ("Gestão
> campanhas" / "Campaign Management") with KPIs/filter/who-opened-clicked; (5) bounded retry
> for TRANSIENT send failures in the DeliveryEngine + a re-enqueue sweep; (6) i18n pt_BR+en.
>
> **Do NOT build** the public unsubscribe LANDING page / preference center (Onda 4). Onda 3
> only adds the bounce/complaint **auto-suppression** that the SNS events drive (writing
> `EmailSuppression` rows), NOT the user-facing unsubscribe endpoint.
>
> Build **ON TOP OF** shipped+enabled Onda 1 + Onda 2. Do NOT rebuild or break them. Do NOT
> modify any Onda 1/2 file EXCEPT the ones explicitly assigned below (`delivery_engine.rb`,
> `email_campaign.rb`, `email_campaign_recipient.rb`, `config/routes.rb`, `config/schedule.yml`,
> `crm.routes.js`, `Sidebar.vue`, `settings.json`, `crm.json`).
>
> Scope source: `docs/email_campaign_v1_prd.md` §9 (Onda 3) + task brief.

---

## 0. Hard rules (apply to every package)

- **Additive + ZERO regression.** Do NOT touch native `Campaign`, `Channel::Email`,
  `WhatsappApiCampaign*`, `campaign_imports/*`. New backend lives under a new top-level model
  `EmailEvent` + the existing `EmailCampaigns::*` service/job namespace + new
  `EmailCampaigns::Tracking::*` and `EmailCampaigns::Sns::*` sub-namespaces.
- **Inert unless enabled.** Every entrypoint (controller, job, cron, FE route, tracking +
  SNS public endpoints) checks `EmailCampaigns::Config.enabled?` (Ruby) /
  `globalConfig.emailCampaignEnabled === true && globalConfig.crmKanbanEnabled === true` (FE).
  `EmailCampaigns::Config.enabled?` already ANDs `Crm::Config.enabled?` with
  `EMAIL_CAMPAIGN_ENABLED` (Onda 1, do not change).
- **gem-free SES** (no `aws-sdk-ses`/`aws-sdk-sesv2`; signed HTTPS via `Aws::Sigv4::Signer`).
  **`aws-sdk-sns` IS bundled** (`1.70.0`) — use `Aws::SNS::MessageVerifier` for SNS signature
  verification and `Aws::SNS::Client` for topic create/subscribe. **NO new gem, NO Dockerfile
  change.**
- **Public endpoints (tracking pixel, click redirect, SNS webhook) are the ONLY
  unauthenticated additions.** They MUST be safe: pixel/click resolve the recipient ONLY from
  a signed `Rails.application.message_verifier` token (reuse the Onda 2 `DeliveryConfig`
  verifier family); click redirects ONLY to the signed original URL carried in the token (NO
  open redirect); SNS verified via `Aws::SNS::MessageVerifier#authentic?`. No account auth, no
  CSRF token.
- **Ruby:** RuboCop, ≤150 cols, compact `module/class`. `ruby -c` every `.rb` touched.
- **Vue 3 `<script setup>` + Composition API**, Tailwind `n-*` tokens ONLY (no scoped /
  custom / inline CSS), `components-next`, `i-lucide-*`, NO bare strings (i18n everywhere).
- **i18n parity:** every key added to `en/*.json` MUST be added to `pt_BR/*.json` with an
  identical key tree. vue-i18n treats `{ }`, `@`, `|` as special — any literal `{{ liquid }}`
  example must be written as `{'{{ liquid }}'}` and any literal `@` as `{'@'}`.

### Verified environment facts (DO NOT re-investigate)

- **`Aws::SNS::MessageVerifier` IS available** (`vendor/bundle/.../aws-sdk-sns-1.70.0/lib/
  aws-sdk-sns/message_verifier.rb`). API:
  `Aws::SNS::MessageVerifier.new.authentic?(raw_json_string) # => Boolean` (also
  `authenticate!` which raises `Aws::SNS::MessageVerifier::VerificationError`). It takes the
  **raw JSON body string** (it parses + canonicalizes + downloads the AWS-hosted `.pem` cert,
  verifying the cert host matches `sns.<region>.amazonaws.com`). Supports SignatureVersion 1
  and 2. **Use `authentic?` and treat false as 403.**
- **`Aws::SNS::Client` IS available** (aws-sdk-sns 1.70.0): `create_topic(name:)`,
  `subscribe(topic_arn:, protocol:, endpoint:, attributes:)`, `set_subscription_attributes`.
  Construct with explicit creds:
  `Aws::SNS::Client.new(region:, access_key_id:, secret_access_key:)` reading from
  `EmailCampaigns::Config`. (SNS may use the gem; only SES must stay gem-free.)
- **DeliveryEngine claim model (CRITICAL for retry).** The real
  `app/services/email_campaigns/delivery_engine.rb` `deliver_one` does:
  1. skip + `mark_suppressed!` if email in suppressed set;
  2. `claim(recipient)` = atomic `UPDATE ... SET status=sent WHERE id=? AND status=pending`
     (flips pending→sent BEFORE the SES call, at-most-once);
  3. render, `sender.deliver(...)`, then `recipient.update_columns(ses_message_id:, sent_at:,
     last_error: nil, ...)`;
  4. `rescue StandardError` → logs + `recipient.mark_failed!(e.message)` (sets status=failed);
  5. `ensure` → `@campaign.refresh_counters!`.
  Onda 3 retry replaces step 4's blanket `mark_failed!` with `handle_send_failure` (transient
  → back to `pending` + `attempts += 1` until `MAX_ATTEMPTS`; then `failed`). The claim stays:
  a row already flipped to `sent` whose SES call SUCCEEDED is never re-sent.
- `EmailCampaignRecipient` enum today: `{ pending: 0, sent: 1, failed: 2, suppressed: 3 }`.
  Onda 3 ADDS `delivered: 4, opened: 5, clicked: 6, bounced: 7, complained: 8` (additive
  integer values — existing rows unaffected). Tracking/SNS advance status forward; the
  delivery claim still only matches `status = sent(1)`-from-`pending(0)`, untouched.
- `EmailCampaign` counters today: `recipients_count, sent_count, failed_count,
  suppressed_count` (refreshed by `refresh_counters!` via `recipients.group(:status).count`).
  Onda 3 ADDS `delivered_count, opened_count, clicked_count, bounced_count, complained_count,
  unsubscribed_count` and extends `refresh_counters!` to fill them from **EmailEvent counts**
  (NOT recipient status, because a recipient can open many times / open is deduped per
  recipient but click/bounce derive from events).
- `EmailCampaigns::DeliveryConfig` (Onda 2, `app/services/email_campaigns/delivery_config.rb`):
  `module_function`; `max_send_rate`; `unsubscribe_token(recipient)` /`unsubscribe_url(token)`;
  `verifier` = `Rails.application.message_verifier(:email_campaign_unsubscribe)`. Onda 3 ADDS
  tracking token + base-URL helpers in a NEW file `tracking/token.rb` (does NOT edit
  `delivery_config.rb`).
- `EmailCampaigns::Ses::Client` (gem-free SESv2). Onda 3 ADDS a method to PUT a configuration
  set event destination (gem-free SES) — owned by Package C as an additive edit (see §C5).
- `EmailCampaigns::Ses::ConfigurationSetEnsurer#perform(name)` idempotently creates the config
  set. Onda 3 EventDestinationEnsurer composes with it (does NOT replace it).
- Public/unauth controller pattern: inherit `ApplicationController`,
  `skip_before_action :authenticate_user!, raise: false` + `skip_before_action
  :set_current_user` (see `app/controllers/api/v1/webhooks_controller.rb`). CSRF: API
  controllers are token-exempt; for these top-level controllers add
  `skip_before_action :verify_authenticity_token, raise: false` to be safe (mirrors
  `webhooks/*` controllers which inherit `ActionController::API`-ish behavior; verify on build).
  Top-level public routes live in `config/routes.rb` AFTER the `Rails.application.routes.draw`
  account/api blocks, in the channel-integration region (~line 715, next to `webhooks/*`).
- Tracking-pixel precedent in-repo: `get 'hc/:slug/articles/:article_slug.png', to:
  'public/api/v1/portals/articles#tracking_pixel'` — confirms a public GIF/PNG endpoint is an
  accepted pattern.
- CRM report backend pattern: `Api::V1::Accounts::Crm::ReportsController <
  Api::V1::Accounts::Crm::BaseController`; `before_action :authorize_reports` →
  `authorize %i[crm report], :view?`; renders `render json: { payload: ... }` (NO jbuilder for
  CRM reports — they emit plain hashes). Policy `Crm::ReportPolicy < ApplicationPolicy`
  (`view? { account_user.present? }`) + `prepend_mod_with('Crm::ReportPolicy')` with an EE
  overlay `enterprise/app/policies/enterprise/crm/report_policy.rb` overriding `view?` to a
  `crm_permission?` check. **Onda 3 report uses jbuilder** (per task brief) but follows the
  `json.payload do ... end` convention; policy is a top-level model policy (see §D).
- CRM report FE pattern: `CrmDashboardPage.vue` / `CrmSlaPage.vue` are `<script setup>` pages
  that hold data in `ref()` and fetch directly via an API class (`CrmKanbanAPI.getReportX`) in
  `onMounted` — **NO Vuex store module for reports**. Gate: `CrmSlaPage` uses an account
  feature flag; the new page uses the `globalConfig` email-campaign gate.
- CRM FE routes: `app/javascript/dashboard/routes/dashboard/crm/crm.routes.js` — array of
  routes with `meta` permissions + `beforeEnter: ensureCrmEnabled`. New route appended here.
- CRM sidebar: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — the CRM block
  (~line 577-613) builds `children:[]` with conditional spreads; an `emailCampaignEnabled`
  computed already exists (~line 86: `globalConfig.value?.emailCampaignEnabled === true &&
  crmKanbanEnabled.value`). Add a child entry gated on it.
- Sidebar i18n labels live in `app/javascript/dashboard/i18n/locale/{en,pt_BR}/settings.json`
  under `SIDEBAR` (e.g. `CRM_SLA` line ~314). CRM page-body i18n lives in
  `app/javascript/dashboard/i18n/locale/{en,pt_BR}/crm.json` (its own namespace; root keys like
  `CRM_SLA` at line ~806). The new page's strings go in `crm.json` under a new root
  `CAMPAIGN_MANAGEMENT`; the sidebar label goes in `settings.json` under `SIDEBAR`.
- globalConfig: `app/javascript/shared/store/globalConfig.js` already maps
  `EMAIL_CAMPAIGN_ENABLED → emailCampaignEnabled` and `CRM_KANBAN_ENABLED → crmKanbanEnabled`.
  No globalConfig edit needed.
- Latest migration timestamp on disk: `20260612093200_create_email_suppressions.rb`. **Onda 3
  migrations start at `20260612094000` and increase.** Use `ActiveRecord::Migration[7.1]`.
- `ApplicationPolicy` exposes `account`, `account_user`, `user`, `record`. `ApplicationRecord`
  global 255-char cap on string columns + 20k cap on text columns without an explicit length
  validator (MEMORY) — `EmailEvent.url` is a `:string` (≤255 fine for tracked URLs; longer
  URLs are stored truncated — see §A).

---

## File ownership table (DISJOINT — no file in two packages)

| Pkg | Owns (create unless noted EDIT) |
|-----|----------------------------|
| **A** models+migrations+counters | `db/migrate/20260612094000_create_email_events.rb`; `db/migrate/20260612094100_add_event_counters_to_email_campaigns.rb`; `db/migrate/20260612094200_add_retry_and_tracking_to_email_campaign_recipients.rb`; `app/models/email_event.rb`; EDIT `app/models/email_campaign.rb` (event-counter columns + `refresh_counters!` extension + `has_many :email_events`); EDIT `app/models/email_campaign_recipient.rb` (new enum values + `has_many :email_events` + retry helpers `mark_retryable!` / `register_attempt!` + tracking-status helpers `mark_delivered!`/`mark_opened!`/`mark_clicked!`/`mark_bounced!`/`mark_complained!`) |
| **B** tracking + DeliveryEngine | `app/services/email_campaigns/tracking/token.rb`; `app/services/email_campaigns/tracking/injector.rb`; `app/services/email_campaigns/tracking/event_recorder.rb`; `app/controllers/email_campaigns/tracking_controller.rb`; EDIT `app/services/email_campaigns/delivery_engine.rb` (**SINGLE OWNER** — BOTH the tracking-injection edit AND the retry edit live here) |
| **C** SNS ingestion + config | `app/controllers/email_campaigns/sns_controller.rb`; `app/services/email_campaigns/sns/message_handler.rb`; `app/services/email_campaigns/sns/event_processor.rb`; `app/services/email_campaigns/ses/event_destination_ensurer.rb`; EDIT `app/services/email_campaigns/ses/client.rb` (add `put_configuration_set_event_destination` — additive); `lib/tasks/email_campaigns.rake` (operational ensurer invoker) |
| **D** report backend | `app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb`; `app/services/email_campaigns/reports/builder.rb`; `app/policies/email_campaign_report_policy.rb`; `app/views/api/v1/accounts/email_campaigns/reports/index.json.jbuilder`; `app/views/api/v1/accounts/email_campaigns/reports/show.json.jbuilder` |
| **E** report FE | `app/javascript/dashboard/api/emailCampaignReports.js`; `app/javascript/dashboard/routes/dashboard/crm/pages/CrmCampaignManagementPage.vue` |
| **F** retry job/cron | `app/jobs/email_campaigns/retry_sweep_job.rb`; `app/services/email_campaigns/retry_sweeper.rb` (recipient retry HELPER methods are owned by A on the model; the DeliveryEngine retry EDIT is owned by B) |
| **G** i18n | new `crm.json` `CAMPAIGN_MANAGEMENT` block + new `settings.json` `SIDEBAR.CRM_CAMPAIGN_MANAGEMENT` label, authored as standalone fragments; reconciled into both locales by J |
| **J** integration | EDIT `config/routes.rb` (public tracking + SNS routes + authed report route); EDIT `config/schedule.yml` (retry-sweep cron); EDIT `app/javascript/dashboard/routes/dashboard/crm/crm.routes.js`; EDIT `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`; merge G's blocks into `en/crm.json`+`pt_BR/crm.json` and `en/settings.json`+`pt_BR/settings.json` |

> **`delivery_engine.rb` single-owner = Package B.** Package F owns ONLY the sweep
> job/service/cron; the recipient model retry helper methods are owned by Package A (model).
> No other package edits `delivery_engine.rb`.
>
> EE policy: report is account-scoped admin/agent read like CRM reports. **No EE overlay
> required** for Onda 3 (the report policy is OSS-only, top-level — see §D rationale). If the
> security reviewer wants custom-role parity later, add an `enterprise/` overlay then.

---

## Package A — Models + Migrations + Counters

### A1. Migration `db/migrate/20260612094000_create_email_events.rb`

```ruby
class CreateEmailEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :email_events do |t|
      t.references :recipient, null: false,
                   foreign_key: { to_table: :email_campaign_recipients }
      # type: delivered(0) open(1) click(2) bounce(3) complaint(4) unsubscribe(5)
      t.integer :event_type, null: false
      t.string :url
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :email_events, [:recipient_id, :event_type],
              name: 'idx_email_events_recipient_type'
    add_index :email_events, :occurred_at, name: 'idx_email_events_occurred_at'
  end
end
```

> Column is `event_type` (NOT `type` — `type` is reserved by Rails STI). The model maps the
> enum name `type` → column `event_type` via `enum type: {...}, _prefix: ...`? NO — Rails
> `enum` cannot remap to a differently-named column cleanly; instead the model declares
> `enum event_type: {...}` and exposes a `type`-like API only if needed. **Decision: model
> attribute + enum is named `event_type`** (the jbuilder/report read `event.event_type`). The
> PRD's "type enum" maps to this column. Keep it consistent everywhere.

### A2. Migration `db/migrate/20260612094100_add_event_counters_to_email_campaigns.rb`

```ruby
class AddEventCountersToEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaigns, :delivered_count, :integer, null: false, default: 0
    add_column :email_campaigns, :opened_count, :integer, null: false, default: 0
    add_column :email_campaigns, :clicked_count, :integer, null: false, default: 0
    add_column :email_campaigns, :bounced_count, :integer, null: false, default: 0
    add_column :email_campaigns, :complained_count, :integer, null: false, default: 0
    add_column :email_campaigns, :unsubscribed_count, :integer, null: false, default: 0
  end
end
```

### A3. Migration `db/migrate/20260612094200_add_retry_and_tracking_to_email_campaign_recipients.rb`

```ruby
class AddRetryAndTrackingToEmailCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaign_recipients, :attempts, :integer, null: false, default: 0
    add_column :email_campaign_recipients, :last_event_at, :datetime
  end
end
```

### A4. Model `app/models/email_event.rb` (NEW, top-level)

```ruby
class EmailEvent < ApplicationRecord
  belongs_to :recipient, class_name: 'EmailCampaignRecipient'

  enum event_type: {
    delivered: 0, open: 1, click: 2, bounce: 3, complaint: 4, unsubscribe: 5
  }

  validates :occurred_at, presence: true

  scope :opens, -> { where(event_type: :open) }
  scope :clicks, -> { where(event_type: :click) }

  before_validation { self.occurred_at ||= Time.current }
end
```

> `EmailEvent` is top-level (no namespace) — Pundit/AR autoload friendly. `payload` jsonb keeps
> the raw SES/tracking context. No `account` column: scope to account via
> `recipient.email_campaign.account` (joins for the report).

### A5. EDIT `app/models/email_campaign_recipient.rb`

- Extend the enum (ADDITIVE values — keep existing 0-3):
  ```ruby
  enum status: { pending: 0, sent: 1, failed: 2, suppressed: 3,
                 delivered: 4, opened: 5, clicked: 6, bounced: 7, complained: 8 }
  ```
- Add association: `has_many :email_events, foreign_key: :recipient_id, dependent: :destroy`.
- Add retry helpers (called ONLY by the DeliveryEngine rescue — see §B/§F):
  ```ruby
  MAX_ATTEMPTS = 3

  # Transient failure: undo the optimistic sent-claim, bump attempts, requeue as pending
  # until MAX_ATTEMPTS, then permanently failed. Uses update_columns to skip the email
  # uniqueness validator on this re-save path (no email change).
  def register_attempt!(message)
    new_attempts = attempts.to_i + 1
    if new_attempts >= MAX_ATTEMPTS
      update_columns(status: self.class.statuses[:failed], attempts: new_attempts,
                     last_error: message.to_s.truncate(500), updated_at: Time.current)
    else
      update_columns(status: self.class.statuses[:pending], attempts: new_attempts,
                     last_error: message.to_s.truncate(500), updated_at: Time.current)
    end
  end

  def retryable?
    pending? && attempts.to_i < MAX_ATTEMPTS
  end
  ```
- Add forward status helpers used by tracking + SNS (idempotent, only advance, never regress a
  bounced/complained/clicked back to delivered):
  ```ruby
  def mark_delivered!
    return unless sent? || delivered?
    update_columns(status: self.class.statuses[:delivered], last_event_at: Time.current, updated_at: Time.current)
  end

  def mark_opened!
    return if bounced? || complained?
    update_columns(status: self.class.statuses[:opened], last_event_at: Time.current, updated_at: Time.current) unless clicked?
    touch_event_time
  end

  def mark_clicked!
    return if bounced? || complained?
    update_columns(status: self.class.statuses[:clicked], last_event_at: Time.current, updated_at: Time.current)
  end

  def mark_bounced!
    update_columns(status: self.class.statuses[:bounced], last_event_at: Time.current, updated_at: Time.current)
  end

  def mark_complained!
    update_columns(status: self.class.statuses[:complained], last_event_at: Time.current, updated_at: Time.current)
  end

  private

  def touch_event_time
    update_columns(last_event_at: Time.current, updated_at: Time.current)
  end
  ```
  (Keep existing `mark_sent!`/`mark_failed!`/`mark_suppressed!`/`normalize_email`.)

### A6. EDIT `app/models/email_campaign.rb`

- Add `has_many :email_events, through: :email_campaign_recipients, source: :email_events`.
- Extend `refresh_counters!` to also fill the event-derived counters. The recipient-status
  counts stay as-is; the event counts are computed from `email_events` grouped by `event_type`,
  with **open deduped per recipient** (distinct recipient_id) and click/bounce/complaint/
  unsubscribe as event counts:
  ```ruby
  def refresh_counters!
    counts = email_campaign_recipients.group(:status).count
    ev = event_counters
    update_columns(
      recipients_count: counts.values.sum,
      sent_count: count_for(counts, 'sent'),
      failed_count: count_for(counts, 'failed'),
      suppressed_count: count_for(counts, 'suppressed'),
      delivered_count: ev[:delivered],
      opened_count: ev[:opened],
      clicked_count: ev[:clicked],
      bounced_count: ev[:bounced],
      complained_count: ev[:complained],
      unsubscribed_count: ev[:unsubscribed],
      updated_at: Time.current
    )
  end
  ```
  Add private:
  ```ruby
  def event_counters
    by_type = email_events.group(:event_type).count   # keys are enum INT or string per AR version
    {
      delivered: type_count(by_type, :delivered),
      # opens deduped per recipient (Apple MPP inflation — report labels APPROXIMATE):
      opened: email_events.opens.distinct.count(:recipient_id),
      clicked: type_count(by_type, :click),
      bounced: type_count(by_type, :bounce),
      complained: type_count(by_type, :complaint),
      unsubscribed: type_count(by_type, :unsubscribe)
    }
  end

  def type_count(by_type, name)
    by_type.fetch(name.to_s, by_type.fetch(EmailEvent.event_types[name.to_s], 0))
  end
  ```
  (`count_for` already exists from Onda 2 — keep it.)

> NOTE: `sent_count` continues to count recipients in status `sent` only. Because tracking/SNS
> advance a recipient's status forward (sent→delivered→opened→clicked), `sent_count` reflects
> "sent but not yet delivered/opened" — the report computes **total attempted sends** as
> `recipients_count - pending - suppressed - failed` OR simply uses the event/derived counters.
> The report (Package D) presents: enviados (sent attempts) = `delivered_count + bounced_count +
> still-sent`, entregues = `delivered_count`, abertos = `opened_count`, clicados =
> `clicked_count`, descadastros = `unsubscribed_count`, bounces = `bounced_count`, spam =
> `complained_count`. **Rates are over `delivered_count`** (PRD §6).

---

## Package B — Tracking (token + injector + recorder + public controller) + DeliveryEngine

All tracking classes under `module EmailCampaigns; module Tracking; ... end; end`.

### B1. `app/services/email_campaigns/tracking/token.rb` (NEW)

Signed token, reusing the Rails message_verifier family (same approach as Onda 2
`DeliveryConfig.verifier`). Two token flavors: open (recipient_id only) and click
(recipient_id + original url).

```ruby
module EmailCampaigns
  module Tracking
    module Token
      module_function

      def verifier
        Rails.application.message_verifier(:email_campaign_tracking)
      end

      # open pixel: encodes recipient id
      def encode_open(recipient)
        verifier.generate({ r: recipient.id, k: 'o' }, purpose: :email_open)
      end

      # click redirect: encodes recipient id + the original (validated http/https) url
      def encode_click(recipient, url)
        verifier.generate({ r: recipient.id, u: url, k: 'c' }, purpose: :email_click)
      end

      def decode_open(token)
        decode(token, :email_open)
      end

      def decode_click(token)
        decode(token, :email_click)
      end

      def decode(token, purpose)
        verifier.verify(token, purpose: purpose)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      # tracking base url: ENV override else FRONTEND_URL (PRD §3 own tracking domain).
      def base_url
        ENV.fetch('EMAIL_CAMPAIGN_TRACKING_BASE_URL', nil).presence ||
          ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com')
      end

      def open_url(recipient)
        "#{base_url}/email_campaigns/t/o/#{encode_open(recipient)}.gif"
      end

      def click_url(recipient, url)
        "#{base_url}/email_campaigns/t/c/#{encode_click(recipient, url)}"
      end
    end
  end
end
```

> Token carries the original URL so the click endpoint redirects ONLY to the signed value (no
> open-redirect possible — a tampered token fails `verify`). Purposes namespace open vs click.

### B2. `app/services/email_campaigns/tracking/injector.rb` (NEW)

Rewrites every `http(s)` `href` to the click-redirect URL and appends a 1x1 open pixel. Safe +
idempotent.

```ruby
module EmailCampaigns
  module Tracking
    # Rewrites http/https hrefs to the signed click-redirect URL and appends a 1x1 open pixel.
    # Skips mailto:/tel:/#anchor and already-tracked links. Idempotent (a second pass is a
    # no-op: rewritten hrefs already point at the tracking base_url; the pixel is appended once).
    class Injector
      PIXEL_MARKER = 'data-ec-pixel'.freeze

      def initialize(recipient, html)
        @recipient = recipient
        @html = html.to_s
      end

      def perform
        return @html if @html.blank?

        body = rewrite_hrefs(@html)
        append_pixel(body)
      end

      private

      def rewrite_hrefs(html)
        html.gsub(/href\s*=\s*("|')(.*?)\1/i) do
          quote = Regexp.last_match(1)
          url = Regexp.last_match(2)
          "href=#{quote}#{rewritten(url)}#{quote}"
        end
      end

      def rewritten(url)
        return url unless trackable?(url)

        EmailCampaigns::Tracking::Token.click_url(@recipient, url)
      end

      def trackable?(url)
        return false if url.blank?
        return false unless url =~ %r{\Ahttps?://}i
        return false if url.start_with?(EmailCampaigns::Tracking::Token.base_url) # already tracked

        true
      end

      def append_pixel(html)
        return html if html.include?(PIXEL_MARKER)

        pixel = %(<img #{PIXEL_MARKER}="1" src="#{EmailCampaigns::Tracking::Token.open_url(@recipient)}" ) +
                %(width="1" height="1" alt="" style="display:none" />)
        if html =~ %r{</body>}i
          html.sub(%r{</body>}i, "#{pixel}</body>")
        else
          html + pixel
        end
      end
    end
  end
end
```

> `mailto:`/`tel:`/`#anchor`/relative hrefs are skipped by the `\Ahttps?://` guard. The
> `base_url` prefix check makes a second injection pass a no-op (idempotent). Regex-based
> rewrite (no nokogiri dependency change) is acceptable for marketing HTML; matches listmonk's
> link-rewrite approach.

### B3. `app/services/email_campaigns/tracking/event_recorder.rb` (NEW)

Shared recording used by the public tracking controller (and reusable by SNS). Creates an
`EmailEvent`, advances recipient status, bumps campaign counters. Open is deduped per recipient.

```ruby
module EmailCampaigns
  module Tracking
    class EventRecorder
      def initialize(recipient)
        @recipient = recipient
        @campaign = recipient.email_campaign
      end

      def record_open(payload = {})
        # dedup: only the first open creates the event + flips status; later opens are ignored
        return if @recipient.email_events.opens.exists?

        @recipient.email_events.create!(event_type: :open, occurred_at: Time.current, payload: payload)
        @recipient.mark_opened!
        @campaign.refresh_counters!
      end

      def record_click(url, payload = {})
        @recipient.email_events.create!(event_type: :click, url: url.to_s.truncate(255),
                                        occurred_at: Time.current, payload: payload)
        @recipient.mark_clicked!
        @campaign.refresh_counters!
      end
    end
  end
end
```

> Open dedup is per-recipient (PRD says dedup optional — we dedup to keep `opened_count` honest;
> still labeled APPROXIMATE in the report due to Apple MPP). Clicks are NOT deduped (each
> distinct click logged) but a click also implies an open — `mark_clicked!` wins over opened.

### B4. `app/controllers/email_campaigns/tracking_controller.rb` (NEW, PUBLIC)

```ruby
class EmailCampaigns::TrackingController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_user, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  TRANSPARENT_GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\xFF\xFF\xFF\x00\x00\x00!\xF9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b.freeze

  # GET /email_campaigns/t/o/:token.gif  — open pixel. ALWAYS returns 200 + the GIF, even on a
  # bad token or disabled feature (never leak; never error a mail client).
  def open
    record_open if EmailCampaigns::Config.enabled?
    send_pixel
  end

  # GET /email_campaigns/t/c/:token — click redirect. Verify token, record, 302 to the SIGNED
  # original URL ONLY. On bad token → redirect to FRONTEND_URL root (never open-redirect, never
  # echo an attacker URL).
  def click
    data = EmailCampaigns::Tracking::Token.decode_click(params[:token]) if EmailCampaigns::Config.enabled?
    url = safe_redirect_url(data)
    record_click(data, url) if EmailCampaigns::Config.enabled? && data.present?
    redirect_to url, allow_other_host: true
  end

  private

  def record_open
    data = EmailCampaigns::Tracking::Token.decode_open(params[:token])
    return if data.blank?

    recipient = EmailCampaignRecipient.find_by(id: data[:r] || data['r'])
    return if recipient.nil?

    EmailCampaigns::Tracking::EventRecorder.new(recipient).record_open('ua' => request.user_agent)
  rescue StandardError => e
    Rails.logger.warn("[EmailCampaigns::Tracking#open] #{e.message}")
  end

  def record_click(data, url)
    recipient = EmailCampaignRecipient.find_by(id: data[:r] || data['r'])
    return if recipient.nil?

    EmailCampaigns::Tracking::EventRecorder.new(recipient).record_click(url, 'ua' => request.user_agent)
  rescue StandardError => e
    Rails.logger.warn("[EmailCampaigns::Tracking#click] #{e.message}")
  end

  # ONLY the signed url from a valid token; otherwise the frontend root. Never an open redirect.
  def safe_redirect_url(data)
    candidate = (data && (data[:u] || data['u'])).to_s
    return EmailCampaigns::Tracking::Token.base_url unless candidate =~ %r{\Ahttps?://}i

    candidate
  end

  def send_pixel
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
    send_data TRANSPARENT_GIF, type: 'image/gif', disposition: 'inline'
  end
end
```

> The GIF endpoint NEVER errors and NEVER reveals validity (always 200 + pixel). The click
> endpoint redirects ONLY to the cryptographically-signed URL — a forged/tampered token fails
> `verify` → `data` is nil → redirect to the safe base. `allow_other_host: true` is required
> because the signed URL is an external marketing link.

### B5. EDIT `app/services/email_campaigns/delivery_engine.rb` (SINGLE OWNER — tracking + retry)

Two edits, both in this file:

**(a) Tracking injection at send time.** In `deliver_one`, AFTER `render(recipient)` and BEFORE
calling `sender.deliver`, run the body through the Injector so it composes with the Onda 2
Liquid render and the List-Unsubscribe header. Exact edit — replace the `html_body:` argument:

```ruby
rendered = render(recipient)
tracked_html = EmailCampaigns::Tracking::Injector.new(recipient, rendered[:body_html]).perform
message_id = sender.deliver(
  to: recipient.email,
  subject: rendered[:subject],
  html_body: tracked_html,
  reply_to: @campaign.reply_to.presence || default_reply_to,
  from_email: from_email,
  headers: unsubscribe_headers(recipient)
)
recipient.update_columns(ses_message_id: message_id, sent_at: Time.current, last_error: nil, updated_at: Time.current)
```

(The List-Unsubscribe placeholder header from Onda 2 stays unchanged. Injection happens on the
rendered HTML only — the subject is not rewritten.)

**(b) Bounded retry on transient send failure.** Replace the current
`rescue StandardError => e ... recipient.mark_failed!(e.message)` branch with a
transient-aware handler. The claim already flipped the row pending→sent; on a transient
failure we must UNDO that (back to pending) so the sweep can retry. On a permanent failure or
after `MAX_ATTEMPTS`, mark failed.

```ruby
rescue StandardError => e
  Rails.logger.error("[EmailCampaigns::DeliveryEngine] campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
  handle_send_failure(recipient, e)
ensure
  @campaign.refresh_counters!
end
```

Add private:

```ruby
# SES transient signals: throttling / 5xx / timeouts. Permanent (bad address, validation) →
# fail immediately. Heuristic on the Ses::Error message + transport exceptions.
TRANSIENT_PATTERNS = /throttl|throttling|timeout|timed out|temporar|503|500|502|504|rate exceeded|service unavailable/i

def handle_send_failure(recipient, error)
  if transient?(error)
    recipient.register_attempt!(error.message)  # pending (retryable) until MAX_ATTEMPTS, then failed
  else
    recipient.mark_failed!(error.message)
  end
end

def transient?(error)
  return true if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout) || error.is_a?(Timeout::Error)

  error.message.to_s.match?(TRANSIENT_PATTERNS)
end
```

> at-most-once preserved: a recipient whose SES call SUCCEEDED is never reset to pending (no
> exception → no rescue). Only a FAILED send (where SES did not accept the message) is requeued.
> A transient failure leaves `status=pending, attempts+=1`; the campaign stays `sending` (not
> finalized) because `no_pending?` is false → `finalize!` is skipped; the RetrySweepJob (§F)
> re-enqueues delivery after a backoff. After `MAX_ATTEMPTS` the row is `failed` (permanent),
> `no_pending?` becomes true, and the next run finalizes the campaign.

> EDGE: if a transient failure leaves pending rows but the engine's `find_each` loop already
> finished, `finalize!` is skipped (guarded by `no_pending?`). The campaign remains `sending`
> until the sweep requeues + all rows reach a terminal state. This is correct.

---

## Package C — SNS ingestion + configuration-set event destination

All under `module EmailCampaigns; module Sns; ... end; end` for services; the controller is
`EmailCampaigns::SnsController`.

### C1. `app/controllers/email_campaigns/sns_controller.rb` (NEW, PUBLIC)

```ruby
class EmailCampaigns::SnsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_user, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  # POST /email_campaigns/sns  — SES event notifications via SNS (Delivery/Bounce/Complaint).
  # Handles SubscriptionConfirmation (auto-confirm) + Notification. Verifies the SNS signature.
  def create
    return head :not_found unless EmailCampaigns::Config.enabled?

    raw = request.raw_post
    EmailCampaigns::Sns::MessageHandler.new(raw).process
    head :ok
  rescue EmailCampaigns::Sns::MessageHandler::InvalidSignature
    head :forbidden
  rescue StandardError => e
    Rails.logger.error("[EmailCampaigns::Sns] #{e.message}")
    head :ok  # 200 so SNS does not hot-retry on our internal error; we log + drop.
  end
end
```

### C2. `app/services/email_campaigns/sns/message_handler.rb` (NEW)

```ruby
module EmailCampaigns
  module Sns
    class MessageHandler
      class InvalidSignature < StandardError; end

      def initialize(raw_body)
        @raw = raw_body.to_s
        @msg = JSON.parse(@raw)
      rescue JSON::ParserError
        @msg = {}
      end

      def process
        raise InvalidSignature unless verified?

        case @msg['Type']
        when 'SubscriptionConfirmation' then confirm_subscription
        when 'Notification'             then handle_notification
        end
      end

      private

      def verified?
        return false if @msg.blank?

        Aws::SNS::MessageVerifier.new.authentic?(@raw)
      end

      # Auto-confirm: GET the SubscribeURL (AWS-hosted https).
      def confirm_subscription
        url = @msg['SubscribeURL']
        return if url.blank?

        Net::HTTP.get_response(URI.parse(url))
      end

      def handle_notification
        ses_event = JSON.parse(@msg['Message'].to_s)
        EmailCampaigns::Sns::EventProcessor.new(ses_event).process
      rescue JSON::ParserError
        nil
      end
    end
  end
end
```

> `Aws::SNS::MessageVerifier#authentic?` does the cert download + canonical-string +
> signature verification; it also enforces the cert is hosted by AWS. We additionally only act
> on `SubscribeURL`s it has already validated as part of a verified message.

### C3. `app/services/email_campaigns/sns/event_processor.rb` (NEW)

Maps the SES event JSON → recipient by `ses_message_id` → EmailEvent + recipient status +
counters; hard bounce / complaint → `EmailSuppression` (account-scoped, idempotent).

```ruby
module EmailCampaigns
  module Sns
    class EventProcessor
      def initialize(ses_event)
        @event = ses_event || {}
      end

      def process
        recipient = find_recipient
        return if recipient.nil?

        case event_type
        when 'Delivery'  then on_delivery(recipient)
        when 'Bounce'    then on_bounce(recipient)
        when 'Complaint' then on_complaint(recipient)
        end
      end

      private

      # SES publishes either eventType (event publishing) or notificationType (legacy feedback).
      def event_type
        @event['eventType'] || @event['notificationType']
      end

      def message_id
        @event.dig('mail', 'messageId')
      end

      def find_recipient
        return nil if message_id.blank?

        EmailCampaignRecipient.find_by(ses_message_id: message_id)
      end

      def campaign_for(recipient)
        recipient.email_campaign
      end

      def on_delivery(recipient)
        recipient.email_events.create!(event_type: :delivered, occurred_at: Time.current, payload: @event)
        recipient.mark_delivered!
        campaign_for(recipient).refresh_counters!
      end

      def on_bounce(recipient)
        recipient.email_events.create!(event_type: :bounce, occurred_at: Time.current, payload: @event)
        recipient.mark_bounced!
        campaign = campaign_for(recipient)
        campaign.refresh_counters!
        suppress!(campaign.account, recipient.email, 'hard_bounce') if permanent_bounce?
      end

      def on_complaint(recipient)
        recipient.email_events.create!(event_type: :complaint, occurred_at: Time.current, payload: @event)
        recipient.mark_complained!
        campaign = campaign_for(recipient)
        campaign.refresh_counters!
        suppress!(campaign.account, recipient.email, 'complaint')
      end

      def permanent_bounce?
        @event.dig('bounce', 'bounceType') == 'Permanent'
      end

      # Account-scoped, idempotent (unique index on account_id + lower(email)).
      def suppress!(account, email, reason)
        EmailSuppression.create!(account: account, email: email, reason: reason, source: 'ses')
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        nil
      end
    end
  end
end
```

> Mapping keys: `mail.messageId` joins to `email_campaign_recipients.ses_message_id` (stored at
> send time). Hard bounce = `bounce.bounceType == 'Permanent'` → suppress (`hard_bounce`).
> Complaint always suppresses (`complaint`). Transient bounces are recorded but NOT suppressed.

### C4. `app/services/email_campaigns/ses/event_destination_ensurer.rb` (NEW)

Creates/uses an SNS topic (aws-sdk-sns), subscribes our public webhook URL, then points the SES
configuration set's event destination at the SNS topic (gem-free SES side). Invoked
OPERATIONALLY (rake/console at enable time), not per request.

```ruby
module EmailCampaigns
  module Ses
    class EventDestinationEnsurer
      DESTINATION_NAME = 'autonomia-sns-events'.freeze
      EVENT_TYPES = %w[DELIVERY BOUNCE COMPLAINT].freeze

      def perform
        EmailCampaigns::Ses::ConfigurationSetEnsurer.new.perform
        topic_arn = ensure_topic
        subscribe_webhook(topic_arn)
        put_event_destination(topic_arn)
        topic_arn
      end

      private

      def sns
        @sns ||= Aws::SNS::Client.new(
          region: EmailCampaigns::Config.region,
          access_key_id: EmailCampaigns::Config.access_key_id,
          secret_access_key: EmailCampaigns::Config.secret_access_key
        )
      end

      def ensure_topic
        sns.create_topic(name: EmailCampaigns::Config.sns_topic_name).topic_arn
      end

      def subscribe_webhook(topic_arn)
        sns.subscribe(topic_arn: topic_arn, protocol: webhook_protocol,
                      endpoint: EmailCampaigns::Config.sns_webhook_url, return_subscription_arn: true)
      end

      def webhook_protocol
        EmailCampaigns::Config.sns_webhook_url.start_with?('https') ? 'https' : 'http'
      end

      # gem-free SES: PUT a configuration-set event destination pointing DELIVERY/BOUNCE/
      # COMPLAINT to the SNS topic.
      def put_event_destination(topic_arn)
        EmailCampaigns::Ses::Client.new.put_configuration_set_event_destination(
          configuration_set: EmailCampaigns::Config.configuration_set_name,
          destination_name: DESTINATION_NAME,
          sns_topic_arn: topic_arn,
          event_types: EVENT_TYPES
        )
      end
    end
  end
end
```

### C5. EDIT `app/services/email_campaigns/ses/client.rb` — add SES event-destination method

ADDITIVE (does not change existing methods). SESv2 path:
`POST /v2/email/configuration-sets/<name>/event-destinations`.

```ruby
def put_configuration_set_event_destination(configuration_set:, destination_name:, sns_topic_arn:, event_types:)
  path = "#{API_VERSION_PATH}/configuration-sets/#{ERB::Util.url_encode(configuration_set)}/event-destinations"
  body = {
    EventDestinationName: destination_name,
    EventDestination: {
      Enabled: true,
      MatchingEventTypes: event_types,
      SnsDestination: { TopicArn: sns_topic_arn }
    }
  }
  post(path, body, idempotent: true)
end
```

> `idempotent: true` treats an AlreadyExists/409 as success (the existing `post` rescue). This
> is the ONLY edit Package C makes to an Onda 1 file; it composes with the existing signer +
> dispatch. SES uses SigV4 gem-free (unchanged); only the SNS side uses `aws-sdk-sns`.

### C6. Config additions — NEW constants/methods needed

`EventDestinationEnsurer` + the controller reference `EmailCampaigns::Config.sns_topic_name`,
`.sns_webhook_url`, plus the already-existing `.region/.access_key_id/.secret_access_key/
.configuration_set_name`. To avoid editing the Onda 1 `config.rb` from Package C, **Package C
adds these as `module_function`s in a NEW file** `app/services/email_campaigns/sns/config.rb`:

```ruby
module EmailCampaigns
  module Sns
    module Config
      module_function

      def topic_name
        ENV.fetch('EMAIL_CAMPAIGN_SNS_TOPIC', 'autonomia-email-campaign-events')
      end

      # Public SNS webhook endpoint AWS posts to. ENV override else FRONTEND_URL + path.
      def webhook_url
        ENV.fetch('EMAIL_CAMPAIGN_SNS_WEBHOOK_URL', nil).presence ||
          "#{ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com')}/email_campaigns/sns"
      end
    end
  end
end
```

Then in C4 use `EmailCampaigns::Sns::Config.topic_name` / `EmailCampaigns::Sns::Config.webhook_url`
(NOT `EmailCampaigns::Config.sns_*`). This keeps all SNS config additive in a new file.

### C7. `lib/tasks/email_campaigns.rake` (NEW — operational invoker)

```ruby
namespace :email_campaigns do
  desc 'Ensure SES configuration-set event destination -> SNS topic -> webhook subscription'
  task ensure_event_destination: :environment do
    abort 'EMAIL_CAMPAIGN_ENABLED is off' unless EmailCampaigns::Config.enabled?

    arn = EmailCampaigns::Ses::EventDestinationEnsurer.new.perform
    puts "Event destination ensured. SNS topic: #{arn}"
  end
end
```

> Run once at enable (operator confirms the SNS subscription via the webhook auto-confirm). Not
> invoked on any request path.

---

## Package D — Report backend (controller / service / policy / jbuilder / route via J)

> Inherits the Onda 1 base controller `Api::V1::Accounts::EmailCampaigns::BaseController`
> (already exists; 404 when feature disabled). Do NOT re-create it.

### D1. `app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb` (NEW)

```ruby
class Api::V1::Accounts::EmailCampaigns::ReportsController <
  Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :authorize_reports

  # GET .../email_campaigns/reports  — per-account campaign list + aggregate KPIs (+ optional
  # ?campaign_id= filter narrows the KPIs to one campaign).
  def index
    @summary = EmailCampaigns::Reports::Builder.new(account: Current.account, params: report_params).summary
    @campaigns = EmailCampaigns::Reports::Builder.new(account: Current.account, params: report_params).campaigns
  end

  # GET .../email_campaigns/reports/:id  — one campaign detail: KPIs + who opened / who clicked.
  def show
    @detail = EmailCampaigns::Reports::Builder.new(account: Current.account, params: report_params)
                                              .campaign_detail(params[:id])
    return render json: { error: 'email_campaign.not_found' }, status: :not_found if @detail.nil?
  end

  private

  def authorize_reports
    authorize EmailCampaign, :report?
  end

  def report_params
    params.permit(:campaign_id, :since, :until)
  end
end
```

> `authorize EmailCampaign, :report?` → uses `EmailCampaignReportPolicy`? NO — Pundit infers
> the policy from the record CLASS `EmailCampaign` → `EmailCampaignPolicy` (Onda 2). To keep a
> SEPARATE report policy without colliding with the Onda 2 `EmailCampaignPolicy`, authorize a
> symbol pair instead: **`authorize %i[email_campaign report], :view?`** (Pundit resolves
> `EmailCampaign::ReportPolicy`? no — it resolves `EmailCampaignReportPolicy` from the array's
> namespacing). **DECISION (locked): use `authorize %i[email_campaign report], :view?`** which
> Pundit maps to policy class `EmailCampaignReportPolicy` (array → `EmailCampaign` + `Report`
> joined). The policy file is §D3. Replace the two lines above accordingly:
> `def authorize_reports; authorize %i[email_campaign report], :view?; end`.

### D2. `app/services/email_campaigns/reports/builder.rb` (NEW)

```ruby
module EmailCampaigns
  module Reports
    class Builder
      OPEN_PER_PAGE = 100

      def initialize(account:, params: {})
        @account = account
        @params = params || {}
      end

      def campaigns
        scope.order(created_at: :desc).map { |c| kpis(c).merge(id: c.id, name: c.name, status: c.status,
                                                               subject: c.subject, created_at: c.created_at) }
      end

      # Aggregate KPIs over the (optionally campaign-filtered) scope.
      def summary
        totals = Hash.new(0)
        scope.find_each do |c|
          kpis(c).each { |k, v| totals[k] += v if v.is_a?(Numeric) }
        end
        totals.merge(rates(totals))
      end

      def campaign_detail(id)
        campaign = scope.find_by(id: id)
        return nil if campaign.nil?

        kpis(campaign).merge(
          id: campaign.id, name: campaign.name, subject: campaign.subject, status: campaign.status,
          rates: rates(kpis(campaign)),
          opened: people(campaign, :open),
          clicked: people(campaign, :click)
        )
      end

      private

      def scope
        s = EmailCampaign.where(account_id: @account.id)
        s = s.where(id: @params[:campaign_id]) if @params[:campaign_id].present?
        s
      end

      def kpis(c)
        {
          recipients: c.recipients_count, sent: c.sent_count, delivered: c.delivered_count,
          opened: c.opened_count, clicked: c.clicked_count, bounced: c.bounced_count,
          complained: c.complained_count, unsubscribed: c.unsubscribed_count, failed: c.failed_count,
          suppressed: c.suppressed_count
        }
      end

      # Rates over DELIVERED (PRD). Guard divide-by-zero.
      def rates(k)
        base = k[:delivered].to_i
        return { open_rate: 0.0, click_rate: 0.0, bounce_rate: 0.0, complaint_rate: 0.0, unsubscribe_rate: 0.0 } if base.zero?

        {
          open_rate: pct(k[:opened], base), click_rate: pct(k[:clicked], base),
          bounce_rate: pct(k[:bounced], base), complaint_rate: pct(k[:complained], base),
          unsubscribe_rate: pct(k[:unsubscribed], base)
        }
      end

      def pct(n, base)
        ((n.to_f / base) * 100).round(2)
      end

      # who opened / who clicked: recent recipients with an event of that type.
      def people(campaign, type)
        EmailCampaignRecipient.where(email_campaign_id: campaign.id)
                              .joins(:email_events)
                              .where(email_events: { event_type: EmailEvent.event_types[type.to_s] })
                              .distinct
                              .order(last_event_at: :desc)
                              .limit(OPEN_PER_PAGE)
                              .map { |r| { id: r.id, name: r.name, email: r.email, last_event_at: r.last_event_at } }
      end
    end
  end
end
```

### D3. Policy `app/policies/email_campaign_report_policy.rb` (NEW, top-level)

```ruby
class EmailCampaignReportPolicy < ApplicationPolicy
  def view?
    administrator? || agent?
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def agent?
    account_user&.agent?
  end
end
```

> Matches the report route's FE permissions (administrator + agent — read-only KPIs). Pundit
> resolves `EmailCampaignReportPolicy` from `authorize %i[email_campaign report], :view?`
> (array head/tail → `EmailCampaign` + `Report` → `EmailCampaignReportPolicy`). Confirm during
> eager_load gate. Account scoping is enforced by the Builder (`where(account_id:)`), not the
> policy scope (no Scope class needed — there is no index of records, only computed payloads).
> No EE overlay (OSS-only, read access). `record` here is the `EmailCampaign` class symbol.

### D4. jbuilder views (dir `app/views/api/v1/accounts/email_campaigns/reports/`)

`index.json.jbuilder`:
```ruby
json.payload do
  json.summary @summary
  json.campaigns @campaigns
end
```

`show.json.jbuilder`:
```ruby
json.payload do
  json.merge! @detail
end
```

> Plain hash emission (the Builder already shapes hashes). `json.merge!` splats the detail hash
> including nested `opened`/`clicked` arrays + `rates`.

### D5. Route (J edits `config/routes.rb`, INSIDE the existing `namespace :email_campaigns`
block ~line 213, as a sibling to `resources :campaigns`)

```ruby
resources :reports, only: [:index, :show]
```

Resulting paths: `GET /api/v1/accounts/:account_id/email_campaigns/reports` and
`GET .../email_campaigns/reports/:id`. Filter via `?campaign_id=`.

---

## Package E — Report FE (CRM "Gestão campanhas" page)

### E1. API module `app/javascript/dashboard/api/emailCampaignReports.js` (NEW)

```js
/* global axios */
import ApiClient from './ApiClient';

class EmailCampaignReportsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/reports', { accountScoped: true });
  }

  getReports(campaignId) {
    const query = campaignId ? `?campaign_id=${campaignId}` : '';
    return axios.get(`${this.url}${query}`);
  }

  getCampaignDetail(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new EmailCampaignReportsAPI();
```

### E2. Page `app/javascript/dashboard/routes/dashboard/crm/pages/CrmCampaignManagementPage.vue` (NEW)

`<script setup>` + Composition API. Mirror `CrmSlaPage.vue` / `CrmDashboardPage.vue` shell
(header, `globalConfig` gate, `ref()` data, direct API fetch in `onMounted`; NO Vuex store).

- Gate:
  ```js
  const globalConfig = useMapGetter('globalConfig/get');
  const enabled = computed(() => globalConfig.value?.emailCampaignEnabled === true &&
    globalConfig.value?.crmKanbanEnabled === true);
  ```
- `const summary = ref(null); const campaigns = ref([]); const selectedCampaignId = ref(null);
  const detail = ref(null);`
- `onMounted` → if `enabled` `fetchReports()`.
- `fetchReports()` → `EmailCampaignReportsAPI.getReports(selectedCampaignId.value)` →
  `summary.value = data.payload.summary; campaigns.value = data.payload.campaigns`.
- A campaign `<select>` (styled with `n-*` tokens) filters: on change set
  `selectedCampaignId` + re-fetch summary AND `EmailCampaignReportsAPI.getCampaignDetail(id)` →
  `detail.value`.
- KPI cards (use `CAMPAIGN_MANAGEMENT.KPIS.*`): Enviados (`sent`), Entregues (`delivered`),
  Abertos (`opened` — label with `(${t('CAMPAIGN_MANAGEMENT.APPROXIMATE')})`), Clicados
  (`clicked`), Descadastros (`unsubscribed`), Bounces (`bounced`), Spam (`complained`). Show the
  rate (over delivered) under each rate-bearing card from `summary.open_rate` etc.
- A note line: `CAMPAIGN_MANAGEMENT.OPEN_APPROXIMATE_HINT` (Apple MPP explanation).
- When a campaign is selected: two drill lists from `detail.opened` / `detail.clicked`
  (email · name · last_event_at) under `CAMPAIGN_MANAGEMENT.WHO_OPENED` /
  `CAMPAIGN_MANAGEMENT.WHO_CLICKED`.
- Empty state `CAMPAIGN_MANAGEMENT.EMPTY_STATE.*`; paywall/disabled state mirrors `CrmSlaPage`
  pattern (if `!enabled`, show a locked block + no API calls).
- Header uses `CAMPAIGN_MANAGEMENT.HEADER.TITLE` / `.DESCRIPTION` (in `crm.json`).
- All Tailwind `n-*`; reuse `text-n-slate-12 / text-n-slate-11 / border-n-weak / bg-n-solid-1`
  classes from `CrmSlaPage`. Icons `i-lucide-*` (e.g. `i-lucide-mail`, `i-lucide-mail-open`,
  `i-lucide-mouse-pointer-click`, `i-lucide-user-x`, `i-lucide-octagon-alert`).

### E3. FE route (J edits `crm.routes.js`)

Add import `import CrmCampaignManagementPage from './pages/CrmCampaignManagementPage.vue';` and
a route appended to the `routes` array AFTER `crm_sla_index`:

```js
{
  path: frontendURL('accounts/:accountId/crm/campaign-management'),
  name: 'crm_campaign_management_index',
  meta: reportsMeta,
  beforeEnter: ensureCrmEnabled,
  component: CrmCampaignManagementPage,
},
```

> `reportsMeta` = `['administrator', 'agent', CRM_VIEW_REPORTS_PERMISSION]` (already defined in
> the file) — matches the admin/agent report read policy. `ensureCrmEnabled` already redirects
> when CRM is off; the page additionally self-gates on `emailCampaignEnabled` (renders a locked
> block if email campaigns are disabled even when CRM is on).

### E4. Sidebar (J edits `Sidebar.vue`)

Inside the CRM block `children:[]` (~line 600, after the SLA conditional spread), add a child
gated on the already-existing `emailCampaignEnabled` computed (~line 86) AND
`canViewCrmReports`:

```js
...(emailCampaignEnabled.value && canViewCrmReports.value
  ? [
      {
        name: 'CRM Campaign Management',
        label: t('SIDEBAR.CRM_CAMPAIGN_MANAGEMENT'),
        to: accountScopedRoute('crm_campaign_management_index'),
        activeOn: ['crm_campaign_management_index'],
      },
    ]
  : []),
```

> `emailCampaignEnabled` computed already exists in `Sidebar.vue` (verified). If for any reason
> it is not in scope of the menu builder, J adds `const emailCampaignEnabled = computed(() =>
> globalConfig.value?.emailCampaignEnabled === true && crmKanbanEnabled.value);` near the other
> CRM computeds.

---

## Package F — Retry job + cron + sweeper (recipient helpers owned by A)

> The recipient model retry helpers (`register_attempt!`, `retryable?`, `MAX_ATTEMPTS`) are
> owned by Package A (model). The DeliveryEngine retry EDIT is owned by Package B. Package F
> owns ONLY the re-enqueue mechanism.

### F1. `app/services/email_campaigns/retry_sweeper.rb` (NEW)

Re-enqueues `DeliveryJob` for campaigns still in `sending` that have retryable pending
recipients (`attempts < MAX_ATTEMPTS`) whose last attempt is older than the backoff window.
Never touches `sent`/`delivered`/etc. recipients (only `pending`).

```ruby
module EmailCampaigns
  class RetrySweeper
    # Don't requeue a campaign whose recipients were just attempted; let SES settle.
    BACKOFF = (ENV.fetch('EMAIL_CAMPAIGN_RETRY_BACKOFF_MINUTES', 5).to_i).minutes

    def perform
      return unless Config.enabled?

      campaigns.find_each(batch_size: 50) { |campaign| requeue(campaign) }
    end

    private

    # sending campaigns that still have a retryable pending recipient past the backoff window.
    def campaigns
      EmailCampaign.where(status: EmailCampaign.statuses[:sending])
                   .where(id: retryable_campaign_ids)
                   .distinct
    end

    def retryable_campaign_ids
      EmailCampaignRecipient
        .where(status: EmailCampaignRecipient.statuses[:pending])
        .where('attempts < ?', EmailCampaignRecipient::MAX_ATTEMPTS)
        .where('attempts > 0')
        .where('updated_at <= ?', Time.current - BACKOFF)
        .select(:email_campaign_id)
    end

    def requeue(campaign)
      EmailCampaigns::DeliveryJob.perform_later(campaign.id)
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::RetrySweeper] campaign=#{campaign.id} #{e.message}")
    end
  end
end
```

> `attempts > 0` ensures we only requeue rows that actually had a transient failure (a never-
> attempted pending row is still being processed by the original run). `updated_at <= now -
> BACKOFF` provides exponential-ish spacing (each `register_attempt!` bumps `updated_at`).
> DeliveryEngine is idempotent + claim-guarded, so re-enqueue is safe (no double-send).

### F2. `app/jobs/email_campaigns/retry_sweep_job.rb` (NEW)

```ruby
class EmailCampaigns::RetrySweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailCampaigns::RetrySweeper.new.perform
  end
end
```

### F3. cron entry (J edits `config/schedule.yml`, append after the Onda 2
`email_campaign_schedule_due_campaigns_job` entry)

```yaml
# executed every 5 minutes; re-enqueues delivery for sending campaigns with retryable
# (transient-failed) pending recipients past the backoff. Flag checked inside the job.
email_campaign_retry_sweep_job:
  cron: '*/5 * * * *'
  class: 'EmailCampaigns::RetrySweepJob'
  queue: scheduled_jobs
```

---

## Package G — i18n (authored once, J merges into both locales, parity 1:1)

> TWO target files: the page body strings go in `crm.json` (new root `CAMPAIGN_MANAGEMENT`); the
> sidebar label goes in `settings.json` under `SIDEBAR`.

### G1. `crm.json` — new root block `CAMPAIGN_MANAGEMENT` (en)

```json
"CAMPAIGN_MANAGEMENT": {
  "HEADER": {
    "TITLE": "Campaign Management",
    "DESCRIPTION": "Track delivery, opens, clicks, unsubscribes, bounces and spam complaints for your email campaigns."
  },
  "PAYWALL": {
    "TITLE": "Email campaigns are not enabled",
    "DESCRIPTION": "Enable email campaigns to view delivery and engagement reports here."
  },
  "FILTER": {
    "LABEL": "Campaign",
    "ALL": "All campaigns"
  },
  "APPROXIMATE": "approximate",
  "OPEN_APPROXIMATE_HINT": "Open rates are approximate. Apple Mail Privacy Protection and similar features can inflate opens by pre-loading images.",
  "KPIS": {
    "SENT": "Sent",
    "DELIVERED": "Delivered",
    "OPENED": "Opened",
    "CLICKED": "Clicked",
    "UNSUBSCRIBED": "Unsubscribes",
    "BOUNCED": "Bounces",
    "COMPLAINED": "Spam complaints"
  },
  "RATES": {
    "OPEN_RATE": "Open rate",
    "CLICK_RATE": "Click rate",
    "BOUNCE_RATE": "Bounce rate",
    "COMPLAINT_RATE": "Complaint rate",
    "UNSUBSCRIBE_RATE": "Unsubscribe rate",
    "OVER_DELIVERED": "of delivered"
  },
  "WHO_OPENED": {
    "TITLE": "Who opened",
    "EMPTY": "No opens recorded yet."
  },
  "WHO_CLICKED": {
    "TITLE": "Who clicked",
    "EMPTY": "No clicks recorded yet."
  },
  "TABLE": {
    "EMAIL": "Email",
    "NAME": "Name",
    "LAST_EVENT_AT": "Last activity"
  },
  "EMPTY_STATE": {
    "TITLE": "No campaign data yet",
    "SUBTITLE": "Send an email campaign to start seeing delivery and engagement metrics."
  },
  "ERROR": "Could not load the campaign report. Please try again."
}
```

### G2. `crm.json` — `CAMPAIGN_MANAGEMENT` (pt_BR, same key tree)

```json
"CAMPAIGN_MANAGEMENT": {
  "HEADER": {
    "TITLE": "Gestão de campanhas",
    "DESCRIPTION": "Acompanhe entregas, aberturas, cliques, descadastros, bounces e reclamações de spam das suas campanhas de e-mail."
  },
  "PAYWALL": {
    "TITLE": "As campanhas de e-mail não estão habilitadas",
    "DESCRIPTION": "Habilite as campanhas de e-mail para ver os relatórios de entrega e engajamento aqui."
  },
  "FILTER": {
    "LABEL": "Campanha",
    "ALL": "Todas as campanhas"
  },
  "APPROXIMATE": "aproximada",
  "OPEN_APPROXIMATE_HINT": "As taxas de abertura são aproximadas. A Proteção de Privacidade do Apple Mail e recursos semelhantes podem inflar as aberturas ao pré-carregar imagens.",
  "KPIS": {
    "SENT": "Enviados",
    "DELIVERED": "Entregues",
    "OPENED": "Abertos",
    "CLICKED": "Clicados",
    "UNSUBSCRIBED": "Descadastros",
    "BOUNCED": "Bounces",
    "COMPLAINED": "Reclamações de spam"
  },
  "RATES": {
    "OPEN_RATE": "Taxa de abertura",
    "CLICK_RATE": "Taxa de cliques",
    "BOUNCE_RATE": "Taxa de bounce",
    "COMPLAINT_RATE": "Taxa de reclamações",
    "UNSUBSCRIBE_RATE": "Taxa de descadastro",
    "OVER_DELIVERED": "dos entregues"
  },
  "WHO_OPENED": {
    "TITLE": "Quem abriu",
    "EMPTY": "Nenhuma abertura registrada ainda."
  },
  "WHO_CLICKED": {
    "TITLE": "Quem clicou",
    "EMPTY": "Nenhum clique registrado ainda."
  },
  "TABLE": {
    "EMAIL": "E-mail",
    "NAME": "Nome",
    "LAST_EVENT_AT": "Última atividade"
  },
  "EMPTY_STATE": {
    "TITLE": "Nenhum dado de campanha ainda",
    "SUBTITLE": "Envie uma campanha de e-mail para começar a ver as métricas de entrega e engajamento."
  },
  "ERROR": "Não foi possível carregar o relatório da campanha. Tente novamente."
}
```

### G3. `settings.json` — `SIDEBAR.CRM_CAMPAIGN_MANAGEMENT`

- en (after `SIDEBAR.CRM_SLA`): `"CRM_CAMPAIGN_MANAGEMENT": "Campaign Management",`
- pt_BR (after `SIDEBAR.CRM_SLA`): `"CRM_CAMPAIGN_MANAGEMENT": "Gestão de campanhas",`

> No literal `{{ }}` or `@` in these strings → no vue-i18n escaping needed. If a future string
> contains a Liquid example, escape as `{'{{ ... }}'}`.

---

## Package J — Integration (edits to shared files)

1. `config/routes.rb`:
   - INSIDE the existing `namespace :email_campaigns` block (~line 213), add
     `resources :reports, only: [:index, :show]` (sibling to `resources :campaigns`).
   - In the top-level channel/webhook region (~after line 726, near `webhooks/*`), add the
     PUBLIC tracking + SNS routes:
     ```ruby
     # Email campaign own-tracking (public, signed-token; safe — see manifest Onda 3).
     get 'email_campaigns/t/o/:token', to: 'email_campaigns/tracking#open',
         constraints: { token: /[^\/]+/ }, format: false, defaults: { format: 'gif' }
     get 'email_campaigns/t/c/:token', to: 'email_campaigns/tracking#click',
         constraints: { token: /[^\/]+/ }
     # SES event ingestion via SNS (public; SNS-signature verified).
     post 'email_campaigns/sns', to: 'email_campaigns/sns#create'
     ```
     > The `.gif` suffix in `Token.open_url` is cosmetic for mail clients; the route matches the
     > token regardless (the `:token` segment + `format: 'gif'` default). Verify the route
     > matches a token ending in `.gif` during build (alternatively define
     > `get 'email_campaigns/t/o/:token.gif'`). DECISION: use
     > `get 'email_campaigns/t/o/:token', ... defaults: { format: 'gif' }` and have `open_url`
     > emit `.../t/o/<token>` WITHOUT the `.gif` suffix to avoid token/format ambiguity —
     > **update `Token.open_url` (Package B) to NOT append `.gif`**. (Single source: Package B
     > owns the URL shape; this note is the contract.)
2. `config/schedule.yml`: append `email_campaign_retry_sweep_job` (§F3) after the Onda 2
   `email_campaign_schedule_due_campaigns_job` entry.
3. `app/javascript/dashboard/routes/dashboard/crm/crm.routes.js`: import
   `CrmCampaignManagementPage` + append the `crm_campaign_management_index` route (§E3).
4. `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`: add the
   `crm_campaign_management_index` child entry in the CRM block (§E4); ensure
   `emailCampaignEnabled` computed is in scope.
5. Merge G's `CAMPAIGN_MANAGEMENT` block into BOTH `en/crm.json` and `pt_BR/crm.json`; add the
   `SIDEBAR.CRM_CAMPAIGN_MANAGEMENT` label to BOTH `en/settings.json` and `pt_BR/settings.json`;
   run i18n parity check on both files.

> No `dashboard_controller.rb` / `globalConfig.js` edit needed — `EMAIL_CAMPAIGN_ENABLED` /
> `emailCampaignEnabled` + `CRM_KANBAN_ENABLED` / `crmKanbanEnabled` already exist.

---

## ENV summary (Onda 3 additions; all optional with fallbacks)

| ENV | Used by | Fallback |
|-----|---------|----------|
| `EMAIL_CAMPAIGN_TRACKING_BASE_URL` | `Tracking::Token.base_url` | `FRONTEND_URL` |
| `EMAIL_CAMPAIGN_SNS_TOPIC` | `Sns::Config.topic_name` | `autonomia-email-campaign-events` |
| `EMAIL_CAMPAIGN_SNS_WEBHOOK_URL` | `Sns::Config.webhook_url` | `${FRONTEND_URL}/email_campaigns/sns` |
| `EMAIL_CAMPAIGN_RETRY_BACKOFF_MINUTES` | `RetrySweeper::BACKOFF` | `5` |

(Region/creds/configuration-set reuse the Onda 1 `EmailCampaigns::Config` ENV.)

---

## Gates (run after build)
- `ruby -c` on every new/edited `.rb`.
- `pnpm eslint` on touched JS/Vue.
- i18n parity: `en/crm.json` vs `pt_BR/crm.json` AND `en/settings.json` vs `pt_BR/settings.json`
  key trees identical.
- `vite build` clean.
- `eager_load` on a temp Swarm service (verify: `EmailEvent` resolves; `EmailCampaignReportPolicy`
  resolves for `authorize %i[email_campaign report], :view?`; the public controllers under
  `EmailCampaigns::` namespace autoload; routes draw without collision).
- Regression: a phone CSV still imports unchanged; an Onda 2 campaign still sends with the
  List-Unsubscribe header (now ALSO with rewritten links + open pixel — verify the injected HTML
  still renders and the unsubscribe header is intact).
- Real smoke (human, later):
  - send a one-recipient campaign → confirm the HTML arrives with rewritten `href`s pointing at
    `${TRACKING_BASE}/email_campaigns/t/c/...` + a 1x1 pixel; opening it hits the pixel endpoint
    → `EmailEvent(open)` + `opened_count` bumps; clicking a link 302-redirects to the original
    URL → `EmailEvent(click)` + `clicked_count` bumps;
  - run `rake email_campaigns:ensure_event_destination` → SNS topic created + webhook subscribed
    (auto-confirmed) + SES configuration-set event destination set; send a real SES message →
    Delivery SNS notification arrives at `/email_campaigns/sns`, signature verifies, recipient →
    `delivered`, `delivered_count` bumps; simulate a SES bounce (mailbox simulator
    `bounce@simulator.amazonses.com`) → recipient `bounced` + `EmailSuppression` row created;
    complaint simulator → `complained` + suppression;
  - force a transient SES error (e.g. throttle) → recipient returns to `pending` with
    `attempts=1`; RetrySweepJob re-enqueues after backoff; after 3 attempts → `failed`.
- Security review: tracking pixel always 200 (no info leak); click endpoint never open-redirects
  (tampered token → safe base); SNS endpoint rejects unsigned/forged messages (403);
  `EmailSuppression` writes are account-scoped + idempotent; report endpoint is account-scoped +
  admin/agent only.

## Out of scope (Onda 4 — do NOT build in Onda 3)
- Public one-click unsubscribe LANDING page / preference center (Onda 3 only adds the
  bounce/complaint auto-suppression that SNS drives; the Onda 2 List-Unsubscribe header still
  points at the Onda 2 PLACEHOLDER URL — Onda 4 ships the real endpoint that resolves it).
- Per-tenant guardrail monitor (bounce/complaint rate alerting) + daily send caps.
- Custom per-client tracking subdomain (Onda 3 uses one tracking base URL).
- Reply-To → inbox association wiring.
```