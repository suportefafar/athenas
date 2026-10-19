class LotsController < ApplicationController
  before_action :set_lot

  def show
    @lot.lot_accesses.create!(user: current_user, accessed_at: Time.current)
  end

  def download
    serve_file(:attachment)
  end

  def preview
    return head :unprocessable_entity unless @lot.previewable?
    response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'"
    serve_file(:inline)
  end

  def destroy
    return head :forbidden unless @lot.deletable_by?(current_user)
    Lots::DeletionService.new.call(@lot, actor: current_user)
    redirect_to my_uploads_path, notice: "Lote excluído."
  end

  private

  def set_lot
    @lot = Lot.find(params[:id])
  end

  def serve_file(disposition)
    return head :not_found unless @lot.file.attached?
    # Proxy through the storage interface; never expose a signed blob URL.
    send_data @lot.file.download, filename: @lot.name,
      type: disposition == :inline ? @lot.content_type : "application/octet-stream", disposition: disposition
  end
end
