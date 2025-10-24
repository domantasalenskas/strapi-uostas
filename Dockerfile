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
COPY package.json ./

# Install ALL dependencies (including dev dependencies needed for build)
# Use npm install instead of npm ci to avoid lockfile platform issues
RUN npm install && \
    npm cache clean --force

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
COPY --from=build /app/package.json ./

# Install ONLY production dependencies
RUN npm install --only=production && \
    npm cache clean --force

# Copy built application from build stage
# Strapi v5 builds admin panel into dist/ directory
COPY --from=build /app/dist ./dist
COPY --from=build /app/public ./public

# Copy TypeScript configuration (needed for runtime)
COPY --from=build /app/tsconfig.json ./tsconfig.json

# Copy source files (needed for Strapi runtime - API routes, controllers, services)
COPY --from=build /app/src ./src

# Copy database directory for migrations
COPY --from=build /app/database ./database

# Copy favicon (both formats)
COPY --from=build /app/favicon.png ./favicon.png
COPY --from=build /app/favicon.png ./favicon.ico

# Create a non-root user for security and set up directories
RUN groupadd -g 1001 nodejs && \
    useradd -u 1001 -g nodejs -s /bin/bash -m strapi && \
    mkdir -p /app/.tmp

# Copy pre-populated SQLite database (with admin user and permissions)
COPY --from=build /app/.tmp/data.db /app/.tmp/data.db

# Set proper ownership
RUN chown -R strapi:nodejs /app

USER strapi

# Set environment variables
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=1337 \
    APP_KEYS=hmCRNfUnc5TAvQ/juPNkcA==,AN9/Aqp+OmvdGQeCUW1Tlg==,tAAmL0IP5ymARPfIsltVLA==,/1JClk5Xn12PacrgY2cFXQ== \
    API_TOKEN_SALT=72Ysx38swPxrPU4vEgvJbg== \
    ADMIN_JWT_SECRET=Tf8OG3IAN6bCc07nbEHcmA== \
    TRANSFER_TOKEN_SALT=Y3I2GJBWcCkZRCJ0CUw6SQ== \
    ENCRYPTION_KEY=tR5Ffuqul6hbMA9VYyT0Og== \
    JWT_SECRET=DMHrvSkiduVXM6Yl3kF7vA== \
    DATABASE_CLIENT=sqlite \
    DATABASE_FILENAME=.tmp/data.db \
    DATABASE_SSL=false

# Expose the port that Sevalla expects
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:' + (process.env.PORT || 1337) + '/_health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start the application
# Strapi will automatically use PORT environment variable if available
CMD ["npm", "run", "start"]
