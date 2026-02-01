// RUN: axi4-opt %s -verify-axi4-network | FileCheck %s

// Example: 2x2 Mesh Network-on-Chip
//
// Topology:
//
//   +----------+     bridge_01     +----------+
//   | Node 0,0 |<----------------->| Node 0,1 |
//   |  (CPU)   |                   |  (DMA)   |
//   +----------+                   +----------+
//        ^                              ^
//        | bridge_00_10                 | bridge_01_11
//        v                              v
//   +----------+     bridge_10     +----------+
//   | Node 1,0 |<----------------->| Node 1,1 |
//   |  (SRAM)  |                   |  (DRAM)  |
//   +----------+                   +----------+
//
// Address Map (from CPU's perspective):
//   0x0000_0000 - 0x0000_FFFF : Local to Node 0,0 (no subordinates)
//   0x1000_0000 - 0x1FFF_FFFF : Node 0,1 (DMA registers)
//   0x2000_0000 - 0x2FFF_FFFF : Node 1,0 (SRAM)
//   0x8000_0000 - 0xFFFF_FFFF : Node 1,1 (DRAM)

// CHECK-LABEL: module @mesh_2x2_noc
module @mesh_2x2_noc {
  //===--------------------------------------------------------------------===//
  // Clock domain (single clock for simplicity)
  //===--------------------------------------------------------------------===//

  // CHECK: axi4.clock @noc_clk
  %clk = axi4.clock @noc_clk

  //===--------------------------------------------------------------------===//
  // Node (0,0) - CPU node (top-left)
  //===--------------------------------------------------------------------===//

  // CPU manager with access to entire address space
  %cpu = axi4.manager %clk {
    access = [#axi4.window<base = 0x00000000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    outstanding_reads = 8 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Node 0,0 xbar - CPU's local interconnect
  // Uses default_error since most addresses route through bridges
  %node_00 = axi4.xbar(%clk, managers = [%cpu]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    default_error = #axi4.error_response<decerr>
  }

  //===--------------------------------------------------------------------===//
  // Node (0,1) - DMA node (top-right)
  //===--------------------------------------------------------------------===//

  // DMA engine (can also initiate transactions)
  %dma = axi4.manager %clk {
    access = [#axi4.window<base = 0x00000000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 64 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Burst splitter for DMA to access register targets (INCR=1)
  %dma_split = axi4.burst_splitter %dma {
    burst_capability = #axi4.burst_capability<incr = 1>
  }

  // DMA control registers (subordinate)
  %dma_regs = axi4.subordinate %clk {
    window = #axi4.window<base = 0x0, size = 0x1000>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    burst_capability = #axi4.burst_capability<incr = 1>
  }

  // Node 0,1 xbar (uses burst-split DMA for local registers)
  %node_01 = axi4.xbar(%clk, managers = [%dma_split], subordinates = [%dma_regs]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    default_error = #axi4.error_response<decerr>
  }

  //===--------------------------------------------------------------------===//
  // Node (1,0) - SRAM node (bottom-left)
  //===--------------------------------------------------------------------===//

  // On-chip SRAM
  %sram = axi4.subordinate %clk {
    window = #axi4.window<base = 0x0, size = 0x00100000>,
    data_width = 64 : ui32,
    outstanding = 16 : ui32,
    burst_capability = #axi4.burst_capability<incr = 256>
  }

  // Node 1,0 xbar - SRAM only, no local managers
  %node_10 = axi4.xbar(%clk, managers = [], subordinates = [%sram]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  //===--------------------------------------------------------------------===//
  // Node (1,1) - DRAM node (bottom-right)
  //===--------------------------------------------------------------------===//

  // External DRAM
  %dram = axi4.subordinate %clk {
    window = #axi4.window<base = 0x0, size = 0x80000000>,
    data_width = 64 : ui32,
    outstanding = 32 : ui32,
    burst_capability = #axi4.burst_capability<incr = 256>
  }

  // Node 1,1 xbar - DRAM only
  %node_11 = axi4.xbar(%clk, managers = [], subordinates = [%dram]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  //===--------------------------------------------------------------------===//
  // Horizontal bridges (East-West links)
  //===--------------------------------------------------------------------===//

  // Bridge: Node 0,0 <-> Node 0,1 (CPU to DMA)
  // Maps 0x1000_0000 on node_00 to 0x0 on node_01
  axi4.bridge %node_00, %node_01 {
    sym_name = "bridge_00_to_01",
    upstream_window = #axi4.window<base = 0x10000000, size = 0x10000000>,
    downstream_base = 0 : ui64,
    outstanding = 8 : ui32
  }

  // Bridge: Node 1,0 <-> Node 1,1 (SRAM to DRAM)
  // Maps 0x8000_0000 on node_10 to 0x0 on node_11
  axi4.bridge %node_10, %node_11 {
    sym_name = "bridge_10_to_11",
    upstream_window = #axi4.window<base = 0x80000000, size = 0x80000000>,
    downstream_base = 0 : ui64,
    outstanding = 16 : ui32
  }

  //===--------------------------------------------------------------------===//
  // Vertical bridges (North-South links)
  //===--------------------------------------------------------------------===//

  // Bridge: Node 0,0 <-> Node 1,0 (CPU to SRAM)
  // Maps 0x2000_0000 on node_00 to 0x0 on node_10
  axi4.bridge %node_00, %node_10 {
    sym_name = "bridge_00_to_10",
    upstream_window = #axi4.window<base = 0x20000000, size = 0x10000000>,
    downstream_base = 0 : ui64,
    outstanding = 8 : ui32
  }

  // Bridge: Node 0,1 <-> Node 1,1 (DMA to DRAM)
  // Maps 0x8000_0000 on node_01 to 0x0 on node_11
  axi4.bridge %node_01, %node_11 {
    sym_name = "bridge_01_to_11",
    upstream_window = #axi4.window<base = 0x80000000, size = 0x80000000>,
    downstream_base = 0 : ui64,
    outstanding = 8 : ui32
  }

  //===--------------------------------------------------------------------===//
  // Additional path: CPU to DRAM via diagonal route
  // This gives CPU direct access to DRAM without going through SRAM node
  //===--------------------------------------------------------------------===//

  // Bridge: Node 0,0 -> Node 1,1 (via node 0,1's east port, conceptually)
  // Maps 0x8000_0000 on node_00 to 0x0 on node_11
  // In a real mesh, this would go through node_01's router
  axi4.bridge %node_00, %node_11 {
    sym_name = "bridge_00_to_11_direct",
    upstream_window = #axi4.window<base = 0x80000000, size = 0x80000000>,
    downstream_base = 0 : ui64,
    outstanding = 16 : ui32
  }
}

