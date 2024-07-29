# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Implemented price caching mechanism in `get_current_price` function to reduce unnecessary oracle calls within the same block.

## [1.3.1] - 2024-06-03

### Fixed

- Add check when setting LPool and locked balance

## [1.3.0] - 2024-04-19

### Added

- `get_fees_percentage` view function

## [1.2.0] - 2024-03-11

### Added

- Support for STRK/USDC pools.
- Bump `starknet` version to `v2.3.1`

## [1.1.0] - 2024-03-11

### Added

- Pricing for Starknet Token (STRK).

## [1.0.1] - 2024-01-09

### Fixed

- Issues found in the [audit by Nethermind](https://carmine.finance/carmine-audit-by-nethermind.pdf).

## [1.0.0] - 2024-01-09

### Added

- Initial release.

[Unreleased]: https://github.com/CarmineOptions/protocol-cairo1/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/CarmineOptions/protocol-cairo1/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/CarmineOptions/protocol-cairo1/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/CarmineOptions/protocol-cairo1/compare/v1.1.1...v1.2.0
[1.1.0]: https://github.com/CarmineOptions/protocol-cairo1/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/CarmineOptions/protocol-cairo1/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/CarmineOptions/protocol-cairo1/releases/tag/v1.0.0
