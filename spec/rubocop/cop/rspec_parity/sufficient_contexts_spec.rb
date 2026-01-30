# frozen_string_literal: true

RSpec.describe RuboCop::Cop::RSpecParity::SufficientContexts do
  subject(:cop) { described_class.new }

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
            ^^^^^^^^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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
          ^^^^^^^^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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

      it "still counts all direct examples as 1 scenario" do
        expect_offense(<<~RUBY, source_path)
          def create_user(params)
          ^^^^^^^^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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
          ^^^^^^^^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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
          ^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `cached_value` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
            @cached_value ||= if some_condition
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
          ^^^^^^^^^^^^^^^^ Method `cached_value` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
            @cached_value ||= expensive_operation
          end
        RUBY
      end

      it "counts return @var if defined?(@var) as a branch" do
        expect_offense(<<~RUBY, source_path)
          def cached_value
          ^^^^^^^^^^^^^^^^ Method `cached_value` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
            return @cached_value if defined?(@cached_value)
            @cached_value = expensive_operation
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
          ^^^^^^^^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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
          ^^^^^^^^^^^^^^^^^^^^^^^ RSpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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
end
