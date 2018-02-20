# travis-enterprise-worker-installers
Installer scripts for the Travis CI Enterprise Worker machines

## installer.sh

This is the default systemd-enabled installer we're using for Ubuntu 16.04 and later. This uses `overlay2` as storage driver which performs better than `aufs` and requires less setup than `devicemapper`.

# Hardware requirements

- 8 CPU Cores
- 16Gig RAM
- At least 40GB HDD
- Ubuntu 16.04

On AWS EC2 the `c4.2xlarge` and bigger are a good fit. _Please note: You need to configure the harddisk capacity manually._

# Usage

First, download the script:

```bash
$ curl -sSL -o /tmp/installer.sh https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/installer.sh
```

Then, execute the installer:

```bash
$ sudo bash /tmp/installer.sh --travis_enterprise_host="<enterprise host>" --travis_enterprise_security_token="<rabbitmq password>"
```

This installs all necesary components, such as Docker and `travis-worker`. It also pulls down Trusty build images by default. If this is the first time you're setting up a worker machine with Trusty build images, please enable [this feature flag](https://docs.travis-ci.com/user/enterprise/trusty/#Enabling-the-Trusty-Beta-Feature-Flag) on your platform machine.

If you need to use Precise build images, please pass in the `--travis_legacy_build_images=true` flag during installation:

```bash
$ sudo bash /tmp/installer.sh --travis_enterprise_host="<enterprise host>" --travis_enterprise_security_token="<rabbitmq password>" --travis_legacy_build_images=true
```

This installs Precise build images and also configures the queue to `builds.linux`.
