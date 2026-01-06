# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-06

### Added

- Initial release
- `UkModulus.validate/2` - validates UK sort code and account number combinations
- `UkModulus.valid?/2` - simple boolean validation
- `UkModulus.ready?/0` - check if data is loaded
- `UkModulus.refresh/0` - manually refresh data from Vocalink
- Support for MOD10, MOD11, and DBLAL algorithms
- Support for Vocalink exceptions 1-14
- Bundled official Vocalink data (1,151 weight rules)
- Optional auto-update from Vocalink website
- ETS-based storage for fast concurrent access
