# Build stage
FROM --platform=linux/amd64 node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci

# Copy source code
COPY . .

# Ensure production builds default to same-origin API routing unless explicitly overridden
ARG VITE_API_URL=/api

# Build for production
RUN VITE_API_URL=$VITE_API_URL npm run build

# Production stage with nginx
FROM --platform=linux/amd64 nginx:alpine

# Default backend upstream — Docker Compose uses the "backend" service name.
# Override with --env BACKEND_URL=http://galaxium-backend:8080 in Code Engine.
# Override with --env NGINX_RESOLVER=172.21.0.10 for Code Engine / Kubernetes.
ENV BACKEND_URL=http://backend:8080
ENV NGINX_RESOLVER=172.21.0.10

# Copy built assets
COPY --from=build /app/dist /usr/share/nginx/html

# Copy warming-up page (served by Nginx error_page on 502/503/504)
COPY warming-up.html /usr/share/nginx/html/warming-up.html

# Copy nginx config as a template; docker-entrypoint.sh runs envsubst at startup
COPY nginx.conf /etc/nginx/conf.d/default.conf.template

# Copy entrypoint that templates nginx.conf before starting nginx
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN sed -i 's/\r$//' /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
