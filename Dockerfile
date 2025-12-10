# syntax=docker/dockerfile:1.19
FROM ruby:3.4-trixie AS base

# Default environment
ARG ENVIRONMENT=production
ENV ENVIRONMENT=${ENVIRONMENT}

# Create a non-root user for security
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/usr/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser

WORKDIR /app

# Copy Gem definitions early for layer caching
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle config set deployment 'true' && \
    bundle config set without 'development test' && \
    bundle install

# Copy the full application code
COPY . .

# Expose default Sinatra/Puma port
EXPOSE 4567

# Run as non-root user
USER appuser

# Health check using Ruby's standard Net::HTTP library
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ruby -rnet/http -e "begin; res = Net::HTTP.get_response(URI('http://localhost:4567/healthz')); exit(res.code == '200' ? 0 : 1); rescue; exit 1; end" || exit 1

CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
