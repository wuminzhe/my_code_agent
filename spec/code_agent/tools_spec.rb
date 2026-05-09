# frozen_string_literal: true

RSpec.describe CodeAgent::Tools::ReadFile, :tmpdir do
  let(:tool) { described_class.new }

  before do
    File.write(File.join(@tmpdir, "test.txt"), "line one\nline two\nline three\n")
  end

  it "reads entire file with line numbers" do
    result = tool.execute(path: "test.txt")
    expect(result).to include("   1| line one")
    expect(result).to include("   2| line two")
    expect(result).to include("   3| line three")
  end

  it "reads with line range" do
    result = tool.execute(path: "test.txt", start_line: 2, end_line: 2)
    expect(result).to eq("   2| line two")
  end

  it "reads from start_line to end" do
    result = tool.execute(path: "test.txt", start_line: 2)
    expect(result).to include("   2| line two")
    expect(result).to include("   3| line three")
    expect(result).not_to include("   1|")
  end

  it "handles start_line beyond file end" do
    result = tool.execute(path: "test.txt", start_line: 10)
    expect(result).to eq("")
  end

  it "returns error for non-existent file" do
    result = tool.execute(path: "nonexistent.txt")
    expect(result[:error]).to include("File not found")
  end

  it "returns error for directory" do
    result = tool.execute(path: ".")
    expect(result[:error]).to include("Not a file")
  end

  it "truncates large files" do
    allow(CodeAgent.config.tools).to receive(:dig).with("read_file", "max_lines").and_return(2)
    File.write(File.join(@tmpdir, "large.txt"), (1..10).map { |i| "line #{i}" }.join("\n"))
    result = tool.execute(path: "large.txt")
    expect(result).to include("[Truncated: 10 lines total")
  end
end

RSpec.describe CodeAgent::Tools::WriteFile, :tmpdir do
  let(:tool) { described_class.new }

  it "creates a new file" do
    result = tool.execute(path: "new.txt", content: "hello world")
    expect(result[:success]).to be true
    expect(result[:lines]).to eq(1)
    expect(File.read(File.join(@tmpdir, "new.txt"))).to eq("hello world")
  end

  it "overwrites an existing file" do
    File.write(File.join(@tmpdir, "existing.txt"), "old content")
    result = tool.execute(path: "existing.txt", content: "new content")
    expect(result[:success]).to be true
    expect(File.read(File.join(@tmpdir, "existing.txt"))).to eq("new content")
  end

  it "creates parent directories" do
    result = tool.execute(path: "deep/nested/file.txt", content: "nested")
    expect(result[:success]).to be true
    expect(File.read(File.join(@tmpdir, "deep/nested/file.txt"))).to eq("nested")
  end
end

RSpec.describe CodeAgent::Tools::EditFile, :tmpdir do
  let(:tool) { described_class.new }

  before do
    File.write(File.join(@tmpdir, "code.rb"), <<~RUBY)
      def hello
        puts "hello"
      end

      def goodbye
        puts "goodbye"
      end
    RUBY
  end

  it "replaces a unique match" do
    result = tool.execute(
      path: "code.rb",
      old_string: 'puts "hello"',
      new_string: 'puts "hi"'
    )
    expect(result[:success]).to be true
    expect(File.read(File.join(@tmpdir, "code.rb"))).to include('puts "hi"')
    expect(File.read(File.join(@tmpdir, "code.rb"))).not_to include('puts "hello"')
  end

  it "rejects multi-match edits" do
    result = tool.execute(
      path: "code.rb",
      old_string: "puts",
      new_string: "print"
    )
    expect(result[:error]).to include("old_string matches 2 locations")
  end

  it "rejects edits when old_string not found" do
    result = tool.execute(
      path: "code.rb",
      old_string: "nonexistent code",
      new_string: "something"
    )
    expect(result[:error]).to include("old_string not found")
  end

  it "returns error for non-existent file" do
    result = tool.execute(path: "missing.rb", old_string: "x", new_string: "y")
    expect(result[:error]).to include("File not found")
  end
end

RSpec.describe CodeAgent::Tools::ExecShell, :tmpdir do
  let(:tool) { described_class.new }

  it "executes a simple command" do
    result = tool.execute(command: "echo hello")
    expect(result[:success]).to be true
    expect(result[:stdout]).to include("hello")
    expect(result[:exit_code]).to eq(0)
  end

  it "captures stderr and non-zero exit" do
    result = tool.execute(command: "ls /nonexistent_path_xyz 2>&1")
    expect(result[:success]).to be false
    expect(result[:exit_code]).not_to eq(0)
  end

  it "enforces command whitelist" do
    allow(CodeAgent.config.tools).to receive(:[]).with("exec_shell").and_return({
      "allow_commands" => ["echo"]
    })
    result = tool.execute(command: "ls")
    expect(result[:error]).to include("not in allowlist")
  end

  it "allows whitelisted command" do
    allow(CodeAgent.config.tools).to receive(:[]).with("exec_shell").and_return({
      "allow_commands" => ["echo"]
    })
    result = tool.execute(command: "echo allowed")
    expect(result[:success]).to be true
  end
end
