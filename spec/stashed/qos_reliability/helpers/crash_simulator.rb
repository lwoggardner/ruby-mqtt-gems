# frozen_string_literal: true

module MQTT
  module QoSReliability
    # Process Crash Simulator - Simulates application crashes (file store only)
    class CrashSimulator
      def initialize
        @crash_points = {}
      end

      # Crashes process during specific operations
      # Operations: :packet_store, :packet_send, :packet_receive, :file_write
      # Note: This is a simulation - it doesn't actually crash the process
      # Instead, it disconnects the client and clears in-memory state
      def crash_during_operation(client, operation, probability = 1.0)
        case operation
        when :packet_store
          # Simulate crash when storing a packet
          client.on_send do |packet|
            if packet && rand <= probability
              simulate_crash(client)
              false # Prevent packet from being sent
            end
          end
        when :packet_send
          # Simulate crash when sending a packet
          client.on_send do |packet|
            if packet && rand <= probability
              # Let the packet be sent, then crash
              Thread.new do
                sleep 0.1
                simulate_crash(client)
              end
            end
          end
        when :packet_receive
          # Simulate crash when receiving a packet
          client.on_receive do |packet|
            if packet && rand <= probability
              simulate_crash(client)
              false # Prevent packet from being processed
            end
          end
        when :file_write
          # For file_write, we'd need to hook into the session store
          # This is a simplified version that just crashes randomly
          Thread.new do
            loop do
              sleep rand(1..5)
              if rand <= probability
                simulate_crash(client)
                break
              end
            end
          end
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end

      # Injects random crash points during execution
      def crash_at_random_point(client, probability = 0.1)
        Thread.new do
          loop do
            sleep rand(1..10)
            if rand <= probability
              simulate_crash(client)
              break
            end
          end
        end
      end

      # Simulates SIGKILL on process
      # In a real implementation, this would actually kill the process
      # Here we just disconnect the client and clear its state
      def simulate_kill_9(pid)
        # In a test environment, we can't actually kill the process
        # Instead, we'll find the client associated with this PID and disconnect it
        # This is a simplified version that assumes the client is passed directly
        if pid.is_a?(MQTT::Core::Client)
          simulate_crash(pid)
        else
          puts "Cannot simulate kill for PID: #{pid}"
        end
      end

      private

      # Simulate a crash by disconnecting the client and clearing its state
      def simulate_crash(client)
        begin
          # Force disconnect without cleanup
          client.instance_variable_get(:@connection)&.close rescue nil
          
          # Clear in-memory state to simulate a crash
          # This is a simplified version - in a real implementation,
          # we would need to be more careful about what state we clear
          client.instance_variable_set(:@status, :stopped)
        rescue => e
          puts "Error simulating crash: #{e.message}"
        end
      end
    end
  end
end