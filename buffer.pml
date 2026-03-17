#define BUF_SIZE 5
#define MAX_PACKETS 20

byte buffer_count = 0;
byte packets_sent = 0;
byte packets_dropped = 0;
byte packets_processed = 0;
bool in_burst = false;

// Track drop increments
byte prev_drops = 0;
bool drop_occurred_this_step = false;

// Track packet IDs to prove no duplicates
byte packet_ids[BUF_SIZE];

// Initialize packet_ids
init {
    byte i = 0;
    for (i: 0 .. BUF_SIZE-1) {
        packet_ids[i] = 0;
    }
}

active proctype Producer() {
    byte packet_id = 0;
    
    do
    :: packets_sent < MAX_PACKETS ->
        // Reset drop flag for this iteration
        drop_occurred_this_step = false;
        
        // Non-deterministic burst behavior
        if
        :: true -> in_burst = false;  // Normal traffic
        :: (packets_sent % 3 == 0) -> in_burst = true;  // Burst every 3rd packet
        fi;
        
        // In burst mode, try to send multiple packets quickly
        if
        :: in_burst ->
            // Try to send 2-3 packets in burst
            byte burst_size = 2 + (packets_sent % 2);
            byte i = 0;
            for (i: 1 .. burst_size) {
                if
                :: buffer_count < BUF_SIZE ->
                    buffer_count++;
                    packet_ids[buffer_count-1] = packet_id;
                    packets_sent++;
                    printf("Producer: Packet %d sent (burst), buffer=%d\n", 
                           packet_id, buffer_count);
                    packet_id++;
                :: else ->
                    packets_dropped++;
                    drop_occurred_this_step = true;
                    printf("Producer: Buffer FULL - Packet %d DROPPED during burst!\n", 
                           packet_id);
                    packet_id++;
                fi;
                
                // Small delay between burst packets
                timeout;
            }
        :: else ->
            // Normal single packet send
            if
            :: buffer_count < BUF_SIZE ->
                buffer_count++;
                packet_ids[buffer_count-1] = packet_id;
                packets_sent++;
                printf("Producer: Packet %d sent, buffer=%d\n", packet_id, buffer_count);
                packet_id++;
            :: else ->
                packets_dropped++;
                drop_occurred_this_step = true;
                printf("Producer: Buffer FULL - Packet %d DROPPED\n", packet_id);
                packet_id++;
            fi;
        fi;
        
        // Random delay between sends
        if
        :: timeout -> skip;
        :: timeout -> skip;
        fi;
        
        // Update previous drops for next iteration
        prev_drops = packets_dropped;
        
    :: else ->
        printf("Producer: Max packets reached. Sent=%d, Dropped=%d, Processed=%d\n",
               packets_sent, packets_dropped, packets_processed);
        break;
    od;
}

active proctype Consumer() {
    do
    :: buffer_count > 0 ->
        // Non-deterministic consumption rate
        if
        :: true ->  // Fast consumption
            buffer_count--;
            packets_processed++;
            printf("Consumer: Packet %d consumed (fast), buffer=%d\n", 
                   packet_ids[buffer_count], buffer_count);
        :: timeout ->  // Slow consumption (simulates processing delay)
            buffer_count--;
            packets_processed++;
            printf("Consumer: Packet %d consumed (slow), buffer=%d\n", 
                   packet_ids[buffer_count], buffer_count);
        fi;
        
        // Random delay between consumes
        if
        :: timeout -> skip;
        :: timeout -> skip;
        fi;
        
    :: else ->
        // Buffer empty - wait
        printf("Consumer: Buffer empty, waiting...\n");
        timeout;
    od;
}

// ============= LTL PROPERTIES =============

// Property 1: Buffer never overflows (safety)
ltl buffer_never_overflows { 
    [] (buffer_count <= BUF_SIZE) 
}

// Property 2: Drops only happen when buffer is full AT THAT MOMENT
// Fixed: Track when drops actually increment
ltl drops_only_when_full {
    [] ((drop_occurred_this_step) -> (buffer_count == BUF_SIZE))
}

// Property 3: Liveness - packets are eventually consumed
ltl packets_eventually_consumed {
    [] ((packets_sent > packets_processed) -> <> (packets_sent == packets_processed))
}

// Property 4: Buffer is never stuck with packets (no deadlock)
ltl buffer_progress {
    [] ((buffer_count > 0) -> <> (buffer_count < buffer_count))
}

// Property 5: System makes progress (total packets eventually reaches max)
ltl system_progress {
    [] (packets_sent < MAX_PACKETS -> <> (packets_sent == MAX_PACKETS))
}

// ============= ASSERTIONS =============

// Assertion 1: Buffer count integrity
active proctype BufferMonitor() {
    do
    :: atomic {
        assert(buffer_count <= BUF_SIZE);
    }
    od;
}

// Assertion 2: No duplicate packet IDs in buffer
active proctype DuplicateMonitor() {
    byte i, j;
    do
    :: atomic {
        for (i: 0 .. BUF_SIZE-1) {
            for (j: i+1 .. BUF_SIZE-1) {
                if
                :: packet_ids[i] == packet_ids[j] && packet_ids[i] != 0 ->
                    assert(false);
                :: else -> skip;
                fi;
            }
        }
    }
    od;
}

// Assertion 3: Total packet count consistency
// FIXED: Only assert after packets have been sent
active proctype CountMonitor() {
    do
    :: atomic {
        if
        :: packets_sent > 0 ->
            // Packets sent should be at least processed + dropped
            assert(packets_sent >= packets_processed + packets_dropped);
        :: else -> skip;
        fi
    }
    od;
}

// Assertion 4: Buffer occupancy consistency
active proctype BufferConsistencyMonitor() {
    do
    :: atomic {
        assert(buffer_count <= BUF_SIZE);
        assert(buffer_count >= 0);
    }
    od;
}

// ============= NEVER CLAIMS =============

// Never claim: Buffer should never stay full forever
never {
    do
    :: atomic {
        buffer_count == BUF_SIZE -> goto accept;
    }
    od;
accept:
    do
    :: atomic {
        buffer_count == BUF_SIZE -> goto accept;
    }
    :: atomic {
        buffer_count < BUF_SIZE -> break;
    }
    od;
}

// Progress label for verification
progress:
    printf("System state: buffer=%d, sent=%d, proc=%d, drop=%d\n",
           buffer_count, packets_sent, packets_processed, packets_dropped);
