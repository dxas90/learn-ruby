# AI Coding Assistant — learn-ruby

Focused guide for AI agents working in this Sinatra microservice project.

## Architecture Overview

**Application:** Single-file Sinatra app (`app.rb`) with 6 RESTful endpoints: `/`, `/ping`, `/healthz`, `/info`, `/version`, `/echo`  
**Deployment:** Containerized with Puma server, Helm chart for Kubernetes, full CI/CD pipeline with security scanning  
**Design philosophy:** Minimal business logic, security-first middleware, JSON-only responses with consistent format

## Critical Files & Gotchas

### Application Layer
- `app.rb` — All HTTP endpoints, middleware (security headers, CORS, logging), system info helpers
- `puma.rb` — Production server config. **CRITICAL:** Uses `/tmp` for pid/state files (read-only root filesystem in K8s)
- `spec/app_spec.rb` — RSpec tests with `Rack::Test`. Sets `Host: localhost` header in `spec_helper.rb` to avoid Rack::Protection 403s

### Container & Deployment
- `Dockerfile` — **GOTCHA:** No cache mount for `/usr/local/bundle` (causes gems to not persist). Gems install to `vendor/bundle` with `deployment: true`
- `k8s/learn-ruby/values.yaml` — **Port must be 4567** (matches Puma default). Environment variables go in `env.variables.*` and render to ConfigMap
- `k8s/learn-ruby/templates/configmap.yaml` — Renders `env.variables` from values.yaml (if not set, PORT defaults but won't be in ConfigMap)
- `k8s/learn-ruby/templates/_helpers.tpl` — Use `base.fullname`, `base.labels`, `base.selectorLabels` for consistency

## Developer Workflows

### Local Development
```bash
bundle install                                    # Install dependencies
bundle exec rspec --format documentation         # Run tests (4 examples)
ruby -c app.rb && ruby -c config.ru             # Syntax check
bundle exec ruby app.rb                          # Run app (port 4567)
```

### Docker & Kubernetes Testing
```bash
docker build -t learn-ruby:test .               # Build image (no cache mounts!)
kind create cluster --name test-cluster          # Create local K8s
kind load docker-image learn-ruby:test --name test-cluster  # Load to Kind

helm upgrade --install learn-ruby ./k8s/learn-ruby \
  --set image.repository=learn-ruby \
  --set image.tag=test \
  --set image.pullPolicy=Never \
  --set autoscaling.enabled=false \
  --wait --timeout 5m

chmod +x scripts/smoke-test.sh && ./scripts/smoke-test.sh    # Basic health check
chmod +x scripts/e2e-test.sh && ./scripts/e2e-test.sh        # Full endpoint tests
```

### Helm Testing
```bash
helm lint k8s/learn-ruby                         # Validate chart
helm unittest k8s/learn-ruby                     # Run 35 unit tests (7 suites)
helm template learn-ruby ./k8s/learn-ruby | less # Inspect rendered templates
```

## Project Conventions

### Response Format
All JSON endpoints return: `{ success: true|false, data: {...}, timestamp: "ISO8601" }`

### Environment Variables
- `PORT=4567` — HTTP port (must match `values.yaml` service.port)
- `RACK_ENV` — Controls logging verbosity and test mode
- `CORS_ORIGIN` — CORS header value (default: `*`)
- `PUMA_THREADS`, `WORKERS` — Puma concurrency settings

### Helm Patterns
- **Toggles:** Add boolean to `values.yaml`, use `{{- if .Values.feature.enabled }}` in templates
- **Labels:** Always use `base.*` helpers, include `app.kubernetes.io/part-of: "learn-ruby"`
- **Tests:** Create `tests/feature_test.yaml` with `set:` overrides and `asserts:` checks

## Common Pitfalls

### Docker Build Issues
❌ **Don't use** `--mount=type=cache,target=/usr/local/bundle` — gems won't persist in image  
✅ **Do use** standard `RUN bundle install` with `deployment: true` mode

### Port Mismatches
❌ **Don't change** `service.port` without updating `PORT` env var  
✅ **Keep aligned:** `values.yaml` port 4567 = `puma.rb` default = `app.rb` set :port

### Writable Paths in K8s
❌ **Don't write** to `./log/` or `./tmp/` (read-only filesystem)  
✅ **Use `/tmp`** for Puma pid/state files and any runtime writes

### Testing with Rack::Protection
❌ **Don't forget** `Host` header in tests — causes 403 rejections  
✅ **Set in spec_helper:** `header 'Host', 'localhost'` for all requests

## CI/CD Pipeline

Full workflow in `.github/workflows/full-workflow.yml`:
1. **Lint** — Ruby syntax check
2. **Test** — RSpec on Ruby 3.2 & 3.4 with coverage
3. **Security** — bundler-audit for CVEs
4. **Helm Test** — 35 unit tests via helm-unittest
5. **Build** — Docker multi-arch, push to GHCR
6. **Trivy** — Container vulnerability scan
7. **Kind Deploy** — Test in local K8s cluster
8. **Smoke Test** — Basic health & connectivity
9. **E2E Test** — Full endpoint validation + resilience

Run locally: See "Docker & Kubernetes Testing" above

## Adding New Endpoints

1. **Add route** in `app.rb`:
```ruby
get '/hello' do
  content_type :json
  { success: true, data: { message: "Hello" }, timestamp: Time.now.utc.iso8601 }.to_json
end
```

2. **Add test** in `spec/app_spec.rb`:
```ruby
it 'returns hello on /hello' do
  get '/hello'
  expect(last_response.status).to eq 200
  json = JSON.parse(last_response.body)
  expect(json['data']['message']).to eq 'Hello'
end
```

3. **Run tests:** `bundle exec rspec`

## Adding Helm Features

1. **Add toggle** to `values.yaml`:
```yaml
newFeature:
  enabled: false
```

2. **Add template** (or conditional in existing):
```helm
{{- if .Values.newFeature.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "base.fullname" . }}-feature
data:
  enabled: "true"
{{- end }}
```

3. **Add test** in `tests/feature_test.yaml`:
```yaml
suite: newFeature
templates:
  - configmap.yaml
tests:
  - it: creates feature configmap when enabled
    set:
      newFeature.enabled: true
    asserts:
      - isKind:
          of: ConfigMap
      - equal:
          path: metadata.name
          value: RELEASE-NAME-learn-ruby-feature
```

4. **Test:** `helm unittest k8s/learn-ruby`

---

**Need details on:** app internals, Docker builds, Helm charts, CI secrets, or security scanning? Ask for specific area expansion.
