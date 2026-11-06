package run

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"

	"github.com/Jyko/Bigbox/internal/errs"
)

// FakeRunner est un Runner scriptable pour les tests : chaque commande est confrontée aux
// règles dans l'ordre de déclaration ; une commande sans règle est une erreur (aucune
// surprise silencieuse). Les appels sont enregistrés.
type FakeRunner struct {
	mu    sync.Mutex
	rules []*Rule
	Calls []Cmd
}

// Rule associe un préfixe d'argv à un résultat.
type Rule struct {
	prefix []string
	result Result
	err    error
	hook   func(Cmd)
	times  int // 0 : illimité
	used   int
}

var _ Runner = (*FakeRunner)(nil)

// On déclare une règle pour les commandes commençant par prefix (ex. "apt-get", "install").
func (f *FakeRunner) On(prefix ...string) *Rule {
	f.mu.Lock()
	defer f.mu.Unlock()
	r := &Rule{prefix: prefix}
	f.rules = append(f.rules, r)
	return r
}

// Return fixe le résultat (code 0 par défaut).
func (r *Rule) Return(res Result) *Rule { r.result = res; return r }

// Stdout fixe la sortie standard (code 0).
func (r *Rule) Stdout(out string) *Rule { r.result.Stdout = out; return r }

// Exit fixe un code de sortie et un stderr.
func (r *Rule) Exit(code int, stderr string) *Rule {
	r.result.ExitCode, r.result.Stderr = code, stderr
	return r
}

// Err simule une commande qui n'a pas pu s'exécuter (programme absent, annulation…).
func (r *Rule) Err(err error) *Rule { r.err = err; return r }

// Do exécute une fonction à chaque appel (ex. bloquer jusqu'à l'annulation).
func (r *Rule) Do(fn func(Cmd)) *Rule { r.hook = fn; return r }

// Times limite le nombre d'utilisations de la règle (les suivantes passent à la règle d'après).
func (r *Rule) Times(n int) *Rule { r.times = n; return r }

func (f *FakeRunner) match(c Cmd) (*Rule, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.Calls = append(f.Calls, c)
	for _, r := range f.rules {
		if r.times > 0 && r.used >= r.times {
			continue
		}
		if hasPrefix(c.Args, r.prefix) {
			r.used++
			return r, nil
		}
	}
	return nil, &errs.Error{Kind: errs.Internal, Op: fmt.Sprintf("FakeRunner : commande inattendue %q", c.String())}
}

func hasPrefix(args, prefix []string) bool {
	if len(prefix) > len(args) {
		return false
	}
	for i, p := range prefix {
		if args[i] != p {
			return false
		}
	}
	return true
}

func (f *FakeRunner) exec(ctx context.Context, c Cmd) (Result, error) {
	r, err := f.match(c)
	if err != nil {
		return Result{}, err
	}
	if r.hook != nil {
		r.hook(c)
	}
	if ctx.Err() != nil {
		return Result{ExitCode: -1}, ctx.Err()
	}
	if r.err != nil {
		return Result{ExitCode: -1}, r.err
	}
	if r.result.ExitCode != 0 {
		return r.result, &ExitError{Code: r.result.ExitCode}
	}
	return r.result, nil
}

// Run implémente Runner.
func (f *FakeRunner) Run(ctx context.Context, c Cmd) (Result, error) {
	res, err := f.exec(ctx, c)
	if err != nil {
		return res, failure(c, res, err, nil)
	}
	return res, nil
}

// Probe implémente Runner.
func (f *FakeRunner) Probe(ctx context.Context, c Cmd) (bool, error) {
	res, err := f.exec(ctx, c)
	var exitErr *ExitError
	if errors.As(err, &exitErr) {
		return false, nil
	}
	if err != nil {
		return false, failure(c, res, err, nil)
	}
	return true, nil
}

// Commands renvoie les commandes reçues, sous forme lisible (assertions des tests).
func (f *FakeRunner) Commands() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]string, len(f.Calls))
	for i, c := range f.Calls {
		s := c.String()
		if c.Privileged {
			s = "[root] " + s
		}
		out[i] = s
	}
	return out
}

// String résume les règles (débogage des tests).
func (f *FakeRunner) String() string {
	var b strings.Builder
	for _, r := range f.rules {
		fmt.Fprintf(&b, "%s → code %d\n", strings.Join(r.prefix, " "), r.result.ExitCode)
	}
	return b.String()
}
