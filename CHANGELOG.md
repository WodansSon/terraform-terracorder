# Changelog

All notable changes to TerraCorder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Database Mode**: New read-only database query mode for analyzing previously discovered data without re-running discovery
  - `-DatabaseDirectory` parameter to specify location of CSV database files
  - `-ShowDirectReferences` to display direct resource references from database
  - `-ShowIndirectReferences` to display template-based and sequential test dependencies
  - `-ShowSequentialReferences` to display sequential test chain dependencies
  - `-ShowCrossFileReferences` to display cross-file struct references
  - `-ShowAllReferences` to display comprehensive analysis of all reference types
- **Sequential Test Support**: Complete analysis of sequential test patterns in Terraform provider tests
  - Detection of sequential test entry points using `resource.ParallelTest()` with `map[string]map[string]func()`
  - Sequential group and key extraction from nested map structures
  - Proper handling of external/cross-resource sequential test references
  - External function stub creation to maintain referential integrity
- **External Reference Handling**: Robust pattern for tracking test functions outside discovery scope
  - Automatic creation of stub records for externally referenced functions
  - Maintains full relational chain (FileRefId, StructRefId, SequentialEntryPointRefId)
  - Clear marking with `Line=0`, `FunctionBody="EXTERNAL_REFERENCE"`, `ReferenceTypeId=10`
- **Enhanced Visualization**: Professional Unicode box-drawing tree visualization for sequential test chains
  - Single-width Unicode characters for proper terminal alignment (`│`, `├`, `└`, `┬`, `►`)
  - Multi-level tree structure showing Entry Point → Sequential Group → Key → Function → Location
  - Smart spacing and indentation for visual hierarchy
  - Color-coded display showing external references vs. tracked functions
  - "External Reference (Not Tracked)" indicator for cross-resource dependencies
- **Syntax Highlighting**: VS Code theme-aware color coding for database query output
  - Automatic detection of VS Code Dark+ and Light+ themes
  - Color-coded syntax elements (functions, line numbers, strings, variables, labels, highlights)
  - Enhanced readability with proper contrast and semantic coloring
  - Graceful fallback for terminals without ANSI support
  - Maintains clean output formatting across all display modes
- **Blast Radius Analysis**: Executive summary of change impact
  - Total impact count (template + sequential dependencies)
  - Service impact classification (SAME_SERVICE vs. CROSS_SERVICE)
  - Risk levels (LOW, MEDIUM, HIGH) with color coding
  - Cross-service coordination warnings
- **Database Schema Enhancements**: Comprehensive relational database structure
  - `SequentialReferences` table linking entry points to referenced functions
  - `ServiceImpactType` classification for same-service vs. cross-service references
  - External reference stub pattern documented across all affected tables
  - Complete referential integrity maintained throughout discovery process

### Changed
- **Database Mode API Simplification**: Streamlined query parameters for better usability
  - Removed `-ShowSequentialReferences` and `-ShowCrossFileReferences` parameters (redundant with `-ShowIndirectReferences`)
  - Sequential and cross-file references already included in indirect references view
  - Simplified from 5 query options to 3: Direct, Indirect, and All
  - Clearer user intent with more intuitive parameter names
- **Default Behavior Enhancement**: Improved discoverability and user experience
  - Running Database Mode without query flags now shows available analysis options
  - New `Show-DatabaseStatistics` function displays simplified database overview
  - Progressive discovery: view options first, then choose specific analysis
  - All `-Show*` parameters now truly optional (no flags required)
  - Execution time for default statistics view: ~0.2 seconds
- **Syntax Highlighting Refinement**: Improved visual consistency and color scheme
  - Normalized file header display with `./` prefix in both direct and indirect modes
  - Unified resource name highlighting using `StringHighlight` color (#d7a895 - lighter peachy-salmon)
  - Subtle, professional highlighting that doesn't overwhelm the output
  - Consistent color scheme across all database query display modes
- **Output Organization**: Improved spacing and formatting in all display functions
  - Consistent blank line handling between sections
  - Proper function separation in template references
  - Cleaner transitions between different reference types
  - Removed redundant "Export Directory" from database mode display
- **Variable Naming**: More descriptive variable names for better code clarity
  - Renamed `$indent0` to `$basePadding` to clearly indicate purpose
  - Removed unused indent variables (`$indent1`, `$indent2`, `$indent3`)
- **Code Quality**: Cleanup of dead code and improved maintainability
  - Removed VSCode-flagged unused variables

### Performance
- **Syntax Highlighting Optimization**: Precompiled regex patterns for ~3x performance improvement
  - Module-level precompiled regex patterns (`ResourceOrData`, `AzureResourceName`, `ServicePath`, `Whitespace`)
  - Switched from PowerShell `-match`/`-replace` operators to compiled `[regex]::Match()` and `[regex]::Replace()`
  - Regex compiled once at module load with `RegexOptions.Compiled` flag
  - Reduces database query output time from ~9 seconds to ~3 seconds for large result sets
  - Zero functional changes - output remains identical
  - Better inline comments explaining complex tree rendering logic

### Fixed
- **Sequential Processing**: Complete sequential test discovery and visualization
  - Fixed bug where only 1 of 5 sequential groups was displayed for cross-resource tests
  - Proper handling of sequential tests referencing functions from different resource files
  - Correct sorting of sequential steps to avoid PowerShell scriptblock errors
- **Spacing Issues**: Eliminated extra newlines in output
  - Fixed double spacing after "Sequential Call Chain:" header
  - Fixed extra spacing between template functions
  - Fixed extra spacing before "End of Blast Radius Analysis"

### Technical
- **Performance**: O(1) lookup optimization using hashtable-based caches
  - Pre-built lookup tables for template references, test function steps, and template functions
  - Eliminates repeated database queries during analysis
- **Architecture**: Proper relational database design patterns
  - External reference stubs maintain full FK relationships
  - No shortcuts or band-aid solutions - complete data integrity
  - Template function copied from sibling functions to preserve relational context

### Documentation
- **DATABASE_SCHEMA.md**: Comprehensive documentation of new patterns
  - External Reference Stub Pattern in TestFunctions table
  - Phase 6 Sequential Stub Creation in TestFunctionSteps table
  - External Reference Handling in SequentialReferences table with Go code examples
- **README.md**: Updated Phase 6 description
  - Sequential reference processing details
  - External stub creation explanation
  - Referential integrity maintenance notes

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

### Security
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
