# travis-enterprise-worker-installers
Installer scripts for the Travis CI Enterprise Worker machines

## installer.sh

This is the default systemd-enabled installer we're using for Ubuntu 16.04 and later. This uses `overlay2` as storage driver which performs better than `aufs` and requires less setup than `devicemapper`.

This installer requires a machine with these minimum specs:

- 8 CPU Cores
- 16Gig RAM
- At least 40GB HDD
- Ubuntu 16.04

On AWS EC2 the `c4.2xlarge` and bigger are a good fit. _Please note: You need to configure the harddisk capacity manually._