module Lots
  class Chunker
    # About 500 tokens (375 words); overlap about 80 tokens (60 words).
    # Paragraph boundaries are preferred, large paragraphs are split safely.
    def call(text)
      chunks = []
      words = []
      text.split(/\n\s*\n/).each do |paragraph|
        paragraph.split.each_slice(375) do |slice|
          if words.size + slice.size > 375 && words.any?
            chunks << words.join(" ")
            words = words.last(60)
          end
          words.concat(slice)
          while words.size > 375
            chunks << words.first(375).join(" ")
            words = words.drop(315)
          end
        end
      end
      chunks << words.join(" ") if words.any?
      chunks
    end
  end
end
