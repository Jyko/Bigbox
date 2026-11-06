package cli

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/Jyko/Bigbox/internal/env"
	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/log"
)

func (a *App) logsCmd() *cobra.Command {
	var runID string
	var raw, list bool
	c := &cobra.Command{
		Use:   "logs",
		Short: "Affiche le journal d'une exécution (le dernier par défaut)",
		Long: `Affiche le journal d'une exécution, en version lisible. Le journal JSONL contient chaque
événement au niveau debug, et pour chaque commande externe : argv, durée, code, stdout et stderr.

  bigbox logs              dernier journal
  bigbox logs --run 7f3a   journal d'une exécution (identifiant affiché en cas d'erreur)
  bigbox logs --raw        JSONL brut, à joindre à un rapport de bug
  bigbox logs --list       liste des journaux conservés`,
		Args: noArgs,
		RunE: func(*cobra.Command, []string) error {
			e, err := env.Source{Root: a.Root, Getenv: a.Getenv, Arch: runtime.GOARCH}.Detect()
			if err != nil {
				return err
			}
			names, err := log.List(e.Paths.LogDir)
			if err != nil {
				return err
			}
			if len(names) == 0 {
				return &errs.Error{Kind: errs.Precondition, Op: "aucun journal dans " + tilde(e.Paths.LogDir, e.Home),
					Hint: "les journaux sont créés par plan, apply, status, enable, disable, start et stop"}
			}
			if list {
				for _, n := range names {
					fmt.Fprintf(a.Stdout, "%s  %s\n", firstRunID(filepath.Join(e.Paths.LogDir, n)), n)
				}
				return nil
			}
			name := names[len(names)-1]
			if runID != "" {
				name = ""
				for i := len(names) - 1; i >= 0; i-- {
					if firstRunID(filepath.Join(e.Paths.LogDir, names[i])) == runID {
						name = names[i]
						break
					}
				}
				if name == "" {
					return &errs.Error{Kind: errs.Usage, Op: "aucun journal pour le run " + runID,
						Hint: "`bigbox logs --list` affiche les identifiants disponibles"}
				}
			}
			path := filepath.Join(e.Paths.LogDir, name)
			f, err := os.Open(path)
			if err != nil {
				return errs.Wrap(err, errs.Environment, "lecture de "+path)
			}
			defer func() { _ = f.Close() }()
			if raw {
				_, err = io.Copy(a.Stdout, f)
				return err
			}
			fmt.Fprintf(a.Stdout, "Journal %s\n\n", tilde(path, e.Home))
			return renderJournal(a.Stdout, f)
		},
	}
	c.Flags().StringVar(&runID, "run", "", "identifiant de l'exécution")
	c.Flags().BoolVar(&raw, "raw", false, "JSONL brut")
	c.Flags().BoolVar(&list, "list", false, "liste les journaux conservés")
	c.Flags().Bool("last", true, "dernier journal (par défaut)")
	return c
}

func firstRunID(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return "--------"
	}
	defer func() { _ = f.Close() }()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64<<10), 4<<20)
	if sc.Scan() {
		var rec map[string]any
		if json.Unmarshal(sc.Bytes(), &rec) == nil {
			if id, ok := rec[log.KeyRunID].(string); ok {
				return id
			}
		}
	}
	return "--------"
}

// renderJournal rend le JSONL lisiblement : heure, niveau, événement, attributs utiles ; les
// sorties des commandes sont indentées.
func renderJournal(w io.Writer, r io.Reader) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64<<10), 4<<20)
	skip := map[string]bool{"time": true, "level": true, "msg": true, log.KeyRunID: true,
		log.KeyStdout: true, log.KeyStderr: true}
	for sc.Scan() {
		var rec map[string]any
		if err := json.Unmarshal(sc.Bytes(), &rec); err != nil {
			fmt.Fprintf(w, "(ligne illisible) %s\n", sc.Text())
			continue
		}
		ts := ""
		if t, err := time.Parse(time.RFC3339Nano, fmt.Sprint(rec["time"])); err == nil {
			ts = t.Format("15:04:05.000")
		}
		keys := make([]string, 0, len(rec))
		for k := range rec {
			if !skip[k] {
				keys = append(keys, k)
			}
		}
		sort.Strings(keys)
		var attrs []string
		for _, k := range keys {
			v := rec[k]
			if l, ok := v.([]any); ok {
				parts := make([]string, len(l))
				for i, x := range l {
					parts[i] = fmt.Sprint(x)
				}
				v = errs.ShellJoin(parts)
			}
			if s := fmt.Sprint(v); s != "" {
				attrs = append(attrs, fmt.Sprintf("%s=%s", k, s))
			}
		}
		fmt.Fprintf(w, "%s %-5s %-14s %s\n", ts, rec["level"], rec["msg"], strings.Join(attrs, " "))
		for _, k := range []string{log.KeyStdout, log.KeyStderr} {
			if s, _ := rec[k].(string); strings.TrimSpace(s) != "" {
				fmt.Fprintf(w, "    %s :\n", k)
				for _, l := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
					fmt.Fprintf(w, "      %s\n", l)
				}
			}
		}
	}
	return sc.Err()
}
