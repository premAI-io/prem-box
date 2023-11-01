# 📦 Prem Box

### Description

Prem Box contains all the files and commands in order to run scuccessfully the Prem installer script. 

```bash
wget -q https://get.prem.ninja/install.sh -O install.sh; sudo bash ./install.sh
```

The installer script has the following objectives:

- Install all Prem dependencies such as Docker, Docker Compose, NVIDIA drivers for GPU etc.
- Run `docker-compose.*` in order to install Prem in your Infrastructure.


### Update

```bash
wget -q https://get.prem.ninja/update.sh -O update.sh; sudo bash ./update.sh
```

### Uninstall
```bash
wget -q https://get.prem.ninja/uninstall.sh -O uninstall.sh; sudo bash ./uninstall.sh
```

### Release Process

When a new version (tag) of [Prem App](https://github.com/premAI-io/prem-app), [Prem Daemon](https://github.com/premAI-io/prem-daemon) or [Prem Gateway](https://github.com/premAI-io/prem-gateway) has been released, the next step is to update Prem Box repository accordingly. In order to do that you will need to run the `bump.sh` script.

```sh
bash bump.sh
```

This script will pull the latest Github Releases and use the Git Tag to bump the versions.json. It will automatically updated version, image and SHA256 digest.




