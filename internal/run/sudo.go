package run

import (
	"context"
	"log/slog"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/log"
)

// keepAliveEvery renouvelle le jeton sudo avant son expiration (15 min par défaut).
const keepAliveEvery = 4 * time.Minute

// Sudo obtient l'élévation une seule fois, uniquement quand le plan contient des étapes
// privilégiées, après avoir affiché leur liste. Le jeton est entretenu tant que le contexte vit.
type Sudo struct {
	Logger      *slog.Logger
	Interactive bool // un TTY est disponible pour demander le mot de passe

	mu       sync.Mutex
	acquired bool
}

// Ensure obtient l'élévation pour les raisons données (libellés des étapes privilégiées).
func (s *Sudo) Ensure(ctx context.Context, reasons []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.acquired || os.Geteuid() == 0 {
		return nil
	}
	logger := s.Logger
	if logger == nil {
		logger = log.Discard()
	}

	// Jeton déjà valide ou NOPASSWD : aucune demande
	if exec.CommandContext(ctx, "sudo", "-n", "true").Run() == nil {
		s.acquired = true
		go s.keepAlive(ctx)
		return nil
	}

	list := "  - " + strings.Join(reasons, "\n  - ")
	if !s.Interactive {
		return &errs.Error{
			Kind: errs.Precondition,
			Op:   "des étapes nécessitent root et aucun terminal n'est disponible pour sudo",
			Hint: "relancez dans un terminal interactif ; étapes concernées :\n" + list,
		}
	}

	logger.Warn(log.EvSudo, log.KeyLabel, "Droits administrateur nécessaires pour :\n"+list, log.KeyReasons, reasons)
	cmd := exec.CommandContext(ctx, "sudo", "-v", "-p", "Mot de passe sudo pour %u : ")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return &errs.Error{
			Kind:  errs.Precondition,
			Op:    "sudo a été refusé",
			Cause: err,
			Hint:  "vérifiez votre mot de passe et que votre compte a les droits sudo",
		}
	}
	s.acquired = true
	go s.keepAlive(ctx)
	return nil
}

func (s *Sudo) keepAlive(ctx context.Context) {
	t := time.NewTicker(keepAliveEvery)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			_ = exec.CommandContext(ctx, "sudo", "-n", "-v").Run()
		}
	}
}
