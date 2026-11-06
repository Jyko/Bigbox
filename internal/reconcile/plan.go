// Package reconcile calcule l'écart entre bigbox.yaml et la machine (observe → plan) et
// l'applique dans l'ordre du graphe : suppressions d'abord, dépendants avant dépendances ;
// puis créations et modifications, dépendances d'abord.
package reconcile

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/feature"
	"github.com/Jyko/Bigbox/internal/spec"
)

// Phase d'une feature dans le plan.
type Phase int

// Phases : les suppressions passent avant les créations.
const (
	PhaseRemove Phase = iota
	PhaseConverge
)

// FeaturePlan est le plan d'une feature.
type FeaturePlan struct {
	Name     string
	Desired  feature.Desired
	Observed feature.Observed
	Steps    []feature.Step
	Phase    Phase
}

// Changes compte les étapes à exécuter (hors « = conservé »).
func (fp *FeaturePlan) Changes() int {
	n := 0
	for _, s := range fp.Steps {
		if s.Action != feature.Keep {
			n++
		}
	}
	return n
}

// Plan est l'écart complet, dans l'ordre d'exécution.
type Plan struct {
	Features []*FeaturePlan
}

// Changes compte toutes les étapes à exécuter.
func (p *Plan) Changes() int {
	n := 0
	for _, fp := range p.Features {
		n += fp.Changes()
	}
	return n
}

// PrivilegedSteps renvoie les libellés des étapes qui nécessitent root.
func (p *Plan) PrivilegedSteps() []string {
	var out []string
	for _, fp := range p.Features {
		for _, s := range fp.Steps {
			if s.Privileged && s.Action != feature.Keep {
				out = append(out, fp.Name+" › "+s.Label)
			}
		}
	}
	return out
}

// Reconciler relie la spec, le registre des features et l'environnement.
type Reconciler struct {
	Features *feature.Registry
	Env      *feature.Env
}

// Desired calcule l'état désiré de chaque feature connue : déclarations, dépendances ajoutées
// automatiquement, et « absent » pour toutes les autres.
func (r *Reconciler) Desired(s *spec.Spec) (map[string]feature.Desired, error) {
	out := map[string]feature.Desired{}
	var pbs []string

	// Features activées et toutes leurs dépendances, directes ou indirectes
	needed := r.Features.Requires(s.Enabled()...)
	for _, name := range needed {
		d := feature.Desired{State: spec.Running}
		if fs := s.Features[name]; fs != nil && fs.State != spec.Absent {
			d.State, d.Explicit, d.Spec = fs.State, fs.Explicit, fs
		}
		out[name] = d
	}
	// Dépendances : ajoutées si non déclarées ; incohérence si déclarées absentes ou arrêtées
	for _, name := range needed {
		f, _ := r.Features.Get(name)
		for _, dep := range f.Dependencies() {
			d := out[dep]
			ds := s.Features[dep]
			switch {
			case ds != nil && ds.State == spec.Absent:
				pbs = append(pbs, fmt.Sprintf("%s nécessite %s, déclarée absente", name, dep))
			case d.State == spec.Stopped && out[name].State == spec.Running:
				pbs = append(pbs, fmt.Sprintf("%s (running) nécessite %s démarrée, déclarée stopped", name, dep))
			}
			if !d.Explicit {
				d.RequiredBy = append(d.RequiredBy, name)
				sort.Strings(d.RequiredBy)
			}
			out[dep] = d
		}
	}
	// Toutes les autres features : absentes
	for _, name := range r.Features.Order() {
		if _, ok := out[name]; !ok {
			out[name] = feature.Desired{State: spec.Absent, Spec: s.Features[name]}
		}
	}
	if len(pbs) > 0 {
		return nil, &errs.Error{Kind: errs.Config, Op: s.Path + " incohérent", Cause: errors.New(strings.Join(pbs, "\n")),
			Hint: "activez la dépendance, ou retirez la feature qui en a besoin"}
	}
	return out, nil
}

// Plan observe chaque feature et calcule ses étapes. Aucune modification de la machine.
func (r *Reconciler) Plan(ctx context.Context, s *spec.Spec) (*Plan, error) {
	desired, err := r.Desired(s)
	if err != nil {
		return nil, err
	}

	var failures []error
	plans := map[string]*FeaturePlan{}
	for _, name := range r.Features.Order() {
		f, _ := r.Features.Get(name)
		octx, cancel := context.WithTimeout(ctx, feature.DefaultObserveTimeout)
		obs, err := f.Observe(octx, r.Env)
		cancel()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		if err != nil {
			failures = append(failures, errs.WithStep(err, name, "observer l'état réel"))
			continue
		}
		steps, err := f.Plan(desired[name], obs)
		if err != nil {
			failures = append(failures, errs.WithStep(err, name, "calculer le plan"))
			continue
		}
		plans[name] = &FeaturePlan{Name: name, Desired: desired[name], Observed: obs, Steps: steps}
	}
	if len(failures) > 0 {
		return nil, errors.Join(failures...)
	}

	// Suppressions (dépendants d'abord), puis convergence (dépendances d'abord)
	p := &Plan{}
	for _, name := range r.Features.Sort(r.Features.Order(), true) {
		if fp := plans[name]; fp != nil && desired[name].State == spec.Absent {
			fp.Phase = PhaseRemove
			p.Features = append(p.Features, fp)
		}
	}
	for _, name := range r.Features.Order() {
		if fp := plans[name]; fp != nil && desired[name].State != spec.Absent {
			fp.Phase = PhaseConverge
			p.Features = append(p.Features, fp)
		}
	}
	return p, nil
}
