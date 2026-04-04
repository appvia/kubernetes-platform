package templates_test

import (
	"encoding/json"
	"fmt"

	"github.com/argoproj/argo-cd/v2/applicationset/utils"
)

// goTemplateOptions matches production recommendations (fail fast on typos).
var goTemplateOptions = []string{"missingkey=error"}

func RenderTemplatePatch(tmpl string, params map[string]any) (string, error) {
	var r utils.Render
	return r.Replace(tmpl, params, true, goTemplateOptions)
}

// applyTemplateParamDefaults fills keys that ApplicationSet goTemplates often reference under
// missingkey=error, so embedded JSON fixtures stay small while matching controller evaluation.
func applyTemplateParamDefaults(p map[string]any) {
	setIfAbsent := func(key string, val any) {
		if _, ok := p[key]; !ok {
			p[key] = val
		}
	}
	setIfAbsent("ignoreDifferences", []any{})
	setIfAbsent("release_name", "")
	setIfAbsent("values", "")
	setIfAbsent("parameters", []any{})
	setIfAbsent("repository_path", "")

	normalizeIgnoreDifferenceEntries(p)

	if kraw, ok := p["kustomize"]; ok && kraw != nil {
		if k, ok := kraw.(map[string]any); ok {
			if _, ok := k["commonLabels"]; !ok {
				k["commonLabels"] = map[string]any{}
			}
			if _, ok := k["commonAnnotations"]; !ok {
				k["commonAnnotations"] = map[string]any{}
			}
			if _, ok := k["patches"]; !ok {
				k["patches"] = []any{}
			}
			if _, ok := k["repository"]; !ok {
				k["repository"] = ""
			}
			if _, ok := k["revision"]; !ok {
				k["revision"] = ""
			}
			normalizeKustomizePatches(k)
		}
	}

	if hraw, ok := p["helm"]; ok && hraw != nil {
		if h, ok := hraw.(map[string]any); ok {
			if _, ok := h["parameters"]; !ok {
				h["parameters"] = []any{}
			}
			if _, ok := h["values"]; !ok {
				h["values"] = ""
			}
			if _, ok := h["release_name"]; !ok {
				h["release_name"] = ""
			}
			if _, ok := h["path"]; !ok {
				h["path"] = ""
			}
			if _, ok := h["repository_path"]; !ok {
				h["repository_path"] = ""
			}
		}
	}
}

func normalizeIgnoreDifferenceEntries(p map[string]any) {
	raw, ok := p["ignoreDifferences"]
	if !ok || raw == nil {
		return
	}
	list, ok := raw.([]any)
	if !ok {
		return
	}
	for _, it := range list {
		m, ok := it.(map[string]any)
		if !ok {
			continue
		}
		ensureOptionalString(m, "group", "")
		ensureOptionalString(m, "kind", "")
		ensureOptionalString(m, "name", "")
		ensureOptionalString(m, "namespace", "")
		if _, ok := m["jsonPointers"]; !ok {
			m["jsonPointers"] = []any{}
		}
		if _, ok := m["jqPathExpressions"]; !ok {
			m["jqPathExpressions"] = []any{}
		}
		if _, ok := m["managedFieldsManagers"]; !ok {
			m["managedFieldsManagers"] = []any{}
		}
	}
}

func ensureOptionalString(m map[string]any, key, def string) {
	if _, ok := m[key]; !ok {
		m[key] = def
	}
}

func normalizeKustomizePatches(k map[string]any) {
	raw, ok := k["patches"]
	if !ok || raw == nil {
		return
	}
	list, ok := raw.([]any)
	if !ok {
		return
	}
	for _, it := range list {
		ch, ok := it.(map[string]any)
		if !ok {
			continue
		}
		if _, ok := ch["target"]; !ok {
			ch["target"] = map[string]any{}
		}
		if t, ok := ch["target"].(map[string]any); ok {
			ensureOptionalString(t, "kind", "")
			ensureOptionalString(t, "name", "")
		}
		praw, ok := ch["patch"]
		if !ok || praw == nil {
			continue
		}
		plist, ok := praw.([]any)
		if !ok {
			continue
		}
		for _, pit := range plist {
			pm, ok := pit.(map[string]any)
			if !ok {
				continue
			}
			ensureOptionalString(pm, "op", "")
			ensureOptionalString(pm, "path", "")
			ensureOptionalString(pm, "value", "")
			ensureOptionalString(pm, "key", "")
			ensureOptionalString(pm, "default", "")
			ensureOptionalString(pm, "prefix", "")
		}
	}
}

func paramsFromEmbeddedJSON(raw string) (map[string]any, error) {
	var out map[string]any
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return nil, fmt.Errorf("parse embedded params: %w", err)
	}
	applyTemplateParamDefaults(out)
	return out, nil
}
