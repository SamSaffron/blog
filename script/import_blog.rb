`dropdb blog`
`createdb blog`
`bundle exec rake db:migrate`

require 'mysql2'

@client = Mysql2::Client.new(:host => "localhost", :username => "root", :password => "password", :database => "blog_development")


require File.expand_path(File.dirname(__FILE__) + "/../../../config/environment")
SiteSetting.email_domains_blacklist = ''
RateLimiter.disable

def create_admin
  User.new.tap { |admin|
    admin.email = "sam.saffron@gmail.com"
    admin.username = "sam"
    admin.password = SecureRandom.uuid
    admin.save
    admin.grant_admin!
    admin.change_trust_level!(:regular)
    admin.email_tokens.update_all(confirmed: true)
  }
end

def ensure_user(name, email, website)
  name = "user" if name.blank?

  name = User.suggest_name(name || email)
  username = UserNameSuggester.suggest(name || email)
  if email.blank?
    email = "#{SecureRandom.uuid}@domain.com"
  end

  email = email.downcase


  user = User.where(email: email).first
  unless user
    user = User.new(email: email, username: username, name: name, website: website)
    user.save!
  end

  user
end


def create_topic(user,result)
  post = PostCreator.create(user,
                        created_at: result["created_at"],
                        updated_at: result["updated_at"],
                        raw: result["body"],
                        title: result["title"],
                        meta_data: {permalink: result["permalink"], summary: result["summary"]},
                        skip_validations: true)

  p result["permalink"]
  comments = @client.query("select * from comments where post_id = #{result["id"]} and approved order by created_at asc").to_a

  responses = @client.query("select comment_id, body, created_at from comment_responses
                              where comment_id in (select id from comments where post_id = #{result["id"]}) ").to_a
  map = {}
  responses.each do |response|
    map[response["comment_id"]] = response
  end

  comments.each do |c|
    user = ensure_user(c["name"], c["email"], c["website"])
    post = PostCreator.create(user, topic_id: post.topic_id, raw: c["body"], created_at: c["created_at"], updated_at: c["created_at"], skip_validations: true)

    if response = map[c["id"]]

      PostCreator.create(@admin, topic_id: post.topic_id,
                                raw: response["body"],
                                created_at: response["created_at"],
                                updated_at: response["created_at"],
                                reply_to_post_number: post.post_number,
                                skip_validations: true)
    end
  end
end

results = @client.query("select * from posts where published order by created_at desc").to_a
@admin = User.where(email: 'sam.saffron@gmail.com').first || create_admin
results.each do |r|
  create_topic(@admin, r)
end

Topic.exec_sql('update topics set bumped_at = (select max(created_at) from posts where topic_id = topics.id)')


