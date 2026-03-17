#include <iostream>
#include <fstream>
#include <random>
#include <chrono>
#include <cmath>
#include <vector>
#include <thread>
#include <atomic>

class NetworkTrafficGenerator {
private:
    std::mt19937 gen;
    std::exponential_distribution<double> base_dist;
    std::uniform_int_distribution<int> size_dist;
    std::uniform_real_distribution<double> burst_prob_dist;
    std::normal_distribution<double> burst_multiplier_dist;
    
    const double lambda;
    const int total_packets;
    const double BURST_PROBABILITY = 0.15;  // 15% chance of burst
    const double BURST_INTENSITY = 5.0;      // Burst packets arrive 5x faster
    
    // Statistics tracking
    std::atomic<long long> packets_dropped{0};
    std::atomic<long long> packets_processed{0};
    std::vector<double> buffer_occupancy_history;
    
public:
    NetworkTrafficGenerator(double arrival_rate, int num_packets) 
        : lambda(arrival_rate), total_packets(num_packets),
          gen(std::random_device{}()),
          base_dist(arrival_rate),
          size_dist(64, 1500),
          burst_prob_dist(0.0, 1.0),
          burst_multiplier_dist(1.0, 2.0) {
        
        buffer_occupancy_history.reserve(total_packets / 100);  // Sample every 100 packets
    }
    
    void simulate_buffer_occupancy(int buffer_size, double current_rate) {
        // Simulate buffer behavior based on arrival rate
        static double buffer_level = 0;
        double arrival_rate = current_rate;
        double service_rate = lambda;  // Service rate = average arrival rate
        
        // Simple queueing model M/M/1
        if (arrival_rate > service_rate) {
            buffer_level += (arrival_rate - service_rate) * 0.001;  // Small time step
            if (buffer_level > buffer_size) {
                packets_dropped += static_cast<int>((buffer_level - buffer_size) * 100);
                buffer_level = buffer_size;
            }
        } else {
            buffer_level = std::max(0.0, buffer_level - (service_rate - arrival_rate) * 0.001);
        }
        
        packets_processed += static_cast<int>(service_rate * 0.001);
    }
    
    void generate(bool enable_bursts = true, int buffer_size = 1000) {
        std::ofstream file("network_traffic.csv");
        file << "timestamp,inter_arrival_time,packet_size,burst_flag,buffer_occupancy,drop_flag\n";
        
        std::cout << "Generating network traffic with λ = " << lambda << " packets/sec\n";
        std::cout << "Total packets: " << total_packets << "\n";
        if (enable_bursts) {
            std::cout << "Burst mode: ENABLED (probability: " << BURST_PROBABILITY * 100 << "%)\n";
        }
        
        double current_time = 0.0;
        int burst_packets_remaining = 0;
        bool in_burst = false;
        long long drops = 0;
        
        for (int i = 0; i < total_packets; ++i) {
            double interval;
            bool is_burst = false;
            
            // Burst mode logic
            if (enable_bursts) {
                if (burst_packets_remaining > 0) {
                    // Currently in a burst
                    interval = base_dist(gen) / BURST_INTENSITY;
                    burst_packets_remaining--;
                    is_burst = true;
                    in_burst = true;
                } else {
                    // Check if we should start a new burst
                    if (!in_burst && burst_prob_dist(gen) < BURST_PROBABILITY) {
                        // Start a burst of random length
                        std::poisson_distribution<int> burst_len_dist(10);  // Average burst of 10 packets
                        burst_packets_remaining = burst_len_dist(gen);
                        interval = base_dist(gen) / BURST_INTENSITY;
                        is_burst = true;
                        in_burst = true;
                    } else {
                        // Normal traffic
                        interval = base_dist(gen);
                        in_burst = false;
                    }
                }
            } else {
                interval = base_dist(gen);
            }
            
            current_time += interval;
            int p_size = size_dist(gen);
            
            // Simulate buffer occupancy
            double current_rate = is_burst ? lambda * BURST_INTENSITY : lambda;
            simulate_buffer_occupancy(buffer_size, current_rate);
            
            bool drop = false;
            if (packets_processed > 0 && packets_dropped > drops) {
                drop = true;
                drops = packets_dropped;
            }
            
            // Sample buffer occupancy every 100 packets
            if (i % 100 == 0) {
                buffer_occupancy_history.push_back(packets_processed - packets_dropped);
            }
            
            file << std::fixed << current_time << ","
                 << interval << ","
                 << p_size << ","
                 << (is_burst ? 1 : 0) << ","
                 << (packets_processed - packets_dropped) << ","
                 << (drop ? 1 : 0) << "\n";
            
            // Progress indicator
            if ((i + 1) % 10000 == 0) {
                std::cout << "Generated " << (i + 1) << " packets... (drops: " << drops << ")\n";
            }
        }
        
        file.close();
        
        // Final statistics
        std::cout << "\n=== Generation Complete ===\n";
        std::cout << "Total packets generated: " << total_packets << "\n";
        std::cout << "Packets processed: " << packets_processed << "\n";
        std::cout << "Packets dropped: " << packets_dropped << "\n";
        std::cout << "Drop rate: " << (100.0 * packets_dropped / packets_processed) << "%\n";
        
        // Write buffer occupancy history to separate file for analysis
        std::ofstream buf_file("buffer_history.csv");
        buf_file << "sample,buffer_occupancy\n";
        for (size_t j = 0; j < buffer_occupancy_history.size(); ++j) {
            buf_file << j << "," << buffer_occupancy_history[j] << "\n";
        }
        buf_file.close();
    }
};

int main(int argc, char* argv[]) {
    // Parse command line arguments
    double lambda = 10.0;  // Default: 10 packets/sec
    int total_packets = 100000;
    int buffer_size = 1000;
    bool enable_bursts = true;
    
    if (argc > 1) lambda = std::atof(argv[1]);
    if (argc > 2) total_packets = std::atoi(argv[2]);
    if (argc > 3) buffer_size = std::atoi(argv[3]);
    if (argc > 4) enable_bursts = (std::atoi(argv[4]) == 1);
    
    std::cout << "=== Stochastic Network Congestion Simulator ===\n";
    std::cout << "Lambda (arrival rate): " << lambda << " packets/sec\n";
    std::cout << "Total packets: " << total_packets << "\n";
    std::cout << "Buffer size: " << buffer_size << " packets\n";
    std::cout << "Burst mode: " << (enable_bursts ? "enabled" : "disabled") << "\n\n";
    
    NetworkTrafficGenerator generator(lambda, total_packets);
    generator.generate(enable_bursts, buffer_size);
    
    return 0;
}
