require "rubygems"
require "net/http"
require "digest/md5"

class UriCache
  def self.get(uri)
    cache_uri = "cache/#{Digest::MD5.hexdigest(uri)}.xml"
    Dir.mkdir 'cache' unless File.directory? 'cache'
    if File.file? cache_uri
      body = File.open(cache_uri).read
    else
      response = Net::HTTP.get_response(URI.parse(uri))
      if response.kind_of?(Net::HTTPRedirection)
        body = Net::HTTP.get(URI.parse(self.redirect_url(response)))
      else
        body = response.body
      end
      file = File.open(cache_uri, 'w')
      file.write(body)
      file.close
    end
    body
  end

  def self.redirect_url(response)
    if response['location'].nil?
      response.body.match(/<a href=\"([^>]+)\">/i)[1]
    else
      response['location']
    end
  end
end