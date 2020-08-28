# travis-enterprise-worker-installers

This is the installer for Travis CI Enterprise worker machines, running on Ubuntu 16.04 and later.

# Requirements

- 8 CPU Cores
- 16Gig RAM
- At least 40GB HDD
- Ubuntu 16.04 or later

On AWS EC2 the `c4.2xlarge` instance types and bigger are a good fit. _Please note: You need to configure the harddisk capacity manually._

# Usage

First, download the script:

```bash
$ curl -sSL -o /tmp/installer.sh https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/installer.sh
```

Then, execute the installer:

```bash
$ sudo bash /tmp/installer.sh --travis_enterprise_host="<enterprise host>" --travis_enterprise_security_token="<rabbitmq password>"
```

This installs all necesary components, such as Docker and `travis-worker`. It also pulls down Xenial build images by default.


## Bionic build environment (beta)

If you wish to use the Bionic build environment, please pass in the `--travis_build_images=bionic` flag during installation:

```bash
$ sudo bash /tmp/installer.sh --travis_enterprise_host="<enterprise host>" --travis_enterprise_security_token="<rabbitmq password>" --travis_build_images=bionic
```

This installs Bionic build images and also configures the queue to `builds.bionic`. Please note, that this requires Travis CI Enterprise 2.2.x or later.
