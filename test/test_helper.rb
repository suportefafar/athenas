ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "webmock/minitest"
require "tempfile"
WebMock.disable_net_connect!(allow_localhost: false)

module TestData
  def create_user(role: "user", **attributes)
    User.create!({ name: "Pessoa", email_address: "#{SecureRandom.hex(6)}@example.test", password: "senha-segura-de-teste", role: role }.merge(attributes))
  end

  def create_lot(status: "ready", uploader: @user || create_user, **attributes)
    Lot.create!({ uploader: uploader, name: "Documento.txt", byte_size: 20, content_type: "text/plain", status: status }.merge(attributes))
  end

  def uploaded_file(text = "Afastamento para capacitação", name: "exemplo.txt", mime: "text/plain")
    file = Tempfile.new([ "upload-", File.extname(name) ])
    file.binmode
    file.write(text)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: name, type: mime)
  end

  def vector(index = 0)
    Array.new(1024, 0.0).tap { |value| value[index] = 1.0 }
  end

  def add_chunk(lot, position: 0, embedding: vector)
    lot.lot_chunks.create!(position: position, text: "Conteúdo", embedding: Embeddings::OllamaClient.sql_vector(embedding))
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "senha-segura-de-teste" }
    assert_redirected_to root_path
  end

  def fake_extraction(text: "Afastamento para capacitação", warnings: [])
    Lots::ExtractionService::Result.new(text: text, content_type: "text/plain", page_count: nil, metadata: {}, warnings: warnings)
  end

  def pdf_document(pages: 1, text: "Afastamento para capacitacao")
    objects = [ "<< /Type /Catalog /Pages 2 0 R >>", "", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>" ]
    kids = []
    pages.times do
      page_id = objects.size + 1
      kids << "#{page_id} 0 R"
      stream_id = page_id + 1
      stream = "BT /F1 24 Tf 40 740 Td (#{text}) Tj ET"
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents #{stream_id} 0 R >>"
      objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
    end
    objects[1] = "<< /Type /Pages /Kids [#{kids.join(' ')}] /Count #{pages} >>"
    output = "%PDF-1.4\n".b
    offsets = [ 0 ]
    objects.each_with_index do |object, i|
      offsets << output.bytesize
      output << "#{i + 1} 0 obj\n#{object}\nendobj\n"
    end
    start = output.bytesize
    output << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.drop(1).each { |offset| output << "%010d 00000 n \n" % offset }
    output << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{start}\n%%EOF\n"
  end
end

class ActiveSupport::TestCase
  include TestData
  include ActiveJob::TestHelper
  self.use_transactional_tests = true
  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Current.reset
  end
end
class ActionDispatch::IntegrationTest
  include TestData
end
