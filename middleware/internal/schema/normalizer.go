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
	"dependentSchemas",
	"if",
	"then",
	"else",
	"not",
	"contentMediaType",
	"contentEncoding",
}

// Normalize recursively removes unsupported JSON Schema features for Gemini compatibility
func Normalize(schema map[string]interface{}, debug bool) map[string]interface{} {
	if schema == nil {
		return nil
	}

	// Remove unsupported keys
	for _, key := range unsupportedKeys {
		if _, exists := schema[key]; exists {
			if debug {
				log.Printf("[schema] removing unsupported key: %s", key)
			}
			delete(schema, key)
		}
	}

	// Handle anyOf/oneOf - flatten to first non-null type
	for _, unionKey := range []string{"anyOf", "oneOf"} {
		if unionVal, exists := schema[unionKey]; exists {
			if unionArr, ok := unionVal.([]interface{}); ok && len(unionArr) > 0 {
				for _, item := range unionArr {
					if itemMap, ok := item.(map[string]interface{}); ok {
						if itemType, hasType := itemMap["type"]; hasType {
							if typeStr, isStr := itemType.(string); isStr && typeStr != "null" {
								schema["type"] = typeStr
								for k, v := range itemMap {
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

	// Recursively normalize nested schemas
	if props, exists := schema["properties"]; exists {
		if propsMap, ok := props.(map[string]interface{}); ok {
			for key, val := range propsMap {
				if valMap, ok := val.(map[string]interface{}); ok {
					propsMap[key] = Normalize(valMap, debug)
				}
			}
		}
	}

	// Normalize items schema (for arrays)
	if items, exists := schema["items"]; exists {
		if itemsMap, ok := items.(map[string]interface{}); ok {
			schema["items"] = Normalize(itemsMap, debug)
		}
	}

	// Normalize additionalProperties if it's a schema
	if addProps, exists := schema["additionalProperties"]; exists {
		if addPropsMap, ok := addProps.(map[string]interface{}); ok {
			schema["additionalProperties"] = Normalize(addPropsMap, debug)
		}
	}

	return schema
}
