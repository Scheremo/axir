// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Attrs.td - axi4 attribute definitions -----------*- tablegen -*-===//
//
// Defines the attributes of the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_ATTRS
#define AXI4_ATTRS

include "axi4/axi4Dialect.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"

//===----------------------------------------------------------------------===//
// axi4 attribute definitions
//===----------------------------------------------------------------------===//

class axi4_Attr<string name, string attrMnemonic, list<Trait> traits = []>
    : AttrDef<axi4_Dialect, name, traits> {
  let mnemonic = attrMnemonic;
}

//===----------------------------------------------------------------------===//
// Window attribute - represents an address window with base and size
//===----------------------------------------------------------------------===//

def axi4_WindowAttr : axi4_Attr<"Window", "window"> {
  let summary = "Address window with base and size";
  let description = [{
    Represents a contiguous address region defined by base address and size.
    The effective address range is [base, base + size) (half-open interval).

    Example:
    ```mlir
    #axi4.window<base = 0x1000, size = 0x100>
    ```
  }];

  let parameters = (ins
    "uint64_t":$base,
    "uint64_t":$size
  );

  let assemblyFormat = "`<` `base` `=` $base `,` `size` `=` $size `>`";

  let genVerifyDecl = 1;
}

//===----------------------------------------------------------------------===//
// Burst capability attribute
//===----------------------------------------------------------------------===//

def axi4_BurstCapabilityAttr : axi4_Attr<"BurstCapability", "burst_capability"> {
  let summary = "Combined burst capability";
  let description = [{
    Describes the burst types and lengths an endpoint supports.
    At least one burst type must be specified.

    Example:
    ```mlir
    #axi4.burst_capability<incr = 256, fixed = 16, wrap = [2, 4, 8, 16]>
    ```
  }];

  let parameters = (ins
    OptionalParameter<"std::optional<uint32_t>">:$incrMaxLen,
    OptionalParameter<"std::optional<uint32_t>">:$fixedMaxLen,
    OptionalArrayRefParameter<"int32_t">:$wrapLengths
  );

  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;
}

//===----------------------------------------------------------------------===//
// Enums
//===----------------------------------------------------------------------===//

def axi4_ErrorResponseEnum : I32EnumAttr<"ErrorResponse",
    "AXI error response type",
    [
      I32EnumAttrCase<"DecErr", 0, "decerr">,
      I32EnumAttrCase<"SlvErr", 1, "slverr">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_ErrorResponseAttr : AttrDef<axi4_Dialect, "ErrorResponse"> {
  let mnemonic = "error_response";
  let parameters = (ins "axi4::ErrorResponse":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::ErrorResponse";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::ErrorResponseAttr::get($_builder.getContext(), $0)";
}

def axi4_ArbitrationEnum : I32EnumAttr<"Arbitration",
    "Crossbar arbitration policy",
    [
      I32EnumAttrCase<"RoundRobin", 0, "rr">,
      I32EnumAttrCase<"WeightedRoundRobin", 1, "wrr">,
      I32EnumAttrCase<"Priority", 2, "priority">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_ArbitrationAttr : AttrDef<axi4_Dialect, "Arbitration"> {
  let mnemonic = "arbitration";
  let parameters = (ins "axi4::Arbitration":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::Arbitration";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::ArbitrationAttr::get($_builder.getContext(), $0)";
}

def axi4_TxnPolicyEnum : I32EnumAttr<"TxnPolicy",
    "Transaction ID policy",
    [
      I32EnumAttrCase<"Expand", 0, "expand">,
      I32EnumAttrCase<"Serialize", 1, "serialize">,
      I32EnumAttrCase<"Pool", 2, "pool">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;  // Don't auto-generate the attribute
}

def axi4_TxnPolicyAttr : AttrDef<axi4_Dialect, "TxnPolicy"> {
  let mnemonic = "txn_policy";
  let parameters = (ins "axi4::TxnPolicy":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::TxnPolicy";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::TxnPolicyAttr::get($_builder.getContext(), $0)";
}

def axi4_CapacityCheckEnum : I32EnumAttr<"CapacityCheck",
    "Capacity verification mode",
    [
      I32EnumAttrCase<"Warn", 0, "warn">,
      I32EnumAttrCase<"Error", 1, "error">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_CapacityCheckAttr : AttrDef<axi4_Dialect, "CapacityCheck"> {
  let mnemonic = "capacity_check";
  let parameters = (ins "axi4::CapacityCheck":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::CapacityCheck";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::CapacityCheckAttr::get($_builder.getContext(), $0)";
}

def axi4_ExclusiveModeEnum : I32EnumAttr<"ExclusiveMode",
    "Exclusive access handling mode",
    [
      I32EnumAttrCase<"Strict", 0, "strict">,
      I32EnumAttrCase<"Advisory", 1, "advisory">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_ExclusiveModeAttr : AttrDef<axi4_Dialect, "ExclusiveMode"> {
  let mnemonic = "exclusive_mode";
  let parameters = (ins "axi4::ExclusiveMode":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::ExclusiveMode";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::ExclusiveModeAttr::get($_builder.getContext(), $0)";
}

def axi4_QosModeEnum : I32EnumAttr<"QosMode",
    "QoS handling mode",
    [
      I32EnumAttrCase<"Passthrough", 0, "passthrough">,
      I32EnumAttrCase<"Fixed", 1, "fixed">,
      I32EnumAttrCase<"Remap", 2, "remap">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_QosModeAttr : AttrDef<axi4_Dialect, "QosMode"> {
  let mnemonic = "qos_mode";
  let parameters = (ins "axi4::QosMode":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::QosMode";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::QosModeAttr::get($_builder.getContext(), $0)";
}

def axi4_AccessEnforcementEnum : I32EnumAttr<"AccessEnforcement",
    "Access window enforcement mode",
    [
      I32EnumAttrCase<"None", 0, "none">,
      I32EnumAttrCase<"Filter", 1, "filter">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_AccessEnforcementAttr : AttrDef<axi4_Dialect, "AccessEnforcement"> {
  let mnemonic = "access_enforcement";
  let parameters = (ins "axi4::AccessEnforcement":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::AccessEnforcement";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::AccessEnforcementAttr::get($_builder.getContext(), $0)";
}

def axi4_CdcModeEnum : I32EnumAttr<"CdcMode",
    "CDC implementation mode",
    [
      I32EnumAttrCase<"Async", 0, "async">,
      I32EnumAttrCase<"Sync", 1, "sync">,
      I32EnumAttrCase<"Handshake", 2, "handshake">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_CdcModeAttr : AttrDef<axi4_Dialect, "CdcMode"> {
  let mnemonic = "cdc_mode";
  let parameters = (ins "axi4::CdcMode":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::CdcMode";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::CdcModeAttr::get($_builder.getContext(), $0)";
}

def axi4_BridgeExclusiveEnum : I32EnumAttr<"BridgeExclusive",
    "Bridge exclusive handling",
    [
      I32EnumAttrCase<"Block", 0, "block">,
      I32EnumAttrCase<"Passthrough", 1, "passthrough">,
      I32EnumAttrCase<"Terminate", 2, "terminate">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_BridgeExclusiveAttr : AttrDef<axi4_Dialect, "BridgeExclusive"> {
  let mnemonic = "bridge_exclusive";
  let parameters = (ins "axi4::BridgeExclusive":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::BridgeExclusive";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::BridgeExclusiveAttr::get($_builder.getContext(), $0)";
}

def axi4_MonitorScopeEnum : I32EnumAttr<"MonitorScope",
    "Exclusive monitor scope",
    [
      I32EnumAttrCase<"Local", 0, "local">,
      I32EnumAttrCase<"Global", 1, "global">
    ]> {
  let cppNamespace = "::axi4";
  let genSpecializedAttr = 0;
}

def axi4_MonitorScopeAttr : AttrDef<axi4_Dialect, "MonitorScope"> {
  let mnemonic = "monitor_scope";
  let parameters = (ins "axi4::MonitorScope":$value);
  let assemblyFormat = "`<` $value `>`";
  let returnType = "axi4::MonitorScope";
  let convertFromStorage = "$_self.getValue()";
  let constBuilderCall = "axi4::MonitorScopeAttr::get($_builder.getContext(), $0)";
}

#endif // AXI4_ATTRS
