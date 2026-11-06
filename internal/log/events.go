// Package log fournit la journalisation de la Bigbox, sur log/slog.
//
// Deux sorties alimentées par les mêmes événements :
//   - la console, pour l'humain : arbre « feature › étape » avec statut et durée ;
//   - le journal JSONL, pour le diagnostic : toujours au niveau debug, une ligne par événement,
//     chaque commande externe avec argv, durée, code, stdout et stderr.
//
// Les valeurs sensibles sont masquées dans les deux sorties (Redactor).
package log

// Événements normalisés : le message d'un enregistrement slog est le nom de l'événement.
// La console et les tests s'appuient sur ces événements, jamais sur du texte libre.
const (
	EvRunStart     = "run.start"
	EvRunEnd       = "run.end"
	EvFeatureStart = "feature.start"
	EvFeatureEnd   = "feature.end"
	EvStepStart    = "step.start"
	EvStepEnd      = "step.end"
	EvCmdExec      = "cmd.exec"
	EvCmdExit      = "cmd.exit"
	EvSudo         = "sudo"
)

// Attributs stables des événements.
const (
	KeyRunID    = "run_id"
	KeyCommand  = "command"
	KeyFeature  = "feature"
	KeyStep     = "step"
	KeyLabel    = "label"
	KeyStatus   = "status"
	KeyDuration = "duration"
	KeyArgv     = "argv"
	KeyDir      = "dir"
	KeyExitCode = "exit_code"
	KeyStdout   = "stdout"
	KeyStderr   = "stderr"
	KeyError    = "error"
	KeyVersion  = "version"
	KeyReasons  = "reasons"
)

// Status d'une étape ou d'une feature.
type Status string

// Statuts affichés par la console et le récapitulatif.
const (
	StatusOK      Status = "ok"      // rien à faire, conforme
	StatusChanged Status = "modifié" // une modification a été appliquée
	StatusSkipped Status = "ignoré"  // non exécutée (dépendance en échec, interruption, préexistant)
	StatusFailed  Status = "échec"
)
