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
      @params[:name] = @options['<name>'] if @options['network']
      @params[:hostname] = @options['<hostname>'] unless (@options['--uuid'] || @options['network'])
      @params[:tags] = @options['--tags'] if @options['--tags']
      @params[:boot] = @options['--boot'] if @options['--boot']
      @params[:install] = @options['--install'] if @options['--install']
      @params[:uuid] = @options['--uuid'] if @options['--uuid']
      @params[:vlan] = @options['--vlan'] if @options['--vlan']
      @params[:network] = @options['--network'] if @options['--network']
    end

    def get_conf(item)
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

    def set_conf(item,conf)
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

    def set_boot
      @params[:status] = self.options['enable'] ? :true : :false
      begin
        resp = RestClient.post("#{@url}/host/boot", @params, { 'X-NoPain-Login' => @login, 
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

    def set_install
      @params[:status] = self.options['enable'] ? :true : :false
      begin
        resp = RestClient.post("#{@url}/host/install", @params, { 'X-NoPain-Login' => @login, 
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

    def delete(item)
      begin
        resp = RestClient.delete("#{@url}/#{item}", params: @params, 
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

    def read_options
      doc = <<DOCOPT
Client for NoPain installer.

Usage:
  #{__FILE__} (show|edit|delete) host [<hostname>] [--tags=<tags>] [--boot=<boolean>] [--install=<boolean>]
  #{__FILE__} (show|edit|delete) host --uuid=<uuid>
  #{__FILE__} (boot|install) (enable|disable) [<hostname>] [--tags=<tags>] [--boot=<boolean>] [--install=<boolean>]
  #{__FILE__} (boot|install) (enable|disable) --uuid=<uuid>
  #{__FILE__} (show|edit|delete) network [<name>] [--vlan=<vlan>] [--network=<network>]
  #{__FILE__} -h | --help
  #{__FILE__} -v | --version

Options:
  -h --help                   Show this screen.
  -v --version                Show version.
  -t --tags=<tags>            Space delimited list of tags. Use '!' before tag to negate tag.
  -b --boot=<boolean>         Boot filter (true/false).
  -i --install=<boolean>      Install filter (true/false).
  -u --uuid=<uuid>            Host UUID.
  -n --network=<network>      Network.
  --vlan=<vlan>		      Vlan.

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

if @client.options['network']
  @item = 'network'
elsif @client.options['host']
  @item = 'host'
else
  puts 'some bad shit happened'
  exit 1
end

if @client.options['show']
  ap @client.get_conf(@item)
elsif @client.options['edit']
  editor = ENV['EDITOR'] ? ENV['EDITOR'] : 'vi'
  conf = @client.get_conf(@item)
  if @client.error
    ap conf 
    exit 1
  else
    file = "/tmp/#{Digest::SHA256.hexdigest(@client.options.to_s)}"
    File.open(file, 'w') { |file| file.write(JSON.pretty_generate(conf)) }
    system("#{editor} #{file}")
    begin
      ap @client.set_conf(@item,JSON.parse(File.read(file)))
    rescue => e
      STDERR.puts "ERROR: #{e.message}"
    end
    File.delete(file)
  end
elsif @client.options['boot']
  ap @client.set_boot
elsif @client.options['install']
  ap @client.set_install
elsif @client.options['delete']
  ap @client.delete(@item)
else
  puts 'Some shit happened. Call 8-800-SPORTLOTO.'
end
