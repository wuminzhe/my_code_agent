# Rails New Project — Reference

## RuboCop Configuration

Create `.rubocop.yml`:

```yaml
require:
  - rubocop-rails

AllCops:
  NewCops: enable
  TargetRubyVersion: 3.2
  Exclude:
    - "db/schema.rb"
    - "bin/**/*"
    - "vendor/**/*"
    - "node_modules/**/*"

Style/Documentation:
  Enabled: false

Style/FrozenStringLiteralComment:
  Enabled: false

Metrics/MethodLength:
  Max: 15

Metrics/AbcSize:
  Max: 20
```

## Docker Compose Setup

Create `Dockerfile`:

```dockerfile
FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
```

Create `docker-compose.yml`:

```yaml
version: "3.8"
services:
  app:
    build: .
    command: bin/rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    volumes:
      - .:/app
    environment:
      RAILS_ENV: development
      DATABASE_URL: postgres://postgres:password@db:5432/my_app_development
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

## GitHub Actions CI

Create `.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: password
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.2"
          bundler-cache: true
      - run: cp config/database.yml.ci config/database.yml
      - run: bin/rails db:create db:migrate
      - run: bundle exec rspec
      - run: bundle exec rubocop
```

## Generator Conventions

Create `config/application.rb` custom generators:

```ruby
config.generators do |g|
  g.test_framework :rspec
  g.fixture_replacement :factory_bot, dir: "spec/factories"
  g.helper false
  g.assets false
  g.view_specs false
  g.stylesheets false
  g.javascripts false
end
```

## Action Cable Setup

```bash
rails generate channel Room
```

Mount in `config/routes.rb`:

```ruby
mount ActionCable.server => "/cable"
```

Configure Redis adapter in `config/cable.yml`:

```yaml
development:
  adapter: redis
  url: redis://localhost:6379/1
```

## Helpful Rake Tasks

```bash
bin/rails routes              # List all routes
bin/rails db:seed             # Seed the database
bin/rails db:rollback         # Rollback last migration
bin/rails db:migrate:status   # Show migration status
bin/rails notes               # Show annotated code comments
bin/rails zeitwerk:check      # Check autoloading
```
