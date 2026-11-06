// Package features assemble les features disponibles dans ce binaire.
//
// Pendant la migration, le binaire Go ne connaît que les features déjà portées ; les autres
// restent assurées par la Bigbox Bash.
package features

import (
	"github.com/Jyko/Bigbox/features/essai"
	"github.com/Jyko/Bigbox/internal/feature"
)

// All renvoie les features disponibles. getenv permet d'activer les features d'essai.
func All(getenv func(string) string) []feature.Feature {
	var fs []feature.Feature
	if getenv(essai.EnvVar) == "1" {
		fs = append(fs, essai.Feature{})
	}
	return fs
}
