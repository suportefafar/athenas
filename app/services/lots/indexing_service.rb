module Lots
  class IndexingService
    def initialize(client: Embeddings::OllamaClient.new)
      @client = client
    end

    def prepare(text)
      warnings = []
      unavailable = false
      chunks = Chunker.new.call(text).each_with_index.map do |chunk, index|
        embedding = nil
        unless unavailable
          begin
            embedding = Embeddings::OllamaClient.sql_vector(@client.call(chunk))
          rescue Embeddings::OllamaClient::Unavailable
            unavailable = true
            warnings << "Embeddings incompletos: serviço local indisponível. A busca lexical permanece disponível."
          end
        end
        { position: index, text: chunk, embedding: embedding }
      end
      [ chunks, warnings ]
    end
  end
end
