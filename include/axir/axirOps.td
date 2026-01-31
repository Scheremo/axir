//===- axirOps.td - axir operation definitions -------------*- tablegen -*-===//
//
// Defines the operations of the axir dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXIR_OPS
#define AXIR_OPS

include "axir/axirDialect.td"
include "mlir/IR/BuiltinAttributeInterfaces.td"
include "mlir/IR/OpAsmInterface.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// axir operations
//===----------------------------------------------------------------------===//

def axir_ConstantOp : axir_Op<"constant", [
    Pure,
    ConstantLike,
    DeclareOpInterfaceMethods<InferTypeOpInterface>
  ]> {
  let summary = "constant operation";
  let description = [{
    Produces a constant value.

    Example:
    ```mlir
    %0 = axir.constant 42 : i32
    ```
  }];

  let arguments = (ins TypedAttrInterface:$value);
  let results = (outs AnyType:$result);

  let assemblyFormat = "attr-dict $value";

  let hasFolder = 1;
}

#endif // AXIR_OPS
