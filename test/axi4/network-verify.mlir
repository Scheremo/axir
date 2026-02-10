// RUN: axi4-opt %s -split-input-file -verify-axi4-network -verify-diagnostics

//===----------------------------------------------------------------------===//
// Coverage verification errors (detected by verify-axi4-network pass)
//===----------------------------------------------------------------------===//

module @xbar_uncovered_no_subordinates {
  // Test: Manager access with no subordinates should error
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager access window: [0x0, 0x1000)}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-error @+3 {{'axi4.xbar' op manager access window not fully covered}}
  // expected-note @+2 {{uncovered region: [0x0, 0x1000)}}
  // expected-note @+1 {{add subordinates or bridges to cover this region, or set 'default_error' to handle unmapped addresses}}
  %bus = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_uncovered_partial {
  // Test: Manager access partially covered should error
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager access window: [0x0, 0x10000)}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x10000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Subordinate only covers [0x0, 0x1000)
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-error @+3 {{'axi4.xbar' op manager access window not fully covered}}
  // expected-note @+2 {{uncovered region: [0x1000, 0x10000)}}
  // expected-note @+1 {{add subordinates or bridges to cover this region, or set 'default_error' to handle unmapped addresses}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_uncovered_gap {
  // Test: Gap in coverage should error
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager access window: [0x0, 0x3000)}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x3000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Covers [0x0, 0x1000)
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // Covers [0x2000, 0x3000) - leaves gap at [0x1000, 0x2000)
  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x2000, size = 0x1000>
  }

  // expected-error @+3 {{'axi4.xbar' op manager access window not fully covered}}
  // expected-note @+2 {{uncovered region: [0x1000, 0x2000)}}
  // expected-note @+1 {{add subordinates or bridges to cover this region, or set 'default_error' to handle unmapped addresses}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_uncovered_multiple_access_windows {
  // Test: Multiple manager access windows, one uncovered
  %clk = axi4.clock @test_clk

  // First access window [0x0, 0x1000) is covered
  // Second access window [0x10000, 0x11000) is not covered
  // expected-note @+1 {{manager access window: [0x10000, 0x11000)}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>,
              #axi4.window<base = 0x10000, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Only covers first access window
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-error @+3 {{'axi4.xbar' op manager access window not fully covered}}
  // expected-note @+2 {{uncovered region: [0x10000, 0x11000)}}
  // expected-note @+1 {{add subordinates or bridges to cover this region, or set 'default_error' to handle unmapped addresses}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

//===----------------------------------------------------------------------===//
// Coverage with default_error (should pass)
//===----------------------------------------------------------------------===//

module @xbar_uncovered_with_default_error {
  // Test: Uncovered region allowed when default_error is set
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x10000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Subordinate only covers part of manager access
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // No error - uncovered region [0x1000, 0x10000) will get decerr response
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Manager with no reachable subordinates (should warn)
//===----------------------------------------------------------------------===//

module @manager_unreachable_warning {
  %clk = axi4.clock @test_clk

  // expected-warning @+1 {{manager cannot reach any subordinate in the network}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x10000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // No subordinates, but default_error handles coverage.
  %bus = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Global address uniqueness (bridge windows vs local subordinates)
//===----------------------------------------------------------------------===//

module @xbar_bridge_overlap_with_subordinate {
  // Test: Downstream subordinate translated into upstream overlaps local subordinate
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x18000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Local subordinate at [0x0, 0x10000)
  // expected-note @+1 {{first window: [0x0, 0x10000)}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 16 : ui32,
    window = #axi4.window<base = 0x0, size = 0x10000>
  }

  // expected-error @+1 {{'axi4.xbar' op address windows overlap in network address space}}
  %upstream = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // Downstream subordinate at [0x0, 0x10000) will map into upstream
  // [0x8000, 0x18000) and overlap with local subordinate.
  // expected-note @+1 {{second window: [0x8000, 0x18000)}}
  %down_sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 16 : ui32,
    window = #axi4.window<base = 0x0, size = 0x10000>
  }

  %downstream = axi4.xbar(%clk, managers = [], subordinates = [%down_sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // Bridge window [0x8000, 0x18000) overlaps with local subordinate [0x0, 0x10000)
  axi4.bridge %upstream, %downstream {
    upstream_window = #axi4.window<base = 0x8000, size = 0x10000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Multi-path ambiguity (should fail)
//===----------------------------------------------------------------------===//

module @xbar_multipath_overlap {
  // Two distinct bridge paths from the root xbar map to the same downstream
  // subordinate window, creating ambiguous routing.
  //
  // Diagram:
  //            b01            b13
  //   [root] ------> [x1] ----------> [x3]
  //     |                             ^
  //     | b02                         | b23
  //     v                             |
  //    [x2] --------------------------+
  //
  // Both paths target x3's local window [0x0, 0x1000). In the root address
  // space, that window appears at [0x1000, 0x2000) via either path.
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x3000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-error @+2 {{'axi4.xbar' op multiple routing paths to subordinate}}
  // expected-note @+1 {{overlap region: [0x1000, 0x2000)}}
  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }

  %x1 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  %x2 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-note @+1 {{subordinate reachable by overlapping address regions}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 16 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %x3 = axi4.xbar(%clk, managers = [], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %root, %x1 {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %root, %x2 {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  // expected-note @+1 {{path via this bridge}}
  axi4.bridge %x1, %x3 {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  // expected-note @+1 {{path via this bridge}}
  axi4.bridge %x2, %x3 {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Bridge burst/exclusive compatibility (should fail)
//===----------------------------------------------------------------------===//

module @bridge_burst_mismatch_manager {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager reachable through this bridge}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %down = axi4.xbar(%clk, managers = [], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-error @+1 {{'axi4.bridge' op bridge burst capability mismatch with manager: manager INCR burst length (16) exceeds subordinate maximum (4)}}
  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64,
    burst_capability = #axi4.burst_capability<incr = 4>
  }
}

// -----

module @bridge_burst_mismatch_subordinate {
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 4>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }

  // expected-note @+1 {{subordinate reachable through this bridge}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 4>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %down = axi4.xbar(%clk, managers = [], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-error @+1 {{'axi4.bridge' op bridge burst capability mismatch with subordinate: manager INCR burst length (16) exceeds subordinate maximum (4)}}
  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64,
    burst_capability = #axi4.burst_capability<incr = 16>
  }
}

// -----

module @bridge_exclusive_block {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager issues exclusive transactions}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 4>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    exclusive = true
  }

  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 4>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>,
    exclusive = true
  }

  %down = axi4.xbar(%clk, managers = [], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-error @+1 {{'axi4.bridge' op bridge does not allow exclusive transactions}}
  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64,
    exclusive = #axi4.bridge_exclusive<block>
  }
}

// -----

//===----------------------------------------------------------------------===//
// 2x2 Mesh NoC with incomplete coverage (should fail)
//===----------------------------------------------------------------------===//

module @mesh_2x2_incomplete_coverage {
  // Test: 2x2 mesh where CPU access window is not fully covered by bridges
  //
  // Topology:
  //   +----------+     bridge_01     +----------+
  //   | Node 0,0 |<----------------->| Node 0,1 |
  //   |  (CPU)   |                   |  (DMA)   |
  //   +----------+                   +----------+
  //        ^                              ^
  //        | bridge_00_10                 | bridge_01_11
  //        v                              v
  //   +----------+                   +----------+
  //   | Node 1,0 |                   | Node 1,1 |
  //   |  (SRAM)  |                   |  (DRAM)  |
  //   +----------+                   +----------+
  //
  // Problem: CPU access [0x0, 0x1_0000_0000) but bridges only cover:
  //   - [0x1000_0000, 0x2000_0000) -> DMA
  //   - [0x2000_0000, 0x3000_0000) -> SRAM
  //   - [0x8000_0000, 0x1_0000_0000) -> DRAM
  // Gap at [0x0, 0x1000_0000) and [0x3000_0000, 0x8000_0000) is uncovered!

  %clk = axi4.clock @noc_clk

  //===-- Node (0,0) - CPU node --===//

  // expected-note @+1 {{manager access window: [0x0, 0x100000000)}}
  %cpu = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 8 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-error @+3 {{'axi4.xbar' op manager access window not fully covered}}
  // expected-note @+2 {{uncovered region: [0x0, 0x10000000)}}
  // expected-note @+1 {{add subordinates or bridges to cover this region, or set 'default_error' to handle unmapped addresses}}
  %node_00 = axi4.xbar(%clk, managers = [%cpu]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  //===-- Node (0,1) - DMA node --===//

  %dma_regs = axi4.subordinate %clk {
    window = #axi4.window<base = 0x0, size = 0x1000>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    burst_capability = #axi4.burst_capability<incr = 1>
  }

  %node_01 = axi4.xbar(%clk, managers = [], subordinates = [%dma_regs]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  //===-- Node (1,0) - SRAM node --===//

  %sram = axi4.subordinate %clk {
    window = #axi4.window<base = 0x0, size = 0x100000>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 16 : ui32,
    burst_capability = #axi4.burst_capability<incr = 256>
  }

  %node_10 = axi4.xbar(%clk, managers = [], subordinates = [%sram]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  //===-- Node (1,1) - DRAM node --===//

  %dram = axi4.subordinate %clk {
    window = #axi4.window<base = 0x0, size = 0x80000000>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 32 : ui32,
    burst_capability = #axi4.burst_capability<incr = 256>
  }

  %node_11 = axi4.xbar(%clk, managers = [], subordinates = [%dram]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  //===-- Bridges --===//

  // Bridge: Node 0,0 -> Node 0,1 (CPU to DMA)
  axi4.bridge %node_00, %node_01 {
    upstream_window = #axi4.window<base = 0x10000000, size = 0x10000000>,
    downstream_base = 0 : ui64,
    outstanding = 8 : ui32
  }

  // Bridge: Node 0,0 -> Node 1,0 (CPU to SRAM)
  axi4.bridge %node_00, %node_10 {
    upstream_window = #axi4.window<base = 0x20000000, size = 0x10000000>,
    downstream_base = 0 : ui64,
    outstanding = 8 : ui32
  }

  // Bridge: Node 0,0 -> Node 1,1 (CPU to DRAM)
  axi4.bridge %node_00, %node_11 {
    upstream_window = #axi4.window<base = 0x80000000, size = 0x80000000>,
    downstream_base = 0 : ui64,
    outstanding = 16 : ui32
  }

  // Bridge: Node 0,1 -> Node 1,1 (DMA to DRAM)
  axi4.bridge %node_01, %node_11 {
    upstream_window = #axi4.window<base = 0x80000000, size = 0x80000000>,
    downstream_base = 0 : ui64,
    outstanding = 8 : ui32
  }
}
