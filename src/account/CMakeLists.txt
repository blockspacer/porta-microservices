set(project_name "service_account") # binary name
set(proto_name "Account") # stands for Customer.proto

project(${project_name})

add_compile_options(-std=c++11 -O3)

#include directory with google/api/annotations.pb.h
include_directories(${GOOGLE_API_PROTO_INCLUDE_DIR})

set(MAIN_PROTO ${PROTOS}/${proto_name}.proto)

set(PROTO_GEN_OUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/proto-src)
file(MAKE_DIRECTORY ${PROTO_GEN_OUT_DIR})
include_directories(${PROTO_GEN_OUT_DIR})


# =========================================================
# build C++ sources from proto files
set(PROTO_SRCS ${PROTO_GEN_OUT_DIR}/${proto_name}.pb.cc)
set(PROTO_HDRS ${PROTO_GEN_OUT_DIR}/${proto_name}.pb.h)

# build C++ gRPC sources from proto files
set(GRPC_SRCS ${PROTO_GEN_OUT_DIR}/${proto_name}.grpc.pb.cc)
set(GRPC_HDRS ${PROTO_GEN_OUT_DIR}/${proto_name}.grpc.pb.h)

add_custom_command(
    OUTPUT ${GRPC_SRCS} ${GRPC_HDRS} ${PROTO_SRCS} ${PROTO_HDRS}
    COMMAND ${PROTOBUF_PROTOC_EXECUTABLE}
    ARGS --grpc_out=${PROTO_GEN_OUT_DIR}
        --cpp_out=${PROTO_GEN_OUT_DIR}
        -I ${PROTOS}
        -I ${GOOGLE_API_PROTO_DIR}
        --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN}
        ${MAIN_PROTO}
    DEPENDS ${MAIN_PROTO} ${PROTOBUF_PROTOC_EXECUTABLE} gRPC::grpc_cpp_plugin
    COMMENT "Running C++ protoc and gRPC compiler on ${MAIN_PROTO}"
    VERBATIM)

# Building microservice
add_executable(${project_name}
    ${CMAKE_CURRENT_SOURCE_DIR}/${project_name}.cxx
    ${PROTO_SRCS}
    ${GRPC_SRCS}
    ${GOOGLE_API_SRC_LIST}
)

target_link_libraries(${project_name}
    gRPC::grpc++_reflection
    ${PROTOBUF_LIBRARY}
    gRPC::grpc++
    gRPC::grpc
    gRPC::grpc++_unsecure
    gflags
    ${CMAKE_BINARY_DIR}/googleapi/libporta-googleapi.a
)

add_dependencies(${project_name}
    porta-googleapi)
