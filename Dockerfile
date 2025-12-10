# syntax=docker/dockerfile:1.19

# Build stage - full Ruby image for compiling native extensions
FROM ruby:3.4-alpine3.20 AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git

# Copy Gem definitions
COPY Gemfile Gemfile.lock ./

# Install gems to vendor/bundle
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install --jobs 4 --retry 3

# Production stage - minimal Alpine image
FROM ruby:3.4-alpine3.20 AS production

# Default environment
ARG ENVIRONMENT=production
ENV ENVIRONMENT=${ENVIRONMENT}
ENV RACK_ENV=production

# Install runtime dependencies only
RUN apk add --no-cache \
    tzdata \
    ca-certificates

# Create a non-root user for security
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001 -G appuser

WORKDIR /app

# Copy Gemfile first
COPY --chown=appuser:appuser Gemfile Gemfile.lock ./

# Copy installed gems from builder
COPY --from=builder --chown=appuser:appuser /app/vendor/bundle ./vendor/bundle

# Copy application code
COPY --chown=appuser:appuser . .

# Configure bundler to use vendor/bundle
ENV BUNDLE_PATH=vendor/bundle
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT=development:test

# Expose default Sinatra/Puma port
EXPOSE 4567

# Run as non-root user
USER appuser

# Health check using Ruby's standard Net::HTTP library
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ruby -rnet/http -e "begin; res = Net::HTTP.get_response(URI('http://localhost:4567/healthz')); exit(res.code == '200' ? 0 : 1); rescue; exit 1; end" || exit 1
# Start the Puma server
CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
