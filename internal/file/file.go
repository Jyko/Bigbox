package file

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type Manager interface {
	AllMatchersFound(path string, matchers ...LineMatcher) (bool, error)
	AnyMatcherFound(path string, matchers ...LineMatcher) (bool, error)
	RemoveLines(path string, matcher LineMatcher) (deleted int, err error)
	RemoveLinesRange(path string, beingMatcher, endMatcher LineMatcher, included bool) (deleted int, err error)
	ReplaceByteContent(path string, content ...byte) error
	ReplaceContent(path string, content ...string) error
	ReplaceKeyValue(path, key, value string, appendIfMissing bool) (changed int, err error)
	ReplaceLines(path string, matcher LineMatcher, newLine string, appendIfMissing bool) (changed int, err error)
	ReplaceLinesRange(path string, beginMatcher, endMatcher LineMatcher, newLines ...string) (changed int, err error)
}

type StdManager struct {
	log *slog.Logger
}

var _ Manager = (*StdManager)(nil)

func NewStdManager(logger *slog.Logger) *StdManager {
	return &StdManager{
		log: logger,
	}
}

type LineMatcher func(line string) bool

func (m *StdManager) AllMatchersFound(path string, matchers ...LineMatcher) (bool, error) {
	//TODO implement me
	panic("implement me")
}

func (m *StdManager) AnyMatcherFound(path string, matchers ...LineMatcher) (bool, error) {
	//TODO implement me
	panic("implement me")
}

// ReplaceLines Modifier toutes les lignes d'un fichier matchant la règle fournie par une nouvelle.
// Si aucune ligne ne répond à la règle fournie et que appendIfMissing=true, la nouvelle ligne est ajoutée en fin de fichier.
func (m *StdManager) ReplaceLines(path string, matcher LineMatcher, newLine string, appendIfMissing bool) (replaced int, err error) {

	replaced = 0

	lines, fileMode, err := m.readLines(path)
	if err != nil {
		return 0, err
	}

	matched := false
	for i, l := range lines {
		if matcher(l) {
			matched = true
			// Scénario où la ligne trouvée est déjà dans l'état attendu
			if l == newLine {
				continue
			} else {
				lines[i] = newLine
				replaced++
			}
		}
	}

	// Scénario où la ligne n'a pas été trouvée et nous sommes en appendIfMissing
	if !matched && appendIfMissing {
		lines = append(lines, newLine)
		replaced = 1
	}

	// Nous n'avons pas de modification à apporter au fichier, nous faisons un early return
	if replaced == 0 {
		return replaced, nil
	}

	// Sinon, nous modifions le fichier existant de manière atomique, en restant les droits appliqués dessus
	if err := m.writeLines(path, lines, fileMode); err != nil {
		return 0, err
	}

	return replaced, nil
}

func (m *StdManager) RemoveLinesRange(path string, beginMatcher, endMatcher LineMatcher, included bool) (removed int, err error) {

	// Nous appelons la function d'altération en précisant l'implémentation de la génération du nouveau contenu du fichier
	return m.alterLinesRange(path, beginMatcher, endMatcher, func(oldContent []string, beginIdx, endIdx int) ([]string, int) {

		// Si l'on ne supprime pas les bornes, nous décalons les index de manière appropriés
		if included {
			beginIdx++
			endIdx--
		}

		removed = endIdx - beginIdx + 1

		// Nous préparons le futur contenu du fichier en copiant les lignes avant la borne de début et après la borne de fin
		newContent := make([]string, 0, len(oldContent)-removed)
		newContent = append(newContent, oldContent[:beginIdx]...)
		newContent = append(newContent, oldContent[endIdx+1:]...)

		return newContent, removed
	})
}

// RemoveLines Supprimer toutes les lignes d'un fichier matchant les règles fournies
func (m *StdManager) RemoveLines(path string, matcher LineMatcher) (removed int, err error) {

	removed = 0

	lines, fileMode, err := m.readLines(path)
	if err != nil {
		return 0, err
	}

	// Magie de Go: On garde le pointeur vers le slice, la taille est conservée ainsi que les backing values pour créer les itérators.
	// Mais le slice est vide. Je sais, c'est fou et ultra-spécifique, mais c'est la manière idiomatique de faire en Go pour filter ou map une slice.
	// Perso, çà me troue le cul, mais la synthaxe est un peu ... bizarre. Pourquoi ne pas avoir fait un Slice.filter() ou .map() ?
	kept := lines[:0]

	for _, l := range lines {
		if matcher(l) {
			removed++
			continue
		}
		// Le slice est vide et on y ajoute les lignes que l'on garde.
		kept = append(kept, l)
	}

	// Aucune ligne n'a été supprimée
	if removed == 0 {
		return removed, nil
	}

	if err := m.writeLines(path, kept, fileMode); err != nil {
		return 0, err
	}

	return removed, nil
}

func (m *StdManager) ReplaceLinesRange(path string, beginMatcher, endMatcher LineMatcher, newLines ...string) (replaced int, err error) {

	// Nous appelons la function d'altération en précisant l'implémentation de la génération du nouveau contenu du fichier
	return m.alterLinesRange(path, beginMatcher, endMatcher, func(oldContent []string, beginIdx, endIdx int) ([]string, int) {

		// Le nombre de lignes que nous allons remplacer
		// Si l1 -> l2, nous changeons un total de 2-1+1=0 ligne
		// Si l1 -> l3, nous changeons un total de 3-1+1=1 ligne, la ligne l2
		replaced := endIdx - beginIdx + 1

		newContent := make([]string, 0, len(oldContent)-replaced+len(newLines))
		newContent = append(newContent, oldContent[:beginIdx+1]...)
		newContent = append(newContent, newLines...)
		newContent = append(newContent, oldContent[endIdx:]...)

		return newContent, replaced
	})
}

// ReplaceByteContent Remplacer le contenu d'un fichier par le contenu binaire candidat
func (m *StdManager) ReplaceByteContent(path string, content ...byte) error {

	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("failed to get file %s infos: %w", path, err)
	}

	if err := m.writeBytes(path, content, info.Mode()); err != nil {
		return fmt.Errorf("failed to replace content from file %s: %w", path, err)
	}

	return nil
}

// ReplaceContent Remplacer le contenu d'un fichier par le contenu caractère candidat
func (m *StdManager) ReplaceContent(path string, content ...string) error {

	// Nous récupérons les droits du fichier [FileInfo.Mode]
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("failed to get file %s infos: %w", path, err)
	}

	if err := m.writeLines(path, content, info.Mode()); err != nil {
		return fmt.Errorf("failed to replace content from file %s: %w", path, err)
	}

	return nil
}

// ReplaceKeyValue Remplacer la valeur d'une clé (key=value) d'un fichier ou l'ajouter si celle-ci n'existe pas en fin de fichier.
func (m *StdManager) ReplaceKeyValue(path, key, value string, appendIfMissing bool) (replaced int, err error) {

	pattern := regexp.MustCompile(`^\s*` + regexp.QuoteMeta(key) + `\s*=`)

	matcher := func(line string) bool {
		return pattern.MatchString(line)
	}

	newLine := fmt.Sprintf("%s=%s", key, value)

	replaced, err = m.ReplaceLines(path, matcher, newLine, appendIfMissing)
	if err != nil {
		return 0, err
	}

	return replaced, nil
}

// Lire les lignes d'un fichier cible
func (m *StdManager) readLines(path string) ([]string, os.FileMode, error) {

	// Nous récupérons les droits du fichier [FileInfo.Mode]
	info, err := os.Stat(path)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get file %s infos: %w", path, err)
	}

	// Ca bruteforce sec, on teste pas l'existence ou le type >:D, pas le temps !
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to open file %s: %w", path, err)
	}
	// Nous fermons l'I/O en fin de function, pas de ressource ouverte à l'infini
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		return nil, 0, fmt.Errorf("failed to read content in file %s: %w", path, err)
	}

	return lines, info.Mode(), nil
}

// Ecrire les lignes dans un fichier sur le chemin cible
// Cette écriture se fait de manière atomique, un passage par un fichier temporaire assure que
// l'ensemble des écritures ont été réussies avant de renommer le fichier final.
func (m *StdManager) writeLines(path string, lines []string, fileMode os.FileMode) error {
	return m.writeBytes(path, []byte(strings.Join(lines, "\n")), fileMode)
}

func (m *StdManager) writeBytes(path string, bytes []byte, fileMode os.FileMode) error {

	// Nous créons un nouveau fichier temporaire
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".bigbox-*.tmp")
	if err != nil {
		return fmt.Errorf("failed to create a temporary file : %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if err := os.WriteFile(tmpPath, bytes, fileMode); err != nil {
		tmp.Close()
		return fmt.Errorf("failed to write file %s: %w", tmpPath, err)
	}

	if err := tmp.Close(); err != nil {
		return fmt.Errorf("failed to close the temporary file %s: %w", path, err)
	}

	// Renommer le fichier temporaire vers le nom cible
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("failed to rename the temporary file %s to %s: %w", tmpPath, path, err)
	}

	return nil
}

func (m *StdManager) alterLinesRange(
	path string,
	beginMatcher, endMatcher LineMatcher,
	generateNewContent func(oldContent []string, beginIdx, endIdx int) (newLines []string, altered int),
) (altered int, err error) {

	altered = 0

	lines, fileMode, err := m.readLines(path)
	if err != nil {
		return 0, err
	}

	beginIdx := -1
	endIdx := -1

	// Nous recherchons les bornes des lignes à remplacer selon les règles qui nous sont fournies
	for i, l := range lines {
		if beginIdx == -1 {
			if beginMatcher(l) {
				beginIdx = i
			}
			// Le continue ici permet d'assurer qu'on recherche d'abord la borne de début et
			// nous évite un test supplémentaire sur endIdx != -1 à la fin de la recherche
			continue
		}
		if endMatcher(l) {
			endIdx = i
			break
		}
	}

	// Le bloc recherché n'existe pas, nous n'avons jamais cherché la borne de fin :P
	if beginIdx == -1 {
		return 0, nil
	}

	if endIdx == -1 {
		return 0, fmt.Errorf("failed to replace lines; begin matching line found [ %s ] but not ending matching line", lines[beginIdx])
	}

	// Nous générons le fichier selon le callback candidat
	newLines, altered := generateNewContent(lines, beginIdx, endIdx)

	// Nous n'avons pas changé le fichier, donc nous ne le modifions pas.
	if altered == 0 {
		return altered, nil
	}

	// Nous écrivons le nouveau contenu altéré
	if err := m.writeLines(path, newLines, fileMode); err != nil {
		return 0, err
	}

	return altered, nil
}
