//===- axi4Attrs.h - axi4 attribute declarations ----------------*- C++ -*-===//
//
// This file declares the axi4 dialect attributes.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_AXI4ATTRS_H
#define AXI4_AXI4ATTRS_H

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"

#include "axi4/axi4Enums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "axi4/axi4Attrs.h.inc"
#undef GET_ATTRDEF_CLASSES

#endif // AXI4_AXI4ATTRS_H
