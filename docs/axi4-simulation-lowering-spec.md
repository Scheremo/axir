# AXI4 Simulation Lowering Specification

This document specifies the SystemVerilog simulation lowering for the AXI4
MLIR dialect. Unless explicitly overridden here, all semantics MUST follow
`include/axi4/INTENT.md`.

## Scope and Goals

- Preserve AXI4 protocol semantics (ordering, routing, bursts, errors).
- Preserve network semantics (routing, bridges, aliasing, coverage).
- Provide deterministic, debuggable behavior.
- Transaction-level modeling internally with cycle-accurate boundaries.

## Minimal Starter Subset (Normative)

The first implementation MUST support the following minimal subset.

### Supported Operations

- `axi4.clock`
- `axi4.manager`
- `axi4.subordinate`
- `axi4.xbar`

### Allowed Xbar Configuration

- `txn_policy` MUST be `#axi4.txn_policy<expand>`
- `arb` MUST be `#axi4.arb<rr>` (round-robin)
- `default_error` MAY be set
- `capacity_check` MAY be set

### Disallowed Features

- Exclusive access flags on endpoints MUST NOT be set
- `axi4.exclusive_monitor` MUST NOT be used
- `axi4.bridge` MUST NOT be used
- `axi4.alias` MUST NOT be used
- `axi4.resizer` MUST NOT be used
- `axi4.burst_splitter` MUST NOT be used
- `axi4.cdc` MUST NOT be used
- Any arbitration policy other than round-robin MUST NOT be used
- Transaction policies other than `expand` MUST NOT be used

### Lowering-Time Validation (Normative)

The lowering pass MUST emit a hard error if any of the following conditions
are detected:

1. Any disallowed operation is present in the IR.
2. Any disallowed attribute value is present (e.g., `arb = "wrr"`).
3. Any manager or subordinate bound to an xbar has a clock operand that
   differs from the xbar's clock operand (SSA value mismatch).
4. Any endpoint has `exclusive = true`.
5. Any subordinate is bound to more than one xbar.

Examples:
- `axi4.xbar { arb = "wrr" }` → lowering fails with error.
- `axi4.bridge` op present → lowering fails with error.
- Manager uses `%cpu_clk`, xbar uses `%sys_clk` → lowering fails with error.
- Subordinate `%sram` appears in two xbars → lowering fails with error.

### Assumptions

- All address windows are aligned and non-overlapping.
- Width and burst compatibility are enforced by verification passes.
- All endpoints bound to an xbar share the xbar's clock domain.
- Each subordinate is bound to exactly one xbar (minimal subset constraint).

### Minimal Simulation Requirements

- Basic routing through xbars
- Coverage checks for `default_error`
- Deterministic round-robin arbitration
- Multiple xbars MAY exist; each forms an independent fabric instance in the
  generated model unless connected by bridges (future expansion).

### Future Expansions (Out of Scope for Minimal Subset)

Adapters:
- `axi4.resizer`
- `axi4.burst_splitter`
- `axi4.cdc`
- `axi4.exclusive_monitor`

Topology:
- `axi4.bridge`
- `axi4.alias`

---

## Output Artifacts

The lowering MUST emit:

- **One top-level SystemVerilog module** with ports for every clock, manager,
  and subordinate.
- **One SystemVerilog package (`axi_pkg`)** containing all type definitions
  and configuration constants.

### Package Contents (`axi_pkg`)

The generated package MUST contain:

```systemverilog
package axi_pkg;
  // ═══════════════════════════════════════════════════════════════════
  // Internal Width Parameters (Implementation Maximums)
  // ═══════════════════════════════════════════════════════════════════
  //
  // These define the maximum widths for internal transaction metadata.
  // They MUST be >= the corresponding boundary widths for all endpoints.
  // Boundary-to-internal mapping zero-extends; internal-to-boundary
  // truncates to the configured endpoint width. Truncation is permitted
  // only for fields that were originally sourced from that endpoint
  // (e.g., ID, user), not for internally-synthesized routing state.
  
  parameter int unsigned INTERNAL_ID_WIDTH   = 16;  // Must be >= max endpoint ID width
  parameter int unsigned INTERNAL_ADDR_WIDTH = 64;  // Must be >= max xbar addr_width
  parameter int unsigned INTERNAL_USER_WIDTH = 16;  // Must be >= max endpoint user width

  // ═══════════════════════════════════════════════════════════════════
  // Configuration Constants
  // ═══════════════════════════════════════════════════════════════════
  
  parameter int unsigned NUM_CLKS  = /* from IR */;
  parameter int unsigned NUM_MGRS  = /* from IR */;
  parameter int unsigned NUM_SUBS  = /* from IR */;
  parameter int unsigned NUM_XBARS = /* from IR */;
  
  // Derived: manager index width for tag encoding (minimum 1)
  parameter int unsigned MGR_IDX_WIDTH = (NUM_MGRS > 1) ? $clog2(NUM_MGRS) : 1;
  
  // Per-xbar configuration (indexed by xbar)
  parameter int unsigned XBAR_ADDR_WIDTH[NUM_XBARS] = '{ /* ... */ };
  parameter int unsigned XBAR_DATA_WIDTH[NUM_XBARS] = '{ /* ... */ };
  
  // Per-xbar endpoint lists (global indices of bound endpoints)
  // These define which managers/subordinates participate in each xbar
  parameter int unsigned XBAR_NUM_MGRS[NUM_XBARS] = '{ /* ... */ };
  parameter int unsigned XBAR_NUM_SUBS[NUM_XBARS] = '{ /* ... */ };
  parameter int unsigned XBAR_MGR_INDICES[NUM_XBARS][/* max mgrs */] = '{ /* ... */ };
  parameter int unsigned XBAR_SUB_INDICES[NUM_XBARS][/* max subs */] = '{ /* ... */ };
  
  // Per-manager configuration (indexed by global manager index)
  parameter int unsigned MGR_DATA_WIDTH[NUM_MGRS]     = '{ /* ... */ };
  parameter int unsigned MGR_ID_WIDTH[NUM_MGRS]       = '{ /* ... */ };
  parameter int unsigned MGR_OUTSTANDING_RD[NUM_MGRS] = '{ /* ... */ };
  parameter int unsigned MGR_OUTSTANDING_WR[NUM_MGRS] = '{ /* ... */ };
  parameter int unsigned MGR_REORDER_DEPTH[NUM_MGRS]  = '{ /* ... */ };
  
  // Per-subordinate configuration (indexed by global subordinate index)
  parameter int unsigned SUB_DATA_WIDTH[NUM_SUBS]     = '{ /* ... */ };
  parameter int unsigned SUB_ID_WIDTH[NUM_SUBS]       = '{ /* ... */ };
  parameter int unsigned SUB_OUTSTANDING[NUM_SUBS]    = '{ /* ... */ };
  parameter logic [63:0] SUB_WINDOW_BASE[NUM_SUBS]    = '{ /* ... */ };
  parameter logic [63:0] SUB_WINDOW_SIZE[NUM_SUBS]    = '{ /* ... */ };
  parameter bit          SUB_REORDERS_READS[NUM_SUBS] = '{ /* ... */ };
  parameter bit          SUB_REORDERS_WRITES[NUM_SUBS]= '{ /* ... */ };

  // ═══════════════════════════════════════════════════════════════════
  // AXI Response Codes
  // ═══════════════════════════════════════════════════════════════════
  
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

  // ═══════════════════════════════════════════════════════════════════
  // PULP AXI Struct Typedefs (parameterized per-endpoint)
  // ═══════════════════════════════════════════════════════════════════
  
  // ... PULP axi_req_t / axi_resp_t definitions ...
  // These are parameterized by ID_WIDTH, ADDR_WIDTH, DATA_WIDTH, USER_WIDTH
  // and instantiated per-endpoint at the boundary.

  // ═══════════════════════════════════════════════════════════════════
  // Internal Transaction Type
  // ═══════════════════════════════════════════════════════════════════
  
  typedef struct packed {
    // Transaction type
    logic        is_write;
    
    // Address and size
    logic [INTERNAL_ADDR_WIDTH-1:0] addr;
    logic [2:0]  size;       // Encoded: 2^size = beat bytes
    logic [7:0]  len;        // AXI ARLEN/AWLEN (beats - 1)
    logic [1:0]  burst;      // INCR=01, WRAP=10, FIXED=00
    
    // ID and routing
    logic [INTERNAL_ID_WIDTH-1:0] id;  // Original AXI ID (zero-extended from boundary)
    logic [MGR_IDX_WIDTH-1:0] mgr_idx; // Source manager index (global)
    logic [47:0] tag;                  // Routing tag (see Tag Encoding)
    
    // Sideband
    logic [3:0]  qos;
    logic [3:0]  region;
    logic [3:0]  cache;
    logic [2:0]  prot;
    logic        lock;
    logic [INTERNAL_USER_WIDTH-1:0] user;  // Zero-extended from boundary
    
    // Response (populated on completion)
    axi_resp_e   resp;
    
    // Payload (dynamically sized in class representation)
    // For struct representation, use maximum supported size
  } axi_txn_meta_t;
  
  class axi_txn_t;
    axi_txn_meta_t meta;
    logic [7:0]    data[];    // Byte array: length = (len+1) * (2^size)
    logic          strb[][];  // Strobe bits: [beat][byte_lane]
    
    function int beat_bytes();
      return 1 << meta.size;
    endfunction
    
    function int num_beats();
      return meta.len + 1;
    endfunction
  endclass

endpackage
```

### Field Width Mapping (Normative)

When mapping between boundary PULP structs and internal `axi_txn_meta_t`:

| Direction | Mapping Rule |
|-----------|--------------|
| Boundary → Internal | Zero-extend narrower fields to internal width |
| Internal → Boundary | Truncate to boundary width |

The lowering MUST verify that `INTERNAL_*_WIDTH >= max(endpoint widths)` for
all endpoints. Failure to satisfy this is a lowering-time error.

### Top-Level Module Interface (Normative)

The top-level module MUST use arrayed ports and preserve MLIR/IR definition
order for managers and subordinates.

```systemverilog
module axi_sim_top
  import axi_pkg::*;
#(
  parameter int unsigned NUM_CLKS = axi_pkg::NUM_CLKS,
  parameter int unsigned NUM_MGRS = axi_pkg::NUM_MGRS,
  parameter int unsigned NUM_SUBS = axi_pkg::NUM_SUBS
) (
  // Clocks (active-high, directly driven by testbench)
  input  logic clk [NUM_CLKS],

  // Managers: external world drives req, receives resp
  input  axi_req_t  mgr_req  [NUM_MGRS],
  output axi_resp_t mgr_resp [NUM_MGRS],

  // Subordinates: model drives req, external world returns resp
  output axi_req_t  sub_req  [NUM_SUBS],
  input  axi_resp_t sub_resp [NUM_SUBS]
);
  // Internal implementation...
endmodule
```

### Index Mapping (Normative)

**Global indices** are used for top-level port arrays and `axi_pkg` parameter
arrays. They follow textual order in the post-canonicalization MLIR module:

- Global manager index: position of `axi4.manager` op in module
- Global subordinate index: position of `axi4.subordinate` op in module

**Local indices** are used within each xbar for arbitration state:

- Local manager index: position within `XBAR_MGR_INDICES[xbar_idx]`
- Local subordinate index: position within `XBAR_SUB_INDICES[xbar_idx]`

Conversion functions:
```systemverilog
// Global → Local (returns -1 if not bound to this xbar)
function int global_to_local_mgr(int xbar_idx, int global_mgr_idx);
  for (int i = 0; i < XBAR_NUM_MGRS[xbar_idx]; i++)
    if (XBAR_MGR_INDICES[xbar_idx][i] == global_mgr_idx) return i;
  return -1;
endfunction

// Local → Global
function int local_to_global_mgr(int xbar_idx, int local_mgr_idx);
  return XBAR_MGR_INDICES[xbar_idx][local_mgr_idx];
endfunction

// Similarly for subordinates...
```

---

## PULP AXI Struct Integration (External I/O)

At the boundary of the simulation model, manager and subordinate ports MUST
use PULP AXI request/response structs (`axi_req_t` / `axi_resp_t`).

### Boundary Direction (Normative)

- **Manager port**: The external world (testbench/DUT) drives `mgr_req`
  (AR/AW/W channels). The model drives `mgr_resp` (R/B channels).
- **Subordinate port**: The model drives `sub_req` (AR/AW/W channels).
  The external world drives `sub_resp` (R/B channels).

### Boundary Adapters (Normative)

The lowering MUST instantiate boundary adapters that translate between
cycle-level handshakes and transaction-level internal representation.

#### Manager Boundary: `axi_mgr_boundary`

```
┌─────────────────────────────────────────────────────────────┐
│                    axi_mgr_boundary                         │
│                                                             │
│  mgr_req ──►  [signal_to_txn] ──► txn_out ──► (to xbar)    │
│                                                             │
│  mgr_resp ◄── [txn_to_signal] ◄── txn_in  ◄── (from xbar)  │
└─────────────────────────────────────────────────────────────┘
```

#### Subordinate Boundary: `axi_sub_boundary`

```
┌─────────────────────────────────────────────────────────────┐
│                    axi_sub_boundary                         │
│                                                             │
│  sub_req ◄──  [txn_to_signal] ◄── txn_in  ◄── (from xbar)  │
│                                                             │
│  sub_resp ──► [signal_to_txn] ──► txn_out ──► (to xbar)    │
└─────────────────────────────────────────────────────────────┘
```

---

## Write Transaction Collection (Normative)

The `signal_to_txn` component at manager boundaries MUST handle AXI4 write
transactions where W beats may arrive before, after, or interleaved with
the AW beat.

### Collection Strategy: AW-Gated with Back-Pressure

The minimal subset uses a simplified collection strategy that applies
back-pressure to W beats until the corresponding AW is received:

1. **AW acceptance:** AWREADY is asserted when fewer than `outstanding_writes`
   AW requests are buffered. Accepted AWs are pushed to an AW FIFO.

2. **W collection:** WREADY is asserted only when:
   - The AW FIFO is non-empty, AND
   - We are collecting W beats for the **head** of the AW FIFO

3. **One write burst at a time:** Only one write burst's W beats are collected
   at a time (the head of the AW FIFO). W beats for subsequent AWs are blocked
   until the current burst completes (WLAST).

4. **A write transaction is complete when:**
   - The AW beat has been received (head of AW FIFO), AND
   - All W beats have been received (WLAST seen)

5. **Ordering guarantee:** Complete transactions are emitted in AW order.

This strategy is simpler than full W-before-AW buffering and is permitted
because the model applies back-pressure (WREADY=0) rather than dropping or
misrouting early W beats. It also avoids any W interleaving complexity
(which AXI4 prohibits across different transactions anyway).

### Collection State Machine

```
                    ┌──────────────┐
         ───────────│     IDLE     │◄────────────────┐
        │           │ (AWREADY=1   │                 │
        │           │  if < limit) │                 │
        │           └──────┬───────┘                 │
        │                  │ AW accepted             │
        │                  │ (push to AW FIFO)       │
        │                  ▼                         │
        │           ┌──────────────┐                 │
        │           │   AW_QUEUED  │◄────────┐       │
        │           │ (WREADY=1 if │         │       │
        │           │  this is head)         │       │
        │           └──────┬───────┘         │       │
        │                  │ W beat accepted │       │
        │                  │ (for head AW)   │       │
        │                  ▼                 │       │
        │           ┌──────────────┐         │       │
        │           │  COLLECTING  │─────────┘       │
        │           │   W BEATS    │ W beat (not last)
        │           └──────┬───────┘                 │
        │                  │ WLAST accepted          │
        │                  ▼                         │
        │           ┌──────────────┐                 │
        └───────────│   COMPLETE   │─────────────────┘
                    │ (emit txn,   │
                    │  pop AW FIFO)│
                    └──────────────┘
```

### Buffer Limits

The collector MUST accept up to `outstanding_writes` AW requests into the AW
FIFO. Back-pressure is applied via AWREADY when this limit is reached.

W beats are collected only for the head of the AW FIFO, ensuring at most one
write burst's W collection is active at any time.

### Alternative Strategy (Future Expansion)

Full W-before-AW support would require:
- Separate AW queue and W data buffer
- Correlation logic to match W bursts to AW by order (AXI4) or WID (AXI3)
- Additional buffering for out-of-order arrival

This is out of scope for the minimal subset.

---

## Response Ordering and Reordering (Normative)

### Subordinate Reordering Behavior

Subordinates declare their reordering behavior via `reorders_reads` and
`reorders_writes` attributes:

| Attribute | Meaning |
|-----------|---------|
| `reorders_reads = false` | Responses return in request order per ID |
| `reorders_reads = true` | Responses may return out of order within ID |
| `reorders_writes = false` | B responses return in request order per ID |
| `reorders_writes = true` | B responses may return out of order within ID |

### Manager Reorder Tolerance

Managers declare their tolerance for reordering via `reorder_depth` (reads)
and `write_reorder_depth` (writes):

- `reorder_depth = 1`: Manager expects strictly in-order responses per ID
- `reorder_depth = N`: Manager tolerates up to N responses out of order per ID

### Enforcement (Normative)

The simulation model MUST enforce reorder depth limits at the manager boundary:

1. **Tracking:** For each `(manager, channel, id)`, maintain a sequence number
   for requests and track which sequence numbers have received responses.

2. **Violation detection:** If a response arrives for sequence number S, and
   there exist more than `reorder_depth - 1` earlier sequence numbers without
   responses, this is a violation.

3. **Violation handling:** On violation, the model MUST emit a diagnostic:
   ```
   ERROR: Reorder depth exceeded for manager %d, channel %s, id %d
          Expected seq <= %d, got seq %d (depth=%d, tolerance=%d)
   ```
   The simulation MAY continue (warning mode) or terminate (error mode),
   controlled by a runtime configuration flag.

### Violation Interpretation

The meaning of a reorder violation depends on the IR annotations:

| IR Says | External Behavior | Interpretation |
|---------|-------------------|----------------|
| `reorders_reads = false` | Subordinate reordered | External model/DUT bug or IR annotation is wrong |
| `reorders_reads = true`, small `reorder_depth` | Reordering exceeded tolerance | Ideally caught by verifier; runtime violation indicates invalid IR or incompatible path |

In both cases, the simulation flags the violation. Root cause analysis is
left to the user.

### Interaction with `expand` Policy

Under `txn_policy = expand`, responses are routed back to the originating
manager using the `tag` field. Reorder checking occurs after routing, at
the manager boundary, using the original AXI ID.

---

## Internal Transaction Model (Normative)

### Tag Encoding (Normative)

The `axi_txn_meta_t.tag` field MUST encode sufficient information to route
responses back to the originating manager. Under `txn_policy = expand`:

```
tag[47:0] encoding (MGR_IDX_WIDTH = $clog2(NUM_MGRS), minimum 1):
  [MGR_IDX_WIDTH-1 : 0]  : Manager index (global)
  [MGR_IDX_WIDTH]        : Is write (0=read, 1=write)
  [MGR_IDX_WIDTH+15 : MGR_IDX_WIDTH+1] : Sequence number (15 bits)
  [47 : MGR_IDX_WIDTH+16] : Reserved (must be zero)
```

**Sequence number wrap:** Sequence numbers are 15 bits (values 0 to 32767).
Reorder checking uses **modular arithmetic** with a sliding window:

- When assigning: `next_seq[is_write][id] = (next_seq[is_write][id] + 1) % 32768`
- When checking: a response with sequence S is valid if S falls within the
  window `[oldest_pending, oldest_pending + reorder_depth)` modulo 32768,
  where `oldest_pending` is the minimum sequence number among pending requests
  for that (manager, channel, id).

Lowering MUST ensure `max(reorder_depth_rd, reorder_depth_wr) <= 2^15` for all
managers. This guarantees the sliding window never spans more than half the
sequence space, making modular comparison unambiguous.

**Authority rules:**
- The authoritative original AXI ID is `meta.id`.
- The authoritative manager index for routing is `meta.mgr_idx`.
- `tag[MGR_IDX_WIDTH-1:0]` MUST equal `meta.mgr_idx` for all transactions.
- The tag is a packed encoding of routing fields; `meta.mgr_idx` is the
  canonical source when unpacking.

The xbar extracts `tag[MGR_IDX_WIDTH-1:0]` to route responses to the correct
manager. The manager boundary uses `meta.id` to restore the AXI ID on the
response, and the sequence number field for reorder checking.

### Address Width Handling (Normative)

The lowering MUST mask addresses according to the relevant xbar's `addr_width`
at decode time. The masking MUST handle all valid `addr_width` values (1-64):

```systemverilog
function logic [63:0] mask_addr(logic [63:0] addr, int unsigned addr_width);
  if (addr_width >= 64)
    return addr;  // No masking needed
  else
    return addr & ((64'h1 << addr_width) - 64'h1);
endfunction
```

Note: The explicit `64'h1` ensures proper width for the shift operation,
avoiding undefined behavior when `addr_width` approaches 64.

Decode comparisons MUST use masked addresses and MUST match the dialect
verifier's `base + size <= 2^addr_width` rules.

### Response Codes

The `axi_txn_meta_t.resp` field uses AXI response encoding:

| Code | Value | Meaning |
|------|-------|---------|
| OKAY | 2'b00 | Normal successful completion |
| EXOKAY | 2'b01 | Exclusive access success (not used in minimal subset) |
| SLVERR | 2'b10 | Subordinate error |
| DECERR | 2'b11 | Decode error (unmapped address) |

### Response Payload Semantics (Normative)

- **Reads**: The internal response `axi_txn_t` MUST contain the full burst
  payload (`data[]`, `len`, `size`). `axi_txn_to_signal` streams it as R beats.
- **Writes**: The internal response `axi_txn_t` MUST contain only completion
  metadata (ID/resp fields), with no payload data.

---

## Execution Model (Normative)

The simulation MUST be deterministic across runs. The execution model is
discrete-time and clocked.

### Clock Domains

Each `axi4.clock` lowers to one posedge-driven tick domain. In the minimal
subset, all components bound to a single xbar share that xbar's clock.

### Phase-Based Execution

On each `posedge clk[i]`, the simulation MUST execute **8 phases in strict
order** for all objects in clock domain `i`. The top-level module orchestrates
phase execution by calling phase-specific methods on each component.

### Phase Methods (Normative Interface)

Each component class MUST expose the following phase methods:

```systemverilog
class axi_mgr_boundary;
  // Phase 1: Sample inputs
  function void phase_sample(axi_req_t req);
  
  // Phase 4: Receive responses from xbar
  function void phase_receive_resp(axi_txn_t resp);
  
  // Phase 5: Collect complete requests
  function void phase_collect_req();
  
  // Phase 8: Drive outputs
  function axi_resp_t phase_drive();
  
  // Inter-phase queries (called by xbar)
  function bit has_pending_txn();
  function axi_txn_t peek_txn();
  function void pop_txn();
endclass

class axi_sub_boundary;
  // Phase 1: Sample inputs
  function void phase_sample(axi_resp_t resp);
  
  // Phase 2: Collect complete responses
  function void phase_collect_resp();
  
  // Phase 7: Receive requests from xbar
  function void phase_receive_req(axi_txn_t req);
  
  // Phase 8: Drive outputs
  function axi_req_t phase_drive();
  
  // Inter-phase queries (called by xbar)
  function bit has_pending_resp();
  function axi_txn_t pop_resp();
  function bit can_accept_req();
endclass

class axi_xbar;
  // Phase 3: Route responses from subordinates to managers
  function void phase_route_resp();
  
  // Phase 6: Arbitrate and forward requests
  function void phase_arbitrate_and_forward();
endclass
```

### Phase Execution Order (Normative)

The top-level module MUST call phase methods in this exact order:

```systemverilog
always_ff @(posedge clk[domain_idx]) begin
  // ═══════════════════════════════════════════════════════════════
  // Phase 1: SAMPLE
  // Sample all input signals from external world
  // ═══════════════════════════════════════════════════════════════
  for (int m = 0; m < NUM_MGRS; m++)
    if (mgr_in_domain(m, domain_idx))
      mgr_boundary[m].phase_sample(mgr_req[m]);
      
  for (int s = 0; s < NUM_SUBS; s++)
    if (sub_in_domain(s, domain_idx))
      sub_boundary[s].phase_sample(sub_resp[s]);

  // ═══════════════════════════════════════════════════════════════
  // Phase 2: SUBORDINATE_RESPONSE_COLLECT
  // Subordinate boundaries collect complete responses from sampled beats
  // ═══════════════════════════════════════════════════════════════
  for (int s = 0; s < NUM_SUBS; s++)
    if (sub_in_domain(s, domain_idx))
      sub_boundary[s].phase_collect_resp();

  // ═══════════════════════════════════════════════════════════════
  // Phase 3: XBAR_RESPONSE_ROUTING
  // Xbars pull responses from subordinate boundaries, route to manager queues
  // ═══════════════════════════════════════════════════════════════
  for (int x = 0; x < NUM_XBARS; x++)
    if (xbar_in_domain(x, domain_idx))
      xbar[x].phase_route_resp();

  // ═══════════════════════════════════════════════════════════════
  // Phase 4: MANAGER_RESPONSE_DELIVERY
  // Xbars push routed responses to manager boundaries
  // (Integrated into phase_route_resp; managers receive via phase_receive_resp)
  // ═══════════════════════════════════════════════════════════════
  // Note: phase_route_resp calls mgr_boundary[m].phase_receive_resp() directly

  // ═══════════════════════════════════════════════════════════════
  // Phase 5: MANAGER_REQUEST_COLLECT
  // Manager boundaries collect complete requests from sampled beats
  // ═══════════════════════════════════════════════════════════════
  for (int m = 0; m < NUM_MGRS; m++)
    if (mgr_in_domain(m, domain_idx))
      mgr_boundary[m].phase_collect_req();

  // ═══════════════════════════════════════════════════════════════
  // Phase 6: XBAR_ARBITRATE_AND_FORWARD
  // Xbars arbitrate among managers, forward to subordinate queues
  // ═══════════════════════════════════════════════════════════════
  for (int x = 0; x < NUM_XBARS; x++)
    if (xbar_in_domain(x, domain_idx))
      xbar[x].phase_arbitrate_and_forward();

  // ═══════════════════════════════════════════════════════════════
  // Phase 7: SUBORDINATE_REQUEST_DELIVERY
  // Xbars push forwarded requests to subordinate boundaries
  // (Integrated into phase_arbitrate_and_forward; subs receive via phase_receive_req)
  // ═══════════════════════════════════════════════════════════════
  // Note: phase_arbitrate_and_forward calls sub_boundary[s].phase_receive_req() directly

  // ═══════════════════════════════════════════════════════════════
  // Phase 8: DRIVE
  // All boundaries drive output signals
  // ═══════════════════════════════════════════════════════════════
  for (int m = 0; m < NUM_MGRS; m++)
    if (mgr_in_domain(m, domain_idx))
      mgr_resp[m] = mgr_boundary[m].phase_drive();
      
  for (int s = 0; s < NUM_SUBS; s++)
    if (sub_in_domain(s, domain_idx))
      sub_req[s] = sub_boundary[s].phase_drive();
end
```

### Latency Model

This phase ordering introduces **one cycle of latency** through each boundary
and through the xbar:

- Request path: Manager input → (1 cycle) → Xbar → (1 cycle) → Subordinate output
- Response path: Subordinate input → (1 cycle) → Xbar → (1 cycle) → Manager output

**Total minimum round-trip latency:** 4 cycles (plus subordinate processing time)

### Progress Bounds (Normative)

Per tick, the following bounds ensure deterministic, bounded execution:

- **Manager boundary:** MAY emit at most **one** complete transaction total
  (read OR write, not both). If both a read and a write would complete in
  the same cycle, **reads take priority**: the manager boundary MUST enqueue
  only the read transaction and MUST defer enqueuing the write transaction
  (retaining its collected AW and W beat state in `aw_fifo`) until a subsequent
  cycle when no read completes.

- **Xbar:** MAY forward at most one transaction per subordinate.

- **Subordinate boundary:** MAY emit at most one complete response.

**Rationale:** The single-transaction-per-manager bound simplifies queue
management and ensures deterministic behavior. The read-priority tie-breaker
is arbitrary but consistent.

---

## Multi-Beat Streaming (Normative)

### Request Streaming (Manager → Subordinate)

For AR (read requests): Single beat, no streaming required.

For AW+W (write requests): The subordinate boundary streams beats:

```
State machine:
  IDLE → AW_PHASE → W_PHASE → IDLE
  
AW_PHASE:
  Drive AWVALID=1, AW channel signals
  On AWREADY: transition to W_PHASE
  
W_PHASE:
  For each beat in transaction:
    Drive WVALID=1, W channel signals, WLAST on final beat
    On WREADY: advance to next beat
  On final beat accepted: transition to IDLE
```

### Response Streaming (Subordinate → Manager)

For B (write responses): Single beat, no streaming required.

For R (read responses): The manager boundary streams beats:

```
State machine:
  IDLE → R_PHASE → IDLE
  
R_PHASE:
  For each beat in transaction:
    Drive RVALID=1, R channel signals, RLAST on final beat
    On RREADY: advance to next beat
  On final beat accepted: transition to IDLE
```

### Back-Pressure Handling

Per-hop queues MUST exist at manager boundaries, xbars, and subordinate
boundaries (and bridges when supported).

When RREADY or WREADY is deasserted:
- The streaming state machine stalls
- VALID remains asserted with the same data
- No progress on that channel until READY is asserted
- Other channels may continue to make progress

When streaming is stalled and the response/request queue has additional
items, they remain queued until the current item completes.

---

## Outstanding Transaction Accounting (Normative)

### Subordinate Outstanding Tracking

Each xbar maintains per-subordinate counters indexed by **local subordinate
index** within that xbar:

```systemverilog
// Inside axi_xbar class
int unsigned sub_outstanding[XBAR_NUM_SUBS[this.xbar_idx]];
```

To access global configuration (e.g., `SUB_OUTSTANDING`), convert local to global:
```systemverilog
int global_sub_idx = XBAR_SUB_INDICES[this.xbar_idx][local_sub_idx];
int limit = SUB_OUTSTANDING[global_sub_idx];
```

**Increment:** When a transaction is forwarded to the subordinate boundary
(Phase 6 succeeds).

**Decrement:** When a complete response is popped from `sub_boundaries[local_s]`
in Phase 3 (`phase_route_resp`). The xbar decrements `sub_outstanding[local_s]`
based on which subordinate queue the response was pulled from, NOT by decoding
the response address.

**Admission check:** A transaction targeting local subordinate `s` is only
forwarded if:
```systemverilog
sub_outstanding[s] < SUB_OUTSTANDING[XBAR_SUB_INDICES[xbar_idx][s]]
```

### Manager Outstanding Tracking

Each manager boundary maintains counters indexed by the single manager it
represents:

```systemverilog
// Inside axi_mgr_boundary class
int unsigned outstanding_rd;
int unsigned outstanding_wr;
```

**Increment:** When a complete transaction is emitted to the xbar
(Phase 5 completes for this txn).

**Decrement:**
- **Reads:** When the last R beat is delivered to the external interface
  (RVALID & RREADY & RLAST in Phase 8).
- **Writes:** When the B beat is delivered to the external interface
  (BVALID & BREADY in Phase 8).

**Admission check:** A new request is only collected if:
- Reads: `outstanding_rd < MGR_OUTSTANDING_RD[mgr_idx]`
- Writes: `outstanding_wr < MGR_OUTSTANDING_WR[mgr_idx]`

Back-pressure is applied via ARREADY/AWREADY when limits are reached.

---

## Arbitration (Normative)

### Round-Robin State

Each xbar maintains per-subordinate round-robin state using **local indices**:

```systemverilog
// Inside axi_xbar class
// rr_pointer[local_sub_idx] stores the local manager index to try next
int unsigned rr_pointer[XBAR_NUM_SUBS[this.xbar_idx]];
```

### Arbitration Algorithm (Phase 6)

Eligibility criteria (normative):
- The manager has at least one queued complete `tx`.
- The head `tx` decodes to the target subordinate window.
- `sub_outstanding[local_s] < SUB_OUTSTANDING[global_s]`.
- Manager-side outstanding is not exceeded at admission (enforced by the
  manager boundary; if checked here, it MUST be equivalent).

```systemverilog
function void phase_arbitrate_and_forward();
  int num_local_mgrs = XBAR_NUM_MGRS[this.xbar_idx];
  int num_local_subs = XBAR_NUM_SUBS[this.xbar_idx];
  
  // ─────────────────────────────────────────────────────────────────
  // Pre-pass: Handle decode errors for all managers
  // This ensures decode errors are processed exactly once per txn,
  // before the per-subordinate arbitration loop.
  // ─────────────────────────────────────────────────────────────────
  for (int local_m = 0; local_m < num_local_mgrs; local_m++) begin
    if (mgr_boundaries[local_m].has_pending_txn()) begin
      axi_txn_t txn = mgr_boundaries[local_m].peek_txn();
      int decoded_local_s = decode(txn.meta.addr);
      
      if (decoded_local_s == -1) begin
        // Decode error: consume request and generate error response
        mgr_boundaries[local_m].pop_txn();
        if (has_default_error) begin
          axi_txn_t err_resp = generate_error_response(txn, default_error);
          mgr_boundaries[local_m].phase_receive_resp(err_resp);
        end else begin
          $error("Decode error with no default_error configured for addr 0x%h from manager %0d",
                 txn.meta.addr, local_m);
        end
      end
    end
  end
  
  // ─────────────────────────────────────────────────────────────────
  // Main pass: Arbitrate and forward to subordinates
  // At this point, all pending txns have valid decode targets.
  // ─────────────────────────────────────────────────────────────────
  for (int local_s = 0; local_s < num_local_subs; local_s++) begin
    int global_s = XBAR_SUB_INDICES[this.xbar_idx][local_s];
    
    // Check subordinate capacity
    if (sub_outstanding[local_s] >= SUB_OUTSTANDING[global_s])
      continue;
    
    // Find eligible managers (local indices)
    int eligible[$];
    for (int local_m = 0; local_m < num_local_mgrs; local_m++) begin
      if (mgr_boundaries[local_m].has_pending_txn()) begin
        axi_txn_t txn = mgr_boundaries[local_m].peek_txn();
        if (decode(txn.meta.addr) == local_s)
          eligible.push_back(local_m);
      end
    end
    
    if (eligible.size() == 0)
      continue;
    
    // Round-robin selection starting from rr_pointer[local_s]
    int winner_local = -1;
    for (int i = 0; i < num_local_mgrs; i++) begin
      int candidate = (rr_pointer[local_s] + i) % num_local_mgrs;
      if (candidate inside {eligible}) begin
        winner_local = candidate;
        break;
      end
    end
    
    if (winner_local != -1) begin
      axi_txn_t txn = mgr_boundaries[winner_local].peek_txn();
      mgr_boundaries[winner_local].pop_txn();
      
      sub_boundaries[local_s].phase_receive_req(txn);
      sub_outstanding[local_s]++;
      
      rr_pointer[local_s] = (winner_local + 1) % num_local_mgrs;
    end
  end
endfunction

// Decode returns local subordinate index, or -1 for decode error
// Note: Verifier guarantees base+size does not overflow for the xbar addr_width.
// Implementations may use widened arithmetic or range comparisons to avoid
// potential 64-bit overflow in the addition.
function int decode(logic [63:0] addr);
  logic [63:0] masked = mask_addr(addr, XBAR_ADDR_WIDTH[this.xbar_idx]);
  
  for (int local_s = 0; local_s < XBAR_NUM_SUBS[this.xbar_idx]; local_s++) begin
    int global_s = XBAR_SUB_INDICES[this.xbar_idx][local_s];
    logic [63:0] base = SUB_WINDOW_BASE[global_s];
    logic [63:0] size = SUB_WINDOW_SIZE[global_s];
    // Range check: base <= masked < base + size
    // Equivalent to: masked >= base && masked - base < size (avoids overflow)
    if (masked >= base && (masked - base) < size)
      return local_s;
  end
  
  return -1;  // Decode error (handled by default_error policy)
endfunction
```

### Determinism Guarantee

The round-robin pointer advances only on successful grants, ensuring
deterministic arbitration across simulation runs with identical inputs.

---

## Burst Semantics (Normative)

### Supported Burst Types

| Type | AXBURST | Addressing |
|------|---------|------------|
| FIXED | 2'b00 | Same address for all beats |
| INCR | 2'b01 | Incrementing address |
| WRAP | 2'b10 | Wrapping at boundary |

### Alignment Rules (Minimal Subset)

The minimal subset enforces **strict alignment** for simplicity:

| Burst Type | Start Address Alignment | Enforced By |
|------------|------------------------|-------------|
| FIXED | Aligned to beat size (`addr % beat_bytes == 0`) | Verifier |
| INCR | Aligned to beat size (`addr % beat_bytes == 0`) | Verifier |
| WRAP | Aligned to wrap boundary (`addr % (beat_bytes * num_beats) == 0`) | Verifier |

Where:
- `beat_bytes = 2^AXSIZE`
- `num_beats = AXLEN + 1`

**Rationale:** Unaligned burst support requires narrow transfer handling and
byte lane steering, which adds complexity. The verifier rejects unaligned
bursts; the simulation model assumes aligned bursts only.

**Future expansion:** Full unaligned support would require:
- Byte lane steering logic
- Narrow transfer indication
- Update to INTENT.md alignment rules

### Address Calculation

For INCR bursts (aligned):
```
beat[n].addr = start_addr + (n * beat_bytes)
```

For WRAP bursts (aligned to wrap boundary):
```
wrap_boundary = start_addr  // Already aligned by verifier
wrap_size = beat_bytes * num_beats
beat[n].addr = wrap_boundary + ((n * beat_bytes) % wrap_size)
```

For FIXED bursts:
```
beat[n].addr = start_addr  // Same for all beats
```

### Burst Length Limits

The model MUST enforce AXI4 burst length limits:
- INCR: 1-256 beats (AXLEN 0x00-0xFF)
- WRAP: 2, 4, 8, or 16 beats only (AXLEN 0x01, 0x03, 0x07, 0x0F)
- FIXED: 1-16 beats (AXLEN 0x00-0x0F)

---

## Error Handling (Normative)

### Decode Errors

When a transaction address does not match any subordinate window:

- If `default_error` is set: The xbar consumes the request in Phase 6 and
  immediately enqueues a synthetic error response to the originating manager
  (delivered via `phase_receive_resp` in the same phase).
- If `default_error` is not set: This is a verification error; the IR verifier
  ensures full coverage, so this case should not occur in valid IR. The
  simulation MUST emit a runtime error and MAY terminate.

### Subordinate Errors

External subordinates may return SLVERR. The model passes this through
unchanged to the originating manager.

### Error Response Generation

For decode errors, the xbar generates a synthetic response:

```systemverilog
function axi_txn_t generate_error_response(axi_txn_t req, axi_resp_e err_type);
  axi_txn_t resp = new();
  resp.meta = req.meta;
  resp.meta.resp = err_type;
  if (!req.meta.is_write) begin
    // Read error: return garbage data for all beats
    resp.data = new[req.num_beats() * req.beat_bytes()];
    foreach (resp.data[i]) resp.data[i] = 8'hXX;
  end
  return resp;
endfunction
```

**Routing preservation:** Synthetic error responses MUST preserve `meta.tag`
and `meta.mgr_idx` from the request so they route identically to normal
responses. The `resp.meta = req.meta` assignment accomplishes this.

---

## Core Classes (Normative Interfaces)

### `axi_mgr_boundary`

```systemverilog
class axi_mgr_boundary;
  // Configuration (set at construction from axi_pkg)
  int unsigned mgr_idx;              // Global manager index
  int unsigned data_width;
  int unsigned id_width;
  int unsigned outstanding_rd_limit;
  int unsigned outstanding_wr_limit;
  int unsigned reorder_depth_rd;
  int unsigned reorder_depth_wr;
  
  // Outstanding tracking
  int unsigned outstanding_rd;
  int unsigned outstanding_wr;
  
  // Request collection state
  axi_req_t    sampled_req;
  axi_txn_t    pending_aw;           // Partial write awaiting W beats
  axi_txn_t    complete_req_queue[$];
  
  // Response delivery state
  axi_txn_t    resp_queue[$];
  axi_txn_t    streaming_resp;       // Currently streaming R beats
  int unsigned streaming_beat_idx;
  
  // Reorder tracking: sparse storage keyed by (is_write, id)
  // Implementations MUST use associative arrays or equivalent sparse
  // storage, NOT dense arrays of size 2^ID_WIDTH.
  int unsigned next_seq[bit][int];           // [is_write][id] -> next seq to assign
  int unsigned pending_seqs[bit][int][$];    // [is_write][id] -> queue of outstanding seqs
  
  // Phase methods
  function void phase_sample(axi_req_t req);
  function void phase_receive_resp(axi_txn_t resp);
  function void phase_collect_req();
  function axi_resp_t phase_drive();
  
  // Xbar interface
  function bit has_pending_txn();
  function axi_txn_t peek_txn();
  function void pop_txn();
endclass
```

### `axi_sub_boundary`

```systemverilog
class axi_sub_boundary;
  // Configuration (set at construction from axi_pkg)
  int unsigned sub_idx;              // Global subordinate index
  int unsigned data_width;
  int unsigned id_width;
  logic [63:0] window_base;
  logic [63:0] window_size;
  int unsigned outstanding_limit;
  
  // Request delivery state
  axi_txn_t    req_queue[$];
  axi_txn_t    streaming_req;        // Currently streaming AW+W
  int unsigned streaming_beat_idx;
  enum { IDLE, AW_PHASE, W_PHASE } streaming_state;
  
  // Response collection state
  axi_resp_t   sampled_resp;
  axi_txn_t    pending_r;            // Partial read collecting R beats
  axi_txn_t    complete_resp_queue[$];
  
  // Phase methods
  function void phase_sample(axi_resp_t resp);
  function void phase_collect_resp();
  function void phase_receive_req(axi_txn_t req);
  function axi_req_t phase_drive();
  
  // Xbar interface
  function bit has_pending_resp();
  function axi_txn_t pop_resp();
  function bit can_accept_req();
endclass
```

### `axi_xbar`

```systemverilog
class axi_xbar;
  // Configuration (set at construction from axi_pkg)
  int unsigned xbar_idx;
  int unsigned addr_width;
  int unsigned data_width;
  axi_resp_e   default_error;
  bit          has_default_error;
  
  // Bound endpoints (references to boundary objects, LOCAL indexing)
  axi_mgr_boundary mgr_boundaries[];  // Indexed by local manager index
  axi_sub_boundary sub_boundaries[];  // Indexed by local subordinate index
  
  // Arbitration state (local indices)
  int unsigned rr_pointer[];          // Per local subordinate
  
  // Outstanding tracking (local indices)
  int unsigned sub_outstanding[];     // Per local subordinate
  
  // Phase methods
  function void phase_route_resp();
  function void phase_arbitrate_and_forward();
  
  // Internal helpers
  function int decode(logic [63:0] addr);  // Returns local sub index or -1
  function axi_txn_t generate_error_response(axi_txn_t req, axi_resp_e err);
endclass
```

---

## Diagnostic Messages (Normative)

### Lowering Errors

```
error: axi4.xbar 'main_bus': unsupported arbitration policy 'wrr'
  note: minimal subset only supports 'rr' (round-robin)
  
error: axi4.manager 'cpu': clock domain mismatch
  note: manager uses clock %cpu_clk defined at example.mlir:10:3
  note: bound xbar 'main_bus' uses clock %sys_clk defined at example.mlir:5:3
  note: insert axi4.cdc adapter or use the same clock

error: axi4.subordinate 'sram': bound to multiple xbars
  note: bound to 'main_bus' at example.mlir:50:3
  note: bound to 'periph_bus' at example.mlir:80:3
  note: minimal subset requires each subordinate bound to exactly one xbar
  
error: axi4.bridge: operation not supported in minimal subset
```

### Runtime Errors

```
ERROR [cycle %0d]: Reorder depth exceeded
  Manager: %s (idx=%0d)
  Channel: READ
  ID: 0x%0h
  Expected response for seq <= %0d, received seq %0d
  Configured reorder_depth: %0d

ERROR [cycle %0d]: Decode error (no default_error configured)
  Source manager: %s (idx=%0d)
  Address: 0x%0h
  This should not occur with valid IR; check verifier output

WARNING [cycle %0d]: Subordinate outstanding limit reached
  Subordinate: %s (idx=%0d)
  Outstanding: %0d (limit: %0d)
  Transaction from manager %s stalled
```

---

## Verification Checklist

The lowering MUST verify (in addition to MLIR passes):

1. ☐ No disallowed operations present
2. ☐ No disallowed attribute values present
3. ☐ All endpoints share xbar clock (SSA equality)
4. ☐ No exclusive flags set
5. ☐ Each subordinate bound to exactly one xbar
6. ☐ All subordinate windows non-overlapping within each xbar
7. ☐ Manager access windows covered by subordinates (or default_error set)
8. ☐ Data widths match within each xbar
9. ☐ Burst capabilities compatible (manager ≤ subordinate)
10. ☐ `INTERNAL_*_WIDTH >= max(endpoint widths)` for all endpoints

---

## Appendix A: PULP AXI Struct Reference

For completeness, the expected PULP AXI struct layout:

```systemverilog
typedef struct packed {
  // AW channel
  logic        aw_valid;
  logic [ID_W-1:0]   aw_id;
  logic [ADDR_W-1:0] aw_addr;
  logic [7:0]  aw_len;
  logic [2:0]  aw_size;
  logic [1:0]  aw_burst;
  logic        aw_lock;
  logic [3:0]  aw_cache;
  logic [2:0]  aw_prot;
  logic [3:0]  aw_qos;
  logic [3:0]  aw_region;
  logic [USER_W-1:0] aw_user;
  
  // W channel
  logic        w_valid;
  logic [DATA_W-1:0] w_data;
  logic [DATA_W/8-1:0] w_strb;
  logic        w_last;
  logic [USER_W-1:0] w_user;
  
  // B channel (active low for request direction)
  logic        b_ready;
  
  // AR channel
  logic        ar_valid;
  logic [ID_W-1:0]   ar_id;
  logic [ADDR_W-1:0] ar_addr;
  logic [7:0]  ar_len;
  logic [2:0]  ar_size;
  logic [1:0]  ar_burst;
  logic        ar_lock;
  logic [3:0]  ar_cache;
  logic [2:0]  ar_prot;
  logic [3:0]  ar_qos;
  logic [3:0]  ar_region;
  logic [USER_W-1:0] ar_user;
  
  // R channel (active low for request direction)
  logic        r_ready;
} axi_req_t;

typedef struct packed {
  // AW channel (active low for response direction)
  logic        aw_ready;
  
  // W channel (active low for response direction)
  logic        w_ready;
  
  // B channel
  logic        b_valid;
  logic [ID_W-1:0]   b_id;
  logic [1:0]  b_resp;
  logic [USER_W-1:0] b_user;
  
  // AR channel (active low for response direction)
  logic        ar_ready;
  
  // R channel
  logic        r_valid;
  logic [ID_W-1:0]   r_id;
  logic [DATA_W-1:0] r_data;
  logic [1:0]  r_resp;
  logic        r_last;
  logic [USER_W-1:0] r_user;
} axi_resp_t;
```

---

## Appendix B: Example Lowering

Given this MLIR input:

```mlir
module @simple_soc {
  %clk = axi4.clock { freq = 100_000_000 }
  
  %cpu = axi4.manager(%clk) {
    sym_name = "cpu",
    access = [{ base = 0x0, size = 0x1_0000_0000 }],
    data_width = 64,
    outstanding_reads = 4,
    outstanding_writes = 2,
    reorder_depth = 4,
    write_reorder_depth = 1,
    burst_capability = { incr = { max_len = 16 } }
  }
  
  %sram = axi4.subordinate(%clk) {
    sym_name = "sram",
    window = { base = 0x0, size = 0x1_0000 },
    data_width = 64,
    outstanding = 4,
    burst_capability = { incr = { max_len = 256 } }
  }
  
  %uart = axi4.subordinate(%clk) {
    sym_name = "uart",
    window = { base = 0x1000_0000, size = 0x1000 },
    data_width = 64,
    outstanding = 1,
    burst_capability = { incr = { max_len = 1 } }
  }
  
  %xbar = axi4.xbar(%clk,
                    managers = [%cpu],
                    subordinates = [%sram, %uart]) {
    sym_name = "main_bus",
    addr_width = 32,
    data_width = 64,
    default_error = "decerr",
    arb = "rr",
    txn_policy = "expand"
  }
}
```

The lowering produces:

```systemverilog
package axi_pkg;
  // Internal width parameters
  parameter int unsigned INTERNAL_ID_WIDTH   = 16;
  parameter int unsigned INTERNAL_ADDR_WIDTH = 64;
  parameter int unsigned INTERNAL_USER_WIDTH = 16;

  // Global counts
  parameter int unsigned NUM_CLKS  = 1;
  parameter int unsigned NUM_MGRS  = 1;
  parameter int unsigned NUM_SUBS  = 2;
  parameter int unsigned NUM_XBARS = 1;
  
  // Per-xbar: number of bound endpoints
  parameter int unsigned XBAR_NUM_MGRS[1] = '{ 1 };
  parameter int unsigned XBAR_NUM_SUBS[1] = '{ 2 };
  
  // Per-xbar: global indices of bound endpoints
  parameter int unsigned XBAR_MGR_INDICES[1][1] = '{ '{ 0 } };      // xbar 0: manager 0
  parameter int unsigned XBAR_SUB_INDICES[1][2] = '{ '{ 0, 1 } };   // xbar 0: subs 0, 1
  
  // Per-xbar configuration
  parameter int unsigned XBAR_ADDR_WIDTH[1] = '{ 32 };
  parameter int unsigned XBAR_DATA_WIDTH[1] = '{ 64 };
  
  // Manager 0: cpu
  parameter int unsigned MGR_DATA_WIDTH[1]     = '{ 64 };
  parameter int unsigned MGR_ID_WIDTH[1]       = '{ 4 };  // Default
  parameter int unsigned MGR_OUTSTANDING_RD[1] = '{ 4 };
  parameter int unsigned MGR_OUTSTANDING_WR[1] = '{ 2 };
  parameter int unsigned MGR_REORDER_DEPTH[1]  = '{ 4 };
  
  // Subordinate 0: sram, Subordinate 1: uart
  parameter int unsigned SUB_DATA_WIDTH[2]      = '{ 64, 64 };
  parameter int unsigned SUB_ID_WIDTH[2]        = '{ 4, 4 };
  parameter int unsigned SUB_OUTSTANDING[2]     = '{ 4, 1 };
  parameter logic [63:0] SUB_WINDOW_BASE[2]     = '{ 64'h0, 64'h1000_0000 };
  parameter logic [63:0] SUB_WINDOW_SIZE[2]     = '{ 64'h1_0000, 64'h1000 };
  parameter bit          SUB_REORDERS_READS[2]  = '{ 0, 0 };
  parameter bit          SUB_REORDERS_WRITES[2] = '{ 0, 0 };
  
  // Type definitions...
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;
  
  // ... axi_txn_meta_t, axi_txn_t, axi_req_t, axi_resp_t ...
endpackage

module axi_sim_top
  import axi_pkg::*;
(
  input  logic        clk [1],
  input  axi_req_t    mgr_req [1],
  output axi_resp_t   mgr_resp [1],
  output axi_req_t    sub_req [2],
  input  axi_resp_t   sub_resp [2]
);

  // Boundary and xbar instances
  axi_mgr_boundary mgr_boundary[1];
  axi_sub_boundary sub_boundary[2];
  axi_xbar         xbar[1];
  
  initial begin
    // Initialize manager boundary 0 (cpu)
    mgr_boundary[0] = new();
    mgr_boundary[0].mgr_idx = 0;
    mgr_boundary[0].data_width = 64;
    mgr_boundary[0].id_width = 4;
    mgr_boundary[0].outstanding_rd_limit = 4;
    mgr_boundary[0].outstanding_wr_limit = 2;
    mgr_boundary[0].reorder_depth_rd = 4;
    mgr_boundary[0].reorder_depth_wr = 1;
    
    // Initialize subordinate boundary 0 (sram)
    sub_boundary[0] = new();
    sub_boundary[0].sub_idx = 0;
    sub_boundary[0].data_width = 64;
    sub_boundary[0].id_width = 4;
    sub_boundary[0].window_base = 64'h0;
    sub_boundary[0].window_size = 64'h1_0000;
    sub_boundary[0].outstanding_limit = 4;
    
    // Initialize subordinate boundary 1 (uart)
    sub_boundary[1] = new();
    sub_boundary[1].sub_idx = 1;
    sub_boundary[1].data_width = 64;
    sub_boundary[1].id_width = 4;
    sub_boundary[1].window_base = 64'h1000_0000;
    sub_boundary[1].window_size = 64'h1000;
    sub_boundary[1].outstanding_limit = 1;
    
    // Initialize xbar 0 (main_bus)
    xbar[0] = new();
    xbar[0].xbar_idx = 0;
    xbar[0].addr_width = 32;
    xbar[0].data_width = 64;
    xbar[0].has_default_error = 1;
    xbar[0].default_error = AXI_RESP_DECERR;
    xbar[0].mgr_boundaries = new[1];
    xbar[0].mgr_boundaries[0] = mgr_boundary[0];
    xbar[0].sub_boundaries = new[2];
    xbar[0].sub_boundaries[0] = sub_boundary[0];
    xbar[0].sub_boundaries[1] = sub_boundary[1];
    xbar[0].rr_pointer = new[2];
    xbar[0].sub_outstanding = new[2];
  end
  
  // All components in clock domain 0
  always_ff @(posedge clk[0]) begin
    // Phase 1: Sample
    mgr_boundary[0].phase_sample(mgr_req[0]);
    sub_boundary[0].phase_sample(sub_resp[0]);
    sub_boundary[1].phase_sample(sub_resp[1]);
    
    // Phase 2: Subordinate response collect
    sub_boundary[0].phase_collect_resp();
    sub_boundary[1].phase_collect_resp();
    
    // Phase 3 & 4: Xbar response routing (calls mgr phase_receive_resp internally)
    xbar[0].phase_route_resp();
    
    // Phase 5: Manager request collect
    mgr_boundary[0].phase_collect_req();
    
    // Phase 6 & 7: Xbar arbitrate and forward (calls sub phase_receive_req internally)
    xbar[0].phase_arbitrate_and_forward();
    
    // Phase 8: Drive
    mgr_resp[0] = mgr_boundary[0].phase_drive();
    sub_req[0] = sub_boundary[0].phase_drive();
    sub_req[1] = sub_boundary[1].phase_drive();
  end

endmodule
```

---

## Appendix C: Future Adapter Classes (Non-Normative)

These class interfaces are provided for future expansion planning.

### `axi_bridge`

```systemverilog
class axi_bridge;
  // Address translation
  logic [63:0] upstream_base;
  logic [63:0] upstream_size;
  logic [63:0] downstream_base;
  
  // Capacity
  int unsigned outstanding_limit;
  int unsigned outstanding;
  
  // Queues
  axi_txn_t req_queue[$];
  axi_txn_t resp_queue[$];
  
  // Stateful: needs tick for CDC if clocks differ
  function axi_txn_t translate_addr(axi_txn_t txn);
  function void phase_route_req();
  function void phase_route_resp();
endclass
```

### `axi_resizer_adapter`

```systemverilog
class axi_resizer_adapter;
  // Stateless: pure combinational translation
  int unsigned input_width;
  int unsigned output_width;
  
  function axi_txn_t upsize_req(axi_txn_t req);
  function axi_txn_t downsize_req(axi_txn_t req);
  function axi_txn_t upsize_resp(axi_txn_t resp);
  function axi_txn_t downsize_resp(axi_txn_t resp);
endclass
```

### `axi_burst_splitter_adapter`

```systemverilog
class axi_burst_splitter_adapter;
  // Stateful: must reassemble responses from split bursts
  int unsigned max_output_len;
  
  // Pending split state
  axi_txn_t pending_input_req;
  axi_txn_t output_req_queue[$];
  axi_txn_t pending_resp_parts[$];
  
  function void push_req(axi_txn_t req);
  function bit has_output_req();
  function axi_txn_t pop_output_req();
  function void push_resp(axi_txn_t resp);
  function bit has_output_resp();
  function axi_txn_t pop_output_resp();
endclass
```

### `axi_cdc_adapter`

```systemverilog
class axi_cdc_adapter;
  // Stateful: async FIFOs require separate tick per domain
  int unsigned fifo_depth;
  
  axi_txn_t req_fifo[$];
  axi_txn_t resp_fifo[$];
  
  function void phase_tick_src();  // Called in source clock domain
  function void phase_tick_dst();  // Called in destination clock domain
endclass
```

---

This specification is expected to evolve alongside the lowering implementation
and the SystemVerilog simulation library API.
