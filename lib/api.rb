$LOAD_PATH << '.'
require_relative 'datamodel'
require 'grape'
require 'json'
require 'net-ldap'
require 'base64'
require 'digest'
require 'awesome_print'

module NoPaIn
  class API < Grape::API
    include NoPain::Data::Filters

    version 'v1', using: :param, parameter: "ver"
    format :json
    prefix :api

    before do
      authenticate!(headers['X-NoPain-Login'], headers['X-NoPain-Password'])
    end
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
    resource :host do
      desc "Get hosts configs."
      get do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  fixed_hosts = Array.new
	  hosts.each do |host|
	    tmp_host = JSON.parse(host.to_json)
	    tmp_host['_id'] = host.id.to_s
	    fixed_hosts << tmp_host
	  end
	  status 200
	  fixed_hosts
	else
	  status 404
	  {error: 'Not found'}
	end
      end

      desc "Switch boot for hosts"
      post '/boot' do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  hosts.each do |host|
	    host.boot = params['status'] ? params['status'].to_sym : :false
	    host.save
	  end
	  status 200
	  hosts
	else
	  status 404
	  {error: 'Not found'}
	end
      end

      desc "Switch install for hosts"
      post '/install' do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  hosts.each do |host|
	    host.install = params['status'] ? params['status'].to_sym : :false
	    host.save
	  end
	  status 200
	  hosts
	else
	  status 404
	  {error: 'Not found'}
	end
      end

      desc "Edit hosts configs"
      post do
	modify(params)
      end

      desc "Get environment variables"
      get '/env' do
	content_type 'text/plain'
	env['api.format'] = :binary
	params[:uuid] ? NoPain::Host.find_by(uuid: params[:uuid]).env.join("\n") : {error: 'you need to specify uuid'}
      end

      desc "Get install script"
      get '/install_script' do
	content_type 'text/plain'
	env['api.format'] = :binary
	params[:uuid] ? NoPain::Host.find_by(uuid: params[:uuid]).install_script : {error: 'you need to specify uuid'}
      end

      desc "Delete hosts"
      delete do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  hosts.each {|host| host.delete}
	end
	status 200
	{status: 'complete'}
      end
    end

    resource :ipxe do
      desc "Receiver for ipxe chainloading"
      params do
	requires :password, type: String, desc: "password"
	requires :uuid, type: String, desc: "Host UUID", regexp: UUID
	requires :ip, type: String, desc: "Temporary host IP received from DHCP server", regexp: IP
      end
      post do
	pxe_authenticate!(params[:password])
	logger.info "Request from host: #{params[:uuid]}"
	host = NoPain::Host.find_by(uuid: params[:uuid])
	if host 
	  update_hwaddrs(host,params)
	  host.checkin = Time.now
	  host.save
	  if host.boot
	    host.boot_image ? return_image(host) : status(404)
	  else
	    status 403
	    {error: 'boot is turned off'}
	  end
	else
	  create_host(params)
	end
      end
    end

    helpers do
      def modify(params)
	begin
	  conf = JSON.parse(Base64.decode64(params['conf']))
	  errors = Array.new
	  conf.each do |host|
	    tmp_host = NoPain::Host.find(host['_id']) if host['_id']
	    tmp_host = NoPain::Host.new unless tmp_host
	    host.each_key do |field|
	      tmp_host[field] = host[field]
	    end
	    errors << {host: host, errors: tmp_host.errors.messages} unless tmp_host.save
	  end
	  if errors.empty?
	    status 200
	    {status: 'complete'}
	  else
	    status 400
	    {error: "Error while creating/modifying hosts: #{errors}"}
	  end
	rescue
	  status 400
	  {error: 'Error while parsing configuration.'}
	end
      end

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
	host.hostname = Resolv.getname(params[:ip]) rescue Digest::SHA256.hexdigest(Time.now.to_s)
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
	File.binread(NoPain::CONFIG['images_path'] + '/' + host.boot_image).force_encoding('utf-8') rescue \
	  logger.error "Error while reading boot image for #{host.uuid}"
      end

      def pxe_authenticate!(password)
	error!('401 Unauthorized', 401) unless password == NoPain::CONFIG['pxe_password']
      end

      def authenticate!(login=nil,password=nil)
	NoPain::CONFIG['auth'] == 'no' ? true : ldap_auth(login,password)
      end

      def ldap_auth(login,password)
	ldap = Net::LDAP.new
	ldap.host = NoPain::CONFIG['ldap_server']
	ldap.auth "cn=#{login},#{NoPain::CONFIG['ldap_bind_dn']}", password
	ldap.bind rescue error!('Access Denied', 401)
      end

      def logger
	API.logger
      end
    end
  end
end
