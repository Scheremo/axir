//===- axi4Interfaces.h - axi4 interface declarations ---------------------*- C++ -*-===//
//
// This file declares the axi4 dialect types.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_AXI4INTERFACE_H
#define AXI4_AXI4INTERFACE_H

#include "mlir/IR/Types.h"
#include "mlir/IR/OpDefinition.h"
#include "axi4/axi4Attrs.h"

#define GET_OP_INTERFACE_CLASSES
#include "axi4/axi4Interfaces.h.inc"
#undef GET_OP_INTERFACE_CLASSES

#endif // AXI4_AXI4INTERFACE_H
