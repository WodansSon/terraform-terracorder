# AST Analyzer Filtering Strategy

## Last Updated: October 11, 2025

Based on comprehensive analysis of the terraform-provider-azurerm test codebase, this document defines the precise filtering rules needed to prevent data explosion (1.8M rows → ~70K rows) while capturing all test-relevant function data.

## CRITICAL: This is the CORRECT and VERIFIED strategy
**DO NOT REVERT TO PREVIOUS APPROACHES WITHOUT READING THIS ENTIRE DOCUMENT**

This strategy was developed through detailed analysis of actual test files and understanding of:
- Service boundary crossing detection
- Reference type assignment logic
- Call chain tracing requirements
- Check block filtering requirements

---

## Core Concepts - READ THIS FIRST

### Service Boundary Detection
- **Service Name**: Extracted from file path: `internal/services/XXXXX/` → service = "XXXXX"
- **Cross-Service**: When a template in service A calls a template in service B
- **Same-Service**: When a template calls another template in the same service

### Reference Type Assignment (CRITICAL)
**Reference types are assigned to CALLS/RELATIONSHIPS, NOT to functions themselves!**

The same function can be called with different reference types depending on the calling context:
- Test → `r.basic()` = **SELF_CONTAINED (1)** (entry point)
- `r.basic()` → `r.template()` = **EMBEDDED_SELF (3)** (same service)
- `r.template()` → `storage.basic()` = **CROSS_FILE (2)** (different service)
- HCL resource definition = **RESOURCE_REFERENCE (5)** (direct resource)

### Call Chain Tracing Rules
1. **Track the ENTIRE call chain** - no depth limit in AST
2. **Only include chains that cross service boundaries**
3. **Same-service chains**: Track only 1 level, mark as EMBEDDED_SELF
4. **Cross-service chains**: Track all levels, mark appropriately
5. **PowerShell determines reference types** - AST just provides raw data with service names

---

## Real-World Example

### Full Test File Context

**File:** `internal/services/network/private_endpoint_resource_test.go` (network service)

```go
func TestAccPrivateEndpoint_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_private_endpoint", "test")
    r := PrivateEndpointResource{}  // network service struct

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),  // ← SELF_CONTAINED (entry from test)
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),  // ← IGNORE THIS BLOCK
            ),
        },
    })
}

// Template method (network service)
func (r PrivateEndpointResource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`%s\n...`, r.template(data))  // ← EMBEDDED_SELF (same service)
}

// Template method (network service)
func (r PrivateEndpointResource) template(data acceptance.TestData) string {
    storage := StorageAccountResource{}  // Different service struct!
    return fmt.Sprintf(`%s\n...`, storage.basic(data))  // ← CROSS_FILE (different service)
}
```

**File:** `internal/services/storage/storage_account_resource_test.go` (storage service)

```go
func (s StorageAccountResource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`resource "azurerm_storage_account"...`)  // ← RESOURCE_REFERENCE
}
```

### Call Chain with Reference Types

1. **Test Function**: `TestAccPrivateEndpoint_basic` (network)
   - Call: `r.basic(data)`
   - **Reference Type: 1 (SELF_CONTAINED)** ← Entry point from test

2. **Inside `r.basic()`**: (network service)
   - Call: `r.template(data)`
   - **Reference Type: 3 (EMBEDDED_SELF)** ← Same service (network → network)

3. **Inside `r.template()`**: (network service)
   - Call: `storage.basic(data)`
   - **Reference Type: 2 (CROSS_FILE)** ← Different service (network → storage)

4. **Inside `storage.basic()`**: (storage service)
   - HCL: `resource "azurerm_storage_account"`
   - **Reference Type: 5 (RESOURCE_REFERENCE)** ← Direct resource definition

---

## Observed Test File Patterns

### Pattern 1: Resource Struct with Methods
```go
type PrivateEndpointResource struct{}

// Test function (NOT a method - standalone)
func TestAccPrivateEndpoint_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_private_endpoint", "test")
    r := PrivateEndpointResource{}  // <-- Creates struct instance

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),  // <-- Calls method on receiver 'r' - TRACK THIS
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),  // <-- IGNORE THIS
            ),
        },
    })
}

// Template methods on Resource receiver
func (r PrivateEndpointResource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`%s...`, r.template(data, r.serviceAutoApprove(data)))
    //                           ^^^^^^^^^^      ^^^^^^^^^^^^^^^^^^^
    //                           Call 1          Call 2 (nested in sprintf args)
}

func (r PrivateEndpointResource) template(data acceptance.TestData, serviceCfg string) string {
    return fmt.Sprintf(`...%s...`, serviceCfg)  // serviceCfg contains nested template
}

func (r PrivateEndpointResource) serviceAutoApprove(data acceptance.TestData) string {
    return fmt.Sprintf(`resource "azurerm_private_link_service"...`)
}
```

**Key Observations:**
- Test functions are **NOT** methods (no receiver)
- Test functions create a local struct instance (e.g., `r := PrivateEndpointResource{}`)
- Template methods are called on the receiver (e.g., `r.basic(data)`)
- **No depth limit**: Track entire call chain regardless of depth
- **Service boundaries matter**: Cross-service = different reference type
- **Check blocks must be ignored**: Everything in `Check:` field is validation, not configuration

### Pattern 2: Dynamic Receiver Resolution

```go
func TestAccSiteVMWareRecoveryReplicatedVM_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_site_recovery_vmware_replicated_vm", "test")
    r, err := newSiteRecoveryVMWareReplicatedVMResource()  // ← Constructor function
    // r is now *SiteRecoveryVMWareReplicatedVMResource

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),  // ← Can now call methods on r
        },
    })
}

// Constructor function (lowercase 'new')
func newSiteRecoveryVMWareReplicatedVMResource() (*SiteRecoveryVMWareReplicatedVMResource, error) {
    return &SiteRecoveryVMWareReplicatedVMResource{}, nil
}
```

**Key Observations:**
- Lowercase `newXxxResource()` functions are constructors
- Return `*XxxResource` pointer
- Must be tracked to resolve receiver type in test functions
- Different from capital `New*` utility functions (e.g., `NewClient`)

### Pattern 3: Cross-Service Template References

```go
// File: internal/services/network/private_endpoint_test.go (network service)
func (r PrivateEndpointResource) needsStorageAccount(data acceptance.TestData) string {
    storage := StorageAccountResource{}  // ← Struct from storage service
    // OR
    storage, err := newStorageAccountResource()  // ← Constructor from storage service

    return fmt.Sprintf(`
%s

resource "azurerm_private_endpoint" "test" {
    ...
}`, storage.basic(data))  // ← Calling method on different service's struct
}
```

**Key Observations:**
- No package import needed - all in `*_test` package
- Service determined by file path, not package
- `StorageAccountResource` is defined in `internal/services/storage/`
- This creates a **CROSS_FILE** reference (network → storage)

---

## Critical Filtering Rules

### Rule 1: Function Tracking (What to INCLUDE)

**INCLUDE these function types:**

1. **Test Functions**
   - Pattern: `func Test*(t *testing.T)` or `func testAcc*(t *testing.T)`
   - No receiver (standalone functions)
   - These call template methods in `Config:` field

2. **Resource Template Methods**
   - Pattern: `func (r *XxxResource) methodName(...) string`
   - Receiver type MUST end with `Resource`
   - Return type MUST be `string`
   - Examples: `basic()`, `template()`, `complete()`, `requiresImport()`

3. **Resource Constructor Functions**
   - Pattern: `func newXxxResource() (*XxxResource, error)` or `func newXxxResource() *XxxResource`
   - **Lowercase** `new` prefix (not capital `New`)
   - Returns `*XxxResource` pointer
   - Used to initialize resource struct in tests

**EXCLUDE these function types:**

1. **Infrastructure/Validation Methods (Exact Names)**
   - `Exists` - Checks if resource exists in Azure
   - `Destroy` - Checks if resource was destroyed
   - `preCheck` - Pre-test validation
   - `checkDestroy` - Destruction validation
   - `testCheckDestroy` - Test destruction validation

2. **SDK Helper Function Prefixes**
   - `Validate*` - ValidateResourceID, ValidateName, etc.
   - `Parse*` - ParseResourceID, ParseName, etc.
   - `Marshal*` - JSON/XML serialization
   - `Unmarshal*` - JSON/XML deserialization
   - `Expand*` - SDK expansion functions (not templates)
   - `Flatten*` - SDK flattening functions (not templates)

3. **Schema/Metadata Function Suffixes**
   - `*Schema` - Schema definitions (metadata, not test execution)
   - `*Arguments` - Argument definitions
   - `*Attributes` - Attribute definitions
   - `*Validator` - Validation logic
   - `*Parser` - Parsing logic
   - `*Client` - Client constructors

4. **Utility Constructors (Capital New)**
   - `New*` - NewClient, NewValidator, NewConfig, etc.
   - Capital `N` indicates utility function
   - Exception: ✅ Lowercase `new*` returning `*XxxResource` (INCLUDE)

### Rule 2: Function Call Tracking (What to INCLUDE)

**CRITICAL: Only track calls from specific contexts**

#### ✅ TRACK These Call Contexts:

1. **Calls in `Config:` Field of TestStep**
   ```go
   data.ResourceTest(t, r, []acceptance.TestStep{
       {
           Config: r.basic(data),  // ✅ TRACK THIS
       },
   })
   ```

2. **Calls Inside Template Functions**
   ```go
   func (r Resource) basic(data acceptance.TestData) string {
       return fmt.Sprintf(`%s`, r.template(data))  // ✅ TRACK THIS
   }
   ```

3. **Calls in fmt.Sprintf Arguments**
   ```go
   return fmt.Sprintf(`%s\n%s`, r.template(data), r.other(data))
   //                           ^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^^^
   //                           ✅ TRACK          ✅ TRACK
   ```

4. **Variable Assignments to Track Receiver Resolution**
   ```go
   config := r.multipleInstances(data, count, false)  // ✅ TRACK
   storage := StorageAccountResource{}  // ✅ TRACK (cross-service struct)
   ```

#### ❌ IGNORE These Call Contexts:

1. **Everything in `Check:` Field (CRITICAL)**
   ```go
   data.ResourceTest(t, r, []acceptance.TestStep{
       {
           Config: r.basic(data),  // ✅ TRACK
           Check: acceptance.ComposeTestCheckFunc(  // ❌ START IGNORING
               check.That(data.ResourceName).ExistsInAzure(r),  // ❌ IGNORE
               check.That(data.ResourceName).Key("subnet_id").Exists(),  // ❌ IGNORE
           ),  // ❌ STOP IGNORING
       },
   })
   ```

2. **Framework/Standard Library Calls**
   - `acceptance.*` (except when extracting Config field value)
   - `check.*` (all validation framework calls)
   - `data.*` (except `data` parameter passed to templates)
   - `fmt.*` (except extracting calls from sprintf arguments)
   - `strings.*`, `testing.*`, etc.

3. **Import/Setup Calls**
   ```go
   data.ImportStep()  // ❌ IGNORE (framework call)
   data.RequiresImportErrorStep()  // ❌ IGNORE
   ```

### Rule 3: Call Chain Depth and Service Boundaries

**NO DEPTH LIMIT - Track entire call chain**

The depth limit approach was WRONG. Instead:

1. **Track ALL levels of the call chain**
2. **Determine reference type based on service boundaries**
3. **Let PowerShell filter based on whether chain crosses services**

**Example Multi-Level Chain:**
```
azurerm_resource_group (service: resource)
  └─> azurerm_storage_account (service: storage)        ← CROSS_FILE
       └─> azurerm_app_service_plan (service: appservice)  ← CROSS_FILE
            └─> azurerm_app_service (service: appservice)      ← EMBEDDED_SELF (same service as parent)
```

**Rules:**
- **CROSS_FILE (2)**: Different service from caller
- **EMBEDDED_SELF (3)**: Same service as caller
- **Continue tracking** regardless of depth
- **PowerShell decides** which chains to include in final output

---

## AST Data Structure Requirements

### Add ServiceName Field to All Structures

```go
type FunctionInfo struct {
    File         string
    Line         int
    FunctionName string
    ReceiverType string
    ReceiverVar  string
    IsTestFunc   bool
    IsExported   bool
    ServiceName  string  // NEW: Extracted from file path
}

type FunctionCall struct {
    CallerFunction string
    CallerFile     string
    CallerService  string  // NEW: Service of caller
    Line           int
    ReceiverExpr   string
    MethodName     string
    IsMethodCall   bool
    IsLocalCall    bool
    FullCall       string
    NumArgs        int
    Arguments      string
    TargetService  string  // NEW: Service of target (if resolvable)
}

type TestStepInfo struct {
    SourceFile     string
    SourceService  string  // NEW: Service containing this test step
    SourceLine     int
    SourceFunction string
    SourceStruct   string
    StepIndex      int
    StepBody       string

    ConfigExpr     string
    ConfigVariable string
    ConfigMethod   string
    ConfigStruct   string
    ConfigService  string  // NEW: Service of config struct
    IsLocalCall    bool
    TargetFile     string
    TargetLine     int
}

type TemplateFunctionCall struct {
    SourceFunction string
    SourceFile     string
    SourceService  string  // NEW: Service of source
    SourceLine     int

    TargetExpr     string
    TargetVariable string
    TargetMethod   string
    TargetStruct   string
    TargetService  string  // NEW: Service of target
    IsLocalCall    bool
    TargetFile     string
    TargetLine     int
}
```

### Service Name Extraction Function

```go
// extractServiceName extracts service name from file path
// Example: internal/services/network/file_test.go → "network"
func extractServiceName(filePath string) string {
    parts := strings.Split(filepath.ToSlash(filePath), "/")
    for i, part := range parts {
        if part == "services" && i+1 < len(parts) {
            return parts[i+1]
        }
    }
    return ""
}
```

---

## Implementation Plan

### Phase 1: Enhanced Function Filtering

```go
func extractFunctions(file *ast.File, fset *token.FileSet, filename string) []FunctionInfo {
    var functions []FunctionInfo

    serviceName := extractServiceName(filename)

    // Infrastructure method names to EXCLUDE (exact match)
    infraMethodNames := map[string]bool{
        "Exists":           true,
        "Destroy":          true,
        "preCheck":         true,
        "checkDestroy":     true,
        "testCheckDestroy": true,
    }

    // Function prefixes to EXCLUDE
    excludePrefixes := []string{
        "Validate", "Parse", "Marshal", "Unmarshal", "Expand", "Flatten",
    }

    // Function suffixes to EXCLUDE
    excludeSuffixes := []string{
        "Schema", "Arguments", "Attributes", "Validator", "Parser", "Client",
    }

    ast.Inspect(file, func(n ast.Node) bool {
        funcDecl, ok := n.(*ast.FuncDecl)
        if !ok {
            return true
        }

        funcName := funcDecl.Name.Name

        // FILTER 1: Exact name exclusions
        if infraMethodNames[funcName] {
            return true
        }

        // FILTER 2: Prefix exclusions
        for _, prefix := range excludePrefixes {
            if strings.HasPrefix(funcName, prefix) {
                return true
            }
        }

        // FILTER 3: Suffix exclusions
        for _, suffix := range excludeSuffixes {
            if strings.HasSuffix(funcName, suffix) {
                return true
            }
        }

        // FILTER 4: Capital 'New' utility functions (exclude)
        if strings.HasPrefix(funcName, "New") {
            // Exception: lowercase 'new' + returns *XxxResource (include)
            if !strings.HasPrefix(funcName, "new") {
                return true
            }
            // If lowercase 'new', check if it returns *XxxResource
            if funcDecl.Type.Results != nil {
                for _, field := range funcDecl.Type.Results.List {
                    if starExpr, ok := field.Type.(*ast.StarExpr); ok {
                        if ident, ok := starExpr.X.(*ast.Ident); ok {
                            if strings.HasSuffix(ident.Name, "Resource") {
                                goto includeFunction  // Valid constructor
                            }
                        }
                    }
                }
            }
            return true  // Not a resource constructor, exclude
        }

includeFunction:
        // FILTER 5: Include test functions OR resource template methods
        isTestFunc := strings.HasPrefix(funcName, "Test") || strings.HasPrefix(funcName, "testAcc")
        hasResourceReceiver := false
        returnsString := false

        if funcDecl.Recv != nil && len(funcDecl.Recv.List) > 0 {
            recv := funcDecl.Recv.List[0]
            switch recvType := recv.Type.(type) {
            case *ast.StarExpr:
                if ident, ok := recvType.X.(*ast.Ident); ok {
                    hasResourceReceiver = strings.HasSuffix(ident.Name, "Resource")
                }
            }
        }

        // Check return type
        if funcDecl.Type.Results != nil {
            for _, field := range funcDecl.Type.Results.List {
                if ident, ok := field.Type.(*ast.Ident); ok {
                    if ident.Name == "string" {
                        returnsString = true
                        break
                    }
                }
            }
        }

        // Include if: test function OR (resource receiver AND returns string)
        if !isTestFunc && !(hasResourceReceiver && returnsString) {
            return true
        }

        fn := FunctionInfo{
            File:         filename,
            Line:         fset.Position(funcDecl.Pos()).Line,
            FunctionName: funcName,
            IsTestFunc:   isTestFunc,
            IsExported:   ast.IsExported(funcName),
            ServiceName:  serviceName,  // NEW
        }

        // Extract receiver information
        if funcDecl.Recv != nil && len(funcDecl.Recv.List) > 0 {
            recv := funcDecl.Recv.List[0]
            if len(recv.Names) > 0 {
                fn.ReceiverVar = recv.Names[0].Name
            }
            switch recvType := recv.Type.(type) {
            case *ast.StarExpr:
                if ident, ok := recvType.X.(*ast.Ident); ok {
                    fn.ReceiverType = ident.Name
                }
            case *ast.Ident:
                fn.ReceiverType = recvType.Name
            }
        }

        functions = append(functions, fn)
        return true
    })

    return functions
}
```

### Phase 2: Context-Aware Call Tracking

```go
func extractFunctionCalls(file *ast.File, fset *token.FileSet, filename string, functions []FunctionInfo) []FunctionCall {
    var calls []FunctionCall

    serviceName := extractServiceName(filename)

    // Build lookup maps
    lineToFunc := make(map[int]FunctionInfo)
    trackedFunctions := make(map[string]bool)
    for _, fn := range functions {
        lineToFunc[fn.Line] = fn
        trackedFunctions[fn.FunctionName] = true
    }

    var currentFunc *FunctionInfo
    var insideCheckBlock bool

    ast.Inspect(file, func(n ast.Node) bool {
        // Track current function context
        if funcDecl, ok := n.(*ast.FuncDecl); ok {
            line := fset.Position(funcDecl.Pos()).Line
            if fn, exists := lineToFunc[line]; exists {
                currentFunc = &fn
            } else {
                currentFunc = nil
            }
            insideCheckBlock = false
        }

        // Detect Check block context
        if compLit, ok := n.(*ast.CompositeLit); ok {
            for _, elt := range compLit.Elts {
                if kvExpr, ok := elt.(*ast.KeyValueExpr); ok {
                    if ident, ok := kvExpr.Key.(*ast.Ident); ok {
                        if ident.Name == "Check" {
                            insideCheckBlock = true
                        } else if ident.Name == "Config" {
                            insideCheckBlock = false
                        }
                    }
                }
            }
        }

        // Skip if not in tracked function OR inside Check block
        if currentFunc == nil || insideCheckBlock {
            return true
        }

        // Process call expressions
        callExpr, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }

        call := FunctionCall{
            CallerFile:     filename,
            CallerService:  serviceName,  // NEW
            CallerFunction: currentFunc.FunctionName,
            Line:           fset.Position(callExpr.Pos()).Line,
        }

        // Analyze call expression
        switch fun := callExpr.Fun.(type) {
        case *ast.SelectorExpr:
            call.IsMethodCall = true
            call.MethodName = fun.Sel.Name

            if ident, ok := fun.X.(*ast.Ident); ok {
                call.ReceiverExpr = ident.Name
                if currentFunc.ReceiverVar == ident.Name {
                    call.IsLocalCall = true
                }
            } else {
                call.ReceiverExpr = exprToString(fun.X)
            }

            call.FullCall = fmt.Sprintf("%s.%s", call.ReceiverExpr, call.MethodName)

        case *ast.Ident:
            call.IsMethodCall = false
            call.MethodName = fun.Name
            call.FullCall = fun.Name
        }

        // Extract arguments
        call.NumArgs = len(callExpr.Args)
        var argExprs []string
        for _, arg := range callExpr.Args {
            argExprs = append(argExprs, exprToString(arg))
        }
        call.Arguments = strings.Join(argExprs, ", ")

        // Only record if: local receiver call OR call to tracked function
        shouldRecord := call.IsLocalCall || trackedFunctions[call.MethodName]

        if shouldRecord && call.MethodName != "" {
            calls = append(calls, call)
        }

        return true
    })

    return calls
}
```

---

## Expected Results After Implementation

### Before Filtering (Broken AST)
- `azurerm_resource_group`: **1,800,000 rows**
- Tracks: ALL functions including SDK, validators, infrastructure
- Tracks: All Check block validation calls
- Call depth: Unlimited through SDK chains
- Result: **25x data explosion**

### After Filtering (Fixed AST)
- `azurerm_resource_group`: **~70,000 rows**
- Tracks: Only test functions + template methods returning string
- Ignores: Everything in Check blocks
- Call depth: Unlimited but only test-relevant chains
- Service boundaries: Properly tracked for CROSS_FILE detection
- Result: **Matches regex-based baseline**

---

## Validation Checklist

After implementing, verify:

- [ ] Row count ~70K (not 1.8M)
- [ ] No `Exists`, `Destroy`, or Check block functions tracked
- [ ] No `Validate*`, `Parse*`, `*Schema` functions
- [ ] All test functions have `ServiceName` populated
- [ ] Template methods have `ServiceName` from file path
- [ ] Function calls have both `CallerService` and `TargetService`
- [ ] Sequential references still work (65 refs for network_manager)
- [ ] Cross-service chains properly detected

---

## Reference Type Clarifications

### Duplicate Reference Types (From Previous Chat)
- **SAME_SERVICE (14)** = Duplicate of **EMBEDDED_SELF (3)**
- **CROSS_SERVICE (15)** = Duplicate of **CROSS_FILE (2)**

### Correct Reference Types to Use
1. **SELF_CONTAINED (1)** - Entry point from test to first template
2. **CROSS_FILE (2)** - Call to template in different service
3. **EMBEDDED_SELF (3)** - Call to template in same service
4. **ATTRIBUTE_REFERENCE (4)** - Direct attribute reference in HCL
5. **RESOURCE_REFERENCE (5)** - Direct resource definition in HCL
6. **DATA_SOURCE_REFERENCE (6)** - Data source reference
7. **TEMPLATE_FUNCTION (7)** - Template function call
8. **SEQUENTIAL_REFERENCE (8)** - Sequential test pattern
9. **ANONYMOUS_FUNCTION_REFERENCE (9)** - Anonymous function
10. **EXTERNAL_REFERENCE (10)** - External test reference
11. **PRIVATE_REFERENCE (11)** - Private (lowercase) function
12. **PUBLIC_REFERENCE (12)** - Public (exported) function
13. **SEQUENTIAL_ENTRYPOINT (13)** - Sequential test entry point

**PowerShell assigns reference types based on call context and service boundaries.**

---

## DO NOT REVERT WITHOUT READING THIS

This strategy represents the **correct and verified** approach based on:
1. Actual examination of terraform-provider-azurerm test files
2. Understanding service boundary detection requirements
3. Check block filtering requirements
4. Cross-service dependency tracking needs

Previous approaches failed because they:
- Limited call depth arbitrarily
- Tracked Check block validation calls
- Included SDK/infrastructure functions
- Assigned reference types in AST (should be PowerShell's job)

**If you need to revert, re-read this entire document first!**

func (r AadB2cDirectoryResource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`
%[1]s

resource "azurerm_aadb2c_directory" "test" {
    ...
    resource_group_name = azurerm_resource_group.test.name
}`, r.template(data), data.RandomInteger)
    //  ^^^^^^^^^^^^^^ Template reference in sprintf args
}

func (r AadB2cDirectoryResource) domainNameUnavailable(data acceptance.TestData) string {
    return fmt.Sprintf(`
%[1]s
...
}`, r.basic(data), ...)
//  ^^^^^^^^^^^^^ Calls another template that calls template()
}
```

**Key Observations:**
- All template functions return `string`
- Templates nest by including other templates in `fmt.Sprintf()` arguments
- **2 levels of nesting observed**: `domainNameUnavailable` → `basic` → `template`

### Pattern 3: Infrastructure Methods (EXCLUDE)
```go
func (r PrivateEndpointResource) Exists(ctx context.Context, clients *clients.Client, state *pluginsdk.InstanceState) (*bool, error) {
    // Validation logic - NOT a template
}

func (r PrivateEndpointResource) checkDestroy() {}
func (r PrivateEndpointResource) preCheck() {}
```

**Key Observations:**
- Methods used in `Check` blocks, not `Config`
- Return types: `*bool`, `error`, `void` (NOT `string`)
- Names: `Exists`, `Destroy`, `checkDestroy`, `preCheck`

---

## Critical Filtering Rules

### Rule 1: Function Tracking (What to INCLUDE)

**INCLUDE these function types:**

1. **Test Functions**
   - Pattern: `func Test*(t *testing.T)` or `func testAcc*(t *testing.T)`
   - No receiver
   - These call template methods

2. **Resource Template Methods**
   - Pattern: `func (r *XxxResource) methodName(...) string`
   - Receiver type MUST end with `Resource`
   - Return type MUST be `string`
   - Examples: `basic()`, `template()`, `complete()`, `requiresImport()`

3. **Resource Constructor Functions**
   - Pattern: `func newXxxResource() *XxxResource`
   - Lowercase `new` prefix
   - Returns `*XxxResource` pointer
   - Used to initialize resource struct in tests

**EXCLUDE these function types:**

1. **Infrastructure Methods**
   - Exact names: `Exists`, `Destroy`, `preCheck`, `checkDestroy`, `testCheckDestroy`
   - Return non-string types (`*bool`, `error`, `void`)

2. **SDK Helper Functions**
   - Prefixes: `Validate*`, `Parse*`, `Marshal*`, `Unmarshal*`, `Expand*`, `Flatten*`
   - These are SDK glue code, not test execution

3. **Schema/Metadata Functions**
   - Suffixes: `*Schema`, `*Arguments`, `*Attributes`, `*Validator`, `*Parser`, `*Client`
   - These define resource structure, not test configuration

4. **Utility Functions**
   - Prefixes: `Get*`, `Set*`, `New*` (except `newXxxResource`)
   - Capital `New` = utility (e.g., `NewClient`)
   - Lowercase `new` = resource constructor (INCLUDE if returns `*XxxResource`)

### Rule 2: Function Call Tracking (What to INCLUDE)

**INCLUDE these call types:**

1. **Direct Template Method Calls**
   - Pattern: `r.methodName(data)` where `r` is receiver in current function
   - Called FROM: Test functions or other template methods
   - Called TO: Other template methods on same receiver

2. **Nested Template Calls in fmt.Sprintf**
   - Pattern: `fmt.Sprintf("%s\n...", r.template(data), r.other(data))`
   - Extract calls from sprintf argument list
   - Track: `r.template`, `r.other` as dependencies

3. **Variable Assignment Calls**
   - Pattern: `config := r.multipleInstances(data, count, false)`
   - Track variable → method mapping

**EXCLUDE these call types:**

1. **Deep Call Chains (3+ levels)**
   - If `basic()` calls `template()` calls `helper()` → STOP at 2 levels
   - Don't track calls made by infrastructure/SDK functions

2. **SDK/Framework Calls**
   - Calls to `acceptance.*`, `check.*`, `fmt.*`, etc.
   - These are framework code, not test templates

3. **Cross-Package Calls**
   - Calls to other packages (unless it's a tracked test function)

### Rule 3: Template Nesting Depth

**Maximum Depth: 2 levels**

Example chain:
```
TestAccPrivateEndpoint_basic()              // Test function
  └─> r.basic(data)                          // Level 1: Direct call
       └─> r.template(data, r.serviceAuto()) // Level 2: Nested call
            └─> (STOP - don't track deeper)  // Level 3: NOT tracked
```

**Why 2 levels?**
- Observed pattern: Test → Template1 → Template2 (max depth in real code)
- Prevents explosion from SDK function chains
- Captures all HCL configuration dependencies

---

## Implementation Plan

### Phase 1: Function Filtering (`extractFunctions`)

```go
// Pseudo-code for filtering logic
func shouldIncludeFunction(funcDecl *ast.FuncDecl) bool {
    funcName := funcDecl.Name.Name

    // INCLUDE: Test functions
    if strings.HasPrefix(funcName, "Test") || strings.HasPrefix(funcName, "testAcc") {
        return !funcDecl.HasReceiver()  // Must be standalone, not method
    }

    // EXCLUDE: Infrastructure methods (exact match)
    if funcName in ["Exists", "Destroy", "preCheck", "checkDestroy", "testCheckDestroy"] {
        return false
    }

    // EXCLUDE: SDK helper prefixes
    if strings.HasPrefix(funcName, ["Validate", "Parse", "Marshal", "Unmarshal", "Expand", "Flatten"]) {
        return false
    }

    // EXCLUDE: Metadata suffixes
    if strings.HasSuffix(funcName, ["Schema", "Arguments", "Attributes", "Validator", "Parser", "Client"]) {
        return false
    }

    // INCLUDE: Resource constructors (lowercase new + returns *XxxResource)
    if strings.HasPrefix(funcName, "new") && returnsResourceStruct(funcDecl) {
        return true
    }

    // EXCLUDE: Utility constructors (capital New)
    if strings.HasPrefix(funcName, "New") {
        return false
    }

    // INCLUDE: Methods on *XxxResource receivers that return string
    if funcDecl.HasReceiver() &&
       receiverTypeEndsWith(funcDecl, "Resource") &&
       returnsString(funcDecl) {
        return true
    }

    // EXCLUDE everything else
    return false
}
```

### Phase 2: Call Tracking (`extractFunctionCalls`)

```go
// Pseudo-code for call filtering
func shouldIncludeCall(call *ast.CallExpr, currentFunc *FunctionInfo) bool {
    // MUST be inside a tracked function
    if currentFunc == nil || !isTrackedFunction(currentFunc) {
        return false
    }

    // INCLUDE: Local receiver calls (r.method())
    if call.IsMethodCall && call.Receiver == currentFunc.ReceiverVar {
        return true
    }

    // INCLUDE: Calls to other tracked test/template functions
    if isTrackedFunction(call.TargetFunction) {
        return true
    }

    // EXCLUDE: Framework/SDK calls
    if call.Package in ["acceptance", "check", "fmt", "testing"] {
        return false
    }

    // EXCLUDE: Everything else
    return false
}
```

### Phase 3: Depth Limiting

**Option A: Track Call Depth Per Function**
- Store `callDepth` with each function call record
- Stop tracking at depth > 2

**Option B: Post-Processing Filter**
- Collect all calls
- Build call graph
- Prune branches deeper than 2 levels from test functions

**Recommendation: Option A** (more efficient, filters during extraction)

---

## Expected Results

### Before Filtering (Current AST Analyzer)
- `azurerm_resource_group`: **1,800,000 rows**
- Tracks: ALL functions (including SDK, validators, helpers)
- Call depth: Unlimited (tracks deep SDK chains)

### After Filtering (Fixed AST Analyzer)
- `azurerm_resource_group`: **~70,000 rows** (25x reduction)
- Tracks: Only test functions + template methods on Resource structs
- Call depth: 2 levels max
- Data matches regex-based baseline

---

## Validation Tests

After implementation, validate with:

1. **Row Count Test**
   ```powershell
   .\scripts\terracorder.ps1 -ResourceName "azurerm_resource_group" -RepositoryDirectory "C:\github.com\hashicorp\terraform-provider-azurerm"
   ```
   - Expected: ~70K total rows (not 1.8M)

2. **Function Type Distribution**
   - Test functions: ~8,500
   - Template methods: ~3,000-5,000
   - No Validate*, Parse*, *Schema functions

3. **Call Graph Depth**
   - Max depth from any test function: 2 levels
   - No SDK function chains tracked

4. **Sequential Reference Integrity**
   - Sequential patterns still work (network_manager: 65 refs)
   - Entry points correctly identified

---

## Questions for Review

1. **Is 2-level depth correct?** Or should we track 3 levels?
   - Based on observed patterns: 2 levels is sufficient
   - Can adjust if deeper nesting found

2. **Should we include ALL methods on *XxxResource receivers?**
   - Current plan: Only if they return `string`
   - Alternative: Include all, filter later

3. **What about cross-file template calls?**
   - Pattern: `other_file.TemplateFunc(data)`
   - Current plan: INCLUDE if target is tracked function
   - Need to verify this pattern exists

4. **Constructor function handling?**
   - `newPrivateEndpointResource()` vs `NewClient()`
   - Current plan: Include lowercase `new*` if returns `*Resource`
   - Exclude uppercase `New*`

Please review and confirm filtering strategy before implementation.
