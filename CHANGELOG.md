# Changelog

All notable changes to TerraCorder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Repository Path Support**: New `-RepositoryPath` parameter allows specifying the Terraform provider repository location
- **Auto-Detection**: Smart repository auto-detection searches current directory, script location, and parent directories
- **Flexible Usage**: Can now run TerraCorder from anywhere, not just within the provider repository
- **Enhanced Error Messages**: Improved error messages with helpful guidance when repository is not found

### Changed
- **Breaking**: Script now requires explicit repository path or must be run from within provider repository structure
- **Improved**: Enhanced help documentation with repository path examples
- **Better**: More robust path resolution and validation

### Added (Initial Release)
- Initial release of TerraCorder
- Comprehensive Terraform test dependency scanning
- Support for direct resource usage detection
- Template reference analysis for indirect dependencies
- Multiple output formats (list, JSON, CSV, summary)
- Cross-platform compatibility (Windows, Linux, macOS)
- Progress visualization with adaptive console width
- Flexible filtering options

### Security
- Input validation for all parameters
- Path validation to prevent directory traversal
- Read-only file system operations
- Secure error handling

## [1.0.0] - 2025-09-08

### Added
- **Core Functionality**
  - Resource dependency scanning for Terraform test files
  - Direct resource usage detection in test configurations
  - Template function analysis for indirect dependencies
  - Multi-phase scanning approach for comprehensive coverage

- **Output Formats**
  - List format (default) with hierarchical display
  - JSON format for programmatic processing
  - CSV format for spreadsheet analysis
  - Summary format for quick overviews

- **User Experience**
  - Progress bars with file-by-file scanning feedback
  - Automatic console width detection and adjustment
  - Graceful handling of narrow terminal windows
  - Colorized output with emoji indicators

- **Filtering Options**
  - Test names only output for CI/CD integration
  - Test prefixes for batch execution
  - Single file analysis capability
  - Detailed output with line numbers and context

- **Cross-Platform Support**
  - Windows PowerShell 5.1 compatibility
  - PowerShell Core 7.x support
  - Linux and macOS compatibility
  - Consistent behavior across platforms

### Technical
- Comprehensive parameter validation
- Robust error handling and user feedback
- Memory-efficient file processing
- Modular function architecture
- Extensive inline documentation

### Documentation
- Complete README with usage examples
- Contributing guidelines
- Security policy
- MIT license
- GitHub Actions CI/CD pipeline
- Example usage scenarios

### Infrastructure
- GitHub Actions workflows for CI/CD
- Automated testing across multiple platforms
- PSScriptAnalyzer integration for code quality
- Automated dependency updates
- Security scanning with DevSkim
- Automated release creation

## Release Notes Format

### Features
New functionality and capabilities

### Bug Fixes
Corrections to existing functionality

### Performance
Improvements to speed or resource usage

### 🔒 Security
Security-related changes and improvements

### Documentation
Updates to documentation and examples

### Infrastructure
Changes to build, test, or deployment processes

### Breaking Changes
Changes that may break existing usage

### Deprecated
Features marked for future removal

---

## Version History

- **v1.0.0**: Initial public release
- **v0.9.0**: Beta release for testing
- **v0.1.0**: Alpha release for early feedback

## Upgrade Guide

### From v0.x to v1.0

No breaking changes - v1.0 is fully backward compatible with all v0.x releases.

## Support

- **Issues**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues)
- **Discussions**: [GitHub Discussions](https://github.com/WodansSon/terraform-terracorder/discussions)
- **Security**: See [SECURITY.md](.github/SECURITY.md)
