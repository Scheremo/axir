// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Passes.cpp - axi4 pass implementations ---------------*- C++ -*-===//
//
// This file implements the passes for the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#include "axi4/axi4Passes.h"
#include "axi4/axi4Analysis.h"
#include "axi4/axi4Attrs.h"
#include "axi4/axi4Dialect.h"
#include "axi4/axi4Ops.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include <queue>

namespace axi4 {

using namespace mlir;

#define GEN_PASS_DEF_VERIFYAXI4NETWORK
#define GEN_PASS_DEF_VERIFYAXI4LOOPFREE
#define GEN_PASS_DEF_CANONICALIZEAXI4ADAPTERS
#include "axi4/axi4Passes.h.inc"

//===----------------------------------------------------------------------===//
// Helper structures for network analysis
//===----------------------------------------------------------------------===//

/// Represents an address window with translation applied.
struct TranslatedWindow {
  uint64_t base;
  uint64_t size;
  Operation *sourceOp; // The subordinate or bridge that owns this window

  uint64_t end() const { return base + size; }
};

/// Information about a path through the network.
struct NetworkPath {
  XbarOp xbar;
  int64_t addressOffset; // Cumulative address translation
};

struct TranslatedRangeKey {
  Operation *sourceOp;
  uint64_t base;
  uint64_t end;
};

struct TranslatedRangeKeyInfo {
  static inline TranslatedRangeKey getEmptyKey() {
    return {nullptr, 0, 0};
  }
  static inline TranslatedRangeKey getTombstoneKey() {
    return {reinterpret_cast<Operation *>(-1), 0, 0};
  }
  static unsigned getHashValue(const TranslatedRangeKey &key) {
    return llvm::hash_combine(key.sourceOp, key.base, key.end);
  }
  static bool isEqual(const TranslatedRangeKey &lhs,
                      const TranslatedRangeKey &rhs) {
    return lhs.sourceOp == rhs.sourceOp && lhs.base == rhs.base &&
           lhs.end == rhs.end;
  }
};

struct VisitKey {
  Operation *xbar;
  int64_t offset;
  uint64_t base;
  uint64_t end;
  uint64_t pathHash;
};

struct VisitKeyInfo {
  static inline VisitKey getEmptyKey() {
    return {nullptr, 0, 0, 0, 0};
  }
  static inline VisitKey getTombstoneKey() {
    return {reinterpret_cast<Operation *>(-1), 0, 0, 0, 0};
  }
  static unsigned getHashValue(const VisitKey &key) {
    return llvm::hash_combine(key.xbar, key.offset, key.base, key.end,
                              key.pathHash);
  }
  static bool isEqual(const VisitKey &lhs, const VisitKey &rhs) {
    return lhs.xbar == rhs.xbar && lhs.offset == rhs.offset &&
           lhs.base == rhs.base && lhs.end == rhs.end &&
           lhs.pathHash == rhs.pathHash;
  }
};

struct RangeWithPath {
  uint64_t base;
  uint64_t end;
  uint64_t pathHash;
  Operation *lastBridge;
};

//===----------------------------------------------------------------------===//
// VerifyAxi4NetworkPass implementation
//===----------------------------------------------------------------------===//

namespace {

class VerifyAxi4NetworkPass
    : public impl::VerifyAxi4NetworkBase<VerifyAxi4NetworkPass> {
public:
  void runOnOperation() override;

private:
  /// Build the network graph from all xbars and bridges.
  void buildNetworkGraph(ModuleOp module);

  /// Find all subordinates reachable from a manager, including through bridges.
  llvm::SmallVector<std::pair<Value, int64_t>>
  findReachableSubordinates(Value manager, XbarOp startXbar);

  /// Verify coverage for all managers considering cross-bridge paths.
  LogicalResult verifyCoverage();

  /// Verify global address uniqueness across the network.
  LogicalResult verifyGlobalAddressUniqueness();

  /// Verify no ambiguous multiple paths to the same subordinate.
  LogicalResult verifyPathUniqueness();

  /// Verify no implicit aliasing (same subordinate at multiple root ranges).
  LogicalResult verifyExplicitAlias();

  /// Verify aliases appear alongside their base subordinate on the same xbar.
  LogicalResult verifyAliasLocality();

  /// Verify bridge exclusive/burst compatibility across paths.
  LogicalResult verifyBridgeCompatibility();

  /// Check for unreachable subordinates.
  void checkUnreachableSubordinates();

  /// Check for managers that cannot reach any subordinate.
  void checkUnreachableManagers();

  struct ReachState {
    XbarOp xbar;
    int64_t offset; // manager_addr = local_addr + offset
    AddressRange allowed;
    uint64_t pathHash;
    llvm::SmallVector<BridgeOp> bridges;
    Operation *lastBridge;
  };

  template <typename SubFn, typename BridgeFn>
  void walkReachable(XbarOp startXbar,
                     llvm::ArrayRef<WindowAttr> accessWindows, SubFn onSub,
                     BridgeFn onBridge, bool trackPathHash,
                     bool trackBridgeStack);

  /// Find uncovered region given sorted coverage windows.
  std::optional<std::pair<uint64_t, uint64_t>>
  findUncoveredRegion(WindowAttr window,
                      llvm::ArrayRef<TranslatedWindow> sortedCoverage);

  /// Collect reachable subordinate windows translated into root xbar space.
  llvm::SmallVector<TranslatedWindow>
  collectTranslatedSubordinateWindows(XbarOp rootXbar);

  // Network graph data
  llvm::SmallVector<XbarOp> allXbars;
  llvm::SmallVector<BridgeOp> allBridges;

  // Map from xbar to bridges that connect FROM it (as upstream)
  llvm::DenseMap<Operation *, llvm::SmallVector<BridgeOp>>
      xbarToDownstreamBridges;

  // Map from xbar to bridges that connect TO it (as downstream)
  llvm::DenseMap<Operation *, llvm::SmallVector<BridgeOp>>
      xbarToUpstreamBridges;

  // All subordinates in the network (for reachability tracking)
  llvm::DenseSet<Value> allSubordinates;

  // Subordinates that have been reached by at least one manager
  llvm::DenseSet<Value> reachedSubordinates;

  // Managers that can reach at least one subordinate
  llvm::DenseSet<Value> reachableManagers;
};

class VerifyAxi4LoopFreePass
    : public impl::VerifyAxi4LoopFreeBase<VerifyAxi4LoopFreePass> {
public:
  void runOnOperation() override;

private:
  struct Edge {
    BridgeOp bridge;
    XbarOp downstream;
  };

  void buildGraph(ModuleOp module);
  bool detectCycle();
  bool dfs(XbarOp xbar);
  void reportCycle(XbarOp from, XbarOp to, BridgeOp via);

  llvm::SmallVector<XbarOp> allXbars;
  llvm::DenseMap<Operation *, llvm::SmallVector<Edge>> adjacency;
  llvm::DenseMap<Operation *, int> state;
  llvm::DenseMap<Operation *, Operation *> parent;
  llvm::DenseMap<Operation *, BridgeOp> parentEdge;
};

class CanonicalizeAxi4AdaptersPass
    : public impl::CanonicalizeAxi4AdaptersBase<
          CanonicalizeAxi4AdaptersPass> {
public:
  void runOnOperation() override;
};

} // namespace

void VerifyAxi4NetworkPass::buildNetworkGraph(ModuleOp module) {
  // Clear previous state
  allXbars.clear();
  allBridges.clear();
  xbarToDownstreamBridges.clear();
  xbarToUpstreamBridges.clear();
  allSubordinates.clear();
  reachedSubordinates.clear();
  reachableManagers.clear();

  // Collect all xbars and bridges
  module.walk([&](XbarOp xbar) { allXbars.push_back(xbar); });
  module.walk([&](BridgeOp bridge) { allBridges.push_back(bridge); });

  // Build bridge connectivity maps
  for (auto bridge : allBridges) {
    auto *upstreamDef = bridge.getUpstream().getDefiningOp();
    auto *downstreamDef = bridge.getDownstream().getDefiningOp();

    if (upstreamDef)
      xbarToDownstreamBridges[upstreamDef].push_back(bridge);
    if (downstreamDef)
      xbarToUpstreamBridges[downstreamDef].push_back(bridge);
  }

  // Collect all subordinates
  for (auto xbar : allXbars) {
    for (auto sub : xbar.getSubordinates()) {
      allSubordinates.insert(sub);
    }
  }
}

template <typename SubFn, typename BridgeFn>
void VerifyAxi4NetworkPass::walkReachable(
    XbarOp startXbar, llvm::ArrayRef<WindowAttr> accessWindows, SubFn onSub,
    BridgeFn onBridge, bool trackPathHash, bool trackBridgeStack) {
  llvm::DenseSet<VisitKey, VisitKeyInfo> visited;
  llvm::SmallVector<ReachState> stack;

  for (const auto &accessWindow : accessWindows) {
    AddressRange allowed{accessWindow.getBase(),
                         accessWindow.getBase() + accessWindow.getSize()};
    stack.push_back({startXbar, 0, allowed, 0, {}, nullptr});
  }

  while (!stack.empty()) {
    auto state = stack.back();
    stack.pop_back();

    VisitKey key{state.xbar.getOperation(), state.offset, state.allowed.base,
                 state.allowed.end, trackPathHash ? state.pathHash : 0};
    if (!visited.insert(key).second)
      continue;

    // Visit subordinates in current xbar.
    for (auto sub : state.xbar.getSubordinates()) {
      auto subWindow = findBaseSubordinateWindow(sub);
      if (!subWindow)
        continue;

      AddressRange subRange{subWindow->getBase(),
                            subWindow->getBase() + subWindow->getSize()};
      auto overlap = intersectRanges(subRange, state.allowed);
      if (!overlap)
        continue;

      onSub(state, sub, *overlap);
    }

    // Traverse bridges to downstream xbars.
    auto it = xbarToDownstreamBridges.find(state.xbar.getOperation());
    if (it == xbarToDownstreamBridges.end())
      continue;

    for (auto bridge : it->second) {
      auto downstream =
          llvm::dyn_cast<XbarOp>(bridge.getDownstream().getDefiningOp());
      if (!downstream)
        continue;

      auto bridgeWindow = bridge.getUpstreamWindow();
      AddressRange bridgeRange{bridgeWindow.getBase(),
                               bridgeWindow.getBase() +
                                   bridgeWindow.getSize()};

      auto overlap = intersectRanges(state.allowed, bridgeRange);
      if (!overlap)
        continue;

      uint64_t downstreamBase = overlap->base - bridgeWindow.getBase() +
                                bridge.getDownstreamBase();
      uint64_t downstreamEnd = overlap->end - bridgeWindow.getBase() +
                               bridge.getDownstreamBase();

      int64_t newOffset = state.offset +
                          (int64_t)bridgeWindow.getBase() -
                          (int64_t)bridge.getDownstreamBase();
      uint64_t newHash =
          llvm::hash_combine(state.pathHash, bridge.getOperation());

      ReachState next{downstream, newOffset,
                      AddressRange{downstreamBase, downstreamEnd},
                      newHash, state.bridges, bridge.getOperation()};
      if (trackBridgeStack)
        next.bridges.push_back(bridge);

      if (onBridge(state, bridge, *overlap, next)) {
        if (!trackPathHash)
          next.pathHash = 0;
        if (!trackBridgeStack)
          next.bridges.clear();
        stack.push_back(std::move(next));
      }
    }
  }
}

llvm::SmallVector<std::pair<Value, int64_t>>
VerifyAxi4NetworkPass::findReachableSubordinates(Value manager,
                                                  XbarOp startXbar) {
  llvm::SmallVector<std::pair<Value, int64_t>> reachable;

  // Get manager's access windows
  auto accessWindows = getManagerAccessWindows(manager);
  if (accessWindows.empty())
    return reachable;

  walkReachable(
      startXbar, accessWindows,
      [&](const ReachState &state, Value sub, AddressRange) {
        reachable.push_back({sub, state.offset});
        reachedSubordinates.insert(sub);
        reachableManagers.insert(manager);
      },
      [&](const ReachState &, BridgeOp, AddressRange, ReachState &) { return true; },
      /*trackPathHash=*/false, /*trackBridgeStack=*/false);

  return reachable;
}

std::optional<std::pair<uint64_t, uint64_t>>
VerifyAxi4NetworkPass::findUncoveredRegion(
    WindowAttr window, llvm::ArrayRef<TranslatedWindow> sortedCoverage) {
  if (sortedCoverage.empty())
    return std::make_pair(window.getBase(), window.getBase() + window.getSize());

  uint64_t windowBase = window.getBase();
  uint64_t windowEnd = windowBase + window.getSize();
  uint64_t currentPos = windowBase;

  for (const auto &cov : sortedCoverage) {
    if (cov.end() <= currentPos)
      continue;
    if (cov.base >= windowEnd)
      break;

    if (cov.base > currentPos) {
      return std::make_pair(currentPos, std::min(cov.base, windowEnd));
    }

    currentPos = std::max(currentPos, cov.end());
    if (currentPos >= windowEnd)
      return std::nullopt;
  }

  if (currentPos < windowEnd)
    return std::make_pair(currentPos, windowEnd);

  return std::nullopt;
}

LogicalResult VerifyAxi4NetworkPass::verifyCoverage() {
  bool hasFailure = false;

  for (auto xbar : allXbars) {
    bool hasDefaultError = xbar.getDefaultError().has_value();

    for (auto manager : xbar.getManagers()) {
      auto accessWindows = getManagerAccessWindows(manager);

      // Find all reachable subordinates with their address offsets
      auto reachable = findReachableSubordinates(manager, xbar);

      // Build coverage windows (translated to manager's address space)
      llvm::SmallVector<TranslatedWindow> coverageWindows;

      for (auto &[sub, offset] : reachable) {
        auto subWindow = findBaseSubordinateWindow(sub);
        if (!subWindow)
          continue;

        TranslatedWindow tw;
        tw.base = subWindow->getBase() + offset;
        tw.size = subWindow->getSize();
        tw.sourceOp = sub.getDefiningOp();
        coverageWindows.push_back(tw);
      }

      // Sort coverage windows by base address
      llvm::sort(coverageWindows,
                 [](const TranslatedWindow &a, const TranslatedWindow &b) {
                   return a.base < b.base;
                 });

      // Check each access window for coverage
      for (const auto &accessWindow : accessWindows) {
        auto uncovered = findUncoveredRegion(accessWindow, coverageWindows);
        if (uncovered && !hasDefaultError) {
          auto diag = xbar.emitOpError()
                      << "manager access window not fully covered";
          diag.attachNote(manager.getLoc())
              << "manager access window: [0x"
              << llvm::Twine::utohexstr(accessWindow.getBase()) << ", 0x"
              << llvm::Twine::utohexstr(accessWindow.getBase() +
                                        accessWindow.getSize())
              << ")";
          diag.attachNote(xbar.getLoc())
              << "uncovered region: [0x"
              << llvm::Twine::utohexstr(uncovered->first) << ", 0x"
              << llvm::Twine::utohexstr(uncovered->second) << ")";
          diag.attachNote(xbar.getLoc())
              << "add subordinates or bridges to cover this region, or set "
                 "'default_error' to handle unmapped addresses";
          hasFailure = true;
        }
      }
    }
  }

  return hasFailure ? failure() : success();
}

LogicalResult VerifyAxi4NetworkPass::verifyGlobalAddressUniqueness() {
  // For each xbar, collect all reachable subordinate windows (including
  // downstream xbars through bridges), translated into the root xbar address
  // space. Check that these translated windows are globally unique.
  for (auto xbar : allXbars) {
    auto windows = collectTranslatedSubordinateWindows(xbar);

    llvm::sort(windows, [](const TranslatedWindow &a,
                           const TranslatedWindow &b) {
      return a.base < b.base;
    });

    for (size_t i = 0; i + 1 < windows.size(); ++i) {
      const auto &curr = windows[i];
      const auto &next = windows[i + 1];
      if (curr.end() > next.base) {
        if (getAliasBase(curr.sourceOp) == getAliasBase(next.sourceOp))
          continue;
        auto diag = xbar.emitOpError()
                    << "address windows overlap in network address space";
        diag.attachNote(curr.sourceOp->getLoc())
            << "first window: [0x" << llvm::Twine::utohexstr(curr.base)
            << ", 0x" << llvm::Twine::utohexstr(curr.end()) << ")";
        diag.attachNote(next.sourceOp->getLoc())
            << "second window: [0x" << llvm::Twine::utohexstr(next.base)
            << ", 0x" << llvm::Twine::utohexstr(next.end()) << ")";
        return failure();
      }
    }
  }

  return success();
}

LogicalResult VerifyAxi4NetworkPass::verifyPathUniqueness() {
  bool hasFailure = false;

  for (auto xbar : allXbars) {
    for (auto manager : xbar.getManagers()) {
      auto accessWindows = getManagerAccessWindows(manager);
      if (accessWindows.empty())
        continue;

      llvm::DenseMap<Operation *, llvm::SmallVector<RangeWithPath>>
          rangesBySub;
      walkReachable(
          xbar, accessWindows,
          [&](const ReachState &state, Value sub, AddressRange overlap) {
            uint64_t base = overlap.base + state.offset;
            uint64_t end = overlap.end + state.offset;
            AddressRange mgrRange{base, end};

            Operation *baseOp = getAliasBase(sub.getDefiningOp());
            auto &existing = rangesBySub[baseOp];
            for (const auto &range : existing) {
              AddressRange other{range.base, range.end};
              if (range.pathHash != state.pathHash &&
                  rangesOverlap(mgrRange, other)) {
                auto diag = xbar.emitOpError()
                            << "multiple routing paths to subordinate";
                diag.attachNote(sub.getLoc()) << "subordinate reachable by "
                                                 "overlapping address regions";
                diag.attachNote(xbar.getLoc())
                    << "overlap region: [0x"
                    << llvm::Twine::utohexstr(std::max(base, range.base))
                    << ", 0x"
                    << llvm::Twine::utohexstr(std::min(end, range.end)) << ")";
                if (range.lastBridge)
                  diag.attachNote(range.lastBridge->getLoc())
                      << "path via this bridge";
                else
                  diag.attachNote(xbar.getLoc()) << "path is direct";
                if (state.lastBridge)
                  diag.attachNote(state.lastBridge->getLoc())
                      << "path via this bridge";
                else
                  diag.attachNote(xbar.getLoc()) << "path is direct";
                hasFailure = true;
                break;
              }
            }

            existing.push_back({base, end, state.pathHash, state.lastBridge});
          },
          [&](const ReachState &, BridgeOp, AddressRange, ReachState &) {
            return true;
          },
          /*trackPathHash=*/true, /*trackBridgeStack=*/false);
    }
  }

  return hasFailure ? failure() : success();
}

LogicalResult VerifyAxi4NetworkPass::verifyExplicitAlias() {
  bool hasFailure = false;

  for (auto xbar : allXbars) {
    for (auto manager : xbar.getManagers()) {
      auto accessWindows = getManagerAccessWindows(manager);
      if (accessWindows.empty())
        continue;

      DenseMap<Operation *, SmallVector<AddressRange>> rangesByBase;

      walkReachable(
          xbar, accessWindows,
          [&](const ReachState &state, Value sub, AddressRange overlap) {
            Operation *baseOp = getAliasBase(sub.getDefiningOp());
            AddressRange mgrRange{overlap.base + state.offset,
                                  overlap.end + state.offset};
            rangesByBase[baseOp].push_back(mgrRange);
          },
          [&](const ReachState &, BridgeOp, AddressRange, ReachState &) {
            return true;
          },
          /*trackPathHash=*/false, /*trackBridgeStack=*/false);

      for (auto &entry : rangesByBase) {
        auto *base = entry.first;
        auto &ranges = entry.second;
        if (ranges.size() < 2)
          continue;

        llvm::sort(ranges, [](const AddressRange &a, const AddressRange &b) {
          return a.base < b.base;
        });

        AddressRange merged = ranges[0];
        for (size_t i = 1; i < ranges.size(); ++i) {
          if (ranges[i].base <= merged.end) {
            merged.end = std::max(merged.end, ranges[i].end);
          } else {
            auto diag = xbar.emitOpError()
                        << "subordinate reachable at multiple address ranges "
                           "without explicit alias";
            diag.attachNote(base->getLoc())
                << "first range: [0x" << Twine::utohexstr(merged.base)
                << ", 0x" << Twine::utohexstr(merged.end) << ")";
            diag.attachNote(base->getLoc())
                << "second range: [0x" << Twine::utohexstr(ranges[i].base)
                << ", 0x" << Twine::utohexstr(ranges[i].end) << ")";
            diag.attachNote(base->getLoc())
                << "use axi4.alias to make mirroring explicit";
            hasFailure = true;
            break;
          }
        }
      }
    }
  }

  return hasFailure ? failure() : success();
}

LogicalResult VerifyAxi4NetworkPass::verifyAliasLocality() {
  bool hasFailure = false;

  for (auto xbar : allXbars) {
    llvm::DenseSet<Value> subordinateSet;
    for (auto sub : xbar.getSubordinates())
      subordinateSet.insert(sub);

    for (auto sub : xbar.getSubordinates()) {
      auto alias = dyn_cast_or_null<AliasOp>(sub.getDefiningOp());
      if (!alias)
        continue;

      Value base = alias.getInput();
      if (subordinateSet.contains(base))
        continue;

      auto diag = xbar.emitOpError()
                  << "alias must appear with its base subordinate in the same "
                     "xbar";
      diag.attachNote(alias.getLoc()) << "alias defined here";
      diag.attachNote(base.getLoc()) << "base subordinate defined here";
      hasFailure = true;
    }
  }

  return hasFailure ? failure() : success();
}

LogicalResult VerifyAxi4NetworkPass::verifyBridgeCompatibility() {
  bool hasFailure = false;

  for (auto xbar : allXbars) {
    for (auto manager : xbar.getManagers()) {
      auto accessWindows = getManagerAccessWindows(manager);
      if (accessWindows.empty())
        continue;

      auto mgrBurst = inferEffectiveBurstCapabilites(manager);
      auto mgrExclusive = inferEffectiveExclusiveAccess(manager);

      walkReachable(
          xbar, accessWindows,
          [&](const ReachState &state, Value sub, AddressRange overlap) {
            auto subBurst = inferEffectiveBurstCapabilites(sub);
            if (failed(subBurst))
              return;

            for (auto bridge : state.bridges) {
              auto bridgeBurst = bridge.getBurstCapability();
              if (!bridgeBurst)
                continue;
              std::string incompat =
                  checkBurstCompatibility(*bridgeBurst, *subBurst);
              if (!incompat.empty()) {
                auto diag = bridge.emitOpError()
                            << "bridge burst capability mismatch with subordinate: "
                            << incompat;
                diag.attachNote(sub.getLoc())
                    << "subordinate reachable through this bridge";
                hasFailure = true;
                break;
              }
            }
          },
          [&](const ReachState &, BridgeOp bridge, AddressRange overlap,
              ReachState &) {
            if (succeeded(mgrExclusive) && *mgrExclusive) {
              if (bridge.getExclusive() != BridgeExclusive::Passthrough) {
                auto diag =
                    bridge.emitOpError()
                    << "bridge does not allow exclusive transactions";
                diag.attachNote(manager.getLoc())
                    << "manager issues exclusive transactions";
                hasFailure = true;
              }
            }

            if (succeeded(mgrBurst) && bridge.getBurstCapability()) {
              std::string incompat =
                  checkBurstCompatibility(*mgrBurst, *bridge.getBurstCapability());
              if (!incompat.empty()) {
                auto diag = bridge.emitOpError()
                            << "bridge burst capability mismatch with manager: "
                            << incompat;
                diag.attachNote(manager.getLoc())
                    << "manager reachable through this bridge";
                hasFailure = true;
              }
            }
            return true;
          },
          /*trackPathHash=*/true, /*trackBridgeStack=*/true);
    }
  }

  return hasFailure ? failure() : success();
}

void VerifyAxi4NetworkPass::checkUnreachableSubordinates() {
  // Find subordinates that were never reached
  for (auto sub : allSubordinates) {
    if (!reachedSubordinates.count(sub)) {
      emitWarning(sub.getLoc())
          << "subordinate is not reachable by any manager in the network";
    }
  }
}

void VerifyAxi4NetworkPass::checkUnreachableManagers() {
  for (auto xbar : allXbars) {
    for (auto mgr : xbar.getManagers()) {
      if (!reachableManagers.count(mgr)) {
        emitWarning(mgr.getLoc())
            << "manager cannot reach any subordinate in the network";
      }
    }
  }
}

void VerifyAxi4NetworkPass::runOnOperation() {
  auto module = getOperation();

  // Build the network graph
  buildNetworkGraph(module);

  // Skip if no xbars
  if (allXbars.empty())
    return;

  // Verify global address uniqueness (including bridges)
  if (failed(verifyGlobalAddressUniqueness())) {
    signalPassFailure();
    return;
  }

  // Verify no ambiguous multi-path reachability.
  if (failed(verifyPathUniqueness())) {
    signalPassFailure();
    return;
  }

  // Verify implicit aliasing is explicit via axi4.alias.
  if (failed(verifyExplicitAlias())) {
    signalPassFailure();
    return;
  }

  // Verify aliases appear alongside their base subordinate on the same xbar.
  if (failed(verifyAliasLocality())) {
    signalPassFailure();
    return;
  }

  // Verify bridge exclusive/burst compatibility.
  if (failed(verifyBridgeCompatibility())) {
    signalPassFailure();
    return;
  }

  // Verify coverage considering cross-bridge paths
  if (failed(verifyCoverage())) {
    signalPassFailure();
    return;
  }

  // Check for unreachable subordinates
  checkUnreachableSubordinates();

  // Check for managers that cannot reach any subordinate
  checkUnreachableManagers();
}

llvm::SmallVector<TranslatedWindow>
VerifyAxi4NetworkPass::collectTranslatedSubordinateWindows(XbarOp rootXbar) {
  llvm::SmallVector<TranslatedWindow> windows;
  llvm::DenseSet<TranslatedRangeKey, TranslatedRangeKeyInfo> seenRanges;

  struct State {
    XbarOp xbar;
    int64_t offset; // root_addr = local_addr + offset
    AddressRange allowed;
  };

  std::queue<State> worklist;
  llvm::DenseMap<std::pair<Operation *, int64_t>,
                 llvm::SmallVector<AddressRange>>
      visited;

  worklist.push({rootXbar, 0, AddressRange{0, UINT64_MAX}});

  auto isSubset = [](AddressRange a, AddressRange b) {
    return a.base >= b.base && a.end <= b.end;
  };

  while (!worklist.empty()) {
    auto state = worklist.front();
    worklist.pop();

    auto key = std::make_pair(state.xbar.getOperation(), state.offset);
    bool skip = false;
    auto &ranges = visited[key];
    for (const auto &r : ranges) {
      if (isSubset(state.allowed, r)) {
        skip = true;
        break;
      }
    }
    if (skip)
      continue;
    ranges.push_back(state.allowed);

    // Collect reachable subordinates in this xbar.
    for (auto sub : state.xbar.getSubordinates()) {
      auto subWindow = findBaseSubordinateWindow(sub);
      if (!subWindow)
        continue;

      AddressRange subRange{subWindow->getBase(),
                            subWindow->getBase() + subWindow->getSize()};
      auto clipped = intersectRanges(subRange, state.allowed);
      if (!clipped)
        continue;

      uint64_t base = clipped->base + state.offset;
      uint64_t end = clipped->end + state.offset;
      TranslatedRangeKey key{sub.getDefiningOp(), base, end};
      if (!seenRanges.insert(key).second)
        continue;

      TranslatedWindow tw;
      tw.base = base;
      tw.size = end - base;
      tw.sourceOp = sub.getDefiningOp();
      windows.push_back(tw);
    }

    // Traverse bridges to downstream xbars.
    auto it = xbarToDownstreamBridges.find(state.xbar.getOperation());
    if (it == xbarToDownstreamBridges.end())
      continue;

    for (auto bridge : it->second) {
      auto downstream =
          llvm::dyn_cast<XbarOp>(bridge.getDownstream().getDefiningOp());
      if (!downstream)
        continue;

      auto bridgeWindow = bridge.getUpstreamWindow();
      AddressRange bridgeRange{bridgeWindow.getBase(),
                               bridgeWindow.getBase() + bridgeWindow.getSize()};

      auto overlap = intersectRanges(state.allowed, bridgeRange);
      if (!overlap)
        continue;

      // Map overlap into downstream address space.
      uint64_t downstreamBase =
          overlap->base - bridgeWindow.getBase() + bridge.getDownstreamBase();
      uint64_t downstreamEnd =
          overlap->end - bridgeWindow.getBase() + bridge.getDownstreamBase();

      int64_t newOffset = state.offset +
                          (int64_t)bridgeWindow.getBase() -
                          (int64_t)bridge.getDownstreamBase();

      worklist.push(
          {downstream, newOffset, AddressRange{downstreamBase, downstreamEnd}});
    }
  }

  return windows;
}

std::unique_ptr<Pass> createVerifyAxi4NetworkPass() {
  return std::make_unique<VerifyAxi4NetworkPass>();
}

//===----------------------------------------------------------------------===//
// VerifyAxi4LoopFreePass implementation
//===----------------------------------------------------------------------===//

void VerifyAxi4LoopFreePass::buildGraph(ModuleOp module) {
  allXbars.clear();
  adjacency.clear();
  state.clear();
  parent.clear();
  parentEdge.clear();

  module.walk([&](XbarOp xbar) { allXbars.push_back(xbar); });
  module.walk([&](BridgeOp bridge) {
    auto upstream = llvm::dyn_cast<XbarOp>(bridge.getUpstream().getDefiningOp());
    auto downstream =
        llvm::dyn_cast<XbarOp>(bridge.getDownstream().getDefiningOp());
    if (!upstream || !downstream)
      return;
    adjacency[upstream.getOperation()].push_back({bridge, downstream});
  });
}

void VerifyAxi4LoopFreePass::reportCycle(XbarOp from, XbarOp to,
                                         BridgeOp via) {
  auto diag = via.emitOpError() << "creates a loop in AXI4 network";

  llvm::SmallVector<XbarOp> cycle;
  llvm::DenseSet<Operation *> seen;

  cycle.push_back(to);
  seen.insert(to.getOperation());
  if (from.getOperation() != to.getOperation()) {
    cycle.push_back(from);
    seen.insert(from.getOperation());
  }

  Operation *cur = from.getOperation();
  while (cur != to.getOperation()) {
    auto it = parent.find(cur);
    if (it == parent.end())
      break;
    cur = it->second;
    if (!cur)
      break;
    if (auto xbar = llvm::dyn_cast<XbarOp>(cur)) {
      if (seen.insert(cur).second)
        cycle.push_back(xbar);
    }
  }

  for (auto xbar : cycle) {
    diag.attachNote(xbar.getLoc()) << "xbar in loop";
  }
}

bool VerifyAxi4LoopFreePass::dfs(XbarOp xbar) {
  auto *node = xbar.getOperation();
  state[node] = 1;

  auto it = adjacency.find(node);
  if (it != adjacency.end()) {
    for (auto &edge : it->second) {
      auto *next = edge.downstream.getOperation();
      int nextState = state.lookup(next);
      if (nextState == 0) {
        parent[next] = node;
        parentEdge[next] = edge.bridge;
        if (dfs(edge.downstream))
          return true;
      } else if (nextState == 1) {
        reportCycle(xbar, edge.downstream, edge.bridge);
        return true;
      }
    }
  }

  state[node] = 2;
  return false;
}

bool VerifyAxi4LoopFreePass::detectCycle() {
  for (auto xbar : allXbars) {
    if (state.lookup(xbar.getOperation()) == 0) {
      if (dfs(xbar))
        return true;
    }
  }
  return false;
}

void VerifyAxi4LoopFreePass::runOnOperation() {
  auto module = getOperation();

  buildGraph(module);

  if (allXbars.empty())
    return;

  if (detectCycle())
    signalPassFailure();
}

std::unique_ptr<Pass> createVerifyAxi4LoopFreePass() {
  return std::make_unique<VerifyAxi4LoopFreePass>();
}

//===----------------------------------------------------------------------===//
// CanonicalizeAxi4AdaptersPass implementation
//===----------------------------------------------------------------------===//

namespace {

struct CollapseResizerChain final : OpRewritePattern<ResizerOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ResizerOp resizer,
                                PatternRewriter &rewriter) const override {
    auto inner = resizer.getInput().getDefiningOp<ResizerOp>();
    if (!inner || !inner->hasOneUse())
      return failure();

    rewriter.setInsertionPoint(resizer);
    auto merged = ResizerOp::create(
        rewriter, resizer.getLoc(), resizer.getResult().getType(),
        inner.getInput(), resizer.getTargetWidth());
    rewriter.replaceOp(resizer, merged.getResult());
    rewriter.eraseOp(inner);
    return success();
  }
};

struct CollapseBurstSplitterChain final
    : OpRewritePattern<BurstSplitterOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(BurstSplitterOp splitter,
                                PatternRewriter &rewriter) const override {
    auto inner = splitter.getInput().getDefiningOp<BurstSplitterOp>();
    if (!inner || !inner->hasOneUse())
      return failure();

    rewriter.setInsertionPoint(splitter);
    auto merged = BurstSplitterOp::create(
        rewriter, splitter.getLoc(), splitter.getResult().getType(),
        inner.getInput(), splitter.getBurstCapability());
    rewriter.replaceOp(splitter, merged.getResult());
    rewriter.eraseOp(inner);
    return success();
  }
};

struct CollapseCdcChain final : OpRewritePattern<CdcOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(CdcOp cdc,
                                PatternRewriter &rewriter) const override {
    auto inner = cdc.getInput().getDefiningOp<CdcOp>();
    if (!inner || !inner->hasOneUse())
      return failure();

    rewriter.setInsertionPoint(cdc);
    auto merged = CdcOp::create(
        rewriter, cdc.getLoc(), cdc.getResult().getType(), inner.getInput(),
        cdc.getTargetClock(), cdc.getDepth(), cdc.getModeAttr());
    rewriter.replaceOp(cdc, merged.getResult());
    rewriter.eraseOp(inner);
    return success();
  }
};

struct MoveResizerBeforeBurstSplitter final : OpRewritePattern<ResizerOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ResizerOp resizer,
                                PatternRewriter &rewriter) const override {
    auto splitter =
        resizer.getInput().getDefiningOp<BurstSplitterOp>();
    if (!splitter || !splitter->hasOneUse())
      return failure();

    auto inputWidth = axi4::inferEffectiveDataWidth(resizer.getInput()).value();
    auto scaled = axi4::scaleBurstCapability(
        splitter.getBurstCapability(), inputWidth, resizer.getTargetWidth(),
        resizer.getContext(), nullptr);
    if (failed(scaled))
      return failure();

    rewriter.setInsertionPoint(resizer);
    auto newResizer = ResizerOp::create(
        rewriter, resizer.getLoc(), resizer.getResult().getType(),
        splitter.getInput(), resizer.getTargetWidth());
    auto newSplitter = BurstSplitterOp::create(
        rewriter, resizer.getLoc(), resizer.getResult().getType(),
        newResizer.getResult(), *scaled);

    rewriter.replaceOp(resizer, newSplitter.getResult());
    rewriter.eraseOp(splitter);
    return success();
  }
};

struct MoveResizerBeforeCdc final : OpRewritePattern<ResizerOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(ResizerOp resizer,
                                PatternRewriter &rewriter) const override {
    auto cdc = resizer.getInput().getDefiningOp<CdcOp>();
    if (!cdc || !cdc->hasOneUse())
      return failure();

    rewriter.setInsertionPoint(resizer);
    auto newResizer = ResizerOp::create(
        rewriter, resizer.getLoc(), resizer.getResult().getType(),
        cdc.getInput(), resizer.getTargetWidth());
    auto newCdc = CdcOp::create(
        rewriter, resizer.getLoc(), resizer.getResult().getType(),
        newResizer.getResult(), cdc.getTargetClock(), cdc.getDepth(),
        cdc.getModeAttr());

    rewriter.replaceOp(resizer, newCdc.getResult());
    rewriter.eraseOp(cdc);
    return success();
  }
};

struct MoveBurstSplitterBeforeCdc final
    : OpRewritePattern<BurstSplitterOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(BurstSplitterOp splitter,
                                PatternRewriter &rewriter) const override {
    auto cdc = splitter.getInput().getDefiningOp<CdcOp>();
    if (!cdc || !cdc->hasOneUse())
      return failure();

    rewriter.setInsertionPoint(splitter);
    auto newSplitter = BurstSplitterOp::create(
        rewriter, splitter.getLoc(), splitter.getResult().getType(),
        cdc.getInput(), splitter.getBurstCapability());
    auto newCdc = CdcOp::create(
        rewriter, splitter.getLoc(), splitter.getResult().getType(),
        newSplitter.getResult(), cdc.getTargetClock(), cdc.getDepth(),
        cdc.getModeAttr());

    rewriter.replaceOp(splitter, newCdc.getResult());
    rewriter.eraseOp(cdc);
    return success();
  }
};

} // namespace

void CanonicalizeAxi4AdaptersPass::runOnOperation() {
  RewritePatternSet patterns(&getContext());
  patterns.add<CollapseResizerChain, CollapseBurstSplitterChain,
               CollapseCdcChain, MoveResizerBeforeBurstSplitter,
               MoveResizerBeforeCdc, MoveBurstSplitterBeforeCdc>(
      &getContext());

  if (failed(applyPatternsGreedily(getOperation(), std::move(patterns)))) {
    signalPassFailure();
  }
}

std::unique_ptr<Pass> createCanonicalizeAxi4AdaptersPass() {
  return std::make_unique<CanonicalizeAxi4AdaptersPass>();
}

} // namespace axi4
