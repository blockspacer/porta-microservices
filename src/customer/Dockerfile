FROM maxkondr/fedora-base
RUN mkdir -p /app
ADD ./certs/* /app/
ADD ./service_customer /app/

EXPOSE 9092
WORKDIR /app


CMD ["/app/service_customer"]