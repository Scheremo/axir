// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Ops.h - axi4 operation declarations ------------------*- C++ -*-===//
//
// This file declares the axi4 dialect operations.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_AXI4OPS_H
#define AXI4_AXI4OPS_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "axi4/axi4Attrs.h"
#include "axi4/axi4Types.h"
#include "axi4/axi4Interfaces.h"

#define GET_OP_CLASSES
#include "axi4/axi4Ops.h.inc"

#endif // AXI4_AXI4OPS_H
