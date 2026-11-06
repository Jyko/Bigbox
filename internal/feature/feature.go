// Package feature définit le contrat d'une feature de la Bigbox et le graphe de leurs
// dépendances. L'ordre d'exécution se déduit du graphe : il n'y a plus de priorités.
package feature

import (
	"context"
	"log/slog"
	"time"

	"github.com/Jyko/Bigbox/internal/env"
	"github.com/Jyko/Bigbox/internal/log"
	"github.com/Jyko/Bigbox/internal/run"
	"github.com/Jyko/Bigbox/internal/spec"
	"github.com/Jyko/Bigbox/internal/state"
)

// Env est passé explicitement à chaque feature : aucune variable globale partagée.
type Env struct {
	Sys      *env.Env
	Run      run.Runner
	State    *state.Registry
	Log      *slog.Logger
	Redactor *log.Redactor
}

// Desired est l'état désiré d'une feature, après application du profil et des dépendances.
type Desired struct {
	State      spec.State
	Explicit   bool     // déclarée dans bigbox.yaml
	RequiredBy []string // features qui l'ont rendue nécessaire (si non explicite)
	Spec       *spec.Feature
}

// Observed est l'état réel d'une feature, propre à chacune. Il est obtenu sans effet de bord.
type Observed any

// Action est la nature d'une étape, affichée comme `terraform plan`.
type Action int

// Actions d'une étape.
const (
	Create Action = iota // + à créer
	Update               // ~ à modifier
	Delete               // - à retirer
	Keep                 // = conservé car préexistant (pas à la Bigbox) : jamais exécuté
)

// Symbol renvoie le symbole de l'action (+, ~, -, =).
func (a Action) Symbol() string { return [...]string{"+", "~", "-", "="}[a] }

func (a Action) String() string { return [...]string{"create", "update", "delete", "keep"}[a] }

// Step est une étape d'un plan. Son libellé est la seule source de vérité : il est réutilisé tel
// quel par `plan`, la console et le journal.
type Step struct {
	ID         string        // identifiant stable dans la feature (ex. "install-packages")
	Label      string        // phrase complète en français (« Installation du client PostgreSQL 17 »)
	Action     Action        //
	Privileged bool          // nécessite root
	Timeout    time.Duration // délai de l'étape (0 : DefaultStepTimeout)
	Detail     string        // précision affichée par plan (ex. liste des paquets)
}

// DefaultStepTimeout borne toute étape qui ne précise pas son délai.
const DefaultStepTimeout = 10 * time.Minute

// DefaultObserveTimeout borne l'observation d'une feature.
const DefaultObserveTimeout = time.Minute

// Feature est le contrat d'une feature.
type Feature interface {
	Name() string
	// Description courte, affichée par `bigbox status`.
	Description() string
	Dependencies() []string
	// Info décrit ce que la feature accepte dans bigbox.yaml.
	Info() spec.Info
	// Observe lit l'état réel, sans effet de bord.
	Observe(ctx context.Context, e *Env) (Observed, error)
	// Plan calcule les étapes ordonnées qui mènent de observed à desired. Fonction pure : un
	// second plan après un apply réussi doit être vide (idempotence).
	Plan(desired Desired, observed Observed) ([]Step, error)
	// Apply exécute une étape du plan. Idempotente.
	Apply(ctx context.Context, e *Env, step Step) error
}
