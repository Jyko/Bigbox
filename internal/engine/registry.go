package engine

import (
	"maps"
	"slices"

	"bigard.fr/bigbox/internal/module"
)

type Registry struct {
	modules map[string]module.Module
}

func NewRegistry() *Registry {
	return &Registry{
		modules: make(map[string]module.Module),
	}
}

func (r *Registry) Register(candidates []module.Module) {
	for _, candidate := range candidates {
		r.modules[candidate.GetInfos().Name] = candidate
	}
}

func (r *Registry) Loaded(moduleName string) bool {
	_, loaded := r.modules[moduleName]
	return loaded
}

func (r *Registry) Keys() []string {
	return slices.Collect(maps.Keys(r.modules))
}

func (r *Registry) Lookup(moduleName string) module.Module {
	return r.modules[moduleName].(module.Module)
}
