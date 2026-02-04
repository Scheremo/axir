// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Analysis.cpp - axi4 analysis helpers ----------------*- C++ -*-===//
//
// Shared helper utilities for AXI4 verification and analysis.
//
//===----------------------------------------------------------------------===//

#include "axi4/axi4Analysis.h"

#include "axi4/axi4Interfaces.h"

using namespace mlir;

namespace axi4 {

bool rangesOverlap(AddressRange a, AddressRange b) {
  return a.base < b.end && b.base < a.end;
}

std::optional<AddressRange> intersectRanges(AddressRange a, AddressRange b) {
  uint64_t base = std::max(a.base, b.base);
  uint64_t end = std::min(a.end, b.end);
  if (base >= end)
    return std::nullopt;
  return AddressRange{base, end};
}

FailureOr<uint32_t> inferEffectiveDataWidth(Value endpoint) {
  auto *def = endpoint.getDefiningOp();
  if (!def)
    return failure();

  auto iface = llvm::dyn_cast<Axi4EndpointOpInterface>(def);
  if (!iface)
    return failure();

  return iface.getEffectiveDataWidth();
}

FailureOr<axi4::BurstCapabilityAttr>
inferEffectiveBurstCapabilites(Value endpoint) {
  auto *def = endpoint.getDefiningOp();
  if (!def)
    return failure();

  auto iface = llvm::dyn_cast<Axi4EndpointOpInterface>(def);
  if (!iface)
    return failure();

  return iface.getEffectiveBurstCapabilities();
}

FailureOr<bool> inferEffectiveExclusiveAccess(Value endpoint) {
  auto *def = endpoint.getDefiningOp();
  if (!def)
    return failure();

  auto iface = llvm::dyn_cast<Axi4EndpointOpInterface>(def);
  if (!iface)
    return failure();

  return iface.getEffectiveExclusiveAccess();
}

FailureOr<uint32_t> inferEffectiveOutstanding(Value endpoint) {
  auto *def = endpoint.getDefiningOp();
  if (!def)
    return failure();

  auto iface = llvm::dyn_cast<Axi4EndpointOpInterface>(def);
  if (!iface)
    return failure();

  return iface.getEffectiveOutstanding();
}

FailureOr<Value> inferEffectiveClock(Value endpoint) {
  auto *def = endpoint.getDefiningOp();
  if (!def)
    return failure();

  auto iface = llvm::dyn_cast<Axi4EndpointOpInterface>(def);
  if (!iface)
    return failure();

  return iface.getEffectiveClock();
}

FailureOr<axi4::BurstCapabilityAttr>
scaleBurstCapability(axi4::BurstCapabilityAttr cap, uint32_t inputWidth,
                     uint32_t targetWidth, MLIRContext *ctx,
                     std::string *errorMessage) {
  if (inputWidth == targetWidth)
    return cap;

  if (inputWidth == 0 || targetWidth == 0) {
    if (errorMessage)
      *errorMessage = "invalid data width";
    return failure();
  }

  bool downsizing = targetWidth < inputWidth;
  uint32_t factor =
      downsizing ? (inputWidth / targetWidth) : (targetWidth / inputWidth);
  if (factor == 0) {
    if (errorMessage)
      *errorMessage = "invalid resize factor";
    return failure();
  }

  auto scaleLen = [&](uint32_t len, uint32_t limit,
                      StringRef kind) -> FailureOr<uint32_t> {
    if (downsizing)
      len *= factor;
    else
      len /= factor;
    if (len < 1 || len > limit) {
      if (errorMessage)
        *errorMessage = (kind + " length out of range").str();
      return failure();
    }
    return len;
  };

  std::optional<uint32_t> incr = cap.getIncrMaxLen();
  if (incr) {
    auto scaled = scaleLen(*incr, 256, "INCR");
    if (failed(scaled))
      return failure();
    incr = *scaled;
  }

  std::optional<uint32_t> fixed = cap.getFixedMaxLen();
  if (fixed) {
    auto scaled = scaleLen(*fixed, 16, "FIXED");
    if (failed(scaled))
      return failure();
    fixed = *scaled;
  }

  llvm::SmallVector<int32_t> wrap;
  wrap.reserve(cap.getWrapLengths().size());
  for (int32_t len : cap.getWrapLengths()) {
    auto scaled = scaleLen(static_cast<uint32_t>(len), 16, "WRAP");
    if (failed(scaled))
      return failure();
    uint32_t val = *scaled;
    if (val != 2 && val != 4 && val != 8 && val != 16) {
      if (errorMessage)
        *errorMessage = "WRAP length must be 2, 4, 8, or 16";
      return failure();
    }
    wrap.push_back(static_cast<int32_t>(val));
  }

  return axi4::BurstCapabilityAttr::get(ctx, incr, fixed, wrap);
}

std::string checkBurstCompatibility(BurstCapabilityAttr mgrBurst,
                                    BurstCapabilityAttr subBurst) {
  if (!mgrBurst || !subBurst)
    return "";

  if (auto mgrIncr = mgrBurst.getIncrMaxLen()) {
    auto subIncr = subBurst.getIncrMaxLen();
    if (!subIncr) {
      return "manager requires INCR bursts but subordinate does not support "
             "INCR";
    }
    if (*mgrIncr > *subIncr) {
      return "manager INCR burst length (" + std::to_string(*mgrIncr) +
             ") exceeds subordinate maximum (" + std::to_string(*subIncr) + ")";
    }
  }

  if (auto mgrFixed = mgrBurst.getFixedMaxLen()) {
    auto subFixed = subBurst.getFixedMaxLen();
    if (!subFixed) {
      return "manager requires FIXED bursts but subordinate does not support "
             "FIXED";
    }
    if (*mgrFixed > *subFixed) {
      return "manager FIXED burst length (" + std::to_string(*mgrFixed) +
             ") exceeds subordinate maximum (" + std::to_string(*subFixed) +
             ")";
    }
  }

  auto mgrWrap = mgrBurst.getWrapLengths();
  if (!mgrWrap.empty()) {
    auto subWrap = subBurst.getWrapLengths();
    if (subWrap.empty()) {
      return "manager requires WRAP bursts but subordinate does not support "
             "WRAP";
    }

    llvm::DenseSet<int32_t> subWrapSet(subWrap.begin(), subWrap.end());
    for (int32_t len : mgrWrap) {
      if (!subWrapSet.contains(len)) {
        return "manager requires WRAP length " + std::to_string(len) +
               " which subordinate does not support";
      }
    }
  }

  return "";
}

ManagerOp findBaseManagerOp(Value endpoint) {
  Operation *op = endpoint.getDefiningOp();
  while (op) {
    if (auto mgr = dyn_cast<ManagerOp>(op))
      return mgr;

    if (auto resizer = dyn_cast<ResizerOp>(op)) {
      op = resizer.getInput().getDefiningOp();
    } else if (auto splitter = dyn_cast<BurstSplitterOp>(op)) {
      op = splitter.getInput().getDefiningOp();
    } else if (auto cdc = dyn_cast<CdcOp>(op)) {
      op = cdc.getInput().getDefiningOp();
    } else {
      return nullptr;
    }
  }
  return nullptr;
}

std::optional<WindowAttr> findBaseSubordinateWindow(Value endpoint) {
  Operation *op = endpoint.getDefiningOp();
  while (op) {
    if (auto alias = dyn_cast<AliasOp>(op))
      return alias.getWindow();
    if (auto sub = dyn_cast<SubordinateOp>(op))
      return sub.getWindow();

    if (auto errSub = dyn_cast<ErrorSubordinateOp>(op))
      return errSub.getWindow();

    if (auto resizer = dyn_cast<ResizerOp>(op)) {
      op = resizer.getInput().getDefiningOp();
    } else if (auto cdc = dyn_cast<CdcOp>(op)) {
      op = cdc.getInput().getDefiningOp();
    } else if (auto exclMon = dyn_cast<ExclusiveMonitorOp>(op)) {
      op = exclMon.getInput().getDefiningOp();
    } else if (auto alias = dyn_cast<AliasOp>(op)) {
      op = alias.getInput().getDefiningOp();
    } else {
      return std::nullopt;
    }
  }
  return std::nullopt;
}

llvm::SmallVector<WindowAttr> getManagerAccessWindows(Value endpoint) {
  llvm::SmallVector<WindowAttr> windows;
  ManagerOp mgr = findBaseManagerOp(endpoint);
  if (!mgr)
    return windows;

  for (Attribute attr : mgr.getAccess()) {
    if (auto window = dyn_cast<WindowAttr>(attr))
      windows.push_back(window);
  }
  return windows;
}

Operation *getAliasBase(Operation *op) {
  Operation *cur = op;
  while (cur) {
    if (auto alias = dyn_cast<AliasOp>(cur)) {
      cur = alias.getInput().getDefiningOp();
      continue;
    }
    return cur;
  }
  return op;
}

Operation *getAliasBase(Value endpoint) {
  return getAliasBase(endpoint.getDefiningOp());
}

} // namespace axi4
