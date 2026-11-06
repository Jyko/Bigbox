// Package testutil regroupe les aides de test partagées (fichiers golden).
package testutil

import (
	"flag"
	"os"
	"path/filepath"
	"testing"
)

var update = flag.Bool("update", false, "réécrire les fichiers golden de testdata/")

// Golden compare got au fichier testdata/<name>.golden ; `go test ./... -update` le réécrit.
func Golden(t *testing.T, name, got string) {
	t.Helper()
	path := filepath.Join("testdata", name+".golden")
	if *update {
		if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(got), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("golden %s absent (lancer avec -update) : %v", path, err)
	}
	if string(want) != got {
		t.Errorf("sortie différente de %s\n--- obtenu ---\n%s\n--- attendu ---\n%s", path, got, want)
	}
}
