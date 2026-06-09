class Captain::DocumentationSufficiencySchema < RubyLLM::Schema
  DECISIONS = %w[sufficient insufficient].freeze
  REASONS = %w[
    answers_exact_question
    no_documentation_used
    bounded_no_answer
    missing_or_weak_evidence
    wrong_entity
    wrong_intent
    missing_constraint
    generic_evidence
    unsupported_high_risk_claim
  ].freeze

  string :decision,
         enum: DECISIONS,
         description: 'Use insufficient for unsupported factual answers; use sufficient only when supported or safely bounded'
  string :reason, enum: REASONS, description: 'The main reason for the decision'
  string :fallback_response, description: 'If insufficient, a brief user-facing fallback in the user language; otherwise empty'
end
