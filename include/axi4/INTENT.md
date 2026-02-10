# AXI4 Declarative Interconnect Dialect

---

## Terminology

| Term | AXI Spec Term | Definition |
|------|---------------|------------|
| Manager | Master | Initiates transactions (issues requests, receives responses) |
| Subordinate | Slave | Responds to transactions (receives requests, issues responses) |
| Transaction | Transaction | Complete request-response exchange (AW→W→B for writes, AR→R for reads) |
| Beat | Transfer | Single data transfer within a burst (one clock cycle of valid data) |
| Burst | Burst | Sequence of beats forming one transaction |
| Crossbar (xbar) | Interconnect | Routing fabric connecting managers to subordinates |
| Bridge | Bridge | Connects two crossbars, performing protocol/domain adaptation |
| Window | Address region | Contiguous address range defined by base and size |

---

## Intent

This dialect models **AXI4 interconnects declaratively** at a high level:

* Describe **clock domains** as first-class values
* Describe **participants** (managers and subordinates) with explicit clock references
* Describe **networks** (crossbars) that compose clocks, managers, and subordinates
* Describe **hierarchical connectivity** via explicit **bridge** ops

**No ports** are modeled. RTL ports are an implementation detail produced during lowering.

A network is conceptually a **crossbar**. Other fabrics (trees, shared buses, hierarchical interconnects) are represented by **connecting multiple crossbars via bridges**.

**Conceptual Model:**

```
  axi4.clock ─────────────────────────────┐
       │                                  │
       ▼                                  ▼
  ┌─────────┐     ┌─────────┐      ┌─────────────┐
  │ Manager │     │ Manager │      │ Subordinate │
  │  (CPU)  │     │  (DMA)  │      │   (SRAM)    │
  └────┬────┘     └────┬────┘      └──────┬──────┘
       │               │                  │
       │   adapters    │   adapters       │
       │   (cdc, etc)  │   (resizer)      │
       ▼               ▼                  ▼
  ┌────────────────────────────────────────────────────┐
  │                      axi4.xbar                     │
  │  (clock, managers, subordinates as SSA operands)  │
  └────────────────────────────────────────────────────┘
```

---

## Design Principles

### SSA-Based Composition

All major constructs are SSA values:
- **Clocks** are created via `axi4.clock` and produce `!axi4.clock` values
- **Managers** are created via `axi4.manager` with a clock operand
- **Subordinates** are created via `axi4.subordinate` with a clock operand
- **Crossbars** are created via `axi4.xbar` with clock, manager, and subordinate operands

This enables:
- Explicit data flow for clock domains
- Clear def-use chains for verification
- Natural composition in MLIR's SSA form

### Strict Semantics (No Implicit Conversion)

| Concern | Strict Rule | Explicit Solution |
|---------|-------------|-------------------|
| Address overlap | **Prohibited unless explicit alias.** Subordinate windows must be disjoint within a network unless one is an `axi4.alias` of the other. | Use `axi4.alias` for intentional mirroring. |
| Data width mismatch | **Prohibited.** All bound endpoints must match network width. | Insert explicit `axi4.resizer` before binding. |
| Clock domain mismatch | **Prohibited.** All bound endpoints must use the xbar's clock. | Insert explicit `axi4.cdc` before binding. |
| Burst length mismatch | **Prohibited.** Manager burst capability must not exceed subordinate. | Insert explicit `axi4.burst_splitter`. |
| Decode errors | **Explicitly specified handling required.** | Bind error subordinates or set `default_error` on xbar. |

**Note on bridges:** Bridges are *composite* constructs that encapsulate adaptation logic internally. A bridge between two xbars with different clocks/widths contains implicit CDC and width conversion *within the bridge itself*.

### Window Specification

All addresses, offsets, and window bounds are specified in **bytes**. Windows are specified as structs:

```mlir
{ base = 0x1000_0000, size = 0x0001_0000 }
```

**Window constraints:**
- `size > 0` (zero-size windows are illegal)
- `base >= 0`
- `base + size <= 2^addr_width` (no overflow)
- `base` and `size` are unsigned integers

The effective address range is `[base, base + size)` (half-open interval).

### Declarative Transaction Model

Endpoints declare **transaction capacity** (how many transactions they can have
in flight). Endpoints may also declare **external ID width**
(`external_id_width`, in bits) when boundary compatibility must be explicit.
Crossbar internals may derive additional bookkeeping requirements from these.

### Crossbar Admission Control (Safety Invariant)

The crossbar **must not forward** more than `S.outstanding` transactions to any subordinate S. This invariant **always holds**.

### Capacity Verification (Performance Bound)

Capacity verification checks whether the system is sized such that the safety invariant never causes backpressure. By default, capacity violations are **warnings**. With `capacity_check = "error"`, they become **hard errors**.

---

## Types

| Type | Description |
|------|-------------|
| `!axi4.clock` | Clock domain handle |
| `!axi4.manager` | Manager endpoint handle |
| `!axi4.subordinate` | Subordinate endpoint handle |
| `!axi4.xbar` | Crossbar network handle |

---

## Clock Operators

### `axi4.clock`

Creates a primary clock domain.

**Syntax:**
```mlir
%clk = axi4.clock
%clk_with_freq = axi4.clock { freq = 500_000_000 }
```

**Results:** `!axi4.clock`

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `freq` | integer | — | Frequency in Hz |

**Notes:**
- Clock identity is determined solely by the SSA value
- Two `axi4.clock` ops are always distinct clocks (different SSA values)
- Clocks created by `axi4.clock` are independent (asynchronous to each other)

**Example:**
```mlir
%sys_clk = axi4.clock { freq = 500_000_000 }
%cpu_clk = axi4.clock { freq = 2_000_000_000 }
```

---

### `axi4.clock_div`

Creates a derived clock by dividing a parent clock.

**Syntax:**
```mlir
%slow_clk = axi4.clock_div %parent { divisor = 4 }
```

**Operands:** `(%parent: !axi4.clock)`

**Results:** `!axi4.clock`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `divisor` | integer | Clock division factor (≥1) |

**Notes:**
- The derived clock is synchronous to its parent (same source, known phase)
- CDC between parent and derived clock uses simple synchronizer + FIFO
- If parent has `freq`, derived clock has `freq / divisor`

**Example:**
```mlir
%sys_clk = axi4.clock { freq = 500_000_000 }
%periph_clk = axi4.clock_div %sys_clk { divisor = 5 }  // 100 MHz, synchronous to sys_clk
```

---

### `axi4.clock_related`

Creates a clock that is related to (but not derived from) another clock.

**Syntax:**
```mlir
%related_clk = axi4.clock_related %reference { relationship = "synchronous" }
%related_clk_freq = axi4.clock_related %reference { relationship = "mesochronous", freq = 100_000_000 }
```

**Operands:** `(%reference: !axi4.clock)`

**Results:** `!axi4.clock`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `relationship` | enum | `"synchronous"` or `"mesochronous"` |

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `freq` | integer | — | Frequency in Hz |

**Relationship types:**

| Value | Meaning | CDC Implementation |
|-------|---------|-------------------|
| `"synchronous"` | Same source, known phase relationship | Simple synchronizer + FIFO |
| `"mesochronous"` | Same frequency, unknown phase | Phase-tolerant FIFO |

**Notes:**
- Use for clocks from the same PLL but different outputs
- Use for clocks with known relationships that aren't simple divisions
- The relationship is with the reference clock and transitively with all clocks related to it

**Example:**
```mlir
%sys_clk = axi4.clock { freq = 500_000_000 }

// Different PLL output, but same PLL source
%periph_clk = axi4.clock_related %sys_clk { relationship = "synchronous", freq = 100_000_000 }

// Same frequency from different source, unknown phase
%external_clk = axi4.clock_related %sys_clk { relationship = "mesochronous", freq = 500_000_000 }
```

---

## Endpoint Operators

### `axi4.manager`

Declares a manager (initiator) endpoint.

**Syntax:**
```mlir
%mgr = axi4.manager(%clk : !axi4.clock) {
  access = [{ base = 0x0, size = 0x4000_0000 }],
  data_width = 64,
  external_id_width = 8,
  outstanding_reads = 8,
  outstanding_writes = 4,
  burst_capability = { incr = { max_len = 16 } }
}
```

**Operands:** `(%clk: !axi4.clock)`

**Results:** `!axi4.manager`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `access` | list of windows | Address windows the manager may access (non-empty) |
| `data_width` | integer | Data width in bits (32, 64, 128, 256, 512) |
| `outstanding_reads` | integer | Max read transactions in flight (≥1 if `read=true`, else 0) |
| `outstanding_writes` | integer | Max write transactions in flight (≥1 if `write=true`, else 0) |
| `burst_capability` | burst capability | Supported burst types and lengths |

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `sym_name` | string | — | Symbol name for cross-referencing |
| `read` | bool | `true` | Initiates read transactions |
| `write` | bool | `true` | Initiates write transactions |
| `exclusive` | bool | `false` | Issues exclusive accesses |
| `reorder_depth` | integer | `outstanding_reads` | Max read response reordering tolerance |
| `write_reorder_depth` | integer | `outstanding_writes` | Max write response reordering tolerance |
| `external_id_width` | integer | — | External AXI ID width in bits (must be ≥1 when present) |

**Constraints:**
- `access` must be non-empty
- All windows must satisfy: `size > 0`, `base + size` does not overflow
- At least one of `read` or `write` must be `true`
- If `read = true`: `outstanding_reads ≥ 1`, `reorder_depth` ∈ [1, `outstanding_reads`]
- If `write = true`: `outstanding_writes ≥ 1`, `write_reorder_depth` ∈ [1, `outstanding_writes`]

**Clock semantics:** The manager operates in the clock domain specified by the `%clk` operand. This clock must match the xbar's clock when binding (or be adapted via `axi4.cdc`).

---

### `axi4.subordinate`

Declares a subordinate (target) endpoint.

**Syntax:**
```mlir
%sub = axi4.subordinate(%clk : !axi4.clock) {
  window = { base = 0x0, size = 0x1_0000 },
  data_width = 64,
  external_id_width = 8,
  outstanding = 4,
  burst_capability = { incr = { max_len = 256 } }
}
```

**Operands:** `(%clk: !axi4.clock)`

**Results:** `!axi4.subordinate`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `window` | window | Address window served (single contiguous region) |
| `data_width` | integer | Data width in bits |
| `outstanding` | integer | Max total transactions target can accept (≥1) |
| `burst_capability` | burst capability | Supported burst types and lengths |

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `sym_name` | string | — | Symbol name for cross-referencing |
| `read` | bool | `true` | Accepts read transactions |
| `write` | bool | `true` | Accepts write transactions |
| `exclusive` | bool | `false` | Supports exclusive access |
| `reorders_reads` | bool | `false` | May return read responses out of order |
| `reorders_writes` | bool | `false` | May return write responses out of order |
| `external_id_width` | integer | — | External AXI ID width in bits (must be ≥1 when present) |

**Constraints:**
- `window` must satisfy: `size > 0`
- At least one of `read` or `write` must be `true`

---

## Network Operators

### `axi4.xbar`

Declares a crossbar network with explicit clock, manager, and target operands.

**Syntax:**
```mlir
%xbar = axi4.xbar(%clk : !axi4.clock,
                  managers = [%mgr1, %mgr2],
                  subordinates = [%sub1, %sub2, %sub3]) {
  addr_width = 32,
  data_width = 64
}
```

**Operands:**
- `%clk: !axi4.clock` — The crossbar's clock domain
- `managers: [!axi4.manager]` — List of manager endpoints (may be empty for subordinate-only xbars)
- `subordinates: [!axi4.subordinate]` — List of subordinate endpoints (may be empty for manager-only xbars)

**Results:** `!axi4.xbar`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `addr_width` | integer | Address width in bits (e.g., 32, 40, 48, 64) |
| `data_width` | integer | Network data width in bits |

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `sym_name` | string | — | Symbol name for cross-referencing |
| `default_error` | enum | — | `"decerr"` or `"slverr"` |
| `arb` | enum | `"rr"` | `"rr"`, `"wrr"`, `"priority"` |
| `txn_policy` | enum | `"expand"` | `"expand"`, `"serialize"`, `"pool"` |
| `pool_size` | integer | — | Required when `txn_policy = "pool"` |
| `capacity_check` | enum | `"warn"` | `"warn"` or `"error"` |
| `exclusive_mode` | enum | `"strict"` | `"strict"` or `"advisory"` |
| `qos_mode` | enum | `"passthrough"` | `"passthrough"`, `"fixed"`, `"remap"` |
| `manager_attrs` | list | — | Per-manager binding attributes |
| `subordinate_attrs` | list | — | Per-subordinate binding attributes |

**Binding constraints:**
- All managers must have `data_width` equal to the xbar's `data_width`
- All managers must have the same clock as the xbar (SSA value equality)
- All subordinates must have `data_width` equal to the xbar's `data_width`
- All subordinates must have the same clock as the xbar (SSA value equality)
- Subordinate windows must be disjoint within the xbar

**Per-endpoint attributes:**

The `manager_attrs` and `subordinate_attrs` lists provide per-endpoint configuration, with indices corresponding to the operand lists:

```mlir
%xbar = axi4.xbar(%clk,
                  managers = [%cpu, %dma],
                  subordinates = [%sram, %dram]) {
  addr_width = 32,
  data_width = 64,
  arb = "wrr",
  manager_attrs = [
    { arb_weight = 4 },  // %cpu
    { arb_weight = 1 }   // %dma
  ],
  subordinate_attrs = [
    { },                 // %sram: defaults
    { }                  // %dram
  ]
}
```

**Manager binding attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `arb_weight` | integer | 1 | Arbitration weight (for `arb = "wrr"`) |
| `arb_priority` | integer | 0 | Priority level (for `arb = "priority"`) |
| `access_enforcement` | enum | `"none"` | `"none"` or `"filter"` |
| `qos_value` | integer | — | Fixed QoS value (for `qos_mode = "fixed"`) |
| `qos_remap` | list | — | QoS remapping table (for `qos_mode = "remap"`) |

**Subordinate binding attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|

**Default error handling:** When `default_error` is specified, addresses not covered by any subordinate receive the specified error response. When omitted, full coverage is required.

**Arbitration (`arb`):**

| Value | Behavior |
|-------|----------|
| `"rr"` | Round-robin among ready managers |
| `"wrr"` | Weighted round-robin using `arb_weight` |
| `"priority"` | Fixed priority using `arb_priority` (higher = more priority) |

**Transaction policy (`txn_policy`):**

| Value | Behavior | Capacity Bound |
|-------|----------|----------------|
| `"expand"` | Each manager gets independent ID space | `S.outstanding ≥ Σ(reachable M.outstanding)` |
| `"serialize"` | At most one manager active per subordinate | `S.outstanding ≥ max(reachable M.outstanding)` |
| `"pool"` | Shared ID pool of size `pool_size` | `S.outstanding ≥ pool_size` |

**Exclusive mode:**

| Value | Behavior |
|-------|----------|
| `"strict"` | Exclusive violations are hard errors |
| `"advisory"` | Exclusive failures permitted (EXOKAY=0) |

---

## Bridge Operators

### `axi4.bridge`

Creates a bidirectional connection between two crossbars.

**Syntax:**
```mlir
axi4.bridge %upstream, %downstream {
  upstream_window = { base = 0x4000_0000, size = 0x10_0000 },
  downstream_base = 0x0,
  outstanding = 8
}
```

**Operands:** `(%upstream: !axi4.xbar, %downstream: !axi4.xbar)`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `upstream_window` | window | Address range in upstream that routes to downstream |
| `downstream_base` | integer | Base address in downstream's address space |

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `sym_name` | string | — | Symbol name |
| `outstanding` | integer | 16 | Bridge transaction capacity |
| `burst_capability` | burst capability | (auto) | Bridge burst support |
| `exclusive` | enum | `"block"` | `"block"`, `"passthrough"`, `"terminate"` |
| `cdc_depth` | integer | 4 | CDC FIFO depth (if clocks differ) |

**Implicit adaptation:**

The bridge automatically handles clock and width differences between the two xbars:

| Condition | Bridge Behavior |
|-----------|-----------------|
| Same clock (SSA equality) | No CDC logic |
| Related clocks (via `clock_div` or `clock_related`) | Synchronous/mesochronous CDC |
| Unrelated clocks | Asynchronous CDC |
| Same data width | No width conversion |
| Different data widths | Width conversion |

**Address translation:** `downstream_addr = upstream_addr - upstream_window.base + downstream_base`

## Adapter Operators

Adapters transform endpoint characteristics before binding to an xbar.
Canonical adapter order is `axi4.resizer` → `axi4.burst_splitter` → `axi4.cdc`
and is enforced by `canonicalize-axi4-adapters`. When reordering around a
resizer, the pass scales `burst_splitter` capabilities to preserve effective
burst lengths.

### `axi4.cdc`

Clock domain crossing adapter.

**Syntax:**
```mlir
%crossed = axi4.cdc %endpoint, %target_clk : !axi4.manager
```

**Operands:**
- `%endpoint: !axi4.manager` or `!axi4.subordinate`
- `%target_clk: !axi4.clock`

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `depth` | integer | 4 | FIFO depth per channel |
| `mode` | enum | (auto) | `"async"`, `"sync"`, `"handshake"` |

**Results:** Same type as input endpoint, now in `%target_clk` domain.

**Mode selection:** If `mode` is omitted:
- Same clock SSA value → **error** (CDC not needed)
- Related clocks (via `clock_div` or `clock_related`) → `"sync"` or `"meso"` based on relationship
- Unrelated clocks → `"async"`

**Example:**
```mlir
%sys_clk = axi4.clock { name = "sys_clk" }
%cpu_clk = axi4.clock { name = "cpu_clk" }

%cpu_raw = axi4.manager(%cpu_clk) { ... }
%cpu = axi4.cdc %cpu_raw, %sys_clk : !axi4.manager

// Now %cpu can be bound to an xbar using %sys_clk
```

---

### `axi4.resizer`

Width conversion adapter.

**Syntax:**
```mlir
%resized = axi4.resizer %endpoint { target_width = 32 } : !axi4.manager
```

**Operands:** `%endpoint: !axi4.manager` or `!axi4.subordinate`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `target_width` | integer | Output data width (power of 2) |

**Results:** Same type with modified `data_width` and adjusted `burst_capability`.
Burst lengths are scaled by the width ratio (e.g. 128→64 doubles max lengths).

---

### `axi4.burst_splitter`

Splits long bursts into shorter bursts.

**Syntax:**
```mlir
%split = axi4.burst_splitter %mgr {
  burst_capability = { incr = { max_len = 16 } }
} : !axi4.manager -> !axi4.manager
```

**Operands:** `%mgr: !axi4.manager`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `burst_capability` | burst capability | Maximum output burst capability |

**Results:** `!axi4.manager` with reduced burst capability.

---

### `axi4.exclusive_monitor`

Wraps a subordinate with exclusive access support.

**Syntax:**
```mlir
%excl = axi4.exclusive_monitor %sub {
  granularity = 64,
  entries = 8
} : !axi4.subordinate -> !axi4.subordinate
```

**Operands:** `%sub: !axi4.subordinate`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `granularity` | integer | Monitor granularity in bytes |
| `entries` | integer | Number of monitored slots |

**Results:** `!axi4.subordinate` with `exclusive = true`.

---

### `axi4.alias`

Declares an additional address window that maps to the same subordinate target.
This makes intentional aliasing explicit and allows overlapping windows only
when they are declared as aliases. If a subordinate is reachable at multiple
disjoint address ranges (e.g. through multiple bridges), those extra ranges
must be represented with `axi4.alias` or the network verification will fail.
Aliases must appear on the same xbar as their base subordinate.

**Syntax:**
```mlir
%alias = axi4.alias %sub {
  window = { base = 0x1600_0000, size = 0x0000_1000 }
}
```

**Operands:** `(%sub: !axi4.subordinate)`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `window` | window | Alias address window |

**Results:** `!axi4.subordinate`

---

### `axi4.error_subordinate`

Creates a synthetic error-responding subordinate.

**Syntax:**
```mlir
%err = axi4.error_subordinate(%clk : !axi4.clock) {
  window = { base = 0xFFFF_0000, size = 0x1_0000 },
  data_width = 64
}
```

**Operands:** `%clk: !axi4.clock`

**Required attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `window` | window | Address window to cover |
| `data_width` | integer | Must match network |

**Optional attributes:**
| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `response` | enum | `"decerr"` | `"decerr"` or `"slverr"` |
| `outstanding` | integer | (auto) | Transaction capacity |

**Results:** `!axi4.subordinate`

---

## Verification

### Pass Structure

1. **Structural validation:** Attribute validity, window constraints
2. **Clock matching:** Verify all endpoints use xbar's clock
3. **Width matching:** Verify all endpoints match xbar's data_width
4. **Window disjointness:** Check subordinate windows don't overlap
5. **Coverage:** Check manager access ranges are covered
6. **Reachability:** Compute (manager, target) pairs including bridges
7. **Burst compatibility:** Check per-type burst constraints
8. **Reorder compatibility:** Check reorder_depth vs subordinate behavior
9. **Exclusive compatibility:** Check exclusive paths
10. **Capacity:** Check transaction capacity

### Hard Errors

- Endpoint clock ≠ xbar clock (SSA value mismatch)
- Endpoint data_width ≠ xbar data_width
- Window `size = 0` or overflow
- Subordinate windows overlap within xbar
- Manager access uncovered without `default_error`
- Burst incompatibility
- Exclusive path violation (strict mode)
- `txn_policy = "pool"` without `pool_size`
- CDC between same clock (SSA equality)

### Warnings

- Subordinate unreachable by any manager
- Capacity insufficient (unless `capacity_check = "error"`)
- Unusual window alignment

---

## Diagnostic Format

```
error: axi4.xbar 'main_bus': clock domain mismatch
  note: manager %cpu uses clock %cpu_clk at example.mlir:15:3
  note: xbar uses clock %sys_clk at example.mlir:50:3
  help: insert axi4.cdc adapter: %cpu_adapted = axi4.cdc %cpu, %sys_clk

error: axi4.xbar 'main_bus': burst incompatibility
  note: manager %cpu has incr.max_len=256
  note: subordinate %uart has incr.max_len=1
  help: insert axi4.burst_splitter on manager
```

---

## Complete Example

```mlir
module @soc {
  // ═══════════════════════════════════════════════════════════════════
  // Clock Domains
  // ═══════════════════════════════════════════════════════════════════
  
  %cpu_clk = axi4.clock { freq = 2_000_000_000 }
  %sys_clk = axi4.clock { freq = 500_000_000 }
  
  // periph_clk is derived from sys_clk's PLL (synchronous relationship)
  %periph_clk = axi4.clock_div %sys_clk { divisor = 5 }  // 100 MHz

  // ═══════════════════════════════════════════════════════════════════
  // Endpoints (in their native clock domains)
  // ═══════════════════════════════════════════════════════════════════

  %cpu_raw = axi4.manager(%cpu_clk) {
    sym_name = "cpu",
    access = [{ base = 0x0, size = 0x4000_0000 }],
    data_width = 64,
    outstanding_reads = 8,
    outstanding_writes = 4,
    reorder_depth = 8,
    write_reorder_depth = 4,
    burst_capability = {
      incr = { max_len = 16 },
      wrap = { lengths = [4, 8] }
    },
    exclusive = true
  }

  %dma_raw = axi4.manager(%sys_clk) {
    sym_name = "dma",
    access = [{ base = 0x0, size = 0x2000_0000 }],
    data_width = 128,
    outstanding_reads = 16,
    outstanding_writes = 16,
    reorder_depth = 1,
    write_reorder_depth = 1,
    burst_capability = { incr = { max_len = 256 } },
    exclusive = false
  }

  %sram = axi4.subordinate(%sys_clk) {
    sym_name = "sram",
    window = { base = 0x0000_0000, size = 0x0001_0000 },
    data_width = 64,
    outstanding = 4,
    reorders_reads = false,
    reorders_writes = false,
    burst_capability = {
      incr = { max_len = 256 },
      fixed = { max_len = 16 },
      wrap = { lengths = [2, 4, 8, 16] }
    },
    exclusive = true
  }

  %dram_raw = axi4.subordinate(%sys_clk) {
    sym_name = "dram_ctrl",
    window = { base = 0x1000_0000, size = 0x1000_0000 },
    data_width = 64,
    outstanding = 64,
    reorders_reads = true,
    reorders_writes = false,
    burst_capability = {
      incr = { max_len = 256 },
      wrap = { lengths = [4, 8, 16] }
    },
    exclusive = false
  }

  // Add exclusive monitor to DRAM
  %dram = axi4.exclusive_monitor %dram_raw {
    granularity = 64,
    entries = 8
  } : !axi4.subordinate -> !axi4.subordinate

  %uart = axi4.subordinate(%sys_clk) {
    sym_name = "uart",
    window = { base = 0x2000_0000, size = 0x0000_1000 },
    data_width = 64,
    outstanding = 1,
    burst_capability = { incr = { max_len = 1 } }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Adapters
  // ═══════════════════════════════════════════════════════════════════

  // CPU: CDC from cpu_clk to sys_clk
  %cpu = axi4.cdc %cpu_raw, %sys_clk { depth = 8 } 
       : !axi4.manager

  // DMA: Width conversion (128b → 64b)
  %dma_narrow = axi4.resizer %dma_raw { target_width = 64 } : !axi4.manager

  // ═══════════════════════════════════════════════════════════════════
  // Main Bus
  // ═══════════════════════════════════════════════════════════════════

  %main_bus = axi4.xbar(%sys_clk,
                        managers = [%cpu, %dma],
                        subordinates = [%sram, %dram, %uart]) {
    sym_name = "main_bus",
    addr_width = 32,
    data_width = 64,
    default_error = "decerr",
    arb = "wrr",
    txn_policy = "expand",
    capacity_check = "warn",
    exclusive_mode = "strict",
    manager_attrs = [
      { arb_weight = 4 },  // cpu
      { arb_weight = 1 }   // dma
    ]
  }

  // ═══════════════════════════════════════════════════════════════════
  // Peripheral Bus
  // ═══════════════════════════════════════════════════════════════════

  %gpio = axi4.subordinate(%periph_clk) {
    sym_name = "gpio",
    window = { base = 0x0, size = 0x100 },
    data_width = 32,
    outstanding = 1,
    burst_capability = { incr = { max_len = 1 } }
  }

  %timer = axi4.subordinate(%periph_clk) {
    sym_name = "timer",
    window = { base = 0x1000, size = 0x100 },
    data_width = 32,
    outstanding = 1,
    burst_capability = { incr = { max_len = 1 } }
  }

  %periph_bus = axi4.xbar(%periph_clk,
                          managers = [],  // No direct managers; fed via bridge
                          subordinates = [%gpio, %timer]) {
    sym_name = "periph_bus",
    addr_width = 20,
    data_width = 32,
    default_error = "slverr",
    txn_policy = "pool",
    pool_size = 4,
    exclusive_mode = "advisory"
  }

  // ═══════════════════════════════════════════════════════════════════
  // Bridge: Main Bus → Peripheral Bus
  // ═══════════════════════════════════════════════════════════════════

  axi4.bridge %main_bus, %periph_bus {
    sym_name = "periph_bridge",
    upstream_window = { base = 0x3000_0000, size = 0x0010_0000 },
    downstream_base = 0x0,
    outstanding = 4,
    burst_capability = { incr = { max_len = 4 } },
    exclusive = "block",
    cdc_depth = 4
  }
  // Bridge automatically handles:
  // - Synchronous CDC (sys_clk → periph_clk, related)
  // - Width downsizing (64b → 32b)
}
```

---

## Lowering Contract

| Dialect Concept | RTL Requirement |
|-----------------|-----------------|
| `axi4.clock` | Primary clock port/net |
| `axi4.clock_div` | Derived clock with division |
| `axi4.clock_related` | Related clock, CDC selection |
| `axi4.manager`/`axi4.subordinate` | AXI port bundle |
| `axi4.xbar` | Crossbar RTL with specified policies |
| `axi4.cdc` | CDC FIFO instantiation |
| `axi4.bridge` | Bridge module with internal adaptation |
| `outstanding_*` | Tracking structures |
| `reorder_depth` | ID allocation strategy |
| `burst_capability` | Burst handling logic |

---

## Future Extensions

- `axi4.firewall` — address/permission filtering
- `axi4.qos_shaper` — bandwidth limiting
- `axi4.buffer` — explicit transaction buffering
- AXI4-Lite protocol variant
- AXI5 features: atomics, cache stash, MPAM
- Formal verification integration
- Power domain modeling
