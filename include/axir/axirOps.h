//===- axirOps.h - axir operation declarations ------------------*- C++ -*-===//
//
// This file declares the axir dialect operations.
//
//===----------------------------------------------------------------------===//

#ifndef AXIR_AXIROPS_H
#define AXIR_AXIROPS_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#define GET_OP_CLASSES
#include "axir/axirOps.h.inc"

#endif // AXIR_AXIROPS_H
