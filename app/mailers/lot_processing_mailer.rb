class LotProcessingMailer < ApplicationMailer
  def completed(lot)
    @lot = lot
    mail(to: lot.uploader.email_address, subject: "Athenas — processamento: #{lot.status_label}")
  end
end
