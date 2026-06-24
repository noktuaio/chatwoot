# CRM Calendar / Meeting Hub — Complete Technical Plan

**Status:** READY (v2, post-revision)
**Base:** Chatwoot v4.15.1 fork, CRM PRs 1–14 merged
**Next PR:** PR15 (this feature)
**Runtime:** Rails 7 + Vue 3, pt_BR, whitelabel
**Date:** 2026-06-18

---

## Revision log (v2)

All fixes applied from adversarial-review. Verified codebase facts override where noted.

| Fix | Change |
|-----|--------|
| F1 | Google OAuth re-consent: force `access_type=offline&prompt=consent` when calendar intent present; preserve existing refresh_token if new callback returns none. Same care for Microsoft (offline_access). Added test case snippet. |
| F2 | Provider API call moved OUTSIDE the ActiveRecord transaction. New order: validate → (txn: persist draft meeting, external_event_id:nil) → provider call → (txn: update with external_event_id+url+status:scheduled, create FollowUp, set reminder_id, log activity). On failure: status:failed. Idempotency: skip provider call if external_event_id already set. |
| F3 | Fixed migration index typo: `%i[account_id meeting_id :email]` → `%i[account_id meeting_id email]`. |
| F4 | (Moot — verified fact 1) Removed all mentions of adding `meeting:4` to follow_up_type enum or adding follow_up_type/automation_mode/status/timezone columns to crm_follow_ups. `meeting` = value 3 already exists. No migration needed. |
| F5 | Google token refresh rewritten to follow BaseRefreshOauthTokenService pattern; no `scope:` param on refresh; uses correct oauth2 gem token refresh. |
| F6 | Microsoft::CalendarEventService rewritten to reuse Microsoft Graph HTTP pattern (like Microsoft::SendMailService) with 401(refresh)/403(no Teams license)/429(backoff) handling instead of raw Net::HTTP. |
| F7 | Microsoft::Scopes: GRAPH_WITH_CALENDAR constant shown; microsoft_concern.rb#scope updated to use it. Re-consent URL documented with offline_access. |
| F8 | Timezone: require ISO8601-with-offset from FE; controller uses ActiveSupport::TimeZone; mailer renders `starts_at.in_time_zone(meeting.timezone)`. |
| F9 | Google verification UX: block calendar re-consent when provider=google AND credentials source='global'; added agent copy about unverified-app screen; noted consumer Gmail cannot use Workspace-Internal. |
| F10 | Crm::Meetings::Sanitizer wired as FIRST step of Creator#perform; sanitizes guest names (strip CRLF/control chars, cap 255) and HTML description before provider call. |
| F11 | Removed `external_event_id` from API serializer; use meeting.id as public id. |
| F12 | Tightened email-reachable-guest validation: require at least one email-reachable guest (contact with email OR extra guest with email), not just "card has a conversation". Updated both model validate and Creator#perform. |
| F13 | Reminder/meeting persistence restructured per F2 reordering; no update_columns races (reminder_id set inside second txn). |
| F14 | Replaced `/auth/sign_in` placeholder in CrmCalendarMeetingScheduler.vue with real API module call via crmKanban.js pattern; FE API module added to file inventory. |
| F15 | Calendar query: added `.includes(:meeting_guests)` and `.size` to kill N+1. |
| F16 | Concrete changes shown for Crm::FollowUps::ReminderNotifier and Crm::FollowUpReminderMailer to handle follow_up_type == :meeting (join-link CTA, meeting title, start time in meeting timezone). Both added to modified-files list. |
| F17 | Provider labels via i18n keys (`t('crm.providers.google_meet')`, `t('crm.providers.teams')`) instead of hardcoded strings. |
| F18 | Reschedule semantics: in-place update (PATCH to provider, update local record). Documented explicitly. |
| F19 | Booking card (P3) includes default pipeline/stage/assignee. |
| F20 | Two-way-sync delta token moved to dedicated `crm_calendar_sync_states` table (new P3 migration); NOT stored in crm_mailbox_availabilities. |
| F23 | crm_meetings.reminder_id FK set to `on_delete: :nullify`; reverse handling documented. |
| F24 | External-events fetch bounded to view window with `$top=100` (MS) / `maxResults=100` (Google). |
| F26 | Dropped redundant guest validation already covered by F12. |
| F27 | Per-account FlagShihTzu feature flag added for staged rollout. |
| F28 | Crm::Config marked as MODIFIED (not new) everywhere; `self.calendar_meetings_enabled?` added to existing file. |
| F29 | Crm::ActivityLogger cited at correct path: `app/services/crm/activity_logger.rb`. |

---

## 1. Executive Overview & Locked Product Decisions

### 1.1 What This Feature Is

The CRM Calendar/Meeting Hub enables agents to schedule meetings directly from CRM deals (Crm::Card), send native calendar invites via the agent's own Google or Microsoft mailbox, auto-create reminders via the existing cal13 stack, and view all meetings on the CRM calendar alongside follow-ups and expected close dates.

### 1.2 Locked Product Decisions

These decisions are final. All implementation choices must conform to them.

| # | Decision | Detail |
|---|---|---|
| 1 | **Calendar = inbox capability, NOT a channel** | A per-inbox opt-in toggle `calendar_enabled` on Channel::Email. No new inbox type. |
| 2 | **Agent identity = their OAuth grant** | The email on the Channel::Email (`channel.email`) is the meeting organizer. The OAuth tokens on that channel grant calendar access. |
| 3 | **Default = personal mailbox; shared allowed** | Agent picks which connected mailbox to use at schedule time. Shared/department mailboxes are allowed but may lack a Teams license (documented caveat). |
| 4 | **Agent picks mailbox at schedule time** | The selected inbox drives: identity, calendar provider, online-meeting type (Teams or Meet), and the from-sender of the invite. |
| 5 | **Meeting MUST link to a Crm::Card** | A meeting without a card cannot be created. The card must have at least one EMAIL-reachable guest: either the contact has an email address, or at least one extra guest email is provided. |
| 6 | **Contact pre-fills as guest** | The card's contact email is automatically added as a guest (if present). The agent can add more guests (email addresses). |
| 7 | **Invite delivery = native .ics** | The calendar service (Google or Microsoft) sends the .ics invite to all guests. We do NOT send a separate plain email. We ALSO log a Chatwoot activity/message in the linked conversation timeline. |
| 8 | **Online meeting link** | Microsoft → Teams (`isOnlineMeeting: true, onlineMeetingProvider: 'teamsForBusiness'`). Google → Meet (`conferenceData.createRequest` with `hangoutsMeet`). |
| 9 | **Reminders = Crm::FollowUp** | Auto-create a `Crm::FollowUp` record at `starts_at - X minutes` using the EXISTING `follow_up_type: :meeting` (value 3) + `automation_mode: :reminder_only`. Fires via the existing cal13 notification stack (push + email + popup). X is configurable per meeting with a default of 15 min. |
| 10 | **Visibility** | Admin sees ALL meetings and all calendar events. Agents see only meetings on cards they can see (transitive through Crm::Card Pundit scope). |
| 11 | **Phase roadmap** | P1: schedule-from-card + Meet/Teams + native invite + inbox log + CRM calendar render + auto reminder. P2: free/busy + reschedule/cancel propagation + invite templates + read-only external events. P3: two-way sync (webhooks/delta), public booking page (Calendly-style), meeting outcome on card, no-show tracking, AI. |

---

## 2. Architecture

### 2.1 Calendar as Inbox Capability

```
Account
  └── Inbox (channel_type: email)
        └── Channel::Email
              ├── provider: 'microsoft' | 'google'
              ├── provider_config: { access_token, refresh_token, expires_on }
              ├── calendar_enabled: boolean  ← NEW toggle (DB column)
              └── calendar_identity: string  ← NEW (email used as organizer; defaults to channel.email)
```

The toggle is per-inbox. An account can have multiple email inboxes; each can independently have calendar enabled or disabled. The admin enables it per inbox; the OAuth scope is extended at re-consent time.

### 2.2 Identity / Mailbox → Calendar / Online Meeting

```
Agent selects inbox at schedule time
          │
          ▼
Channel::Email (calendar_enabled = true)
          │
          ├─ provider = 'microsoft'
          │       └─ Microsoft::GraphTokenService → access_token
          │       └─ POST /me/events (isOnlineMeeting: true, onlineMeetingProvider: teamsForBusiness)
          │       └─ response.onlineMeeting.joinUrl → meeting.online_meeting_url
          │
          └─ provider = 'google'
                  └─ Google::CalendarAccessTokenService → access_token
                  └─ POST /calendar/v3/calendars/primary/events (conferenceData.createRequest hangoutsMeet)
                  └─ response.conferenceData.entryPoints[video].uri → meeting.online_meeting_url
```

### 2.3 Existing Code Reuse Map

| What | Existing File | How Reused |
|------|---|---|
| OAuth credential resolution | `app/services/email_oauth/credential_resolver.rb` | Resolve client_id/secret per account+provider |
| MS Graph token fetch | `app/services/microsoft/graph_token_service.rb` | Access token for calendar API (same token as Mail.Send) |
| Token refresh base | `app/services/base_refresh_oauth_token_service.rb` | Base for Google calendar token refresh service |
| MS scope strings | `app/services/microsoft/scopes.rb` | Add `GRAPH_WITH_CALENDAR` constant |
| Google OAuth concern | `app/controllers/concerns/google_concern.rb` | Extend `#scope` to include calendar scope on re-consent |
| MS OAuth concern | `app/controllers/concerns/microsoft_concern.rb` | Extend scope for calendar on re-consent using `GRAPH_WITH_CALENDAR` |
| OAuth callback | `app/controllers/oauth_callback_controller.rb` | Update `#update_channel` to set `calendar_enabled` from intent; preserve existing refresh_token |
| CRM calendar controller | `app/controllers/api/v1/accounts/crm/calendar_controller.rb` | Append `meeting_events` to payload alongside follow_up_events + expected_close_events |
| cal13 reminder notifier | `app/services/crm/follow_ups/reminder_notifier.rb` | Fire meeting reminders via existing push+email+popup stack (MODIFIED: handle meeting type) |
| cal13 due processor | `app/services/crm/follow_ups/due_processor.rb` (Crm::FollowUps::DueProcessor) | Process meeting reminder follow-ups at due time |
| Follow-up mailer | `app/mailers/crm/follow_up_reminder_mailer.rb` | Send meeting reminder emails (MODIFIED: join-link CTA, meeting title, start time) |
| Notification enum | NotificationSetting (FlagShihTzu) `crm_followup_reminder` | Meeting reminders reuse this flag |
| CRM calendar FE | `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendar.vue` | Add meeting overlay |
| Quick-add placeholder | `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarQuickAdd.vue` | Meeting type `soon: true` → unlock in P1 |
| CRM API client | `app/javascript/dashboard/api/crmKanban.js` | Add meetings API methods (or sibling module following same ApiClient pattern) |
| Dyte API client precedent | `lib/dyte.rb` | Pattern for external meeting API client |
| Integration hook precedent | `app/models/integrations/hook.rb` | Account/inbox-level capability pattern |
| Activity logger | `app/services/crm/activity_logger.rb` | `Crm::ActivityLogger.new(card:, actor:, event_type:, conversation:, payload:).perform` |

---

## 3. Data Model & Ordered Migration List

### 3.1 Design Decision: DB Column vs. JSONB for `calendar_enabled`

**Decision: DB column on `channel_email`.**

Rationale: `calendar_enabled` needs to be indexed for queries like "list all calendar-enabled inboxes for this account". JSONB lookups cannot use standard B-tree indexes. A boolean column is nullable-safe, trivially indexed, and migration-safe (additive with `default: false`). Token data stays in `provider_config` JSONB (existing, encrypted). Settings go in DB columns.

### 3.2 New Table: `crm_meetings`

```ruby
# db/migrate/20260620000001_create_crm_meetings.rb
class CreateCrmMeetings < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_meetings do |t|
      # Core relationships
      t.references :account,      null: false, foreign_key: true
      t.references :card,         null: false, foreign_key: { to_table: :crm_cards }
      t.references :inbox,        null: false, foreign_key: true  # The chosen Channel::Email's parent Inbox
      t.references :scheduled_by, null: false, foreign_key: { to_table: :users }
      # reminder FK uses on_delete: :nullify so deleting a FollowUp does not block/cascade-delete the meeting
      t.references :reminder,     null: true,  foreign_key: { to_table: :crm_follow_ups, on_delete: :nullify }

      # Meeting content
      t.string   :title,               null: false
      t.text     :description
      t.datetime :starts_at,           null: false
      t.datetime :ends_at,             null: false
      t.string   :timezone,            null: false, default: 'UTC'

      # Status lifecycle: draft → scheduled → (completed|canceled|rescheduled|no_show)
      # status:draft means created in DB before provider call succeeds
      # status:failed means provider API returned an error
      t.integer  :status,              null: false, default: 0  # enum: draft/scheduled/completed/canceled/rescheduled/no_show/failed

      # Provider
      t.integer  :provider,            null: false              # enum: microsoft/google
      t.integer  :online_meeting_type, null: false, default: 0 # enum: teams/google_meet/none

      # External provider reference (nil until provider call succeeds)
      t.string   :external_event_id                             # Graph event ID or Google event ID; unique per provider
      t.text     :online_meeting_url                            # Teams joinUrl or Google Meet URI

      # Extensible metadata (P2: sync_token, delta; P3: outcome notes, AI summary)
      t.jsonb    :metadata,            null: false, default: {}

      t.timestamps
    end

    add_index :crm_meetings, %i[account_id card_id],                    name: 'idx_crm_meetings_card'
    add_index :crm_meetings, %i[account_id inbox_id],                   name: 'idx_crm_meetings_inbox'
    add_index :crm_meetings, %i[account_id scheduled_by_id],            name: 'idx_crm_meetings_agent'
    add_index :crm_meetings, %i[account_id status],                     name: 'idx_crm_meetings_status'
    add_index :crm_meetings, %i[account_id starts_at],                  name: 'idx_crm_meetings_starts_at'
    add_index :crm_meetings, %i[external_event_id provider],
              unique: true, where: 'external_event_id IS NOT NULL',      name: 'idx_crm_meetings_external_unique'
  end
end
```

### 3.3 New Table: `crm_meeting_guests`

```ruby
# db/migrate/20260620000002_create_crm_meeting_guests.rb
class CreateCrmMeetingGuests < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_meeting_guests do |t|
      t.references :account, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: { to_table: :crm_meetings }
      t.references :contact, null: true,  foreign_key: true  # CRM contact (if applicable)
      t.references :user,    null: true,  foreign_key: true  # Internal user/agent (if applicable)

      t.string  :email,       null: false
      t.string  :name
      t.integer :guest_type,  null: false, default: 0  # enum: contact/external_email/internal_user
      t.integer :rsvp_status, null: false, default: 0  # enum: pending/accepted/declined/tentative

      t.jsonb   :metadata,    null: false, default: {}  # P2: response_sent_at, external_guest_id

      t.timestamps
    end

    add_index :crm_meeting_guests, %i[account_id meeting_id],   name: 'idx_crm_meeting_guests_meeting'
    # F3 fix: removed leading colon from email in the symbol array
    add_index :crm_meeting_guests, %i[account_id meeting_id email],
              unique: true,                                       name: 'idx_crm_meeting_guests_unique_email'
    add_index :crm_meeting_guests, :contact_id,                  name: 'idx_crm_meeting_guests_contact'
  end
end
```

### 3.4 New Columns on `channel_email`

```ruby
# db/migrate/20260620000003_add_calendar_capability_to_channel_email.rb
class AddCalendarCapabilityToChannelEmail < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_email, :calendar_enabled,  :boolean, null: false, default: false
    add_column :channel_email, :calendar_identity, :string   # Optional override; defaults to channel.email

    add_index :channel_email, %i[account_id calendar_enabled], name: 'idx_channel_email_calendar_enabled'
  end
end
```

### 3.5 New Column on `crm_follow_ups` (Meeting Link only)

**Note (verified fact 1):** `crm_follow_ups` ALREADY has `follow_up_type` (int), `automation_mode` (int), `status` (int), `timezone` (string). `Crm::FollowUp` enum `follow_up_type` already includes `meeting: 3`. NO migration needed for those columns. This migration adds only the `meeting_id` back-reference.

```ruby
# db/migrate/20260620000004_add_meeting_to_crm_follow_ups.rb
class AddMeetingToCrmFollowUps < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_follow_ups, :meeting_id, :bigint
    add_foreign_key :crm_follow_ups, :crm_meetings, column: :meeting_id, on_delete: :nullify
    add_index :crm_follow_ups, :meeting_id, name: 'idx_crm_follow_ups_meeting'
  end
end
```

### 3.6 P2 Migrations (Free/Busy Cache)

```ruby
# db/migrate/20260630000001_create_crm_mailbox_availability.rb
class CreateCrmMailboxAvailability < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_mailbox_availabilities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox,   null: false, foreign_key: true  # Channel::Email parent Inbox
      t.date    :date,               null: false
      t.jsonb   :availability_json,  null: false, default: {}  # slots: [{start, end, busy}]
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :crm_mailbox_availabilities, %i[account_id inbox_id date],
              unique: true, name: 'idx_crm_mailbox_avail_unique'
  end
end
```

**Note (F20):** Delta/sync tokens for two-way sync are stored in the dedicated `crm_calendar_sync_states` table (P3 migration below), NOT in `crm_mailbox_availabilities`.

### 3.7 P3 Migrations (Booking Page + Two-Way Sync States)

```ruby
# db/migrate/20260701000001_create_crm_agent_booking_profiles.rb
class CreateCrmAgentBookingProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_agent_booking_profiles do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true  # The agent

      t.string  :slug,                null: false   # UUID-based; used in public URL
      t.string  :title
      t.text    :description
      # F19: default pipeline/stage/assignee for booking-created cards
      t.references :default_pipeline, null: true, foreign_key: { to_table: :crm_pipelines }
      t.references :default_stage,    null: true, foreign_key: { to_table: :crm_stages }
      t.references :default_assignee, null: true, foreign_key: { to_table: :users }

      t.integer :booking_window_days, null: false, default: 30
      t.integer :meeting_duration,    null: false, default: 30   # minutes
      t.integer :buffer_minutes,      null: false, default: 15   # between meetings
      t.string  :timezone
      t.boolean :enabled,             null: false, default: false
      t.jsonb   :settings,            null: false, default: {}  # color, email_template, etc.

      t.timestamps
    end

    add_index :crm_agent_booking_profiles, :slug, unique: true
    add_index :crm_agent_booking_profiles, %i[account_id user_id], unique: true
  end
end

# db/migrate/20260701000002_create_crm_calendar_sync_states.rb
# F20: delta/sync tokens live here, not in crm_mailbox_availabilities
class CreateCrmCalendarSyncStates < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_calendar_sync_states do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox,   null: false, foreign_key: true
      t.string  :provider,           null: false  # 'microsoft' | 'google'
      t.string  :delta_token                      # MS Graph: deltaLink token; Google: syncToken
      t.string  :subscription_id                  # MS: subscription ID for change notifications
      t.string  :channel_id                       # Google: push notification channel ID
      t.datetime :subscription_expires_at
      t.datetime :last_synced_at
      t.jsonb   :metadata,           null: false, default: {}

      t.timestamps
    end

    add_index :crm_calendar_sync_states, %i[account_id inbox_id provider],
              unique: true, name: 'idx_crm_cal_sync_states_unique'
  end
end
```

### 3.8 Model: `Crm::Meeting`

**File:** `app/models/crm/meeting.rb`

Status enum includes `draft` (created before provider call) and `failed` (provider call failed), per F2.

```ruby
class Crm::Meeting < ApplicationRecord
  self.table_name = 'crm_meetings'

  belongs_to :account
  belongs_to :card,         class_name: 'Crm::Card'
  belongs_to :inbox                                    # Parent Inbox; channel resolved via inbox.channel
  belongs_to :scheduled_by, class_name: 'User'
  belongs_to :reminder,     class_name: 'Crm::FollowUp', optional: true

  has_many :meeting_guests, class_name: 'Crm::MeetingGuest',
           dependent: :destroy, inverse_of: :meeting

  # draft: created in DB before provider call; failed: provider call errored
  enum status: { draft: 0, scheduled: 1, completed: 2, canceled: 3, rescheduled: 4, no_show: 5, failed: 6 }
  enum provider: { microsoft: 0, google: 1 }
  enum online_meeting_type: { teams: 0, google_meet: 1, no_online: 2 }

  validates :title, :starts_at, :ends_at, :timezone, :provider, presence: true
  validates :account_id, :card_id, :inbox_id, :scheduled_by_id, presence: true
  validates :external_event_id, uniqueness: { scope: :provider }, allow_blank: true
  validate  :ends_at_after_starts_at
  validate  :linked_records_must_belong_to_account
  validate  :inbox_must_have_calendar_enabled
  validate  :card_must_have_email_reachable_guest  # F12

  scope :upcoming,  -> { where(status: :scheduled).where('starts_at > ?', Time.current) }
  scope :past,      -> { where(status: %i[completed canceled no_show]) }
  scope :by_agent,  ->(user_id) { where(scheduled_by_id: user_id) }

  # Resolves the Channel::Email from the parent Inbox
  def email_channel
    inbox.channel
  end

  private

  def ends_at_after_starts_at
    return if ends_at.blank? || starts_at.blank?
    errors.add(:ends_at, 'must be after starts_at') unless ends_at > starts_at
  end

  def linked_records_must_belong_to_account
    %i[card inbox].each do |assoc|
      record = public_send(assoc)
      next if record.blank? || account_id.blank?
      errors.add(assoc, 'must belong to the same account') if record.account_id != account_id
    end
    if scheduled_by.present?
      unless scheduled_by.account_users.exists?(account_id: account_id)
        errors.add(:scheduled_by, 'must belong to the same account')
      end
    end
  end

  def inbox_must_have_calendar_enabled
    return if inbox.blank?
    ch = inbox.channel
    return if ch.is_a?(Channel::Email) && ch.calendar_enabled?
    errors.add(:inbox, 'must have calendar enabled')
  end

  # F12: require at least one EMAIL-reachable guest
  # (contact with an email address OR at least one extra guest email provided)
  def card_must_have_email_reachable_guest
    return if card.blank?
    contact_has_email = card.contact&.email.present?
    guests_have_email = meeting_guests.any? { |g| g.email.present? }
    return if contact_has_email || guests_have_email
    errors.add(:base, 'at least one email-reachable guest is required (contact email or extra guest email)')
  end
end
```

### 3.9 Model: `Crm::MeetingGuest`

**File:** `app/models/crm/meeting_guest.rb`

```ruby
class Crm::MeetingGuest < ApplicationRecord
  self.table_name = 'crm_meeting_guests'

  belongs_to :account
  belongs_to :meeting,  class_name: 'Crm::Meeting', inverse_of: :meeting_guests
  belongs_to :contact,  optional: true
  belongs_to :user,     optional: true

  enum guest_type:  { contact_guest: 0, external_email: 1, internal_user: 2 }
  enum rsvp_status: { rsvp_pending: 0, rsvp_accepted: 1, rsvp_declined: 2, rsvp_tentative: 3 }

  validates :email, :guest_type, presence: true
  validates :account_id, :meeting_id, presence: true
  validates :email, uniqueness: { scope: [:account_id, :meeting_id] }
  # Note: redundant at_least_one_identifier removed (F26): email presence above is sufficient
end
```

### 3.10 Channel::Email Model Additions

**File:** `app/models/channel/email.rb` (additive methods only)

```ruby
# Add these methods to the existing Channel::Email class:

def calendar_enabled?
  calendar_enabled == true
end

def can_enable_calendar?
  microsoft? || google?
end

def calendar_organizer_email
  calendar_identity.presence || email
end

# F17: use i18n keys for provider labels, not hardcoded strings
def calendar_provider_label
  return I18n.t('crm.providers.teams')      if microsoft?
  return I18n.t('crm.providers.google_meet') if google?
  nil
end
```

---

## 4. Phased Roadmap

### 4.1 Phase 1 (P1): Schedule-from-Card MVP

**Goal:** Agent schedules a meeting from a card → native .ics invite sent → online meeting link auto-created → activity logged in conversation → reminder auto-created → event appears in CRM calendar.

#### 4.1.1 P1 Backend: OAuth Scope Extension

**File:** `app/services/microsoft/scopes.rb`

```ruby
module Microsoft
  module Scopes
    IMAP               = 'openid profile email offline_access https://outlook.office.com/IMAP.AccessAsUser.All'.freeze
    GRAPH              = 'https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/Mail.ReadWrite offline_access'.freeze
    # F7: GRAPH_WITH_CALENDAR adds Calendars.ReadWrite; offline_access preserved for refresh token
    GRAPH_WITH_CALENDAR = "#{GRAPH} https://graph.microsoft.com/Calendars.ReadWrite".freeze
  end
end
```

**File:** `app/controllers/concerns/microsoft_concern.rb` (F7 — extend `#scope` for calendar intent):

```ruby
# In microsoft_concern.rb, update the scope method:
def scope
  # F7: use GRAPH_WITH_CALENDAR when calendar intent is present; offline_access is included in both
  if params[:calendar_intent].present? || (session[:oauth_state_params] || {})['calendar_intent'].present?
    Microsoft::Scopes::GRAPH_WITH_CALENDAR
  else
    Microsoft::Scopes::GRAPH
  end
end
```

**File:** `app/controllers/concerns/google_concern.rb` (F1 + F9 — re-consent with access_type=offline + prompt=consent):

```ruby
def scope
  base = 'email profile https://mail.google.com/'
  return "#{base} https://www.googleapis.com/auth/calendar" if params[:calendar_intent].present?
  base
end

# F1: force offline access and consent prompt when calendar scope is requested
def authorization_params
  p = super
  if params[:calendar_intent].present?
    # F9: block if using global credentials (per-account own-app required for calendar)
    resolver = EmailOauth::CredentialResolver.new(current_account, 'google')
    if resolver.credentials[:source] == 'global'
      raise StandardError, I18n.t('crm.oauth.google_calendar_requires_own_app')
    end
    p.merge!(access_type: 'offline', prompt: 'consent')
  end
  p
end
```

> **F9 — Google Verification UX Note (for implementation & agent-facing copy):**
> - Calendar re-consent is **blocked** when `provider=google` AND credentials source is `global`. The agent must register their own GCP project (per-account own-app via `AccountEmailOauthApp` pattern).
> - When an agent uses their own GCP project in test/dev, Google shows an "unverified app" warning screen. Agents should click "Advanced" → "Go to [app name] (unsafe)" to proceed during testing. For production, the GCP app must complete Google OAuth verification.
> - Consumer Gmail accounts **cannot** use Workspace-Internal app type (Workspace-Internal requires a Google Workspace org). Personal Gmail users must use per-account own-app and complete verification.

**File:** `app/controllers/oauth_callback_controller.rb` (F1 — preserve existing refresh_token if new callback returns none):

```ruby
def update_channel(channel_email)
  existing_config = channel_email.provider_config.to_h
  new_refresh_token = parsed_body['refresh_token']

  # F1: never nullify an existing refresh_token if the new callback doesn't return one
  # (Google only returns a new refresh_token on first consent or when prompt=consent was forced)
  preserved_refresh_token = new_refresh_token.presence || existing_config['refresh_token']

  channel_email.update!(
    imap_login:      imap_login_identity,
    imap_address:    imap_address,
    provider:        provider_name,
    provider_config: {
      access_token:  parsed_body['access_token'],
      refresh_token: preserved_refresh_token,
      expires_on:    token_expires_on
    },
    # Preserve calendar_enabled if already set; enable if calendar_intent present
    calendar_enabled:  calendar_intent_present? || channel_email.calendar_enabled?,
    calendar_identity: users_data['email']
  )
end

private

def calendar_intent_present?
  params[:calendar_intent].present? || (session[:oauth_state_params] || {})['calendar_intent'].present?
end
```

**Test case snippet (F1):**

```ruby
# spec/controllers/oauth_callback_controller_spec.rb
describe '#update_channel (refresh_token preservation)' do
  let(:channel) { create(:channel_email, provider: 'google', provider_config: { 'refresh_token' => 'existing_token' }) }

  it 'preserves the existing refresh_token when the callback returns none' do
    # Simulate Google callback without refresh_token (access_token only)
    allow(controller).to receive(:parsed_body).and_return({ 'access_token' => 'new_access', 'expires_in' => 3600 })
    controller.send(:update_channel, channel)
    expect(channel.reload.provider_config['refresh_token']).to eq('existing_token')
  end

  it 'updates the refresh_token when the callback returns a new one' do
    allow(controller).to receive(:parsed_body).and_return({ 'access_token' => 'new_access', 'refresh_token' => 'new_token', 'expires_in' => 3600 })
    controller.send(:update_channel, channel)
    expect(channel.reload.provider_config['refresh_token']).to eq('new_token')
  end
end
```

#### 4.1.2 P1 Backend: Google Calendar Token Service

**File:** `app/services/google/calendar_access_token_service.rb` (NEW)

**F5 fix:** Follows the EXISTING `BaseRefreshOauthTokenService` / `Microsoft::RefreshOauthTokenService` pattern. Does NOT pass a `scope:` param on refresh (the refresh grant type does not accept a scope param in the oauth2 gem). Uses the correct oauth2 gem `refresh!` call.

```ruby
# F5: follows BaseRefreshOauthTokenService pattern; no scope: param on refresh
class Google::CalendarAccessTokenService < BaseRefreshOauthTokenService
  def initialize(channel:)
    @channel = channel
  end

  # Called by BaseRefreshOauthTokenService; returns { access_token:, refresh_token:, expires_on: }
  def provider_config
    @channel.provider_config.to_h
  end

  def channel
    @channel
  end

  def credentials
    EmailOauth::CredentialResolver.new(@channel.account, 'google').credentials
  end

  # Override the token_expired? check from base if needed; base uses expires_on with 5-min buffer

  private

  # F5: correct oauth2 gem refresh — no scope param; use access_token.refresh! pattern
  def refresh_access_token
    creds = credentials
    client = OAuth2::Client.new(
      creds[:client_id], creds[:client_secret],
      site:      'https://oauth2.googleapis.com',
      token_url: 'https://accounts.google.com/o/oauth2/token'
    )
    existing_config = provider_config
    existing_token  = OAuth2::AccessToken.new(
      client,
      existing_config['access_token'],
      refresh_token: existing_config['refresh_token']
    )
    # F5: refresh! does NOT take a scope: param
    new_token = existing_token.refresh!
    # F1: preserve existing refresh_token if the response doesn't return a new one
    new_refresh = new_token.refresh_token.presence || existing_config['refresh_token']
    @channel.update!(
      provider_config: existing_config.merge(
        'access_token' => new_token.token,
        'refresh_token' => new_refresh,
        'expires_on'   => (Time.current + new_token.expires_in.to_i.seconds).iso8601
      )
    )
    new_token.token
  end
end
```

#### 4.1.3 P1 Backend: Microsoft Graph Calendar Event Service

**File:** `app/services/microsoft/calendar_event_service.rb` (NEW)

**F6 fix:** Reuses the existing Microsoft Graph HTTP pattern (like `Microsoft::SendMailService`) with proper 401 (refresh + retry), 403 (no Teams license, surface error), and 429 (backoff + retry) handling. NOT raw Net::HTTP.

```ruby
# F6: follows Microsoft::SendMailService pattern with Graph HTTP base class
class Microsoft::CalendarEventService
  GRAPH_EVENTS_URL = 'https://graph.microsoft.com/v1.0/me/events'.freeze
  MAX_RETRIES      = 2

  def initialize(channel:, meeting_params:, guests:)
    @channel        = channel
    @meeting_params = meeting_params
    @guests         = guests
  end

  def create
    response = make_graph_request(event_payload)
    body     = parse_response!(response)

    OpenStruct.new(
      external_event_id:  body['id'],
      online_meeting_url: body.dig('onlineMeeting', 'joinUrl'),
      provider:           :microsoft
    )
  end

  private

  def make_graph_request(payload, attempt: 1)
    token    = Microsoft::GraphTokenService.new(channel: @channel).access_token
    response = send_request(token, payload)

    case response.code.to_i
    when 201
      response
    when 401
      # F6: refresh and retry once
      raise Microsoft::CalendarError, 'Unauthorized after token refresh' if attempt >= MAX_RETRIES
      Microsoft::GraphTokenService.new(channel: @channel).refresh!
      make_graph_request(payload, attempt: attempt + 1)
    when 403
      # F6: 403 often means no Teams license for the shared mailbox
      body = safe_parse(response.body)
      msg  = body.dig('error', 'message') || 'Forbidden'
      raise Microsoft::CalendarNoTeamsLicenseError, "Microsoft Graph 403: #{msg} (check Teams license on mailbox)"
    when 429
      # F6: rate limit — back off and retry
      raise Microsoft::CalendarError, 'Rate limited by Microsoft Graph (429)' if attempt >= MAX_RETRIES
      retry_after = response['Retry-After']&.to_i || 2
      sleep(retry_after)
      make_graph_request(payload, attempt: attempt + 1)
    else
      body = safe_parse(response.body)
      raise Microsoft::CalendarError, "MS Graph #{response.code}: #{body.dig('error', 'message')}"
    end
  end

  def send_request(token, payload)
    # Reuse the same Faraday/Net::HTTP wrapper pattern as Microsoft::SendMailService
    uri  = URI(GRAPH_EVENTS_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 15
    http.read_timeout = 30
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{token}"
    req['Content-Type']  = 'application/json'
    req.body              = payload.to_json
    http.request(req)
  end

  def parse_response!(response)
    JSON.parse(response.body)
  end

  def safe_parse(body)
    JSON.parse(body)
  rescue
    {}
  end

  def event_payload
    {
      subject:    @meeting_params[:title],
      body:       { contentType: 'HTML', content: @meeting_params[:description].to_s },
      start:      { dateTime: @meeting_params[:starts_at].iso8601, timeZone: @meeting_params[:timezone] },
      end:        { dateTime: @meeting_params[:ends_at].iso8601,   timeZone: @meeting_params[:timezone] },
      attendees:  attendees_payload,
      isOnlineMeeting:            true,
      onlineMeetingProvider:      'teamsForBusiness',
      isReminderOn:               true,
      reminderMinutesBeforeStart: 15,
      categories:                 ['CRM']
    }
  end

  def attendees_payload
    @guests.map do |g|
      { emailAddress: { address: g[:email], name: g[:name] }, type: 'required' }
    end
  end
end

module Microsoft
  CalendarError              = Class.new(StandardError)
  CalendarNoTeamsLicenseError = Class.new(CalendarError)
end
```

#### 4.1.4 P1 Backend: Google Calendar Event Service

**File:** `app/services/google/calendar_event_service.rb` (NEW)

```ruby
class Google::CalendarEventService
  CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'.freeze

  def initialize(channel:, meeting_params:, guests:)
    @channel        = channel
    @meeting_params = meeting_params
    @guests         = guests
  end

  def create
    url      = "#{CALENDAR_API_BASE}/calendars/primary/events?sendUpdates=all&conferenceDataVersion=1"
    response = post_to_calendar(url, event_payload)
    body     = JSON.parse(response.body)
    raise "Google Calendar #{response.code}: #{body.dig('error', 'message')}" unless response.code.to_i == 200

    join_url = body.dig('conferenceData', 'entryPoints')
                   &.find { |ep| ep['entryPointType'] == 'video' }
                   &.dig('uri')

    OpenStruct.new(
      external_event_id:  body['id'],
      online_meeting_url: join_url,
      provider:           :google
    )
  end

  private

  def event_payload
    {
      summary:     @meeting_params[:title],
      description: @meeting_params[:description].to_s,
      start:       { dateTime: @meeting_params[:starts_at].iso8601, timeZone: @meeting_params[:timezone] },
      end:         { dateTime: @meeting_params[:ends_at].iso8601,   timeZone: @meeting_params[:timezone] },
      attendees:   attendees_payload,
      conferenceData: {
        createRequest: {
          requestId:             SecureRandom.uuid,
          conferenceSolutionKey: { type: 'hangoutsMeet' }
        }
      },
      reminders: { useDefault: false, overrides: [{ method: 'notification', minutes: 15 }] },
      extendedProperties: {
        shared: { crm_card_id: @meeting_params[:card_id].to_s }
      }
    }
  end

  def attendees_payload
    @guests.map { |g| { email: g[:email], displayName: g[:name], responseStatus: 'needsAction' } }
  end

  def post_to_calendar(url, payload)
    token = Google::CalendarAccessTokenService.new(channel: @channel).access_token
    uri   = URI(url)
    http  = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 15
    http.read_timeout = 30
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{token}"
    req['Content-Type']  = 'application/json'
    req.body              = payload.to_json
    http.request(req)
  end
end
```

#### 4.1.5 P1 Backend: Meeting Sanitizer (F10)

**File:** `app/services/crm/meetings/sanitizer.rb` (NEW)

Called as the FIRST step of `Crm::Meetings::Creator#perform` before any provider call.

```ruby
class Crm::Meetings::Sanitizer
  CONTROL_CHAR_REGEX  = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/.freeze
  CRLF_REGEX          = /[\r\n]+/.freeze
  MAX_TITLE_LENGTH    = 255
  MAX_GUEST_NAME_LEN  = 255
  MAX_DESCRIPTION_LEN = 5000

  def initialize(params)
    @params = params.dup
  end

  # Returns sanitized params hash; raises ArgumentError on invalid guest emails
  def sanitize!
    @params[:title]       = sanitize_string(@params[:title], max: MAX_TITLE_LENGTH)
    @params[:description] = sanitize_html(@params[:description])
    @params[:extra_guests] = sanitize_guest_emails(@params[:extra_guests] || [])
    @params
  end

  private

  def sanitize_string(str, max: 255)
    return '' if str.blank?
    str.gsub(CRLF_REGEX, ' ').gsub(CONTROL_CHAR_REGEX, '').strip.truncate(max)
  end

  def sanitize_html(html)
    return '' if html.blank?
    # Strip all HTML tags for plain text; truncate
    ActionView::Base.full_sanitizer.sanitize(html.to_s).strip.truncate(MAX_DESCRIPTION_LEN)
  end

  def sanitize_guest_emails(emails)
    emails.map do |email|
      normalized = email.to_s.strip
      Mail::Address.new(normalized).address  # raises if invalid RFC 5322
      normalized
    end
  rescue Mail::Field::ParseError => e
    raise ArgumentError, "Invalid guest email: #{e.message}"
  end

  # Guest names (from params or contact records) sanitized before sending to provider
  def self.sanitize_guest_name(name)
    return '' if name.blank?
    name.gsub(CRLF_REGEX, ' ').gsub(CONTROL_CHAR_REGEX, '').strip.truncate(MAX_GUEST_NAME_LEN)
  end
end
```

#### 4.1.6 P1 Backend: Meeting Creation Orchestrator (F2, F10, F12, F13)

**File:** `app/services/crm/meetings/creator.rb` (NEW)

**F2 critical fix:** Provider API call is OUTSIDE the ActiveRecord transaction. Two-phase commit:
1. (txn) persist meeting with status:draft, external_event_id:nil
2. (outside txn) call provider API
3. (txn) update meeting with external_event_id + url + status:scheduled, create FollowUp, set reminder_id, log activity

Idempotency: if `external_event_id` is already set (e.g., after a crash+retry), skip the provider call.

```ruby
class Crm::Meetings::Creator
  def initialize(account:, card:, inbox:, scheduled_by:, params:)
    @account      = account
    @card         = card
    @inbox        = inbox
    @scheduled_by = scheduled_by
    @params       = params
  end

  def perform
    # F10: sanitize FIRST before any DB or provider interaction
    sanitized_params = Crm::Meetings::Sanitizer.new(@params).sanitize!

    # F12: validate email-reachable guest BEFORE touching DB
    guests = build_guest_list(sanitized_params)
    validate_email_reachable_guest!(guests)

    # F2 Phase 1: persist meeting as :draft outside any provider interaction
    meeting = create_draft_meeting!(sanitized_params)

    # F2 Idempotency: skip provider call if already has external_event_id (crash+retry safe)
    unless meeting.external_event_id.present?
      begin
        provider_res = call_provider_api(sanitized_params, guests)
      rescue => e
        meeting.update_columns(status: Crm::Meeting.statuses[:failed], metadata: meeting.metadata.merge('error' => e.message))
        raise
      end

      # F2 Phase 2: update meeting + create reminder + log activity (all in one txn)
      ActiveRecord::Base.transaction do
        persist_guests!(meeting, guests)
        meeting.update!(
          external_event_id:  provider_res.external_event_id,
          online_meeting_url: provider_res.online_meeting_url,
          status:             :scheduled
        )
        reminder = create_reminder!(meeting, sanitized_params)
        # F13: set reminder_id inside this txn, not via update_columns race
        meeting.update_column(:reminder_id, reminder.id)
        log_activity(meeting)
      end
    end

    meeting.reload
  end

  private

  def build_guest_list(params)
    guests = []
    if @card.contact&.email.present?
      guests << {
        email:      @card.contact.email,
        name:       Crm::Meetings::Sanitizer.sanitize_guest_name(@card.contact.name),
        type:       :contact_guest,
        contact_id: @card.contact.id
      }
    end
    (params[:extra_guests] || []).each do |email|
      next if email.blank?
      guests << { email: email, name: nil, type: :external_email, contact_id: nil }
    end
    guests
  end

  # F12: require at least one email-reachable guest
  def validate_email_reachable_guest!(guests)
    return if guests.any? { |g| g[:email].present? }
    raise ArgumentError, I18n.t('crm.meetings.errors.no_email_reachable_guest')
  end

  def create_draft_meeting!(params)
    # F2: persisted with status:draft, external_event_id:nil — BEFORE provider call
    ActiveRecord::Base.transaction do
      Crm::Meeting.create!(
        account:             @account,
        card:                @card,
        inbox:               @inbox,
        scheduled_by:        @scheduled_by,
        title:               params[:title],
        description:         params[:description],
        starts_at:           params[:starts_at],
        ends_at:             params[:ends_at],
        timezone:            params[:timezone],
        provider:            resolve_provider,
        online_meeting_type: online_type(resolve_provider),
        external_event_id:   nil,
        online_meeting_url:  nil,
        status:              :draft
      )
    end
  end

  def call_provider_api(params, guests)
    channel = @inbox.channel
    mp      = params.merge(card_id: @card.id)

    if channel.microsoft?
      Microsoft::CalendarEventService.new(channel: channel, meeting_params: mp, guests: guests).create
    elsif channel.google?
      Google::CalendarEventService.new(channel: channel, meeting_params: mp, guests: guests).create
    else
      raise "Inbox provider not supported for calendar: #{channel.provider}"
    end
  end

  def persist_guests!(meeting, guests)
    guests.each do |g|
      meeting.meeting_guests.create!(
        account:     @account,
        email:       g[:email],
        name:        g[:name],
        guest_type:  g[:type],
        contact_id:  g[:contact_id],
        rsvp_status: :rsvp_pending
      )
    end
  end

  # F13: reminder creation inside the second txn (no update_columns race)
  # Uses EXISTING follow_up_type: :meeting (value 3) per verified fact 1 — NO enum change needed
  def create_reminder!(meeting, params)
    reminder_minutes = params[:reminder_minutes_before] || 15
    Crm::FollowUp.create!(
      account:         @account,
      card:            @card,
      created_by:      @scheduled_by,
      title:           "Reunião: #{meeting.title}",
      due_at:          meeting.starts_at - reminder_minutes.minutes,
      timezone:        meeting.timezone,
      follow_up_type:  :meeting,    # EXISTING value 3 — no migration needed
      automation_mode: :reminder_only,
      status:          :pending,
      meeting_id:      meeting.id
    )
  end

  # F29: uses Crm::ActivityLogger at app/services/crm/activity_logger.rb
  def log_activity(meeting)
    conv = @card.primary_conversation  # verified fact 3: belongs_to via conversation_id
    return unless conv

    Crm::ActivityLogger.new(
      card:         @card,
      actor:        @scheduled_by,
      event_type:   'meeting_scheduled',
      conversation: conv,
      payload: {
        meeting_id:         meeting.id,
        title:              meeting.title,
        starts_at:          meeting.starts_at.iso8601,
        online_meeting_url: meeting.online_meeting_url,
        provider:           meeting.provider,
        guests_count:       meeting.meeting_guests.size
      }
    ).perform
  end

  def resolve_provider
    @inbox.channel.microsoft? ? :microsoft : :google
  end

  def online_type(provider)
    provider.to_s == 'microsoft' ? :teams : :google_meet
  end
end
```

#### 4.1.7 P1 Backend: Controller & Routes

**File:** `app/controllers/api/v1/accounts/crm/meetings_controller.rb` (NEW)

**F8:** Controller parses starts_at/ends_at as ISO8601 with timezone offset.

```ruby
class Api::V1::Accounts::Crm::MeetingsController < Api::V1::Accounts::Crm::BaseController
  def create
    authorize Crm::Meeting, :create?

    meeting = Crm::Meetings::Creator.new(
      account:      Current.account,
      card:         card,
      inbox:        inbox,
      scheduled_by: Current.user,
      params:       meeting_params
    ).perform

    render json: { payload: serialize(meeting) }, status: :created
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Microsoft::CalendarNoTeamsLicenseError => e
    render json: { error: e.message, code: 'no_teams_license' }, status: :unprocessable_entity
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def card
    @card ||= policy_scope(Crm::Card).find(params[:card_id])
  end

  def inbox
    @inbox ||= Current.account.inboxes.find(params[:inbox_id])
  end

  def meeting_params
    # F8: require ISO8601-with-offset from FE; parse with ActiveSupport for timezone awareness
    raw = params.require(:meeting).permit(
      :title, :description, :starts_at, :ends_at, :timezone,
      :reminder_minutes_before, extra_guests: []
    ).to_h.symbolize_keys

    tz_name = raw[:timezone].presence || 'UTC'
    tz      = ActiveSupport::TimeZone[tz_name] || ActiveSupport::TimeZone['UTC']

    raw.merge(
      starts_at: tz.parse(raw[:starts_at].to_s),
      ends_at:   tz.parse(raw[:ends_at].to_s)
    )
  end

  # F11: external_event_id REMOVED from serializer (server-side only); use meeting.id as public id
  def serialize(meeting)
    {
      id:                  meeting.id,
      card_id:             meeting.card_id,
      title:               meeting.title,
      starts_at:           meeting.starts_at.iso8601,
      ends_at:             meeting.ends_at.iso8601,
      timezone:            meeting.timezone,
      status:              meeting.status,
      provider:            meeting.provider,
      online_meeting_type: meeting.online_meeting_type,
      online_meeting_url:  meeting.online_meeting_url,
      reminder_id:         meeting.reminder_id,
      guests:              meeting.meeting_guests.map { |g|
        { id: g.id, email: g.email, name: g.name, rsvp_status: g.rsvp_status }
      },
      scheduled_by: { id: meeting.scheduled_by.id, name: meeting.scheduled_by.name },
      created_at:   meeting.created_at.iso8601
    }
  end
end
```

**Routes addition** (`config/routes.rb`):

```ruby
namespace :crm do
  resources :meetings, only: %i[index create show update destroy]
  # ... existing crm routes
end
```

#### 4.1.8 P1 Backend: Calendar Controller Extension (F15)

**File:** `app/controllers/api/v1/accounts/crm/calendar_controller.rb` (extend `#events`):

**F15:** Added `.includes(:meeting_guests)` to kill the N+1; use `.size` (uses preloaded association).

```ruby
def events
  authorize ::Crm::FollowUp, :index?
  render json: { payload: follow_up_events + expected_close_events + meeting_events }
end

private

def meeting_events
  scope = policy_scope(Crm::Meeting).where(account_id: Current.account.id)
  scope = scope.where('starts_at >= ?', parsed_time(:from)) if params[:from].present?
  scope = scope.where('starts_at <= ?', parsed_time(:to))   if params[:to].present?

  # F15: includes(:meeting_guests) kills N+1; .size uses preloaded array
  scope.includes(:meeting_guests).order(:starts_at).limit(200).map do |m|
    {
      id:          "meeting_#{m.id}",
      event_type:  'meeting',
      title:       m.title,
      starts_at:   m.starts_at&.iso8601,
      ends_at:     m.ends_at&.iso8601,
      status:      m.status,
      card_id:     m.card_id,
      inbox_id:    m.inbox_id,
      assignee_id: m.scheduled_by_id,
      metadata: {
        meeting_id:          m.id,
        online_meeting_url:  m.online_meeting_url,
        online_meeting_type: m.online_meeting_type,
        provider:            m.provider,
        guests_count:        m.meeting_guests.size  # F15: .size uses loaded association
      }
    }
  end
end
```

#### 4.1.9 P1 Frontend: Meetings API Module (F14)

**File:** `app/javascript/dashboard/api/crmMeetings.js` (NEW — follows crmKanban.js ApiClient pattern)

```javascript
// app/javascript/dashboard/api/crmMeetings.js
// Follows the same ApiClient subclass pattern as crmKanban.js
import ApiClient from './ApiClient';

class CrmMeetingsAPI extends ApiClient {
  constructor() {
    super('/crm/meetings', { accountScoped: true });
  }

  /**
   * Schedule a new meeting from a CRM card.
   * @param {Object} params - { card_id, inbox_id, meeting: { title, starts_at, ends_at, timezone, ... } }
   */
  createMeeting({ cardId, inboxId, meeting }) {
    return axios.post(this.url, {
      card_id:  cardId,
      inbox_id: inboxId,
      meeting,
    });
  }

  getMeetings({ cardId, from, to } = {}) {
    return axios.get(this.url, {
      params: { card_id: cardId, from, to },
    });
  }

  getMeeting(meetingId) {
    return axios.get(`${this.url}/${meetingId}`);
  }

  rescheduleMeeting(meetingId, params) {
    return axios.patch(`${this.url}/${meetingId}`, params);
  }

  cancelMeeting(meetingId) {
    return axios.delete(`${this.url}/${meetingId}`);
  }
}

export default new CrmMeetingsAPI();
```

#### 4.1.10 P1 Frontend: Unlock Meeting Quick-Add

**File:** `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarQuickAdd.vue`

Change the `meeting` entry in the TYPES array:

```javascript
// Before:
{ type: 'meeting', icon: 'i-lucide-video', label: 'Meeting', soon: true }

// After:
{ type: 'meeting', icon: 'i-lucide-video', label: t('CRM_KANBAN.CALENDAR.QUICK_ADD.MEETING') }
```

When `type === 'meeting'`, emit `openMeetingScheduler` instead of rendering inline:

```javascript
const onMeetingClick = () => {
  if (type.value === 'meeting') {
    emit('openMeetingScheduler', {
      cardId:    selectedCardId.value,
      date:      dueAt.value,
      dealTitle: selectedCardLabel.value,
    });
    emit('close');
    return;
  }
  // ... existing flow
};
```

#### 4.1.11 P1 Frontend: Meeting Scheduler Modal (F14)

**File:** `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarMeetingScheduler.vue` (NEW)

**F14:** API call uses `crmMeetingsAPI.createMeeting(...)` from `app/javascript/dashboard/api/crmMeetings.js`. NEVER `window.chatwootBus.$http` and NEVER `/auth/sign_in`.

```vue
<script setup>
import { ref, computed, watch }  from 'vue';
import { useI18n }               from 'vue-i18n';
import crmMeetingsAPI            from '../../../../api/crmMeetings';  // F14: real API module

const props = defineProps({
  show:             Boolean,
  cardId:           [String, Number],
  dealTitle:        String,
  date:             Date,
  availableInboxes: Array,   // [{id, email, provider, calendar_enabled}]
  cardContactEmail: String,
  cardContactName:  String,
});

const emit = defineEmits(['created', 'close']);
const { t } = useI18n();

const title              = ref('');
const description        = ref('');
const selectedInboxId    = ref(null);
const selectedTime       = ref('09:00');
const pickedDate         = ref(props.date || new Date());
const duration           = ref(60);
const reminderMinutes    = ref(15);
const guests             = ref([]);
const isLoading          = ref(false);
const error              = ref('');

// Pre-fill card contact
watch(() => props.cardContactEmail, (email) => {
  if (email && !guests.value.find(g => g.email === email)) {
    guests.value = [{ email, name: props.cardContactName || '' }, ...guests.value];
  }
}, { immediate: true });

const calendarInboxes = computed(() =>
  (props.availableInboxes || []).filter(i => i.calendar_enabled)
);

// F17: provider label via i18n keys
const providerLabel = computed(() => {
  const inbox = calendarInboxes.value.find(i => i.id === selectedInboxId.value);
  if (!inbox) return '';
  return inbox.provider === 'microsoft'
    ? t('CRM_KANBAN.PROVIDERS.TEAMS')
    : t('CRM_KANBAN.PROVIDERS.GOOGLE_MEET');
});

// F12: require at least one email-reachable guest
const canSave = computed(() =>
  title.value.trim() &&
  selectedInboxId.value &&
  guests.value.some(g => g.email.trim())
);

const onConfirm = async () => {
  if (!canSave.value) return;
  isLoading.value = true;
  error.value = '';

  const [h, m] = selectedTime.value.split(':').map(Number);
  const startsAt = new Date(pickedDate.value);
  startsAt.setHours(h, m, 0, 0);
  const endsAt = new Date(startsAt.getTime() + duration.value * 60000);

  try {
    // F14: use real API module; F8: send ISO8601 with timezone offset
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const { data } = await crmMeetingsAPI.createMeeting({
      cardId:  props.cardId,
      inboxId: selectedInboxId.value,
      meeting: {
        title:                   title.value.trim(),
        description:             description.value.trim(),
        // F8: ISO8601 with offset
        starts_at:               startsAt.toISOString(),
        ends_at:                 endsAt.toISOString(),
        timezone:                tz,
        reminder_minutes_before: reminderMinutes.value,
        extra_guests:            guests.value.filter(g => g.email.trim()).map(g => g.email.trim()),
      },
    });
    emit('created', data.payload);
    emit('close');
  } catch (e) {
    error.value = e.response?.data?.error || t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.ERROR');
  } finally {
    isLoading.value = false;
  }
};
</script>
```

#### 4.1.12 P1 Frontend: Calendar Event Rendering

**File:** `app/javascript/dashboard/routes/dashboard/crm/components/calendar/calendarEvents.js`

Add `meeting` overlay group and event type meta:

```javascript
export const OVERLAY_GROUP = {
  // ... existing
  MEETING: 'meeting',
};

export const EVENT_TYPE_META = {
  // ... existing
  meeting: {
    group:      'meeting',
    icon:       'i-lucide-video',
    dotClass:   'bg-n-blue-9',
    textClass:  'text-n-blue-11',
    pillClass:  'bg-n-blue-9/10 text-n-blue-11',
    overlayKey: 'meetings',
  },
};
```

**File:** `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendar.vue`

Add `meetings` to overlays ref and add the toggle button:

```javascript
const overlays = ref({ reminders: true, whatsapp: true, closeDates: true, meetings: true });
```

#### 4.1.13 P1 Backend: ReminderNotifier + Mailer for Meeting Type (F16)

**File:** `app/services/crm/follow_ups/reminder_notifier.rb` (MODIFIED)

Add handling for `follow_up_type == :meeting`:

```ruby
# In Crm::FollowUps::ReminderNotifier#notify (or #build_notification_payload):

def build_notification_payload
  base_payload = {
    follow_up_id: follow_up.id,
    title:        follow_up.title,
    due_at:       follow_up.due_at&.iso8601,
    card_id:      follow_up.card_id,
  }

  if follow_up.follow_up_type.to_sym == :meeting && follow_up.meeting.present?
    meeting = follow_up.meeting
    # F16: include join-link CTA and meeting-specific fields
    base_payload.merge!(
      meeting_id:         meeting.id,
      meeting_title:      meeting.title,
      # F8: render start time in meeting timezone
      meeting_starts_at:  meeting.starts_at.in_time_zone(meeting.timezone).iso8601,
      online_meeting_url: meeting.online_meeting_url,
      online_meeting_type: meeting.online_meeting_type,
      cta_label:          I18n.t('crm.meetings.reminder.join_cta'),
      cta_url:            meeting.online_meeting_url,
    )
  end

  base_payload
end
```

**File:** `app/mailers/crm/follow_up_reminder_mailer.rb` (MODIFIED)

Add meeting-specific rendering:

```ruby
# In Crm::FollowUpReminderMailer#reminder_email (extend existing):

def reminder_email(follow_up_id)
  @follow_up = Crm::FollowUp.includes(:meeting).find(follow_up_id)
  @account   = @follow_up.account
  @card      = @follow_up.card

  if @follow_up.follow_up_type.to_sym == :meeting && @follow_up.meeting.present?
    @meeting = @follow_up.meeting
    # F8: render start time in the meeting's timezone
    @meeting_starts_at = @meeting.starts_at.in_time_zone(@meeting.timezone)
    @join_url          = @meeting.online_meeting_url
    # F16: use meeting-specific subject and template
    mail(
      to:      @follow_up.created_by.email,
      subject: I18n.t('crm.meetings.reminder.email_subject',
                       title: @meeting.title,
                       time: I18n.l(@meeting_starts_at, format: :short))
    ) do |format|
      format.html { render 'crm/follow_up_reminder_mailer/meeting_reminder' }
    end
  else
    # existing non-meeting reminder flow
    mail(to: @follow_up.created_by.email, subject: @follow_up.title) do |format|
      format.html { render 'crm/follow_up_reminder_mailer/reminder_email' }
    end
  end
end
```

New mailer view (referenced above):
- **File:** `app/views/crm/follow_up_reminder_mailer/meeting_reminder.html.erb` (NEW) — renders meeting title, formatted start time in meeting timezone, join-link CTA button.

#### 4.1.14 P1 i18n Keys

**File:** `config/locales/en.yml` (under `crm:`):

```yaml
crm:
  # F17: i18n provider labels (used by Channel::Email#calendar_provider_label and FE)
  providers:
    teams:       'Microsoft Teams'
    google_meet: 'Google Meet'
  oauth:
    google_calendar_requires_own_app: 'Calendar requires a per-account GCP app. Configure your own OAuth credentials in Inbox Settings.'
  meetings:
    scheduled:        'Meeting scheduled: %{title}'
    reminder:
      join_cta:       'Join meeting'
      email_subject:  'Reminder: %{title} at %{time}'
    activity_created: 'Meeting scheduled by %{agent}'
    errors:
      calendar_not_enabled:       'Calendar not enabled for this inbox'
      no_calendar_inboxes:        'No calendar-enabled inboxes found'
      token_expired:              'Calendar authorization expired. Re-connect the inbox.'
      guest_email_invalid:        'Invalid guest email: %{email}'
      creation_failed:            'Failed to create meeting on %{provider}: %{error}'
      no_email_reachable_guest:   'At least one email-reachable guest is required (contact email or extra guest email)'
```

**File:** `app/javascript/dashboard/i18n/locale/en/crm.json` (add under `CRM_KANBAN`):

```json
"PROVIDERS": {
  "TEAMS": "Microsoft Teams",
  "GOOGLE_MEET": "Google Meet"
},
"CALENDAR": {
  "MEETING_SCHEDULER": {
    "TITLE": "Schedule Meeting",
    "DEAL": "Deal: {deal}",
    "TITLE_LABEL": "Meeting title",
    "TITLE_PLACEHOLDER": "e.g. Product demo",
    "DESCRIPTION_LABEL": "Description (optional)",
    "MAILBOX_LABEL": "Send from",
    "MAILBOX_PLACEHOLDER": "Select mailbox…",
    "PROVIDER_LABEL": "Video conference",
    "TIME_LABEL": "Start time",
    "DURATION_LABEL": "Duration",
    "REMINDER_LABEL": "Remind me",
    "GUESTS_LABEL": "Guests",
    "GUEST_EMAIL_PLACEHOLDER": "email@example.com",
    "ADD_GUEST": "Add guest",
    "SCHEDULE": "Schedule meeting",
    "SUCCESS": "Meeting scheduled and invitations sent",
    "ERROR": "Could not schedule meeting. Try again."
  },
  "QUICK_ADD": {
    "MEETING": "Meeting"
  },
  "OVERLAY": {
    "MEETINGS": "Meetings"
  },
  "EVENT": {
    "JOIN_MEETING": "Join meeting",
    "COPY_LINK": "Copy link"
  }
}
```

**File:** `app/javascript/dashboard/i18n/locale/pt_BR/crm.json` (parity):

```json
"PROVIDERS": {
  "TEAMS": "Microsoft Teams",
  "GOOGLE_MEET": "Google Meet"
},
"CALENDAR": {
  "MEETING_SCHEDULER": {
    "TITLE": "Agendar Reunião",
    "DEAL": "Negócio: {deal}",
    "TITLE_LABEL": "Título da reunião",
    "TITLE_PLACEHOLDER": "ex. Demonstração do produto",
    "DESCRIPTION_LABEL": "Descrição (opcional)",
    "MAILBOX_LABEL": "Enviar de",
    "MAILBOX_PLACEHOLDER": "Selecione a caixa de entrada…",
    "PROVIDER_LABEL": "Videoconferência",
    "TIME_LABEL": "Horário de início",
    "DURATION_LABEL": "Duração",
    "REMINDER_LABEL": "Lembrete",
    "GUESTS_LABEL": "Convidados",
    "GUEST_EMAIL_PLACEHOLDER": "email@exemplo.com",
    "ADD_GUEST": "Adicionar convidado",
    "SCHEDULE": "Agendar reunião",
    "SUCCESS": "Reunião agendada e convites enviados",
    "ERROR": "Não foi possível agendar a reunião. Tente novamente."
  },
  "QUICK_ADD": {
    "MEETING": "Reunião"
  },
  "OVERLAY": {
    "MEETINGS": "Reuniões"
  },
  "EVENT": {
    "JOIN_MEETING": "Entrar na reunião",
    "COPY_LINK": "Copiar link"
  }
}
```

#### 4.1.15 P1 Acceptance Criteria

- [ ] Admin can toggle `calendar_enabled` on a Google or Microsoft email inbox
- [ ] OAuth re-consent flow forces `access_type=offline&prompt=consent` (Google) / includes `offline_access` (Microsoft) and sets `calendar_enabled = true`; existing refresh_token never nullified
- [ ] Google re-consent is blocked when using global credentials; agent sees the own-app requirement message
- [ ] Agent can open "Schedule Meeting" from a card with a calendar-enabled inbox
- [ ] Scheduler modal shows only calendar-enabled inboxes; provider label uses i18n key
- [ ] Meeting requires at least one email-reachable guest (contact email or extra guest email)
- [ ] Input is sanitized (title/guest names strip CRLF/control chars; description HTML stripped) before provider call
- [ ] Provider API call is OUTSIDE the transaction; meeting persisted as :draft first
- [ ] On provider failure meeting is marked :failed; error surfaced to agent
- [ ] Scheduling a meeting via Google sends a native .ics invite with a Meet link to all guests
- [ ] Scheduling a meeting via Microsoft sends a native .ics invite with a Teams link to all guests; 403 → no Teams license error shown
- [ ] Meeting appears in CRM calendar view under the meetings overlay
- [ ] A `Crm::FollowUp` reminder (EXISTING follow_up_type: :meeting, value 3) fires X minutes before the meeting via push + email with join-link CTA
- [ ] Mailer renders start time in the meeting's own timezone
- [ ] Meeting creation logs an activity in the card's primary conversation timeline (via `app/services/crm/activity_logger.rb`)
- [ ] Agent without admin role cannot see meetings on cards they cannot see
- [ ] `external_event_id` never returned in the API response (server-side only)

---

## 4.2 Phase 2 (P2): Free/Busy, Reschedule, Cancel, External Events

### 4.2.1 P2 Services

**File:** `app/services/calendar/free_busy_service.rb` (NEW)

```ruby
class Calendar::FreeBusyService
  def initialize(inbox:, start_date:, end_date:, account:)
    @inbox      = inbox
    @start_date = start_date
    @end_date   = end_date
    @account    = account
  end

  def available_slots(duration_minutes = 30)
    cached = fetch_from_cache
    slots  = cached || fetch_from_provider
    cache_slots(slots) unless cached
    slots.reject { |s| s[:busy] || s[:duration_minutes] < duration_minutes }
  end

  def busy_times
    (fetch_from_cache || fetch_from_provider).select { |s| s[:busy] }
  end

  private

  def fetch_from_provider
    channel = @inbox.channel
    if channel.microsoft?
      Microsoft::FreeBusyService.new(channel: channel, account: @account)
                                .fetch(@start_date, @end_date)
    elsif channel.google?
      Google::FreeBusyService.new(channel: channel, account: @account)
                             .fetch(@start_date, @end_date)
    else
      []
    end
  end

  def fetch_from_cache
    rec = Crm::MailboxAvailability.find_by(
      account_id: @account.id,
      inbox_id:   @inbox.id,
      date:       @start_date.to_date
    )
    return nil unless rec && rec.last_synced_at > 4.hours.ago
    rec.availability_json['slots']
  end

  def cache_slots(slots)
    Crm::MailboxAvailability.upsert(
      { account_id: @account.id, inbox_id: @inbox.id, date: @start_date.to_date,
        availability_json: { slots: slots }, last_synced_at: Time.current },
      unique_by: %i[account_id inbox_id date]
    )
  end
end
```

**File:** `app/services/microsoft/free_busy_service.rb` (NEW) — calls `POST /me/calendar/getSchedule` (availabilityViewInterval: 30)

**File:** `app/services/google/free_busy_service.rb` (NEW) — calls `POST /calendar/v3/freeBusy`

**File:** `app/services/calendar/reschedule_service.rb` (NEW)

**F18 — Reschedule semantics:** In-place update (PATCH to Graph `/me/events/{id}` or Google `/calendar/v3/calendars/primary/events/{id}` with `sendUpdates: all`). The `external_event_id` stays the same; only start/end/title are updated. The local `Crm::Meeting` is updated in place and the linked `Crm::FollowUp.due_at` is adjusted. No new meeting record is created for a reschedule.

**File:** `app/services/calendar/cancel_service.rb` (NEW) — DELETE to provider; marks meeting `status: :canceled`; sets linked FollowUp `status: :canceled`; logs activity

### 4.2.2 P2 External Events (F24)

**F24:** External-events fetch is bounded to the current calendar view window; results capped at `$top=100` (Microsoft) / `maxResults=100` (Google) per request. Do NOT fetch unbounded event lists.

```ruby
# In Microsoft::ExternalEventsService (P2 NEW):
# GET /me/calendarView?startDateTime={from}&endDateTime={to}&$top=100&$select=id,subject,start,end,isOnlineMeeting

# In Google::ExternalEventsService (P2 NEW):
# GET /calendar/v3/calendars/primary/events?timeMin={from}&timeMax={to}&maxResults=100&singleEvents=true
```

### 4.2.3 P2 Endpoints

```
GET  /api/v1/accounts/:id/crm/calendar/available_slots
POST /api/v1/accounts/:id/crm/meetings/:id/reschedule
DELETE /api/v1/accounts/:id/crm/meetings/:id
GET  /api/v1/accounts/:id/crm/calendar/events (extended to include read-only external events)
```

### 4.2.4 P2 External Events Read-Only in CRM Calendar

Fetch organizer's external events from provider and include them in the calendar event payload as `event_type: 'external'` with `editable: false`. Displayed in the calendar with a muted style. Only the agent's own calendar events; admin sees all agents' external events. Cached aggressively (1 hour).

### 4.2.5 P2 Acceptance Criteria

- [ ] Availability picker shows free slots from the selected inbox's calendar
- [ ] Rescheduling a meeting updates the external event in place and re-sends the invite (no new event created)
- [ ] Canceling a meeting sends a cancellation notice to all guests; FollowUp status set to :canceled
- [ ] Linked `Crm::FollowUp` reminder due_at is updated when meeting is rescheduled
- [ ] Agent's external calendar events appear read-only in CRM calendar view (bounded to view window, max 100)
- [ ] Cache invalidation on manual refresh

---

## 4.3 Phase 3 (P3): Booking Page, Two-Way Sync, Outcomes, No-Show, AI

### 4.3.1 P3 Services

**File:** `app/services/calendar/public_booking_service.rb` — creates meeting from unauthenticated booking; finds-or-creates contact; creates lead card using `default_pipeline`/`default_stage`/`default_assignee` from `Crm::AgentBookingProfile` (F19); sends confirmation email

**File:** `app/services/calendar/public_available_slots.rb` — computes available slots for public page (respects working hours, buffer_minutes, booking_window_days)

**File:** `app/services/calendar/record_outcome_service.rb` — records held/no_show/rescheduled on `Crm::Meeting`; logs to card activity; optionally triggers AI summary job

**File:** `app/services/crm/ai/suggest_meeting_time_service.rb` — GPT-4o-mini: suggests 3 best times from free/busy + deal context

**File:** `app/services/crm/ai/draft_invite_service.rb` — GPT-4o-mini: drafts meeting invite description from deal context

**File:** `app/jobs/crm/ai/summarize_meeting_job.rb` — Sidekiq job: after outcome = held, summarize from notes/transcript; append to `outcome_notes`

### 4.3.2 P3 Two-Way Sync

**F20 (delta tokens in `crm_calendar_sync_states`):**
- Microsoft: Graph API change notifications (`POST /subscriptions`) → webhook receiver at `/webhooks/microsoft/calendar`; subscription_id + delta token stored in `Crm::CalendarSyncState`
- Google: Push Notifications (`POST /calendar/v3/channels/watch`) → webhook receiver at `/webhooks/google/calendar`; channel_id + syncToken stored in `Crm::CalendarSyncState`
- Both: idempotency via `external_event_id`; delta tokens stored in `crm_calendar_sync_states.delta_token` (NOT in crm_mailbox_availabilities)
- Conflict resolution: provider wins on external changes; log both states in `metadata`

### 4.3.3 P3 Public Booking Page

**Route:** `/book/:slug` (no authentication required)

- Slug = UUID-based (hard to guess); admin can disable
- Rate-limit: 10 requests/min per IP (Rack::Attack)
- CAPTCHA on form submission
- Email confirmation required before meeting is confirmed
- Creates `Crm::Card` using `Crm::AgentBookingProfile#default_pipeline` + `#default_stage` + `#default_assignee` (F19)
- Creates `Crm::Meeting` + `Crm::MeetingGuest`

### 4.3.4 P3 Acceptance Criteria

- [ ] Agent can set up a public booking profile with slug + default pipeline/stage/assignee
- [ ] Public booking page shows available slots without authentication
- [ ] Booking creates a lead card (with default pipeline/stage/assignee) + meeting + sends confirmation email
- [ ] External RSVP changes sync back to `Crm::MeetingGuest.rsvp_status`
- [ ] Agent can mark meeting as held/no_show/rescheduled after it occurs
- [ ] AI suggests 3 meeting times when requested
- [ ] No-show rate is visible in CRM analytics dashboard

---

## 5. Security & Permissions

### 5.1 Pundit Policies

**File:** `app/policies/crm/meeting_policy.rb` (NEW)

```ruby
class Crm::MeetingPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    visible_scope.exists?(id: record.id)
  end

  def create?
    account_user.present? && visible_card_scope.exists?(id: record.card_id)
  end

  def update?
    show? && (account_user.administrator? || record.scheduled_by_id == user.id)
  end

  alias reschedule? update?
  alias cancel?     update?
  alias destroy?    update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Transitive card visibility: agents see meetings on cards they can see
      visible_card_ids = Pundit.policy_scope!(user_context, Crm::Card).select(:id)
      scope.where(account_id: account.id, card_id: visible_card_ids)
    end
  end

  private

  def visible_scope
    Pundit.policy_scope!(user_context, Crm::Meeting)
  end

  def visible_card_scope
    Pundit.policy_scope!(user_context, Crm::Card)
  end
end

Crm::MeetingPolicy.prepend_mod_with('Crm::MeetingPolicy')
```

**File:** `enterprise/app/policies/crm/meeting_policy.rb` (EE overlay)

```ruby
# F4 (verified fact 4): CrmPermissions is at enterprise/app/policies/crm_permissions.rb
module Enterprise::Crm::MeetingPolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_view_deals') || crm_permission?('crm_edit_deals')
  end

  def create?
    crm_permission?('crm_edit_deals') && super
  end

  def update?
    crm_permission?('crm_edit_deals') && super
  end
end
```

### 5.2 Admin-Sees-All Pattern

The `Crm::MeetingPolicy::Scope` inherits card visibility from `Crm::CardPolicy::Scope`. Admins see all cards → all meetings. Custom role `crm_view_deals` = see, `crm_edit_deals` = create/reschedule/cancel.

### 5.3 Calendar Toggle Authorization (Admin Only)

The inbox `calendar_enabled` toggle is admin-only:

```ruby
# In InboxSettingPolicy (extend existing):
def toggle_calendar?
  account_user.administrator?
end
```

Frontend: hide the toggle from non-admin agents.

### 5.4 Token Security

- Tokens stored in `provider_config` JSONB (existing, encrypted via `Chatwoot.encryption_configured?`)
- Never log tokens; use `[FILTERED]` in Rails logger
- Token refresh runs in the request thread with a 5-minute expiry buffer
- On 401 from provider: refresh once, retry; if still 401, raise and surface re-auth UI to agent
- Microsoft: GraphTokenService handles resource-scoped token exchange; 403 = no Teams license (surfaced to agent); 429 = backoff + retry
- Google: CalendarAccessTokenService follows BaseRefreshOauthTokenService; no scope: param on refresh

### 5.5 Input Sanitization

**File:** `app/services/crm/meetings/sanitizer.rb` (NEW — see §4.1.5)

- Called as the FIRST step of `Creator#perform` (F10)
- Sanitize `title` (strip CRLF/control chars, max 255 chars)
- Sanitize guest names (strip CRLF/control chars, cap 255) before sending to provider
- Sanitize `description` (strip HTML, max 5000 chars)
- Validate guest emails via `Mail::Address.new(email).address` (raises on invalid RFC 5322)
- Never trust externally-provided `.ics`; always generate via Graph/Calendar API

### 5.6 Google Verification Path

- `https://www.googleapis.com/auth/calendar` is a **Sensitive scope** requiring Google verification for public OAuth apps.
- **F9 — Blocked if using global credentials:** `EmailOauth::CredentialResolver` returns `source: 'global'` vs `source: 'account'`. Calendar re-consent is BLOCKED if `source == 'global'`; agent is directed to configure their own GCP project.
- **Strategy for P1:** Use per-account own-app (agent registers their GCP project; `AccountEmailOauthApp` pattern already exists). No verification audit needed.
- **Agent-facing copy (unverified app screen):** "Google may show an 'unverified app' warning during setup. Click 'Advanced' → 'Go to [your app name] (unsafe)' to proceed. This is expected for development/own-app setups. Before going live, complete Google OAuth verification."
- **Consumer Gmail limitation:** Personal Gmail accounts CANNOT use the Google Workspace-Internal app type (Workspace-Internal requires a Google Workspace organization). Personal Gmail users must use per-account own-app and complete Google OAuth verification before GA.
- **Strategy for P2/P3 (shared SaaS):** Either Workspace-Internal (no audit, Workspace orgs only) or complete Google OAuth verification (~2-3 weeks). Budget this before GA.

### 5.7 Public Booking Page Security (P3)

- Slug must be UUID-based (not guessable)
- Rack::Attack rate limit: 10 requests/min/IP on booking endpoints
- CAPTCHA (hCaptcha or similar) on form submission
- Email verification: send confirmation link; meeting confirmed only after link clicked
- No PII returned in booking page response (no agent email, no calendar details)
- CSRF token on form

---

## 6. cal13 Notification Reuse for Meeting Reminders

### 6.1 How cal13 Works (Existing Stack)

```
Crm::FollowUps::DueProcessor (Sidekiq, runs every minute)
    ↓ finds Crm::FollowUp where due_at <= now AND status = :pending
    ↓ calls Crm::FollowUps::ReminderNotifier.new(follow_up).notify
        ↓ push notification (Notification enum: crm_followup_reminder)
        ↓ popup notification (ActionCable broadcast)
        ↓ email (Crm::FollowUpReminderMailer)
```

### 6.2 Meeting Reminder Wiring (P1)

**Verified Fact 1:** `crm_follow_ups` ALREADY has `follow_up_type` (int), `automation_mode` (int), `status` (int), `timezone` (string). `Crm::FollowUp` enum `follow_up_type` ALREADY includes `meeting: 3`. NO migration and NO enum change needed for these columns.

When `Crm::Meetings::Creator` creates a meeting, it creates a linked `Crm::FollowUp` (inside the second transaction, after the provider call succeeds):

```ruby
Crm::FollowUp.create!(
  account:         @account,
  card:            @card,
  created_by:      @scheduled_by,
  title:           "Reunião em #{reminder_minutes} min: #{title}",
  due_at:          starts_at - reminder_minutes.minutes,
  timezone:        timezone,
  follow_up_type:  :meeting,    # EXISTING value 3 — already in the enum, NO migration needed
  automation_mode: :reminder_only,
  status:          :pending,
  meeting_id:      meeting.id
)
```

When the DueProcessor fires this FollowUp:
- `ReminderNotifier` fires push + email + popup
- For `follow_up_type == :meeting`: payload includes `meeting.online_meeting_url` as a CTA button, meeting title, and start time rendered in the meeting's timezone (F16, F8)
- The mailer renders meeting-specific template with join-link CTA (see §4.1.13)

### 6.3 Crm::FollowUp Model Changes (additive only)

`Crm::FollowUp` model changes are limited to:
1. Add `belongs_to :meeting, class_name: 'Crm::Meeting', optional: true` association
2. No enum changes — `follow_up_type: :meeting` (value 3) already exists

```ruby
# In Crm::FollowUp (app/models/crm/follow_up.rb) — add only:
belongs_to :meeting, class_name: 'Crm::Meeting', optional: true
```

### 6.4 Reminder Cancellation / Update on Reschedule

When a meeting is rescheduled (P2 — in-place update, F18):

```ruby
# Reminder due_at adjusted to new starts_at
meeting.reminder.update!(due_at: new_starts_at - reminder_minutes.minutes)
```

When a meeting is canceled:

```ruby
meeting.reminder.update!(status: :canceled)
```

**F23 — FK nullify:** If a `Crm::FollowUp` (reminder) is deleted directly (e.g., agent deletes the follow-up from the UI), `crm_meetings.reminder_id` is NULLified via the `on_delete: :nullify` FK defined in the migration. The meeting record is NOT deleted. Conversely, deleting a `Crm::Meeting` triggers `on_delete: :nullify` on `crm_follow_ups.meeting_id` (also defined in migration 4), so the FollowUp remains but loses its meeting reference.

---

## 7. Testing, Gates, Feature Flag & Rollback

### 7.1 Test Strategy

#### P1 Isolated Harness

```ruby
# spec/support/stubs/calendar_api_stubs.rb
module CalendarApiStubs
  def stub_microsoft_create_event(event_id: 'graph_event_123', join_url: 'https://teams.microsoft.com/...')
    instance = double('Microsoft::CalendarEventService')
    allow(Microsoft::CalendarEventService).to receive(:new).and_return(instance)
    allow(instance).to receive(:create).and_return(
      OpenStruct.new(external_event_id: event_id, online_meeting_url: join_url, provider: :microsoft)
    )
  end

  def stub_google_create_event(event_id: 'google_event_abc', join_url: 'https://meet.google.com/...')
    instance = double('Google::CalendarEventService')
    allow(Google::CalendarEventService).to receive(:new).and_return(instance)
    allow(instance).to receive(:create).and_return(
      OpenStruct.new(external_event_id: event_id, online_meeting_url: join_url, provider: :google)
    )
  end
end

RSpec.configure { |c| c.include CalendarApiStubs, :stub_calendar }
```

Key specs to write:

```
spec/
  models/
    crm/meeting_spec.rb           # validations, associations, scopes, email-reachable-guest validation
    crm/meeting_guest_spec.rb     # uniqueness, email presence
    channel/email_spec.rb         # calendar_enabled?, can_enable_calendar?
  services/
    crm/meetings/sanitizer_spec.rb  # title/name stripping, HTML description, invalid emails
    crm/meetings/creator_spec.rb    # F2 two-phase flow, provider-outside-txn, F12 guest validation,
                                    # F10 sanitizer called first, idempotency, activity log, reminder creation
    microsoft/calendar_event_service_spec.rb   # payload structure, 401 refresh+retry, 403 no-license, 429 backoff
    google/calendar_event_service_spec.rb      # payload structure, conferenceData, sendUpdates
    google/calendar_access_token_service_spec.rb  # F5 refresh flow (no scope param), F1 token preservation
  policies/
    crm/meeting_policy_spec.rb    # agent sees own, admin sees all, card visibility
  requests/
    api/v1/accounts/crm/meetings_spec.rb  # POST create happy path, auth errors, validation errors,
                                           # external_event_id NOT in response (F11)
  controllers/
    api/v1/accounts/crm/calendar_controller_spec.rb  # meeting_events appended, includes guest N+1 check
    oauth_callback_controller_spec.rb                 # F1 refresh_token preservation (see §4.1.1 test case)
```

#### P2 Real Test Mailbox (VCR/WebMock)

```ruby
RSpec.describe 'Calendar Integration', :vcr do
  it 'creates a Teams meeting and retrieves the join URL'
  it 'creates a Google Meet event and retrieves the Meet link'
  it 'fetches free/busy slots for a date range'
end
```

#### P3 Load/Abuse Tests (Public Booking Page)

- Verify rate limiting fires at 10 req/min/IP
- Verify CAPTCHA blocks headless browser submissions
- Verify no PII leakage in booking response

### 7.2 Per-Phase Gates

| Gate | Command / Check | Required For |
|------|---|---|
| **Migrations additive** | Review migration files: no DROP, no ALTER...DROP | All phases |
| **Eager load** | `bundle exec rails zeitwerk:check` | All phases |
| **Rubocop** | `bundle exec rubocop app/services/crm/meetings/ app/models/crm/meeting*.rb` | All phases |
| **ESLint 0** | `pnpm eslint --ext .vue,.js app/javascript/dashboard/routes/dashboard/crm/components/calendar/` | All phases |
| **i18n parity** | All keys in `en/crm.json` present in `pt_BR/crm.json`; all backend `en.yml` keys added | All phases |
| **Unit tests pass** | `bundle exec rspec spec/models/crm/meeting_spec.rb spec/services/crm/meetings/` | All phases |
| **Integration tests pass** | `bundle exec rspec spec/requests/api/v1/accounts/crm/meetings_spec.rb` | All phases |
| **Dual review** | 1 code review + 1 security/product review | All phases |
| **Explicit user OK** | User confirms deployment in writing | All phases |

### 7.3 Feature Flag (F27, F28)

**F27 — Per-account FlagShihTzu flag for staged rollout:**

```ruby
# app/models/account.rb (add to existing FlagShihTzu flag set):
flag :crm_calendar_meetings_enabled, 28  # Use next available bit
```

**F28 — `Crm::Config` is a MODIFIED file** (`app/services/crm/config.rb` already exists with `self.enabled?`). Add `self.calendar_meetings_enabled?`:

```ruby
# app/services/crm/config.rb (MODIFIED — add method to existing class)
module Crm
  class Config
    # Existing: def self.enabled? ... end

    # F27+F28: two-level gate — env var AND per-account flag
    def self.calendar_meetings_enabled?(account)
      return false unless ENV['CRM_CALENDAR_MEETINGS_ENABLED'].present?
      # F27: per-account FlagShihTzu flag for staged rollout
      account.crm_calendar_meetings_enabled?
    end
  end
end
```

Frontend: wrap calendar meeting UI in `v-if="store.featureFlags.crmCalendarMeetingsEnabled"`.

**Controller gate:**

```ruby
before_action :check_calendar_feature
def check_calendar_feature
  raise Pundit::NotAuthorizedError unless Crm::Config.calendar_meetings_enabled?(Current.account)
end
```

### 7.4 Rollback Strategy

**Fast rollback (no data loss):**

1. Set `CRM_CALENDAR_MEETINGS_ENABLED=` (empty) → env gate closes
2. Disable per-account flag: `account.update!(flags: account.flags & ~Account.flag_masks[:crm_calendar_meetings_enabled])`
3. Existing meetings remain in DB; rollback is reversible at any time
4. No migration rollback needed for additive columns

**If migration must be rolled back:**

```bash
bundle exec rails db:rollback STEP=4  # Reverses migrations 1-4 in reverse order
# crm_follow_ups.meeting_id → dropped (migration 4)
# channel_email calendar columns → dropped (migration 3)
# crm_meeting_guests → dropped (migration 2)
# crm_meetings → dropped (migration 1)
```

All migration `change` blocks are reversible. No data at risk.

---

## 8. Risks & Open Questions

### 8.1 Known Risks

| Risk | Severity | Mitigation |
|------|---|---|
| **Google sensitive scope verification** | High | Use per-account own-app for P1 (blocked at re-consent if global); plan 2-3 week verification before P2 SaaS GA |
| **Consumer Gmail / Workspace-Internal limitation** | High | Consumer Gmail cannot use Workspace-Internal; document clearly; require own-app or completed verification |
| **Shared mailbox without Teams license** | Medium | Document as limitation; warn in UI (F6: 403 surfaces a specific no-license error); recommend personal mailbox |
| **Token expiry during meeting creation** | Medium | Refresh with 5-min buffer; retry once on 401; surface re-auth UI if still fails |
| **Google 6-month refresh token invalidation** | Medium | Detect 401 on refresh; prompt re-authorization; F1: never nullify existing refresh token |
| **Provider rate limits on free/busy** | Low-Medium | Cache aggressively (4h); queue batch fetches async; monitor via error tracking |
| **Timezone mismatch / DST** | Medium | Always send provider-specified timezone string (IANA); F8: require ISO8601-with-offset from FE; test EST→EDT transition |
| **Concurrent meeting creation race** | Low | Unique constraint on `external_event_id` + `provider` guards duplicate creation; F2 idempotency skip |
| **Provider call failure between txn phases (F2)** | Low | Meeting persisted as :draft; on failure marked :failed; idempotency prevents double provider call on retry |
| **Public booking spam (P3)** | High | Rate limiting + CAPTCHA + email verification before confirming |
| **AI prompt injection via deal/contact data (P3)** | Medium | Sanitize inputs before AI call; never send raw user input as system prompt |
| **Transcript/recording access (P3)** | High complexity | Defer to P4; stub the `fetch_meeting_transcript` service returning nil for now |

### 8.2 Open Questions (Require Product Decision)

1. **Shared mailbox Teams license check:** Should we detect and hard-block, or just warn? Recommend: warn with a yellow banner (F6 surfaces 403 as specific error); do not block at creation time.
2. **Reminder configurability scope:** Per-meeting (current P1 design) or per-inbox setting (global default)? Recommend: per-meeting with a sensible default from an account-level setting.
3. **Multi-mailbox scenarios:** If an agent has 2 calendar-enabled inboxes, what is the default? Recommend: inbox linked to card's primary conversation; fallback to agent's first calendar-enabled inbox.
4. **Google Meet availability without Google Workspace:** Personal Gmail accounts can create Meet links. Microsoft Teams requires a Teams license. Recommend: attempt and surface provider error as a user-friendly message (F6).
5. **P3 AI cost and consent:** Who pays for the GPT-4o-mini calls? Recommend: use the account's own OpenAI API key; AI features disabled if no key configured.
6. **Meeting outcome flow (P3):** Manual for P3 (agent marks outcome after the meeting); auto-detection deferred to P4.

---

## 9. Complete File Inventory

### 9.1 New Files

**Backend:**
- `db/migrate/20260620000001_create_crm_meetings.rb`
- `db/migrate/20260620000002_create_crm_meeting_guests.rb`
- `db/migrate/20260620000003_add_calendar_capability_to_channel_email.rb`
- `db/migrate/20260620000004_add_meeting_to_crm_follow_ups.rb`
- `db/migrate/20260630000001_create_crm_mailbox_availability.rb` (P2)
- `db/migrate/20260701000001_create_crm_agent_booking_profiles.rb` (P3)
- `db/migrate/20260701000002_create_crm_calendar_sync_states.rb` (P3 — F20: delta tokens)
- `app/models/crm/meeting.rb`
- `app/models/crm/meeting_guest.rb`
- `app/services/google/calendar_access_token_service.rb`
- `app/services/google/calendar_event_service.rb`
- `app/services/google/free_busy_service.rb` (P2)
- `app/services/microsoft/calendar_event_service.rb`
- `app/services/microsoft/free_busy_service.rb` (P2)
- `app/services/crm/meetings/creator.rb`
- `app/services/crm/meetings/sanitizer.rb`
- `app/services/calendar/free_busy_service.rb` (P2)
- `app/services/calendar/reschedule_service.rb` (P2)
- `app/services/calendar/cancel_service.rb` (P2)
- `app/services/calendar/public_booking_service.rb` (P3)
- `app/services/calendar/public_available_slots.rb` (P3)
- `app/services/calendar/record_outcome_service.rb` (P3)
- `app/services/crm/ai/suggest_meeting_time_service.rb` (P3)
- `app/services/crm/ai/draft_invite_service.rb` (P3)
- `app/jobs/crm/ai/summarize_meeting_job.rb` (P3)
- `app/controllers/api/v1/accounts/crm/meetings_controller.rb`
- `app/policies/crm/meeting_policy.rb`
- `enterprise/app/policies/crm/meeting_policy.rb`
- `app/javascript/dashboard/api/crmMeetings.js` (F14: real API module, ApiClient subclass)
- `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarMeetingScheduler.vue`
- `app/views/crm/follow_up_reminder_mailer/meeting_reminder.html.erb` (F16)
- `spec/models/crm/meeting_spec.rb`
- `spec/models/crm/meeting_guest_spec.rb`
- `spec/services/crm/meetings/sanitizer_spec.rb`
- `spec/services/crm/meetings/creator_spec.rb`
- `spec/services/microsoft/calendar_event_service_spec.rb`
- `spec/services/google/calendar_event_service_spec.rb`
- `spec/services/google/calendar_access_token_service_spec.rb`
- `spec/policies/crm/meeting_policy_spec.rb`
- `spec/requests/api/v1/accounts/crm/meetings_spec.rb`
- `spec/factories/crm_meetings.rb`
- `spec/factories/crm_meeting_guests.rb`
- `spec/support/stubs/calendar_api_stubs.rb`

### 9.2 Modified Files

**Backend:**
- `app/services/microsoft/scopes.rb` — add `GRAPH_WITH_CALENDAR` constant (F7)
- `app/services/crm/config.rb` — **MODIFIED** (existing file); add `self.calendar_meetings_enabled?(account)` (F27, F28)
- `app/services/crm/activity_logger.rb` — **existing** at this path (F29); no changes needed; cited for reference
- `app/controllers/concerns/google_concern.rb` — extend `#scope` + `#authorization_params` for calendar (F1, F9)
- `app/controllers/concerns/microsoft_concern.rb` — extend `#scope` to use `GRAPH_WITH_CALENDAR` on calendar intent (F7)
- `app/controllers/oauth_callback_controller.rb` — persist `calendar_enabled`; preserve existing refresh_token (F1)
- `app/controllers/api/v1/accounts/crm/calendar_controller.rb` — append `meeting_events` with `.includes(:meeting_guests)` (F15)
- `app/models/channel/email.rb` — add `calendar_enabled?`, `can_enable_calendar?`, `calendar_organizer_email`, `calendar_provider_label` (i18n, F17)
- `app/models/crm/card.rb` — add `has_many :meetings, class_name: 'Crm::Meeting'`
- `app/models/crm/follow_up.rb` — add `belongs_to :meeting, optional: true` (NO enum changes — meeting:3 already exists)
- `app/models/account.rb` — add FlagShihTzu flag `crm_calendar_meetings_enabled` (F27)
- `app/services/crm/follow_ups/reminder_notifier.rb` — handle `follow_up_type == :meeting` with join-link CTA, meeting title, timezone-aware start time (F16)
- `app/mailers/crm/follow_up_reminder_mailer.rb` — add meeting-specific rendering with `starts_at.in_time_zone(meeting.timezone)` (F16, F8)
- `config/locales/en.yml` — add `crm.meetings.*`, `crm.providers.*`, `crm.oauth.*` keys (F17)
- `config/routes.rb` — add crm/meetings route

**Frontend:**
- `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarQuickAdd.vue` — unlock meeting type; use i18n key (F17)
- `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendar.vue` — add meetings overlay
- `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarEventPopover.vue` — add meeting actions
- `app/javascript/dashboard/routes/dashboard/crm/components/calendar/calendarEvents.js` — add meeting event type meta
- `app/javascript/dashboard/i18n/locale/en/crm.json` — add MEETING_SCHEDULER, PROVIDERS, OVERLAY.MEETINGS, EVENT keys
- `app/javascript/dashboard/i18n/locale/pt_BR/crm.json` — parity for all new keys

---

## Appendix: Key API Reference

### Microsoft Graph: Create Calendar Event

```
POST https://graph.microsoft.com/v1.0/me/events
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "subject": "Meeting Title",
  "start": { "dateTime": "2026-07-01T14:00:00", "timeZone": "America/Sao_Paulo" },
  "end":   { "dateTime": "2026-07-01T15:00:00", "timeZone": "America/Sao_Paulo" },
  "attendees": [{ "emailAddress": { "address": "guest@example.com" }, "type": "required" }],
  "isOnlineMeeting": true,
  "onlineMeetingProvider": "teamsForBusiness"
}

Response 201: { "id": "...", "onlineMeeting": { "joinUrl": "https://teams.microsoft.com/..." } }
Required scope: https://graph.microsoft.com/Calendars.ReadWrite (included in GRAPH_WITH_CALENDAR)
```

### Google Calendar: Create Event with Meet

```
POST https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=all&conferenceDataVersion=1
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "summary": "Meeting Title",
  "start": { "dateTime": "2026-07-01T14:00:00", "timeZone": "America/Sao_Paulo" },
  "end":   { "dateTime": "2026-07-01T15:00:00", "timeZone": "America/Sao_Paulo" },
  "attendees": [{ "email": "guest@example.com" }],
  "conferenceData": { "createRequest": { "requestId": "uuid", "conferenceSolutionKey": { "type": "hangoutsMeet" } } }
}

Response 200: { "id": "...", "conferenceData": { "entryPoints": [{ "entryPointType": "video", "uri": "https://meet.google.com/..." }] } }
Required scope: https://www.googleapis.com/auth/calendar
```

### Microsoft Graph: Free/Busy (F24 — bound to view window, max 100)

```
POST https://graph.microsoft.com/v1.0/me/calendar/getSchedule
Authorization: Bearer {access_token}

{ "schedules": ["agent@company.com"], "startTime": { ... }, "endTime": { ... }, "availabilityViewInterval": 30 }

Response: availabilityView string where 0=free, 1=tentative, 2=busy, 3=OOO, 4=working elsewhere
```

### Google Calendar: Free/Busy (F24 — bound to view window, maxResults=100)

```
POST https://www.googleapis.com/calendar/v3/freeBusy
Authorization: Bearer {access_token}

{ "timeMin": "...", "timeMax": "...", "items": [{ "id": "agent@gmail.com" }] }

Response: { "calendars": { "agent@gmail.com": { "busy": [{ "start": "...", "end": "..." }] } } }
```

### External Events Fetch (P2, F24 — always bounded + capped)

```
# Microsoft — calendarView bounded to UI window, $top=100
GET https://graph.microsoft.com/v1.0/me/calendarView?startDateTime={from}&endDateTime={to}&$top=100&$select=id,subject,start,end,isOnlineMeeting

# Google — bounded to UI window, maxResults=100
GET https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin={from}&timeMax={to}&maxResults=100&singleEvents=true
```

---

**Document verdict: READY (v2, post-revision)**

---

## 10. UI/UX Design Specification (todas as fases)

> Princípio-mestre: **simples por padrão, poderoso quando preciso.** Cada tela reusa o design system existente (`components-next` + tokens `n-*` + ícones `i-lucide-*`/`i-logos-*`) para parecer nativa do CRM. Mockups de referência entregues no chat (agendador, detalhe, resultado+IA, booking público).

### 10.0 Princípios de simplicidade (aplicados em todas as fases)
- **Defaults inteligentes:** contato do negócio já entra como convidado; lembrete pré-selecionado em 15 min; link Meet/Teams gerado automaticamente; caixa pessoal do agente pré-selecionada; duração 30 min.
- **Divulgação progressiva:** o diálogo mostra só o essencial; "mais opções" (notas, mais lembretes, fuso de convidado) fica recolhido.
- **Zero ambiguidade de canal:** o provedor (Google/Microsoft) e o tipo de link (Meet/Teams) são **inferidos da caixa escolhida** — o usuário não escolhe API nenhuma.
- **Feedback imediato:** estados `draft → scheduled → failed` viram microcopy clara ("Agendando…", "Reunião criada", "Não consegui criar — tentar de novo").
- **Consistência:** chips de horário, fieldset/legend e densidade idênticos ao `CrmCalendarQuickAdd` já existente.

### 10.1 Estratégia de ícones e logos (Google / Microsoft / Teams / Meet)
O fork **já tem a coleção Iconify `logos`** habilitada no `tailwind.config.js` — usar direto, **sem assets custom**:

| Marca | Classe | Onde |
|---|---|---|
| Google | `i-logos-google-icon` | seletor de caixa, botão conectar agenda |
| Microsoft | `i-logos-microsoft-icon` | seletor de caixa, botão conectar agenda |
| Microsoft Teams | `i-logos-microsoft-teams` | badge "link gerado", botão Entrar |
| Google Meet | `i-logos-google-meet` | badge "link gerado", botão Entrar, chip no calendário |

Renderização padrão do fork: `<span class="i-logos-microsoft-teams size-4" />`. Provider/label de texto sempre via i18n (`crm.providers.teams`, `crm.providers.google_meet`) — nunca hardcoded (Finding F17). Cores de marca ficam **só** no glifo do logo; o resto da UI segue os tokens `n-*` (sem cor de marca em botões/bordas, para não brigar com o whitelabel).

### 10.2 FASE 1 — Criar (o agendador)
**Componente:** `CrmCalendarMeetingScheduler.vue` — reusa `Dialog.vue` (`width="md"`), `ComboBox.vue`, `Input.vue`, `Button.vue`, `Switch.vue`.

Layout (cima→baixo), espelhando o mockup:
1. **Cabeçalho** — título "Agendar reunião" + subtítulo `i-lucide-briefcase` "Negócio: <card>". (O vínculo ao negócio é obrigatório — F12.)
2. **Enviar de** — `ComboBox` das caixas com agenda habilitada que o agente acessa; cada opção = logo do provedor (`i-logos-*`) + e-mail + tag "pessoal/departamento". Pré-seleciona a pessoal.
3. **Convidados** — chips removíveis; o contato do card já vem preenchido (chip com avatar + tag "contato"); input "adicionar convidado" valida e-mail. Pelo menos 1 e-mail-alcançável (F12).
4. **Data + Duração** — pill de data (date-picker nativo) + `ComboBox` de duração (15/30/45/60).
5. **Horário** — chips de preset (mesmo padrão do quick-add) + "outro"; abaixo, **linha de IA** (`i-lucide-sparkles`, cor `n-iris/n-blue`) com 3 horários sugeridos do free/busy (P2+; some na P1 se sem free/busy).
6. **Link de vídeo** — linha read-only: logo Meet/Teams (conforme provedor da caixa) + "gerado automaticamente" (badge `success`) + check. Toggle off opcional ("sem vídeo").
7. **Lembrete** — "Lembrar 15 min antes (push + e-mail)" com chevron p/ ajustar (reusa cal13).
8. **Rodapé** — microcopy "convite .ics enviado aos convidados" + `Cancelar` + `Agendar e convidar` (solid brand; `disableConfirmButton` até válido).

**Estados:** `Agendando…` (botão `isLoading`), sucesso (fecha + toast "Reunião criada" + chip aparece no calendário em realtime, reusando o `syncCalendarIfActive` da cal12), **falha do provedor** (banner inline ruby "Não consegui criar no <provedor> — tentar de novo", meeting fica `failed`, sem reunião-fantasma — F2). Validação inline (sem e-mail-alcançável → ajuda "adicione um convidado com e-mail").

**Entradas:** botão **"Reunião"** no `CrmCalendarQuickAdd` (hoje placeholder `soon`) **e** botão "Agendar" no drawer do card (aba Follow-ups/nova aba "Reuniões").

### 10.3 FASE 1 — Acompanhar (calendário + detalhe)
- **Chip no calendário:** novo overlay `meeting` no `CrmCalendarMonthGrid` — dot + `i-logos-google-meet`/`i-logos-microsoft-teams` (size-3.5) + hora + título; cor de fundo `n-iris-9/10` (distinta de reminder-teal/whatsapp-blue/close-amber). Filtro novo "Reuniões" na barra (junto de Lembretes/WhatsApp/Previsões).
- **Card de detalhe** (`Popover`/drawer, ver mockup): logo do provedor + título + "em 2h"; horário no **fuso do usuário**; lista de convidados com **status de resposta** (aceitou `success`/aguardando `tertiary`); botão grande **Entrar no Teams/Meet** (cor da marca, exceção controlada); rodapé com lembrete + **Reagendar**/**Cancelar** (ruby).
- **Realtime:** criar/cancelar/reagendar atualiza o calendário sem refresh (reusa o padrão cal12).

### 10.4 FASE 2 — Disponibilidade & gestão
- **Free/busy no horário:** chips de horário ocupados ficam `disabled` (riscado/`n-slate-7`) com tooltip "ocupado"; a linha da IA prioriza slots livres. Indicador de fuso explícito.
- **Reagendar:** reabre o agendador com os campos preenchidos; ao salvar, faz `PATCH` no evento externo (mesmo `external_event_id`), reenvia convite, atualiza o lembrete (F18 — update in-place).
- **Cancelar:** confirma em `Dialog type="alert"`; `DELETE` no evento + notifica convidados + nullify do lembrete.
- **Eventos externos (read-only):** a agenda real do agente aparece no calendário do CRM em estilo **mudo/hachurado** (`n-alpha-1`, sem ações) p/ contexto, claramente separada das reuniões do CRM.

### 10.5 FASE 3 — Resultados com IA + Booking público
- **Registrar resultado** (ver mockup): após o horário, o card/calendário oferece "Como foi a reunião?" com 3 botões — **Aconteceu** (`success`), **Reagendou** (`slate`), **Não compareceu** (`danger`, no-show). 1 clique.
- **Resumo da IA:** bloco `i-lucide-sparkles` com resumo + **próximos passos** (checkboxes) gerados de notas/transcrição; CTA "Criar follow-up para quinta 09:00?" (1 clique → reusa o agendador/lembrete). Tudo logado na **timeline do card** (`Crm::ActivityLogger`).
- **IA no agendador:** "Sugerir horários" (3 chips do free/busy) e "Redigir convite" (preenche a descrição) — opcionais, recolhidos.
- **Página de booking pública** (ver mockup, estilo Calendly): cabeçalho do agente (avatar + "Conversa de 30 min"), mini-calendário, **slots livres reais** (free/busy), confirmação em 1 passo → cria o card no CRM + convite + link Meet/Teams. Rota pública com slug UUID, rate-limit + verificação de e-mail (F: hardening).

### 10.6 Acessibilidade, responsivo e i18n
- **A11y:** `Dialog` já entrega foco/escape/aria; chips de convidado removíveis por teclado; botão "Entrar" com `aria-label`; logos decorativos com `aria-hidden`; estados de erro com `role="alert"`.
- **Responsivo:** abaixo de `md`, o agendador vira full-screen (padrão do `Dialog`); booking público é mobile-first (calendário em cima, slots embaixo).
- **i18n:** todas as strings em `en/crm.json` + `pt_BR/crm.json` sob `CRM_KANBAN.CALENDAR.MEETING_*` e `crm.providers.*` (paridade obrigatória). Datas/horas via `date-fns` no fuso do usuário/convidado.
- **Whitelabel:** nenhuma string "Chatwoot/Captain/WAHA"; nomes de marca (Teams/Meet/Google/Microsoft) só nos glifos `i-logos-*` e em labels i18n próprias.

### 10.7 Novos arquivos de UI (acrescentar ao §9)
`CrmCalendarMeetingScheduler.vue` (agendador), `CrmMeetingDetail.vue` (card/popover de detalhe), `CrmMeetingOutcome.vue` (resultado + IA), overlay `meeting` em `CrmCalendarMonthGrid.vue` + filtro no header, `api/crmMeetings.js`, e (P3) `public/booking/*` (página pública standalone). i18n keys em `en/crm.json` + `pt_BR/crm.json`.
