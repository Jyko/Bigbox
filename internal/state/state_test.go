package state

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
)

func TestRegistreAllerRetour(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state", "owned.json")
	r, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	r.now = func() time.Time { return time.Date(2026, 11, 6, 14, 0, 0, 0, time.UTC) }
	r.Mark(KindApt, "jq", "core")
	r.Mark(KindApt, "jq", "autre") // déjà possédé : la feature d'origine est conservée
	r.Mark(KindMark, "k3s", "k3s")
	if err := r.Save(); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0o600 {
		t.Errorf("droits : %v", info.Mode().Perm())
	}

	r2, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if !r2.Owned(KindApt, "jq") || !r2.Owned(KindMark, "k3s") || r2.Owned(KindApt, "htop") {
		t.Errorf("contenu inattendu : %v", r2.Items(""))
	}
	if it := r2.Items(KindApt); len(it) != 1 || it[0].Feature != "core" {
		t.Errorf("items apt : %v", it)
	}
	r2.Unmark(KindApt, "jq")
	if r2.Owned(KindApt, "jq") {
		t.Error("jq doit être retiré")
	}
}

func TestSaveAtomique(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "owned.json")
	r, _ := Load(path)
	r.Mark(KindApt, "jq", "core")
	if err := r.Save(); err != nil {
		t.Fatal(err)
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 {
		t.Errorf("aucun fichier temporaire ne doit rester : %v", entries)
	}
	// Un fichier corrompu est signalé, jamais écrasé en silence
	if err := os.WriteFile(path, []byte("{tronqué"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); errs.KindOf(err) != errs.Config {
		t.Errorf("Config attendu pour un registre illisible : %v", err)
	}
}

func TestFormatFutur(t *testing.T) {
	path := filepath.Join(t.TempDir(), "owned.json")
	_ = os.WriteFile(path, []byte(`{"version": 99, "items": []}`), 0o600)
	if _, err := Load(path); errs.KindOf(err) != errs.Precondition {
		t.Errorf("Precondition attendue : %v", err)
	}
}

func TestLectureFormatBash(t *testing.T) {
	path := filepath.Join(t.TempDir(), "owned")
	content := strings.Join([]string{
		"apt:jq", "apt:yq", "file:/etc/apt/sources.list.d/kubernetes.list", "group:docker",
		"k3s", "k8s-namespace:bigbox", "", "apt:jq", "file:/home/u/.local/bin/lazygit",
	}, "\n")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	items, err := ReadBash(path)
	if err != nil {
		t.Fatal(err)
	}
	var keys []string
	for _, it := range items {
		keys = append(keys, it.Key())
	}
	want := "apt:jq apt:yq file:/etc/apt/sources.list.d/kubernetes.list group:docker k3s k8s-namespace:bigbox file:/home/u/.local/bin/lazygit"
	if strings.Join(keys, " ") != want {
		t.Errorf("clés relues :\n %s\nattendu\n %s", strings.Join(keys, " "), want)
	}
	if items[4].Kind != KindMark || items[5].Kind != "k8s-namespace" {
		t.Errorf("natures : %+v %+v", items[4], items[5])
	}

	// Conversion sans perte vers owned.json
	r, _ := Load(filepath.Join(t.TempDir(), "owned.json"))
	r.Import(items)
	if len(r.Items("")) != 7 {
		t.Errorf("%d éléments importés, attendu 7", len(r.Items("")))
	}
	if missing, _ := ReadBash(filepath.Join(t.TempDir(), "absent")); missing != nil {
		t.Error("registre Bash absent : aucun élément")
	}
}

func TestVerrou(t *testing.T) {
	path := filepath.Join(t.TempDir(), "lock")
	l1, err := Acquire(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Acquire(path); errs.KindOf(err) != errs.Conflict {
		t.Errorf("second verrou : Conflict attendu, obtenu %v", err)
	}
	if err := l1.Release(); err != nil {
		t.Fatal(err)
	}
	l2, err := Acquire(path)
	if err != nil {
		t.Fatalf("verrou libéré : %v", err)
	}
	_ = l2.Release()
}
