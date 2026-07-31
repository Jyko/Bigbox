package cli

import (
	"bigard.fr/bigbox/internal/engine"
	"github.com/spf13/cobra"
)

func NewRootCmd(reconciler *engine.Reconciler) *cobra.Command {

	root := &cobra.Command{
		Use: "bigbox",
	}

	root.AddCommand(
		newActionCmd(reconciler, "install", engine.ActionInstall),
		newActionCmd(reconciler, "uninstall", engine.ActionUninstall),
		newActionCmd(reconciler, "start", engine.ActionStart),
		newActionCmd(reconciler, "stop", engine.ActionStop),
		newActionCmd(reconciler, "info", engine.ActionInfo),
		newActionCmd(reconciler, "version", engine.ActionVersion),
	)

	return root
}

func newActionCmd(
	reconciler *engine.Reconciler,
	use string,
	action engine.Action,
) *cobra.Command {

	return &cobra.Command{
		Use:   use + " [modules...]",
		Short: "",
		RunE: func(cmd *cobra.Command, args []string) error {

			ctx := cmd.Context()

			intents := []engine.Intent{
				{
					Action:      action,
					ModulesName: args,
				},
			}

			_, err := reconciler.Reconcile(ctx, intents)
			if err != nil {
				return err
			}

			return nil
		},
	}
}
