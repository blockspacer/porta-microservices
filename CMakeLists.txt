project( ba-microservices )

#----------------------------------------------------------------------
# The minimum version cmake
#----------------------------------------------------------------------
cmake_minimum_required( VERSION 2.8 )

# Cmake find modules
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")

find_package(Protobuf REQUIRED)
find_package(GRPC REQUIRED)
find_package(gflags REQUIRED)

include_directories(${PROTOBUF_INCLUDE_DIRS})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src)

#----------------------------------------------------------------------
# Information output about the project
#----------------------------------------------------------------------
message( STATUS "Protoc: " ${PROTOBUF_PROTOC_EXECUTABLE} )
message( STATUS "gRPC CPP plugin: " ${GRPC_CPP_PLUGIN} )
message( STATUS "Building mode: " ${CMAKE_BUILD_TYPE} )
message( STATUS "Files will be installed to: " ${CMAKE_INSTALL_PREFIX} )
set(PROTOS  ${CMAKE_CURRENT_SOURCE_DIR}/proto)

add_subdirectory( googleapi )
add_subdirectory( src/customer )
