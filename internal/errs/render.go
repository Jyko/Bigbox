package errs

import (
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
)

// JournalRef désigne le journal d'une exécution, ajouté au rendu d'une erreur.
type JournalRef struct {
	Path  string
	RunID string
}

// RenderOptions paramètre le rendu d'une erreur.
type RenderOptions struct {
	Elapsed time.Duration // durée de l'étape en échec (0 : non affichée)
	Journal JournalRef
	Mark    string // symbole d'échec ("✗" par défaut)
}

// Render écrit une erreur dans le format de la section 2.1 du plan :
//
//	✗ pg › déployer le Cluster bigbox-pg  (échec après 42 s)
//	  cause    : …
//	  commande : …
//	  à faire  : …
//	  journal  : … (run 7f3a)
//
// Une erreur multiple (errors.Join) est rendue erreur par erreur.
func Render(w io.Writer, err error, opt RenderOptions) {
	if err == nil {
		return
	}
	if j, ok := err.(interface{ Unwrap() []error }); ok {
		for _, e := range j.Unwrap() {
			Render(w, e, RenderOptions{Mark: opt.Mark})
		}
		renderJournal(w, opt.Journal)
		return
	}
	mark := opt.Mark
	if mark == "" {
		mark = "✗"
	}

	var e *Error
	if !errors.As(err, &e) {
		e = &Error{Kind: Internal, Cause: err}
	}

	title := e.Feature
	if e.Step != "" {
		if title != "" {
			title += " › "
		}
		title += e.Step
	}
	if title == "" {
		title = e.Op
	}
	if title == "" {
		title = "erreur " + e.Kind.String()
	}
	fmt.Fprintf(w, "%s %s", mark, title)
	if opt.Elapsed > 0 {
		fmt.Fprintf(w, "  (échec après %s)", FormatDuration(opt.Elapsed))
	}
	fmt.Fprintln(w)

	cause := ""
	switch {
	case e.Op != "" && e.Op != title && e.Cause != nil:
		cause = e.Op + " : " + e.Cause.Error()
	case e.Cause != nil:
		cause = e.Cause.Error()
	case e.Op != title:
		cause = e.Op
	}
	field(w, "cause", cause)
	if len(e.Command) > 0 {
		field(w, "commande", ShellJoin(e.Command))
	}
	if len(e.Stderr) > 0 {
		field(w, "stderr", strings.Join(e.Stderr, "\n"))
	}
	hint := e.Hint
	if hint == "" && e.Kind == Internal {
		hint = "erreur inattendue de la Bigbox ; ouvrez un ticket en joignant `bigbox logs --last --raw`"
	}
	field(w, "à faire", hint)
	renderJournal(w, opt.Journal)
}

func renderJournal(w io.Writer, j JournalRef) {
	if j.Path == "" {
		return
	}
	v := j.Path
	if j.RunID != "" {
		v += " (run " + j.RunID + ")"
	}
	field(w, "journal", v)
}

// field écrit « label : valeur » aligné, les lignes suivantes indentées sous la valeur.
func field(w io.Writer, label, value string) {
	if strings.TrimSpace(value) == "" {
		return
	}
	const width = 8 // « commande »
	prefix := fmt.Sprintf("  %-*s : ", width, label)
	pad := strings.Repeat(" ", len([]rune(prefix)))
	for i, l := range strings.Split(value, "\n") {
		if i == 0 {
			fmt.Fprintf(w, "%s%s\n", prefix, l)
		} else {
			fmt.Fprintf(w, "%s%s\n", pad, l)
		}
	}
}

// ShellJoin rend un argv copiable dans un shell : les arguments contenant des espaces ou des
// caractères spéciaux sont entre apostrophes.
func ShellJoin(argv []string) string {
	out := make([]string, len(argv))
	for i, a := range argv {
		if a != "" && strings.IndexFunc(a, needsQuote) < 0 {
			out[i] = a
			continue
		}
		out[i] = "'" + strings.ReplaceAll(a, "'", `'\''`) + "'"
	}
	return strings.Join(out, " ")
}

func needsQuote(r rune) bool {
	switch {
	case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		return false
	default:
		return !strings.ContainsRune("-_./=:,+@%«»", r)
	}
}

// FormatDuration rend une durée lisible : « 850 ms », « 42 s », « 3 min 12 s ».
func FormatDuration(d time.Duration) string {
	switch {
	case d < time.Second:
		return fmt.Sprintf("%d ms", d.Milliseconds())
	case d < time.Minute:
		return fmt.Sprintf("%d s", int(d.Round(time.Second).Seconds()))
	default:
		d = d.Round(time.Second)
		m := int(d.Minutes())
		s := int(d.Seconds()) - 60*m
		if s == 0 {
			return fmt.Sprintf("%d min", m)
		}
		return fmt.Sprintf("%d min %d s", m, s)
	}
}
