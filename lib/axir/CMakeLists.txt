add_mlir_dialect_library(axir
  axirDialect.cpp
  axirOps.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/axir

  DEPENDS
  axirOpsIncGen
  axirTypesIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
)
