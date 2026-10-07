cmake_minimum_required(VERSION 3.22)
project(rcbeam LANGUAGES CXX)

option(RCBEAM_BUILD_TESTS "Build RCBeam smoke tests" ON)

add_library(rcbeam STATIC
    src/solver.cpp
)

target_include_directories(rcbeam
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(rcbeam PUBLIC cxx_std_17)

if(MSVC)
    target_compile_options(rcbeam PRIVATE /W4 /permissive-)
else()
    target_compile_options(rcbeam PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(RCBEAM_BUILD_TESTS)
    enable_testing()
    add_executable(rcbeam_smoke tests/solver_smoke.cpp)
    target_link_libraries(rcbeam_smoke PRIVATE rcbeam)
    add_test(NAME rcbeam_smoke COMMAND rcbeam_smoke)
    # Keep smoke assertions active in Release builds as well.
    if(MSVC)
        target_compile_options(rcbeam_smoke PRIVATE /UNDEBUG)
    else()
        target_compile_options(rcbeam_smoke PRIVATE -UNDEBUG)
    endif()
    add_executable(rcbeam_regression tests/solver_regression.cpp)
    target_link_libraries(rcbeam_regression PRIVATE rcbeam)
    add_test(NAME rcbeam_regression COMMAND rcbeam_regression)
endif()
