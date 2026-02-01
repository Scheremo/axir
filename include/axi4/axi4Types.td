//===- axi4Types.td - axi4 type definitions ----------------*- tablegen -*-===//
//
// Defines the types of the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_TYPES
#define AXI4_TYPES

include "axi4/axi4Dialect.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// axi4 type definitions
//===----------------------------------------------------------------------===//

class axi4_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<axi4_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

//===----------------------------------------------------------------------===//
// Clock type
//===----------------------------------------------------------------------===//

def axi4_ClockType : axi4_Type<"Clock", "clock"> {
  let summary = "Clock domain type";
  let description = [{
    Represents a clock domain with a name and optional frequency.
    Examples:
    ```mlir
    !axi4.clock
    ```
  }];
}

//===----------------------------------------------------------------------===//
// Endpoint types
//===----------------------------------------------------------------------===//

def axi4_ManagerType : axi4_Type<"Manager", "manager"> {
  let summary = "AXI4 manager (master) endpoint type";
  let description = [{
    Opaque handle to a manager endpoint that initiates transactions.
  }];
}

def axi4_SubordinateType : axi4_Type<"Subordinate", "subordinate"> {
  let summary = "AXI4 subordinate (slave) endpoint type";
  let description = [{
    Opaque handle to a subordinate endpoint that responds to transactions.
  }];
}

//===----------------------------------------------------------------------===//
// Network type
//===----------------------------------------------------------------------===//

def axi4_XbarType : axi4_Type<"Xbar", "xbar"> {
  let summary = "AXI4 crossbar network type";
  let description = [{
    Opaque handle to a crossbar network instance.
  }];
}

#endif // AXI4_TYPES
