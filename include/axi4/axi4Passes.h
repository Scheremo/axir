// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 AXIR Contributors

//===- axi4Passes.h - axi4 pass declarations --------------------*- C++ -*-===//
//
// This file declares the passes for the axi4 dialect.
//
//===----------------------------------------------------------------------===//

#ifndef AXI4_PASSES_H
#define AXI4_PASSES_H

#include "mlir/Pass/Pass.h"

namespace axi4 {

/// Creates a pass that verifies AXI4 network topology.
std::unique_ptr<mlir::Pass> createVerifyAxi4NetworkPass();

/// Creates a pass that verifies AXI4 network is loop-free.
std::unique_ptr<mlir::Pass> createVerifyAxi4LoopFreePass();

/// Creates a pass that canonicalizes AXI4 adapter chains.
std::unique_ptr<mlir::Pass> createCanonicalizeAxi4AdaptersPass();

/// Generate the code for registering passes.
#define GEN_PASS_REGISTRATION
#include "axi4/axi4Passes.h.inc"

} // namespace axi4

#endif // AXI4_PASSES_H
