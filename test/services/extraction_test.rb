require "test_helper"
require_relative "../support/office_documents"
class ExtractionTest < ActiveSupport::TestCase
  include OfficeDocuments

  def extract(bytes, name:, runner: Lots::CommandRunner.new)
    upload = uploaded_file(bytes, name: name)
    Lots::ExtractionService.new(runner: runner).call(upload.tempfile.path, name: name)
  end

  def mock_runner(pages: 1, scanned: [], ocr_failures: [])
    runner = Object.new
    runner.define_singleton_method(:call) do |program, *args, directory:, **options|
      case program
      when "pdfinfo" then "Pages: #{pages}\nTitle: Titulo interno\nAuthor: Autor interno\n"
      when "pdftotext"
        page = args[args.index("-f") + 1]
        scanned.include?(page) ? "" : "Texto da página #{page} financeiro"
      when "pdftoppm" then ""
      when "tesseract"
        if args == [ "--list-langs" ]
          "List of available languages (2):\npor\neng\n"
        else
          page = args.first[/page-(\d+)/, 1].to_i
          raise Lots::CommandRunner::Error if ocr_failures.include?(page)
          "Texto reconhecido capacitação"
        end
      when "libreoffice"
        File.write(File.join(directory, "input.pdf"), "converted")
        ""
      when "python3"
        args.include?("info") ? { pages: pages }.to_json : ""
      else raise "Comando inesperado: #{program}"
      end
    end
    runner
  end

  test "PDF 100 páginas aceito e 101 rejeitado" do
    result = extract(pdf_document, name: "documento.pdf", runner: mock_runner(pages: 100))
    assert_equal 100, result.page_count
    assert_includes result.text, "página 100"
    assert_raises(Lots::ExtractionService::Rejected) { extract(pdf_document, name: "documento.pdf", runner: mock_runner(pages: 101)) }
  end

  test "OCR apenas nas páginas sem texto e falha parcial mantém demais" do
    result = extract(pdf_document, name: "documento.pdf", runner: mock_runner(pages: 3, scanned: [ 2, 3 ], ocr_failures: [ 3 ]))
    assert_includes result.text, "Texto da página 1"
    assert_includes result.text, "Texto reconhecido capacitação"
    assert_match "Página 3", result.warnings.first
  end

  test "TXT JSON CSV XML e MD sem contagem de páginas com encoding" do
    %w[txt json csv xml md].each do |extension|
      result = extract("conteúdo financeiro", name: "documento.#{extension}")
      assert_includes result.text, "financeiro"
      assert_nil result.page_count
    end
    result = extract("açúcar e capacitação".encode("Windows-1252"), name: "documento.txt")
    assert_equal "açúcar e capacitação", result.text
  end

  test "DOCX XLSX PPTX ODT ODS ODP extraem conteúdo e validam páginas" do
    %w[.docx .xlsx .pptx .odt .ods .odp].each do |ext|
      result = extract(office_document(ext), name: "documento#{ext}", runner: mock_runner)
      assert_includes result.text, "financeiro", ext
      assert_equal 1, result.page_count
      assert_empty result.warnings
    end
  end

  test "TIFF multipágina usa páginas e rejeita 101 quadros" do
    # A TIFF signature is enough here because validation and decoding are mocked.
    image = "II*\x00\x08\x00\x00\x00".b + "\0" * 30
    result = extract(image, name: "imagem.tiff", runner: mock_runner(pages: 2))
    assert_equal 2, result.page_count
    assert_raises(Lots::ExtractionService::Rejected) { extract(image, name: "imagem.tiff", runner: mock_runner(pages: 101)) }
  end

  test "Office sem conversor não é liberado com contagem desconhecida" do
    runner = Object.new
    def runner.call(*) = raise Lots::CommandRunner::Error
    assert_raises(Lots::ExtractionService::Invalid) { extract(office_document(".docx"), name: "documento.docx", runner: runner) }
  end

  test "macros XML com entidades e arquivos Office corrompidos são recusados" do
    assert_raises(Lots::ExtractionService::Rejected) { extract(office_document(".docx", macros: true), name: "documento.docx", runner: mock_runner) }
    bad = zip_document("word/document.xml" => '<!DOCTYPE x [<!ENTITY x SYSTEM "file:///etc/passwd">]><x>&x;</x>')
    assert_raises(Lots::ExtractionService::Rejected) { extract(bad, name: "documento.docx", runner: mock_runner) }
    assert_raises(Lots::ExtractionService::Invalid) { extract("PK\x03\x04corrompido", name: "documento.docx", runner: mock_runner) }
  end

  test "apresentação com mais de 100 slides e excesso de entradas recusados" do
    assert_raises(Lots::ExtractionService::Rejected) { extract(office_document(".pptx", slides: 101), name: "documento.pptx", runner: mock_runner) }
    entries = 2001.times.to_h { |i| [ "word/entry#{i}.xml", "<x/>" ] }
    assert_raises(Lots::ExtractionService::Rejected) { extract(zip_document(entries), name: "documento.docx", runner: mock_runner) }
  end

  test "formato desconhecido fica apenas com metadados sem executar comandos" do
    result = extract("arquivo sem suporte", name: "documento.unknown", runner: Object.new)
    assert_empty result.text
    assert_match "Conteúdo não extraído", result.warnings.first
  end

  test "chunker limita tamanho mantém sobreposição e aceita vazio" do
    chunks = Lots::Chunker.new.call((1..900).map { |i| "palavra#{i}" }.join(" "))
    assert chunks.all? { |chunk| chunk.split.size <= 375 }
    assert_equal chunks.first.split.last(60), chunks[1].split.first(60)
    assert_empty Lots::Chunker.new.call("")
  end
end
