# RuboCop RSpecParity

A RuboCop plugin that enforces spec parity and best practices in RSpec test suites. This gem helps ensure your Ruby code has proper test coverage and follows RSpec conventions.

## Features

This plugin provides these custom cops:

- **RSpecParity/FileHasSpec**: Ensures every Ruby file in your app directory has a corresponding spec file
- **RSpecParity/PublicMethodHasSpec**: Ensures every public method has spec test coverage
- **RSpecParity/SufficientContexts**: Ensures specs have at least as many contexts as the method has branches (if/elsif/else, case/when, &&, ||, ternary operators)

## Examples

### RSpecParity/FileHasSpec

Ensures every Ruby file in your app directory has a corresponding spec file.

```ruby
# bad - app/models/user.rb exists but spec/models/user_spec.rb doesn't
# This will trigger an offense

# good - both files exist:
# app/models/user.rb
# spec/models/user_spec.rb
```

### RSpecParity/PublicMethodHasSpec

Ensures every public method has spec test coverage.

```ruby
# bad - app/services/user_creator.rb
class UserCreator
  def create(params)  # No spec coverage for this method
    User.create(params)
  end
end

# good - app/services/user_creator.rb with spec/services/user_creator_spec.rb
class UserCreator
  def create(params)
    User.create(params)
  end
end

# spec/services/user_creator_spec.rb
RSpec.describe UserCreator do
  describe '#create' do
    it 'creates a user' do
      # test implementation
    end
  end
end
```

#### SkipMethodDescribeFor Configuration

For service objects and similar patterns with a single public method, you can skip the method describe block:

```yaml
RSpecParity/PublicMethodHasSpec:
  SkipMethodDescribeFor:
    - 'app/services/**/*'
    - 'app/operations/**/*'

RSpecParity/SufficientContexts:
  SkipMethodDescribeFor:
    - 'app/services/**/*'
    - 'app/operations/**/*'
```

With this configuration:

```ruby
# app/services/user_creator.rb
class UserCreator
  def call(params)
    User.create(params)
  end

  private

  def validate(params)
    # Private helper - doesn't count
  end
end

# spec/services/user_creator_spec.rb - Valid!
RSpec.describe UserCreator do
  it 'creates a user' do
    # test implementation
  end

  context 'when invalid params' do
    it 'raises error' do
    end
  end
end
```

**Requirements:**
- Class must have exactly ONE public method
- Spec must contain at least one example (`it`, `example`, or `specify`)
- Traditional method describes still work if you prefer them

**How it works:**
- `PublicMethodHasSpec`: Instead of requiring `describe '#call'`, it just checks that examples exist
- `SufficientContexts`: Counts top-level contexts/examples instead of looking inside method describes

#### DescribeAliases Configuration

When an instance method is tested via a class method (e.g., service objects where `def call` is tested via `describe '.call'`, or jobs where `def perform` is tested via `describe '.perform_later'`), you can configure describe aliases:

```yaml
RSpecParity/PublicMethodHasSpec:
  DescribeAliases:
    '#call': '.call'
    '#perform':
      - '.perform_later'
      - '.perform_now'

RSpecParity/SufficientContexts:
  DescribeAliases:
    '#call': '.call'
    '#perform':
      - '.perform_later'
      - '.perform_now'
```

With this configuration:

```ruby
# app/services/user_creator.rb
class UserCreator
  def call(params)
    User.create(params)
  end
end

# spec/services/user_creator_spec.rb - Valid!
# The alias '#call' => '.call' allows .call to satisfy #call
RSpec.describe UserCreator do
  describe '.call' do
    it 'creates a user' do
      # test implementation
    end
  end
end
```

```ruby
# app/jobs/user_job.rb
class UserJob
  def perform(params)
    process(params)
  end
end

# spec/jobs/user_job_spec.rb - Valid!
# The alias '#perform' => ['.perform_later', '.perform_now'] allows either
RSpec.describe UserJob do
  describe '.perform_later' do
    it 'processes params' do
      # test implementation
    end
  end
end
```

**Notes:**
- Keys use `#` for instance method describes, `.` for class method describes
- Values can be a single string or an array of strings
- Aliases are unidirectional: `'#call': '.call'` allows `.call` to satisfy `#call`, but not vice versa
- `SufficientContexts` aggregates contexts from both the original and alias describe blocks

### RSpecParity/SufficientContexts

Ensures specs have at least as many contexts as the method has branches.

```ruby
# bad - app/services/user_creator.rb
def create_user(params)
  if params[:admin]
    create_admin(params)
  elsif params[:moderator]
    create_moderator(params)
  else
    create_regular_user(params)
  end
end

# spec/services/user_creator_spec.rb - only 1 context for 3 branches
RSpec.describe UserCreator do
  describe '#create_user' do
    context 'when creating users' do
      # Only one context for 3 branches - triggers offense
    end
  end
end

# good - 3 contexts for 3 branches
RSpec.describe UserCreator do
  describe '#create_user' do
    context 'when admin' do
      # tests admin branch
    end

    context 'when moderator' do
      # tests moderator branch
    end

    context 'when regular user' do
      # tests regular user branch
    end
  end
end

# Memoization patterns are ignored by default
def cached_value
  @cached_value ||= expensive_operation  # Not counted as a branch
end

def cached_value
  return @cached_value if defined?(@cached_value)  # Not counted as a branch
  @cached_value = expensive_operation
end
```

**Configuration options:**

- `IgnoreMemoization` (default: `true`) - When enabled, common memoization patterns like `@var ||=` and `return @var if defined?(@var)` are not counted as branches. Set to `false` if you want to count these as branches.

## Assumptions

These cops work based on the following conventions:

- **File organization**: Each Ruby file has a corresponding spec file stored in the `spec/` directory, mirroring the same directory structure. For example, `app/models/user.rb` should have a spec at `spec/models/user_spec.rb`.
- **Spec file naming**: Spec files use the `_spec.rb` suffix.
- **Instance method specs**: Instance methods are tested using the convention `describe '#method_name' do`.
- **Class method specs**: Class methods are tested using the convention `describe '.class_method' do`.
- **Context blocks for branches**: The `SufficientContexts` cop counts `context` blocks within a method's `describe` block to ensure each branch path is tested.

If your project uses different conventions, these cops may not work as expected.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rubocop-rspec_parity', require: false
```

And then execute:

```bash
bundle install
```

Or install it directly:

```bash
gem install rubocop-rspec_parity
```

## Usage

Add `rubocop-rspec_parity` to your `.rubocop.yml`:

```yaml
require:
  - rubocop-rspec_parity

# For RuboCop >= 1.72
plugins:
  - rubocop-rspec_parity
```

The default configuration enables all cops. You can customize them in your `.rubocop.yml`:

```yaml
RSpecParity/FileHasSpec:
  Enabled: true
  Include:
    - 'app/**/*.rb'
  Exclude:
    - 'app/assets/**/*'
    - 'app/views/**/*'

RSpecParity/PublicMethodHasSpec:
  Enabled: true
  SkipMethodDescribeFor: []  # Paths where single-method classes don't need method describe
  DescribeAliases: {}  # Map describe strings to aliases, e.g. '#call': '.call'
  Include:
    - 'app/**/*.rb'

RSpecParity/SufficientContexts:
  Enabled: true
  IgnoreMemoization: true  # Set to false to count memoization patterns as branches
  SkipMethodDescribeFor: []  # Paths where single-method classes use top-level contexts
  DescribeAliases: {}  # Map describe strings to aliases, e.g. '#call': '.call'
  Include:
    - 'app/**/*.rb'
  Exclude:
    - 'app/assets/**/*'
    - 'app/views/**/*'
```

Run RuboCop as usual:

```bash
bundle exec rubocop
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/povilasjurcys/rubocop-rspec_parity. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/povilasjurcys/rubocop-rspec_parity/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RuboCop RSpecParity project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/povilasjurcys/rubocop-rspec_parity/blob/main/CODE_OF_CONDUCT.md).
