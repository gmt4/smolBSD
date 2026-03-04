<div align="center" markdown="1">

**Running smolClaw with ollama**

<img src="images/smolTelegram.png">

</div>

Refer to [this guide][1] to prepare your local model for tooling. I applied it to
[qwen3.5][2] `qwen3.5:9b` and have impressive
results. I called the created model `qwen3.5-agent`.

Example [picoclaw][3] `config.json`, modify:

* `YOUR_TELEGRAM_TOKEN`, on Telegram, create a `/newbot` speaking to `@BotFather`
* Ollama's IP address

```json
{
  "agents": {
    "defaults": {
      "workspace": "~/.picoclaw/workspace",
      "restrict_to_workspace": false,
      "model": "qwen3.5-agent",
      "max_tokens": 8192,
      "temperature": 0.7,
      "max_tool_iterations": 20
    }
  },
  "model_list": [
    {
      "model_name": "qwen3.5-agent",
      "model": "ollama/qwen3.5-agent:latest",
      "api_base": "http://192.168.1.1:11434/v1",
      "api_key": "-"
    }
  ],
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "YOUR_BOT_TOKEN",
      "allow_from": ["YOUR_USER_ID"]
    }
  },
  "gateway": {
    "host": "0.0.0.0",
    "port": 18790
  },
  "tools": {
    "web": {
      "brave": {
        "enabled": false,
        "api_key": "",
        "max_results": 5
      },
      "duckduckgo": {
        "enabled": true,
        "max_results": 5
      }
    }
  },
  "devices": {
    "enabled": false,
    "monitor_usb": false
  },
  "heartbeat": {
    "enabled": true,
    "interval": 30
  }
}
```

[1]: https://gist.github.com/Hegghammer/86d2070c0be8b3c62083d6653ad27c23
[2]: https://ollama.com/library/qwen3:5
[3]: https://github.com/sipeed/picoclaw
