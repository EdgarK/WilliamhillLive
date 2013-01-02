require "rubygems"
require "net/http"
require "nokogiri"
require_relative "uri_cache"

class WilliamhillLive
  attr_accessor :sport_name, :home_team, :away_team, :market_type, :league_name, :market, :result, :period

  URL = "http://pricefeeds.williamhill.com/bet/en-gb?action=GoPriceFeed"
  LIVE_LINE_NAME = /LIVE Betting In-running/
  SPORT_NAME_PATTERN = /(Football)|(European Major Leagues)|(Hockey)|(Basketball)|(Volleyball)|(Tennis)/
  PASS_SPORT_NAMES_PATTERNS = /(Newcastle Hotbox)/
  SPORT_NAME_TRANSLATION = {'Football' => 'soccer', 'European Major Leagues' => 'soccer'}
  PASS_TYPES_PATTERN = /([0-9]+(th|st).* Min(ute|s)|Before\/After [0-9]+ Mins|Puck|Correct Score|Total Pts|Winning Margin|Live Score|minutes|Easy As 1-2-3|To Win To Nil|Highest Scoring Period Live|Clean Sheet|To Score Both Halves|Win To Deuce|Match Betting Live|Set Race To|Set - Point)/
  UNUSUAL_MAIN_LINE_NUMBERS_PATTERN = /(Tennis|Basketball)/

  def initialize()
    @sport_name = @home_team = @away_team = @market_type = @league_name = @period = nil
    @result = {}
  end

  def league_name=(name)
    @result[sport_name][name] ||= {}
    @league_name = name
  end





  def parse()
    xmls = get_xmls

    xmls.each do |xml|
      test = Nokogiri::XML.parse(xml)
      sport = test.xpath('//williamhill/class').first
      next unless sport
      self.sport_name = parse_sport_name(sport['name'])
      if !sport_name || sport_name == ''
        puts "Log:     Don't know this kind of sport #{sport['name']}"
        next
      end
      sport.xpath('type').each do |league|
        self.league_name = league['name']
        league.xpath('market').each do |market|
          @market = market
          teams, self.market_type = market['name'].split(' - ',2)
          next if market_type =~ PASS_TYPES_PATTERN
          self.home_team, self.away_team = teams.split(' v ')
          parse_evt_name()
          parse_periods()
          if market_type == 'Both Teams To Score Live'
            parse_both_teams_to_score()
          elsif market_type =~ /Corners/
            parse_total_corners()
          elsif market_type =~ /(Total Match|Half) Goals Odd\/Even Live/ || market_type =~ /Total Games Odd\/Even/
            parse_total_odd_even()
          elsif market_type == 'Draw No Bet Live'
            parse_draw_no_bet()
          elsif market_type == 'Double Result Live' || market_type =~ /Set Winner/
            parse_winner()
          elsif market_type =~ /Under\/Over/
            parse_under_over()
          elsif market_type == 'Teams To Score Live'
            parse_teams_to_score()
          elsif market_type =~ /Handicap [0-9+-]+ Live/
            parse_handicap()
          else
            #puts "Home => #{home_team} ; Away => #{away_team}    -----     #{market_type}"
          end
        end

      end
    end
    puts @result.inspect
  end

  def parse_evt_name
    @evt_name = "#{home_team}, #{away_team}, #{market['date']}-#{market['time']}"
    @result[sport_name][league_name][@evt_name] ||= []
  end

  def parse_sport_name(sport_val)
    name = SPORT_NAME_TRANSLATION[sport_val.match(SPORT_NAME_PATTERN).to_s]
    name = ((name)? name : sport_val.match(SPORT_NAME_PATTERN).to_s)
    self.result[name]||={}  unless name == ''
    name
  end

  def add_to_result(arr)
    @result[sport_name][league_name][@evt_name] << arr
  end

  def parse_handicap()
    #puts "!!!!!!! F1 F2 !!!!!!!!!!!"
    #period = parse_periods(market_type)
    val = market_type.match(/Handicap ([0-9+-]+)/)[1]
    koefF1 = market.xpath("participant[@name='#{home_team}']").first['oddsDecimal']
    koefF2 = market.xpath("participant[@name='#{away_team}']").first['oddsDecimal']
    add_to_result [period, 'F1', val, koefF1]
    add_to_result [period, 'F2', val, koefF2]
  end


  def parse_under_over()
    #puts "!!!!!!!!!! TU TO !!!!!!!!!!!!!!"
    val = market_type.match(/Under\/Over ([0-9.]+)/)[1]

    market.xpath('participant').each do |participant|
      name = ''
      if market_type.include? home_team
        name = 'I1'
      elsif market_type.include? away_team
        name = 'I2'
      end
      if participant['name'].include? home_team
        name = 'I1'
      elsif participant['name'].include? away_team
        name = 'I2'
      end

      isxod = "#{name}T#{participant['name'].match(/(Under|Over)/)[0][0]}"
      add_to_result [period, isxod, val, participant['oddsDecimal']]
    end

  end

  def parse_winner()
    #puts "!!!!!!!!!!1 X 2 1X X2 12!!!!!!!!!!!!"
    market.xpath('participant').each do |participant|
      name = participant['name']
      has_x = (market.xpath("participant[@name='Draw']").first || market.xpath("participant[@name='Draw/Draw']").first)
      name = name.gsub('Draw','X').gsub(home_team, '1').gsub(away_team, '2').gsub('/','')
      name = name[0] if name[1] == name[0]
      next if %w(X1 2X 21).include?(name)
      if name.length == 1 && !has_x
        name = "ML#{name}"
      end
      koef = participant['oddsDecimal']
      add_to_result [period, name, nil, koef]
    end
  end

  def parse_draw_no_bet()
    #puts "!!!!!!!DNB1 DNB2!!!!!!!"
    koefDNB1 = market.xpath("participant[@name='#{home_team}']").first['oddsDecimal']
    koefDNB2 = market.xpath("participant[@name='#{away_team}']").first['oddsDecimal']
    add_to_result [period, 'DNB1', nil, koefDNB1]
    add_to_result [period, 'DNB2', nil, koefDNB2]
  end

  def parse_total_odd_even()
    koefODD = market.xpath('participant[@name="Odd"]').first['oddsDecimal']
    koefEVEN = market.xpath('participant[@name="Even"]').first['oddsDecimal']
    add_to_result [period, 'ODD', nil, koefODD]
    add_to_result [period, 'EVEN', nil, koefEVEN]
  end

  def parse_total_corners()
    market.xpath('participant').each do |participant|
      pattern = /(Over|Under) ([0-9]+)/
      next unless participant['name'] =~ pattern
      isxod = (participant['name'].match(pattern)[1] == 'Under')? 'CNR_TU' : 'CNR_TO'
      val = participant['name'].match(pattern)[2]
      koef = participant['oddsDecimal']
      add_to_result [period, isxod, val, koef]
    end
  end

  def parse_both_teams_to_score()
    koefBTS_Y = market.xpath("participant[@name='Yes']").first['oddsDecimal']
    koefBTS_N = market.xpath("participant[@name='No']").first['oddsDecimal']
    add_to_result [period, 'BTS_Y', nil, koefBTS_Y]
    add_to_result [period, 'BTS_N', nil, koefBTS_N]
  end


  def parse_teams_to_score()
    #puts "!!!!!!!!!!  BTS_Y  !!!!!!!!!!!!", 1
    koefBTS_Y = market.xpath("participant[@name='Both Teams']").first
    koefBTS_N = market.xpath("participant[@name='Neither']").first
    add_to_result [period, 'BTS_Y', nil, koefBTS_Y] if koefBTS_Y
    add_to_result [period, 'BTS_N', nil, koefBTS_N] if koefBTS_N
  end

  def parse_periods()
    match = market_type.match(/([0-9]+)(nd|st|th|rd) (Half|Set)/)
    if match
      period = match[1]
    else
      period = (sport_name =~ UNUSUAL_MAIN_LINE_NUMBERS_PATTERN)? '-1' : '0'
    end
    self.period=period
    period
  end

  def get_xmls()
    body = get(URL)
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
      xmls << get(xml_uri)
    end
    xmls
  end

  private

  def get(uri)
    response = Net::HTTP.get_response(URI.parse(uri))
    if response.kind_of?(Net::HTTPRedirection)
      body = Net::HTTP.get(URI.parse(redirect_url(response)))
    else
      body = response.body
    end
    body
  end

  def redirect_url(response)
    if response['location'].nil?
      response.body.match(/<a href=\"([^>]+)\">/i)[1]
    else
      response['location']
    end
  end
end