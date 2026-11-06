package reconcile

import (
	"context"
	"errors"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/feature"
	"github.com/Jyko/Bigbox/internal/log"
)

// Elevator obtient les droits root avant les étapes privilégiées (run.Sudo en production).
type Elevator interface {
	Ensure(ctx context.Context, reasons []string) error
}

// StepResult est le résultat d'une étape.
type StepResult struct {
	Feature  string
	Step     feature.Step
	Status   log.Status
	Duration time.Duration
	Reason   string // pourquoi l'étape a été ignorée
	Err      error  // erreur typée, située dans la feature et l'étape
}

// Report est le compte rendu d'un apply.
type Report struct {
	Steps      []StepResult
	Conformant []string // features sans aucune étape à exécuter
	Duration   time.Duration
}

// Counts compte les étapes par statut ; une feature conforme compte pour un « ok ».
func (r *Report) Counts() map[log.Status]int {
	c := map[log.Status]int{log.StatusOK: len(r.Conformant)}
	for _, s := range r.Steps {
		c[s.Status]++
	}
	return c
}

// Failed renvoie les étapes en échec.
func (r *Report) Failed() []StepResult {
	var out []StepResult
	for _, s := range r.Steps {
		if s.Status == log.StatusFailed {
			out = append(out, s)
		}
	}
	return out
}

// Apply exécute le plan.
//
//   - Convergence : une étape en échec arrête les étapes suivantes de sa feature, et les
//     features qui en dépendent sont ignorées ; les features indépendantes continuent.
//   - Suppression (best effort) : chaque étape est tentée même si une précédente échoue, sauf
//     dépendance d'ordre (pg doit être retirée avant cnpg : si pg échoue, cnpg est conservée).
//   - Interruption (Ctrl-C) : l'étape en cours est annulée, les suivantes ignorées ; l'erreur
//     renvoyée contient context.Canceled (code 130).
//
// L'erreur renvoyée regroupe toutes les erreurs (errors.Join) ; le Report porte le détail.
func (r *Reconciler) Apply(ctx context.Context, p *Plan, elev Elevator) (*Report, error) {
	start := time.Now()
	rep := &Report{}
	defer func() { rep.Duration = time.Since(start) }()
	logger := r.Env.Log
	if logger == nil {
		logger = log.Discard()
	}

	if priv := p.PrivilegedSteps(); len(priv) > 0 && elev != nil {
		if err := elev.Ensure(ctx, priv); err != nil {
			return rep, err
		}
	}

	var all []error
	failed := map[string]bool{}
	for _, fp := range p.Features {
		if fp.Changes() == 0 {
			rep.Conformant = append(rep.Conformant, fp.Name)
			logger.Debug(log.EvFeatureEnd, log.KeyFeature, fp.Name, log.KeyStatus, string(log.StatusOK))
			continue
		}
		f, _ := r.Features.Get(fp.Name)
		blocker := r.blocker(fp, failed)

		logger.Info(log.EvFeatureStart, log.KeyFeature, fp.Name)
		featureFailed := false
		for _, st := range fp.Steps {
			if st.Action == feature.Keep {
				continue
			}
			reason := ""
			switch {
			case ctx.Err() != nil:
				reason = "exécution interrompue"
			case blocker != "" && fp.Phase == PhaseConverge:
				reason = "dépendance " + blocker + " en échec"
			case blocker != "":
				reason = blocker + " n'a pas pu être retirée avant"
			case featureFailed && fp.Phase == PhaseConverge:
				reason = "étape précédente en échec"
			}
			if reason != "" {
				rep.Steps = append(rep.Steps, StepResult{Feature: fp.Name, Step: st, Status: log.StatusSkipped, Reason: reason})
				logger.Info(log.EvStepEnd, log.KeyFeature, fp.Name, log.KeyStep, st.ID, log.KeyLabel, st.Label,
					log.KeyStatus, string(log.StatusSkipped), log.KeyError, reason)
				continue
			}

			res := r.runStep(ctx, f, fp.Name, st)
			rep.Steps = append(rep.Steps, res)
			if res.Status == log.StatusFailed {
				featureFailed = true
				all = append(all, res.Err)
			}
		}
		status := log.StatusChanged
		if featureFailed {
			failed[fp.Name] = true
			status = log.StatusFailed
		}
		logger.Info(log.EvFeatureEnd, log.KeyFeature, fp.Name, log.KeyStatus, string(status))
	}
	if ctx.Err() != nil && !errors.Is(errors.Join(all...), context.Canceled) {
		all = append(all, ctx.Err())
	}
	return rep, errors.Join(all...)
}

func (r *Reconciler) runStep(ctx context.Context, f feature.Feature, name string, st feature.Step) StepResult {
	logger := r.Env.Log
	if logger == nil {
		logger = log.Discard()
	}
	timeout := st.Timeout
	if timeout <= 0 {
		timeout = feature.DefaultStepTimeout
	}
	logger.Info(log.EvStepStart, log.KeyFeature, name, log.KeyStep, st.ID, log.KeyLabel, st.Label)
	sctx, cancel := context.WithTimeout(ctx, timeout)
	t0 := time.Now()
	err := safeApply(sctx, f, r.Env, st)
	cancel()
	res := StepResult{Feature: name, Step: st, Duration: time.Since(t0), Status: log.StatusChanged}

	if err != nil {
		res.Status = log.StatusFailed
		if ctx.Err() == nil && errors.Is(err, context.DeadlineExceeded) {
			e := &errs.Error{Kind: errs.Environment, Op: "délai de " + errs.FormatDuration(timeout) + " dépassé", Cause: err,
				Hint: "consultez le journal pour voir où l'étape s'est arrêtée, puis relancez `bigbox apply`"}
			err = e
		}
		res.Err = errs.WithStep(err, name, st.Label)
		logger.Info(log.EvStepEnd, log.KeyFeature, name, log.KeyStep, st.ID, log.KeyLabel, st.Label,
			log.KeyStatus, string(log.StatusFailed), log.KeyDuration, res.Duration, log.KeyError, res.Err)
		return res
	}
	logger.Info(log.EvStepEnd, log.KeyFeature, name, log.KeyStep, st.ID, log.KeyLabel, st.Label,
		log.KeyStatus, string(log.StatusChanged), log.KeyDuration, res.Duration)
	return res
}

// safeApply transforme une panique de feature en erreur interne : l'exécution continue et le
// registre est sauvegardé.
func safeApply(ctx context.Context, f feature.Feature, e *feature.Env, st feature.Step) (err error) {
	defer func() {
		if p := recover(); p != nil {
			err = &errs.Error{Kind: errs.Internal, Op: "panique dans la feature", Cause: panicError{p}}
		}
	}()
	return f.Apply(ctx, e, st)
}

type panicError struct{ v any }

func (p panicError) Error() string { return "panic: " + toString(p.v) }

func toString(v any) string {
	if e, ok := v.(error); ok {
		return e.Error()
	}
	if s, ok := v.(string); ok {
		return s
	}
	return "valeur inattendue"
}

// blocker renvoie une feature en échec qui empêche celle-ci de s'exécuter : une dépendance en
// convergence, un dépendant en suppression.
func (r *Reconciler) blocker(fp *FeaturePlan, failed map[string]bool) string {
	var related []string
	if fp.Phase == PhaseConverge {
		related = r.Features.Requires(fp.Name)
	} else {
		related = r.Features.Dependents(fp.Name)
	}
	for _, n := range related {
		if n != fp.Name && failed[n] {
			return n
		}
	}
	return ""
}
