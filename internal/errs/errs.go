// Package errs définit les erreurs typées de la Bigbox, leurs codes de sortie et leur rendu.
//
// Une erreur doit permettre à l'utilisateur de savoir, sans relancer en debug, ce qui a échoué
// (feature, étape, commande), pourquoi (cause, stderr) et quoi faire (remède).
package errs

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// Kind classe une erreur et détermine le code de sortie.
type Kind int

const (
	// Internal : bug de la Bigbox (valeur par défaut d'une erreur non classée).
	Internal Kind = iota
	// Usage : ligne de commande incorrecte.
	Usage
	// Config : bigbox.yaml invalide.
	Config
	// Precondition : OS non supporté, sudo refusé, port occupé, espace disque…
	Precondition
	// Environment : une commande, le réseau ou le cluster a échoué pendant l'exécution.
	Environment
	// Conflict : une autre exécution est en cours, ou une ressource est déjà prise.
	Conflict
)

func (k Kind) String() string {
	switch k {
	case Usage:
		return "usage"
	case Config:
		return "configuration"
	case Precondition:
		return "précondition"
	case Environment:
		return "environnement"
	case Conflict:
		return "conflit"
	default:
		return "interne"
	}
}

// Codes de sortie stables, documentés dans `bigbox --help`.
const (
	ExitOK           = 0
	ExitFailed       = 1
	ExitUsage        = 2
	ExitDrift        = 3
	ExitPrecondition = 4
	ExitInterrupted  = 130
)

// MaxStderrLines borne le nombre de lignes de stderr conservées dans une erreur.
const MaxStderrLines = 20

// Error est l'erreur typée de la Bigbox. Compatible errors.Is / errors.As via Unwrap.
type Error struct {
	Kind    Kind
	Feature string   // ex. "pg"
	Step    string   // ex. "déployer le Cluster bigbox-pg"
	Op      string   // ce qu'on tentait, en langage utilisateur
	Cause   error    // erreur enveloppée
	Hint    string   // action concrète à mener
	Command []string // argv, déjà masqué
	Stderr  []string // dernières lignes utiles
}

func (e *Error) Error() string {
	var b strings.Builder
	if e.Feature != "" {
		b.WriteString(e.Feature)
		if e.Step != "" {
			b.WriteString(" › ")
			b.WriteString(e.Step)
		}
		b.WriteString(" : ")
	} else if e.Step != "" {
		b.WriteString(e.Step)
		b.WriteString(" : ")
	}
	switch {
	case e.Op != "" && e.Cause != nil:
		fmt.Fprintf(&b, "%s : %v", e.Op, e.Cause)
	case e.Op != "":
		b.WriteString(e.Op)
	case e.Cause != nil:
		b.WriteString(e.Cause.Error())
	default:
		b.WriteString("erreur inconnue")
	}
	return b.String()
}

func (e *Error) Unwrap() error { return e.Cause }

// New crée une erreur d'un type donné.
func New(kind Kind, op string) *Error { return &Error{Kind: kind, Op: op} }

// Wrap enveloppe une cause dans une nouvelle *Error.
func Wrap(cause error, kind Kind, op string) *Error {
	return &Error{Kind: kind, Op: op, Cause: cause}
}

// WithStep situe une erreur dans une feature et une étape. Une *Error existante est complétée
// (copie) sans empiler une seconde erreur ; toute autre erreur est enveloppée, avec le type
// Environment pour une annulation ou un délai dépassé, Internal sinon.
func WithStep(err error, feature, step string) error {
	if err == nil {
		return nil
	}
	var e *Error
	if errors.As(err, &e) {
		c := *e
		if c.Feature == "" {
			c.Feature = feature
		}
		if c.Step == "" {
			c.Step = step
		}
		return &c
	}
	kind := Internal
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		kind = Environment
	}
	return &Error{Kind: kind, Feature: feature, Step: step, Cause: err}
}

// KindOf renvoie le type de la première *Error de la chaîne, Internal sinon.
func KindOf(err error) Kind {
	var e *Error
	if errors.As(err, &e) {
		return e.Kind
	}
	return Internal
}

// ExitCode traduit une erreur en code de sortie.
func ExitCode(err error) int {
	if err == nil {
		return ExitOK
	}
	if errors.Is(err, context.Canceled) {
		return ExitInterrupted
	}
	var d *DriftError
	if errors.As(err, &d) {
		return ExitDrift
	}
	switch KindOf(err) {
	case Usage, Config:
		return ExitUsage
	case Precondition, Conflict:
		return ExitPrecondition
	default:
		return ExitFailed
	}
}

// DriftError signale une dérive (`status`) ou des changements en attente
// (`plan --detailed-exitcode`). Ce n'est pas une panne : le rendu est déjà fait par la commande.
type DriftError struct{ Changes int }

func (d *DriftError) Error() string { return fmt.Sprintf("%d changement(s) en attente", d.Changes) }

// TailLines renvoie les n dernières lignes non vides d'une sortie.
func TailLines(out string, n int) []string {
	var lines []string
	for _, l := range strings.Split(strings.ReplaceAll(out, "\r", "\n"), "\n") {
		if strings.TrimSpace(l) != "" {
			lines = append(lines, strings.TrimRight(l, " \t"))
		}
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}
