---
name: ruby-testing
description: Write and run RSpec tests for Ruby projects
---

## Ruby Testing with RSpec

This project uses RSpec for testing. Follow these conventions when writing or
modifying tests.

### Running Tests

```bash
# Run all tests (excluding integration)
bundle exec rspec --tag ~integration

# Run a specific file
bundle exec rspec spec/path/to/file_spec.rb

# Run with documentation format
bundle exec rspec --format documentation
```

### Test Structure

- Use `describe` for the class/module under test, `context` for scenarios,
  `it` for specific behaviors.
- Place test files in `spec/` mirroring the `lib/` structure.
- Name test files `<name>_spec.rb`.

### Patterns

- Use `let` for test setup, not instance variables.
- Use `subject` when testing a single object.
- Prefer `expect(...).to` over `should` syntax.
- Use `Dir.mktmpdir` for temporary directories in tests.
- Tag integration tests with `:integration` and exclude them in CI.

### Example

```ruby
RSpec.describe MyClass do
  let(:instance) { described_class.new(arg: 42) }

  describe "#do_thing" do
    context "with valid input" do
      it "returns expected result" do
        expect(instance.do_thing("hello")).to eq("HELLO")
      end
    end

    context "with nil input" do
      it "raises ArgumentError" do
        expect { instance.do_thing(nil) }.to raise_error(ArgumentError)
      end
    end
  end
end
```

- Write tests before implementing features when possible.
- Keep tests focused — one behavior per test.
- Use descriptive test names that explain the expected behavior.
