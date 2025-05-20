#!/bin/sh

BASE_DOMAIN=$(echo "$CERTBOT_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

curl https://developers.hostinger.com/api/dns/v1/zones/${BASE_DOMAIN} \
  --request PUT \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${HOSTINGER_TOKEN}" \
  --data '{"overwrite":true,"zone":[{"name":"_acme-challenge.'${CERTBOT_DOMAIN}'.","records":[{"content":"'${CERTBOT_VALIDATION}'"}],"ttl": 300,"type":"TXT"}]}'
