configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in
  ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
  @ONLY
)

set(AXI4_TEST_DEPENDS
  axi4-opt
  FileCheck
  count
  not
)

add_lit_testsuite(check-axi4 "Running the axi4 regression tests"
  ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS ${AXI4_TEST_DEPENDS}
)
set_target_properties(check-axi4 PROPERTIES FOLDER "Tests")

add_lit_testsuites(AXI4 ${CMAKE_CURRENT_SOURCE_DIR} DEPENDS ${AXI4_TEST_DEPENDS})
