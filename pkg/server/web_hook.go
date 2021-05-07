package server

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/replicate/cog/pkg/logger"
	"github.com/replicate/cog/pkg/model"
)

type WebHook struct {
	url    *url.URL
	secret string
}

func newWebHook(urlWithSecret string) (*WebHook, error) {
	splitIndex := strings.LastIndex(urlWithSecret, "@")
	if splitIndex == -1 {
		return nil, fmt.Errorf("Web hooks must be in the format <url>@<secret>")
	}
	rawURL := urlWithSecret[:splitIndex]
	secret := urlWithSecret[splitIndex+1:]

	hookURL, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	return &WebHook{url: hookURL, secret: secret}, nil
}

func (wh *WebHook) run(user string, name string, id string, mod *model.Model, image *model.Image, dir string, logWriter logger.Logger) error {
	values := url.Values{
		"model_id":  {id},
		"user":      {user},
		"repo_name": {name},
		"secret":    {wh.secret},
	}
	if mod != nil {
		modelJSON, err := json.Marshal(mod)
		if err != nil {
			return err
		}
		values["model_json_base64"] = []string{base64.StdEncoding.EncodeToString(modelJSON)}
		values["model_path"] = []string{fmt.Sprintf("/v1/repos/%s/%s/models/%s", user, name, mod.ID)}
	}
	if image != nil {
		imageJSON, err := json.Marshal(image)
		if err != nil {
			return err
		}
		values["image_json_base64"] = []string{base64.StdEncoding.EncodeToString(imageJSON)}
		values["arch"] = []string{image.Arch}
		values["cpu_usage"] = []string{fmt.Sprintf("%.2f", image.TestStats.CPUUsage)}
		values["memory_usage"] = []string{strconv.FormatUint(image.TestStats.MemoryUsage, 10)}
	}

	logWriter.Infof("Posting to web hook %s", wh.url.Host)

	req, err := http.PostForm(wh.url.String(), values)
	if err != nil {
		return fmt.Errorf("Model post failed: %w", err)
	}
	if req.StatusCode != http.StatusOK {
		return fmt.Errorf("Model post failed with HTTP status %d", req.StatusCode)
	}
	return nil
}

func (s *Server) runHooks(hooks []*WebHook, user string, id string, name string, mod *model.Model, image *model.Image, dir string, logWriter logger.Logger) error {
	for _, hook := range hooks {
		if err := hook.run(user, name, id, mod, image, dir, logWriter); err != nil {
			return err
		}
	}
	return nil
}

func webHooksFromRaw(rawHooks []string) ([]*WebHook, error) {
	hooks := []*WebHook{}
	for _, rawHook := range rawHooks {
		webHook, err := newWebHook(rawHook)
		if err != nil {
			return nil, err
		}
		hooks = append(hooks, webHook)
	}
	return hooks, nil
}