class Whatsapp::Groups::ApiError < StandardError
  attr_reader :status, :body

  def initialize(status, body)
    @status = status
    @body = body
    super(message_from(body) || "WhatsApp Groups API error (#{status})")
  end

  private

  def message_from(body)
    return unless body.is_a?(Hash)

    body.dig('error', 'message') || body['message']
  end
end
