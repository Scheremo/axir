// RUN: axi4-opt %s -split-input-file -verify-axi4-loop-free -verify-diagnostics

//===----------------------------------------------------------------------===//
// Loop-free network (should pass)
//===----------------------------------------------------------------------===//

module @loop_free_ok {
  %clk = axi4.clock @clk

  %x0 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  %x1 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %x0, %x1 {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Simple bridge cycle (should fail)
//===----------------------------------------------------------------------===//

module @loop_cycle_two_nodes {
  %clk = axi4.clock @clk

  // expected-note @+1 {{xbar in loop}}
  %x0 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-note @+1 {{xbar in loop}}
  %x1 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %x0, %x1 {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  // expected-error @+1 {{'axi4.bridge' op creates a loop in AXI4 network}}
  axi4.bridge %x1, %x0 {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Less-obvious cycle with extra cross-links (should fail)
//===----------------------------------------------------------------------===//

module @loop_cycle_four_nodes_crosslinks {
  // Topology:
  //   x0 -> x1 -> x2 -> x3
  //    \\             ^
  //     \\-> x2 ------|
  //
  // The back edge x3 -> x1 completes a cycle: x1 -> x2 -> x3 -> x1.
  %clk = axi4.clock @clk

  %x0 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-note @+1 {{xbar in loop}}
  %x1 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-note @+1 {{xbar in loop}}
  %x2 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // expected-note @+1 {{xbar in loop}}
  %x3 = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %x0, %x1 {
    upstream_window = #axi4.window<base = 0x0000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %x1, %x2 {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %x2, %x3 {
    upstream_window = #axi4.window<base = 0x2000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %x0, %x2 {
    upstream_window = #axi4.window<base = 0x3000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  // expected-error @+1 {{'axi4.bridge' op creates a loop in AXI4 network}}
  axi4.bridge %x3, %x1 {
    upstream_window = #axi4.window<base = 0x4000, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Cycle with managers/subordinates present (should fail)
//===----------------------------------------------------------------------===//

module @loop_cycle_with_endpoints {
  // This builds a 3-node ring. Each xbar has one manager and one subordinate,
  // with bridge windows set so coverage is complete if the ring is ignored.
  // The loop is the only reason this module fails.
  //
  // Diagram:
  //   [x0] --b01--> [x1] --b12--> [x2]
  //     ^                         |
  //     |-----------b20-----------|
  //
  // Local windows:
  //   x0: sub [0x0000,0x1000)  bridge to x1 [0x1000,0x2000)
  //   x1: sub [0x2000,0x3000)  bridge to x2 [0x3000,0x4000)
  //   x2: sub [0x4000,0x5000)  bridge to x0 [0x5000,0x6000)
  %clk = axi4.clock @clk

  %m0 = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 2 : ui32,
    outstanding_writes = 2 : ui32
  }

  %s0 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-note @+1 {{xbar in loop}}
  %x0 = axi4.xbar(%clk, managers = [%m0], subordinates = [%s0]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  %m1 = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 2 : ui32,
    outstanding_writes = 2 : ui32
  }

  %s1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x2000, size = 0x1000>
  }

  // expected-note @+1 {{xbar in loop}}
  %x1 = axi4.xbar(%clk, managers = [%m1], subordinates = [%s1]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  %m2 = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 2 : ui32,
    outstanding_writes = 2 : ui32
  }

  %s2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x4000, size = 0x1000>
  }

  // expected-note @+1 {{xbar in loop}}
  %x2 = axi4.xbar(%clk, managers = [%m2], subordinates = [%s2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %x0, %x1 {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %x1, %x2 {
    upstream_window = #axi4.window<base = 0x3000, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  // expected-error @+1 {{'axi4.bridge' op creates a loop in AXI4 network}}
  axi4.bridge %x2, %x0 {
    upstream_window = #axi4.window<base = 0x5000, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}
