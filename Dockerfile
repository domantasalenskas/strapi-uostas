# syntax=docker/dockerfile:1

# Stage 1: Build stage
FROM node:22-bookworm-slim AS build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    python3 \
    libvips-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ALL dependencies (including dev dependencies needed for build)
RUN npm ci

# Copy source code
COPY . .

# Build the admin panel (requires dev dependencies)
RUN NODE_ENV=production npm run build

# Stage 2: Production stage
FROM node:22-bookworm-slim AS production

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libvips42 \
    && rm -rf /var/lib/apt/lists/*

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
RUN groupadd -g 1001 nodejs && \
    useradd -u 1001 -g nodejs -s /bin/bash -m strapi && \
    chown -R strapi:nodejs /app

USER strapi

# Set environment variables
ENV NODE_ENV=production

# Expose the port that Sevalla expects
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:' + (process.env.PORT || 1337) + '/_health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start the application
# Strapi will automatically use PORT environment variable if available
CMD ["npm", "run", "start"]
