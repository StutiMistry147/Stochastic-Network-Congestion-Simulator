#!/bin/bash

DB_NAME="network_data.db"
CSV_FILE="network_traffic.csv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Stochastic Network Congestion Simulator - Data Import"
echo "========================================================"

# Check if CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}Error: $CSV_FILE not found!${NC}"
    echo "Please run ./generator first to generate traffic data."
    exit 1
fi

# Count lines in CSV
TOTAL_LINES=$(wc -l < "$CSV_FILE")
DATA_LINES=$((TOTAL_LINES - 1))  # Subtract header

echo -e "Found ${YELLOW}$CSV_FILE${NC} with ${GREEN}$DATA_LINES${NC} data rows"

# Remove existing database
if [ -f "$DB_NAME" ]; then
    echo "Removing existing database..."
    rm -f "$DB_NAME"
fi

# Create new database with schema and indexes
echo "Creating database schema..."
sqlite3 $DB_NAME <<EOF
-- Create table with proper types
CREATE TABLE traffic (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    inter_arrival_time REAL NOT NULL,
    packet_size INTEGER NOT NULL,
    burst_flag INTEGER DEFAULT 0,
    buffer_occupancy INTEGER DEFAULT 0,
    drop_flag INTEGER DEFAULT 0
);

-- Create indexes for performance
CREATE INDEX idx_timestamp ON traffic(timestamp);
CREATE INDEX idx_burst ON traffic(burst_flag);
CREATE INDEX idx_drop ON traffic(drop_flag);
CREATE INDEX idx_size ON traffic(packet_size);

-- Import data
.mode csv
.import --skip 1 $CSV_FILE traffic_temp

-- Copy data with proper type conversion
INSERT INTO traffic (timestamp, inter_arrival_time, packet_size, burst_flag, buffer_occupancy, drop_flag)
SELECT 
    timestamp, 
    inter_arrival_time, 
    packet_size,
    COALESCE(burst_flag, 0),
    COALESCE(buffer_occupancy, 0),
    COALESCE(drop_flag, 0)
FROM traffic_temp;

-- Drop temp table
DROP TABLE traffic_temp;

-- Verify import
SELECT COUNT(*) as row_count FROM traffic;
EOF

# Check if import was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Data import completed successfully${NC}"
    
    # Show database stats
    echo -e "\nDatabase Statistics:"
    sqlite3 $DB_NAME <<EOF
    SELECT 'Total rows: ' || COUNT(*) FROM traffic;
    SELECT 'Time range: ' || MIN(timestamp) || ' - ' || MAX(timestamp) || ' seconds' FROM traffic;
    SELECT 'Burst packets: ' || COUNT(*) || ' (' || ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM traffic), 2) || '%)' FROM traffic WHERE burst_flag = 1;
    SELECT 'Dropped packets: ' || COUNT(*) || ' (' || ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM traffic), 2) || '%)' FROM traffic WHERE drop_flag = 1;
    SELECT 'Avg packet size: ' || ROUND(AVG(packet_size), 2) || ' bytes' FROM traffic;
EOF

else
    echo -e "${RED}✗ Data import failed${NC}"
    exit 1
fi

echo -e "\n${GREEN}Done!${NC} Data from $CSV_FILE has been loaded into $DB_NAME."
