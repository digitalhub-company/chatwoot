class Api::V1::Accounts::Inboxes::WhatsappGroupsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_administrator
  before_action :ensure_groups_enabled, only: [:index, :create]

  def index
    return render json: { error: 'limit must be between 1 and 1024' }, status: :unprocessable_entity if params[:limit].present? && !limit_param

    render json: client.list_groups(limit: limit_param, after: params[:after], before: params[:before])
  rescue Whatsapp::Groups::ApiError => e
    render json: { error: e.message, details: e.body }, status: :unprocessable_entity
  end

  def enable
    enroll(true)
  end

  def disable
    enroll(false)
  end

  def create
    error = group_params_error
    return render json: { error: error }, status: :unprocessable_entity if error

    render json: client.create_group(
      subject: params[:subject].to_s.strip,
      description: params[:description].presence,
      join_approval_mode: params[:join_approval_mode].presence || 'auto_approve'
    )
  rescue Whatsapp::Groups::ApiError => e
    render json: { error: e.message, details: e.body }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'Administrator access required' }, status: :forbidden
  end

  def enroll(enabled)
    channel = @inbox.channel
    unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
      return render json: { error: I18n.t('errors.whatsapp.groups_unsupported_provider') }, status: :unprocessable_entity
    end

    channel.provider_config = channel.provider_config.merge('groups_enabled' => enabled)
    Whatsapp::WebhookSetupService.new(channel).register_callback
    channel.save!(validate: false)
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def ensure_groups_enabled
    channel = @inbox.channel
    return if channel.is_a?(Channel::Whatsapp) && channel.groups_enabled?

    render json: { error: I18n.t('errors.whatsapp.groups_disabled') }, status: :unprocessable_entity
  end

  def client
    @client ||= Whatsapp::Groups::Client.new(channel: @inbox.channel)
  end

  def limit_param
    return if params[:limit].blank?

    limit = params[:limit].to_i
    return limit if limit.between?(1, 1024)

    nil
  end

  def group_params_error
    subject = params[:subject].to_s.strip
    return 'subject is required' if subject.blank?
    return 'subject is too long' if subject.length > Whatsapp::Groups::Client::SUBJECT_MAX

    description = params[:description].to_s
    return 'description is too long' if description.length > Whatsapp::Groups::Client::DESCRIPTION_MAX

    mode = params[:join_approval_mode].presence || 'auto_approve'
    return 'join_approval_mode must be auto_approve or approval_required' unless Whatsapp::Groups::Client::JOIN_APPROVAL_MODES.include?(mode)

    nil
  end
end
