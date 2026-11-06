package log

import (
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
)

// Summary est le récapitulatif de fin d'exécution.
type Summary struct {
	Command  string          // apply, plan…
	Duration time.Duration   //
	Counts   map[Status]int  // nombre d'étapes par statut
	Failures []string        // « feature › étape » en échec
	NewTools []string        // nouvelles commandes disponibles dans le shell
	Journal  errs.JournalRef //
}

// RenderSummary écrit :
//
//	Bigbox apply terminé en 3 min 12 s : 14 ok, 6 modifiés, 2 ignorés, 1 échec
//	  ✗ sftp › charger les utilisateurs   (voir ci-dessus)
//	Shell : nouvelles commandes kubectl, helm, psql ; lancez `exec bash`
//	Journal : ~/.local/state/bigbox/logs/…-apply.jsonl
func RenderSummary(w io.Writer, s Summary) {
	parts := []string{
		plural(s.Counts[StatusOK], "ok", "ok"),
		plural(s.Counts[StatusChanged], "modifié", "modifiés"),
		plural(s.Counts[StatusSkipped], "ignoré", "ignorés"),
		plural(s.Counts[StatusFailed], "échec", "échecs"),
	}
	fmt.Fprintf(w, "Bigbox %s terminé en %s : %s\n", s.Command, errs.FormatDuration(s.Duration), strings.Join(parts, ", "))
	for _, f := range s.Failures {
		fmt.Fprintf(w, "  ✗ %s   (voir ci-dessus)\n", f)
	}
	if len(s.NewTools) > 0 {
		fmt.Fprintf(w, "Shell : nouvelles commandes %s ; lancez `exec bash`\n", strings.Join(s.NewTools, ", "))
	}
	if s.Journal.Path != "" {
		fmt.Fprintf(w, "Journal : %s\n", s.Journal.Path)
	}
}

func plural(n int, one, many string) string {
	if n > 1 {
		return fmt.Sprintf("%d %s", n, many)
	}
	return fmt.Sprintf("%d %s", n, one)
}
