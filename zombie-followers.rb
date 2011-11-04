require 'twitter'
require 'fileutils'
require 'logger'

include FileUtils


$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG


class ZombieDetector
  def initialize(usr)
    @usr = usr
    raise "User #{usr} doesn't exist" unless Twitter.user?(usr)

    @id = Twitter.user(usr).id
  end

  def run
    update_followers
  end

  private

  def load_followers
    if File.exist?('followers.db')
      $log.debug { 'loading followers' }
      @followers = File.open('followers.db', 'r') { |io| Marshal.load(io) }
    end
  end

  def save_followers
    File.open('followers.tmp', 'w') { |io| Marshal.dump(@followers, io) }
    mv('followers.tmp', 'followers.db')
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

    @followers = followers
    save_followers

    $log.debug { "fetched #{@followers.count} followers" }
  end

  def update_followers
    load_followers || fetch_followers
  end

end



usr = 'luisparravicini'
zombies = ZombieDetector.new(usr)

zombies.run
