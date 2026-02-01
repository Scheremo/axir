//===- axi4Analysis.h - axi4 analysis helpers -------------------*- C++ -*-===//
//
// Shared helper utilities for AXI4 verification and analysis.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_ANALYSIS_H
#define AXI4_ANALYSIS_H

#include "axi4/axi4Attrs.h"
#include "axi4/axi4Interfaces.h"
#include "axi4/axi4Ops.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/SmallVector.h"
#include <string>

namespace axi4 {

struct AddressRange {
  uint64_t base;
  uint64_t end; // exclusive
};

bool rangesOverlap(AddressRange a, AddressRange b);
std::optional<AddressRange> intersectRanges(AddressRange a, AddressRange b);

mlir::FailureOr<uint32_t> inferEffectiveDataWidth(mlir::Value endpoint);
mlir::FailureOr<axi4::BurstCapabilityAttr>
inferEffectiveBurstCapabilites(mlir::Value endpoint);
mlir::FailureOr<axi4::BurstCapabilityAttr>
scaleBurstCapability(axi4::BurstCapabilityAttr cap, uint32_t inputWidth,
                     uint32_t targetWidth, mlir::MLIRContext *ctx,
                     std::string *errorMessage);
mlir::FailureOr<bool> inferEffectiveExclusiveAccess(mlir::Value endpoint);
mlir::FailureOr<uint32_t> inferEffectiveOutstanding(mlir::Value endpoint);
mlir::FailureOr<mlir::Value> inferEffectiveClock(mlir::Value endpoint);

/// Returns empty string if compatible, or a description of incompatibility.
std::string checkBurstCompatibility(axi4::BurstCapabilityAttr mgrBurst,
                                    axi4::BurstCapabilityAttr subBurst);

/// Walk through adapter chain to find the base ManagerOp.
/// Returns nullptr if the chain doesn't lead to a ManagerOp.
axi4::ManagerOp findBaseManagerOp(mlir::Value endpoint);

/// Walk through adapter chain to find the base SubordinateOp or ErrorSubordinateOp.
/// Returns the window attribute if found, nullopt otherwise.
std::optional<axi4::WindowAttr> findBaseSubordinateWindow(mlir::Value endpoint);

/// Get the access windows from a manager (possibly through adapter chain).
llvm::SmallVector<axi4::WindowAttr> getManagerAccessWindows(mlir::Value endpoint);

/// Returns the base subordinate for an alias chain (or the op itself).
mlir::Operation *getAliasBase(mlir::Operation *op);
mlir::Operation *getAliasBase(mlir::Value endpoint);

} // namespace axi4

#endif // AXI4_ANALYSIS_H
