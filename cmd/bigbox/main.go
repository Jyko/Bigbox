// Commande bigbox : environnement de développement local sur Ubuntu, décrit dans bigbox.yaml.
package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/Jyko/Bigbox/features"
	"github.com/Jyko/Bigbox/internal/cli"
)

// Renseignés à la construction : -ldflags "-X main.version=… -X main.commit=… -X main.date=…"
var (
	version = "dev"
	commit  = ""
	date    = ""
)

func main() {
	// Premier Ctrl-C : annulation propre de l'étape en cours. Second : arrêt immédiat.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	go func() {
		<-ctx.Done()
		stop()
	}()
	code := cli.Main(ctx, cli.Build{Version: version, Commit: commit, Date: date}, features.All)
	stop()
	os.Exit(code)
}
