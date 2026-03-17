# Stochastic Network Congestion Simulator

A high-performance network traffic simulation pipeline modeling
real-world bursty packet arrivals using Poisson processes, with
formal verification of buffer safety and liveness properties using
the SPIN model checker.

---

## Overview

The simulator generates 100,000+ synthetic network packets using
exponential inter-arrival times derived from a Poisson arrival
process. Packets are produced with realistic burst behavior — 15%
of traffic arrives in high-intensity bursts at 5x the normal rate.
All traffic data is persisted to SQLite and analyzed for congestion
patterns, throughput volatility, and statistical conformance to the
Poisson model.

The buffer management protocol is formally verified using Promela
and SPIN, which performs exhaustive state-space search to prove
five properties: buffer overflow prevention, drop policy correctness,
packet consumption liveness, progress guarantees, and system-wide
termination.

---

## Architecture
```
buffer.pml  (Promela + SPIN)
    └── Exhaustive verification of producer-consumer buffer protocol
        ├── 5 LTL properties
        ├── 4 monitor processes with runtime assertions
        └── Never claim for buffer liveness

generator.cpp  (C++)
    ├── MT19937 RNG with hardware entropy seed
    ├── Exponential inter-arrival times  →  t = -ln(U)/λ
    ├── Mean-reverting burst simulation (15% probability, 5x intensity)
    ├── Buffer occupancy tracking (M/M/1 queueing model)
    ├── Packet drop counter
    └── network_traffic.csv + buffer_history.csv

import_data.sh  (Bash)
    ├── Error handling and CSV validation
    ├── SQLite schema with 4 indexes (timestamp, burst, drop, size)
    ├── Post-import row count verification
    └── network_data.db

analysis.py  (Python)
    ├── Kolmogorov-Smirnov test for Poisson validation
    ├── Dynamic congestion detection (3× average threshold)
    ├── P50 / P75 / P90 / P95 / P99 / P99.9 latency percentiles
    ├── Throughput volatility + ARCH clustering effect
    ├── Burst intensity ratio
    ├── 6-panel visualization dashboard
    └── network_analysis_dashboard.png

run_network_sim.sh  (Bash)
    └── End-to-end pipeline orchestration with interactive mode
        selection (1k / 100k / 1M packets or custom parameters)
```

---

## Tech Stack

| Component | Technology |
|---|---|
| Traffic Generator | C++ (MT19937, Poisson/Exponential) |
| Formal Verification | Promela + SPIN Model Checker |
| Data Ingestion | SQLite, Bash |
| Statistical Analysis | Python, Pandas, SciPy, NumPy |
| Visualization | Matplotlib, Seaborn |

---

## Formal Verification

`buffer.pml` models a producer-consumer system where the Producer
generates bursty network packets and the Consumer processes them
from a bounded buffer of size BUF_SIZE=5.

SPIN performs exhaustive state-space search to verify:

| Property | Type | Description |
|---|---|---|
| `buffer_never_overflows` | LTL Safety | `buffer_count ≤ BUF_SIZE` always |
| `drops_only_when_full` | LTL Safety | Drops only increment when buffer is at capacity |
| `packets_eventually_consumed` | LTL Liveness | All sent packets are eventually processed |
| `buffer_progress` | LTL Liveness | Non-empty buffer always drains |
| `system_progress` | LTL Liveness | System reaches MAX_PACKETS under fairness |

Runtime assertions cover buffer count integrity, duplicate packet
ID detection, and packet count consistency.
```bash
spin -a buffer.pml
gcc -o pan pan.c
./pan -m10000          # safety verification
./pan -f -m10000       # liveness under weak fairness
```

Expected: `errors: 0` on both runs.

---

## Traffic Model

**Poisson Arrival Process**

Inter-arrival times follow an exponential distribution:
```
t = -ln(U) / λ    where U ~ Uniform(0,1), λ = arrival rate
```

**Burst Simulation**

- Burst probability: 15% per packet
- Burst intensity: 5× normal arrival rate
- Burst length: Poisson distributed (mean = 10 packets)
- Buffer model: M/M/1 queueing with configurable buffer size

**Statistical Validation**

The Kolmogorov-Smirnov test is applied to verify that generated
inter-arrival times conform to the theoretical exponential
distribution. A p-value > 0.05 confirms the model is correct.

---

## Getting Started

### Prerequisites

- GCC / G++ (C++11 or later)
- Python 3.8+
- SQLite3
- SPIN model checker
```bash
# Install SPIN on Ubuntu
sudo apt install spin

# Install Python dependencies
pip install pandas numpy matplotlib seaborn scipy
```

---

## Running the Pipeline

### Option 1 — Automated (recommended)
```bash
chmod +x run_network_sim.sh
./run_network_sim.sh
```

Interactive mode selection:
- Quick test: 1,000 packets
- Standard: 100,000 packets
- Heavy load: 1,000,000 packets
- Custom: configurable λ, packet count, buffer size, burst mode

### Option 2 — Manual step by step
```bash
# Step 1: Formal verification
spin -a buffer.pml && gcc -o pan pan.c
./pan -m10000
./pan -f -m10000

# Step 2: Generate traffic
g++ -std=c++11 -O3 generator.cpp -o generator
./generator 10 100000 1000 1    # λ=10, 100k packets, buffer=1000, bursts=on

# Step 3: Ingest to SQLite
chmod +x import_data.sh && ./import_data.sh

# Step 4: Analyze
python3 analysis.py
```

---

## Sample Output
```
POISSON PROCESS VALIDATION
============================================================
Estimated λ: 9.9873 packets/sec
Mean inter-arrival time: 0.100127 sec
KS statistic: 0.0041
P-value: 0.8923
✓ Cannot reject exponential distribution (p > 0.05)

CONGESTION ANALYSIS
============================================================
Average throughput: 0.0061 Mbps
Peak throughput: 0.0243 Mbps
Congestion threshold (3x avg): 0.0183 Mbps
Total congestion periods: 847
Burst ratio: 14.82%
Burst intensity: 4.97x normal rate

PERCENTILE ANALYSIS
============================================================
Percentile    Value (sec)     Packets/min
P50           0.069315        865.62
P95           0.298902        200.74
P99           0.459987        130.44
P99.9         0.689714        86.99
```

---

## Project Structure
```
stochastic-network-simulator/
├── generator.cpp                    # C++ traffic generation engine
├── buffer.pml                       # Promela formal verification model
├── analysis.py                      # Statistical analysis and visualization
├── import_data.sh                   # SQLite ingestion script
├── run_network_sim.sh               # End-to-end pipeline orchestrator
├── network_traffic.csv              # Generated traffic data (auto-created)
├── buffer_history.csv               # Buffer occupancy samples (auto-created)
├── network_data.db                  # SQLite database (auto-created)
├── network_analysis_dashboard.png   # 6-panel analysis dashboard (auto-created)
├── network_report.html              # HTML simulation report (auto-created)
└── README.md
```

---
