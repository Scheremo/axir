// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Dialect.td - axi4 dialect definition ------------*- tablegen -*-===//
//
// Defines the axi4 dialect for AXI4 interconnect modeling.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_DIALECT
#define AXI4_DIALECT

include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// axi4 dialect definition
//===----------------------------------------------------------------------===//

def axi4_Dialect : Dialect {
  let name = "axi4";
  let summary = "AXI4 declarative interconnect dialect";
  let description = [{
    This dialect models AXI4 interconnects declaratively at a high level.
    It describes participants (managers and targets), address reachability,
    network membership, and implementation constraints.
  }];
  let cppNamespace = "::axi4";

  let useDefaultTypePrinterParser = 1;
  let useDefaultAttributePrinterParser = 1;
}

//===----------------------------------------------------------------------===//
// Base axi4 operation definition
//===----------------------------------------------------------------------===//

class axi4_Op<string mnemonic, list<Trait> traits = []> :
    Op<axi4_Dialect, mnemonic, traits>;

#endif // AXI4_DIALECT
