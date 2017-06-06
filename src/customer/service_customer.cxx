#include "utils/utils.hxx"
#include <iostream>
#include <memory>
#include <string>

#include "Customer.grpc.pb.h"
#include "Customer.pb.h"
#include <gflags/gflags.h>
#include <grpc++/grpc++.h>

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using Customer::CustomerApi;
using Customer::CustomerInfo;
using Customer::CustomerInfoRequest;
using Customer::CustomerInfoResponse;

using namespace std;

DEFINE_string(bind_address, "0.0.0.0:9092", "Customer service bind address");
DEFINE_string(cert_file, "./etsys.intra.crt", "SSL certificate file");
DEFINE_string(key_file, "./etsys.intra.key", "SSL key file");

// Logic and data behind the server's behavior.
class CustomerServiceImpl final :
    public CustomerApi::Service
{
    Status
    GetCustomerInfo(ServerContext *context, const CustomerInfoRequest *request,
                    CustomerInfoResponse *reply) override
    {
        reply->mutable_info()->set_id(string("Hello ") + std::to_string(request->i_customer()));
        reply->mutable_info()->set_password("123test");
        reply->mutable_info()->set_i_customer(request->i_customer());
        return Status::OK;
    }
};

void
RunServer()
{
    std::string cert, key;

    // read and assing SSL cert
    readFile(FLAGS_cert_file, cert);
    readFile(FLAGS_key_file, key);
    grpc::SslServerCredentialsOptions::PemKeyCertPair keycert =
    {
        key,
        cert
    };

    grpc::SslServerCredentialsOptions sslOps;
    sslOps.pem_root_certs = "";
    sslOps.pem_key_cert_pairs.push_back(keycert);

    // Listen on the given address without any authentication mechanism.
    ServerBuilder builder;
    builder.AddListeningPort(FLAGS_bind_address, grpc::SslServerCredentials(sslOps));
    // Register "service" as the instance through which we'll communicate with
    // clients. In this case it corresponds to an *synchronous* service.
    CustomerServiceImpl service;
    builder.RegisterService(&service);
    // Finally assemble the server.
    std::unique_ptr<Server> server(builder.BuildAndStart());
    std::cout << "Server listening on " << FLAGS_bind_address << std::endl;

    // Wait for the server to shutdown. Note that some other thread must be
    // responsible for shutting down the server for this call to ever return.
    server->Wait();
}

int
main(int argc, char **argv)
{
    gflags::ParseCommandLineFlags(&argc, &argv, true);
    RunServer();
    gflags::ShutDownCommandLineFlags();

    return 0;
}

