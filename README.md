# RuboCop SpecParity

A RuboCop plugin that enforces spec parity and best practices in RSpec test suites. This gem helps ensure your Ruby code has proper test coverage and follows RSpec conventions.

## Features

This plugin provides these custom cops:

- **SpecParity/FileHasSpec**: Ensures every Ruby file in your app directory has a corresponding spec file
- **SpecParity/PublicMethodHasSpec**: Ensures every public method has spec test coverage
- **SpecParity/SufficientContexts**: Ensures specs have at least as many contexts as the method has branches (if/elsif/else, case/when, &&, ||, ternary operators)
- **SpecParity/NoLetBang**: Disallows the use of `let!` in specs, encouraging explicit setup

## Examples

### SpecParity/FileHasSpec

Ensures every Ruby file in your app directory has a corresponding spec file.

```ruby
# bad - app/models/user.rb exists but spec/models/user_spec.rb doesn't
# This will trigger an offense

# good - both files exist:
# app/models/user.rb
# spec/models/user_spec.rb
```

### SpecParity/PublicMethodHasSpec

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

### SpecParity/SufficientContexts

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
```

### SpecParity/NoLetBang

Disallows the use of `let!` in specs, encouraging explicit setup.

```ruby
# bad
RSpec.describe User do
  let!(:user) { create(:user) }

  it 'does something' do
    expect(user).to be_valid
  end
end

# good - use let with explicit reference
RSpec.describe User do
  let(:user) { create(:user) }

  it 'does something' do
    expect(user).to be_valid  # Explicit reference
  end
end

# good - use before block when setup is needed
RSpec.describe User do
  let(:user) { build(:user) }

  before do
    user.save!  # Explicit setup in before block
  end

  it 'does something' do
    expect(user).to be_persisted
  end
end
```

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
gem 'rubocop-spec_parity', require: false
```

And then execute:

```bash
bundle install
```

Or install it directly:

```bash
gem install rubocop-spec_parity
```

## Usage

Add `rubocop-spec_parity` to your `.rubocop.yml`:

```yaml
require:
  - rubocop-spec_parity

# For RuboCop >= 1.72
plugins:
  - rubocop-spec_parity
```

The default configuration enables all cops. You can customize them in your `.rubocop.yml`:

```yaml
SpecParity/FileHasSpec:
  Enabled: true
  Include:
    - 'app/**/*.rb'
  Exclude:
    - 'app/assets/**/*'
    - 'app/views/**/*'

SpecParity/PublicMethodHasSpec:
  Enabled: true
  Include:
    - 'app/**/*.rb'

SpecParity/SufficientContexts:
  Enabled: true
  Include:
    - 'app/**/*.rb'
  Exclude:
    - 'app/assets/**/*'
    - 'app/views/**/*'

SpecParity/NoLetBang:
  Enabled: true
  Include:
    - 'spec/**/*_spec.rb'
```

Run RuboCop as usual:

```bash
bundle exec rubocop
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/povilasjurcys/rubocop-spec_parity. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/povilasjurcys/rubocop-spec_parity/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RuboCop SpecParity project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/povilasjurcys/rubocop-spec_parity/blob/main/CODE_OF_CONDUCT.md).
