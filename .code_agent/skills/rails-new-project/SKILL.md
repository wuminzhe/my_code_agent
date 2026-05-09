---
name: rails-new-project
description: Scaffold new Ruby on Rails projects with database, gems, testing, linting, and Docker. Use when user asks to create a new Rails app, start a Rails project, or set up a Rails application from scratch.
---

# Rails New Project

## Quick Start

```bash
rails new my_app --database=postgresql --test-framework=rspec --skip-action-mailbox --skip-action-text
cd my_app
```

## Workflows

### 1. Create the Project

1. Check Ruby version (`ruby --version`) and Rails version (`rails --version`).
2. Decide on options:
   - `--database=postgresql` — default; use `mysql` or `sqlite3` if user prefers.
   - `--test-framework=rspec` — unless user wants minitest.
   - `--skip-action-mailbox`, `--skip-action-text` — omit if not needed.
   - `--api` — if it's an API-only app.
   - `--skip-test` — if adding rspec manually later.
3. Run `rails new <app_name>` with chosen flags.

### 2. After Creation — Setup Checklist

- [ ] `cd <app_name>` and open in editor.
- [ ] Initialize Git: `git init && git add . && git commit -m "Initial commit"`
- [ ] Configure `database.yml` (username, password, host).
- [ ] Run `bin/rails db:create`
- [ ] Run `bin/rails db:migrate`
- [ ] Run the test suite to verify setup.
- [ ] Start dev server: `bin/rails server`

### 3. Common Gems to Add

Add to `Gemfile` and run `bundle install`:

| Gem | Purpose | Installation |
|-----|---------|-------------|
| `devise` | Authentication | `bundle add devise` + `rails generate devise:install` |
| `pundit` | Authorization | `bundle add pundit` |
| `annotate` | Schema annotations | `bundle add annotate` + `rails g annotate:install` |
| `rubocop-rails` | Linting | `bundle add rubocop-rails` |
| `dotenv-rails` | Environment vars | `bundle add dotenv-rails` |
| `factory_bot_rails` | Test fixtures | `bundle add factory_bot_rails --group "development, test"` |
| `faker` | Seed data | `bundle add faker --group "development, test"` |
| `bullet` | N+1 detection | `bundle add bullet --group "development, test"` |
| `rack-cors` | CORS (API apps) | `bundle add rack-cors` |

### 4. Set Up Testing (if not already done)

```bash
# Generate RSpec config
rails generate rspec:install

# Create a system test helper (feature tests)
mkdir -p spec/support
```

Add to `spec/rails_helper.rb`:
```ruby
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }
```

### 5. Code Quality

```bash
# RuboCop
bundle exec rubocop --init
```

Create `.rubocop.yml` with Rails defaults. See [REFERENCE.md](REFERENCE.md).

### 6. Environment Variables

- Add `dotenv-rails` to Gemfile.
- Create `.env` (add to `.gitignore`).
- Create `.env.example` as a template.
- Use `ENV.fetch("KEY")` in config files.

### 7. Docker (optional)

If user wants Docker, see [REFERENCE.md](REFERENCE.md).

## Advanced

See [REFERENCE.md](REFERENCE.md) for:
- Rails generator conventions
- Docker Compose setup
- CI configuration (GitHub Actions)
- Action Cable setup
