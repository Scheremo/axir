// RUN: axi4-opt %s -split-input-file -verify-axi4-network -verify-diagnostics

//===----------------------------------------------------------------------===//
// Alias overlap is allowed
//===----------------------------------------------------------------------===//

module @alias_overlap_ok {
  %clk = axi4.clock @test_clk

  // expected-warning @+1 {{subordinate is not reachable by any manager in the network}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }
  // expected-warning @+1 {{subordinate is not reachable by any manager in the network}}
  %alias = axi4.alias %sub {
    window = #axi4.window<base = 0x16000000, size = 0x1000>
  }

  %bus = axi4.xbar(%clk, managers = [], subordinates = [%sub, %alias]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

//===----------------------------------------------------------------------===//
// Alias across multiple bridges (should be allowed)
//===----------------------------------------------------------------------===//

module @alias_across_bridges_ok {
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x2000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    default_error = #axi4.error_response<decerr>
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // Alias of the same subordinate at a different window.
  %alias = axi4.alias %sub {
    window = #axi4.window<base = 0x1000, size = 0x1000>
  }

  %down = axi4.xbar(%clk, managers = [], subordinates = [%sub, %alias]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  // Two separate bridges map different windows to the same underlying target.
  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 4096 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Implicit aliasing across bridges (should fail)
//===----------------------------------------------------------------------===//

module @implicit_alias_across_bridges_error {
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [
      #axi4.window<base = 0x0, size = 0x1000>,
      #axi4.window<base = 0x16000000, size = 0x1000>
    ],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-error @+1 {{'axi4.xbar' op subordinate reachable at multiple address ranges without explicit alias}}
  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    default_error = #axi4.error_response<decerr>
  }

  // expected-note @+3 {{use axi4.alias to make mirroring explicit}}
  // expected-note @+2 {{first range: [0x0, 0x1000)}}
  // expected-note @+1 {{second range: [0x16000000, 0x16001000)}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %down = axi4.xbar(%clk, managers = [], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x16000000, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Overlap without alias is still an error
//===----------------------------------------------------------------------===//

module @alias_overlap_error {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{first subordinate window: [0x0, 0x2000)}}
  %s0 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x2000>
  }

  // expected-note @+1 {{second subordinate window: [0x1000, 0x2000)}}
  %s1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x1000, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op subordinate windows overlap}}
  %bus = axi4.xbar(%clk, managers = [], subordinates = [%s0, %s1]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

//===----------------------------------------------------------------------===//
// Aliases must share an xbar with their base subordinate
//===----------------------------------------------------------------------===//

module @alias_requires_base_same_xbar_error {
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %root = axi4.xbar(%clk, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    default_error = #axi4.error_response<decerr>
  }

  // expected-note @+1 {{base subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-note @+1 {{alias defined here}}
  %alias = axi4.alias %sub {
    window = #axi4.window<base = 0x2000, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op alias must appear with its base subordinate in the same xbar}}
  %down = axi4.xbar(%clk, managers = [], subordinates = [%alias]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }
}

// -----

//===----------------------------------------------------------------------===//
// Aliases share the same adapted endpoint (no duplicated adapters)
//===----------------------------------------------------------------------===//

module @alias_with_adapters_ok {
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  %mgr = axi4.manager %clk_a {
    access = [
      #axi4.window<base = 0x0, size = 0x1000>,
      #axi4.window<base = 0x1000, size = 0x1000>
    ],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %root = axi4.xbar(%clk_a, managers = [%mgr]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    default_error = #axi4.error_response<decerr>
  }

  %sub_raw = axi4.subordinate %clk_b {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %sub_cdc = axi4.cdc %sub_raw, %clk_a {depth = 4 : ui32} : !axi4.subordinate
  %alias = axi4.alias %sub_cdc {
    window = #axi4.window<base = 0x1000, size = 0x1000>
  }

  %down = axi4.xbar(%clk_a, managers = [], subordinates = [%sub_cdc, %alias]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }

  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x0, size = 0x1000>,
    downstream_base = 0 : ui64
  }

  axi4.bridge %root, %down {
    upstream_window = #axi4.window<base = 0x1000, size = 0x1000>,
    downstream_base = 4096 : ui64
  }
}
