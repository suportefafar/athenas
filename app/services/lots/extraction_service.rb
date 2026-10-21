require "tmpdir"
require "fileutils"
require "zip"
require "nokogiri"

module Lots
  class ExtractionService
    class Invalid < StandardError; end
    class Rejected < Invalid; end
    Result = Struct.new(:text, :content_type, :page_count, :metadata, :warnings, keyword_init: true)
    OFFICE = {
      ".docx" => [ "word/document.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ],
      ".xlsx" => [ "xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ],
      ".pptx" => [ "ppt/presentation.xml", "application/vnd.openxmlformats-officedocument.presentationml.presentation" ],
      ".odt" => [ "content.xml", "application/vnd.oasis.opendocument.text" ],
      ".ods" => [ "content.xml", "application/vnd.oasis.opendocument.spreadsheet" ],
      ".odp" => [ "content.xml", "application/vnd.oasis.opendocument.presentation" ]
    }.freeze
    TEXT_EXTENSIONS = %w[.txt .md .csv .json .xml].freeze
    IMAGE_TYPES = %w[image/png image/jpeg image/tiff image/webp].freeze

    def initialize(runner: CommandRunner.new)
      @runner = runner
    end

    def call(path, name:)
      size = File.size(path)
      raise Rejected, "Arquivo excede o limite de 10 MB." if size > [ ENV.fetch("MAX_UPLOAD_BYTES", 10.megabytes).to_i, 10.megabytes ].min
      raise Invalid, "Arquivo vazio." if size.zero?
      @warnings = []
      @metadata = {}
      @pages = nil
      @mime = Marcel::MimeType.for(Pathname.new(path), name: name)
      Dir.mktmpdir("athenas-extract-") do |directory|
        @directory = directory
        ext = File.extname(name).downcase
        @path = File.join(directory, "input#{ext.match?(/\A\.[a-z0-9]{1,8}\z/) ? ext : '.bin'}")
        FileUtils.cp(path, @path)
        if %w[application/msword application/vnd.ms-excel application/vnd.ms-powerpoint application/postscript application/oxps application/vnd.ms-xpsdocument].include?(@mime)
          raise Invalid, "Formato paginado sem validação segura de páginas; exporte para PDF."
        end
        text = if @mime == "application/pdf"
          pdf(@path)
        elsif IMAGE_TYPES.include?(@mime)
          image
        elsif (OFFICE.key?(ext) && %w[application/zip application/octet-stream].include?(@mime)) || OFFICE.values.any? { |_, mime| mime == @mime }
          raise Invalid, "Extensão de documento incompatível." unless OFFICE.key?(ext)
          office(ext)
        elsif TEXT_EXTENSIONS.include?(ext) && text_mime?(@mime)
          plain_text
        else
          @warnings << "Conteúdo não extraído: formato sem extrator seguro. Apenas nome e metadados estão pesquisáveis."
          ""
        end
        @metadata.merge!("tipo" => @mime, "tamanho_bytes" => size)
        @metadata["paginas"] = @pages if @pages
        text = normalize(text)
        if text.empty? && @warnings.empty?
          @warnings << "Conteúdo não extraído: nenhum texto disponível. Apenas nome e metadados estão pesquisáveis."
        end
        Result.new(text: text, content_type: @mime, page_count: @pages, metadata: @metadata, warnings: @warnings)
      end
    rescue CommandRunner::Error
      raise Invalid, "Não foi possível validar o arquivo com segurança. Verifique as ferramentas locais e a integridade do documento."
    rescue Zip::Error, Nokogiri::XML::SyntaxError, JSON::ParserError, ArgumentError
      raise Invalid, "Arquivo inválido ou corrompido."
    end

    private

    def run(*args, **options)
      @runner.call(*args, directory: @directory, **options)
    end

    def limit_pages!(count)
      raise Invalid, "Não foi possível validar o número de páginas." unless count && count.positive?
      max = [ ENV.fetch("MAX_DOCUMENT_PAGES", 100).to_i, 100 ].min
      raise Rejected, "Documento excede o limite de #{max} páginas." if count > max
      @pages = count
    end

    def pdf(path, text: true)
      info = run("pdfinfo", path)
      limit_pages!(info[/^Pages:\s+(\d+)/, 1]&.to_i)
      @metadata["titulo_interno"] = info[/^Title:\s+(.+)/, 1].to_s.first(500)
      @metadata["autor_interno"] = info[/^Author:\s+(.+)/, 1].to_s.first(500)
      return "" unless text
      (1..@pages).map do |page|
        begin
          extracted = run("pdftotext", "-f", page, "-l", page, "-layout", path, "-")
          if extracted.strip.empty?
            prefix = File.join(@directory, "page-#{page}")
            run("pdftoppm", "-f", page, "-l", page, "-singlefile", "-scale-to", "2500", "-png", path, prefix)
            extracted = ocr("#{prefix}.png", page)
            FileUtils.rm_f("#{prefix}.png")
          end
          "[Página #{page}]\n#{extracted.delete("\f").strip}"
        rescue CommandRunner::Error
          @warnings << "Página #{page}: extração/OCR incompleto."
          ""
        end
      end.join("\n\n")
    end

    def image
      info = JSON.parse(run("python3", Rails.root.join("script/image_tool.py"), "info", @path))
      count = info.fetch("pages")
      limit_pages!(count) # TIFF frames are actual pages; ordinary images have one.
      (0...count).map do |page|
        target = File.join(@directory, "image-#{page}.png")
        begin
          run("python3", Rails.root.join("script/image_tool.py"), "frame", @path, page, target)
          ocr(target, page + 1)
        rescue CommandRunner::Error
          @warnings << "Página #{page + 1}: OCR incompleto."
          ""
        ensure
          FileUtils.rm_f(target)
        end
      end.join("\n\n")
    end

    def ocr(path, page)
      @languages ||= run("tesseract", "--list-langs").lines.map(&:strip)
      language = @languages.include?("por") ? (@languages.include?("eng") ? "por+eng" : "por") : "eng"
      @warnings << "OCR em português indisponível; utilizado inglês." unless @languages.include?("por")
      result = run("tesseract", path, "stdout", "-l", language)
      @warnings << "Página #{page}: nenhum texto reconhecido pelo OCR." if result.strip.empty?
      result
    rescue CommandRunner::Error
      @warnings << "Página #{page}: OCR indisponível ou falhou."
      ""
    end

    def text_mime?(mime)
      mime.start_with?("text/") || %w[application/json application/xml application/octet-stream].include?(mime)
    end

    def plain_text
      bytes = File.binread(@path)
      raise Invalid, "Arquivo textual contém dados binários inválidos." if bytes.include?("\0") && !bytes.start_with?("\xFF\xFE".b, "\xFE\xFF".b)
      encoding = if bytes.start_with?("\xFF\xFE".b)
        "UTF-16LE"
      elsif bytes.start_with?("\xFE\xFF".b)
        "UTF-16BE"
      elsif bytes.dup.force_encoding("UTF-8").valid_encoding?
        "UTF-8"
      else
        "Windows-1252"
      end
      bytes.force_encoding(encoding).encode("UTF-8", invalid: :replace, undef: :replace).delete_prefix("\uFEFF")
    end

    def office(ext)
      entries = {}
      total = 0
      expanded = 0
      Zip::File.open(@path) do |archive|
        raise Rejected, "Documento compactado excede limites de segurança." if archive.entries.size > 2000
        archive.each do |entry|
          raise Rejected, "Documento contém macros ou objetos executáveis." if entry.name.match?(/vbaProject|embeddings\/|Basic\/|Scripts\//i)
          next if entry.directory?
          if entry.name.match?(%r{\A(word|xl|ppt)/media/})
            @warnings << "Imagens incorporadas no Office não foram submetidas a OCR."
          end
          total += entry.size
          if total > 50.megabytes || entry.size > 10.megabytes || entry.name.include?("..") || entry.name.start_with?("/") || entry.ftype == :symlink
            raise Rejected, "Documento compactado excede limites de segurança."
          end
          next unless entry.name.end_with?(".xml") || entry.name == "mimetype"
          bytes = entry.get_input_stream { |stream| stream.read(10.megabytes + 1) }
          raise Rejected, "Documento compactado excede limites de segurança." if bytes.bytesize > 10.megabytes
          expanded += bytes.bytesize
          raise Rejected, "Documento compactado excede limites de segurança." if expanded > 50.megabytes
          entries[entry.name] = bytes
        end
      end
      required, @mime = OFFICE.fetch(ext)
      raise Invalid, "Estrutura Office inválida." unless entries.key?(required)
      if ext.start_with?(".od")
        raise Invalid, "Tipo OpenDocument incompatível." unless entries["mimetype"] == @mime
      end
      core = entries["docProps/core.xml"] || entries["meta.xml"]
      if core
        doc = xml(core)
        @metadata["titulo_interno"] = doc.xpath("//*[local-name()='title']").map(&:text).join(" ").first(500)
        @metadata["autor_interno"] = doc.xpath("//*[local-name()='creator' or local-name()='initial-creator']").map(&:text).join(" ").first(500)
      end
      if ext == ".pptx"
        slides = entries.keys.grep(%r{\Appt/slides/slide\d+\.xml\z})
        limit_pages!(slides.size)
        slides.sort_by { |key| key[/slide(\d+)/, 1].to_i }.map { |key| xml(entries[key]).xpath("//*[local-name()='t']").map(&:text).join(" ") }.join("\n\n")
      elsif ext == ".odp"
        doc = xml(entries.fetch("content.xml"))
        slides = doc.xpath("//*[local-name()='page']")
        limit_pages!(slides.size)
        slides.map(&:text).join("\n\n")
      else
        # Native source text keeps every spreadsheet cell; rendered PDF validates effective pages.
        native = if ext == ".docx"
          entries.select { |key, _| key.match?(%r{\Aword/(document|header\d+|footer\d+|footnotes|endnotes)\.xml\z}) }.values.map { |value| xml(value).xpath("//*[local-name()='p']").map(&:text).join("\n") }.join("\n")
        elsif ext == ".xlsx"
          shared = entries["xl/sharedStrings.xml"] ? xml(entries["xl/sharedStrings.xml"]).xpath("//*[local-name()='si']").map(&:text) : []
          entries.select { |key, _| key.match?(%r{\Axl/worksheets/sheet\d+\.xml\z}) }.values.map do |value|
            xml(value).xpath("//*[local-name()='c']").map do |cell|
              content = cell.at_xpath("./*[local-name()='v']")&.text
              cell["t"] == "s" ? shared.fetch(Integer(content)) : cell["t"] == "inlineStr" ? cell.xpath(".//*[local-name()='t']").map(&:text).join : content
            end.join(" ")
          end.join("\n")
        else
          xml(entries.fetch("content.xml")).xpath("//*[local-name()='p' or local-name()='h']").map(&:text).join("\n")
        end
        profile = File.join(@directory, "lo-profile")
        template = ENV["LIBREOFFICE_PROFILE_TEMPLATE"].presence || (File.directory?("/usr/local/share/athenas/lo-profile") ? "/usr/local/share/athenas/lo-profile" : Rails.root.join("tmp/libreoffice-profile").to_s)
        FileUtils.cp_r("#{template}/.", profile) if File.directory?(template)
        FileUtils.mkdir_p(File.join(profile, "user"))
        File.write(File.join(profile, "user/registrymodifications.xcu"), <<~XML)
          <?xml version="1.0"?><oor:items xmlns:oor="http://openoffice.org/2001/registry"><item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop><prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop></item></oor:items>
        XML
        run("libreoffice", "-env:UserInstallation=file://#{profile}", "--headless", "--nologo", "--nodefault", "--norestore", "--convert-to", "pdf", "--outdir", @directory, @path, timeout: 120)
        rendered = File.join(@directory, "input.pdf")
        raise Invalid, "Não foi possível validar as páginas do documento Office." unless File.file?(rendered)
        pdf(rendered, text: false)
        native
      end
    end

    def xml(value)
      raise Rejected, "XML com entidades não permitido." if value.match?(/<!DOCTYPE|<!ENTITY/i)
      Nokogiri::XML(value) { |config| config.strict.nonet }
    end

    def normalize(text)
      text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).delete("\0")
        .gsub("\r\n", "\n").gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
