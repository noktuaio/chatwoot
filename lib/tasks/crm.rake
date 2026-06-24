namespace :crm do
  # One-time cutover backfill for PR14.1 (CRM granular permissions).
  #
  # Before this change every custom-role agent had implicit full agent-level CRM
  # access (board read + card CRUD/move). After the granular crm_* keys land,
  # custom roles without those keys would silently lose board/card access.
  #
  # LOCKED DECISION: grant the baseline (crm_view, crm_manage_cards, crm_move_cards)
  # to ALL existing custom roles so nobody loses access on deploy.
  # Idempotent: only appends missing keys. Administrators and plain agents are
  # unaffected (they keep full CRM access independently of this backfill).
  desc 'Backfill baseline CRM permissions on all existing custom roles (cutover step)'
  task backfill_role_permissions: :environment do
    baseline = %w[crm_view crm_manage_cards crm_move_cards]
    updated = 0

    CustomRole.find_each do |role|
      missing = baseline - role.permissions
      next if missing.empty?

      role.update!(permissions: (role.permissions + missing).uniq)
      updated += 1
    end

    Rails.logger.info("[crm:backfill_role_permissions] updated #{updated} custom role(s)")
    puts "Backfilled baseline CRM permissions on #{updated} custom role(s)."
  end
end
