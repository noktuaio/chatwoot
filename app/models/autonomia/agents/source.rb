module Autonomia
  module Agents
    class Source < ApplicationRecord
      self.table_name = 'autonomia_agent_sources'

      # Arquivo enviado (pdf/xlsx/docx/json/txt/md). Em fontes do tipo `link` não há anexo.
      # O controller faz file.attach(...) e os Processors leem via @source.file.
      has_one_attached :file

      belongs_to :account
      belongs_to :agent, class_name: 'Autonomia::Agents::Agent',
                         foreign_key: :autonomia_agent_id
      has_many :knowledge_entries, class_name: 'Autonomia::Agents::KnowledgeEntry',
                                   foreign_key: :source_id, dependent: :delete_all

      enum status: { pending: 0, processing: 1, ready: 2, failed: 3 }

      # GAP (A) — DOIS grupos de materiais (plano v2 §1). `kind` decide o PIPELINE:
      #   - knowledge: "o que ela SABE" → ingest → chunk → embed → revisora (caminho ATUAL, inalterado).
      #   - media:     "o que ela ENVIA" (catálogo/tabela/imagem) → só armazenada (ready direto), SEM
      #                embed e SEM revisora de qualidade de KB.
      # Prefixo `kind_` evita colisão de métodos com o enum `status` e deixa explícito (kind_media?).
      enum kind: { knowledge: 0, media: 1 }, _prefix: :kind

      # Escopos por grupo. `knowledge`/`media` (do enum) já existem; estes são aliases legíveis usados
      # pelos serializers e pelo contexto do Construtor (mídias de envio).
      scope :knowledge_sources, -> { where(kind: kinds[:knowledge]) }
      scope :media_sources,     -> { where(kind: kinds[:media]) }

      # Parecer da IA Revisora (colunas reais — migration 20260620120000). 'needs_review' é o default
      # conservador quando a IA falha/credencial ausente: NÃO bloqueia o agente (conhecimento já foi
      # gravado), só marca confiança baixa sem summary. Só fontes 'accepted' alimentam o Construtor e
      # o retrieval (ver Retriever / Builder).
      REVIEW_STATUSES = %w[accepted needs_resend needs_review].freeze
      CONFIDENCE_LEVELS = %w[alta media baixa].freeze
      REVIEW_LABELS = %w[otima boa fraca].freeze

      # Escopo do parecer aceito — usado pelo retrieval e pelos resumos do Construtor.
      scope :accepted, -> { where(review_status: 'accepted') }

      SOURCE_TYPES = %w[link pdf xlsx docx json txt md].freeze
      # Teto de tamanho do ANEXO comprimido (defesa contra upload gigante / zip-bomb). O cap do
      # tamanho DESCOMPRIMIDO de docx/xlsx é aplicado no processor.
      MAX_FILE_BYTES = 25.megabytes
      ALLOWED_CONTENT_TYPES = %w[
        application/pdf
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
        application/vnd.openxmlformats-officedocument.wordprocessingml.document
        application/json text/plain text/markdown text/x-markdown application/octet-stream
      ].freeze

      validates :source_type, inclusion: { in: SOURCE_TYPES }
      # Validação branda dos campos de revisão: aceita nil (fontes antigas / ainda não revisadas) mas
      # rejeita valores fora do vocabulário pt-BR. allow_nil mantém a migração aditiva sem regressão.
      validates :review_status, inclusion: { in: REVIEW_STATUSES }, allow_nil: true
      validates :confidence, inclusion: { in: CONFIDENCE_LEVELS }, allow_nil: true
      validates :review_label, inclusion: { in: REVIEW_LABELS }, allow_nil: true
      validate :file_within_limits

      store_accessor :metadata, :fingerprint, :byte_size, :chunk_count, :mime

      # token-guard idêntico ao padrão EmailCampaign#ai_guarded_update: marca processing + novo
      # sync_token; toda escrita posterior (mark_ready!/mark_failed!) só vence se o token ainda for
      # o ativo E o status ainda for processing. Retorna o token p/ o IngestJob/ProcessJob carregarem.
      def begin_ingestion!
        token = SecureRandom.hex(16)
        # Rebaixa a fonte a NÃO-utilizável até a nova revisão vencer: no re-sync de uma fonte antes
        # 'accepted', o Ingestor recria os KnowledgeEntry (status ready) ANTES do Reviewer rodar, e o
        # Retriever (que exclui needs_review) deixaria o conteúdo re-embebido mas ainda-não-revalidado
        # entrar em Testar/Operar — violando "revisado ANTES de usar". Limpa também o parecer antigo
        # para o Construtor não ler um review_summary defasado. mark_reviewed! recoloca em 'accepted'.
        update_columns(status: self.class.statuses[:processing], sync_token: token,
                       error: nil, sync_status: nil,
                       review_status: 'needs_review', quality_score: nil, confidence: nil,
                       review_summary: nil, review_label: nil, review_reason: nil, reviewed_at: nil,
                       updated_at: Time.current)
        token
      end

      # GAP (A) — mídia de ENVIO: caminho NOVO, sem ingestão. NÃO embeda, NÃO chama a revisora; só
      # marca `ready` e guarda os metadados de exibição (nome/tipo já vêm de reference/source_type +
      # metadata byte_size/mime do upload). Sem token-guard porque não há pipeline concorrente de
      # ingestão para uma mídia (ela nunca passa por begin_ingestion!). review_status fica nil — as
      # mídias NUNCA entram no retrieval nem no portão de materiais do Construtor.
      def mark_media_ready!
        update_columns(status: self.class.statuses[:ready], error: nil, sync_status: nil,
                       synced_at: Time.current, updated_at: Time.current)
      end

      def mark_ready!(token, chunk_count:)
        new_metadata = (metadata || {}).merge('chunk_count' => chunk_count)
        guarded_update(token, status: self.class.statuses[:ready], error: nil,
                              metadata: new_metadata, synced_at: Time.current)
      end

      def mark_failed!(token, message)
        guarded_update(token, status: self.class.statuses[:failed],
                              error: message.to_s.truncate(500))
      end

      # Grava o parecer da IA Revisora. Corre DEPOIS de mark_ready! (status já é `ready`), por isso
      # NÃO usa o guarded_update de ingestão (que exige `processing`); usa o review_guard, que só
      # vence se o sync_token desta revisão ainda for o ativo (anti-supersede: um re-sync concorrente
      # gerou outro token e esta escrita vira no-op). `attrs` traz quality_score/confidence/
      # review_status/review_summary/review_label/review_reason. Retorna true se ganhou a escrita.
      def mark_reviewed!(token, attrs)
        review_guard(token, attrs.merge(reviewed_at: Time.current))
      end

      def accepted?
        review_status == 'accepted'
      end

      private

      # Guard de revisão: escreve só se o sync_token ainda for o desta execução (não exige status —
      # a fonte já está `ready`/`failed`). update_all atômico fecha a janela check→write. true se ganhou.
      def review_guard(token, attrs)
        return false if token.blank?

        rows = self.class.where(id: id, sync_token: token)
                   .update_all(attrs.merge(updated_at: Time.current))
        reload if rows.positive?
        rows.positive?
      end

      # Bloqueia anexos acima do teto comprimido e de content-types não suportados (DoS de memória /
      # zip-bomb / upload arbitrário). Só roda quando há arquivo (fontes `link` não têm anexo).
      def file_within_limits
        return unless file.attached?

        errors.add(:file, 'too_large') if file.blob.byte_size > MAX_FILE_BYTES
        errors.add(:file, 'unsupported_content_type') unless ALLOWED_CONTENT_TYPES.include?(file.blob.content_type)
      end

      # Escreve só se a ingestão identificada por `token` ainda for a ativa e ainda processing.
      # update_all atômico fecha a janela entre checagem e escrita. Retorna true se ganhou (1 linha).
      def guarded_update(token, attrs)
        return false if token.blank?

        rows = self.class.where(id: id, sync_token: token, status: self.class.statuses[:processing])
                   .update_all(attrs.merge(updated_at: Time.current))
        reload if rows.positive?
        rows.positive?
      end
    end
  end
end
