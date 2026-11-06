package reconcile

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/feature"
	"github.com/Jyko/Bigbox/internal/log"
	"github.com/Jyko/Bigbox/internal/spec"
	"github.com/Jyko/Bigbox/internal/testutil"
)

// world simule la machine : ce qui est installé et démarré, et l'ordre des actions.
type world struct {
	mu        sync.Mutex
	installed map[string]bool
	running   map[string]bool
	journal   []string
}

func newWorld() *world { return &world{installed: map[string]bool{}, running: map[string]bool{}} }

func (w *world) record(s string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.journal = append(w.journal, s)
}

type obs struct{ installed, running bool }

func (o obs) String() string {
	switch {
	case o.running:
		return "démarrée"
	case o.installed:
		return "arrêtée"
	default:
		return "absente"
	}
}

type fake struct {
	name   string
	deps   []string
	w      *world
	fail   map[string]bool // étapes en échec
	block  string          // étape qui attend l'annulation
	panic  string          // étape qui panique
	priv   bool
	tmo    time.Duration
	failOb bool
}

func (f *fake) Name() string           { return f.name }
func (f *fake) Description() string    { return "feature " + f.name }
func (f *fake) Dependencies() []string { return f.deps }
func (f *fake) Info() spec.Info        { return spec.Info{Stoppable: true} }

func (f *fake) Observe(context.Context, *feature.Env) (feature.Observed, error) {
	if f.failOb {
		return nil, errors.New("observation impossible")
	}
	f.w.mu.Lock()
	defer f.w.mu.Unlock()
	return obs{f.w.installed[f.name], f.w.running[f.name]}, nil
}

func (f *fake) Plan(d feature.Desired, o feature.Observed) ([]feature.Step, error) {
	ob := o.(obs)
	st := func(id, label string, a feature.Action) feature.Step {
		return feature.Step{ID: id, Label: label + " de " + f.name, Action: a, Privileged: f.priv, Timeout: f.tmo}
	}
	var steps []feature.Step
	switch d.State {
	case spec.Running, spec.Stopped:
		if !ob.installed {
			steps = append(steps, st("install", "Installation", feature.Create), st("configure", "Configuration", feature.Create))
		}
		if d.State == spec.Running && !ob.running {
			steps = append(steps, st("start", "Démarrage", feature.Update))
		}
		if d.State == spec.Stopped && ob.running {
			steps = append(steps, st("stop", "Arrêt", feature.Update))
		}
	case spec.Absent:
		if ob.installed {
			steps = append(steps, st("purge", "Purge", feature.Delete), st("cleanup", "Nettoyage", feature.Delete))
		}
	}
	return steps, nil
}

func (f *fake) Apply(ctx context.Context, _ *feature.Env, s feature.Step) error {
	f.w.record(f.name + ":" + s.ID)
	if s.ID == f.block {
		<-ctx.Done()
		return fmt.Errorf("attente interrompue : %w", ctx.Err())
	}
	if s.ID == f.panic {
		panic("boum")
	}
	if f.fail[s.ID] {
		return &errs.Error{Kind: errs.Environment, Op: "échec simulé", Hint: "relancez"}
	}
	f.w.mu.Lock()
	defer f.w.mu.Unlock()
	switch s.ID {
	case "install":
		f.w.installed[f.name] = true
	case "start":
		f.w.running[f.name] = true
	case "stop":
		f.w.running[f.name] = false
	case "purge":
		f.w.installed[f.name], f.w.running[f.name] = false, false
	}
	return nil
}

type cible struct {
	w                                *world
	k3s, cnpg, pg, nats, docker, qol *fake
	r                                *Reconciler
}

func newCible(t *testing.T) *cible {
	t.Helper()
	w := newWorld()
	c := &cible{w: w,
		k3s: &fake{name: "k3s", w: w}, cnpg: &fake{name: "cnpg", deps: []string{"k3s"}, w: w},
		pg: &fake{name: "pg", deps: []string{"cnpg"}, w: w}, nats: &fake{name: "nats", deps: []string{"k3s"}, w: w},
		docker: &fake{name: "docker", w: w}, qol: &fake{name: "qol", w: w},
	}
	reg, err := feature.NewRegistry(c.k3s, c.cnpg, c.pg, c.nats, c.docker, c.qol)
	if err != nil {
		t.Fatal(err)
	}
	c.r = &Reconciler{Features: reg, Env: &feature.Env{Log: log.Discard()}}
	return c
}

func parse(t *testing.T, c *cible, yaml string) *spec.Spec {
	t.Helper()
	s, err := spec.Parse("bigbox.yaml", []byte("apiVersion: bigbox.dev/v1\n"+yaml), c.r.Features)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func (c *cible) plan(t *testing.T, s *spec.Spec) *Plan {
	t.Helper()
	p, err := c.r.Plan(context.Background(), s)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func (c *cible) journal() string { return strings.Join(c.w.journal, " ") }

func TestIdempotence(t *testing.T) {
	c := newCible(t)
	s := parse(t, c, "features:\n  pg: {}\n  docker: {}\n")
	p := c.plan(t, s)

	var b strings.Builder
	RenderPlan(&b, p)
	testutil.Golden(t, "plan_pg", b.String())
	b.Reset()
	if err := WriteJSON(&b, p); err != nil {
		t.Fatal(err)
	}
	testutil.Golden(t, "plan_pg_json", b.String())

	rep, err := c.r.Apply(context.Background(), p, nil)
	if err != nil {
		t.Fatal(err)
	}
	// Dépendances d'abord, dans l'ordre du graphe
	want := "docker:install docker:configure docker:start k3s:install k3s:configure k3s:start " +
		"cnpg:install cnpg:configure cnpg:start pg:install pg:configure pg:start"
	if c.journal() != want {
		t.Errorf("ordre :\n %s\nattendu\n %s", c.journal(), want)
	}
	if rep.Counts()[log.StatusChanged] != 12 {
		t.Errorf("compteurs : %v", rep.Counts())
	}
	// Second plan : aucune étape
	if p2 := c.plan(t, s); p2.Changes() != 0 {
		t.Errorf("second plan non vide : %d changements", p2.Changes())
	}
	b.Reset()
	RenderStatus(&b, c.plan(t, s), c.r.Features)
	testutil.Golden(t, "status_conforme", b.String())
}

func TestSuppressionDansLOrdreInverse(t *testing.T) {
	c := newCible(t)
	if _, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  pg: {}\n  nats: {}\n")), nil); err != nil {
		t.Fatal(err)
	}
	c.w.journal = nil
	// Tout retirer : dépendants avant dépendances
	p := c.plan(t, parse(t, c, "features: {}\n"))
	if _, err := c.r.Apply(context.Background(), p, nil); err != nil {
		t.Fatal(err)
	}
	j := c.journal()
	if strings.Index(j, "pg:purge") > strings.Index(j, "cnpg:purge") || strings.Index(j, "cnpg:purge") > strings.Index(j, "k3s:purge") ||
		strings.Index(j, "nats:purge") > strings.Index(j, "k3s:purge") {
		t.Errorf("ordre de suppression : %s", j)
	}
}

func TestDésactiverUneDépendanceUtiliséeEstIncohérent(t *testing.T) {
	c := newCible(t)
	s := parse(t, c, "features:\n  pg: {}\n  k3s:\n    state: absent\n")
	_, err := c.r.Plan(context.Background(), s)
	if errs.KindOf(err) != errs.Config || !strings.Contains(err.Error(), "cnpg nécessite k3s, déclarée absente") {
		t.Errorf("incohérence attendue : %v", err)
	}
	s = parse(t, c, "features:\n  pg: {}\n  k3s:\n    state: stopped\n")
	if _, err := c.r.Plan(context.Background(), s); err == nil || !strings.Contains(err.Error(), "nécessite k3s démarrée") {
		t.Errorf("incohérence stopped attendue : %v", err)
	}
	// Mais tout arrêter est cohérent
	s = parse(t, c, "features:\n  pg: {state: stopped}\n  cnpg: {state: stopped}\n  k3s: {state: stopped}\n")
	if _, err := c.r.Plan(context.Background(), s); err != nil {
		t.Errorf("arrêt complet : %v", err)
	}
}

func TestÉchecEnConvergence(t *testing.T) {
	c := newCible(t)
	c.cnpg.fail = map[string]bool{"install": true}
	rep, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  pg: {}\n  qol: {}\n")), nil)
	if errs.ExitCode(err) != errs.ExitFailed {
		t.Fatalf("code 1 attendu : %v", err)
	}
	// cnpg s'arrête à sa première étape, pg est ignorée, qol (indépendante) passe
	if strings.Contains(c.journal(), "cnpg:configure") || strings.Contains(c.journal(), " pg:") ||
		!strings.Contains(c.journal(), "qol:start") {
		t.Errorf("journal : %s", c.journal())
	}
	var reasons []string
	for _, s := range rep.Steps {
		if s.Status == log.StatusSkipped {
			reasons = append(reasons, s.Feature+":"+s.Step.ID+" ("+s.Reason+")")
		}
	}
	want := "cnpg:configure (étape précédente en échec) cnpg:start (étape précédente en échec) " +
		"pg:install (dépendance cnpg en échec) pg:configure (dépendance cnpg en échec) pg:start (dépendance cnpg en échec)"
	if strings.Join(reasons, " ") != want {
		t.Errorf("ignorées :\n %s\nattendu\n %s", strings.Join(reasons, " "), want)
	}
	f := rep.Failed()
	var te *errs.Error
	if len(f) != 1 || !errors.As(f[0].Err, &te) || te.Feature != "cnpg" || te.Step != "Installation de cnpg" {
		t.Errorf("échec mal situé : %+v", f)
	}
}

func TestSuppressionBestEffort(t *testing.T) {
	c := newCible(t)
	if _, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  pg: {}\n  docker: {}\n")), nil); err != nil {
		t.Fatal(err)
	}
	c.w.journal = nil
	c.pg.fail = map[string]bool{"purge": true}
	c.docker.fail = map[string]bool{"purge": true}
	rep, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features: {}\n")), nil)
	if err == nil {
		t.Fatal("échec attendu")
	}
	j := c.journal()
	// Chaque étape est tentée (pg:cleanup, docker:cleanup), mais cnpg et k3s sont conservées
	// car pg n'a pas pu être retirée avant elles.
	for _, want := range []string{"pg:purge", "pg:cleanup", "docker:purge", "docker:cleanup"} {
		if !strings.Contains(j, want) {
			t.Errorf("%s doit être tentée : %s", want, j)
		}
	}
	if strings.Contains(j, "cnpg:purge") || strings.Contains(j, "k3s:purge") {
		t.Errorf("cnpg et k3s ne doivent pas être retirées avant pg : %s", j)
	}
	if len(rep.Failed()) != 2 || len(strings.Split(err.Error(), "\n")) != 2 {
		t.Errorf("toutes les erreurs doivent être rapportées : %v", err)
	}
}

func TestInterruption(t *testing.T) {
	c := newCible(t)
	c.k3s.block = "configure"
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(50*time.Millisecond, cancel)
	rep, err := c.r.Apply(ctx, c.plan(t, parse(t, c, "features:\n  pg: {}\n")), nil)
	if errs.ExitCode(err) != errs.ExitInterrupted {
		t.Fatalf("code 130 attendu : %v", err)
	}
	if strings.Contains(c.journal(), "cnpg") {
		t.Errorf("aucune étape après l'interruption : %s", c.journal())
	}
	skipped := 0
	for _, s := range rep.Steps {
		if s.Status == log.StatusSkipped {
			skipped++
		}
	}
	if skipped != 7 { // k3s:start + 3 cnpg + 3 pg
		t.Errorf("%d étapes ignorées, attendu 7", skipped)
	}
	// Reprise : un nouvel apply termine sans dérive
	c.k3s.block = ""
	if _, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  pg: {}\n")), nil); err != nil {
		t.Fatal(err)
	}
	if p := c.plan(t, parse(t, c, "features:\n  pg: {}\n")); p.Changes() != 0 {
		t.Errorf("dérive après reprise : %d", p.Changes())
	}
}

func TestDélaiParÉtape(t *testing.T) {
	c := newCible(t)
	c.qol.block, c.qol.tmo = "install", 50*time.Millisecond
	_, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  qol: {}\n")), nil)
	var te *errs.Error
	if !errors.As(err, &te) || !strings.Contains(te.Op, "délai de 50 ms dépassé") || errs.ExitCode(err) != errs.ExitFailed {
		t.Errorf("délai dépassé attendu (code 1) : %v", err)
	}
}

func TestPanique(t *testing.T) {
	c := newCible(t)
	c.docker.panic = "install"
	_, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  docker: {}\n  qol: {}\n")), nil)
	if errs.KindOf(err) != errs.Internal || !strings.Contains(err.Error(), "boum") || !strings.Contains(c.journal(), "qol:start") {
		t.Errorf("panique transformée en erreur interne, exécution poursuivie : %v / %s", err, c.journal())
	}
}

type elevator struct{ reasons []string }

func (e *elevator) Ensure(_ context.Context, r []string) error { e.reasons = r; return nil }

func TestÉlévationSeulementSiNécessaire(t *testing.T) {
	c := newCible(t)
	el := &elevator{}
	if _, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  qol: {}\n")), el); err != nil {
		t.Fatal(err)
	}
	if el.reasons != nil {
		t.Errorf("aucune élévation attendue : %v", el.reasons)
	}
	c.docker.priv = true
	if _, err := c.r.Apply(context.Background(), c.plan(t, parse(t, c, "features:\n  qol: {}\n  docker: {}\n")), el); err != nil {
		t.Fatal(err)
	}
	if strings.Join(el.reasons, "|") != "docker › Installation de docker|docker › Configuration de docker|docker › Démarrage de docker" {
		t.Errorf("raisons : %v", el.reasons)
	}
}

func TestObservationEnÉchec(t *testing.T) {
	c := newCible(t)
	c.nats.failOb = true
	_, err := c.r.Plan(context.Background(), parse(t, c, "features: {}\n"))
	var te *errs.Error
	if !errors.As(err, &te) || te.Feature != "nats" || te.Step != "observer l'état réel" {
		t.Errorf("erreur d'observation située attendue : %v", err)
	}
}
