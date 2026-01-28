cmake_minimum_required(VERSION 4.2)
project(initool_project)

# Set default build type if none specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Customize flags for each build type
set(CMAKE_CXX_FLAGS_DEBUG "-g2 -O0 -DDEBUG -D_DEBUG")
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -DRELEASE")


set(CMAKE_CXX_STANDARD 20)

add_executable(initool initool.cpp)

target_compile_options(initool PRIVATE -Wall -O2)

