//===- axi4Passes.td - axi4 pass definitions ---------------*- tablegen -*-===//
//
// Defines the passes for the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_PASSES
#define AXI4_PASSES

include "mlir/Pass/PassBase.td"

def VerifyAxi4Network : Pass<"verify-axi4-network", "mlir::ModuleOp"> {
  let summary = "Verify AXI4 interconnect network topology";
  let description = [{
    Performs network-wide verification of AXI4 interconnects including:

    - Global reachability analysis: Traces paths through bridges to find all
      subordinates reachable from each manager.
    - Cross-bridge coverage verification: Ensures manager access windows are
      fully covered by subordinates, considering paths through bridges.
    - Global address uniqueness: Verifies no two subordinates in the network
      have overlapping address windows (accounting for bridge address translation).
    - Unreachable subordinate detection: Warns about subordinates that cannot
      be reached by any manager through any path.

    This pass should be run after the complete interconnect is defined.
    It complements the local verification done by individual op verifiers.
  }];
  let constructor = "axi4::createVerifyAxi4NetworkPass()";
}

def VerifyAxi4LoopFree : Pass<"verify-axi4-loop-free", "mlir::ModuleOp"> {
  let summary = "Verify AXI4 interconnect is loop-free";
  let description = [{
    Verifies that the AXI4 interconnect does not contain cycles in the
    crossbar/bridge graph. A cycle indicates a potential routing loop and
    is illegal.

    The analysis treats each bridge as a directed edge from its upstream
    crossbar to its downstream crossbar.
  }];
  let constructor = "axi4::createVerifyAxi4LoopFreePass()";
}

def CanonicalizeAxi4Adapters : Pass<"canonicalize-axi4-adapters", "mlir::ModuleOp"> {
  let summary = "Canonicalize AXI4 adapter chains";
  let description = [{
    Normalizes adapter chains to the canonical order:

      resizer -> burst_splitter -> cdc

    This pass rewrites adapter chains while preserving semantics and avoids
    duplicating adapters unless required.
  }];
  let constructor = "axi4::createCanonicalizeAxi4AdaptersPass()";
}

#endif // AXI4_PASSES
