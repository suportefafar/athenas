require "net/http"
require "uri"
require "json"

class HermesDeliveryMethod
  def initialize(_settings = {})
  end

  def deliver!(mail)
    base_url = ENV.fetch("HERMES_API_URL", "http://hermes:80")
    token = ENV.fetch("HERMES_API_TOKEN")
    uri = URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", "api/v1/messages")

    payload = {
      to_addresses: mail.to,
      subject: mail.subject,
      body_html: mail.html_part&.decoded || mail.body.decoded
    }
    payload[:from_address] = mail.from if mail.from.present?
    payload[:reply_to] = mail.reply_to if mail.reply_to.present?
    payload[:cc_addresses] = mail.cc if mail.cc.present?
    payload[:bcc_addresses] = mail.bcc if mail.bcc.present?

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(payload)

    response = Net::HTTP.start(
      uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: 5, read_timeout: 15, write_timeout: 15
    ) { |http| http.request(request) }
    return if response.is_a?(Net::HTTPAccepted)

    raise DeliveryError, "O gateway de e-mail respondeu HTTP #{response.code}."
  end

  class DeliveryError < StandardError; end
end
