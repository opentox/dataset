#OT_LOGO = File.join(CONFIG[:services]["opentox-validation"],"resources/ot-logo.png")

# AM: needed since this gem has a nested directory structure
require 'sinatra/url_for'

class String
  # encloses URI in text with with link tag
  # @return [String] new text with marked links
  def link_urls
    regex = Regexp.new '(https?:\/\/[\S]+)([>"])'
    self.gsub( regex, '<a href="\1">\1</a>\2' )
  end
end

module OpenTox
  
  # produces a html page for making web services browser friendly
  # format of text (=string params) is preserved (e.g. line breaks)
  # urls are marked as links
  #
  # @param [String] text this is the actual content, 
  # @param [optional,String] related_links info on related resources
  # @param [optional,String] description general info
  # @param [optional,Array] post_command, infos for the post operation, object defined below
  # @return [String] html page
  def self.text_to_html( text, subjectid=nil, related_links=nil, description=nil, post_command=nil  )
    
    # TODO add title as parameter
    title = nil #$sinatra.url_for($sinatra.request.env['PATH_INFO'], :full) if $sinatra
    html = "<html>"
    html += "<title>"+title+"</title>" if title
    #html += "<img src=\""+OT_LOGO+"\"><\/img><body>"
      
    html += "<h3>Description</h3><pre><p>"+description.link_urls+"</p></pre>" if description
    html += "<h3>Related links</h3><pre><p>"+related_links.link_urls+"</p></pre>" if related_links
    html += "<h3>Content</h3>" if description || related_links
    html += "<pre><p style=\"padding:15px; border:10px solid \#5D308A\">"
    html += text.link_urls
    html += "</p></pre></body></html>"
    html
  end
  
end
