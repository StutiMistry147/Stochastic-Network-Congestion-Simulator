#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   STOCHASTIC NETWORK CONGESTION SIMULATOR              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"

# Step 1: Verify SPIN model
echo -e "\n${YELLOW}[1/5] Verifying buffer logic with SPIN model checker...${NC}"

# Safety verification
echo "Running safety verification..."
spin -a buffer.pml
gcc -o pan pan.c
./pan -m10000 > spin_safety.txt 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Safety verification passed${NC}"
    grep -E "errors: [0-9]+" spin_safety.txt | head -1
else
    echo -e "${RED}✗ Safety verification failed${NC}"
    tail -20 spin_safety.txt
    exit 1
fi

# Liveness verification (with fairness)
echo "Running liveness verification..."
./pan -f -m10000 > spin_liveness.txt 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Liveness verification passed${NC}"
    grep -E "errors: [0-9]+" spin_liveness.txt | head -1
else
    echo -e "${RED}✗ Liveness verification failed${NC}"
    tail -20 spin_liveness.txt
    exit 1
fi

# Step 2: Generate traffic
echo -e "\n${YELLOW}[2/5] Generating synthetic network traffic...${NC}"
echo "Options:"
echo "1) Quick test (1,000 packets)"
echo "2) Standard run (100,000 packets)"
echo "3) Heavy load (1,000,000 packets)"
echo "4) Custom parameters"
read -p "Select mode [1-4]: " mode

case $mode in
    1) PACKETS=1000; LAMBDA=10; BUFFER=100; BURST=1 ;;
    2) PACKETS=100000; LAMBDA=10; BUFFER=1000; BURST=1 ;;
    3) PACKETS=1000000; LAMBDA=50; BUFFER=5000; BURST=1 ;;
    4) 
        read -p "Arrival rate (packets/sec) [10]: " LAMBDA
        LAMBDA=${LAMBDA:-10}
        read -p "Number of packets [100000]: " PACKETS
        PACKETS=${PACKETS:-100000}
        read -p "Buffer size [1000]: " BUFFER
        BUFFER=${BUFFER:-1000}
        read -p "Enable bursts (1/0) [1]: " BURST
        BURST=${BURST:-1}
        ;;
    *) PACKETS=100000; LAMBDA=10; BUFFER=1000; BURST=1 ;;
esac

echo -e "\nRunning generator with:"
echo "  λ = $LAMBDA packets/sec"
echo "  Packets = $PACKETS"
echo "  Buffer = $BUFFER"
echo "  Bursts = $([ $BURST -eq 1 ] && echo "enabled" || echo "disabled")"

g++ -std=c++11 -O3 generator.cpp -o generator
time ./generator $LAMBDA $PACKETS $BUFFER $BURST

# Step 3: Import data
echo -e "\n${YELLOW}[3/5] Importing data to SQLite database...${NC}"
chmod +x import_data.sh
./import_data.sh

# Step 4: Run analysis
echo -e "\n${YELLOW}[4/5] Running network analysis...${NC}"
python3 analysis.py

# Step 5: Generate report
echo -e "\n${YELLOW}[5/5] Generating final report...${NC}"

# Get statistics for report
TOTAL_PACKETS=$(sqlite3 network_data.db "SELECT COUNT(*) FROM traffic;")
BURST_PACKETS=$(sqlite3 network_data.db "SELECT COUNT(*) FROM traffic WHERE burst_flag=1;")
DROP_PACKETS=$(sqlite3 network_data.db "SELECT COUNT(*) FROM traffic WHERE drop_flag=1;")
AVG_SIZE=$(sqlite3 network_data.db "SELECT ROUND(AVG(packet_size), 2) FROM traffic;")

# Create summary report
cat > network_report.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Network Congestion Simulation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        h1 { color: #333; border-bottom: 2px solid #333; }
        h2 { color: #666; }
        .stats { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 20px 0; }
        .stat-card { background: #f9f9f9; padding: 15px; border-radius: 5px; text-align: center; }
        .stat-value { font-size: 24px; font-weight: bold; color: #007bff; }
        .stat-label { color: #666; margin-top: 5px; }
        img { max-width: 100%; margin: 20px 0; border: 1px solid #ddd; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .footer { margin-top: 40px; color: #999; font-size: 12px; text-align: center; }
    </style>
</head>
<body>
    <h1>Network Congestion Simulation Report</h1>
    
    <div class="stats">
        <h2>Configuration</h2>
        <ul>
            <li><strong>Arrival rate (λ):</strong> $LAMBDA packets/sec</li>
            <li><strong>Total packets:</strong> $PACKETS</li>
            <li><strong>Buffer size:</strong> $BUFFER</li>
            <li><strong>Burst mode:</strong> $([ $BURST -eq 1 ] && echo "Enabled" || echo "Disabled")</li>
        </ul>
    </div>
    
    <div class="stat-grid">
        <div class="stat-card">
            <div class="stat-value">$TOTAL_PACKETS</div>
            <div class="stat-label">Total Packets</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$BURST_PACKETS ($(echo "scale=1; $BURST_PACKETS*100/$TOTAL_PACKETS" | bc)%)</div>
            <div class="stat-label">Burst Packets</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$DROP_PACKETS ($(echo "scale=2; $DROP_PACKETS*100/$TOTAL_PACKETS" | bc)%)</div>
            <div class="stat-label">Drop Rate</div>
        </div>
    </div>
    
    <h2>Visualization Dashboard</h2>
    <img src="network_analysis_dashboard.png" alt="Network Analysis Dashboard">
    
    <h2>SPIN Verification Results</h2>
    <div class="stats">
        <h3>Safety Properties</h3>
        <pre>$(grep -A 5 "errors:" spin_safety.txt | head -6)</pre>
        
        <h3>Liveness Properties</h3>
        <pre>$(grep -A 5 "errors:" spin_liveness.txt | head -6)</pre>
    </div>
    
    <div class="footer">
        Generated on $(date) | Stochastic Network Congestion Simulator
    </div>
</body>
</html>
EOF

echo -e "${GREEN}✓ Report generated: network_report.html${NC}"

echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Simulation complete!${NC}"
echo "Results:"
echo "  - SPIN safety: spin_safety.txt"
echo "  - SPIN liveness: spin_liveness.txt"
echo "  - Traffic data: network_traffic.csv"
echo "  - Database: network_data.db"
echo "  - Analysis plots: network_analysis_dashboard.png"
echo "  - HTML report: network_report.html"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Optional: Open report in browser
if command -v xdg-open > /dev/null; then
    xdg-open network_report.html
elif command -v open > /dev/null; then
    open network_report.html
fi
