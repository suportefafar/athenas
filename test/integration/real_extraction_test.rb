require "test_helper"
require_relative "../support/office_documents"
class RealExtractionTest < ActiveSupport::TestCase
  include OfficeDocuments
  setup { skip "Execute RUN_EXTRACTION_TESTS=1 no Docker para OCR/conversão reais." unless ENV["RUN_EXTRACTION_TESTS"] == "1" }

  def extract(bytes, name:)
    upload = uploaded_file(bytes, name: name)
    Lots::ExtractionService.new.call(upload.tempfile.path, name: name)
  end

  test "Poppler real extrai PDF e rejeita 101 páginas" do
    result = extract(pdf_document, name: "textual.pdf")
    assert_match "capacitacao", result.text
    assert_empty result.warnings
    assert_equal 1, result.page_count
    assert_raises(Lots::ExtractionService::Rejected) { extract(pdf_document(pages: 101), name: "longo.pdf") }
  end

  test "LibreOffice real valida DOCX e XLSX e preserva texto de tabelas e células" do
    %w[.docx .xlsx].each do |ext|
      result = extract(office_document(ext), name: "documento#{ext}")
      assert_match "financeiro", result.text
      assert result.page_count.positive?
      assert_empty result.warnings
    end
  end

  test "Tesseract real reconhece imagem e PDF digitalizado e TIFF multipágina" do
    Dir.mktmpdir("athenas-fixture-") do |directory|
      original = File.join(directory, "original.pdf")
      File.binwrite(original, pdf_document(text: "AFASTAMENTO CAPACITACAO FINANCEIRO"))
      runner = Lots::CommandRunner.new
      runner.call("pdftoppm", "-png", "-singlefile", "-scale-to", "2500", original, File.join(directory, "scan"), directory: directory)
      scan = File.binread(File.join(directory, "scan.png"))
      image = extract(scan, name: "scan.png")
      assert_match(/AFASTAMENTO/i, image.text)
      assert_empty image.warnings
      script = 'from PIL import Image; import sys; im=Image.open(sys.argv[1]).convert("RGB"); im.save(sys.argv[2], "PDF"); im.save(sys.argv[3], "TIFF", save_all=True, append_images=[im], compression="tiff_deflate")'
      runner.call("python3", "-c", script, File.join(directory, "scan.png"), File.join(directory, "scan.pdf"), File.join(directory, "scan.tiff"), directory: directory)
      result = extract(File.binread(File.join(directory, "scan.pdf")), name: "scan.pdf")
      assert_match(/AFASTAMENTO/i, result.text)
      assert_empty result.warnings
      tiff = extract(File.binread(File.join(directory, "scan.tiff")), name: "scan.tiff")
      assert_equal 2, tiff.page_count
      assert_match(/AFASTAMENTO/i, tiff.text)
    end
  end

  test "subprocessos não acessam rede segredos ou variáveis da aplicação" do
    Dir.mktmpdir("athenas-isolation-") do |directory|
      runner = Lots::CommandRunner.new
      result = runner.call("python3", "-c", 'import os; print(os.getenv("DATABASE_URL", "ausente"))', directory: directory)
      assert_equal "ausente", result.strip
      assert_raises(Lots::CommandRunner::Error) do
        runner.call("python3", "-c", 'import socket; socket.create_connection(("127.0.0.1", 5432))', directory: directory)
      end
      secret = Rails.root.join("tmp/isolation-secret")
      File.write(secret, "NAO LER")
      assert_raises(Lots::CommandRunner::Error) do
        runner.call("python3", "-c", "import sys; print(open(sys.argv[1]).read())", secret, directory: directory)
      end
    ensure
      FileUtils.rm_f(secret) if secret
    end
  end
end
