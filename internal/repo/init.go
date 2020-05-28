package repo

import (
	"os"
	"path/filepath"
	"text/template"

	"github.com/gobuffalo/packd"
	"github.com/gobuffalo/packr"
	"github.com/meshplus/bitxhub-kit/fileutil"
)

const (
	packPath = "../../config"
)

func Initialize(repoRoot, mode string, id int) error {
	box := packr.NewBox(packPath)
	if err := box.Walk(func(s string, file packd.File) error {
		p := filepath.Join(repoRoot, s)
		dir := filepath.Dir(p)
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			err := os.MkdirAll(dir, 0755)
			if err != nil {
				return err
			}
		}

		t := template.New(file.Name())
		t, err := t.Parse(file.String())
		if err != nil {
			return err
		}

		f, err := os.Create(p)
		if err != nil {
			return err
		}

		consensus := "solo"
		if mode == "cluster" {
			consensus = "raft"
		}

		data := struct {
			Id        int
			Solo      bool
			Consensus string
		}{id, mode == "solo", consensus}

		if err := t.Execute(f, data); err != nil {
			return err
		}

		return nil
	}); err != nil {
		return err
	}

	return nil
}

func Initialized(repoRoot string) bool {
	return fileutil.Exist(filepath.Join(repoRoot, caPrivKeyName)) && fileutil.Exist(filepath.Join(repoRoot, "node1"))
}
