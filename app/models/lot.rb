class Lot < ApplicationRecord
  STATUSES = %w[pending processing ready partial failed rejected].freeze
  STATUS_LABELS = { "pending" => "Aguardando processamento", "processing" => "Em processamento", "ready" => "Indexado", "partial" => "Indexação incompleta", "failed" => "Falha no processamento", "rejected" => "Rejeitado" }.freeze
  SAFE_PREVIEWS = %w[application/pdf image/png image/jpeg image/webp].freeze
  belongs_to :uploader, class_name: "User"
  has_one_attached :file
  has_many :lot_chunks, dependent: :delete_all
  has_many :lot_accesses, dependent: :delete_all
  validates :name, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: STATUSES }
  scope :searchable, -> { where(status: %w[ready partial]) }

  def deletable_by?(user) = user.admin? || uploader_id == user.id
  def status_label = STATUS_LABELS.fetch(status)
  def previewable? = SAFE_PREVIEWS.include?(content_type) && %w[ready partial].include?(status)

  def self.popular
    searchable.joins(:lot_accesses).where(lot_accesses: { accessed_at: 30.days.ago.. })
      .group("lots.id").order(Arel.sql("COUNT(lot_accesses.id) DESC, MAX(lot_accesses.accessed_at) DESC, lots.id DESC")).limit(10)
  end
end
