# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecParity
      # Checks that each Ruby file in the app directory has a corresponding spec file.
      #
      # @example
      #   # bad - app/models/user.rb exists but spec/models/user_spec.rb does not
      #
      #   # good - app/models/user.rb has a matching spec/models/user_spec.rb
      #
      class FileHasSpec < Base
        include DepartmentConfig

        MSG = "Missing spec file. Expected %<spec_path>s to exist"

        def on_new_investigation
          return unless should_check_file?

          spec_paths = expected_spec_paths
          return if spec_paths.empty?
          return if spec_paths.any? { |path| File.exist?(path) }

          add_offense(
            processed_source.ast || processed_source.tokens.first,
            message: format(MSG, spec_path: relative_spec_path(spec_paths.first))
          )
        end

        private

        def should_check_file?
          path = processed_source.file_path
          return false unless path && !path.end_with?("_spec.rb")

          matches_any_mapping?(path)
        end
      end
    end
  end
end
