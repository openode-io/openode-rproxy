
require 'erb'

class InstanceTemplateEngine
  include ERB::Util

  def initialize(website_location, opts = {})
    @website_location = website_location
    @opts = opts
  end

  def render()
    template = File.read("./instance_template.ryml")
    
    ERB.new(template).result(binding)
  end
end
