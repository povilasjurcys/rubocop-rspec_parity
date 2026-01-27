# frozen_string_literal: true

RSpec.describe RuboCop::Cop::SpecParity::SufficientContexts do
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
            ^^^^^^^^^^^^^^^^^^^^^^^ SpecParity/SufficientContexts: Method `create_user` has 2 branches but only 1 context in spec. Add 1 more context to cover all branches.
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
  end
end
