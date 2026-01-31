//===- axirOps.cpp - axir operations implementation -------------*- C++ -*-===//
//
// This file implements the axir dialect operations.
//
//===----------------------------------------------------------------------===//

#include "axir/axirOps.h"
#include "axir/axirDialect.h"

using namespace mlir;
using namespace axir;

//===----------------------------------------------------------------------===//
// ConstantOp
//===----------------------------------------------------------------------===//

LogicalResult ConstantOp::inferReturnTypes(
    MLIRContext *context, std::optional<Location> location, ValueRange operands,
    DictionaryAttr attributes, OpaqueProperties properties, RegionRange regions,
    SmallVectorImpl<Type> &inferredReturnTypes) {
  Adaptor adaptor(operands, attributes, properties, regions);
  auto typedAttr = llvm::dyn_cast<TypedAttr>(adaptor.getValue());
  if (!typedAttr)
    return failure();
  inferredReturnTypes.push_back(typedAttr.getType());
  return success();
}

OpFoldResult ConstantOp::fold(FoldAdaptor adaptor) { return getValue(); }

#define GET_OP_CLASSES
#include "axir/axirOps.cpp.inc"
