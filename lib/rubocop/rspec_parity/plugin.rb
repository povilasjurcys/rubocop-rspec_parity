# frozen_string_literal: true

require "lint_roller"

module RuboCop
  module RSpecParity
    # LintRoller plugin for RuboCop integration (RuboCop >= 1.72)
    class Plugin < LintRoller::Plugin
      def about
        LintRoller::About.new(
          name: "rubocop-rspec_parity",
          version: VERSION,
          homepage: "https://github.com/example/rubocop-rspec_parity",
          description: "RuboCop cops for RSpec parity checks"
        )
      end

      def supported?(context)
        context.engine == :rubocop
      end

      def rules(_context)
        project_root = Pathname.new(__dir__).join("../../..")

        LintRoller::Rules.new(
          type: :path,
          config_format: :rubocop,
          value: project_root.join("config", "default.yml")
        )
      end
    end
  end
end
