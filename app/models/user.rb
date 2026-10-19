class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :chat_conversations, dependent: :destroy
  has_many :lots, foreign_key: :uploader_id, inverse_of: :uploader
  normalizes :email_address, with: ->(value) { value.strip.downcase }
  validates :name, presence: true, length: { maximum: 150 }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: %w[admin user] }
  validates :password, length: { minimum: 12 }, allow_nil: true
  validate :protect_admin
  before_destroy { throw :abort if admin? }

  def admin? = role == "admin"
  def invited? = invitation_digest.present?

  def invite!
    token = SecureRandom.urlsafe_base64(32)
    update!(invitation_digest: Digest::SHA256.hexdigest(token), invitation_sent_at: Time.current)
    token
  end

  def self.from_invitation(token)
    return if token.blank?
    find_by(invitation_digest: Digest::SHA256.hexdigest(token))&.then do |user|
      user if user.invitation_sent_at > 48.hours.ago
    end
  end

  private

  def protect_admin
    if persisted? && role_in_database == "admin" && role != "admin"
      errors.add(:role, "não pode remover o administrador")
    end
  end
end
