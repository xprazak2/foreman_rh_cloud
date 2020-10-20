require 'rest-client'

module ForemanRhCloud
  class CloudRequestForwarder
    include ::ForemanRhCloud::CloudAuth
    include ::InsightsCloud::CandlepinCache

    def forward_request(original_request, controller_name, branch_id, certs)
      forward_params = prepare_forward_params(original_request, branch_id)
      logger.debug{"Request parameters for telemetry request: #{forward_params}"}

      forward_payload = prepare_forward_payload(original_request, controller_name)

      logger.debug("User agent for telemetry is: #{http_user_agent original_request}")

      cloud_url = ForemanRhCloud.prepare_forward_cloud_url(original_request.path)
      logger.debug("Sending request to: #{cloud_url}")

      execute_cloud_request(original_request.method, cloud_url, forward_payload, forward_params, certs)
    end

    def execute_cloud_request(req_method, cloud_url, forward_payload, forward_params, certs)
      RestClient::Request.execute(
        method: req_method,
        url: cloud_url,
        verify_ssl: ForemanRhCloud.verify_ssl_method,
        payload: forward_payload,
        ssl_client_cert: OpenSSL::X509::Certificate.new(certs[:cert]),
        ssl_client_key: OpenSSL::PKey::RSA.new(certs[:key]),
        headers: {
          # Authorization: "Bearer #{rh_credentials}",
          params: forward_params,
        }
      )
    end

    def prepare_forward_payload(original_request, controller_name)
      forward_payload = original_request.request_parameters[controller_name]

      forward_payload = original_request.raw_post.clone if original_request.post? && original_request.raw_post
      forward_payload = original_request.body.read if original_request.put?

      forward_payload = original_request.params.slice(:file, :metadata) if original_request.params[:file]

      # fix rails behaviour for http PATCH:
      forward_payload = forward_payload.to_json if original_request.format.json? && original_request.patch? && forward_payload && !forward_payload.is_a?(String)
      forward_payload
    end

    def prepare_forward_params(original_request, branch_id)
      forward_params = original_request.query_parameters
      if original_request.user_agent && !original_request.user_agent.include?('redhat_access_cfme')
        forward_params = forward_params.merge(:branch_id => branch_id)
      end

      forward_params
    end

    def core_app_name
      'Foreman'
    end

    def core_app_version
      Foreman::Version.new
    end

    def http_user_agent(original_request)
      "#{core_app_name}/#{core_app_version};#{ForemanRhCloud::Engine.engine_name}/#{ForemanRhCloud::VERSION};#{original_request.env['HTTP_USER_AGENT']}"
    end

    def logger
      Foreman::Logging.logger('app')
    end
  end
end
