$LOAD_PATH << '.'
require 'mongoid'
require_relative 'filters'

Mongoid.raise_not_found_error = false
Mongoid.load!("#{ENV['CONFIGPATH'] || File.dirname(__FILE__) + '/../config/'}/mongoid.yml")

module NoPain
    class Host
      include Mongoid::Document
      include NoPain::Data::Filters
      field :uuid, type: String
      field :hostname, type: String
      field :ip, type: String
      field :hwaddr, type: Hash
      field :tags, type: Array, default: ['new']
      field :boot, type: Boolean, default: false
      field :install, type: Boolean, default: false
      field :checkin, type: DateTime
      field :env, type: Hash
      field :install_script, type: String
      field :boot_image, type: String
      validates :uuid, presence: true, format: { with: UUID }
      validates :install_script, format: { with: FILENAME }, allow_nil: true
      validates :boot_image, format: { with: FILENAME }, allow_nil: true
      validates_uniqueness_of :uuid, :hostname
      index({ uuid: 1, hostname: 1 }, { unique: true })

      before_save :normalize

      private

      def normalize
        self.hwaddr.each { |dev,mac| self.hwaddr[dev] = mac.downcase } if self.hwaddr
      end
    end

    class Network
      include Mongoid::Document
      include NoPain::Data::Filters
      field :name, type: String
      field :network, type: String
      field :vlan, type: String, default: 'none'
      validates :name, presence: true, format: { with: NETWORK_NAME }
      validates :network, presence: true, format: { with: NETWORK }
      validates :vlan, presence: true, format: { with: VLAN }
      validates_uniqueness_of :name
    end
end
