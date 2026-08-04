package bash

import (
	"bytes"
	"context"
	"embed"
	_ "embed"
	"fmt"
	"log/slog"
	"os"
	"path"
	"path/filepath"
	"text/template"

	"bigard.fr/bigbox/internal/file"
	"bigard.fr/bigbox/internal/user"
)

//go:embed rsc
var rsc embed.FS

const (
	BigboxDir        = ".bigbox"
	BigboxEntrypoint = "bigbox.sh"
	bashrc           = ".bashrc"
	markerStart      = "# >>> start BIGBOX GENERATED BLOCK, do not modify >>>"
	markerEnd        = "# <<< end BIGBOX GENERATED BLOCK, do not modify <<<"
)

type RcManager interface {
	Install(ctx context.Context) error
	Verify(ctx context.Context) (bool, error)
	Uninstall(ctx context.Context) error
	RegisterModule(ctx context.Context, moduleName string) error
	VerifyModule(ctx context.Context, moduleName string) (bool, error)
	UnregisterModule(ctx context.Context, moduleName string) error
}

type StdRcManager struct {
	logger      *slog.Logger
	user        user.Context
	cmdRunner   CmdRunner
	fileManager file.Manager
}

var _ RcManager = (*StdRcManager)(nil)

// NewStdRcManager Instancier un nouveau manageur de Runtime Configuration
func NewStdRcManager(logger *slog.Logger, user user.Context, cmdRunner CmdRunner, fileManager file.Manager) *StdRcManager {
	return &StdRcManager{
		logger:      logger,
		user:        user,
		cmdRunner:   cmdRunner,
		fileManager: fileManager,
	}
}

func (rc *StdRcManager) Install(ctx context.Context) error {

	bigboxHome := filepath.Join(rc.user.HomeDir, BigboxDir)

	// Nous assurons la présence du répertoire racine de la configuration de la Bigbox
	if err := rc.cmdRunner.Run(ctx, &Cmd{Cmd: "mkdir", Args: []string{"-p", bigboxHome}}); err != nil {
		return fmt.Errorf("bigbox root directory creation failed: %w", err)
	}

	// Nous créons le bigbox.sh qui a pour mission de centraliser le chargement de tous les RC/Dotfiles des modules
	if err := rc.createEntrypoint(); err != nil {
		return err
	}

	// Nous ajoutons le chargement du bigbox.sh dans le .bashrc si cette instruction n'est pas déjà présente
	if err := rc.bootstrapEntrypoint(); err != nil {
		return err
	}

	return nil
}

func (rc *StdRcManager) Verify(ctx context.Context) (bool, error) {

	// Le répertoire de racine de la configuration Bigbox est-il présent ?
	bigboxDir := filepath.Join(rc.user.HomeDir, BigboxDir)
	info, err := os.Stat(bigboxDir)
	if err != nil {
		return false, err
	}
	if !info.IsDir() {
		return false, nil
	}

	// Le bootstrap dans .bashrc est-il réalisé ?
	rc.fileManager.AllMatchersFound()

	// L'entrypoint bigbox est-il crée ?
	entrypoint := filepath.Join(bigboxDir, BigboxEntrypoint)
	info, err = os.Stat(entrypoint)
	if err != nil {
		return false, err
	}
	if os.IsNotExist(entrypoint) {
		return false, nil
	}

	return true, nil
}

func (rc *StdRcManager) Uninstall(ctx context.Context) error {

	bigboxDir := filepath.Join(rc.user.HomeDir, BigboxDir)

	// Nous supprimons le répertoire racine de configuration de la Bigbox ainsi que son contenu
	if err := os.RemoveAll(bigboxDir); err != nil {
		return fmt.Errorf("failed to delete bigbox home directory %s: %w", bigboxDir, err)
	}

	// Nous nettoyons l'entrée dans le .bashrc de manière idempotent
	if err := rc.removeEntrypoint(); err != nil {
		return err
	}

	return nil
}

func (rc *StdRcManager) RegisterModule(ctx context.Context, moduleName string) error {
	//TODO implement me
	panic("implement me")
}

func (rc *StdRcManager) VerifyModule(ctx context.Context, moduleName string) (bool, error) {
	//TODO implement me
	panic("implement me")
}

func (rc *StdRcManager) UnregisterModule(ctx context.Context, moduleName string) error {
	//TODO implement me
	panic("implement me")
}

type bigboxModel struct {
	BigboxHome string
}

func (rc *StdRcManager) createEntrypoint() error {

	bigboxDir := filepath.Join(rc.user.HomeDir, BigboxDir)

	// Récupération du template depuis les ressources
	tmpl, err := template.ParseFS(rsc, "rsc/bigbox.sh")
	if err != nil {
		return fmt.Errorf("bigbox entrypoint template loading failed: %w", err)
	}

	model := bigboxModel{
		BigboxHome: bigboxDir,
	}

	// Nous exécutons le template contre notre modèle
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, model); err != nil {
		return fmt.Errorf("bigbox entrypoint template execution failed: %w", err)
	}

	bigboxEntrypoint := path.Join(bigboxDir, BigboxEntrypoint)

	// Nous utilisons directement la stdlib plutôt que le file.Editor, simplicité avant tout.
	if err := os.WriteFile(bigboxEntrypoint, buf.Bytes(), 0o755); err != nil {
		return fmt.Errorf("bigbox entrypoint file %s creation failed: %w", bigboxEntrypoint, err)
	}

	return nil
}

type bashrcModel struct {
	MarkerStart      string
	MarkerEnd        string
	BigboxEntrypoint string
}

func (rc *StdRcManager) bootstrapEntrypoint() error {

	homeDir := rc.user.HomeDir

	bashrc := filepath.Join(homeDir, bashrc)

	content, err := os.ReadFile(bashrc)
	if err != nil {
		return fmt.Errorf("failed to read %s: %w", bashrc, err)
	}

	hasStart := bytes.Contains(content, []byte(markerStart))
	hasEnd := bytes.Contains(content, []byte(markerEnd))

	switch {
	// Nous estimons que la présence des deux marqueurs indique un bootstrap existant propre de la bigbox
	case hasStart && hasEnd:
		return nil
	// Les ennuis, le .bashrc est corrompu, nous n'avons qu'un des deux marqueurs. Seul l'utilisateur peut nous aider à rétablir le .bashrc
	case hasStart || hasEnd:
		return fmt.Errorf("corrupted %s file, user intervention is required to restore a stable state", bashrc)
	}

	// Dernier cas, nous n'avons aucun marqueur, nous modifions le .bashrc en y ajoutant le fragment de bootstrap de la bigbox
	tmpl, err := template.ParseFS(rsc, "rsc/bashrc-fragment")
	if err != nil {
		return fmt.Errorf("bashrc-fragment template loading failed: %w", err)
	}

	var buf bytes.Buffer

	if err := tmpl.Execute(&buf, bashrcModel{
		MarkerStart:      markerStart,
		MarkerEnd:        markerEnd,
		BigboxEntrypoint: filepath.Join(homeDir, BigboxDir, BigboxEntrypoint),
	}); err != nil {
		return fmt.Errorf("bashrc-fragment template execution failed: %w", err)
	}

	content = append(content, '\n')
	content = append(content, buf.Bytes()...)
	content = append(content, '\n')

	return rc.fileManager.ReplaceByteContent(bashrc, content...)
}

func (rc *StdRcManager) removeEntrypoint() error {

	homeDir := rc.user.HomeDir

	bashrc := filepath.Join(homeDir, bashrc)

	content, err := os.ReadFile(bashrc)
	if err != nil {
		return fmt.Errorf("failed to read %s: %w", bashrc, err)
	}

	hasStart := bytes.Contains(content, []byte(markerStart))
	hasEnd := bytes.Contains(content, []byte(markerEnd))

	switch {
	// Les marqueurs ne sont pas présent, nous assumons que le bootstrap a déjà été supprimé
	case !hasStart && !hasEnd:
		return nil
	// Les ennuis, le .bashrc est corrompu, nous n'avons qu'un des deux marqueurs. Seul l'utilisateur peut nous aider à rétablir le .bashrc
	case hasStart:
		return fmt.Errorf("corrupted %s file, user intervention is required to restore a stable state", bashrc)
	}

	// Nous nettoyons le bootstrap, y compris les marqueurs
	if _, err := rc.fileManager.RemoveLinesRange(
		bashrc,
		func(line string) bool { return line == markerStart },
		func(line string) bool { return line == markerEnd },
		true,
	); err != nil {
		return err
	}

	return nil
}
