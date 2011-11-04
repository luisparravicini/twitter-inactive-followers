require 'twitter'
require 'fileutils'
require 'logger'
require 'time'

include FileUtils


$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG
$log.formatter = proc { |severity, datetime, progname, msg|
  "#{datetime}, #{severity}: #{msg}\n"
}


class ZombieDetector
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
        next if (@followers[uid] - @threshold).abs < @threshold
      end

      result = Twitter.user_timeline(uid, :count => 1, :include_rts => 1,
        :include_entities => 0, :trim_user => 1)
      @followers[uid] = DateTime.parse(result.first['created_at'])

      $log.debug { "#{uid} tweeted on #{@followers[uid]}" }

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
    @log.debug { 'saving followers' }

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



threshold = 10  # days
usr = 'luisparravicini'
zombies = ZombieDetector.new(usr, threshold)

zombies.run
