# Helper function to add axir dialect libraries
function(add_axir_dialect_library name)
  add_mlir_dialect_library(${name} ${ARGN})
endfunction()

# Helper function to set up tablegen for axir
function(axir_tablegen ofn)
  tablegen(MLIR ${ARGV})
  set(TABLEGEN_OUTPUT ${TABLEGEN_OUTPUT} ${CMAKE_CURRENT_BINARY_DIR}/${ofn} PARENT_SCOPE)
endfunction()
