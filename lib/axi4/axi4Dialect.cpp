// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Dialect.cpp - axi4 dialect implementation ------------*- C++ -*-===//
//
// This file implements the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#include "axi4/axi4Dialect.h"
#include "axi4/axi4Attrs.h"
#include "axi4/axi4Ops.h"
#include "axi4/axi4Types.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"
#include <optional>

using namespace mlir;
using namespace axi4;

// Include the generated dialect definition
#include "axi4/axi4Dialect.cpp.inc"

//===----------------------------------------------------------------------===//
// Type storage and implementations
//===----------------------------------------------------------------------===//

// Include generated type classes (with storage)
#define GET_TYPEDEF_CLASSES
#include "axi4/axi4Types.cpp.inc"


//===----------------------------------------------------------------------===//
// Attribute storage and implementations
//===----------------------------------------------------------------------===//

// Include generated attribute classes (with storage)
#define GET_ATTRDEF_CLASSES
#include "axi4/axi4Attrs.cpp.inc"

// Include generated enum attribute classes
#include "axi4/axi4Enums.cpp.inc"

// WindowAttr verification
LogicalResult WindowAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                 uint64_t base, uint64_t size) {
  if (size == 0)
    return emitError() << "window size must be greater than 0";
  if (base > UINT64_MAX - size)
    return emitError() << "window base + size overflows uint64_t";
  constexpr uint64_t kAlign = 0x1000;
  if (base % kAlign != 0)
    return emitError() << "window base must be 4KiB aligned";
  if (size % kAlign != 0)
    return emitError() << "window size must be 4KiB aligned";
  return success();
}

// BurstCapabilityAttr verification
LogicalResult
BurstCapabilityAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                            std::optional<uint32_t> incrMaxLen,
                            std::optional<uint32_t> fixedMaxLen,
                            ArrayRef<int32_t> wrapLengths) {

  if (!incrMaxLen && !fixedMaxLen && wrapLengths.empty())
    return emitError() << "at least one burst type must be specified";

  if (incrMaxLen && (*incrMaxLen < 1 || *incrMaxLen > 256))
    return emitError() << "INCR burst max_len must be in range [1, 256]";

  if (fixedMaxLen && (*fixedMaxLen < 1 || *fixedMaxLen > 16))
    return emitError() << "FIXED burst max_len must be in range [1, 16]";

  for (int32_t len : wrapLengths) {
    if (len != 2 && len != 4 && len != 8 && len != 16)
      return emitError() << "WRAP burst length must be 2, 4, 8, or 16";
  }

  return success();
}

// BurstCapabilityAttr parsing
Attribute BurstCapabilityAttr::parse(AsmParser &parser, Type type) {
  if (parser.parseLess())
    return {};

  std::optional<uint32_t> incrMaxLen;
  std::optional<uint32_t> fixedMaxLen;
  SmallVector<int32_t> wrapLengths;

  auto parseKeywordValue = [&]() -> ParseResult {
    StringRef keyword;
    if (failed(parser.parseOptionalKeyword(&keyword)))
      return failure();

    if (keyword == "incr") {
      if (parser.parseEqual())
        return failure();
      uint32_t val;
      if (parser.parseInteger(val))
        return failure();
      incrMaxLen = val;
    } else if (keyword == "fixed") {
      if (parser.parseEqual())
        return failure();
      uint32_t val;
      if (parser.parseInteger(val))
        return failure();
      fixedMaxLen = val;
    } else if (keyword == "wrap") {
      if (parser.parseEqual() || parser.parseLSquare())
        return failure();
      if (parser.parseCommaSeparatedList([&]() -> ParseResult {
            int32_t val;
            if (parser.parseInteger(val))
              return failure();
            wrapLengths.push_back(val);
            return success();
          }))
        return failure();
      if (parser.parseRSquare())
        return failure();
    } else {
      parser.emitError(parser.getCurrentLocation(), "unknown burst type: ")
          << keyword;
      return failure();
    }
    return success();
  };

  if (succeeded(parseKeywordValue())) {
    while (succeeded(parser.parseOptionalComma())) {
      if (failed(parseKeywordValue()))
        return {};
    }
  }

  if (parser.parseGreater())
    return {};

  return BurstCapabilityAttr::get(parser.getContext(), incrMaxLen, fixedMaxLen,
                                  wrapLengths);
}

// BurstCapabilityAttr printing
void BurstCapabilityAttr::print(AsmPrinter &printer) const {
  printer << "<";
  bool first = true;

  if (getIncrMaxLen()) {
    printer << "incr = " << *getIncrMaxLen();
    first = false;
  }

  if (getFixedMaxLen()) {
    if (!first)
      printer << ", ";
    printer << "fixed = " << *getFixedMaxLen();
    first = false;
  }

  if (!getWrapLengths().empty()) {
    if (!first)
      printer << ", ";
    printer << "wrap = [";
    llvm::interleaveComma(getWrapLengths(), printer);
    printer << "]";
  }

  printer << ">";
}

//===----------------------------------------------------------------------===//
// Operation implementations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "axi4/axi4Ops.cpp.inc"

//===----------------------------------------------------------------------===//
// Dialect initialization
//===----------------------------------------------------------------------===//

void axi4Dialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "axi4/axi4Ops.cpp.inc"
      >();

  addTypes<
#define GET_TYPEDEF_LIST
#include "axi4/axi4Types.cpp.inc"
      >();

  addAttributes<
#define GET_ATTRDEF_LIST
#include "axi4/axi4Attrs.cpp.inc"
      >();
}
