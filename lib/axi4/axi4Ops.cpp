//===- axi4Ops.cpp - axi4 operations implementation -------------*- C++ -*-===//
//
// This file implements the axi4 dialect operations.
//
//===----------------------------------------------------------------------===//

#include "axi4/axi4Ops.h"
#include "axi4/axi4Analysis.h"
#include "axi4/axi4Attrs.h"
#include "axi4/axi4Dialect.h"
#include "axi4/axi4Interfaces.h"
#include "axi4/axi4Types.h"
#include "mlir/IR/Diagnostics.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;
using namespace axi4;

namespace axi4 {

}; // namespace axi4

//===----------------------------------------------------------------------===//
// ManagerOp
//===----------------------------------------------------------------------===//

Value ManagerOp::getEffectiveClock() {
  // Since this is a base endpoint, "effective" == declared.
  return getClock();
}

uint32_t ManagerOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return static_cast<uint32_t>(getDataWidth());
}

axi4::BurstCapabilityAttr ManagerOp::getEffectiveBurstCapabilities() {
  // Since this is a base endpoint, "effective" == declared.
  return static_cast<axi4::BurstCapabilityAttr>(getBurstCapability());
}

bool ManagerOp::getEffectiveExclusiveAccess() {
  // Since this is a base endpoint, "effective" == declared.
  return getExclusive();
}

uint32_t ManagerOp::getEffectiveOutstanding() {
  // For managers, total outstanding is reads + writes.
  return getOutstandingReads() + getOutstandingWrites();
}

LogicalResult ManagerOp::verify() {
  // access must be non-empty
  if (getAccess().empty())
    return emitOpError("access windows must not be empty");

  // Validate each window in access
  for (Attribute attr : getAccess()) {
    auto window = dyn_cast<WindowAttr>(attr);
    if (!window)
      return emitOpError("access must contain only window attributes");
  }

  // At least one of read or write must be true
  if (!getRead() && !getWrite())
    return emitOpError("at least one of 'read' or 'write' must be true");

  // If read=true: outstanding_reads >= 1
  if (getRead() && getOutstandingReads() < 1)
    return emitOpError("outstanding_reads must be >= 1 when read=true");

  // If write=true: outstanding_writes >= 1
  if (getWrite() && getOutstandingWrites() < 1)
    return emitOpError("outstanding_writes must be >= 1 when write=true");

  // If read=false: outstanding_reads should be 0
  if (!getRead() && getOutstandingReads() != 0)
    return emitOpError("outstanding_reads must be 0 when read=false");

  // If write=false: outstanding_writes should be 0
  if (!getWrite() && getOutstandingWrites() != 0)
    return emitOpError("outstanding_writes must be 0 when write=false");

  // Validate reorder_depth if present
  if (auto reorderDepth = getReorderDepth()) {
    if (*reorderDepth < 1 || *reorderDepth > getOutstandingReads())
      return emitOpError(
          "reorder_depth must be in range [1, outstanding_reads]");
  }

  // Validate write_reorder_depth if present
  if (auto writeReorderDepth = getWriteReorderDepth()) {
    if (*writeReorderDepth < 1 || *writeReorderDepth > getOutstandingWrites())
      return emitOpError(
          "write_reorder_depth must be in range [1, outstanding_writes]");
  }

  // Validate data_width is power of 2 and reasonable
  uint32_t dw = getDataWidth();
  if (dw != 32 && dw != 64 && dw != 128 && dw != 256 && dw != 512)
    return emitOpError("data_width must be 32, 64, 128, 256, or 512");

  return success();
}

//===----------------------------------------------------------------------===//
// SubordinateOp
//===----------------------------------------------------------------------===//

Value SubordinateOp::getEffectiveClock() {
  // Since this is a base endpoint, "effective" == declared.
  return getClock();
}

axi4::BurstCapabilityAttr SubordinateOp::getEffectiveBurstCapabilities() {
  // Since this is a base endpoint, "effective" == declared.
  return static_cast<axi4::BurstCapabilityAttr>(getBurstCapability());
}

uint32_t SubordinateOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return static_cast<uint32_t>(getDataWidth());
}

bool SubordinateOp::getEffectiveExclusiveAccess() {
  // Since this is a base endpoint, "effective" == declared.
  return getExclusive();
}

uint32_t SubordinateOp::getEffectiveOutstanding() {
  // For subordinates, outstanding is the declared value.
  return getOutstanding();
}

LogicalResult SubordinateOp::verify() {
  // At least one of read or write must be true
  if (!getRead() && !getWrite())
    return emitOpError("at least one of 'read' or 'write' must be true");

  // outstanding must be >= 1
  if (getOutstanding() < 1)
    return emitOpError("outstanding must be >= 1");

  // Validate data_width
  uint32_t dw = getDataWidth();
  if (dw != 32 && dw != 64 && dw != 128 && dw != 256 && dw != 512)
    return emitOpError("data_width must be 32, 64, 128, 256, or 512");

  return success();
}

//===----------------------------------------------------------------------===//
// XbarOp
//===----------------------------------------------------------------------===//

LogicalResult XbarOp::verify() {
  // Validate data_width
  uint32_t dw = getDataWidth();
  if (dw != 32 && dw != 64 && dw != 128 && dw != 256 && dw != 512)
    return emitOpError("data_width must be 32, 64, 128, 256, or 512");

  // Validate addr_width
  uint32_t aw = getAddrWidth();
  if (aw < 12 || aw > 64)
    return emitOpError("addr_width must be in range [12, 64]");

  // If txn_policy is pool, pool_size is required
  if (getTxnPolicy() == TxnPolicy::Pool && !getPoolSize())
    return emitOpError("pool_size is required when txn_policy is 'pool'");

  // If pool_size is specified, txn_policy should be pool
  if (getPoolSize() && getTxnPolicy() != TxnPolicy::Pool)
    return emitOpError(
        "pool_size should only be specified when txn_policy is 'pool'");

  // Verify Manager data width matches
  FailureOr<uint32_t> mgrWidth;
  auto xbarWidth = getDataWidth();

  for (auto mgr : getManagers()) {
    mgrWidth = inferEffectiveDataWidth(mgr);

    if (failed(mgrWidth)) {
      return mlir::emitError(mgr.getLoc()) << "Failed to compare data widths!";
    }

    if (mgrWidth.value() != getDataWidth()) {
      auto diag = emitOpError() << "manager data width mismatch";
      diag.attachNote(mgr.getLoc())
          << "Manager defines data width as " << mgrWidth.value();
      diag.attachNote(this->getLoc())
          << "XBar defines data width as " << xbarWidth;
      return failure();
    }
  }

  // Verify Subordinate data width matches
  FailureOr<uint32_t> subWidth;
  for (auto sub : getSubordinates()) {
    subWidth = inferEffectiveDataWidth(sub);

    if (failed(subWidth)) {
      return mlir::emitError(sub.getLoc()) << "Failed to compare data widths!";
    }

    if (subWidth.value() != getDataWidth()) {
      auto diag = emitOpError() << "subordinate data width mismatch";
      diag.attachNote(sub.getLoc())
          << "Subordinate defines data width as " << subWidth.value();
      diag.attachNote(this->getLoc())
          << "XBar defines data width as " << xbarWidth;
      return failure();
    }
  }

  // Verify Manager clock domains match xbar clock
  Value xbarClock = getClock();
  for (auto mgr : getManagers()) {
    auto mgrClock = inferEffectiveClock(mgr);
    if (failed(mgrClock)) {
      return mlir::emitError(mgr.getLoc()) << "Failed to determine clock domain!";
    }

    if (mgrClock.value() != xbarClock) {
      auto diag = emitOpError() << "manager clock domain mismatch";
      diag.attachNote(mgr.getLoc())
          << "manager has different effective clock domain";
      diag.attachNote(getLoc())
          << "xbar clock domain defined here; use axi4.cdc to cross clock domains";
      return failure();
    }
  }

  // Verify Subordinate clock domains match xbar clock
  for (auto sub : getSubordinates()) {
    auto subClock = inferEffectiveClock(sub);
    if (failed(subClock)) {
      return mlir::emitError(sub.getLoc()) << "Failed to determine clock domain!";
    }

    if (subClock.value() != xbarClock) {
      auto diag = emitOpError() << "subordinate clock domain mismatch";
      diag.attachNote(sub.getLoc())
          << "subordinate has different effective clock domain";
      diag.attachNote(getLoc())
          << "xbar clock domain defined here; use axi4.cdc to cross clock domains";
      return failure();
    }
  }

  // Verify subordinate windows are disjoint
  auto subordinates = getSubordinates();
  auto managers = getManagers();

  // Collect all subordinate windows with their indices
  llvm::SmallVector<std::pair<size_t, WindowAttr>> subordinateWindows;
  for (size_t i = 0; i < subordinates.size(); ++i) {
    auto window = findBaseSubordinateWindow(subordinates[i]);
    if (window)
      subordinateWindows.push_back({i, *window});
  }

  // Sort subordinate windows by base address - O(S log S)
  // This sorted order is reused for both disjointness and coverage checks
  llvm::sort(subordinateWindows, [](const auto &a, const auto &b) {
    return a.second.getBase() < b.second.getBase();
  });

  // Check adjacent pairs for overlap - O(S) after sorting
  // If windows are sorted by base, overlap can only occur between adjacent pairs
  for (size_t i = 0; i + 1 < subordinateWindows.size(); ++i) {
    const auto &curr = subordinateWindows[i];
    const auto &next = subordinateWindows[i + 1];
    // Overlap if curr.end > next.base (since they're sorted by base)
    uint64_t currEnd = curr.second.getBase() + curr.second.getSize();
    if (currEnd > next.second.getBase()) {
      Operation *currBase = getAliasBase(subordinates[curr.first].getDefiningOp());
      Operation *nextBase = getAliasBase(subordinates[next.first].getDefiningOp());
      if (currBase == nextBase)
        continue;
      auto diag = emitOpError() << "subordinate windows overlap";
      diag.attachNote(subordinates[curr.first].getLoc())
          << "first subordinate window: [0x"
          << llvm::Twine::utohexstr(curr.second.getBase()) << ", 0x"
          << llvm::Twine::utohexstr(currEnd) << ")";
      diag.attachNote(subordinates[next.first].getLoc())
          << "second subordinate window: [0x"
          << llvm::Twine::utohexstr(next.second.getBase()) << ", 0x"
          << llvm::Twine::utohexstr(next.second.getBase() +
                                    next.second.getSize())
          << ")";
      return failure();
    }
  }

  // Note: Coverage verification and unreachable subordinate warnings are now
  // handled by the verify-axi4-network pass, which can consider cross-bridge paths.

  // Build mapping: subordinate index -> list of manager indices that can access it
  // A manager can access a subordinate if any of the manager's access windows
  // overlap with the subordinate's window.
  llvm::DenseMap<size_t, llvm::SmallVector<size_t>> subordinateToManagers;

  for (size_t subIdx = 0; subIdx < subordinates.size(); ++subIdx) {
    auto subordinateWindow = findBaseSubordinateWindow(subordinates[subIdx]);
    if (!subordinateWindow)
      continue;

    llvm::SmallVector<size_t> accessingManagers;

    for (size_t mgrIdx = 0; mgrIdx < managers.size(); ++mgrIdx) {
      auto mgrWindows = getManagerAccessWindows(managers[mgrIdx]);

      for (const auto &mgrWindow : mgrWindows) {
        AddressRange mgrRange{mgrWindow.getBase(),
                              mgrWindow.getBase() + mgrWindow.getSize()};
        AddressRange subRange{subordinateWindow->getBase(),
                              subordinateWindow->getBase() +
                                  subordinateWindow->getSize()};
        if (rangesOverlap(mgrRange, subRange)) {
          accessingManagers.push_back(mgrIdx);
          break;
        }
      }
    }

    subordinateToManagers[subIdx] = std::move(accessingManagers);
  }

  // Verify burst capability compatibility for each manager-subordinate pair
  for (const auto &[subIdx, mgrIndices] : subordinateToManagers) {
    auto subBurst = inferEffectiveBurstCapabilites(subordinates[subIdx]);
    if (failed(subBurst))
      continue; // Skip if we can't determine subordinate burst capabilities

    for (size_t mgrIdx : mgrIndices) {
      auto mgrBurst = inferEffectiveBurstCapabilites(managers[mgrIdx]);
      if (failed(mgrBurst))
        continue; // Skip if we can't determine manager burst capabilities

      std::string incompatibility =
          checkBurstCompatibility(*mgrBurst, *subBurst);
      if (!incompatibility.empty()) {
        auto diag = emitOpError() << "burst capability mismatch: "
                                  << incompatibility;
        diag.attachNote(managers[mgrIdx].getLoc()) << "manager defined here";
        diag.attachNote(subordinates[subIdx].getLoc()) << "subordinate defined here";
        return failure();
      }
    }
  }

  // Verify exclusive access compatibility when exclusive_mode is strict
  if (getExclusiveMode() == ExclusiveMode::Strict) {
    for (const auto &[subIdx, mgrIndices] : subordinateToManagers) {
      auto subExcl = inferEffectiveExclusiveAccess(subordinates[subIdx]);
      if (failed(subExcl))
        continue; // Skip if we can't determine subordinate exclusive support

      for (size_t mgrIdx : mgrIndices) {
        auto mgrExcl = inferEffectiveExclusiveAccess(managers[mgrIdx]);
        if (failed(mgrExcl))
          continue; // Skip if we can't determine manager exclusive requirement

        if (*mgrExcl && !*subExcl) {
          auto diag = emitOpError()
                      << "exclusive access mismatch: manager requires "
                         "exclusive access but subordinate does not support it";
          diag.attachNote(managers[mgrIdx].getLoc())
              << "manager with exclusive=true defined here";
          diag.attachNote(subordinates[subIdx].getLoc())
              << "subordinate without exclusive support defined here";
          diag.attachNote(getLoc())
              << "xbar has exclusive_mode=strict; use exclusive_mode=advisory "
                 "to allow this, or add an exclusive_monitor adapter";
          return failure();
        }
      }
    }
  }

  // Verify outstanding transaction capacity based on txn_policy
  // The capacity bound depends on the transaction policy:
  // - expand: S.outstanding >= sum of reachable M.outstanding
  // - serialize: S.outstanding >= max of reachable M.outstanding
  // - pool: S.outstanding >= pool_size
  bool capacityCheckIsError = getCapacityCheck() == CapacityCheck::Error;

  for (const auto &[subIdx, mgrIndices] : subordinateToManagers) {
    auto subOutstanding = inferEffectiveOutstanding(subordinates[subIdx]);
    if (failed(subOutstanding))
      continue; // Skip if we can't determine subordinate outstanding

    uint32_t requiredOutstanding = 0;
    std::string policyDesc;

    switch (getTxnPolicy()) {
    case TxnPolicy::Expand: {
      // Sum of all reachable managers' outstanding transactions
      policyDesc = "sum of reachable managers' outstanding (txn_policy=expand)";
      for (size_t mgrIdx : mgrIndices) {
        auto mgrOut = inferEffectiveOutstanding(managers[mgrIdx]);
        if (succeeded(mgrOut))
          requiredOutstanding += *mgrOut;
      }
      break;
    }
    case TxnPolicy::Serialize: {
      // Max of all reachable managers' outstanding transactions
      policyDesc =
          "max of reachable managers' outstanding (txn_policy=serialize)";
      for (size_t mgrIdx : mgrIndices) {
        auto mgrOut = inferEffectiveOutstanding(managers[mgrIdx]);
        if (succeeded(mgrOut) && *mgrOut > requiredOutstanding)
          requiredOutstanding = *mgrOut;
      }
      break;
    }
    case TxnPolicy::Pool: {
      // Pool size
      policyDesc = "pool_size (txn_policy=pool)";
      if (auto ps = getPoolSize())
        requiredOutstanding = *ps;
      break;
    }
    }

    if (*subOutstanding < requiredOutstanding) {
      if (capacityCheckIsError) {
        auto diag = emitOpError()
                    << "insufficient subordinate outstanding capacity: subordinate has "
                    << *subOutstanding << " but requires " << requiredOutstanding
                    << " (" << policyDesc << ")";
        diag.attachNote(subordinates[subIdx].getLoc()) << "subordinate defined here";
        return failure();
      } else {
        // Emit warning with explicit location
        mlir::emitWarning(getLoc())
            << "subordinate outstanding capacity may be insufficient: "
            << "subordinate has " << *subOutstanding << " but " << policyDesc
            << " is " << requiredOutstanding;
      }
    }
  }

  return success();
}

//===----------------------------------------------------------------------===//
// ResizerOp
//===----------------------------------------------------------------------===//
Value ResizerOp::getEffectiveClock() {
  // Pass through from input.
  return axi4::inferEffectiveClock(getInput()).value();
}

axi4::BurstCapabilityAttr ResizerOp::getEffectiveBurstCapabilities() {
  auto inputBurst = axi4::inferEffectiveBurstCapabilites(getInput()).value();
  auto inputWidth = axi4::inferEffectiveDataWidth(getInput()).value();
  auto scaled = axi4::scaleBurstCapability(
      inputBurst, inputWidth, getTargetWidth(), getContext(), nullptr);
  if (failed(scaled))
    return inputBurst;
  return *scaled;
}

uint32_t ResizerOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return static_cast<uint32_t>(getTargetWidth());
}

bool ResizerOp::getEffectiveExclusiveAccess() {
  // Pass through from input.
  return axi4::inferEffectiveExclusiveAccess(getInput()).value();
}

uint32_t ResizerOp::getEffectiveOutstanding() {
  // Pass through from input.
  return axi4::inferEffectiveOutstanding(getInput()).value();
}

LogicalResult ResizerOp::verify() {
  // Validate target_width is a valid AXI data width
  uint32_t tw = getTargetWidth();
  if (tw != 32 && tw != 64 && tw != 128 && tw != 256 && tw != 512)
    return emitOpError("target_width must be 32, 64, 128, 256, or 512");

  // Input and result must be the same type (manager or target)
  if (getInput().getType() != getResult().getType())
    return emitOpError("input and result must have the same type");

  // Type must be manager or subordinate
  Type inputType = getInput().getType();
  if (!isa<ManagerType>(inputType) && !isa<SubordinateType>(inputType))
    return emitOpError("input must be a manager or subordinate type");

  auto inputBurst = axi4::inferEffectiveBurstCapabilites(getInput()).value();
  auto inputWidth = axi4::inferEffectiveDataWidth(getInput()).value();
  std::string error;
  auto scaled = axi4::scaleBurstCapability(
      inputBurst, inputWidth, getTargetWidth(), getContext(), &error);
  if (failed(scaled))
    return emitOpError("resizing would produce invalid burst capability: ")
           << error;

  return success();
}

//===----------------------------------------------------------------------===//
// BurstSplitterOp
//===----------------------------------------------------------------------===//

Value BurstSplitterOp::getEffectiveClock() {
  // Pass through from input.
  return axi4::inferEffectiveClock(getInput()).value();
}

axi4::BurstCapabilityAttr BurstSplitterOp::getEffectiveBurstCapabilities() {
  return getBurstCapability();
}

uint32_t BurstSplitterOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return axi4::inferEffectiveDataWidth(getInput()).value();
}

bool BurstSplitterOp::getEffectiveExclusiveAccess() {
  // Pass through from input.
  return axi4::inferEffectiveExclusiveAccess(getInput()).value();
}

uint32_t BurstSplitterOp::getEffectiveOutstanding() {
  // Pass through from input.
  return axi4::inferEffectiveOutstanding(getInput()).value();
}

LogicalResult BurstSplitterOp::verify() {
  // Burst capability is validated by the attribute itself
  return success();
}

//===----------------------------------------------------------------------===//
// CdcOp
//===----------------------------------------------------------------------===//

Value CdcOp::getEffectiveClock() {
  // CDC changes the clock domain - return the target clock.
  return getTargetClock();
}

axi4::BurstCapabilityAttr CdcOp::getEffectiveBurstCapabilities() {
  // Pass through from input.
  return axi4::inferEffectiveBurstCapabilites(getInput()).value();
}

uint32_t CdcOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return axi4::inferEffectiveDataWidth(getInput()).value();
}

bool CdcOp::getEffectiveExclusiveAccess() {
  // Pass through from input.
  return axi4::inferEffectiveExclusiveAccess(getInput()).value();
}

uint32_t CdcOp::getEffectiveOutstanding() {
  // Pass through from input.
  return axi4::inferEffectiveOutstanding(getInput()).value();
}

LogicalResult CdcOp::verify() {
  // Input and result must be the same type (manager or subordinate)
  if (getInput().getType() != getResult().getType())
    return emitOpError("input and result must have the same type");

  // Type must be manager or subordinate
  Type inputType = getInput().getType();
  if (!isa<ManagerType>(inputType) && !isa<SubordinateType>(inputType))
    return emitOpError("input must be a manager or subordinate type");

  // Depth must be at least 2
  if (getDepth() < 2)
    return emitOpError("CDC depth must be at least 2");

  return success();
}

//===----------------------------------------------------------------------===//
// ErrorSubordinateOp
//===----------------------------------------------------------------------===//

Value ErrorSubordinateOp::getEffectiveClock() {
  // Since this is a base endpoint, "effective" == declared.
  return getClock();
}

axi4::BurstCapabilityAttr ErrorSubordinateOp::getEffectiveBurstCapabilities() {
  // Error subordinates accept any burst - return empty capabilities.
  return {};
}

uint32_t ErrorSubordinateOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return static_cast<uint32_t>(getDataWidth());
}

bool ErrorSubordinateOp::getEffectiveExclusiveAccess() {
  // Error subordinates do not support exclusive access.
  return false;
}

uint32_t ErrorSubordinateOp::getEffectiveOutstanding() {
  // Error subordinates have optional outstanding, default to 1.
  if (auto os = getOutstanding())
    return *os;
  return 1;
}

LogicalResult ErrorSubordinateOp::verify() {
  // Validate data_width
  uint32_t dw = getDataWidth();
  if (dw != 32 && dw != 64 && dw != 128 && dw != 256 && dw != 512)
    return emitOpError("data_width must be 32, 64, 128, 256, or 512");

  return success();
}

//===----------------------------------------------------------------------===//
// ExclusiveMonitorOp
//===----------------------------------------------------------------------===//

Value ExclusiveMonitorOp::getEffectiveClock() {
  // Pass through from input.
  return axi4::inferEffectiveClock(getInput()).value();
}

axi4::BurstCapabilityAttr ExclusiveMonitorOp::getEffectiveBurstCapabilities() {
  // Pass through from input.
  return axi4::inferEffectiveBurstCapabilites(getInput()).value();
}

uint32_t ExclusiveMonitorOp::getEffectiveDataWidth() {
  // Since this is a base endpoint, "effective" == declared.
  return axi4::inferEffectiveDataWidth(getInput()).value();
}

bool ExclusiveMonitorOp::getEffectiveExclusiveAccess() {
  // ExclusiveMonitorOp provides exclusive access support.
  return true;
}

uint32_t ExclusiveMonitorOp::getEffectiveOutstanding() {
  // Pass through from input.
  return axi4::inferEffectiveOutstanding(getInput()).value();
}

LogicalResult ExclusiveMonitorOp::verify() {
  // Granularity must be a power of 2
  uint32_t gran = getGranularity();
  if (gran == 0 || (gran & (gran - 1)) != 0)
    return emitOpError("granularity must be a power of 2");

  // Entries must be >= 1
  if (getEntries() < 1)
    return emitOpError("entries must be >= 1");

  return success();
}

//===----------------------------------------------------------------------===//
// AliasOp
//===----------------------------------------------------------------------===//

Value AliasOp::getEffectiveClock() {
  return axi4::inferEffectiveClock(getInput()).value();
}

uint32_t AliasOp::getEffectiveDataWidth() {
  return axi4::inferEffectiveDataWidth(getInput()).value();
}

axi4::BurstCapabilityAttr AliasOp::getEffectiveBurstCapabilities() {
  return axi4::inferEffectiveBurstCapabilites(getInput()).value();
}

bool AliasOp::getEffectiveExclusiveAccess() {
  return axi4::inferEffectiveExclusiveAccess(getInput()).value();
}

uint32_t AliasOp::getEffectiveOutstanding() {
  return axi4::inferEffectiveOutstanding(getInput()).value();
}

LogicalResult AliasOp::verify() {
  return success();
}

//===----------------------------------------------------------------------===//
// BridgeOp
//===----------------------------------------------------------------------===//

LogicalResult BridgeOp::verify() {
  // Outstanding must be >= 1
  if (getOutstanding() < 1)
    return emitOpError("outstanding must be >= 1");

  return success();
}
