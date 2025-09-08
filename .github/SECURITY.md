# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

The TerraCorder team takes security bugs seriously. We appreciate your efforts to responsibly disclose your findings, and will make every effort to acknowledge your contributions.

### How to Report a Security Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **security@example.com** (replace with actual email)

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

### What to Include

Please include the requested information listed below (as much as you can provide) to help us better understand the nature and scope of the possible issue:

* Type of issue (e.g. buffer overflow, code injection, cross-site scripting, etc.)
* Full paths of source file(s) related to the manifestation of the issue
* The location of the affected source code (tag/branch/commit or direct URL)
* Any special configuration required to reproduce the issue
* Step-by-step instructions to reproduce the issue
* Proof-of-concept or exploit code (if possible)
* Impact of the issue, including how an attacker might exploit the issue

### Our Response Process

1. **Acknowledgment**: We'll acknowledge receipt of your report within 48 hours.

2. **Assessment**: Our security team will assess the vulnerability and determine its impact and severity.

3. **Resolution**: We'll work on a fix and keep you updated on our progress.

4. **Disclosure**: Once the issue is resolved, we'll coordinate with you on public disclosure timing.

5. **Recognition**: With your permission, we'll acknowledge your contribution in our security advisories.

### Safe Harbor

We support safe harbor for security researchers who:

* Make a good faith effort to avoid privacy violations, destruction of data, and interruption or degradation of our services
* Only interact with accounts you own or with explicit permission of the account holder
* Do not access a system or account beyond what is necessary to demonstrate the vulnerability
* Report vulnerabilities as soon as you discover them
* Do not exploit the vulnerability for any reason

## Security Best Practices

When using TerraCorder:

### For Users
* Always download TerraCorder from official sources (GitHub releases)
* Verify checksums of downloaded files when available
* Keep your PowerShell environment updated
* Review scripts before execution, especially from untrusted sources
* Run with minimal necessary privileges

### For Contributors
* Follow secure coding practices
* Validate all inputs and parameters
* Avoid storing sensitive information in code or logs
* Use PowerShell security features appropriately
* Test for injection vulnerabilities in file path handling

### Script Security Features

TerraCorder includes several security measures:

* **Input Validation**: All parameters are validated for type and content
* **Path Security**: File paths are validated to prevent directory traversal
* **No Network Access**: The script operates entirely locally
* **Read-Only Operations**: Script only reads files, never modifies them
* **Error Handling**: Graceful error handling prevents information disclosure

## Known Security Considerations

### File System Access
TerraCorder reads files from the local file system. Users should:
* Only run the script in trusted directories
* Be aware that the script will scan all files in the target directory structure
* Ensure appropriate file system permissions are in place

### PowerShell Execution Policy
The script requires PowerShell execution policy to allow script execution:
* Use `Set-ExecutionPolicy RemoteSigned` or more restrictive policies
* Avoid `Set-ExecutionPolicy Unrestricted` in production environments

### Output Sensitivity
Be cautious when sharing TerraCorder output, as it may contain:
* File paths that could reveal directory structures
* Test names that might indicate system architecture
* Resource names that could be considered sensitive

## Security Updates

Security updates will be released as patch versions and announced through:
* GitHub Security Advisories
* Release notes
* Repository README updates

Subscribe to repository notifications to stay informed about security updates.

## Contact

For security-related questions or concerns, please contact:
* **Security Email**: security@example.com (replace with actual email)
* **General Issues**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues) (for non-security issues only)

## Acknowledgments

We thank the security research community for helping to keep TerraCorder and our users safe.
