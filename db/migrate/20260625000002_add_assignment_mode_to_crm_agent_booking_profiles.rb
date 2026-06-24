# Booking attribution mode for a public booking profile.
#   fixed (0, default)  -> one default_assignee owns every booking (current S6).
#   per_agent (1)       -> each eligible agent shares their OWN link
#                          (crm_agent_booking_links); a booking made through that
#                          link is attributed to that agent and uses that agent's
#                          chosen mailbox/availability.
class AddAssignmentModeToCrmAgentBookingProfiles < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_agent_booking_profiles, :assignment_mode, :integer, default: 0, null: false
  end
end
