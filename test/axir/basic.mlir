// RUN: axir-opt %s | axir-opt | FileCheck %s

// CHECK-LABEL: func.func @test_constant
func.func @test_constant() -> i32 {
  // CHECK: axir.constant 42 : i32
  %0 = axir.constant 42 : i32
  return %0 : i32
}
