#!/bin/sh
# Inject BACKEND_URL into the nginx config template before starting nginx.
# envsubst is part of gettext, which ships with the nginx:alpine base image.
# Only ${BACKEND_URL} is substituted — other nginx variables (e.g. $host) are
# passed through unchanged by listing the explicit variable name.
export BACKEND_HOST=$(echo "$BACKEND_URL" | sed -E 's#^https?://##; s#/.*$##')
envsubst '${BACKEND_URL} ${BACKEND_HOST} ${NGINX_RESOLVER}' \
    < /etc/nginx/conf.d/default.conf.template \
    > /etc/nginx/conf.d/default.conf
nslookup galaxium-backend.2g3916ae1w3m.us-south.codeengine.appdomain.cloud 172.21.0.10
sed -n '/location \/api\//,/^    }/p' /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
