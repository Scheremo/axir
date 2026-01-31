//===- axirTypes.td - axir type definitions ----------------*- tablegen -*-===//
//
// Defines the types of the axir dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXIR_TYPES
#define AXIR_TYPES

include "axir/axirDialect.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// axir type definitions
//===----------------------------------------------------------------------===//

class axir_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<axir_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

// Example custom type - uncomment and modify as needed:
// def axir_CustomType : axir_Type<"Custom", "custom"> {
//   let summary = "custom axir type";
//   let description = "A custom type for the axir dialect.";
//   let parameters = (ins "int64_t":$width);
//   let assemblyFormat = "`<` $width `>`";
// }

#endif // AXIR_TYPES
