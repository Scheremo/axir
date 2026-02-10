// RUN: axi4-opt %s | axi4-opt | FileCheck %s

// Clock defintions

// CHECK-LABEL: module @clock {
module @clock {
  // CHECK: [[SYSCLK:%.+]] = axi4.clock @sys_clk
  %sys_clk = axi4.clock @sys_clk
  // CHECK: [[CLUCLK:%.+]] = axi4.clock @clu_clk {freq = 200000000 : ui64}
  %clu_clk = axi4.clock @clu_clk { freq = 200000000 : ui64 }
}

// Manager definitions

// CHECK-LABEL: module @manager {
module @manager {
  // CHECK: [[CLK:%.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: [[MGR:%.+]] = axi4.manager [[CLK]] {
  // CHECK-SAME: access = [#axi4.window<base = 268435456, size = 4294967296>],
  // CHECK-SAME: burst_capability = #axi4.burst_capability<incr = 256>,
  // CHECK-SAME: data_width = 64 : ui32,
// CHECK-SAME: external_id_width = 8 : ui32,
  // CHECK-SAME: outstanding_reads = 4 : ui32,
  // CHECK-SAME: outstanding_writes = 4 : ui32
  // CHECK-SAME: }

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x10000000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

}

// Subordinate definitions

// CHECK-LABEL: module @subordinate {
module @subordinate {
  // CHECK: [[CLK:%.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: [[sub:%.+]] = axi4.subordinate [[CLK]] {
  // CHECK-SAME: burst_capability = #axi4.burst_capability<incr = 256>,
  // CHECK-SAME: data_width = 64 : ui32,
// CHECK-SAME: external_id_width = 8 : ui32,
  // CHECK-SAME: outstanding = 4 : ui32,
  // CHECK-SAME: window = #axi4.window<base = 268435456, size = 4294967296>
  // CHECK-SAME: }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x10000000, size = 0x100000000>
  }

}

// Xbar definitions

// CHECK-LABEL: module @xbar {
module @xbar {
  // CHECK: %[[CLK:.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: %[[mgr:.+]] = axi4.manager %[[CLK]] {
  // CHECK-SAME: access = [#axi4.window<base = 305397760, size = 4294967296>],
  // CHECK-SAME: burst_capability = #axi4.burst_capability<incr = 256>,
  // CHECK-SAME: data_width = 64 : ui32,
// CHECK-SAME: external_id_width = 8 : ui32,
  // CHECK-SAME: outstanding_reads = 4 : ui32,
  // CHECK-SAME: outstanding_writes = 4 : ui32
  // CHECK-SAME: }

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x12340000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // CHECK: %[[sub:.+]] = axi4.subordinate %[[CLK]] {
  // CHECK-SAME: burst_capability = #axi4.burst_capability<incr = 256>,
  // CHECK-SAME: data_width = 64 : ui32,
// CHECK-SAME: external_id_width = 8 : ui32,
  // CHECK-SAME: outstanding = 8 : ui32,
  // CHECK-SAME: window = #axi4.window<base = 305397760, size = 4294967296>
  // CHECK-SAME: }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x12340000, size = 0x100000000>
  }

  // CHECK: %[[XBAR:.+]] = axi4.xbar(%[[CLK]],
  // CHECK-SAME: managers = [%[[mgr]]],
  // CHECK-SAME: subordinates = [%[[sub]]])
  // CHECK-SAME: {addr_width = 32 : ui32, data_width = 64 : ui32}

  %narrow_bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
  addr_width = 32 : ui32,
  data_width = 64 : ui32 }
}

// Burst splitter definitions

// CHECK-LABEL: module @burst_splitter {
module @burst_splitter {
  // CHECK: %[[CLK:.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: %[[mgr:.+]] = axi4.manager %[[CLK]] {
  // CHECK-SAME: access = [#axi4.window<base = 305397760, size = 4294967296>],
  // CHECK-SAME: burst_capability = #axi4.burst_capability<incr = 256>,
  // CHECK-SAME: data_width = 64 : ui32,
// CHECK-SAME: external_id_width = 8 : ui32,
  // CHECK-SAME: outstanding_reads = 4 : ui32,
  // CHECK-SAME: outstanding_writes = 4 : ui32
  // CHECK-SAME: }

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x12340000, size = 0x100000000>],
    burst_capability = #axi4.burst_capability<incr = 256>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // CHECK: %[[mgr_split:.+]] = axi4.burst_splitter %[[mgr]] {burst_capability = #axi4.burst_capability<incr = 64>}
  %mgr_split = axi4.burst_splitter %mgr {
    burst_capability = #axi4.burst_capability<incr = 64>
  }

  // CHECK: %[[sub:.+]] = axi4.subordinate %[[CLK]] {
  // CHECK-SAME: burst_capability = #axi4.burst_capability<incr = 64>,
  // CHECK-SAME: data_width = 64 : ui32,
// CHECK-SAME: external_id_width = 8 : ui32,
  // CHECK-SAME: outstanding = 8 : ui32,
  // CHECK-SAME: window = #axi4.window<base = 305397760, size = 4294967296>
  // CHECK-SAME: }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x12340000, size = 0x100000000>
  }

  // CHECK: %[[XBAR:.+]] = axi4.xbar(%[[CLK]],
  // CHECK-SAME: managers = [%[[mgr_split]]],
  // CHECK-SAME: subordinates = [%[[sub]]])
  // CHECK-SAME: {addr_width = 32 : ui32, data_width = 64 : ui32}

  %narrow_bus = axi4.xbar(%clk, managers = [%mgr_split], subordinates = [%sub]) {
  addr_width = 32 : ui32,
  data_width = 64 : ui32
}
}


// Exclusive mode tests

// CHECK-LABEL: module @xbar_exclusive_advisory_allows_mismatch {
module @xbar_exclusive_advisory_allows_mismatch {
  // CHECK: %[[CLK:.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: %[[mgr:.+]] = axi4.manager %[[CLK]] {
  // CHECK-SAME: exclusive = true
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    exclusive = true
  }

  // CHECK: %[[sub:.+]] = axi4.subordinate %[[CLK]] {
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>,
    exclusive = false
  }

  // CHECK: axi4.xbar(%[[CLK]], managers = [%[[mgr]]], subordinates = [%[[sub]]])
  // CHECK-SAME: exclusive_mode = #axi4.exclusive_mode<advisory>
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  exclusive_mode = #axi4.exclusive_mode<advisory>
  }
}

// CHECK-LABEL: module @xbar_exclusive_strict_subordinate_supports {
module @xbar_exclusive_strict_subordinate_supports {
  // CHECK: %[[CLK:.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: %[[mgr:.+]] = axi4.manager %[[CLK]] {
  // CHECK-SAME: exclusive = true
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    exclusive = true
  }

  // CHECK: %[[sub:.+]] = axi4.subordinate %[[CLK]] {
  // CHECK-SAME: exclusive = true
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>,
    exclusive = true
  }

  // CHECK: axi4.xbar(%[[CLK]], managers = [%[[mgr]]], subordinates = [%[[sub]]])
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  exclusive_mode = #axi4.exclusive_mode<strict>
  }
}

// CHECK-LABEL: module @xbar_exclusive_monitor_satisfies_strict {
module @xbar_exclusive_monitor_satisfies_strict {
  // CHECK: %[[CLK:.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: %[[mgr:.+]] = axi4.manager %[[CLK]] {
  // CHECK-SAME: exclusive = true
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    exclusive = true
  }

  // CHECK: %[[sub:.+]] = axi4.subordinate %[[CLK]] {
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>,
    exclusive = false
  }

  // CHECK: %[[sub_excl:.+]] = axi4.exclusive_monitor %[[sub]] {entries = 4 : ui32, granularity = 64 : ui32}
  %sub_excl = axi4.exclusive_monitor %sub {
    granularity = 64 : ui32,
    entries = 4 : ui32
  }

  // CHECK: axi4.xbar(%[[CLK]], managers = [%[[mgr]]], subordinates = [%[[sub_excl]]])
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub_excl]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  exclusive_mode = #axi4.exclusive_mode<strict>
  }
}

// CHECK-LABEL: module @xbar_exclusive_strict_no_exclusive_needed {
module @xbar_exclusive_strict_no_exclusive_needed {
  // CHECK: %[[CLK:.+]] = axi4.clock @test_clk
  %clk = axi4.clock @test_clk

  // CHECK: %[[mgr:.+]] = axi4.manager %[[CLK]] {
  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32,
    exclusive = false
  }

  // CHECK: %[[sub:.+]] = axi4.subordinate %[[CLK]] {
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>,
    exclusive = false
  }

  // CHECK: axi4.xbar(%[[CLK]], managers = [%[[mgr]]], subordinates = [%[[sub]]])
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  exclusive_mode = #axi4.exclusive_mode<strict>
  }
}

// Outstanding transaction capacity tests

// CHECK-LABEL: module @xbar_capacity_expand_adequate {
module @xbar_capacity_expand_adequate {
  // Test: txn_policy=expand requires sum of managers' outstanding
  // Manager has 4+4=8 outstanding, subordinate has 8, should pass
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // CHECK: axi4.xbar
  // No warning - subordinate outstanding (8) >= sum of manager outstanding (8)
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_capacity_serialize_adequate {
module @xbar_capacity_serialize_adequate {
  // Test: txn_policy=serialize requires max of managers' outstanding
  // Two managers with 8 and 4 outstanding, subordinate has 8, should pass
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

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // CHECK: axi4.xbar
  // No warning - subordinate outstanding (8) >= max of manager outstanding (8)
  %bus = axi4.xbar(%clk, managers = [%mgr1, %mgr2], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  txn_policy = #axi4.txn_policy<serialize>
  }
}

// CHECK-LABEL: module @xbar_capacity_pool_adequate {
module @xbar_capacity_pool_adequate {
  // Test: txn_policy=pool requires pool_size
  // pool_size=4, subordinate has 4, should pass
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0, size = 0x1000>
  }

  // CHECK: axi4.xbar
  // No warning - subordinate outstanding (4) >= pool_size (4)
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  txn_policy = #axi4.txn_policy<pool>,
    pool_size = 4 : ui32
  }
}

// Window disjointness tests

// CHECK-LABEL: module @xbar_disjoint_windows {
module @xbar_disjoint_windows {
  // Test: Multiple subordinates with disjoint windows should pass
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x30000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Three subordinates with non-overlapping windows
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x10000>
  }

  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x10000, size = 0x10000>
  }

  %sub3 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x20000, size = 0x10000>
  }

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2, %sub3]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_adjacent_windows {
module @xbar_adjacent_windows {
  // Test: Adjacent windows (touching but not overlapping) should pass
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0, size = 0x2000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Window 1: [0x0, 0x1000)
  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // Window 2: [0x1000, 0x2000) - starts exactly where window 1 ends
  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x1000, size = 0x1000>
  }

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// Coverage verification tests

// CHECK-LABEL: module @xbar_full_coverage {
module @xbar_full_coverage {
  // Test: Manager access fully covered by subordinates
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x1000, size = 0x2000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Subordinate covers entire manager access range
  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x10000>
  }

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_coverage_by_multiple_subordinates {
module @xbar_coverage_by_multiple_subordinates {
  // Test: Manager access covered by union of multiple subordinate windows
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x3000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x1000, size = 0x1000>
  }

  %sub3 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x2000, size = 0x1000>
  }

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2, %sub3]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_uncovered_with_default_error {
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

  // CHECK: axi4.xbar
  // Uncovered region [0x1000, 0x10000) will get decerr response
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// CHECK-LABEL: module @xbar_multiple_manager_access_windows {
module @xbar_multiple_manager_access_windows {
  // Test: Manager with multiple access windows, all covered
  %clk = axi4.clock @test_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>,
              #axi4.window<base = 0x10000, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub1 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %sub2 = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x10000, size = 0x1000>
  }

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub1, %sub2]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// Clock domain matching tests

// CHECK-LABEL: module @xbar_same_clock_domain {
module @xbar_same_clock_domain {
  // Test: All endpoints on same clock domain should pass
  %clk = axi4.clock @sys_clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %sub = axi4.subordinate %clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%clk, managers = [%mgr], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_cdc_manager_to_xbar_clock {
module @xbar_cdc_manager_to_xbar_clock {
  // Test: Manager on different clock, CDC brings it to xbar clock
  %fast_clk = axi4.clock @fast_clk
  %slow_clk = axi4.clock @slow_clk

  // Manager is on fast clock
  %mgr = axi4.manager %fast_clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // CDC crosses from fast to slow (xbar clock)
  %mgr_cdc = axi4.cdc %mgr, %slow_clk : !axi4.manager

  // Subordinate is on slow clock
  %sub = axi4.subordinate %slow_clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // CHECK: axi4.xbar
  // Xbar is on slow clock - mgr_cdc and sub both have effective clock = slow_clk
  %bus = axi4.xbar(%slow_clk, managers = [%mgr_cdc], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_cdc_subordinate_to_xbar_clock {
module @xbar_cdc_subordinate_to_xbar_clock {
  // Test: Subordinate on different clock, CDC brings it to xbar clock
  %fast_clk = axi4.clock @fast_clk
  %slow_clk = axi4.clock @slow_clk

  // Manager is on fast clock
  %mgr = axi4.manager %fast_clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Subordinate is on slow clock
  %sub = axi4.subordinate %slow_clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // CDC crosses subordinate from slow to fast (xbar clock)
  %sub_cdc = axi4.cdc %sub, %fast_clk : !axi4.subordinate

  // CHECK: axi4.xbar
  // Xbar is on fast clock - mgr and sub_cdc both have effective clock = fast_clk
  %bus = axi4.xbar(%fast_clk, managers = [%mgr], subordinates = [%sub_cdc]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_cdc_both_endpoints {
module @xbar_cdc_both_endpoints {
  // Test: Both manager and subordinate on different clocks, CDC brings both to xbar clock
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b
  %xbar_clk = axi4.clock @xbar_clk

  // Manager is on clk_a
  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // CDC crosses manager from clk_a to xbar_clk
  %mgr_cdc = axi4.cdc %mgr, %xbar_clk : !axi4.manager

  // Subordinate is on clk_b
  %sub = axi4.subordinate %clk_b {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // CDC crosses subordinate from clk_b to xbar_clk
  %sub_cdc = axi4.cdc %sub, %xbar_clk : !axi4.subordinate

  // CHECK: axi4.xbar
  %bus = axi4.xbar(%xbar_clk, managers = [%mgr_cdc], subordinates = [%sub_cdc]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// CHECK-LABEL: module @xbar_clock_through_adapter_chain {
module @xbar_clock_through_adapter_chain {
  // Test: Clock propagation through adapter chain (resizer, burst_splitter, cdc)
  %fast_clk = axi4.clock @fast_clk
  %slow_clk = axi4.clock @slow_clk

  // Manager is on fast clock with wide data
  %mgr = axi4.manager %fast_clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 128>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  // Resize to 64-bit (still on fast_clk)
  %mgr_resized = axi4.resizer %mgr {target_width = 64 : ui32} : !axi4.manager

  // Split bursts (still on fast_clk)
  %mgr_split = axi4.burst_splitter %mgr_resized {
    burst_capability = #axi4.burst_capability<incr = 16>
  }

  // CDC to slow_clk (changes clock domain)
  %mgr_cdc = axi4.cdc %mgr_split, %slow_clk : !axi4.manager

  // Subordinate is on slow clock
  %sub = axi4.subordinate %slow_clk {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 8 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  // CHECK: axi4.xbar
  // Xbar is on slow_clk - effective clock of mgr_cdc is slow_clk
  %bus = axi4.xbar(%slow_clk, managers = [%mgr_cdc], subordinates = [%sub]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}
