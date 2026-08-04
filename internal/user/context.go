package user

import (
	"fmt"
	"os/user"
	"strconv"
)

type Context struct {
	Username string
	Uid      uint32
	Gid      uint32
	HomeDir  string
}

func NewContext() (Context, error) {

	current, err := user.Current()
	if err != nil {
		return Context{}, fmt.Errorf("failed to get current user: %w", err)
	}

	uid, err := strconv.ParseUint(current.Uid, 10, 32)
	if err != nil {
		return Context{}, fmt.Errorf("failed to parse uid %q: %w", current.Uid, err)
	}

	gid, err := strconv.ParseUint(current.Gid, 10, 32)
	if err != nil {
		return Context{}, fmt.Errorf("failed to parse uid %q: %w", current.Uid, err)
	}

	return Context{
		Username: current.Username,
		Uid:      uint32(uid), // Le cast est safe, t'inquiètes, grâce à ParseUint(x,x, 32)
		Gid:      uint32(gid),
		HomeDir:  current.HomeDir,
	}, nil
}
