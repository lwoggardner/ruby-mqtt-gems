#!/bin/bash
# Generate self-signed certificates for local mosquitto testing

cd "$(dirname "$0")/../ssl"

# Generate server key and certificate
openssl req -new -x509 -days 3650 -extensions v3_ca -keyout server.key -out server.crt -subj "/CN=localhost" -nodes

# Generate expired certificate for testing
openssl req -new -x509 -days 1 -set_serial 1 -keyout expired.key -out expired.crt -subj "/CN=localhost" -nodes
# Backdate it
touch -t 202001010000 expired.crt

echo "Certificates generated in spec/fixture/ssl/"
echo "- server.key/server.crt: Valid server certificate"
echo "- expired.key/expired.crt: Expired certificate for testing"
