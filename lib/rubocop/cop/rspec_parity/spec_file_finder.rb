# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecParity
      # Shared module for finding and validating spec files
      module SpecFileFinder
        private

        def extract_class_name(node)
          class_node = find_class_or_module(node)

          if class_node
            # Get the class/module name from the AST
            const_node = class_node.children[0]
            return const_node.const_name if const_node.const_type?
          end

          # Fallback: infer class name from file path
          infer_class_name_from_path
        end

        def find_class_or_module(node)
          node.each_ancestor.find { |n| n.class_type? || n.module_type? }
        end

        def infer_class_name_from_path
          path = source_file_path
          return nil unless path

          # Extract filename and convert to class name
          # e.g., app/services/user_creator.rb → UserCreator
          filename = File.basename(path, ".rb")
          filename.split("_").map(&:capitalize).join
        end

        def find_valid_spec_files(class_name, base_spec_path)
          return [] unless base_spec_path

          valid_files = []

          # Always include the base spec file if it exists (maintains original behavior)
          valid_files << base_spec_path if File.exist?(base_spec_path)

          # Also check for wildcard spec files (e.g., user_updates_spec.rb)
          # But only include them if they describe the correct class
          spec_dir = File.dirname(base_spec_path)
          base_name = File.basename(base_spec_path, "_spec.rb")
          wildcard_files = Dir.glob(File.join(spec_dir, "#{base_name}_*_spec.rb"))

          wildcard_files.each do |file|
            valid_files << file if File.exist?(file) && spec_describes_class?(file, class_name)
          end

          valid_files.uniq
        end

        def spec_describes_class?(spec_path, class_name)
          spec_content = File.read(spec_path)
          # Match RSpec.describe ClassName or describe ClassName
          spec_content.match?(/(?:RSpec\.)?describe\s+#{Regexp.escape(class_name)}(?:\s|,|do)/)
        end

        def describe_aliases_for(describe_key)
          value = @describe_aliases[describe_key]
          return [] unless value

          Array(value).map(&:to_s)
        end

        # Override this method in the including class
        def source_file_path
          processed_source.file_path
        end
      end
    end
  end
end
