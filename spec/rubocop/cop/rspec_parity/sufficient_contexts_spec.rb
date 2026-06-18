# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecParity::SufficientContexts, :config do
  let(:spec_path) { "spec/services/user_creator_spec.rb" }
  let(:source_path) { "app/services/user_creator.rb" }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:exist?).with(spec_path).and_return(spec_exists)
    allow(File).to receive(:read).with(spec_path).and_return(spec_content) if spec_exists
  end

  describe "methods with branches" do
    context "when spec file does not exist" do
      let(:spec_exists) { false }

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when method has if/else branches" do
      context "when spec has insufficient contexts" do
        let(:spec_exists) { true }
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#create_user' do
                context 'when admin' do
                end
              end
            end
          RUBY
        end

        it "registers an offense" do
          expect_offense(<<~RUBY, source_path)
            def create_user(params)
            ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
          RUBY
        end
      end

      context "when spec has sufficient contexts" do
        let(:spec_exists) { true }
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#create_user' do
                context 'when admin' do
                end
                context 'when not admin' do
                end
              end
            end
          RUBY
        end

        it "does not register an offense" do
          expect_no_offenses(<<~RUBY, source_path)
            def create_user(params)
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
          RUBY
        end
      end
    end

    context "when method has if/elsif/else branches" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
              context 'when moderator' do
              end
              context 'when regular user' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            elsif params[:moderator]
              create_moderator
            else
              create_regular_user
            end
          end
        RUBY
      end
    end
  end

  describe "methods without branches" do
    let(:spec_exists) { true }
    let(:spec_content) do
      <<~RUBY
        RSpec.describe UserCreator do
          describe '#simple_method' do
          end
        end
      RUBY
    end

    it "does not register an offense" do
      expect_no_offenses(<<~RUBY, source_path)
        def simple_method
          puts "Hello"
        end
      RUBY
    end
  end

  describe "methods with no specs at all" do
    let(:spec_exists) { true }
    let(:spec_content) do
      <<~RUBY
        RSpec.describe UserCreator do
          describe '#other_method' do
          end
        end
      RUBY
    end

    it "does not register an offense (PublicMethodHasSpec handles this)" do
      expect_no_offenses(<<~RUBY, source_path)
        def create_user(params)
          if params[:admin]
            create_admin
          else
            create_regular_user
          end
        end
      RUBY
    end

    context "when method name appears in unrelated context descriptions but has no describe block" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#call' do
              context 'when data is present' do
                it 'processes data' do
                end
              end
              context 'with empty data' do
                it 'skips processing' do
                end
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          def data
            if condition_a
              value_a
            elsif condition_b
              value_b
            else
              value_c
            end
          end
        RUBY
      end
    end
  end

  describe "describe blocks with examples but no contexts" do
    context "when method has 2 branches and describe has direct examples" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              it 'creates users' do
              end
            end
          end
        RUBY
      end

      it "counts direct examples as 1 scenario and registers offense" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when method has 2 branches and describe has multiple direct examples" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              it 'creates admin users' do
              end
              it 'creates regular users' do
              end
              it 'handles edge cases' do
              end
            end
          end
        RUBY
      end

      it "counts each direct example as a scenario, covering the 2 branches" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when describe has direct it block and context at same level" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              it 'does stuff' do
              end

              context 'when things get weird' do
                it 'does stuff differently' do
                end
              end
            end
          end
        RUBY
      end

      it "counts as 2 contexts (direct examples + context block)" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when describe has direct it block and multiple contexts at same level" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              it 'does the default thing' do
              end

              context 'when admin' do
                it 'creates admin' do
                end
              end

              context 'when moderator' do
                it 'creates moderator' do
                end
              end
            end
          end
        RUBY
      end

      it "counts as 3 contexts (direct examples + 2 context blocks)" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            elsif params[:moderator]
              create_moderator
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when describe has it blocks only inside contexts (not direct)" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
                it 'creates admin' do
                end
              end
            end
          end
        RUBY
      end

      it "does not count nested it blocks as additional context" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when using example keyword instead of it" do
      let(:spec_exists) { true }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              example 'creates users' do
              end
            end
          end
        RUBY
      end

      it "also counts examples as 1 scenario" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end
  end

  describe "excluded methods" do
    let(:spec_exists) { true }
    let(:spec_content) { "" }

    it "does not check initialize" do
      expect_no_offenses(<<~RUBY, source_path)
        def initialize(params)
          if params[:admin]
            @admin = true
          else
            @admin = false
          end
        end
      RUBY
    end
  end

  describe "memoization patterns" do
    let(:spec_exists) { true }
    let(:spec_content) do
      <<~RUBY
        RSpec.describe UserCreator do
          describe '#cached_value' do
            it 'returns cached value' do
            end
          end
        end
      RUBY
    end

    context "with IgnoreMemoization enabled (default)" do
      it "does not count @var ||= as a branch" do
        expect_no_offenses(<<~RUBY, source_path)
          def cached_value
            @cached_value ||= expensive_operation
          end
        RUBY
      end

      it "does not count return @var if defined?(@var) as a branch" do
        expect_no_offenses(<<~RUBY, source_path)
          def cached_value
            return @cached_value if defined?(@cached_value)
            @cached_value = expensive_operation
          end
        RUBY
      end

      it "does not count @var = value if @var.nil? as a branch" do
        expect_no_offenses(<<~RUBY, source_path)
          def cached_value
            @cached_value = expensive_operation if @cached_value.nil?
            @cached_value
          end
        RUBY
      end

      it "still counts regular branches" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Missing coverage for `some_condition` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers some_condition` to mark it covered.
            @cached_value ||= if some_condition
              value_a
            else
              value_b
            end
          end
        RUBY
      end

      it "does not count local_var ||= as a branch" do
        expect_no_offenses(<<~RUBY, source_path)
          def cached_value
            result ||= expensive_operation
            result
          end
        RUBY
      end

      it "does not count hash[key] ||= as a branch" do
        expect_no_offenses(<<~RUBY, source_path)
          def cached_value
            @cache[:key] ||= expensive_operation
          end
        RUBY
      end

      it "does not count nested hash ||= as a branch" do
        expect_no_offenses(<<~RUBY, source_path)
          def cached_value
            @cache[:foo][:bar] ||= expensive_operation
          end
        RUBY
      end

      it "still counts regular branches with local var ||=" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Missing coverage for `some_condition` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers some_condition` to mark it covered.
            result ||= if some_condition
              value_a
            else
              value_b
            end
          end
        RUBY
      end
    end

    context "with IgnoreMemoization disabled" do
      subject(:cop) { described_class.new(config) }

      let(:config) do
        RuboCop::Config.new("RSpecParity/SufficientContexts" => { "IgnoreMemoization" => false })
      end

      it "counts @var ||= as a branch" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Missing coverage for `@cached_value ||= expensive_operation (already set)` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers @cached_value ||= expensive_operation (already set)` to mark it covered.
            @cached_value ||= expensive_operation
          end
        RUBY
      end

      it "counts return @var if defined?(@var) as a branch" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Missing coverage for `defined?(@cached_value)` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers defined?(@cached_value)` to mark it covered.
            return @cached_value if defined?(@cached_value)
            @cached_value = expensive_operation
          end
        RUBY
      end

      it "counts local_var ||= as a branch" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Missing coverage for `result ||= expensive_operation (already set)` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers result ||= expensive_operation (already set)` to mark it covered.
            result ||= expensive_operation
            result
          end
        RUBY
      end

      it "counts hash[key] ||= as a branch" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Missing coverage for `@cache[:key] ||= expensive_operation (already set)` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers @cache[:key] ||= expensive_operation (already set)` to mark it covered.
            @cache[:key] ||= expensive_operation
          end
        RUBY
      end
    end
  end

  describe "file path filtering" do
    let(:spec_exists) { true }

    context "when in lib/" do
      let(:source_path) { "lib/user_helper.rb" }
      let(:spec_path) { "spec/user_helper_spec.rb" }
      let(:spec_content) { "" }

      it "does not check the method" do
        expect_no_offenses(<<~RUBY, source_path)
          def method
            if condition
              true
            else
              false
            end
          end
        RUBY
      end
    end

    context "when using absolute paths" do
      let(:source_path) { "/Users/test/myapp/app/services/user_creator.rb" }
      let(:spec_path) { "/Users/test/myapp/spec/services/user_creator_spec.rb" }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "still detects insufficient contexts" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end
  end

  describe "wildcard spec files" do
    let(:spec_exists) { true }
    let(:wildcard_spec_path) { "spec/services/user_creator_updates_spec.rb" }

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("spec/services/user_creator_*_spec.rb")
        .and_return([wildcard_spec_path])
    end

    context "when wildcard spec file describes the same class" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "aggregates contexts from both spec files" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when wildcard spec file describes a different class" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreatorUpdates do
            describe '#create_user' do
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "does not use contexts from wildcard spec file" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when base spec has no contexts but wildcard spec has sufficient contexts" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "uses contexts from wildcard spec file" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when base spec does not exist but wildcard spec does" do
      let(:spec_exists) { false }

      before do
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "uses wildcard spec file" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when method has 3 branches and contexts are split across files" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(wildcard_spec_path).and_return(true)
        allow(File).to receive(:read).with(wildcard_spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when moderator' do
              end
              context 'when regular user' do
              end
            end
          end
        RUBY
      end

      it "aggregates contexts from both files to meet requirement" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            elsif params[:moderator]
              create_moderator
            else
              create_regular_user
            end
          end
        RUBY
      end
    end
  end

  describe "DescribeAliases configuration" do
    let(:spec_exists) { true }
    let(:cop_config) do
      { "DescribeAliases" => { "#call" => ".invoke" } }
    end

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("spec/services/user_creator_*_spec.rb")
        .and_return([])
    end

    context "when alias describe has sufficient contexts" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '.invoke' do
              context 'when valid' do
              end
              context 'when invalid' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          def call(params)
            if params[:valid]
              process
            else
              raise "Invalid"
            end
          end
        RUBY
      end
    end

    context "when alias describe has insufficient contexts" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '.invoke' do
              context 'when valid' do
              end
            end
          end
        RUBY
      end

      it "registers an offense" do
        expect_offense(<<~RUBY, source_path)
          def call(params)
          ^^^^^^^^^^^^^^^^ Missing coverage for `params[:valid]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:valid]` to mark it covered.
            if params[:valid]
              process
            else
              raise "Invalid"
            end
          end
        RUBY
      end
    end

    context "when alias contexts aggregate with base contexts" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#call' do
              context 'when valid' do
              end
            end
            describe '.invoke' do
              context 'when invalid' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          def call(params)
            if params[:valid]
              process
            else
              raise "Invalid"
            end
          end
        RUBY
      end
    end

    context "with empty config" do
      let(:cop_config) { { "DescribeAliases" => {} } }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '.invoke' do
              context 'when valid' do
              end
              context 'when invalid' do
              end
            end
          end
        RUBY
      end

      it "does not count alias contexts" do
        expect_no_offenses(<<~RUBY, source_path)
          def call(params)
            if params[:valid]
              process
            else
              raise "Invalid"
            end
          end
        RUBY
      end
    end
  end

  describe "SkipMethodDescribeFor configuration" do
    let(:source_path) { "app/services/user_creator.rb" }
    let(:spec_path) { "spec/services/user_creator_spec.rb" }
    let(:spec_exists) { true }
    let(:cop_config) do
      { "SkipMethodDescribeFor" => ["app/services/**/*"] }
    end

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("spec/services/user_creator_*_spec.rb")
        .and_return([])
    end

    context "single method with branches and top-level contexts" do
      let(:spec_content) do
        <<~RUBY
          describe UserCreator do
            context 'when valid' do
              it 'creates user' do
              end
            end

            context 'when invalid' do
              it 'raises error' do
              end
            end
          end
        RUBY
      end

      it "counts top-level contexts instead of method contexts" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call(params)
              if params[:valid]
                create_user
              else
                raise "Invalid"
              end
            end
          end
        RUBY
      end
    end

    context "single method with branches but insufficient contexts" do
      let(:spec_content) do
        <<~RUBY
          describe UserCreator do
            it 'works' do
            end
          end
        RUBY
      end

      it "registers offense for insufficient coverage" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def call(params)
            ^^^^^^^^^^^^^^^^ Missing coverage for `params[:valid]` (line 3) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:valid]` to mark it covered.
              if params[:valid]
                create_user
              else
                raise "Invalid"
              end
            end
          end
        RUBY
      end
    end

    context "single method with branches and direct examples at top level" do
      let(:spec_content) do
        <<~RUBY
          describe UserCreator do
            it 'creates user when valid' do
            end

            it 'raises error when invalid' do
            end
          end
        RUBY
      end

      it "counts each top-level example as a scenario, covering the 2 branches" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call(params)
              if params[:valid]
                create_user
              else
                raise "Invalid"
              end
            end
          end
        RUBY
      end
    end

    context "single method with direct it block and context at top level" do
      let(:spec_content) do
        <<~RUBY
          describe UserCreator do
            it 'does the default thing' do
            end

            context 'when invalid' do
              it 'raises error' do
              end
            end
          end
        RUBY
      end

      it "counts as 2 contexts (direct examples + context block)" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call(params)
              if params[:valid]
                create_user
              else
                raise "Invalid"
              end
            end
          end
        RUBY
      end
    end

    context "multiple public methods" do
      let(:spec_content) do
        <<~RUBY
          describe UserCreator do
            describe '#call' do
              context 'when valid' do
                it 'creates user' do
                end
              end

              context 'when invalid' do
                it 'raises error' do
                end
              end
            end
          end
        RUBY
      end

      it "uses normal method-based counting" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call(params)
              if params[:valid]
                create_user
              else
                raise "Invalid"
              end
            end

            def another_method
              # not counted, only call checked
            end
          end
        RUBY
      end
    end
  end

  describe "modules with dual access methods" do
    let(:spec_exists) { true }

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob)
        .with("spec/services/user_creator_*_spec.rb")
        .and_return([])
    end

    context "when module uses extend self and spec uses '.method'" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '.create_user' do
              context 'when admin' do
              end
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          module UserCreator
            extend self

            def create_user(params)
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
          end
        RUBY
      end
    end

    context "when module uses module_function and spec uses '.method'" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '.create_user' do
              context 'when admin' do
              end
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          module UserCreator
            module_function

            def create_user(params)
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
          end
        RUBY
      end
    end

    context "when module uses targeted module_function and spec uses '.method'" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '.create_user' do
              context 'when admin' do
              end
              context 'when not admin' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          module UserCreator
            def create_user(params)
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
            module_function :create_user
          end
        RUBY
      end
    end
  end

  describe "department-level configuration" do
    # Satisfy the outer before block which references spec_exists/spec_content
    let(:spec_exists) { true }
    let(:spec_content) { "" }

    context "with department-level DescribeAliases" do
      let(:spec_path) { "spec/services/user_creator_spec.rb" }
      let(:source_path) { "app/services/user_creator.rb" }

      let(:config) do
        RuboCop::Config.new(
          "RSpecParity" => { "DescribeAliases" => { "#call" => ".invoke" } },
          "RSpecParity/SufficientContexts" => { "Enabled" => true, "IgnoreMemoization" => true }
        )
      end

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreator do
            describe '.invoke' do
              context 'when valid' do
              end
              context 'when invalid' do
              end
            end
          end
        RUBY
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with("spec/services/user_creator_*_spec.rb")
          .and_return([])
      end

      it "uses department-level aliases for context counting" do
        expect_no_offenses(<<~RUBY, source_path)
          def call(params)
            if params[:valid]
              process
            else
              raise "Invalid"
            end
          end
        RUBY
      end
    end

    context "with department-level SkipMethodDescribeFor" do
      let(:spec_path) { "spec/services/user_creator_spec.rb" }
      let(:source_path) { "app/services/user_creator.rb" }

      let(:config) do
        RuboCop::Config.new(
          "RSpecParity" => { "SkipMethodDescribeFor" => ["app/services/**/*"] },
          "RSpecParity/SufficientContexts" => { "Enabled" => true, "IgnoreMemoization" => true }
        )
      end

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          describe UserCreator do
            context 'when valid' do
              it 'creates user' do
              end
            end

            context 'when invalid' do
              it 'raises error' do
              end
            end
          end
        RUBY
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with("spec/services/user_creator_*_spec.rb")
          .and_return([])
      end

      it "uses department-level skip paths for top-level context counting" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def call(params)
              if params[:valid]
                create_user
              else
                raise "Invalid"
              end
            end
          end
        RUBY
      end
    end

    context "with department-level SpecFilePathMappings" do
      let(:spec_path) { "test/services/user_creator_spec.rb" }
      let(:source_path) { "src/services/user_creator.rb" }

      let(:config) do
        RuboCop::Config.new(
          "RSpecParity" => { "SpecFilePathMappings" => { "src/" => ["test/"] } },
          "RSpecParity/SufficientContexts" => { "Enabled" => true, "IgnoreMemoization" => true }
        )
      end

      before do
        allow(File).to receive(:exist?).with(spec_path).and_return(true)
        allow(File).to receive(:read).with(spec_path).and_return(<<~RUBY)
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
              context 'when not admin' do
              end
            end
          end
        RUBY
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with("test/services/user_creator_*_spec.rb")
          .and_return([])
      end

      it "uses custom path mappings to find spec files" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end
  end

  describe "tracing single-use private method branches" do
    let(:spec_exists) { true }

    context "when public method calls a single-use private helper with branches" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "inflates branch count and lists the helper in the message" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def create_user(params)
            ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `build: params[:admin]` (build line 9) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers build: params[:admin]` to mark it covered. (including branches from: build)
              build(params)
            end

            private

            def build(params)
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end

    context "when spec contexts cover the inflated branch count" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
              context 'when regular' do
              end
            end
          end
        RUBY
      end

      it "does not register an offense" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def create_user(params)
              build(params)
            end

            private

            def build(params)
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end

    context "when the private helper is called from two public methods" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
            describe '#destroy_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "does not inflate branches for either caller" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def create_user(params); build(params); end
            def destroy_user(params); build(params); end

            private

            def build(params)
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end

    context "when the class contains dynamic dispatch" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "does not inflate branches and keeps the original message" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def create_user(params); build(params); end
            def call_dynamic(name); send(name); end

            private

            def build(params)
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end

    context "when a branchless helper sits between caller and a branchy helper" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "names only the branchy helper in the message" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def create_user(params)
            ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `build: params[:admin]` (build line 13) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers build: params[:admin]` to mark it covered. (including branches from: build)
              passthrough(params)
            end

            private

            def passthrough(params)
              build(params)
            end

            def build(params)
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end

    context "when the private helper memoizes with `@var ||= ...`" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "does not count memoization as a branch (same rule as public methods)" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def create_user(params)
              build(params)
            end

            private

            def build(params)
              @cached ||= expensive_lookup(params)
            end
          end
        RUBY
      end
    end

    context "when the private helper has memoization alongside a real branch" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "counts only the real branch, not the memoization" do
        expect_offense(<<~RUBY, source_path)
          class UserCreator
            def create_user(params)
            ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `build: params[:admin]` (build line 10) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers build: params[:admin]` to mark it covered. (including branches from: build)
              build(params)
            end

            private

            def build(params)
              @cached ||= fetch
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end

    context "when TraceSingleUsePrivateMethods is disabled" do
      let(:cop_config) { { "TraceSingleUsePrivateMethods" => false } }
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'when admin' do
              end
            end
          end
        RUBY
      end

      it "does not inflate branches and produces no offense for a single-context spec" do
        expect_no_offenses(<<~RUBY, source_path)
          class UserCreator
            def create_user(params)
              build(params)
            end

            private

            def build(params)
              params[:admin] ? admin : regular
            end
          end
        RUBY
      end
    end
  end

  # A compound boolean condition needs more than one scenario to exercise: each
  # operand must be shown to independently affect the outcome (condition /
  # MC/DC coverage). The cop therefore counts each `&&` / `||` as a branch on
  # top of the conditional it belongs to, so a decision with N conditions
  # requires N + 1 scenarios -- the standard MC/DC lower bound. These specs
  # characterize that intentional counting against a single-condition baseline.
  describe "compound boolean conditions require a scenario per operand (MC/DC)" do
    let(:spec_exists) { true }

    context "with a single condition" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when a is truthy' do
              end
            end
          end
        RUBY
      end

      it "needs 2 scenarios (a truthy, a falsey)" do
        expect_offense(<<~RUBY, source_path)
          def allowed?(a)
          ^^^^^^^^^^^^^^^ Missing coverage for `a` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers a` to mark it covered.
            "yes" if a
          end
        RUBY
      end
    end

    context "with an `&&` condition" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when a and b are truthy' do
              end
              context 'when a is falsey' do
              end
            end
          end
        RUBY
      end

      it "needs 3 scenarios: a&b true, a false (short-circuit), a true & b false" do
        expect_offense(<<~RUBY, source_path)
          def allowed?(a, b)
          ^^^^^^^^^^^^^^^^^^ Missing coverage for `a && b` (line 2) — 1 of 3 branches untested. Add `context '...' do # rspec_parity:covers a && b` to mark it covered.
            "yes" if a && b
          end
        RUBY
      end
    end

    context "with an `||` condition" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when a is truthy' do
              end
              context 'when a is falsey but b is truthy' do
              end
            end
          end
        RUBY
      end

      it "needs 3 scenarios: a true (short-circuit), a false & b true, both false" do
        expect_offense(<<~RUBY, source_path)
          def allowed?(a, b)
          ^^^^^^^^^^^^^^^^^^ Missing coverage for `a || b` (line 2) — 1 of 3 branches untested. Add `context '...' do # rspec_parity:covers a || b` to mark it covered.
            "yes" if a || b
          end
        RUBY
      end
    end

    context "with three conditions `a && b && c`" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when all truthy' do
              end
              context 'when a falsey' do
              end
              context 'when b falsey' do
              end
            end
          end
        RUBY
      end

      it "needs N + 1 = 4 scenarios for 3 conditions" do
        expect_offense(<<~RUBY, source_path)
          def allowed?(a, b, c)
          ^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `a && b` (line 2) — 1 of 4 branches untested. Add `context '...' do # rspec_parity:covers a && b` to mark it covered.
            "yes" if a && b && c
          end
        RUBY
      end
    end
  end

  # The unit of coverage is a test scenario, which is naturally expressed as an
  # `it`/`example`, not necessarily a `context`. MC/DC cases for a compound
  # condition are usually sibling examples inside one context, so examples count
  # toward the requirement -- a context whose examples each exercise a branch is
  # sufficient even without one context per branch. Empty placeholder contexts
  # still count, so this never under-counts relative to context-only counting.
  describe "counting `it` examples as scenarios" do
    let(:spec_exists) { true }

    context "when one context holds an example per branch" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'permissions' do
                it 'creates an admin' do
                end
                it 'creates a regular user' do
                end
              end
            end
          end
        RUBY
      end

      it "treats the two examples as two scenarios and registers no offense" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when examples sit directly under the method describe" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              it 'creates an admin' do
              end
              it 'creates a moderator' do
              end
              it 'creates a regular user' do
              end
            end
          end
        RUBY
      end

      it "counts each example, covering a 3-branch method" do
        expect_no_offenses(<<~RUBY, source_path)
          def create_user(params)
            if params[:admin]
              create_admin
            elsif params[:moderator]
              create_moderator
            else
              create_regular_user
            end
          end
        RUBY
      end
    end

    context "when there are fewer examples than branches" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#create_user' do
              context 'permissions' do
                it 'creates an admin' do
                end
              end
            end
          end
        RUBY
      end

      it "still registers an offense" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered.
            if params[:admin]
              create_admin
            else
              create_regular_user
            end
          end
        RUBY
      end
    end
  end

  # Guard clauses (`return`/`raise`/`next ... if/unless`) exit early; their
  # non-exit path is a single shared fall-through ("all guards pass"). A chain of
  # guards therefore needs one scenario per way a guard can FIRE, plus ONE shared
  # happy-path scenario — not one happy path per guard. Each `&&`/`||` inside a
  # guard condition is still a distinct way to fire (MC/DC per operand).
  describe "guard clauses share a single all-pass fall-through" do
    let(:spec_exists) { true }

    context "with a single guard clause" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when x is falsey (guard fires)' do
              end
            end
          end
        RUBY
      end

      it "needs 2 scenarios: guard fires, and the all-pass path" do
        expect_offense(<<~RUBY, source_path)
          def allowed?(x)
          ^^^^^^^^^^^^^^^ Missing coverage for `x` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers x` to mark it covered.
            return unless x

            do_thing
          end
        RUBY
      end
    end

    context "with an `&&` inside the guard condition" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when a is falsey' do
              end
              context 'when b is falsey' do
              end
            end
          end
        RUBY
      end

      it "needs 3 scenarios: a fires it, b fires it, and the all-pass path" do
        expect_offense(<<~RUBY, source_path)
          def allowed?(a, b)
          ^^^^^^^^^^^^^^^^^^ Missing coverage for `a && b` (line 2) — 1 of 3 branches untested. Add `context '...' do # rspec_parity:covers a && b` to mark it covered.
            return false unless a && b

            true
          end
        RUBY
      end
    end

    context "with a chain of guard clauses (the real-world case)" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when a is missing' do
              end
              context 'when b is missing' do
              end
              context 'when a is not ready' do
              end
              context 'when b is not ready' do
              end
            end
          end
        RUBY
      end

      it "counts each guard-fire once plus ONE shared happy path (5, not 6)" do
        # Two guards, each with an `&&` → 4 ways to fire + 1 all-pass = 5.
        # The all-pass path is counted once, not once per guard.
        expect_offense(<<~RUBY, source_path)
          def allowed?(a, b)
          ^^^^^^^^^^^^^^^^^^ Missing coverage for `a && b` (line 2) — 1 of 5 branches untested. Add `context '...' do # rspec_parity:covers a && b` to mark it covered.
            return false unless a && b
            return false unless a.ready? && b.ready?

            perform_action
          end
        RUBY
      end
    end

    context "with a guard clause followed by real branching" do
      let(:spec_content) do
        <<~RUBY
          RSpec.describe UserCreator do
            describe '#allowed?' do
              context 'when x is falsey (guard fires)' do
              end
              context 'when y is truthy' do
              end
            end
          end
        RUBY
      end

      it "adds no extra happy path: the trailing if/else already covers it (3)" do
        # guard fire (1) + if/else (2) = 3. No separate all-pass bonus, because
        # the post-guard branches ARE the happy-path scenarios.
        expect_offense(<<~RUBY, source_path)
          def allowed?(x, y)
          ^^^^^^^^^^^^^^^^^^ Missing coverage for `x` (line 2) — 1 of 3 branches untested. Add `context '...' do # rspec_parity:covers x` to mark it covered.
            return unless x

            if y
              handle_yes
            else
              handle_no
            end
          end
        RUBY
      end
    end

    describe "rspec_parity:covers annotations" do
      let(:spec_exists) { true }

      context "when a context is annotated for each branch" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#role_label' do
                context 'admin' do # rspec_parity:covers user.admin?
                  it 'is admin'
                end
                context 'staff' do # rspec_parity:covers user.staff?
                  it 'is staff'
                end
                context 'guest' do # rspec_parity:covers else
                  it 'is guest'
                end
              end
            end
          RUBY
        end

        it "treats every branch as covered and registers no offense" do
          expect_no_offenses(<<~RUBY, source_path)
            def role_label(user)
              if user.admin?
                'admin'
              elsif user.staff?
                'staff'
              else
                'guest'
              end
            end
          RUBY
        end
      end

      context "when annotations sit on their own line inside the context" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#role_label' do
                context 'admin' do
                  # rspec_parity:covers user.admin?
                  it 'is admin'
                end
                context 'staff' do
                  # rspec_parity:covers user.staff?
                  it 'is staff'
                end
                context 'guest' do
                  # rspec_parity:covers else
                  it 'is guest'
                end
              end
            end
          RUBY
        end

        it "attributes each standalone annotation to its context and registers no offense" do
          expect_no_offenses(<<~RUBY, source_path)
            def role_label(user)
              if user.admin?
                'admin'
              elsif user.staff?
                'staff'
              else
                'guest'
              end
            end
          RUBY
        end
      end

      context "when one context carries several annotations for the branches it exercises" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#role_label' do
                context 'privileged' do # rspec_parity:covers user.admin?
                  # rspec_parity:covers user.staff?
                  it 'is privileged'
                end
                context 'guest' do # rspec_parity:covers else
                  it 'is guest'
                end
              end
            end
          RUBY
        end

        it "lets a single context cover multiple branches and registers no offense" do
          expect_no_offenses(<<~RUBY, source_path)
            def role_label(user)
              if user.admin?
                'admin'
              elsif user.staff?
                'staff'
              else
                'guest'
              end
            end
          RUBY
        end
      end

      context "when a single annotation comment lists several branches with semicolons" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#role_label' do
                context 'privileged' do # rspec_parity:covers user.admin?; user.staff?
                  it 'is privileged'
                end
                context 'guest' do # rspec_parity:covers else
                  it 'is guest'
                end
              end
            end
          RUBY
        end

        it "treats every listed branch as covered and registers no offense" do
          expect_no_offenses(<<~RUBY, source_path)
            def role_label(user)
              if user.admin?
                'admin'
              elsif user.staff?
                'staff'
              else
                'guest'
              end
            end
          RUBY
        end
      end

      context "when only some branches are annotated" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#role_label' do
                context 'admin' do # rspec_parity:covers user.admin?
                  it 'is admin'
                end
              end
            end
          RUBY
        end

        it "points at a branch with no covering annotation" do
          expect_offense(<<~RUBY, source_path)
            def role_label(user)
            ^^^^^^^^^^^^^^^^^^^^ Missing coverage for `user.staff?` (line 4) — 2 of 3 branches untested. Add `context '...' do # rspec_parity:covers user.staff?` to mark it covered.
              if user.admin?
                'admin'
              elsif user.staff?
                'staff'
              else
                'guest'
              end
            end
          RUBY
        end
      end

      context "when an annotated context holds several examples" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#role_label' do
                context 'admin' do # rspec_parity:covers user.admin?
                  it 'is admin'
                  it 'also logs'
                  it 'also audits'
                end
              end
            end
          RUBY
        end

        it "collapses the examples into the one annotated branch" do
          # Without the collapse the three `it`s would count as three scenarios
          # and mask the two untested branches; the annotation pins them to one.
          expect_offense(<<~RUBY, source_path)
            def role_label(user)
            ^^^^^^^^^^^^^^^^^^^^ Missing coverage for `user.staff?` (line 4) — 2 of 3 branches untested. Add `context '...' do # rspec_parity:covers user.staff?` to mark it covered.
              if user.admin?
                'admin'
              elsif user.staff?
                'staff'
              else
                'guest'
              end
            end
          RUBY
        end
      end

      context "when an annotation matches no branch" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#create_user' do
                context 'admin' do # rspec_parity:covers params[:admni]
                  it 'creates an admin'
                end
              end
            end
          RUBY
        end

        it "reports the orphan annotation with a did-you-mean suggestion" do
          expect_offense(<<~RUBY, source_path)
            def create_user(params)
            ^^^^^^^^^^^^^^^^^^^^^^^ Missing coverage for `params[:admin]` (line 2) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers params[:admin]` to mark it covered. `rspec_parity:covers` annotation `params[:admni]` matches no branch — did you mean `params[:admin]`?
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
          RUBY
        end
      end

      context "when a bare condition annotates a traced private branch" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#visible?' do
                context 'active or pending' do # rspec_parity:covers user.status == 'active' || user.status == 'pending'
                  it 'is visible'
                end
              end
            end
          RUBY
        end

        it "matches without the origin prefix and leaves only the guard uncovered" do
          expect_offense(<<~RUBY, source_path)
            class UserCreator
              def visible?(user)
              ^^^^^^^^^^^^^^^^^^ Missing coverage for `user` (line 3) — 1 of 2 branches untested. Add `context '...' do # rspec_parity:covers user` to mark it covered. (including branches from: flag_check)
                return false unless user

                flag_check(user)
              end

              private

              def flag_check(user)
                user.status == 'active' || user.status == 'pending'
              end
            end
          RUBY
        end
      end

      context "when CoversAnnotations is disabled" do
        let(:cop_config) { { "CoversAnnotations" => false } }
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#create_user' do
                context 'admin' do # rspec_parity:covers params[:admin]
                  it 'creates an admin'
                end
              end
            end
          RUBY
        end

        it "ignores annotations and uses the legacy message" do
          expect_offense(<<~RUBY, source_path)
            def create_user(params)
            ^^^^^^^^^^^^^^^^^^^^^^^ Method `create_user` is missing coverage for 1 of 2 branches.
              if params[:admin]
                create_admin
              else
                create_regular_user
              end
            end
          RUBY
        end
      end

      context "when a method has many branches" do
        let(:spec_content) do
          <<~RUBY
            RSpec.describe UserCreator do
              describe '#classify' do
                context 'a' do
                end
              end
            end
          RUBY
        end

        it "points at the rspec-parity-cover CLI instead of naming one branch" do
          expect_offense(<<~RUBY, source_path)
            def classify(kind)
            ^^^^^^^^^^^^^^^^^^ 9 of 10 branches untested. Run `bundle exec rspec-parity-cover app/services/user_creator.rb:1` for the full list.
              case kind
              when :a then 1
              when :b then 2
              when :c then 3
              when :d then 4
              when :e then 5
              when :f then 6
              when :g then 7
              when :h then 8
              when :i then 9
              else 0
              end
            end
          RUBY
        end
      end
    end
  end
end
