// Package run exécute les commandes externes (apt-get, systemctl, usermod, gsettings…).
//
// Toute commande passe par un Runner : délai et annulation par contexte, capture complète de
// stdout et stderr, journalisation (argv masqué, durée, code, sorties) quel que soit le niveau
// console, et erreur typée en cas d'échec. Les tests utilisent FakeRunner : aucun test unitaire
// n'exécute réellement apt, systemctl ni sudo.
package run

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/log"
)

// Cmd décrit une commande externe.
type Cmd struct {
	Args    []string      // argv, Args[0] est le programme
	Dir     string        // répertoire de travail (vide : courant)
	Env     []string      // variables ajoutées à l'environnement ("CLE=valeur")
	Stdin   io.Reader     // entrée (nil : aucune)
	Timeout time.Duration // délai propre à la commande (0 : celui du contexte)
	// Privileged : la commande nécessite root, elle est lancée via sudo (sauf si déjà root).
	Privileged bool
}

// String rend la commande lisible (non masquée : à passer par un Redactor avant affichage).
func (c Cmd) String() string { return strings.Join(c.Args, " ") }

// Result est le résultat d'une commande terminée.
type Result struct {
	ExitCode int
	Stdout   string
	Stderr   string
	Duration time.Duration
}

// Runner exécute des commandes externes.
type Runner interface {
	// Run exécute la commande ; un code de sortie non nul est une erreur (*errs.Error).
	Run(ctx context.Context, c Cmd) (Result, error)
	// Probe exécute une commande de test : true si code 0, false si code non nul.
	// Une erreur signifie que le test n'a pas pu avoir lieu (programme absent, annulation…).
	Probe(ctx context.Context, c Cmd) (bool, error)
}

// AsRoot exécute une commande en root (via sudo si nécessaire).
func AsRoot(ctx context.Context, r Runner, c Cmd) (Result, error) {
	c.Privileged = true
	return r.Run(ctx, c)
}

// ExitError est la cause d'un échec dû à un code de sortie non nul.
type ExitError struct{ Code int }

func (e *ExitError) Error() string { return fmt.Sprintf("code de sortie %d", e.Code) }

// failure construit l'erreur typée d'une commande en échec. Le remède et le type sont déduits
// des sorties (catalogue errs.FindHint) ; argv et sorties sont masqués.
func failure(c Cmd, res Result, cause error, red *log.Redactor) error {
	kind := errs.Environment
	hint := ""
	if h, k, ok := errs.FindHint(res.Stderr + "\n" + res.Stdout); ok {
		hint, kind = h, k
	}
	if errors.Is(cause, context.DeadlineExceeded) {
		hint = "la commande a dépassé son délai ; consultez le journal pour voir où elle s'est arrêtée"
	}
	if hint == "" {
		hint = "lisez stderr ci-dessus ; la sortie complète de la commande est dans le journal"
	}
	stderr := res.Stderr
	if strings.TrimSpace(stderr) == "" {
		stderr = res.Stdout
	}
	argv := c.Args
	if c.Privileged {
		argv = append([]string{"sudo"}, argv...)
	}
	var typed *errs.Error
	if errors.As(cause, &typed) {
		// Erreur déjà qualifiée (ex. programme introuvable) : on ajoute seulement la commande
		e := *typed
		e.Command = red.RedactAll(argv)
		return &e
	}
	return &errs.Error{
		Kind:    kind,
		Op:      "la commande " + c.Args[0] + " a échoué",
		Cause:   cause,
		Hint:    red.Redact(hint),
		Command: red.RedactAll(argv),
		Stderr:  red.RedactAll(errs.TailLines(stderr, errs.MaxStderrLines)),
	}
}
