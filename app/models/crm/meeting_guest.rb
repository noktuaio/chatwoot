class Crm::MeetingGuest < ApplicationRecord
  self.table_name = 'crm_meeting_guests'

  belongs_to :account
  belongs_to :meeting, class_name: 'Crm::Meeting', inverse_of: :meeting_guests
  belongs_to :contact, optional: true
  belongs_to :user, optional: true

  enum guest_type: { contact_guest: 0, external_email: 1, internal_user: 2 }
  enum rsvp_status: { rsvp_pending: 0, rsvp_accepted: 1, rsvp_declined: 2, rsvp_tentative: 3 }

  validates :email, :guest_type, presence: true
  validates :account_id, :meeting_id, presence: true
  validates :email, uniqueness: { scope: [:account_id, :meeting_id] }
  validates :metadata, jsonb_attributes_length: true
end
