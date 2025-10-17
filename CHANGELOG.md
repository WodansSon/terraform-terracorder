# Changelog

All notable changes to TerraCorder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes
- **AST-Based Architecture**: Complete migration from regex pattern matching to Go AST (Abstract Syntax Tree) semantic analysis
  - **External Dependency**: Requires Go 1.21+ to build the AST `replicode` analyzer tool (`tools/replicode`)
  - **Processing Model**: Multi-phase regex analysis replaced with semantic AST parsing
  - **Module Changes**: 9 regex processing modules removed, 2 AST modules added
  - **Accuracy**: 100% accurate parsing vs. ~85% with regex patterns
  - **Backward Compatibility**: None - databases from regex-based versions incompatible

### Added
- **AST Semantic Analysis**: Go-based AST `replicode` analyzer for precise code parsing
  - Direct integration with Go's AST parser for semantic understanding
  - Extracts function signatures, call graphs, struct references, resource usage
  - Eliminates regex ambiguity and pattern matching errors
  - Single-pass semantic analysis replaces multi-pass graph traversal
  - Located in `tools/replicode` directory
  - Build: `make -f GNUmakefile` (Unix/Linux/macOS) or `.\Build.ps1` (Windows)
  - Output: JSON metadata consumed by PowerShell for database import
- **ASTImport Module**: New PowerShell module for importing AST-generated metadata
  - Processes JSON output from `replicode` tool
  - Populates in-memory database with semantically accurate data
  - Replaces 7 regex processing modules with single import module
- **Prerequisites Module**: Environment validation for AST-based workflow
  - Validates PowerShell Core 7.0+ requirement
  - Checks Go 1.21+ installation for `replicode`
  - Clear error messages with installation guidance
- **TemplateCallChain Table**: New 14th database table for tracking template-to-template function calls
  - Enables cross-file template call detection
  - Supports service boundary analysis in blast radius visualization
  - Includes ReferenceTypeId for call type classification
- **Service Boundary Display**: Enhanced `CROSS_FILE` reference visualization
  - Shows template service -> resource service relationships
  - Format: `(templateService -> resourceService): CROSS_FILE; CROSS_SERVICE`
  - Helps identify cross-team dependencies
- **External Reference Markers**: Clear indication of cross-resource dependencies
  - Displays `<external>` for functions defined outside current analysis scope
  - Common in sequential tests referencing other resource test files
  - Maintains `CROSS_SERVICE` flag when applicable
- **Reference Type Documentation**: Comprehensive explanation in README.md
  - `SELF_CONTAINED`: Template and resource in same file
  - `CROSS_FILE`: Multi-hop dependency across files with service boundaries
  - `CROSS_SERVICE`: Dependencies crossing Azure service boundaries
  - `EXTERNAL_REFERENCE`: Target defined outside current analysis scope
- **Enhanced Analysis Summary**: Expanded Phase 2 statistics display
  - Registry: Resource-to-Service Mappings count (1045 mappings)
  - Structure: Services, Files, Structs
  - Functions: Tests, Configuration (templates)
  - References: Steps, Direct, Calls (template-to-template)
- **Unified Color Scheme**: Centralized color initialization in main script
  - Single `$colors` hashtable defined in `terracorder.ps1` and shared across all modules
  - Consistent VS Code theme-aware colors throughout application
  - Easy customization - modify colors in one location
  - UI.psm1 module uses shared color scheme for all output formatting
- **RGB Color Functions**: New UI module functions for ANSI color conversion
  - `Convert-RGBToAnsi`: Converts RGB hex codes to ANSI escape sequences
  - `Get-VscodeThemeColors`: Detects VS Code theme and returns appropriate color scheme
  - Enables theme-aware syntax highlighting and visual consistency

### Changed
- **Module Architecture**: Simplified from 14 modules to 6 active modules (57% reduction)
  - **Removed** (9): `PatternAnalysis.psm1`, `ReferencesProcessing.psm1`, `TemplateProcessing.psm1`, `TemplateProcessingStrategies.psm1`, `TestFunctionProcessing.psm1`, `TestFunctionStepsProcessing.psm1`, `SequentialProcessing.psm1`, `ProcessingCore.psm1`, and `RelationalQueries.psm1`
  - **Added** (2): `ASTImport.psm1`, `Prerequisites.psm1`
  - **Retained** (4): `Database.psm1`, `DatabaseMode.psm1`, `FileDiscovery.psm1`, `UI.psm1`
  - Cleaner separation of concerns and easier maintenance
- **Processing Pipeline**: Streamlined from 8-phase regex to 3-phase AST workflow
  - **Phase 1**: File Discovery (PowerShell discovers `.go` test files)
  - **Phase 2**: AST Analysis & Import (replicode → JSON → PowerShell imports to database)
  - **Phase 3**: CSV Export (PowerShell exports relational data)
- **Service Count Reporting**: Fixed bug showing incorrect service count
  - Now reports actual services with test commands, not all services with files
  - Uses `$commandsResult.ConsoleData.Count` instead of `$serviceGroups.Count`
- **Arrow Color Consistency**: Unified color scheme in blast radius display
  - Changed service boundary arrow from Highlight to Label color
  - Consistent with parentheses, colons, and other structural elements
- **Database Statistics**: Added missing counts to Get-DatabaseStats
  - ResourceRegistrations count now included
  - TemplateCallChain count now included
  - TotalRecords calculation updated to include all tables
- **Blast Radius Display UX**: Simplified reference type suffix display for better readability
  - Removed redundant `CROSS_FILE` and `SELF_CONTAINED` suffixes (visual notation already conveys this)
  - Visual indicators clearly show structure: `calls` for cross-file references, line numbers for same-file references
  - Only display architecturally meaningful suffixes: `// EXTERNAL_REFERENCE` and `// CROSS_SERVICE`
  - Changed suffix format from colon-style to comment-style using `//` for intuitive developer understanding
  - Changed cross-file indicator from arrow `->` to `calls` for clearer semantics (e.g., `r.method calls r.template`)
  - Added "calls" verb in cross-service annotations (e.g., `// CROSS_SERVICE: \`vmware\` calls \`netapp\``)
  - Graceful fallback: displays "UNKNOWN" for service names when information unavailable
  - All suffixes displayed in `Comment` color for consistent metadata appearance
- **Code Refactoring**: Simplified reference type handling in blast radius display
  - Replaced string concatenation with direct ID-based comparisons for better performance
  - Data preparation now passes `FileReferenceTypeId` and `ServiceImpactTypeId` as integers instead of combined strings
  - Display logic uses direct ID comparison instead of string parsing
  - Eliminates overhead from string building and parsing operations

### Removed
- **Regex Processing Modules**: Removed 9 legacy regex-based processing modules after AST migration
  - `modules/PatternAnalysis.psm1` - regex pattern definitions and matching
  - `modules/ReferencesProcessing.psm1` - regex-based reference extraction
  - `modules/TemplateProcessing.psm1` - regex-based template analysis
  - `modules/TemplateProcessingStrategies.psm1` - multi-strategy template parsing
  - `modules/TestFunctionProcessing.psm1` - regex-based test function extraction
  - `modules/TestFunctionStepsProcessing.psm1` - regex-based step parsing
  - `modules/SequentialProcessing.psm1` - regex-based sequential test detection
  - `modules/ProcessingCore.psm1` - core regex processing functions
  - `modules/RelationalQueries.psm1` - legacy relational query functions (310 lines)
  - All functionality replaced by AST semantic analysis (100% accurate vs ~85% with regex)
- **Database Mode Parameters**: Removed unhelpful query options
  - `-ShowAllReferences` - Removed as it provided no additional value over individual reference type displays

### Fixed
- **Documentation Synchronization**: Updated all documentation files
  - README.md: Module download list corrected (removed ProcessingCore, RelationalQueries; added Prerequisites)
  - README.md: All table counts updated from 13 to 14 tables
  - DATABASE_SCHEMA.md: Complete TemplateCallChain documentation added
  - DATABASE_SCHEMA.md: ERD diagram updated with TemplateCallChain relationships
  - CHANGELOG.md: Module counts corrected to reflect actual state
- **Code Quality Cleanup**: Removed contradictory comments and dead code from AST migration
  - Removed misleading comments claiming TemplateCallChain table was "no longer used" when it is actively used
  - Added proper `.Clear()` call and counter reset for TemplateCallChain table in Reset-DatabaseTables
  - Removed completely unused TemplateChainResources table code (variable, counter, Add function - never called)
  - Removed commented-out IsDataSourceTest code in ASTImport.psm1 (half-implemented feature)
  - Removed 7 dead regex-era functions from Database.psm1 never called in AST workflow:
    - `Get-TestFunctionStepsByFunctionId` (17 lines)
    - `Update-TestFunctionStepStructRefId` (27 lines)
    - `Update-TestFunctionStepReferenceType` (29 lines)
    - `Update-TestFunctionStepStructVisibility` (29 lines)
    - `Update-IndirectConfigReferenceServiceImpact` (28 lines)
    - `Get-TestFunctionStepRefIdByIndex` (43 lines)
    - `Update-TestFunctionSequentialInfo` (26 lines)
  - Removed duplicate `Show-SequentialCallChain` function in DatabaseMode.psm1 (308 lines)
    - First definition (line 576) took `-TemplateRefs` parameter but was completely unreachable
    - Second definition (line 884) took `-SequentialRefs` parameter and was the only one ever called
    - PowerShell only uses the last definition when functions have duplicate names
  - Removed 8 unused function parameters identified by PSScriptAnalyzer
    - Database.psm1: `ElapsedColor` from `Initialize-TerraDatabase`, `ExportDirectory` from `Get-DatabaseStats`
    - DatabaseMode.psm1: `NumberColor` from `Show-DatabaseStatistics`, `FilePath` and `NumberColor` from `Show-SequentialCallChain`, `FilePath` from `Show-TemplateFunctionDependencies`
    - UI.psm1: `ItemColor` from `Show-InlineProgress`, `ServiceGroups` and `NumberColor` from `Show-RunTestsByService`
    - Updated all call sites in terracorder.ps1 to match corrected function signatures
  - Total cleanup: ~508 lines of dead code removed

### Documentation
- **TemplateCallChain Schema**: Full documentation in DATABASE_SCHEMA.md
  - Complete SQL CREATE TABLE definition
  - Example data with sample rows
  - Column-by-column documentation
  - ReferenceTypeId values explained
  - Query patterns and use cases
- **README.md Enhancements**:
  - Visual Blast Radius Trees section expanded
  - Understanding Reference Type Labels section added
  - CSV export list updated to 14 tables
  - All code examples updated to reflect current architecture

## [2.0.6] - 2025-10-06

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
  - Single-width Unicode characters for proper terminal alignment
  - Multi-level tree structure showing Entry Point -> Sequential Group -> Key -> Function -> Location
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
