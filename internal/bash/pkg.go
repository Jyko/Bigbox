package bash

import (
	"context"
	"fmt"
	"log/slog"
)

const (
	apt        = "apt"
	update     = "update"
	install    = "install"
	upgrade    = "upgrade"
	autoremove = "autoremove"
	uninstall  = "purge"
)

type PkgManager interface {
	Install(ctx context.Context, pkgs []string) error
	Update(ctx context.Context, pkgs []string) error
	Uninstall(ctx context.Context, pkgs []string) error
}

type AptPkgManager struct {
	logger *slog.Logger
	runner CmdRunner
}

var _ PkgManager = (*AptPkgManager)(nil)

// NewAptPkgManager Instancier un nouveau manageur de packages
func NewAptPkgManager(logger *slog.Logger, runner CmdRunner) *AptPkgManager {
	return &AptPkgManager{
		logger: logger,
		runner: runner,
	}
}

// Install Installer les packages candidats
func (pm *AptPkgManager) Install(ctx context.Context, pkgs []string) error {

	if err := pm.runner.RunSequence(
		ctx,
		[]Cmd{
			{Cmd: apt, Args: []string{update}, Privilege: PrivilegeRoot},
			{Cmd: apt, Args: append([]string{install, "-y"}, pkgs...), Privilege: PrivilegeRoot},
			{Cmd: apt, Args: append([]string{autoremove, "-y"}), Privilege: PrivilegeRoot},
		},
	); err != nil {
		pm.logger.Error("packages installation sequence failed", "error", err)
		return fmt.Errorf("packages installation sequence failed: %w", err)
	}

	return nil
}

// Update Mettre à jour les packages candidats
func (pm *AptPkgManager) Update(ctx context.Context, pkgs []string) error {

	if err := pm.runner.RunSequence(
		ctx,
		[]Cmd{
			{Cmd: apt, Args: []string{update}, Privilege: PrivilegeRoot},
			{Cmd: apt, Args: append([]string{upgrade, "-y"}, pkgs...), Privilege: PrivilegeRoot},
			{Cmd: apt, Args: append([]string{autoremove, "-y"}), Privilege: PrivilegeRoot},
		},
	); err != nil {
		pm.logger.Error("packages update sequence failed", "error", err)
		return fmt.Errorf("packages update sequence failed: %w", err)
	}

	return nil
}

// Uninstall Désinstaller les packages candidats
func (pm *AptPkgManager) Uninstall(ctx context.Context, pkgs []string) error {

	if err := pm.runner.RunSequence(
		ctx,
		[]Cmd{
			{Cmd: apt, Args: []string{update}, Privilege: PrivilegeRoot},
			{Cmd: apt, Args: append([]string{uninstall, "-y"}, pkgs...), Privilege: PrivilegeRoot},
			{Cmd: apt, Args: append([]string{autoremove, "-y"}), Privilege: PrivilegeRoot},
		},
	); err != nil {
		pm.logger.Error("packages uninstall sequence failed", "error", err)
		return fmt.Errorf("packages uninstall sequence failed: %w", err)
	}

	return nil
}
