# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecParity
      # Shared module for reading department-level configuration.
      # Provides config resolution (cop-level > department-level > default),
      # spec file path mappings, and shared describe aliases / skip paths.
      module DepartmentConfig
        private

        def department_config
          @department_config ||= config["RSpecParity"] || {}
        end

        def spec_file_path_mappings
          resolve_config("SpecFilePathMappings", { "app/" => ["spec/"] })
        end

        def shared_describe_aliases
          resolve_config("DescribeAliases", {})
        end

        def shared_skip_method_describe_paths
          resolve_config("SkipMethodDescribeFor", [])
        end

        def expected_spec_paths(source_path = nil) # rubocop:disable Metrics/MethodLength
          source_path ||= processed_source.file_path
          return [] unless source_path

          paths = []
          spec_file_path_mappings.each do |source_dir, spec_dirs|
            next unless path_matches_mapping?(source_path, source_dir)

            Array(spec_dirs).each do |spec_dir|
              spec_path = substitute_path(source_path, source_dir, spec_dir)
              paths << spec_path if spec_path
            end
          end
          paths.uniq
        end

        def matches_any_mapping?(source_path)
          spec_file_path_mappings.any? do |source_dir, _|
            path_matches_mapping?(source_path, source_dir)
          end
        end

        def relative_spec_path(spec_path)
          source_path = processed_source.file_path
          return spec_path unless source_path

          root = find_project_root(source_path)
          root ? spec_path.sub("#{root}/", "") : spec_path
        end

        def resolve_config(key, default)
          if cop_config.key?(key)
            cop_config[key]
          elsif department_config.key?(key)
            department_config[key]
          else
            default
          end
        end

        def path_matches_mapping?(source_path, source_dir)
          source_path.include?("/#{source_dir}") || source_path.start_with?(source_dir)
        end

        def substitute_path(source_path, source_dir, spec_dir)
          result = if source_path.include?("/#{source_dir}")
                     source_path.sub("/#{source_dir}", "/#{spec_dir}")
                   elsif source_path.start_with?(source_dir)
                     source_path.sub(source_dir, spec_dir)
                   end
          result&.sub(/\.rb$/, "_spec.rb")
        end

        def find_project_root(source_path)
          spec_file_path_mappings.each_key do |source_dir|
            first_dir = source_dir.split("/").first
            parts = source_path.split("/")
            dir_index = parts.index(first_dir)
            next unless dir_index&.positive?

            return parts[0...dir_index].join("/")
          end
          nil
        end
      end
    end
  end
end
