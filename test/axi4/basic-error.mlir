// RUN: axi4-opt %s -split-input-file -verify-diagnostics

//===----------------------------------------------------------------------===//
// Manager validation errors
//===----------------------------------------------------------------------===//

module @manager_invalid_data_width {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.manager' op data_width must be 32, 64, 128, 256, or 512}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x10000000, size = 0x100000000>],
    data_width = 31 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    burst_capability = #axi4.burst_capability<incr = 256>
  }
}

// -----

module @manager_zero_external_id_width {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.manager' op external_id_width must be >= 1}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    data_width = 64 : ui32,
    external_id_width = 0 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    burst_capability = #axi4.burst_capability<incr = 16>
  }
}

// -----

module @manager_empty_access {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.manager' op access windows must not be empty}}
  %mgr = axi4.manager %clk {
    access = [],
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    burst_capability = #axi4.burst_capability<incr = 256>
  }
}

// -----

module @manager_no_read_or_write {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.manager' op at least one of 'read' or 'write' must be true}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 0 : ui32,
    outstanding_writes = 0 : ui32,
    burst_capability = #axi4.burst_capability<incr = 16>,
    read = false,
    write = false
  }
}

// -----

module @manager_access_window_misaligned_base {
  %clk = axi4.clock @test_clk
  %mgr = axi4.manager %clk {
    // expected-error @+1 {{window base must be 4KiB aligned}}
    access = [#axi4.window<base = 0x100, size = 0x1000>],
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 1 : ui32,
    outstanding_writes = 1 : ui32,
    burst_capability = #axi4.burst_capability<incr = 16>
  }
}

// -----

module @manager_outstanding_reads_zero_when_read {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.manager' op outstanding_reads must be >= 1 when read=true}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 0 : ui32,
    outstanding_writes = 4 : ui32,
    burst_capability = #axi4.burst_capability<incr = 16>
  }
}

//===----------------------------------------------------------------------===//
// Subordinate validation errors
//===----------------------------------------------------------------------===//

// -----

module @subordinate_invalid_data_width {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.subordinate' op data_width must be 32, 64, 128, 256, or 512}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 17 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x10000000, size = 0x100000000>
  }
}

// -----

module @subordinate_zero_external_id_width {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.subordinate' op external_id_width must be >= 1}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 0 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }
}

// -----

module @subordinate_no_read_or_write {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.subordinate' op at least one of 'read' or 'write' must be true}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>,
    read = false,
    write = false
  }
}

// -----

module @subordinate_zero_outstanding {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.subordinate' op outstanding must be >= 1}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 0 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }
}

// -----

module @subordinate_window_misaligned_size {
  %clk = axi4.clock @test_clk
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 1 : ui32,
    // expected-error @+1 {{window size must be 4KiB aligned}}
    window = #axi4.window<base = 0x0, size = 0x1200>
  }
}

//===----------------------------------------------------------------------===//
// Xbar data width mismatch errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_manager_data_width_mismatch {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{Manager defines data width as 32}}
  %mgr_wrong = axi4.manager %clk {
    access = [#axi4.window<base = 0x12340000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 32 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x12340000, size = 0x100000000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager data width mismatch}}
  // expected-note @+1 {{XBar defines data width as 64}}
  %bus = axi4.xbar(%clk, managers = [%mgr_wrong], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_subordinate_data_width_mismatch {
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x12340000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{Subordinate defines data width as 32}}
  %sub_wrong = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 32 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x12340000, size = 0x100000000>
  }

  // expected-error @+2 {{'axi4.xbar' op subordinate data width mismatch}}
  // expected-note @+1 {{XBar defines data width as 64}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub_wrong]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

// Test: Multiple managers - one matches, one doesn't
module @xbar_multiple_managers_one_mismatch {
  %clk = axi4.clock @test_clk

  %mgr_ok = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{Manager defines data width as 128}}
  %mgr_wrong = axi4.manager %clk {
    access = [#axi4.window<base = 0x1000, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x2000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager data width mismatch}}
  // expected-note @+1 {{XBar defines data width as 64}}
  %bus = axi4.xbar(%clk, managers = [%mgr_ok, %mgr_wrong], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Resizer tests - effective data width propagation
//===----------------------------------------------------------------------===//

// -----

// Test: Resizer still results in width mismatch
module @xbar_resizer_still_mismatch {
  %clk = axi4.clock @test_clk

  %mgr_wide = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Downsize from 128 to 32, but xbar is 64
  // expected-note @+1 {{Manager defines data width as 32}}
  %mgr_downsized = axi4.resizer %mgr_wide {target_width = 32 : ui32} : !axi4.manager

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager data width mismatch}}
  // expected-note @+1 {{XBar defines data width as 64}}
  %bus = axi4.xbar(%clk, managers = [%mgr_downsized], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

// Test: Resizer still results in width mismatch
module @xbar_resizer_still_mismatch {
  %clk = axi4.clock @test_clk

  %mgr_narrow = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 32 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Upsize from 32 to 128, but xbar is 64
  // expected-note @+1 {{Manager defines data width as 128}}
  %mgr_upsized = axi4.resizer %mgr_narrow {target_width = 128 : ui32} : !axi4.manager

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager data width mismatch}}
  // expected-note @+1 {{XBar defines data width as 64}}
  %bus = axi4.xbar(%clk, managers = [%mgr_upsized], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

// Test: Subordinate resizer mismatch
module @xbar_subordinate_resizer_mismatch {
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub_wide = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // Downsize subordinate from 128 to 32, but xbar is 64
  // expected-note @+1 {{Subordinate defines data width as 32}}
  %sub_downsized = axi4.resizer %sub_wide {target_width = 32 : ui32} : !axi4.subordinate

  // expected-error @+2 {{'axi4.xbar' op subordinate data width mismatch}}
  // expected-note @+1 {{XBar defines data width as 64}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub_downsized]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Xbar configuration errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_invalid_data_width {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.xbar' op data_width must be 32, 64, 128, 256, or 512}}
  %bus = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 96 : ui32
  }
}

// -----

module @xbar_addr_width_too_small {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.xbar' op addr_width must be in range [12, 64]}}
  %bus = axi4.xbar(%clk) {
    addr_width = 8 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_addr_width_too_large {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.xbar' op addr_width must be in range [12, 64]}}
  %bus = axi4.xbar(%clk) {
    addr_width = 128 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_pool_without_size {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.xbar' op pool_size is required when txn_policy is 'pool'}}
  %bus = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  txn_policy = #axi4.txn_policy<pool>
  }
}

// -----

module @xbar_pool_size_without_policy {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.xbar' op pool_size should only be specified when txn_policy is 'pool'}}
  %bus = axi4.xbar(%clk) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  pool_size = 4 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Adapter validation errors
//===----------------------------------------------------------------------===//

// -----

module @resizer_invalid_width {
  %clk = axi4.clock @test_clk
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 32 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }
  // expected-error @+1 {{'axi4.resizer' op target_width must be 32, 64, 128, 256, or 512}}
  %wide = axi4.resizer %mgr {target_width = 100 : ui32} : !axi4.manager
}

// -----

module @cdc_depth_too_small {
  %clk1 = axi4.clock @clk1
  %clk2 = axi4.clock @clk2
  %mgr = axi4.manager %clk1 {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }
  // expected-error @+1 {{'axi4.cdc' op CDC depth must be at least 2}}
%crossed = axi4.cdc %mgr, %clk2 {depth = 1 : ui32} : !axi4.manager
}

// -----

module @exclusive_monitor_invalid_granularity {
  %clk = axi4.clock @test_clk
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }
  // expected-error @+1 {{'axi4.exclusive_monitor' op granularity must be a power of 2}}
  %excl = axi4.exclusive_monitor %sub {granularity = 48 : ui32, entries = 8 : ui32}
}

// -----

module @exclusive_monitor_zero_entries {
  %clk = axi4.clock @test_clk
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }
  // expected-error @+1 {{'axi4.exclusive_monitor' op entries must be >= 1}}
  %excl = axi4.exclusive_monitor %sub {granularity = 64 : ui32, entries = 0 : ui32}
}

//===----------------------------------------------------------------------===//
// Error subordinate validation
//===----------------------------------------------------------------------===//

// -----

module @error_subordinate_invalid_width {
  %clk = axi4.clock @test_clk
  // expected-error @+1 {{'axi4.error_subordinate' op data_width must be 32, 64, 128, 256, or 512}}
  %err = axi4.error_subordinate %clk {
    window = #axi4.window<base = 0xFFFF0000, size = 0x10000>,
    data_width = 16 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Burst capability mismatch errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_burst_incr_mismatch {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager defined here}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op burst capability mismatch: manager INCR burst length (256) exceeds subordinate maximum (64)}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_burst_fixed_not_supported {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager defined here}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16, fixed = 8>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op burst capability mismatch: manager requires FIXED bursts but subordinate does not support FIXED}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_burst_wrap_not_supported {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager defined here}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16, wrap = [4, 8]>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op burst capability mismatch: manager requires WRAP bursts but subordinate does not support WRAP}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Exclusive mode validation errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_exclusive_strict_mismatch {
  %clk = axi4.clock @test_clk

  // expected-note @+1 {{manager with exclusive=true defined here}}
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    exclusive = true
  }

  // expected-note @+1 {{subordinate without exclusive support defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>,
    exclusive = false
  }

  // expected-error @+2 {{'axi4.xbar' op exclusive access mismatch: manager requires exclusive access but subordinate does not support it}}
  // expected-note @+1 {{xbar has exclusive_mode=strict; use exclusive_mode=advisory to allow this, or add an exclusive_monitor adapter}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  exclusive_mode = #axi4.exclusive_mode<strict>
  }
}

//===----------------------------------------------------------------------===//
// Bridge validation errors
//===----------------------------------------------------------------------===//

// -----

module @bridge_zero_outstanding {
  %clk1 = axi4.clock @clk1
  %clk2 = axi4.clock @clk2
  %upstream = axi4.xbar(%clk1) {addr_width = 32 : ui32, data_width = 64 : ui32}
  %downstream = axi4.xbar(%clk2) {addr_width = 32 : ui32, data_width = 64 : ui32}
  // expected-error @+1 {{'axi4.bridge' op outstanding must be >= 1}}
  axi4.bridge %upstream, %downstream {
    upstream_window = #axi4.window<base = 0x40000000, size = 0x100000>,
    downstream_base = 0 : ui64,
    outstanding = 0 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Outstanding capacity errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_capacity_expand_insufficient {
  // Test: txn_policy=expand (default) requires sum of managers' outstanding
  // Manager has 4+4=8 outstanding, subordinate only has 4
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op insufficient subordinate outstanding capacity: subordinate has 4 but requires 8 (sum of reachable managers' outstanding (txn_policy=expand))}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  capacity_check = #axi4.capacity_check<error>
  }
}

// -----

module @xbar_capacity_serialize_insufficient {
  // Test: txn_policy=serialize requires max of managers' outstanding
  // Two managers with 8 and 4 outstanding, subordinate only has 4
  %clk = axi4.clock @test_clk

  %mgr1 = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %mgr2 = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 2 : ui32,
    outstanding_writes = 2 : ui32
  }

  // expected-note @+1 {{subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op insufficient subordinate outstanding capacity: subordinate has 4 but requires 8 (max of reachable managers' outstanding (txn_policy=serialize))}}
  %bus = axi4.xbar(%clk, managers = [%mgr1, %mgr2], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  txn_policy = #axi4.txn_policy<serialize>,
    capacity_check = #axi4.capacity_check<error>
  }
}

// -----

module @xbar_capacity_pool_insufficient {
  // Test: txn_policy=pool requires pool_size
  // pool_size=8, subordinate only has 4
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{subordinate defined here}}
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op insufficient subordinate outstanding capacity: subordinate has 4 but requires 8 (pool_size (txn_policy=pool))}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  txn_policy = #axi4.txn_policy<pool>,
    pool_size = 8 : ui32,
    capacity_check = #axi4.capacity_check<error>
  }
}

//===----------------------------------------------------------------------===//
// Window disjointness errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_overlapping_windows_full {
  // Test: Fully overlapping windows (same window) should error
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x2000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{first subordinate window: [0x0, 0x1000)}}
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-note @+1 {{second subordinate window: [0x0, 0x1000)}}
  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op subordinate windows overlap}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_overlapping_windows_partial {
  // Test: Partially overlapping windows should error
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x3000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Window 1: [0x0, 0x2000)
  // expected-note @+1 {{first subordinate window: [0x0, 0x2000)}}
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x2000>
  }

  // Window 2: [0x1000, 0x3000) - overlaps with window 1 at [0x1000, 0x2000)
  // expected-note @+1 {{second subordinate window: [0x1000, 0x3000)}}
  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x1000, size = 0x2000>
  }

  // expected-error @+1 {{'axi4.xbar' op subordinate windows overlap}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_overlapping_windows_contained {
  // Test: One window contained within another should error
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x10000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Large window: [0x0, 0x10000)
  // expected-note @+1 {{first subordinate window: [0x0, 0x10000)}}
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x10000>
  }

  // Small window inside: [0x1000, 0x2000)
  // expected-note @+1 {{second subordinate window: [0x1000, 0x2000)}}
  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x1000, size = 0x1000>
  }

  // expected-error @+1 {{'axi4.xbar' op subordinate windows overlap}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_overlapping_windows_three_subordinates {
  // Test: Three subordinates where two overlap should error
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x30000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Window 1: [0x0, 0x10000) - disjoint from window 3
  // expected-note @+1 {{first subordinate window: [0x0, 0x10000)}}
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x10000>
  }

  // Window 2: [0x8000, 0x18000) - overlaps with window 1
  // expected-note @+1 {{second subordinate window: [0x8000, 0x18000)}}
  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x8000, size = 0x10000>
  }

  // Window 3: [0x20000, 0x30000) - disjoint from window 1
  %sub3 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x20000, size = 0x10000>
  }

  // expected-error @+1 {{'axi4.xbar' op subordinate windows overlap}}
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2, %sub3]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

//===----------------------------------------------------------------------===//
// Clock domain mismatch errors
//===----------------------------------------------------------------------===//

// -----

module @xbar_manager_clock_mismatch {
  // Test: Manager on different clock than xbar should error
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  // expected-note @+1 {{manager has different effective clock domain}}
  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk_b {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager clock domain mismatch}}
  // expected-note @+1 {{xbar clock domain defined here; use axi4.cdc to cross clock domains}}
  %bus = axi4.xbar(%clk_b, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_subordinate_clock_mismatch {
  // Test: Subordinate on different clock than xbar should error
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // expected-note @+1 {{subordinate has different effective clock domain}}
  %sub = axi4.subordinate %clk_b {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-error @+2 {{'axi4.xbar' op subordinate clock domain mismatch}}
  // expected-note @+1 {{xbar clock domain defined here; use axi4.cdc to cross clock domains}}
  %bus = axi4.xbar(%clk_a, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_cdc_wrong_target_clock {
  // Test: CDC to wrong clock should still result in mismatch
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b
  %clk_c = axi4.clock @clk_c

  // Manager on clk_a
  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // CDC to clk_c (not clk_b which is xbar clock)
  // expected-note @+1 {{manager has different effective clock domain}}
%mgr_cdc = axi4.cdc %mgr, %clk_c : !axi4.manager

  %sub = axi4.subordinate %clk_b {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager clock domain mismatch}}
  // expected-note @+1 {{xbar clock domain defined here; use axi4.cdc to cross clock domains}}
  %bus = axi4.xbar(%clk_b, managers = [%mgr_cdc], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_adapter_chain_clock_mismatch {
  // Test: Clock mismatch detected through adapter chain
  %fast_clk = axi4.clock @fast_clk
  %slow_clk = axi4.clock @slow_clk

  // Manager on fast clock
  %mgr = axi4.manager %fast_clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 128>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Resize (still on fast clock)
  %mgr_resized = axi4.resizer %mgr {target_width = 64 : ui32} : !axi4.manager

  // Burst split (still on fast clock) - no CDC, so still on fast_clk
  // expected-note @+1 {{manager has different effective clock domain}}
  %mgr_split = axi4.burst_splitter %mgr_resized {
    burst_capability = #axi4.burst_capability<incr = 16>
  }

  %sub = axi4.subordinate %slow_clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // Xbar on slow_clk, but manager chain is still on fast_clk
  // expected-error @+2 {{'axi4.xbar' op manager clock domain mismatch}}
  // expected-note @+1 {{xbar clock domain defined here; use axi4.cdc to cross clock domains}}
  %bus = axi4.xbar(%slow_clk, managers = [%mgr_split], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

module @xbar_multiple_managers_one_clock_mismatch {
  // Test: Multiple managers, one has clock mismatch
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  // First manager on correct clock
  %mgr1 = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Second manager on wrong clock
  // expected-note @+1 {{manager has different effective clock domain}}
  %mgr2 = axi4.manager %clk_b {
    access = [#axi4.window<base = 0x1000, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk_a {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x2000>
  }

  // expected-error @+2 {{'axi4.xbar' op manager clock domain mismatch}}
  // expected-note @+1 {{xbar clock domain defined here; use axi4.cdc to cross clock domains}}
  %bus = axi4.xbar(%clk_a, managers = [%mgr1, %mgr2], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}
