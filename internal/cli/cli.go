// Package cli définit les commandes de la Bigbox (cobra) et l'orchestration d'une exécution :
// environnement, journal, logger, Runner, registre, réconciliation, rendu et code de sortie.
package cli

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/Jyko/Bigbox/internal/env"
	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/feature"
	"github.com/Jyko/Bigbox/internal/log"
	"github.com/Jyko/Bigbox/internal/reconcile"
	"github.com/Jyko/Bigbox/internal/run"
	"github.com/Jyko/Bigbox/internal/spec"
	"github.com/Jyko/Bigbox/internal/state"
)

// Build décrit la version du binaire (renseignée par -ldflags).
type Build struct {
	Version, Commit, Date string
}

// App porte les entrées/sorties et les options globales d'une exécution.
type App struct {
	Build    Build
	Stdin    io.Reader
	Stdout   io.Writer
	Stderr   io.Writer
	Getenv   func(string) string
	Root     string // racine des fichiers système lus (tests ; "" : /)
	StdinTTY bool   // confirmation et mot de passe sudo possibles
	ErrTTY   bool   // console interactive (couleurs, ligne d'étape réécrite)
	// Features construit les features disponibles (features.All en production).
	Features func(getenv func(string) string) []feature.Feature

	verbose, quiet, yes bool
	config, output      string
	ran                 bool // une commande a démarré (sinon : erreur d'usage de cobra)
}

// rendered signale une erreur déjà affichée (seul le code de sortie reste à calculer).
type rendered struct{ error }

func (r rendered) Unwrap() error { return r.error }

// Run exécute la ligne de commande et renvoie le code de sortie.
func (a *App) Run(ctx context.Context, args []string) int {
	root := a.root()
	root.SetArgs(args)
	root.SetIn(a.Stdin)
	root.SetOut(a.Stdout)
	root.SetErr(a.Stderr)
	err := root.ExecuteContext(ctx)
	if err == nil {
		return errs.ExitOK
	}
	var te *errs.Error
	var drift *errs.DriftError
	if !a.ran && !errors.As(err, &te) && !errors.As(err, &drift) {
		err = &errs.Error{Kind: errs.Usage, Op: "ligne de commande invalide", Cause: err, Hint: "`bigbox --help` liste les commandes et options"}
	}
	var r rendered
	if !errors.As(err, &r) && !errors.As(err, &drift) {
		fmt.Fprintln(a.Stderr)
		errs.Render(a.Stderr, err, errs.RenderOptions{})
	}
	return errs.ExitCode(err)
}

const exitCodesHelp = `Codes de sortie :
  0    succès (pour status : aucune dérive)
  1    échec d'au moins une étape d'apply
  2    usage incorrect ou bigbox.yaml invalide
  3    dérive détectée (status) ou changements en attente (plan --detailed-exitcode)
  4    précondition non remplie : OS non supporté, sudo refusé, port occupé, autre exécution en cours
  130  interruption (Ctrl-C) : l'étape en cours est annulée proprement`

func (a *App) root() *cobra.Command {
	root := &cobra.Command{
		Use:   "bigbox",
		Short: "Environnement de développement local sur Ubuntu, décrit dans bigbox.yaml",
		Long: `La Bigbox installe et pilote un environnement de développement local (Docker, k3s,
services, outillage du shell) sur Ubuntu 24.04 ou plus récent, sur un poste, dans WSL2 ou en
conteneur.

Décrivez ce que vous voulez dans ~/.config/bigbox/bigbox.yaml, vérifiez l'écart avec
« bigbox plan », puis appliquez-le avec « bigbox apply ».

` + exitCodesHelp,
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			a.ran = true
			if a.verbose && a.quiet {
				return &errs.Error{Kind: errs.Usage, Op: "-v et -q sont incompatibles"}
			}
			if a.output != "text" && a.output != "json" {
				return &errs.Error{Kind: errs.Usage, Op: fmt.Sprintf("--output = %q invalide (admis : text, json)", a.output)}
			}
			return nil
		},
	}
	root.SetFlagErrorFunc(func(_ *cobra.Command, err error) error {
		return &errs.Error{Kind: errs.Usage, Op: "option invalide", Cause: err, Hint: "`bigbox --help` liste les options"}
	})
	pf := root.PersistentFlags()
	pf.BoolVarP(&a.verbose, "verbose", "v", false, "affiche le détail (commandes lancées, debug)")
	pf.BoolVarP(&a.quiet, "quiet", "q", false, "n'affiche que les erreurs")
	pf.BoolVarP(&a.yes, "yes", "y", false, "applique sans demander de confirmation")
	pf.StringVar(&a.config, "config", "", "chemin de bigbox.yaml (défaut : ~/.config/bigbox/bigbox.yaml)")
	pf.StringVarP(&a.output, "output", "o", "text", "format de sortie de plan et status : text ou json")

	root.AddCommand(a.versionCmd(), a.planCmd(), a.applyCmd(), a.statusCmd(), a.logsCmd())
	root.AddCommand(a.stateCmd("enable", "Active une feature (et ses dépendances), puis applique", spec.Running))
	root.AddCommand(a.stateCmd("disable", "Retire une feature (et celles qui en dépendent), puis applique", spec.Absent))
	root.AddCommand(a.stateCmd("start", "Démarre une feature (et ses dépendances), puis applique", spec.Running))
	root.AddCommand(a.stateCmd("stop", "Arrête une feature (et celles qui en dépendent), puis applique", spec.Stopped))
	return root
}

// ---------------------------------------------------------------------------------------------
// Session : tout ce dont une commande a besoin
// ---------------------------------------------------------------------------------------------

type session struct {
	app      *App
	command  string
	env      *env.Env
	red      *log.Redactor
	journal  *log.Journal
	logger   *slog.Logger
	features *feature.Registry
	sudo     *run.Sudo
	runner   *run.Exec
	start    time.Time
}

func (a *App) open(command string) (*session, error) {
	e, err := env.Source{Root: a.Root, Getenv: a.Getenv, Arch: runtime.GOARCH}.Detect()
	if err != nil {
		return nil, err
	}
	if a.config != "" {
		e.Paths.Config = a.config
	}
	s := &session{app: a, command: command, env: e, red: log.NewRedactor(), start: time.Now()}

	runID := log.NewRunID()
	if j, err := log.OpenJournal(e.Paths.LogDir, command, runID, s.start); err == nil {
		s.journal = j
	} else {
		fmt.Fprintf(a.Stderr, "⚠ journal indisponible : %v\n", err)
	}
	level := slog.LevelInfo
	switch {
	case a.verbose:
		level = slog.LevelDebug
	case a.quiet:
		level = slog.LevelError
	}
	opt := log.Options{
		Console: a.Stderr, ConsoleLevel: level, RunID: runID, Redactor: s.red,
		Color:       a.ErrTTY && a.Getenv("NO_COLOR") == "",
		Interactive: a.ErrTTY && !a.verbose,
	}
	if s.journal != nil {
		opt.Journal = s.journal
	}
	s.logger = log.New(opt)
	s.logger.Debug(log.EvRunStart, log.KeyCommand, command, log.KeyVersion, a.Build.Version,
		"context", e.Context(), "config", e.Paths.Config)

	s.features, err = feature.NewRegistry(a.Features(a.Getenv)...)
	if err != nil {
		s.close(err)
		return nil, err
	}
	s.sudo = &run.Sudo{Logger: s.logger, Interactive: a.StdinTTY}
	s.runner = &run.Exec{Logger: s.logger, Redactor: s.red, Sudo: s.sudo}
	return s, nil
}

func (s *session) close(err error) {
	if s == nil {
		return
	}
	s.logger.Debug(log.EvRunEnd, log.KeyCommand, s.command, log.KeyDuration, time.Since(s.start),
		log.KeyExitCode, errs.ExitCode(err), log.KeyError, errString(err))
	_ = s.journal.Close()
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func (s *session) journalRef() errs.JournalRef {
	if s.journal == nil {
		return errs.JournalRef{}
	}
	return errs.JournalRef{Path: tilde(s.journal.Path, s.env.Home), RunID: s.journal.RunID}
}

func tilde(p, home string) string {
	if home != "" && strings.HasPrefix(p, home+"/") {
		return "~" + strings.TrimPrefix(p, home)
	}
	return p
}

func (s *session) reconciler(reg *state.Registry) *reconcile.Reconciler {
	return &reconcile.Reconciler{Features: s.features, Env: &feature.Env{
		Sys: s.env, Run: s.runner, State: reg, Log: s.logger, Redactor: s.red,
	}}
}

func (s *session) loadSpec() (*spec.Spec, error) {
	sp, err := spec.Load(s.env.Paths.Config, s.features)
	if err != nil {
		return nil, err
	}
	if !sp.Exists {
		s.logger.Info(fmt.Sprintf("%s absent : valeurs par défaut (profil minimal, aucune feature)", tilde(sp.Path, s.env.Home)))
	}
	return sp, nil
}

// withSession ouvre une session, exécute fn, et rend l'erreur avec la référence au journal.
func (a *App) withSession(command string, fn func(*session) error) error {
	s, err := a.open(command)
	if err != nil {
		return err
	}
	err = fn(s)
	s.close(err)
	var r rendered
	var drift *errs.DriftError
	if err != nil && !errors.As(err, &r) && !errors.As(err, &drift) {
		fmt.Fprintln(a.Stderr)
		errs.Render(a.Stderr, err, errs.RenderOptions{Journal: s.journalRef()})
		return rendered{err}
	}
	return err
}

// ---------------------------------------------------------------------------------------------
// Commandes
// ---------------------------------------------------------------------------------------------

func (a *App) versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Affiche la version de la Bigbox",
		Args:  noArgs,
		RunE: func(*cobra.Command, []string) error {
			fmt.Fprintf(a.Stdout, "bigbox %s\n", a.Build.Version)
			fmt.Fprintf(a.Stdout, "  commit   : %s\n  construit : %s\n  go       : %s %s/%s\n",
				orDash(a.Build.Commit), orDash(a.Build.Date), runtime.Version(), runtime.GOOS, runtime.GOARCH)
			return nil
		},
	}
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func (a *App) planCmd() *cobra.Command {
	var detailed bool
	c := &cobra.Command{
		Use:   "plan",
		Short: "Affiche l'écart entre bigbox.yaml et la machine, sans rien modifier",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.withSession("plan", func(s *session) error {
				p, err := s.plan(cmd.Context())
				if err != nil {
					return err
				}
				if a.output == "json" {
					if err := reconcile.WriteJSON(a.Stdout, p); err != nil {
						return err
					}
				} else {
					reconcile.RenderPlan(a.Stdout, p)
				}
				if detailed && p.Changes() > 0 {
					return &errs.DriftError{Changes: p.Changes()}
				}
				return nil
			})
		},
	}
	c.Flags().BoolVar(&detailed, "detailed-exitcode", false, "code 3 si des changements sont en attente")
	return c
}

func (s *session) plan(ctx context.Context) (*reconcile.Plan, error) {
	sp, err := s.loadSpec()
	if err != nil {
		return nil, err
	}
	reg, err := state.Load(s.env.Paths.Registry)
	if err != nil {
		return nil, err
	}
	return s.reconciler(reg).Plan(ctx, sp)
}

func (a *App) statusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Affiche l'état observé de chaque feature et la dérive (code 3 si dérive)",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.withSession("status", func(s *session) error {
				p, err := s.plan(cmd.Context())
				if err != nil {
					return err
				}
				if a.output == "json" {
					if err := reconcile.WriteJSON(a.Stdout, p); err != nil {
						return err
					}
				} else {
					fmt.Fprintf(a.Stdout, "Bigbox %s sur %s\n\n", a.Build.Version, s.env.Context())
					reconcile.RenderStatus(a.Stdout, p, s.features)
				}
				if p.Changes() > 0 {
					return &errs.DriftError{Changes: p.Changes()}
				}
				return nil
			})
		},
	}
}

func (a *App) applyCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "apply",
		Short: "Applique l'écart entre bigbox.yaml et la machine",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.withSession("apply", func(s *session) error { return s.apply(cmd.Context(), nil) })
		},
	}
}

// apply verrouille, planifie, confirme, applique et rend le récapitulatif. edit, s'il est
// fourni, modifie bigbox.yaml sous le verrou avant le plan (enable, disable, start, stop).
func (s *session) apply(ctx context.Context, edit func() error) error {
	a := s.app
	if err := s.env.CheckSupported(); err != nil {
		return err
	}
	lock, err := state.Acquire(s.env.Paths.Lock)
	if err != nil {
		return err
	}
	defer func() { _ = lock.Release() }()

	if edit != nil {
		if err := edit(); err != nil {
			return err
		}
	}
	sp, err := s.loadSpec()
	if err != nil {
		return err
	}
	reg, err := state.Load(s.env.Paths.Registry)
	if err != nil {
		return err
	}
	rec := s.reconciler(reg)
	p, err := rec.Plan(ctx, sp)
	if err != nil {
		return err
	}
	if p.Changes() == 0 {
		fmt.Fprintln(a.Stdout, "Rien à faire : la machine est conforme à bigbox.yaml.")
		return nil
	}
	reconcile.RenderPlan(a.Stdout, p)
	if ok, err := a.confirm(); err != nil || !ok {
		if err == nil {
			fmt.Fprintln(a.Stdout, "Annulé : aucune modification.")
		}
		return err
	}
	fmt.Fprintln(a.Stdout)

	rep, applyErr := rec.Apply(ctx, p, s.sudo)
	if err := reg.Save(); err != nil {
		applyErr = errors.Join(applyErr, err)
	}

	// Détail de chaque échec, puis récapitulatif
	failed := rep.Failed()
	for _, f := range failed {
		fmt.Fprintln(a.Stderr)
		errs.Render(a.Stderr, f.Err, errs.RenderOptions{Elapsed: f.Duration, Journal: s.journalRef()})
	}
	// Erreurs hors étapes (sudo refusé, registre non sauvegardé…)
	var other []error
	for _, e := range unjoin(applyErr) {
		if !errors.Is(e, context.Canceled) && !isStepError(e, failed) {
			other = append(other, e)
		}
	}
	for _, e := range other {
		fmt.Fprintln(a.Stderr)
		errs.Render(a.Stderr, e, errs.RenderOptions{Journal: s.journalRef()})
	}
	if ctx.Err() != nil {
		fmt.Fprintln(a.Stderr, "\nInterrompu : l'étape en cours a été annulée ; relancez `bigbox apply` pour terminer.")
	}

	sum := log.Summary{Command: "apply", Duration: rep.Duration, Counts: rep.Counts(), Journal: s.journalRef()}
	for _, f := range failed {
		sum.Failures = append(sum.Failures, f.Feature+" › "+f.Step.Label)
	}
	fmt.Fprintln(a.Stdout)
	log.RenderSummary(a.Stdout, sum)

	if applyErr != nil {
		return rendered{applyErr}
	}
	return nil
}

func unjoin(err error) []error {
	if err == nil {
		return nil
	}
	if j, ok := err.(interface{ Unwrap() []error }); ok {
		var out []error
		for _, e := range j.Unwrap() {
			out = append(out, unjoin(e)...)
		}
		return out
	}
	return []error{err}
}

func isStepError(e error, failed []reconcile.StepResult) bool {
	for _, f := range failed {
		if errors.Is(e, f.Err) {
			return true
		}
	}
	return false
}

func (a *App) confirm() (bool, error) {
	if a.yes {
		return true, nil
	}
	if !a.StdinTTY {
		return false, &errs.Error{Kind: errs.Usage, Op: "confirmation impossible sans terminal",
			Hint: "relancez avec --yes pour appliquer sans confirmation"}
	}
	fmt.Fprint(a.Stdout, "\nAppliquer ces changements ? [o/N] ")
	line, err := bufio.NewReader(a.Stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return false, err
	}
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "o", "oui", "y", "yes":
		return true, nil
	}
	return false, nil
}

// stateCmd : enable, disable, start, stop. Modifie bigbox.yaml (après validation du résultat)
// puis applique.
func (a *App) stateCmd(name, short string, target spec.State) *cobra.Command {
	return &cobra.Command{
		Use:   name + " <feature> [feature…]",
		Short: short,
		Args: func(_ *cobra.Command, args []string) error {
			if len(args) == 0 {
				return &errs.Error{Kind: errs.Usage, Op: name + " : au moins une feature est attendue",
					Hint: "ex. `bigbox " + name + " pg` ; `bigbox status` liste les features"}
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return a.withSession(name, func(s *session) error {
				return s.apply(cmd.Context(), func() error { return s.editStates(name, args, target) })
			})
		},
	}
}

// editStates calcule les nouveaux états : les dépendances suivent pour enable/start, les
// dépendants pour disable/stop. Le fichier n'est écrit que si le résultat est valide.
func (s *session) editStates(verb string, names []string, target spec.State) error {
	var unknown []string
	for _, n := range names {
		info, ok := s.features.Info(n)
		if !ok {
			unknown = append(unknown, n)
			continue
		}
		if target == spec.Stopped && !info.Stoppable {
			return &errs.Error{Kind: errs.Usage, Op: n + " ne s'arrête pas", Hint: "utilisez `bigbox disable " + n + "` pour la retirer"}
		}
	}
	if len(unknown) > 0 {
		avail := strings.Join(s.features.Names(), ", ")
		if avail == "" {
			avail = "aucune pour l'instant, la migration vers Go est en cours"
		}
		return &errs.Error{Kind: errs.Usage, Op: "feature inconnue : " + strings.Join(unknown, ", "),
			Hint: "features disponibles : " + avail}
	}

	cur, err := spec.Load(s.env.Paths.Config, s.features)
	if err != nil {
		return err
	}
	changes := map[string]spec.State{}
	for _, n := range names {
		changes[n] = target
	}
	switch verb {
	case "disable", "stop":
		for _, n := range s.features.Dependents(names...) {
			if f := cur.Features[n]; f != nil && f.State != spec.Absent && (target == spec.Absent || f.State == spec.Running) {
				changes[n] = target
			}
		}
	case "start":
		for _, n := range s.features.Requires(names...) {
			if f := cur.Features[n]; f != nil && f.State == spec.Stopped {
				changes[n] = spec.Running
			}
		}
	}

	data, err := spec.WithStates(cur.Path, changes)
	if err != nil {
		return err
	}
	next, err := spec.Parse(cur.Path, data, s.features)
	if err != nil {
		return err
	}
	if _, err := s.reconciler(nil).Desired(next); err != nil {
		return err
	}
	if err := spec.Write(cur.Path, data); err != nil {
		return err
	}
	var desc []string
	for _, n := range s.features.Sort(keys(changes), false) {
		desc = append(desc, n+" → "+string(changes[n]))
	}
	s.logger.Info(tilde(cur.Path, s.env.Home) + " mis à jour : " + strings.Join(desc, ", "))
	return nil
}

func keys(m map[string]spec.State) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func noArgs(cmd *cobra.Command, args []string) error {
	if len(args) > 0 {
		return &errs.Error{Kind: errs.Usage, Op: fmt.Sprintf("%s n'accepte aucun argument (reçu : %s)", cmd.Name(), strings.Join(args, " "))}
	}
	return nil
}

// Main est le point d'entrée de cmd/bigbox.
func Main(ctx context.Context, b Build, fs func(func(string) string) []feature.Feature) int {
	a := &App{
		Build: b, Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr, Getenv: os.Getenv,
		StdinTTY: isTTY(os.Stdin), ErrTTY: isTTY(os.Stderr), Features: fs,
	}
	return a.Run(ctx, os.Args[1:])
}

func isTTY(f *os.File) bool {
	info, err := f.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}
