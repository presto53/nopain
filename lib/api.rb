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

    resource :config do
      desc "Get config(s) for host(s)."
      params do
	optional :hostname, type: String, desc: "String representing hostname, could be a regexp."
	optional :tags, type: String, desc: "Space delimited tags"
	optional :boot, type: String, desc: "Boot enabled/disabled"
	optional :install, type: String, desc: "Install enabled/disabled"
	optional :uuid, type: String, desc: "Server UUID"
	mutually_exclusive :uuid, :hostname
	mutually_exclusive :uuid, :tags
	mutually_exclusive :uuid, :boot
	mutually_exclusive :uuid, :install
	at_least_one_of :uuid, :hostname, :tags, :boot, :install
      end
      get do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  status 200
	  hosts
	else
	  status 404
	end
      end
    end

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
	  host.checkin = Time.now
	  host.save
	  host.boot_image ? return_image(host) : status(404)
	else
	  create_host(params)
	end
      end
    end

    helpers do
      def find_hosts(params)
	if params[:uuid]
	  hosts = NoPain::Host.where(uuid: params[:uuid])
	else
	  hosts = filter_by_hostname(hosts, params[:hostname]) if params[:hostname]
	  hosts = filter_by_tags(hosts, params[:tags]) if params[:tags]
	  hosts = filter_by_boot(hosts, params[:boot]) if params[:boot]
	  hosts = filter_by_install(hosts, params[:install]) if params[:install]
	end
	hosts
      end

      def filter_by_hostname(hosts, hostname)
	if hosts
	  hosts = hosts.where(hostname: /#{hostname}/)
	else
	  hosts = NoPain::Host.where(hostname: /#{hostname}/)
	end
	hosts
      end

      def filter_by_tags(hosts, tags)
	@intags = tags.split(' ').map {|tag| tag if /\A[^!]/ =~ tag}.compact
	@nintags = tags.split(' ').map {|tag| tag[1..-1] if /\A!/ =~ tag}.compact
	if hosts
	    hosts = hosts.in(tags: @intags)
	    hosts = hosts.nin(tags: @nintags)
	else
	  hosts = NoPain::Host.in(tags: @intags)
	  if hosts
	    hosts = hosts.nin(tags: @nintags)
	  else
	    hosts = NoPain::Host.nin(tags: @nintags)
	  end
	end
	hosts
      end

      def filter_by_boot(hosts, boot)
	if hosts
	  hosts = hosts.where(boot: boot)
	else
	  hosts = NoPain::Host.where(boot: boot)
	end
	hosts
      end

      def filter_by_install(hosts, install)
	if hosts
	  hosts = hosts.where(install: install)
	else
	  hosts = NoPain::Host.where(install: install)
	end
	hosts
      end

      def create_host(params)
	host = NoPain::Host.new
	host.uuid = params[:uuid]
	host.hostname = Resolv.getname(params[:ip]) rescue 'nopain'
	host.ip = params[:ip]
	host.checkin = Time.now
	update_hwaddrs(host,params)
	host.save
      end

      def update_hwaddrs(host,params)
	host.hwaddr = Hash.new unless host.hwaddr
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
