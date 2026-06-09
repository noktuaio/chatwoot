# == Schema Information
#
# Table name: captain_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  documentable_type :string
#  edited            :boolean          default(FALSE), not null
#  embedding         :vector(1536)
#  question          :string           not null
#  status            :integer          default("approved"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#  documentable_id   :bigint
#
# Indexes
#
#  idx_cap_asst_resp_on_documentable                  (documentable_id,documentable_type)
#  index_captain_assistant_responses_on_account_id    (account_id)
#  index_captain_assistant_responses_on_assistant_id  (assistant_id)
#  index_captain_assistant_responses_on_status        (status)
#  vector_idx_knowledge_entries_embedding             (embedding) USING ivfflat
#
class Captain::AssistantResponse < ApplicationRecord
  self.table_name = 'captain_assistant_responses'
  SEARCH_LIMIT = 5
  KEYWORD_SEARCH_LIMIT_MULTIPLIER = 2
  SEARCH_STOP_WORDS = %w[
    about after all also and any are but can for from has have how into its may more not now off our out
    the their them then there these they this was what when where which who why with you your
  ].freeze
  SearchMatch = Struct.new(
    :response,
    :semantic_distance,
    :keyword_score,
    :keyword_coverage,
    :matched_terms,
    :retrieval_methods,
    keyword_init: true
  ) do
    def to_h
      {
        response_id: response.id,
        question: response.question,
        answer: response.answer,
        source: response.documentable&.try(:external_link),
        semantic_distance: semantic_distance,
        keyword_score: keyword_score,
        keyword_coverage: keyword_coverage,
        matched_terms: matched_terms,
        retrieval_methods: retrieval_methods
      }
    end
  end

  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true
  has_neighbors :embedding, normalize: true

  validates :question, presence: true
  validates :answer, presence: true

  before_validation :ensure_account
  before_validation :ensure_status
  before_validation :mark_as_edited, on: :update
  after_commit :update_response_embedding

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }
  scope :with_document, ->(document_id) { where(document_id: document_id) }

  enum status: { pending: 0, approved: 1 }

  def self.search(query, account_id: nil)
    search_with_metadata(query, account_id: account_id).map(&:response)
  end

  def self.search_with_metadata(query, account_id: nil, limit: SEARCH_LIMIT)
    semantic_matches = semantic_search_matches(query, account_id: account_id, limit: limit)
    keyword_matches = keyword_search_matches(query, limit: limit * KEYWORD_SEARCH_LIMIT_MULTIPLIER)

    merge_search_matches(semantic_matches, keyword_matches).first(limit)
  end

  def self.semantic_search_matches(query, account_id:, limit:)
    embedding = Captain::Llm::EmbeddingService.new(account_id: account_id).get_embedding(query)
    nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(limit).map do |response|
      SearchMatch.new(
        response: response,
        semantic_distance: response.neighbor_distance&.to_f,
        keyword_score: 0,
        keyword_coverage: 0.0,
        matched_terms: [],
        retrieval_methods: ['semantic']
      )
    end
  end

  def self.keyword_search_matches(query, limit:)
    terms = search_terms(query)
    return [] if terms.empty?

    matches = keyword_search_scope(terms).limit(limit).map do |response|
      matched_terms = matched_terms_for(response, terms)
      SearchMatch.new(
        response: response,
        semantic_distance: nil,
        keyword_score: matched_terms.size,
        keyword_coverage: matched_terms.size.to_f / terms.size,
        matched_terms: matched_terms,
        retrieval_methods: ['keyword']
      )
    end
    matches.sort_by { |match| [-match.keyword_score, match.response.id] }
  end

  def self.keyword_search_scope(terms)
    conditions = []
    values = []

    terms.each do |term|
      pattern = "%#{sanitize_sql_like(term)}%"
      conditions << '(question ILIKE ? OR answer ILIKE ?)'
      values.push(pattern, pattern)
    end

    where(conditions.join(' OR '), *values)
  end

  def self.search_terms(query)
    query.to_s.downcase.scan(/[[:alnum:]]+/).filter_map do |term|
      next if term.length < 3
      next if SEARCH_STOP_WORDS.include?(term)

      term
    end.uniq
  end

  def self.matched_terms_for(response, terms)
    text = "#{response.question} #{response.answer}".downcase
    terms.select { |term| text.include?(term) }
  end

  def self.merge_search_matches(semantic_matches, keyword_matches)
    matches_by_response_id = {}

    semantic_matches.each do |match|
      matches_by_response_id[match.response.id] = match
    end

    keyword_matches.each do |keyword_match|
      existing = matches_by_response_id[keyword_match.response.id]
      if existing
        merge_keyword_match!(existing, keyword_match)
      else
        matches_by_response_id[keyword_match.response.id] = keyword_match
      end
    end

    sort_search_matches(matches_by_response_id.values)
  end

  def self.merge_keyword_match!(existing, keyword_match)
    existing.keyword_score = keyword_match.keyword_score
    existing.keyword_coverage = keyword_match.keyword_coverage
    existing.matched_terms = keyword_match.matched_terms
    existing.retrieval_methods |= keyword_match.retrieval_methods
  end

  def self.sort_search_matches(matches)
    matches.sort_by do |match|
      [match.semantic_distance || 1.0, -match.keyword_score, match.response.id]
    end
  end

  private

  def ensure_status
    self.status ||= :approved
  end

  def mark_as_edited
    self.edited = true if question_changed? || answer_changed?
  end

  def ensure_account
    self.account = assistant&.account
  end

  def update_response_embedding
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, "#{question}: #{answer}")
  end
end
