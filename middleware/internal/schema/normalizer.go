package schema

import "log"

// unsupportedKeys are JSON Schema keys not supported by Gemini
var unsupportedKeys = []string{
	"propertyNames",
	"$ref",
	"$defs",
	"definitions",
	"patternProperties",
	"unevaluatedProperties",
	"unevaluatedItems",
	"dependentSchemas",
	"dependentRequired",
	"if",
	"then",
	"else",
	"not",
	"contentMediaType",
	"contentEncoding",
	"contentSchema",
	"minContains",
	"maxContains",
}

// Normalize recursively removes unsupported JSON Schema features for Gemini compatibility
func Normalize(schema map[string]interface{}, debug bool) map[string]interface{} {
	if schema == nil {
		return nil
	}

	// Remove unsupported keys at current level
	for _, key := range unsupportedKeys {
		if _, exists := schema[key]; exists {
			if debug {
				log.Printf("[schema] removing unsupported key: %s", key)
			}
			delete(schema, key)
		}
	}

	// Handle anyOf/oneOf/allOf - flatten to first non-null type or normalize each
	for _, unionKey := range []string{"anyOf", "oneOf"} {
		if unionVal, exists := schema[unionKey]; exists {
			if unionArr, ok := unionVal.([]interface{}); ok && len(unionArr) > 0 {
				// Find first non-null type and use it
				for _, item := range unionArr {
					if itemMap, ok := item.(map[string]interface{}); ok {
						// Normalize this schema first
						normalizedItem := Normalize(itemMap, debug)
						if itemType, hasType := normalizedItem["type"]; hasType {
							if typeStr, isStr := itemType.(string); isStr && typeStr != "null" {
								schema["type"] = typeStr
								for k, v := range normalizedItem {
									if k != "type" {
										schema[k] = v
									}
								}
								break
							}
						}
					}
				}
			}
			delete(schema, unionKey)
			if debug {
				log.Printf("[schema] flattened %s to single type", unionKey)
			}
		}
	}

	// Handle allOf - merge all schemas into one
	if allOfVal, exists := schema["allOf"]; exists {
		if allOfArr, ok := allOfVal.([]interface{}); ok {
			for _, item := range allOfArr {
				if itemMap, ok := item.(map[string]interface{}); ok {
					normalizedItem := Normalize(itemMap, debug)
					for k, v := range normalizedItem {
						if _, exists := schema[k]; !exists {
							schema[k] = v
						}
					}
				}
			}
		}
		delete(schema, "allOf")
		if debug {
			log.Printf("[schema] merged allOf schemas")
		}
	}

	// Handle type arrays like ["string", "null"] -> "string"
	if typeVal, exists := schema["type"]; exists {
		if typeArr, ok := typeVal.([]interface{}); ok {
			for _, t := range typeArr {
				if typeStr, isStr := t.(string); isStr && typeStr != "null" {
					schema["type"] = typeStr
					if debug {
						log.Printf("[schema] simplified type array to: %s", typeStr)
					}
					break
				}
			}
		}
	}

	// Recursively normalize all possible nested schema locations
	normalizeNested(schema, "properties", debug)
	normalizeNested(schema, "patternProperties", debug) // normalize before it might be deleted
	normalizeNestedSchema(schema, "items", debug)
	normalizeNestedSchema(schema, "additionalProperties", debug)
	normalizeNestedSchema(schema, "contains", debug)
	normalizeNestedSchema(schema, "propertyNames", debug) // normalize before deletion
	normalizeNestedArraySchemas(schema, "prefixItems", debug)
	normalizeNestedArraySchemas(schema, "allOf", debug)
	normalizeNestedArraySchemas(schema, "anyOf", debug)
	normalizeNestedArraySchemas(schema, "oneOf", debug)

	// Final cleanup - remove any unsupported keys that may have been added during normalization
	for _, key := range unsupportedKeys {
		delete(schema, key)
	}

	return schema
}

// normalizeNested handles map of schemas (like properties)
func normalizeNested(schema map[string]interface{}, key string, debug bool) {
	if val, exists := schema[key]; exists {
		if valMap, ok := val.(map[string]interface{}); ok {
			for propKey, propVal := range valMap {
				if propValMap, ok := propVal.(map[string]interface{}); ok {
					valMap[propKey] = Normalize(propValMap, debug)
				}
			}
		}
	}
}

// normalizeNestedSchema handles a single nested schema
func normalizeNestedSchema(schema map[string]interface{}, key string, debug bool) {
	if val, exists := schema[key]; exists {
		if valMap, ok := val.(map[string]interface{}); ok {
			schema[key] = Normalize(valMap, debug)
		}
	}
}

// normalizeNestedArraySchemas handles array of schemas (like prefixItems, allOf)
func normalizeNestedArraySchemas(schema map[string]interface{}, key string, debug bool) {
	if val, exists := schema[key]; exists {
		if valArr, ok := val.([]interface{}); ok {
			for i, item := range valArr {
				if itemMap, ok := item.(map[string]interface{}); ok {
					valArr[i] = Normalize(itemMap, debug)
				}
			}
		}
	}
}
