# frozen_string_literal: true

[[-100, "Judge GPT"], [-101, "GPT bot"]].each do |id, chatbot_name|
  user = User.find_by(id: id)
  if !user
    suggested_username = UserNameSuggester.suggest(chatbot_name)
    User.seed do |u|
      u.id = id
      u.name = chatbot_name
      u.username = suggested_username
      u.username_lower = suggested_username.downcase
      u.password = SecureRandom.hex
      u.active = true
      u.approved = true
      u.trust_level = TrustLevel[4]
      u.admin = true
      u.email = "invalid@#{SecureRandom.hex}.com}"
    end
  end
end
