package feature

import (
	"fmt"
	"sort"
	"strings"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/spec"
)

// Registry est l'ensemble des features connues de ce binaire, et leur graphe de dépendances.
type Registry struct {
	features map[string]Feature
	order    []string // tri topologique : dépendances d'abord
}

var _ spec.Catalog = (*Registry)(nil)

// NewRegistry valide les features : noms uniques, dépendances existantes, aucun cycle.
func NewRegistry(fs ...Feature) (*Registry, error) {
	r := &Registry{features: map[string]Feature{}}
	for _, f := range fs {
		if _, dup := r.features[f.Name()]; dup {
			return nil, errs.New(errs.Internal, "feature déclarée deux fois : "+f.Name())
		}
		r.features[f.Name()] = f
	}
	for _, name := range r.Names() {
		for _, d := range r.features[name].Dependencies() {
			if _, ok := r.features[d]; !ok {
				return nil, errs.New(errs.Internal, fmt.Sprintf("la feature %s dépend de %s, inconnue", name, d))
			}
		}
	}
	order, err := r.topo()
	if err != nil {
		return nil, err
	}
	r.order = order
	return r, nil
}

// Get renvoie une feature.
func (r *Registry) Get(name string) (Feature, bool) { f, ok := r.features[name]; return f, ok }

// Info implémente spec.Catalog.
func (r *Registry) Info(name string) (spec.Info, bool) {
	f, ok := r.features[name]
	if !ok {
		return spec.Info{}, false
	}
	return f.Info(), true
}

// Names renvoie les noms triés alphabétiquement.
func (r *Registry) Names() []string {
	out := make([]string, 0, len(r.features))
	for n := range r.features {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// Order renvoie toutes les features, dépendances d'abord (ordre de création). L'ordre est
// déterministe : à égalité, ordre alphabétique.
func (r *Registry) Order() []string { return append([]string(nil), r.order...) }

// Sort trie un sous-ensemble selon Order ; reverse donne l'ordre de suppression.
func (r *Registry) Sort(names []string, reverse bool) []string {
	pos := map[string]int{}
	for i, n := range r.order {
		pos[n] = i
	}
	out := append([]string(nil), names...)
	sort.SliceStable(out, func(i, j int) bool {
		if reverse {
			return pos[out[i]] > pos[out[j]]
		}
		return pos[out[i]] < pos[out[j]]
	})
	return out
}

// Requires renvoie la fermeture avant : les features données et toutes leurs dépendances
// (directes et indirectes), dans l'ordre de création.
func (r *Registry) Requires(names ...string) []string {
	return r.closure(names, func(n string) []string { return r.features[n].Dependencies() }, false)
}

// Dependents renvoie la fermeture arrière : les features données et toutes celles qui en
// dépendent, dans l'ordre de suppression (dépendants d'abord).
func (r *Registry) Dependents(names ...string) []string {
	rev := map[string][]string{}
	for n, f := range r.features {
		for _, d := range f.Dependencies() {
			rev[d] = append(rev[d], n)
		}
	}
	return r.closure(names, func(n string) []string { return rev[n] }, true)
}

func (r *Registry) closure(names []string, next func(string) []string, reverse bool) []string {
	seen := map[string]bool{}
	var visit func(string)
	visit = func(n string) {
		if seen[n] {
			return
		}
		if _, ok := r.features[n]; !ok {
			return
		}
		seen[n] = true
		for _, m := range next(n) {
			visit(m)
		}
	}
	for _, n := range names {
		visit(n)
	}
	out := make([]string, 0, len(seen))
	for n := range seen {
		out = append(out, n)
	}
	return r.Sort(out, reverse)
}

// topo : tri topologique de Kahn, file triée pour un ordre déterministe ; un cycle est rapporté
// avec son chemin.
func (r *Registry) topo() ([]string, error) {
	indeg := map[string]int{}
	rev := map[string][]string{}
	for n, f := range r.features {
		indeg[n] += 0
		for _, d := range f.Dependencies() {
			indeg[n]++
			rev[d] = append(rev[d], n)
		}
	}
	var queue, out []string
	for n, d := range indeg {
		if d == 0 {
			queue = append(queue, n)
		}
	}
	sort.Strings(queue)
	for len(queue) > 0 {
		n := queue[0]
		queue = queue[1:]
		out = append(out, n)
		next := rev[n]
		sort.Strings(next)
		for _, m := range next {
			indeg[m]--
			if indeg[m] == 0 {
				queue = append(queue, m)
				sort.Strings(queue)
			}
		}
	}
	if len(out) != len(r.features) {
		return nil, errs.New(errs.Internal, "cycle de dépendances entre features : "+r.findCycle())
	}
	return out, nil
}

// findCycle renvoie un cycle sous la forme « a → b → a ».
func (r *Registry) findCycle() string {
	const (
		white = iota
		grey
		black
	)
	color := map[string]int{}
	var stack []string
	var cycle []string
	var dfs func(string) bool
	dfs = func(n string) bool {
		color[n] = grey
		stack = append(stack, n)
		deps := append([]string(nil), r.features[n].Dependencies()...)
		sort.Strings(deps)
		for _, d := range deps {
			if color[d] == grey {
				for i, s := range stack {
					if s == d {
						cycle = append(append([]string(nil), stack[i:]...), d)
						return true
					}
				}
			}
			if color[d] == white && dfs(d) {
				return true
			}
		}
		stack = stack[:len(stack)-1]
		color[n] = black
		return false
	}
	for _, n := range r.Names() {
		if color[n] == white && dfs(n) {
			break
		}
	}
	return strings.Join(cycle, " → ")
}
