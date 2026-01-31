# axir

axir is an MLIR dialect project.

## Build

LLVM/MLIR is a git submodule in `third_party/llvm-project`.

```bash
# First time: build LLVM/MLIR
cd third_party/llvm-project/build
cmake -G Ninja ../llvm -DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD="Native" -DCMAKE_BUILD_TYPE=Release
ninja
cd ../../..

# Build axir
mkdir build && cd build
cmake .. -DMLIR_DIR=$(pwd)/../third_party/llvm-project/build/lib/cmake/mlir
cmake --build .
```

## Project Structure

- `include/axir/` - TableGen definitions (`.td`) and C++ headers
- `lib/axir/` - C++ implementations
- `tools/axir-opt/` - optimizer driver tool
- `test/` - lit tests

## Conventions

- Keep "axir" lowercase everywhere (namespace, filenames, dialect name)
- TableGen files: `axir*.td` generate `axir*.h.inc` and `axir*.cpp.inc`
- New operations go in `axirOps.td`, new types in `axirTypes.td`
- Test files use `.mlir` extension and FileCheck syntax

## Key Files

- `include/axir/axirDialect.td` - dialect definition
- `include/axir/axirOps.td` - operation definitions
- `include/axir/axirTypes.td` - type definitions
- `lib/axir/axirDialect.cpp` - dialect initialization
