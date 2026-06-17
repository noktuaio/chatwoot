# Email Campaign — ONDA 1 Build Manifest (AUTHORITATIVE)

> Fork Chatwoot v4.14.1 EE (Hub2you / Autonomia) at
> `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`. Rails 7.1 + Vue 3.
> This manifest is the single source of truth for parallel impl agents. All paths
> ABSOLUTE-relative to the repo root above. **Build ONLY Onda 1** (sender
> foundation). Do NOT build recipient import, campaign model, sending campaigns,
> tracking, reports, unsubscribe (later waves).
>
> Scope source: `docs/email_campaign_v1_prd.md` §9 (Onda 1) + `docs/email_campaign_discovery.md`.

---

## 0. Hard rules (apply to every package)

- **Additive + zero regression.** Do NOT touch: native `Campaign` model, `Channel::Email`,
  `WhatsappApiCampaign*`, `campaign_imports/*`. Everything new lives under an
  `EmailCampaigns::*` namespace + a single new model `EmailSenderIdentity`.
- **Inert unless enabled.** Every entrypoint (controller, job, FE route) checks
  `EmailCampaigns::Config.enabled?` (Ruby) or `globalConfig.emailCampaignEnabled` (FE).
- **Ruby:** RuboCop style, ≤150 cols, compact `module/class`, no nested module style.
  Run `ruby -c` on every `.rb` touched.
- **Vue 3 `<script setup>` + Composition API**, Tailwind `n-*` tokens ONLY (no scoped /
  custom / inline CSS), `components-next`, `i-lucide-*`, NO bare strings (i18n everywhere).
- **i18n parity:** every key added to `en/campaign.json` MUST be added to
  `pt_BR/campaign.json` with identical key tree.
- **No new gem. No Dockerfile change.** SES access is gem-free signed HTTPS (see §B).
- Backend i18n (errors) is not required in Onda 1 (no `en.yml` strings); FE i18n only.

### Verified environment facts (do not re-investigate)
- Bundle HAS: `aws-sigv4 (1.12.1)`, `aws-sdk-core (3.240.0)`, `aws-sdk-sns (1.70.0)`,
  `faraday_middleware-aws-sigv4 (1.0.1)`. Bundle does NOT have `aws-sdk-ses` / `aws-sdk-sesv2`.
- `Aws::Sigv4::Signer#sign_request(request)` takes a hash
  `{ http_method:, url:, headers:, body: }` and returns an object whose `.headers`
  is a `Hash<String,String>` to merge onto the outgoing request. Constructor:
  `Aws::Sigv4::Signer.new(service:, region:, access_key_id:, secret_access_key:, session_token: nil)`.
- Gate pattern (mirror): `Crm::Config.enabled? == BOOLEAN.cast(ENV.fetch('CRM_KANBAN_ENABLED', false))`;
  `Crm::Ai::Config.enabled? == Crm::Config.enabled? && BOOLEAN.cast(ENV.fetch('CRM_AI_ENABLED', false))`.
- Job queue used by sibling cron-driven CRM jobs: `queue_as :scheduled_jobs`.
- jbuilder convention: response wrapped in `json.payload do ... end`; collection via
  `json.array! @collection, partial: '<name>', as: :<name>`; partial named `_<name>.json.jbuilder`.
- CRM routes live in `config/routes.rb` inside `namespace :crm do` (line ~142) under
  `api/v1/accounts`. New namespace `:email_campaigns` goes as a SIBLING block right
  after the `:crm` block closes (line ~212).
- globalConfig flag flow: `dashboard_controller.rb#global_config` (~line 80) emits
  `SCREAMING_CASE` string → `app/javascript/shared/store/globalConfig.js` maps to
  camelCase + `parseBoolean`. WhatsApp API page reads `globalConfig.value?.whatsappApiCampaignsEnabled === true`.
- FE campaigns routes: `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js`.
  Sibling page pattern + `beforeEnter` globalConfig gate: `WhatsAppApiCampaignsPage.vue`.
- Vuex store registration: `app/javascript/dashboard/store/index.js` (import ~line 16,
  modules list ~line 83); mutation types in `app/javascript/dashboard/store/mutation-types.js`.
- i18n campaign file is `campaign.json` (singular), root key `CAMPAIGN`. New block
  `CAMPAIGN.EMAIL_SENDER` inserted after the `WHATSAPP_API` block (~line 204), before
  the trailing `CONFIRM_DELETE` block.
- Migration filename convention: `db/migrate/<UTC timestamp>_<snake>.rb`,
  `ActiveRecord::Migration[7.1]`, latest existing is `20260611100200_*`.

---

## SES design decision (locked)

- **API:** SESv2 HTTPS REST. Base host `https://email.<region>.amazonaws.com`.
  Endpoints used in Onda 1:
  - `POST /v2/email/identities` — CreateEmailIdentity (body `{ "EmailIdentity": "<domain>" }`)
  - `GET  /v2/email/identities/<identity>` — GetEmailIdentity
  - `POST /v2/email/configuration-sets` — CreateConfigurationSet (body `{ "ConfigurationSetName": "<name>" }`)
  - `POST /v2/email/outbound-emails` — SendEmail (Simple content)
- **Signing:** `Aws::Sigv4::Signer` with `service: 'ses'`, region from config. Sign
  `{ http_method:, url:, headers: { 'host' => host, 'content-type' => 'application/json' }, body: json }`,
  merge returned `.headers`, dispatch with `Net::HTTP`.
- **Credentials/region from ENV** (see §A Config). Region default `sa-east-1`. Never read `~/.aws`.
- Easy DKIM: CreateEmailIdentity returns `DkimAttributes.Tokens` (3 tokens). Each →
  CNAME `<token>._domainkey.<domain>` → `<token>.dkim.amazonses.com`.
- SES account is in SANDBOX (200/day), suppression on at account level. Design must work in sandbox.

---

## File ownership table (DISJOINT — no file in two packages)

| Pkg | Owns (create unless noted) |
|-----|----------------------------|
| **A** db+model+config | `db/migrate/20260612090000_create_email_sender_identities.rb`; `app/models/email_sender_identity.rb`; `app/services/email_campaigns/config.rb` |
| **B** SES access layer | `app/services/email_campaigns/ses/client.rb`; `app/services/email_campaigns/ses/identity_provisioner.rb`; `app/services/email_campaigns/ses/configuration_set_ensurer.rb`; `app/services/email_campaigns/ses/sender.rb` |
| **C** job+cron | `app/jobs/email_campaigns/domain_verification_poll_job.rb`; `app/jobs/email_campaigns/poll_pending_identities_job.rb` |
| **D** API | `app/controllers/api/v1/accounts/email_campaigns/base_controller.rb`; `app/controllers/api/v1/accounts/email_campaigns/sender_identities_controller.rb`; `app/policies/email_campaigns/sender_identity_policy.rb`; `app/views/api/v1/accounts/email_campaigns/sender_identities/_sender_identity.json.jbuilder`; `.../index.json.jbuilder`; `.../show.json.jbuilder` |
| **E** FE | `app/javascript/dashboard/api/emailSenderIdentities.js`; `app/javascript/dashboard/store/modules/emailSenderIdentities.js`; `app/javascript/dashboard/routes/dashboard/campaigns/pages/EmailSenderPage.vue`; `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailSender/EmailSenderDomainDialog.vue` |
| **F** i18n | new `CAMPAIGN.EMAIL_SENDER` block authored as a standalone fragment; reconciled into both `campaign.json` by J |
| **J** integration | EDIT `config/routes.rb`; EDIT `config/schedule.yml`; EDIT `app/controllers/dashboard_controller.rb`; EDIT `app/javascript/shared/store/globalConfig.js`; EDIT `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js`; EDIT `app/javascript/dashboard/store/index.js`; EDIT `app/javascript/dashboard/store/mutation-types.js`; merge F's block into `en/campaign.json` + `pt_BR/campaign.json` |

> EE policy mirror: the CRM policy pattern uses an EE overlay
> (`enterprise/app/policies/enterprise/crm/...` + `prepend_mod_with`). For Onda 1 the
> sender-identity policy is admin-only and does NOT need granular custom-role keys, so
> **no EE mirror is required** — implement a single OSS policy (§D). (Rationale recorded
> for the security reviewer: admin-or-crm_admin reduces to `administrator?` here.)

---

## Package A — DB + Model + Config

### A1. Migration `db/migrate/20260612090000_create_email_sender_identities.rb`

```ruby
class CreateEmailSenderIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :email_sender_identities do |t|
      t.references :account, null: false, foreign_key: true
      t.string :domain, null: false
      t.string :from_email
      t.bigint :reply_to_inbox_id
      # status: pending(0) verifying(1) verified(2) failed(3)
      t.integer :status, null: false, default: 0
      t.jsonb :dkim_records, null: false, default: []
      t.string :spf_record
      t.string :dmarc_record
      t.string :ses_configuration_set
      t.string :provider, null: false, default: 'ses'
      t.datetime :verified_at
      t.string :last_error

      t.timestamps
    end

    add_index :email_sender_identities,
              'account_id, lower(domain)',
              unique: true,
              name: 'idx_email_sender_identities_account_domain'
    add_index :email_sender_identities, [:account_id, :status],
              name: 'idx_email_sender_identities_account_status'
  end
end
```

Notes: `account_id` index is created by `t.references`. The unique index uses a raw SQL
expression string (`lower(domain)`) — this is the established fork pattern for
case-insensitive uniqueness. `reply_to_inbox_id` is a plain `bigint` (nullable, no FK in
Onda 1 — wired in a later wave).

### A2. Model `app/models/email_sender_identity.rb`

```ruby
class EmailSenderIdentity < ApplicationRecord
  belongs_to :account

  enum status: { pending: 0, verifying: 1, verified: 2, failed: 3 }

  DOMAIN_REGEX = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/i

  before_validation :normalize_domain

  validates :domain, presence: true, format: { with: DOMAIN_REGEX }
  validates :domain, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :provider, presence: true

  scope :verified_identities, -> { where(status: :verified) }
  scope :pending_verification, -> { where(status: %i[pending verifying]) }

  def usable?
    verified?
  end

  private

  def normalize_domain
    self.domain = domain.to_s.strip.downcase.presence
  end
end
```

Notes: no `prepend_mod_with` needed (not extended by EE). `dkim_records` is an array of
hashes `[{ "name" => "...", "type" => "CNAME", "value" => "..." }]`. `belongs_to :account`
gives `account.email_sender_identities` only if Account declares the association — Onda 1
does NOT edit `app/models/account.rb`; controllers scope via
`EmailSenderIdentity.where(account: Current.account)` (see §D). Do not add the inverse on Account.

### A3. Config `app/services/email_campaigns/config.rb`

```ruby
module EmailCampaigns
  class Config
    BOOLEAN = ActiveModel::Type::Boolean.new

    DEFAULT_REGION = 'sa-east-1'.freeze
    CONFIGURATION_SET_NAME = 'autonomia-email-campaigns'.freeze

    def self.enabled?
      ::Crm::Config.enabled? && BOOLEAN.cast(ENV.fetch('EMAIL_CAMPAIGN_ENABLED', false))
    end

    def self.region
      ENV.fetch('EMAIL_CAMPAIGN_AWS_REGION', nil).presence ||
        ENV.fetch('AWS_REGION', nil).presence ||
        DEFAULT_REGION
    end

    def self.access_key_id
      ENV.fetch('EMAIL_CAMPAIGN_AWS_ACCESS_KEY_ID', nil).presence ||
        ENV.fetch('AWS_ACCESS_KEY_ID', '')
    end

    def self.secret_access_key
      ENV.fetch('EMAIL_CAMPAIGN_AWS_SECRET_ACCESS_KEY', nil).presence ||
        ENV.fetch('AWS_SECRET_ACCESS_KEY', '')
    end

    def self.configuration_set_name
      ENV.fetch('EMAIL_CAMPAIGN_SES_CONFIGURATION_SET', CONFIGURATION_SET_NAME)
    end
  end
end
```

Gate decision (locked): `enabled?` = `Crm::Config.enabled?` AND `EMAIL_CAMPAIGN_ENABLED`
(mirrors `Crm::Ai::Config`, the fork norm). ENV credential names: prefer
`EMAIL_CAMPAIGN_AWS_*`, fall back to generic `AWS_*`.

---

## Package B — SES access layer (gem-free, signed HTTPS)

All classes under `module EmailCampaigns; module Ses; ... end; end`. Read region/creds
from `EmailCampaigns::Config`. Errors raise `EmailCampaigns::Ses::Error` (define in
`client.rb` as `class Error < StandardError; end`). Callers (provisioner/job) rescue it and
write the message to `identity.last_error`.

### B1. `app/services/email_campaigns/ses/client.rb`

Low-level signed HTTPS client. Public API:

```ruby
module EmailCampaigns
  module Ses
    class Client
      class Error < StandardError; end

      def create_email_identity(domain)        # POST /v2/email/identities
      def get_email_identity(identity)         # GET  /v2/email/identities/<identity>
      def create_configuration_set(name)       # POST /v2/email/configuration-sets
      def send_email(from:, to:, subject:, html_body:, text_body: nil, configuration_set: nil, reply_to: nil)
      # all return parsed JSON Hash (symbolize_names: false). Raise Error on non-2xx
      # (except create_* which treat 409/AlreadyExists as success → return {}).
    end
  end
end
```

Implementation contract:
- `host = "email.#{EmailCampaigns::Config.region}.amazonaws.com"`, `base = "https://#{host}"`.
- Build `signer = Aws::Sigv4::Signer.new(service: 'ses', region: ..., access_key_id: ..., secret_access_key: ...)`.
- For each call: `body = payload.to_json` (or `''` for GET); `url = base + path`;
  `headers = { 'host' => host, 'content-type' => 'application/json' }`;
  `signature = signer.sign_request(http_method:, url:, headers:, body:)`;
  `headers.merge!(signature.headers)`; dispatch with `Net::HTTP.start(host, 443, use_ssl: true)`.
- Parse `response.body` as JSON. On `2xx` return parsed hash (or `{}` if empty body).
  On non-2xx raise `Error` with `"#{code} #{parsed['message'] || body}"`.
  `create_email_identity` / `create_configuration_set`: rescue an `AlreadyExists`/`409`
  and return `{}` (idempotent).
- `send_email` body shape (SESv2 Simple):
  `{ FromEmailAddress:, Destination: { ToAddresses: [to] }, ReplyToAddresses: [reply_to].compact,
     ConfigurationSetName:, Content: { Simple: { Subject: { Data: subject },
     Body: { Html: { Data: html_body }, Text: { Data: text_body } }.compact } } }` (drop nil keys).

### B2. `app/services/email_campaigns/ses/identity_provisioner.rb`

```ruby
module EmailCampaigns
  module Ses
    class IdentityProvisioner
      # identity: EmailSenderIdentity record (already persisted, status pending)
      def initialize(identity)
      def perform   # idempotent: calls SES, persists DNS records, sets status :verifying
    end
  end
end
```

Contract:
- Call `Client#create_email_identity(identity.domain)`. Response provides
  `dig('DkimAttributes', 'Tokens')` (Array<String>). If create returned `{}` (already
  exists), call `get_email_identity` to fetch tokens.
- Build `dkim_records` = for each token:
  `{ 'type' => 'CNAME', 'name' => "#{token}._domainkey.#{domain}", 'value' => "#{token}.dkim.amazonses.com" }`.
- Build recommended records:
  - `spf_record` = `"v=spf1 include:amazonses.com ~all"` (TXT on root domain — store the value).
  - `dmarc_record` = `"v=DMARC1; p=none;"` (TXT on `_dmarc.#{domain}` — store the value).
- `identity.update!(dkim_records:, spf_record:, dmarc_record:, status: :verifying,
   ses_configuration_set: EmailCampaigns::Config.configuration_set_name, last_error: nil)`.
- On `Ses::Error`: `identity.update!(status: :failed, last_error: e.message)` then re-raise
  (controller maps to 422). Also ensure configuration set exists via
  `ConfigurationSetEnsurer.new.perform` before/after create (best-effort; swallow its error
  into a log, do not fail provisioning).

### B3. `app/services/email_campaigns/ses/configuration_set_ensurer.rb`

```ruby
module EmailCampaigns
  module Ses
    class ConfigurationSetEnsurer
      def perform(name = EmailCampaigns::Config.configuration_set_name)
        # Client#create_configuration_set(name); idempotent (AlreadyExists → ok). Returns name.
      end
    end
  end
end
```

### B4. `app/services/email_campaigns/ses/sender.rb`

```ruby
module EmailCampaigns
  module Ses
    class Sender
      # identity: a verified EmailSenderIdentity. Powers the human smoke test + later waves.
      def initialize(identity)
      def deliver(to:, subject:, html_body:, text_body: nil, from_email: nil, reply_to: nil)
        # raise Ses::Error unless identity.usable?
        # from = from_email || identity.from_email || "no-reply@#{identity.domain}"
        # Client#send_email(... configuration_set: identity.ses_configuration_set ...)
        # returns the SES MessageId (String) from response['MessageId']
    end
  end
end
```

---

## Package C — Job + cron

### C1. `app/jobs/email_campaigns/domain_verification_poll_job.rb`

```ruby
class EmailCampaigns::DomainVerificationPollJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(identity_id)
    return unless EmailCampaigns::Config.enabled?

    identity = EmailSenderIdentity.find_by(id: identity_id)
    return if identity.nil? || identity.verified?

    response = EmailCampaigns::Ses::Client.new.get_email_identity(identity.domain)
    verified = response['VerifiedForSendingStatus'] == true ||
               response.dig('DkimAttributes', 'Status') == 'SUCCESS'
    if verified
      identity.update!(status: :verified, verified_at: Time.current, last_error: nil)
    else
      identity.update!(status: :verifying, last_error: nil)
    end
  rescue EmailCampaigns::Ses::Error => e
    identity&.update(status: :failed, last_error: e.message)
  end
end
```

### C2. `app/jobs/email_campaigns/poll_pending_identities_job.rb` (cron fan-out)

```ruby
class EmailCampaigns::PollPendingIdentitiesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailSenderIdentity.pending_verification.find_each do |identity|
      EmailCampaigns::DomainVerificationPollJob.perform_later(identity.id)
    end
  end
end
```

### C3. cron entry (J edits `config/schedule.yml`, append after the CRM block ~line 105)

```yaml
# executed every 5 minutes; re-polls SES for pending domain verifications.
# feature flag checked inside the job.
email_campaign_poll_pending_identities_job:
  cron: '*/5 * * * *'
  class: 'EmailCampaigns::PollPendingIdentitiesJob'
  queue: scheduled_jobs
```

---

## Package D — API (controller / routes / policy / jbuilder)

### D1. Base controller `app/controllers/api/v1/accounts/email_campaigns/base_controller.rb`

```ruby
class Api::V1::Accounts::EmailCampaigns::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_email_campaign_enabled

  private

  def ensure_email_campaign_enabled
    return if ::EmailCampaigns::Config.enabled?

    render json: { error: 'email_campaign.disabled' }, status: :not_found
  end
end
```

### D2. Controller `app/controllers/api/v1/accounts/email_campaigns/sender_identities_controller.rb`

```ruby
class Api::V1::Accounts::EmailCampaigns::SenderIdentitiesController <
  Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_identity, only: [:show, :verify]

  def index
    authorize EmailSenderIdentity
    @sender_identities = identity_scope.order(created_at: :desc)
  end

  def show; end

  def create
    @sender_identity = identity_scope.new(sender_identity_params)
    authorize @sender_identity
    @sender_identity.save!
    EmailCampaigns::Ses::IdentityProvisioner.new(@sender_identity).perform
    render :show, status: :created
  rescue EmailCampaigns::Ses::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def verify
    EmailCampaigns::DomainVerificationPollJob.perform_later(@sender_identity.id)
    render :show
  end

  private

  def identity_scope
    EmailSenderIdentity.where(account: Current.account)
  end

  def fetch_identity
    @sender_identity = identity_scope.find(params[:id])
    authorize @sender_identity
  end

  def sender_identity_params
    params.require(:sender_identity).permit(:domain, :from_email, :reply_to_inbox_id)
  end
end
```

Notes: `index`/`show`/`create` render the jbuilder views. `verify` is a member action that
re-enqueues the poll job (synchronous re-check is not needed — keep API fast). All lookups
scoped to `Current.account`. The instance var names (`@sender_identities`,
`@sender_identity`) MUST match the jbuilder views.

### D3. Routes (J edits `config/routes.rb`, NEW sibling namespace right after the
`namespace :crm do ... end` closes, ~line 212)

```ruby
namespace :email_campaigns do
  resources :sender_identities, only: [:index, :create, :show] do
    member do
      post :verify
    end
  end
end
```

Resulting paths under `/api/v1/accounts/:account_id/email_campaigns/sender_identities`.
Route helper prefix: `api_v1_account_email_campaigns_sender_identities`.

### D4. Policy `app/policies/email_campaigns/sender_identity_policy.rb`

```ruby
class EmailCampaigns::SenderIdentityPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def create?
    administrator?
  end

  def verify?
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

Decision: admin-only (matches `meta.permissions: ['administrator']` on the FE campaigns
routes). No EE overlay / `prepend_mod_with` in Onda 1 (the granular `crm_*` custom-role
keys do not apply to sender setup). `ApplicationPolicy` exposes `account`, `account_user`,
`user`, `record` — confirmed by `Crm::PipelinePolicy`.

### D5. jbuilder views (dir `app/views/api/v1/accounts/email_campaigns/sender_identities/`)

`_sender_identity.json.jbuilder`:
```ruby
json.id sender_identity.id
json.account_id sender_identity.account_id
json.domain sender_identity.domain
json.from_email sender_identity.from_email
json.reply_to_inbox_id sender_identity.reply_to_inbox_id
json.status sender_identity.status
json.dkim_records sender_identity.dkim_records
json.spf_record sender_identity.spf_record
json.dmarc_record sender_identity.dmarc_record
json.ses_configuration_set sender_identity.ses_configuration_set
json.provider sender_identity.provider
json.verified_at sender_identity.verified_at
json.last_error sender_identity.last_error
json.created_at sender_identity.created_at
json.updated_at sender_identity.updated_at
```

`index.json.jbuilder`:
```ruby
json.payload do
  json.sender_identities do
    json.array! @sender_identities, partial: 'sender_identity', as: :sender_identity
  end
end
```

`show.json.jbuilder`:
```ruby
json.payload do
  json.partial! 'sender_identity', sender_identity: @sender_identity
end
```

---

## Package E — Frontend (Campanhas area)

### E1. API module `app/javascript/dashboard/api/emailSenderIdentities.js`

```js
/* global axios */
import ApiClient from './ApiClient';

class EmailSenderIdentitiesAPI extends ApiClient {
  constructor() {
    super('email_campaigns/sender_identities', { accountScoped: true });
  }

  verify(id) {
    return axios.post(`${this.url}/${id}/verify`);
  }
}

export default new EmailSenderIdentitiesAPI();
```

Notes: `ApiClient` `create(payload)`/`get()`/`show(id)` already exist. The controller
expects the create body wrapped under `sender_identity` — pass
`{ sender_identity: { domain, from_email, reply_to_inbox_id } }` from the store/dialog.

### E2. Store module `app/javascript/dashboard/store/modules/emailSenderIdentities.js`

Mirror `whatsappApiCampaigns.js` shape. State `{ records, uiFlags: { isFetching,
isCreating, isUpdating } }`. Getters `getIdentities`, `getUIFlags`. Actions:
- `get({ commit })` → `EmailSenderIdentitiesAPI.get()`, commit `SET_EMAIL_SENDER_IDENTITIES`
  with `response.data.payload.sender_identities`.
- `create({ commit }, payload)` → `EmailSenderIdentitiesAPI.create({ sender_identity: payload })`,
  commit `ADD_EMAIL_SENDER_IDENTITY` with `response.data.payload`.
- `verify({ commit }, id)` → `EmailSenderIdentitiesAPI.verify(id)`, commit
  `EDIT_EMAIL_SENDER_IDENTITY` with `response.data.payload`.

Uses `MutationHelpers.set/create/update` like the WhatsApp module.

### E3. Mutation types (J edits `app/javascript/dashboard/store/mutation-types.js`)
```
SET_EMAIL_SENDER_IDENTITY_UI_FLAG: 'SET_EMAIL_SENDER_IDENTITY_UI_FLAG',
SET_EMAIL_SENDER_IDENTITIES: 'SET_EMAIL_SENDER_IDENTITIES',
ADD_EMAIL_SENDER_IDENTITY: 'ADD_EMAIL_SENDER_IDENTITY',
EDIT_EMAIL_SENDER_IDENTITY: 'EDIT_EMAIL_SENDER_IDENTITY',
```

### E4. Store registration (J edits `app/javascript/dashboard/store/index.js`)
Add `import emailSenderIdentities from './modules/emailSenderIdentities';` and add
`emailSenderIdentities,` to the modules object.

### E5. Page `.../campaigns/pages/EmailSenderPage.vue`

`<script setup>`, Composition API. Mirror `WhatsAppApiCampaignsPage.vue`:
- `const globalConfig = useMapGetter('globalConfig/get');`
- `const enabled = computed(() => globalConfig.value?.emailCampaignEnabled === true);`
- `const identities = useMapGetter('emailSenderIdentities/getIdentities');`
- `const uiFlags = useMapGetter('emailSenderIdentities/getUIFlags');`
- `onMounted` → if `enabled` dispatch `emailSenderIdentities/get`.
- Wrap in `<CampaignLayout :header-title="t('CAMPAIGN.EMAIL_SENDER.HEADER_TITLE')"
  :button-label="t('CAMPAIGN.EMAIL_SENDER.NEW_DOMAIN')" @click="toggleDialog()">`.
- `#action` slot renders `<EmailSenderDomainDialog v-if="showDialog" @created="..." @close="...">`.
- List table columns: Domain · Status badge · Actions (a "Verificar"/"Verify" `Button`
  `icon="i-lucide-refresh-cw"` calling `store.dispatch('emailSenderIdentities/verify', id)`).
- Status badge helper mapping (use `CAMPAIGN.EMAIL_SENDER.STATUS.*`):
  `pending`→amber, `verifying`→blue, `verified`→teal, `failed`→ruby (reuse the WhatsApp
  `text-n-*-11 bg-n-*-3` token classes).
- Empty state uses `CAMPAIGN.EMAIL_SENDER.EMPTY_STATE.*`.
- DNS records render: per identity, a panel listing `dkim_records` (name/type/value) + SPF +
  DMARC, each row with a copy `Button` `icon="i-lucide-copy"` using `useClipboard` from
  `@vueuse/core` (or existing `copyTextToClipboard` helper) + `useAlert(t('CAMPAIGN.EMAIL_SENDER.DNS.COPIED'))`.

### E6. Dialog `.../components-next/Campaigns/Pages/CampaignPage/EmailSender/EmailSenderDomainDialog.vue`

`<script setup>` + `components-next` `Dialog`/`Input`/`Button` (mirror
`WhatsAppApiCampaignDialog.vue`). Single required field `domain` (text). Optional
`from_email`. On submit → `emailSenderIdentities/create` with `{ domain, fromEmail }`
(store maps to snake_case), emit `created`, `useAlert(t('CAMPAIGN.EMAIL_SENDER.DIALOG.SUCCESS'))`.
Validate domain non-empty (i18n error `CAMPAIGN.EMAIL_SENDER.DIALOG.DOMAIN_ERROR`).

### E7. FE route (J edits `campaigns.routes.js`)

Add import `import EmailSenderPage from './pages/EmailSenderPage.vue';` and a child route
AFTER `whatsapp_api`:
```js
{
  path: 'email_sender',
  name: 'campaigns_email_sender_index',
  meta,
  beforeEnter: (to, _from, next) => {
    if (window.globalConfig?.EMAIL_CAMPAIGN_ENABLED === 'true') {
      next();
      return;
    }
    next({ name: 'campaigns_sms_index', params: to.params });
  },
  component: EmailSenderPage,
},
```
(`meta` already carries `featureFlag: FEATURE_FLAGS.CAMPAIGNS` + `permissions: ['administrator']`.)

---

## Package F — i18n (block authored once, J merges into both files)

Insert under root `CAMPAIGN` in `en/campaign.json` AND `pt_BR/campaign.json` (parity 1:1),
after the `WHATSAPP_API` block. Key namespace `CAMPAIGN.EMAIL_SENDER`.

### English (`en/campaign.json`)
```json
"EMAIL_SENDER": {
  "HEADER_TITLE": "Email sending domains",
  "NEW_DOMAIN": "Add sending domain",
  "DESCRIPTION": "Verify your sending domain once so email campaigns are delivered with your own brand and pass SPF, DKIM and DMARC checks.",
  "EMPTY_STATE": {
    "TITLE": "No sending domains yet",
    "SUBTITLE": "Add your domain to generate the DNS records you need to paste at your registrar."
  },
  "TABLE": {
    "DOMAIN": "Domain",
    "STATUS": "Status",
    "ACTIONS": "Actions"
  },
  "STATUS": {
    "PENDING": "Pending",
    "VERIFYING": "Verifying",
    "VERIFIED": "Verified",
    "FAILED": "Failed"
  },
  "ACTIONS": {
    "VERIFY": "Verify",
    "VERIFY_SUCCESS": "Re-checking verification with the provider.",
    "ERROR": "Something went wrong. Please try again."
  },
  "DNS": {
    "TITLE": "DNS records",
    "SUBTITLE": "Add these records at your domain registrar. Verification can take a few minutes after they propagate.",
    "TYPE": "Type",
    "NAME": "Name",
    "VALUE": "Value",
    "DKIM": "DKIM (CNAME)",
    "SPF": "SPF (TXT)",
    "DMARC": "DMARC (TXT)",
    "COPY": "Copy",
    "COPIED": "Copied to clipboard"
  },
  "DIALOG": {
    "TITLE": "Add sending domain",
    "DOMAIN_LABEL": "Domain",
    "DOMAIN_PLACEHOLDER": "e.g. mail.yourcompany.com",
    "DOMAIN_ERROR": "Enter a valid domain",
    "FROM_EMAIL_LABEL": "Default from address (optional)",
    "FROM_EMAIL_PLACEHOLDER": "e.g. marketing@yourcompany.com",
    "SUBMIT": "Add domain",
    "CANCEL": "Cancel",
    "SUCCESS": "Domain added. Paste the DNS records to finish verification.",
    "ERROR": "Could not add the domain. Please try again."
  }
}
```

### Portuguese (`pt_BR/campaign.json`) — same key tree
```json
"EMAIL_SENDER": {
  "HEADER_TITLE": "Domínios de envio de e-mail",
  "NEW_DOMAIN": "Adicionar domínio de envio",
  "DESCRIPTION": "Verifique seu domínio de envio uma única vez para que as campanhas de e-mail sejam entregues com a sua marca e passem nas checagens de SPF, DKIM e DMARC.",
  "EMPTY_STATE": {
    "TITLE": "Nenhum domínio de envio ainda",
    "SUBTITLE": "Adicione seu domínio para gerar os registros DNS que você precisa colar no seu registrador."
  },
  "TABLE": {
    "DOMAIN": "Domínio",
    "STATUS": "Status",
    "ACTIONS": "Ações"
  },
  "STATUS": {
    "PENDING": "Pendente",
    "VERIFYING": "Verificando",
    "VERIFIED": "Verificado",
    "FAILED": "Falhou"
  },
  "ACTIONS": {
    "VERIFY": "Verificar",
    "VERIFY_SUCCESS": "Reverificando junto ao provedor.",
    "ERROR": "Algo deu errado. Tente novamente."
  },
  "DNS": {
    "TITLE": "Registros DNS",
    "SUBTITLE": "Adicione estes registros no seu registrador de domínio. A verificação pode levar alguns minutos após a propagação.",
    "TYPE": "Tipo",
    "NAME": "Nome",
    "VALUE": "Valor",
    "DKIM": "DKIM (CNAME)",
    "SPF": "SPF (TXT)",
    "DMARC": "DMARC (TXT)",
    "COPY": "Copiar",
    "COPIED": "Copiado para a área de transferência"
  },
  "DIALOG": {
    "TITLE": "Adicionar domínio de envio",
    "DOMAIN_LABEL": "Domínio",
    "DOMAIN_PLACEHOLDER": "ex.: mail.suaempresa.com",
    "DOMAIN_ERROR": "Informe um domínio válido",
    "FROM_EMAIL_LABEL": "Remetente padrão (opcional)",
    "FROM_EMAIL_PLACEHOLDER": "ex.: marketing@suaempresa.com",
    "SUBMIT": "Adicionar domínio",
    "CANCEL": "Cancelar",
    "SUCCESS": "Domínio adicionado. Cole os registros DNS para concluir a verificação.",
    "ERROR": "Não foi possível adicionar o domínio. Tente novamente."
  }
}
```

---

## Package J — Integration (edits to shared files)

1. `config/routes.rb`: add the `namespace :email_campaigns` block (§D3) after the
   `namespace :crm do ... end` block closes (~line 212).
2. `config/schedule.yml`: append the cron entry (§C3).
3. `app/controllers/dashboard_controller.rb` (~line 82, near `CRM_KANBAN_ENABLED`): add
   `EMAIL_CAMPAIGN_ENABLED: ActiveModel::Type::Boolean.new.cast(ENV.fetch('EMAIL_CAMPAIGN_ENABLED', false)).to_s,`.
4. `app/javascript/shared/store/globalConfig.js`: destructure
   `EMAIL_CAMPAIGN_ENABLED: emailCampaignEnabled,` and add
   `emailCampaignEnabled: parseBoolean(emailCampaignEnabled),` to `state`.
5. `campaigns.routes.js`: import + child route (§E7).
6. `store/index.js` + `store/mutation-types.js`: register module + mutation types (§E3/E4).
7. Merge F's `EMAIL_SENDER` block into BOTH `en/campaign.json` and `pt_BR/campaign.json`;
   run i18n parity check.

> NOTE: The FE flag string `EMAIL_CAMPAIGN_ENABLED` reflects only the ENV var; the
> server-side `enabled?` ALSO requires `CRM_KANBAN_ENABLED`. For Onda 1 the FE gate on the
> raw flag is acceptable (matches WhatsApp API precedent); the API itself stays protected by
> `EmailCampaigns::Config.enabled?` (which enforces both). Acceptable because CRM is already
> enabled in this fork's prod (`conn21`).

---

## Gates (run after build)
- `ruby -c` on every new/edited `.rb`.
- `pnpm eslint` on touched JS/Vue.
- i18n parity: `en/campaign.json` vs `pt_BR/campaign.json` key trees identical.
- `vite build` clean.
- `eager_load` on a temp Swarm service.
- Real SES smoke (human, later): provision a domain identity for `hub2you.ai`, confirm DKIM
  CNAMEs returned + status flips to `verified` via the poll job; send one test email from the
  verified test identity `atendimento@hub2you.ai` (sandbox 200/day) via `Ses::Sender`.

## Open items deferred to later waves (NOT Onda 1)
Recipient import, `EmailCampaign` model, sending campaigns, SNS event webhook + configuration-set
event destinations, tracking pixel/click, reports/management UI (CRM area), unsubscribe +
suppression, per-tenant guardrails. Account-model inverse association
(`Account has_many :email_sender_identities`) is intentionally NOT added in Onda 1.
