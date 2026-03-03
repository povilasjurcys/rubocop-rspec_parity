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
        MSG = "Missing spec file. Expected %<spec_path>s to exist"

        def on_new_investigation
          return unless should_check_file?

          spec_path = expected_spec_path
          return if File.exist?(spec_path)

          add_offense(
            processed_source.ast || processed_source.tokens.first,
            message: format(MSG, spec_path: relative_spec_path(spec_path))
          )
        end

        private

        def should_check_file?
          path = processed_source.file_path
          path&.include?("/app/") && !path.end_with?("_spec.rb")
        end

        def expected_spec_path
          processed_source.file_path.sub("/app/", "/spec/").sub(/\.rb$/, "_spec.rb")
        end

        def relative_spec_path(spec_path)
          parts = processed_source.file_path.split("/")
          app_index = parts.index("app")
          return spec_path unless app_index

          root = parts[0...app_index].join("/")
          spec_path.sub("#{root}/", "")
        end
      end
    end
  end
end
