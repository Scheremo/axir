add_mlir_dialect_library(axi4
  axi4Analysis.cpp
  axi4Dialect.cpp
  axi4Ops.cpp
  axi4Interfaces.cpp
  axi4Passes.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/axi4

  DEPENDS
  axi4OpsIncGen
  axi4TypesIncGen
  axi4AttrsIncGen
  axi4InterfacesIncGen
  axi4PassesIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRSupport
)
