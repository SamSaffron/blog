module Blog
  class UpdateStackOverflow < ::Jobs::Scheduled
    recurrence { hourly }

    def execute(args)
      payload = Rubyoverflow::Answers.retrieve_by_user(17174, :sort => :creation, :pagesize => 5)
      answers = payload.answers.map{|a| {:title => a.title, :id => a.answer_id, :date => Time.at(a.creation_date).to_datetime}}
      Rails.cache.write("so_answers", {answers: answers}, :expires_in => 2.days)
    end

  end
end

