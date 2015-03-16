#!/usr/bin/env ruby
require 'rest-client'
require 'json'
require 'yaml'
require 'digest'
require 'docopt'
require 'base64'
require 'awesome_print'

module NoPain
  class Client
    attr_reader :options, :error

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
      @params = Hash.new
      @options['<hostname>'] ||= '.*'
      @options['<name>'] ||= '.*'
      @params[:hostname] = @options['<hostname>'] unless @options['--uuid']
      @params[:tags] = @options['--tags'] if @options['--tags']
      @params[:boot] = @options['--boot'] if @options['--boot']
      @params[:install] = @options['--install'] if @options['--install']
      @params[:uuid] = @options['--uuid'] if @options['--uuid']
    end

    def get(item)
      begin
        resp = RestClient.get("#{@url}/#{item}", params: @params, 
			                         'X-NoPain-Login' => @login, 
						 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      rescue => e
	if e.methods.include?(:response)
	  resp = e.response.code
	elsif e.methods.include?(:message)
	  resp = e.message
	else
	  resp = 'Unknown error'
	end
	@error = true
      end
      JSON.parse(resp) rescue { error: resp }
    end

    def set(item,conf)
      @params[:conf] = Base64.encode64(conf.to_json)
      begin
        resp = RestClient.post("#{@url}/#{item}", @params, { 'X-NoPain-Login' => @login, 
							     'X-NoPain-Password' => Digest::SHA256.hexdigest(@password)} )
      rescue => e
	if e.methods.include?(:response)
	  resp = e.response
	elsif e.methods.include?(:message)
	  resp = e.message
	else
	  resp = 'Unknown error'
	end
	@error = true
      end
      JSON.parse(resp) rescue { error: resp }
    end

    def read_options
      doc = <<DOCOPT
Client for NoPain installer.

Usage:
  #{__FILE__} (show|edit|delete) host [<hostname>] [--tags=<tags>] [--boot=<boolean>] [--install=<boolean>]
  #{__FILE__} (show|edit|delete) host --uuid=<uuid>
  #{__FILE__} (boot|install) (enable|disable) [<hostname>] [--tags=<tags>] [--boot=<boolean>] [--install=<boolean>]
  #{__FILE__} (boot|install) (enable|disable) --uuid=<uuid>
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
      ap options if ENV['DEBUG'] == 'YES'
      true
    end

  end
end
AwesomePrint.defaults = {
  indent:    -2,
  index:     false,
  sort_keys: true 
}

@client = NoPain::Client.new

def get_conf
    @client.get('host')
end

def set_conf(conf)
  @client.set('host',conf)
end

if @client.options['show']
  ap get_conf
elsif @client.options['edit']
  editor = ENV['EDITOR'] ? ENV['EDITOR'] : 'vi'
  conf = get_conf
  if @client.error
    ap conf 
    exit 1
  else
    file = "/tmp/#{Digest::SHA256.hexdigest(@client.options.to_s)}"
    File.open(file, 'w') { |file| file.write(JSON.pretty_generate(conf)) }
    system("#{editor} #{file}")
    begin
      ap set_conf(JSON.parse(File.read(file)))
    rescue => e
      STDERR.puts "ERROR: #{e.message}"
    end
    File.delete(file)
  end
elsif @client.options['boot']
  puts 'Not implemented yet'
elsif @client.options['install']
  puts 'Not implemented yet'
elsif @client.options['delete']
  puts 'Not implemented yet'
else
  puts 'Some shit happened. Call 8-800-SPORTLOTO.'
end
