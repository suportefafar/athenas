module ChatMessagesHelper
  CHAT_MARKDOWN_INLINE = /(\*\*\*[^*\n]+\*\*\*|\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`|\[[^\]]+\]\(https?:\/\/[^)\s]+\)|<br\s*\/?\s*>|\n|\*[^*\n]+\*|_[^_\n]+_)/i

  def render_chat_markdown(content)
    blocks = split_chat_markdown_blocks(clean_chat_model_artifacts(content))
    safe_join(blocks.map { |type, value| render_chat_markdown_block(type, value) })
  end

  private

  def clean_chat_model_artifacts(content)
    content.to_s
      .gsub(/<tool_call\b[^>]*>.*?(?:<\/tool_call\s*>|\z)/im, "")
      .gsub(/:chatgpt-content-reference\{[^}\n]*\}/i, "")
      .gsub(/【[^】]*(?:cite|turn\d+[^】]*)】/i, "")
      .gsub(/\[\s*cite[^\]\n]*\]/i, "")
      .gsub(/[ \t]+\n/, "\n")
      .strip
  end

  def split_chat_markdown_blocks(content)
    lines = content.gsub("\r\n", "\n").gsub("\r", "\n").split("\n").map { |line| line.sub(/^\s*>\s?/, "") }
    blocks = []
    text_lines = []
    code_lines = []
    in_code = false
    index = 0

    push_text = lambda do
      unless text_lines.empty?
        type = chat_markdown_list_type(text_lines.first)
        blocks << [ type ? :list : :paragraph, text_lines.join("\n") ]
        text_lines = []
      end
    end

    while index < lines.length
      line = lines[index]

      if !in_code && chat_markdown_table_start?(lines, index)
        push_text.call
        table_lines = [ line ]
        index += 1
        index += 1 while index < lines.length && lines[index].blank?
        while index < lines.length && lines[index].include?("|")
          table_lines << lines[index]
          index += 1
          index += 1 while index < lines.length && lines[index].blank?
        end
        blocks << [ :table, table_lines ]
        next
      end

      if line.match?(/^\s*```/)
        if in_code
          blocks << [ :code, code_lines.join("\n") ]
          code_lines = []
          in_code = false
        else
          push_text.call
          in_code = true
        end
      elsif in_code
        code_lines << line
      elsif line.match?(/^\s{0,3}\#{1,6}\s/) || chat_markdown_rule?(line)
        push_text.call
        blocks << [ chat_markdown_rule?(line) ? :rule : :heading, line.strip ]
      elsif line.blank?
        next_index = index + 1
        next_index += 1 while next_index < lines.length && lines[next_index].blank?
        previous_type = text_lines.empty? ? nil : chat_markdown_list_type(text_lines.last)
        next_type = next_index < lines.length ? chat_markdown_list_type(lines[next_index]) : nil
        unless previous_type && previous_type == next_type
          push_text.call
        end
        index = next_index
        next
      else
        previous_type = text_lines.empty? ? nil : chat_markdown_list_type(text_lines.last)
        next_type = chat_markdown_list_type(line)
        push_text.call if previous_type != next_type && !text_lines.empty?
        text_lines << line
      end
      index += 1
    end

    blocks << [ :code, code_lines.join("\n") ] if in_code
    push_text.call
    blocks
  end

  def chat_markdown_table_start?(lines, index)
    lines[index].include?("|") && lines[(index + 1)..].to_a.any? { |line| !line.blank? } &&
      lines[(index + 1)..].to_a.find { |line| !line.blank? }.match?(/^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/)
  end

  def chat_markdown_list_type(line)
    return :ordered if line.match?(/^\s*\d+[.)]\s+/)
    return :unordered if line.match?(/^\s*[-*+]\s+/)
  end

  def chat_markdown_rule?(line)
    line.match?(/^\s*(?:---+|\*\*\*+|___+)\s*$/)
  end

  def render_chat_markdown_block(type, value)
    case type
    when :code
      content_tag(:pre, content_tag(:code, value), data: { block_kind: "code" })
    when :rule
      tag.hr(data: { block_kind: "rule" })
    when :heading
      level = value[/\A#+/].length
      content_tag("h#{level}", render_chat_markdown_inline(value.sub(/\A#+\s+/, "")), data: { block_kind: "heading" })
    when :list
      lines = value.lines.map(&:chomp)
      ordered = chat_markdown_list_type(lines.first) == :ordered
      list_tag = ordered ? :ol : :ul
      items = lines.map do |line|
        text = line.sub(ordered ? /^\s*\d+[.)]\s+/ : /^\s*[-*+]\s+/, "")
        content_tag(:li, render_chat_markdown_inline(text), data: { block_kind: "list-item" })
      end
      content_tag(list_tag, safe_join(items))
    when :table
      render_chat_markdown_table(value)
    else
      content_tag(:p, render_chat_markdown_inline(value), data: { block_kind: "paragraph" })
    end
  end

  def render_chat_markdown_table(lines)
    headers = split_chat_markdown_table_cells(lines.first)
    rows = lines.drop(2).map { |line| split_chat_markdown_table_cells(line) }
    head = content_tag(:thead, content_tag(:tr, safe_join(headers.map { |cell| content_tag(:th, render_chat_markdown_inline(cell)) })))
    body = content_tag(:tbody, safe_join(rows.map do |row|
      content_tag(:tr, safe_join(row.map { |cell| content_tag(:td, render_chat_markdown_inline(cell)) }))
    end))
    table = content_tag(:table, safe_join([ head, body ]), data: { block_kind: "table" })
    content_tag(:div, table, class: "chat-markdown-table-scroll", role: "region", aria: { label: "Tabela com rolagem horizontal" }, tabindex: "0")
  end

  def split_chat_markdown_table_cells(line)
    source = line.strip.delete_prefix("|").delete_suffix("|")
    cells = []
    cell = +""
    in_code = false
    characters = source.chars
    index = 0
    while index < characters.length
      character = characters[index]
      if character == "\\" && characters[index + 1] == "|"
        cell << "|"
        index += 2
      elsif character == "`"
        in_code = !in_code
        cell << character
        index += 1
      elsif character == "|" && !in_code
        cells << cell.strip
        cell = +""
        index += 1
      else
        cell << character
        index += 1
      end
    end
    cells << cell.strip
    cells
  end

  def render_chat_markdown_inline(text, depth = 0)
    return ERB::Util.html_escape(text) if depth > 5

    quoted_emphasis = text.match(/^\*((?:["“])[\s\S]*(?:["”]))\*$/)
    source = unwrap_chat_paragraph_emphasis(quoted_emphasis ? quoted_emphasis[1] : text)
    parts = []
    cursor = 0

    source.to_enum(:scan, CHAT_MARKDOWN_INLINE).each do
      match = Regexp.last_match
      parts << source[cursor...match.begin(0)] if match.begin(0) > cursor
      token = match[0]
      rendered = if token.start_with?("***")
        content_tag(:strong, content_tag(:em, render_chat_markdown_inline(token[3...-3], depth + 1)))
      elsif token.start_with?("**", "__")
        content_tag(:strong, render_chat_markdown_inline(token[2...-2], depth + 1))
      elsif token.start_with?("`")
        content_tag(:code, token[1...-1])
      elsif token.start_with?("[")
        link = token.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/i)
        link_to(link[1], link[2], target: "_blank", rel: "noopener noreferrer")
      elsif token.match?(/^<br/i)
        tag.br
      elsif token == "\n"
        tag.br
      else
        content_tag(:em, render_chat_markdown_inline(token[1...-1], depth + 1))
      end
      parts << rendered
      cursor = match.end(0)
    end
    parts << source[cursor..] if cursor < source.length
    safe_join(parts)
  end

  def unwrap_chat_paragraph_emphasis(text)
    text.split("\n").map do |line|
      match = line.match(/^\s*(\*\*|__)([\s\S]+)\1\s*$/)
      next line unless match

      content = match[2].strip
      next line if content.include?(match[1])

      word_count = content.split(/\s+/).length
      sentence = content.match?(/[.!?](?:["”’')\]]?)(?:\s|$)/)
      label = content.length > 35 && content.match?(/^[^:]{2,40}:\s+\S/)
      content.length > 100 || (label && sentence) || (sentence && word_count > 10) ? content : line
    end.join("\n")
  end
end
