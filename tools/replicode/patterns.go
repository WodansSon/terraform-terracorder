package main

import (
	"go/ast"
	"strings"
	"unicode"
)

// PatternDetector holds all pattern detection results
type PatternDetector struct {
	SequentialTests    []SequentialTestInfo
	MapBasedTests      []MapBasedTestInfo
	AnonymousFunctions []AnonymousFunctionInfo
	VisibilityInfo     []FunctionVisibilityInfo
}

// SequentialTestInfo captures sequential test patterns
type SequentialTestInfo struct {
	FunctionName string // The main test function (e.g., TestAccResourceSequential)
	Line         int
	FilePath     string
	Pattern      string // "RunTestsInSequence" or "MapBased"
	IsEntryPoint bool   // True if this is the entry point function
}

// MapBasedTestInfo captures map-based sequential test storage
type MapBasedTestInfo struct {
	MapVariableName  string // Name of the map variable
	MapType          string // Full map type (map[string]map[string]func...)
	Line             int
	FilePath         string
	FunctionRefs     []string                    // Functions stored in the map (for quick reference)
	Mappings         []SequentialFunctionMapping // Detailed group/key/function mappings
	IsInlineArgument bool                        // True if this map is an inline argument to RunTestsInSequence
}

// SequentialFunctionMapping captures the group -> key -> function structure
type SequentialFunctionMapping struct {
	SequentialGroup string // e.g., "raiBlocklist", "ipv4", "ipv6"
	SequentialKey   string // e.g., "basic", "requiresImport", "update"
	FunctionName    string // e.g., "TestAccCognitiveRaiBlocklist_basic"
	Line            int    // Line number where this mapping appears
}

// AnonymousFunctionInfo captures anonymous function declarations
type AnonymousFunctionInfo struct {
	ParentFunction string // Function that contains the anonymous function
	Line           int
	FilePath       string
	FunctionType   string // Type signature of the anonymous function
	Context        string // Where it appears (assignment, argument, etc.)
}

// FunctionVisibilityInfo captures Go visibility classification
type FunctionVisibilityInfo struct {
	FunctionName    string
	ReceiverType    string
	Line            int
	FilePath        string
	IsPublic        bool   // Uppercase first letter (IsPrivate is just !IsPublic)
	VisibilityType  string // "PUBLIC_REFERENCE" or "PRIVATE_REFERENCE"
	ReferenceTypeId int    // Maps to database: 11=PRIVATE, 12=PUBLIC
}

// DetectPatterns analyzes AST for all pattern types
func DetectPatterns(file *ast.File, filePath string) *PatternDetector {
	detector := &PatternDetector{
		SequentialTests:    []SequentialTestInfo{},
		MapBasedTests:      []MapBasedTestInfo{},
		AnonymousFunctions: []AnonymousFunctionInfo{},
		VisibilityInfo:     []FunctionVisibilityInfo{},
	}

	// Track current function context for proper linking
	var currentFunction string

	// Walk the AST to find all patterns
	ast.Inspect(file, func(n ast.Node) bool {
		switch node := n.(type) {
		case *ast.FuncDecl:
			// Update context
			currentFunction = node.Name.Name
			// Detect visibility for all functions
			detector.analyzeFunctionDecl(node, filePath)

		case *ast.CallExpr:
			// Detect RunTestsInSequence calls within function context
			detector.analyzeCallExpr(node, filePath, currentFunction)

		case *ast.ValueSpec:
			// Detect map-based test declarations (var statements)
			detector.analyzeValueSpec(node, filePath, currentFunction)

		case *ast.AssignStmt:
			// Detect map-based test declarations (:= statements)
			detector.analyzeAssignStmt(node, filePath, currentFunction)

		case *ast.FuncLit:
			// Detect anonymous functions
			detector.analyzeFuncLit(node, filePath, currentFunction)
		}
		return true
	})

	return detector
}

// analyzeFunctionDecl checks function declarations for patterns
func (d *PatternDetector) analyzeFunctionDecl(node *ast.FuncDecl, filePath string) {
	functionName := node.Name.Name
	line := node.Pos()

	// Check visibility based on first character (Go naming convention)
	firstChar := rune(functionName[0])
	isPublic := unicode.IsUpper(firstChar)

	visibilityType := "PRIVATE_REFERENCE"
	referenceTypeId := 11 // PRIVATE_REFERENCE
	if isPublic {
		visibilityType = "PUBLIC_REFERENCE"
		referenceTypeId = 12 // PUBLIC_REFERENCE
	}

	receiverType := ""
	if node.Recv != nil && len(node.Recv.List) > 0 {
		if starExpr, ok := node.Recv.List[0].Type.(*ast.StarExpr); ok {
			if ident, ok := starExpr.X.(*ast.Ident); ok {
				receiverType = ident.Name
			}
		} else if ident, ok := node.Recv.List[0].Type.(*ast.Ident); ok {
			receiverType = ident.Name
		}
	}

	d.VisibilityInfo = append(d.VisibilityInfo, FunctionVisibilityInfo{
		FunctionName:    functionName,
		ReceiverType:    receiverType,
		Line:            int(line),
		FilePath:        filePath,
		IsPublic:        isPublic,
		VisibilityType:  visibilityType,
		ReferenceTypeId: referenceTypeId,
	})

	// NOTE: Sequential test detection is NOT based on naming conventions!
	// Sequential tests are detected by:
	// 1. Functions that CONTAIN RunTestsInSequence calls (detected in analyzeCallExpr)
	// 2. Functions that are REFERENCED in map-based sequential patterns (detected in analyzeValueSpec)
	// 3. Lowercase functions that are REFERENCED by sequential entry points (detected via cross-reference)
	// We don't assume "testAcc" prefix or "Sequential" suffix - developer can name them anything!
}

// analyzeCallExpr detects RunTestsInSequence calls
func (d *PatternDetector) analyzeCallExpr(node *ast.CallExpr, filePath string, currentFunction string) {
	// Check for acceptance.RunTestsInSequence pattern
	if sel, ok := node.Fun.(*ast.SelectorExpr); ok {
		if pkg, ok := sel.X.(*ast.Ident); ok {
			if pkg.Name == "acceptance" && sel.Sel.Name == "RunTestsInSequence" {
				// Found RunTestsInSequence call - this function is a sequential entry point
				// regardless of its name (developer can name it anything)
				d.SequentialTests = append(d.SequentialTests, SequentialTestInfo{
					FunctionName: currentFunction, // Use actual function context
					Line:         int(node.Pos()),
					FilePath:     filePath,
					Pattern:      "RunTestsInSequence",
					IsEntryPoint: true,
				})

				// Check if the second argument is a map-based sequential pattern
				// RunTestsInSequence(t, map[string]map[string]func(...){...})
				if len(node.Args) >= 2 {
					if compLit, ok := node.Args[1].(*ast.CompositeLit); ok {
						if mapType, ok := compLit.Type.(*ast.MapType); ok {
							if innerMap, ok := mapType.Value.(*ast.MapType); ok {
								if _, ok := innerMap.Value.(*ast.FuncType); ok {
									// This is a map-based sequential pattern as argument!
									functionRefs := d.extractFunctionRefs(compLit)
									mappings := d.extractSequentialMappings(compLit)

									d.MapBasedTests = append(d.MapBasedTests, MapBasedTestInfo{
										MapVariableName:  "inline_map_arg", // Not a variable, inline argument
										MapType:          "map[string]map[string]func(t *testing.T)",
										Line:             int(node.Pos()),
										FilePath:         filePath,
										FunctionRefs:     functionRefs,
										Mappings:         mappings, // Now includes group/key/function details!
										IsInlineArgument: true,     // Mark as inline argument to RunTestsInSequence
									})
								}
							}
						}
					}
				}
			}
		}
	}
}

// analyzeValueSpec detects map-based sequential test declarations
func (d *PatternDetector) analyzeValueSpec(node *ast.ValueSpec, filePath string, currentFunction string) {
	// Check for map[string]map[string]func(t *testing.T) patterns
	for i, name := range node.Names {
		if i < len(node.Values) {
			if compLit, ok := node.Values[i].(*ast.CompositeLit); ok {
				if mapType, ok := compLit.Type.(*ast.MapType); ok {
					// Check if this is a nested map
					if innerMap, ok := mapType.Value.(*ast.MapType); ok {
						// Check if inner map value is a function type
						if funcType, ok := innerMap.Value.(*ast.FuncType); ok {
							// This is a map[string]map[string]func(...) pattern
							mapTypeStr := d.formatMapType()
							functionRefs := d.extractFunctionRefs(compLit)
							mappings := d.extractSequentialMappings(compLit)

							d.MapBasedTests = append(d.MapBasedTests, MapBasedTestInfo{
								MapVariableName: name.Name,
								MapType:         mapTypeStr,
								Line:            int(node.Pos()),
								FilePath:        filePath,
								FunctionRefs:    functionRefs,
								Mappings:        mappings, // Now includes group/key/function details!
								// IsInlineArgument defaults to false (zero value)
							})

							// Mark the containing function as sequential entry point
							// Developer can name it anything - we detect by behavior
							d.SequentialTests = append(d.SequentialTests, SequentialTestInfo{
								FunctionName: currentFunction, // Use actual function context
								Line:         int(node.Pos()),
								FilePath:     filePath,
								Pattern:      "MapBased",
								IsEntryPoint: true,
							})

							_ = funcType // Used for type checking
						}
					}
				}
			}
		}
	}
}

// analyzeAssignStmt detects map-based sequential test declarations using := syntax
func (d *PatternDetector) analyzeAssignStmt(node *ast.AssignStmt, filePath string, currentFunction string) {
	// Check for short variable declarations (:=) with map[string]map[string]func patterns
	for i, lhs := range node.Lhs {
		if i < len(node.Rhs) {
			// Get the variable name
			var varName string
			if ident, ok := lhs.(*ast.Ident); ok {
				varName = ident.Name
			} else {
				continue
			}

			// Check if the right-hand side is a composite literal (map initialization)
			if compLit, ok := node.Rhs[i].(*ast.CompositeLit); ok {
				if mapType, ok := compLit.Type.(*ast.MapType); ok {
					// Check if this is a nested map
					if innerMap, ok := mapType.Value.(*ast.MapType); ok {
						// Check if inner map value is a function type
						if funcType, ok := innerMap.Value.(*ast.FuncType); ok {
							// This is a map[string]map[string]func(...) pattern
							mapTypeStr := d.formatMapType()
							functionRefs := d.extractFunctionRefs(compLit)
							mappings := d.extractSequentialMappings(compLit)

							d.MapBasedTests = append(d.MapBasedTests, MapBasedTestInfo{
								MapVariableName: varName,
								MapType:         mapTypeStr,
								Line:            int(node.Pos()),
								FilePath:        filePath,
								FunctionRefs:    functionRefs,
								Mappings:        mappings,
							})

							// Mark the containing function as sequential entry point
							d.SequentialTests = append(d.SequentialTests, SequentialTestInfo{
								FunctionName: currentFunction,
								Line:         int(node.Pos()),
								FilePath:     filePath,
								Pattern:      "MapBased",
								IsEntryPoint: true,
							})

							_ = funcType // Used for type checking
						}
					}
				}
			}
		}
	}
}

// analyzeFuncLit detects anonymous function declarations
func (d *PatternDetector) analyzeFuncLit(node *ast.FuncLit, filePath string, currentFunction string) {
	// Anonymous function detected
	funcType := d.formatFuncType()

	d.AnonymousFunctions = append(d.AnonymousFunctions, AnonymousFunctionInfo{
		ParentFunction: currentFunction, // Now we have proper context
		Line:           int(node.Pos()),
		FilePath:       filePath,
		FunctionType:   funcType,
		Context:        "anonymous_function",
	})
}

// Helper functions
func (d *PatternDetector) formatMapType() string {
	// Build string representation of map type
	return "map[string]map[string]func(t *testing.T)"
}

func (d *PatternDetector) formatFuncType() string {
	// Build string representation of function type
	return "func(...)"
}

func (d *PatternDetector) extractFunctionRefs(compLit *ast.CompositeLit) []string {
	refs := []string{}

	// Walk the composite literal to find function references
	for _, elt := range compLit.Elts {
		if kv, ok := elt.(*ast.KeyValueExpr); ok {
			// This is a map entry
			if innerMap, ok := kv.Value.(*ast.CompositeLit); ok {
				// Nested map - extract function names
				for _, innerElt := range innerMap.Elts {
					if innerKv, ok := innerElt.(*ast.KeyValueExpr); ok {
						if ident, ok := innerKv.Value.(*ast.Ident); ok {
							refs = append(refs, ident.Name)
						}
					}
				}
			}
		}
	}

	return refs
}

// extractSequentialMappings extracts group -> key -> function mappings with line numbers
func (d *PatternDetector) extractSequentialMappings(compLit *ast.CompositeLit) []SequentialFunctionMapping {
	mappings := []SequentialFunctionMapping{}

	// Walk the composite literal: map[string]map[string]func{...}
	for _, elt := range compLit.Elts {
		if kv, ok := elt.(*ast.KeyValueExpr); ok {
			// Get the group name (outer map key)
			var groupName string
			if basicLit, ok := kv.Key.(*ast.BasicLit); ok {
				// Remove quotes from string literal
				groupName = strings.Trim(basicLit.Value, `"`)
			}

			// Navigate to inner map: { "key": functionName, ... }
			if innerMap, ok := kv.Value.(*ast.CompositeLit); ok {
				for _, innerElt := range innerMap.Elts {
					if innerKv, ok := innerElt.(*ast.KeyValueExpr); ok {
						// Get the key name (inner map key)
						var keyName string
						if basicLit, ok := innerKv.Key.(*ast.BasicLit); ok {
							keyName = strings.Trim(basicLit.Value, `"`)
						}

						// Get the function name (inner map value)
						var functionName string
						if ident, ok := innerKv.Value.(*ast.Ident); ok {
							functionName = ident.Name
						}

						if groupName != "" && keyName != "" && functionName != "" {
							mappings = append(mappings, SequentialFunctionMapping{
								SequentialGroup: groupName,
								SequentialKey:   keyName,
								FunctionName:    functionName,
								Line:            int(innerKv.Pos()),
							})
						}
					}
				}
			}
		}
	}

	return mappings
}
