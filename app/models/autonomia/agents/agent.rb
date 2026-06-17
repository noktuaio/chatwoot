module Autonomia
  module Agents
    class Agent < ApplicationRecord
      self.table_name = 'autonomia_agents'

      belongs_to :account
      belongs_to :created_by, class_name: 'User', optional: true
      has_many :sources, class_name: 'Autonomia::Agents::Source',
                         foreign_key: :autonomia_agent_id, dependent: :destroy
      has_many :knowledge_entries, class_name: 'Autonomia::Agents::KnowledgeEntry',
                                   foreign_key: :autonomia_agent_id, dependent: :destroy
      has_many :build_threads, class_name: 'Autonomia::Agents::BuildThread',
                               foreign_key: :autonomia_agent_id, dependent: :nullify
      has_many :agent_inboxes, class_name: 'Autonomia::Agents::AgentInbox',
                               foreign_key: :autonomia_agent_id, dependent: :destroy
      has_many :inboxes, through: :agent_inboxes
      # Revisor v2: só as fontes APROVADAS pela IA Revisora alimentam o Construtor (resumos) e o
      # retrieval do Testar/Operar. needs_resend/needs_review ficam de fora.
      has_many :accepted_sources, -> { accepted }, class_name: 'Autonomia::Agents::Source',
                                  foreign_key: :autonomia_agent_id
      # Fase F: eventos de operação (replied/handed_off). delete_all = limpeza barata e
      # imutável ao destruir o agente; o Analytics consulta por autonomia_agent_id direto.
      has_many :events, class_name: 'Autonomia::Agents::AgentEvent',
                        foreign_key: :autonomia_agent_id, dependent: :delete_all

      enum status: { draft: 0, active: 1, paused: 2 }
      enum mode:   { guided: 0, manual: 1 }

      AGENT_TYPES = %w[support sdr reception onboarding scheduler reactivation custom].freeze
      validates :name, presence: true
      validates :agent_type, inclusion: { in: AGENT_TYPES }

      store_accessor :config, :model, :temperature, :business_hours, :max_turns, :guardrails
      store_accessor :config, :confidence_threshold # Fase B: portão de confiança (lido no Answerer)
      # Fase D: handoff real configurável por agente (jsonb `config`, sem migração).
      # handoff_strategy ∈ Operate::HANDOFF_STRATEGIES; default conservador = 'none'
      # (comportamento da Fase C: só mensagem graciosa + bot_handoff!, conversa fica unassigned).
      # handoff_target_id = id do User (assign_member) ou Team (assign_team) alvo.
      store_accessor :config, :handoff_strategy, :handoff_target_id
      # Revisor v2: MAPA DE TEMAS + confiança geral da base, gravados por Reviewer.recompute_overall!
      # no jsonb `config` (sem migração). Alimentam a UI de Conhecimento e o Construtor (NÃO o
      # jbuilder do agente expõe instruction/scaffold; estes 3 são seguros de expor).
      store_accessor :config, :topic_map, :knowledge_confidence, :knowledge_summary
      # #3 INSTRUÇÃO VIVA (B): token de coalescência do refresh debounced da instrução. Uma rajada de
      # uploads grava tokens sucessivos; só o ÚLTIMO RefreshInstructionJob enfileirado (token corrente)
      # roda — os anteriores viram no-op. Vive no jsonb `config` (sem migração); NÃO é exposto pelo
      # jbuilder (não está na lista de campos seguros do serializer) e nunca vaza a instrução.
      store_accessor :config, :knowledge_refresh_token

      # Aplica config gerada pelo Construtor (token-guarded — análogo a ai_guarded_update do
      # EmailCampaign). `build_token` é o token ativo do BuildThread; a escrita só vence se este
      # ainda for o token da geração corrente (idempotência anti-supersede). `attrs` já vem mapeado
      # do schema do Builder para colunas (incluindo instruction/scaffold ocultos). Retorna true se
      # esta geração ganhou a escrita.
      def apply_builder_config!(build_token, attrs)
        return false if build_token.blank?

        transaction do
          thread = build_threads.where(build_token: build_token).lock.first
          next false if thread.nil? || !thread.processing?

          # Merge no jsonb `config` em vez de substituí-lo: preserva model/temperature/business_hours/
          # max_turns já setados (o Construtor só gera `guardrails`). Substituir zeraria a config a
          # cada "Ajustar com IA".
          merged = attrs.dup
          merged[:config] = config.to_h.merge(attrs[:config] || {}) if attrs.key?(:config)
          update!(merged)
          true
        end
      end

      # #3 INSTRUÇÃO VIVA — Atualiza a instrução fora do fluxo do Construtor (a KB mudou, não há
      # BuildThread em geração). SEM token: não há geração concorrente do usuário aqui. Toca SÓ a
      # coluna `instruction` (oculta); `config` — topic_map/knowledge_summary/confidence — acabou de
      # ser gravado por recompute_overall! no mesmo agente, então NÃO é tocado (preservado por
      # omissão). Não dispara recompute_overall! de volta (não mexe em config/sources): sem loop.
      def refresh_instruction!(new_instruction)
        update!(instruction: new_instruction)
      end

      # #3 INSTRUÇÃO VIVA (B): grava um token de coalescência novo no jsonb `config` e o retorna. Relê
      # o config corrente (merge) para não clobberar topic_map/knowledge_summary que recompute_overall!
      # acabou de assentar. Usado por RefreshInstructionJob.enqueue para deduplicar a rajada de uploads.
      def bump_knowledge_refresh_token!
        reload
        token = SecureRandom.hex(8)
        update!(config: config.to_h.merge('knowledge_refresh_token' => token))
        token
      end
    end
  end
end
