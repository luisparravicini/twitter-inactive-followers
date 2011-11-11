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

UPDATE_THRESHOLD = 15

class TweetInfo
  attr_reader :last_tweet, :updated_at

  def initialize(last_tweet, prot=false)
    @last_tweet = last_tweet
    @updated_at = DateTime.now
    @protected = prot
  end

  def protected?; @protected; end

  def to_s
    last = unless @last_tweet.nil?
      @last_tweet.strftime('%F')
    end
    "tweet: %s\tupdate: %s\tprotected=%s" % [last, @updated_at.strftime('%F'), @protected]
  end
end

class UserInfo
  attr_reader :uid, :screen_name, :friends, :followers, :friends, :created_at

  #FIXME change attr name
  def statuses
    @statutes
  end

  def initialize(data)
    @uid = data['id']
    @created_at = data['created_at']
    @screen_name = data['screen_name']
    @location = data['location']
    @desc = data['description']
    @favs = data['favorites_count']
    @followers = data['followers_count']
    @listed = data['listed_count']
    @location = data['location']
    @name = data['name']
    @statutes = data['statuses_count']
    @friends = data['friends_count']
    @default_profile = data['default_profile']
    @url = data['url']
    @protected = data['protected']
  end
end

module Zombie

module Users
  def self.usr_for(uid)
    #FIXME hack
    usr = @users.find do |_, info|
      next if info.nil?

      uid == info.uid
    end

    usr.last unless usr.nil?
  end

  def self.screen_name(uid)
    usr = usr_for(uid)

    if usr.nil?
      uid
    else
      usr.screen_name
    end
  end

  def self.uid_for(screen_name)
    self.load
    unless @users.has_key?(screen_name)
      self.update(Twitter.user(screen_name))
    end

    @users[screen_name.downcase].uid
  end

  def self.update(data)
    data = UserInfo.new(data)
    @users[data.screen_name.downcase] = data
    self.save_users
  end

  private

  def self.load
    self.init

    @users = if File.exist?(@db_name)
      $log.debug { 'loading users' }
      File.open(@db_name, 'r') { |io| Marshal.load(io) }
    else
      Hash.new
    end
  end

  def self.init
    @db_name ||= 'users.db'
  end

  def self.save_users
    self.init
    #$log.debug { "saving #{@users.count} users" }

    tmp = @db_name + '.tmp'
    File.open(tmp, 'w') { |io| Marshal.dump(@users, io) }
    mv(tmp, @db_name)

    @users ||= Hash.new
  end
end

class Fetcher
  def initialize(usr)
    @usr = usr
    @uid = Users.uid_for(usr)

    @followers_db_name = "followers_%d.db" % @uid
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
          :include_entities => 0)
        last_update = nil
        unless result.empty?
          result = result.first
          last_update = DateTime.parse(result['created_at'])
          Users.update(result['user'])
        end 
        @followers[uid] = TweetInfo.new(last_update)

        $log.debug { "uid:#{uid}, #{@followers[uid]}" }
      rescue Twitter::BadRequest
        if $!.ratelimit_remaining == 0
          save_followers

          t = $!.ratelimit_reset - Time.now
          $log.info { "no more calls left, sleeping till #{Time.now + t}" }

          sleep(t)
          retry
        else
          raise $!
        end
      rescue Twitter::Unauthorized
        $log.debug { "#{uid} tweets are protected" }
        @followers[uid] = TweetInfo.new(nil, true)
      end

      i += 1
      save_followers if i % 20 == 0
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
    $log.debug { "saving #{@followers.size} followers" }

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
  def initialize(usr, threshold)
    @threshold = threshold
    @uid = Users.uid_for(usr)
    @followers_db_name = "followers_%d.db" % @uid
  end

  def run
    load_followers

    t = DateTime.now - @threshold
    $log.debug { "searching for followers without activity since #{t}" }
    inactive = no_data = prot = 0
    @followers.each do |fuid, info|
      # TODO should be stored as fixnum
      fuid = fuid.to_i

      if !info.nil? && info.protected?
        prot += 1
      end
      if info.nil? || info.last_tweet.nil?
        no_data += 1
        next
      end
      next unless info.last_tweet < t

      usr = Users.usr_for(fuid)
      unless usr.nil?
        # TODO this should be a DateTime
        d = DateTime.parse(usr.created_at).strftime('%F')
        puts [usr.screen_name, d, usr.statuses, usr.friends, usr.followers, info].join("\t")
      #else
      #  puts [Users.screen_name(fuid), info].join("  ")
      end
      inactive += 1
    end

    with_data = @followers.size - no_data
    puts "%d/%d = %2.2f%% (total:%d, protected:%d)" % [inactive,
      with_data, inactive*100/with_data.to_f, @followers.size, prot]
  end

  def load_followers
    if File.exist?(@followers_db_name)
      $log.debug { 'loading followers' }
      @followers = File.open(@followers_db_name, 'r') { |io| Marshal.load(io) }
    end
  end

end

end


usr = ARGV.shift
threshold = ARGV.shift.to_i
dont_fetch = ARGV.shift == '-n'
if usr.nil? || threshold < 1
  puts "usage: #{$0} <user> <threshold_in_days> [-n]"
  exit 1
end
if threshold < UPDATE_THRESHOLD
  puts "threshold must be > #{UPDATE_THRESHOLD}"
  exit 2
end

unless dont_fetch
  begin
    Zombie::Fetcher.new(usr).run
  rescue Twitter::BadRequest
    #FIXME copypasted from above code. refactor
    if $!.ratelimit_remaining == 0

      t = $!.ratelimit_reset - Time.now
      $log.info { "no more calls left, sleeping till #{Time.now + t}" }

      sleep(t)
      retry
    else
      raise $!
    end
  rescue Errno::ECONNRESET, SocketError, Twitter::Error, Timeout::Error, EOFError
    $log.error { "#{$!.message}. sleeping" }
    sleep 30
    retry
  end
end
Zombie::Reporter.new(usr, threshold).run
