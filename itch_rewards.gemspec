# frozen_string_literal: true

require_relative "lib/itch_rewards/version"

Gem::Specification.new do |spec|
  spec.name          = "itch_rewards"
  spec.version       = ItchRewards::VERSION
  spec.authors       = ["Billiam"]
  spec.email         = ["billiamthesecond@gmail.com"]

  spec.summary       = "Itch community copy automation utility"
  spec.description   = "Automatically update available rewards based on purchases"
  spec.homepage      = "https://github.com/Billiam/itch-community-rewards"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = ['itch-rewards']
  spec.require_paths = ["lib"]

  spec.add_dependency "itch_client", "~> 0.4.1"
  spec.add_dependency "dry-cli", "~> 0.7.0"
  spec.add_dependency "tty-prompt", "~> 0.23.1"
  spec.add_dependency "tty-table", "~> 0.12.0"
  spec.add_dependency "pastel", "~> 0.8.0"
end
