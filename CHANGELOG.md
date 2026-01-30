## [Unreleased]

Added: Support for checking wildcard spec files (`<model>_*_spec.rb`) in addition to base spec file, with automatic class validation
Added: `SkipMethodDescribeFor` configuration for `PublicMethodHasSpec` and `SufficientContexts` cops to allow single-method classes (like service objects) to skip method describe blocks in specs

## [1.0.0] - 2026-01-27

Added: `IgnoreMemoization` configuration option for `SufficientContexts` cop to ignore memoization patterns like `@var ||=` and `return @var if defined?(@var)`
Fixed: `SufficientContexts` cop now works with absolute file paths
Removed: `NoLetBang` cop

## [0.1.0] - 2026-01-15

- Initial release
