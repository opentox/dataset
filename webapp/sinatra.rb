# sinatra.rb
# Common service
# Author: Andreas Maunz

module OpenTox
  class Application < Service

    # Get url_for support
    helpers Sinatra::UrlForHelper

    # Conveniently accessible from anywhere within the Application class,
    # it negotiates the appropriate output format based on object class
    # and requested MIME type.
    # @param [Object] an object
    # @return [String] object serialization
    def format_output (obj)

      if obj.class == String

        case @accept
          when /text\/html/
            content_type "text/html"
            OpenTox.text_to_html obj
          else
            content_type 'text/uri-list'
            obj
        end

      else
  
        case @accept
          when "application/rdf+xml"
            content_type "application/rdf+xml"
            obj.to_rdfxml
          when /text\/html/
            content_type "text/html"
            OpenTox.text_to_html obj.to_turtle
          else
            content_type "text/turtle"
            obj.to_turtle
        end
  
      end
    end

  end
end
