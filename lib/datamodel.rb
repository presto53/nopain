$LOAD_PATH << '.'
require 'mongoid'
require_relative 'filters'

module NoPain
    class Host
      include Mongoid::Document
      include NoPain::Data::Filters
      belongs_to :install_script
      belongs_to :boot_image
      field :uuid, type: String
      field :hostname, type: String
      field :ip, type: String
      field :hwaddr, type: Array
      field :tags, type: Array
      field :boot, type: Boolean, default: false
      field :install, type: Boolean, default: false
      field :checkin, type: DateTime
      field :env, type: Hash
      validates :uuid, presence: true, format: { with: UUID }
      validates :ip, presence: true, format: { with: IP }
      validates_uniqueness_of :uuid
      index({ uuid: 1, hostname: 1 }, { unique: true })

      before_save :normalize

      private

      def normalize
        self.hwaddr.map! { |addr| addr.downcase }
      end
    end

    class InstallScript
      include Mongoid::Document
      include NoPain::Data::Filters
      has_many :hosts
      field :name, type: String
      field :script, type: String
      validates :name, presence: true, format: { with: NAME }
      validates :script, presence: true, format: { with: FILENAME }
    end

    class BootImage
      include Mongoid::Document
      include NoPain::Data::Filters
      has_many :hosts
      field :name, type: String
      field :image, type: String
      validates :name, presence: true, format: { with: NAME }
      validates :image, presence: true, format: { with: FILENAME }
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
    end
end
