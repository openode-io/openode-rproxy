
require './instance_template_engine.rb'
require 'httparty'
require 'json'


LOOP_SYNC_INTERVAL = (ENV["LOOP_SYNC_INTERVAL"] || 30).to_i
OPENODE_API_URL = ENV["OPENODE_API_URL"] || "http://localhost:3000/"
OPENODE_API_TOKEN = ENV["OPENODE_API_TOKEN"]
CONFIGS_PATH = ENV["CONFIGS_PATH"] || "./configs"

### General utils

def log(msg)
  $stdout.sync = true
  puts "#{Time.now} [INFO] - #{msg}"
end

def log_error(msg)
  $stderr.sync = true
  STDERR.puts "#{Time.now} [ERROR] - #{msg}"
end

def http_get(url, headers = nil)
  uri = URI(url)

  HTTParty.get(url, :headers => headers).body
end

# openode

def openode_get(path)
  return JSON.parse(
    http_get(
      "#{OPENODE_API_URL}#{path}",
      headers={"x-auth-token" => OPENODE_API_TOKEN}
    )
  )
end

def openode_load_balancer_requiring_sync
  openode_get("/super_admin/website_locations/load_balancer_requiring_sync")
end

### Main

log("Booting with sync interval #{LOOP_SYNC_INTERVAL}")

loop do
  log("Begin loop")

  openode_load_balancer_requiring_sync.each do |website_location|
    wl = website_location
    engine = InstanceTemplateEngine.new(website_location)

    data = engine.render

    website_id = wl["website_id"]
    website_location_id = wl["id"]
    file_path = "#{CONFIGS_PATH}/#{website_id}-#{website_location_id}.yml"
    File.open(file_path, 'w') { |file| file.write(data) }
    log("[+] Wrote #{file_path}")
  end

  sleep LOOP_SYNC_INTERVAL
rescue StandardError => e
  log_error("#{e}, #{e.backtrace}")
  sleep LOOP_SYNC_INTERVAL
end
