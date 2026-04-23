# ARM Branch-Directed Instruction Prefetcher

This repository contains the cycle-accurate, synthesizable Verilog RTL for a Branch-Directed Instruction Prefetcher with a Sidecar FIFO. Designed for a 32-bit ARM-like architecture, this module completely hides memory fetch latency on correctly predicted branches while utilizing a quarantine buffer to ensure **zero cache pollution** on mispredictions.

## File Structure

- `arm_branch_predecoder.v` - Combinationally detects ARM B/BL opcodes and calculates the target PC.
- `prefetch_axi_master.v` - Autonomous AXI4-Lite master using a Default-Deassert FSM.
- `prefetch_sidecar_fifo.v` - Synchronous circular buffer with an atomic, 1-cycle pointer reset for flush recovery.
- `cpu_memory_arbiter.v` - Strict-priority AXI routing with zero-latency combinational FIFO hit detection.
- `tb_prefetch_system.v` - 6-phase self-checking integration testbench.

## How to Run the Simulation

This project requires Icarus Verilog.

1. Compile the design:
   iverilog -o prefetch_sim.vvp arm_branch_predecoder.v prefetch_sidecar_fifo.v prefetch_axi_master.v cpu_memory_arbiter.v tb_prefetch_system.v
2. Execute the testbench:
   vvp prefetch_sim.vvp

## Verification Results

The testbench validates 6 phases of operation (Reset, NOP Fetch, Branch Fetch, Prefetch Fill, Arbiter Hit, and Flush Recovery). The system currently achieves a **100% pass rate** across all internal assertions with zero memory traffic generated during a Sidecar FIFO hit.
