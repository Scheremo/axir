//===- axi4-opt.cpp - axi4 optimizer driver ---------------------*- C++ -*-===//
//
// Main entry point for the axi4 optimizer driver.
//
//===----------------------------------------------------------------------===//

#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "axi4/axi4Dialect.h"
#include "axi4/axi4Ops.h"
#include "axi4/axi4Passes.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;

  // Register all MLIR core dialects.
  mlir::registerAllDialects(registry);

  // Register all MLIR core passes.
  mlir::registerAllPasses();

  // Register the axi4 dialect.
  registry.insert<axi4::axi4Dialect>();

  // Register axi4 passes.
  axi4::registerAxi4Passes();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "axi4 optimizer driver\n", registry));
}
