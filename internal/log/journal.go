package log

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// KeepJournals est le nombre d'exécutions dont le journal est conservé.
const KeepJournals = 20

const journalExt = ".jsonl"

// Journal est le fichier JSONL d'une exécution.
type Journal struct {
	Path  string
	RunID string
	file  *os.File
}

// NewRunID génère un identifiant court d'exécution (8 caractères hexadécimaux).
func NewRunID() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%08x", time.Now().UnixNano()&0xffffffff)
	}
	return hex.EncodeToString(b)
}

// OpenJournal crée le journal d'une exécution dans dir (droits 700 / 600) et retire les plus
// anciens au-delà de KeepJournals.
func OpenJournal(dir, command, runID string, now time.Time) (*Journal, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("création du répertoire des journaux %s : %w", dir, err)
	}
	name := fmt.Sprintf("%s-%s%s", now.Format("2006-01-02T15-04-05"), command, journalExt)
	path := filepath.Join(dir, name)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return nil, fmt.Errorf("ouverture du journal %s : %w", path, err)
	}
	if err := rotate(dir, KeepJournals); err != nil {
		_ = f.Close()
		return nil, err
	}
	return &Journal{Path: path, RunID: runID, file: f}, nil
}

// Write implémente io.Writer.
func (j *Journal) Write(p []byte) (int, error) { return j.file.Write(p) }

// Close ferme le journal.
func (j *Journal) Close() error {
	if j == nil || j.file == nil {
		return nil
	}
	return j.file.Close()
}

// rotate ne conserve que les keep journaux les plus récents (le nom commence par l'horodatage).
func rotate(dir string, keep int) error {
	names, err := List(dir)
	if err != nil {
		return err
	}
	for i := 0; i < len(names)-keep; i++ {
		if err := os.Remove(filepath.Join(dir, names[i])); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("rotation des journaux : %w", err)
		}
	}
	return nil
}

// List renvoie les noms des journaux de dir, du plus ancien au plus récent.
func List(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("lecture des journaux %s : %w", dir, err)
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), journalExt) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
