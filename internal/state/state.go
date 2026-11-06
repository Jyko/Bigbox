// Package state tient le registre de propriété : ce que la Bigbox a elle-même installé ou créé.
//
// Règle d'or : ne rien retirer que la Bigbox n'ait installé. Le modèle déclaratif dit ce qui
// doit exister ; le registre dit ce que la Bigbox a le droit de retirer (un paquet préexistant,
// ex. htop sur un Ubuntu Desktop, n'est jamais purgé).
package state

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
)

// Version du format de owned.json.
const Version = 1

// Natures d'éléments connues (les marques libres du Bash ont la nature KindMark).
const (
	KindApt   = "apt"
	KindFile  = "file"
	KindGroup = "group"
	KindMark  = "mark" // marque libre, ex. « k3s »
)

// Item est un élément possédé par la Bigbox.
type Item struct {
	Kind    string    `json:"kind"`
	Name    string    `json:"name"`
	Feature string    `json:"feature,omitempty"` // feature qui l'a installé (vide : import du Bash)
	Since   time.Time `json:"since"`
}

// Key est la représentation au format du registre Bash : « apt:htop », « k3s ».
func (i Item) Key() string {
	if i.Kind == KindMark {
		return i.Name
	}
	return i.Kind + ":" + i.Name
}

// ParseKey lit une ligne du registre Bash.
func ParseKey(key string) Item {
	if k, n, ok := strings.Cut(key, ":"); ok && k != "" && n != "" {
		return Item{Kind: k, Name: n}
	}
	return Item{Kind: KindMark, Name: key}
}

type file struct {
	Version int    `json:"version"`
	Items   []Item `json:"items"`
}

// Registry est le registre chargé en mémoire. Il n'est pas sûr en concurrence : une exécution
// le possède via Lock.
type Registry struct {
	path  string
	items map[string]Item
	now   func() time.Time
}

// Load charge le registre (vide s'il n'existe pas encore).
func Load(path string) (*Registry, error) {
	r := &Registry{path: path, items: map[string]Item{}, now: time.Now}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return r, nil
	}
	if err != nil {
		return nil, errs.Wrap(err, errs.Environment, "lecture du registre de propriété "+path)
	}
	var f file
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, &errs.Error{Kind: errs.Config, Op: "registre de propriété illisible " + path, Cause: err,
			Hint: "ne pas le supprimer : il dit ce que la Bigbox a le droit de retirer ; restaurez-le ou signalez le problème"}
	}
	if f.Version > Version {
		return nil, &errs.Error{Kind: errs.Precondition, Op: fmt.Sprintf("registre au format %d, plus récent que cette Bigbox (%d)", f.Version, Version),
			Hint: "mettez à jour la Bigbox"}
	}
	for _, it := range f.Items {
		r.items[it.Key()] = it
	}
	return r, nil
}

// Path renvoie le chemin du registre.
func (r *Registry) Path() string { return r.path }

// Mark enregistre un élément comme installé par la Bigbox (sans effet s'il l'est déjà).
func (r *Registry) Mark(kind, name, feature string) {
	it := Item{Kind: kind, Name: name, Feature: feature, Since: r.now().UTC().Truncate(time.Second)}
	if _, ok := r.items[it.Key()]; !ok {
		r.items[it.Key()] = it
	}
}

// Owned indique si l'élément a été installé par la Bigbox.
func (r *Registry) Owned(kind, name string) bool {
	_, ok := r.items[Item{Kind: kind, Name: name}.Key()]
	return ok
}

// Unmark retire un élément du registre (après sa désinstallation).
func (r *Registry) Unmark(kind, name string) {
	delete(r.items, Item{Kind: kind, Name: name}.Key())
}

// Items renvoie les éléments d'une nature (toutes si kind est vide), triés par clé.
func (r *Registry) Items(kind string) []Item {
	var out []Item
	for _, it := range r.items {
		if kind == "" || it.Kind == kind {
			out = append(out, it)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key() < out[j].Key() })
	return out
}

// Save écrit le registre de façon atomique : fichier temporaire du même répertoire, fsync,
// puis rename. Une interruption laisse l'ancienne version ou la nouvelle, jamais un mélange.
func (r *Registry) Save() error {
	f := file{Version: Version, Items: r.Items("")}
	if f.Items == nil {
		f.Items = []Item{}
	}
	data, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return errs.Wrap(err, errs.Internal, "sérialisation du registre")
	}
	if err := WriteFileAtomic(r.path, append(data, '\n'), 0o600); err != nil {
		return errs.Wrap(err, errs.Environment, "écriture du registre de propriété "+r.path)
	}
	return nil
}

// WriteFileAtomic écrit un fichier par fichier temporaire + rename.
func WriteFileAtomic(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }() // sans effet après le rename
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// ReadBash lit le registre au format Bash (~/.config/bigbox/state/owned : une clé par ligne),
// pour la reprise d'un poste installé par la Bigbox Bash. Aucune marque n'est perdue.
func ReadBash(path string) ([]Item, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()
	var out []Item
	seen := map[string]bool{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || seen[line] {
			continue
		}
		seen[line] = true
		out = append(out, ParseKey(line))
	}
	return out, sc.Err()
}

// Import ajoute des éléments (issus du registre Bash) au registre.
func (r *Registry) Import(items []Item) {
	for _, it := range items {
		r.Mark(it.Kind, it.Name, it.Feature)
	}
}

// Lock est le verrou d'exécution : deux Bigbox ne modifient jamais le poste en même temps.
type Lock struct{ f *os.File }

// Acquire prend le verrou sans attendre ; s'il est déjà pris, renvoie une erreur Conflict.
func Acquire(path string) (*Lock, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, errs.Wrap(err, errs.Environment, "création du répertoire du verrou")
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, errs.Wrap(err, errs.Environment, "ouverture du verrou "+path)
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, &errs.Error{Kind: errs.Conflict, Op: "une autre exécution de la Bigbox est en cours",
				Hint: "attendez qu'elle se termine puis relancez"}
		}
		return nil, errs.Wrap(err, errs.Environment, "verrouillage de "+path)
	}
	_ = f.Truncate(0)
	_, _ = fmt.Fprintf(f, "%d\n", os.Getpid())
	return &Lock{f: f}, nil
}

// Release libère le verrou.
func (l *Lock) Release() error {
	if l == nil || l.f == nil {
		return nil
	}
	_ = syscall.Flock(int(l.f.Fd()), syscall.LOCK_UN)
	return l.f.Close()
}
