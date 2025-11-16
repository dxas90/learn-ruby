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

CMD ["bundle", "exec", "puma", "-C", "puma.rb"]
