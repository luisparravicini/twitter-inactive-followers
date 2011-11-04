require 'twitter'
require 'fileutils'
require 'logger'
require 'date'

include FileUtils


$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG
$log.formatter = proc { |severity, datetime, progname, msg|
  "#{datetime}, #{severity}: #{msg}\n"
}

UPDATE_THRESHOLD = 5

class TweetInfo
  attr_reader :last_tweet, :updated_at

  def initialize(last_tweet, prot=false)
    @last_tweet = last_tweet
    @updated_at = DateTime.now
    @protected = prot
  end

  def protected?; @protected; end

  def to_s
    "tweet: %s, update: %s, protected=%s" % [@last_tweet, @updated_at, @protected]
  end
end

module Zombie

class Fetcher
  def initialize(usr, threshold)
    @threshold = threshold
    @usr = usr
    raise "User #{usr} doesn't exist" unless Twitter.user?(usr)

    @id = Twitter.user(usr).id

    @followers_db_name = "followers_%d.db" % @id
  end

  def run
    update_followers
    update_last_tweets
  end

  private

  def update_last_tweets
    $log.debug { "fetching last tweeted date for #{@followers.size} followers" }

    now = DateTime.now
    i = 0
    @followers.keys.each do |uid|
      unless @followers[uid].nil?
        next if @followers[uid].protected?
        next if (now - @followers[uid].updated_at).abs < UPDATE_THRESHOLD
      end

      begin
        result = Twitter.user_timeline(uid, :count => 1, :include_rts => 1,
          :include_entities => 0, :trim_user => 1)
        last_update = unless result.empty?
          DateTime.parse(result.first['created_at'])
        end 
        @followers[uid] = TweetInfo.new(last_update)

        $log.debug { "#{uid} tweeted on #{@followers[uid]}" }
      rescue Twitter::Unauthorized
        $log.debug { "#{uid} tweets are protected" }
        @followers[uid] = TweetInfo.new(nil, true)
      end

      i += 1
      save_followers if i % 10 == 0
    end

    save_followers
  end

  def load_followers
    if File.exist?(@followers_db_name)
      $log.debug { 'loading followers' }
      @followers = File.open(@followers_db_name, 'r') { |io| Marshal.load(io) }
    end
  end

  def save_followers
    $log.debug { 'saving followers' }

    tmp = @followers_db_name + '.tmp'
    File.open(tmp, 'w') { |io| Marshal.dump(@followers, io) }
    mv(tmp, @followers_db_name)
  end

  def fetch_followers
    $log.debug { 'fetching followers' }

    #followers_count = Twitter.user(@usr).followers_count
    followers = []
    cursor = -1

    while true do
      result = Twitter.follower_ids(@usr, :cursor => cursor)
      followers += result['ids']
      cursor = result['next_cursor']

      break if result['ids'].size == 0 || cursor == 0
    end

    new_followers = Hash.new
    followers.each { |k| new_followers[k] = nil }
    @followers = new_followers

    save_followers

    $log.debug { "fetched #{@followers.count} followers" }
  end

  def update_followers
    load_followers || fetch_followers
  end
end

class Reporter
  def initialize(usr)
    @usr = usr
  end

  def run
  end
end

end


usr = ARGV.shift
threshold = ARGV.shift.to_i
if usr.nil? || threshold < 1
  puts "usage: #{$0} <user> <threshold_in_days>"
  exit 1
end
if threshold < UPDATE_THRESHOLD
  puts "threshold must be > #{UPDATE_THRESHOLD}"
  exit 2
end

Zombie::Fetcher.new(usr, threshold).run
Zombie::Reporter.new(usr).run
