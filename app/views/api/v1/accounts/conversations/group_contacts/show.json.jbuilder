json.meta do
  json.count @total_count
  json.current_page @current_page.to_i
end

json.payload do
  json.array! @group_contacts do |group_contact|
    json.id group_contact.id
    json.contact_id group_contact.contact_id
    json.contact do
      json.partial! 'api/v1/models/contact', formats: [:json], resource: group_contact.contact
    end
  end
end
