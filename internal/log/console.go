package log

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"sort"
	"strings"
	"sync"

	"github.com/Jyko/Bigbox/internal/errs"
)

// ConsoleOptions configure le rendu humain.
type ConsoleOptions struct {
	Level       slog.Level
	Color       bool
	Interactive bool
	Redactor    *Redactor
}

// ConsoleHandler rend les événements en arbre « feature › étape ». C'est le seul composant qui
// met en forme la console : les messages ne portent ni retour chariot, ni tabulation, ni emoji.
type ConsoleHandler struct {
	opt   ConsoleOptions
	base  []slog.Attr
	state *consoleState
}

type consoleState struct {
	mu      sync.Mutex
	w       io.Writer
	pending bool // une ligne « étape en cours » est affichée sans retour à la ligne
}

// NewConsoleHandler crée le handler console.
func NewConsoleHandler(w io.Writer, opt ConsoleOptions) *ConsoleHandler {
	return &ConsoleHandler{opt: opt, state: &consoleState{w: w}}
}

// Enabled implémente slog.Handler.
func (h *ConsoleHandler) Enabled(_ context.Context, l slog.Level) bool { return l >= h.opt.Level }

// WithAttrs implémente slog.Handler.
func (h *ConsoleHandler) WithAttrs(as []slog.Attr) slog.Handler {
	c := *h
	c.base = append(append([]slog.Attr{}, h.base...), as...)
	return &c
}

// WithGroup implémente slog.Handler (les groupes sont aplatis en console).
func (h *ConsoleHandler) WithGroup(string) slog.Handler { return h }

// Couleurs ANSI.
const (
	cReset = "\033[0m"
	cBold  = "\033[1m"
	cDim   = "\033[2m"
	cRed   = "\033[31m"
	cGreen = "\033[32m"
	cYel   = "\033[33m"
	cBlue  = "\033[34m"
)

func (h *ConsoleHandler) c(color, s string) string {
	if !h.opt.Color || s == "" {
		return s
	}
	return color + s + cReset
}

// Handle implémente slog.Handler.
func (h *ConsoleHandler) Handle(_ context.Context, r slog.Record) error {
	m := attrs(h.base, r)
	red := func(s string) string { return h.opt.Redactor.Redact(s) }

	var line string
	pending := false
	switch r.Message {
	case EvRunStart, EvRunEnd:
		return nil
	case EvFeatureStart:
		line = h.c(cBold, "▸ "+str(m, KeyFeature))
	case EvFeatureEnd:
		if Status(str(m, KeyStatus)) == StatusOK && r.Level <= slog.LevelDebug {
			line = h.c(cDim, "= "+str(m, KeyFeature)+" : conforme")
		} else {
			return nil
		}
	case EvStepStart:
		if !h.opt.Interactive {
			return nil
		}
		line = "  " + h.c(cBlue, "⋯") + " " + red(str(m, KeyLabel))
		pending = true
	case EvStepEnd:
		line = h.stepEnd(m, red)
	case EvCmdExec:
		line = h.c(cDim, "    $ "+errs.ShellJoin(argv(m, h.opt.Redactor)))
	case EvCmdExit:
		line = h.c(cDim, fmt.Sprintf("    ↳ code %s (%s)", str(m, KeyExitCode), errs.FormatDuration(dur(m, KeyDuration))))
	case EvSudo:
		line = h.c(cYel, "⚠ ") + red(str(m, KeyLabel))
	default:
		line = h.message(r, m, red)
	}

	st := h.state
	st.mu.Lock()
	defer st.mu.Unlock()
	switch {
	case st.pending && r.Message == EvStepEnd:
		// La ligne « en cours » est remplacée par le résultat de l'étape
		fmt.Fprint(st.w, "\r\033[K")
	case st.pending:
		fmt.Fprintln(st.w)
	}
	st.pending = pending
	if pending {
		_, err := fmt.Fprint(st.w, line)
		return err
	}
	_, err := fmt.Fprintln(st.w, line)
	return err
}

func (h *ConsoleHandler) stepEnd(m map[string]slog.Value, red func(string) string) string {
	label := red(str(m, KeyLabel))
	d := errs.FormatDuration(dur(m, KeyDuration))
	switch Status(str(m, KeyStatus)) {
	case StatusFailed:
		return fmt.Sprintf("  %s %s  %s", h.c(cRed, "✗"), label, h.c(cRed, "échec après "+d))
	case StatusSkipped:
		reason := red(str(m, KeyError))
		if reason != "" {
			reason = " : " + reason
		}
		return fmt.Sprintf("  %s %s  %s", h.c(cDim, "–"), label, h.c(cDim, "ignoré"+reason))
	case StatusChanged:
		return fmt.Sprintf("  %s %s  %s", h.c(cGreen, "✓"), label, h.c(cDim, "modifié, "+d))
	default:
		return fmt.Sprintf("  %s %s  %s", h.c(cGreen, "✓"), label, h.c(cDim, "ok, "+d))
	}
}

// message rend un message libre : texte, puis attributs en debug.
func (h *ConsoleHandler) message(r slog.Record, m map[string]slog.Value, red func(string) string) string {
	var b strings.Builder
	switch {
	case r.Level >= slog.LevelError:
		b.WriteString(h.c(cRed, "✗ "))
	case r.Level >= slog.LevelWarn:
		b.WriteString(h.c(cYel, "⚠ "))
	case r.Level < slog.LevelInfo:
		b.WriteString(h.c(cDim, "· "))
	}
	b.WriteString(red(r.Message))
	if r.Level < slog.LevelInfo || r.Level >= slog.LevelWarn {
		keys := make([]string, 0, len(m))
		for k := range m {
			if k != KeyRunID {
				keys = append(keys, k)
			}
		}
		sort.Strings(keys)
		for _, k := range keys {
			b.WriteString(h.c(cDim, fmt.Sprintf(" %s=%s", k, red(m[k].String()))))
		}
	}
	return b.String()
}

func argv(m map[string]slog.Value, r *Redactor) []string {
	if v, ok := m[KeyArgv]; ok {
		if a, ok := v.Any().([]string); ok {
			return r.RedactAll(a)
		}
	}
	return nil
}
