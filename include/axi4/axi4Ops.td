//===- axi4Ops.td - axi4 operation definitions -------------*- tablegen -*-===//
//
// Defines the operations of the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_OPS
#define AXI4_OPS

include "axi4/axi4Dialect.td"
include "axi4/axi4Types.td"
include "axi4/axi4Attrs.td"
include "axi4/axi4Interfaces.td"
include "mlir/IR/BuiltinAttributeInterfaces.td"
include "mlir/IR/OpAsmInterface.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Clock Operations
//===----------------------------------------------------------------------===//

def axi4_ClockOp : axi4_Op<"clock", []> {
  let summary = "Declares a clock domain";
  let description = [{
    Declares an AXI4 clock domain with optional frequency and relationship info.

    Example:
    ```mlir
    %sys_clk = axi4.clock
    %cpu_clk = axi4.clock
    %periph_clk = axi4.clock
    ```
  }];

  let arguments = (ins
    SymbolNameAttr:$sym_name,
    OptionalAttr<UI64Attr>:$freq
  );

  let results = (outs axi4_ClockType:$result);

  let assemblyFormat = [{
    $sym_name attr-dict
  }];
}

//===----------------------------------------------------------------------===//
// Endpoint Operations
//===----------------------------------------------------------------------===//

def axi4_ManagerOp : axi4_Op<"manager", [Axi4_EndpointOpInterface]> {
  let summary = "Declares a manager (initiator) endpoint";
  let description = [{
    Declares an AXI4 manager endpoint that initiates transactions.

    Example:
    ```mlir
    %cpu = axi4.manager {
      access = [#axi4.window<base = 0, size = 0x40000000>],
      data_width = 64,
      clock = !axi4.clock<"sys_clk">,
      outstanding_reads = 8,
      outstanding_writes = 4,
      burst_capability = #axi4.burst_capability<incr = 16>
    }
    ```
  }];

  let arguments = (ins
    // Required attributes
    axi4_ClockType:$clock,
    ArrayAttr:$access,
    UI32Attr:$data_width,
    UI32Attr:$outstanding_reads,
    UI32Attr:$outstanding_writes,
    axi4_BurstCapabilityAttr:$burst_capability,
    // Optional attributes
    DefaultValuedAttr<BoolAttr, "true">:$read,
    DefaultValuedAttr<BoolAttr, "true">:$write,
    DefaultValuedAttr<BoolAttr, "false">:$exclusive,
    OptionalAttr<UI32Attr>:$reorder_depth,
    OptionalAttr<UI32Attr>:$write_reorder_depth
  );

  let results = (outs axi4_ManagerType:$result);

  let assemblyFormat = [{
    $clock attr-dict
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

def axi4_SubordinateOp : axi4_Op<"subordinate", [Axi4_EndpointOpInterface]> {
  let summary = "Declares a subordinate (target) endpoint";
  let description = [{
    Declares an AXI4 subordinate endpoint that responds to transactions.

    Example:
    ```mlir
    %sram = axi4.subordinate %clk : !axi4.clock<"sys_clk"> {
      window = #axi4.window<base = 0, size = 0x10000>,
      data_width = 64,
      outstanding = 4,
      burst_capability = #axi4.burst_capability<incr = 256>
    }
    ```
  }];

  let arguments = (ins
    // Required operands
    axi4_ClockType:$clock,
    // Required attributes
    axi4_WindowAttr:$window,
    UI32Attr:$data_width,
    UI32Attr:$outstanding,
    axi4_BurstCapabilityAttr:$burst_capability,
    // Optional attributes
    DefaultValuedAttr<BoolAttr, "true">:$read,
    DefaultValuedAttr<BoolAttr, "true">:$write,
    DefaultValuedAttr<BoolAttr, "false">:$exclusive,
    DefaultValuedAttr<BoolAttr, "false">:$reorders_reads,
    DefaultValuedAttr<BoolAttr, "false">:$reorders_writes
  );

  let results = (outs axi4_SubordinateType:$result);

  let assemblyFormat = [{
    $clock attr-dict
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Alias Operations
//===----------------------------------------------------------------------===//

def axi4_AliasOp : axi4_Op<"alias", [Axi4_EndpointOpInterface,
  TypesMatchWith<"input and result types match", "input", "result", "$_self">]> {
  let summary = "Declares an alias window for a subordinate";
  let description = [{
    Declares an additional address window that maps to the same subordinate
    target. Aliases make overlapping address regions explicit.

    Example:
    ```mlir
    %alias = axi4.alias %sub {
      window = #axi4.window<base = 0x1600_0000, size = 0x1000>
    }
    ```
  }];

  let arguments = (ins
    axi4_SubordinateType:$input,
    axi4_WindowAttr:$window
  );

  let results = (outs axi4_SubordinateType:$result);

  let assemblyFormat = [{
    $input attr-dict
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Network Operations
//===----------------------------------------------------------------------===//

def axi4_XbarOp : axi4_Op<"xbar", [AttrSizedOperandSegments]> {
  let summary = "Declares a crossbar network";
  let description = [{
    Declares an AXI4 crossbar network that routes transactions between
    managers and subordinates.

    Example:
    ```mlir
    %bus = axi4.xbar(%clk : !axi4.clock,
                     managers = [%cpu, %dma],
                     subordinates = [%sram, %dram]) {
      addr_width = 32,
      data_width = 64
    }
    ```
  }];

  let arguments = (ins
    // Required operands
    axi4_ClockType:$clock,
    Variadic<axi4_ManagerType>:$managers,
    Variadic<axi4_SubordinateType>:$subordinates,
    // Required attributes
    UI32Attr:$addr_width,
    UI32Attr:$data_width,
    // Optional attributes
    OptionalAttr<axi4_ErrorResponseAttr>:$default_error,
    DefaultValuedAttr<axi4_ArbitrationAttr, "axi4::Arbitration::RoundRobin">:$arb,
    DefaultValuedAttr<axi4_TxnPolicyAttr, "axi4::TxnPolicy::Expand">:$txn_policy,
    OptionalAttr<UI32Attr>:$pool_size,
    DefaultValuedAttr<axi4_CapacityCheckAttr, "axi4::CapacityCheck::Warn">:$capacity_check,
    DefaultValuedAttr<axi4_ExclusiveModeAttr, "axi4::ExclusiveMode::Strict">:$exclusive_mode,
    DefaultValuedAttr<axi4_QosModeAttr, "axi4::QosMode::Passthrough">:$qos_mode
  );

  let results = (outs axi4_XbarType:$result);

  let assemblyFormat = [{
    `(` $clock (`,` `managers` `=` `[` $managers^ `]`)? (`,` `subordinates` `=` `[` $subordinates^ `]`)? `)` attr-dict
  }];

  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Adapter Operations
//===----------------------------------------------------------------------===//

def axi4_ResizerOp : axi4_Op<"resizer", [Axi4_EndpointOpInterface,
 TypesMatchWith<"input and result types match",
    "input", "result", "$_self">]> {
  let summary = "Converts input interface data width to different data width";
  let description = [{
    Converts an endpoint from a data width to a different data width.
    Can be applied to either managers or targets.

    Example:
    ```mlir
    %wide = axi4.resizer %narrow { target_width = 128 : ui32 }
    ```
  }];

  let arguments = (ins
    AnyType:$input,
    UI32Attr:$target_width
  );

  let results = (outs AnyType:$result);

  let assemblyFormat = [{
    $input attr-dict `:` type($input)
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

def axi4_BurstSplitterOp : axi4_Op<"burst_splitter", [Axi4_EndpointOpInterface]> {
  let summary = "Splits long bursts into shorter bursts";
  let description = [{
    Splits long bursts from a manager into shorter bursts that fit
    the subordinate's burst capability.

    Example:
    ```mlir
    %split = axi4.burst_splitter %mgr {
      burst_capability = #axi4.burst_capability<incr = 16>
    }
    ```
  }];

  let arguments = (ins
    axi4_ManagerType:$input,
    axi4_BurstCapabilityAttr:$burst_capability
  );

  let results = (outs axi4_ManagerType:$result);

  let assemblyFormat = [{
    $input attr-dict
  }];


  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

def axi4_CdcOp : axi4_Op<"cdc", [Axi4_EndpointOpInterface,
    TypesMatchWith<"input and result types match",
    "input", "result", "$_self">]> {
  let summary = "Inserts clock domain crossing logic";
  let description = [{
    Inserts clock domain crossing logic to move an endpoint
    from one clock domain to another.

    Example:
    ```mlir
    %crossed = axi4.cdc %endpoint, %target_clk : !axi4.manager, !axi4.clock<"fast_clk">
    ```
  }];

  let arguments = (ins
    AnyType:$input,
    axi4_ClockType:$target_clock,
    DefaultValuedAttr<UI32Attr, "4">:$depth,
    OptionalAttr<axi4_CdcModeAttr>:$mode
  );

  let results = (outs AnyType:$result);

  let assemblyFormat = [{
    $input `,` $target_clock attr-dict `:` type($input)
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

def axi4_ErrorSubordinateOp : axi4_Op<"error_subordinate", [Axi4_EndpointOpInterface]> {
  let summary = "Creates a synthetic subordinate that responds with errors";
  let description = [{
    Creates a subordinate that responds to all transactions with an error.
    Useful for handling unmapped address regions.

    Example:
    ```mlir
    %err = axi4.error_subordinate %clk : !axi4.clock<"sys_clk"> {
      window = #axi4.window<base = 0xFFFF0000, size = 0x10000>,
      data_width = 64 : ui32
    }
    ```
  }];

  let arguments = (ins
    axi4_ClockType:$clock,
    axi4_WindowAttr:$window,
    UI32Attr:$data_width,
    DefaultValuedAttr<axi4_ErrorResponseAttr, "axi4::ErrorResponse::DecErr">:$response,
    OptionalAttr<UI32Attr>:$outstanding
  );

  let results = (outs axi4_SubordinateType:$result);

  let assemblyFormat = [{
    $clock attr-dict
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

def axi4_ExclusiveMonitorOp : axi4_Op<"exclusive_monitor", [Axi4_EndpointOpInterface]> {
  let summary = "Wraps a non-exclusive subordinate with exclusive support";
  let description = [{
    Wraps a subordinate that doesn't natively support exclusive access
    with an exclusive monitor that tracks reservations.

    Example:
    ```mlir
    %excl_mem = axi4.exclusive_monitor %mem {
      granularity = 64 : ui32,
      entries = 8 : ui32
    }
    ```
  }];

  let arguments = (ins
    axi4_SubordinateType:$input,
    UI32Attr:$granularity,
    UI32Attr:$entries,
    DefaultValuedAttr<axi4_MonitorScopeAttr, "axi4::MonitorScope::Local">:$scope
  );

  let results = (outs axi4_SubordinateType:$result);

  let assemblyFormat = [{
    $input attr-dict
  }];

  let extraClassDeclaration = [{
    mlir::Value getEffectiveClock();
    uint32_t getEffectiveDataWidth();
    axi4::BurstCapabilityAttr getEffectiveBurstCapabilities();
    bool getEffectiveExclusiveAccess();
    uint32_t getEffectiveOutstanding();
  }];

  let hasVerifier = 1;
}

//===----------------------------------------------------------------------===//
// Bridge Operations
//===----------------------------------------------------------------------===//

def axi4_BridgeOp : axi4_Op<"bridge", []> {
  let summary = "Creates a bidirectional connection between two crossbars";
  let description = [{
    Creates a bridge connecting an upstream crossbar to a downstream crossbar.
    The bridge handles clock domain crossing and width conversion internally.

    Example:
    ```mlir
    axi4.bridge %upstream, %downstream {
      upstream_window = #axi4.window<base = 0x40000000, size = 0x100000>,
      downstream_base = 0 : ui64,
      outstanding = 8 : ui32
    }
    ```
  }];

  let arguments = (ins
    axi4_XbarType:$upstream,
    axi4_XbarType:$downstream,
    axi4_WindowAttr:$upstream_window,
    UI64Attr:$downstream_base,
    // Optional attributes
    OptionalAttr<SymbolNameAttr>:$sym_name,
    DefaultValuedAttr<UI32Attr, "16">:$outstanding,
    OptionalAttr<axi4_BurstCapabilityAttr>:$burst_capability,
    DefaultValuedAttr<axi4_BridgeExclusiveAttr, "axi4::BridgeExclusive::Block">:$exclusive,
    DefaultValuedAttr<UI32Attr, "4">:$cdc_depth
  );

  let assemblyFormat = [{
    $upstream `,` $downstream attr-dict
  }];

  let hasVerifier = 1;
}

#endif // AXI4_OPS
