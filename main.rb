#!/usr/bin/env ruby

require "rubygems"
require "bundler/setup"

require "time"
require "date"
require "httpx"
require "json"
require "dotenv/load"
require "progressbar"
require "optparse"

def slack_param_token
  ENV["SLACK_PARAM_TOKEN"]
end

def slack_cookie_d
  ENV["SLACK_COOKIE_D"]
end

def slack_domain
  "https://#{ENV["SLACK_DOMAIN"]}"
end

def verify_env!
  if slack_param_token.to_s.empty? || slack_cookie_d.to_s.empty?
    raise "Please set environment variables for slack auth."
  end
end

def cache_dir
  @cache_dir ||= Pathname.new(File.join(__dir__, "cache", DateTime.now.strftime("%Y-%m-%d")))
end

def pbar!(title, total = nil)
  ProgressBar.create(title: title, total: total) 
end

def log(msg)
  puts msg
end

# We probably don't need this anymore since emojis contains display name.
def get_user_id_map(from_cache: true)
  cache_file = cache_dir.join("user_id_map.json")

  if from_cache && cache_file.exist?
    log("Reading user id map from cache...")
    users = JSON.parse(cache_file.read)
    return users
  end

  url = File.join(slack_domain, "api/users.list")
  params = {
    token: slack_param_token,
    limit: 100,
  }
  
  cookies = { d: slack_cookie_d }
  http = HTTPX.plugin(:cookies).with_cookies(cookies)

  query_bar = pbar!("Fetching user info from Slack")
  members = []
  loop do
    query_bar.increment

    response = http.post(url, form: params)
    raise "request failed! #{response.error}: #{response.body.to_s}" if response.error
    
    parsed = JSON.parse(response.body.to_s)
    raise "Response was not OK! #{parsed}" if !parsed["ok"]

    members += parsed["members"]
    
    next_cursor = parsed["response_metadata"]["next_cursor"].to_s
    break if next_cursor.empty?
      
    params = params.merge({ cursor: next_cursor })
    sleep(0.1) # Avoid hitting the rate limit
  end
  query_bar.finish

  map_bar = pbar!("Parsing user data", members.size)
  user_map = {}
  members.each do |u|
    map_bar.increment
    next if u["deleted"]

    slack_name = u["profile"]["display_name"].to_s
    slack_name = u["profile"]["real_name"].to_s if slack_name.empty?

    user_map[u["id"]] = slack_name
  end

  log("Writing user data to cache...")
  cache_dir.mkpath
  cache_file.open("w") { |f| f.write(JSON.pretty_generate(user_map)) }

  user_map
end

def get_emojis(from_cache: true)
  cache_file = cache_dir.join("emojis.json")

  if from_cache && cache_file.exist?
    log("Reading emojis from cache...")
    emojis = JSON.parse(cache_file.read)
    return emojis
  end

  url = File.join(slack_domain, "api/emoji.adminList")
  params = {
    token: slack_param_token,
    page: 1,
    count: 100,
    sort_by: "name",
    sort_dir: "asc",
  }
  cookies = { d: slack_cookie_d }

  http = HTTPX.plugin(:cookies).with_cookies(cookies)

  emojis_bar = pbar!("Fetching emojis from slack")

  response = http.post(url, form: params)
  raise "request failed! #{response.error}: #{response.body.to_s}" if response.error

  response_body = JSON.parse(response.body.to_s)
  raise "Ok not true! #{response_body}" if !response_body["ok"]
  
  emojis = response_body["emoji"]

  total_expected = response_body["paging"]["total"]
  total_pages = response_body["paging"]["pages"]

  emojis_bar.total = total_expected
  emojis.size.times { emojis_bar.increment }

  (2..total_pages).each do |page|
    params[:page] = page
    response = nil

    loop do
      response = http.post(url, form: params)
      if response.error && response.code == 429
        sleep(1)
      else
        break
      end
    end

    raise "request failed! #{response.error}: #{response.body.to_s}" if response.error
    
    response_body = JSON.parse(response.body.to_s)
    raise "Ok not true! #{response_body}" if !response_body["ok"]

    emojis += response_body["emoji"]

    response_body["emoji"].size.times { emojis_bar.increment }
  end

  noalias_emojis = emojis.reject { |e| e["is_alias"] == 1 }

  log("Writing emoji data to cache...")
  cache_dir.mkpath
  cache_file.open("w") { |f| f.write(JSON.pretty_generate(noalias_emojis)) }

  return noalias_emojis
end

# Sample Emoji JSON:
# {
#   "name": "+++1",
#   "is_alias": 0,
#   "alias_for": "",
#   "url": "https://emoji.slack-edge.com/TBPR4B74Y/%252B%252B%252B1/165bb739875e5f96.png",
#   "team_id": "TBPR4B74Y",
#   "user_id": "U0383JGA16C",
#   "created": 1693516337,
#   "is_bad": false,
#   "user_display_name": "Ian Chesal",
#   "avatar_hash": "8a307b2a66ee",
#   "can_delete": false,
#   "synonyms": []
# }
def leaderboard_stats(emojis, top_num = nil, since = 0)
  log("")

  emojis = emojis.select { |e| e["created"] >= since }

  by_person = emojis.group_by { |e| e["user_display_name"] }
  if !top_num.nil? && by_person.size < top_num
    top_num = nil
  end

  log("Showing #{top_num.nil? ? "all" : "the top " + top_num.to_s} emoji uploaders since #{Time.at(since)}:\n\n")

  top_num ||= by_person.size
  count_by_person = by_person.map { |k, v| [k, v.size] }.sort_by { |a| - a.last }.first(top_num)

  message = ""
  count_by_person.each.with_index do |v, i|
    user = v[0]
    count = v[1]
    message += "#{i+1}) @#{user}: #{count}\n"
  end
  log(message)

  top_emojis = []
  count_by_person.map(&:first).each do |person|
    top_emojis += by_person[person]
  end

  message = "\n"
  top_emojis.each do |e|
    message += ":#{e["name"]}: "
  end
  log(message)
end

def main!
  top_num = nil
  since = 0
  from_cache = true

  OptionParser.new do |opt|
    opt.banner = "Usage: ./main.rb [--weeks 1 --top 5]"

    opt.on("--days NUM", "How many days ago to check for emoji uploads. Defaults to all time.") do |o|
      since = Time.now.to_i - o.to_i * 24 * 60 * 60
    end

    opt.on("--weeks NUM", "How many weeks ago to check for emoji uploads. Defaults to all time.") do |o|
      since = Time.now.to_i - o.to_i * 7 * 24 * 60 * 60
    end

    opt.on("--years NUM", "How many years ago to check for emoji uploads. Defaults to all time.") do |o|
      since = Time.now.to_i - o.to_i * 365 * 24 * 60 * 60
    end

    opt.on("--since DATE", "YYYY-MM-DD Emoji uploads since the given date starting at 12am. Default to all time.") do |o|
      since = Time.parse(o).to_i
    end

    opt.on("--top NUM", "Show the top NUM uploaders, defaults to displaying all.") do |o|
      top_num = o.to_i
    end

    opt.on("--cache-bust", "Skip the cache even if it exists and query Slack.") do |_|
      from_cache = false
    end
  end.parse!

  all_emojis = get_emojis(from_cache: from_cache)
  leaderboard_stats(all_emojis, top_num, since)
end

main!
