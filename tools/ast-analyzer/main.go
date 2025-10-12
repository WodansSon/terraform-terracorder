package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
)

// FunctionInfo represents a function discovered in the code
type FunctionInfo struct {
	File         string
	Line         int
	FunctionName string
	ReceiverType string // e.g., "PrivateEndpointResource"
	ReceiverVar  string // e.g., "r"
	IsTestFunc   bool
	IsExported   bool
	ServiceName  string // NEW: Service extracted from file path (e.g., "network")
}

// FunctionCall represents a function call site
type FunctionCall struct {
	CallerFunction string
	CallerFile     string
	CallerService  string // NEW: Service of the caller
	Line           int
	ReceiverExpr   string // "r", "other", package name
	MethodName     string // "basic", "withTag"
	IsMethodCall   bool
	IsLocalCall    bool   // true if receiver matches caller's receiver
	FullCall       string // complete call expression for reference
	NumArgs        int    // number of arguments
	Arguments      string // comma-separated argument expressions
	TargetService  string // NEW: Service of the target (if resolvable)
}

// TestStepInfo represents a test step element from []acceptance.TestStep arrays with full source/target tracking
type TestStepInfo struct {
	// Source information (where the test step is)
	SourceFile     string `json:"source_file"`     // File containing this test step
	SourceService  string `json:"source_service"`  // NEW: Service containing this test step
	SourceLine     int    `json:"source_line"`     // Line number where the step starts
	SourceFunction string `json:"source_function"` // Test function containing this step
	SourceStruct   string `json:"source_struct"`   // Struct type if test function is a method
	StepIndex      int    `json:"step_index"`      // Index in the TestStep array (1-based)
	StepBody       string `json:"step_body"`       // Full text of the {Config:..., Check:...} element

	// Target information (what the Config field references)
	ConfigExpr     string `json:"config_expr"`     // Full Config expression (e.g., "r.basic(data)")
	ConfigVariable string `json:"config_variable"` // Variable name (e.g., "r")
	ConfigMethod   string `json:"config_method"`   // Method name (e.g., "basic")
	ConfigStruct   string `json:"config_struct"`   // Resolved struct type (e.g., "PrivateEndpointResource")
	ConfigService  string `json:"config_service"`  // NEW: Service of config struct
	IsLocalCall    bool   `json:"is_local_call"`   // true if config_struct is in same file
	TargetFile     string `json:"target_file"`     // File where the config method is defined (if cross-file)
	TargetLine     int    `json:"target_line"`     // Line number where the config method is defined
}

// TemplateFunctionCall represents a call from one template function to another
// Found in fmt.Sprintf arguments like: fmt.Sprintf("%s\nresource...", r.template(data))
type TemplateFunctionCall struct {
	SourceFunction string `json:"source_function"` // The template function making the call
	SourceFile     string `json:"source_file"`
	SourceService  string `json:"source_service"` // NEW: Service of source
	SourceLine     int    `json:"source_line"`

	TargetExpr     string `json:"target_expr"`     // Full expression: r.template(data)
	TargetVariable string `json:"target_variable"` // Variable: r
	TargetMethod   string `json:"target_method"`   // Method: template
	TargetStruct   string `json:"target_struct"`   // Resolved struct type
	TargetService  string `json:"target_service"`  // NEW: Service of target
	IsLocalCall    bool   `json:"is_local_call"`
	TargetFile     string `json:"target_file"`
	TargetLine     int    `json:"target_line"`
}

// SequentialReference represents a sequential test call (t.Run or RunTestsInSequence)
type SequentialReference struct {
	EntryPointFunction string `json:"entry_point_function"` // The test function calling t.Run or RunTestsInSequence
	EntryPointFile     string `json:"entry_point_file"`
	EntryPointLine     int    `json:"entry_point_line"`

	ReferencedFunction string `json:"referenced_function"` // The function being called sequentially
	SequentialGroup    string `json:"sequential_group"`    // Group name (e.g., "interactiveQuery", "hadoop")
	SequentialKey      string `json:"sequential_key"`      // Key name (e.g., "securityProfile", "basic")
}

// DirectResourceReference represents a direct mention of an Azure resource in HCL template code
type DirectResourceReference struct {
	TemplateFunction string `json:"template_function"` // Template function containing this reference
	TemplateFile     string `json:"template_file"`
	TemplateLine     int    `json:"template_line"` // Line in source where template function is defined

	ResourceName  string `json:"resource_name"`  // e.g., "azurerm_resource_group", "azurerm_virtual_network"
	ReferenceType string `json:"reference_type"` // "RESOURCE_BLOCK" or "ATTRIBUTE_REFERENCE"
	Context       string `json:"context"`        // The actual HCL line containing the reference
	ContextLine   int    `json:"context_line"`   // Line number within the HCL string (relative)
}

// VarAssignment tracks variable assignments within a function scope
// Used to resolve patterns like: config := r.multipleInstances(...)
type VarAssignment struct {
	VarName        string // The variable name (e.g., "config")
	ReceiverVar    string // The receiver variable (e.g., "r")
	ReceiverStruct string // The struct type (e.g., "PrivateEndpointResource")
	MethodName     string // The method being called (e.g., "multipleInstances")
	FullExpr       string // Full assignment expression
}

// FunctionReturnType tracks function declarations and their return types
type FunctionReturnType struct {
	FunctionName string // The function name (e.g., "newSiteRecoveryVMWareReplicatedVMResource")
	ReturnType   string // The primary return type (ignoring error returns)
}

// ASTAnalysisResult is the consolidated output structure for JSON format
type ASTAnalysisResult struct {
	FilePath             string                    `json:"file_path"`
	Functions            []FunctionInfo            `json:"functions"`
	Calls                []FunctionCall            `json:"calls"`
	Imports              []ImportInfo              `json:"imports"`
	TestSteps            []TestStepInfo            `json:"test_steps"`
	TemplateCalls        []TemplateFunctionCall    `json:"template_calls"`
	SequentialReferences []SequentialReference     `json:"sequential_references"`
	DirectResourceRefs   []DirectResourceReference `json:"direct_resource_references"`
	Patterns             *PatternDetector          `json:"patterns,omitempty"`
}

var (
	filePath     = flag.String("file", "", "Go file to analyze")
	repoRoot     = flag.String("reporoot", "", "Repository root directory (for relative path conversion)")
	resourceName = flag.String("resourcename", "", "Target resource name to filter direct references (e.g., azurerm_resource_group)")
	verbose      = flag.Bool("verbose", false, "Verbose output")
)

// toRelativePath converts an absolute file path to relative based on repository root
func toRelativePath(absPath string) string {
	if *repoRoot == "" {
		fmt.Fprintf(os.Stderr, "Error: -reporoot parameter is required for relative path conversion\n")
		os.Exit(1)
	}

	// Use Go's standard library to compute relative path
	relPath, err := filepath.Rel(*repoRoot, absPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: Failed to convert path to relative: %v\n", err)
		os.Exit(1)
	}

	// Convert to forward slashes for consistency across platforms
	return filepath.ToSlash(relPath)
}

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

func main() {
	flag.Parse()

	if *filePath == "" {
		fmt.Println("Usage: ast-analyzer -file <path-to-go-file> -reporoot <repo-root>")
		flag.PrintDefaults()
		os.Exit(1)
	}

	// Parse the file
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, *filePath, nil, parser.ParseComments)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing file: %v\n", err)
		os.Exit(1)
	}

	// Extract data using absolute paths throughout
	functions := extractFunctions(file, fset, *filePath)
	// Enrich test functions with struct information from their body
	enrichTestFunctionsWithStructInfo(file, fset, *filePath, &functions)
	calls := extractFunctionCalls(file, fset, *filePath, functions)
	imports := extractImports(file)
	testSteps := extractTestSteps(file, fset, *filePath, functions)
	templateCalls := extractTemplateCalls(file, fset, *filePath, functions)
	sequentialRefs := extractSequentialReferences(file, fset, *filePath, functions)
	directRefs := extractDirectResourceReferences(file, fset, *filePath, functions, *resourceName)

	// Detect patterns (sequential, map-based, anonymous functions)
	patterns := DetectPatterns(file, *filePath)

	// Convert to relative path for output
	relativeFilePath := toRelativePath(*filePath)

	// Convert all file paths in the results to relative paths
	for i := range functions {
		functions[i].File = toRelativePath(functions[i].File)
	}
	for i := range calls {
		calls[i].CallerFile = toRelativePath(calls[i].CallerFile)
	}
	for i := range testSteps {
		testSteps[i].SourceFile = toRelativePath(testSteps[i].SourceFile)
		if testSteps[i].TargetFile != "" {
			testSteps[i].TargetFile = toRelativePath(testSteps[i].TargetFile)
		}
	}
	for i := range templateCalls {
		templateCalls[i].SourceFile = toRelativePath(templateCalls[i].SourceFile)
		if templateCalls[i].TargetFile != "" {
			templateCalls[i].TargetFile = toRelativePath(templateCalls[i].TargetFile)
		}
	}
	for i := range sequentialRefs {
		sequentialRefs[i].EntryPointFile = toRelativePath(sequentialRefs[i].EntryPointFile)
	}
	for i := range directRefs {
		directRefs[i].TemplateFile = toRelativePath(directRefs[i].TemplateFile)
	}
	for i := range patterns.VisibilityInfo {
		if patterns.VisibilityInfo[i].FilePath != "" {
			patterns.VisibilityInfo[i].FilePath = toRelativePath(patterns.VisibilityInfo[i].FilePath)
		}
	}

	// Output JSON to stdout for PowerShell to capture
	result := ASTAnalysisResult{
		FilePath:             relativeFilePath,
		Functions:            functions,
		Calls:                calls,
		Imports:              imports,
		TestSteps:            testSteps,
		TemplateCalls:        templateCalls,
		SequentialReferences: sequentialRefs,
		DirectResourceRefs:   directRefs,
		Patterns:             patterns,
	}

	jsonData, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error marshaling JSON: %v\n", err)
		os.Exit(1)
	}

	// Write JSON to stdout (PowerShell will capture this)
	fmt.Println(string(jsonData))
}

// extractFunctions finds all function declarations - FILTERED for test relevance
func extractFunctions(file *ast.File, fset *token.FileSet, filename string) []FunctionInfo {
	var functions []FunctionInfo

	// CRITICAL FILTER: Only track test-relevant functions
	// This prevents the data explosion (1.8M rows -> ~70K rows)

	// Infrastructure/test lifecycle method names to exclude
	infraMethodNames := map[string]bool{
		"Exists":           true,
		"Destroy":          true,
		"preCheck":         true,
		"checkDestroy":     true,
		"testCheckDestroy": true,
	}

	// Prefixes to exclude
	excludePrefixes := []string{
		"Validate", "Parse", "Marshal", "Unmarshal",
		"Expand", "Flatten",
	}

	// Suffixes to exclude
	excludeSuffixes := []string{
		"Schema", "Arguments", "Attributes",
		"Validator", "Parser", "Client",
	}

	ast.Inspect(file, func(n ast.Node) bool {
		funcDecl, ok := n.(*ast.FuncDecl)
		if !ok {
			return true
		}

		funcName := funcDecl.Name.Name

		// FILTER 1: Exact match exclusions
		if infraMethodNames[funcName] {
			return true
		}

		// FILTER 2: Prefix-based exclusions
		for _, prefix := range excludePrefixes {
			if strings.HasPrefix(funcName, prefix) {
				return true
			}
		}

		// FILTER 3: Suffix-based exclusions
		for _, suffix := range excludeSuffixes {
			if strings.HasSuffix(funcName, suffix) {
				return true
			}
		}

		// FILTER 4: Capital New* utilities (exclude)
		// But lowercase newXxxResource() constructors are handled in FILTER 6
		if len(funcName) > 0 && funcName[0] == 'N' && strings.HasPrefix(funcName, "New") {
			return true
		}

		// FILTER 5: Test functions (include)
		isTestFunc := strings.HasPrefix(funcName, "Test") || strings.HasPrefix(funcName, "testAcc")

		// FILTER 6: Lowercase newXxxResource() constructors (include if returns *XxxResource)
		isResourceConstructor := false
		if len(funcName) > 0 && funcName[0] == 'n' && strings.HasPrefix(funcName, "new") &&
			strings.HasSuffix(funcName, "Resource") && funcDecl.Recv == nil {
			// Check if it returns *XxxResource
			if funcDecl.Type.Results != nil {
				for _, field := range funcDecl.Type.Results.List {
					if starExpr, ok := field.Type.(*ast.StarExpr); ok {
						if ident, ok := starExpr.X.(*ast.Ident); ok {
							if strings.HasSuffix(ident.Name, "Resource") {
								isResourceConstructor = true
								break
							}
						}
					}
				}
			}
		}

		// FILTER 7: Resource receiver methods that return string (template methods)
		hasResourceReceiver := false
		returnsString := false

		if funcDecl.Recv != nil && len(funcDecl.Recv.List) > 0 {
			recv := funcDecl.Recv.List[0]
			var receiverTypeName string

			switch recvType := recv.Type.(type) {
			case *ast.StarExpr:
				// Pointer receiver: (r *ManagerResource)
				if ident, ok := recvType.X.(*ast.Ident); ok {
					receiverTypeName = ident.Name
				}
			case *ast.Ident:
				// Value receiver: (r ManagerResource)
				receiverTypeName = recvType.Name
			}

			// Only track methods on XxxResource structs (pointer or value receiver)
			if strings.HasSuffix(receiverTypeName, "Resource") {
				hasResourceReceiver = true

				// Check if returns string
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
			}
		}

		// Accept function only if it matches one of our criteria:
		// - Test function (Test* or testAcc*)
		// - Resource constructor (newXxxResource returning *XxxResource)
		// - Resource method returning string (template method)
		if !isTestFunc && !isResourceConstructor && !(hasResourceReceiver && returnsString) {
			return true
		}

		// Extract service name from file path
		serviceName := extractServiceName(filename)

		fn := FunctionInfo{
			File:         filename,
			Line:         fset.Position(funcDecl.Pos()).Line,
			FunctionName: funcName,
			IsTestFunc:   isTestFunc,
			IsExported:   ast.IsExported(funcName),
			ServiceName:  serviceName,
		}

		// Extract receiver if this is a method
		if funcDecl.Recv != nil && len(funcDecl.Recv.List) > 0 {
			recv := funcDecl.Recv.List[0]

			// Get receiver variable name (e.g., "r")
			if len(recv.Names) > 0 {
				fn.ReceiverVar = recv.Names[0].Name
			}

			// Get receiver type (e.g., "PrivateEndpointResource")
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

// enrichTestFunctionsWithStructInfo finds struct assignments in test function bodies
// and updates the ReceiverType for test functions (which are not methods)
func enrichTestFunctionsWithStructInfo(file *ast.File, fset *token.FileSet, filePath string, functions *[]FunctionInfo) {
	// Build function return type map (for resolving function calls)
	functionReturnTypes := extractFunctionReturnTypes(file)

	// Create map of line -> function for lookup
	lineToFunc := make(map[int]*FunctionInfo)
	for i := range *functions {
		fn := &(*functions)[i]
		lineToFunc[fn.Line] = fn
	}

	// Visit each function and look for struct assignments
	ast.Inspect(file, func(n ast.Node) bool {
		funcDecl, ok := n.(*ast.FuncDecl)
		if !ok {
			return true
		}

		// Only process test functions
		funcName := funcDecl.Name.Name
		if !strings.HasPrefix(funcName, "Test") && !strings.HasPrefix(funcName, "testAcc") {
			return true
		}

		// Skip if it's already a method (has a receiver)
		if funcDecl.Recv != nil {
			return true
		}

		// Find the corresponding FunctionInfo
		line := fset.Position(funcDecl.Pos()).Line
		fn, exists := lineToFunc[line]
		if !exists {
			return true
		}

		// Look for the first variable assignment in the function body
		// Pattern: r := StructName{} or r, err := newFunction()
		ast.Inspect(funcDecl.Body, func(n ast.Node) bool {
			// Stop if we already found a struct type
			if fn.ReceiverType != "" {
				return false
			}

			assignStmt, ok := n.(*ast.AssignStmt)
			if !ok {
				return true
			}

			// We need at least one LHS and RHS
			if len(assignStmt.Lhs) == 0 || len(assignStmt.Rhs) == 0 {
				return true
			}

			// Get the first variable name
			lhsIdent, ok := assignStmt.Lhs[0].(*ast.Ident)
			if !ok {
				return true
			}
			varName := lhsIdent.Name

			// Only care about 'r' variable (common convention)
			if varName != "r" {
				return true
			}

			rhsExpr := assignStmt.Rhs[0]

			// Pattern 1: r := StructName{}
			if compLit, ok := rhsExpr.(*ast.CompositeLit); ok {
				if ident, ok := compLit.Type.(*ast.Ident); ok {
					fn.ReceiverType = ident.Name
					fn.ReceiverVar = varName
					return false // Found it, stop searching
				}
			}

			// Pattern 2: r, err := newFunction()
			if callExpr, ok := rhsExpr.(*ast.CallExpr); ok {
				if funcIdent, ok := callExpr.Fun.(*ast.Ident); ok {
					functionName := funcIdent.Name
					if returnType, exists := functionReturnTypes[functionName]; exists {
						fn.ReceiverType = returnType
						fn.ReceiverVar = varName
						return false // Found it, stop searching
					}
				}
			}

			return true
		})

		return true
	})
}

// extractFunctionCalls finds all function call sites - FILTERED to prevent explosion
func extractFunctionCalls(file *ast.File, fset *token.FileSet, filename string, functions []FunctionInfo) []FunctionCall {
	var calls []FunctionCall

	// CRITICAL FILTER: Only track calls in Config: field and template bodies
	// IGNORE all calls in Check: field (validation code)

	// Build map of line -> function for determining caller context
	lineToFunc := make(map[int]FunctionInfo)
	for _, fn := range functions {
		lineToFunc[fn.Line] = fn
	}

	// Build set of tracked function names (test functions and resource methods)
	trackedFunctions := make(map[string]bool)
	for _, fn := range functions {
		trackedFunctions[fn.FunctionName] = true
	}

	// Extract service name from file path
	serviceName := extractServiceName(filename)

	// Track current function context
	var currentFunc *FunctionInfo
	inCheckBlock := false // Track if we're inside a Check: block

	ast.Inspect(file, func(n ast.Node) bool {
		// Track which function we're in
		if funcDecl, ok := n.(*ast.FuncDecl); ok {
			line := fset.Position(funcDecl.Pos()).Line
			if fn, exists := lineToFunc[line]; exists {
				currentFunc = &fn
				inCheckBlock = false // Reset Check block flag
			} else {
				// Not in a tracked function, don't process calls
				currentFunc = nil
				inCheckBlock = false
			}
		}

		// CRITICAL: Detect Check: field in test steps
		// Check blocks contain validation code (Exists, checkDestroy), NOT configuration
		if kvExpr, ok := n.(*ast.KeyValueExpr); ok {
			if ident, ok := kvExpr.Key.(*ast.Ident); ok {
				if ident.Name == "Check" {
					inCheckBlock = true
					return false // Don't visit children of Check block
				}
			}
		}

		// FILTER: Only track calls if we're inside a tracked function AND NOT in Check block
		if currentFunc == nil || inCheckBlock {
			return true
		}

		// Look for function calls
		callExpr, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}

		call := FunctionCall{
			CallerFile:    filename,
			CallerService: serviceName,
			Line:          fset.Position(callExpr.Pos()).Line,
		}

		if currentFunc != nil {
			call.CallerFunction = currentFunc.FunctionName
		}

		// Analyze the call expression
		switch fun := callExpr.Fun.(type) {
		case *ast.SelectorExpr:
			// Method call: receiver.method()
			call.IsMethodCall = true
			call.MethodName = fun.Sel.Name

			// Get receiver expression
			if ident, ok := fun.X.(*ast.Ident); ok {
				call.ReceiverExpr = ident.Name

				// Check if this is a local receiver call
				if currentFunc != nil && currentFunc.ReceiverVar == ident.Name {
					call.IsLocalCall = true
				}
			} else {
				// Complex receiver expression (e.g., pkg.Type)
				call.ReceiverExpr = exprToString(fun.X)
			}

			call.FullCall = fmt.Sprintf("%s.%s", call.ReceiverExpr, call.MethodName)

		case *ast.Ident:
			// Direct function call
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

		// FILTER: Only record calls to other tracked functions OR local receiver calls
		// This prevents tracking calls to SDK functions, validators, etc.
		shouldRecord := false
		targetService := ""

		if call.IsLocalCall {
			// Always track local receiver calls (r.method())
			shouldRecord = true
			targetService = serviceName // Same service
		} else if trackedFunctions[call.MethodName] {
			// Track calls to other tracked test/template functions
			shouldRecord = true

			// Find the target function to get its service
			for _, fn := range functions {
				if fn.FunctionName == call.MethodName {
					targetService = fn.ServiceName
					break
				}
			}
		}

		if shouldRecord && call.MethodName != "" {
			call.TargetService = targetService
			calls = append(calls, call)
		}

		return true
	})

	return calls
}

// extractImports finds all import statements
func extractImports(file *ast.File) []ImportInfo {
	var imports []ImportInfo

	for _, imp := range file.Imports {
		info := ImportInfo{
			PackagePath: strings.Trim(imp.Path.Value, `"`),
		}

		if imp.Name != nil {
			info.Alias = imp.Name.Name
		} else {
			// Extract package name from path
			parts := strings.Split(info.PackagePath, "/")
			info.PackageName = parts[len(parts)-1]
		}

		imports = append(imports, info)
	}

	return imports
}

// extractFunctionReturnTypes walks the AST to find function declarations and their return types
// This is used to resolve patterns like: r, err := newSomeResource(...)
func extractFunctionReturnTypes(file *ast.File) map[string]string {
	returnTypes := make(map[string]string)

	ast.Inspect(file, func(n ast.Node) bool {
		funcDecl, ok := n.(*ast.FuncDecl)
		if !ok {
			return true
		}

		// Skip methods (we only want package-level functions)
		if funcDecl.Recv != nil {
			return true
		}

		// Skip functions with no return values
		if funcDecl.Type.Results == nil || len(funcDecl.Type.Results.List) == 0 {
			return true
		}

		functionName := funcDecl.Name.Name

		// Extract the first non-error return type
		// Pattern: func newResource(...) (*SomeResource, error)
		// We want to capture "SomeResource" (ignoring pointer and error)
		for _, field := range funcDecl.Type.Results.List {
			var typeName string

			switch t := field.Type.(type) {
			case *ast.Ident:
				// Direct type: error, bool, etc.
				typeName = t.Name
			case *ast.StarExpr:
				// Pointer type: *SomeResource
				if ident, ok := t.X.(*ast.Ident); ok {
					typeName = ident.Name
				}
			case *ast.SelectorExpr:
				// Package-qualified type: pkg.Type
				if ident, ok := t.X.(*ast.Ident); ok {
					typeName = ident.Name + "." + t.Sel.Name
				}
			}

			// Skip error types - we want the actual return value
			if typeName != "" && typeName != "error" {
				returnTypes[functionName] = typeName
				break // Take the first non-error type
			}
		}

		return true
	})
	return returnTypes
}

// extractVariableAssignments processes assignment statements to track local variables
// Handles patterns like:
//   - r := PrivateEndpointResource{} (struct instantiation)
//   - config := r.multipleInstances(data, count, false) (method call)
//   - r, err := newSiteRecoveryVMWareReplicatedVMResource(...) (function call with multiple returns)
func extractVariableAssignments(assignStmt *ast.AssignStmt, varAssignments map[string]*VarAssignment, currentFunc *FunctionInfo, functionReturnTypes map[string]string, fset *token.FileSet, source string) {
	// Handle different assignment patterns:
	// 1. Simple: x := value (len(LHS) == len(RHS))
	// 2. Multi-value return: x, y := function() (len(LHS) > len(RHS), RHS is call expression)

	// For multi-value returns, process the first LHS variable with the call expression
	if len(assignStmt.Lhs) > len(assignStmt.Rhs) {
		// Multi-value return from function call
		if len(assignStmt.Rhs) != 1 {
			return // Unexpected pattern
		}

		// Get the first variable being assigned to (usually the return value, e.g., "r")
		lhsIdent, ok := assignStmt.Lhs[0].(*ast.Ident)
		if !ok {
			return
		}

		varName := lhsIdent.Name
		rhsExpr := assignStmt.Rhs[0]

		// Check if RHS is a function call
		callExpr, ok := rhsExpr.(*ast.CallExpr)
		if !ok {
			return
		}

		// Check if it's a simple function call (not a method)
		if funcIdent, ok := callExpr.Fun.(*ast.Ident); ok {
			functionName := funcIdent.Name

			// Look up the function's return type
			if returnType, exists := functionReturnTypes[functionName]; exists {
				// Extract full expression text
				startPos := fset.Position(rhsExpr.Pos())
				endPos := fset.Position(rhsExpr.End())
				fullExpr := extractTextRange(source, startPos, endPos)

				// Store the assignment with the function's return type as the struct
				varAssignments[varName] = &VarAssignment{
					VarName:        varName,
					ReceiverVar:    varName,
					ReceiverStruct: returnType,
					MethodName:     functionName, // Store the constructor function name
					FullExpr:       fullExpr,
				}
			}
		}
		return
	}

	// Simple assignments: len(LHS) == len(RHS)
	if len(assignStmt.Lhs) != len(assignStmt.Rhs) {
		return // Mismatched assignment
	}

	for i := 0; i < len(assignStmt.Lhs); i++ {
		// Get the variable being assigned to
		lhsIdent, ok := assignStmt.Lhs[i].(*ast.Ident)
		if !ok {
			continue // Not a simple identifier
		}

		varName := lhsIdent.Name
		rhsExpr := assignStmt.Rhs[i]

		// Pattern 1: Struct instantiation (r := PrivateEndpointResource{})
		if compLit, ok := rhsExpr.(*ast.CompositeLit); ok {
			if ident, ok := compLit.Type.(*ast.Ident); ok {
				structName := ident.Name
				// Store as a special assignment with no method
				varAssignments[varName] = &VarAssignment{
					VarName:        varName,
					ReceiverVar:    varName,
					ReceiverStruct: structName,
					MethodName:     "", // No method - this is the struct itself
					FullExpr:       structName + "{}",
				}
			}
			continue
		}

		// Patterns 2 & 3: Function/method call
		callExpr, ok := rhsExpr.(*ast.CallExpr)
		if !ok {
			continue // Not a function call
		}

		// Pattern 2: Method call (config := r.multipleInstances(...))
		if selectorExpr, ok := callExpr.Fun.(*ast.SelectorExpr); ok {
			// Extract receiver variable
			receiverIdent, ok := selectorExpr.X.(*ast.Ident)
			if !ok {
				continue // Receiver is not a simple identifier
			}

			// Extract method name
			methodName := selectorExpr.Sel.Name
			receiverVar := receiverIdent.Name

			// Resolve receiver struct in priority order:
			// 1. Check if it's the function's receiver
			// 2. Check if it's a previously tracked local variable
			receiverStruct := ""
			if currentFunc != nil && currentFunc.ReceiverVar == receiverVar {
				receiverStruct = currentFunc.ReceiverType
			} else if prevAssignment, exists := varAssignments[receiverVar]; exists {
				receiverStruct = prevAssignment.ReceiverStruct
			}

			// Extract full expression text
			startPos := fset.Position(rhsExpr.Pos())
			endPos := fset.Position(rhsExpr.End())
			fullExpr := extractTextRange(source, startPos, endPos)

			// Store the assignment
			varAssignments[varName] = &VarAssignment{
				VarName:        varName,
				ReceiverVar:    receiverVar,
				ReceiverStruct: receiverStruct,
				MethodName:     methodName,
				FullExpr:       fullExpr,
			}
			continue
		}

		// Pattern 3: Function call (r, err := newSiteRecoveryVMWareReplicatedVMResource(...))
		if funcIdent, ok := callExpr.Fun.(*ast.Ident); ok {
			functionName := funcIdent.Name

			// Look up the function's return type
			if returnType, exists := functionReturnTypes[functionName]; exists {
				// Extract full expression text
				startPos := fset.Position(rhsExpr.Pos())
				endPos := fset.Position(rhsExpr.End())
				fullExpr := extractTextRange(source, startPos, endPos)

				// Store the assignment with the function's return type as the struct
				varAssignments[varName] = &VarAssignment{
					VarName:        varName,
					ReceiverVar:    varName,
					ReceiverStruct: returnType,
					MethodName:     functionName, // Store the constructor function name
					FullExpr:       fullExpr,
				}
			}
		}
	}
}

// extractVariableDeclarations handles var declarations like: var f FluidRelayResource
func extractVariableDeclarations(declStmt *ast.DeclStmt, varAssignments map[string]*VarAssignment) {
	// Check if this is a GenDecl (general declaration)
	genDecl, ok := declStmt.Decl.(*ast.GenDecl)
	if !ok {
		return
	}

	// We only care about variable declarations (var)
	if genDecl.Tok != token.VAR {
		return
	}

	// Process each spec in the declaration
	for _, spec := range genDecl.Specs {
		valueSpec, ok := spec.(*ast.ValueSpec)
		if !ok {
			continue
		}

		// Extract the type information
		var typeName string
		switch t := valueSpec.Type.(type) {
		case *ast.Ident:
			// Simple type: var f FluidRelayResource
			typeName = t.Name
		case *ast.StarExpr:
			// Pointer type: var f *FluidRelayResource
			if ident, ok := t.X.(*ast.Ident); ok {
				typeName = ident.Name
			}
		case *ast.SelectorExpr:
			// Qualified type: var f package.FluidRelayResource
			typeName = t.Sel.Name
		default:
			continue
		}

		// Store the declaration for each variable name
		for _, name := range valueSpec.Names {
			varName := name.Name
			varAssignments[varName] = &VarAssignment{
				VarName:        varName,
				ReceiverVar:    varName,
				ReceiverStruct: typeName,
				MethodName:     "", // No method - this is the variable itself
				FullExpr:       "var " + varName + " " + typeName,
			}
		}
	}
}

// extractTestSteps finds []acceptance.TestStep composite literals and extracts each element
func extractTestSteps(file *ast.File, fset *token.FileSet, filePath string, functions []FunctionInfo) []TestStepInfo {
	var testSteps []TestStepInfo

	// Extract function return types for resolving function call assignments
	functionReturnTypes := extractFunctionReturnTypes(file)

	// Build map of line -> function for determining caller context
	lineToFunc := make(map[int]FunctionInfo)
	for _, fn := range functions {
		lineToFunc[fn.Line] = fn
	}

	// Extract service name from file path
	serviceName := extractServiceName(filePath)

	// Track current function context
	var currentFunc *FunctionInfo

	// Track variable assignments in current function scope
	// Map: variable name -> assignment expression info
	varAssignments := make(map[string]*VarAssignment)

	// Read the source file to extract text using absolute path
	sourceBytes, err := os.ReadFile(filePath)
	if err != nil {
		// Silent failure - return empty results if file cannot be read
		return testSteps
	}
	source := string(sourceBytes)

	ast.Inspect(file, func(n ast.Node) bool {
		// Track which function we're in
		if funcDecl, ok := n.(*ast.FuncDecl); ok {
			line := fset.Position(funcDecl.Pos()).Line
			if fn, exists := lineToFunc[line]; exists {
				currentFunc = &fn
				// Clear variable assignments when entering new function
				varAssignments = make(map[string]*VarAssignment)
			}
		}

		// Track variable assignments like: config := r.multipleInstances(...)
		if assignStmt, ok := n.(*ast.AssignStmt); ok && currentFunc != nil {
			extractVariableAssignments(assignStmt, varAssignments, currentFunc, functionReturnTypes, fset, source)
		}

		// Track variable declarations like: var f FluidRelayResource
		if declStmt, ok := n.(*ast.DeclStmt); ok && currentFunc != nil {
			extractVariableDeclarations(declStmt, varAssignments)
		}

		// Look for composite literals (arrays/slices)
		compLit, ok := n.(*ast.CompositeLit)
		if !ok {
			return true
		}

		// Check if this is []acceptance.TestStep type
		arrayType, ok := compLit.Type.(*ast.ArrayType)
		if !ok {
			return true
		}

		// Check if element type is acceptance.TestStep
		selectorExpr, ok := arrayType.Elt.(*ast.SelectorExpr)
		if !ok {
			return true
		}

		// Verify it's acceptance.TestStep (or similar patterns)
		pkgIdent, ok := selectorExpr.X.(*ast.Ident)
		if !ok {
			return true
		}

		// Match patterns: acceptance.TestStep, resource.TestStep, pluginsdk.TestStep, etc.
		if pkgIdent.Name != "acceptance" && pkgIdent.Name != "resource" && pkgIdent.Name != "pluginsdk" {
			return true
		}

		if selectorExpr.Sel.Name != "TestStep" {
			return true
		}

		// Found a []acceptance.TestStep{...} array!
		// Extract each element in the array
		stepIndex := 1
		for _, elt := range compLit.Elts {
			// Each element should be a composite literal {Config: ..., Check: ...}
			stepLit, ok := elt.(*ast.CompositeLit)
			if !ok {
				continue
			}

			// FILTER: Skip infrastructure validation test steps
			// We only want steps that test actual resource configuration.
			// Filter out:
			// 1. Steps with no Config field (import-only steps, check-only steps)
			//    Examples: data.ImportStep(), steps with only Check field
			//
			// Keep steps that have Config field (actual configuration tests)
			// - It's OK if they also have Check (validation is expected)
			// - It's OK if they have ExpectError (error configs can have cross-service references)
			hasConfigField := false
			for _, field := range stepLit.Elts {
				kvExpr, ok := field.(*ast.KeyValueExpr)
				if !ok {
					continue
				}
				if key, ok := kvExpr.Key.(*ast.Ident); ok {
					if key.Name == "Config" {
						hasConfigField = true
						break
					}
				}
			}

			// Skip this step if it has no Config field
			if !hasConfigField {
				continue
			} // Get the full text of this element from source
			startPos := fset.Position(stepLit.Pos())
			endPos := fset.Position(stepLit.End())

			// Extract text from source
			stepBody := extractTextRange(source, startPos, endPos)

			stepInfo := TestStepInfo{
				SourceFile:    filePath,
				SourceLine:    startPos.Line,
				StepIndex:     stepIndex,
				StepBody:      stepBody,
				SourceService: serviceName,
			}

			if currentFunc != nil {
				stepInfo.SourceFunction = currentFunc.FunctionName
				stepInfo.SourceStruct = currentFunc.ReceiverType
			}

			// Extract Config field information
			extractConfigInfo(&stepInfo, stepLit, fset, source, currentFunc, varAssignments, functions)

			testSteps = append(testSteps, stepInfo)
			stepIndex++
		}

		return true
	})

	return testSteps
}

// extractTemplateCalls finds template function calls within fmt.Sprintf arguments
// This builds the template -> template reference chain for IndirectConfigReferences
// CROSS-FILE ONLY: Only tracks calls to methods in different files (cross-service dependencies)
func extractTemplateCalls(file *ast.File, fset *token.FileSet, filePath string, functions []FunctionInfo) []TemplateFunctionCall {
	var templateCalls []TemplateFunctionCall

	// Build a map of line -> function for context tracking
	lineToFunc := make(map[int]FunctionInfo)
	for _, fn := range functions {
		lineToFunc[fn.Line] = fn
	}

	// Build a map of method name -> function for same-file detection
	// Key: "ReceiverType.MethodName" -> FunctionInfo
	methodToFunc := make(map[string]FunctionInfo)
	for _, fn := range functions {
		if fn.ReceiverType != "" {
			key := fn.ReceiverType + "." + fn.FunctionName
			methodToFunc[key] = fn
		}
	}

	// Extract service name from file path
	serviceName := extractServiceName(filePath)

	// Read source for text extraction using absolute path
	sourceBytes, err := os.ReadFile(filePath)
	if err != nil {
		// Silent failure - return empty results if file cannot be read
		return templateCalls
	}
	source := string(sourceBytes)

	// Track current function context
	var currentFunc *FunctionInfo

	ast.Inspect(file, func(n ast.Node) bool {
		// Track which function we're in
		if funcDecl, ok := n.(*ast.FuncDecl); ok {
			line := fset.Position(funcDecl.Pos()).Line
			if fn, exists := lineToFunc[line]; exists {
				currentFunc = &fn
			}
		}

		// Look for function calls
		callExpr, ok := n.(*ast.CallExpr)
		if !ok || currentFunc == nil {
			return true
		}

		// Check if this is a fmt.Sprintf call
		if !isFmtSprintfCall(callExpr) {
			return true
		}

		// Extract template calls from sprintf arguments (skip the format string)
		for i, arg := range callExpr.Args {
			if i == 0 {
				// Skip the format string
				continue
			}

			// Extract template calls (cross-file only)
			extractTemplateCallsFromExpr(arg, currentFunc, filePath, serviceName, fset, source, methodToFunc, functions, &templateCalls)
		}

		return true
	})

	return templateCalls
}

// extractTemplateCallsFromExpr extracts template calls from an expression
// CROSS-FILE ONLY: Only extracts calls to methods in different files
// DEPTH LIMIT: Only extracts the top-level call, NOT nested calls within arguments
// Example: fmt.Sprintf("%s", r.basic(data))
//   - If basic() is in same file: SKIP (embedded call, not tracked)
//   - If basic() is in different file: TRACK (cross-file dependency)
func extractTemplateCallsFromExpr(expr ast.Expr, currentFunc *FunctionInfo, filePath string, serviceName string, fset *token.FileSet, source string, methodToFunc map[string]FunctionInfo, functions []FunctionInfo, templateCalls *[]TemplateFunctionCall) {
	// Check if this expression itself is a template call
	templateCall := analyzeTemplateCallExpr(expr, fset, source)
	if templateCall == nil {
		return
	}

	// Set source information
	templateCall.SourceFunction = currentFunc.FunctionName
	templateCall.SourceFile = filePath
	templateCall.SourceLine = fset.Position(expr.Pos()).Line
	templateCall.SourceService = serviceName

	// Resolve the struct type if the variable is the receiver
	if templateCall.TargetVariable != "" &&
		currentFunc.ReceiverVar != "" &&
		templateCall.TargetVariable == currentFunc.ReceiverVar {
		templateCall.TargetStruct = currentFunc.ReceiverType
	}

	// Track ALL template calls (same-file + cross-file) for complete dependency chains
	// Mark same-file calls with IsLocalCall flag, but ALWAYS append them
	if templateCall.TargetStruct != "" && templateCall.TargetMethod != "" {
		key := templateCall.TargetStruct + "." + templateCall.TargetMethod
		if _, existsInSameFile := methodToFunc[key]; existsInSameFile {
			// Same-file call - mark as local (internal template composition)
			templateCall.IsLocalCall = true
			// Determine target service from the same file (use current function's service)
			templateCall.TargetService = currentFunc.ServiceName
		} else {
			// Cross-file call - mark as non-local
			templateCall.IsLocalCall = false
			// Determine target service by looking up the method in functions
			for _, fn := range functions {
				if fn.ReceiverType == templateCall.TargetStruct && fn.FunctionName == templateCall.TargetMethod {
					templateCall.TargetService = fn.ServiceName
					break
				}
			}
		}
	}

	// This is a cross-file call - track it
	*templateCalls = append(*templateCalls, *templateCall)

	// REMOVED: Recursive descent into arguments
	// We only track direct calls from fmt.Sprintf arguments
	// Nested calls within those arguments will be tracked when we analyze
	// the called function's body (depth = 1 tracking)
}

// extractSequentialReferences extracts t.Run() and RunTestsInSequence() calls from test functions
func extractSequentialReferences(file *ast.File, fset *token.FileSet, filePath string, functions []FunctionInfo) []SequentialReference {
	var seqRefs []SequentialReference

	// Build a map of test function names for lookup
	testFuncMap := make(map[string]FunctionInfo)
	for _, fn := range functions {
		if fn.IsTestFunc {
			testFuncMap[fn.FunctionName] = fn
		}
	}

	// Walk the AST looking for function declarations (test functions)
	ast.Inspect(file, func(n ast.Node) bool {
		// Only process function declarations
		funcDecl, ok := n.(*ast.FuncDecl)
		if !ok || funcDecl.Body == nil {
			return true
		}

		// Get the current function info
		var currentFunc *FunctionInfo
		for i := range functions {
			if functions[i].FunctionName == funcDecl.Name.Name {
				currentFunc = &functions[i]
				break
			}
		}

		if currentFunc == nil || !currentFunc.IsTestFunc {
			return true // Skip non-test functions
		}

		// Look for t.Run() calls and acceptance.RunTestsInSequence() calls
		ast.Inspect(funcDecl.Body, func(n2 ast.Node) bool {
			callExpr, ok := n2.(*ast.CallExpr)
			if !ok {
				return true
			}

			// Check for data.ResourceSequentialTest(t, r, []acceptance.TestStep{...}) pattern
			// Pattern: data.ResourceSequentialTest(t, resource, steps)
			// This indicates the test function calls other test steps sequentially
			if sel, ok := callExpr.Fun.(*ast.SelectorExpr); ok {
				if _, ok := sel.X.(*ast.Ident); ok && sel.Sel.Name == "ResourceSequentialTest" {
					// Extract the current test function as a sequential entry point
					// The test steps within are the sequential references
					// For now, we'll just mark this test as having sequential behavior
					// The actual test steps are handled separately in the TestStepInfo extraction

					// Note: We don't create individual SequentialReference records here
					// because ResourceSequentialTest uses TestStep arrays, not named function references
					// The sequential nature is implicit in the test execution order
				}

				// Check for t.Run(name, func) pattern
				if ident, ok := sel.X.(*ast.Ident); ok && ident.Name == "t" && sel.Sel.Name == "Run" {
					// Extract t.Run(name, func) where name is a string literal
					if len(callExpr.Args) >= 2 {
						// Get the test name (first argument)
						var testName string
						if basicLit, ok := callExpr.Args[0].(*ast.BasicLit); ok && basicLit.Kind == token.STRING {
							testName = strings.Trim(basicLit.Value, `"`)
						}

						// Get the function being called (second argument)
						// This can be a function literal or a function identifier
						var referencedFunc string
						switch arg := callExpr.Args[1].(type) {
						case *ast.Ident:
							referencedFunc = arg.Name
						case *ast.FuncLit:
							// For function literals in t.Run, we don't track them
							// as separate sequential references
							return true
						}

						if testName != "" && referencedFunc != "" {
							seqRefs = append(seqRefs, SequentialReference{
								EntryPointFunction: currentFunc.FunctionName,
								EntryPointFile:     filePath,
								EntryPointLine:     fset.Position(callExpr.Pos()).Line,
								ReferencedFunction: referencedFunc,
								SequentialGroup:    testName,
								SequentialKey:      "",
							})
						}
					}
				}

				// Check for acceptance.RunTestsInSequence(t, map[string]map[string]func) pattern
				if pkgIdent, ok := sel.X.(*ast.Ident); ok && pkgIdent.Name == "acceptance" && sel.Sel.Name == "RunTestsInSequence" {
					// The second argument should be a composite literal (the map)
					if len(callExpr.Args) >= 2 {
						if compLit, ok := callExpr.Args[1].(*ast.CompositeLit); ok {
							// Parse the map structure: map[string]map[string]func
							for _, elt := range compLit.Elts {
								kvExpr, ok := elt.(*ast.KeyValueExpr)
								if !ok {
									continue
								}

								// Get the outer key (group name)
								var groupName string
								if keyLit, ok := kvExpr.Key.(*ast.BasicLit); ok && keyLit.Kind == token.STRING {
									groupName = strings.Trim(keyLit.Value, `"`)
								}

								// The value should be another map: map[string]func
								if innerMap, ok := kvExpr.Value.(*ast.CompositeLit); ok {
									for _, innerElt := range innerMap.Elts {
										innerKV, ok := innerElt.(*ast.KeyValueExpr)
										if !ok {
											continue
										}

										// Get the inner key (test key)
										var testKey string
										if innerKeyLit, ok := innerKV.Key.(*ast.BasicLit); ok && innerKeyLit.Kind == token.STRING {
											testKey = strings.Trim(innerKeyLit.Value, `"`)
										}

										// Get the function name (value)
										var funcName string
										if innerValueIdent, ok := innerKV.Value.(*ast.Ident); ok {
											funcName = innerValueIdent.Name
										}

										if groupName != "" && testKey != "" && funcName != "" {
											seqRefs = append(seqRefs, SequentialReference{
												EntryPointFunction: currentFunc.FunctionName,
												EntryPointFile:     filePath,
												EntryPointLine:     fset.Position(callExpr.Pos()).Line,
												ReferencedFunction: funcName,
												SequentialGroup:    groupName,
												SequentialKey:      testKey,
											})
										}
									}
								}
							}
						}
					}
				}
			}

			return true
		})

		// ADDITIONAL PATTERN: Map-based sequential tests
		// Pattern: testCases := map[string]map[string]func(t *testing.T){ ... }
		//          for group, m := range testCases { t.Run(group, ...) }
		// This extracts the map structure directly from the variable assignment
		// Variable name can be anything, but commonly "testCases"
		ast.Inspect(funcDecl.Body, func(n2 ast.Node) bool {
			// Look for assignment statements
			assignStmt, ok := n2.(*ast.AssignStmt)
			if !ok {
				return true
			}

			// Check if this is a := ... assignment (short variable declaration)
			if len(assignStmt.Lhs) != 1 || len(assignStmt.Rhs) != 1 {
				return true
			}

			// The RHS should be a composite literal (the map)
			compLit, ok := assignStmt.Rhs[0].(*ast.CompositeLit)
			if !ok {
				return true
			}

			// Check if the composite literal type is map[string]map[string]...
			// This validates we're looking at the right kind of map structure
			mapType, ok := compLit.Type.(*ast.MapType)
			if !ok {
				return true
			}

			// Outer map key should be string
			if keyIdent, ok := mapType.Key.(*ast.Ident); !ok || keyIdent.Name != "string" {
				return true
			}

			// Outer map value should be another map
			innerMapType, ok := mapType.Value.(*ast.MapType)
			if !ok {
				return true
			}

			// Inner map key should be string
			if innerKeyIdent, ok := innerMapType.Key.(*ast.Ident); !ok || innerKeyIdent.Name != "string" {
				return true
			}

			// If we got here, we have a map[string]map[string]... structure
			// Parse the map structure
			for _, elt := range compLit.Elts {
				kvExpr, ok := elt.(*ast.KeyValueExpr)
				if !ok {
					continue
				}

				// Get the outer key (group name)
				var groupName string
				if keyLit, ok := kvExpr.Key.(*ast.BasicLit); ok && keyLit.Kind == token.STRING {
					groupName = strings.Trim(keyLit.Value, `"`)
				}

				// The value should be another map: map[string]func
				if innerMap, ok := kvExpr.Value.(*ast.CompositeLit); ok {
					for _, innerElt := range innerMap.Elts {
						innerKV, ok := innerElt.(*ast.KeyValueExpr)
						if !ok {
							continue
						}

						// Get the inner key (test key)
						var testKey string
						if innerKeyLit, ok := innerKV.Key.(*ast.BasicLit); ok && innerKeyLit.Kind == token.STRING {
							testKey = strings.Trim(innerKeyLit.Value, `"`)
						}

						// Get the function name (value)
						var funcName string
						if innerValueIdent, ok := innerKV.Value.(*ast.Ident); ok {
							funcName = innerValueIdent.Name
						}

						if groupName != "" && testKey != "" && funcName != "" {
							seqRefs = append(seqRefs, SequentialReference{
								EntryPointFunction: currentFunc.FunctionName,
								EntryPointFile:     filePath,
								EntryPointLine:     fset.Position(assignStmt.Pos()).Line,
								ReferencedFunction: funcName,
								SequentialGroup:    groupName,
								SequentialKey:      testKey,
							})
						}
					}
				}
			}

			return true
		})

		return true
	})

	return seqRefs
}

// extractDirectResourceReferences extracts direct Azure resource references from template function bodies
// Parses HCL strings returned by template functions to find:
// 1. resource "azurerm_xxx" "test" { ... } → RESOURCE_BLOCK
// 2. azurerm_xxx.test.attribute → ATTRIBUTE_REFERENCE
// Only extracts references matching targetResource (e.g., only azurerm_resource_group refs)
func extractDirectResourceReferences(file *ast.File, fset *token.FileSet, filePath string, functions []FunctionInfo, targetResource string) []DirectResourceReference {
	var directRefs []DirectResourceReference

	// Build a map of template functions (non-test functions that return strings)
	templateFuncs := make(map[string]*FunctionInfo)
	for i := range functions {
		if !functions[i].IsTestFunc {
			templateFuncs[functions[i].FunctionName] = &functions[i]
		}
	}

	// Walk the AST to find template function bodies
	ast.Inspect(file, func(n ast.Node) bool {
		funcDecl, ok := n.(*ast.FuncDecl)
		if !ok || funcDecl.Body == nil {
			return true
		}

		// Find the corresponding FunctionInfo
		var currentFunc *FunctionInfo
		for i := range functions {
			if functions[i].FunctionName == funcDecl.Name.Name && !functions[i].IsTestFunc {
				currentFunc = &functions[i]
				break
			}
		}

		if currentFunc == nil {
			return true // Not a template function
		}

		// Extract string literals from return statements and fmt.Sprintf calls
		hclContent := extractHCLContentFromFunction(funcDecl, fset)
		if hclContent == "" {
			return true
		}

		// Parse the HCL content for resource references (filtered by targetResource)
		refs := parseHCLForResourceReferences(hclContent, currentFunc.FunctionName, filePath, currentFunc.Line, targetResource)
		directRefs = append(directRefs, refs...)

		return true
	})

	return directRefs
}

// extractHCLContentFromFunction extracts HCL string content from a template function
// Looks for return statements with string literals or fmt.Sprintf calls
func extractHCLContentFromFunction(funcDecl *ast.FuncDecl, fset *token.FileSet) string {
	var hclContent strings.Builder

	// Walk the function body to find return statements
	ast.Inspect(funcDecl.Body, func(n ast.Node) bool {
		// Look for return statements
		returnStmt, ok := n.(*ast.ReturnStmt)
		if !ok || len(returnStmt.Results) == 0 {
			return true
		}

		// Check if it's a fmt.Sprintf call
		if callExpr, ok := returnStmt.Results[0].(*ast.CallExpr); ok {
			if isFmtSprintfCall(callExpr) {
				// Extract string literals from fmt.Sprintf arguments
				for _, arg := range callExpr.Args {
					if lit, ok := arg.(*ast.BasicLit); ok && lit.Kind == token.STRING {
						// Remove quotes and unescape the string
						content := strings.Trim(lit.Value, "`\"")
						content = strings.ReplaceAll(content, "\\n", "\n")
						content = strings.ReplaceAll(content, "\\t", "\t")
						hclContent.WriteString(content)
						hclContent.WriteString("\n")
					}
				}
			}
		}

		// Also check for direct string literals
		if lit, ok := returnStmt.Results[0].(*ast.BasicLit); ok && lit.Kind == token.STRING {
			content := strings.Trim(lit.Value, "`\"")
			content = strings.ReplaceAll(content, "\\n", "\n")
			content = strings.ReplaceAll(content, "\\t", "\t")
			hclContent.WriteString(content)
		}

		return true
	})

	return hclContent.String()
}

// parseHCLForResourceReferences parses HCL content to find Azure resource references
// Only extracts references matching targetResource (e.g., only azurerm_resource_group)
func parseHCLForResourceReferences(hclContent, templateFunc, templateFile string, templateLine int, targetResource string) []DirectResourceReference {
	var refs []DirectResourceReference

	// Split into lines for line-by-line analysis
	lines := strings.Split(hclContent, "\n")

	for lineNum, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Pattern 1: resource "azurerm_xxx" "name" {
		// Pattern 2: data "azurerm_xxx" "name" {
		if strings.HasPrefix(trimmed, "resource \"azurerm_") || strings.HasPrefix(trimmed, "data \"azurerm_") {
			// Extract resource name
			parts := strings.Fields(trimmed)
			if len(parts) >= 2 {
				resourceName := strings.Trim(parts[1], "\"")
				// Only add if it matches targetResource (or if no filter specified)
				if strings.HasPrefix(resourceName, "azurerm_") && (targetResource == "" || resourceName == targetResource) {
					refs = append(refs, DirectResourceReference{
						TemplateFunction: templateFunc,
						TemplateFile:     templateFile,
						TemplateLine:     templateLine,
						ResourceName:     resourceName,
						ReferenceType:    "RESOURCE_BLOCK",
						Context:          trimmed,
						ContextLine:      lineNum + 1,
					})
				}
			}
		}

		// Pattern 3: azurerm_xxx.name.attribute (attribute reference)
		// Look for patterns like: resource_group_name = azurerm_resource_group.test.name
		if strings.Contains(trimmed, "azurerm_") {
			// Use regex to find azurerm_xxx.name patterns
			// Pattern: azurerm_[a-z0-9_]+\.[a-z0-9_]+
			words := strings.FieldsFunc(trimmed, func(r rune) bool {
				return r == ' ' || r == '=' || r == '(' || r == ')' || r == ',' || r == '[' || r == ']' || r == '{' || r == '}'
			})

			for _, word := range words {
				if strings.HasPrefix(word, "azurerm_") && strings.Count(word, ".") >= 1 {
					// Extract the resource type (azurerm_xxx)
					parts := strings.Split(word, ".")
					if len(parts) >= 2 {
						resourceName := parts[0]
						// Only add if it matches targetResource (or if no filter specified)
						if targetResource == "" || resourceName == targetResource {
							// Only add if we haven't already added a RESOURCE_BLOCK for this resource on this line
							isDuplicate := false
							for _, existing := range refs {
								if existing.ContextLine == lineNum+1 && existing.ResourceName == resourceName && existing.ReferenceType == "RESOURCE_BLOCK" {
									isDuplicate = true
									break
								}
							}

							if !isDuplicate {
								refs = append(refs, DirectResourceReference{
									TemplateFunction: templateFunc,
									TemplateFile:     templateFile,
									TemplateLine:     templateLine,
									ResourceName:     resourceName,
									ReferenceType:    "ATTRIBUTE_REFERENCE",
									Context:          trimmed,
									ContextLine:      lineNum + 1,
								})
							}
						}
					}
				}
			}
		}
	}

	return refs
}

// isFmtSprintfCall checks if a call expression is fmt.Sprintf
func isFmtSprintfCall(callExpr *ast.CallExpr) bool {
	selector, ok := callExpr.Fun.(*ast.SelectorExpr)
	if !ok {
		return false
	}

	pkgIdent, ok := selector.X.(*ast.Ident)
	if !ok {
		return false
	}

	return pkgIdent.Name == "fmt" && selector.Sel.Name == "Sprintf"
}

// analyzeTemplateCallExpr analyzes an expression to see if it's a template function call
// Returns TemplateFunctionCall if it matches patterns like: r.template(data), StructName{}.method(data)
func analyzeTemplateCallExpr(expr ast.Expr, fset *token.FileSet, source string) *TemplateFunctionCall {
	callExpr, ok := expr.(*ast.CallExpr)
	if !ok {
		return nil
	}

	templateCall := &TemplateFunctionCall{}

	// Extract the full expression text
	startPos := fset.Position(callExpr.Pos())
	endPos := fset.Position(callExpr.End())
	templateCall.TargetExpr = extractTextRange(source, startPos, endPos)

	// Parse the function being called
	switch fun := callExpr.Fun.(type) {
	case *ast.SelectorExpr:
		// Pattern: r.template(data) or StructName{}.method(data)
		templateCall.TargetMethod = fun.Sel.Name

		switch x := fun.X.(type) {
		case *ast.Ident:
			// Pattern: r.template(data) - variable.method
			templateCall.TargetVariable = x.Name
			templateCall.IsLocalCall = true

		case *ast.CompositeLit:
			// Pattern: StructName{}.method(data) - direct struct instantiation
			if ident, ok := x.Type.(*ast.Ident); ok {
				templateCall.TargetStruct = ident.Name
				templateCall.IsLocalCall = true
			}
		}

		return templateCall

	default:
		// Not a method call pattern we're looking for
		return nil
	}
}

// extractConfigInfo parses the Config field from a TestStep composite literal
// and extracts variable, method, and struct information
func extractConfigInfo(stepInfo *TestStepInfo, stepLit *ast.CompositeLit, fset *token.FileSet, source string, currentFunc *FunctionInfo, varAssignments map[string]*VarAssignment, functions []FunctionInfo) {
	// Iterate through the fields of the composite literal
	for _, elt := range stepLit.Elts {
		kvExpr, ok := elt.(*ast.KeyValueExpr)
		if !ok {
			continue
		}

		// Check if this is the Config field
		key, ok := kvExpr.Key.(*ast.Ident)
		if !ok || key.Name != "Config" {
			continue
		}

		// Extract the full expression text
		startPos := fset.Position(kvExpr.Value.Pos())
		endPos := fset.Position(kvExpr.Value.End())
		stepInfo.ConfigExpr = extractTextRange(source, startPos, endPos)

		// Parse the expression to extract variable and method
		parseConfigExpression(stepInfo, kvExpr.Value, currentFunc, varAssignments)

		// Determine ConfigService by looking up the method in functions
		if stepInfo.ConfigMethod != "" {
			for _, fn := range functions {
				if fn.FunctionName == stepInfo.ConfigMethod {
					stepInfo.ConfigService = fn.ServiceName
					break
				}
			}
		}

		break
	}
}

// parseConfigExpression analyzes the Config field expression
// Handles patterns like: r.basic(data), StructName{}.method(data), func(...) { return r.method(...) }, config (variable)
func parseConfigExpression(stepInfo *TestStepInfo, expr ast.Expr, currentFunc *FunctionInfo, varAssignments map[string]*VarAssignment) {
	switch e := expr.(type) {
	case *ast.CallExpr:
		// This is a function call - extract the function being called
		switch fun := e.Fun.(type) {
		case *ast.SelectorExpr:
			// Pattern: r.basic(data) or StructName{}.method(data)
			stepInfo.ConfigMethod = fun.Sel.Name

			// Check what's on the left of the dot
			switch x := fun.X.(type) {
			case *ast.Ident:
				// Pattern: r.basic(data) - variable.method
				stepInfo.ConfigVariable = x.Name
				stepInfo.IsLocalCall = true // We'll verify this later

			case *ast.CompositeLit:
				// Pattern: StructName{}.method(data) - direct struct instantiation
				if ident, ok := x.Type.(*ast.Ident); ok {
					stepInfo.ConfigStruct = ident.Name
					stepInfo.IsLocalCall = true
				}
			}

		case *ast.Ident:
			// Pattern: someFunction(data) - direct function call (rare)
			stepInfo.ConfigMethod = fun.Name
		}

	case *ast.Ident:
		// Pattern: Config: config - a variable reference
		// Store the variable name - we'll need to trace it back to its assignment
		stepInfo.ConfigVariable = e.Name
		// Mark as local call by default - variable assignments are typically in same function
		stepInfo.IsLocalCall = true

	case *ast.FuncLit:
		// Pattern: func(...) { return r.method(...) } - legacy anonymous function
		// Parse the function body to find the return statement
		if e.Body != nil && len(e.Body.List) > 0 {
			for _, stmt := range e.Body.List {
				if retStmt, ok := stmt.(*ast.ReturnStmt); ok && len(retStmt.Results) > 0 {
					// Recursively parse the return expression
					parseConfigExpression(stepInfo, retStmt.Results[0], currentFunc, varAssignments)
					break
				}
			}
		}
	}

	// Resolve the struct type using multiple strategies:
	// 1. Check if variable is the function's receiver
	// 2. Check if variable is a local variable with known struct type
	if stepInfo.ConfigVariable != "" {
		// Strategy 1: Function receiver (e.g., func (r Resource) TestFunc() { ... Config: r.basic() })
		if currentFunc != nil && currentFunc.ReceiverVar != "" && stepInfo.ConfigVariable == currentFunc.ReceiverVar {
			stepInfo.ConfigStruct = currentFunc.ReceiverType
		}
		// Strategy 2: Local variable with struct instantiation (e.g., r := Resource{})
		if stepInfo.ConfigStruct == "" {
			if assignment, exists := varAssignments[stepInfo.ConfigVariable]; exists {
				stepInfo.ConfigStruct = assignment.ReceiverStruct
			}
		}
	}

	// Resolve variable assignments for simple variable references (e.g., Config: config)
	// This handles: config := r.multipleInstances(...) followed by Config: config
	if stepInfo.ConfigVariable != "" && stepInfo.ConfigMethod == "" {
		if assignment, exists := varAssignments[stepInfo.ConfigVariable]; exists {
			// Found the variable assignment! Extract the method and struct info
			stepInfo.ConfigMethod = assignment.MethodName
			stepInfo.ConfigStruct = assignment.ReceiverStruct
			// Update ConfigVariable to point to the receiver (e.g., "r")
			// Keep the original in ConfigExpr which already has the variable name
			stepInfo.ConfigVariable = assignment.ReceiverVar
			stepInfo.IsLocalCall = true
		}
	}
}

// extractTextRange extracts text from source between two positions
func extractTextRange(source string, start, end token.Position) string {
	lines := strings.Split(source, "\n")

	if start.Line < 1 || start.Line > len(lines) {
		return ""
	}

	// Single line case
	if start.Line == end.Line {
		line := lines[start.Line-1]
		if start.Column <= len(line) && end.Column <= len(line)+1 {
			return line[start.Column-1 : end.Column-1]
		}
		return line
	}

	// Multi-line case
	var result strings.Builder

	// First line
	if start.Line <= len(lines) {
		firstLine := lines[start.Line-1]
		if start.Column <= len(firstLine)+1 {
			result.WriteString(firstLine[start.Column-1:])
		}
		result.WriteString("\n")
	}

	// Middle lines
	for i := start.Line; i < end.Line-1 && i < len(lines); i++ {
		result.WriteString(lines[i])
		result.WriteString("\n")
	}

	// Last line
	if end.Line <= len(lines) {
		lastLine := lines[end.Line-1]
		if end.Column <= len(lastLine)+1 {
			result.WriteString(lastLine[:end.Column-1])
		}
	}

	return result.String()
}

// ImportInfo represents an import statement
type ImportInfo struct {
	PackagePath string
	PackageName string
	Alias       string
}

// exprToString converts an expression to a string (best effort)
func exprToString(expr ast.Expr) string {
	switch e := expr.(type) {
	case *ast.Ident:
		return e.Name
	case *ast.SelectorExpr:
		return exprToString(e.X) + "." + e.Sel.Name
	case *ast.CallExpr:
		// Function call as argument
		funcName := exprToString(e.Fun)
		if len(e.Args) > 0 {
			return funcName + "(...)"
		}
		return funcName + "()"
	case *ast.BasicLit:
		// Literal value (string, number, etc.)
		return e.Value
	case *ast.CompositeLit:
		// Composite literal like []string{...}
		return "composite{...}"
	case *ast.UnaryExpr:
		// Unary expression like &value
		return e.Op.String() + exprToString(e.X)
	case *ast.BinaryExpr:
		// Binary expression like a + b
		return exprToString(e.X) + " " + e.Op.String() + " " + exprToString(e.Y)
	default:
		return "?"
	}
}
