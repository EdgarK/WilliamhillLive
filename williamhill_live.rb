require "rubygems"
require "net/http"
require "nokogiri"
require_relative "uri_cache"

class WilliamhillLive
  URL = "http://pricefeeds.williamhill.com/bet/en-gb?action=GoPriceFeed"
  LIVE_LINE_NAME = /LIVE Betting In-running/
  SPORT_NAME_PATTERN = /(Football)|(Hockey)/
  SPORT_NAME_TRANSLATION = {'Football' => 'soccer'}
  PASS_TYPES_PATTERN = /([0-9]+(th|st).* Min(ute|s)|Before\/After [0-9]+ Mins)/

  def parse()
    xmls = get_xmls
    #puts xmls.inspect

    xmls.each do |xml|
      test = Nokogiri::XML.parse(xml)
      sport = test.xpath('//williamhill/class').first
      next unless sport
      sport_name = sport['name']
      sport.xpath('type').each do |league|
        league_name = league['name']
        league.xpath('market').each do |market|
          teams, market_type = market['name'].split(' - ',2)
          next if market_type =~ PASS_TYPES_PATTERN
          home_team, away_team = teams.split(' v ')
          puts "Home => #{home_team} ; Away => #{away_team}    -----     #{market_type}"
        end

      end
      puts 'sds'
    end


  end

  def get_xmls()
    body = UriCache.get(URL)
    nodeset = Nokogiri.parse(body)
    main_table = nodeset.css('table')
    rows = main_table.css('tr')
    xmls = []
    rows.each do |row|
      if row.css('td').first && row.css('td').first['colspan'] == '3'
        if row.css('td').first.text =~ LIVE_LINE_NAME
          next
        else
          break
        end
      end
      next if row.css('th').length > 0
      xml_uri = row.css('td')[2].css('a')[0]['href']
      #redir = UriCache.get(xml_uri).match(/http:\/\/[^"]+/).to_s
      xmls << UriCache.get(xml_uri)
    end
    xmls
  end
end