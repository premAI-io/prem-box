# 📦 Prem Box

### Description

Prem Box contains all the files and commands in order to run scuccessfully the Prem installer script. 

```bash
wget -q https://get.prem.ninja/install.sh -O install.sh; sudo bash ./install.sh
```

The installer script has the following objectives:

- Install all Prem dependencies
- Run `docker-compose` in order to install Prem in your Infrastructure.

### Release Process

When a new version (tag) of [Prem Gateway](https://github.com/premAI-io/prem-gateway), [Prem App](https://github.com/premAI-io/prem-app) or   [Prem Daemon](https://github.com/premAI-io/prem-daemon) has been released, the next step is to update Prem Box repository accordingly. In order to do that you will need to run the `bump.sh` script.

```sh
bash bump.sh
```

This script will pull the latest Github Releases and use the Git Tag to bump the versions.json. It will automatically updated version, image and SHA256 digest.




