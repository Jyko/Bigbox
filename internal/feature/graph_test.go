package feature

import (
	"context"
	"strings"
	"testing"

	"github.com/Jyko/Bigbox/internal/spec"
)

type stub struct {
	name string
	deps []string
}

func (s stub) Name() string                                    { return s.name }
func (s stub) Description() string                             { return s.name }
func (s stub) Dependencies() []string                          { return s.deps }
func (s stub) Info() spec.Info                                 { return spec.Info{} }
func (s stub) Observe(context.Context, *Env) (Observed, error) { return nil, nil }
func (s stub) Plan(Desired, Observed) ([]Step, error)          { return nil, nil }
func (s stub) Apply(context.Context, *Env, Step) error         { return nil }

// Graphe proche de la cible : pg → cnpg → k3s → docker ; nats, sftp → k3s ; qol, shell seuls.
func cible(t *testing.T) *Registry {
	t.Helper()
	r, err := NewRegistry(
		stub{"pg", []string{"cnpg"}}, stub{"cnpg", []string{"k3s"}}, stub{"k3s", nil},
		stub{"nats", []string{"k3s"}}, stub{"sftp", []string{"k3s"}}, stub{"docker", nil},
		stub{"qol", nil}, stub{"shell", []string{"qol"}},
	)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func j(s []string) string { return strings.Join(s, " ") }

func TestOrdre(t *testing.T) {
	r := cible(t)
	order := r.Order()
	pos := map[string]int{}
	for i, n := range order {
		pos[n] = i
	}
	for _, f := range r.Names() {
		ff, _ := r.Get(f)
		for _, d := range ff.Dependencies() {
			if pos[d] > pos[f] {
				t.Errorf("%s doit précéder %s : %v", d, f, order)
			}
		}
	}
	// Déterministe
	if j(order) != j(cible(t).Order()) || j(order) != "docker k3s cnpg nats pg qol sftp shell" {
		t.Errorf("ordre : %v", order)
	}
}

func TestFermetures(t *testing.T) {
	r := cible(t)
	if got := j(r.Requires("pg")); got != "k3s cnpg pg" {
		t.Errorf("Requires(pg) = %s", got)
	}
	if got := j(r.Requires("pg", "shell")); got != "k3s cnpg pg qol shell" {
		t.Errorf("Requires(pg, shell) = %s", got)
	}
	// Ordre de suppression : dépendants d'abord, pg avant cnpg
	if got := j(r.Dependents("cnpg")); got != "pg cnpg" {
		t.Errorf("Dependents(cnpg) = %s", got)
	}
	got := r.Dependents("k3s")
	if got[len(got)-1] != "k3s" || strings.Index(j(got), "pg") > strings.Index(j(got), "cnpg") || len(got) != 5 {
		t.Errorf("Dependents(k3s) = %v", got)
	}
	if j(r.Requires("inconnue")) != "" {
		t.Error("feature inconnue ignorée")
	}
}

func TestCycle(t *testing.T) {
	_, err := NewRegistry(stub{"a", []string{"b"}}, stub{"b", []string{"c"}}, stub{"c", []string{"a"}}, stub{"d", nil})
	if err == nil || !strings.Contains(err.Error(), "a → b → c → a") {
		t.Errorf("cycle attendu avec son chemin : %v", err)
	}
}

func TestDépendanceInconnueEtDoublon(t *testing.T) {
	if _, err := NewRegistry(stub{"pg", []string{"k3s"}}); err == nil || !strings.Contains(err.Error(), "k3s, inconnue") {
		t.Errorf("dépendance inconnue : %v", err)
	}
	if _, err := NewRegistry(stub{"pg", nil}, stub{"pg", nil}); err == nil {
		t.Error("doublon attendu")
	}
}
