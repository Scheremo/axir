// RUN: axi4-opt %s -split-input-file -canonicalize-axi4-adapters | FileCheck %s

//===----------------------------------------------------------------------===//
// Canonicalize: resizer -> burst_splitter -> cdc
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_full_chain
// CHECK: %[[CLK_A:.+]] = axi4.clock
// CHECK: %[[CLK_B:.+]] = axi4.clock
// CHECK: %[[MGR:.+]] = axi4.manager %[[CLK_A]]
module @canonicalize_full_chain {
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %mgr_cdc = axi4.cdc %mgr, %clk_b : !axi4.manager
  %mgr_split = axi4.burst_splitter %mgr_cdc {
    burst_capability = #axi4.burst_capability<incr = 16>
  }
  %mgr_resized = axi4.resizer %mgr_split {target_width = 64 : ui32} : !axi4.manager

  // CHECK: %[[RESIZED:.+]] = axi4.resizer %[[MGR]] {target_width = 64 : ui32} : !axi4.manager
  // CHECK: %[[SPLIT:.+]] = axi4.burst_splitter %[[RESIZED]] {burst_capability = #axi4.burst_capability<incr = 32>}
  // CHECK: %[[CDC:.+]] = axi4.cdc %[[SPLIT]], %[[CLK_B]] : !axi4.manager
  %bus = axi4.xbar(%clk_b, managers = [%mgr_resized]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Canonicalize: resizer before cdc for subordinates
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_subordinate_chain
// CHECK: %[[CLK_A:.+]] = axi4.clock
// CHECK: %[[CLK_B:.+]] = axi4.clock
// CHECK: %[[SUB:.+]] = axi4.subordinate %[[CLK_A]]
module @canonicalize_subordinate_chain {
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  %sub = axi4.subordinate %clk_a {
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding = 4 : ui32,
    window = #axi4.window<base = 0x0, size = 0x1000>
  }

  %sub_cdc = axi4.cdc %sub, %clk_b : !axi4.subordinate
  %sub_resized = axi4.resizer %sub_cdc {target_width = 64 : ui32} : !axi4.subordinate

  // CHECK: %[[RESIZED:.+]] = axi4.resizer %[[SUB]] {target_width = 64 : ui32} : !axi4.subordinate
  // CHECK: %[[CDC:.+]] = axi4.cdc %[[RESIZED]], %[[CLK_B]] : !axi4.subordinate
  %bus = axi4.xbar(%clk_b, managers = [], subordinates = [%sub_resized]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32
  }
}

// -----

//===----------------------------------------------------------------------===//
// Canonicalize: burst_splitter before cdc
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_splitter_chain
// CHECK: %[[CLK_A:.+]] = axi4.clock
// CHECK: %[[CLK_B:.+]] = axi4.clock
// CHECK: %[[MGR:.+]] = axi4.manager %[[CLK_A]]
module @canonicalize_splitter_chain {
  %clk_a = axi4.clock @clk_a
  %clk_b = axi4.clock @clk_b

  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %mgr_cdc = axi4.cdc %mgr, %clk_b : !axi4.manager
  %mgr_split = axi4.burst_splitter %mgr_cdc {
    burst_capability = #axi4.burst_capability<incr = 16>
  }

  // CHECK: %[[SPLIT:.+]] = axi4.burst_splitter %[[MGR]] {burst_capability = #axi4.burst_capability<incr = 16>}
  // CHECK: %[[CDC:.+]] = axi4.cdc %[[SPLIT]], %[[CLK_B]] : !axi4.manager
  %bus = axi4.xbar(%clk_b, managers = [%mgr_split]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Canonicalize: collapse multiple resizers
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_resizer_chain
// CHECK: %[[CLK:.+]] = axi4.clock
// CHECK: %[[MGR:.+]] = axi4.manager %[[CLK]]
// CHECK: %[[RESIZED:.+]] = axi4.resizer %[[MGR]] {target_width = 64 : ui32} : !axi4.manager
// CHECK-NOT: axi4.resizer %[[RESIZED]]
module @canonicalize_resizer_chain {
  %clk = axi4.clock @clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 128 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %mid = axi4.resizer %mgr {target_width = 32 : ui32} : !axi4.manager
  %final = axi4.resizer %mid {target_width = 64 : ui32} : !axi4.manager

  %bus = axi4.xbar(%clk, managers = [%final]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Canonicalize: collapse multiple burst_splitters
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_splitter_chain_collapse
// CHECK: %[[CLK:.+]] = axi4.clock
// CHECK: %[[MGR:.+]] = axi4.manager %[[CLK]]
// CHECK: %[[SPLIT:.+]] = axi4.burst_splitter %[[MGR]] {burst_capability = #axi4.burst_capability<incr = 16>}
// CHECK-NOT: axi4.burst_splitter %[[SPLIT]]
module @canonicalize_splitter_chain_collapse {
  %clk = axi4.clock @clk

  %mgr = axi4.manager %clk {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 64>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %mid = axi4.burst_splitter %mgr {
    burst_capability = #axi4.burst_capability<incr = 32>
  }
  %final = axi4.burst_splitter %mid {
    burst_capability = #axi4.burst_capability<incr = 16>
  }

  %bus = axi4.xbar(%clk, managers = [%final]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Canonicalize: collapse multiple cdc ops
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_cdc_chain_collapse
// CHECK: %[[CLK_A:.+]] = axi4.clock
// CHECK: %[[CLK_B:.+]] = axi4.clock
// CHECK: %[[MGR:.+]] = axi4.manager %[[CLK_A]]
// CHECK: %[[CDC:.+]] = axi4.cdc %[[MGR]], %[[CLK_B]] : !axi4.manager
// CHECK-NOT: axi4.cdc %[[CDC]]
module @canonicalize_cdc_chain_collapse {
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

  %mid = axi4.cdc %mgr, %clk_b {depth = 4 : ui32} : !axi4.manager
  %final = axi4.cdc %mid, %clk_b {depth = 4 : ui32} : !axi4.manager

  %bus = axi4.xbar(%clk_b, managers = [%final]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}

// -----

//===----------------------------------------------------------------------===//
// Canonicalize: collapse CDC through intermediate clock
//===----------------------------------------------------------------------===//

// CHECK-LABEL: module @canonicalize_cdc_chain_intermediate
// CHECK: %[[CLK_A:.+]] = axi4.clock
// CHECK: %[[CLK_C:.+]] = axi4.clock
// CHECK: %[[CLK_B:.+]] = axi4.clock
// CHECK: %[[MGR:.+]] = axi4.manager %[[CLK_A]]
// CHECK: %[[CDC:.+]] = axi4.cdc %[[MGR]], %[[CLK_B]] : !axi4.manager
// CHECK-NOT: axi4.cdc %[[CDC]]
module @canonicalize_cdc_chain_intermediate {
  %clk_a = axi4.clock @clk_a
  %clk_c = axi4.clock @clk_c
  %clk_b = axi4.clock @clk_b

  %mgr = axi4.manager %clk_a {
    access = [#axi4.window<base = 0x0, size = 0x1000>],
    burst_capability = #axi4.burst_capability<incr = 16>,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
    outstanding_reads = 4 : ui32,
    outstanding_writes = 4 : ui32
  }

  %mid = axi4.cdc %mgr, %clk_c {depth = 4 : ui32} : !axi4.manager
  %final = axi4.cdc %mid, %clk_b {depth = 4 : ui32} : !axi4.manager

  %bus = axi4.xbar(%clk_b, managers = [%final]) {
    addr_width = 32 : ui32,
    data_width = 64 : ui32,
    external_id_width = 8 : ui32,
  default_error = #axi4.error_response<decerr>
  }
}
