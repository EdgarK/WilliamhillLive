require "rubygems"
require "net/http"
require "nokogiri"
require_relative "uri_cache"

class WilliamhillLive
  URL = "http://pricefeeds.williamhill.com/bet/en-gb?action=GoPriceFeed"
  LIVE_LINE_NAME = /LIVE Betting In-running/
  SPORT_NAME_PATTERN = /(Football)|(Hockey)/
  SPORT_NAME_TRANSLATION = {'Football' => 'soccer'}
  PASS_TYPES_PATTERN = /([0-9]+(th|st).* Min(ute|s)|Before\/After [0-9]+ Mins|Goal|Puck|Correct Score|Total Pts|Winning Margin|Live Score|minutes|Easy As 1-2-3|To Win To Nil|Highest Scoring Period Live|Clean Sheet|To Score Both Halves)/

  def parse()
    xmls = get_xmls
    #puts xmls.inspect

    n = 0
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
          if market_type == 'Both Teams To Score Live'
            parse_both_teams_to_score()
          elsif market_type == 'Corners'
            #'1st Half Corners Live'
            parse_total_corners()
          elsif market_type == 'Total Match Goals Odd/Even Live' || market_type =~ /Total Games Odd\/Even/
            parse_total_odd_even()
          elsif market_type == 'Draw No Bet Live'
            parse_draw_no_bet()
          else
            puts "Home => #{home_team} ; Away => #{away_team}    -----     #{market_type}"
            n+=1
          end
        end

      end
      puts 'sds'
    end
    puts "total_not_parsed => #{n}"

  end

  def parse_draw_no_bet()
    puts "!!!!!!!DNB1 DNB2!!!!!!!"
  end

  def parse_total_odd_even()
    puts "!!!!!!!!ODD EVEN!!!!!!!"
  end

  def parse_total_corners()
    puts "!!!!!!!!!!!CNR_TO CNR_TU!!!!!!!!"
  end

  def parse_both_teams_to_score()
    puts "!!!!!!!!!!! BTS_Y !!!!!!!!!!!!"
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