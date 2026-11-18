class Whatsapp::Groups::Client
  # https://developers.facebook.com/docs/whatsapp/cloud-api/groups
  # https://developers.facebook.com/documentation/business-messaging/whatsapp/groups/reference
  SUBJECT_MAX = 128
  DESCRIPTION_MAX = 2048
  PARTICIPANT_LIMIT = 8
  GROUP_INFO_FIELDS = 'subject,description,participants,join_approval_mode,total_participant_count,suspended,creation_timestamp'.freeze
  JOIN_APPROVAL_MODES = %w[auto_approve approval_required].freeze

  pattr_initialize [:channel!]

  def create_group(subject:, description: nil, join_approval_mode: 'auto_approve')
    body = {
      messaging_product: 'whatsapp',
      subject: subject
    }
    body[:description] = description if description.present?
    body[:join_approval_mode] = join_approval_mode

    post("#{phone_number_id}/groups", body)
  end

  def list_groups(limit: nil, after: nil, before: nil)
    query = { limit: limit, after: after, before: before }.compact
    get("#{phone_number_id}/groups", query)
  end

  def group_info(group_id)
    get(group_id, { fields: GROUP_INFO_FIELDS })
  end

  def invite_link(group_id)
    get("#{group_id}/invite_link")
  end

  def remove_participants(group_id, participants)
    delete("#{group_id}/participants", { messaging_product: 'whatsapp', participants: participants })
  end

  private

  def post(path, body)
    request(:post, path, body: body.to_json)
  end

  def get(path, query = nil)
    request(:get, path, query: query.presence)
  end

  def delete(path, body)
    request(:delete, path, body: body.to_json)
  end

  def request(verb, path, options)
    response = HTTParty.public_send(verb, url(path), { headers: headers }.merge(options.compact))
    parsed = response.parsed_response
    return parsed if response.success?

    raise Whatsapp::Groups::ApiError.new(response.code, parsed)
  end

  def url(path)
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{api_version}/#{path}"
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def headers
    {
      'Authorization' => "Bearer #{channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def phone_number_id
    channel.provider_config['phone_number_id']
  end
end
