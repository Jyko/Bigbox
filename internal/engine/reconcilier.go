package engine

import (
	"context"
	"fmt"
	"log/slog"
)

type Reconciler struct {
	log      *slog.Logger
	registry *Registry
}

func NewReconciler(registry *Registry) *Reconciler {
	return &Reconciler{
		log:      slog.With("component", "Reconciler"),
		registry: registry,
	}
}

func (r *Reconciler) Reconcile(ctx context.Context, intents []Intent) (*ReconciliationResult, error) {

	plan, err := r.generatePlan(ctx, intents)
	if err != nil {
		return nil, err
	}

	if err = r.resolvePlan(ctx, plan); err != nil {
		return nil, err
	}

	return nil, nil
}

func (r *Reconciler) generatePlan(ctx context.Context, intents []Intent) (*Plan, error) {

	var operations []Operation

	for _, intent := range intents {

		var modulesName []string

		// Aucun modules fournis -> Tous les modules enregistrés
		if len(intent.ModulesName) == 0 {
			modulesName = r.registry.Keys()
		} else {
			modulesName = intent.ModulesName
		}

		for _, moduleName := range modulesName {

			// TODO: Gérer les modules inexistants ou invalides
			m := r.registry.Lookup(moduleName)

			// Déterminer le(s) opération(s)
			// POC -> 1 ACTION = 1 OPERATION
			// TODO : Gérer la state machine (UNINSTALLED -> INSTALLED -> STARTED -> STOPPED -> INSTALLED/UNINSTALLED)
			var ot OperationType
			switch intent.Action {
			case ActionInstall:
				ot = InstallOperation
			case ActionUninstall:
				ot = UninstallOperation
			default:
				return nil, fmt.Errorf("unsupported action %s", intent.Action)
			}

			operations = append(operations, Operation{
				Module:        m,
				OperationType: ot,
			})
		}
	}

	return &Plan{Operations: operations}, nil
}

func (r *Reconciler) resolvePlan(ctx context.Context, plan *Plan) error {

	// Nous exécutons chaque opération dans l'ordre fourni par le plan de réconciliation.
	// La logique de réconciliation d'état est ainsi encapsulé dans le générateur de plan, pas durant l'exécution des opérations.
	for _, operation := range plan.Operations {

		m := operation.Module
		mi := m.GetInfos()

		ms, err := m.GetState(ctx)
		if err != nil {
			return err
			return fmt.Errorf("failed to get module %s current state : %w", m.GetInfos().Name, err)
		}

		switch operation.OperationType {
		case InstallOperation:
			if !ms.Installed && mi.Installable {
				if err := m.Install(ctx); err != nil {
					return fmt.Errorf("failed to install module %s : %w", m.GetInfos().Name, err)
				}
			} else {
				r.log.Warn("module %s install has been skipped", m.GetInfos().Name)
			}
		case UninstallOperation:
			if ms.Installed && mi.Installable {
				if err := m.Uninstall(ctx); err != nil {
					return fmt.Errorf("failed to uninstall module %s : %w", m.GetInfos().Name, err)
				}
			} else {
				r.log.Warn("module %s uninstall has been skipped", m.GetInfos().Name)
			}
		case StartOperation:
			// TODO : A implémenter
			return fmt.Errorf("%s operation not yet implemented", operation.OperationType)

		case StopOperation:
			// TODO : A implémenter
			return fmt.Errorf("%s operation not yet implemented", operation.OperationType)

		default:
			return fmt.Errorf("invalid operation type, %v", operation.OperationType)
		}

	}

	return nil
}

type ReconciliationResult struct{}
