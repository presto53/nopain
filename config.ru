$LOAD_PATH << '.'
require 'puma'
require 'yaml'
require 'lib/api'

begin
  NoPain::CONFIG = YAML::load(File.open(File.dirname(__FILE__) + '/config/config.yml'))
rescue
  STDERR.puts "No config file. \nPlease check that config.yml exist."
  exit 1
end

run NoPaIn::API
