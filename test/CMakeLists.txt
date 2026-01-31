configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in
  ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
  @ONLY
)

set(AXIR_TEST_DEPENDS
  axir-opt
  FileCheck
  count
  not
)

add_lit_testsuite(check-axir "Running the axir regression tests"
  ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS ${AXIR_TEST_DEPENDS}
)
set_target_properties(check-axir PROPERTIES FOLDER "Tests")

add_lit_testsuites(AXIR ${CMAKE_CURRENT_SOURCE_DIR} DEPENDS ${AXIR_TEST_DEPENDS})
