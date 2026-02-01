# Helper function to add axi4 dialect libraries
function(add_axi4_dialect_library name)
  add_mlir_dialect_library(${name} ${ARGN})
endfunction()

# Helper function to set up tablegen for axi4
function(axi4_tablegen ofn)
  tablegen(MLIR ${ARGV})
  set(TABLEGEN_OUTPUT ${TABLEGEN_OUTPUT} ${CMAKE_CURRENT_BINARY_DIR}/${ofn} PARENT_SCOPE)
endfunction()
