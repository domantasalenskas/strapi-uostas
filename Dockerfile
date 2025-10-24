# syntax=docker/dockerfile:1

# Stage 1: Build stage
FROM node:22-alpine AS build

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    gcc \
    autoconf \
    automake \
    zlib-dev \
    libpng-dev \
    nasm \
    bash \
    vips-dev \
    python3

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ALL dependencies (including dev dependencies needed for build)
RUN npm ci && \
    npm cache clean --force

# Copy source code
COPY . .

# Build the admin panel (requires dev dependencies)
RUN NODE_ENV=production npm run build

# Stage 2: Production stage
FROM node:22-alpine AS production

# Install runtime dependencies
RUN apk add --no-cache \
    vips-dev \
    bash

WORKDIR /app

# Copy package files
COPY --from=build /app/package*.json ./

# Install ONLY production dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy built application from build stage
COPY --from=build /app/dist ./dist
COPY --from=build /app/build ./build
COPY --from=build /app/public ./public

# Copy configuration and source files
COPY --from=build /app/config ./config
COPY --from=build /app/database ./database
COPY --from=build /app/src ./src

# Copy favicon if it exists
COPY --from=build /app/favicon.png* ./

# Create a non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S strapi -u 1001 && \
    chown -R strapi:nodejs /app

USER strapi

# Set environment variables
ENV NODE_ENV=production

# Expose the port that Sevalla expects
EXPOSE 8080

# Start the application
# Strapi will automatically use PORT environment variable if available
CMD ["npm", "run", "start"]

