# AXI4 Dialect to SystemVerilog Simulation Lowering

This document defines a high-level, semantically correct (not necessarily
cycle-accurate) SystemVerilog simulation model for lowering the AXI4 dialect.
The goal is to preserve protocol semantics (ordering, routing, bursts,
exclusive access, errors, address translation, aliasing) while enabling a
fast, deterministic simulation model.

## Goals

- Preserve AXI4 protocol semantics (ordering, burst behavior, errors).
- Preserve network semantics (routing, bridges, aliasing, coverage).
- Provide deterministic, debuggable behavior.
- Avoid cycle-accurate modeling unless explicitly required.

## Non-Goals

- Cycle-accurate timing or precise arbitration timing.
- Bit-accurate modeling of IDs, channels, or backpressure.
- Synthesizable RTL.

## Conceptual Model

Lower the dialect to SystemVerilog classes representing endpoints and
interconnect fabric. The model is event-driven, uses queues for requests, and
resolves routing via address translation and configured windows.

```
Manager -> Xbar -> (Bridge -> Xbar -> ... ) -> Subordinate
```

### Canonical Data Types

- **Address**: 64-bit unsigned
- **Data**: arbitrary width (byte array or packed bit vector)
- **Burst**: `{type, length, beat_bytes}`
- **Response**: `OKAY/SLVERR/DECERR`

## PULP AXI Struct Integration (External I/O)

At the boundary of the simulation model, **manager and subordinate models must
accept/emit PULP AXI request/response structs**. Internally, the model may
translate those structs into a simpler representation (queues of requests,
decoded bursts, etc.), but the public API should speak PULP AXI types.

PULP provides typedef macros for the five channels and aggregated
request/response structs (e.g. `AXI_TYPEDEF_*_CHAN_T`, `AXI_TYPEDEF_REQ_T`,
`AXI_TYPEDEF_RESP_T`). These are used broadly in the PULP AXI codebase to
define `axi_req_t`/`axi_resp_t` types that connect modules. citeturn3search0turn2search1

**Boundary direction:**
- **`axi_manager`**: accepts `axi_req_t` from the outside world and emits
  `axi_resp_t` back to the outside world. Internally it injects requests into
  the interconnect and returns responses from the network.
- **`axi_subordinate`**: accepts `axi_req_t` from the interconnect and emits
  `axi_resp_t` back into the interconnect. The external device model (if any)
  can sit behind the subordinate implementation.
- **Interconnect links**: xbar/bridge routing may use a simplified internal
  request/response model but should provide adapters at the boundary that
  pack/unpack `axi_req_t`/`axi_resp_t`.

The lowering should emit or reference a common `axi_pkg` (or local package)
with these typedefs instantiated once per address/data/ID/USER width set,
then use those types consistently across the generated SV classes. citeturn3search0turn2search1

## Core Classes

### `axi_manager`
Represents an initiator that issues read/write transactions.

Key responsibilities:
- Issue transactions (single or burst).
- Observe ordering and exclusive access semantics.
- Consume responses asynchronously.

Key APIs:
- `send_read(addr, length, burst)`
- `send_write(addr, data, burst)`
- `on_response(resp)`

### `axi_subordinate`
Represents a target or memory-mapped peripheral.

Key responsibilities:
- Accept requests and produce responses.
- Enforce burst and alignment rules.
- Model exclusive access (if enabled).

Key APIs:
- `handle_read(req)`
- `handle_write(req)`

### `axi_xbar`
Routes requests from managers to subordinates based on address windows.

Key responsibilities:
- Address decode and routing.
- Enforce window coverage / default error behavior.
- Handle aliasing (multiple windows to same subordinate).
- Provide deterministic arbitration (policy from dialect).

Key APIs:
- `route_request(req)`
- `register_manager(m)`
- `register_subordinate(s)`

### `axi_bridge`
Connects two xbars with address translation.

Key responsibilities:
- Translate address: `downstream_addr = addr - upstream_window.base + downstream_base`.
- Enforce bridge constraints (burst capability, exclusive access, outstanding).
- Forward requests and responses between xbars.

Key APIs:
- `forward_request(req)`
- `forward_response(resp)`

### `axi_alias`
Represents a subordinate alias window.

Key responsibilities:
- Provide alternate window mapping to same subordinate.
- Preserve base subordinate identity.

Key APIs:
- `resolve_target()`

## Adapter Classes

Adapters are explicit classes that transform or validate requests as they pass
through the simulation model. They may be composed between endpoints and xbars
or used internally within bridges.

### `axi_resizer_adapter`

Converts between data widths. This adapter scales burst lengths by the width
ratio (e.g. 128→64 doubles max burst length in beats).

Key responsibilities:
- Adjust request beat size / strobe width.
- Scale burst length constraints.
- Preserve ordering and response routing.

Key APIs:
- `translate_req(req)` / `translate_resp(resp)`

### `axi_burst_splitter_adapter`

Splits long bursts into shorter bursts within capability limits.

Key responsibilities:
- Segment bursts into legal lengths.
- Reassemble responses in order.

Key APIs:
- `split_req(req)` / `merge_resp(resp)`

### `axi_cdc_adapter`

Models clock domain crossing at a semantic level.

Key responsibilities:
- Optionally insert latency/queueing.
- Preserve ordering across domains.

Key APIs:
- `enqueue(req)` / `dequeue(resp)`

### `axi_exclusive_monitor_adapter`

Models exclusive access support for subordinates that do not implement
exclusive semantics directly.

Key responsibilities:
- Track exclusive monitors by address.
- Validate exclusive sequences.

Key APIs:
- `check_exclusive(req)` / `update_exclusive(resp)`

## Request/Response Model

### Request
```
struct axi_req {
  bit is_write;
  uint64 addr;
  byte data[];  // for writes; size == burst length * beat_bytes
  axi_burst burst;
  bit exclusive;
}
```

### Response
```
struct axi_resp {
  axi_resp_code code;
  byte data[];  // for reads
}
```

## Semantics to Preserve

### Address Translation and Coverage
- Xbars route by window match.
- Bridges translate address and then route in downstream xbar.
- If an address is uncovered, emit DECERR unless `default_error` is configured.

### Aliasing
- Multiple windows may map to the same subordinate (explicit alias).
- This is treated as a single target for ordering and exclusive semantics.

### Burst Semantics
- Burst type and length are preserved.
- Subordinates enforce their burst capability; invalid bursts return DECERR.
- Resizers/width adapters are applied prior to simulation (semantic lowering).

### Exclusive Access
- Exclusive transactions must be accepted/denied per subordinate policy.
- Exclusive monitors may be modeled with a simple lock map per address range.

### Ordering
- Preserve ordering per manager and per target.
- Optional transaction policy: expand/serialize/pool may influence
  arbitration and queueing order.

## Lowering Strategy (IR to SV)

### 1. Build Graph
- Parse all `axi4.xbar`, `axi4.bridge`, `axi4.manager`, `axi4.subordinate`.
- Resolve alias chains (collapse to base subordinate).
- Build adjacency of xbars and bridge routes.

### 2. Instantiate Classes
- Create `axi_manager` for each manager op.
- Create `axi_subordinate` for each subordinate op.
- Create `axi_xbar` for each xbar op and register endpoints.
- Create `axi_bridge` for each bridge op and connect xbars.

### 3. Configure Properties
- Set windows, addr_width, data_width, burst_capability, exclusive policy.
- Configure arbitration policy, outstanding limits, default_error behavior.

### 4. Wire Up Simulation
- Managers issue to their root xbar.
- Xbars resolve to subordinates or bridge paths.
- Bridges forward to downstream xbar.

## Performance and Back-Pressure Modeling

The recommended abstraction is **transaction-level with explicit queue
capacity**, which captures architectural back-pressure (full queues,
outstanding limits, arbitration contention) without cycle-accurate signaling.

**Model back-pressure with:**
- **Per-hop queues** at managers, xbars, bridges, and subordinates.
- **Outstanding limits** enforced at endpoints and bridges.
- **Service latency** (deterministic or randomized) per hop.
- **Arbitration policy** consistent with `txn_policy` and xbar settings.

This approach models head-of-line blocking and throughput limits while keeping
simulation fast. Beat-level modeling is only needed if you require mid-burst
stalling or beat interleaving.

### Constructive Implementation Recommendations

**Data flow pipeline**
- Each hop owns an input queue (`in_q`) and optional response queue (`out_q`).
- A request advances only if the next hop queue has space.
- Responses traverse the reverse path through queues.

**Minimal internal request struct**
```
struct tx {
  bit is_write;
  uint64 addr;
  uint32 beat_bytes;
  uint32 beats;
  bit exclusive;
  byte data[];      // optional for reads
  uint64 tag;       // correlation id for responses
}
```

**Routing and translation**
- Precompute xbar window tables at build time.
- Bridges apply address translation once per transaction.

**Adapter implementation**
- Adapters are pure transforms on `tx` (resizer scales beats, splitter may
  segment into multiple `tx`, CDC adds optional latency/queueing).

**Performance tips**
- Avoid per-beat scheduling unless required by a target model.
- Use object pools for `tx` objects to reduce allocations.
- Prefer packed structs or small classes for hot-path data.

## Validation Hooks

Optional checks during lowering:
- Coverage and overlap should already be verified in MLIR passes.
- Validate width/burst/exclusive settings for each class instantiation.

## Implementation Checklists

### Compiler Lowering Checklist

Use this list to make the compiler-side lowering implementable and testable.

1. **PULP AXI type parameters**
   Define widths for `addr`, `data`, `id`, `user`, `strb`, `len`, and the
   exact `axi_pkg` typedef instantiations per bus domain.
2. **IR-to-model mapping**
   Specify how each op (`axi4.xbar`, `axi4.bridge`, adapters, alias) maps to
   model class instantiation and configuration.
3. **Graph construction**
   Build the xbar/bridge graph, resolve alias chains, and compute routing
   tables for window decode.
4. **Boundary adapters**
   Define pack/unpack rules between `axi_req_t`/`axi_resp_t` and internal `tx`.
5. **Model parameter emission**
   Emit configuration tables (windows, widths, burst caps, policies) in a
   deterministic order for reproducibility.
6. **Lowering validation**
   Validate that the MLIR verification passes cover all required invariants,
   and emit diagnostics if model constraints are unmet.

### Simulation Model Checklist

Use this list to implement the SystemVerilog simulation library.

1. **Manager/subordinate external API**
   Specify blocking vs non-blocking calls, response delivery mechanism, and
   how requests are correlated (ID, tag, or queue index).
2. **Internal transaction schema**
   Define the internal `tx` struct (ID, byte enables, protections, QoS,
   burst type/len, exclusive flag) and explicit pack/unpack rules.
3. **Arbitration semantics**
   Provide a deterministic algorithm for `txn_policy` (`expand`, `serialize`,
   `pool`) and arb modes, including tie-break rules.
4. **Outstanding and queue behavior**
   Define queue capacity semantics, outstanding limit enforcement, and
   back-pressure behavior when limits are exceeded.
5. **Burst handling rules**
   Specify alignment rules, wrap behavior, and how resizer scaling affects
   beat size and length in the internal model.
6. **Exclusive access**
   Define monitor granularity, scope (per subordinate vs global), and
   success/failure rules.
7. **Error handling**
   Define DECERR vs SLVERR cases and default error behavior in xbars.
8. **Bridge semantics**
   Clarify whether bridges adapt bursts/exclusive or only validate, and
   define bridge latency semantics.
9. **Determinism**
   If randomized latency is allowed, define seeding. Ensure arbitration is
   deterministic for equal priority.

## Open Questions / Next Steps

- How to represent outstanding transaction limits in a high-level model?
- How to model arbitration fairness vs strict ordering?
- Should the bridge enforce CDC/burst adaptation, or rely on canonicalization?
- Provide a reference SystemVerilog package with base classes?

---

This document is an initial design sketch. It should evolve alongside the
lowering implementation and the SV simulation library API.
