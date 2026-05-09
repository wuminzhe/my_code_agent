# CodeAgent

A minimal, extensible terminal coding agent built with Ruby and [RubyLLM](https://rubyllm.com/).

## Architecture

| Layer | Implementation |
|-------|----------------|
| LLM Communication | **RubyLLM** gem (OpenAI, Anthropic, Google, + more) |
| Agent Loop | `AgentLoop` — tool registration, system prompt assembly, streaming |
| Coding Tools | 4 built-in tools: read, write, edit, shell |
| Terminal UI | `TTY::Prompt` + `Pastel` — colored REPL, slash commands |
| Extensions | `Extension` DSL — custom tools, system prompt fragments, skills |
| Sessions | `SessionManager` — JSON persistence, load/save, context compaction |

## Quick Start

```bash
# Install dependencies
bundle install

# Set your API key (DeepSeek by default)
export DEEPSEEK_API_KEY="sk-..."

# Start the agent
bundle exec ruby -I lib bin/code_agent chat

# Or switch provider on the fly
bundle exec ruby -I lib bin/code_agent chat --provider=openai --model=gpt-4o
```

## Commands

| Command | Description |
|---------|-------------|
| `/help` | Show all commands |
| `/quit` | Exit the agent |
| `/clear` | Clear conversation history |
| `/model` | Show current model/provider |
| `/tools` | List registered tools |
| `/extensions` | List loaded extensions |
| `/save <name>` | Save current session |
| `/load <name>` | Load a saved session |
| `/sessions` | List all saved sessions |
| `/compact` | Summarize and compact context |

Multi-line input: end a line with `\` to continue on the next line.

## Configuration

Default config at `config/default.yml`. Override in `~/.code_agent/config.yml`:

```yaml
model:
  provider: deepseek        # deepseek | openai | anthropic | google
  name: deepseek-v4-flash
  api_key: sk-...           # optional; prefers env var (DEEPSEEK_API_KEY)

agent:
  max_turns: 50
  workspace: /path/to/project

tools:
  read_file:
    enabled: true
    max_lines: 500
  write_file:
    enabled: true
  edit_file:
    enabled: true
  exec_shell:
    enabled: true
    timeout_sec: 120
    allow_commands: []      # empty = all allowed
```

## Extensions

Create extensions as Ruby files in `~/.code_agent/extensions/` or `.code_agent/extensions/` (project-level):

```ruby
# ~/.code_agent/extensions/rails_helper.rb
CodeAgent::Extension.define "rails_helper" do
  description "Adds Rails context"

  system_prompt do
    "This is a Rails #{Rails.version} project. Use Rails conventions."
  end

  on_load do |agent|
    puts "Rails helper loaded!"
  end
end
```

Extensions can also register custom tools:

```ruby
CodeAgent::Extension.define "my_tools" do
  description "Custom toolset"

  tool MyCustomTool   # must be a RubyLLM::Tool subclass
end
```

## Sessions

Sessions are saved to `~/.code_agent/sessions/<name>.json`. They preserve the full conversation history including tool calls and results.

## Tools

### read_file
Read a file from the workspace. Supports line ranges (`start_line`, `end_line`). Auto-truncates large files.

### write_file
Create or overwrite a file. Creates parent directories as needed.

### edit_file
Search-and-replace in a file. The `old_string` must match exactly and uniquely. For safety, multi-match edits are rejected — provide more surrounding context to make the match unique.

### exec_shell
Run a shell command in the workspace. Returns stdout, stderr, and exit code. Supports timeout and optional command whitelisting.

## Project Structure

```
my_code_agent/
├── bin/code_agent          # CLI entry point (Thor)
├── config/default.yml      # Default configuration
├── lib/
│   ├── code_agent.rb       # Main entry + version
│   ├── code_agent/
│   │   ├── config.rb       # YAML config loader
│   │   ├── extension.rb    # Extension DSL and loader
│   │   ├── session_manager.rb  # Session persistence
│   │   ├── agent_loop.rb   # LLM chat + tool registration
│   │   ├── repl.rb         # Interactive REPL
│   │   └── tools/
│   │       ├── base.rb     # Tool base class
│   │       ├── read_file.rb
│   │       ├── write_file.rb
│   │       ├── edit_file.rb
│   │       └── exec_shell.rb
├── .code_agent/
│   └── extensions/         # Project-level extensions
└── Gemfile
```

## Requirements

- Ruby >= 3.2
- API key for your chosen provider (DeepSeek, OpenAI, Anthropic, or Google)
