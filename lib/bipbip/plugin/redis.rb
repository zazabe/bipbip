require 'redis'
class RedisClient < Redis
end

module Bipbip

  class Plugin::Redis < Plugin

    def metrics_schema
      [
          {:name => 'total_commands_processed', :type => 'ce_counter', :unit => 'Commands'},
          {:name => 'used_memory', :type => 'ce_gauge', :unit => 'b'},
      ]
    end

    def monitor(server)
      redis = RedisClient.new(
          :host => server['hostname'],
          :port => server['port']
      )
      stats = redis.info

      data = {}
      metrics_names.each do |key|
        data[key] = stats[key].to_i
      end
      data
    end
  end
end