class UploadsController < ApplicationController
  def new; end

  def create
    accepted = 0
    errors = []
    Array(params[:files]).reject(&:blank?).each do |file|
      Lots::UploadService.new.call(file, uploader: current_user)
      accepted += 1
    rescue Lots::UploadService::InvalidUpload => e
      errors << e.message
    end
    if accepted.positive?
      flash[:notice] = "Arquivo recebido. Ele será processado em segundo plano. Você receberá um e-mail quando o processamento terminar. (#{accepted} arquivo(s))"
    end
    flash[:alert] = errors.join(" ") if errors.any?
    flash[:alert] = "Selecione ao menos um arquivo." if accepted.zero? && errors.empty?
    redirect_to my_uploads_path
  end
end
