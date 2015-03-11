#!/usr/bin/env ruby
require 'rest-client'
require 'json'
require 'yaml'
require 'digest'
require 'optparse'

module NoPain
  class Client

    def self.die(msg, code)
      STDERR.puts msg
      exit code
    end

    CONFIG = YAML::load(File.open(ENV['HOME']+  '/.nopain.yml')) rescue die('Error while openening config.', 1)

    def initialize
      @url = CONFIG['server']
      @login = CONFIG['login']
      @password = CONFIG['password']
    end

    def get_hosts(params)
      resp = RestClient.get("#{@url}/hosts", params: params, 'X-NoPain-Login' => @login, 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      JSON.parse(resp)
    end

    def get_images(params)
      resp = RestClient.get("#{@url}/boot_images", params: params, 'X-NoPain-Login' => @login, 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      JSON.parse(resp)
    end

    def get_scripts(params)
      resp = RestClient.get("#{@url}/install_scripts", params: params, 'X-NoPain-Login' => @login, 'X-NoPain-Password' => Digest::SHA256.hexdigest(@password) )
      JSON.parse(resp)
    end

  end
end

NoPain::Client.new.get_hosts({hostname: '.*'})
#tags boot install hostname uuid
p NoPain::Client.new.get_images({name: '.*'})
#name
