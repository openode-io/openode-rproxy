
require 'net/http'


LOOP_SYNC_INTERVAL = (ENV["LOOP_SYNC_INTERVAL"] || 30).to_i

### General utils

def log(msg)
  $stdout.sync = true
  puts "#{Time.now} [INFO] - #{msg}"
end

def log_error(msg)
  $stderr.sync = true
  STDERR.puts "#{Time.now} [ERROR] - #{msg}"
end

def http_get(url)
  uri = URI(url)
  
  Net::HTTP.get(uri)
end

### Main

log("Booting with sync interval #{LOOP_SYNC_INTERVAL}")

loop do
  log("Begin loop")
  sleep LOOP_SYNC_INTERVAL
rescue StandardError => e
  log_error("#{e}, #{e.backtrace}")
  sleep LOOP_SYNC_INTERVAL
end
