import pandas as pd
import sqlite3
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from scipy import stats
import warnings
warnings.filterwarnings('ignore')

class NetworkAnalyzer:
    def __init__(self, db_path='network_data.db'):
        self.conn = sqlite3.connect(db_path)
        self.df = None
        self.buffer_df = None
        
    def load_data(self):
        """Load all data from database"""
        print("Loading traffic data...")
        self.df = pd.read_sql_query("SELECT * FROM traffic ORDER BY timestamp", self.conn)
        print(f"Loaded {len(self.df):,} packets")
        
        # Try to load buffer history if exists
        try:
            self.buffer_df = pd.read_csv('buffer_history.csv')
            print(f"Loaded buffer occupancy history with {len(self.buffer_df)} samples")
        except:
            print("No buffer history found")
    
    def validate_poisson_distribution(self):
        """Statistical validation of Poisson process"""
        print("\n" + "="*60)
        print("POISSON PROCESS VALIDATION")
        print("="*60)
        
        # Inter-arrival times should be exponentially distributed
        inter_arrivals = self.df['inter_arrival_time'].values
        
        # Kolmogorov-Smirnov test for exponential distribution
        lambda_est = 1.0 / np.mean(inter_arrivals)
        ks_statistic, p_value = stats.kstest(inter_arrivals, 'expon', args=(0, 1/lambda_est))
        
        print(f"Estimated λ: {lambda_est:.4f} packets/sec")
        print(f"Mean inter-arrival time: {np.mean(inter_arrivals):.6f} sec")
        print(f"Std inter-arrival time: {np.std(inter_arrivals):.6f} sec")
        print(f"\nKolmogorov-Smirnov test for exponential distribution:")
        print(f"  KS statistic: {ks_statistic:.4f}")
        print(f"  P-value: {p_value:.4f}")
        
        if p_value > 0.05:
            print(f"  ✓ Cannot reject exponential distribution (p > 0.05)")
            print(f"  ✓ Inter-arrival times follow exponential distribution")
        else:
            print(f"  ✗ Reject exponential distribution (p < 0.05)")
        
        # Check memoryless property
        quartiles = np.percentile(inter_arrivals, [25, 50, 75])
        print(f"\nQuartiles:")
        print(f"  Q1: {quartiles[0]:.6f}")
        print(f"  Q2 (median): {quartiles[1]:.6f}")
        print(f"  Q3: {quartiles[2]:.6f}")
        
        return lambda_est
    
    def analyze_congestion(self):
        """Analyze network congestion patterns"""
        print("\n" + "="*60)
        print("CONGESTION ANALYSIS")
        print("="*60)
        
        # Add time-based features
        self.df['timestamp_dt'] = pd.to_datetime(self.df['timestamp'], unit='s')
        self.df.set_index('timestamp_dt', inplace=True)
        
        # Calculate throughput in 100ms windows
        # FIXED: Keep in bytes/sec for realistic values
        throughput_bytes = self.df['packet_size'].resample('100ms').sum()
        throughput_bytes = throughput_bytes.fillna(0)
        
        # Convert to Mbps for display (but keep realistic values)
        # Average packet ~750 bytes, 10 packets/sec = 7,500 bytes/sec = 0.06 Mbps
        # Congestion threshold should be relative to max observed, not link capacity
        throughput_mbps = throughput_bytes * 8 / 1_000_000  # Convert to Mbps
        
        # Calculate dynamic threshold based on traffic patterns
        PEAK_MULTIPLIER = 3.0  # Congestion when throughput > 3x average
        avg_throughput = throughput_mbps.mean()
        CONGESTION_THRESHOLD = avg_throughput * PEAK_MULTIPLIER
        
        # Identify congestion periods
        congestion_periods = throughput_mbps[throughput_mbps > CONGESTION_THRESHOLD]
        
        print(f"Average throughput: {avg_throughput:.4f} Mbps")
        print(f"Peak throughput: {throughput_mbps.max():.4f} Mbps")
        print(f"Congestion threshold ({PEAK_MULTIPLIER}x avg): {CONGESTION_THRESHOLD:.4f} Mbps")
        print(f"\nTotal congestion periods: {len(congestion_periods)}")
        print(f"Total congestion duration: {len(congestion_periods) * 0.1:.1f} seconds")
        
        if len(congestion_periods) > 0:
            print(f"Peak during congestion: {congestion_periods.max():.4f} Mbps")
            print(f"Average during congestion: {congestion_periods.mean():.4f} Mbps")
        
        # Packet loss analysis
        if 'drop_flag' in self.df.columns:
            drops = self.df['drop_flag'].sum()
            print(f"\nPacket drops: {drops}")
            print(f"Drop rate: {100 * drops / len(self.df):.4f}%")
        
        # Burst analysis
        if 'burst_flag' in self.df.columns:
            bursts = self.df['burst_flag'].sum()
            print(f"\nBurst packets: {bursts}")
            print(f"Burst ratio: {100 * bursts / len(self.df):.2f}%")
            
            # Burst intensity
            burst_times = self.df[self.df['burst_flag'] == 1]['inter_arrival_time']
            normal_times = self.df[self.df['burst_flag'] == 0]['inter_arrival_time']
            if len(burst_times) > 0 and len(normal_times) > 0:
                intensity = normal_times.mean() / burst_times.mean()
                print(f"Burst intensity: {intensity:.2f}x normal rate")
        
        return throughput_mbps, congestion_periods
    
    def calculate_percentiles(self):
        """Calculate P95, P99 latencies and other percentiles"""
        print("\n" + "="*60)
        print("PERCENTILE ANALYSIS")
        print("="*60)
        
        inter_arrivals = self.df['inter_arrival_time'].values
        
        percentiles = [50, 75, 90, 95, 99, 99.9]
        values = np.percentile(inter_arrivals, percentiles)
        
        print(f"{'Percentile':<12} {'Value (sec)':<15} {'Packets/min':<15}")
        print("-" * 42)
        
        for p, v in zip(percentiles, values):
            packets_per_min = 60 / v if v > 0 else float('inf')
            print(f"P{p:<11} {v:<15.6f} {packets_per_min:<15.2f}")
        
        # Packet size percentiles
        print("\nPacket Size Percentiles (bytes):")
        size_percentiles = np.percentile(self.df['packet_size'], [50, 95, 99])
        print(f"  Median: {size_percentiles[0]:.0f}")
        print(f"  P95: {size_percentiles[1]:.0f}")
        print(f"  P99: {size_percentiles[2]:.0f}")
    
    def calculate_volatility(self, throughput_mbps):
        """Calculate throughput volatility metrics"""
        print("\n" + "="*60)
        print("VOLATILITY METRICS")
        print("="*60)
        
        # Calculate returns (percentage changes)
        returns = throughput_mbps.pct_change().dropna()
        
        # Volatility metrics
        if len(returns) > 0:
            volatility = returns.std() * np.sqrt(100)  # Annualized (assuming 100ms intervals)
            downside_volatility = returns[returns < 0].std() * np.sqrt(100) if any(returns < 0) else 0
            
            print(f"Throughput volatility: {volatility:.4f}")
            print(f"Downside volatility: {downside_volatility:.4f}")
            print(f"Max 1-second drop: {returns.min():.2%}")
            print(f"Max 1-second gain: {returns.max():.2%}")
            
            # Coefficient of variation
            cv = throughput_mbps.std() / throughput_mbps.mean() if throughput_mbps.mean() > 0 else float('inf')
            print(f"Coefficient of variation: {cv:.4f}")
            
            # New: Volatility clustering (ARCH effects)
            squared_returns = returns ** 2
            arch_corr = squared_returns.autocorr()
            print(f"Volatility clustering (ARCH effect): {arch_corr:.4f}")
        else:
            print("Insufficient data for volatility calculation")
            volatility = 0
        
        return volatility
    
    def plot_analysis(self, throughput_mbps, congestion_periods):
        """Generate comprehensive visualization dashboard"""
        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        fig.suptitle('Network Congestion Analysis Dashboard', fontsize=16, fontweight='bold')
        
        # 1. Inter-arrival time distribution
        ax1 = axes[0, 0]
        sns.histplot(self.df['inter_arrival_time'], kde=True, color='blue', bins=50, ax=ax1)
        ax1.set_title('Stochastic Validation: Inter-Arrival Times')
        ax1.set_xlabel('Time between packets (seconds)')
        ax1.set_ylabel('Frequency')
        
        # Add exponential fit
        mu = np.mean(self.df['inter_arrival_time'])
        x = np.linspace(0, mu*5, 100)
        y = len(self.df) * (1/mu) * np.exp(-x/mu) * (x[1]-x[0]) * 10
        ax1.plot(x, y, 'r--', label=f'Exponential fit (μ={mu:.4f})')
        ax1.legend()
        
        # 2. Time-series throughput
        ax2 = axes[0, 1]
        ax2.plot(throughput_mbps.index, throughput_mbps.values, 'b-', linewidth=1, alpha=0.7)
        
        # Dynamic congestion threshold
        avg_throughput = throughput_mbps.mean()
        threshold = avg_throughput * 3
        ax2.axhline(y=threshold, color='orange', linestyle='--', 
                   label=f'Congestion Threshold ({threshold:.2f} Mbps)')
        
        # Highlight congestion periods
        if len(congestion_periods) > 0:
            ax2.fill_between(congestion_periods.index, 0, congestion_periods.values,
                            color='red', alpha=0.3, label='Congestion')
        
        ax2.set_title('Time-Series: Network Throughput')
        ax2.set_xlabel('Time')
        ax2.set_ylabel('Throughput (Mbps)')
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        
        # 3. Buffer occupancy over time
        ax3 = axes[0, 2]
        if self.buffer_df is not None:
            ax3.plot(self.buffer_df['sample'], self.buffer_df['buffer_occupancy'], 
                    'g-', linewidth=2)
            ax3.set_title('Buffer Occupancy Over Time')
            ax3.set_xlabel('Sample (every 100 packets)')
            ax3.set_ylabel('Buffer Occupancy (packets)')
            ax3.grid(True, alpha=0.3)
        else:
            ax3.text(0.5, 0.5, 'No buffer data available', ha='center', va='center')
        
        # 4. Packet size distribution
        ax4 = axes[1, 0]
        sns.histplot(self.df['packet_size'], kde=True, color='purple', bins=30, ax=ax4)
        ax4.axvline(x=64, color='r', linestyle='--', label='Min MTU')
        ax4.axvline(x=1500, color='r', linestyle='--', label='Max MTU')
        ax4.set_title('Packet Size Distribution')
        ax4.set_xlabel('Packet Size (bytes)')
        ax4.set_ylabel('Frequency')
        ax4.legend()
        
        # 5. QQ plot for exponential distribution
        ax5 = axes[1, 1]
        stats.probplot(self.df['inter_arrival_time'], dist='expon', plot=ax5)
        ax5.set_title('Q-Q Plot: Exponential Distribution')
        ax5.grid(True, alpha=0.3)
        
        # 6. Throughput distribution and CDF
        ax6 = axes[1, 2]
        # Histogram
        sns.histplot(throughput_mbps, kde=True, color='green', bins=30, ax=ax6, alpha=0.6)
        ax6.set_title('Throughput Distribution')
        ax6.set_xlabel('Throughput (Mbps)')
        ax6.set_ylabel('Frequency')
        
        # Add CDF on secondary axis
        ax6_twin = ax6.twinx()
        sorted_throughput = np.sort(throughput_mbps)
        cdf = np.arange(1, len(sorted_throughput) + 1) / len(sorted_throughput)
        ax6_twin.plot(sorted_throughput, cdf, 'r-', linewidth=2, label='CDF')
        ax6_twin.set_ylabel('CDF', color='r')
        ax6_twin.tick_params(axis='y', labelcolor='r')
        
        plt.tight_layout()
        plt.savefig('network_analysis_dashboard.png', dpi=300, bbox_inches='tight')
        plt.show()
        print("\n📊 Dashboard saved as 'network_analysis_dashboard.png'")
    
    def run_complete_analysis(self):
        """Run all analyses"""
        print("\n" + "="*60)
        print("STOCHASTIC NETWORK CONGESTION SIMULATOR")
        print("ANALYSIS REPORT")
        print("="*60)
        
        self.load_data()
        
        if self.df is None or len(self.df) == 0:
            print("No data to analyze!")
            return
        
        # Run analyses
        lambda_est = self.validate_poisson_distribution()
        throughput_mbps, congestion = self.analyze_congestion()
        self.calculate_percentiles()
        volatility = self.calculate_volatility(throughput_mbps)
        
        # Generate plots
        self.plot_analysis(throughput_mbps, congestion)
        
        # Summary
        print("\n" + "="*60)
        print("SUMMARY STATISTICS")
        print("="*60)
        print(f"Total packets analyzed: {len(self.df):,}")
        print(f"Time span: {self.df['timestamp'].max() - self.df['timestamp'].min():.2f} seconds")
        print(f"Average throughput: {throughput_mbps.mean():.4f} Mbps")
        print(f"Peak throughput: {throughput_mbps.max():.4f} Mbps")
        print(f"Congestion events: {len(congestion)}")
        print(f"Volatility index: {volatility:.4f}")
        print("="*60)
    
    def close(self):
        self.conn.close()

if __name__ == "__main__":
    analyzer = NetworkAnalyzer()
    analyzer.run_complete_analysis()
    analyzer.close()
