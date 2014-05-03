@url = url_for(:only_path => false).gsub("/posts", "")

xml.instruct!
xml.feed "xmlns" => "http://www.w3.org/2005/Atom" do

  xml.title   "Sam Saffron's blog"
  xml.link    "rel" => "self", "href" => @url + "/posts.atom"
  xml.link    "rel" => "alternate", "href" => @url
  xml.id      url_for(:only_path => false)
  xml.updated @topics.first.created_at.strftime "%Y-%m-%dT%H:%M:%SZ"
  xml.author  { xml.name "Sam Saffron" }

  @topics.each do |topic|
    xml.entry do
      xml.title   topic.title
      xml.link    "rel" => "alternate", "href" => @url + topic.permalink
      xml.id      @url + topic.permalink
      xml.updated topic.created_at.strftime "%Y-%m-%dT%H:%M:%SZ"
      xml.author  { xml.name "Sam Saffron" }
      xml.summary topic.custom_fields["cooked_summary"]
      xml.content "type" => "html" do
        xml.text! topic.cooked
      end
    end
  end

end

