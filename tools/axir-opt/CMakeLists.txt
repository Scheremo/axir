get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)
get_property(conversion_libs GLOBAL PROPERTY MLIR_CONVERSION_LIBS)
get_property(extension_libs GLOBAL PROPERTY MLIR_EXTENSION_LIBS)

add_llvm_executable(axir-opt
  axir-opt.cpp
)

llvm_update_compile_flags(axir-opt)

target_link_libraries(axir-opt
  PRIVATE
  ${dialect_libs}
  ${conversion_libs}
  ${extension_libs}
  axir
  MLIROptLib
  MLIRParser
  MLIRPass
  MLIRTransforms
  MLIRSupport
  MLIRIR
  MLIRRegisterAllDialects
  MLIRRegisterAllPasses
)

mlir_check_all_link_libraries(axir-opt)
