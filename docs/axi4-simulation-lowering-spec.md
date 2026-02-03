# AXI4 Simulation Lowering Specification

This document specifies the SystemVerilog simulation lowering for the AXI4
MLIR dialect. Unless explicitly overridden here, all semantics MUST follow
`include/axi4/INTENT.md`.

## Scope and Goals

- Preserve AXI4 protocol semantics (ordering, routing, bursts, errors).
- Preserve network semantics (routing, bridges, aliasing, coverage).
- Provide deterministic, debuggable behavior.
- Avoid cycle-accurate modeling unless explicitly required.

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

- Exclusive access flags on endpoints MUST NOT be used
- `axi4.exclusive_monitor` MUST NOT be used
- `axi4.exclusive` bridge attributes MUST NOT be used
- `axi4.bridge` MUST NOT be used
- `axi4.alias` MUST NOT be used
- Any arbitration policy other than round-robin MUST NOT be used
- Transaction policies other than `expand` MUST NOT be used

[REQUIRED CHANGE] Lowering-time enforcement.
The lowering pass MUST emit a hard error if any disallowed operation or
disallowed attribute value is present in the IR.

Example: axi4.xbar { arb = "wrr" } ⇒ lowering fails.

Example: any axi4.bridge op ⇒ lowering fails.

### Assumptions

- All address windows are aligned and non-overlapping.
- Width and burst compatibility are enforced by verification passes.

### Minimal Simulation Requirements

- Basic routing through xbars
- Coverage checks for `default_error`
- Deterministic round-robin arbitration

### Future Expansions (Out of Scope for Minimal Subset)

Adapters:
- `axi4.resizer`
- `axi4.burst_splitter`
- `axi4.cdc`
- `axi4.exclusive_monitor`

Topology:
- `axi4.bridge`
- `axi4.alias`

## Output Artifacts

The lowering MUST emit:

- **One top-level SystemVerilog module** with ports for every clock, manager,
  and subordinate.
- **One SystemVerilog package** containing all configuration (typedef
  instantiations, windows, widths, policies, constants).

### Top-Level Module Interface (Normative)

The top-level module MUST use arrayed ports and preserve MLIR/IR definition
order for managers and subordinates. A single global `axi_pkg` MUST be emitted.

```systemverilog
module axi_sim_top #(
  parameter int unsigned NUM_CLKS = ...,
  parameter int unsigned NUM_MGRS = ...,
  parameter int unsigned NUM_SUBS = ...
) (
  // Clocks
  input  logic [NUM_CLKS-1:0] clk,

  // Managers: external world drives req, receives resp
  input  axi_req_t  mgr_req   [NUM_MGRS],
  output axi_resp_t mgr_resp  [NUM_MGRS],

  // Subordinates: model drives req, external world returns resp
  output axi_req_t  sub_req   [NUM_SUBS],
  input  axi_resp_t sub_resp  [NUM_SUBS]
);
  // ...
endmodule
```

[CLARIFICATION] Index mapping must be unambiguous.
The lowering MUST define a global index space for managers and subordinates
used by these arrayed ports.

Global manager indices MUST follow textual order of axi4.manager ops
in the (post-canonicalization) module.

Global subordinate indices MUST follow textual order of axi4.subordinate
ops in the (post-canonicalization) module.

For each axi4.xbar, the lowering MUST emit the list of global indices
corresponding to the xbar's managers=[...] and subordinates=[...] operands
into the generated package.

## PULP AXI Struct Integration (External I/O)

At the boundary of the simulation model, manager and subordinate models MUST
accept/emit PULP AXI request/response structs (`axi_req_t` / `axi_resp_t`).
Internally, the model MAY translate those structs into a simpler representation,
but the public API MUST speak PULP AXI types.

Boundary direction (normative):
- **`axi_manager`**: accepts `axi_req_t` from the outside world and emits
  `axi_resp_t` back to the outside world.
- **`axi_subordinate`**: accepts `axi_req_t` from the interconnect and emits
  `axi_resp_t` back into the interconnect.

[REQUIRED CHANGE] Make boundary translation explicit.
axi_req_t/axi_resp_t represent channel-level ready/valid handshakes.
The internal simulation core is transaction-level. Therefore the lowering
MUST instantiate boundary adapters that translate between handshake structs and
complete internal transactions (tx).

axi_signal_to_txn (packer/collector): consumes axi_req_t over cycles and
produces complete tx objects.

axi_txn_to_signal (unpacker/driver): consumes tx responses and drives
axi_resp_t over cycles while respecting ready/valid.

Without these adapters, a class method signature like
push_req(axi_req_t req) is ambiguous (it would treat a per-cycle struct as a
whole request).

## Execution Model (Normative)

[REQUIRED CHANGE] Define deterministic scheduling.
The simulation MUST be deterministic across runs. The execution model is
discrete-time and clocked.

Each axi4.clock lowers to one posedge-driven tick domain.

Each object (manager boundary, xbar, subordinate boundary) is assigned to
exactly one clock domain in the minimal subset.

On each posedge clk[i], the top module MUST call tick() for all objects
in that domain in a fixed, deterministic order.

Normative tick order within a clock domain:

Drain responses from external subordinates into xbar response queues.

Arbitrate + admit new transactions from managers into xbars.

Forward admitted transactions from xbars to subordinate boundaries.

Deliver responses from xbars to manager boundaries.

Progress bound (minimal subset):

Each xbar tick MUST admit at most one new transaction per subordinate
(or fewer if the subordinate outstanding limit would be exceeded).

Each manager boundary tick MUST emit at most one complete transaction
into the fabric.

Each subordinate boundary tick MUST emit at most one complete response
into the fabric.

These bounds keep the model simple and deterministic; future versions may
loosen them but must specify new bounds.

## Core Classes (Normative Interfaces)

### `axi_manager`

```systemverilog
class axi_manager;
  function void push_req(axi_req_t req);
  function bit  pop_resp(output axi_resp_t resp);
  function void tick();
endclass
```

### `axi_subordinate`

```systemverilog
class axi_subordinate;
  function bit  accept_req(axi_req_t req);
  function bit  pop_resp(output axi_resp_t resp);
  function void tick();
endclass
```

### `axi_xbar`

```systemverilog
class axi_xbar;
  function bit  accept_req(int mgr_idx, tx req);
  function bit  pop_resp(int mgr_idx, output tx resp);
  function void tick();
endclass
```

[REQUIRED CHANGE] Clarify role of PULP structs vs internal tx.
The axi_manager and axi_subordinate classes above are boundary-facing and
accept/emit PULP AXI structs.

The axi_xbar class is internal and MUST operate on transaction objects tx.
Therefore, boundary adapters (see below) MUST exist between:

axi_manager (struct-level) ⇄ tx (fabric-level)

tx (fabric-level) ⇄ axi_subordinate (struct-level)

Implementations MAY choose to integrate these adapters into the boundary
classes, but the translation MUST be present and MUST follow the rules below.

### `axi_bridge` (future expansion)

```systemverilog
class axi_bridge;
  function bit  accept_req(tx req);
  function bit  pop_resp(output tx resp);
  function void tick();
endclass
```

### `axi_alias` (future expansion)

```systemverilog
class axi_alias;
  function axi_subordinate resolve_target();
endclass
```

## Boundary Adapter Components (Normative)

[REQUIRED CHANGE] Add explicit boundary adapters.
The lowering MUST instantiate the following logical components per manager and
per subordinate boundary.

axi_signal_to_txn (packer)

Collects AR bursts into a tx (read request).

Collects AW + all W beats into a tx (write request).

Normative rule (minimal subset):

A write transaction MUST NOT be emitted into the fabric until the full burst
payload has been collected (AW received and all W beats received).

axi_txn_to_signal (driver)

Converts a tx response into the appropriate B or R handshake sequence on
axi_resp_t.

**[CLARIFICATION] This model is transaction-level internally but still
handshake-correct at the boundary.

## Adapter Classes (Future Expansion)

### `axi_resizer_adapter`

```systemverilog
class axi_resizer_adapter;
  function tx   translate_req(tx req);
  function tx   translate_resp(tx resp);
endclass
```

### `axi_burst_splitter_adapter`

```systemverilog
class axi_burst_splitter_adapter;
  function bit  push_req(tx req);
  function bit  pop_req(output tx req);
  function bit  push_resp(tx resp);
  function bit  pop_resp(output tx resp);
endclass
```

### `axi_cdc_adapter`

```systemverilog
class axi_cdc_adapter;
  function bit  push_req(tx req);
  function bit  pop_resp(output tx resp);
  function void tick();
endclass
```

### `axi_exclusive_monitor_adapter`

```systemverilog
class axi_exclusive_monitor_adapter;
  function bit  accept_req(tx req);
  function bit  pop_resp(output tx resp);
endclass
```

## Internal Transaction Model (Normative)

[CLARIFICATION] Address width behavior.
The lowering MUST mask/interpret addresses according to the relevant xbar's
addr_width. All decode comparisons MUST match the dialect verifier's
base + size <= 2^addr_width rules.

### Internal `tx` Structure

```
struct tx {
  bit is_write;
  uint64 addr;
  uint32 beat_bytes;
  uint32 beats;
  bit exclusive;
  uint32 id;
  uint32 user;
  uint8  prot;
  uint8  qos;
  uint8  region;
  uint8  cache;
  bit    lock;
  byte   data[];
  byte   strb[];
  uint64 tag;
}
```

### ID Semantics (Normative)

- Preserve AXI IDs end-to-end.
- Maintain ordering per `(manager, channel, id)`.
- Treat read and write ID spaces independently.

[REQUIRED CHANGE] Define expand-policy disambiguation.
Under txn_policy=expand, different managers may issue the same AXI ID.
Internally, the model MUST disambiguate and route responses correctly.

Each admitted request MUST be tagged with (mgr_idx, original_id, is_write).

The tx.tag field MUST carry sufficient information to route the response
back to the correct manager and to restore the original AXI ID at the
boundary.

If an internal subordinate-facing representation requires unique IDs, the
model MAY synthesize internal IDs, but MUST restore the original IDs when
emitting responses to the manager boundary.

## Semantics to Preserve

Unless narrowed by the minimal subset, all semantics follow
`include/axi4/INTENT.md`.

- **Address translation and coverage**: Xbars route by window match. Bridges
  translate and then route downstream. Unmapped accesses return DECERR.
- **Burst semantics**: Enforce AXI length limits and alignment. Address MUST be
  aligned to `beat_bytes` for all bursts.
- **Ordering**: Preserve ordering per manager and per target.
- **Exclusive access**: Out of scope for the minimal subset.

[REQUIRED CHANGE] Align unmapped behavior with dialect intent.

If default_error is present on an xbar, unmapped accesses MUST return the
specified error response.

If default_error is absent, IR verification MUST ensure full coverage; the
lowering MAY assume that unmapped accesses do not occur.

This replaces the previous statement that unmapped accesses return DECERR even
when default_error is not set.

## Performance and Back-Pressure Modeling (Normative)

The model MUST be transaction-level with explicit queue capacity.

- **Per-hop queues** at managers, xbars, bridges, and subordinates.
- **Outstanding limits** enforced at admission; if full, upstream stalls.
- **Deterministic** arbitration and timing (no randomized latency).
- **Queue depth default**: when not configured, use the corresponding
  `outstanding_*` limit.

[CLARIFICATION] Outstanding accounting (minimal subset).

Each xbar maintains sub_outstanding[sub_idx] = number of forwarded
transactions that have not yet completed.

Increment when subordinate.accept_req(tx) succeeds.

Decrement when the corresponding completion is observed:

writes: upon B completion

reads: upon last R beat completion
(or equivalently, when the complete response tx is received back internally
if modeling whole-response transactions).

## Arbitration (Normative)

- Round-robin only, with a strict rotating pointer for tie-breaks.

[CLARIFICATION] Unit of arbitration.
Each xbar tick performs arbitration per subordinate:

For each subordinate, select at most one eligible manager request that
targets that subordinate.

Advance that subordinate's RR pointer only after a successful grant/forward.

## Error Handling (Normative)

- Unmapped addresses return **DECERR**, even when `default_error` is not set.
- Target-signaled failures return **SLVERR**.

[REQUIRED CHANGE] Unmapped access handling depends on default_error.

If default_error is present, unmapped accesses return the configured
response (DECERR or SLVERR).

If default_error is absent, unmapped accesses are a verifier error and are
assumed not to occur during simulation.

## Lowering Validation (Normative)

- Coverage and overlap MUST be verified in MLIR passes.
- Width/burst compatibility MUST be verified before model instantiation.

[REQUIRED CHANGE] Minimal-subset validation.
The lowering MUST additionally validate (and hard-error) that:

no disallowed ops appear (axi4.bridge, axi4.alias, adapters, exclusives)

axi4.xbar uses only arb=rr and txn_policy=expand

endpoint exclusive flags are not set

---

This specification is expected to evolve alongside the lowering
implementation and the SV simulation library API.
