package log

import (
	"regexp"
	"sort"
	"strings"
	"sync"
)

// Masked remplace toute valeur sensible dans les sorties.
const Masked = "«masqué»"

// minSecretLen évite de masquer des fragments trop courts (et donc tout le texte).
const minSecretLen = 4

// Motifs de valeurs sensibles reconnues même quand le secret n'a pas été déclaré.
// Le premier groupe (la clé) est conservé, la valeur est masquée.
var sensitivePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)(authorization:\s*(?:bearer|basic)?\s*)\S+`),
	regexp.MustCompile(`(?i)((?:password|passwd|pwd|token|secret|api[_-]?key)["']?\s*[=:]\s*["']?)[^\s"',&]+`),
	regexp.MustCompile(`(?i)(://[^:/\s@]+:)[^@\s/]+(@)`), // identifiants dans une URL
}

// Redactor masque les secrets connus (déclarés par internal/secret) et les motifs sensibles,
// dans toutes les sorties : console, journal, erreurs. Sûr en concurrence.
type Redactor struct {
	mu      sync.RWMutex
	secrets []string // triés du plus long au plus court
}

// NewRedactor crée un Redactor vide.
func NewRedactor() *Redactor { return &Redactor{} }

// Add déclare des valeurs sensibles à masquer.
func (r *Redactor) Add(secrets ...string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, s := range secrets {
		if len(s) >= minSecretLen {
			r.secrets = append(r.secrets, s)
		}
	}
	// Le plus long d'abord : un secret qui en contient un autre est masqué en entier.
	sort.Slice(r.secrets, func(i, j int) bool { return len(r.secrets[i]) > len(r.secrets[j]) })
}

// Redact renvoie s sans aucune valeur sensible.
func (r *Redactor) Redact(s string) string {
	if s == "" {
		return s
	}
	if r != nil {
		r.mu.RLock()
		for _, sec := range r.secrets {
			s = strings.ReplaceAll(s, sec, Masked)
		}
		r.mu.RUnlock()
	}
	for i, re := range sensitivePatterns {
		if i == 2 {
			s = re.ReplaceAllString(s, "${1}"+Masked+"${2}")
		} else {
			s = re.ReplaceAllString(s, "${1}"+Masked)
		}
	}
	return s
}

// RedactAll masque chaque élément (ex. argv).
func (r *Redactor) RedactAll(in []string) []string {
	out := make([]string, len(in))
	for i, s := range in {
		out[i] = r.Redact(s)
	}
	return out
}
