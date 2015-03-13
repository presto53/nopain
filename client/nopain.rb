#!/usr/bin/env ruby
require 'rest-client'
require 'json'
require 'yaml'
require 'digest'
require 'docopt'
require 'awesome_print'

module NoPain
  class Client
    attr_reader :options

    def self.die(msg, code)
      STDERR.puts msg
      exit code
    end

    CONFIG = YAML::load(File.open(ENV['HOME']+  '/.nopain.yml')) rescue die('Error while openening config.', 1)

    def initialize
      @url = CONFIG['server']
      @login = CONFIG['login']
      @password = CONFIG['password']
      read_options
    end

    def get_hosts
      params = Hash.new
      @options['<hostname>'] ||= '.*'
      params[:hostname] = @options['<hostname>'] 
      params[:tags] = @options['--tags'] if @options['--tags']
      params[:boot] = @options['--boot'] if @options['--boot']
      params[:install] = @options['--install'] if @options['--install']
      params[:uuid] = @options['--uuid'] if @options['--uuid']
      resp = RestClient.get("#{@url}/hosts", params: params, 'X-NoPain-Login' => @login, 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      JSON.parse(resp)
    end

    def get_images
      params = Hash.new
      @options['<name>'] ||= '.*'
      params[:name] = @options['<name>'] 
      resp = RestClient.get("#{@url}/boot_images", params: params, 'X-NoPain-Login' => @login, 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      JSON.parse(resp)
    end

    def get_scripts
      params = Hash.new
      @options['<name>'] ||= '.*'
      params[:name] = @options['<name>'] 
      resp = RestClient.get("#{@url}/install_scripts", params: params, 'X-NoPain-Login' => @login, 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      JSON.parse(resp)
    end

    def read_options
      doc = <<DOCOPT
Client for NoPain installer.

Usage:
  #{__FILE__} (show|edit) host [<hostname>] [--tags=<tags>] [--boot=<boolean>] [--install=<boolean>]
  #{__FILE__} (show|edit) host --uuid=<uuid>
  #{__FILE__} (boot|install) (enable|disable) [<hostname>] [--tags=<tags>] [--boot=<boolean>] [--install=<boolean>]
  #{__FILE__} (boot|install) (enable|disable) --uuid=<uuid>
  #{__FILE__} (show|edit) (image|script) [<name>]
  #{__FILE__} -h | --help
  #{__FILE__} -v | --version

Options:
  -h --help                   Show this screen.
  -v --version                Show version.
  -t --tags=<tags>            Space delimited list of tags. Use '!' before tag to negate tag.
  -b --boot=<boolean>         Boot filter (true/false).
  -i --install=<boolean>      Install filter (true/false).
  -u --uuid=<uuid>            Host UUID.

DOCOPT
      begin
	@options = Docopt::docopt(doc, {version: '0.0.1'})
      rescue Docopt::Exit => e
	puts e.message
	exit 1
      end
      validate_options(@options)
    end

    def validate_options(options)
      #ap options
      true
    end

  end
end
AwesomePrint.defaults = {
  indent:    -2,
  index:     false,
  sort_keys: true 
}

client = NoPain::Client.new
ap client.get_hosts if client.options['host'] && client.options['show']
ap client.get_images if client.options['image'] && client.options['show']
