package main

// Usage rpc-proxy --account_endpoint=etsys.intra:9091 --customer_endpoint=etsys.intra:9092
import (
	"crypto/tls"
	"flag"
	"net/http"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"

	gwAccount "ba-microservices/rpc-stubs/Account"
	gwCustomer "ba-microservices/rpc-stubs/Customer"

	"github.com/golang/glog"
	"github.com/grpc-ecosystem/grpc-gateway/runtime"
)

var (
	bindAddr             = flag.String("bind_address", "0.0.0.0:11000", "Account endpoint")
	endpointAccount      = flag.String("account_endpoint", "service-account.172.16.99.106.xip.io:443", "Account endpoint")
	endpointCustomer     = flag.String("customer_endpoint", "service-customer.172.16.99.106.xip.io:443", "Customer endpoint")
	clientCertFile       = flag.String("cert_file", "./etsys.intra.crt", "SSL certificate file")
	clientKeyFile        = flag.String("key_file", "./etsys.intra.key", "SSL key file ")
	clientTransportCreds credentials.TransportCredentials
)

func init() {
	var err error
	clientTransportCreds, err = getNewServerTLSFromFile(*clientCertFile, *clientKeyFile)
	if err != nil {
		panic(err)
	}
}

// getNewServerTLSFromFile helper for outgoing TLS connection creation
func getNewServerTLSFromFile(certFile, keyFile string) (credentials.TransportCredentials, error) {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, err
	}
	tlsConf := &tls.Config{Certificates: []tls.Certificate{cert},
		InsecureSkipVerify: true,
		NextProtos:         []string{"h2"},
	}
	return credentials.NewTLS(tlsConf), nil
}

func run() error {
	mux := runtime.NewServeMux()
	opts := []grpc.DialOption{
		grpc.WithTransportCredentials(clientTransportCreds),
		grpc.WithTimeout(time.Millisecond * 100),
		grpc.FailOnNonTempDialError(true),
		grpc.WithBlock(),
	}

	gwAccount.RegisterAccountApiHandlerFromEndpoint(mux, *endpointAccount, opts)
	gwCustomer.RegisterCustomerApiHandlerFromEndpoint(mux, *endpointCustomer, opts)
	return http.ListenAndServeTLS(*bindAddr,
		*clientCertFile,
		*clientKeyFile,
		mux,
	)
}

func main() {
	flag.Parse()
	defer glog.Flush()

	if err := run(); err != nil {
		glog.Fatal(err)
	}
}
