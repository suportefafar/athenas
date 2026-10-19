namespace :lots do
  desc "Reindexa lotes seguros; ID opcional. Oculta durante o processamento."
  task reindex: :environment do
    scope = ENV["ID"].present? ? Lot.where(id: ENV["ID"]) : Lot.searchable
    scope.find_each do |lot|
      lot.with_lock do
        lot.update!(status: "pending", notified_at: nil, processing_error: nil)
        ProcessLotJob.perform_later(lot.id)
      end
    end
  end
end
namespace :athenas do
  desc "Verifica banco, OCR, conversor e modelo local (sem documentos)"
  task doctor: :environment do
    puts "PostgreSQL: #{ApplicationRecord.connection.select_value('SELECT version()').split.first(2).join(' ')}"
    puts "Extensões: #{ApplicationRecord.connection.select_values("SELECT extname FROM pg_extension WHERE extname IN ('vector','unaccent')").join(', ')}"
    Dir.mktmpdir("athenas-doctor-") do |directory|
      %w[pdfinfo tesseract libreoffice].each do |command|
        begin
          args = case command
          when "tesseract" then [ "--list-langs" ]
          when "pdfinfo" then [ "-v" ]
          else [ "--version" ]
          end
          Lots::CommandRunner.new.call(command, *args, directory: directory)
          puts "#{command}: OK (isolamento ativo)"
        rescue Lots::CommandRunner::Error
          puts "#{command}: indisponível ou isolamento incompatível"
        end
      end
    end
    begin
      Embeddings::OllamaClient.new.call("Diagnóstico do Athenas")
      puts "Ollama/modelo: OK"
    rescue Embeddings::OllamaClient::Unavailable
      puts "Ollama/modelo: indisponível; processamento ficará parcial e fallback semântico indisponível"
    end
    puts Rails.env.production? ? "E-mail: SMTP configurado" : "E-mail: captura em tmp/mail (sem envio externo)"
  end
end
