class Api::V1::Accounts::Conversations::WhatsappGroupController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_whatsapp_group
  before_action :ensure_administrator, only: [:remove_participants]

  def show
    render json: group_payload(client.group_info(@conversation.group_source_id))
  rescue Whatsapp::Groups::ApiError => e
    render json: group_payload(nil).merge(error: e.message, details: e.body), status: :unprocessable_entity
  end

  def invite_link
    response = client.invite_link(@conversation.group_source_id)
    store_invite_link(response['invite_link']) if response.is_a?(Hash) && response['invite_link'].present?
    render json: response
  rescue Whatsapp::Groups::ApiError => e
    render json: { error: e.message, details: e.body }, status: :unprocessable_entity
  end

  def remove_participants
    participants = normalized_participants
    return render json: { error: 'participants is required' }, status: :unprocessable_entity if participants.blank?
    if participants.size > Whatsapp::Groups::Client::PARTICIPANT_LIMIT
      return render json: { error: 'a group remove accepts at most 8 participants' }, status: :unprocessable_entity
    end

    render json: client.remove_participants(@conversation.group_source_id, participants)
  rescue Whatsapp::Groups::ApiError => e
    render json: { error: e.message, details: e.body }, status: :unprocessable_entity
  end

  private

  def ensure_whatsapp_group
    channel = @conversation.inbox.channel
    return if @conversation.group? && channel.is_a?(Channel::Whatsapp) && channel.groups_enabled? && @conversation.group_source_id.present?

    render json: { error: I18n.t('errors.whatsapp.groups_disabled') }, status: :unprocessable_entity
  end

  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'Administrator access required' }, status: :forbidden
  end

  def client
    @client ||= Whatsapp::Groups::Client.new(channel: @conversation.inbox.channel)
  end

  def group_payload(info)
    {
      group_source_id: @conversation.group_source_id,
      group_title: @conversation.group_title,
      stored_invite_link: @conversation.additional_attributes&.dig('whatsapp_group', 'invite_link'),
      info: info
    }
  end

  def store_invite_link(invite_link)
    attributes = @conversation.additional_attributes.is_a?(Hash) ? @conversation.additional_attributes.deep_dup : {}
    attributes['whatsapp_group'] = (attributes['whatsapp_group'] || {}).merge('invite_link' => invite_link)
    @conversation.update!(additional_attributes: attributes)
  end

  def normalized_participants
    Array(params[:participants]).filter_map { |participant| participant_identifier(participant) }
  end

  def participant_identifier(participant)
    data = participant.respond_to?(:to_unsafe_h) ? participant.to_unsafe_h.symbolize_keys : participant.symbolize_keys
    user = data[:user].presence
    user_id = data[:user_id].presence
    return { user: user } if user.present? && user_id.blank?
    return { user_id: user_id } if user_id.present? && user.blank?

    nil
  end
end
