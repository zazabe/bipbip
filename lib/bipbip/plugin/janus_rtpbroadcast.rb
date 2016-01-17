require 'janus_gateway'

module Bipbip
  class Plugin::JanusRtpbroadcast < Plugin
    def metrics_schema
      [
        { name: 'rtpbroadcast_mountpoints_count', type: 'gauge', unit: 'Mountpoints' },
        { name: 'rtpbroadcast_total_streams_count', type: 'gauge', unit: 'Streams' },
        { name: 'rtpbroadcast_total_streams_bandwidth', type: 'gauge', unit: 'b/s' },
        { name: 'rtpbroadcast_streams_zero_fps_count', type: 'gauge', unit: 'Streams' },
        { name: 'rtpbroadcast_streams_zero_bitrate_count', type: 'gauge', unit: 'Streams' }
      ]
    end

    def monitor
      data_rtp = _fetch_rtpbroadcast_data
      mountpoints = data_rtp['data']['list']
      {
        'rtpbroadcast_mountpoints_count' => mountpoints.count,
        'rtpbroadcast_streams_count' => mountpoints.map { |mp| mp['streams'].count }.reduce(:+),
        'rtpbroadcast_streams_listeners_count' => mountpoints.map { |mp| mp['streams'].map { |s| s['listeners'] || 0 }.reduce(:+) }.reduce(:+),
        'rtpbroadcast_streams_waiters_count' => mountpoints.map { |mp| mp['streams'].map { |s| s['waiters'] || 0 }.reduce(:+) }.reduce(:+),
        'rtpbroadcast_streams_bandwidth' => mountpoints.map { |mp| mp['streams'].map { |s| s['stats']['cur'] }.reduce(:+) }.reduce(:+),
        'rtpbroadcast_streams_zero_fps_count' => mountpoints.map { |mp| mp['streams'].select { |s| s['frame']['fps'] == 0 } }.count,
        'rtpbroadcast_streams_zero_bitrate_count' => mountpoints.map { |mp| mp['streams'].select { |s| s['stats']['cur'] == 0 } }.count,
      }
    end

    private

    def _fetch_rtpbroadcast_data
      promise = Concurrent::Promise.new

      client = _create_client(config['url'] || 'http://localhost:8088/janus')

      _create_session(client).then do |session|
        _create_plugin(client, session).then do |plugin|
          plugin.list.then do |list|
            data = list['plugindata']
            promise.set(data).execute

            session.destroy
          end.rescue do |error|
            fail "Failed to get list of mountpoints: #{error}"
          end
        end.rescue do |error|
          fail "Failed to create rtpbroadcast plugin: #{error}"
        end
      end.rescue do |error|
        fail "Failed to create session: #{error}"
      end

      promise.value
    end

    # @param [String] http_url
    # @param [String] session_data
    # @return [JanusGateway::Client]
    def _create_client(http_url)
      transport = JanusGateway::Transport::Http.new(http_url)
      client = JanusGateway::Client.new(transport)

      client.on(:close) do
        fail 'Connection to Janus closed.'
      end
      client
    end

    # @param [JanusGateway::Client] client
    # @return [Concurrent::Promise]
    def _create_session(client)
      session = JanusGateway::Resource::Session.new(client)
      session.on(:destroy) do
        fail 'Session got destroyed.'
      end
      session.create
    end

    # @param [JanusGateway::Client] client
    # @param [JanusGateway::Resource::Session] session
    # @return [Concurrent::Promise]
    def _create_plugin(client, session)
      plugin = JanusGateway::Plugin::Rtpbroadcast.new(client, session)
      plugin.on(:destroy) do
        fail 'Plugin got destroyed.'
      end
      plugin.create
    end
  end
end
