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
      get '/boot' do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  hosts.each do |host|
	    host.boot = params[:status] if params[:status]
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
      get '/install' do
	hosts = find_hosts(params)
	if hosts && !hosts.empty?
	  hosts.each do |host|
	    host.install = params[:status] if params[:status]
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
	modify(:hosts,params)
      end

      desc "Get install script"
      get '/install_script' do
	content_type 'text/plain'
	env['api.format'] = :binary
	if params[:uuid]
	  host = NoPain::Host.find_by(uuid: params[:uuid])
	  if host
	    env = host.env.join("\n") if host.env
	    script = '. ' + host.install_script if host.install_script
            ip = Resolv.getaddress hostname rescue ''
	    NoPain::Network.each do |config|
	      @net_config = config
	      break if IPAddr.new(config.network).include?(ip)
	    end
            reply = Array.new
	    if @net_config
	      reply << "ip_address=#{ip}"
	      reply << "subnet=#{@net_config.network.split('/')[1]}"
	      reply << "vlan=#{@net_config.vlan}" unless @net_config.vlan.to_i == 0
	      reply << "defaultrouter=#{IPAddr.new(@net_config.network).to_range.to_a[1].to_s}"
	    end
	    reply << "HOSTNAME=#{host.hostname}"
            reply << env 
            reply << script
	    if host.install
	      reply.join("\n")
	    else
	      status 403
	      {error: 'Install is turned off for host.'}
	    end
	  else
	    status 404
	    {error: 'Host not found.'}
	  end
	else
	  {error: 'you need to specify uuid'}
	end
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

    before do
      authenticate!(headers['X-NoPain-Login'], headers['X-NoPain-Password'])
    end
    params do
      optional :name, type: String, desc: "String representing name, could be a regexp."
      optional :network, type: String, desc: "String representing network in CIDR notation"
      optional :vlan, type: Fixnum, desc: "Number representing vlan"
      at_least_one_of :name, :network, :vlan
    end
    resource :network do
      desc "Get networks"
      get do
	networks = find_networks(params)
	if networks && !networks.empty?
	  fixed_networks = Array.new
	  networks.each do |network|
	    tmp_network = JSON.parse(network.to_json)
	    tmp_network['_id'] = network.id.to_s
	    fixed_networks << tmp_network
	  end
	  status 200
	  fixed_networks
	else
	  status 404
	  {error: 'Not found'}
	end
      end

      desc "Edit networks"
      post do
	modify(:networks,params)
      end

      desc "Delete networks"
      delete do
	networks = find_networks(params)
	if networks && !networks.empty?
	  networks.each {|network| network.delete}
	end
	status 200
	{status: 'complete'}
      end
    end

    helpers do
      def modify(type, params)
	begin
	  conf = JSON.parse(Base64.decode64(params['conf']))
	  errors = Array.new
	  conf.each do |c|
	    case type
	    when :hosts
	      tmp = NoPain::Host.find(c['_id']) if c['_id']
	      tmp = NoPain::Host.new unless tmp
	    when :networks
	      tmp = NoPain::Network.find(c['_id']) if c['_id']
	      tmp = NoPain::Network.new unless tmp
	    end
	    c.each_key do |field|
	      tmp[field] = c[field]
	    end
	    errors << {item: c, errors: tmp.errors.messages} unless tmp.save
	  end
	  if errors.empty?
	    status 200
	    {status: 'complete'}
	  else
	    status 400
	    {error: "Error while creating/modifying items: #{errors}"}
	  end
	rescue
	  status 400
	  {error: 'Error while parsing configuration.'}
	end
      end

      def find_networks(params)
	networks = NoPain::Network.where(name: /#{params[:name]}/)
	networks = networks.where(vlan: params[:vlan]) if params[:vlan]
	networks = networks.where(network: /#{params[:network]}/) if params[:network]
	networks
      end

      def find_hosts(params)
	if params[:uuid]
	  hosts = NoPain::Host.where(uuid: params[:uuid])
	else
	  hosts = NoPain::Host.where(hostname: /#{params[:hostname]}/)
	  hosts = hosts.where(boot: params[:boot]) if params[:boot]
	  hosts = hosts.where(install: params[:install]) if params[:install]
	  hosts = filter_by_tags(hosts, params[:tags]) if params[:tags]
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
