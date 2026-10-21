module Lots
  class Chunker
    # About 500 tokens (375 words); overlap about 80 tokens (60 words).
    # Paragraph boundaries are preferred, large paragraphs are split safely.
    def call(text)
      chunks = []
      # Keep the original whitespace: rows, columns and page markers are evidence.
      words = text.scan(/\S+\s*/)
      start = 0
      while start < words.size
        finish = [ start + 375, words.size ].min
        if finish < words.size
          paragraph_end = (start + 315...finish).to_a.reverse.find { |index| words[index].match?(/\n\s*\n/) }
          finish = paragraph_end + 1 if paragraph_end
        end
        chunks << words[start...finish].join.strip
        break if finish == words.size
        start = finish - 60
      end
      chunks
    end
  end
end
