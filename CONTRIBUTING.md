# Contributing to TerraCorder 🤝

Thank you for your interest in contributing to TerraCorder! This document provides guidelines and information for contributors.

## 🎯 Ways to Contribute

- **🐛 Bug Reports**: Help us identify and fix issues
- **💡 Feature Requests**: Suggest new functionality
- **📝 Documentation**: Improve guides, examples, and code comments
- **🔧 Code Contributions**: Submit bug fixes and enhancements
- **🧪 Testing**: Help test new features and edge cases

## 🚀 Getting Started

### Prerequisites
- PowerShell 5.1+ or PowerShell Core 7.x
- Git for version control
- A text editor or IDE (VS Code recommended)

### Development Setup
```powershell
# Clone the repository
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Create a new branch for your work
git checkout -b feature/your-feature-name

# Make your changes
# Test your changes (see Testing section below)
```

## 🧪 Testing Your Changes

### Basic Testing
```powershell
# Test syntax validation
$parseErrors = $null
[System.Management.Automation.PSParser]::Tokenize((Get-Content "./scripts/terracorder.ps1" -Raw), [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { Write-Error "Syntax errors found!" }

# Test basic execution
.\scripts\terracorder.ps1 -?

# Test with sample resource name
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -TestConsoleWidth 80
```

### Code Quality
```powershell
# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

# Run static analysis
Invoke-ScriptAnalyzer -Path "./scripts/terracorder.ps1"
```

### Manual Testing Scenarios
1. **Different Output Formats**: Test `-OutputFormat` with json, csv, list
2. **Edge Cases**: Empty results, invalid resource names, missing files
3. **Console Width**: Test with `-TestConsoleWidth` values: 40, 80, 120, 200
4. **Cross-Platform**: Test on Windows, Linux, and macOS if possible

## 📝 Code Style Guidelines

### PowerShell Best Practices
- Use **approved verbs** for function names (Get-, Set-, New-, etc.)
- Follow **PascalCase** for functions and parameters
- Use **camelCase** for variables
- Include **comment-based help** for all functions
- Use **Write-Host** for user output, **Write-Verbose** for debug info

### Code Structure
```powershell
# Good: Clear parameter definition
param(
    [string]$ResourceName,
    [switch]$ShowDetails
)

# Good: Descriptive function names
function Get-ResourceTests {
    # Implementation
}

# Good: Error handling
try {
    $result = Get-Content $filePath
} catch {
    Write-Error "Failed to read file: $_"
    return
}
```

### Documentation
- Update the README if adding new features
- Include examples in function help
- Comment complex logic and algorithms
- Update parameter descriptions

## 🔄 Submission Process

### 1. Prepare Your Changes
```powershell
# Ensure code quality
Invoke-ScriptAnalyzer -Path "./scripts/terracorder.ps1"

# Test functionality
.\scripts\terracorder.ps1 -ResourceName "test" -Summary

# Update documentation if needed
```

### 2. Commit Guidelines
- Use clear, descriptive commit messages
- Reference issues when applicable
- Keep commits focused and atomic

```bash
# Good commit messages
git commit -m "Add JSON output format support (#15)"
git commit -m "Fix progress bar display on narrow terminals"
git commit -m "Update README with new usage examples"

# Less helpful
git commit -m "Updates"
git commit -m "Bug fixes"
```

### 3. Pull Request Process
1. **Fork** the repository
2. **Create** a feature branch
3. **Make** your changes
4. **Test** thoroughly
5. **Update** documentation
6. **Submit** a pull request

#### Pull Request Template
```markdown
## Description
Brief description of what this PR does.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Tested on Windows PowerShell 5.1
- [ ] Tested on PowerShell Core 7.x
- [ ] Tested different output formats
- [ ] Tested edge cases
- [ ] Updated documentation

## Screenshots/Output
If applicable, add screenshots or example output.
```

## 🐛 Reporting Issues

### Bug Reports
Please include:
- **PowerShell Version**: `$PSVersionTable`
- **Operating System**: Windows/Linux/macOS version
- **Command Used**: Exact command that triggered the issue
- **Expected Behavior**: What should have happened
- **Actual Behavior**: What actually happened
- **Error Messages**: Full error text if applicable

### Feature Requests
Please include:
- **Use Case**: Why this feature would be helpful
- **Proposed Solution**: How you envision it working
- **Alternatives**: Other ways to achieve the same goal
- **Examples**: Sample usage or output

## 🏷️ Issue Labels

- `bug`: Something isn't working correctly
- `enhancement`: New feature or improvement
- `documentation`: Improvements to docs
- `help wanted`: Good for community contributors
- `good first issue`: Good for newcomers
- `priority/high`: Important issues
- `platform/windows`: Windows-specific issues
- `platform/linux`: Linux-specific issues
- `platform/macos`: macOS-specific issues

## 🎉 Recognition

Contributors are recognized in several ways:
- Listed in GitHub contributors
- Mentioned in release notes for significant contributions
- Featured in the README acknowledgments

## 📞 Getting Help

- **Discussions**: [GitHub Discussions](https://github.com/WodansSon/terraform-terracorder/discussions)
- **Issues**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues)
- **Documentation**: [Wiki](https://github.com/WodansSon/terraform-terracorder/wiki)

## 📋 Development Roadmap

Current focus areas:
- **Multi-provider support** (AWS, GCP providers)
- **Performance optimization** for large codebases
- **GitHub Actions integration** templates
- **Visual dependency graphs**

## 🙏 Thank You

Every contribution, no matter how small, makes TerraCorder better for the entire Terraform community. We appreciate your time and effort!

---

## Quick Reference

```powershell
# Setup
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Test
.\scripts\terracorder.ps1 -ResourceName "test" -Summary

# Quality Check
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path "./scripts/terracorder.ps1"

# Submit
git checkout -b feature/my-feature
git commit -m "Add feature description"
git push origin feature/my-feature
# Create Pull Request
```
