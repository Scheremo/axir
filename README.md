# axir

An MLIR dialect project template.

## Contents

```
axir/
├── CMakeLists.txt                 # Top-level CMake configuration
├── cmake/modules/
│   └── Addaxir.cmake              # Helper CMake functions
├── include/axir/
│   ├── CMakeLists.txt             # TableGen generation rules
│   ├── axirDialect.td             # Dialect definition (TableGen)
│   ├── axirDialect.h              # Dialect C++ header
│   ├── axirOps.td                 # Operations definition (TableGen)
│   ├── axirOps.h                  # Operations C++ header
│   ├── axirTypes.td               # Types definition (TableGen)
│   └── axirTypes.h                # Types C++ header
├── lib/axir/
│   ├── CMakeLists.txt             # Library build rules
│   ├── axirDialect.cpp            # Dialect initialization
│   └── axirOps.cpp                # Operations implementation
├── tools/axir-opt/
│   ├── CMakeLists.txt             # Tool build rules
│   └── axir-opt.cpp               # Optimizer driver
└── test/
    ├── CMakeLists.txt             # Test configuration
    ├── lit.cfg.py                 # Lit test runner config
    ├── lit.site.cfg.py.in         # Lit site config template
    └── axir/
        └── basic.mlir             # Example test
```

## Prerequisites

- CMake 3.20+
- Ninja build system
- C++17 compatible compiler

## Build Instructions

### 1. Clone with submodules

```bash
git clone --recursive https://github.com/user/axir.git
cd axir
```

Or if already cloned:

```bash
git submodule update --init --recursive
```

### 2. Build LLVM/MLIR (one-time setup)

```bash
mkdir -p third_party/llvm-project/build
cd third_party/llvm-project/build

cmake -G Ninja ../llvm \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD="Native" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=ON

ninja
cd ../../..
```

### 3. Build axir

```bash
mkdir build && cd build

cmake .. \
  -DMLIR_DIR=$(pwd)/../third_party/llvm-project/build/lib/cmake/mlir \
  -DCMAKE_BUILD_TYPE=Release

cmake --build .
```

### 4. Run Tests (optional)

```bash
cmake --build . --target check-axir
```

## Getting Started

### Using the Dialect

The axir dialect registers under the namespace `axir`. After building, use `axir-opt` to parse and transform `.mlir` files:

```bash
./build/bin/axir-opt input.mlir
```

### Example

```mlir
func.func @example() -> i32 {
  %0 = axir.constant 42 : i32
  return %0 : i32
}
```

### Adding New Operations

1. Define the operation in `include/axir/axirOps.td`:

```tablegen
def axir_MyOp : axir_Op<"my_op", [Pure]> {
  let summary = "my operation";
  let arguments = (ins AnyType:$input);
  let results = (outs AnyType:$output);
  let assemblyFormat = "$input attr-dict `:` type($input) `->` type($output)";
}
```

2. Rebuild to generate the C++ code.

3. Optionally add custom verification or canonicalization in `lib/axir/axirOps.cpp`.

### Adding New Types

1. Define the type in `include/axir/axirTypes.td`:

```tablegen
def axir_MyType : axir_Type<"My", "my"> {
  let summary = "my custom type";
  let parameters = (ins "int64_t":$width);
  let assemblyFormat = "`<` $width `>`";
}
```

2. Rebuild to generate the C++ code.

### Adding Passes

1. Create `include/axir/Passes.td` for pass TableGen definitions
2. Create `lib/axir/Passes/` directory for pass implementations
3. Register passes in `axir-opt.cpp`

## License

[Add your license here]
