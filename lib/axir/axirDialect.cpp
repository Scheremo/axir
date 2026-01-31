//===- axirDialect.cpp - axir dialect implementation ------------*- C++ -*-===//
//
// This file implements the axir dialect.
//
//===----------------------------------------------------------------------===//

#include "axir/axirDialect.h"
#include "axir/axirOps.h"
#include "axir/axirTypes.h"

using namespace mlir;
using namespace axir;

#include "axir/axirDialect.cpp.inc"

void axirDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "axir/axirOps.cpp.inc"
      >();

  addTypes<
#define GET_TYPEDEF_LIST
#include "axir/axirTypes.cpp.inc"
      >();
}
