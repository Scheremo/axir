# axi4

AXI4 declarative interconnect dialect for MLIR.

## Contents

```
axi4/
├── CMakeLists.txt                 # Top-level CMake configuration
├── cmake/modules/
│   └── Addaxi4.cmake              # Helper CMake functions
├── include/axi4/
│   ├── CMakeLists.txt             # TableGen generation rules
│   ├── axi4Dialect.td             # Dialect definition
│   ├── axi4Dialect.h              # Dialect C++ header
│   ├── axi4Ops.td                 # Operations definition
│   ├── axi4Ops.h                  # Operations C++ header
│   ├── axi4Types.td               # Types definition
│   ├── axi4Types.h                # Types C++ header
│   ├── axi4Attrs.td               # Attributes definition
│   ├── axi4Attrs.h                # Attributes C++ header
│   ├── axi4Interfaces.td          # Op interfaces definition
│   ├── axi4Interfaces.h           # Op interfaces C++ header
│   ├── axi4Passes.td              # Pass definitions
│   ├── axi4Passes.h               # Pass C++ header
│   ├── axi4Analysis.h             # Analysis utilities header
│   └── INTENT.md                  # Dialect specification
├── lib/axi4/
│   ├── CMakeLists.txt             # Library build rules
│   ├── axi4Dialect.cpp            # Dialect initialization
│   ├── axi4Ops.cpp                # Operations implementation
│   ├── axi4Interfaces.cpp         # Interfaces implementation
│   ├── axi4Passes.cpp             # Pass implementations
│   └── axi4Analysis.cpp           # Analysis utilities
├── tools/axi4-opt/
│   ├── CMakeLists.txt             # Tool build rules
│   └── axi4-opt.cpp               # Optimizer driver
├── examples/
│   └── chimera.mlir               # Example SoC interconnect
└── test/axi4/
    ├── basic.mlir                 # Positive tests
    ├── basic-error.mlir           # Op-level error tests
    ├── network-verify.mlir        # Network verification tests
    ├── loop-free.mlir             # Loop detection tests
    ├── alias.mlir                 # Alias operation tests
    ├── canonicalize-adapters.mlir # Adapter canonicalization tests
    └── mesh-noc.mlir              # Mesh NoC topology example
```

## Prerequisites

- CMake 3.20+
- Ninja build system
- C++17 compatible compiler

## Build Instructions

### 1. Clone with submodules

```bash
git clone --recursive https://github.com/Scheremo/axir.git
cd axi4
```

Or if already cloned:

```bash
git submodule update --init --recursive
```

### 2. Build LLVM/MLIR (one-time setup)

```bash
mkdir -p third_party/llvm-project/build
cd third_party/llvm-project/build

cmake -G Ninja ../llvm \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD="Native" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=ON

ninja
cd ../../..
```

### 3. Build axi4

```bash
mkdir build && cd build

cmake -G Ninja .. \
  -DMLIR_DIR=$(pwd)/../third_party/llvm-project/build/lib/cmake/mlir \
  -DCMAKE_BUILD_TYPE=Release

ninja all
```

### 4. Run Tests

```bash
ninja check-axi4
```

## Overview

The axi4 dialect models AXI4 interconnects declaratively:

- **Endpoints**: `axi4.manager` and `axi4.subordinate` define bus participants
- **Networks**: `axi4.xbar` defines crossbar networks with configurable policies
- **Adapters**: Width converters, CDC, burst splitters, exclusive monitors
- **Bridges**: `axi4.bridge` connects networks hierarchically

See `include/axi4/INTENT.md` for the full specification.

## Types

| Type | Description |
|------|-------------|
| `!axi4.clock` | Clock domain reference |
| `!axi4.manager` | Manager (initiator) endpoint handle |
| `!axi4.subordinate` | Subordinate (target) endpoint handle |
| `!axi4.xbar` | Crossbar network handle |

## Operations

### Endpoints

| Operation | Description |
|-----------|-------------|
| `axi4.clock` | Declares a clock domain |
| `axi4.manager` | Declares a manager endpoint with access windows, burst capabilities |
| `axi4.subordinate` | Declares a subordinate endpoint with address window, outstanding capacity |
| `axi4.error_subordinate` | Synthetic subordinate that responds with errors |

### Networks

| Operation | Description |
|-----------|-------------|
| `axi4.xbar` | Crossbar network connecting managers to subordinates |

### Adapters

| Operation | Description |
|-----------|-------------|
| `axi4.resizer` | Converts interface data width (and scales burst lengths accordingly) |
| `axi4.burst_splitter` | Splits long bursts into shorter bursts |
| `axi4.cdc` | Clock domain crossing |
| `axi4.exclusive_monitor` | Adds exclusive access support to non-exclusive subordinates |

### Bridges

| Operation | Description |
|-----------|-------------|
| `axi4.bridge` | Bidirectional bridge between crossbars |

## Attributes

### Custom Attributes

| Attribute | Description |
|-----------|-------------|
| `#axi4.window<base, size>` | Address window (half-open interval) |
| `#axi4.burst_capability<incr, fixed, wrap>` | Supported burst types and lengths |

### Enum Attributes

| Attribute | Values |
|-----------|--------|
| `#axi4.txn_policy<...>` | `expand`, `serialize`, `pool` |
| `#axi4.capacity_check<...>` | `warn`, `error` |
| `#axi4.exclusive_mode<...>` | `strict`, `advisory` |
| `#axi4.arbitration<...>` | `rr`, `wrr`, `priority` |
| `#axi4.error_response<...>` | `decerr`, `slverr` |
| `#axi4.cdc_mode<...>` | `async`, `sync`, `handshake` |
| `#axi4.qos_mode<...>` | `passthrough`, `fixed`, `remap` |
| `#axi4.bridge_exclusive<...>` | `block`, `passthrough`, `terminate` |
| `#axi4.monitor_scope<...>` | `local`, `global` |

## Example

```mlir
// Declare clock domain
%clk = axi4.clock @sys_clk

// Declare a CPU manager
%cpu = axi4.manager %clk {
  access = [#axi4.window<base = 0, size = 0x100000000>],
  data_width = 64 : ui32,
  outstanding_reads = 8 : ui32,
  outstanding_writes = 4 : ui32,
  burst_capability = #axi4.burst_capability<incr = 256>
}

// Declare SRAM subordinate
%sram = axi4.subordinate %clk {
  window = #axi4.window<base = 0x20000000, size = 0x10000>,
  data_width = 64 : ui32,
  outstanding = 16 : ui32,
  burst_capability = #axi4.burst_capability<incr = 256>
}

// Declare DRAM subordinate
%dram = axi4.subordinate %clk {
  window = #axi4.window<base = 0x80000000, size = 0x80000000>,
  data_width = 64 : ui32,
  outstanding = 32 : ui32,
  burst_capability = #axi4.burst_capability<incr = 256>
}

// Create crossbar
%bus = axi4.xbar(%clk, managers = [%cpu], subordinates = [%sram, %dram]) {
  addr_width = 32 : ui32,
  data_width = 64 : ui32,
  txn_policy = #axi4.txn_policy<expand>
}
```

## Verification

### Op-Level Verification

Each operation performs local validation:

- Data width compatibility between endpoints and crossbar
- Burst capability compatibility (INCR, FIXED, WRAP lengths)
- Exclusive access requirements matching
- Outstanding transaction capacity checking based on transaction policy
- Subordinate window disjointness (windows must not overlap within an xbar)
- Overlap is allowed only when using explicit `axi4.alias` of the same target
- Window base/size alignment (4KiB)
- Clock domain matching (all endpoints must be on xbar's clock domain; use `axi4.cdc` to cross domains)

### Network-Level Verification (Pass)

The `verify-axi4-network` pass performs global analysis across bridges:

```bash
axi4-opt input.mlir -verify-axi4-network
```

This pass verifies:

- **Cross-bridge coverage**: Manager access windows are fully covered by reachable subordinate windows, considering paths through bridges
- **Global address uniqueness**: No overlap between reachable subordinate windows when translated into each root xbar's address space
- **Explicit aliasing**: A subordinate reachable at multiple disjoint address ranges must be represented with `axi4.alias`; implicit mirroring is rejected
- **Alias locality**: An `axi4.alias` must appear on the same xbar as its base subordinate
- **Multi-path ambiguity**: Detects overlapping address regions that reach the same subordinate via distinct bridge paths
- **Bridge compatibility**: Ensures bridge burst/exclusive settings are compatible with reachable managers and subordinates
- **Unreachable subordinate warnings**: Subordinates not accessible by any manager through any path
- **Unreachable manager warnings**: Managers that cannot reach any subordinate through any path

The `verify-axi4-loop-free` pass checks for cycles in the crossbar/bridge graph:

```bash
axi4-opt input.mlir -verify-axi4-loop-free
```

This pass verifies:

- **Loop-free topology**: The directed bridge graph (upstream → downstream) must be acyclic

## Canonicalization

The `canonicalize-axi4-adapters` pass normalizes adapter chains into a
deterministic order to simplify analysis and downstream transforms:

```bash
axi4-opt input.mlir -canonicalize-axi4-adapters
```

Canonical adapter order:

- `axi4.resizer` → `axi4.burst_splitter` → `axi4.cdc`

When reordering around a resizer, the pass scales `burst_splitter`
capabilities to preserve effective burst lengths.

## Op Interface

The `Axi4EndpointOpInterface` provides effective property inference through adapter chains:

- `getEffectiveClock()` - Returns clock domain after CDC adapters
- `getEffectiveDataWidth()` - Returns data width after width converters
- `getEffectiveBurstCapabilities()` - Returns burst capabilities after splitters
- `getEffectiveExclusiveAccess()` - Returns exclusive support after monitors
- `getEffectiveOutstanding()` - Returns outstanding capacity
