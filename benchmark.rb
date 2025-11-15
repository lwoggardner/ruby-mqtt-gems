# frozen_string_literal: true

require 'mqtt/core'
require 'benchmark'
require 'optparse'
require 'json'

# Simple MQTT stress testing tool for benchmarking throughput
class SimpleMQTTStressTest
  attr_reader :client

  def initialize(options = {})
    @options = {
      uri: 'mqtt://localhost:1883',
      topic: 'stress/test',
      qos: 1,
      message_size: 256,
      thread_count: 200,
      messages_per_thread: 20,
      protocol_version: 5,
      show_progress: false
    }.merge(options)

    @total_sent = 0
    @total_failed = 0
    @start_time = nil
    @end_time = nil

    # Generate a sample message payload
    @payload = generate_payload(@options[:message_size])
  end

  def run
    puts 'Starting MQTT Stress Test'
    puts '------------------------'
    puts "URI: #{@options[:uri]}"
    puts "Topic: #{@options[:topic]}"
    puts "QoS: #{@options[:qos]}"
    puts "Message size: #{@options[:message_size]} bytes"
    puts "Thread count: #{@options[:thread_count]}"
    puts "Messages per thread: #{@options[:messages_per_thread]}"
    puts "Total messages to send: #{@options[:thread_count] * @options[:messages_per_thread]}"
    puts '------------------------'

    @start_time = Time.now

    # Connect to the broker
    uri, protocol_version, async = @options.values_at(:uri, :protocol_version, :async)
    MQTT.open(uri, protocol_version:, async: !async.nil?) do |client|
      @client = client

      pr, pw = IO.pipe
      client.async do
        client.task_dump while pr.read(1) == 'd' # Blocks until a byte is available
      ensure
        pr.close
      end
      Signal.trap('QUIT') do
        pw.write('d')
      end

      # Stub max packet id to test id contention
      # s = client.send(:session)
      # def s.max_packet_id
      #  100
      # end

      # Start a progress reporting thread if enabled
      progress_thread = nil
      if @options[:show_progress]
        progress_thread = client.async do
          last_sent = 0
          target_count = @options[:thread_count] * @options[:messages_per_thread]

          while @total_sent < target_count
            sleep 1
            current = @total_sent
            delta = current - last_sent
            percent = (current.to_f / target_count * 100).round(1)

            puts "Progress: #{current}/#{target_count} messages (#{percent}%) - #{delta} msg/s"
            last_sent = current
          end
        end
      end

      # Use with_barrier to wait for all publishing tasks to complete
      client.with_barrier do |barrier|
        @options[:thread_count].times do |thread_id|
          barrier.async("worker#{thread_id}") do
            thread_work(client, thread_id)
          end
        end
      end
      @end_time = Time.now

      pw.write('')
      pw.close
      progress_thread&.wait
    end

    print_results
  end

  private

  def generate_payload(size)
    # Create a simple message payload of the specified size
    base_data = {
      timestamp: Time.now.to_i,
      thread_id: 0,
      message_id: 0,
      data: 'X' * (size - 60) # Rough estimate to account for JSON overhead
    }

    # Adjust to match exact size
    json = base_data.to_json
    actual_size = json.bytesize

    if actual_size < size
      # Add more data to reach target size
      base_data[:data] = 'X' * (base_data[:data].length + (size - actual_size))
    elsif actual_size > size
      # Reduce data to reach target size
      base_data[:data] = 'X' * [0, (base_data[:data].length - (actual_size - size))].max
    end

    base_data
  end

  def thread_work(client, thread_id)
    local_sent = 0
    local_failed = 0
    thread_topic = "#{@options[:topic]}/thread-#{thread_id}"

    @options[:messages_per_thread].times do |i|
      # Update the payload with specific message details
      payload = @payload.dup
      payload[:thread_id] = thread_id
      payload[:message_id] = i
      payload[:timestamp] = Time.now.to_i

      # Publish the message
      client.publish(
        topic_name: thread_topic,
        payload: payload.to_json,
        qos: @options[:qos],
        retain: false
      )

      local_sent += 1
    rescue StandardError => e
      local_failed += 1
      puts "Thread #{thread_id} error: #{e.message}" if @options[:verbose]
    end

    # Update global counters - client is thread-safe so no mutex needed
    @total_sent += local_sent
    @total_failed += local_failed
  end

  def print_results
    duration = @end_time - @start_time
    messages_per_second = @total_sent / duration
    bytes_sent = @total_sent * @options[:message_size]
    mbps = (bytes_sent * 8 / 1_000_000.0) / duration

    puts "\nStress Test Results"
    puts '------------------------'
    puts "Total messages sent: #{@total_sent}"
    puts "Failed messages: #{@total_failed}"
    puts "Test duration: #{duration.round(2)} seconds"
    puts "Average throughput: #{messages_per_second.round(2)} messages/second"
    puts "Average throughput: #{mbps.round(2)} Mbps"
    puts '------------------------'
  end
end

# Parse command line options
if __FILE__ == $PROGRAM_NAME
  options = {}

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: mqtt_v5_stress.rb [options]'

    opts.on('-a', '--async', 'Run in async mode (default: sync)') do
      options[:async] = true
    end

    opts.on('-u', '--uri URI', 'MQTT broker URI (default: mqtt://localhost:1883)') do |u|
      options[:uri] = u
    end

    opts.on('-t', '--topic TOPIC', 'Topic to publish to (default: stress/test)') do |t|
      options[:topic] = t
    end

    opts.on('-q', '--qos QOS', Integer, 'QoS level (0-2, default: 1)') do |q|
      options[:qos] = q.to_i
    end

    opts.on('-s', '--size SIZE', Integer, 'Message size in bytes (default: 256)') do |s|
      options[:message_size] = s.to_i
    end

    opts.on('-c', '--threads COUNT', Integer, 'Number of publishing threads (default: 4)') do |c|
      options[:thread_count] = c.to_i
    end

    opts.on('-m', '--messages COUNT', Integer, 'Messages per thread (default: 1000)') do |m|
      options[:messages_per_thread] = m.to_i
    end

    opts.on('-n', '--no-progress', 'Disable progress reporting') do
      options[:show_progress] = false
    end

    opts.on('-v', '--verbose', 'Show verbose output including errors') do
      options[:verbose] = true
      MQTT::Logger.log.debug!
    end

    opts.on('-p', '--protocol PROTOCOL_VERSION', 'Use protocol version 3 or 5') do |p|
      options[:protocol_version] = p.to_i
      raise ArgumentError, "Invalid protocol version #{p}" unless [3, 5].include?(options[:protocol_version])
    end

    opts.on('--profile', 'Run the profiler') do
      require 'profile'
    end
  end

  parser.parse!

  # Run the stress test
  st = SimpleMQTTStressTest.new(options)
  Signal.trap('QUIT') do
    st.task_dump
  end
  st.run
end
