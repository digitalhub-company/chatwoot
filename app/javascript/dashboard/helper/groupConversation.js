export const conversationDisplayName = (chat, contactName) => {
  if (chat?.group) {
    return chat.group_title || contactName || '';
  }

  return contactName || '';
};
