Gem::Specification.new do |spec|
  spec.required_ruby_version = ">= 3.0.0"

  spec.name = "aids"
  spec.version = "1.0.1"
  spec.authors = ["emanrdesu"]
  spec.email = ["janitor@waifu.club"]
  spec.summary = "AI DeepSeek client REPL for the terminal"
  spec.description = "Interactive AI assistant with session management, " \
                     "file attachments, syntax highlighting, and cost tracking."
  spec.homepage = "https://github.com/emanrdesu/aids"
  spec.license = "MIT"

  spec.files = Dir["lib/**/*.rb", "bin/*"]
  spec.executables = ["aids"]
  spec.require_paths = ["lib"]

  spec.add_dependency "emanlib", "~> 1.0"
end
