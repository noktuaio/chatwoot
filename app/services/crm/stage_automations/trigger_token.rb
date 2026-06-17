class Crm::StageAutomations::TriggerToken
  def self.for_enter(card:, stage_id:)
    "enter:#{stage_id}:#{card.entered_stage_at.to_i}"
  end

  def self.for_exit(card:, from_stage_id:, exited_at:)
    "exit:#{from_stage_id}:#{card.id}:#{exited_at.to_i}"
  end
end
