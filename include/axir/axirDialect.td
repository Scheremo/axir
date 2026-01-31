//===- axirDialect.td - axir dialect definition ------------*- tablegen -*-===//
//
// Defines the axir dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXIR_DIALECT
#define AXIR_DIALECT

include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// axir dialect definition
//===----------------------------------------------------------------------===//

def axir_Dialect : Dialect {
  let name = "axir";
  let summary = "The axir dialect";
  let description = [{
    This is the axir dialect.
  }];
  let cppNamespace = "::axir";
}

//===----------------------------------------------------------------------===//
// Base axir operation definition
//===----------------------------------------------------------------------===//

class axir_Op<string mnemonic, list<Trait> traits = []> :
    Op<axir_Dialect, mnemonic, traits>;

#endif // AXIR_DIALECT
