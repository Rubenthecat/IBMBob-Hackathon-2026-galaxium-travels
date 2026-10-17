#!/bin/sh
# Inject BACKEND_URL into the nginx config template before starting nginx.
# envsubst is part of gettext, which ships with the nginx:alpine base image.
# Only ${BACKEND_URL} is substituted — other nginx variables (e.g. $host) are
# passed through unchanged by listing the explicit variable name.
envsubst '${BACKEND_URL}' \
    < /etc/nginx/conf.d/default.conf.template \
    > /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
