$LOAD_PATH << '.'
require_relative 'datamodel'
require 'grape'
require 'json'
require 'net-ldap'
require 'base64'
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
	  status 200
	  expand(hosts)
	else
	  status 404
	  {error: 'Not found'}
	end
      end
      post do
	status 200
	ap JSON.parse(Base64.decode64(params['conf']))
      end
    end

    before do
      authenticate!(headers['X-NoPain-Login'], headers['X-NoPain-Password'])
    end
    params do
      optional :name, type: String, desc: "Name of image"
    end
    resource :image do
      desc "Get boot images list."
      get do
	images = find_images(params)
	if images && !images.empty?
	  status 200
	  expand(images)
	else
	  status 404
	  {error: 'Not found'}
	end
      end
      post do
	begin
	  conf = JSON.parse(Base64.decode64(params['conf']))
	  result = Array.new
	  conf.each do |item|
	    if item['_id']
	      image = NoPain::BootImage.find_by(id: item['_id'])
	    else
	      image = NoPain::BootImage.new
	      create = true
	    end
	    item.each { |key,value| image[key] = value }
	    name = item['name']? item['name'] : item
	    if image.changed?
	      result << "fail while #{create ? 'create' : 'modify'} #{name}" unless image.save
	    end
	  end
	  if result.empty?
	    status 200
	    result = 'complete'
	  else
	    status 400
	  end
	  {status: result}
	rescue
	  status 400
	  {error: 'Error while parsing configuration.'}
	end
      end
    end

    before do
      authenticate!(headers['X-NoPain-Login'], headers['X-NoPain-Password'])
    end
    params do
      optional :name, type: String, desc: "Name of image"
    end
    resource :script do
      desc "Get install scripts list."
      get do
	scripts = find_scripts(params)
	if scripts && !scripts.empty?
	  status 200
	  expand(scripts)
	else
	  status 404
	  {error: 'Not found'}
	end
      end
      post do
	status 200
	ap JSON.parse(Base64.decode64(params['conf']))
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
	pxe_authenticate!(params[:password])
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
      def expand(items)
	expanded_items = Array.new
	items.each do |item|
	  tmp_item = Hash.new
	  item.fields.each do |key,value|
	    if key == '_id'
	      tmp_item[key] = item[key].to_s
	    elsif /_id\z/ =~ key
	      tmp_key = key.gsub(/_id\z/,'')
	      tmp_item[tmp_key] = nil
	      tmp_item[tmp_key] = item.method(tmp_key.to_sym).call.name if item.method(tmp_key.to_sym).call
	    else
	      tmp_item[key] = item[key]
	    end
	  end
	  expanded_items << tmp_item
	end
	expanded_items
      end

      def find_images(params)
	if params[:name]
	  images = NoPain::BootImage.where(name: /#{params[:name]}/)
	else
	  images = NoPain::BootImage.all
	end
	images
      end

      def find_scripts(params)
	if params[:name]
	  scripts = NoPain::InstallScript.where(name: /#{params[:name]}/)
	else
	  scripts = NoPain::InstallScript.all
	end
	scripts
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
	if host.boot
	  status 200
	  env['api.format'] = :binary
	  content_type 'application/octet-stream'
	  File.binread(NoPain::CONFIG['images_path'] + '/' + host.boot_image.file).force_encoding('utf-8') rescue \
	    logger.error "Error while reading boot image for #{host.uuid}"
	else
	  status 403
	end
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
