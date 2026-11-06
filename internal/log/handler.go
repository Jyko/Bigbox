package log

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"time"
)

// Options configure la journalisation d'une exécution.
type Options struct {
	Console      io.Writer  // sortie humaine (stderr en général)
	ConsoleLevel slog.Level // Info par défaut, Debug avec -v, Error avec -q
	Color        bool       // couleurs ANSI (désactivées hors TTY ou avec NO_COLOR)
	Interactive  bool       // TTY : ligne d'étape en cours réécrite à la fin de l'étape
	Journal      io.Writer  // journal JSONL (nil : pas de journal)
	RunID        string
	Redactor     *Redactor
}

// New construit le logger de l'exécution : un seul flux d'événements, deux sorties.
func New(opt Options) *slog.Logger {
	var handlers []slog.Handler
	if opt.Console != nil {
		handlers = append(handlers, NewConsoleHandler(opt.Console, ConsoleOptions{
			Level: opt.ConsoleLevel, Color: opt.Color, Interactive: opt.Interactive, Redactor: opt.Redactor,
		}))
	}
	if opt.Journal != nil {
		handlers = append(handlers, NewJournalHandler(opt.Journal, opt.Redactor))
	}
	l := slog.New(fanout(handlers))
	if opt.RunID != "" {
		l = l.With(KeyRunID, opt.RunID)
	}
	return l
}

// Discard est un logger qui n'écrit rien (tests).
func Discard() *slog.Logger { return slog.New(fanout(nil)) }

// NewJournalHandler écrit chaque événement en JSON, toujours au niveau debug, valeurs masquées.
func NewJournalHandler(w io.Writer, r *Redactor) slog.Handler {
	return slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: slog.LevelDebug,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			return redactAttr(r, a)
		},
	})
}

// redactAttr masque les chaînes, les listes de chaînes et les erreurs ; les durées sont écrites
// en millisecondes pour rester lisibles dans le JSONL.
func redactAttr(r *Redactor, a slog.Attr) slog.Attr {
	v := a.Value.Resolve()
	switch v.Kind() {
	case slog.KindString:
		return slog.String(a.Key, r.Redact(v.String()))
	case slog.KindDuration:
		return slog.Int64(a.Key+"_ms", v.Duration().Milliseconds())
	case slog.KindAny:
		switch x := v.Any().(type) {
		case []string:
			return slog.Any(a.Key, r.RedactAll(x))
		case error:
			return slog.String(a.Key, r.Redact(x.Error()))
		}
	}
	return a
}

// fanout distribue chaque enregistrement à plusieurs handlers.
type fanout []slog.Handler

func (f fanout) Enabled(ctx context.Context, l slog.Level) bool {
	for _, h := range f {
		if h.Enabled(ctx, l) {
			return true
		}
	}
	return false
}

func (f fanout) Handle(ctx context.Context, r slog.Record) error {
	var errs []error
	for _, h := range f {
		if h.Enabled(ctx, r.Level) {
			errs = append(errs, h.Handle(ctx, r.Clone()))
		}
	}
	return errors.Join(errs...)
}

func (f fanout) WithAttrs(as []slog.Attr) slog.Handler {
	out := make(fanout, len(f))
	for i, h := range f {
		out[i] = h.WithAttrs(as)
	}
	return out
}

func (f fanout) WithGroup(name string) slog.Handler {
	out := make(fanout, len(f))
	for i, h := range f {
		out[i] = h.WithGroup(name)
	}
	return out
}

// attrs extrait les attributs d'un enregistrement (et ceux hérités de With) dans une map.
func attrs(base []slog.Attr, r slog.Record) map[string]slog.Value {
	m := make(map[string]slog.Value, r.NumAttrs()+len(base))
	for _, a := range base {
		m[a.Key] = a.Value.Resolve()
	}
	r.Attrs(func(a slog.Attr) bool {
		m[a.Key] = a.Value.Resolve()
		return true
	})
	return m
}

func str(m map[string]slog.Value, k string) string {
	if v, ok := m[k]; ok {
		return v.String()
	}
	return ""
}

func dur(m map[string]slog.Value, k string) time.Duration {
	if v, ok := m[k]; ok && v.Kind() == slog.KindDuration {
		return v.Duration()
	}
	return 0
}
