class Crm::PipelineStages::Reorderer
  SUCCESS = :success
  FAILURE = :failure

  def initialize(account:, stage_ids:)
    @account = account
    @stage_ids = Array(stage_ids).map(&:to_i)
  end

  def perform
    return FAILURE unless valid_stage_set?

    ActiveRecord::Base.transaction do
      @stage_ids.each_with_index { |stage_id, index| stages_by_id[stage_id]&.update!(position: index) }
    end
    SUCCESS
  end

  private

  def valid_stage_set?
    @stage_ids.present? && stages.size == @stage_ids.size && pipeline_ids.one?
  end

  def stages
    @stages ||= @account.crm_pipeline_stages.where(id: @stage_ids).to_a
  end

  def stages_by_id
    @stages_by_id ||= stages.index_by(&:id)
  end

  def pipeline_ids
    stages.map(&:pipeline_id).uniq
  end
end
