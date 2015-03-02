require 'grape'
require 'json'

module NoPaIn
  class API < Grape::API
    version 'v1', using: :param, parameter: "ver"
    format :json
    prefix :api
    helpers do
      def authenticate!(password)
	error!('401 Unauthorized', 401) unless password == 'NoPain'
      end
      def logger
	API.logger
      end
    end

    resource :ipxe do
      desc "Receiver for ipxe chainloading"
      params do
	requires :password, type: String, desc: "password"
	requires :uuid, type: String, desc: "Host UUID", regexp: /\A[a-z0-9]{8}-([a-z0-9]{4}-){3}[a-z0-9]{12}\z/
      end
      post do
	authenticate!(params[:password])
	logger.info "Request from host: #{params[:uuid]}"
	status 200
	env['api.format'] = :binary
	content_type 'application/octet-stream'
	File.binread('ipxe/undionly.kpxe').force_encoding('utf-8')
      end
    end
  end
end
