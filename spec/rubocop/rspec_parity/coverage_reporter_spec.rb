# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "rubocop/rspec_parity/coverage_reporter"

RSpec.describe RuboCop::RSpecParity::CoverageReporter do
  def write_file(dir, relative, content)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  let(:source) do
    <<~RUBY
      class Classifier
        def classify(user)
          if user.admin?
            :admin
          elsif user.staff?
            :staff
          else
            :guest
          end
        end
      end
    RUBY
  end

  it "lists branches without a covering annotation as paste-ready stubs" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/classifier.rb", source)
      write_file(dir, "spec/services/classifier_spec.rb", <<~RUBY)
        RSpec.describe Classifier do
          describe '#classify' do
            context 'admin' do # rspec_parity:covers user.admin?
              it { is_expected.to eq(:admin) }
            end
          end
        end
      RUBY

      output = described_class.new(source_path).render

      expect(output).to include("# classify — 2 uncovered branches:")
      expect(output).to include("# rspec_parity:covers user.staff?")
      expect(output).to include("# rspec_parity:covers else of user.admin?")
      expect(output).to include("it '...' do")
      expect(output).not_to include("# rspec_parity:covers user.admin?\n")
    end
  end

  it "lists every branch when the spec file is missing (bootstrap)" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/classifier.rb", source)

      output = described_class.new(source_path).render

      expect(output).to include("# classify — 3 branches:")
      expect(output).to include("rspec_parity:covers user.admin?")
      expect(output).to include("rspec_parity:covers user.staff?")
    end
  end

  it "renders nothing when every branch is already annotated" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/classifier.rb", source)
      write_file(dir, "spec/services/classifier_spec.rb", <<~RUBY)
        RSpec.describe Classifier do
          describe '#classify' do
            context 'a' do # rspec_parity:covers user.admin?
              it { is_expected.to eq(:admin) }
            end
            context 'b' do # rspec_parity:covers user.staff?
              it { is_expected.to eq(:staff) }
            end
            context 'c' do # rspec_parity:covers else of user.admin?
              it { is_expected.to eq(:guest) }
            end
          end
        end
      RUBY

      expect(described_class.new(source_path).render).to eq("")
    end
  end

  it "reports only the method enclosing the given line" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/pair.rb", <<~RUBY)
        class Pair
          def first(x)
            x ? 1 : 2
          end

          def second(y)
            if y then 1 else 2 end
          end
        end
      RUBY

      output = described_class.new(source_path, line: 6).render

      expect(output).to include("# second —")
      expect(output).to include("rspec_parity:covers y")
      expect(output).not_to include("# first —")
    end
  end

  it "notes un-annotated specs it can't attribute, and what is already annotated" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/classifier.rb", source)
      write_file(dir, "spec/services/classifier_spec.rb", <<~RUBY)
        RSpec.describe Classifier do
          describe '#classify' do
            context 'admin' do
              it { is_expected.to eq(:admin) }
            end

            context 'staff' do # rspec_parity:covers user.staff?
              it { is_expected.to eq(:staff) }
            end
          end
        end
      RUBY

      output = described_class.new(source_path).render

      expect(output).to include("# already annotated as covered: user.staff?")
      expect(output).to include("# note: 1 example(s)/context(s) here aren't annotated")
    end
  end

  it "gives each branch of a compound condition a distinct 1:1 label" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/gate.rb", <<~RUBY)
        class Gate
          def allow?(a, b)
            if a && b
              :yes
            else
              :no
            end
          end
        end
      RUBY

      output = described_class.new(source_path).render

      expect(output).to include("# rspec_parity:covers a && b\n")
      expect(output).to include("# rspec_parity:covers a && b (b decides)")
      expect(output).to include("# rspec_parity:covers else of a && b")
    end
  end

  it "positionally disambiguates two branches with identical source" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/dup.rb", <<~RUBY)
        class Dup
          def categorize(x)
            if x.zero?
              :a
            else
              :b
            end

            if x.zero?
              :c
            else
              :d
            end
          end
        end
      RUBY

      output = described_class.new(source_path).render

      expect(output).to include("# rspec_parity:covers x.zero? (1)")
      expect(output).to include("# rspec_parity:covers x.zero? (2)")
      expect(output).to include("# rspec_parity:covers else of x.zero? (1)")
      expect(output).to include("# rspec_parity:covers else of x.zero? (2)")
    end
  end

  it "honours an explicitly provided spec path" do
    Dir.mktmpdir do |dir|
      source_path = write_file(dir, "app/services/classifier.rb", source)
      spec_path = write_file(dir, "elsewhere/classifier_spec.rb", <<~RUBY)
        RSpec.describe Classifier do
          describe '#classify' do
            context 'admin' do # rspec_parity:covers user.admin?
              it { is_expected.to eq(:admin) }
            end
          end
        end
      RUBY

      output = described_class.new(source_path, spec_path: spec_path).render

      expect(output).to include("# classify — 2 uncovered branches:")
    end
  end
end
