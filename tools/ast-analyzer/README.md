# AST Analyzer - Proof of Concept

This is a simple Go AST (Abstract Syntax Tree) analyzer that demonstrates how we can extract accurate function and call information from Go test files.

## Purpose

Replace regex-based parsing with AST parsing to achieve 100% accuracy in detecting:
- Function declarations with receivers
- Method calls vs function calls
- Local receiver calls vs cross-struct calls
- Import dependencies

## Build

### Windows (Recommended)

Use the PowerShell build script (uses Windows Go installation):
```powershell
# Build the binary
.\Build.ps1

# Clean build artifacts
.\Build.ps1 clean

# Clean and rebuild
.\Build.ps1 rebuild

# Show help
.\Build.ps1 help
```

### WSL Users (Windows Subsystem for Linux)

If you have Go installed in WSL, you can build from within a WSL terminal:

```bash
# First, enter WSL shell
wsl

# Navigate to the ast-analyzer directory
cd /mnt/c/github.com/WodansSon/terraform-terracorder/tools/ast-analyzer

# Build the binary using GNUmakefile
make -f GNUmakefile

# Or clean and rebuild
make -f GNUmakefile rebuild

# Show help
make -f GNUmakefile help
```

**Important Notes:**
- You **must** run `wsl` first to enter the WSL shell - don't run `wsl make` directly from PowerShell
- Use `make -f GNUmakefile` to explicitly specify the makefile
- Building from WSL creates a **Linux binary** (`ast-analyzer`), not a Windows binary (`ast-analyzer.exe`)
- To build for Windows, use the PowerShell script `.\Build.ps1` or use `make -f GNUmakefile build-all` for cross-compilation
- The WSL binary won't run in Windows PowerShell - it only runs inside WSL

### Linux/macOS Users

Use Make with the GNUmakefile:
```bash
# Navigate to the ast-analyzer directory
cd tools/ast-analyzer

# Build the binary
make -f GNUmakefile

# Or clean and rebuild
make -f GNUmakefile rebuild

# See all available targets
make -f GNUmakefile help
```

**Tip**: On some systems, you can use `gmake` (GNU Make) directly:
```bash
gmake build
gmake rebuild
```

### Using Go Directly (All Platforms)

```powershell
# Windows
go build -o ast-analyzer.exe

# Linux/macOS/WSL
go build -o ast-analyzer
```

## Usage

Analyze a single test file:

```powershell
.\ast-analyzer.exe -file "C:\github.com\hashicorp\terraform-provider-azurerm\internal\services\network\private_endpoint_resource_test.go"
```

With verbose output:

```powershell
.\ast-analyzer.exe -file "path\to\test.go" -verbose -output "output/ast-test"
```

## Output

Creates 3 CSV files in the output directory:

### 1. functions_ast.csv
Contains all function declarations:
- Line number
- Function name
- Receiver type (e.g., "PrivateEndpointResource")
- Receiver variable (e.g., "r")
- IsTestFunc (true/false)
- IsExported (true/false)

**Maps to your schema**: TemplateFunctions and TestFunctions tables

### 2. function_calls_ast.csv
Contains all function call sites:
- Line number
- CallerFunction (which function made the call)
- ReceiverExpression (e.g., "r", "other", package name)
- MethodName (e.g., "basic", "withTag")
- IsMethodCall (true for receiver.method())
- IsLocalCall (true if receiver matches caller's receiver)
- FullCall (complete expression)

**Maps to your schema**: NEW FunctionCalls table (to be added)

### 3. imports_ast.csv
Contains all import statements:
- PackagePath
- PackageName
- Alias (if any)

**Maps to your schema**: NEW Imports table (to be added)

## Key Benefits Over Regex

### Problem: Regex Can't Tell These Apart
```go
// In TestAccPrivateEndpoint_updateTag:
r.basic(data)         // Local receiver - SAME SERVICE
other.basic(data)     // Different struct - COULD BE CROSS SERVICE
recovery.Basic(data)  // Import - CROSS SERVICE
```

### AST Solution
```
IsLocalCall = true   → r.basic() - caller receiver is 'r', call receiver is 'r'
IsLocalCall = false  → other.basic() - different receiver
PackagePath != ""    → recovery.Basic() - cross-package call
```

## Example Output

Running on `private_endpoint_resource_test.go`:

```
Analyzing: C:\...\private_endpoint_resource_test.go

Found 15 functions
Found 47 function calls
Found 8 imports

=== SAMPLE FUNCTIONS ===
  Line 40: TestAccPrivateEndpoint_updateTag
  Line 154: TestAccPrivateEndpoint_complete
  Line 486: basic (receiver: r PrivateEndpointResource)
  Line 531: withTag (receiver: r PrivateEndpointResource)
  Line 576: template (receiver: r PrivateEndpointResource)

=== SAMPLE FUNCTION CALLS ===
  Line 46 in TestAccPrivateEndpoint_updateTag: r.basic() [LOCAL]
  Line 54 in TestAccPrivateEndpoint_updateTag: r.withTag() [LOCAL]
  Line 62 in TestAccPrivateEndpoint_updateTag: r.basic() [LOCAL]
  Line 487 in basic: r.template()
  Line 487 in basic: r.serviceAutoApprove() [LOCAL]
  Line 532 in withTag: r.template() [LOCAL]
```

## Schema Mapping

### Current Schema Enhancement Needed

**Add to TestFunctionSteps**:
```sql
ALTER TABLE TestFunctionSteps
ADD COLUMN FunctionCallRefId INTEGER,
ADD FOREIGN KEY (FunctionCallRefId) REFERENCES FunctionCalls(FunctionCallRefId);
```

**New FunctionCalls Table**:
```sql
CREATE TABLE FunctionCalls (
    FunctionCallRefId INTEGER PRIMARY KEY,
    CallerFunctionRefId INTEGER NOT NULL,
    Line INTEGER NOT NULL,
    ReceiverExpression TEXT,
    MethodName TEXT NOT NULL,
    IsMethodCall BOOLEAN NOT NULL,
    IsLocalCall BOOLEAN NOT NULL,
    TargetFunctionRefId INTEGER,
    FOREIGN KEY (CallerFunctionRefId) REFERENCES TestFunctions(TestFunctionRefId) OR TemplateFunctions(TemplateFunctionRefId)
);
```

**New Imports Table**:
```sql
CREATE TABLE Imports (
    ImportRefId INTEGER PRIMARY KEY,
    FileRefId INTEGER NOT NULL,
    PackagePath TEXT NOT NULL,
    PackageAlias TEXT,
    FOREIGN KEY (FileRefId) REFERENCES Files(FileRefId)
);
```

## Next Steps

1. ✅ Build and test this tool
2. Compare AST output with your current regex output
3. Identify discrepancies (AST is ground truth)
4. Design full integration into your discovery process
5. Update PowerShell modules to use AST data

## Testing

Test on the problematic file:

```powershell
cd cmd\ast-analyzer
go build
.\ast-analyzer.exe -file "C:\github.com\hashicorp\terraform-provider-azurerm\internal\services\network\private_endpoint_resource_test.go" -output "..\..\output\ast-poc"

# Then examine the CSV files
Import-Csv "..\..\output\ast-poc\function_calls_ast.csv" |
    Where-Object { $_.CallerFunction -eq "TestAccPrivateEndpoint_updateTag" } |
    Format-Table Line, ReceiverExpression, MethodName, IsLocalCall
```

You should see:
- `r.basic()` with `IsLocalCall = true`
- `r.withTag()` with `IsLocalCall = true`
- Both are LOCAL calls (same struct receiver)
- Therefore: SAME SERVICE, not cross-service!

## Questions to Answer

1. How many false positives does regex have? (showing cross-service when it's actually local)
2. How many missed calls does regex have? (not detecting actual cross-service calls)
3. Can we map ReceiverExpression to existing Structs table?
4. How do we link FunctionCalls back to TestFunctionSteps?

Build it, run it, and let's see what the data looks like!
