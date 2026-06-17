module Autonomia
  module Agents
    module Knowledge
      # Orquestrador síncrono da ingestão de UMA fonte (rodado dentro do ProcessJob):
      # extrai texto -> chunka -> embeda em lote -> substitui o conhecimento antigo da fonte por
      # KnowledgeEntry novos (content + embedding + chunk_index, status: ready). Retorna a contagem
      # de chunks gravados; qualquer erro sobe p/ o job marcar a fonte como `failed`.
      class Ingestor
        # Levantada quando, na hora de gravar, outra ingestão (re-sync) já venceu o sync_token: o job
        # antigo NÃO pode tocar o conhecimento da geração nova.
        class Superseded < StandardError; end

        def initialize(source:, token:)
          @source = source
          @token = token
          @agent = source.agent
          @account = source.account
        end

        def perform
          text = Processors.for(@source).extract
          chunks = Chunker.new(text).chunks
          return replace_knowledge([], []) if chunks.empty?

          vectors = Autonomia::Agents::EmbeddingService.new(account: @account).embed_batch(chunks)
          replace_knowledge(chunks, vectors)
        end

        private

        # Apaga os entries antigos da fonte e cria os novos numa transação (re-sync idempotente).
        # Token-guard (padrão Fase C): trava a row da fonte e SÓ substitui se o sync_token desta
        # execução ainda for o ativo E a fonte ainda estiver processing — senão `Superseded` (no-op),
        # evitando que um job velho apague o conhecimento de uma ingestão nova (race de resync).
        # Descarta pares cujo vetor veio vazio. Cria via model (não insert_all) p/ o cast de vetor da
        # gem `neighbor`. Retorna a contagem gravada.
        def replace_knowledge(chunks, vectors)
          count = 0
          KnowledgeEntry.transaction do
            @source.lock!
            raise Superseded unless @source.sync_token == @token && @source.processing?

            KnowledgeEntry.where(source_id: @source.id).delete_all
            chunks.each_with_index do |content, index|
              vector = vectors[index]
              next if vector.blank?

              create_entry(content, vector, index)
              count += 1
            end
          end
          count
        end

        def create_entry(content, vector, index)
          KnowledgeEntry.create!(
            autonomia_agent_id: @agent.id, account_id: @account.id, source_id: @source.id,
            content: content, embedding: vector, chunk_index: index,
            status: :ready, metadata: { source_type: @source.source_type }
          )
        end
      end
    end
  end
end
