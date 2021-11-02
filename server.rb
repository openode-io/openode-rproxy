
require './instance_template_engine.rb'
require 'httparty'
require 'json'


LOOP_SYNC_INTERVAL = (ENV["LOOP_SYNC_INTERVAL"] || 30).to_i
OPENODE_API_URL = ENV["OPENODE_API_URL"] || "http://localhost:3000"
OPENODE_API_TOKEN = ENV["OPENODE_API_TOKEN"]
GSTORAGE_BUCKET = ENV["GSTORAGE_BUCKET"] || "gs://instance-certs"
LOCAL_CERTS_PATH = ENV["LOCAL_CERTS_PATH"] || "./certs"
CONFIGS_PATH = ENV["CONFIGS_PATH"] || "./configs"

### General utils

puts system("gsutil cp #{GSTORAGE_BUCKET}/167.cert #{LOCAL_CERTS_PATH}/167.cert")
asdf

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

def http_patch(url, body, headers = nil)
  uri = URI(url)

  HTTParty.patch(url, :headers => headers, body: body).body
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

def openode_patch(path, body)
  log("Openode patch #{path}")

  return JSON.parse(
    http_patch(
      "#{OPENODE_API_URL}#{path}",
      body,
      headers={"x-auth-token" => OPENODE_API_TOKEN}
    )
  )
end

def openode_load_balancer_requiring_sync
  openode_get("/super_admin/website_locations/load_balancer_requiring_sync")
end

def openode_set_load_balancer_synced(website_location_id)
  openode_patch(
    "/super_admin/website_locations/#{website_location_id}",
    {
      "website_location" => {
        "load_balancer_synced" => true
      }
    }
  )
end

### Main

log("Booting with sync interval #{LOOP_SYNC_INTERVAL}")

loop do
  log("Begin loop")

  openode_load_balancer_requiring_sync.each do |website_location|
    wl = website_location
    puts "wl = #{wl.inspect}"
    engine = InstanceTemplateEngine.new(website_location)

    data = engine.render

    website_id = wl["website_id"]
    website_location_id = wl["id"]
    file_path = "#{CONFIGS_PATH}/#{website_id}-#{website_location_id}.yml"
    File.open(file_path, 'w') { |file| file.write(data) }
    log("[+] Wrote #{file_path}")

    # openode_set_load_balancer_synced(website_location_id)
  end

  sleep LOOP_SYNC_INTERVAL
rescue StandardError => e
  log_error("#{e}, #{e.backtrace}")
  sleep LOOP_SYNC_INTERVAL
end
