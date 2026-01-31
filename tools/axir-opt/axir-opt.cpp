//===- axir-opt.cpp - axir optimizer driver ---------------------*- C++ -*-===//
//
// Main entry point for the axir optimizer driver.
//
//===----------------------------------------------------------------------===//

#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "axir/axirDialect.h"
#include "axir/axirOps.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;

  // Register all MLIR core dialects.
  mlir::registerAllDialects(registry);

  // Register all MLIR core passes.
  mlir::registerAllPasses();

  // Register the axir dialect.
  registry.insert<axir::axirDialect>();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "axir optimizer driver\n", registry));
}
