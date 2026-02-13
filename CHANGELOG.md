## [Unreleased]

## [1.3.0] - 2026-02-13

Added: `IgnoreMemoization` now skips all `||=` patterns including local variables and hash keys, not just instance variables

## [1.2.4] - 2026-02-10

Fixed: `PublicMethodHasSpec` correctly counts methods re-publicized with `public :method_name` and `public def method_name` for SkipMethodDescribeFor validation

## [1.2.3] - 2026-02-10

Fixed: `PublicMethodHasSpec` correctly detects visibility for `private :method_name`, `protected :method_name`, `private def method_name`, `protected def method_name`, and `private`/`protected` inside `class << self`

## [1.2.2] - 2026-02-10

Added: `PublicMethodHasSpec` now skips class methods marked with `private_class_method` (both inline and post-hoc forms)

## [1.2.1] - 2026-02-09

Fixed: Detect tested methods correctly for classes nested inside modules (e.g. `Calendar::UserCreator`)

## [1.2.0] - 2026-02-09

Added: `SufficientContexts` now counts direct `it` blocks alongside `context` blocks as an additional implicit context

## [1.1.0] - 2026-02-06

Added: Support for checking wildcard spec files (`<model>_*_spec.rb`) in addition to base spec file, with automatic class validation
Added: `SkipMethodDescribeFor` configuration for `PublicMethodHasSpec` and `SufficientContexts` cops to allow single-method classes (like service objects) to skip method describe blocks in specs
Added: `DescribeAliases` configuration for mapping describe strings to alias describe patterns

## [1.0.0] - 2026-01-27

Added: `IgnoreMemoization` configuration option for `SufficientContexts` cop to ignore memoization patterns like `@var ||=` and `return @var if defined?(@var)`
Fixed: `SufficientContexts` cop now works with absolute file paths
Removed: `NoLetBang` cop

## [0.1.0] - 2026-01-15

- Initial release
