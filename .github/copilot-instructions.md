# AI Coding Assistant — learn-ruby (concise guide)

This file gives a focused summary for AI coding agents working in the learn-ruby project (Sinatra microservice).

Overview
- Small Sinatra microservice (single file `app.rb`) with these endpoints: `/`, `/ping`, `/healthz`, `/info`, `/version`, `/echo`.
- Containerized and production-ready with Puma, a `Dockerfile`, Helm chart `k8s/learn-ruby`, and CI for build/test.
- Design: minimal business logic in `app.rb`, middleware for security headers & logging, and helper functions for system/process info.

Key Files & Where to Look
- `app.rb` — Main HTTP endpoints and middleware. Use for logic, request/response shape, and environment usage.
- `puma.rb` — Puma server config (port from `PORT` env). Use this for production server options.
- `Gemfile` — Dependencies (Sinatra, Puma). Update here for Ruby packages.
- `Dockerfile` — Multi-stage production image; check build args and non-root user configuration.
- `Makefile` — Developer/U/X commands: `make install`, `make dev` (rackup), `make run` (app), `make docker-build/docker-run`, `make helm-deploy`.
- `k8s/learn-ruby` — Helm chart: `templates/` and `values.yaml` (feature toggles, ports, image repo). Tests sit under `k8s/learn-ruby/tests/` and use `helm-unittest`.
- `scripts/` — Smoke & e2e tests used by CI and `make` targets.
- CI: `.github/workflows/full-workflow.yml` (GitHub Actions) & `.gitlab-ci.yml` (GitLab). They show the full pipeline, Kind test cluster usage, `helm unittest` and Trivy/bundler-audit scans.

Developer Workflows & Common Commands
- Local development (run app):
  - `bundle install` (installs gems)
  - `make dev` or `RACK_ENV=development bundle exec rackup config.ru` (run using Rack)
  - `make run` or `bundle exec ruby app.rb`
-- Run syntax checks & quick tests: `ruby -c app.rb`, `ruby -c config.ru` (Makefile `build/test` targets run these)
- Tests: `bundle exec rspec` (RSpec tests live in `spec/`) and `make helm-test` to run helm unittest. Use `bundle exec rspec --format documentation` to run locally.
- Docker: `make docker-build`, `make docker-run` (exposes to 4567)
- Helm: `make helm-deploy`, `helm lint k8s/learn-ruby`, `helm unittest k8s/learn-ruby` (in CI or locally)
- CI locally: Use `kind` and run `helm upgrade --install` with `--set image.pullPolicy=Never` to test deployment in Kind.

Project Conventions & Patterns
- Port & environment: `PORT=4567`, `RACK_ENV` controls logging and test mode; `ENV['CORS_ORIGIN']` sets CORS.
- JSON response format: All JSON endpoints return a consistent format: `{ success: true|false, data: <...>, timestamp: <iso> }`.
- Security & CORS: `after` middleware sets security headers & CORS defaults. Respect `RACK_ENV` for test vs production behavior.
- Helm helpers: Use `templates/_helpers.tpl` helpers `base.fullname`, `base.labels`, `base.selectorLabels` for consistent naming and label conventions. Use `toYaml` + `nindent` for multi-line inserts.
- Helm toggles: `values.yaml` controls `autoscaling.enabled`, `persistence.enabled`, `httproute.enabled`, and service `port`. Always add tests reflecting toggles.
- Labeling: Use `app.kubernetes.io/name` and `app.kubernetes.io/part-of: "learn-ruby"` in templates and tests.

Integration Points & External Dependencies
- Container repository: `ghcr.io/dxas90/learn-ruby` (update in `values.yaml`). CI uses GitHub Container Registry (GHCR).
- CI tools: GitHub Actions for build/test; `kind` for in-cluster tests; `helm-unittest` for chart unit tests; `trivy` and `bundler-audit` for security scanning.
- Gateway/Traefik: `httproute` and annotations configured in `values.yaml`; tests assert presence when enabled.

Helm Tests
- Unit tests live under `k8s/learn-ruby/tests/*.yaml` and run with `helm unittest`.
- Tests are value-driven. Use `set:` blocks to define overrides and `asserts:` to verify the rendered template.
- Templates should be rendered with `helm template -n <namespace> --name-template NAME k8s/learn-ruby` to inspect output.

Tips for AI Agents (Do's & Don'ts)
- DO follow `base.*` helper patterns when changing templates to keep naming consistent.
- DO check `values.yaml` defaults when adding features; write or update `helm-unittest` tests to cover toggles.
- DO keep `app.rb` minimal and testable; avoid large monolithic changes without adding unit-like tests (small integration checks are OK via smoke/e2e scripts).
- DO not change `Puma` port and `service.port` arbitrarily — keep the named port `http` in templates.
- DON'T assume presence of a DB; this app doesn't rely on ActiveRecord in the current configuration (it was removed).
 - DO add RSpec tests for new endpoints or behavior changes (see `spec/app_spec.rb`).
   - Tests use Rack::Test with a default `Host: localhost` header set in `spec/spec_helper.rb` to avoid Rack::Protection 'Host not permitted' 403 rejections.

If you need more details, tell me which area you want: app endpoints, Helm chart, Helm tests, CI secrets, or Docker images. I can expand the sections or add sample commands and snippet examples for CI or chart changes.

Code Examples — Common Changes

- Add a new Sinatra endpoint (GET '/hello')
  1. Open `app.rb` and add:

    ```ruby
    get '/hello' do
      content_type :json
      {
        success: true,
        data: { message: "Hello World" },
        timestamp: Time.now.utc.iso8601
      }.to_json
    end
    ```
  2. Add a compact RSpec test in `spec/app_spec.rb`:

    ```ruby
    it 'returns hello on /hello' do
      get '/hello'
      expect(last_response.status).to eq 200
      json = JSON.parse(last_response.body)
      expect(json['data']['message']).to eq 'Hello World'
    end
    ```

- Add a Helm toggle and test (e.g., `values.yaml` boolean `featureX.enabled`)
  1. Add to `k8s/learn-ruby/values.yaml`:

    ```yaml
    featureX:
      enabled: false
    ```
  2. Add conditional template block in an existing template or new template (e.g., `templates/configmap.yaml`):

    ```helm
    {{- if .Values.featureX.enabled }}
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ include "base.fullname" . }}-featurex
    data:
      enabled: "true"
    {{- end }}
    ```
  3. Add a Helm unit test `tests/featurex_test.yaml`:

    ```yaml
    suite: featureX
    templates:
      - configmap.yaml
    tests:
      - it: creates featureX configmap when enabled
        set:
          featureX.enabled: true
        asserts:
          - isKind:
              of: ConfigMap
          - equal:
              path: metadata.name
              value: RELEASE-NAME-learn-ruby-featurex
    ```
