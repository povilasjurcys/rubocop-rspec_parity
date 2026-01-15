# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      # Disallows the use of `let!` in specs.
      #
      # `let!` creates implicit setup that runs before each example,
      # which can make tests harder to understand and debug.
      # Prefer using `let` with explicit references or `before` blocks.
      #
      # @example
      #   # bad
      #   let!(:user) { create(:user) }
      #
      #   # good
      #   let(:user) { create(:user) }
      #
      #   # good
      #   before { create(:user) }
      #
      class NoLetBang < Base
        MSG = 'Do not use `let!`. Use `let` with explicit reference or `before` block instead.'

        # @!method let_bang?(node)
        def_node_matcher :let_bang?, '(send nil? :let! ...)'

        def on_send(node)
          return unless let_bang?(node)

          add_offense(node)
        end
      end
    end
  end
end
