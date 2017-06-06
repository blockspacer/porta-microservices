FROM maxkondr/fedora-base
RUN mkdir -p /app
ADD ./certs/* /app/
ADD ./service_account /app/

EXPOSE 9091
WORKDIR /app

CMD ["/app/service_account"]