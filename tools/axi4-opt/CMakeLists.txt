get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)
get_property(conversion_libs GLOBAL PROPERTY MLIR_CONVERSION_LIBS)
get_property(extension_libs GLOBAL PROPERTY MLIR_EXTENSION_LIBS)

add_llvm_executable(axi4-opt
  axi4-opt.cpp
)

llvm_update_compile_flags(axi4-opt)

target_link_libraries(axi4-opt
  PRIVATE
  ${dialect_libs}
  ${conversion_libs}
  ${extension_libs}
  axi4
  MLIROptLib
  MLIRParser
  MLIRPass
  MLIRTransforms
  MLIRSupport
  MLIRIR
  MLIRRegisterAllDialects
  MLIRRegisterAllPasses
)

mlir_check_all_link_libraries(axi4-opt)

install(TARGETS axi4-opt
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
