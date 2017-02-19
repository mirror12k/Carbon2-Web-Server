#!/bin/sh

# commands to create the certificate and key
openssl genrsa -out key.pem 4096
openssl req -new -key key.pem -out request.pem
openssl x509 -req -days 30 -in request.pem -signkey key.pem -out cert.pem
