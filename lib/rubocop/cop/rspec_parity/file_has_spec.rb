# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecParity
      # Checks that each Ruby file in the app directory has a corresponding spec file.
      #
      # @example
      #   # bad - app/models/user.rb exists but spec/models/user_spec.rb doesn't
      #
      #   # good - both files exist:
      #   # app/models/user.rb
      #   # spec/models/user_spec.rb
      #
      class FileHasSpec < Base
        MSG = "Missing spec file. Expected %<spec_path>s"

        COVERED_DIRECTORIES = %w[models controllers services jobs mailers helpers].freeze

        def on_new_investigation
          return unless checkable_file?

          spec_path = expected_spec_path
          return if File.exist?(spec_path)

          message = format(MSG, spec_path: relative_spec_path(spec_path))
          add_offense(processed_source.buffer.source_range, message: message)
        end

        private

        def checkable_file?
          path = processed_source.file_path
          return false unless path
          return false if path.end_with?("_spec.rb")

          COVERED_DIRECTORIES.any? { |dir| path.include?("/app/#{dir}/") }
        end

        def expected_spec_path
          processed_source.file_path.sub("/app/", "/spec/").sub(/\.rb$/, "_spec.rb")
        end

        def relative_spec_path(spec_path)
          root = find_project_root
          root ? spec_path.sub("#{root}/", "") : spec_path
        end

        def find_project_root
          path = processed_source.file_path
          return nil if path.nil?

          app_index = path.split("/").index("app")
          app_index ? path.split("/")[0...app_index].join("/") : nil
        end
      end
    end
  end
end
