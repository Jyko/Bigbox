// Package essai est une feature d'essai du socle, sans effet hors de ~/.config/bigbox : elle
// crée un fichier témoin et peut simuler une étape en échec (option `echec: true`), via le
// Runner, pour vérifier de bout en bout le plan, l'apply, le registre, le journal et le rendu
// des erreurs. Elle n'est disponible que si BIGBOX_ESSAI=1 (TU de l'étape 1).
package essai

import (
	"context"
	"errors"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/feature"
	"github.com/Jyko/Bigbox/internal/run"
	"github.com/Jyko/Bigbox/internal/spec"
	"github.com/Jyko/Bigbox/internal/state"
)

// EnvVar active la feature.
const EnvVar = "BIGBOX_ESSAI"

// Feature d'essai.
type Feature struct{}

// Observed est l'état du fichier témoin.
type Observed struct {
	Path   string
	Exists bool
	Owned  bool
}

func (o Observed) String() string {
	switch {
	case o.Exists && o.Owned:
		return "fichier témoin présent"
	case o.Exists:
		return "fichier témoin préexistant (pas à la Bigbox)"
	default:
		return "fichier témoin absent"
	}
}

// Name implémente feature.Feature.
func (Feature) Name() string { return "essai" }

// Description implémente feature.Feature.
func (Feature) Description() string { return "feature d'essai du socle" }

// Dependencies implémente feature.Feature.
func (Feature) Dependencies() []string { return nil }

// Info implémente feature.Feature : seule l'option booléenne `echec` est admise.
func (Feature) Info() spec.Info {
	return spec.Info{ValidateOptions: func(n *yaml.Node) []spec.Problem {
		var pbs []spec.Problem
		for i := 0; i+1 < len(n.Content); i += 2 {
			k, v := n.Content[i], n.Content[i+1]
			switch {
			case k.Value != "echec":
				pbs = append(pbs, spec.Problem{Line: k.Line, Column: k.Column, Key: k.Value, Msg: ": option inconnue (admises : state, echec)"})
			case v.Tag != "!!bool":
				pbs = append(pbs, spec.Problem{Line: v.Line, Column: v.Column, Key: "echec", Msg: "= " + v.Value + " invalide (admis : true, false)"})
			}
		}
		return pbs
	}}
}

func path(e *feature.Env) string { return filepath.Join(e.Sys.Paths.ConfigDir, "essai", "temoin") }

// Observe implémente feature.Feature.
func (Feature) Observe(_ context.Context, e *feature.Env) (feature.Observed, error) {
	p := path(e)
	_, err := os.Stat(p)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, errs.Wrap(err, errs.Environment, "lecture de "+p)
	}
	return Observed{Path: p, Exists: err == nil, Owned: e.State.Owned(state.KindFile, p)}, nil
}

func wantsFailure(d feature.Desired) bool {
	if d.Spec == nil || d.Spec.Options == nil {
		return false
	}
	var o struct {
		Echec bool `yaml:"echec"`
	}
	return d.Spec.Options.Decode(&o) == nil && o.Echec
}

// Plan implémente feature.Feature.
func (Feature) Plan(d feature.Desired, o feature.Observed) ([]feature.Step, error) {
	ob := o.(Observed)
	var steps []feature.Step
	switch d.State {
	case spec.Absent:
		switch {
		case ob.Exists && ob.Owned:
			steps = append(steps, feature.Step{ID: "remove", Label: "Suppression du fichier témoin", Action: feature.Delete, Detail: ob.Path})
		case ob.Exists:
			steps = append(steps, feature.Step{ID: "keep", Label: "Fichier témoin préexistant, conservé", Action: feature.Keep, Detail: ob.Path})
		}
	default:
		if !ob.Exists {
			steps = append(steps, feature.Step{ID: "create", Label: "Création du fichier témoin", Action: feature.Create, Detail: ob.Path})
		}
		if wantsFailure(d) {
			steps = append(steps, feature.Step{ID: "fail", Label: "Étape d'essai en échec", Action: feature.Update})
		}
	}
	return steps, nil
}

// Apply implémente feature.Feature.
func (Feature) Apply(ctx context.Context, e *feature.Env, s feature.Step) error {
	p := path(e)
	switch s.ID {
	case "create":
		// Enregistré avant l'écriture : une interruption ne laisse pas de fichier orphelin
		e.State.Mark(state.KindFile, p, "essai")
		if err := state.WriteFileAtomic(p, []byte("Fichier témoin de la feature essai de la Bigbox\n"), 0o600); err != nil {
			return errs.Wrap(err, errs.Environment, "écriture de "+p)
		}
	case "remove":
		if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
			return errs.Wrap(err, errs.Environment, "suppression de "+p)
		}
		_ = os.Remove(filepath.Dir(p))
		e.State.Unmark(state.KindFile, p)
	case "fail":
		_, err := e.Run.Run(ctx, run.Cmd{Args: []string{"sh", "-c",
			"echo 'essai : début de la commande'; echo 'essai : erreur simulée pour vérifier le rendu des erreurs' >&2; exit 3"}})
		return err
	}
	return nil
}
