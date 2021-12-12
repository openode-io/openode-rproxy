
require './instance_template_engine.rb'
require 'httparty'
require 'json'


LOOP_SYNC_INTERVAL = (ENV["LOOP_SYNC_INTERVAL"] || 30).to_i
OPENODE_API_URL = ENV["OPENODE_API_URL"] || "http://localhost:3000"
OPENODE_API_TOKEN = ENV["OPENODE_API_TOKEN"]
GSTORAGE_BUCKET = ENV["GSTORAGE_BUCKET"] || "gs://instance-certs"
LOCAL_CERTS_PATH = ENV["LOCAL_CERTS_PATH"] || "./certs"
CONFIGS_PATH = ENV["CONFIGS_PATH"] || "./configs"
LOCATION_STR_ID = ENV["LOCATION_STR_ID"] || "invalid"

CLOUDFLARE_API_TOKEN = ENV["CLOUDFLARE_API_TOKEN"]
CLOUDFLARE_ZONE = ENV["CLOUDFLARE_ZONE"]
CLOUDFLARE_API_URL = ENV["CLOUDFLARE_API_URL"] || "https://api.cloudflare.com/client/v4"

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

def http_patch(url, body, headers = nil)
  uri = URI(url)

  HTTParty.patch(url, :headers => headers, body: body).body
end

def http_post(url, body, headers = nil)
  uri = URI(url)

  HTTParty.post(url, :headers => headers, body: body).body
end

def http_put(url, body, headers = nil)
  uri = URI(url)

  HTTParty.put(url, :headers => headers, body: body).body
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
  openode_get(
    "/super_admin/website_locations/load_balancer_requiring_sync?location=#{LOCATION_STR_ID}"
  )
end

def openode_all_sites_online_gcloud_run
  openode_get(
    "/super_admin/website_locations/online/gcloud_run?location=#{LOCATION_STR_ID}"
  )
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

# cloudflare

def cloudflare_get(path)
  return JSON.parse(
    http_get(
      "#{CLOUDFLARE_API_URL}#{path}",
      headers={"Authorization" => "Bearer #{CLOUDFLARE_API_TOKEN}"}
    )
  )
end

def cloudflare_post(path, body)
  log("Cloudflare post #{path}, body=#{body.inspect}")

  return JSON.parse(
    http_post(
      "#{CLOUDFLARE_API_URL}#{path}",
      body.to_json,
      headers={
        "Authorization" => "Bearer #{CLOUDFLARE_API_TOKEN}",
        "Content-Type" => "application/json"
      }
    )
  )
end

def cloudflare_put(path, body)
  log("Cloudflare put #{path}, body=#{body.inspect}")

  return JSON.parse(
    http_put(
      "#{CLOUDFLARE_API_URL}#{path}",
      body.to_json,
      headers={
        "Authorization" => "Bearer #{CLOUDFLARE_API_TOKEN}",
        "Content-Type" => "application/json"
      }
    )
  )
end

# gstorage

def gstorage_cp(from, to)
  cmd = "gsutil cp #{from} #{to}"
  log("gstorage: #{cmd}")

  system(cmd)
end

def sync_certs(website_location)
  wl = website_location

  sync_cert(wl["gcloud_ssl_cert_url"], "#{wl["website_id"]}.cert")
  sync_cert(wl["gcloud_ssl_key_url"], "#{wl["website_id"]}.key")
end

def sync_cert(url, filename)
  if url
    gstorage_cp("#{GSTORAGE_BUCKET}/#{filename}", "#{LOCAL_CERTS_PATH}/#{filename}")
  end
end

### Main

log("Booting with sync interval #{LOOP_SYNC_INTERVAL}")

def config_filename(website_location)
  website_id = website_location["website_id"]
  website_location_id = website_location["id"]

  "#{website_id}-#{website_location_id}.yml"
end

def sync_website_locations(website_locations, with_set_load_balancer_synced = false)
  website_locations.each do |website_location|
    wl = website_location
    log "Sync of #{wl["hosts"]}"

    sync_certs(wl)

    engine = InstanceTemplateEngine.new(website_location)

    data = engine.render

    website_location_id = wl["id"]
    file_path = "#{CONFIGS_PATH}/#{config_filename(wl)}"
    File.open(file_path, 'w') { |file| file.write(data) }
    log "[+] Wrote #{file_path}"

    if wl["domain_type"] == "subdomain" && ENV["WITH_CLOUDFLARE_SYNC"].to_s == "true"
      # check if we should create the dns record
      host = wl["hosts"].first
      dns_record = cloudflare_get("/zones/#{CLOUDFLARE_ZONE}/dns_records?name=#{host}")

      dns_record_update = {
        "type" => "CNAME",
        "name" => host,
        "content" => wl["cname"],
        "proxied" => true
      }

      if dns_record&.dig("result_info")&.dig("count")&.zero?
        cloudflare_post("/zones/#{CLOUDFLARE_ZONE}/dns_records", dns_record_update)
      else
        # need to update
        record_id = dns_record&.dig("result").first&.dig("id")

        if record_id
          cloudflare_put(
            "/zones/#{CLOUDFLARE_ZONE}/dns_records/#{record_id}",
            dns_record_update
          )
        end
      end
    end

    openode_set_load_balancer_synced(website_location_id) if with_set_load_balancer_synced
  end
end

def sync_clean_inactive_website_locations(website_locations)
  config_filenames = Dir.entries(CONFIGS_PATH)

  website_location_filenames = website_locations.map { |wl| config_filename(wl) }
  filenames_ok = ["http-catchall.yml", ".", ".."] + website_location_filenames

  filenames_to_remove = config_filenames - filenames_ok

  filenames_to_remove.each do |filename_to_remove|
    filepath = "#{CONFIGS_PATH}/#{filename_to_remove}"
    log "Removing file #{filepath}"

    File.delete(filepath)
  end
end

def sync_clean_inactive_website_location_certs(website_locations)
  cert_filenames = Dir.entries(LOCAL_CERTS_PATH)

  expected_filenames = website_locations.map do |wl|
    [
      "#{wl["website_id"]}.cert",
      "#{wl["website_id"]}.key",
    ]
  end

  filenames_ok = ([".", ".."] + expected_filenames).flatten

  filenames_to_remove = cert_filenames - filenames_ok

  filenames_to_remove.each do |filename_to_remove|
    filepath = "#{LOCAL_CERTS_PATH}/#{filename_to_remove}"
    log "Removing cert #{filepath}"

    File.delete(filepath)
  end
end

# On boot, do a global sync
initial_website_locations = openode_all_sites_online_gcloud_run

sync_clean_inactive_website_locations(initial_website_locations)
sync_clean_inactive_website_location_certs(initial_website_locations)

sync_website_locations(initial_website_locations, false)
initial_website_locations = nil

loop do
  log("Begin loop")

  sync_website_locations(openode_load_balancer_requiring_sync, true)

  sleep LOOP_SYNC_INTERVAL
rescue StandardError => e
  log_error("#{e}, #{e.backtrace}")
  sleep LOOP_SYNC_INTERVAL
end
