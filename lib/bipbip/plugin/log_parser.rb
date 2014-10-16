require 'date'

module Bipbip

  TIMESTAMP_REGEXP = '^\d{4}-\d{2}-\d{2}T\d{2}\:\d{2}\:\d{2}'
  REGEXP_IGNORE_LINE = '^\s*$'

  class Plugin::LogParser < Plugin

    def metrics_schema
      config['matchers'].map do |matcher|
        {:name => matcher['name'], :type => 'gauge', :unit => 'Boolean'}
      end
    end

    def monitor
      time_first = nil

      lines = lines_backwards.take_while do |line|
        if line.match(REGEXP_IGNORE_LINE)
          true
        elsif timestamp_match = line.match(regexp_timestamp)
          time = DateTime.parse(timestamp_match[0]).to_time
          time_first ||= time
          (time > log_time_min)
        else
          Bipbip::logger.warn("Log parser: Unparseable line `#{line.chomp}` in `#{config['path']}`")
        end
      end

      self.log_time_min = time_first unless time_first.nil?

      Hash[config['matchers'].map do |matcher|
        name = matcher['name']
        regexp = Regexp.new(matcher['regexp'])
        value = lines.reject { |line| line.match(regexp).nil? }.length
        [name, value]
      end]
    end

    private

    def log_time_min
      @log_time_min ||= Time.now - @frequency.to_i
    end

    def log_time_min=(time)
      @log_time_min = time
    end

    def regexp_timestamp
      @regexp_timestamp ||= Regexp.new(config.fetch('regexp_timestamp', TIMESTAMP_REGEXP))
    end

    def lines_backwards
      buffer_size = 65536

      Enumerator.new do |yielder|
        File.open(config['path']) do |file|
          file.seek(0, File::SEEK_END)

          while file.pos > 0
            buffer_size = file.pos if file.pos < buffer_size

            file.seek(-buffer_size, File::SEEK_CUR)
            buffer = file.read(buffer_size)
            file.seek(-buffer_size, File::SEEK_CUR)

            line_list = buffer.each_line.entries

            if file.pos != 0
              # Remove first line as can be incomplete
              # due to seeking backward with buffer_size steps
              first_line = line_list.shift
              raise "Line length exceeds buffer size `#{buffer_size}`" if first_line.length == buffer_size
              file.seek(first_line.length, File::SEEK_CUR)
            end

            line_list.reverse.each do |line|
              yielder.yield(line)
            end
          end
        end
      end
    end

  end
end
