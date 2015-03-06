$LOAD_PATH << '.'
require_relative 'datamodel'
require 'grape'
require 'json'

module NoPaIn
  class API < Grape::API
    include NoPain::Data::Filters

    version 'v1', using: :param, parameter: "ver"
    format :json
    prefix :api

    resource :ipxe do
      desc "Receiver for ipxe chainloading"
      params do
	requires :password, type: String, desc: "password"
	requires :uuid, type: String, desc: "Host UUID", regexp: UUID
	requires :ip, type: String, desc: "Temporary host IP received from DHCP server", regexp: UUID
      end
      post do
	authenticate!(params[:password])
	logger.info "Request from host: #{params[:uuid]}"
	host = NoPain::Host.find_by(uuid: params[:uuid])
	if host 
	  update_hwaddrs(host,params)
	  host.save
	  return_image(host) 
	else
	  create_host(params)
	end
      end
    end

    helpers do
      def create_host(params)
	host = NoPain::Host.new
	host.uuid = params[:uuid]
	host.hostname = Resolv.getname(params[:ip]) rescue 'nopain'
	host.ip = params[:ip]
	update_hwaddrs(host,params)
	host.save
      end

      def update_hwaddrs(host,params)
	params.each do |key,value|
	  if /\A(net[0-9]+)_mac\z/ =~ key
	    host.hwaddr[$1] = value
	  end
	end
      end

      def return_image(host)
	status 200
	env['api.format'] = :binary
	content_type 'application/octet-stream'
	File.binread(host.boot_image.file).force_encoding('utf-8') rescue \
	  logger.error "Error while reading boot image for #{host.uuid}"
      end

      def authenticate!(password)
	error!('401 Unauthorized', 401) unless password == 'NoPain'
      end

      def logger
	API.logger
      end
    end
  end
end
