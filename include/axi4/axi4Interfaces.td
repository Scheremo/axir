// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Dialect.td - axi4 dialect definition ------------*- tablegen -*-===//
//
// Defines the axi4 dialect for AXI4 interconnect modeling.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_INTERFACE
#define AXI4_INTERFACE

include "axi4/axi4Attrs.td"
include "mlir/IR/OpBase.td"

def Axi4_EndpointOpInterface : OpInterface<"Axi4EndpointOpInterface"> {
  let description = [{
    Implemented by ops that define or transform an AXI endpoint value
    (manager/target and adapters). Provides effective endpoint properties.
  }];

  let methods = [
    InterfaceMethod<
      /*desc=*/"Return the effective clock domain of the endpoint value produced by this op.",
      /*retType=*/"mlir::Value",
      /*methodName=*/"getEffectiveClock",
      /*args=*/(ins)
      // No methodBody here => must be implemented by each model/op.
    >,
    InterfaceMethod<
      /*desc=*/"Return the effective data width (in bits) of the endpoint value produced by this op.",
      /*retType=*/"uint32_t",
      /*methodName=*/"getEffectiveDataWidth",
      /*args=*/(ins)
      // No methodBody here => must be implemented by each model/op.
    >,
    InterfaceMethod<
      /*desc=*/"Return the effective burst capabilites of the endpoint value produced by this op.",
      /*retType=*/"axi4::BurstCapabilityAttr",
      /*methodName=*/"getEffectiveBurstCapabilities",
      /*args=*/(ins)
      // No methodBody here => must be implemented by each model/op.
    >,
    InterfaceMethod<
      /*desc=*/"Return whether this endpoint requires (for managers) or supports (for targets) exclusive access.",
      /*retType=*/"bool",
      /*methodName=*/"getEffectiveExclusiveAccess",
      /*args=*/(ins)
      // No methodBody here => must be implemented by each model/op.
    >,
    InterfaceMethod<
      /*desc=*/"Return the effective outstanding transaction capacity. For managers, this is reads+writes. For targets, this is outstanding.",
      /*retType=*/"uint32_t",
      /*methodName=*/"getEffectiveOutstanding",
      /*args=*/(ins)
      // No methodBody here => must be implemented by each model/op.
    >
  ];
}

#endif // AXI4_INTERFACE
