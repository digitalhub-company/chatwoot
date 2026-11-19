class Api::V1::Accounts::Conversations::GroupContactsController < Api::V1::Accounts::Conversations::BaseController
  RESULTS_PER_PAGE = 100

  before_action :ensure_group_conversation, only: [:create, :update, :destroy]
  before_action :validate_contact_ids, only: [:create, :update, :destroy]
  before_action :set_page, only: [:show, :update]

  def show
    load_group_contacts
  end

  def create
    ActiveRecord::Base.transaction do
      @group_contacts = contacts_to_be_added_ids.map do |contact_id|
        @conversation.group_contacts.create!(contact_id: contact_id)
      end
    end
  end

  def update
    ActiveRecord::Base.transaction do
      contacts_to_be_added_ids.each { |contact_id| @conversation.group_contacts.create!(contact_id: contact_id) }
      contacts_to_be_removed_ids.each { |contact_id| @conversation.group_contacts.find_by(contact_id: contact_id)&.destroy! }
    end
    load_group_contacts
    render :show
  end

  def destroy
    ActiveRecord::Base.transaction do
      params[:contact_ids].each { |contact_id| @conversation.group_contacts.find_by(contact_id: contact_id)&.destroy! }
    end
    head :ok
  end

  private

  def load_group_contacts
    @total_count = @conversation.group_contacts.count
    @group_contacts = @conversation.group_contacts.includes(:contact).page(@current_page).per(RESULTS_PER_PAGE)
  end

  def ensure_group_conversation
    return if @conversation.group?

    render json: { error: 'Conversation must be a group' }, status: :unprocessable_entity
  end

  def validate_contact_ids
    return if params[:contact_ids].is_a?(Array)

    render json: { error: 'contact_ids must be an array' }, status: :unprocessable_entity
  end

  def contacts_to_be_added_ids
    params[:contact_ids].map(&:to_i) - current_group_contact_ids
  end

  def contacts_to_be_removed_ids
    current_group_contact_ids - params[:contact_ids].map(&:to_i)
  end

  def current_group_contact_ids
    @current_group_contact_ids ||= @conversation.group_contacts.pluck(:contact_id)
  end

  def set_page
    @current_page = params[:page] || 1
  end
end
